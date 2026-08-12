`timescale 1ns/1ps

module dma_read_scheduler #(
    parameter RD_FIFO_DEPTH = 4
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         dma_start,
    input  wire                         dma_soft_rst,
    input  wire [0:0]                   context_id,
    input  wire [31:0]                  ad_src_addr,
    input  wire [28:0]                  ad_total_blocks,
    input  wire [7:0]                   ad_burst_len,
    input  wire [28:0]                  total_blocks,
    input  wire [7:0]                   burst_len,
    input  wire                         rd_busy,
    input  wire                         rd_done,
    input  wire                         rd_fifo_full,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_fill_count,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_drain_count,
    input  wire                         rd_buf_active_bank,
    input  wire                         rd_buf_fill_bank,
    input  wire                         rd_buf_drain_ready,
    input  wire                         rd_buf_fill_ready,

    output reg                          rd_start,
    output reg  [31:0]                  rd_override_addr,
    output reg                          rd_use_override,
    output wire [7:0]                   rd_burst_len,
    output reg                          status_rd_done,
    output reg  [0:0]                   context_id_active,
    output reg  [1:0]                   dma_phase
);

    localparam [1:0]
        DMA_PHASE_AD      = 2'd0,
        DMA_PHASE_PAYLOAD = 2'd1,
        DMA_PHASE_DONE    = 2'd2;

    reg [28:0] rd_blocks_sent;

    wire has_ad = (ad_total_blocks != 29'd0);
    wire [28:0] payload_max_burst_blocks = {21'd0, burst_len} + 29'd1;
    wire [28:0] payload_blocks_remaining =
        (rd_blocks_sent < total_blocks) ? (total_blocks - rd_blocks_sent) : 29'd0;
    wire [28:0] payload_initial_blocks =
        (total_blocks > payload_max_burst_blocks) ? payload_max_burst_blocks : total_blocks;
    wire [28:0] payload_issue_blocks;
    wire [7:0]  payload_issue_burst_len;
    wire [1:0]  payload_issue_urgency;
    wire [7:0] cur_burst_len = (dma_phase == DMA_PHASE_AD) ? ad_burst_len :
                                                          payload_issue_burst_len;
    wire [28:0] blocks_per_read = {21'd0, cur_burst_len} + 29'd1;
    wire payload_issue_refill;
    wire payload_issue_steady =
        payload_issue_refill &&
        (payload_issue_urgency >= 2'd2) &&
        (payload_issue_blocks != 29'd0);
    wire [28:0] payload_start_blocks =
        (payload_issue_urgency >= 2'd2 && payload_issue_blocks != 29'd0) ?
            payload_issue_blocks : payload_initial_blocks;

    assign rd_burst_len = cur_burst_len;

    dma_read_refill_policy #(
        .RD_FIFO_DEPTH (RD_FIFO_DEPTH)
    ) u_read_refill_policy (
        .rd_busy                 (rd_busy),
        .rd_fifo_full            (rd_fifo_full),
        .rd_fifo_fill_count      (rd_fifo_fill_count),
        .rd_fifo_drain_count     (rd_fifo_drain_count),
        .active_bank             (rd_buf_active_bank),
        .fill_bank_sel           (rd_buf_fill_bank),
        .drain_bank_ready        (rd_buf_drain_ready),
        .fill_bank_ready         (rd_buf_fill_ready),
        .payload_blocks_remaining(payload_blocks_remaining),
        .issue_refill            (payload_issue_refill)
    );

    dma_read_bank_credit_planner #(
        .RD_FIFO_DEPTH (RD_FIFO_DEPTH)
    ) u_read_bank_credit_planner (
        .payload_blocks_remaining(payload_blocks_remaining),
        .max_burst_len          (burst_len),
        .rd_fifo_fill_count     (rd_fifo_fill_count),
        .rd_fifo_drain_count    (rd_fifo_drain_count),
        .fill_bank_ready        (rd_buf_fill_ready),
        .drain_bank_ready       (rd_buf_drain_ready),
        .target_blocks          (payload_issue_blocks),
        .target_burst_len       (payload_issue_burst_len),
        .urgency_class          (payload_issue_urgency)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_start          <= 1'b0;
            rd_override_addr  <= 32'h0;
            rd_use_override   <= 1'b0;
            rd_blocks_sent    <= 29'd0;
            dma_phase         <= DMA_PHASE_AD;
            status_rd_done    <= 1'b0;
            context_id_active <= 1'b0;
        end else if (dma_soft_rst) begin
            rd_start          <= 1'b0;
            rd_override_addr  <= 32'h0;
            rd_use_override   <= 1'b0;
            rd_blocks_sent    <= 29'd0;
            dma_phase         <= DMA_PHASE_AD;
            status_rd_done    <= 1'b0;
            context_id_active <= 1'b0;
        end else begin
            rd_start <= 1'b0;

            if (dma_start) begin
                rd_blocks_sent    <= 29'd0;
                status_rd_done    <= 1'b0;
                context_id_active <= context_id;
                if (has_ad) begin
                    dma_phase        <= DMA_PHASE_AD;
                    rd_override_addr <= ad_src_addr;
                    rd_use_override  <= 1'b1;
                    rd_start         <= 1'b1;
                end else begin
                    dma_phase       <= DMA_PHASE_PAYLOAD;
                    rd_use_override <= 1'b0;
                    if (payload_start_blocks > 0) begin
                        rd_start       <= 1'b1;
                        rd_blocks_sent <= payload_start_blocks;
                    end
                end
            end else if (rd_done) begin
                case (dma_phase)
                    DMA_PHASE_AD: begin
                        if (rd_blocks_sent + blocks_per_read < ad_total_blocks) begin
                            rd_start       <= 1'b1;
                            rd_blocks_sent <= rd_blocks_sent + blocks_per_read;
                        end else begin
                            rd_blocks_sent <= 29'd0;
                            dma_phase      <= DMA_PHASE_PAYLOAD;
                            rd_use_override <= 1'b0;
                            if (payload_start_blocks > 0) begin
                                rd_start       <= 1'b1;
                                rd_blocks_sent <= payload_start_blocks;
                            end
                        end
                    end
                    DMA_PHASE_PAYLOAD: begin
                        if (payload_issue_steady) begin
                            rd_start       <= 1'b1;
                            rd_blocks_sent <= rd_blocks_sent + payload_issue_blocks;
                        end
                    end
                    default: ;
                endcase
            end else if (dma_phase == DMA_PHASE_PAYLOAD) begin
                if (payload_issue_refill && (payload_issue_urgency != 2'd0)) begin
                    rd_start       <= 1'b1;
                    rd_blocks_sent <= rd_blocks_sent + payload_issue_blocks;
                end else if (!rd_busy && rd_blocks_sent >= total_blocks) begin
                    status_rd_done <= 1'b1;
                end
            end
        end
    end
endmodule
