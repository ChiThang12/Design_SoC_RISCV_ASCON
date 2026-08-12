`timescale 1ns/1ps

module dma_write_drain_policy #(
    parameter WR_FIFO_DEPTH = 32
) (
    input  wire                         wr_busy,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_drain_count,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_fill_count,
    input  wire                         active_bank,
    input  wire                         fill_bank_sel,
    input  wire                         drain_bank_ready,
    input  wire                         fill_bank_ready,
    input  wire [28:0]                  remaining_beats,
    output wire                         issue_drain
);

    localparam integer DRAIN_START_WM  = 2;
    localparam integer FILL_BACKLOG_WM = (WR_FIFO_DEPTH > 4) ? (WR_FIFO_DEPTH/4) : 1;
    localparam integer FILL_BACKLOG_HI = (WR_FIFO_DEPTH > 8) ? (WR_FIFO_DEPTH/2) : 2;

    wire beats_pending   = (remaining_beats != 29'd0);
    wire role_split_ok   = (active_bank != fill_bank_sel);
    wire enough_to_start = (fifo_drain_count >= DRAIN_START_WM);
    wire fill_backlog    = (fifo_fill_count >= FILL_BACKLOG_WM);
    wire fill_backlog_hi = (fifo_fill_count >= FILL_BACKLOG_HI);
    wire drain_starving  = (fifo_drain_count < DRAIN_START_WM);
    wire keep_overlap_bias = fill_bank_ready && fill_backlog_hi;

    // If the active drain bank is ready and the other bank is already filling,
    // allow draining once we have the minimum 64-bit beat available. If the
    // fill bank is building a large backlog, drain sooner to preserve overlap.
    assign issue_drain = beats_pending &&
                         !wr_busy &&
                         role_split_ok &&
                         drain_bank_ready &&
                         (enough_to_start ||
                          (drain_starving && fill_backlog && keep_overlap_bias));
endmodule
