`timescale 1ns/1ps

`timescale 1ns/1ps
// ============================================================================
// run_soc_imem.v — CPU fetch liên tục, log data flow theo từng tầng
//
// Không chia phase. Chỉ monitor:
//   [IMEM→XB]  : data ra khỏi IMEM
//   [XB→IC ]   : data vào ICache sau crossbar
//   [IC→CPU]   : instruction delivered cho CPU
//   AR IC→XB   : ICache gửi refill request
//   AR XB→MEM  : crossbar forward xuống IMEM
//
// Dừng khi: gặp EBREAK (0x00100073) hoặc 8 NOP liên tiếp hoặc timeout
//
// Compile:
//   iverilog -g2005 -o run_soc_imem.vvp cpu/tb/run_soc_imem.v
//   vvp run_soc_imem.vvp
// ============================================================================

// `include "cpu/memory_axi4full/inst_mem_axi_slave.v"
// `include "cpu/interconnect/axi4_crossbar.v"
// `include "cpu/interface/icache/icache_top.v"
`include "cpu/cpu_core.v"
`define CLK_PERIOD  10
`define TIMEOUT_CYC 5000
`define ID_W        4

module tb_run_soc_imem;

// ============================================================================
// Clock / Reset
// ============================================================================
reg clk, rst_n;
integer cyc;

initial  clk = 0;
always #(`CLK_PERIOD/2) clk = ~clk;
always @(posedge clk) if (rst_n) cyc = cyc + 1;

initial begin
    #(`CLK_PERIOD * `TIMEOUT_CYC);
    $display("[%4d] TIMEOUT — treo sau %0d cycle", cyc, `TIMEOUT_CYC);
    $finish;
end

// ============================================================================
// VCD
// ============================================================================
initial begin
    $dumpfile("tb_run_soc_imem.vcd");
    $dumpvars(0, tb_run_soc_imem);
end

// ============================================================================
// Reference memory
// ============================================================================
reg [31:0] ref_mem [0:1023];

// ============================================================================
// CPU-side signals
// ============================================================================
reg  [31:0] cpu_addr;
reg         cpu_req;
wire [31:0] cpu_rdata;
wire        cpu_ready;

// ============================================================================
// ICache ↔ Crossbar (M0)
// ============================================================================
wire [`ID_W-1:0] ic_arid,  ic_awid,  ic_rid,  ic_bid;
wire [31:0]  ic_araddr, ic_awaddr, ic_rdata, ic_wdata;
wire [7:0]   ic_arlen,  ic_awlen;
wire [2:0]   ic_arsize, ic_awsize, ic_arprot, ic_awprot;
wire [1:0]   ic_arburst,ic_awburst,ic_rresp, ic_bresp;
wire         ic_arvalid,ic_arready,ic_rvalid,ic_rready,ic_rlast;
wire         ic_awvalid,ic_awready,ic_wvalid,ic_wready,ic_wlast;
wire         ic_bvalid, ic_bready;
wire [3:0]   ic_wstrb;

// ============================================================================
// S0 (IMEM)
// ============================================================================
wire [`ID_W-1:0] s0_arid, s0_awid, s0_rid, s0_bid;
wire [31:0]  s0_araddr, s0_awaddr, s0_rdata, s0_wdata;
wire [7:0]   s0_arlen,  s0_awlen;
wire [2:0]   s0_arsize, s0_awsize, s0_arprot, s0_awprot;
wire [1:0]   s0_arburst,s0_awburst,s0_rresp, s0_bresp;
wire         s0_arvalid,s0_arready,s0_rvalid,s0_rready,s0_rlast;
wire         s0_awvalid,s0_awready,s0_wvalid,s0_wready,s0_wlast;
wire         s0_bvalid, s0_bready;
wire [3:0]   s0_wstrb;

// ============================================================================
// Stub S1/S2/S3 — instant SLVERR, không làm gì
// ============================================================================
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
// IMEM
// ============================================================================
inst_mem_axi_slave #(
    .ID_WIDTH(`ID_W), .MEM_SIZE(4096),
    .MEM_INIT_FILE("cpu/memory_axi4full/program.hex")
) u_imem (
    .clk(clk), .rst_n(rst_n),
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
// Crossbar
// ============================================================================
axi4_crossbar #(.ID_WIDTH(`ID_W)) u_xbar (
    .clk(clk), .rst_n(rst_n),
    .M0_AXI_ARID(ic_arid),    .M0_AXI_ARADDR(ic_araddr),  .M0_AXI_ARLEN(ic_arlen),
    .M0_AXI_ARSIZE(ic_arsize),.M0_AXI_ARBURST(ic_arburst),.M0_AXI_ARPROT(ic_arprot),
    .M0_AXI_ARVALID(ic_arvalid),.M0_AXI_ARREADY(ic_arready),
    .M0_AXI_RID(ic_rid),      .M0_AXI_RDATA(ic_rdata),    .M0_AXI_RRESP(ic_rresp),
    .M0_AXI_RLAST(ic_rlast),  .M0_AXI_RVALID(ic_rvalid),  .M0_AXI_RREADY(ic_rready),
    .M0_AXI_AWID(ic_awid),    .M0_AXI_AWADDR(ic_awaddr),  .M0_AXI_AWLEN(ic_awlen),
    .M0_AXI_AWSIZE(ic_awsize),.M0_AXI_AWBURST(ic_awburst),.M0_AXI_AWPROT(ic_awprot),
    .M0_AXI_AWVALID(ic_awvalid),.M0_AXI_AWREADY(ic_awready),
    .M0_AXI_WDATA(ic_wdata),  .M0_AXI_WSTRB(ic_wstrb),    .M0_AXI_WLAST(ic_wlast),
    .M0_AXI_WVALID(ic_wvalid),.M0_AXI_WREADY(ic_wready),
    .M0_AXI_BID(ic_bid),      .M0_AXI_BRESP(ic_bresp),    .M0_AXI_BVALID(ic_bvalid),
    .M0_AXI_BREADY(ic_bready),
    .M1_AXI_ARID(4'h0),  .M1_AXI_ARADDR(32'h0), .M1_AXI_ARLEN(8'h0),
    .M1_AXI_ARSIZE(3'h2),.M1_AXI_ARBURST(2'b01),.M1_AXI_ARPROT(3'h0),
    .M1_AXI_ARVALID(1'b0),.M1_AXI_ARREADY(),
    .M1_AXI_RID(),.M1_AXI_RDATA(),.M1_AXI_RRESP(),.M1_AXI_RLAST(),
    .M1_AXI_RVALID(),.M1_AXI_RREADY(1'b1),
    .M1_AXI_AWID(4'h0),.M1_AXI_AWADDR(32'h0),.M1_AXI_AWLEN(8'h0),
    .M1_AXI_AWSIZE(3'h2),.M1_AXI_AWBURST(2'b01),.M1_AXI_AWPROT(3'h0),
    .M1_AXI_AWVALID(1'b0),.M1_AXI_AWREADY(),
    .M1_AXI_WDATA(32'h0),.M1_AXI_WSTRB(4'h0),.M1_AXI_WLAST(1'b0),
    .M1_AXI_WVALID(1'b0),.M1_AXI_WREADY(),
    .M1_AXI_BID(),.M1_AXI_BRESP(),.M1_AXI_BVALID(),.M1_AXI_BREADY(1'b1),
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
    .S1_AXI_ARID(s1_arid),.S1_AXI_ARADDR(s1_araddr),.S1_AXI_ARLEN(s1_arlen),
    .S1_AXI_ARSIZE(s1_arsize),.S1_AXI_ARBURST(s1_arburst),.S1_AXI_ARPROT(s1_arprot),
    .S1_AXI_ARVALID(s1_arvalid),.S1_AXI_ARREADY(s1_arready),
    .S1_AXI_RID(s1_rid),.S1_AXI_RDATA(s1_rdata),.S1_AXI_RRESP(s1_rresp),
    .S1_AXI_RLAST(s1_rlast),.S1_AXI_RVALID(s1_rvalid),.S1_AXI_RREADY(s1_rready),
    .S1_AXI_AWID(s1_awid),.S1_AXI_AWADDR(s1_awaddr),.S1_AXI_AWLEN(s1_awlen),
    .S1_AXI_AWSIZE(s1_awsize),.S1_AXI_AWBURST(s1_awburst),.S1_AXI_AWPROT(s1_awprot),
    .S1_AXI_AWVALID(s1_awvalid),.S1_AXI_AWREADY(s1_awready),
    .S1_AXI_WDATA(s1_wdata),.S1_AXI_WSTRB(s1_wstrb),.S1_AXI_WLAST(s1_wlast),
    .S1_AXI_WVALID(s1_wvalid),.S1_AXI_WREADY(s1_wready),
    .S1_AXI_BID(s1_bid),.S1_AXI_BRESP(s1_bresp),.S1_AXI_BVALID(s1_bvalid),
    .S1_AXI_BREADY(s1_bready),
    .S2_AXI_ARID(s2_arid),.S2_AXI_ARADDR(s2_araddr),.S2_AXI_ARLEN(s2_arlen),
    .S2_AXI_ARSIZE(s2_arsize),.S2_AXI_ARBURST(s2_arburst),.S2_AXI_ARPROT(s2_arprot),
    .S2_AXI_ARVALID(s2_arvalid),.S2_AXI_ARREADY(s2_arready),
    .S2_AXI_RID(s2_rid),.S2_AXI_RDATA(s2_rdata),.S2_AXI_RRESP(s2_rresp),
    .S2_AXI_RLAST(s2_rlast),.S2_AXI_RVALID(s2_rvalid),.S2_AXI_RREADY(s2_rready),
    .S2_AXI_AWID(s2_awid),.S2_AXI_AWADDR(s2_awaddr),.S2_AXI_AWLEN(s2_awlen),
    .S2_AXI_AWSIZE(s2_awsize),.S2_AXI_AWBURST(s2_awburst),.S2_AXI_AWPROT(s2_awprot),
    .S2_AXI_AWVALID(s2_awvalid),.S2_AXI_AWREADY(s2_awready),
    .S2_AXI_WDATA(s2_wdata),.S2_AXI_WSTRB(s2_wstrb),.S2_AXI_WLAST(s2_wlast),
    .S2_AXI_WVALID(s2_wvalid),.S2_AXI_WREADY(s2_wready),
    .S2_AXI_BID(s2_bid),.S2_AXI_BRESP(s2_bresp),.S2_AXI_BVALID(s2_bvalid),
    .S2_AXI_BREADY(s2_bready),
    .S3_AXI_ARID(s3_arid),.S3_AXI_ARADDR(s3_araddr),.S3_AXI_ARLEN(s3_arlen),
    .S3_AXI_ARSIZE(s3_arsize),.S3_AXI_ARBURST(s3_arburst),.S3_AXI_ARPROT(s3_arprot),
    .S3_AXI_ARVALID(s3_arvalid),.S3_AXI_ARREADY(s3_arready),
    .S3_AXI_RID(s3_rid),.S3_AXI_RDATA(s3_rdata),.S3_AXI_RRESP(s3_rresp),
    .S3_AXI_RLAST(s3_rlast),.S3_AXI_RVALID(s3_rvalid),.S3_AXI_RREADY(s3_rready),
    .S3_AXI_AWID(s3_awid),.S3_AXI_AWADDR(s3_awaddr),.S3_AXI_AWLEN(s3_awlen),
    .S3_AXI_AWSIZE(s3_awsize),.S3_AXI_AWBURST(s3_awburst),.S3_AXI_AWPROT(s3_awprot),
    .S3_AXI_AWVALID(s3_awvalid),.S3_AXI_AWREADY(s3_awready),
    .S3_AXI_WDATA(s3_wdata),.S3_AXI_WSTRB(s3_wstrb),.S3_AXI_WLAST(s3_wlast),
    .S3_AXI_WVALID(s3_wvalid),.S3_AXI_WREADY(s3_wready),
    .S3_AXI_BID(s3_bid),.S3_AXI_BRESP(s3_bresp),.S3_AXI_BVALID(s3_bvalid),
    .S3_AXI_BREADY(s3_bready)
);

// ============================================================================
// ICache
// ============================================================================
icache_top #(.ID_WIDTH(`ID_W)) u_icache (
    .clk(clk), .rst_n(rst_n),
    .cpu_addr(cpu_addr), .cpu_req(cpu_req),
    .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
    .flush(1'b0),
    .mem_arid(ic_arid),    .mem_araddr(ic_araddr),  .mem_arlen(ic_arlen),
    .mem_arsize(ic_arsize),.mem_arburst(ic_arburst),.mem_arprot(ic_arprot),
    .mem_arvalid(ic_arvalid),.mem_arready(ic_arready),
    .mem_rid(ic_rid),      .mem_rdata(ic_rdata),    .mem_rresp(ic_rresp),
    .mem_rlast(ic_rlast),  .mem_rvalid(ic_rvalid),  .mem_rready(ic_rready),
    .mem_awid(ic_awid),    .mem_awaddr(ic_awaddr),  .mem_awlen(ic_awlen),
    .mem_awsize(ic_awsize),.mem_awburst(ic_awburst),.mem_awprot(ic_awprot),
    .mem_awvalid(ic_awvalid),.mem_awready(ic_awready),
    .mem_wdata(ic_wdata),  .mem_wstrb(ic_wstrb),    .mem_wlast(ic_wlast),
    .mem_wvalid(ic_wvalid),.mem_wready(ic_wready),
    .mem_bid(ic_bid),      .mem_bresp(ic_bresp),    .mem_bvalid(ic_bvalid),
    .mem_bready(ic_bready),
    .stat_hits(), .stat_misses()
);

// ============================================================================
// Monitor — log data đi qua từng tầng mỗi khi có handshake
// ============================================================================
always @(posedge clk) begin

    // AR: ICache gửi refill request lên crossbar
    if (ic_arvalid && ic_arready)
        $display("[%4d] AR  IC->XB   addr=0x%08h  len=%0d",
                 cyc, ic_araddr, ic_arlen + 1);

    // AR: Crossbar forward xuống IMEM
    if (s0_arvalid && s0_arready)
        $display("[%4d] AR  XB->MEM  addr=0x%08h  len=%0d",
                 cyc, s0_araddr, s0_arlen + 1);

    // R beat: IMEM trả data lên crossbar
    if (s0_rvalid && s0_rready)
        $display("[%4d] R   IMEM->XB data=0x%08h  last=%b  ok=%b",
                 cyc, s0_rdata, s0_rlast, (s0_rresp == 2'b00));

    // R beat: Crossbar trả data xuống ICache
    if (ic_rvalid && ic_rready)
        $display("[%4d] R   XB->IC   data=0x%08h  last=%b  ok=%b",
                 cyc, ic_rdata, ic_rlast, (ic_rresp == 2'b00));

    // CPU nhận instruction từ ICache
    if (cpu_ready && cpu_req)
        $display("[%4d] >>> IC->CPU  PC=0x%08h  instr=0x%08h  exp=0x%08h  %s",
                 cyc, cpu_addr, cpu_rdata, ref_mem[cpu_addr[11:2]],
                 (cpu_rdata === ref_mem[cpu_addr[11:2]]) ? "OK" : "MISMATCH <<<");

end

// ============================================================================
// CPU model — fetch tuần tự, tăng PC khi nhận xong
// Dừng khi: EBREAK, 8 NOP liên tiếp, hoặc timeout
// ============================================================================
integer nop_streak;

initial begin
    $readmemh("cpu/memory_axi4full/program.hex", ref_mem);

    $display("");
    $display("========================================================");
    $display("  run_soc_imem  |  Data flow: IMEM -> XBar -> ICache -> CPU");
    $display("  AR IC->XB   : ICache gửi refill request");
    $display("  AR XB->MEM  : Crossbar forward xuống IMEM");
    $display("  R  IMEM->XB : Data ra khỏi IMEM");
    $display("  R  XB->IC   : Data vào ICache");
    $display("  >> IC->CPU  : Instruction đến CPU, OK/MISMATCH");
    $display("========================================================");
    $display("");

    cyc        = 0;
    nop_streak = 0;
    cpu_addr   = 32'h0;
    cpu_req    = 1'b0;

    rst_n = 0;
    repeat(8) @(posedge clk);
    @(negedge clk); rst_n = 1;
    repeat(4) @(posedge clk);

    // Fetch loop
    forever begin
        @(negedge clk);
        cpu_addr = cpu_addr;   // giữ nguyên PC
        cpu_req  = 1'b1;

        // Chờ ICache ready
        @(posedge clk);
        while (!cpu_ready) @(posedge clk);

        // Kiểm tra điều kiện dừng
        if (cpu_rdata == 32'h00100073) begin
            $display("[%4d] EBREAK tại PC=0x%08h — kết thúc", cyc, cpu_addr);
            @(negedge clk); cpu_req = 1'b0;
            repeat(5) @(posedge clk);
            $finish;
        end

        if (cpu_rdata == 32'h00000013) nop_streak = nop_streak + 1;
        else                           nop_streak = 0;

        if (nop_streak >= 8) begin
            $display("[%4d] 8 NOP liên tiếp tại PC=0x%08h — dừng", cyc, cpu_addr);
            @(negedge clk); cpu_req = 1'b0;
            repeat(5) @(posedge clk);
            $finish;
        end

        // Tăng PC
        @(negedge clk);
        cpu_req  = 1'b0;
        cpu_addr = cpu_addr + 4;
        @(posedge clk);   // 1 cycle gap trước fetch tiếp theo
    end
end

endmodule