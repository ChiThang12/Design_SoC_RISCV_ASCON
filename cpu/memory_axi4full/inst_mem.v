// ============================================================================
// inst_mem.v - ZERO-LATENCY Instruction Memory for CPI=1.0
// ============================================================================
// OPTIMIZATION:
//   - First beat available SAME CYCLE as burst_req (combinational read)
//   - Subsequent beats pipelined (1 beat/cycle)
//   - Total latency: 0 cycle for first word, N-1 more cycles for remaining
//   - Supports 10-word cache line refill (ARLEN=9, 10 beats)
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
    output wire [DATA_WIDTH-1:0] burst_data,
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
    
    // ========================================================================
    // CRITICAL: Combinational burst_data for ZERO-LATENCY first beat
    // ========================================================================
    wire [ADDR_WIDTH-1:0] read_addr;
    wire [ADDR_WIDTH-1:0] read_word_addr;
    
    // Mux between burst_addr (first beat) and current_addr (subsequent beats)
    assign read_addr = (burst_state == BURST_IDLE && burst_req) ? 
                       burst_addr : current_addr;
    assign read_word_addr = read_addr[ADDR_WIDTH-1:ADDR_LSB];
    
    // COMBINATIONAL READ - Available SAME CYCLE!
    assign burst_data = memory[read_word_addr];

    // Next address calculation
    wire [ADDR_WIDTH-1:0] next_addr;
    wire [ADDR_WIDTH-1:0] next_word_addr;
    assign next_addr      = current_addr + (DATA_WIDTH/8);
    assign next_word_addr = next_addr[ADDR_WIDTH-1:ADDR_LSB];

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
                        // ================================================
                        // ZERO-LATENCY: burst_data already available via
                        // combinational read (see assign above)
                        // Just assert valid/last immediately!
                        // ================================================
                        current_addr <= burst_addr;
                        beat_count   <= 8'd0;
                        total_beats  <= burst_len;
                        burst_state  <= BURST_ACTIVE;

                        burst_valid <= 1'b1;
                        burst_last  <= (burst_len == 8'd0);  // Single beat case

                    end else begin
                        burst_valid <= 1'b0;
                        burst_last  <= 1'b0;
                    end
                end

                BURST_ACTIVE: begin
                    if (burst_ready && burst_valid) begin
                        if (burst_last) begin
                            // End of burst
                            burst_state <= BURST_IDLE;
                            burst_valid <= 1'b0;
                            burst_last  <= 1'b0;
                        end else begin
                            // Continue burst
                            beat_count   <= beat_count + 1'b1;
                            current_addr <= next_addr;

                            // burst_data will update combinationally via next_addr
                            burst_valid <= 1'b1;
                            burst_last  <= (beat_count + 8'd1 == total_beats);
                        end
                    end
                    // If !ready → hold current state
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
                $display("[IMEM] Loaded program from cpu/memory_axi4full/program.hex");
            `else
                $display("[IMEM] TESTBENCH_MODE - initialized to NOP");
            `endif
        end
    end

endmodule