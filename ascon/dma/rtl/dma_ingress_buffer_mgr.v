`timescale 1ns/1ps

module dma_ingress_buffer_mgr #(
    parameter WIDTH = 64,
    parameter DEPTH = 4
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   dma_start,
    input  wire                   dma_soft_rst,
    input  wire [WIDTH-1:0]       push_data,
    input  wire                   push_valid,
    input  wire                   pop_ready,
    output wire [WIDTH-1:0]       pop_data,
    output wire                   pop_valid,
    output wire [WIDTH-1:0]       pop_data_reg,
    output wire                   full,
    output wire                   empty,
    output wire [$clog2(DEPTH):0] count,
    output wire [$clog2(DEPTH):0] drain_count,
    output wire [$clog2(DEPTH):0] fill_count,
    output wire                   drain_bank_ready,
    output wire                   fill_bank_ready,
    output wire                   swap_pulse,
    output wire                   active_bank,
    output wire                   fill_bank_sel
);

    localparam COUNT_W = $clog2(DEPTH) + 1;

    wire fifo_rst_n = rst_n & ~dma_soft_rst;

    wire [WIDTH-1:0] bank0_dout_reg;
    wire [WIDTH-1:0] bank1_dout_reg;
    wire [WIDTH-1:0] bank0_fwft_dout;
    wire [WIDTH-1:0] bank1_fwft_dout;
    wire bank0_full, bank1_full;
    wire bank0_empty, bank1_empty;
    wire bank0_fwft_valid, bank1_fwft_valid;
    wire [COUNT_W-1:0] bank0_count;
    wire [COUNT_W-1:0] bank1_count;

    wire drain_bank;
    wire fill_bank;
    wire push_bank0 = push_valid && (fill_bank == 1'b0) && !bank0_full;
    wire push_bank1 = push_valid && (fill_bank == 1'b1) && !bank1_full;
    wire pop_bank0  = pop_ready && (drain_bank == 1'b0) && !bank0_empty;
    wire pop_bank1  = pop_ready && (drain_bank == 1'b1) && !bank1_empty;

    wire [COUNT_W:0] total_count_ext = {1'b0, bank0_count} + {1'b0, bank1_count};
    localparam [COUNT_W-1:0] COUNT_SAT = {COUNT_W{1'b1}};

    dma_pingpong_bank_state u_bank_state (
        .clk              (clk),
        .rst_n            (rst_n),
        .dma_start        (dma_start),
        .dma_soft_rst     (dma_soft_rst),
        .bank0_empty      (bank0_empty),
        .bank1_empty      (bank1_empty),
        .fill_bank_sel    (fill_bank),
        .drain_bank_sel   (drain_bank),
        .fill_bank_ready  (fill_bank_ready),
        .drain_bank_ready (drain_bank_ready),
        .swap_pulse       (swap_pulse)
    );

    assign active_bank = drain_bank;
    assign fill_bank_sel = fill_bank;
    assign pop_data     = (drain_bank == 1'b0) ? bank0_fwft_dout  : bank1_fwft_dout;
    assign pop_valid    = (drain_bank == 1'b0) ? bank0_fwft_valid : bank1_fwft_valid;
    assign pop_data_reg = (drain_bank == 1'b0) ? bank0_dout_reg   : bank1_dout_reg;
    assign empty        = bank0_empty & bank1_empty;
    assign full         = (fill_bank == 1'b0) ? bank0_full : bank1_full;
    assign count        = total_count_ext[COUNT_W] ? COUNT_SAT : total_count_ext[COUNT_W-1:0];
    assign drain_count  = (drain_bank == 1'b0) ? bank0_count : bank1_count;
    assign fill_count   = (fill_bank == 1'b0) ? bank0_count : bank1_count;

    sync_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) u_bank0 (
        .clk        (clk),
        .rst_n      (fifo_rst_n),
        .din        (push_data),
        .push       (push_bank0),
        .full       (bank0_full),
        .dout       (bank0_dout_reg),
        .pop        (pop_bank0),
        .empty      (bank0_empty),
        .fwft_dout  (bank0_fwft_dout),
        .fwft_valid (bank0_fwft_valid),
        .count      (bank0_count)
    );

    sync_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) u_bank1 (
        .clk        (clk),
        .rst_n      (fifo_rst_n),
        .din        (push_data),
        .push       (push_bank1),
        .full       (bank1_full),
        .dout       (bank1_dout_reg),
        .pop        (pop_bank1),
        .empty      (bank1_empty),
        .fwft_dout  (bank1_fwft_dout),
        .fwft_valid (bank1_fwft_valid),
        .count      (bank1_count)
    );
endmodule
