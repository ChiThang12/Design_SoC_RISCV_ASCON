`timescale 1ns/1ps

// Compatibility wrapper for legacy S-box testbenches.
module ASCON_SBOX (
    input  wire [4:0] in,
    output wire [4:0] out
);
    ASCON_SBOX_PIPELINED #(
        .G_SBOX_PIPELINE(0)
    ) u_sbox (
        .clk  (1'b0),
        .rst_n(1'b1),
        .in   (in),
        .out  (out)
    );
endmodule
