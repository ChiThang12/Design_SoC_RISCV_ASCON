// ============================================================================
// inst_mem.v - Instruction Memory with Burst Read Support
// ============================================================================
// Description:
//   - Instruction memory array (4KB)
//   - Supports both single access and burst reads
//   - Read-only memory (ROM)
//   - Can be initialized from hex file
//
// Author: ChiThang
// Updated: Added burst read support for I-Cache
// ============================================================================

module inst_mem #(
    parameter MEM_SIZE = 4096,        // Memory size in bytes (4KB)
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_INIT_FILE = ""      // Optional hex file for initialization
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Simple Interface (for backwards compatibility)
    // ========================================================================
    input  wire [ADDR_WIDTH-1:0] PC,             // Program Counter (byte address)
    output wire [DATA_WIDTH-1:0] Instruction_Code,// Instruction output
    
    // ========================================================================
    // Burst Read Interface (for cache line fills)
    // ========================================================================
    input  wire [ADDR_WIDTH-1:0] burst_addr,     // Burst start address
    input  wire [7:0]            burst_len,      // Burst length (number of words - 1)
    input  wire                  burst_req,      // Burst request
    output reg  [DATA_WIDTH-1:0] burst_data,     // Burst data output
    output reg                   burst_valid,    // Burst data valid
    output reg                   burst_last,     // Last word in burst
    input  wire                  burst_ready     // Master ready to receive
);

    // ========================================================================
    // Local Parameters
    // ========================================================================
    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);  // 1024 words
    localparam ADDR_LSB = $clog2(DATA_WIDTH/8);        // 2 for 32-bit
    
    // ========================================================================
    // Memory Array
    // ========================================================================
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];
    
    // ========================================================================
    // Simple Read Interface (Combinational)
    // ========================================================================
    wire [9:0] word_addr;
    assign word_addr = PC[11:2];  // Extract word address from byte address
    assign Instruction_Code = memory[word_addr];
    
    // ========================================================================
    // Burst Read State Machine
    // ========================================================================
    localparam BURST_IDLE = 1'b0;
    localparam BURST_ACTIVE = 1'b1;
    
    reg burst_state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [7:0] beat_count;
    reg [7:0] total_beats;
    
    // Calculate word address for burst
    wire [ADDR_WIDTH-1:0] burst_word_addr;
    assign burst_word_addr = current_addr[ADDR_WIDTH-1:ADDR_LSB];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_state <= BURST_IDLE;
            burst_data  <= {DATA_WIDTH{1'b0}};
            burst_valid <= 1'b0;
            burst_last  <= 1'b0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            beat_count  <= 8'd0;
            total_beats <= 8'd0;
        end else begin
            case (burst_state)
                BURST_IDLE: begin
                    if (burst_req) begin
                        // Start new burst
                        current_addr <= burst_addr;
                        beat_count   <= 8'd0;
                        total_beats  <= burst_len;
                        burst_state  <= BURST_ACTIVE;
                        
                        // Output first word immediately
                        if (burst_word_addr < MEM_DEPTH) begin
                            burst_data <= memory[burst_word_addr];
                        end else begin
                            burst_data <= {DATA_WIDTH{1'b0}};
                        end
                        burst_valid <= 1'b1;
                        burst_last  <= (burst_len == 8'd0);
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
                            // Continue burst - increment address
                            beat_count   <= beat_count + 1'b1;
                            current_addr <= current_addr + (DATA_WIDTH/8);
                            
                            // Output next word
                            if (burst_word_addr + 1 < MEM_DEPTH) begin
                                burst_data <= memory[burst_word_addr + 1];
                            end else begin
                                burst_data <= {DATA_WIDTH{1'b0}};
                            end
                            
                            burst_valid <= 1'b1;
                            burst_last  <= (beat_count + 1 == total_beats);
                        end
                    end
                    // If not ready, hold current values
                end
                
                default: begin
                    burst_state <= BURST_IDLE;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Memory Initialization
    // ========================================================================
    integer i;
    initial begin
        // Initialize to NOP instruction (ADDI x0, x0, 0)
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = 32'h00000013;
        end
        
        // Load from file if specified
        if (MEM_INIT_FILE != "") begin
            $readmemh(MEM_INIT_FILE, memory);
            $display("[IMEM] Loaded program from %s", MEM_INIT_FILE);
        end else begin
            `ifndef TESTBENCH_MODE
                $readmemh("memory/program.hex", memory);
                $display("[IMEM] Loaded program from memory/program.hex");
            `else
                $display("[IMEM] Running in TESTBENCH_MODE - initialized to NOP");
            `endif
        end
    end
    
    // ========================================================================
    // Debug/Simulation
    // ========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (burst_req && burst_state == BURST_IDLE) begin
            $display("[IMEM] Burst read: addr=0x%h, len=%0d", burst_addr, burst_len + 1);
        end
        if (burst_valid && burst_ready) begin
            $display("[IMEM] Burst data[%0d]: addr=0x%h, data=0x%h, last=%b",
                     beat_count, current_addr, burst_data, burst_last);
        end
    end
    `endif

endmodule