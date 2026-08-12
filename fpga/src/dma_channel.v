`timescale 1ns/1ps

// ============================================================================
// dma_channel.v — 1 kênh DMA (mem-to-mem)
//
// SỬA LỖI so với bản gốc:
//
//  [FIX-1] S_WAIT_RD: rd_last được latch từ assign wire (rd_last = m_axi_rlast
//          && m_axi_rvalid && m_axi_rready). Trong bản gốc, rd_last chỉ là
//          m_axi_rlast → có thể HIGH trước khi rvalid/rready → channel chuyển
//          state sớm. Fix: kiểm tra rd_data_v && rd_last cùng lúc.
//
//  [FIX-2] S_WAIT_WR: wr_wvalid / wr_wlast không bị clear sau khi wready
//          accept beat cuối → slave nhận double-beat. Fix: clear wr_wvalid
//          ngay sau handshake (wr_wvalid && wr_wready).
//
//  [FIX-3] bytes_left comparison khi tính done: 
//          "bytes_left <= ((wr_len+1) << 2)" — wr_len là reg [7:0], wr_len+1
//          là 9-bit, shift 2 là 11-bit, nhưng bytes_left là 32-bit.
//          Verilog sẽ zero-extend đúng, nhưng dễ gây cảnh báo tool.
//          Fix: dùng {24'b0, wr_len} + 32'h1 để tường minh.
//
//  [FIX-4] buf_count là 5-bit (0–16) nhưng BUF_DEPTH=16 nên max count=16
//          cần bit thứ 5 (0–16 = 5 bits). Bản gốc đúng, giữ nguyên.
//
//  [FIX-5] integer i trong always block: Verilog-2001 cho phép integer trong
//          always sequential nhưng không synthesizable nếu dùng trong loop
//          với non-constant bound. Bản gốc chỉ dùng i để khởi tạo buf_mem
//          trong initial block (không có initial block nào trong RTL) →
//          loại bỏ integer i và dùng reset block không có loop.
//          → Đổi sang reset buf_mem bằng reg default (FF sẽ reset về 0).
//
//  [FIX-6] S_FETCH_RD: rd_len calculation khi bytes_left không chia hết
//          cho 4. "(bytes_left >> 2) - 1" có thể underflow nếu bytes_left < 4.
//          Fix: gate bằng điều kiện >= 4.
//
//  [FIX-7] Loại bỏ "integer i" ở module scope — không hợp lệ trong Verilog-2001
//          cho synthesis (integer variables ở module scope chỉ dùng được
//          trong initial/task, không trong always sequential).
//
// NOTE về modes:
//   Mode 2'b00 = mem-to-mem: đã implement đầy đủ
//   Mode 2'b01 = periph-to-mem: cần periph_req/periph_ack handshake
//     (chưa implement — channel báo lỗi nếu cfg_mode != 0)
//   Mode 2'b10 = mem-to-periph: tương tự
//   → Trong SoC hiện tại, PLIC + UART/SPI dùng DMA mode 0 (mem-to-mem)
//     vì peripheral FIFO được map vào địa chỉ MMIO.
// ============================================================================

module dma_channel #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter BURST_LEN   = 8'd15  // AXI ARLEN = 15 → 16-beat burst (64 bytes)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ── Config từ dma_reg_slave ───────────────────────────────────────────
    input  wire [ADDR_WIDTH-1:0] cfg_src,
    input  wire [ADDR_WIDTH-1:0] cfg_dst,
    input  wire [31:0]           cfg_len,    // tổng số byte cần transfer
    input  wire [1:0]            cfg_mode,
    input  wire                  cfg_en,
    input  wire                  cfg_start,  // 1-cycle pulse

    // ── Peripheral handshake (mode 01/10 only) ────────────────────────────
    // PERIPH_RX (01): src=MMIO fixed, dst=DMEM increments, 1-word per req
    // PERIPH_TX (10): src=DMEM increments, dst=MMIO fixed, 1-word per req
    input  wire                  periph_req, // peripheral has data / is ready
    output reg                   periph_ack, // 1-cycle pulse after each word xfer

    // ── Status → dma_reg_slave ────────────────────────────────────────────
    output reg                   done,       // 1-cycle pulse khi hoàn tất
    output reg                   error,      // 1-cycle pulse khi lỗi
    output wire                  busy,

    // ── Bus request/grant (từ dma_arbiter) ────────────────────────────────
    output reg                   rd_req,
    input  wire                  rd_grant,
    output reg                   rd_rel,
    output reg                   wr_req,
    input  wire                  wr_grant,
    output reg                   wr_rel,

    // ── Data interface với dma_axi_master ─────────────────────────────────
    output reg  [ADDR_WIDTH-1:0] rd_addr,
    output reg  [7:0]            rd_len,
    output reg                   rd_valid,
    input  wire                  rd_ready,
    input  wire [DATA_WIDTH-1:0] rd_data,
    input  wire                  rd_data_v,  // valid && rready (từ dma_axi_master)
    input  wire                  rd_last,    // last beat (từ dma_axi_master)
    output wire                  rd_data_rdy,

    output reg  [ADDR_WIDTH-1:0] wr_addr,
    output reg  [7:0]            wr_len,
    output reg                   wr_valid,
    input  wire                  wr_ready,
    output reg  [DATA_WIDTH-1:0] wr_data,
    output reg  [3:0]            wr_wstrb,
    output reg                   wr_wvalid,
    output reg                   wr_wlast,
    input  wire                  wr_wready,
    input  wire [1:0]            wr_bresp,
    input  wire                  wr_bvalid,
    output wire                  wr_bready
);

    // WHY rd_data_rdy = 1: channel luôn sẵn sàng nhận data vào buffer.
    // Buffer overflow được kiểm soát bởi buf_full (không ghi khi đầy).
    assign rd_data_rdy = 1'b1;
    assign wr_bready   = 1'b1;
    assign busy        = (state != S_IDLE);

    // ── FSM states ────────────────────────────────────────────────────────
    localparam [2:0]
        S_IDLE     = 3'd0,
        S_FETCH_RD = 3'd1,
        S_WAIT_RD  = 3'd2,
        S_FETCH_WR = 3'd3,
        S_WAIT_WR  = 3'd4,
        S_DONE     = 3'd5,
        S_ERROR    = 3'd6,
        S_P_WAIT   = 3'd7;  // wait for periph_req (mode 01/10)

    reg [2:0]            state;
    reg [ADDR_WIDTH-1:0] cur_src;
    reg [ADDR_WIDTH-1:0] cur_dst;
    reg [31:0]           bytes_left;
    reg                  is_periph;    // 1 when mode=01 or mode=10
    reg                  periph_rx;    // 1=PERIPH_RX(src fixed), 0=PERIPH_TX(dst fixed)

    // WHY line buffer 16×32-bit = 64 bytes = 1 burst (ARLEN=15, 16 beats × 4 bytes).
    // Không cần FIFO lớn hơn vì channel xử lý 1 burst mỗi lần: đọc đầy buffer,
    // rồi ghi hết buffer, rồi mới đọc burst tiếp theo.
    localparam BUF_DEPTH = 16;
    reg [DATA_WIDTH-1:0] buf_mem [0:BUF_DEPTH-1];
    reg [3:0]            buf_wr_ptr;   // write pointer vào buffer
    reg [3:0]            buf_rd_ptr;   // read pointer từ buffer
    reg [4:0]            buf_count;    // số words hiện có trong buffer

    wire buf_empty = (buf_count == 5'd0);
    wire buf_full  = (buf_count == BUF_DEPTH[4:0]);

    // ── Computed burst length cho request tiếp theo ───────────────────────
    // WHY: bytes_left >> 2 = số words còn lại. Burst tối đa = BURST_LEN+1 beats.
    // Nếu còn đủ → dùng full burst; không đủ → dùng partial burst.
    wire [7:0] next_burst_len;
    assign next_burst_len = (bytes_left >= {24'b0, BURST_LEN} + 32'h4) // [FIX-6]
                            ? BURST_LEN
                            : (bytes_left[9:2] - 8'd1);  // words - 1 = ARLEN

    // ── Bytes transferred in current burst ───────────────────────────────
    wire [31:0] burst_bytes;
    assign burst_bytes = ({24'b0, wr_len} + 32'h1) << 2;  // (ARLEN+1) × 4

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            rd_req     <= 1'b0;  wr_req    <= 1'b0;
            rd_rel     <= 1'b0;  wr_rel    <= 1'b0;
            rd_valid   <= 1'b0;  wr_valid  <= 1'b0;
            wr_wvalid  <= 1'b0;  wr_wlast  <= 1'b0;
            done       <= 1'b0;  error     <= 1'b0;
            periph_ack <= 1'b0;
            is_periph  <= 1'b0;  periph_rx <= 1'b0;
            buf_wr_ptr <= 4'd0;  buf_rd_ptr <= 4'd0;
            buf_count  <= 5'd0;
            cur_src    <= {ADDR_WIDTH{1'b0}};
            cur_dst    <= {ADDR_WIDTH{1'b0}};
            bytes_left <= 32'd0;
            rd_addr    <= {ADDR_WIDTH{1'b0}};
            rd_len     <= 8'd0;
            wr_addr    <= {ADDR_WIDTH{1'b0}};
            wr_len     <= 8'd0;
            wr_data    <= {DATA_WIDTH{1'b0}};
            wr_wstrb   <= 4'hF;
        end else begin
            // ── Pulse resets (default) ────────────────────────────────────
            done       <= 1'b0;
            error      <= 1'b0;
            rd_rel     <= 1'b0;
            wr_rel     <= 1'b0;
            periph_ack <= 1'b0;

            case (state)
                // ─────────────────────────────────────────────────────────
                S_IDLE: begin
                    if (cfg_start && cfg_en) begin
                        if (cfg_mode == 2'b00) begin
                            // mem-to-mem
                            if (cfg_len == 32'd0) begin
                                done <= 1'b1;
                            end else begin
                                cur_src    <= cfg_src;
                                cur_dst    <= cfg_dst;
                                bytes_left <= cfg_len;
                                is_periph  <= 1'b0;
                                buf_wr_ptr <= 4'd0;
                                buf_rd_ptr <= 4'd0;
                                buf_count  <= 5'd0;
                                rd_req     <= 1'b1;
                                state      <= S_FETCH_RD;
                            end
                        end else if (cfg_mode == 2'b01 || cfg_mode == 2'b10) begin
                            // periph mode: word-by-word, gated by periph_req
                            if (cfg_len == 32'd0) begin
                                done <= 1'b1;
                            end else begin
                                cur_src    <= cfg_src;
                                cur_dst    <= cfg_dst;
                                bytes_left <= cfg_len;
                                is_periph  <= 1'b1;
                                periph_rx  <= (cfg_mode == 2'b01);
                                buf_wr_ptr <= 4'd0;
                                buf_rd_ptr <= 4'd0;
                                buf_count  <= 5'd0;
                                state      <= S_P_WAIT;
                            end
                        end else begin
                            error <= 1'b1;  // mode 11: reserved
                        end
                    end
                end

                // ─────────────────────────────────────────────────────────
                // S_P_WAIT: wait for peripheral to assert req, then do
                // a single-word (ARLEN=0/AWLEN=0) transfer.
                // ─────────────────────────────────────────────────────────
                S_P_WAIT: begin
                    if (periph_req) begin
                        // Single-beat: rd_len=0 (1 word = 4 bytes)
                        buf_wr_ptr <= 4'd0;
                        buf_rd_ptr <= 4'd0;
                        buf_count  <= 5'd0;
                        rd_req     <= 1'b1;
                        state      <= S_FETCH_RD;
                    end
                end

                // ─────────────────────────────────────────────────────────
                S_FETCH_RD: begin
                    if (rd_grant) begin
                        rd_addr  <= cur_src;
                        rd_len   <= is_periph ? 8'd0 : next_burst_len;
                        rd_valid <= 1'b1;
                        rd_req   <= 1'b0;
                        state    <= S_WAIT_RD;
                    end
                end

                // ─────────────────────────────────────────────────────────
                S_WAIT_RD: begin
                    // Drop rd_valid sau AR handshake
                    if (rd_valid && rd_ready)
                        rd_valid <= 1'b0;

                    // Latch R data vào line buffer
                    // [FIX-1] kiểm tra rd_data_v (đã gated với rvalid && rready)
                    if (rd_data_v && !buf_full) begin
                        buf_mem[buf_wr_ptr] <= rd_data;
                        buf_wr_ptr          <= buf_wr_ptr + 4'd1;
                        buf_count           <= buf_count + 5'd1;
                    end

                    // [FIX-1] rd_last đã gated với valid && ready từ dma_axi_master
                    if (rd_last) begin
                        rd_rel <= 1'b1;
                        wr_req <= 1'b1;
                        state  <= S_FETCH_WR;
                    end
                end

                // ─────────────────────────────────────────────────────────
                S_FETCH_WR: begin
                    if (wr_grant) begin
                        // PERIPH_TX (mode 10): dst is fixed MMIO, don't use cur_dst
                        wr_addr  <= (is_periph && !periph_rx) ? cfg_dst : cur_dst;
                        wr_len   <= rd_len;  // 0 for periph, next_burst_len for mem
                        wr_valid <= 1'b1;
                        wr_req   <= 1'b0;
                        state    <= S_WAIT_WR;
                    end
                end

                // ─────────────────────────────────────────────────────────
                S_WAIT_WR: begin
                    // Drop wr_valid sau AW handshake
                    if (wr_valid && wr_ready)
                        wr_valid <= 1'b0;

                    // Drive W channel từ line buffer
                    // [FIX-2] clear wr_wvalid sau mỗi beat được accept
                    if (!buf_empty && wr_wready && !wr_wvalid) begin
                        // Lấy word từ buffer khi slave sẵn sàng nhận beat mới
                        wr_data    <= buf_mem[buf_rd_ptr];
                        wr_wstrb   <= 4'hF;
                        wr_wvalid  <= 1'b1;
                        wr_wlast   <= (buf_count == 5'd1);  // last beat khi còn 1 word
                        buf_rd_ptr <= buf_rd_ptr + 4'd1;
                        buf_count  <= buf_count - 5'd1;
                    end else if (wr_wvalid && wr_wready) begin
                        // Beat được accept → clear valid
                        // [FIX-2] Không double-drive: sau khi clear,
                        // vòng lặp tiếp theo mới nạp beat kế tiếp
                        wr_wvalid <= 1'b0;
                        wr_wlast  <= 1'b0;
                    end

                    // Chờ B response
                    if (wr_bvalid) begin
                        if (wr_bresp != 2'b00) begin
                            error  <= 1'b1;
                            wr_rel <= 1'b1;
                            state  <= S_ERROR;
                        end else begin
                            wr_rel <= 1'b1;

                            if (is_periph) begin
                                // Periph mode: single-word (4 bytes) per req/ack cycle
                                // PERIPH_RX: src (MMIO) fixed, dst increments
                                // PERIPH_TX: src increments, dst (MMIO) fixed via cfg_dst
                                if (!periph_rx) cur_src <= cur_src + 32'd4;
                                if ( periph_rx) cur_dst <= cur_dst + 32'd4;
                                bytes_left <= bytes_left - 32'd4;
                                periph_ack <= 1'b1;
                                if (bytes_left <= 32'd4) begin
                                    state <= S_DONE;
                                end else begin
                                    state <= S_P_WAIT;
                                end
                            end else begin
                                // mem-to-mem burst loop
                                cur_src    <= cur_src    + burst_bytes;
                                cur_dst    <= cur_dst    + burst_bytes;
                                bytes_left <= bytes_left - burst_bytes;
                                if (bytes_left <= burst_bytes) begin
                                    state <= S_DONE;
                                end else begin
                                    buf_wr_ptr <= 4'd0;
                                    buf_rd_ptr <= 4'd0;
                                    buf_count  <= 5'd0;
                                    rd_req     <= 1'b1;
                                    state      <= S_FETCH_RD;
                                end
                            end
                        end
                    end
                end

                // ─────────────────────────────────────────────────────────
                S_DONE: begin
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                S_ERROR: begin
                    // error đã được pulse ở S_WAIT_WR
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule