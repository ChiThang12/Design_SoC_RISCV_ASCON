// ============================================================================
// Module: icache_data_array
// ============================================================================
// Description:
//   Data storage for instruction cache
//   - 64 lines × 4 words = 256 entries (1D flattened array)
//   - Word-addressable read
//   - Line-addressable write (refill 4 words sequentially)
//
// Author: ChiThang
// ============================================================================

`include "icache_defines.vh"

module icache_data_array (
    input wire clk,
    input wire rst_n,
    
    // Read Interface
    input wire [5:0]  read_index,       // Cache line index
    input wire [1:0]  read_offset,      // Word offset within line
    output wire [31:0] read_data,       // Read data output
    
    // Write Interface (for refill)
    input wire        write_enable,     // Write enable
    input wire [5:0]  write_index,      // Cache line index
    input wire [1:0]  write_offset,     // Word offset within line
    input wire [31:0] write_data        // Data to write
);

    // ========================================================================
    // Storage Array (1D - 256 entries)
    // ========================================================================
    reg [31:0] data_array [0:255];
    
    // ========================================================================
    // Read Logic (Combinational)
    // ========================================================================
    wire [7:0] read_addr;
    
    // Calculate flattened address: (line_index * 4) + word_offset
    assign read_addr = {read_index, read_offset};
    assign read_data = data_array[read_addr];
    
    // ========================================================================
    // Write Logic (Sequential)
    // ========================================================================
    wire [7:0] write_addr;
    
    assign write_addr = {write_index, write_offset};
    
    always @(posedge clk) begin
        if (write_enable) begin
            data_array[write_addr] <= write_data;
        end
    end
    
    // ========================================================================
    // Initialization (optional - for simulation)
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            data_array[i] = 32'h00000013; // NOP
        end
    end

endmodule