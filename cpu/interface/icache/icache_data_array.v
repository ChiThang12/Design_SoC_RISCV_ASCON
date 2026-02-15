`include "cpu/interface/icache/icache_defines.vh"

// ============================================================================
// icache_data_array — 32 lines × 8 words = 256 entries (giữ nguyên depth)
// Thay đổi: offset 2 bit → 3 bit, index 6 bit → 5 bit
// ============================================================================
module icache_data_array (
    input wire clk,
    input wire rst_n,

    // Read
    input wire [4:0]   read_index,    // 5 bit (32 lines)
    input wire [2:0]   read_offset,   // 3 bit (8 words)
    output wire [31:0] read_data,

    // Write (refill)
    input wire         write_enable,
    input wire [4:0]   write_index,   // 5 bit
    input wire [2:0]   write_offset,  // 3 bit
    input wire [31:0]  write_data
);
    // 32 lines × 8 words = 256 entries — depth không đổi
    reg [31:0] data_array [0:255];

    // Read: {index[4:0], offset[2:0]} = 8 bit address
    wire [7:0] read_addr  = {read_index,  read_offset};
    wire [7:0] write_addr = {write_index, write_offset};

    assign read_data = data_array[read_addr];

    always @(posedge clk) begin
        if (write_enable)
            data_array[write_addr] <= write_data;
    end

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            data_array[i] = 32'h00000013; // NOP
    end
endmodule