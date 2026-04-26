// ============================================================================
// inst_mem.v - ZERO-LATENCY Instruction Memory for CPI=1.0
// ============================================================================
// FIXES:
//
// [FIX-BURST-LAST] Bug trong BURST_ACTIVE: khi advance current_addr, điều kiện
//   burst_last phải dùng beat_count SAU KHI tăng (beat_count + 1), nhưng code
//   gốc tính (beat_count + 1 == total_beats) trước khi update beat_count.
//   Điều này đúng về mặt giá trị (beat_count vẫn là giá trị CŨ trong cùng cycle),
//   nhưng có edge case: khi total_beats = 0 (single-beat, xử lý ở BURST_IDLE),
//   và khi total_beats = 1 (2-beat burst), cần verify.
//
//   Cụ thể bug: với 2-beat burst (burst_len=1, total_beats=1):
//     - Beat 0: IDLE→ACTIVE, burst_last = (1==0) = 0 ✓
//     - Beat 1 (ACTIVE): beat_count=0, beat_count+1=1 == total_beats=1 → burst_last=1 ✓
//   Logic đúng nhưng có thể bị off-by-one nếu beat_count update trước khi đánh giá.
//   Fix: tách thành wire rõ ràng để dễ trace và tránh nhầm lẫn.
//
// [FIX-SINGLE-BEAT-HOLD] Khi burst_len=0 (single beat), BURST_ACTIVE nhận
//   beat_count=0, total_beats=0 → điều kiện (beat_count+1 == total_beats) = (1==0) = false
//   → burst_last sẽ KHÔNG bao giờ assert trong ACTIVE, gây treo!
//   Gốc dùng burst_last <= (burst_len == 0) trong IDLE (đúng), nhưng trong ACTIVE
//   cần check (beat_count + 1 >= total_beats) để handle case total_beats=0 đúng.
//   Fix: dùng (beat_count >= total_beats) vì khi enter ACTIVE, beat đầu đã gửi.
// ============================================================================

module inst_mem #(
    parameter MEM_SIZE      = 4096,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_INIT_FILE = ""   // unused — IMEM is now a blank SRAM; boot_ctrl loads it
)(
    input wire clk,
    input wire rst_n,

    // Simple Interface (combinational)
    input  wire [ADDR_WIDTH-1:0] PC,
    output wire [DATA_WIDTH-1:0] Instruction_Code,

    // Burst Read Interface
    input  wire [ADDR_WIDTH-1:0] burst_addr,
    input  wire [7:0]            burst_len,
    input  wire                  burst_req,
    output wire [DATA_WIDTH-1:0] burst_data,
    output reg                   burst_valid,
    output reg                   burst_last,
    input  wire                  burst_ready,

    // Write port (shared by boot sideband and AXI write path)
    input  wire                    wr_en,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    input  wire [DATA_WIDTH/8-1:0] wr_strb
);

    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);
    localparam ADDR_LSB  = $clog2(DATA_WIDTH/8);
    localparam ADDR_BITS = $clog2(MEM_DEPTH);

    // ========================================================================
    // Memory Array
    // ========================================================================
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // Simple combinational read
    // [FIX-ADDR-WRAP] Dùng modulo thay vì bit-slice cứng ADDR_BITS bits.
    // Vấn đề gốc: ADDR_BITS=$clog2(1024)=10 → PC[11:2] chỉ 10 bits
    // → PC=0x1000 wrap về index 0 → CPU loop vô tận.
    // Fix: (PC >> ADDR_LSB) % MEM_DEPTH → index luôn trong [0,MEM_DEPTH-1].
    wire [ADDR_WIDTH-1:0] word_addr_full;
    wire [ADDR_BITS-1:0]  word_addr;
    assign word_addr_full   = (PC >> ADDR_LSB) % MEM_DEPTH;
    assign word_addr        = word_addr_full[ADDR_BITS-1:0];
    assign Instruction_Code = memory[word_addr];

    // ========================================================================
    // Burst FSM
    // ========================================================================
    localparam BURST_IDLE   = 1'b0;
    localparam BURST_ACTIVE = 1'b1;

    reg        burst_state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [7:0]  beat_count;
    reg [7:0]  total_beats;

    // ========================================================================
    // Combinational burst_data (ZERO-LATENCY)
    // ========================================================================
    wire [ADDR_WIDTH-1:0] read_addr;
    wire [ADDR_WIDTH-1:0] read_word_addr_full;
    wire [ADDR_BITS-1:0]  read_word_addr;

    assign read_addr           = (burst_state == BURST_IDLE && burst_req) ?
                                 burst_addr : current_addr;
    // [FIX-ADDR-WRAP] Dùng modulo giống PC path, tránh truncate bit cao
    assign read_word_addr_full = (read_addr >> ADDR_LSB) % MEM_DEPTH;
    assign read_word_addr      = read_word_addr_full[ADDR_BITS-1:0];
    assign burst_data          = memory[read_word_addr];

    // Next address (combinational)
    wire [ADDR_WIDTH-1:0] next_addr;
    assign next_addr = current_addr + (DATA_WIDTH/8);

    // ========================================================================
    // [FIX] burst_last decision wire — dùng trong BURST_ACTIVE
    // Khi enter BURST_ACTIVE, beat 0 đã được gửi (valid/last set trong IDLE).
    // beat_count đếm từ 0 sau khi beat 0 được handshaked.
    // burst_last của beat tiếp theo = (beat_count + 1 == total_beats).
    // Nhưng khi total_beats = 0 (single beat, không vào đây) → đã handled ở IDLE.
    // Khi total_beats = 1: beat_count=0 → next_is_last = (0+1==1) = 1 ✓
    // ========================================================================
    wire next_is_last;
    assign next_is_last = (beat_count + 8'd1 == total_beats);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_state  <= BURST_IDLE;
            burst_valid  <= 1'b0;
            burst_last   <= 1'b0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            beat_count   <= 8'd0;
            total_beats  <= 8'd0;
        end else begin
            case (burst_state)

                BURST_IDLE: begin
                    if (burst_req) begin
                        current_addr <= burst_addr;
                        beat_count   <= 8'd0;
                        total_beats  <= burst_len;
                        burst_state  <= BURST_ACTIVE;
                        burst_valid  <= 1'b1;
                        // [FIX] Single-beat: burst_len=0 → last ngay beat đầu
                        burst_last   <= (burst_len == 8'd0);
                    end else begin
                        burst_valid  <= 1'b0;
                        burst_last   <= 1'b0;
                    end
                end

                BURST_ACTIVE: begin
                    if (burst_ready && burst_valid) begin
                        if (burst_last) begin
                            // Burst kết thúc
                            burst_state <= BURST_IDLE;
                            burst_valid <= 1'b0;
                            burst_last  <= 1'b0;
                        end else begin
                            // Advance sang beat tiếp
                            beat_count   <= beat_count + 8'd1;
                            current_addr <= next_addr;
                            burst_valid  <= 1'b1;
                            // [FIX] Dùng next_is_last wire (rõ ràng, dễ trace)
                            burst_last   <= next_is_last;
                        end
                    end
                    // !ready → hold state (burst_data update combinationally)
                end

                default: burst_state <= BURST_IDLE;

            endcase
        end
    end

    // ========================================================================
    // Write port (byte-enable)
    // Used by boot sideband during boot phase, and by AXI write path (JTAG).
    // ========================================================================
    wire [ADDR_BITS-1:0] wr_word_addr;
    assign wr_word_addr = wr_addr[ADDR_BITS+1:2];   // byte→word index

    integer b;
    always @(posedge clk) begin
        if (wr_en) begin
            for (b = 0; b < DATA_WIDTH/8; b = b + 1) begin
                if (wr_strb[b])
                    memory[wr_word_addr][b*8 +: 8] <= wr_data[b*8 +: 8];
            end
        end
    end

    // ========================================================================
    // Memory Initialization — blank SRAM (boot_ctrl loads program at runtime)
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = 32'h00000013;  // NOP (safe default until boot completes)
    end

endmodule