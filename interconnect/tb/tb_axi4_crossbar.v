`timescale 1ns/1ps

// =============================================================================
// tb_axi4_crossbar.v  —  Testbench for axi4_crossbar_5m12s
//
// DUT  : axi4_crossbar_5m12s (5 masters x 12 slaves, SoC address map)
//
// Address map (default parameters):
//   S0  IMEM      0x0000_0000
//   S1  DMEM      0x1000_0000
//   S2  ASCON     0x2000_0000
//   S3  SOC_CTRL  0x3000_0000
//   S4  CLINT     0x4000_0000
//   S5  UART      0x5000_0000
//   S6  GPIO      0x5001_0000
//   S7  SPI       0x5002_0000
//   S8  Timer/WDT 0x5003_0000
//   S9  PLIC      0x5004_0000
//   S10 OTP       0x6000_0000
//   S11 DMA_CTRL  0x6001_0000
//   ERR unmapped  (any other address)
//
// Test cases (per test_plan.md A5):
//   TC-M0-S0   : M0 (ICache) read -> IMEM S0 — routing correct
//   TC-M1-S1r  : M1 (DCache) read -> DMEM S1 — routing correct
//   TC-M1-S1w  : M1 write   -> DMEM S1 — BRESP=OKAY
//   TC-M0-S5   : M0 read    -> UART S5 — peripheral routing
//   TC-M0-S11  : M0 read    -> DMA_CTRL S11 — peripheral routing
//   TC-BURST   : M1 burst4  -> DMEM S1 — all beats, RLAST correct
//   TC-BID     : BID echoes AWID
//   TC-RID     : RID echoes ARID
//   TC-ARBIT   : M0 and M3 simultaneous to S0 — both served, no deadlock
//   TC-DECODE  : Unmapped 0x9000_0000 -> DECERR read
//   TC-DECODEW : Unmapped 0x8000_0000 -> DECERR write
//
// Run:
//   ~/workflow/urun_verilog.sh interconnect/tb/tb_axi4_crossbar.v
//   rtk read interconnect/tb/tb_axi4_crossbar.log
// =============================================================================

`include "interconnect/axi4_crossbar_5m12s.v"

// =============================================================================
// Parameterized AXI4 slave stub
// Responds to reads with rdata[31:24]=SLAVE_ID, [23:16]=beat_index, [15:0]=araddr[15:0]
// Responds to writes with BRESP=OKAY
// =============================================================================
module axi4_slave_stub #(
    parameter ID_W     = 4,
    parameter DW       = 32,
    parameter SLAVE_ID = 0
)(
    input  wire            clk,
    input  wire            rst_n,

    input  wire [ID_W-1:0] arid,
    input  wire [31:0]     araddr,
    input  wire [7:0]      arlen,
    input  wire [2:0]      arsize,
    input  wire [1:0]      arburst,
    input  wire [2:0]      arprot,
    input  wire            arvalid,
    output reg             arready,

    output reg [ID_W-1:0]  rid,
    output reg [DW-1:0]    rdata,
    output reg [1:0]       rresp,
    output reg             rlast,
    output reg             rvalid,
    input  wire            rready,

    input  wire [ID_W-1:0] awid,
    input  wire [31:0]     awaddr,
    input  wire [7:0]      awlen,
    input  wire [2:0]      awsize,
    input  wire [1:0]      awburst,
    input  wire [2:0]      awprot,
    input  wire            awvalid,
    output reg             awready,

    input  wire [DW-1:0]   wdata,
    input  wire [DW/8-1:0] wstrb,
    input  wire            wlast,
    input  wire            wvalid,
    output reg             wready,

    output reg [ID_W-1:0]  bid,
    output reg [1:0]       bresp,
    output reg             bvalid,
    input  wire            bready
);

// Read channel state
reg [ID_W-1:0] r_arid_lat;
reg [31:0]     r_araddr_lat;
reg [7:0]      r_arlen_lat;
reg [7:0]      r_beat;
reg            r_active;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arready   <= 1'b1;
        rvalid    <= 1'b0; rlast <= 1'b0;
        rdata     <= 0; rid <= 0; rresp <= 2'b00;
        r_active  <= 1'b0; r_beat <= 0;
        r_arid_lat <= 0; r_araddr_lat <= 0; r_arlen_lat <= 0;
    end else begin
        if (arvalid && arready) begin
            r_arid_lat   <= arid;
            r_araddr_lat <= araddr;
            r_arlen_lat  <= arlen;
            r_beat       <= 8'h0;
            r_active     <= 1'b1;
            arready      <= 1'b0;
        end

        if (r_active) begin
            if (!rvalid || rready) begin
                rvalid <= 1'b1;
                rid    <= r_arid_lat;
                rresp  <= 2'b00;
                rdata  <= {SLAVE_ID[7:0], r_beat[7:0], r_araddr_lat[15:0]};
                rlast  <= (r_beat == r_arlen_lat);
                if (r_beat == r_arlen_lat) begin
                    r_active <= 1'b0;
                    arready  <= 1'b1;
                end else begin
                    r_beat <= r_beat + 1;
                end
            end
        end else if (rvalid && rready && rlast) begin
            rvalid <= 1'b0;
            rlast  <= 1'b0;
        end
    end
end

// Write channel state
reg [ID_W-1:0] w_awid_lat;
reg            w_aw_lat;
reg            w_done;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        awready  <= 1'b1; wready <= 1'b1;
        bvalid   <= 1'b0; bid <= 0; bresp <= 2'b00;
        w_aw_lat <= 1'b0; w_done <= 1'b0; w_awid_lat <= 0;
    end else begin
        if (awvalid && awready) begin
            w_awid_lat <= awid;
            w_aw_lat   <= 1'b1;
            awready    <= 1'b0;
        end
        if (wvalid && wready && wlast) begin
            w_done <= 1'b1;
            wready <= 1'b0;
        end
        if (w_aw_lat && w_done && !bvalid) begin
            bvalid   <= 1'b1;
            bid      <= w_awid_lat;
            bresp    <= 2'b00;
            w_aw_lat <= 1'b0;
            w_done   <= 1'b0;
        end
        if (bvalid && bready) begin
            bvalid  <= 1'b0;
            awready <= 1'b1;
            wready  <= 1'b1;
        end
    end
end

endmodule // axi4_slave_stub


// =============================================================================
// Testbench top
// =============================================================================
module tb_axi4_crossbar;

localparam ID_W = 4;
localparam DW   = 32;
localparam AW   = 32;
localparam SW   = DW/8;

// ---------------------------------------------------------------------------
// Clock & reset
// ---------------------------------------------------------------------------
reg clk, rst_n;
initial clk = 0;
always #5 clk = ~clk;

// ---------------------------------------------------------------------------
// Master signals
// ---------------------------------------------------------------------------
// M0 (ICache)
reg  [ID_W-1:0] m0_arid,m0_awid;   reg  [AW-1:0]  m0_araddr,m0_awaddr;
reg  [7:0]      m0_arlen,m0_awlen; reg  [2:0]     m0_arsize,m0_awsize;
reg  [1:0]      m0_arburst,m0_awburst; reg  [2:0] m0_arprot,m0_awprot;
reg             m0_arvalid,m0_awvalid,m0_rready,m0_bready,m0_wvalid,m0_wlast;
reg  [DW-1:0]   m0_wdata; reg [SW-1:0] m0_wstrb;
wire            m0_arready,m0_rvalid,m0_rlast,m0_awready,m0_wready,m0_bvalid;
wire [ID_W-1:0] m0_rid,m0_bid;
wire [DW-1:0]   m0_rdata; wire [1:0] m0_rresp,m0_bresp;

// M1 (DCache)
reg  [ID_W-1:0] m1_arid,m1_awid;   reg  [AW-1:0]  m1_araddr,m1_awaddr;
reg  [7:0]      m1_arlen,m1_awlen; reg  [2:0]     m1_arsize,m1_awsize;
reg  [1:0]      m1_arburst,m1_awburst; reg  [2:0] m1_arprot,m1_awprot;
reg             m1_arvalid,m1_awvalid,m1_rready,m1_bready,m1_wvalid,m1_wlast;
reg  [DW-1:0]   m1_wdata; reg [SW-1:0] m1_wstrb;
wire            m1_arready,m1_rvalid,m1_rlast,m1_awready,m1_wready,m1_bvalid;
wire [ID_W-1:0] m1_rid,m1_bid;
wire [DW-1:0]   m1_rdata; wire [1:0] m1_rresp,m1_bresp;

// M2 (ASCON DMA) — tied inactive
reg [ID_W-1:0] m2_arid=0,m2_awid=0; reg [AW-1:0] m2_araddr=0,m2_awaddr=0;
reg [7:0] m2_arlen=0,m2_awlen=0; reg [2:0] m2_arsize=3'b010,m2_awsize=3'b010;
reg [1:0] m2_arburst=2'b01,m2_awburst=2'b01; reg [2:0] m2_arprot=0,m2_awprot=0;
reg m2_arvalid=0,m2_awvalid=0,m2_rready=1,m2_bready=1,m2_wvalid=0,m2_wlast=1;
reg [DW-1:0] m2_wdata=0; reg [SW-1:0] m2_wstrb=4'hF;
wire m2_arready,m2_rvalid,m2_rlast,m2_awready,m2_wready,m2_bvalid;
wire [ID_W-1:0] m2_rid,m2_bid; wire [DW-1:0] m2_rdata; wire [1:0] m2_rresp,m2_bresp;

// M3 (GP-DMA) — used for arbitration test
reg  [ID_W-1:0] m3_arid,m3_awid;   reg  [AW-1:0]  m3_araddr,m3_awaddr;
reg  [7:0]      m3_arlen,m3_awlen; reg  [2:0]     m3_arsize,m3_awsize;
reg  [1:0]      m3_arburst,m3_awburst; reg  [2:0] m3_arprot,m3_awprot;
reg             m3_arvalid,m3_awvalid,m3_rready,m3_bready,m3_wvalid,m3_wlast;
reg  [DW-1:0]   m3_wdata; reg [SW-1:0] m3_wstrb;
wire            m3_arready,m3_rvalid,m3_rlast,m3_awready,m3_wready,m3_bvalid;
wire [ID_W-1:0] m3_rid,m3_bid;
wire [DW-1:0]   m3_rdata; wire [1:0] m3_rresp,m3_bresp;

// M4 (JTAG) — tied inactive
reg [ID_W-1:0] m4_arid=0,m4_awid=0; reg [AW-1:0] m4_araddr=0,m4_awaddr=0;
reg [7:0] m4_arlen=0,m4_awlen=0; reg [2:0] m4_arsize=3'b010,m4_awsize=3'b010;
reg [1:0] m4_arburst=2'b01,m4_awburst=2'b01; reg [2:0] m4_arprot=0,m4_awprot=0;
reg m4_arvalid=0,m4_awvalid=0,m4_rready=1,m4_bready=1,m4_wvalid=0,m4_wlast=1;
reg [DW-1:0] m4_wdata=0; reg [SW-1:0] m4_wstrb=4'hF;
wire m4_arready,m4_rvalid,m4_rlast,m4_awready,m4_wready,m4_bvalid;
wire [ID_W-1:0] m4_rid,m4_bid; wire [DW-1:0] m4_rdata; wire [1:0] m4_rresp,m4_bresp;

// ---------------------------------------------------------------------------
// Slave wires (S0..S11) — crossbar outputs to slave ports
// ---------------------------------------------------------------------------
wire [ID_W-1:0] s0_arid,s0_awid,s0_rid,s0_bid;
wire [AW-1:0]   s0_araddr,s0_awaddr;
wire [7:0]      s0_arlen,s0_awlen; wire [2:0] s0_arsize,s0_awsize;
wire [1:0]      s0_arburst,s0_awburst; wire [2:0] s0_arprot,s0_awprot;
wire            s0_arvalid,s0_arready,s0_awvalid,s0_awready;
wire [DW-1:0]   s0_rdata,s0_wdata; wire [SW-1:0] s0_wstrb;
wire [1:0]      s0_rresp,s0_bresp;
wire            s0_rlast,s0_rvalid,s0_rready,s0_wlast,s0_wvalid,s0_wready;
wire            s0_bvalid,s0_bready;

wire [ID_W-1:0] s1_arid,s1_awid,s1_rid,s1_bid;
wire [AW-1:0]   s1_araddr,s1_awaddr;
wire [7:0]      s1_arlen,s1_awlen; wire [2:0] s1_arsize,s1_awsize;
wire [1:0]      s1_arburst,s1_awburst; wire [2:0] s1_arprot,s1_awprot;
wire            s1_arvalid,s1_arready,s1_awvalid,s1_awready;
wire [DW-1:0]   s1_rdata,s1_wdata; wire [SW-1:0] s1_wstrb;
wire [1:0]      s1_rresp,s1_bresp;
wire            s1_rlast,s1_rvalid,s1_rready,s1_wlast,s1_wvalid,s1_wready;
wire            s1_bvalid,s1_bready;

wire [ID_W-1:0] s2_arid,s2_awid,s2_rid,s2_bid;
wire [AW-1:0]   s2_araddr,s2_awaddr;
wire [7:0]      s2_arlen,s2_awlen; wire [2:0] s2_arsize,s2_awsize;
wire [1:0]      s2_arburst,s2_awburst; wire [2:0] s2_arprot,s2_awprot;
wire            s2_arvalid,s2_arready,s2_awvalid,s2_awready;
wire [DW-1:0]   s2_rdata,s2_wdata; wire [SW-1:0] s2_wstrb;
wire [1:0]      s2_rresp,s2_bresp;
wire            s2_rlast,s2_rvalid,s2_rready,s2_wlast,s2_wvalid,s2_wready;
wire            s2_bvalid,s2_bready;

wire [ID_W-1:0] s3_arid,s3_awid,s3_rid,s3_bid;
wire [AW-1:0]   s3_araddr,s3_awaddr;
wire [7:0]      s3_arlen,s3_awlen; wire [2:0] s3_arsize,s3_awsize;
wire [1:0]      s3_arburst,s3_awburst; wire [2:0] s3_arprot,s3_awprot;
wire            s3_arvalid,s3_arready,s3_awvalid,s3_awready;
wire [DW-1:0]   s3_rdata,s3_wdata; wire [SW-1:0] s3_wstrb;
wire [1:0]      s3_rresp,s3_bresp;
wire            s3_rlast,s3_rvalid,s3_rready,s3_wlast,s3_wvalid,s3_wready;
wire            s3_bvalid,s3_bready;

wire [ID_W-1:0] s4_arid,s4_awid,s4_rid,s4_bid;
wire [AW-1:0]   s4_araddr,s4_awaddr;
wire [7:0]      s4_arlen,s4_awlen; wire [2:0] s4_arsize,s4_awsize;
wire [1:0]      s4_arburst,s4_awburst; wire [2:0] s4_arprot,s4_awprot;
wire            s4_arvalid,s4_arready,s4_awvalid,s4_awready;
wire [DW-1:0]   s4_rdata,s4_wdata; wire [SW-1:0] s4_wstrb;
wire [1:0]      s4_rresp,s4_bresp;
wire            s4_rlast,s4_rvalid,s4_rready,s4_wlast,s4_wvalid,s4_wready;
wire            s4_bvalid,s4_bready;

wire [ID_W-1:0] s5_arid,s5_awid,s5_rid,s5_bid;
wire [AW-1:0]   s5_araddr,s5_awaddr;
wire [7:0]      s5_arlen,s5_awlen; wire [2:0] s5_arsize,s5_awsize;
wire [1:0]      s5_arburst,s5_awburst; wire [2:0] s5_arprot,s5_awprot;
wire            s5_arvalid,s5_arready,s5_awvalid,s5_awready;
wire [DW-1:0]   s5_rdata,s5_wdata; wire [SW-1:0] s5_wstrb;
wire [1:0]      s5_rresp,s5_bresp;
wire            s5_rlast,s5_rvalid,s5_rready,s5_wlast,s5_wvalid,s5_wready;
wire            s5_bvalid,s5_bready;

wire [ID_W-1:0] s6_arid,s6_awid,s6_rid,s6_bid;
wire [AW-1:0]   s6_araddr,s6_awaddr;
wire [7:0]      s6_arlen,s6_awlen; wire [2:0] s6_arsize,s6_awsize;
wire [1:0]      s6_arburst,s6_awburst; wire [2:0] s6_arprot,s6_awprot;
wire            s6_arvalid,s6_arready,s6_awvalid,s6_awready;
wire [DW-1:0]   s6_rdata,s6_wdata; wire [SW-1:0] s6_wstrb;
wire [1:0]      s6_rresp,s6_bresp;
wire            s6_rlast,s6_rvalid,s6_rready,s6_wlast,s6_wvalid,s6_wready;
wire            s6_bvalid,s6_bready;

wire [ID_W-1:0] s7_arid,s7_awid,s7_rid,s7_bid;
wire [AW-1:0]   s7_araddr,s7_awaddr;
wire [7:0]      s7_arlen,s7_awlen; wire [2:0] s7_arsize,s7_awsize;
wire [1:0]      s7_arburst,s7_awburst; wire [2:0] s7_arprot,s7_awprot;
wire            s7_arvalid,s7_arready,s7_awvalid,s7_awready;
wire [DW-1:0]   s7_rdata,s7_wdata; wire [SW-1:0] s7_wstrb;
wire [1:0]      s7_rresp,s7_bresp;
wire            s7_rlast,s7_rvalid,s7_rready,s7_wlast,s7_wvalid,s7_wready;
wire            s7_bvalid,s7_bready;

wire [ID_W-1:0] s8_arid,s8_awid,s8_rid,s8_bid;
wire [AW-1:0]   s8_araddr,s8_awaddr;
wire [7:0]      s8_arlen,s8_awlen; wire [2:0] s8_arsize,s8_awsize;
wire [1:0]      s8_arburst,s8_awburst; wire [2:0] s8_arprot,s8_awprot;
wire            s8_arvalid,s8_arready,s8_awvalid,s8_awready;
wire [DW-1:0]   s8_rdata,s8_wdata; wire [SW-1:0] s8_wstrb;
wire [1:0]      s8_rresp,s8_bresp;
wire            s8_rlast,s8_rvalid,s8_rready,s8_wlast,s8_wvalid,s8_wready;
wire            s8_bvalid,s8_bready;

wire [ID_W-1:0] s9_arid,s9_awid,s9_rid,s9_bid;
wire [AW-1:0]   s9_araddr,s9_awaddr;
wire [7:0]      s9_arlen,s9_awlen; wire [2:0] s9_arsize,s9_awsize;
wire [1:0]      s9_arburst,s9_awburst; wire [2:0] s9_arprot,s9_awprot;
wire            s9_arvalid,s9_arready,s9_awvalid,s9_awready;
wire [DW-1:0]   s9_rdata,s9_wdata; wire [SW-1:0] s9_wstrb;
wire [1:0]      s9_rresp,s9_bresp;
wire            s9_rlast,s9_rvalid,s9_rready,s9_wlast,s9_wvalid,s9_wready;
wire            s9_bvalid,s9_bready;

wire [ID_W-1:0] s10_arid,s10_awid,s10_rid,s10_bid;
wire [AW-1:0]   s10_araddr,s10_awaddr;
wire [7:0]      s10_arlen,s10_awlen; wire [2:0] s10_arsize,s10_awsize;
wire [1:0]      s10_arburst,s10_awburst; wire [2:0] s10_arprot,s10_awprot;
wire            s10_arvalid,s10_arready,s10_awvalid,s10_awready;
wire [DW-1:0]   s10_rdata,s10_wdata; wire [SW-1:0] s10_wstrb;
wire [1:0]      s10_rresp,s10_bresp;
wire            s10_rlast,s10_rvalid,s10_rready,s10_wlast,s10_wvalid,s10_wready;
wire            s10_bvalid,s10_bready;

wire [ID_W-1:0] s11_arid,s11_awid,s11_rid,s11_bid;
wire [AW-1:0]   s11_araddr,s11_awaddr;
wire [7:0]      s11_arlen,s11_awlen; wire [2:0] s11_arsize,s11_awsize;
wire [1:0]      s11_arburst,s11_awburst; wire [2:0] s11_arprot,s11_awprot;
wire            s11_arvalid,s11_arready,s11_awvalid,s11_awready;
wire [DW-1:0]   s11_rdata,s11_wdata; wire [SW-1:0] s11_wstrb;
wire [1:0]      s11_rresp,s11_bresp;
wire            s11_rlast,s11_rvalid,s11_rready,s11_wlast,s11_wvalid,s11_wready;
wire            s11_bvalid,s11_bready;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
axi4_crossbar_5m12s #(
    .DATA_WIDTH(DW), .ADDR_WIDTH(AW), .ID_WIDTH(ID_W)
) dut (
    .clk(clk), .rst_n(rst_n),
    // M0
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
    .M0_AXI_BID(m0_bid), .M0_AXI_BRESP(m0_bresp),
    .M0_AXI_BVALID(m0_bvalid), .M0_AXI_BREADY(m0_bready),
    // M1
    .M1_AXI_ARID(m1_arid), .M1_AXI_ARADDR(m1_araddr), .M1_AXI_ARLEN(m1_arlen),
    .M1_AXI_ARSIZE(m1_arsize), .M1_AXI_ARBURST(m1_arburst), .M1_AXI_ARPROT(m1_arprot),
    .M1_AXI_ARVALID(m1_arvalid), .M1_AXI_ARREADY(m1_arready),
    .M1_AXI_RID(m1_rid), .M1_AXI_RDATA(m1_rdata), .M1_AXI_RRESP(m1_rresp),
    .M1_AXI_RLAST(m1_rlast), .M1_AXI_RVALID(m1_rvalid), .M1_AXI_RREADY(m1_rready),
    .M1_AXI_AWID(m1_awid), .M1_AXI_AWADDR(m1_awaddr), .M1_AXI_AWLEN(m1_awlen),
    .M1_AXI_AWSIZE(m1_awsize), .M1_AXI_AWBURST(m1_awburst), .M1_AXI_AWPROT(m1_awprot),
    .M1_AXI_AWVALID(m1_awvalid), .M1_AXI_AWREADY(m1_awready),
    .M1_AXI_WDATA(m1_wdata), .M1_AXI_WSTRB(m1_wstrb), .M1_AXI_WLAST(m1_wlast),
    .M1_AXI_WVALID(m1_wvalid), .M1_AXI_WREADY(m1_wready),
    .M1_AXI_BID(m1_bid), .M1_AXI_BRESP(m1_bresp),
    .M1_AXI_BVALID(m1_bvalid), .M1_AXI_BREADY(m1_bready),
    // M2 (inactive)
    .M2_AXI_ARID(m2_arid), .M2_AXI_ARADDR(m2_araddr), .M2_AXI_ARLEN(m2_arlen),
    .M2_AXI_ARSIZE(m2_arsize), .M2_AXI_ARBURST(m2_arburst), .M2_AXI_ARPROT(m2_arprot),
    .M2_AXI_ARVALID(m2_arvalid), .M2_AXI_ARREADY(m2_arready),
    .M2_AXI_RID(m2_rid), .M2_AXI_RDATA(m2_rdata), .M2_AXI_RRESP(m2_rresp),
    .M2_AXI_RLAST(m2_rlast), .M2_AXI_RVALID(m2_rvalid), .M2_AXI_RREADY(m2_rready),
    .M2_AXI_AWID(m2_awid), .M2_AXI_AWADDR(m2_awaddr), .M2_AXI_AWLEN(m2_awlen),
    .M2_AXI_AWSIZE(m2_awsize), .M2_AXI_AWBURST(m2_awburst), .M2_AXI_AWPROT(m2_awprot),
    .M2_AXI_AWVALID(m2_awvalid), .M2_AXI_AWREADY(m2_awready),
    .M2_AXI_WDATA(m2_wdata), .M2_AXI_WSTRB(m2_wstrb), .M2_AXI_WLAST(m2_wlast),
    .M2_AXI_WVALID(m2_wvalid), .M2_AXI_WREADY(m2_wready),
    .M2_AXI_BID(m2_bid), .M2_AXI_BRESP(m2_bresp),
    .M2_AXI_BVALID(m2_bvalid), .M2_AXI_BREADY(m2_bready),
    // M3
    .M3_AXI_ARID(m3_arid), .M3_AXI_ARADDR(m3_araddr), .M3_AXI_ARLEN(m3_arlen),
    .M3_AXI_ARSIZE(m3_arsize), .M3_AXI_ARBURST(m3_arburst), .M3_AXI_ARPROT(m3_arprot),
    .M3_AXI_ARVALID(m3_arvalid), .M3_AXI_ARREADY(m3_arready),
    .M3_AXI_RID(m3_rid), .M3_AXI_RDATA(m3_rdata), .M3_AXI_RRESP(m3_rresp),
    .M3_AXI_RLAST(m3_rlast), .M3_AXI_RVALID(m3_rvalid), .M3_AXI_RREADY(m3_rready),
    .M3_AXI_AWID(m3_awid), .M3_AXI_AWADDR(m3_awaddr), .M3_AXI_AWLEN(m3_awlen),
    .M3_AXI_AWSIZE(m3_awsize), .M3_AXI_AWBURST(m3_awburst), .M3_AXI_AWPROT(m3_awprot),
    .M3_AXI_AWVALID(m3_awvalid), .M3_AXI_AWREADY(m3_awready),
    .M3_AXI_WDATA(m3_wdata), .M3_AXI_WSTRB(m3_wstrb), .M3_AXI_WLAST(m3_wlast),
    .M3_AXI_WVALID(m3_wvalid), .M3_AXI_WREADY(m3_wready),
    .M3_AXI_BID(m3_bid), .M3_AXI_BRESP(m3_bresp),
    .M3_AXI_BVALID(m3_bvalid), .M3_AXI_BREADY(m3_bready),
    // M4 (inactive)
    .M4_AXI_ARID(m4_arid), .M4_AXI_ARADDR(m4_araddr), .M4_AXI_ARLEN(m4_arlen),
    .M4_AXI_ARSIZE(m4_arsize), .M4_AXI_ARBURST(m4_arburst), .M4_AXI_ARPROT(m4_arprot),
    .M4_AXI_ARVALID(m4_arvalid), .M4_AXI_ARREADY(m4_arready),
    .M4_AXI_RID(m4_rid), .M4_AXI_RDATA(m4_rdata), .M4_AXI_RRESP(m4_rresp),
    .M4_AXI_RLAST(m4_rlast), .M4_AXI_RVALID(m4_rvalid), .M4_AXI_RREADY(m4_rready),
    .M4_AXI_AWID(m4_awid), .M4_AXI_AWADDR(m4_awaddr), .M4_AXI_AWLEN(m4_awlen),
    .M4_AXI_AWSIZE(m4_awsize), .M4_AXI_AWBURST(m4_awburst), .M4_AXI_AWPROT(m4_awprot),
    .M4_AXI_AWVALID(m4_awvalid), .M4_AXI_AWREADY(m4_awready),
    .M4_AXI_WDATA(m4_wdata), .M4_AXI_WSTRB(m4_wstrb), .M4_AXI_WLAST(m4_wlast),
    .M4_AXI_WVALID(m4_wvalid), .M4_AXI_WREADY(m4_wready),
    .M4_AXI_BID(m4_bid), .M4_AXI_BRESP(m4_bresp),
    .M4_AXI_BVALID(m4_bvalid), .M4_AXI_BREADY(m4_bready),
    // S0
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
    .S0_AXI_BID(s0_bid), .S0_AXI_BRESP(s0_bresp),
    .S0_AXI_BVALID(s0_bvalid), .S0_AXI_BREADY(s0_bready),
    // S1
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
    .S1_AXI_BID(s1_bid), .S1_AXI_BRESP(s1_bresp),
    .S1_AXI_BVALID(s1_bvalid), .S1_AXI_BREADY(s1_bready),
    // S2
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
    .S2_AXI_BID(s2_bid), .S2_AXI_BRESP(s2_bresp),
    .S2_AXI_BVALID(s2_bvalid), .S2_AXI_BREADY(s2_bready),
    // S3
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
    .S3_AXI_BID(s3_bid), .S3_AXI_BRESP(s3_bresp),
    .S3_AXI_BVALID(s3_bvalid), .S3_AXI_BREADY(s3_bready),
    // S4
    .S4_AXI_ARID(s4_arid), .S4_AXI_ARADDR(s4_araddr), .S4_AXI_ARLEN(s4_arlen),
    .S4_AXI_ARSIZE(s4_arsize), .S4_AXI_ARBURST(s4_arburst), .S4_AXI_ARPROT(s4_arprot),
    .S4_AXI_ARVALID(s4_arvalid), .S4_AXI_ARREADY(s4_arready),
    .S4_AXI_RID(s4_rid), .S4_AXI_RDATA(s4_rdata), .S4_AXI_RRESP(s4_rresp),
    .S4_AXI_RLAST(s4_rlast), .S4_AXI_RVALID(s4_rvalid), .S4_AXI_RREADY(s4_rready),
    .S4_AXI_AWID(s4_awid), .S4_AXI_AWADDR(s4_awaddr), .S4_AXI_AWLEN(s4_awlen),
    .S4_AXI_AWSIZE(s4_awsize), .S4_AXI_AWBURST(s4_awburst), .S4_AXI_AWPROT(s4_awprot),
    .S4_AXI_AWVALID(s4_awvalid), .S4_AXI_AWREADY(s4_awready),
    .S4_AXI_WDATA(s4_wdata), .S4_AXI_WSTRB(s4_wstrb), .S4_AXI_WLAST(s4_wlast),
    .S4_AXI_WVALID(s4_wvalid), .S4_AXI_WREADY(s4_wready),
    .S4_AXI_BID(s4_bid), .S4_AXI_BRESP(s4_bresp),
    .S4_AXI_BVALID(s4_bvalid), .S4_AXI_BREADY(s4_bready),
    // S5
    .S5_AXI_ARID(s5_arid), .S5_AXI_ARADDR(s5_araddr), .S5_AXI_ARLEN(s5_arlen),
    .S5_AXI_ARSIZE(s5_arsize), .S5_AXI_ARBURST(s5_arburst), .S5_AXI_ARPROT(s5_arprot),
    .S5_AXI_ARVALID(s5_arvalid), .S5_AXI_ARREADY(s5_arready),
    .S5_AXI_RID(s5_rid), .S5_AXI_RDATA(s5_rdata), .S5_AXI_RRESP(s5_rresp),
    .S5_AXI_RLAST(s5_rlast), .S5_AXI_RVALID(s5_rvalid), .S5_AXI_RREADY(s5_rready),
    .S5_AXI_AWID(s5_awid), .S5_AXI_AWADDR(s5_awaddr), .S5_AXI_AWLEN(s5_awlen),
    .S5_AXI_AWSIZE(s5_awsize), .S5_AXI_AWBURST(s5_awburst), .S5_AXI_AWPROT(s5_awprot),
    .S5_AXI_AWVALID(s5_awvalid), .S5_AXI_AWREADY(s5_awready),
    .S5_AXI_WDATA(s5_wdata), .S5_AXI_WSTRB(s5_wstrb), .S5_AXI_WLAST(s5_wlast),
    .S5_AXI_WVALID(s5_wvalid), .S5_AXI_WREADY(s5_wready),
    .S5_AXI_BID(s5_bid), .S5_AXI_BRESP(s5_bresp),
    .S5_AXI_BVALID(s5_bvalid), .S5_AXI_BREADY(s5_bready),
    // S6
    .S6_AXI_ARID(s6_arid), .S6_AXI_ARADDR(s6_araddr), .S6_AXI_ARLEN(s6_arlen),
    .S6_AXI_ARSIZE(s6_arsize), .S6_AXI_ARBURST(s6_arburst), .S6_AXI_ARPROT(s6_arprot),
    .S6_AXI_ARVALID(s6_arvalid), .S6_AXI_ARREADY(s6_arready),
    .S6_AXI_RID(s6_rid), .S6_AXI_RDATA(s6_rdata), .S6_AXI_RRESP(s6_rresp),
    .S6_AXI_RLAST(s6_rlast), .S6_AXI_RVALID(s6_rvalid), .S6_AXI_RREADY(s6_rready),
    .S6_AXI_AWID(s6_awid), .S6_AXI_AWADDR(s6_awaddr), .S6_AXI_AWLEN(s6_awlen),
    .S6_AXI_AWSIZE(s6_awsize), .S6_AXI_AWBURST(s6_awburst), .S6_AXI_AWPROT(s6_awprot),
    .S6_AXI_AWVALID(s6_awvalid), .S6_AXI_AWREADY(s6_awready),
    .S6_AXI_WDATA(s6_wdata), .S6_AXI_WSTRB(s6_wstrb), .S6_AXI_WLAST(s6_wlast),
    .S6_AXI_WVALID(s6_wvalid), .S6_AXI_WREADY(s6_wready),
    .S6_AXI_BID(s6_bid), .S6_AXI_BRESP(s6_bresp),
    .S6_AXI_BVALID(s6_bvalid), .S6_AXI_BREADY(s6_bready),
    // S7
    .S7_AXI_ARID(s7_arid), .S7_AXI_ARADDR(s7_araddr), .S7_AXI_ARLEN(s7_arlen),
    .S7_AXI_ARSIZE(s7_arsize), .S7_AXI_ARBURST(s7_arburst), .S7_AXI_ARPROT(s7_arprot),
    .S7_AXI_ARVALID(s7_arvalid), .S7_AXI_ARREADY(s7_arready),
    .S7_AXI_RID(s7_rid), .S7_AXI_RDATA(s7_rdata), .S7_AXI_RRESP(s7_rresp),
    .S7_AXI_RLAST(s7_rlast), .S7_AXI_RVALID(s7_rvalid), .S7_AXI_RREADY(s7_rready),
    .S7_AXI_AWID(s7_awid), .S7_AXI_AWADDR(s7_awaddr), .S7_AXI_AWLEN(s7_awlen),
    .S7_AXI_AWSIZE(s7_awsize), .S7_AXI_AWBURST(s7_awburst), .S7_AXI_AWPROT(s7_awprot),
    .S7_AXI_AWVALID(s7_awvalid), .S7_AXI_AWREADY(s7_awready),
    .S7_AXI_WDATA(s7_wdata), .S7_AXI_WSTRB(s7_wstrb), .S7_AXI_WLAST(s7_wlast),
    .S7_AXI_WVALID(s7_wvalid), .S7_AXI_WREADY(s7_wready),
    .S7_AXI_BID(s7_bid), .S7_AXI_BRESP(s7_bresp),
    .S7_AXI_BVALID(s7_bvalid), .S7_AXI_BREADY(s7_bready),
    // S8
    .S8_AXI_ARID(s8_arid), .S8_AXI_ARADDR(s8_araddr), .S8_AXI_ARLEN(s8_arlen),
    .S8_AXI_ARSIZE(s8_arsize), .S8_AXI_ARBURST(s8_arburst), .S8_AXI_ARPROT(s8_arprot),
    .S8_AXI_ARVALID(s8_arvalid), .S8_AXI_ARREADY(s8_arready),
    .S8_AXI_RID(s8_rid), .S8_AXI_RDATA(s8_rdata), .S8_AXI_RRESP(s8_rresp),
    .S8_AXI_RLAST(s8_rlast), .S8_AXI_RVALID(s8_rvalid), .S8_AXI_RREADY(s8_rready),
    .S8_AXI_AWID(s8_awid), .S8_AXI_AWADDR(s8_awaddr), .S8_AXI_AWLEN(s8_awlen),
    .S8_AXI_AWSIZE(s8_awsize), .S8_AXI_AWBURST(s8_awburst), .S8_AXI_AWPROT(s8_awprot),
    .S8_AXI_AWVALID(s8_awvalid), .S8_AXI_AWREADY(s8_awready),
    .S8_AXI_WDATA(s8_wdata), .S8_AXI_WSTRB(s8_wstrb), .S8_AXI_WLAST(s8_wlast),
    .S8_AXI_WVALID(s8_wvalid), .S8_AXI_WREADY(s8_wready),
    .S8_AXI_BID(s8_bid), .S8_AXI_BRESP(s8_bresp),
    .S8_AXI_BVALID(s8_bvalid), .S8_AXI_BREADY(s8_bready),
    // S9
    .S9_AXI_ARID(s9_arid), .S9_AXI_ARADDR(s9_araddr), .S9_AXI_ARLEN(s9_arlen),
    .S9_AXI_ARSIZE(s9_arsize), .S9_AXI_ARBURST(s9_arburst), .S9_AXI_ARPROT(s9_arprot),
    .S9_AXI_ARVALID(s9_arvalid), .S9_AXI_ARREADY(s9_arready),
    .S9_AXI_RID(s9_rid), .S9_AXI_RDATA(s9_rdata), .S9_AXI_RRESP(s9_rresp),
    .S9_AXI_RLAST(s9_rlast), .S9_AXI_RVALID(s9_rvalid), .S9_AXI_RREADY(s9_rready),
    .S9_AXI_AWID(s9_awid), .S9_AXI_AWADDR(s9_awaddr), .S9_AXI_AWLEN(s9_awlen),
    .S9_AXI_AWSIZE(s9_awsize), .S9_AXI_AWBURST(s9_awburst), .S9_AXI_AWPROT(s9_awprot),
    .S9_AXI_AWVALID(s9_awvalid), .S9_AXI_AWREADY(s9_awready),
    .S9_AXI_WDATA(s9_wdata), .S9_AXI_WSTRB(s9_wstrb), .S9_AXI_WLAST(s9_wlast),
    .S9_AXI_WVALID(s9_wvalid), .S9_AXI_WREADY(s9_wready),
    .S9_AXI_BID(s9_bid), .S9_AXI_BRESP(s9_bresp),
    .S9_AXI_BVALID(s9_bvalid), .S9_AXI_BREADY(s9_bready),
    // S10
    .S10_AXI_ARID(s10_arid), .S10_AXI_ARADDR(s10_araddr), .S10_AXI_ARLEN(s10_arlen),
    .S10_AXI_ARSIZE(s10_arsize), .S10_AXI_ARBURST(s10_arburst), .S10_AXI_ARPROT(s10_arprot),
    .S10_AXI_ARVALID(s10_arvalid), .S10_AXI_ARREADY(s10_arready),
    .S10_AXI_RID(s10_rid), .S10_AXI_RDATA(s10_rdata), .S10_AXI_RRESP(s10_rresp),
    .S10_AXI_RLAST(s10_rlast), .S10_AXI_RVALID(s10_rvalid), .S10_AXI_RREADY(s10_rready),
    .S10_AXI_AWID(s10_awid), .S10_AXI_AWADDR(s10_awaddr), .S10_AXI_AWLEN(s10_awlen),
    .S10_AXI_AWSIZE(s10_awsize), .S10_AXI_AWBURST(s10_awburst), .S10_AXI_AWPROT(s10_awprot),
    .S10_AXI_AWVALID(s10_awvalid), .S10_AXI_AWREADY(s10_awready),
    .S10_AXI_WDATA(s10_wdata), .S10_AXI_WSTRB(s10_wstrb), .S10_AXI_WLAST(s10_wlast),
    .S10_AXI_WVALID(s10_wvalid), .S10_AXI_WREADY(s10_wready),
    .S10_AXI_BID(s10_bid), .S10_AXI_BRESP(s10_bresp),
    .S10_AXI_BVALID(s10_bvalid), .S10_AXI_BREADY(s10_bready),
    // S11
    .S11_AXI_ARID(s11_arid), .S11_AXI_ARADDR(s11_araddr), .S11_AXI_ARLEN(s11_arlen),
    .S11_AXI_ARSIZE(s11_arsize), .S11_AXI_ARBURST(s11_arburst), .S11_AXI_ARPROT(s11_arprot),
    .S11_AXI_ARVALID(s11_arvalid), .S11_AXI_ARREADY(s11_arready),
    .S11_AXI_RID(s11_rid), .S11_AXI_RDATA(s11_rdata), .S11_AXI_RRESP(s11_rresp),
    .S11_AXI_RLAST(s11_rlast), .S11_AXI_RVALID(s11_rvalid), .S11_AXI_RREADY(s11_rready),
    .S11_AXI_AWID(s11_awid), .S11_AXI_AWADDR(s11_awaddr), .S11_AXI_AWLEN(s11_awlen),
    .S11_AXI_AWSIZE(s11_awsize), .S11_AXI_AWBURST(s11_awburst), .S11_AXI_AWPROT(s11_awprot),
    .S11_AXI_AWVALID(s11_awvalid), .S11_AXI_AWREADY(s11_awready),
    .S11_AXI_WDATA(s11_wdata), .S11_AXI_WSTRB(s11_wstrb), .S11_AXI_WLAST(s11_wlast),
    .S11_AXI_WVALID(s11_wvalid), .S11_AXI_WREADY(s11_wready),
    .S11_AXI_BID(s11_bid), .S11_AXI_BRESP(s11_bresp),
    .S11_AXI_BVALID(s11_bvalid), .S11_AXI_BREADY(s11_bready)
);

// ---------------------------------------------------------------------------
// Slave stub instances
// ---------------------------------------------------------------------------
axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 0)) u_s0 (.clk(clk),.rst_n(rst_n),
    .arid(s0_arid),.araddr(s0_araddr),.arlen(s0_arlen),.arsize(s0_arsize),.arburst(s0_arburst),.arprot(s0_arprot),
    .arvalid(s0_arvalid),.arready(s0_arready),.rid(s0_rid),.rdata(s0_rdata),.rresp(s0_rresp),
    .rlast(s0_rlast),.rvalid(s0_rvalid),.rready(s0_rready),
    .awid(s0_awid),.awaddr(s0_awaddr),.awlen(s0_awlen),.awsize(s0_awsize),.awburst(s0_awburst),.awprot(s0_awprot),
    .awvalid(s0_awvalid),.awready(s0_awready),.wdata(s0_wdata),.wstrb(s0_wstrb),.wlast(s0_wlast),
    .wvalid(s0_wvalid),.wready(s0_wready),.bid(s0_bid),.bresp(s0_bresp),.bvalid(s0_bvalid),.bready(s0_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 1)) u_s1 (.clk(clk),.rst_n(rst_n),
    .arid(s1_arid),.araddr(s1_araddr),.arlen(s1_arlen),.arsize(s1_arsize),.arburst(s1_arburst),.arprot(s1_arprot),
    .arvalid(s1_arvalid),.arready(s1_arready),.rid(s1_rid),.rdata(s1_rdata),.rresp(s1_rresp),
    .rlast(s1_rlast),.rvalid(s1_rvalid),.rready(s1_rready),
    .awid(s1_awid),.awaddr(s1_awaddr),.awlen(s1_awlen),.awsize(s1_awsize),.awburst(s1_awburst),.awprot(s1_awprot),
    .awvalid(s1_awvalid),.awready(s1_awready),.wdata(s1_wdata),.wstrb(s1_wstrb),.wlast(s1_wlast),
    .wvalid(s1_wvalid),.wready(s1_wready),.bid(s1_bid),.bresp(s1_bresp),.bvalid(s1_bvalid),.bready(s1_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 2)) u_s2 (.clk(clk),.rst_n(rst_n),
    .arid(s2_arid),.araddr(s2_araddr),.arlen(s2_arlen),.arsize(s2_arsize),.arburst(s2_arburst),.arprot(s2_arprot),
    .arvalid(s2_arvalid),.arready(s2_arready),.rid(s2_rid),.rdata(s2_rdata),.rresp(s2_rresp),
    .rlast(s2_rlast),.rvalid(s2_rvalid),.rready(s2_rready),
    .awid(s2_awid),.awaddr(s2_awaddr),.awlen(s2_awlen),.awsize(s2_awsize),.awburst(s2_awburst),.awprot(s2_awprot),
    .awvalid(s2_awvalid),.awready(s2_awready),.wdata(s2_wdata),.wstrb(s2_wstrb),.wlast(s2_wlast),
    .wvalid(s2_wvalid),.wready(s2_wready),.bid(s2_bid),.bresp(s2_bresp),.bvalid(s2_bvalid),.bready(s2_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 3)) u_s3 (.clk(clk),.rst_n(rst_n),
    .arid(s3_arid),.araddr(s3_araddr),.arlen(s3_arlen),.arsize(s3_arsize),.arburst(s3_arburst),.arprot(s3_arprot),
    .arvalid(s3_arvalid),.arready(s3_arready),.rid(s3_rid),.rdata(s3_rdata),.rresp(s3_rresp),
    .rlast(s3_rlast),.rvalid(s3_rvalid),.rready(s3_rready),
    .awid(s3_awid),.awaddr(s3_awaddr),.awlen(s3_awlen),.awsize(s3_awsize),.awburst(s3_awburst),.awprot(s3_awprot),
    .awvalid(s3_awvalid),.awready(s3_awready),.wdata(s3_wdata),.wstrb(s3_wstrb),.wlast(s3_wlast),
    .wvalid(s3_wvalid),.wready(s3_wready),.bid(s3_bid),.bresp(s3_bresp),.bvalid(s3_bvalid),.bready(s3_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 4)) u_s4 (.clk(clk),.rst_n(rst_n),
    .arid(s4_arid),.araddr(s4_araddr),.arlen(s4_arlen),.arsize(s4_arsize),.arburst(s4_arburst),.arprot(s4_arprot),
    .arvalid(s4_arvalid),.arready(s4_arready),.rid(s4_rid),.rdata(s4_rdata),.rresp(s4_rresp),
    .rlast(s4_rlast),.rvalid(s4_rvalid),.rready(s4_rready),
    .awid(s4_awid),.awaddr(s4_awaddr),.awlen(s4_awlen),.awsize(s4_awsize),.awburst(s4_awburst),.awprot(s4_awprot),
    .awvalid(s4_awvalid),.awready(s4_awready),.wdata(s4_wdata),.wstrb(s4_wstrb),.wlast(s4_wlast),
    .wvalid(s4_wvalid),.wready(s4_wready),.bid(s4_bid),.bresp(s4_bresp),.bvalid(s4_bvalid),.bready(s4_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 5)) u_s5 (.clk(clk),.rst_n(rst_n),
    .arid(s5_arid),.araddr(s5_araddr),.arlen(s5_arlen),.arsize(s5_arsize),.arburst(s5_arburst),.arprot(s5_arprot),
    .arvalid(s5_arvalid),.arready(s5_arready),.rid(s5_rid),.rdata(s5_rdata),.rresp(s5_rresp),
    .rlast(s5_rlast),.rvalid(s5_rvalid),.rready(s5_rready),
    .awid(s5_awid),.awaddr(s5_awaddr),.awlen(s5_awlen),.awsize(s5_awsize),.awburst(s5_awburst),.awprot(s5_awprot),
    .awvalid(s5_awvalid),.awready(s5_awready),.wdata(s5_wdata),.wstrb(s5_wstrb),.wlast(s5_wlast),
    .wvalid(s5_wvalid),.wready(s5_wready),.bid(s5_bid),.bresp(s5_bresp),.bvalid(s5_bvalid),.bready(s5_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 6)) u_s6 (.clk(clk),.rst_n(rst_n),
    .arid(s6_arid),.araddr(s6_araddr),.arlen(s6_arlen),.arsize(s6_arsize),.arburst(s6_arburst),.arprot(s6_arprot),
    .arvalid(s6_arvalid),.arready(s6_arready),.rid(s6_rid),.rdata(s6_rdata),.rresp(s6_rresp),
    .rlast(s6_rlast),.rvalid(s6_rvalid),.rready(s6_rready),
    .awid(s6_awid),.awaddr(s6_awaddr),.awlen(s6_awlen),.awsize(s6_awsize),.awburst(s6_awburst),.awprot(s6_awprot),
    .awvalid(s6_awvalid),.awready(s6_awready),.wdata(s6_wdata),.wstrb(s6_wstrb),.wlast(s6_wlast),
    .wvalid(s6_wvalid),.wready(s6_wready),.bid(s6_bid),.bresp(s6_bresp),.bvalid(s6_bvalid),.bready(s6_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 7)) u_s7 (.clk(clk),.rst_n(rst_n),
    .arid(s7_arid),.araddr(s7_araddr),.arlen(s7_arlen),.arsize(s7_arsize),.arburst(s7_arburst),.arprot(s7_arprot),
    .arvalid(s7_arvalid),.arready(s7_arready),.rid(s7_rid),.rdata(s7_rdata),.rresp(s7_rresp),
    .rlast(s7_rlast),.rvalid(s7_rvalid),.rready(s7_rready),
    .awid(s7_awid),.awaddr(s7_awaddr),.awlen(s7_awlen),.awsize(s7_awsize),.awburst(s7_awburst),.awprot(s7_awprot),
    .awvalid(s7_awvalid),.awready(s7_awready),.wdata(s7_wdata),.wstrb(s7_wstrb),.wlast(s7_wlast),
    .wvalid(s7_wvalid),.wready(s7_wready),.bid(s7_bid),.bresp(s7_bresp),.bvalid(s7_bvalid),.bready(s7_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 8)) u_s8 (.clk(clk),.rst_n(rst_n),
    .arid(s8_arid),.araddr(s8_araddr),.arlen(s8_arlen),.arsize(s8_arsize),.arburst(s8_arburst),.arprot(s8_arprot),
    .arvalid(s8_arvalid),.arready(s8_arready),.rid(s8_rid),.rdata(s8_rdata),.rresp(s8_rresp),
    .rlast(s8_rlast),.rvalid(s8_rvalid),.rready(s8_rready),
    .awid(s8_awid),.awaddr(s8_awaddr),.awlen(s8_awlen),.awsize(s8_awsize),.awburst(s8_awburst),.awprot(s8_awprot),
    .awvalid(s8_awvalid),.awready(s8_awready),.wdata(s8_wdata),.wstrb(s8_wstrb),.wlast(s8_wlast),
    .wvalid(s8_wvalid),.wready(s8_wready),.bid(s8_bid),.bresp(s8_bresp),.bvalid(s8_bvalid),.bready(s8_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID( 9)) u_s9 (.clk(clk),.rst_n(rst_n),
    .arid(s9_arid),.araddr(s9_araddr),.arlen(s9_arlen),.arsize(s9_arsize),.arburst(s9_arburst),.arprot(s9_arprot),
    .arvalid(s9_arvalid),.arready(s9_arready),.rid(s9_rid),.rdata(s9_rdata),.rresp(s9_rresp),
    .rlast(s9_rlast),.rvalid(s9_rvalid),.rready(s9_rready),
    .awid(s9_awid),.awaddr(s9_awaddr),.awlen(s9_awlen),.awsize(s9_awsize),.awburst(s9_awburst),.awprot(s9_awprot),
    .awvalid(s9_awvalid),.awready(s9_awready),.wdata(s9_wdata),.wstrb(s9_wstrb),.wlast(s9_wlast),
    .wvalid(s9_wvalid),.wready(s9_wready),.bid(s9_bid),.bresp(s9_bresp),.bvalid(s9_bvalid),.bready(s9_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID(10)) u_s10 (.clk(clk),.rst_n(rst_n),
    .arid(s10_arid),.araddr(s10_araddr),.arlen(s10_arlen),.arsize(s10_arsize),.arburst(s10_arburst),.arprot(s10_arprot),
    .arvalid(s10_arvalid),.arready(s10_arready),.rid(s10_rid),.rdata(s10_rdata),.rresp(s10_rresp),
    .rlast(s10_rlast),.rvalid(s10_rvalid),.rready(s10_rready),
    .awid(s10_awid),.awaddr(s10_awaddr),.awlen(s10_awlen),.awsize(s10_awsize),.awburst(s10_awburst),.awprot(s10_awprot),
    .awvalid(s10_awvalid),.awready(s10_awready),.wdata(s10_wdata),.wstrb(s10_wstrb),.wlast(s10_wlast),
    .wvalid(s10_wvalid),.wready(s10_wready),.bid(s10_bid),.bresp(s10_bresp),.bvalid(s10_bvalid),.bready(s10_bready));

axi4_slave_stub #(.ID_W(ID_W),.DW(DW),.SLAVE_ID(11)) u_s11 (.clk(clk),.rst_n(rst_n),
    .arid(s11_arid),.araddr(s11_araddr),.arlen(s11_arlen),.arsize(s11_arsize),.arburst(s11_arburst),.arprot(s11_arprot),
    .arvalid(s11_arvalid),.arready(s11_arready),.rid(s11_rid),.rdata(s11_rdata),.rresp(s11_rresp),
    .rlast(s11_rlast),.rvalid(s11_rvalid),.rready(s11_rready),
    .awid(s11_awid),.awaddr(s11_awaddr),.awlen(s11_awlen),.awsize(s11_awsize),.awburst(s11_awburst),.awprot(s11_awprot),
    .awvalid(s11_awvalid),.awready(s11_awready),.wdata(s11_wdata),.wstrb(s11_wstrb),.wlast(s11_wlast),
    .wvalid(s11_wvalid),.wready(s11_wready),.bid(s11_bid),.bresp(s11_bresp),.bvalid(s11_bvalid),.bready(s11_bready));

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
integer pass_cnt, fail_cnt;

task check;
    input [255:0] name;
    input [31:0]  got;
    input [31:0]  exp;
    begin
        if (got === exp) begin
            $display("[PASS] %0s  got=0x%08h", name, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s  got=0x%08h  exp=0x%08h", name, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// Master bus idle tasks
// ---------------------------------------------------------------------------
task m0_idle;
    begin
        m0_arvalid<=0; m0_rready<=1; m0_awvalid<=0; m0_wvalid<=0; m0_bready<=1;
        m0_arid<=0; m0_araddr<=0; m0_arlen<=0; m0_arsize<=3'b010;
        m0_arburst<=2'b01; m0_arprot<=0;
        m0_awid<=0; m0_awaddr<=0; m0_awlen<=0; m0_awsize<=3'b010;
        m0_awburst<=2'b01; m0_awprot<=0;
        m0_wdata<=0; m0_wstrb<=4'hF; m0_wlast<=1;
    end
endtask

task m1_idle;
    begin
        m1_arvalid<=0; m1_rready<=1; m1_awvalid<=0; m1_wvalid<=0; m1_bready<=1;
        m1_arid<=0; m1_araddr<=0; m1_arlen<=0; m1_arsize<=3'b010;
        m1_arburst<=2'b01; m1_arprot<=0;
        m1_awid<=0; m1_awaddr<=0; m1_awlen<=0; m1_awsize<=3'b010;
        m1_awburst<=2'b01; m1_awprot<=0;
        m1_wdata<=0; m1_wstrb<=4'hF; m1_wlast<=1;
    end
endtask

task m3_idle;
    begin
        m3_arvalid<=0; m3_rready<=1; m3_awvalid<=0; m3_wvalid<=0; m3_bready<=1;
        m3_arid<=0; m3_araddr<=0; m3_arlen<=0; m3_arsize<=3'b010;
        m3_arburst<=2'b01; m3_arprot<=0;
        m3_awid<=0; m3_awaddr<=0; m3_awlen<=0; m3_awsize<=3'b010;
        m3_awburst<=2'b01; m3_awprot<=0;
        m3_wdata<=0; m3_wstrb<=4'hF; m3_wlast<=1;
    end
endtask

// ---------------------------------------------------------------------------
// AXI single-beat read tasks
// ---------------------------------------------------------------------------
task axi_read_m0;
    input  [ID_W-1:0] tid;
    input  [AW-1:0]   addr;
    output [DW-1:0]   rdat;
    output [1:0]      rres;
    begin
        @(negedge clk);
        m0_arid<=tid; m0_araddr<=addr; m0_arlen<=0;
        m0_arsize<=3'b010; m0_arburst<=2'b01; m0_arprot<=0; m0_arvalid<=1;
        @(posedge clk); while (!m0_arready) @(posedge clk);
        @(negedge clk); m0_arvalid<=0;
        @(posedge clk); while (!m0_rvalid) @(posedge clk);
        rdat = m0_rdata; rres = m0_rresp;
        @(negedge clk);
    end
endtask

task axi_read_m1;
    input  [ID_W-1:0] tid;
    input  [AW-1:0]   addr;
    output [DW-1:0]   rdat;
    output [1:0]      rres;
    begin
        @(negedge clk);
        m1_arid<=tid; m1_araddr<=addr; m1_arlen<=0;
        m1_arsize<=3'b010; m1_arburst<=2'b01; m1_arprot<=0; m1_arvalid<=1;
        @(posedge clk); while (!m1_arready) @(posedge clk);
        @(negedge clk); m1_arvalid<=0;
        @(posedge clk); while (!m1_rvalid) @(posedge clk);
        rdat = m1_rdata; rres = m1_rresp;
        @(negedge clk);
    end
endtask

// Burst read on M1
task axi_burst_read_m1;
    input  [ID_W-1:0] tid;
    input  [AW-1:0]   addr;
    input  [7:0]       arlen;
    output [DW-1:0]   last_rdat;
    output [1:0]      last_rres;
    begin : burst_blk
        integer b;
        @(negedge clk);
        m1_arid<=tid; m1_araddr<=addr; m1_arlen<=arlen;
        m1_arsize<=3'b010; m1_arburst<=2'b01; m1_arprot<=0; m1_arvalid<=1;
        @(posedge clk); while (!m1_arready) @(posedge clk);
        @(negedge clk); m1_arvalid<=0;
        for (b = 0; b <= arlen; b = b + 1) begin
            @(posedge clk); while (!m1_rvalid) @(posedge clk);
            last_rdat = m1_rdata; last_rres = m1_rresp;
        end
        @(negedge clk);
    end
endtask

// Single-beat write on M1
task axi_write_m1;
    input  [ID_W-1:0] tid;
    input  [AW-1:0]   addr;
    input  [DW-1:0]   data;
    input  [3:0]       strb;
    output [1:0]      bres;
    begin : wr_blk
        reg aw_done, w_done;
        aw_done = 0; w_done = 0;
        @(negedge clk);
        m1_awid<=tid; m1_awaddr<=addr; m1_awlen<=0; m1_awsize<=3'b010;
        m1_awburst<=2'b01; m1_awprot<=0; m1_awvalid<=1;
        m1_wdata<=data; m1_wstrb<=strb; m1_wlast<=1; m1_wvalid<=1;
        @(posedge clk);
        while (!(aw_done && w_done)) begin
            if (m1_awvalid && m1_awready) aw_done = 1;
            if (m1_wvalid  && m1_wready)  w_done  = 1;
            @(negedge clk);
            if (aw_done) m1_awvalid<=0;
            if (w_done)  m1_wvalid <=0;
            if (!(aw_done && w_done)) @(posedge clk);
        end
        @(negedge clk); m1_awvalid<=0; m1_wvalid<=0;
        @(posedge clk); while (!m1_bvalid) @(posedge clk);
        bres = m1_bresp;
        @(negedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Shared result registers
// ---------------------------------------------------------------------------
reg [DW-1:0] rd0, rd1, rd3;
reg [1:0]    rr0, rr1, rr3, br1;

// ---------------------------------------------------------------------------
// Main test sequence
// ---------------------------------------------------------------------------
integer tout;

initial begin
    pass_cnt = 0; fail_cnt = 0;
    m0_idle; m1_idle; m3_idle;

    rst_n = 0;
    repeat(5) @(posedge clk);
    @(negedge clk); rst_n = 1;
    repeat(3) @(posedge clk);

    $display("============================================");
    $display("  A5 — axi4_crossbar_5m12s Testbench");
    $display("============================================");

    // -------------------------------------------------------------------------
    // TC-M0-S0: M0 (ICache) reads from IMEM (S0, 0x0000_1000)
    // rdata[31:24] = SLAVE_ID = 0 confirms routing to S0
    // -------------------------------------------------------------------------
    $display("\n--- TC-M0-S0: M0 -> IMEM (S0) ---");
    axi_read_m0(4'h1, 32'h0000_1000, rd0, rr0);
    check("M0-S0 RRESP OKAY",  {30'd0, rr0}, 32'd0);
    check("M0-S0 sid=0",       rd0[31:24],   32'd0);

    // -------------------------------------------------------------------------
    // TC-M1-S1r: M1 (DCache) reads from DMEM (S1, 0x1000_0020)
    // -------------------------------------------------------------------------
    $display("\n--- TC-M1-S1r: M1 -> DMEM (S1) read ---");
    axi_read_m1(4'h2, 32'h1000_0020, rd1, rr1);
    check("M1-S1r RRESP OKAY", {30'd0, rr1}, 32'd0);
    check("M1-S1r sid=1",      rd1[31:24],   32'd1);

    // -------------------------------------------------------------------------
    // TC-M1-S1w: M1 writes to DMEM (S1, 0x1000_0040)
    // -------------------------------------------------------------------------
    $display("\n--- TC-M1-S1w: M1 -> DMEM (S1) write ---");
    axi_write_m1(4'h3, 32'h1000_0040, 32'hDEAD_BEEF, 4'hF, br1);
    check("M1-S1w BRESP OKAY", {30'd0, br1}, 32'd0);

    // -------------------------------------------------------------------------
    // TC-M0-S5: M0 reads from UART (S5, 0x5000_0000)
    // -------------------------------------------------------------------------
    $display("\n--- TC-M0-S5: M0 -> UART (S5) ---");
    axi_read_m0(4'h4, 32'h5000_0000, rd0, rr0);
    check("M0-S5 RRESP OKAY",  {30'd0, rr0}, 32'd0);
    check("M0-S5 sid=5",       rd0[31:24],   32'd5);

    // -------------------------------------------------------------------------
    // TC-M0-S11: M0 reads from DMA_CTRL (S11, 0x6001_0000)
    // -------------------------------------------------------------------------
    $display("\n--- TC-M0-S11: M0 -> DMA_CTRL (S11) ---");
    axi_read_m0(4'h5, 32'h6001_0000, rd0, rr0);
    check("M0-S11 RRESP OKAY", {30'd0, rr0}, 32'd0);
    check("M0-S11 sid=11",     rd0[31:24],   32'd11);

    // -------------------------------------------------------------------------
    // TC-DECODE read: Unmapped 0x9000_0000 -> DECERR (RRESP=2'b11)
    // -------------------------------------------------------------------------
    $display("\n--- TC-DECODE read: 0x9000_0000 -> DECERR ---");
    axi_read_m0(4'h6, 32'h9000_0000, rd0, rr0);
    check("DECODE RRESP=11",   {30'd0, rr0}, 32'h3);

    // -------------------------------------------------------------------------
    // TC-DECODEW write: Unmapped 0x8000_0000 -> DECERR (BRESP=2'b11)
    // -------------------------------------------------------------------------
    $display("\n--- TC-DECODEW write: 0x8000_0000 -> DECERR ---");
    axi_write_m1(4'h7, 32'h8000_0000, 32'h1234_5678, 4'hF, br1);
    check("DECODEW BRESP=11",  {30'd0, br1}, 32'h3);

    // -------------------------------------------------------------------------
    // TC-BURST: M1 burst4 read from DMEM (ARLEN=3, 4 beats)
    // Last beat: rdata[23:16]=beat_index=3, rdata[31:24]=sid=1
    // -------------------------------------------------------------------------
    $display("\n--- TC-BURST: M1 burst4 -> DMEM (S1), ARLEN=3 ---");
    axi_burst_read_m1(4'h8, 32'h1000_0100, 8'd3, rd1, rr1);
    check("BURST RRESP OKAY",  {30'd0, rr1}, 32'd0);
    check("BURST sid=1",       rd1[31:24],   32'd1);
    check("BURST last beat=3", rd1[23:16],   32'd3);

    // -------------------------------------------------------------------------
    // TC-BID: AWID=0xA -> BID echoed back
    // -------------------------------------------------------------------------
    $display("\n--- TC-BID: BID echoes AWID ---");
    axi_write_m1(4'hA, 32'h1000_0200, 32'hABCD_EF01, 4'hF, br1);
    check("BID echo 0xA",      {28'd0, m1_bid}, 32'hA);
    check("BID BRESP OKAY",    {30'd0, br1},    32'd0);

    // -------------------------------------------------------------------------
    // TC-RID: ARID=0xB -> RID echoed back
    // -------------------------------------------------------------------------
    $display("\n--- TC-RID: RID echoes ARID ---");
    axi_read_m1(4'hB, 32'h1000_0300, rd1, rr1);
    check("RID echo 0xB",      {28'd0, m1_rid}, 32'hB);
    check("RID RRESP OKAY",    {30'd0, rr1},    32'd0);

    // -------------------------------------------------------------------------
    // TC-ARBIT: M0 and M3 both request S0 (IMEM) simultaneously
    // Both must eventually receive RVALID — no deadlock allowed
    // -------------------------------------------------------------------------
    $display("\n--- TC-ARBIT: M0+M3 simultaneous -> S0 (IMEM) ---");
    begin : arbit_blk
        reg m0_got, m3_got;
        m0_got = 0; m3_got = 0;
        @(negedge clk);
        // M0 request
        m0_arid<=4'h1; m0_araddr<=32'h0000_2000; m0_arlen<=0;
        m0_arsize<=3'b010; m0_arburst<=2'b01; m0_arprot<=0; m0_arvalid<=1;
        // M3 request (same slave S0)
        m3_arid<=4'h2; m3_araddr<=32'h0000_3000; m3_arlen<=0;
        m3_arsize<=3'b010; m3_arburst<=2'b01; m3_arprot<=0; m3_arvalid<=1;
        m3_rready<=1;

        tout = 0;
        @(posedge clk);
        while (!(m0_got && m3_got) && tout < 300) begin
            if (m0_arvalid && m0_arready) begin @(negedge clk); m0_arvalid<=0; end
            if (m3_arvalid && m3_arready) begin @(negedge clk); m3_arvalid<=0; end
            if (m0_rvalid) begin rd0 = m0_rdata; m0_got = 1; end
            if (m3_rvalid) begin rd3 = m3_rdata; m3_got = 1; end
            tout = tout + 1;
            if (!(m0_got && m3_got)) begin @(negedge clk); @(posedge clk); end
        end
        @(negedge clk); m0_arvalid<=0; m3_arvalid<=0;

        if (tout < 300) begin
            $display("[PASS] TC-ARBIT no deadlock (done in %0d cycles)", tout);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] TC-ARBIT TIMEOUT — deadlock suspected");
            fail_cnt = fail_cnt + 1;
        end
        if (m0_got) check("ARBIT M0 sid=0", rd0[31:24], 32'd0);
        if (m3_got) check("ARBIT M3 sid=0", rd3[31:24], 32'd0);
        m0_idle; m3_idle;
    end

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    repeat(5) @(posedge clk);
    $display("\n============================================");
    $display("  RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0)
        $display("  *** ALL A5 TESTS PASSED ***");
    else
        $display("  *** %0d TEST(S) FAILED ***", fail_cnt);
    $display("============================================");
    $finish;
end

// Timeout watchdog
initial begin
    #2000000;
    $display("[WATCHDOG] timeout — possible AXI deadlock");
    $finish;
end

initial begin
    $dumpfile("tb_axi4_crossbar.vcd");
    $dumpvars(0, tb_axi4_crossbar);
end

endmodule
