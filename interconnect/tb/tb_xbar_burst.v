`timescale 1ns/1ps

`timescale 1ns/1ps
// ============================================================================
// tb_xbar_burst.v — Focused debug TB: Crossbar + Master Mux
//
// Mục tiêu: verify 3 bug đã fix hoạt động đúng
//   BUG1 (mux line 295): m0_rlast = s_rlast  (không gate → leak)
//   BUG2 (mux line 172): if/if race → rd_burst_active set+clear cùng cycle
//   BUG3 (xbar line 397): RLAST OR thô → bắt rác từ slave idle
//
// Test cases:
//   T1  1-beat baseline — data đúng, RLAST=1 đúng cycle
//   T2  8-beat burst    — đủ 8 beat, RLAST chỉ ở beat[7]
//   T3  State pollution — 1-beat → 8-beat ngay sau, FSM không bị dơ
//   T4  8-beat tại offset — address decode + burst offset đúng
//   T5  Stress 5 burst  — 5 lần 8-beat liên tiếp, không stuck
//   T6  RLAST early detection — kiểm tra không có RLAST trước beat cuối
//
// Compile:
//   iverilog -g2005 -o tb_xbar_burst.vvp cpu/tb/tb_xbar_burst.v
//   vvp tb_xbar_burst.vvp
// ============================================================================

`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/interconnect/axi4_crossbar.v"

`define CLK_PERIOD 10
`define ID_W       4
`define TIMEOUT    3000

module tb_xbar_burst;

// ============================================================================
// Clock / Reset / Cycle counter
// ============================================================================
reg clk, rst_n;
integer cyc;

initial  clk = 0;
always #(`CLK_PERIOD/2) clk = ~clk;
always @(posedge clk) if (rst_n) cyc = cyc + 1;

// ============================================================================
// Counters
// ============================================================================
integer pass_cnt, fail_cnt;

// ============================================================================
// Burst collection buffers
// ============================================================================
integer      bi;           // số beats đã nhận
reg          got_last;
reg [31:0]   bdata [0:15]; // beat data
reg [1:0]    bresp [0:15]; // beat resp
reg          blast [0:15]; // beat RLAST
integer      wc;           // wait counter

// ============================================================================
// Reference memory (loaded từ program.hex)
// ============================================================================
reg [31:0] ref_mem [0:1023];

// ============================================================================
// M0 drive signals — TB là master
// ============================================================================
reg [`ID_W-1:0] m0_arid;
reg [31:0]      m0_araddr;
reg [7:0]       m0_arlen;
reg [2:0]       m0_arsize;
reg [1:0]       m0_arburst;
reg             m0_arvalid;
reg             m0_rready;

// Write tied off
wire [`ID_W-1:0] m0_awid    = 4'h0;
wire [31:0]      m0_awaddr  = 32'h0;
wire [7:0]       m0_awlen   = 8'h0;
wire [2:0]       m0_awsize  = 3'h2;
wire [1:0]       m0_awburst = 2'b01;
wire [2:0]       m0_awprot  = 3'h0;
wire             m0_awvalid = 1'b0;
wire [31:0]      m0_wdata   = 32'h0;
wire [3:0]       m0_wstrb   = 4'h0;
wire             m0_wlast   = 1'b0;
wire             m0_wvalid  = 1'b0;
wire             m0_bready  = 1'b1;

// M0 outputs from crossbar
wire             m0_arready;
wire [`ID_W-1:0] m0_rid;
wire [31:0]      m0_rdata;
wire [1:0]       m0_rresp;
wire             m0_rlast;
wire             m0_rvalid;
wire             m0_awready, m0_wready;
wire [`ID_W-1:0] m0_bid;
wire [1:0]       m0_bresp;
wire             m0_bvalid;

// ============================================================================
// S0 (IMEM) wires
// ============================================================================
wire [`ID_W-1:0] s0_arid, s0_awid, s0_rid, s0_bid;
wire [31:0]  s0_araddr, s0_awaddr, s0_rdata, s0_wdata;
wire [7:0]   s0_arlen, s0_awlen;
wire [2:0]   s0_arsize, s0_awsize, s0_arprot, s0_awprot;
wire [1:0]   s0_arburst, s0_awburst, s0_rresp, s0_bresp;
wire         s0_arvalid, s0_arready, s0_rvalid, s0_rready, s0_rlast;
wire         s0_awvalid, s0_awready, s0_wvalid, s0_wready, s0_wlast;
wire         s0_bvalid, s0_bready;
wire [3:0]   s0_wstrb;

// ============================================================================
// Stub S1/S2/S3 — SLVERR instant
// ============================================================================
`define STUB_SLAVE(N) \
wire [`ID_W-1:0] s``N``_arid,s``N``_awid; \
wire [31:0] s``N``_araddr,s``N``_awaddr,s``N``_wdata; \
wire [7:0] s``N``_arlen,s``N``_awlen; \
wire [2:0] s``N``_arsize,s``N``_awsize,s``N``_arprot,s``N``_awprot; \
wire [1:0] s``N``_arburst,s``N``_awburst; \
wire s``N``_arvalid,s``N``_awvalid,s``N``_wvalid,s``N``_wlast; \
wire [3:0] s``N``_wstrb; \
wire [`ID_W-1:0] s``N``_rid; \
wire [31:0] s``N``_rdata; \
wire [1:0] s``N``_rresp,s``N``_bresp; \
wire s``N``_rlast,s``N``_rvalid,s``N``_rready,s``N``_arready; \
wire s``N``_awready,s``N``_wready; \
wire [`ID_W-1:0] s``N``_bid; \
wire s``N``_bvalid,s``N``_bready; \
assign s``N``_arready=1'b1; assign s``N``_rid=s``N``_arid; \
assign s``N``_rdata=32'hDEAD_BEEF; assign s``N``_rresp=2'b10; \
assign s``N``_rlast=1'b1; assign s``N``_rvalid=s``N``_arvalid; \
assign s``N``_awready=1'b1; assign s``N``_wready=1'b1; \
assign s``N``_bid=s``N``_awid; assign s``N``_bresp=2'b10; \
assign s``N``_bvalid=1'b0;

// Verilog-2001 không hỗ trợ macro multiline tốt — khai báo thủ công
wire [`ID_W-1:0] s1_arid,s1_awid; wire[31:0] s1_araddr,s1_awaddr,s1_wdata;
wire[7:0] s1_arlen,s1_awlen; wire[2:0] s1_arsize,s1_awsize,s1_arprot,s1_awprot;
wire[1:0] s1_arburst,s1_awburst; wire s1_arvalid,s1_awvalid,s1_wvalid,s1_wlast; wire[3:0] s1_wstrb;
wire [`ID_W-1:0] s1_rid; wire[31:0] s1_rdata; wire[1:0] s1_rresp,s1_bresp;
wire s1_rlast,s1_rvalid,s1_rready,s1_arready,s1_awready,s1_wready;
wire [`ID_W-1:0] s1_bid; wire s1_bvalid,s1_bready;
assign s1_arready=1'b1; assign s1_rid=s1_arid; assign s1_rdata=32'hDEAD_BEEF;
assign s1_rresp=2'b10;  assign s1_rlast=1'b1;  assign s1_rvalid=s1_arvalid;
assign s1_awready=1'b1; assign s1_wready=1'b1; assign s1_bid=s1_awid;
assign s1_bresp=2'b10;  assign s1_bvalid=1'b0;

wire [`ID_W-1:0] s2_arid,s2_awid; wire[31:0] s2_araddr,s2_awaddr,s2_wdata;
wire[7:0] s2_arlen,s2_awlen; wire[2:0] s2_arsize,s2_awsize,s2_arprot,s2_awprot;
wire[1:0] s2_arburst,s2_awburst; wire s2_arvalid,s2_awvalid,s2_wvalid,s2_wlast; wire[3:0] s2_wstrb;
wire [`ID_W-1:0] s2_rid; wire[31:0] s2_rdata; wire[1:0] s2_rresp,s2_bresp;
wire s2_rlast,s2_rvalid,s2_rready,s2_arready,s2_awready,s2_wready;
wire [`ID_W-1:0] s2_bid; wire s2_bvalid,s2_bready;
assign s2_arready=1'b1; assign s2_rid=s2_arid; assign s2_rdata=32'hDEAD_BEEF;
assign s2_rresp=2'b10;  assign s2_rlast=1'b1;  assign s2_rvalid=s2_arvalid;
assign s2_awready=1'b1; assign s2_wready=1'b1; assign s2_bid=s2_awid;
assign s2_bresp=2'b10;  assign s2_bvalid=1'b0;

wire [`ID_W-1:0] s3_arid,s3_awid; wire[31:0] s3_araddr,s3_awaddr,s3_wdata;
wire[7:0] s3_arlen,s3_awlen; wire[2:0] s3_arsize,s3_awsize,s3_arprot,s3_awprot;
wire[1:0] s3_arburst,s3_awburst; wire s3_arvalid,s3_awvalid,s3_wvalid,s3_wlast; wire[3:0] s3_wstrb;
wire [`ID_W-1:0] s3_rid; wire[31:0] s3_rdata; wire[1:0] s3_rresp,s3_bresp;
wire s3_rlast,s3_rvalid,s3_rready,s3_arready,s3_awready,s3_wready;
wire [`ID_W-1:0] s3_bid; wire s3_bvalid,s3_bready;
assign s3_arready=1'b1; assign s3_rid=s3_arid; assign s3_rdata=32'hDEAD_BEEF;
assign s3_rresp=2'b10;  assign s3_rlast=1'b1;  assign s3_rvalid=s3_arvalid;
assign s3_awready=1'b1; assign s3_wready=1'b1; assign s3_bid=s3_awid;
assign s3_bresp=2'b10;  assign s3_bvalid=1'b0;

// ============================================================================
// DUT 1: IMEM (S0)
// ============================================================================
inst_mem_axi_slave #(
    .ID_WIDTH(`ID_W), .MEM_SIZE(4096),
    .MEM_INIT_FILE("cpu/memory_axi4full/program.hex")
) u_imem (
    .clk(clk),           .rst_n(rst_n),
    .S_AXI_ARID(s0_arid),    .S_AXI_ARADDR(s0_araddr),  .S_AXI_ARLEN(s0_arlen),
    .S_AXI_ARSIZE(s0_arsize),.S_AXI_ARBURST(s0_arburst),.S_AXI_ARPROT(s0_arprot),
    .S_AXI_ARVALID(s0_arvalid),.S_AXI_ARREADY(s0_arready),
    .S_AXI_RID(s0_rid),      .S_AXI_RDATA(s0_rdata),    .S_AXI_RRESP(s0_rresp),
    .S_AXI_RLAST(s0_rlast),  .S_AXI_RVALID(s0_rvalid),  .S_AXI_RREADY(s0_rready),
    .S_AXI_AWID(s0_awid),    .S_AXI_AWADDR(s0_awaddr),  .S_AXI_AWLEN(s0_awlen),
    .S_AXI_AWSIZE(s0_awsize),.S_AXI_AWBURST(s0_awburst),.S_AXI_AWPROT(s0_awprot),
    .S_AXI_AWVALID(s0_awvalid),.S_AXI_AWREADY(s0_awready),
    .S_AXI_WDATA(s0_wdata),  .S_AXI_WSTRB(s0_wstrb),    .S_AXI_WLAST(s0_wlast),
    .S_AXI_WVALID(s0_wvalid),.S_AXI_WREADY(s0_wready),
    .S_AXI_BID(s0_bid),      .S_AXI_BRESP(s0_bresp),    .S_AXI_BVALID(s0_bvalid),
    .S_AXI_BREADY(s0_bready)
);

// ============================================================================
// DUT 2: Crossbar
// ============================================================================
axi4_crossbar #(.ID_WIDTH(`ID_W)) u_xbar (
    .clk(clk), .rst_n(rst_n),
    // M0
    .M0_AXI_ARID(m0_arid),     .M0_AXI_ARADDR(m0_araddr),  .M0_AXI_ARLEN(m0_arlen),
    .M0_AXI_ARSIZE(m0_arsize), .M0_AXI_ARBURST(m0_arburst),.M0_AXI_ARPROT(3'h0),
    .M0_AXI_ARVALID(m0_arvalid),.M0_AXI_ARREADY(m0_arready),
    .M0_AXI_RID(m0_rid),       .M0_AXI_RDATA(m0_rdata),    .M0_AXI_RRESP(m0_rresp),
    .M0_AXI_RLAST(m0_rlast),   .M0_AXI_RVALID(m0_rvalid),  .M0_AXI_RREADY(m0_rready),
    .M0_AXI_AWID(m0_awid),     .M0_AXI_AWADDR(m0_awaddr),  .M0_AXI_AWLEN(m0_awlen),
    .M0_AXI_AWSIZE(m0_awsize), .M0_AXI_AWBURST(m0_awburst),.M0_AXI_AWPROT(3'h0),
    .M0_AXI_AWVALID(m0_awvalid),.M0_AXI_AWREADY(m0_awready),
    .M0_AXI_WDATA(m0_wdata),   .M0_AXI_WSTRB(m0_wstrb),    .M0_AXI_WLAST(m0_wlast),
    .M0_AXI_WVALID(m0_wvalid), .M0_AXI_WREADY(m0_wready),
    .M0_AXI_BID(m0_bid),       .M0_AXI_BRESP(m0_bresp),    .M0_AXI_BVALID(m0_bvalid),
    .M0_AXI_BREADY(m0_bready),
    // M1 tied off
    .M1_AXI_ARID(4'h0),  .M1_AXI_ARADDR(32'h0), .M1_AXI_ARLEN(8'h0),
    .M1_AXI_ARSIZE(3'h2),.M1_AXI_ARBURST(2'b01),.M1_AXI_ARPROT(3'h0),
    .M1_AXI_ARVALID(1'b0),.M1_AXI_ARREADY(),
    .M1_AXI_RID(),       .M1_AXI_RDATA(),        .M1_AXI_RRESP(),
    .M1_AXI_RLAST(),     .M1_AXI_RVALID(),       .M1_AXI_RREADY(1'b1),
    .M1_AXI_AWID(4'h0),  .M1_AXI_AWADDR(32'h0), .M1_AXI_AWLEN(8'h0),
    .M1_AXI_AWSIZE(3'h2),.M1_AXI_AWBURST(2'b01),.M1_AXI_AWPROT(3'h0),
    .M1_AXI_AWVALID(1'b0),.M1_AXI_AWREADY(),
    .M1_AXI_WDATA(32'h0),.M1_AXI_WSTRB(4'h0),   .M1_AXI_WLAST(1'b0),
    .M1_AXI_WVALID(1'b0),.M1_AXI_WREADY(),
    .M1_AXI_BID(),       .M1_AXI_BRESP(),        .M1_AXI_BVALID(),
    .M1_AXI_BREADY(1'b1),
    // S0
    .S0_AXI_ARID(s0_arid),    .S0_AXI_ARADDR(s0_araddr),  .S0_AXI_ARLEN(s0_arlen),
    .S0_AXI_ARSIZE(s0_arsize),.S0_AXI_ARBURST(s0_arburst),.S0_AXI_ARPROT(s0_arprot),
    .S0_AXI_ARVALID(s0_arvalid),.S0_AXI_ARREADY(s0_arready),
    .S0_AXI_RID(s0_rid),      .S0_AXI_RDATA(s0_rdata),    .S0_AXI_RRESP(s0_rresp),
    .S0_AXI_RLAST(s0_rlast),  .S0_AXI_RVALID(s0_rvalid),  .S0_AXI_RREADY(s0_rready),
    .S0_AXI_AWID(s0_awid),    .S0_AXI_AWADDR(s0_awaddr),  .S0_AXI_AWLEN(s0_awlen),
    .S0_AXI_AWSIZE(s0_awsize),.S0_AXI_AWBURST(s0_awburst),.S0_AXI_AWPROT(s0_awprot),
    .S0_AXI_AWVALID(s0_awvalid),.S0_AXI_AWREADY(s0_awready),
    .S0_AXI_WDATA(s0_wdata),  .S0_AXI_WSTRB(s0_wstrb),    .S0_AXI_WLAST(s0_wlast),
    .S0_AXI_WVALID(s0_wvalid),.S0_AXI_WREADY(s0_wready),
    .S0_AXI_BID(s0_bid),      .S0_AXI_BRESP(s0_bresp),    .S0_AXI_BVALID(s0_bvalid),
    .S0_AXI_BREADY(s0_bready),
    // S1
    .S1_AXI_ARID(s1_arid),    .S1_AXI_ARADDR(s1_araddr),  .S1_AXI_ARLEN(s1_arlen),
    .S1_AXI_ARSIZE(s1_arsize),.S1_AXI_ARBURST(s1_arburst),.S1_AXI_ARPROT(s1_arprot),
    .S1_AXI_ARVALID(s1_arvalid),.S1_AXI_ARREADY(s1_arready),
    .S1_AXI_RID(s1_rid),      .S1_AXI_RDATA(s1_rdata),    .S1_AXI_RRESP(s1_rresp),
    .S1_AXI_RLAST(s1_rlast),  .S1_AXI_RVALID(s1_rvalid),  .S1_AXI_RREADY(s1_rready),
    .S1_AXI_AWID(s1_awid),    .S1_AXI_AWADDR(s1_awaddr),  .S1_AXI_AWLEN(s1_awlen),
    .S1_AXI_AWSIZE(s1_awsize),.S1_AXI_AWBURST(s1_awburst),.S1_AXI_AWPROT(s1_awprot),
    .S1_AXI_AWVALID(s1_awvalid),.S1_AXI_AWREADY(s1_awready),
    .S1_AXI_WDATA(s1_wdata),  .S1_AXI_WSTRB(s1_wstrb),    .S1_AXI_WLAST(s1_wlast),
    .S1_AXI_WVALID(s1_wvalid),.S1_AXI_WREADY(s1_wready),
    .S1_AXI_BID(s1_bid),      .S1_AXI_BRESP(s1_bresp),    .S1_AXI_BVALID(s1_bvalid),
    .S1_AXI_BREADY(s1_bready),
    // S2
    .S2_AXI_ARID(s2_arid),    .S2_AXI_ARADDR(s2_araddr),  .S2_AXI_ARLEN(s2_arlen),
    .S2_AXI_ARSIZE(s2_arsize),.S2_AXI_ARBURST(s2_arburst),.S2_AXI_ARPROT(s2_arprot),
    .S2_AXI_ARVALID(s2_arvalid),.S2_AXI_ARREADY(s2_arready),
    .S2_AXI_RID(s2_rid),      .S2_AXI_RDATA(s2_rdata),    .S2_AXI_RRESP(s2_rresp),
    .S2_AXI_RLAST(s2_rlast),  .S2_AXI_RVALID(s2_rvalid),  .S2_AXI_RREADY(s2_rready),
    .S2_AXI_AWID(s2_awid),    .S2_AXI_AWADDR(s2_awaddr),  .S2_AXI_AWLEN(s2_awlen),
    .S2_AXI_AWSIZE(s2_awsize),.S2_AXI_AWBURST(s2_awburst),.S2_AXI_AWPROT(s2_awprot),
    .S2_AXI_AWVALID(s2_awvalid),.S2_AXI_AWREADY(s2_awready),
    .S2_AXI_WDATA(s2_wdata),  .S2_AXI_WSTRB(s2_wstrb),    .S2_AXI_WLAST(s2_wlast),
    .S2_AXI_WVALID(s2_wvalid),.S2_AXI_WREADY(s2_wready),
    .S2_AXI_BID(s2_bid),      .S2_AXI_BRESP(s2_bresp),    .S2_AXI_BVALID(s2_bvalid),
    .S2_AXI_BREADY(s2_bready),
    // S3
    .S3_AXI_ARID(s3_arid),    .S3_AXI_ARADDR(s3_araddr),  .S3_AXI_ARLEN(s3_arlen),
    .S3_AXI_ARSIZE(s3_arsize),.S3_AXI_ARBURST(s3_arburst),.S3_AXI_ARPROT(s3_arprot),
    .S3_AXI_ARVALID(s3_arvalid),.S3_AXI_ARREADY(s3_arready),
    .S3_AXI_RID(s3_rid),      .S3_AXI_RDATA(s3_rdata),    .S3_AXI_RRESP(s3_rresp),
    .S3_AXI_RLAST(s3_rlast),  .S3_AXI_RVALID(s3_rvalid),  .S3_AXI_RREADY(s3_rready),
    .S3_AXI_AWID(s3_awid),    .S3_AXI_AWADDR(s3_awaddr),  .S3_AXI_AWLEN(s3_awlen),
    .S3_AXI_AWSIZE(s3_awsize),.S3_AXI_AWBURST(s3_awburst),.S3_AXI_AWPROT(s3_awprot),
    .S3_AXI_AWVALID(s3_awvalid),.S3_AXI_AWREADY(s3_awready),
    .S3_AXI_WDATA(s3_wdata),  .S3_AXI_WSTRB(s3_wstrb),    .S3_AXI_WLAST(s3_wlast),
    .S3_AXI_WVALID(s3_wvalid),.S3_AXI_WREADY(s3_wready),
    .S3_AXI_BID(s3_bid),      .S3_AXI_BRESP(s3_bresp),    .S3_AXI_BVALID(s3_bvalid),
    .S3_AXI_BREADY(s3_bready)
);

// ============================================================================
// VCD + Watchdog
// ============================================================================
initial begin
    $dumpfile("tb_xbar_burst.vcd");
    $dumpvars(0, tb_xbar_burst);
end
initial begin
    #(`CLK_PERIOD * `TIMEOUT);
    $display("[TIMEOUT] hung @ cyc=%0d", cyc);
    $finish;
end

// ============================================================================
// Monitor: log mọi AR/R handshake — hiển thị RLAST từ cả 2 điểm để so sánh
// ============================================================================
always @(posedge clk) begin
    // AR handshake M0 → Crossbar
    if (m0_arvalid && m0_arready)
        $display("[%4d] AR  TB→XB   addr=0x%08h  arlen=%0d  id=0x%h",
                 cyc, m0_araddr, m0_arlen+1, m0_arid);
    // AR handshake Crossbar → IMEM
    if (s0_arvalid && s0_arready)
        $display("[%4d] AR  XB→S0   addr=0x%08h  arlen=%0d  id=0x%h",
                 cyc, s0_araddr, s0_arlen+1, s0_arid);
    // R beat IMEM → Crossbar (điểm gốc, last từ IMEM)
    if (s0_rvalid && s0_rready)
        $display("[%4d] R   S0→XB   data=0x%08h  last_IMEM=%b  rid=0x%h",
                 cyc, s0_rdata, s0_rlast, s0_rid);
    // R beat Crossbar → TB (điểm quan sát, last sau gate)
    if (m0_rvalid && m0_rready)
        $display("[%4d] R   XB→TB   data=0x%08h  last_XBAR=%b  rid=0x%h  resp=%0b",
                 cyc, m0_rdata, m0_rlast, m0_rid, m0_rresp);
end

// ============================================================================
// Task: gửi 1 AR burst và thu thập tất cả R beats
// ============================================================================
task do_burst;
    input [`ID_W-1:0] t_id;
    input [31:0]      t_addr;
    input [7:0]       t_len;    // ARLEN (beat count = t_len + 1)
    integer j;
    begin
        bi       = 0;
        got_last = 1'b0;
        for (j = 0; j < 16; j = j + 1) begin
            bdata[j] = 32'hx;
            bresp[j] = 2'bxx;
            blast[j] = 1'bx;
        end

        // Drive AR
        @(negedge clk);
        m0_arid    = t_id;
        m0_araddr  = t_addr;
        m0_arlen   = t_len;
        m0_arsize  = 3'b010;   // 4 bytes/beat
        m0_arburst = 2'b01;    // INCR
        m0_arvalid = 1'b1;
        m0_rready  = 1'b1;

        // Chờ ARREADY (tối đa 20 cycle)
        wc = 0;
        @(posedge clk);
        while (!m0_arready && wc < 20) begin
            @(posedge clk);
            wc = wc + 1;
        end
        if (!m0_arready)
            $display("  [WARN] ARREADY timeout addr=0x%08h", t_addr);

        // Deassert ARVALID sau handshake
        @(negedge clk);
        m0_arvalid = 1'b0;

        // Thu thập R beats
        wc = 0;
        @(posedge clk);
        while (!got_last && wc < `TIMEOUT) begin
            if (m0_rvalid) begin
                bdata[bi] = m0_rdata;
                bresp[bi] = m0_rresp;
                blast[bi] = m0_rlast;
                got_last  = m0_rlast;
                bi        = bi + 1;
            end
            @(posedge clk);
            wc = wc + 1;
        end
        if (!got_last)
            $display("  [WARN] RLAST never came, addr=0x%08h len=%0d", t_addr, t_len+1);

        // Deassert RREADY
        @(negedge clk);
        m0_rready = 1'b0;

        // Gap giữa các transaction (cho FSM về IDLE)
        repeat(5) @(posedge clk);
    end
endtask

// ============================================================================
// Task: kiểm tra RLAST chỉ xuất hiện đúng ở beat cuối
// ============================================================================
task check_rlast_position;
    input integer expected_beats;
    input [127:0] test_label;  // unused, chỉ để readable
    integer j;
    begin
        for (j = 0; j < expected_beats - 1; j = j + 1) begin
            if (blast[j] !== 1'b0) begin
                $display("  [FAIL-RLAST] RLAST sớm tại beat[%0d] — BUG3 RLAST gate hoặc BUG1/2",j);
                fail_cnt = fail_cnt + 1;
            end
        end
        if (blast[expected_beats-1] !== 1'b1) begin
            $display("  [FAIL-RLAST] RLAST không có ở beat[%0d] — IMEM FSM sai", expected_beats-1);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ============================================================================
// Main test
// ============================================================================
initial begin
    pass_cnt = 0; fail_cnt = 0; cyc = 0;
    m0_arid = 0; m0_araddr = 0; m0_arlen = 0;
    m0_arsize = 3'b010; m0_arburst = 2'b01;
    m0_arvalid = 0; m0_rready = 0;

    $readmemh("cpu/memory_axi4full/program.hex", ref_mem);

    $display("");
    $display("================================================================");
    $display("  tb_xbar_burst — AXI4 Crossbar + Master Mux Burst Debug TB");
    $display("  Verify 3 bugs fixed:");
    $display("  BUG1 mux line 295: m0_rlast = s_rlast (ungated)");
    $display("  BUG2 mux line 172: if/if race rd_burst_active");
    $display("  BUG3 xbar line 397: RLAST OR bus ungated");
    $display("================================================================");

    // Reset
    rst_n = 0;
    repeat(8) @(posedge clk);
    @(negedge clk); rst_n = 1;
    repeat(4) @(posedge clk);

    // =========================================================================
    // T1: 1-beat read baseline
    //   Pass nếu: bi=1, data=ref[0], resp=OKAY, rlast=1
    // =========================================================================
    $display("\n[T1] 1-beat read @ 0x0000_0000 (baseline)");
    do_burst(4'h1, 32'h0, 8'd0);
    if (bi == 1 && bdata[0] === ref_mem[0] && bresp[0] == 2'b00 && blast[0] == 1'b1) begin
        $display("  [PASS] data=0x%08h resp=OKAY rlast=%b", bdata[0], blast[0]);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  [FAIL] bi=%0d data=0x%08h exp=0x%08h resp=%0b rlast=%b",
                 bi, bdata[0], ref_mem[0], bresp[0], blast[0]);
        fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // T2: 8-beat burst — KEY TEST cho BUG1+BUG2+BUG3
    //   Pass nếu: bi=8, data đúng, RLAST chỉ ở beat[7], không có RLAST sớm
    // =========================================================================
    $display("\n[T2] 8-beat burst @ 0x0000_0000 (ARLEN=7) — KEY BUG TEST");
    do_burst(4'h2, 32'h0, 8'd7);
    $display("  Nhận %0d beat(s) (cần 8)", bi);

    if (bi == 8) begin
        begin : blk_t2_data
            integer j; reg all_ok;
            all_ok = 1;
            for (j = 0; j < 8; j = j + 1) begin
                if (bdata[j] !== ref_mem[j] || bresp[j] !== 2'b00) begin
                    $display("  [FAIL] beat[%0d] data=0x%08h exp=0x%08h resp=%0b",
                             j, bdata[j], ref_mem[j], bresp[j]);
                    all_ok = 0; fail_cnt = fail_cnt + 1;
                end else
                    $display("  beat[%0d] 0x%08h last=%b ✓", j, bdata[j], blast[j]);
            end
            if (all_ok) begin
                $display("  [PASS] Tất cả 8 beats data đúng");
                pass_cnt = pass_cnt + 1;
            end
        end
        check_rlast_position(8, "T2");
        if (blast[7] == 1'b1 && blast[6] == 1'b0) begin
            $display("  [PASS] RLAST đúng vị trí beat[7]");
            pass_cnt = pass_cnt + 1;
        end
    end else begin
        $display("  [FAIL] Nhận %0d beat ≠ 8", bi);
        $display("  Nguyên nhân có thể: BUG2 rd_burst_active race hoặc BUG3 RLAST OR");
        begin : blk_t2_dump
            integer j;
            for (j = 0; j < bi; j = j + 1)
                $display("  dump beat[%0d] data=0x%08h last=%b resp=%0b",
                         j, bdata[j], blast[j], bresp[j]);
        end
        fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // T3: State pollution — 1-beat rồi ngay 8-beat
    //   Nếu BUG2 vẫn còn: rd_burst_active sau 1-beat sai → 8-beat sẽ fail
    // =========================================================================
    $display("\n[T3] State pollution: 1-beat @ 0x4 rồi ngay 8-beat @ 0x0");
    do_burst(4'h3, 32'h0000_0004, 8'd0);  // 1-beat
    if (bi == 1 && bdata[0] === ref_mem[1])
        $display("  1-beat [OK] data=0x%08h", bdata[0]);
    else begin
        $display("  1-beat [FAIL] bi=%0d data=0x%08h exp=0x%08h", bi, bdata[0], ref_mem[1]);
        fail_cnt = fail_cnt + 1;
    end
    // Không thêm delay — kiểm tra FSM tự reset đúng
    do_burst(4'h4, 32'h0000_0000, 8'd7);  // 8-beat ngay sau
    if (bi == 8) begin
        $display("  8-beat [PASS] nhận đủ 8 beats sau 1-beat — không bị state pollution");
        pass_cnt = pass_cnt + 1;
        check_rlast_position(8, "T3");
    end else begin
        $display("  8-beat [FAIL] nhận %0d beat ≠ 8 — BUG2 rd_burst_active vẫn còn!", bi);
        fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // T4: 8-beat tại offset 0x20 (cache line 1)
    //   Verify address decode + IMEM burst từ offset
    // =========================================================================
    $display("\n[T4] 8-beat burst @ 0x0000_0020 (cache line 1)");
    do_burst(4'h5, 32'h0000_0020, 8'd7);
    if (bi == 8) begin
        begin : blk_t4
            integer j; reg all_ok;
            all_ok = 1;
            for (j = 0; j < 8; j = j + 1) begin
                if (bdata[j] !== ref_mem[8+j] || bresp[j] !== 2'b00) begin
                    $display("  [FAIL] beat[%0d] data=0x%08h exp=0x%08h",
                             j, bdata[j], ref_mem[8+j]);
                    all_ok = 0; fail_cnt = fail_cnt + 1;
                end else
                    $display("  beat[%0d] 0x%08h last=%b ✓", j, bdata[j], blast[j]);
            end
            if (all_ok) begin
                $display("  [PASS] 8 beats data đúng tại offset 0x20");
                pass_cnt = pass_cnt + 1;
            end
        end
        check_rlast_position(8, "T4");
    end else begin
        $display("  [FAIL] Nhận %0d beat ≠ 8", bi); fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // T5: Stress — 5 lần 8-beat liên tiếp
    //   Verify FSM tự reset sau mỗi burst, không stuck
    // =========================================================================
    $display("\n[T5] Stress: 5 lần 8-beat burst liên tiếp");
    begin : blk_t5
        integer round; reg stress_ok;
        stress_ok = 1;
        for (round = 0; round < 5; round = round + 1) begin
            do_burst(4'h6, 32'h0000_0000, 8'd7);
            if (bi == 8) begin
                $display("  round[%0d] [OK] 8 beats ✓", round);
            end else begin
                $display("  round[%0d] [FAIL] nhận %0d beat ≠ 8", round, bi);
                stress_ok = 0; fail_cnt = fail_cnt + 1;
            end
        end
        if (stress_ok) begin
            $display("  [PASS] Tất cả 5 round đều đủ 8 beats");
            pass_cnt = pass_cnt + 1;
        end
    end

    // =========================================================================
    // T6: RLAST early detection — 4-beat burst, verify RLAST không ở beat[0..2]
    //   Bắt BUG1+BUG3 nếu vẫn còn: RLAST sẽ xuất hiện ở beat[0]
    // =========================================================================
    $display("\n[T6] RLAST early detection: 4-beat burst @ 0x0");
    do_burst(4'h7, 32'h0, 8'd3);
    if (bi == 4) begin
        $display("  Nhận đủ 4 beats");
        check_rlast_position(4, "T6");
        begin : blk_t6
            integer j; reg rlast_ok;
            rlast_ok = 1;
            for (j = 0; j < 4; j = j + 1) begin
                $display("  beat[%0d] data=0x%08h last=%b", j, bdata[j], blast[j]);
                if (j < 3 && blast[j] == 1'b1) rlast_ok = 0;
            end
            if (rlast_ok) begin
                $display("  [PASS] RLAST chỉ ở beat[3] — BUG1+BUG3 đã fix");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] RLAST xuất hiện sớm — BUG1 hoặc BUG3 vẫn còn!");
                fail_cnt = fail_cnt + 1;
            end
        end
    end else begin
        $display("  [FAIL] Nhận %0d beat ≠ 4", bi); fail_cnt = fail_cnt + 1;
    end

    // =========================================================================
    // Summary
    // =========================================================================
    repeat(5) @(posedge clk);
    $display("");
    $display("================================================================");
    $display("  KẾT QUẢ CUỐI: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) begin
        $display("  ✓ ALL PASS — 3 bugs đã được fix hoàn toàn");
        $display("  Sẵn sàng chạy run_soc_imem.v với ICache");
    end else begin
        $display("  ✗ VẪN CÒN LỖI — xem log và VCD bên trên");
        $display("");
        $display("  Hướng dẫn debug:");
        $display("  T2 fail bi<8        → BUG2 rd_burst_active race (mux line 172-184)");
        $display("  T2 RLAST sớm        → BUG1 (mux line 295) + BUG3 (xbar line 397)");
        $display("  T3 8-beat fail      → BUG2 FSM state không reset sau 1-beat");
        $display("  T6 RLAST beat[0..2] → BUG1 m0_rlast ungated hoặc BUG3 OR bus");
        $display("  Data sai            → inst_mem.v address decode sai");
    end
    $display("================================================================");
    $finish;
end

endmodule