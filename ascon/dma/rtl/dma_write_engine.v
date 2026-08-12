`timescale 1ns/1ps

// ============================================================================
// Module  : dma_write_engine
//
// Notes:
//   - Write bursts are used in both legacy and coherent modes.
//   - Coherent mode pre-invalidates each affected 16B DCache line before
//     issuing the AXI write burst.
// ============================================================================

module dma_write_engine #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH   = 64,
    parameter AXI_ID_WIDTH     = 4,
    parameter SNOOP_DATA_WIDTH = 128,
    parameter MAX_BURST_LEN    = 8'd15,
    parameter WR_FIFO_DEPTH  = 32,
    parameter MAX_OUTSTANDING_BRESP = 2
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // Control
    input  wire [ADDR_WIDTH-1:0]       dst_addr,
    input  wire                        dma_start,
    input  wire [28:0]                 total_wr_beats,
    output reg                         wr_busy,
    output reg                         wr_done,
    output reg                         wr_error,
    output reg  [ADDR_WIDTH-1:0]       wr_err_addr,

    // Optional coherent sideband invalidate
    input  wire                        coherent_invalidate_en,
    output reg                         snoop_req_valid,
    output reg  [1:0]                  snoop_req_cmd,
    output reg  [ADDR_WIDTH-1:0]       snoop_req_addr,
    input  wire                        snoop_req_ready,
    input  wire                        snoop_resp_valid,
    input  wire                        snoop_resp_hit,
    input  wire [SNOOP_DATA_WIDTH-1:0]  snoop_resp_data,

    // WR FIFO paths
    input  wire [31:0]                 fifo_dout,
    output reg                         fifo_pop,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_count,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_drain_count,
    input  wire [$clog2(WR_FIFO_DEPTH):0] fifo_fill_count,
    input  wire                        fifo_active_bank,
    input  wire                        fifo_fill_bank_sel,
    input  wire                        fifo_drain_bank_ready,
    input  wire                        fifo_fill_bank_ready,
    output reg                         bench_chain_pulse,
    input  wire [31:0]                 fifo_fwft_dout,
    input  wire                        fifo_fwft_valid,

    // AXI4 Write Address Channel
    output reg  [AXI_ID_WIDTH-1:0]     M_AXI_AWID,
    output reg  [ADDR_WIDTH-1:0]       M_AXI_AWADDR,
    output wire [7:0]                  M_AXI_AWLEN,
    output wire [2:0]                  M_AXI_AWSIZE,
    output wire [1:0]                  M_AXI_AWBURST,
    output wire [3:0]                  M_AXI_AWCACHE,
    output wire [2:0]                  M_AXI_AWPROT,
    output reg                         M_AXI_AWVALID,
    input  wire                        M_AXI_AWREADY,

    // AXI4 Write Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]   M_AXI_WDATA,
    output wire [AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output reg                         M_AXI_WLAST,
    output reg                         M_AXI_WVALID,
    input  wire                        M_AXI_WREADY,

    // AXI4 Write Response Channel
    input  wire [AXI_ID_WIDTH-1:0]     M_AXI_BID,
    input  wire [1:0]                  M_AXI_BRESP,
    input  wire                        M_AXI_BVALID,
    output reg                         M_AXI_BREADY
);

    reg [7:0] awlen_reg;
    assign M_AXI_AWLEN   = awlen_reg;
    assign M_AXI_AWSIZE  = 3'b011;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_WSTRB   = {(AXI_DATA_WIDTH/8){1'b1}};

    localparam [3:0]
        WR_IDLE     = 4'd0,
        WR_SNP_REQ  = 4'd1,
        WR_SNP_WAIT = 4'd2,
        WR_ADDR     = 4'd3,
        WR_LOAD_H   = 4'd4,
        WR_WAIT_POP = 4'd5,
        WR_DATA_L   = 4'd6,
        WR_BEAT     = 4'd7,
        WR_RESP     = 4'd8;
    localparam [1:0] MAX_OUTSTANDING_BRESP_W = MAX_OUTSTANDING_BRESP[1:0];

    reg [3:0]            state;
    reg [31:0]           wdata_hi;
    reg [ADDR_WIDTH-1:0] active_burst_addr;
    reg [ADDR_WIDTH-1:0] cur_dst_addr;
    reg [28:0]           remaining_beats;
    reg [7:0]            beats_in_burst;
    reg [7:0]            burst_beats;
    reg [ADDR_WIDTH-1:0] inv_addr;
    reg [ADDR_WIDTH-1:0] inv_end_addr;
    reg [1:0]            pending_bresp;
    reg [ADDR_WIDTH-1:0] resp_addr_q0;
    reg [ADDR_WIDTH-1:0] resp_addr_q1;

    wire [ADDR_WIDTH-1:0] burst_bytes = {21'd0, burst_beats, 3'b000};
    wire [7:0] selected_burst_beats;
    wire [ADDR_WIDTH-1:0] selected_burst_bytes = {21'd0, selected_burst_beats, 3'b000};
    wire [ADDR_WIDTH-1:0] selected_first_line_addr;
    wire [ADDR_WIDTH-1:0] selected_last_line_addr;
    wire [7:0]            selected_line_count;
    wire [ADDR_WIDTH-1:0] chain_first_line_addr;
    wire [ADDR_WIDTH-1:0] chain_last_line_addr;
    wire [7:0]            chain_line_count;

    wire [31:0] _unused_fifo_dout = fifo_dout;
    wire [$clog2(WR_FIFO_DEPTH):0] _unused_fifo_count = fifo_count;
    wire [SNOOP_DATA_WIDTH-1:0] _unused_snoop_resp_data = snoop_resp_data;
    wire _unused_snoop_resp_hit = snoop_resp_hit;
    wire [AXI_ID_WIDTH-1:0] _unused_bid = M_AXI_BID;
    wire issue_write_drain;
    wire [1:0] write_burst_urgency;
    wire chain_issue_write_drain;
    wire [7:0] chain_selected_burst_beats;
    wire [1:0] chain_write_burst_urgency;

    dma_write_inval_range #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_write_inval_range (
        .burst_addr      (cur_dst_addr),
        .burst_beats     (selected_burst_beats),
        .first_line_addr (selected_first_line_addr),
        .last_line_addr  (selected_last_line_addr),
        .line_count      (selected_line_count)
    );

    dma_write_inval_range #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_write_inval_range_chain (
        .burst_addr      (cur_dst_addr),
        .burst_beats     (chain_selected_burst_beats),
        .first_line_addr (chain_first_line_addr),
        .last_line_addr  (chain_last_line_addr),
        .line_count      (chain_line_count)
    );

    dma_write_drain_policy #(
        .WR_FIFO_DEPTH (WR_FIFO_DEPTH)
    ) u_write_drain_policy (
        .wr_busy              (wr_busy),
        .fifo_drain_count     (fifo_drain_count),
        .fifo_fill_count      (fifo_fill_count),
        .active_bank          (fifo_active_bank),
        .fill_bank_sel        (fifo_fill_bank_sel),
        .drain_bank_ready     (fifo_drain_bank_ready),
        .fill_bank_ready      (fifo_fill_bank_ready),
        .remaining_beats      (remaining_beats),
        .issue_drain          (issue_write_drain)
    );

    dma_write_bank_credit_planner #(
        .WR_FIFO_DEPTH (WR_FIFO_DEPTH),
        .MAX_BURST_LEN (MAX_BURST_LEN)
    ) u_write_bank_credit_planner (
        .remaining_beats   (remaining_beats),
        .fifo_count        (fifo_count),
        .fifo_drain_count  (fifo_drain_count),
        .fifo_fill_count   (fifo_fill_count),
        .fill_bank_ready   (fifo_fill_bank_ready),
        .drain_bank_ready  (fifo_drain_bank_ready),
        .target_burst_beats(selected_burst_beats),
        .urgency_class     (write_burst_urgency)
    );

    dma_write_drain_policy #(
        .WR_FIFO_DEPTH (WR_FIFO_DEPTH)
    ) u_write_drain_policy_chain (
        .wr_busy              (1'b0),
        .fifo_drain_count     (fifo_drain_count),
        .fifo_fill_count      (fifo_fill_count),
        .active_bank          (fifo_active_bank),
        .fill_bank_sel        (fifo_fill_bank_sel),
        .drain_bank_ready     (fifo_drain_bank_ready),
        .fill_bank_ready      (fifo_fill_bank_ready),
        .remaining_beats      (remaining_beats),
        .issue_drain          (chain_issue_write_drain)
    );

    dma_write_bank_credit_planner #(
        .WR_FIFO_DEPTH (WR_FIFO_DEPTH),
        .MAX_BURST_LEN (MAX_BURST_LEN)
    ) u_write_bank_credit_planner_chain (
        .remaining_beats   (remaining_beats),
        .fifo_count        (fifo_count),
        .fifo_drain_count  (fifo_drain_count),
        .fifo_fill_count   (fifo_fill_count),
        .fill_bank_ready   (fifo_fill_bank_ready),
        .drain_bank_ready  (fifo_drain_bank_ready),
        .target_burst_beats(chain_selected_burst_beats),
        .urgency_class     (chain_write_burst_urgency)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= WR_IDLE;
            wr_busy         <= 1'b0;
            wr_done         <= 1'b0;
            wr_error        <= 1'b0;
            wr_err_addr     <= {ADDR_WIDTH{1'b0}};
            snoop_req_valid <= 1'b0;
            snoop_req_cmd   <= 2'b00;
            snoop_req_addr  <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWVALID   <= 1'b0;
            M_AXI_AWID      <= {AXI_ID_WIDTH{1'b0}};
            M_AXI_AWADDR    <= {ADDR_WIDTH{1'b0}};
            awlen_reg       <= 8'd0;
            M_AXI_WVALID    <= 1'b0;
            M_AXI_WDATA     <= {AXI_DATA_WIDTH{1'b0}};
            M_AXI_WLAST     <= 1'b0;
            M_AXI_BREADY    <= 1'b0;
            fifo_pop        <= 1'b0;
            bench_chain_pulse <= 1'b0;
            wdata_hi        <= 32'h0;
            active_burst_addr <= {ADDR_WIDTH{1'b0}};
            cur_dst_addr    <= {ADDR_WIDTH{1'b0}};
            remaining_beats <= 29'd0;
            beats_in_burst  <= 8'd0;
            burst_beats     <= 8'd0;
            inv_addr        <= {ADDR_WIDTH{1'b0}};
            inv_end_addr    <= {ADDR_WIDTH{1'b0}};
            pending_bresp   <= 2'd0;
            resp_addr_q0    <= {ADDR_WIDTH{1'b0}};
            resp_addr_q1    <= {ADDR_WIDTH{1'b0}};
        end else begin
            wr_done         <= 1'b0;
            fifo_pop        <= 1'b0;
            snoop_req_valid <= 1'b0;
            bench_chain_pulse <= 1'b0;
            M_AXI_BREADY    <= (pending_bresp != 2'd0);
            wr_busy         <= (state != WR_IDLE) || (pending_bresp != 2'd0);

            if (M_AXI_BVALID && M_AXI_BREADY) begin
                if (M_AXI_BRESP != 2'b00) begin
                    wr_error    <= 1'b1;
                    wr_err_addr <= resp_addr_q0;
                end
                if (pending_bresp > 2'd0)
                    pending_bresp <= pending_bresp - 1'b1;
                resp_addr_q0 <= resp_addr_q1;
                resp_addr_q1 <= {ADDR_WIDTH{1'b0}};
            end

            if (dma_start) begin
                state           <= WR_IDLE;
                cur_dst_addr    <= dst_addr;
                remaining_beats <= total_wr_beats;
                inv_addr        <= {ADDR_WIDTH{1'b0}};
                inv_end_addr    <= {ADDR_WIDTH{1'b0}};
                wr_error        <= 1'b0;
                wr_busy         <= 1'b0;
                M_AXI_AWVALID   <= 1'b0;
                M_AXI_WVALID    <= 1'b0;
                M_AXI_BREADY    <= 1'b0;
                M_AXI_WLAST     <= 1'b0;
                pending_bresp   <= 2'd0;
                resp_addr_q0    <= {ADDR_WIDTH{1'b0}};
                resp_addr_q1    <= {ADDR_WIDTH{1'b0}};
            end else begin
                case (state)
                    WR_IDLE: begin
                        M_AXI_AWVALID <= 1'b0;
                        M_AXI_WVALID  <= 1'b0;
                        M_AXI_BREADY  <= 1'b0;
                        M_AXI_WLAST   <= 1'b0;

                        if (issue_write_drain &&
                            (write_burst_urgency != 2'd0) &&
                            (selected_burst_beats != 8'd0) &&
                            (pending_bresp < MAX_OUTSTANDING_BRESP_W)) begin
                            awlen_reg      <= selected_burst_beats - 8'd1;
                            burst_beats    <= selected_burst_beats;
                            beats_in_burst <= selected_burst_beats;
                            active_burst_addr <= cur_dst_addr;
                            inv_addr       <= selected_first_line_addr;
                            inv_end_addr   <= selected_last_line_addr;
                            cur_dst_addr   <= cur_dst_addr + selected_burst_bytes;
                            remaining_beats <= remaining_beats - {21'd0, selected_burst_beats};
                            if (pending_bresp == 2'd0)
                                resp_addr_q0 <= cur_dst_addr;
                            else
                                resp_addr_q1 <= cur_dst_addr;
                            pending_bresp <= pending_bresp + 1'b1;

                            wr_busy      <= 1'b1;
                            M_AXI_AWID   <= {AXI_ID_WIDTH{1'b0}};
                            M_AXI_AWADDR <= cur_dst_addr;
                            if (coherent_invalidate_en) begin
                                state <= WR_SNP_REQ;
                            end else begin
                                M_AXI_AWVALID <= 1'b1;
                                state         <= WR_ADDR;
                            end
                        end else begin
                            wr_busy <= 1'b0;
                        end
                    end

                    WR_SNP_REQ: begin
                        wr_busy         <= 1'b1;
                        snoop_req_valid <= 1'b1;
                        snoop_req_cmd   <= 2'b10;
                        snoop_req_addr  <= inv_addr;
                        if (snoop_req_ready)
                            state <= WR_SNP_WAIT;
                    end

                    WR_SNP_WAIT: begin
                        wr_busy <= 1'b1;
                        if (snoop_resp_valid) begin
                            if (inv_addr >= inv_end_addr) begin
                                M_AXI_AWVALID <= 1'b1;
                                state         <= WR_ADDR;
                            end else begin
                                inv_addr <= inv_addr + {{(ADDR_WIDTH-5){1'b0}}, 5'd16};
                                state    <= WR_SNP_REQ;
                            end
                        end
                    end

                    WR_ADDR: begin
                        wr_busy <= 1'b1;
                        if (M_AXI_AWREADY && M_AXI_AWVALID) begin
                            M_AXI_AWVALID <= 1'b0;
                            if (fifo_fwft_valid) begin
                                wdata_hi <= fifo_fwft_dout;
                                fifo_pop <= 1'b1;
                                state    <= WR_WAIT_POP;
                            end else begin
                                state <= WR_LOAD_H;
                            end
                        end
                    end

                    WR_LOAD_H: begin
                        wr_busy <= 1'b1;
                        if (fifo_fwft_valid) begin
                            wdata_hi <= fifo_fwft_dout;
                            fifo_pop <= 1'b1;
                            state    <= WR_WAIT_POP;
                        end
                    end

                    WR_WAIT_POP: begin
                        wr_busy <= 1'b1;
                        state   <= WR_DATA_L;
                    end

                    WR_DATA_L: begin
                        wr_busy <= 1'b1;
                        if (fifo_fwft_valid) begin
                            M_AXI_WDATA  <= {fifo_fwft_dout, wdata_hi};
                            M_AXI_WVALID <= 1'b1;
                            M_AXI_WLAST  <= (beats_in_burst == 8'd1);
                            fifo_pop     <= 1'b1;
                            state        <= WR_BEAT;
                        end
                    end

                    WR_BEAT: begin
                        wr_busy <= 1'b1;
                        if (M_AXI_WVALID && M_AXI_WREADY) begin
                            wr_done      <= 1'b1;
                            M_AXI_WVALID <= 1'b0;
                            M_AXI_WLAST  <= 1'b0;

                            if (beats_in_burst > 8'd1) begin
                                beats_in_burst <= beats_in_burst - 8'd1;
                                state          <= WR_LOAD_H;
                            end else begin
                                beats_in_burst <= 8'd0;
                                if (chain_issue_write_drain &&
                                    (chain_write_burst_urgency >= 2'd2) &&
                                    (chain_selected_burst_beats != 8'd0) &&
                                    (pending_bresp < MAX_OUTSTANDING_BRESP_W)) begin
                                    bench_chain_pulse <= 1'b1;
                                    awlen_reg      <= chain_selected_burst_beats - 8'd1;
                                    burst_beats    <= chain_selected_burst_beats;
                                    beats_in_burst <= chain_selected_burst_beats;
                                    active_burst_addr <= cur_dst_addr;
                                    inv_addr       <= chain_first_line_addr;
                                    inv_end_addr   <= chain_last_line_addr;
                                    if (pending_bresp == 2'd0)
                                        resp_addr_q0 <= cur_dst_addr;
                                    else
                                        resp_addr_q1 <= cur_dst_addr;
                                    pending_bresp   <= pending_bresp + 1'b1;
                                    cur_dst_addr    <= cur_dst_addr + {21'd0, chain_selected_burst_beats, 3'b000};
                                    remaining_beats <= remaining_beats - {21'd0, chain_selected_burst_beats};
                                    M_AXI_AWID      <= {AXI_ID_WIDTH{1'b0}};
                                    M_AXI_AWADDR    <= cur_dst_addr;
                                    if (coherent_invalidate_en) begin
                                        state <= WR_SNP_REQ;
                                    end else begin
                                        M_AXI_AWVALID <= 1'b1;
                                        state         <= WR_ADDR;
                                    end
                                end else begin
                                    state <= WR_RESP;
                                end
                            end
                        end
                    end

                    WR_RESP: begin
                        wr_busy <= 1'b1;
                        if ((pending_bresp == 2'd0) && (remaining_beats == 29'd0))
                            state <= WR_IDLE;
                    end

                    default: begin
                        state <= WR_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
