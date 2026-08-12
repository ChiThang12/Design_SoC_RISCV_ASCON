`timescale 1ns/1ps

module dma_runtime_counters (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dma_start,
    input  wire        dma_soft_rst,
    input  wire        dma_busy,
    input  wire        rd_start_pulse,
    input  wire        rd_done_pulse,
    input  wire        wr_done_pulse,
    input  wire        payload_feed_pulse,
    input  wire        payload_chain_pulse,
    input  wire        write_chain_pulse,
    input  wire        ingress_swap_pulse,
    input  wire        egress_swap_pulse,
    input  wire        core_data_valid,
    input  wire        core_data_out_valid,
    output reg [31:0]  cnt_rd_issue,
    output reg [31:0]  cnt_rd_done,
    output reg [31:0]  cnt_wr_done,
    output reg [31:0]  cnt_payload_feed,
    output reg [31:0]  cnt_payload_chain,
    output reg [31:0]  cnt_write_chain,
    output reg [31:0]  cnt_ingress_swap,
    output reg [31:0]  cnt_egress_swap,
    output reg [31:0]  cnt_busy_cycles,
    output reg [31:0]  cnt_core_wait_cycles
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_rd_issue        <= 32'd0;
            cnt_rd_done         <= 32'd0;
            cnt_wr_done         <= 32'd0;
            cnt_payload_feed    <= 32'd0;
            cnt_payload_chain   <= 32'd0;
            cnt_write_chain     <= 32'd0;
            cnt_ingress_swap    <= 32'd0;
            cnt_egress_swap     <= 32'd0;
            cnt_busy_cycles     <= 32'd0;
            cnt_core_wait_cycles<= 32'd0;
        end else if (dma_soft_rst || dma_start) begin
            cnt_rd_issue        <= 32'd0;
            cnt_rd_done         <= 32'd0;
            cnt_wr_done         <= 32'd0;
            cnt_payload_feed    <= 32'd0;
            cnt_payload_chain   <= 32'd0;
            cnt_write_chain     <= 32'd0;
            cnt_ingress_swap    <= 32'd0;
            cnt_egress_swap     <= 32'd0;
            cnt_busy_cycles     <= 32'd0;
            cnt_core_wait_cycles<= 32'd0;
        end else begin
            if (rd_start_pulse)      cnt_rd_issue      <= cnt_rd_issue + 1'b1;
            if (rd_done_pulse)       cnt_rd_done       <= cnt_rd_done + 1'b1;
            if (wr_done_pulse)       cnt_wr_done       <= cnt_wr_done + 1'b1;
            if (payload_feed_pulse)  cnt_payload_feed  <= cnt_payload_feed + 1'b1;
            if (payload_chain_pulse) cnt_payload_chain <= cnt_payload_chain + 1'b1;
            if (write_chain_pulse)   cnt_write_chain   <= cnt_write_chain + 1'b1;
            if (ingress_swap_pulse)  cnt_ingress_swap  <= cnt_ingress_swap + 1'b1;
            if (egress_swap_pulse)   cnt_egress_swap   <= cnt_egress_swap + 1'b1;
            if (dma_busy)            cnt_busy_cycles   <= cnt_busy_cycles + 1'b1;
            if (core_data_valid && !core_data_out_valid)
                cnt_core_wait_cycles <= cnt_core_wait_cycles + 1'b1;
        end
    end
endmodule
