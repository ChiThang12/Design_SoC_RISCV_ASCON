`timescale 1ns/1ps

module dma_read_bank_credit_planner #(
    parameter RD_FIFO_DEPTH = 4
) (
    input  wire [28:0]                  payload_blocks_remaining,
    input  wire [7:0]                   max_burst_len,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_fill_count,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_drain_count,
    input  wire                         fill_bank_ready,
    input  wire                         drain_bank_ready,
    output wire [28:0]                  target_blocks,
    output wire [7:0]                   target_burst_len,
    output wire [1:0]                   urgency_class
);

    localparam integer FILL_TARGET_BASE = (RD_FIFO_DEPTH > 2) ? (RD_FIFO_DEPTH/2) : 1;
    localparam integer FILL_TARGET_HIGH = (RD_FIFO_DEPTH > 1) ? (RD_FIFO_DEPTH-1) : 1;
    localparam integer DRAIN_GUARD_WM   = 1;

    wire drain_near_empty = (rd_fifo_drain_count <= DRAIN_GUARD_WM);
    wire [28:0] max_burst_blocks = {21'd0, max_burst_len} + 29'd1;
    wire [28:0] target_fill_level =
        drain_near_empty ? FILL_TARGET_HIGH[28:0] :
        fill_bank_ready  ? FILL_TARGET_BASE[28:0] :
                           (FILL_TARGET_BASE + 1);
    wire [28:0] fill_count_ext = {{(29-($clog2(RD_FIFO_DEPTH)+1)){1'b0}}, rd_fifo_fill_count};
    wire [28:0] planner_deficit =
        (target_fill_level > fill_count_ext) ? (target_fill_level - fill_count_ext) : 29'd1;
    wire [28:0] desired_blocks =
        drain_bank_ready ? planner_deficit : max_burst_blocks;
    wire [28:0] capped_to_max =
        (desired_blocks > max_burst_blocks) ? max_burst_blocks : desired_blocks;
    wire [28:0] planned_blocks =
        (payload_blocks_remaining > capped_to_max) ? capped_to_max : payload_blocks_remaining;
    wire refill_urgent = drain_near_empty && !fill_bank_ready;
    wire refill_warm   = !drain_near_empty && !fill_bank_ready;

    assign target_blocks = planned_blocks;
    assign target_burst_len = (planned_blocks == 29'd0) ? 8'd0 : (planned_blocks[7:0] - 8'd1);
    assign urgency_class =
        (payload_blocks_remaining == 29'd0) ? 2'd0 :
        refill_urgent                       ? 2'd3 :
        refill_warm                         ? 2'd2 :
        (drain_bank_ready && (planned_blocks <= 29'd1)) ? 2'd1 :
                                                          2'd2;
endmodule
