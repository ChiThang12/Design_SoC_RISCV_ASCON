`timescale 1ns/1ps

module dma_completion_scoreboard (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dma_start,
    input  wire        dma_soft_rst,
    input  wire [28:0] expected_wr_beats,
    input  wire        wr_done,
    input  wire        rd_error,
    input  wire        wr_error,
    input  wire        wr_fifo_full,
    input  wire        core_data_out_valid,
    input  wire        core_tag_valid,
    input  wire        push_busy,
    input  wire        tag_latch_pending,

    output reg  [28:0] wr_beats_done,
    output reg         status_wr_done,
    output reg         status_fifo_overflow,
    output reg         dma_busy,
    output reg         dma_done,
    output reg         dma_error
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_beats_done        <= 29'd0;
            status_wr_done       <= 1'b0;
            status_fifo_overflow <= 1'b0;
            dma_busy             <= 1'b0;
            dma_done             <= 1'b0;
            dma_error            <= 1'b0;
        end else if (dma_soft_rst) begin
            wr_beats_done        <= 29'd0;
            status_wr_done       <= 1'b0;
            status_fifo_overflow <= 1'b0;
            dma_busy             <= 1'b0;
            dma_done             <= 1'b0;
            dma_error            <= 1'b0;
        end else begin
            dma_done <= 1'b0;

            if (dma_start) begin
                dma_busy       <= 1'b1;
                dma_error      <= 1'b0;
                status_wr_done <= 1'b0;
                wr_beats_done  <= 29'd0;
            end

            if (rd_error || wr_error)
                dma_error <= 1'b1;

            if (wr_fifo_full && (core_data_out_valid || core_tag_valid || push_busy || tag_latch_pending)) begin
                status_fifo_overflow <= 1'b1;
                dma_error            <= 1'b1;
            end

            if (wr_done) begin
                wr_beats_done <= wr_beats_done + 1'b1;
                if (wr_beats_done + 1'b1 == expected_wr_beats) begin
                    status_wr_done <= 1'b1;
                    dma_busy       <= 1'b0;
                    dma_done       <= 1'b1;
                end
            end
        end
    end
endmodule
