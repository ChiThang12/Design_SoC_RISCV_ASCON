// ============================================================================
// uart_boot_ctrl.v — UART-based Boot Controller
//
// Thay thế boot_ctrl (ROM-based). Hai chế độ hoạt động:
//
//   SIM_MODE=1  : Dùng $readmemh nội bộ, copy 1 word/cycle (giống boot_ctrl cũ).
//                 Dùng cho simulation — không tốn 71M cycles chờ UART.
//
//   SIM_MODE=0  : Nhận chương trình qua UART RX (8N1, BAUD_RATE bps).
//                 Protocol: host gửi đúng PROG_WORDS × 4 bytes, little-endian,
//                 không header, không ACK. boot_done sau khi nhận đủ.
//
// UART RX timing (SIM_MODE=0):
//   - Detect start bit: uart_rx falls to 0
//   - Sample center of start bit sau BAUD_HALF cycles
//   - Sample mỗi data bit sau BAUD_FULL cycles
//   - Byte assembly: 4 bytes → 1 word, little-endian (byte đầu = LSB)
//   - Mỗi 4 bytes: write 1 word vào IMEM qua sideband port
//
// Interface giống boot_ctrl + thêm uart_rx.
// ============================================================================

module uart_boot_ctrl #(
    parameter CLK_FREQ   = 100_000_000,   // Hz
    parameter BAUD_RATE  = 115200,
    parameter PROG_WORDS = 2048,          // = IMEM_SIZE / 4
    parameter SIM_MODE   = 0,             // 0=UART RX, 1=fast $readmemh
    parameter BOOT_FILE  = "memory/program.hex"
)(
    input  wire        clk,
    input  wire        rst_n,      // fabric_rst_n (async active-low)
    input  wire        uart_rx,    // từ pad; idle = 1'b1 (SIM_MODE=1 không dùng)

    // IMEM sideband write port
    output reg         boot_we,
    output reg  [31:0] boot_addr,  // byte address vào IMEM
    output reg  [31:0] boot_wdata,

    output reg         boot_done   // sticky, gates cpu_rst_n release
);

localparam ADDR_W   = $clog2(PROG_WORDS);

// ============================================================================
// SIM_MODE=1: Fast ROM load — $readmemh + copy 1 word/cycle
// ============================================================================
generate
if (SIM_MODE == 1) begin : g_sim

    localparam [1:0] SS_IDLE  = 2'd0,
                     SS_WRITE = 2'd1,
                     SS_DONE  = 2'd2;

    reg [31:0]           mem [0:PROG_WORDS-1];
    reg [1:0]            state;
    reg [ADDR_W-1:0]     widx;

    initial $readmemh(BOOT_FILE, mem);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= SS_IDLE;
            widx       <= {ADDR_W{1'b0}};
            boot_we    <= 1'b0;
            boot_addr  <= 32'h0;
            boot_wdata <= 32'h0;
            boot_done  <= 1'b0;
        end else begin
            case (state)
                SS_IDLE: begin
                    state <= SS_WRITE;
                    widx  <= {ADDR_W{1'b0}};
                    boot_we <= 1'b0;
                end

                SS_WRITE: begin
                    boot_we    <= 1'b1;
                    boot_addr  <= {{(32-ADDR_W-2){1'b0}}, widx, 2'b00};
                    boot_wdata <= mem[widx];
                    if (widx == PROG_WORDS - 1) begin
                        state <= SS_DONE;
                    end else begin
                        widx <= widx + 1'b1;
                    end
                end

                SS_DONE: begin
                    boot_we   <= 1'b0;
                    boot_done <= 1'b1;
                end

                default: state <= SS_IDLE;
            endcase
        end
    end

end else begin : g_uart

// ============================================================================
// SIM_MODE=0: UART RX boot — 8N1, PROG_WORDS × 4 bytes, little-endian
// ============================================================================

// Baud rate constants
localparam [19:0] BAUD_FULL = CLK_FREQ / BAUD_RATE - 1;      // full bit period - 1
localparam [19:0] BAUD_HALF = CLK_FREQ / BAUD_RATE / 2 - 1;  // half-period - 1 (center sample)

localparam [2:0]
    ST_IDLE   = 3'd0,   // uart_rx=1, wait start bit
    ST_CENTER = 3'd1,   // count half-period, verify start bit
    ST_DATA   = 3'd2,   // receive 8 data bits (LSB first)
    ST_STOP   = 3'd3,   // wait stop bit, then process byte
    ST_DONE   = 3'd4;   // boot_done=1, sticky

reg [2:0]         state;
reg [19:0]        tick_cnt;   // baud counter
reg [2:0]         bit_cnt;    // bit index [0..7]
reg [1:0]         byte_cnt;   // byte index in current word [0..3]
reg [7:0]         byte_reg;   // received byte (shifts in LSB first)
reg [23:0]        word_buf;   // lower 3 bytes of assembled word
reg [ADDR_W-1:0]  word_idx;   // next word address

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= ST_IDLE;
        tick_cnt   <= 20'h0;
        bit_cnt    <= 3'd0;
        byte_cnt   <= 2'd0;
        byte_reg   <= 8'h0;
        word_buf   <= 24'h0;
        word_idx   <= {ADDR_W{1'b0}};
        boot_we    <= 1'b0;
        boot_addr  <= 32'h0;
        boot_wdata <= 32'h0;
        boot_done  <= 1'b0;
    end else begin
        // Default: boot_we bị clear mỗi cycle; override trong ST_STOP khi word done
        boot_we <= 1'b0;

        case (state)

            // ── IDLE: đợi start bit (uart_rx falls to 0) ──────────────────────
            ST_IDLE: begin
                if (!uart_rx) begin
                    tick_cnt <= 20'h0;
                    state    <= ST_CENTER;
                end
            end

            // ── CENTER: đợi nửa baud period, xác nhận start bit ───────────────
            ST_CENTER: begin
                if (tick_cnt == BAUD_HALF) begin
                    tick_cnt <= 20'h0;
                    if (!uart_rx) begin
                        // Start bit hợp lệ → bắt đầu nhận data
                        bit_cnt <= 3'd0;
                        state   <= ST_DATA;
                    end else begin
                        // Noise glitch — bỏ qua
                        state   <= ST_IDLE;
                    end
                end else begin
                    tick_cnt <= tick_cnt + 20'h1;
                end
            end

            // ── DATA: sample 8 bits (LSB first, mỗi bit cách nhau BAUD_FULL) ──
            ST_DATA: begin
                if (tick_cnt == BAUD_FULL) begin
                    tick_cnt <= 20'h0;
                    // Shift in bit (LSB first)
                    byte_reg <= {uart_rx, byte_reg[7:1]};
                    if (bit_cnt == 3'd7) begin
                        bit_cnt <= 3'd0;
                        state   <= ST_STOP;
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end else begin
                    tick_cnt <= tick_cnt + 20'h1;
                end
            end

            // ── STOP: đợi stop bit period, sau đó xử lý byte ──────────────────
            ST_STOP: begin
                if (tick_cnt == BAUD_FULL) begin
                    tick_cnt <= 20'h0;
                    // Không kiểm tra stop bit (uart_rx nên = 1)
                    if (byte_cnt == 2'd3) begin
                        // Byte thứ 4 → word hoàn chỉnh
                        // word = {byte3(MSB), byte2, byte1, byte0(LSB)} = little-endian
                        boot_we    <= 1'b1;
                        boot_addr  <= {{(32-ADDR_W-2){1'b0}}, word_idx, 2'b00};
                        boot_wdata <= {byte_reg, word_buf};  // {byte3, byte2, byte1, byte0}
                        byte_cnt   <= 2'd0;
                        if (word_idx == PROG_WORDS - 1) begin
                            // Từ cuối cùng → boot done
                            state <= ST_DONE;
                        end else begin
                            word_idx <= word_idx + 1;
                            state    <= ST_IDLE;
                        end
                    end else begin
                        // Byte 0,1,2 → tích lũy vào word_buf
                        case (byte_cnt)
                            2'd0: word_buf[7:0]   <= byte_reg;
                            2'd1: word_buf[15:8]  <= byte_reg;
                            2'd2: word_buf[23:16] <= byte_reg;
                            default: ;
                        endcase
                        byte_cnt <= byte_cnt + 2'd1;
                        state    <= ST_IDLE;
                    end
                end else begin
                    tick_cnt <= tick_cnt + 20'h1;
                end
            end

            // ── DONE: boot_done sticky, CPU released bởi clk_reset_ctrl ───────
            ST_DONE: begin
                boot_done <= 1'b1;
            end

            default: state <= ST_IDLE;

        endcase
    end
end

end // g_uart
endgenerate

endmodule
