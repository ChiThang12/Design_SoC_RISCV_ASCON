// ============================================================================
// Module: dcache_tag_array
// ============================================================================
// Description:
//   Tag array with valid bits for data cache
//   - 64 entries (one per cache line)
//   - Each entry: [valid_bit | tag(22 bits)]
//   - No dirty bit needed (write-through policy)
//
// Author: ChiThang
// ============================================================================

`include "dcache_defines.vh"

module dcache_tag_array (
    input wire clk,
    input wire rst_n,
    
    // Lookup Interface
    input wire [5:0]  lookup_index,     // Cache line index
    input wire [21:0] lookup_tag,       // Tag to compare
    output wire       hit,              // Tag match & valid
    
    // Update Interface
    input wire        update_valid,     // Update enable
    input wire [5:0]  update_index,     // Line to update
    input wire [21:0] update_tag,       // New tag value
    
    // Flush Interface
    input wire        flush_all         // Invalidate all entries
);

    // ========================================================================
    // Storage Arrays
    // ========================================================================
    reg        valid_array [0:63];
    reg [21:0] tag_array   [0:63];
    
    // ========================================================================
    // Lookup Logic (Combinational)
    // ========================================================================
    wire tag_match;
    wire line_valid;
    
    assign line_valid = valid_array[lookup_index];
    assign tag_match  = (tag_array[lookup_index] == lookup_tag);
    assign hit        = line_valid && tag_match;
    
    // ========================================================================
    // Update Logic (Sequential)
    // ========================================================================
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: invalidate all entries
            for (i = 0; i < 64; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= 22'h0;
            end
        end else begin
            if (flush_all) begin
                // Flush: invalidate all entries
                for (i = 0; i < 64; i = i + 1) begin
                    valid_array[i] <= 1'b0;
                end
            end else if (update_valid) begin
                // Update single entry
                valid_array[update_index] <= 1'b1;
                tag_array[update_index]   <= update_tag;
            end
        end
    end

endmodule