`timescale 1ns/1ps

module dma_write_bank_credit_planner #(
    parameter WR_FIFO_DEPTH = 32,
    parameter MAX_BURST_LEN = 8'd15
) (
    input  wire [28:0]                  remaining_beats,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_count,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_drain_count,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_fill_count,
    input  wire                         fill_bank_ready,
    input  wire                         drain_bank_ready,
    output wire [7:0]                   target_burst_beats,
    output wire [1:0]                   urgency_class
);

    localparam integer FILL_BACKLOG_WM = (WR_FIFO_DEPTH > 4) ? (WR_FIFO_DEPTH/4) : 1;
    localparam integer FILL_BACKLOG_HI = (WR_FIFO_DEPTH > 8) ? (WR_FIFO_DEPTH/2) : 2;

    wire [28:0] max_burst_beats_29 = {21'd0, MAX_BURST_LEN} + 29'd1;
    wire [28:0] total_available_beats = {{(29-($clog2(WR_FIFO_DEPTH)+1)){1'b0}}, fifo_count} >> 1;
    wire [28:0] available_drain_beats = {{(29-($clog2(WR_FIFO_DEPTH)+1)){1'b0}}, fifo_drain_count} >> 1;
    wire fill_backlog_hi = (fifo_fill_count >= FILL_BACKLOG_HI);
    wire fill_backlog    = (fifo_fill_count >= FILL_BACKLOG_WM);
    wire small_packet_holdoff =
        (remaining_beats <= 29'd3) &&
        (total_available_beats < remaining_beats);
    wire small_packet_ready = (remaining_beats <= 29'd3) &&
                              (total_available_beats >= remaining_beats);
    wire [28:0] backlog_bias_beats =
        (fill_backlog_hi && fill_bank_ready) ? max_burst_beats_29 :
        (fill_backlog && fill_bank_ready)    ? available_drain_beats :
                                               29'd1;
    wire [28:0] desired_beats =
        (!drain_bank_ready || small_packet_holdoff) ? 29'd0 :
        small_packet_ready ? remaining_beats :
        drain_bank_ready ?
            ((available_drain_beats > backlog_bias_beats) ? available_drain_beats :
                                                            backlog_bias_beats) :
            29'd0;
    wire [28:0] max_capped =
        (desired_beats > max_burst_beats_29) ? max_burst_beats_29 : desired_beats;
    wire [28:0] planned_beats =
        (remaining_beats > max_capped) ? max_capped : remaining_beats;
    wire backlog_pressure = fill_backlog_hi && fill_bank_ready;
    wire drain_light      = (available_drain_beats <= 29'd1);

    assign target_burst_beats = planned_beats[7:0];
    assign urgency_class =
        (remaining_beats == 29'd0)                 ? 2'd0 :
        (!drain_bank_ready || small_packet_holdoff)? 2'd0 :
        backlog_pressure                           ? 2'd3 :
        drain_light                                ? 2'd1 :
                                                     2'd2;
endmodule
