`timescale 1ns/1ps

module dma_atu #(
    parameter ADDR_WIDTH = 32
) (
    input  wire [ADDR_WIDTH-1:0]  atu_base,
    input  wire [ADDR_WIDTH-1:0]  atu_window,
    input  wire [ADDR_WIDTH-1:0]  src_addr,
    input  wire [ADDR_WIDTH-1:0]  dst_addr,
    input  wire [ADDR_WIDTH-1:0]  ad_src_addr,
    output wire [ADDR_WIDTH-1:0]  src_addr_atu,
    output wire [ADDR_WIDTH-1:0]  dst_addr_atu,
    output wire [ADDR_WIDTH-1:0]  ad_src_addr_atu
);

    function [31:0] atu_translate;
        input [31:0] addr;
        begin
            if (atu_window != 32'h0 && addr < atu_window)
                atu_translate = atu_base + addr;
            else
                atu_translate = addr;
        end
    endfunction

    assign src_addr_atu    = atu_translate(src_addr);
    assign dst_addr_atu    = atu_translate(dst_addr);
    assign ad_src_addr_atu = atu_translate(ad_src_addr);

endmodule
