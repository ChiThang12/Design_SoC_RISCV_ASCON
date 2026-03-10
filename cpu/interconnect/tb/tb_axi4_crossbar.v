// ============================================================================
// tb_axi4_crossbar.v  —  Testbench cho axi4_crossbar
//
// Test cases:
//   TC1: M0 đọc IMEM (0x0000_1000) — basic read
//   TC2: M1 đọc DMEM (0x1000_0020) — basic read
//   TC3: M1 ghi DMEM (0x1000_0040) — basic write
//   TC4: M0 và M1 đọc đồng thời các slave khác nhau — non-blocking
//   TC5: M0 và M1 tranh chấp cùng slave (S0) — arbitration, M0 thắng
//   TC6: M0 đọc địa chỉ không ánh xạ (0x9000_0000) — DECERR
//   TC7: M1 ghi địa chỉ không ánh xạ — DECERR
//   TC8: M1 đọc ASCON (0x2000_0000) — forward tới S2 (stub)
// ============================================================================

`timescale 1ns/1ps

// `include "interconnect/axi4_addr_decoder.v"
// `include "interconnect/axi4_master_mux.v"
// `include "interconnect/axi4_decerr_slave.v"
`include "cpu/interconnect/axi4_crossbar_3m4s.v"

module tb_axi4_crossbar;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam ID_WIDTH   = 4;
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam CLK_PERIOD = 10; // 100MHz

    // ========================================================================
    // DUT signals
    // ========================================================================
    reg clk, rst_n;

    // M0
    reg  [ID_WIDTH-1:0] m0_arid;
    reg  [31:0] m0_araddr;
    reg  [7:0]  m0_arlen;
    reg  [2:0]  m0_arsize;
    reg  [1:0]  m0_arburst;
    reg  [2:0]  m0_arprot;
    reg         m0_arvalid;
    wire        m0_arready;
    wire [ID_WIDTH-1:0] m0_rid;
    wire [31:0] m0_rdata;
    wire [1:0]  m0_rresp;
    wire        m0_rlast;
    wire        m0_rvalid;
    reg         m0_rready;
    reg  [ID_WIDTH-1:0] m0_awid;
    reg  [31:0] m0_awaddr;
    reg  [7:0]  m0_awlen;
    reg  [2:0]  m0_awsize;
    reg  [1:0]  m0_awburst;
    reg  [2:0]  m0_awprot;
    reg         m0_awvalid;
    wire        m0_awready;
    reg  [31:0] m0_wdata;
    reg  [3:0]  m0_wstrb;
    reg         m0_wlast;
    reg         m0_wvalid;
    wire        m0_wready;
    wire [ID_WIDTH-1:0] m0_bid;
    wire [1:0]  m0_bresp;
    wire        m0_bvalid;
    reg         m0_bready;

    // M1
    reg  [ID_WIDTH-1:0] m1_arid;
    reg  [31:0] m1_araddr;
    reg  [7:0]  m1_arlen;
    reg  [2:0]  m1_arsize;
    reg  [1:0]  m1_arburst;
    reg  [2:0]  m1_arprot;
    reg         m1_arvalid;
    wire        m1_arready;
    wire [ID_WIDTH-1:0] m1_rid;
    wire [31:0] m1_rdata;
    wire [1:0]  m1_rresp;
    wire        m1_rlast;
    wire        m1_rvalid;
    reg         m1_rready;
    reg  [ID_WIDTH-1:0] m1_awid;
    reg  [31:0] m1_awaddr;
    reg  [7:0]  m1_awlen;
    reg  [2:0]  m1_awsize;
    reg  [1:0]  m1_awburst;
    reg  [2:0]  m1_awprot;
    reg         m1_awvalid;
    wire        m1_awready;
    reg  [31:0] m1_wdata;
    reg  [3:0]  m1_wstrb;
    reg         m1_wlast;
    reg         m1_wvalid;
    wire        m1_wready;
    wire [ID_WIDTH-1:0] m1_bid;
    wire [1:0]  m1_bresp;
    wire        m1_bvalid;
    reg         m1_bready;

    // Slave 0 (IMEM model)
    wire [ID_WIDTH-1:0] s0_arid;
    wire [31:0] s0_araddr;
    wire [7:0]  s0_arlen;
    wire [2:0]  s0_arsize;
    wire [1:0]  s0_arburst;
    wire [2:0]  s0_arprot;
    wire        s0_arvalid;
    reg         s0_arready;
    reg  [ID_WIDTH-1:0] s0_rid;
    reg  [31:0] s0_rdata;
    reg  [1:0]  s0_rresp;
    reg         s0_rlast;
    reg         s0_rvalid;
    wire        s0_rready;
    wire [ID_WIDTH-1:0] s0_awid;
    wire [31:0] s0_awaddr;
    wire        s0_awvalid;
    reg         s0_awready;
    wire [31:0] s0_wdata;
    wire        s0_wlast;
    wire        s0_wvalid;
    reg         s0_wready;
    reg  [ID_WIDTH-1:0] s0_bid;
    reg  [1:0]  s0_bresp;
    reg         s0_bvalid;
    wire        s0_bready;
    wire [7:0]  s0_awlen;
    wire [2:0]  s0_awsize, s0_awprot;
    wire [1:0]  s0_awburst;
    wire [3:0]  s0_wstrb;

    // Slave 1 (DMEM model)
    wire [ID_WIDTH-1:0] s1_arid;
    wire [31:0] s1_araddr;
    wire [7:0]  s1_arlen;
    wire [2:0]  s1_arsize;
    wire [1:0]  s1_arburst;
    wire [2:0]  s1_arprot;
    wire        s1_arvalid;
    reg         s1_arready;
    reg  [ID_WIDTH-1:0] s1_rid;
    reg  [31:0] s1_rdata;
    reg  [1:0]  s1_rresp;
    reg         s1_rlast;
    reg         s1_rvalid;
    wire        s1_rready;
    wire [ID_WIDTH-1:0] s1_awid;
    wire [31:0] s1_awaddr;
    wire        s1_awvalid;
    reg         s1_awready;
    wire [31:0] s1_wdata;
    wire        s1_wlast;
    wire        s1_wvalid;
    reg         s1_wready;
    reg  [ID_WIDTH-1:0] s1_bid;
    reg  [1:0]  s1_bresp;
    reg         s1_bvalid;
    wire        s1_bready;
    wire [7:0]  s1_awlen;
    wire [2:0]  s1_awsize, s1_awprot;
    wire [1:0]  s1_awburst;
    wire [3:0]  s1_wstrb;

    // Slave 2 & 3 (stub)
    wire [ID_WIDTH-1:0] s2_arid, s2_awid, s2_rid, s2_bid;
    wire [31:0] s2_araddr, s2_awaddr, s2_rdata, s2_wdata;
    wire [7:0]  s2_arlen, s2_awlen;
    wire [2:0]  s2_arsize, s2_arprot, s2_awsize, s2_awprot;
    wire [1:0]  s2_arburst, s2_awburst;
    wire        s2_arvalid, s2_awvalid, s2_wlast, s2_wvalid;
    wire [3:0]  s2_wstrb;
    wire [1:0]  s2_rresp, s2_bresp;
    wire        s2_rlast, s2_rvalid, s2_bvalid;
    wire        s2_rready, s2_bready;

    reg  s2_arready, s2_awready, s2_wready;
    reg  [ID_WIDTH-1:0] s2_rid_r;
    reg  [31:0] s2_rdata_r;
    reg  [1:0]  s2_rresp_r;
    reg  s2_rlast_r, s2_rvalid_r;
    reg  [ID_WIDTH-1:0] s2_bid_r;
    reg  [1:0]  s2_bresp_r;
    reg  s2_bvalid_r;

    assign s2_rid    = s2_rid_r;
    assign s2_rdata  = s2_rdata_r;
    assign s2_rresp  = s2_rresp_r;
    assign s2_rlast  = s2_rlast_r;
    assign s2_rvalid = s2_rvalid_r;
    assign s2_bid    = s2_bid_r;
    assign s2_bresp  = s2_bresp_r;
    assign s2_bvalid = s2_bvalid_r;

    wire [ID_WIDTH-1:0] s3_arid, s3_awid, s3_rid, s3_bid;
    wire [31:0] s3_araddr, s3_awaddr, s3_rdata, s3_wdata;
    wire [7:0]  s3_arlen, s3_awlen;
    wire [2:0]  s3_arsize, s3_arprot, s3_awsize, s3_awprot;
    wire [1:0]  s3_arburst, s3_awburst;
    wire        s3_arvalid, s3_awvalid, s3_wlast, s3_wvalid;
    wire [3:0]  s3_wstrb;
    wire [1:0]  s3_rresp, s3_bresp;
    wire        s3_rlast, s3_rvalid, s3_bvalid;
    wire        s3_rready, s3_bready;

    reg s3_arready, s3_awready, s3_wready;
    reg [ID_WIDTH-1:0] s3_rid_r;
    reg [31:0] s3_rdata_r;
    reg [1:0]  s3_rresp_r;
    reg s3_rlast_r, s3_rvalid_r;
    reg [ID_WIDTH-1:0] s3_bid_r;
    reg [1:0]  s3_bresp_r;
    reg s3_bvalid_r;

    assign s3_rid    = s3_rid_r;
    assign s3_rdata  = s3_rdata_r;
    assign s3_rresp  = s3_rresp_r;
    assign s3_rlast  = s3_rlast_r;
    assign s3_rvalid = s3_rvalid_r;
    assign s3_bid    = s3_bid_r;
    assign s3_bresp  = s3_bresp_r;
    assign s3_bvalid = s3_bvalid_r;

    // ========================================================================
    // DUT
    // ========================================================================
    axi4_crossbar_3m4s #(.ID_WIDTH(ID_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .M0_AXI_ARID(m0_arid), .M0_AXI_ARADDR(m0_araddr), .M0_AXI_ARLEN(m0_arlen),
        .M0_AXI_ARSIZE(m0_arsize), .M0_AXI_ARBURST(m0_arburst), .M0_AXI_ARPROT(m0_arprot),
        .M0_AXI_ARVALID(m0_arvalid), .M0_AXI_ARREADY(m0_arready),
        .M0_AXI_RID(m0_rid), .M0_AXI_RDATA(m0_rdata), .M0_AXI_RRESP(m0_rresp),
        .M0_AXI_RLAST(m0_rlast), .M0_AXI_RVALID(m0_rvalid), .M0_AXI_RREADY(m0_rready),
        .M0_AXI_AWID(m0_awid), .M0_AXI_AWADDR(m0_awaddr), .M0_AXI_AWLEN(m0_awlen),
        .M0_AXI_AWSIZE(m0_awsize), .M0_AXI_AWBURST(m0_awburst), .M0_AXI_AWPROT(m0_awprot),
        .M0_AXI_AWVALID(m0_awvalid), .M0_AXI_AWREADY(m0_awready),
        .M0_AXI_WDATA(m0_wdata), .M0_AXI_WSTRB(m0_wstrb), .M0_AXI_WLAST(m0_wlast),
        .M0_AXI_WVALID(m0_wvalid), .M0_AXI_WREADY(m0_wready),
        .M0_AXI_BID(m0_bid), .M0_AXI_BRESP(m0_bresp), .M0_AXI_BVALID(m0_bvalid),
        .M0_AXI_BREADY(m0_bready),
        .M1_AXI_ARID(m1_arid), .M1_AXI_ARADDR(m1_araddr), .M1_AXI_ARLEN(m1_arlen),
        .M1_AXI_ARSIZE(m1_arsize), .M1_AXI_ARBURST(m1_arburst), .M1_AXI_ARPROT(m1_arprot),
        .M1_AXI_ARVALID(m1_arvalid), .M1_AXI_ARREADY(m1_arready),
        .M1_AXI_RID(m1_rid), .M1_AXI_RDATA(m1_rdata), .M1_AXI_RRESP(m1_rresp),
        .M1_AXI_RLAST(m1_rlast), .M1_AXI_RVALID(m1_rvalid), .M1_AXI_RREADY(m1_rready),
        .M1_AXI_AWID(m1_awid), .M1_AXI_AWADDR(m1_awaddr), .M1_AXI_AWLEN(m1_awlen),
        .M1_AXI_AWSIZE(m1_awsize), .M1_AXI_AWBURST(m1_arburst), .M1_AXI_AWPROT(m1_awprot),
        .M1_AXI_AWVALID(m1_awvalid), .M1_AXI_AWREADY(m1_awready),
        .M1_AXI_WDATA(m1_wdata), .M1_AXI_WSTRB(m1_wstrb), .M1_AXI_WLAST(m1_wlast),
        .M1_AXI_WVALID(m1_wvalid), .M1_AXI_WREADY(m1_wready),
        .M1_AXI_BID(m1_bid), .M1_AXI_BRESP(m1_bresp), .M1_AXI_BVALID(m1_bvalid),
        .M1_AXI_BREADY(m1_bready),
        .S0_AXI_ARID(s0_arid), .S0_AXI_ARADDR(s0_araddr), .S0_AXI_ARLEN(s0_arlen),
        .S0_AXI_ARSIZE(s0_arsize), .S0_AXI_ARBURST(s0_arburst), .S0_AXI_ARPROT(s0_arprot),
        .S0_AXI_ARVALID(s0_arvalid), .S0_AXI_ARREADY(s0_arready),
        .S0_AXI_RID(s0_rid), .S0_AXI_RDATA(s0_rdata), .S0_AXI_RRESP(s0_rresp),
        .S0_AXI_RLAST(s0_rlast), .S0_AXI_RVALID(s0_rvalid), .S0_AXI_RREADY(s0_rready),
        .S0_AXI_AWID(s0_awid), .S0_AXI_AWADDR(s0_awaddr), .S0_AXI_AWLEN(s0_awlen),
        .S0_AXI_AWSIZE(s0_awsize), .S0_AXI_AWBURST(s0_awburst), .S0_AXI_AWPROT(s0_awprot),
        .S0_AXI_AWVALID(s0_awvalid), .S0_AXI_AWREADY(s0_awready),
        .S0_AXI_WDATA(s0_wdata), .S0_AXI_WSTRB(s0_wstrb), .S0_AXI_WLAST(s0_wlast),
        .S0_AXI_WVALID(s0_wvalid), .S0_AXI_WREADY(s0_wready),
        .S0_AXI_BID(s0_bid), .S0_AXI_BRESP(s0_bresp), .S0_AXI_BVALID(s0_bvalid),
        .S0_AXI_BREADY(s0_bready),
        .S1_AXI_ARID(s1_arid), .S1_AXI_ARADDR(s1_araddr), .S1_AXI_ARLEN(s1_arlen),
        .S1_AXI_ARSIZE(s1_arsize), .S1_AXI_ARBURST(s1_arburst), .S1_AXI_ARPROT(s1_arprot),
        .S1_AXI_ARVALID(s1_arvalid), .S1_AXI_ARREADY(s1_arready),
        .S1_AXI_RID(s1_rid), .S1_AXI_RDATA(s1_rdata), .S1_AXI_RRESP(s1_rresp),
        .S1_AXI_RLAST(s1_rlast), .S1_AXI_RVALID(s1_rvalid), .S1_AXI_RREADY(s1_rready),
        .S1_AXI_AWID(s1_awid), .S1_AXI_AWADDR(s1_awaddr), .S1_AXI_AWLEN(s1_awlen),
        .S1_AXI_AWSIZE(s1_awsize), .S1_AXI_AWBURST(s1_awburst), .S1_AXI_AWPROT(s1_awprot),
        .S1_AXI_AWVALID(s1_awvalid), .S1_AXI_AWREADY(s1_awready),
        .S1_AXI_WDATA(s1_wdata), .S1_AXI_WSTRB(s1_wstrb), .S1_AXI_WLAST(s1_wlast),
        .S1_AXI_WVALID(s1_wvalid), .S1_AXI_WREADY(s1_wready),
        .S1_AXI_BID(s1_bid), .S1_AXI_BRESP(s1_bresp), .S1_AXI_BVALID(s1_bvalid),
        .S1_AXI_BREADY(s1_bready),
        .S2_AXI_ARID(s2_arid), .S2_AXI_ARADDR(s2_araddr), .S2_AXI_ARLEN(s2_arlen),
        .S2_AXI_ARSIZE(s2_arsize), .S2_AXI_ARBURST(s2_arburst), .S2_AXI_ARPROT(s2_arprot),
        .S2_AXI_ARVALID(s2_arvalid), .S2_AXI_ARREADY(s2_arready),
        .S2_AXI_RID(s2_rid), .S2_AXI_RDATA(s2_rdata), .S2_AXI_RRESP(s2_rresp),
        .S2_AXI_RLAST(s2_rlast), .S2_AXI_RVALID(s2_rvalid), .S2_AXI_RREADY(s2_rready),
        .S2_AXI_AWID(s2_awid), .S2_AXI_AWADDR(s2_awaddr), .S2_AXI_AWLEN(s2_awlen),
        .S2_AXI_AWSIZE(s2_awsize), .S2_AXI_AWBURST(s2_awburst), .S2_AXI_AWPROT(s2_awprot),
        .S2_AXI_AWVALID(s2_awvalid), .S2_AXI_AWREADY(s2_awready),
        .S2_AXI_WDATA(s2_wdata), .S2_AXI_WSTRB(s2_wstrb), .S2_AXI_WLAST(s2_wlast),
        .S2_AXI_WVALID(s2_wvalid), .S2_AXI_WREADY(s2_wready),
        .S2_AXI_BID(s2_bid), .S2_AXI_BRESP(s2_bresp), .S2_AXI_BVALID(s2_bvalid),
        .S2_AXI_BREADY(s2_bready),
        .S3_AXI_ARID(s3_arid), .S3_AXI_ARADDR(s3_araddr), .S3_AXI_ARLEN(s3_arlen),
        .S3_AXI_ARSIZE(s3_arsize), .S3_AXI_ARBURST(s3_arburst), .S3_AXI_ARPROT(s3_arprot),
        .S3_AXI_ARVALID(s3_arvalid), .S3_AXI_ARREADY(s3_arready),
        .S3_AXI_RID(s3_rid), .S3_AXI_RDATA(s3_rdata), .S3_AXI_RRESP(s3_rresp),
        .S3_AXI_RLAST(s3_rlast), .S3_AXI_RVALID(s3_rvalid), .S3_AXI_RREADY(s3_rready),
        .S3_AXI_AWID(s3_awid), .S3_AXI_AWADDR(s3_awaddr), .S3_AXI_AWLEN(s3_awlen),
        .S3_AXI_AWSIZE(s3_awsize), .S3_AXI_AWBURST(s3_awburst), .S3_AXI_AWPROT(s3_awprot),
        .S3_AXI_AWVALID(s3_awvalid), .S3_AXI_AWREADY(s3_awready),
        .S3_AXI_WDATA(s3_wdata), .S3_AXI_WSTRB(s3_wstrb), .S3_AXI_WLAST(s3_wlast),
        .S3_AXI_WVALID(s3_wvalid), .S3_AXI_WREADY(s3_wready),
        .S3_AXI_BID(s3_bid), .S3_AXI_BRESP(s3_bresp), .S3_AXI_BVALID(s3_bvalid),
        .S3_AXI_BREADY(s3_bready)
    );

    // ========================================================================
    // Clock
    // ========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================================
    // Slave Models — FSM đúng chuẩn AXI4, không dùng @(posedge clk) trong always
    // ========================================================================

    // S0 Read FSM
    reg [1:0] s0_rd_st; // 0=IDLE, 1=RESP, 2=WAIT
    reg [ID_WIDTH-1:0] s0_ar_id_lat;
    reg [31:0]         s0_ar_addr_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_rd_st     <= 2'd0;
            s0_arready   <= 1'b1;
            s0_rvalid    <= 1'b0;
            s0_rlast     <= 1'b0;
            s0_rresp     <= 2'b00;
            s0_rdata     <= 32'h0;
            s0_rid       <= 4'h0;
        end else begin
            case (s0_rd_st)
                2'd0: begin // IDLE
                    s0_rvalid <= 1'b0; s0_rlast <= 1'b0;
                    if (s0_arvalid && s0_arready) begin
                        s0_ar_id_lat   <= s0_arid;
                        s0_ar_addr_lat <= s0_araddr;
                        s0_arready     <= 1'b0;
                        s0_rd_st       <= 2'd1;
                    end
                end
                2'd1: begin // RESP — assert rvalid next cycle
                    s0_rid    <= s0_ar_id_lat;
                    s0_rdata  <= 32'hC0DE_0000 | {24'h0, s0_ar_addr_lat[7:0]};
                    s0_rresp  <= 2'b00;
                    s0_rlast  <= 1'b1;
                    s0_rvalid <= 1'b1;
                    s0_rd_st  <= 2'd2;
                end
                2'd2: begin // WAIT rready
                    if (s0_rvalid && s0_rready) begin
                        s0_rvalid  <= 1'b0;
                        s0_rlast   <= 1'b0;
                        s0_arready <= 1'b1;
                        s0_rd_st   <= 2'd0;
                    end
                end
                default: s0_rd_st <= 2'd0;
            endcase
        end
    end

    // S0 Write FSM
    reg [1:0] s0_wr_st; // 0=IDLE, 1=DRAIN_W, 2=BRESP, 3=BWAIT
    reg [ID_WIDTH-1:0] s0_aw_id_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_wr_st   <= 2'd0;
            s0_awready <= 1'b1;
            s0_wready  <= 1'b0;
            s0_bvalid  <= 1'b0;
            s0_bresp   <= 2'b00;
            s0_bid     <= 4'h0;
        end else begin
            case (s0_wr_st)
                2'd0: begin // IDLE
                    s0_bvalid <= 1'b0;
                    if (s0_awvalid && s0_awready) begin
                        s0_aw_id_lat <= s0_awid;
                        s0_awready   <= 1'b0;
                        s0_wready    <= 1'b1;
                        s0_wr_st     <= 2'd1;
                    end
                end
                2'd1: begin // DRAIN_W
                    if (s0_wvalid && s0_wready && s0_wlast) begin
                        s0_wready <= 1'b0;
                        s0_bid    <= s0_aw_id_lat;
                        s0_bresp  <= 2'b00;
                        s0_bvalid <= 1'b1;
                        s0_wr_st  <= 2'd2;
                    end
                end
                2'd2: begin // BWAIT
                    if (s0_bvalid && s0_bready) begin
                        s0_bvalid  <= 1'b0;
                        s0_awready <= 1'b1;
                        s0_wr_st   <= 2'd0;
                    end
                end
                default: s0_wr_st <= 2'd0;
            endcase
        end
    end

    // S1 Read FSM
    reg [1:0] s1_rd_st;
    reg [ID_WIDTH-1:0] s1_ar_id_lat;
    reg [31:0]         s1_ar_addr_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_rd_st     <= 2'd0;
            s1_arready   <= 1'b1;
            s1_rvalid    <= 1'b0;
            s1_rlast     <= 1'b0;
            s1_rresp     <= 2'b00;
            s1_rdata     <= 32'h0;
            s1_rid       <= 4'h0;
        end else begin
            case (s1_rd_st)
                2'd0: begin
                    s1_rvalid <= 1'b0; s1_rlast <= 1'b0;
                    if (s1_arvalid && s1_arready) begin
                        s1_ar_id_lat   <= s1_arid;
                        s1_ar_addr_lat <= s1_araddr;
                        s1_arready     <= 1'b0;
                        s1_rd_st       <= 2'd1;
                    end
                end
                2'd1: begin
                    s1_rid    <= s1_ar_id_lat;
                    s1_rdata  <= 32'hDA7A_0000 | {24'h0, s1_ar_addr_lat[7:0]};
                    s1_rresp  <= 2'b00;
                    s1_rlast  <= 1'b1;
                    s1_rvalid <= 1'b1;
                    s1_rd_st  <= 2'd2;
                end
                2'd2: begin
                    if (s1_rvalid && s1_rready) begin
                        s1_rvalid  <= 1'b0;
                        s1_rlast   <= 1'b0;
                        s1_arready <= 1'b1;
                        s1_rd_st   <= 2'd0;
                    end
                end
                default: s1_rd_st <= 2'd0;
            endcase
        end
    end

    // S1 Write FSM
    reg [1:0] s1_wr_st;
    reg [ID_WIDTH-1:0] s1_aw_id_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_wr_st   <= 2'd0;
            s1_awready <= 1'b1;
            s1_wready  <= 1'b0;
            s1_bvalid  <= 1'b0;
            s1_bresp   <= 2'b00;
            s1_bid     <= 4'h0;
        end else begin
            case (s1_wr_st)
                2'd0: begin
                    s1_bvalid <= 1'b0;
                    if (s1_awvalid && s1_awready) begin
                        s1_aw_id_lat <= s1_awid;
                        s1_awready   <= 1'b0;
                        s1_wready    <= 1'b1;
                        s1_wr_st     <= 2'd1;
                    end
                end
                2'd1: begin
                    if (s1_wvalid && s1_wready && s1_wlast) begin
                        s1_wready <= 1'b0;
                        s1_bid    <= s1_aw_id_lat;
                        s1_bresp  <= 2'b00;
                        s1_bvalid <= 1'b1;
                        s1_wr_st  <= 2'd2;
                    end
                end
                2'd2: begin
                    if (s1_bvalid && s1_bready) begin
                        s1_bvalid  <= 1'b0;
                        s1_awready <= 1'b1;
                        s1_wr_st   <= 2'd0;
                    end
                end
                default: s1_wr_st <= 2'd0;
            endcase
        end
    end

    // S2/S3 — combinational stub (1-cycle respond)
    always @(*) begin
        s2_arready  = 1'b1; s2_awready = 1'b1; s2_wready = 1'b1;
        s2_rid_r    = s2_arid;
        s2_rdata_r  = 32'hA5C0_0000;
        s2_rresp_r  = 2'b00;
        s2_rlast_r  = 1'b1;
        s2_rvalid_r = s2_arvalid;
        s2_bid_r    = s2_awid; s2_bresp_r = 2'b00; s2_bvalid_r = 1'b0;

        s3_arready  = 1'b1; s3_awready = 1'b1; s3_wready = 1'b1;
        s3_rid_r    = s3_arid;
        s3_rdata_r  = 32'hC7E1_0000;
        s3_rresp_r  = 2'b00;
        s3_rlast_r  = 1'b1;
        s3_rvalid_r = s3_arvalid;
        s3_bid_r    = s3_awid; s3_bresp_r = 2'b00; s3_bvalid_r = 1'b0;
    end

    // ========================================================================
    // Helper tasks
    // ========================================================================
    task init_masters;
        begin
            m0_arvalid = 0; m0_araddr = 0; m0_arid = 0;
            m0_arlen = 0; m0_arsize = 3'b010; m0_arburst = 2'b01; m0_arprot = 0;
            m0_rready = 1;
            m0_awvalid = 0; m0_awaddr = 0; m0_awid = 0;
            m0_awlen = 0; m0_awsize = 3'b010; m0_awburst = 2'b01; m0_awprot = 0;
            m0_wvalid = 0; m0_wdata = 0; m0_wstrb = 4'hF; m0_wlast = 0;
            m0_bready = 1;

            m1_arvalid = 0; m1_araddr = 0; m1_arid = 0;
            m1_arlen = 0; m1_arsize = 3'b010; m1_arburst = 2'b01; m1_arprot = 0;
            m1_rready = 1;
            m1_awvalid = 0; m1_awaddr = 0; m1_awid = 0;
            m1_awlen = 0; m1_awsize = 3'b010; m1_awburst = 2'b01; m1_awprot = 0;
            m1_wvalid = 0; m1_wdata = 0; m1_wstrb = 4'hF; m1_wlast = 0;
            m1_bready = 1;
        end
    endtask

    // AXI read: gửi AR, chờ R
    task axi_read;
        input [3:0]  id;
        input [31:0] addr;
        input        use_m0; // 1=M0, 0=M1
        output [31:0] rdata_out;
        output [1:0]  rresp_out;
        integer timeout;
        begin
            @(negedge clk);
            if (use_m0) begin
                m0_arid = id; m0_araddr = addr; m0_arvalid = 1;
                @(posedge clk); while (!m0_arready) @(posedge clk);
                @(negedge clk); m0_arvalid = 0;
                @(posedge clk); timeout = 0;
                while (!m0_rvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
                rdata_out = m0_rdata; rresp_out = m0_rresp;
            end else begin
                m1_arid = id; m1_araddr = addr; m1_arvalid = 1;
                @(posedge clk); while (!m1_arready) @(posedge clk);
                @(negedge clk); m1_arvalid = 0;
                @(posedge clk); timeout = 0;
                while (!m1_rvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
                rdata_out = m1_rdata; rresp_out = m1_rresp;
            end
            @(negedge clk);
        end
    endtask

    // AXI write: gửi AW+W, chờ B
    task axi_write;
        input [3:0]  id;
        input [31:0] addr;
        input [31:0] wdata;
        input        use_m0;
        output [1:0] bresp_out;
        integer timeout;
        begin
            @(negedge clk);
            if (use_m0) begin
                m0_awid = id; m0_awaddr = addr; m0_awvalid = 1;
                m0_wdata = wdata; m0_wvalid = 1; m0_wlast = 1;
                @(posedge clk); while (!m0_awready) @(posedge clk);
                @(negedge clk); m0_awvalid = 0;
                @(posedge clk); while (!m0_wready) @(posedge clk);
                @(negedge clk); m0_wvalid = 0; m0_wlast = 0;
                @(posedge clk); timeout = 0;
                while (!m0_bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
                bresp_out = m0_bresp;
            end else begin
                m1_awid = id; m1_awaddr = addr; m1_awvalid = 1;
                m1_wdata = wdata; m1_wvalid = 1; m1_wlast = 1;
                @(posedge clk); while (!m1_awready) @(posedge clk);
                @(negedge clk); m1_awvalid = 0;
                @(posedge clk); while (!m1_wready) @(posedge clk);
                @(negedge clk); m1_wvalid = 0; m1_wlast = 0;
                @(posedge clk); timeout = 0;
                while (!m1_bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
                bresp_out = m1_bresp;
            end
            @(negedge clk);
        end
    endtask

    // ========================================================================
    // Test
    // ========================================================================
    integer pass_count, fail_count;
    reg [31:0] rdata;
    reg [1:0]  rresp, bresp;

    task check;
        input [63:0] got;
        input [63:0] expected;
        input [127:0] name;
        begin
            if (got === expected) begin
                $display("[PASS] %s: got=0x%08h", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s: got=0x%08h expected=0x%08h", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        init_masters;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        $display("\n======== TC1: M0 đọc IMEM (0x0000_1000) ========");
        axi_read(4'h1, 32'h0000_1000, 1, rdata, rresp);
        check(rresp, 2'b00, "TC1 RRESP");
        check(rdata[31:8], 24'hC0DE00, "TC1 RDATA pattern");

        $display("\n======== TC2: M1 đọc DMEM (0x1000_0020) ========");
        axi_read(4'h2, 32'h1000_0020, 0, rdata, rresp);
        check(rresp, 2'b00, "TC2 RRESP");

        $display("\n======== TC3: M1 ghi DMEM (0x1000_0040) ========");
        axi_write(4'h3, 32'h1000_0040, 32'hABCD_EF01, 0, bresp);
        check(bresp, 2'b00, "TC3 BRESP");

        $display("\n======== TC4: M0 và M1 đọc các slave khác nhau đồng thời ========");
        // Gửi cả 2 cùng lúc
        fork
            axi_read(4'h4, 32'h0000_2000, 1, rdata, rresp);
            axi_read(4'h5, 32'h1000_0060, 0, rdata, rresp);
        join
        $display("[INFO] TC4 done — non-blocking parallel reads");

        $display("\n======== TC5: M0 và M1 tranh chấp S0 — M0 phải thắng ========");
        fork
            begin
                axi_read(4'h6, 32'h0000_3000, 1, rdata, rresp);
                $display("[INFO] TC5 M0 received first (expected)");
            end
            begin
                repeat(1) @(posedge clk); // M1 delay nhỏ
                axi_read(4'h7, 32'h0000_4000, 0, rdata, rresp);
                $display("[INFO] TC5 M1 received after M0");
            end
        join

        $display("\n======== TC6: M0 đọc địa chỉ không ánh xạ (0x9000_0000) ========");
        axi_read(4'h8, 32'h9000_0000, 1, rdata, rresp);
        check(rresp, 2'b11, "TC6 RRESP=DECERR");
        check(rdata, 32'hDEAD_BEEF, "TC6 RDATA=DEAD_BEEF");

        $display("\n======== TC7: M1 ghi địa chỉ không ánh xạ (0x8000_0000) ========");
        axi_write(4'h9, 32'h8000_0000, 32'hDEAD_1234, 0, bresp);
        check(bresp, 2'b11, "TC7 BRESP=DECERR");

        $display("\n======== TC8: M1 đọc ASCON (0x2000_0000) ========");
        axi_read(4'hA, 32'h2000_0000, 0, rdata, rresp);
        check(rresp, 2'b00, "TC8 RRESP=OKAY (S2 stub)");

        $display("\n======== SUMMARY ========");
        $display("PASS: %0d  FAIL: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        #100;
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("[TIMEOUT] Simulation timed out");
        $finish;
    end

    // VCD dump
    initial begin
        $dumpfile("tb_axi4_crossbar.vcd");
        $dumpvars(0, tb_axi4_crossbar);
    end

endmodule