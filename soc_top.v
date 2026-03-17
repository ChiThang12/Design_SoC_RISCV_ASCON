`include "cpu/riscv_cpu_core_v2.v"
`include "cpu/interface/icache/icache_top.v"
`include "cpu/interface/dcache/dcache_top.v"
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/memory_axi4full/data_mem_axi_slave.v"
`include "cpu/interconnect/axi4_crossbar_3m5s.v"
`include "ascon/ascon_top.v"
`include "axi_width_converter_64to32.v"
`include "controller/soc_ctrl_slave.v"
`include "clint.v"

module soc_top #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter ID_WIDTH      = 4,

    parameter IMEM_SIZE     = 8192,
    parameter DMEM_SIZE     = 8192,

    parameter IMEM_INIT_FILE = "cpu/memory_axi4full/program.hex",

    parameter [31:0] S0_BASE = 32'h0000_0000,
    parameter [31:0] S0_MASK = 32'hFFFF_E000,
    parameter [31:0] S1_BASE = 32'h1000_0000,
    parameter [31:0] S1_MASK = 32'hFFFF_E000,
    parameter [31:0] S2_BASE = 32'h2000_0000,
    parameter [31:0] S2_MASK = 32'hFFFF_F000,
    parameter [31:0] S3_BASE = 32'h3000_0000,
    parameter [31:0] S3_MASK = 32'hFFFF_F000,
    parameter [31:0] S4_BASE = 32'h4000_0000,
    parameter [31:0] S4_MASK = 32'hFFFF_0000
)(
    input  wire clk,
    input  wire ext_rst_n,
    output wire soft_rst_pulse
);

// ============================================================================
// Reset generation
// ============================================================================
wire fabric_rst_n = ext_rst_n;
wire cpu_rst      = ~ext_rst_n | soft_rst_pulse;

// ============================================================================
// mtime_tick prescaler: 100 MHz → 1 MHz
// ============================================================================
reg [6:0] prescaler_cnt;
reg       mtime_tick;

always @(posedge clk or negedge fabric_rst_n) begin
    if (!fabric_rst_n) begin
        prescaler_cnt <= 7'd0;
        mtime_tick    <= 1'b0;
    end else begin
        if (prescaler_cnt == 7'd99) begin
            prescaler_cnt <= 7'd0;
            mtime_tick    <= 1'b1;
        end else begin
            prescaler_cnt <= prescaler_cnt + 7'd1;
            mtime_tick    <= 1'b0;
        end
    end
end

// ============================================================================
// CPU ↔ ICache wires
// ============================================================================
wire [31:0] cpu_imem_addr;
wire        cpu_imem_valid;
wire [31:0] icache_imem_rdata;
wire        icache_imem_ready;

// ============================================================================
// CPU ↔ DCache wires
// ============================================================================
wire [31:0] cpu_dcache_addr;
wire [31:0] cpu_dcache_wdata;
wire [3:0]  cpu_dcache_wstrb;
wire        cpu_dcache_req;
wire        cpu_dcache_we;
wire [31:0] dcache_cpu_rdata;
wire        dcache_cpu_ready;
wire        cpu_dcache_fence;

// ============================================================================
// Interrupt wires
// ============================================================================
wire external_irq;
wire timer_irq;
wire sw_irq;
wire ascon_irq;

// ============================================================================
// ASCON AXI-Stream interface wires (unused in SoC — tied off)
// ============================================================================
wire [63:0] ascon_s_axis_tdata  = 64'h0;
wire        ascon_s_axis_tvalid = 1'b0;
wire        ascon_s_axis_tlast  = 1'b0;
wire        ascon_s_axis_tready;   // output — not connected upstream

wire [63:0] ascon_m_axis_tdata;    // outputs — available for future use
wire        ascon_m_axis_tvalid;
wire        ascon_m_axis_tlast;
wire        ascon_m_axis_tready = 1'b1;  // always consume

// ASCON tag parallel output wires
wire [127:0] ascon_o_tag;
wire         ascon_o_tag_valid;
wire         ascon_o_busy;

// ============================================================================
// ICache ↔ Crossbar M0 (AXI4)
// ============================================================================
wire [ID_WIDTH-1:0]   m0_arid;
wire [ADDR_WIDTH-1:0] m0_araddr;
wire [7:0]            m0_arlen;
wire [2:0]            m0_arsize;
wire [1:0]            m0_arburst;
wire [2:0]            m0_arprot;
wire                  m0_arvalid;
wire                  m0_arready;
wire [ID_WIDTH-1:0]   m0_rid;
wire [DATA_WIDTH-1:0] m0_rdata;
wire [1:0]            m0_rresp;
wire                  m0_rlast;
wire                  m0_rvalid;
wire                  m0_rready;
wire [ID_WIDTH-1:0]   m0_awid;
wire [ADDR_WIDTH-1:0] m0_awaddr;
wire [7:0]            m0_awlen;
wire [2:0]            m0_awsize;
wire [1:0]            m0_awburst;
wire [2:0]            m0_awprot;
wire                  m0_awvalid;
wire                  m0_awready;
wire [DATA_WIDTH-1:0] m0_wdata;
wire [DATA_WIDTH/8-1:0] m0_wstrb;
wire                  m0_wlast;
wire                  m0_wvalid;
wire                  m0_wready;
wire [ID_WIDTH-1:0]   m0_bid;
wire [1:0]            m0_bresp;
wire                  m0_bvalid;
wire                  m0_bready;

// ============================================================================
// DCache ↔ Crossbar M1 (AXI4)
// ============================================================================
wire [ID_WIDTH-1:0]   m1_arid;
wire [ADDR_WIDTH-1:0] m1_araddr;
wire [7:0]            m1_arlen;
wire [2:0]            m1_arsize;
wire [1:0]            m1_arburst;
wire [2:0]            m1_arprot;
wire                  m1_arvalid;
wire                  m1_arready;
wire [ID_WIDTH-1:0]   m1_rid;
wire [DATA_WIDTH-1:0] m1_rdata;
wire [1:0]            m1_rresp;
wire                  m1_rlast;
wire                  m1_rvalid;
wire                  m1_rready;
wire [ID_WIDTH-1:0]   m1_awid;
wire [ADDR_WIDTH-1:0] m1_awaddr;
wire [7:0]            m1_awlen;
wire [2:0]            m1_awsize;
wire [1:0]            m1_awburst;
wire [2:0]            m1_awprot;
wire                  m1_awvalid;
wire                  m1_awready;
wire [DATA_WIDTH-1:0] m1_wdata;
wire [DATA_WIDTH/8-1:0] m1_wstrb;
wire                  m1_wlast;
wire                  m1_wvalid;
wire                  m1_wready;
wire [ID_WIDTH-1:0]   m1_bid;
wire [1:0]            m1_bresp;
wire                  m1_bvalid;
wire                  m1_bready;

// ============================================================================
// DMA (width converter 32-bit out) ↔ Crossbar M2 (AXI4)
// ============================================================================
wire [ID_WIDTH-1:0]   m2_arid;
wire [ADDR_WIDTH-1:0] m2_araddr;
wire [7:0]            m2_arlen;
wire [2:0]            m2_arsize;
wire [1:0]            m2_arburst;
wire [2:0]            m2_arprot;
wire                  m2_arvalid;
wire                  m2_arready;
wire [ID_WIDTH-1:0]   m2_rid;
wire [DATA_WIDTH-1:0] m2_rdata;
wire [1:0]            m2_rresp;
wire                  m2_rlast;
wire                  m2_rvalid;
wire                  m2_rready;
wire [ID_WIDTH-1:0]   m2_awid;
wire [ADDR_WIDTH-1:0] m2_awaddr;
wire [7:0]            m2_awlen;
wire [2:0]            m2_awsize;
wire [1:0]            m2_awburst;
wire [2:0]            m2_awprot;
wire                  m2_awvalid;
wire                  m2_awready;
wire [DATA_WIDTH-1:0] m2_wdata;
wire [DATA_WIDTH/8-1:0] m2_wstrb;
wire                  m2_wlast;
wire                  m2_wvalid;
wire                  m2_wready;
wire [ID_WIDTH-1:0]   m2_bid;
wire [1:0]            m2_bresp;
wire                  m2_bvalid;
wire                  m2_bready;

// ============================================================================
// ASCON DMA 64-bit master wires
// ============================================================================
wire [ID_WIDTH-1:0]   dma_awid;
wire [ADDR_WIDTH-1:0] dma_awaddr;
wire [7:0]            dma_awlen;
wire [2:0]            dma_awsize;
wire [1:0]            dma_awburst;
wire [3:0]            dma_awcache;
wire [2:0]            dma_awprot;
wire                  dma_awvalid;
wire                  dma_awready;
wire [63:0]           dma_wdata;
wire [7:0]            dma_wstrb;
wire                  dma_wlast;
wire                  dma_wvalid;
wire                  dma_wready;
wire [ID_WIDTH-1:0]   dma_bid;
wire [1:0]            dma_bresp;
wire                  dma_bvalid;
wire                  dma_bready;
wire [ID_WIDTH-1:0]   dma_arid;
wire [ADDR_WIDTH-1:0] dma_araddr;
wire [7:0]            dma_arlen;
wire [2:0]            dma_arsize;
wire [1:0]            dma_arburst;
wire [3:0]            dma_arcache;
wire [2:0]            dma_arprot;
wire                  dma_arvalid;
wire                  dma_arready;
wire [ID_WIDTH-1:0]   dma_rid;
wire [63:0]           dma_rdata;
wire [1:0]            dma_rresp;
wire                  dma_rlast;
wire                  dma_rvalid;
wire                  dma_rready;

// ============================================================================
// Crossbar slave wires: S0–S4
// ============================================================================
wire [ID_WIDTH-1:0]   s0_arid;  wire [ADDR_WIDTH-1:0] s0_araddr; wire [7:0] s0_arlen;
wire [2:0] s0_arsize; wire [1:0] s0_arburst; wire [2:0] s0_arprot;
wire s0_arvalid; wire s0_arready;
wire [ID_WIDTH-1:0] s0_rid; wire [DATA_WIDTH-1:0] s0_rdata; wire [1:0] s0_rresp;
wire s0_rlast; wire s0_rvalid; wire s0_rready;
wire [ID_WIDTH-1:0] s0_awid; wire [ADDR_WIDTH-1:0] s0_awaddr; wire [7:0] s0_awlen;
wire [2:0] s0_awsize; wire [1:0] s0_awburst; wire [2:0] s0_awprot;
wire s0_awvalid; wire s0_awready;
wire [DATA_WIDTH-1:0] s0_wdata; wire [DATA_WIDTH/8-1:0] s0_wstrb;
wire s0_wlast; wire s0_wvalid; wire s0_wready;
wire [ID_WIDTH-1:0] s0_bid; wire [1:0] s0_bresp; wire s0_bvalid; wire s0_bready;

wire [ID_WIDTH-1:0]   s1_arid;  wire [ADDR_WIDTH-1:0] s1_araddr; wire [7:0] s1_arlen;
wire [2:0] s1_arsize; wire [1:0] s1_arburst; wire [2:0] s1_arprot;
wire s1_arvalid; wire s1_arready;
wire [ID_WIDTH-1:0] s1_rid; wire [DATA_WIDTH-1:0] s1_rdata; wire [1:0] s1_rresp;
wire s1_rlast; wire s1_rvalid; wire s1_rready;
wire [ID_WIDTH-1:0] s1_awid; wire [ADDR_WIDTH-1:0] s1_awaddr; wire [7:0] s1_awlen;
wire [2:0] s1_awsize; wire [1:0] s1_awburst; wire [2:0] s1_awprot;
wire s1_awvalid; wire s1_awready;
wire [DATA_WIDTH-1:0] s1_wdata; wire [DATA_WIDTH/8-1:0] s1_wstrb;
wire s1_wlast; wire s1_wvalid; wire s1_wready;
wire [ID_WIDTH-1:0] s1_bid; wire [1:0] s1_bresp; wire s1_bvalid; wire s1_bready;

wire [ID_WIDTH-1:0]   s2_arid;  wire [ADDR_WIDTH-1:0] s2_araddr; wire [7:0] s2_arlen;
wire [2:0] s2_arsize; wire [1:0] s2_arburst; wire [2:0] s2_arprot;
wire s2_arvalid; wire s2_arready;
wire [ID_WIDTH-1:0] s2_rid; wire [DATA_WIDTH-1:0] s2_rdata; wire [1:0] s2_rresp;
wire s2_rlast; wire s2_rvalid; wire s2_rready;
wire [ID_WIDTH-1:0] s2_awid; wire [ADDR_WIDTH-1:0] s2_awaddr; wire [7:0] s2_awlen;
wire [2:0] s2_awsize; wire [1:0] s2_awburst; wire [2:0] s2_awprot;
wire s2_awvalid; wire s2_awready;
wire [DATA_WIDTH-1:0] s2_wdata; wire [DATA_WIDTH/8-1:0] s2_wstrb;
wire s2_wlast; wire s2_wvalid; wire s2_wready;
wire [ID_WIDTH-1:0] s2_bid; wire [1:0] s2_bresp; wire s2_bvalid; wire s2_bready;

wire [ID_WIDTH-1:0]   s3_arid;  wire [ADDR_WIDTH-1:0] s3_araddr; wire [7:0] s3_arlen;
wire [2:0] s3_arsize; wire [1:0] s3_arburst; wire [2:0] s3_arprot;
wire s3_arvalid; wire s3_arready;
wire [ID_WIDTH-1:0] s3_rid; wire [DATA_WIDTH-1:0] s3_rdata; wire [1:0] s3_rresp;
wire s3_rlast; wire s3_rvalid; wire s3_rready;
wire [ID_WIDTH-1:0] s3_awid; wire [ADDR_WIDTH-1:0] s3_awaddr; wire [7:0] s3_awlen;
wire [2:0] s3_awsize; wire [1:0] s3_awburst; wire [2:0] s3_awprot;
wire s3_awvalid; wire s3_awready;
wire [DATA_WIDTH-1:0] s3_wdata; wire [DATA_WIDTH/8-1:0] s3_wstrb;
wire s3_wlast; wire s3_wvalid; wire s3_wready;
wire [ID_WIDTH-1:0] s3_bid; wire [1:0] s3_bresp; wire s3_bvalid; wire s3_bready;

wire [ID_WIDTH-1:0]   s4_arid;  wire [ADDR_WIDTH-1:0] s4_araddr; wire [7:0] s4_arlen;
wire [2:0] s4_arsize; wire [1:0] s4_arburst; wire [2:0] s4_arprot;
wire s4_arvalid; wire s4_arready;
wire [ID_WIDTH-1:0] s4_rid; wire [DATA_WIDTH-1:0] s4_rdata; wire [1:0] s4_rresp;
wire s4_rlast; wire s4_rvalid; wire s4_rready;
wire [ID_WIDTH-1:0] s4_awid; wire [ADDR_WIDTH-1:0] s4_awaddr; wire [7:0] s4_awlen;
wire [2:0] s4_awsize; wire [1:0] s4_awburst; wire [2:0] s4_awprot;
wire s4_awvalid; wire s4_awready;
wire [DATA_WIDTH-1:0] s4_wdata; wire [DATA_WIDTH/8-1:0] s4_wstrb;
wire s4_wlast; wire s4_wvalid; wire s4_wready;
wire [ID_WIDTH-1:0] s4_bid; wire [1:0] s4_bresp; wire s4_bvalid; wire s4_bready;

// ============================================================================
// Statistics wires
// ============================================================================
wire [31:0] icache_stat_hits;
wire [31:0] icache_stat_misses;
wire [31:0] dcache_stat_hits;
wire [31:0] dcache_stat_misses;
wire [31:0] dcache_stat_writes;

// ============================================================================
// INSTANCE: riscv_cpu_core
// ============================================================================
riscv_cpu_core u_cpu (
    .clk            (clk),
    .rst            (cpu_rst),

    .imem_addr      (cpu_imem_addr),
    .imem_valid     (cpu_imem_valid),
    .imem_rdata     (icache_imem_rdata),
    .imem_ready     (icache_imem_ready),

    .dcache_addr    (cpu_dcache_addr),
    .dcache_wdata   (cpu_dcache_wdata),
    .dcache_wstrb   (cpu_dcache_wstrb),
    .dcache_req     (cpu_dcache_req),
    .dcache_we      (cpu_dcache_we),
    .dcache_rdata   (dcache_cpu_rdata),
    .dcache_ready   (dcache_cpu_ready),
    .dcache_fence   (cpu_dcache_fence),

    .external_irq   (external_irq),
    .timer_irq      (timer_irq),
    .sw_irq         (sw_irq)
);

// ============================================================================
// INSTANCE: icache_top  (Master 0)
// ============================================================================
icache_top u_icache (
    .clk            (clk),
    .rst_n          (fabric_rst_n),

    .cpu_addr       (cpu_imem_addr),
    .cpu_req        (cpu_imem_valid),
    .cpu_rdata      (icache_imem_rdata),
    .cpu_ready      (icache_imem_ready),
    .flush          (1'b0),

    .mem_arid       (m0_arid),   .mem_araddr  (m0_araddr),
    .mem_arlen      (m0_arlen),  .mem_arsize  (m0_arsize),
    .mem_arburst    (m0_arburst),.mem_arprot  (m0_arprot),
    .mem_arvalid    (m0_arvalid),.mem_arready (m0_arready),
    .mem_rid        (m0_rid),    .mem_rdata   (m0_rdata),
    .mem_rresp      (m0_rresp),  .mem_rlast   (m0_rlast),
    .mem_rvalid     (m0_rvalid), .mem_rready  (m0_rready),
    .mem_awid       (m0_awid),   .mem_awaddr  (m0_awaddr),
    .mem_awlen      (m0_awlen),  .mem_awsize  (m0_awsize),
    .mem_awburst    (m0_awburst),.mem_awprot  (m0_awprot),
    .mem_awvalid    (m0_awvalid),.mem_awready (m0_awready),
    .mem_wdata      (m0_wdata),  .mem_wstrb   (m0_wstrb),
    .mem_wlast      (m0_wlast),  .mem_wvalid  (m0_wvalid),
    .mem_wready     (m0_wready),
    .mem_bid        (m0_bid),    .mem_bresp   (m0_bresp),
    .mem_bvalid     (m0_bvalid), .mem_bready  (m0_bready),

    .stat_hits      (icache_stat_hits),
    .stat_misses    (icache_stat_misses)
);

// ============================================================================
// INSTANCE: dcache_top  (Master 1)
// ============================================================================
dcache_top u_dcache (
    .clk            (clk),
    .rst_n          (fabric_rst_n),

    .cpu_addr       (cpu_dcache_addr),
    .cpu_wdata      (cpu_dcache_wdata),
    .cpu_wstrb      (cpu_dcache_wstrb),
    .cpu_req        (cpu_dcache_req),
    .cpu_we         (cpu_dcache_we),
    .cpu_rdata      (dcache_cpu_rdata),
    .cpu_ready      (dcache_cpu_ready),
    .fence          (cpu_dcache_fence),

    .current_addr   (),
    .current_data   (),
    .current_valid  (),

    .mem_arid       (m1_arid),   .mem_araddr  (m1_araddr),
    .mem_arlen      (m1_arlen),  .mem_arsize  (m1_arsize),
    .mem_arburst    (m1_arburst),.mem_arprot  (m1_arprot),
    .mem_arvalid    (m1_arvalid),.mem_arready (m1_arready),
    .mem_rid        (m1_rid),    .mem_rdata   (m1_rdata),
    .mem_rresp      (m1_rresp),  .mem_rlast   (m1_rlast),
    .mem_rvalid     (m1_rvalid), .mem_rready  (m1_rready),
    .mem_awid       (m1_awid),   .mem_awaddr  (m1_awaddr),
    .mem_awlen      (m1_awlen),  .mem_awsize  (m1_awsize),
    .mem_awburst    (m1_awburst),.mem_awprot  (m1_awprot),
    .mem_awvalid    (m1_awvalid),.mem_awready (m1_awready),
    .mem_wdata      (m1_wdata),  .mem_wstrb   (m1_wstrb),
    .mem_wlast      (m1_wlast),  .mem_wvalid  (m1_wvalid),
    .mem_wready     (m1_wready),
    .mem_bid        (m1_bid),    .mem_bresp   (m1_bresp),
    .mem_bvalid     (m1_bvalid), .mem_bready  (m1_bready),

    .stat_hits      (dcache_stat_hits),
    .stat_misses    (dcache_stat_misses),
    .stat_writes    (dcache_stat_writes)
);

// ============================================================================
// INSTANCE: ascon_ip_top  (S2 slave + DMA 64-bit master)
// ============================================================================
ascon_ip_top u_ascon (
    .clk            (clk),
    .rst_n          (fabric_rst_n),

    .S_AXI_AWID     (s2_awid),   .S_AXI_AWADDR  (s2_awaddr),
    .S_AXI_AWLEN    (s2_awlen),  .S_AXI_AWSIZE  (s2_awsize),
    .S_AXI_AWBURST  (s2_awburst),.S_AXI_AWPROT  (s2_awprot),
    .S_AXI_AWVALID  (s2_awvalid),.S_AXI_AWREADY (s2_awready),
    .S_AXI_WDATA    (s2_wdata),  .S_AXI_WSTRB   (s2_wstrb),
    .S_AXI_WLAST    (s2_wlast),  .S_AXI_WVALID  (s2_wvalid),
    .S_AXI_WREADY   (s2_wready),
    .S_AXI_BID      (s2_bid),    .S_AXI_BRESP   (s2_bresp),
    .S_AXI_BVALID   (s2_bvalid), .S_AXI_BREADY  (s2_bready),
    .S_AXI_ARID     (s2_arid),   .S_AXI_ARADDR  (s2_araddr),
    .S_AXI_ARLEN    (s2_arlen),  .S_AXI_ARSIZE  (s2_arsize),
    .S_AXI_ARBURST  (s2_arburst),.S_AXI_ARPROT  (s2_arprot),
    .S_AXI_ARVALID  (s2_arvalid),.S_AXI_ARREADY (s2_arready),
    .S_AXI_RID      (s2_rid),    .S_AXI_RDATA   (s2_rdata),
    .S_AXI_RRESP    (s2_rresp),  .S_AXI_RLAST   (s2_rlast),
    .S_AXI_RVALID   (s2_rvalid), .S_AXI_RREADY  (s2_rready),

    .M_AXI_AWID     (dma_awid),  .M_AXI_AWADDR  (dma_awaddr),
    .M_AXI_AWLEN    (dma_awlen), .M_AXI_AWSIZE  (dma_awsize),
    .M_AXI_AWBURST  (dma_awburst),.M_AXI_AWCACHE(dma_awcache),
    .M_AXI_AWPROT   (dma_awprot),.M_AXI_AWVALID (dma_awvalid),
    .M_AXI_AWREADY  (dma_awready),
    .M_AXI_WDATA    (dma_wdata), .M_AXI_WSTRB   (dma_wstrb),
    .M_AXI_WLAST    (dma_wlast), .M_AXI_WVALID  (dma_wvalid),
    .M_AXI_WREADY   (dma_wready),
    .M_AXI_BID      (dma_bid),   .M_AXI_BRESP   (dma_bresp),
    .M_AXI_BVALID   (dma_bvalid),.M_AXI_BREADY  (dma_bready),
    .M_AXI_ARID     (dma_arid),  .M_AXI_ARADDR  (dma_araddr),
    .M_AXI_ARLEN    (dma_arlen), .M_AXI_ARSIZE  (dma_arsize),
    .M_AXI_ARBURST  (dma_arburst),.M_AXI_ARCACHE(dma_arcache),
    .M_AXI_ARPROT   (dma_arprot),.M_AXI_ARVALID (dma_arvalid),
    .M_AXI_ARREADY  (dma_arready),
    .M_AXI_RID      (dma_rid),   .M_AXI_RDATA   (dma_rdata),
    .M_AXI_RRESP    (dma_rresp), .M_AXI_RLAST   (dma_rlast),
    .M_AXI_RVALID   (dma_rvalid),.M_AXI_RREADY  (dma_rready),

    // AXI4-Stream interface (tied off — SoC không dùng stream mode)
    .s_axis_tdata   (ascon_s_axis_tdata),
    .s_axis_tvalid  (ascon_s_axis_tvalid),
    .s_axis_tlast   (ascon_s_axis_tlast),
    .s_axis_tready  (ascon_s_axis_tready),
    .m_axis_tdata   (ascon_m_axis_tdata),
    .m_axis_tvalid  (ascon_m_axis_tvalid),
    .m_axis_tlast   (ascon_m_axis_tlast),
    .m_axis_tready  (ascon_m_axis_tready),

    // Tag parallel output
    .o_tag          (ascon_o_tag),
    .o_tag_valid    (ascon_o_tag_valid),
    .o_busy         (ascon_o_busy),

    .irq            (ascon_irq)
);

// ============================================================================
// INSTANCE: axi_width_converter_64to32
// ============================================================================
axi_width_converter_64to32 u_width_conv (
    .clk            (clk),
    .rst_n          (fabric_rst_n),

    .M_AXI_AWID     (dma_awid),  .M_AXI_AWADDR  (dma_awaddr),
    .M_AXI_AWLEN    (dma_awlen), .M_AXI_AWSIZE  (dma_awsize),
    .M_AXI_AWBURST  (dma_awburst),.M_AXI_AWCACHE(dma_awcache),
    .M_AXI_AWPROT   (dma_awprot),.M_AXI_AWVALID (dma_awvalid),
    .M_AXI_AWREADY  (dma_awready),
    .M_AXI_WDATA    (dma_wdata), .M_AXI_WSTRB   (dma_wstrb),
    .M_AXI_WLAST    (dma_wlast), .M_AXI_WVALID  (dma_wvalid),
    .M_AXI_WREADY   (dma_wready),
    .M_AXI_BID      (dma_bid),   .M_AXI_BRESP   (dma_bresp),
    .M_AXI_BVALID   (dma_bvalid),.M_AXI_BREADY  (dma_bready),
    .M_AXI_ARID     (dma_arid),  .M_AXI_ARADDR  (dma_araddr),
    .M_AXI_ARLEN    (dma_arlen), .M_AXI_ARSIZE  (dma_arsize),
    .M_AXI_ARBURST  (dma_arburst),.M_AXI_ARCACHE(dma_arcache),
    .M_AXI_ARPROT   (dma_arprot),.M_AXI_ARVALID (dma_arvalid),
    .M_AXI_ARREADY  (dma_arready),
    .M_AXI_RID      (dma_rid),   .M_AXI_RDATA   (dma_rdata),
    .M_AXI_RRESP    (dma_rresp), .M_AXI_RLAST   (dma_rlast),
    .M_AXI_RVALID   (dma_rvalid),.M_AXI_RREADY  (dma_rready),

    .S_AXI_AWID     (m2_awid),   .S_AXI_AWADDR  (m2_awaddr),
    .S_AXI_AWLEN    (m2_awlen),  .S_AXI_AWSIZE  (m2_awsize),
    .S_AXI_AWBURST  (m2_awburst),.S_AXI_AWPROT  (m2_awprot),
    .S_AXI_AWVALID  (m2_awvalid),.S_AXI_AWREADY (m2_awready),
    .S_AXI_WDATA    (m2_wdata),  .S_AXI_WSTRB   (m2_wstrb),
    .S_AXI_WLAST    (m2_wlast),  .S_AXI_WVALID  (m2_wvalid),
    .S_AXI_WREADY   (m2_wready),
    .S_AXI_BID      (m2_bid),    .S_AXI_BRESP   (m2_bresp),
    .S_AXI_BVALID   (m2_bvalid), .S_AXI_BREADY  (m2_bready),
    .S_AXI_ARID     (m2_arid),   .S_AXI_ARADDR  (m2_araddr),
    .S_AXI_ARLEN    (m2_arlen),  .S_AXI_ARSIZE  (m2_arsize),
    .S_AXI_ARBURST  (m2_arburst),.S_AXI_ARPROT  (m2_arprot),
    .S_AXI_ARVALID  (m2_arvalid),.S_AXI_ARREADY (m2_arready),
    .S_AXI_RID      (m2_rid),    .S_AXI_RDATA   (m2_rdata),
    .S_AXI_RRESP    (m2_rresp),  .S_AXI_RLAST   (m2_rlast),
    .S_AXI_RVALID   (m2_rvalid), .S_AXI_RREADY  (m2_rready)
);

// ============================================================================
// INSTANCE: axi4_crossbar_3m5s
// ============================================================================
axi4_crossbar_3m5s #(
    .DATA_WIDTH (DATA_WIDTH), .ADDR_WIDTH (ADDR_WIDTH), .ID_WIDTH (ID_WIDTH),
    .S0_BASE (S0_BASE), .S0_MASK (S0_MASK),
    .S1_BASE (S1_BASE), .S1_MASK (S1_MASK),
    .S2_BASE (S2_BASE), .S2_MASK (S2_MASK),
    .S3_BASE (S3_BASE), .S3_MASK (S3_MASK),
    .S4_BASE (S4_BASE), .S4_MASK (S4_MASK)
) u_crossbar (
    .clk    (clk),
    .rst_n  (fabric_rst_n),

    .M0_AXI_ARID    (m0_arid),   .M0_AXI_ARADDR (m0_araddr),
    .M0_AXI_ARLEN   (m0_arlen),  .M0_AXI_ARSIZE (m0_arsize),
    .M0_AXI_ARBURST (m0_arburst),.M0_AXI_ARPROT (m0_arprot),
    .M0_AXI_ARVALID (m0_arvalid),.M0_AXI_ARREADY(m0_arready),
    .M0_AXI_RID     (m0_rid),    .M0_AXI_RDATA  (m0_rdata),
    .M0_AXI_RRESP   (m0_rresp),  .M0_AXI_RLAST  (m0_rlast),
    .M0_AXI_RVALID  (m0_rvalid), .M0_AXI_RREADY (m0_rready),
    .M0_AXI_AWID    (m0_awid),   .M0_AXI_AWADDR (m0_awaddr),
    .M0_AXI_AWLEN   (m0_awlen),  .M0_AXI_AWSIZE (m0_awsize),
    .M0_AXI_AWBURST (m0_awburst),.M0_AXI_AWPROT (m0_awprot),
    .M0_AXI_AWVALID (m0_awvalid),.M0_AXI_AWREADY(m0_awready),
    .M0_AXI_WDATA   (m0_wdata),  .M0_AXI_WSTRB  (m0_wstrb),
    .M0_AXI_WLAST   (m0_wlast),  .M0_AXI_WVALID (m0_wvalid),
    .M0_AXI_WREADY  (m0_wready),
    .M0_AXI_BID     (m0_bid),    .M0_AXI_BRESP  (m0_bresp),
    .M0_AXI_BVALID  (m0_bvalid), .M0_AXI_BREADY (m0_bready),

    .M1_AXI_ARID    (m1_arid),   .M1_AXI_ARADDR (m1_araddr),
    .M1_AXI_ARLEN   (m1_arlen),  .M1_AXI_ARSIZE (m1_arsize),
    .M1_AXI_ARBURST (m1_arburst),.M1_AXI_ARPROT (m1_arprot),
    .M1_AXI_ARVALID (m1_arvalid),.M1_AXI_ARREADY(m1_arready),
    .M1_AXI_RID     (m1_rid),    .M1_AXI_RDATA  (m1_rdata),
    .M1_AXI_RRESP   (m1_rresp),  .M1_AXI_RLAST  (m1_rlast),
    .M1_AXI_RVALID  (m1_rvalid), .M1_AXI_RREADY (m1_rready),
    .M1_AXI_AWID    (m1_awid),   .M1_AXI_AWADDR (m1_awaddr),
    .M1_AXI_AWLEN   (m1_awlen),  .M1_AXI_AWSIZE (m1_awsize),
    .M1_AXI_AWBURST (m1_awburst),.M1_AXI_AWPROT (m1_awprot),
    .M1_AXI_AWVALID (m1_awvalid),.M1_AXI_AWREADY(m1_awready),
    .M1_AXI_WDATA   (m1_wdata),  .M1_AXI_WSTRB  (m1_wstrb),
    .M1_AXI_WLAST   (m1_wlast),  .M1_AXI_WVALID (m1_wvalid),
    .M1_AXI_WREADY  (m1_wready),
    .M1_AXI_BID     (m1_bid),    .M1_AXI_BRESP  (m1_bresp),
    .M1_AXI_BVALID  (m1_bvalid), .M1_AXI_BREADY (m1_bready),

    .M2_AXI_ARID    (m2_arid),   .M2_AXI_ARADDR (m2_araddr),
    .M2_AXI_ARLEN   (m2_arlen),  .M2_AXI_ARSIZE (m2_arsize),
    .M2_AXI_ARBURST (m2_arburst),.M2_AXI_ARPROT (m2_arprot),
    .M2_AXI_ARVALID (m2_arvalid),.M2_AXI_ARREADY(m2_arready),
    .M2_AXI_RID     (m2_rid),    .M2_AXI_RDATA  (m2_rdata),
    .M2_AXI_RRESP   (m2_rresp),  .M2_AXI_RLAST  (m2_rlast),
    .M2_AXI_RVALID  (m2_rvalid), .M2_AXI_RREADY (m2_rready),
    .M2_AXI_AWID    (m2_awid),   .M2_AXI_AWADDR (m2_awaddr),
    .M2_AXI_AWLEN   (m2_awlen),  .M2_AXI_AWSIZE (m2_awsize),
    .M2_AXI_AWBURST (m2_awburst),.M2_AXI_AWPROT (m2_awprot),
    .M2_AXI_AWVALID (m2_awvalid),.M2_AXI_AWREADY(m2_awready),
    .M2_AXI_WDATA   (m2_wdata),  .M2_AXI_WSTRB  (m2_wstrb),
    .M2_AXI_WLAST   (m2_wlast),  .M2_AXI_WVALID (m2_wvalid),
    .M2_AXI_WREADY  (m2_wready),
    .M2_AXI_BID     (m2_bid),    .M2_AXI_BRESP  (m2_bresp),
    .M2_AXI_BVALID  (m2_bvalid), .M2_AXI_BREADY (m2_bready),

    .S0_AXI_ARID    (s0_arid),   .S0_AXI_ARADDR (s0_araddr),
    .S0_AXI_ARLEN   (s0_arlen),  .S0_AXI_ARSIZE (s0_arsize),
    .S0_AXI_ARBURST (s0_arburst),.S0_AXI_ARPROT (s0_arprot),
    .S0_AXI_ARVALID (s0_arvalid),.S0_AXI_ARREADY(s0_arready),
    .S0_AXI_RID     (s0_rid),    .S0_AXI_RDATA  (s0_rdata),
    .S0_AXI_RRESP   (s0_rresp),  .S0_AXI_RLAST  (s0_rlast),
    .S0_AXI_RVALID  (s0_rvalid), .S0_AXI_RREADY (s0_rready),
    .S0_AXI_AWID    (s0_awid),   .S0_AXI_AWADDR (s0_awaddr),
    .S0_AXI_AWLEN   (s0_awlen),  .S0_AXI_AWSIZE (s0_awsize),
    .S0_AXI_AWBURST (s0_awburst),.S0_AXI_AWPROT (s0_awprot),
    .S0_AXI_AWVALID (s0_awvalid),.S0_AXI_AWREADY(s0_awready),
    .S0_AXI_WDATA   (s0_wdata),  .S0_AXI_WSTRB  (s0_wstrb),
    .S0_AXI_WLAST   (s0_wlast),  .S0_AXI_WVALID (s0_wvalid),
    .S0_AXI_WREADY  (s0_wready),
    .S0_AXI_BID     (s0_bid),    .S0_AXI_BRESP  (s0_bresp),
    .S0_AXI_BVALID  (s0_bvalid), .S0_AXI_BREADY (s0_bready),

    .S1_AXI_ARID    (s1_arid),   .S1_AXI_ARADDR (s1_araddr),
    .S1_AXI_ARLEN   (s1_arlen),  .S1_AXI_ARSIZE (s1_arsize),
    .S1_AXI_ARBURST (s1_arburst),.S1_AXI_ARPROT (s1_arprot),
    .S1_AXI_ARVALID (s1_arvalid),.S1_AXI_ARREADY(s1_arready),
    .S1_AXI_RID     (s1_rid),    .S1_AXI_RDATA  (s1_rdata),
    .S1_AXI_RRESP   (s1_rresp),  .S1_AXI_RLAST  (s1_rlast),
    .S1_AXI_RVALID  (s1_rvalid), .S1_AXI_RREADY (s1_rready),
    .S1_AXI_AWID    (s1_awid),   .S1_AXI_AWADDR (s1_awaddr),
    .S1_AXI_AWLEN   (s1_awlen),  .S1_AXI_AWSIZE (s1_awsize),
    .S1_AXI_AWBURST (s1_awburst),.S1_AXI_AWPROT (s1_awprot),
    .S1_AXI_AWVALID (s1_awvalid),.S1_AXI_AWREADY(s1_awready),
    .S1_AXI_WDATA   (s1_wdata),  .S1_AXI_WSTRB  (s1_wstrb),
    .S1_AXI_WLAST   (s1_wlast),  .S1_AXI_WVALID (s1_wvalid),
    .S1_AXI_WREADY  (s1_wready),
    .S1_AXI_BID     (s1_bid),    .S1_AXI_BRESP  (s1_bresp),
    .S1_AXI_BVALID  (s1_bvalid), .S1_AXI_BREADY (s1_bready),

    .S2_AXI_ARID    (s2_arid),   .S2_AXI_ARADDR (s2_araddr),
    .S2_AXI_ARLEN   (s2_arlen),  .S2_AXI_ARSIZE (s2_arsize),
    .S2_AXI_ARBURST (s2_arburst),.S2_AXI_ARPROT (s2_arprot),
    .S2_AXI_ARVALID (s2_arvalid),.S2_AXI_ARREADY(s2_arready),
    .S2_AXI_RID     (s2_rid),    .S2_AXI_RDATA  (s2_rdata),
    .S2_AXI_RRESP   (s2_rresp),  .S2_AXI_RLAST  (s2_rlast),
    .S2_AXI_RVALID  (s2_rvalid), .S2_AXI_RREADY (s2_rready),
    .S2_AXI_AWID    (s2_awid),   .S2_AXI_AWADDR (s2_awaddr),
    .S2_AXI_AWLEN   (s2_awlen),  .S2_AXI_AWSIZE (s2_awsize),
    .S2_AXI_AWBURST (s2_awburst),.S2_AXI_AWPROT (s2_awprot),
    .S2_AXI_AWVALID (s2_awvalid),.S2_AXI_AWREADY(s2_awready),
    .S2_AXI_WDATA   (s2_wdata),  .S2_AXI_WSTRB  (s2_wstrb),
    .S2_AXI_WLAST   (s2_wlast),  .S2_AXI_WVALID (s2_wvalid),
    .S2_AXI_WREADY  (s2_wready),
    .S2_AXI_BID     (s2_bid),    .S2_AXI_BRESP  (s2_bresp),
    .S2_AXI_BVALID  (s2_bvalid), .S2_AXI_BREADY (s2_bready),

    .S3_AXI_ARID    (s3_arid),   .S3_AXI_ARADDR (s3_araddr),
    .S3_AXI_ARLEN   (s3_arlen),  .S3_AXI_ARSIZE (s3_arsize),
    .S3_AXI_ARBURST (s3_arburst),.S3_AXI_ARPROT (s3_arprot),
    .S3_AXI_ARVALID (s3_arvalid),.S3_AXI_ARREADY(s3_arready),
    .S3_AXI_RID     (s3_rid),    .S3_AXI_RDATA  (s3_rdata),
    .S3_AXI_RRESP   (s3_rresp),  .S3_AXI_RLAST  (s3_rlast),
    .S3_AXI_RVALID  (s3_rvalid), .S3_AXI_RREADY (s3_rready),
    .S3_AXI_AWID    (s3_awid),   .S3_AXI_AWADDR (s3_awaddr),
    .S3_AXI_AWLEN   (s3_awlen),  .S3_AXI_AWSIZE (s3_awsize),
    .S3_AXI_AWBURST (s3_awburst),.S3_AXI_AWPROT (s3_awprot),
    .S3_AXI_AWVALID (s3_awvalid),.S3_AXI_AWREADY(s3_awready),
    .S3_AXI_WDATA   (s3_wdata),  .S3_AXI_WSTRB  (s3_wstrb),
    .S3_AXI_WLAST   (s3_wlast),  .S3_AXI_WVALID (s3_wvalid),
    .S3_AXI_WREADY  (s3_wready),
    .S3_AXI_BID     (s3_bid),    .S3_AXI_BRESP  (s3_bresp),
    .S3_AXI_BVALID  (s3_bvalid), .S3_AXI_BREADY (s3_bready),

    .S4_AXI_ARID    (s4_arid),   .S4_AXI_ARADDR (s4_araddr),
    .S4_AXI_ARLEN   (s4_arlen),  .S4_AXI_ARSIZE (s4_arsize),
    .S4_AXI_ARBURST (s4_arburst),.S4_AXI_ARPROT (s4_arprot),
    .S4_AXI_ARVALID (s4_arvalid),.S4_AXI_ARREADY(s4_arready),
    .S4_AXI_RID     (s4_rid),    .S4_AXI_RDATA  (s4_rdata),
    .S4_AXI_RRESP   (s4_rresp),  .S4_AXI_RLAST  (s4_rlast),
    .S4_AXI_RVALID  (s4_rvalid), .S4_AXI_RREADY (s4_rready),
    .S4_AXI_AWID    (s4_awid),   .S4_AXI_AWADDR (s4_awaddr),
    .S4_AXI_AWLEN   (s4_awlen),  .S4_AXI_AWSIZE (s4_awsize),
    .S4_AXI_AWBURST (s4_awburst),.S4_AXI_AWPROT (s4_awprot),
    .S4_AXI_AWVALID (s4_awvalid),.S4_AXI_AWREADY(s4_awready),
    .S4_AXI_WDATA   (s4_wdata),  .S4_AXI_WSTRB  (s4_wstrb),
    .S4_AXI_WLAST   (s4_wlast),  .S4_AXI_WVALID (s4_wvalid),
    .S4_AXI_WREADY  (s4_wready),
    .S4_AXI_BID     (s4_bid),    .S4_AXI_BRESP  (s4_bresp),
    .S4_AXI_BVALID  (s4_bvalid), .S4_AXI_BREADY (s4_bready)
);

// ============================================================================
// INSTANCE: inst_mem_axi_slave  (S0)
// ============================================================================
inst_mem_axi_slave #(
    .ADDR_WIDTH    (ADDR_WIDTH), .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH      (ID_WIDTH),   .MEM_SIZE   (IMEM_SIZE),
    .MEM_INIT_FILE (IMEM_INIT_FILE)
) u_imem (
    .clk            (clk),
    .rst_n          (fabric_rst_n),
    .S_AXI_AWID     (s0_awid),   .S_AXI_AWADDR  (s0_awaddr),
    .S_AXI_AWLEN    (s0_awlen),  .S_AXI_AWSIZE  (s0_awsize),
    .S_AXI_AWBURST  (s0_awburst),.S_AXI_AWPROT  (s0_awprot),
    .S_AXI_AWVALID  (s0_awvalid),.S_AXI_AWREADY (s0_awready),
    .S_AXI_WDATA    (s0_wdata),  .S_AXI_WSTRB   (s0_wstrb),
    .S_AXI_WLAST    (s0_wlast),  .S_AXI_WVALID  (s0_wvalid),
    .S_AXI_WREADY   (s0_wready),
    .S_AXI_BID      (s0_bid),    .S_AXI_BRESP   (s0_bresp),
    .S_AXI_BVALID   (s0_bvalid), .S_AXI_BREADY  (s0_bready),
    .S_AXI_ARID     (s0_arid),   .S_AXI_ARADDR  (s0_araddr),
    .S_AXI_ARLEN    (s0_arlen),  .S_AXI_ARSIZE  (s0_arsize),
    .S_AXI_ARBURST  (s0_arburst),.S_AXI_ARPROT  (s0_arprot),
    .S_AXI_ARVALID  (s0_arvalid),.S_AXI_ARREADY (s0_arready),
    .S_AXI_RID      (s0_rid),    .S_AXI_RDATA   (s0_rdata),
    .S_AXI_RRESP    (s0_rresp),  .S_AXI_RLAST   (s0_rlast),
    .S_AXI_RVALID   (s0_rvalid), .S_AXI_RREADY  (s0_rready)
);

// ============================================================================
// INSTANCE: data_mem_axi4_slave  (S1)
// ============================================================================
data_mem_axi4_slave #(
    .ADDR_WIDTH (ADDR_WIDTH), .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH),   .MEM_SIZE   (DMEM_SIZE)
) u_dmem (
    .clk            (clk),
    .rst_n          (fabric_rst_n),
    .S_AXI_AWID     (s1_awid),   .S_AXI_AWADDR  (s1_awaddr),
    .S_AXI_AWLEN    (s1_awlen),  .S_AXI_AWSIZE  (s1_awsize),
    .S_AXI_AWBURST  (s1_awburst),.S_AXI_AWPROT  (s1_awprot),
    .S_AXI_AWVALID  (s1_awvalid),.S_AXI_AWREADY (s1_awready),
    .S_AXI_WDATA    (s1_wdata),  .S_AXI_WSTRB   (s1_wstrb),
    .S_AXI_WLAST    (s1_wlast),  .S_AXI_WVALID  (s1_wvalid),
    .S_AXI_WREADY   (s1_wready),
    .S_AXI_BID      (s1_bid),    .S_AXI_BRESP   (s1_bresp),
    .S_AXI_BVALID   (s1_bvalid), .S_AXI_BREADY  (s1_bready),
    .S_AXI_ARID     (s1_arid),   .S_AXI_ARADDR  (s1_araddr),
    .S_AXI_ARLEN    (s1_arlen),  .S_AXI_ARSIZE  (s1_arsize),
    .S_AXI_ARBURST  (s1_arburst),.S_AXI_ARPROT  (s1_arprot),
    .S_AXI_ARVALID  (s1_arvalid),.S_AXI_ARREADY (s1_arready),
    .S_AXI_RID      (s1_rid),    .S_AXI_RDATA   (s1_rdata),
    .S_AXI_RRESP    (s1_rresp),  .S_AXI_RLAST   (s1_rlast),
    .S_AXI_RVALID   (s1_rvalid), .S_AXI_RREADY  (s1_rready)
);

// ============================================================================
// INSTANCE: soc_ctrl_slave  (S3)
// ============================================================================
soc_ctrl_slave #(
    .ADDR_WIDTH (ADDR_WIDTH), .DATA_WIDTH (DATA_WIDTH), .ID_WIDTH (ID_WIDTH)
) u_soc_ctrl (
    .clk            (clk),
    .rst_n          (fabric_rst_n),
    .S_AXI_AWID     (s3_awid),   .S_AXI_AWADDR  (s3_awaddr),
    .S_AXI_AWLEN    (s3_awlen),  .S_AXI_AWSIZE  (s3_awsize),
    .S_AXI_AWBURST  (s3_awburst),.S_AXI_AWPROT  (s3_awprot),
    .S_AXI_AWVALID  (s3_awvalid),.S_AXI_AWREADY (s3_awready),
    .S_AXI_WDATA    (s3_wdata),  .S_AXI_WSTRB   (s3_wstrb),
    .S_AXI_WLAST    (s3_wlast),  .S_AXI_WVALID  (s3_wvalid),
    .S_AXI_WREADY   (s3_wready),
    .S_AXI_BID      (s3_bid),    .S_AXI_BRESP   (s3_bresp),
    .S_AXI_BVALID   (s3_bvalid), .S_AXI_BREADY  (s3_bready),
    .S_AXI_ARID     (s3_arid),   .S_AXI_ARADDR  (s3_araddr),
    .S_AXI_ARLEN    (s3_arlen),  .S_AXI_ARSIZE  (s3_arsize),
    .S_AXI_ARBURST  (s3_arburst),.S_AXI_ARPROT  (s3_arprot),
    .S_AXI_ARVALID  (s3_arvalid),.S_AXI_ARREADY (s3_arready),
    .S_AXI_RID      (s3_rid),    .S_AXI_RDATA   (s3_rdata),
    .S_AXI_RRESP    (s3_rresp),  .S_AXI_RLAST   (s3_rlast),
    .S_AXI_RVALID   (s3_rvalid), .S_AXI_RREADY  (s3_rready),
    .icache_hits    (icache_stat_hits),
    .icache_misses  (icache_stat_misses),
    .dcache_hits    (dcache_stat_hits),
    .dcache_misses  (dcache_stat_misses),
    .dcache_writes  (dcache_stat_writes),
    .ascon_irq      (ascon_irq),
    .irq_out        (external_irq),
    .soft_rst_pulse (soft_rst_pulse)
);

// ============================================================================
// INSTANCE: clint  (S4)
// ============================================================================
clint #(
    .ADDR_WIDTH (ADDR_WIDTH), .DATA_WIDTH (DATA_WIDTH), .ID_WIDTH (ID_WIDTH)
) u_clint (
    .clk            (clk),
    .rst_n          (fabric_rst_n),
    .mtime_tick     (mtime_tick),
    .S_AXI_AWID     (s4_awid),   .S_AXI_AWADDR  (s4_awaddr),
    .S_AXI_AWLEN    (s4_awlen),  .S_AXI_AWSIZE  (s4_awsize),
    .S_AXI_AWBURST  (s4_awburst),.S_AXI_AWPROT  (s4_awprot),
    .S_AXI_AWVALID  (s4_awvalid),.S_AXI_AWREADY (s4_awready),
    .S_AXI_WDATA    (s4_wdata),  .S_AXI_WSTRB   (s4_wstrb),
    .S_AXI_WLAST    (s4_wlast),  .S_AXI_WVALID  (s4_wvalid),
    .S_AXI_WREADY   (s4_wready),
    .S_AXI_BID      (s4_bid),    .S_AXI_BRESP   (s4_bresp),
    .S_AXI_BVALID   (s4_bvalid), .S_AXI_BREADY  (s4_bready),
    .S_AXI_ARID     (s4_arid),   .S_AXI_ARADDR  (s4_araddr),
    .S_AXI_ARLEN    (s4_arlen),  .S_AXI_ARSIZE  (s4_arsize),
    .S_AXI_ARBURST  (s4_arburst),.S_AXI_ARPROT  (s4_arprot),
    .S_AXI_ARVALID  (s4_arvalid),.S_AXI_ARREADY (s4_arready),
    .S_AXI_RID      (s4_rid),    .S_AXI_RDATA   (s4_rdata),
    .S_AXI_RRESP    (s4_rresp),  .S_AXI_RLAST   (s4_rlast),
    .S_AXI_RVALID   (s4_rvalid), .S_AXI_RREADY  (s4_rready),
    .timer_irq      (timer_irq),
    .sw_irq         (sw_irq)
);

endmodule