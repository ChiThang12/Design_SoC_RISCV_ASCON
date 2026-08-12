`timescale 1ns/1ps

module dma_read_refill_policy #(
    parameter RD_FIFO_DEPTH = 4
) (
    input  wire                         rd_busy,
    input  wire                         rd_fifo_full,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_fill_count,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_drain_count,
    input  wire                         active_bank,
    input  wire                         fill_bank_sel,
    input  wire                         drain_bank_ready,
    input  wire                         fill_bank_ready,
    input  wire [28:0]                  payload_blocks_remaining,
    output wire                         issue_refill
);

    localparam integer FILL_LOW_WM      = (RD_FIFO_DEPTH > 2) ? (RD_FIFO_DEPTH/2) : 1;
    localparam integer DRAIN_GUARD_WM   = 1;
    localparam integer FILL_TARGET_BASE = (RD_FIFO_DEPTH > 2) ? (RD_FIFO_DEPTH/2) : 1;
    localparam integer FILL_TARGET_HIGH = (RD_FIFO_DEPTH > 1) ? (RD_FIFO_DEPTH-1) : 1;
    localparam integer FILL_TARGET_WARM = (FILL_TARGET_BASE < FILL_TARGET_HIGH) ?
                                          (FILL_TARGET_BASE + 1) : FILL_TARGET_HIGH;

    wire payload_pending  = (payload_blocks_remaining != 29'd0);
    wire fill_low         = (rd_fifo_fill_count <= FILL_LOW_WM);
    wire drain_near_empty = (rd_fifo_drain_count <= DRAIN_GUARD_WM);
    wire role_split_ok    = (active_bank != fill_bank_sel);
    wire [28:0] fill_target_level =
        drain_near_empty ? FILL_TARGET_HIGH[28:0] :
        fill_bank_ready  ? FILL_TARGET_BASE[28:0] :
                           FILL_TARGET_WARM[28:0];
    wire fill_below_target = (rd_fifo_fill_count < fill_target_level[$clog2(RD_FIFO_DEPTH):0]);

    // Refill earlier when the current drain bank is nearly empty and the next
    // fill bank has not accumulated enough data yet.
    wire refill_urgent = (rd_fifo_fill_count == {($clog2(RD_FIFO_DEPTH)+1){1'b0}}) &&
                         drain_near_empty &&
                         drain_bank_ready &&
                         !fill_bank_ready;

    assign issue_refill = payload_pending &&
                          !rd_busy &&
                          !rd_fifo_full &&
                          role_split_ok &&
                          ((fill_below_target && (!fill_bank_ready || drain_near_empty)) ||
                           (fill_low && drain_bank_ready) ||
                           refill_urgent);
endmodule
