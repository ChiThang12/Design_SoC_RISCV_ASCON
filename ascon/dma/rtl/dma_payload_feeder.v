`timescale 1ns/1ps

module dma_payload_feeder #(
    parameter RD_FIFO_DEPTH = 4
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         dma_start,
    input  wire                         dma_soft_rst,
    input  wire                         dma_phase_payload,
    input  wire                         ad_pump_done,
    input  wire [63:0]                  rd_fifo_fwft_dout,
    input  wire                         rd_fifo_fwft_valid,
    input  wire [$clog2(RD_FIFO_DEPTH):0] rd_fifo_drain_count,
    input  wire                         rd_buf_drain_ready,
    input  wire                         rd_buf_fill_ready,
    input  wire [28:0]                  total_blocks,
    input  wire                         core_data_out_valid,
    output reg  [31:0]                  core_ptext_0,
    output reg  [31:0]                  core_ptext_1,
    output reg                          core_data_valid,
    output reg                          core_start,
    output reg                          core_data_last,
    output reg                          rd_fifo_pop,
    output reg  [28:0]                  core_blocks_fed,
    output reg                          feed_pulse,
    output reg                          chain_pulse
);

    localparam [1:0]
        PUMP_IDLE      = 2'd0,
        PUMP_START     = 2'd1,
        PUMP_WAIT_CORE = 2'd2;

    reg [1:0] pump_state;

    wire feed_window_open =
        rd_fifo_fwft_valid &&
        (rd_fifo_drain_count != {($clog2(RD_FIFO_DEPTH)+1){1'b0}}) &&
        dma_phase_payload &&
        ad_pump_done &&
        (core_blocks_fed < total_blocks);
    wire high_urgency_chain = rd_buf_drain_ready && !rd_buf_fill_ready &&
                              (rd_fifo_drain_count <= {{($clog2(RD_FIFO_DEPTH)){1'b0}}, 1'b1});
    wire warm_urgency_chain = rd_buf_drain_ready && rd_buf_fill_ready;
    wire allow_chain_feed   = feed_window_open && (high_urgency_chain || warm_urgency_chain);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pump_state      <= PUMP_IDLE;
            rd_fifo_pop     <= 1'b0;
            core_ptext_0    <= 32'h0;
            core_ptext_1    <= 32'h0;
            core_data_valid <= 1'b0;
            core_start      <= 1'b0;
            core_data_last  <= 1'b0;
            core_blocks_fed <= 29'd0;
            feed_pulse      <= 1'b0;
            chain_pulse     <= 1'b0;
        end else if (dma_soft_rst) begin
            pump_state      <= PUMP_IDLE;
            rd_fifo_pop     <= 1'b0;
            core_ptext_0    <= 32'h0;
            core_ptext_1    <= 32'h0;
            core_data_valid <= 1'b0;
            core_start      <= 1'b0;
            core_data_last  <= 1'b0;
            core_blocks_fed <= 29'd0;
            feed_pulse      <= 1'b0;
            chain_pulse     <= 1'b0;
        end else begin
            rd_fifo_pop <= 1'b0;
            core_start  <= 1'b0;
            feed_pulse  <= 1'b0;
            chain_pulse <= 1'b0;

            if (dma_start) begin
                pump_state      <= PUMP_IDLE;
                core_blocks_fed <= 29'd0;
                core_data_valid <= 1'b0;
                core_start      <= 1'b1;
            end

            case (pump_state)
                PUMP_IDLE: begin
                    if (feed_window_open) begin
                        core_ptext_0    <= rd_fifo_fwft_dout[31:0];
                        core_ptext_1    <= rd_fifo_fwft_dout[63:32];
                        core_data_valid <= 1'b1;
                        core_data_last  <= (core_blocks_fed + 1 >= total_blocks);
                        core_blocks_fed <= core_blocks_fed + 1;
                        rd_fifo_pop     <= 1'b1;
                        feed_pulse      <= 1'b1;
                        pump_state      <= PUMP_START;
                    end
                end

                PUMP_START: begin
                    pump_state <= PUMP_WAIT_CORE;
                end

                PUMP_WAIT_CORE: begin
                    if (core_data_out_valid) begin
                        if (allow_chain_feed) begin
                            core_ptext_0    <= rd_fifo_fwft_dout[31:0];
                            core_ptext_1    <= rd_fifo_fwft_dout[63:32];
                            core_data_valid <= 1'b1;
                            core_data_last  <= (core_blocks_fed + 1 >= total_blocks);
                            core_blocks_fed <= core_blocks_fed + 1;
                            rd_fifo_pop     <= 1'b1;
                            feed_pulse      <= 1'b1;
                            chain_pulse     <= 1'b1;
                            pump_state      <= PUMP_START;
                        end else begin
                            core_data_valid <= 1'b0;
                            pump_state      <= PUMP_IDLE;
                        end
                    end
                end

                default: pump_state <= PUMP_IDLE;
            endcase
        end
    end
endmodule
