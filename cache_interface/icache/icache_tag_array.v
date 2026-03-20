`include "cache_interface/icache/icache_defines.vh"

// ============================================================================
// icache_tag_array — 32 lines, index 5 bit, tag 22 bit
// ============================================================================
module icache_tag_array (
    input wire clk,
    input wire rst_n,

    input wire [4:0]   lookup_index,
    input wire [21:0]  lookup_tag,
    output wire        hit,

    input wire         update_valid,
    input wire [4:0]   update_index,
    input wire [21:0]  update_tag,

    input wire         flush_all
);
    reg        valid_array [0:31];
    reg [21:0] tag_array   [0:31];

    assign hit = valid_array[lookup_index] &&
                 (tag_array[lookup_index] == lookup_tag);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= 22'h0;
            end
        end else begin
            if (flush_all) begin
                for (i = 0; i < 32; i = i + 1)
                    valid_array[i] <= 1'b0;
            end else if (update_valid) begin
                valid_array[update_index] <= 1'b1;
                tag_array[update_index]   <= update_tag;
            end
        end
    end
endmodule