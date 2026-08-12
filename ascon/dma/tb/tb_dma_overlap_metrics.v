`timescale 1ns/1ps
`define SIMULATION

`include "ascon/dma/rtl/dma_read_engine.v"
`include "ascon/dma/rtl/dma_write_inval_range.v"
`include "ascon/dma/rtl/dma_write_drain_policy.v"
`include "ascon/dma/rtl/dma_write_bank_credit_planner.v"
`include "ascon/dma/rtl/dma_write_engine.v"

module tb_dma_overlap_metrics;
    localparam ADDR_WIDTH = 32;
    localparam AXI_DATA_WIDTH = 64;
    localparam AXI_ID_WIDTH = 4;
    localparam RD_FIFO_DEPTH = 8;
    localparam WR_FIFO_DEPTH = 32;
    localparam CLK_PERIOD = 10;
    localparam AR_Q_DEPTH = 4;
    localparam B_Q_DEPTH = 4;

    reg clk, rst_n;
    integer i;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_count, fail_count;

    task check;
        input [255:0] name;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  [PASS] %s -- %s", name, msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s -- %s (@%0t)", name, msg, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Read-engine DUT and model
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH-1:0] rd_src_addr;
    reg  [7:0]            rd_burst_len;
    reg                   rd_dma_start;
    reg                   rd_start;
    wire                  rd_busy;
    wire                  rd_done;
    wire                  rd_error;
    wire [ADDR_WIDTH-1:0] rd_err_addr;
    wire [AXI_DATA_WIDTH-1:0] rd_fifo_din;
    wire                  rd_fifo_push;
    reg                   rd_fifo_full;
    reg  [$clog2(RD_FIFO_DEPTH):0] rd_fifo_fill_count;
    wire [AXI_ID_WIDTH-1:0] rd_arid;
    wire [ADDR_WIDTH-1:0]   rd_araddr;
    wire [7:0]              rd_arlen;
    wire [2:0]              rd_arsize;
    wire [1:0]              rd_arburst;
    wire [3:0]              rd_arcache;
    wire [2:0]              rd_arprot;
    wire                    rd_arvalid;
    reg                     rd_arready;
    reg  [AXI_ID_WIDTH-1:0] rd_rid;
    reg  [AXI_DATA_WIDTH-1:0] rd_rdata;
    reg  [1:0]              rd_rresp;
    reg                     rd_rlast;
    reg                     rd_rvalid;
    wire                    rd_rready;

    dma_read_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .RD_FIFO_DEPTH (RD_FIFO_DEPTH),
        .MAX_OUTSTANDING_READS (2)
    ) u_rd_engine (
        .clk(clk),
        .rst_n(rst_n),
        .src_addr(rd_src_addr),
        .burst_len(rd_burst_len),
        .dma_start(rd_dma_start),
        .rd_start(rd_start),
        .rd_busy(rd_busy),
        .rd_done(rd_done),
        .rd_error(rd_error),
        .rd_err_addr(rd_err_addr),
        .coherent_read_en(1'b0),
        .snoop_req_valid(),
        .snoop_req_cmd(),
        .snoop_req_addr(),
        .snoop_req_ready(1'b0),
        .snoop_resp_valid(1'b0),
        .snoop_resp_hit(1'b0),
        .snoop_resp_data({128{1'b0}}),
        .fifo_din(rd_fifo_din),
        .fifo_push(rd_fifo_push),
        .fifo_full(rd_fifo_full),
        .fifo_fill_count(rd_fifo_fill_count),
        .M_AXI_ARID(rd_arid),
        .M_AXI_ARADDR(rd_araddr),
        .M_AXI_ARLEN(rd_arlen),
        .M_AXI_ARSIZE(rd_arsize),
        .M_AXI_ARBURST(rd_arburst),
        .M_AXI_ARCACHE(rd_arcache),
        .M_AXI_ARPROT(rd_arprot),
        .M_AXI_ARVALID(rd_arvalid),
        .M_AXI_ARREADY(rd_arready),
        .M_AXI_RID(rd_rid),
        .M_AXI_RDATA(rd_rdata),
        .M_AXI_RRESP(rd_rresp),
        .M_AXI_RLAST(rd_rlast),
        .M_AXI_RVALID(rd_rvalid),
        .M_AXI_RREADY(rd_rready)
    );

    reg [ADDR_WIDTH-1:0] rdq_addr [0:AR_Q_DEPTH-1];
    reg [7:0]            rdq_len  [0:AR_Q_DEPTH-1];
    reg [1:0]            rdq_count;
    reg [1:0]            rdq_head, rdq_tail;
    reg [ADDR_WIDTH-1:0] rd_stream_addr;
    reg [7:0]            rd_stream_rem;
    reg                  rd_stream_active;
    reg [3:0]            rd_resp_delay_cnt;
    integer              rd_accepted_cur;
    integer              rd_accepted_max;
    reg [3:0]            rd_ar_delay_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_arready       <= 1'b0;
            rd_rvalid        <= 1'b0;
            rd_rlast         <= 1'b0;
            rd_rresp         <= 2'b00;
            rd_rid           <= {AXI_ID_WIDTH{1'b0}};
            rd_rdata         <= {AXI_DATA_WIDTH{1'b0}};
            rdq_count        <= 0;
            rdq_head         <= 0;
            rdq_tail         <= 0;
            rd_stream_active <= 1'b0;
            rd_stream_addr   <= {ADDR_WIDTH{1'b0}};
            rd_stream_rem    <= 8'd0;
            rd_resp_delay_cnt <= 0;
            rd_accepted_cur  <= 0;
            rd_accepted_max  <= 0;
            rd_ar_delay_cnt  <= 0;
        end else begin
            rd_arready <= 1'b0;

            if (rd_arvalid && (rdq_count < AR_Q_DEPTH)) begin
                if (rd_ar_delay_cnt < 3) begin
                    rd_ar_delay_cnt <= rd_ar_delay_cnt + 1'b1;
                end else begin
                    rd_arready <= 1'b1;
                    rdq_addr[rdq_tail] <= rd_araddr;
                    rdq_len[rdq_tail]  <= rd_arlen;
                    rdq_tail           <= rdq_tail + 1'b1;
                    rdq_count          <= rdq_count + 1'b1;
                    rd_ar_delay_cnt    <= 0;
                    rd_accepted_cur    <= rd_accepted_cur + 1;
                    if (rd_accepted_cur + 1 > rd_accepted_max)
                        rd_accepted_max <= rd_accepted_cur + 1;
                end
            end else begin
                rd_ar_delay_cnt <= 0;
            end

            if (!rd_stream_active && (rdq_count != 0)) begin
                if (rd_resp_delay_cnt < 4) begin
                    rd_resp_delay_cnt <= rd_resp_delay_cnt + 1'b1;
                    rd_rvalid <= 1'b0;
                end else begin
                    rd_stream_active <= 1'b1;
                    rd_stream_addr   <= rdq_addr[rdq_head];
                    rd_stream_rem    <= rdq_len[rdq_head];
                    rdq_head         <= rdq_head + 1'b1;
                    rdq_count        <= rdq_count - 1'b1;
                    rd_rvalid        <= 1'b1;
                    rd_rlast         <= (rdq_len[rdq_head] == 0);
                    rd_rdata         <= {rdq_addr[rdq_head][31:0], rdq_addr[rdq_head][31:0]};
                    rd_resp_delay_cnt <= 0;
                end
            end else if (rd_stream_active) begin
                rd_rvalid <= 1'b1;
                rd_rlast  <= (rd_stream_rem == 0);
                rd_rdata  <= {rd_stream_addr[31:0], rd_stream_addr[31:0]};
                if (rd_rvalid && rd_rready) begin
                    if (rd_stream_rem == 0) begin
                        rd_stream_active <= 1'b0;
                        rd_rvalid        <= 1'b0;
                        rd_rlast         <= 1'b0;
                        rd_accepted_cur  <= rd_accepted_cur - 1;
                        rd_resp_delay_cnt <= 0;
                    end else begin
                        rd_stream_addr <= rd_stream_addr + 8;
                        rd_stream_rem  <= rd_stream_rem - 1'b1;
                    end
                end
            end else begin
                rd_rvalid <= 1'b0;
                rd_rlast  <= 1'b0;
            end

            if (rd_fifo_push && (rd_fifo_fill_count < RD_FIFO_DEPTH-1))
                rd_fifo_fill_count <= rd_fifo_fill_count + 1'b1;
            else if (rd_fifo_fill_count != 0)
                rd_fifo_fill_count <= rd_fifo_fill_count - 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Write-engine DUT and model
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH-1:0] wr_dst_addr;
    reg                   wr_dma_start;
    reg  [28:0]           wr_total_beats;
    wire                  wr_busy;
    wire                  wr_done;
    wire                  wr_error;
    wire [ADDR_WIDTH-1:0] wr_err_addr;
    reg  [31:0]           wr_fifo_mem [0:31];
    reg  [5:0]            wr_fifo_rd_ptr;
    reg  [5:0]            wr_fifo_count;
    wire [5:0]            wr_fifo_fill_count_w = 6'd0;
    wire [31:0]           wr_fifo_dout = wr_fifo_mem[wr_fifo_rd_ptr];
    wire [31:0]           wr_fifo_fwft_dout = wr_fifo_mem[wr_fifo_rd_ptr];
    wire                  wr_fifo_fwft_valid = (wr_fifo_count != 0);
    wire                  wr_fifo_pop;
    wire [AXI_ID_WIDTH-1:0] wr_awid;
    wire [ADDR_WIDTH-1:0]   wr_awaddr;
    wire [7:0]              wr_awlen;
    wire [2:0]              wr_awsize;
    wire [1:0]              wr_awburst;
    wire [3:0]              wr_awcache;
    wire [2:0]              wr_awprot;
    wire                    wr_awvalid;
    reg                     wr_awready;
    wire [AXI_DATA_WIDTH-1:0] wr_wdata;
    wire [AXI_DATA_WIDTH/8-1:0] wr_wstrb;
    wire                    wr_wlast;
    wire                    wr_wvalid;
    reg                     wr_wready;
    reg  [AXI_ID_WIDTH-1:0] wr_bid;
    reg  [1:0]              wr_bresp;
    reg                     wr_bvalid;
    wire                    wr_bready;
    wire                    bench_chain_pulse;

    dma_write_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .WR_FIFO_DEPTH (WR_FIFO_DEPTH),
        .MAX_BURST_LEN (8'd1),
        .MAX_OUTSTANDING_BRESP (2)
    ) u_wr_engine (
        .clk(clk),
        .rst_n(rst_n),
        .dst_addr(wr_dst_addr),
        .dma_start(wr_dma_start),
        .total_wr_beats(wr_total_beats),
        .wr_busy(wr_busy),
        .wr_done(wr_done),
        .wr_error(wr_error),
        .wr_err_addr(wr_err_addr),
        .coherent_invalidate_en(1'b0),
        .snoop_req_valid(),
        .snoop_req_cmd(),
        .snoop_req_addr(),
        .snoop_req_ready(1'b0),
        .snoop_resp_valid(1'b0),
        .snoop_resp_hit(1'b0),
        .snoop_resp_data({128{1'b0}}),
        .fifo_dout(wr_fifo_dout),
        .fifo_pop(wr_fifo_pop),
        .fifo_count(wr_fifo_count),
        .fifo_drain_count(wr_fifo_count),
        .fifo_fill_count(wr_fifo_fill_count_w),
        .fifo_active_bank(1'b0),
        .fifo_fill_bank_sel(1'b1),
        .fifo_drain_bank_ready(1'b1),
        .fifo_fill_bank_ready(1'b1),
        .bench_chain_pulse(bench_chain_pulse),
        .fifo_fwft_dout(wr_fifo_fwft_dout),
        .fifo_fwft_valid(wr_fifo_fwft_valid),
        .M_AXI_AWID(wr_awid),
        .M_AXI_AWADDR(wr_awaddr),
        .M_AXI_AWLEN(wr_awlen),
        .M_AXI_AWSIZE(wr_awsize),
        .M_AXI_AWBURST(wr_awburst),
        .M_AXI_AWCACHE(wr_awcache),
        .M_AXI_AWPROT(wr_awprot),
        .M_AXI_AWVALID(wr_awvalid),
        .M_AXI_AWREADY(wr_awready),
        .M_AXI_WDATA(wr_wdata),
        .M_AXI_WSTRB(wr_wstrb),
        .M_AXI_WLAST(wr_wlast),
        .M_AXI_WVALID(wr_wvalid),
        .M_AXI_WREADY(wr_wready),
        .M_AXI_BID(wr_bid),
        .M_AXI_BRESP(wr_bresp),
        .M_AXI_BVALID(wr_bvalid),
        .M_AXI_BREADY(wr_bready)
    );

    reg [AXI_ID_WIDTH-1:0] bq_id [0:B_Q_DEPTH-1];
    reg [1:0] bq_count;
    reg [1:0] bq_head, bq_tail;
    reg [3:0] b_delay_cnt;
    integer   write_pending_peak;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_awready <= 1'b0;
            wr_wready  <= 1'b0;
            wr_bvalid  <= 1'b0;
            wr_bresp   <= 2'b00;
            wr_bid     <= {AXI_ID_WIDTH{1'b0}};
            wr_fifo_rd_ptr <= 0;
            wr_fifo_count  <= 0;
            bq_count    <= 0;
            bq_head     <= 0;
            bq_tail     <= 0;
            b_delay_cnt <= 0;
            write_pending_peak <= 0;
        end else begin
            wr_awready <= wr_awvalid;
            wr_wready  <= wr_wvalid;

            if (wr_fifo_pop && (wr_fifo_count != 0)) begin
                wr_fifo_rd_ptr <= wr_fifo_rd_ptr + 1'b1;
                wr_fifo_count  <= wr_fifo_count - 1'b1;
            end

            if (wr_awvalid && wr_awready) begin
                if (u_wr_engine.pending_bresp > write_pending_peak)
                    write_pending_peak <= u_wr_engine.pending_bresp;
            end

            if (wr_wvalid && wr_wready && wr_wlast) begin
                bq_id[bq_tail] <= wr_awid;
                bq_tail        <= bq_tail + 1'b1;
                bq_count       <= bq_count + 1'b1;
                if (u_wr_engine.pending_bresp > write_pending_peak)
                    write_pending_peak <= u_wr_engine.pending_bresp;
            end

            if (!wr_bvalid && (bq_count != 0)) begin
                if (b_delay_cnt < 40) begin
                    b_delay_cnt <= b_delay_cnt + 1'b1;
                end else begin
                    wr_bvalid <= 1'b1;
                    wr_bresp  <= 2'b00;
                    wr_bid    <= bq_id[bq_head];
                    bq_head   <= bq_head + 1'b1;
                    bq_count  <= bq_count - 1'b1;
                    b_delay_cnt <= 0;
                end
            end else if (wr_bvalid && wr_bready) begin
                wr_bvalid <= 1'b0;
                b_delay_cnt <= 0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        rst_n = 1'b0;
        rd_src_addr = 0;
        rd_burst_len = 0;
        rd_dma_start = 0;
        rd_start = 0;
        rd_fifo_full = 1'b0;
        rd_fifo_fill_count = 0;
        wr_dst_addr = 0;
        wr_dma_start = 0;
        wr_total_beats = 0;
        for (i = 0; i < 32; i = i + 1)
            wr_fifo_mem[i] = 32'h1000_0000 + i;

        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);

        $display("\n[TC-RD] Read-engine outstanding metric");
        rd_src_addr   = 32'h3000_0100;
        rd_burst_len  = 8'd3;
        rd_dma_start  = 1'b1;
        rd_start      = 1'b1;
        @(posedge clk);
        rd_dma_start  = 1'b0;
        rd_start      = 1'b0;
        wait_cycles(80);
        check("TC-RD", rd_error === 1'b0, "read transaction stayed error-free");
        check("TC-RD", rd_accepted_max > 1, "accepted more than one AR outstanding");
        check("TC-RD", u_rd_engine.rd_outstanding_reads > 0 || rd_accepted_max > 1,
              "engine exposed outstanding-read behavior");
        $display("[TC-RD] peak accepted outstanding AR = %0d", rd_accepted_max);

        $display("\n[TC-WR] Write-engine pending BRESP metric");
        wr_fifo_rd_ptr = 0;
        wr_fifo_count  = 24;
        wr_dst_addr    = 32'h3000_0200;
        wr_total_beats = 29'd12;
        wr_dma_start   = 1'b1;
        @(posedge clk);
        wr_dma_start   = 1'b0;
        wait_cycles(160);
        check("TC-WR", bench_chain_pulse !== 1'bx, "write engine produced defined chain signal");
        check("TC-WR", write_pending_peak > 1 || u_wr_engine.pending_bresp > 1,
              "pending BRESP exceeded one");
        $display("[TC-WR] peak pending_bresp = %0d", write_pending_peak);

        $display("\n================================================");
        $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d TEST(S) FAILED ***", fail_count);
        $display("================================================");
        #50 $finish;
    end

    initial begin
        #200000;
        $display("[WATCHDOG] Timeout.");
        $finish;
    end
endmodule
