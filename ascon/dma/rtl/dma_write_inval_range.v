`timescale 1ns/1ps

module dma_write_inval_range #(
    parameter ADDR_WIDTH = 32
) (
    input  wire [ADDR_WIDTH-1:0] burst_addr,
    input  wire [7:0]            burst_beats,
    output wire [ADDR_WIDTH-1:0] first_line_addr,
    output wire [ADDR_WIDTH-1:0] last_line_addr,
    output wire [7:0]            line_count
);

    wire [ADDR_WIDTH-1:0] burst_bytes = {21'd0, burst_beats, 3'b000};
    wire [ADDR_WIDTH-1:0] last_byte_addr =
        burst_addr + burst_bytes - {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
    wire [ADDR_WIDTH-1:0] first_line = {burst_addr[ADDR_WIDTH-1:4], 4'b0000};
    wire [ADDR_WIDTH-1:0] last_line  = {last_byte_addr[ADDR_WIDTH-1:4], 4'b0000};
    wire [ADDR_WIDTH-1:0] line_span_bytes = last_line - first_line;

    assign first_line_addr = first_line;
    assign last_line_addr  = last_line;
    assign line_count      = line_span_bytes[7:4] + 8'd1;
endmodule
