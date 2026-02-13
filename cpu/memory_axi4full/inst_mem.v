// ============================================================================
// inst_mem.v - Instruction Memory with Burst Read Support  [FIXED]
// ============================================================================
// FIXES:
//   Bug A: Beat đầu dùng burst_addr trực tiếp thay vì current_addr cũ
//   Bug B: rlast logic dùng beat_count+1 == total_beats (0-indexed đúng)
//   Bug C: next_addr tính combinational để đọc memory đúng cycle
// ============================================================================

module inst_mem #(
    parameter MEM_SIZE = 4096,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,

    // Simple Interface
    input  wire [ADDR_WIDTH-1:0] PC,
    output wire [DATA_WIDTH-1:0] Instruction_Code,

    // Burst Read Interface
    input  wire [ADDR_WIDTH-1:0] burst_addr,
    input  wire [7:0]            burst_len,
    input  wire                  burst_req,
    output reg  [DATA_WIDTH-1:0] burst_data,
    output reg                   burst_valid,
    output reg                   burst_last,
    input  wire                  burst_ready
);

    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);
    localparam ADDR_LSB  = $clog2(DATA_WIDTH/8);        // = 2

    // ========================================================================
    // Memory Array
    // ========================================================================
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // Simple read (combinational)
    wire [9:0] word_addr;
    assign word_addr = PC[11:2];
    assign Instruction_Code = memory[word_addr];

    // ========================================================================
    // Burst FSM
    // ========================================================================
    localparam BURST_IDLE   = 1'b0;
    localparam BURST_ACTIVE = 1'b1;

    reg burst_state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [7:0]            beat_count;
    reg [7:0]            total_beats;

    // ----------------------------------------------------------------
    // FIX: next_addr tính COMBINATIONAL từ current_addr
    //      → dùng để đọc memory beat tiếp theo trong cùng cycle
    // ----------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] next_addr;
    wire [ADDR_WIDTH-1:0] next_word_addr;
    assign next_addr      = current_addr + (DATA_WIDTH/8);
    assign next_word_addr = next_addr[ADDR_WIDTH-1:ADDR_LSB];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_state  <= BURST_IDLE;
            burst_data   <= {DATA_WIDTH{1'b0}};
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

                        // ------------------------------------------------
                        // FIX A: Dùng burst_addr trực tiếp (combinational)
                        //        KHÔNG dùng current_addr vì chưa update
                        // ------------------------------------------------
                        burst_data  <= memory[burst_addr[ADDR_WIDTH-1:ADDR_LSB]];
                        burst_valid <= 1'b1;
                        // beat_count=0, last khi total_beats=0 (single beat)
                        burst_last  <= (burst_len == 8'd0);

                    end else begin
                        burst_valid <= 1'b0;
                        burst_last  <= 1'b0;
                    end
                end

                BURST_ACTIVE: begin
                    if (burst_ready && burst_valid) begin
                        if (burst_last) begin
                            // Kết thúc burst
                            burst_state <= BURST_IDLE;
                            burst_valid <= 1'b0;
                            burst_last  <= 1'b0;
                        end else begin
                            // Tiếp tục burst
                            beat_count   <= beat_count + 1'b1;
                            current_addr <= next_addr;  // update addr

                            // ----------------------------------------
                            // FIX B: Dùng next_word_addr (combinational)
                            //        KHÔNG dùng burst_word_addr + 1
                            // ----------------------------------------
                            burst_data  <= memory[next_word_addr];
                            burst_valid <= 1'b1;

                            // ----------------------------------------
                            // FIX C: rlast đúng khi beat_count+1 == total_beats
                            //        beat_count hiện tại = beat đang output
                            //        beat_count+1        = beat sắp output
                            // ----------------------------------------
                            burst_last  <= (beat_count + 8'd1 == total_beats);
                        end
                    end
                    // Nếu !ready → giữ nguyên (hold)
                end

                default: burst_state <= BURST_IDLE;

            endcase
        end
    end

    // ========================================================================
    // Memory Initialization
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = 32'h00000013;  // NOP

        if (MEM_INIT_FILE != "") begin
            $readmemh(MEM_INIT_FILE, memory);
            $display("[IMEM] Loaded program from %s", MEM_INIT_FILE);
        end else begin
            `ifndef TESTBENCH_MODE
                $readmemh("cpu/memory_axi4full/program.hex", memory);
                $display("[IMEM] Loaded program from memory/program.hex");
            `else
                $display("[IMEM] TESTBENCH_MODE - initialized to NOP");
            `endif
        end
    end

    // ========================================================================
    // Debug
    // ========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (burst_req && burst_state == BURST_IDLE)
            $display("[IMEM] Burst start: addr=0x%h, len=%0d beats",
                     burst_addr, burst_len + 1);
        if (burst_valid && burst_ready)
            $display("[IMEM] beat[%0d]: addr=0x%h  data=0x%h  last=%b",
                     beat_count, current_addr, burst_data, burst_last);
    end
    `endif

endmodule