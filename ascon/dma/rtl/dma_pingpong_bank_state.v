`timescale 1ns/1ps

module dma_pingpong_bank_state (
    input  wire clk,
    input  wire rst_n,
    input  wire dma_start,
    input  wire dma_soft_rst,
    input  wire bank0_empty,
    input  wire bank1_empty,
    output reg  fill_bank_sel,
    output reg  drain_bank_sel,
    output wire fill_bank_ready,
    output wire drain_bank_ready,
    output wire swap_pulse
);

    wire bank0_has_data = !bank0_empty;
    wire bank1_has_data = !bank1_empty;
    wire cur_fill_bank_ready  = (fill_bank_sel  == 1'b0) ? bank0_has_data : bank1_has_data;
    wire cur_drain_bank_ready = (drain_bank_sel == 1'b0) ? bank0_has_data : bank1_has_data;
    assign swap_pulse = !cur_drain_bank_ready && cur_fill_bank_ready;

    assign fill_bank_ready  = cur_fill_bank_ready;
    assign drain_bank_ready = cur_drain_bank_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_bank_sel  <= 1'b0;
            drain_bank_sel <= 1'b1;
        end else if (dma_soft_rst) begin
            fill_bank_sel  <= 1'b0;
            drain_bank_sel <= 1'b1;
        end else if (dma_start) begin
            fill_bank_sel  <= 1'b0;
            drain_bank_sel <= 1'b1;
        end else if (!cur_drain_bank_ready && cur_fill_bank_ready) begin
            fill_bank_sel  <= drain_bank_sel;
            drain_bank_sel <= fill_bank_sel;
        end
    end
endmodule
