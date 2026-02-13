// ============================================================================
// Module: dcache_data_array
// ============================================================================
// Description:
//   Data storage for data cache with byte-enable write support
//   - 64 lines × 4 words = 256 entries (1D flattened array)
//   - Word-addressable read
//   - Byte-enable write (for partial word writes)
//
// Author: ChiThang
// ============================================================================

`include "cpu/interface/dcache/dcache_defines.vh"

module dcache_data_array (
    input wire clk,
    input wire rst_n,
    
    // Read Interface
    input wire [5:0]  read_index,       // Cache line index 
    input wire [1:0]  read_offset,      // Word offset within line
    output wire [31:0] read_data,       // Read data output
    
    // Write Interface (for refill and store operations)
    input wire        write_enable,     // Write enable
    input wire [5:0]  write_index,      // Cache line index
    input wire [1:0]  write_offset,     // Word offset within line
    input wire [31:0] write_data,       // Data to write
    input wire [3:0]  write_strb        // Byte enable (for partial writes)
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
    // Write Logic (Sequential with byte-enable)
    // ========================================================================
    wire [7:0] write_addr;
    
    assign write_addr = {write_index, write_offset};
    
    always @(posedge clk) begin
        if (write_enable) begin
            // Byte-enable write (for store byte/halfword/word)
            if (write_strb[0]) data_array[write_addr][7:0]   <= write_data[7:0];
            if (write_strb[1]) data_array[write_addr][15:8]  <= write_data[15:8];
            if (write_strb[2]) data_array[write_addr][23:16] <= write_data[23:16];
            if (write_strb[3]) data_array[write_addr][31:24] <= write_data[31:24];
        end
    end
    
    // ========================================================================
    // Initialization (optional - for simulation)
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            data_array[i] = 32'h00000000; // Initialize to zero
        end
    end

endmodule