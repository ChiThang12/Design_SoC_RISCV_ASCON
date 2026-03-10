// ============================================================================
// soc_top.v  —  RISC-V SoC Top-Level Integration
// ============================================================================
//
// Topology:
//
//   ┌─────────────────────────────────────────────────────────────────┐
//   │                        soc_top                                  │
//   │                                                                 │
//   │  ┌──────────────┐    imem_*   ┌────────────┐                   │
//   │  │ riscv_cpu    │ ──────────► │ icache_top │ (M0)──┐           │
//   │  │   _core      │             └────────────┘       │           │
//   │  │              │    dcache_* ┌────────────┐       │  ┌──────────────────┐
//   │  │              │ ──────────► │ dcache_top │ (M1)──┼─►│axi4_crossbar_3m4s│
//   │  └──────────────┘             └────────────┘       │  │                  │
//   │                                                    │  │  S0→inst_mem     │
//   │  ┌──────────────────────────────────────────┐      │  │  S1→data_mem     │
//   │  │           ascon_ip_top                   │      │  │  S2→ascon (lite) │
//   │  │  S_AXI (AXI4-Lite) ◄── crossbar S2 ─────┼──────┘  │  S3→soc_ctrl     │
//   │  │  M_AXI (AXI4-Full) ──► crossbar M2 ──────┼──────┬─►│                  │
//   │  │  irq ──────────────────────────────────   │      │  └──────────────────┘
//   │  └──────────────────────────────────────────┘      │
//   │                                                     │  (M2 = ASCON DMA)
//   └─────────────────────────────────────────────────────┘
//
// Memory Map (từ crossbar):
//   S0: IMEM  (inst_mem_axi_slave)   0x0000_0000 – 0x0000_FFFF
//   S1: DMEM  (data_mem_axi4_slave)  0x1000_0000 – 0x1000_FFFF
//   S2: ASCON (ascon_ip_top)         0x2000_0000 – 0x2000_0FFF  (AXI4-Lite bridge)
//   S3: SoC Ctrl (stub)              0x3000_0000 – 0x3000_0FFF
//
// Lưu ý giao thức:
//   - Crossbar S2 là AXI4-Full; ascon_ip_top.S_AXI là AXI4-Lite.
//     Một bridge đơn giản (axi4full_to_lite_bridge) được nhúng bên trong
//     module này để chuyển đổi (chỉ forward beat đầu, AWLEN/ARLEN = 0).
//   - data_mem_axi4_slave không có port ID → ID bị bỏ qua (tied/ignored).
//   - ASCON DMA master (M_AXI, 64-bit) kết nối vào crossbar M2 (32-bit).
//     DATA_WIDTH mismatch: crossbar là 32-bit, DMA master là 64-bit.
//     Xem cảnh báo bên dưới — cần width adapter nếu dùng DMA mode.
//
// Parameters:
//   AXI_ID_WIDTH   : ID width dùng trong crossbar (default 4, phải >= 3)
//   IMEM_INIT_FILE : Đường dẫn file hex khởi tạo instruction memory
//   IMEM_SIZE      : Kích thước IMEM tính bằng words (default 4096)
//   DMEM_SIZE      : Kích thước DMEM tính bằng words (default 8192)
//
// Cảnh báo:
//   [W1] ASCON DMA M_AXI là 64-bit nhưng crossbar M2 là 32-bit.
//        Module này tie off M2 width ở 32-bit; DMA mode sẽ cần width bridge.
//        Nếu chỉ dùng CPU-Direct mode (dma_en=0), không ảnh hưởng.
//   [W2] S3 (SoC Ctrl) chưa có slave thực — đây là stub trả DECERR.
//        Thay bằng module SoC Ctrl thực tế khi cần.
// ============================================================================
`include "cpu/riscv_cpu_core_v2.v"
`include "cpu/interface/icache/icache_top.v"
`include "cpu/interface/dcache/dcache_top.v"
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/memory_axi4full/data_mem_axi_slave.v"
`include "cpu/interconnect/axi4_crossbar_3m4s.v"
`include "ascon_accelerator/ascon_top.v"
`include "axi_width_converter_64to32.v"


module soc_top #(
    parameter AXI_ID_WIDTH   = 4,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,

    parameter IMEM_INIT_FILE = "cpu/memory_axi4full/program.hex",
    parameter IMEM_SIZE      = 4096,
    parameter DMEM_SIZE      = 8192
)(
    input  wire clk,
    input  wire rst_n,

    // Cache statistics (cho testbench)
    output wire [31:0] icache_hits,
    output wire [31:0] icache_misses,
    output wire [31:0] dcache_hits,
    output wire [31:0] dcache_misses,
    output wire [31:0] dcache_writes,

    // Interrupt output (từ ASCON) ra ngoài SoC
    output wire ascon_irq
);

    // ========================================================================
    // Local parameters
    // ========================================================================
    localparam STRB_WIDTH = AXI_DATA_WIDTH / 8;

    // ========================================================================
    // CPU ↔ ICache wires
    // ========================================================================
    wire [31:0] cpu_imem_addr;
    wire        cpu_imem_valid;
    wire [31:0] cpu_imem_rdata;
    wire        cpu_imem_ready;

    // ========================================================================
    // CPU ↔ DCache wires
    // ========================================================================
    wire [31:0] cpu_dcache_addr;
    wire [31:0] cpu_dcache_wdata;
    wire [3:0]  cpu_dcache_wstrb;
    wire        cpu_dcache_req;
    wire        cpu_dcache_we;
    wire [31:0] cpu_dcache_rdata;
    wire        cpu_dcache_ready;

    // ========================================================================
    // ICache ↔ Crossbar M0 (AXI4 Full)
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   ic_m_arid,   ic_m_awid;
    wire [AXI_ADDR_WIDTH-1:0] ic_m_araddr, ic_m_awaddr;
    wire [7:0]                ic_m_arlen,  ic_m_awlen;
    wire [2:0]                ic_m_arsize, ic_m_awsize;
    wire [1:0]                ic_m_arburst,ic_m_awburst;
    wire [2:0]                ic_m_arprot, ic_m_awprot;
    wire                      ic_m_arvalid,ic_m_awvalid;
    wire                      ic_m_arready,ic_m_awready;

    wire [AXI_ID_WIDTH-1:0]   ic_m_rid,    ic_m_bid;
    wire [AXI_DATA_WIDTH-1:0] ic_m_rdata;
    wire [1:0]                ic_m_rresp,  ic_m_bresp;
    wire                      ic_m_rlast,  ic_m_bvalid;
    wire                      ic_m_rvalid, ic_m_bready;
    wire                      ic_m_rready;

    wire [AXI_DATA_WIDTH-1:0] ic_m_wdata;
    wire [STRB_WIDTH-1:0]     ic_m_wstrb;
    wire                      ic_m_wlast, ic_m_wvalid, ic_m_wready;

    // ========================================================================
    // DCache ↔ Crossbar M1 (AXI4 Full)
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   dc_m_arid,   dc_m_awid;
    wire [AXI_ADDR_WIDTH-1:0] dc_m_araddr, dc_m_awaddr;
    wire [7:0]                dc_m_arlen,  dc_m_awlen;
    wire [2:0]                dc_m_arsize, dc_m_awsize;
    wire [1:0]                dc_m_arburst,dc_m_awburst;
    wire [2:0]                dc_m_arprot, dc_m_awprot;
    wire                      dc_m_arvalid,dc_m_awvalid;
    wire                      dc_m_arready,dc_m_awready;

    wire [AXI_ID_WIDTH-1:0]   dc_m_rid,    dc_m_bid;
    wire [AXI_DATA_WIDTH-1:0] dc_m_rdata;
    wire [1:0]                dc_m_rresp,  dc_m_bresp;
    wire                      dc_m_rlast,  dc_m_bvalid;
    wire                      dc_m_rvalid, dc_m_bready;
    wire                      dc_m_rready;

    wire [AXI_DATA_WIDTH-1:0] dc_m_wdata;
    wire [STRB_WIDTH-1:0]     dc_m_wstrb;
    wire                      dc_m_wlast, dc_m_wvalid, dc_m_wready;

    // ========================================================================
    // ASCON DMA ↔ axi_width_converter_64to32 (Master side, 64-bit)
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   ascon_m_arid,   ascon_m_awid;
    wire [AXI_ADDR_WIDTH-1:0] ascon_m_araddr, ascon_m_awaddr;
    wire [7:0]                ascon_m_arlen,  ascon_m_awlen;
    wire [2:0]                ascon_m_arsize, ascon_m_awsize;
    wire [1:0]                ascon_m_arburst,ascon_m_awburst;
    wire [2:0]                ascon_m_arprot, ascon_m_awprot;
    wire [3:0]                ascon_m_arcache,ascon_m_awcache;
    wire                      ascon_m_arvalid,ascon_m_awvalid;
    wire                      ascon_m_arready,ascon_m_awready;

    wire [AXI_ID_WIDTH-1:0]   ascon_m_rid,    ascon_m_bid;
    wire [63:0]               ascon_m_rdata;   // 64-bit native
    wire [1:0]                ascon_m_rresp,   ascon_m_bresp;
    wire                      ascon_m_rlast,   ascon_m_bvalid;
    wire                      ascon_m_rvalid,  ascon_m_bready;
    wire                      ascon_m_rready;

    wire [63:0]               ascon_m_wdata;   // 64-bit native
    wire [7:0]                ascon_m_wstrb;
    wire                      ascon_m_wlast, ascon_m_wvalid, ascon_m_wready;

    // ========================================================================
    // axi_width_converter_64to32 ↔ Crossbar M2 (Slave side, 32-bit)
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   wconv_m_arid,   wconv_m_awid;
    wire [AXI_ADDR_WIDTH-1:0] wconv_m_araddr, wconv_m_awaddr;
    wire [7:0]                wconv_m_arlen,  wconv_m_awlen;
    wire [2:0]                wconv_m_arsize, wconv_m_awsize;
    wire [1:0]                wconv_m_arburst,wconv_m_awburst;
    wire [2:0]                wconv_m_arprot, wconv_m_awprot;
    wire                      wconv_m_arvalid,wconv_m_awvalid;
    wire                      wconv_m_arready,wconv_m_awready;

    wire [AXI_ID_WIDTH-1:0]   wconv_m_rid,    wconv_m_bid;
    wire [AXI_DATA_WIDTH-1:0] wconv_m_rdata;
    wire [1:0]                wconv_m_rresp,  wconv_m_bresp;
    wire                      wconv_m_rlast,  wconv_m_bvalid;
    wire                      wconv_m_rvalid, wconv_m_bready;
    wire                      wconv_m_rready;

    wire [AXI_DATA_WIDTH-1:0] wconv_m_wdata;
    wire [STRB_WIDTH-1:0]     wconv_m_wstrb;
    wire                      wconv_m_wlast, wconv_m_wvalid, wconv_m_wready;

    // ========================================================================
    // Crossbar ↔ IMEM S0
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   s0_arid,   s0_awid;
    wire [AXI_ADDR_WIDTH-1:0] s0_araddr, s0_awaddr;
    wire [7:0]                s0_arlen,  s0_awlen;
    wire [2:0]                s0_arsize, s0_awsize;
    wire [1:0]                s0_arburst,s0_awburst;
    wire [2:0]                s0_arprot, s0_awprot;
    wire                      s0_arvalid,s0_awvalid;
    wire                      s0_arready,s0_awready;

    wire [AXI_ID_WIDTH-1:0]   s0_rid,    s0_bid;
    wire [AXI_DATA_WIDTH-1:0] s0_rdata;
    wire [1:0]                s0_rresp,  s0_bresp;
    wire                      s0_rlast,  s0_bvalid;
    wire                      s0_rvalid, s0_bready;
    wire                      s0_rready;

    wire [AXI_DATA_WIDTH-1:0] s0_wdata;
    wire [STRB_WIDTH-1:0]     s0_wstrb;
    wire                      s0_wlast, s0_wvalid, s0_wready;

    // ========================================================================
    // Crossbar ↔ DMEM S1
    // NOTE: data_mem_axi4_slave không có ID ports — ID tie-off/ignored
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   s1_awid_nc, s1_arid_nc; // not connected to slave
    wire [AXI_ADDR_WIDTH-1:0] s1_araddr, s1_awaddr;
    wire [7:0]                s1_arlen,  s1_awlen;
    wire [2:0]                s1_arsize, s1_awsize;
    wire [1:0]                s1_arburst,s1_awburst;
    wire [2:0]                s1_arprot, s1_awprot;
    wire                      s1_arvalid,s1_awvalid;
    wire                      s1_arready,s1_awready;

    wire [AXI_ID_WIDTH-1:0]   s1_rid_nc,  s1_bid_nc;  // driven by stub
    wire [AXI_DATA_WIDTH-1:0] s1_rdata;
    wire [1:0]                s1_rresp,   s1_bresp;
    wire                      s1_rlast,   s1_bvalid;
    wire                      s1_rvalid,  s1_bready;
    wire                      s1_rready;

    wire [AXI_DATA_WIDTH-1:0] s1_wdata;
    wire [STRB_WIDTH-1:0]     s1_wstrb;
    wire                      s1_wlast, s1_wvalid, s1_wready;

    // ========================================================================
    // Crossbar ↔ ASCON S2 (AXI4-Full side; bridge to Lite inside this module)
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   s2_arid,   s2_awid;
    wire [AXI_ADDR_WIDTH-1:0] s2_araddr, s2_awaddr;
    wire [7:0]                s2_arlen,  s2_awlen;     // Lite bridge drops these
    wire [2:0]                s2_arsize, s2_awsize;
    wire [1:0]                s2_arburst,s2_awburst;
    wire [2:0]                s2_arprot, s2_awprot;
    wire                      s2_arvalid,s2_awvalid;
    wire                      s2_arready,s2_awready;

    wire [AXI_ID_WIDTH-1:0]   s2_rid,    s2_bid;
    wire [AXI_DATA_WIDTH-1:0] s2_rdata;
    wire [1:0]                s2_rresp,  s2_bresp;
    wire                      s2_rlast,  s2_bvalid;
    wire                      s2_rvalid, s2_bready;
    wire                      s2_rready;

    wire [AXI_DATA_WIDTH-1:0] s2_wdata;
    wire [STRB_WIDTH-1:0]     s2_wstrb;
    wire                      s2_wlast, s2_wvalid, s2_wready;

    // ========================================================================
    // Crossbar ↔ SoC Ctrl S3 (stub — trả DECERR cho mọi access)
    // ========================================================================
    wire [AXI_ID_WIDTH-1:0]   s3_arid,   s3_awid;
    wire [AXI_ADDR_WIDTH-1:0] s3_araddr, s3_awaddr;
    wire [7:0]                s3_arlen,  s3_awlen;
    wire [2:0]                s3_arsize, s3_awsize;
    wire [1:0]                s3_arburst,s3_awburst;
    wire [2:0]                s3_arprot, s3_awprot;
    wire                      s3_arvalid,s3_awvalid;
    wire                      s3_arready,s3_awready;

    wire [AXI_ID_WIDTH-1:0]   s3_rid,    s3_bid;
    wire [AXI_DATA_WIDTH-1:0] s3_rdata;
    wire [1:0]                s3_rresp,  s3_bresp;
    wire                      s3_rlast,  s3_bvalid;
    wire                      s3_rvalid, s3_bready;
    wire                      s3_rready;

    wire [AXI_DATA_WIDTH-1:0] s3_wdata;
    wire [STRB_WIDTH-1:0]     s3_wstrb;
    wire                      s3_wlast, s3_wvalid, s3_wready;

    // ========================================================================
    // Testbench-visible wire aliases
    // Testbench tap: soc.m0_*, soc.m1_*, soc.m2_*, soc.s0..s3_*
    // ========================================================================

    // M0 = ICache
    wire [AXI_ID_WIDTH-1:0]   m0_arid    = ic_m_arid;
    wire [AXI_ADDR_WIDTH-1:0] m0_araddr  = ic_m_araddr;
    wire [7:0]                m0_arlen   = ic_m_arlen;
    wire [2:0]                m0_arsize  = ic_m_arsize;
    wire [1:0]                m0_arburst = ic_m_arburst;
    wire                      m0_arvalid = ic_m_arvalid;
    wire                      m0_arready = ic_m_arready;
    wire [AXI_ID_WIDTH-1:0]   m0_rid     = ic_m_rid;
    wire [AXI_DATA_WIDTH-1:0] m0_rdata   = ic_m_rdata;
    wire [1:0]                m0_rresp   = ic_m_rresp;
    wire                      m0_rlast   = ic_m_rlast;
    wire                      m0_rvalid  = ic_m_rvalid;
    wire                      m0_rready  = ic_m_rready;
    wire                      m0_awvalid = ic_m_awvalid;
    wire [AXI_ADDR_WIDTH-1:0] m0_awaddr  = ic_m_awaddr;
    wire [1:0]                m0_bresp   = ic_m_bresp;
    wire                      m0_bvalid  = ic_m_bvalid;

    // M1 = DCache
    wire [AXI_ID_WIDTH-1:0]   m1_arid    = dc_m_arid;
    wire [AXI_ADDR_WIDTH-1:0] m1_araddr  = dc_m_araddr;
    wire [7:0]                m1_arlen   = dc_m_arlen;
    wire [2:0]                m1_arsize  = dc_m_arsize;
    wire [1:0]                m1_arburst = dc_m_arburst;
    wire                      m1_arvalid = dc_m_arvalid;
    wire                      m1_arready = dc_m_arready;
    wire [AXI_ID_WIDTH-1:0]   m1_rid     = dc_m_rid;
    wire [AXI_DATA_WIDTH-1:0] m1_rdata   = dc_m_rdata;
    wire [1:0]                m1_rresp   = dc_m_rresp;
    wire                      m1_rlast   = dc_m_rlast;
    wire                      m1_rvalid  = dc_m_rvalid;
    wire                      m1_rready  = dc_m_rready;
    wire [AXI_ID_WIDTH-1:0]   m1_awid    = dc_m_awid;
    wire [AXI_ADDR_WIDTH-1:0] m1_awaddr  = dc_m_awaddr;
    wire [7:0]                m1_awlen   = dc_m_awlen;
    wire [2:0]                m1_awsize  = dc_m_awsize;
    wire [1:0]                m1_awburst = dc_m_awburst;
    wire                      m1_awvalid = dc_m_awvalid;
    wire                      m1_awready = dc_m_awready;
    wire [AXI_DATA_WIDTH-1:0] m1_wdata   = dc_m_wdata;
    wire [STRB_WIDTH-1:0]     m1_wstrb   = dc_m_wstrb;
    wire                      m1_wlast   = dc_m_wlast;
    wire                      m1_wvalid  = dc_m_wvalid;
    wire                      m1_wready  = dc_m_wready;
    wire [AXI_ID_WIDTH-1:0]   m1_bid     = dc_m_bid;
    wire [1:0]                m1_bresp   = dc_m_bresp;
    wire                      m1_bvalid  = dc_m_bvalid;
    wire                      m1_bready  = dc_m_bready;

    // M2 = ASCON DMA (wconv side = 32-bit, crossbar-facing)
    wire [AXI_ID_WIDTH-1:0]   m2_arid    = wconv_m_arid;
    wire [AXI_ADDR_WIDTH-1:0] m2_araddr  = wconv_m_araddr;
    wire [7:0]                m2_arlen   = wconv_m_arlen;
    wire [2:0]                m2_arsize  = wconv_m_arsize;
    wire [1:0]                m2_arburst = wconv_m_arburst;
    wire                      m2_arvalid = wconv_m_arvalid;
    wire                      m2_arready = wconv_m_arready;
    wire [AXI_ID_WIDTH-1:0]   m2_rid     = wconv_m_rid;
    wire [AXI_DATA_WIDTH-1:0] m2_rdata   = wconv_m_rdata;
    wire [1:0]                m2_rresp   = wconv_m_rresp;
    wire                      m2_rlast   = wconv_m_rlast;
    wire                      m2_rvalid  = wconv_m_rvalid;
    wire                      m2_rready  = wconv_m_rready;
    wire [AXI_ID_WIDTH-1:0]   m2_awid    = wconv_m_awid;
    wire [AXI_ADDR_WIDTH-1:0] m2_awaddr  = wconv_m_awaddr;
    wire [7:0]                m2_awlen   = wconv_m_awlen;
    wire [2:0]                m2_awsize  = wconv_m_awsize;
    wire [1:0]                m2_awburst = wconv_m_awburst;
    wire                      m2_awvalid = wconv_m_awvalid;
    wire                      m2_awready = wconv_m_awready;
    wire [AXI_DATA_WIDTH-1:0] m2_wdata   = wconv_m_wdata;
    wire [STRB_WIDTH-1:0]     m2_wstrb   = wconv_m_wstrb;
    wire                      m2_wlast   = wconv_m_wlast;
    wire                      m2_wvalid  = wconv_m_wvalid;
    wire                      m2_wready  = wconv_m_wready;
    wire [AXI_ID_WIDTH-1:0]   m2_bid     = wconv_m_bid;
    wire [1:0]                m2_bresp   = wconv_m_bresp;
    wire                      m2_bvalid  = wconv_m_bvalid;
    wire                      m2_bready  = wconv_m_bready;


    riscv_cpu_core cpu   (
        .clk           (clk),
        .rst           (~rst_n),  // CPU dùng active-high reset

        // Instruction memory interface → ICache
        .imem_addr     (cpu_imem_addr),
        .imem_valid    (cpu_imem_valid),
        .imem_rdata    (cpu_imem_rdata),
        .imem_ready    (cpu_imem_ready),

        // Data cache interface → DCache
        .dcache_addr   (cpu_dcache_addr),
        .dcache_wdata  (cpu_dcache_wdata),
        .dcache_wstrb  (cpu_dcache_wstrb),
        .dcache_req    (cpu_dcache_req),
        .dcache_we     (cpu_dcache_we),
        .dcache_rdata  (cpu_dcache_rdata),
        .dcache_ready  (cpu_dcache_ready)
    );

    // ========================================================================
    // [2] Instruction Cache
    // ========================================================================
    icache_top u_icache (
        .clk           (clk),
        .rst_n         (rst_n),

        // CPU side
        .cpu_addr      (cpu_imem_addr),
        .cpu_req       (cpu_imem_valid),
        .cpu_rdata     (cpu_imem_rdata),
        .cpu_ready     (cpu_imem_ready),
        .flush         (1'b0),          // Tie off: flush từ CPU nếu cần

        // AXI4 master → Crossbar M0
        .mem_arid      (ic_m_arid),
        .mem_araddr    (ic_m_araddr),
        .mem_arlen     (ic_m_arlen),
        .mem_arsize    (ic_m_arsize),
        .mem_arburst   (ic_m_arburst),
        .mem_arprot    (ic_m_arprot),
        .mem_arvalid   (ic_m_arvalid),
        .mem_arready   (ic_m_arready),

        .mem_rid       (ic_m_rid),
        .mem_rdata     (ic_m_rdata),
        .mem_rresp     (ic_m_rresp),
        .mem_rlast     (ic_m_rlast),
        .mem_rvalid    (ic_m_rvalid),
        .mem_rready    (ic_m_rready),

        .mem_awid      (ic_m_awid),
        .mem_awaddr    (ic_m_awaddr),
        .mem_awlen     (ic_m_awlen),
        .mem_awsize    (ic_m_awsize),
        .mem_awburst   (ic_m_awburst),
        .mem_awprot    (ic_m_awprot),
        .mem_awvalid   (ic_m_awvalid),
        .mem_awready   (ic_m_awready),

        .mem_wdata     (ic_m_wdata),
        .mem_wstrb     (ic_m_wstrb),
        .mem_wlast     (ic_m_wlast),
        .mem_wvalid    (ic_m_wvalid),
        .mem_wready    (ic_m_wready),

        .mem_bid       (ic_m_bid),
        .mem_bresp     (ic_m_bresp),
        .mem_bvalid    (ic_m_bvalid),
        .mem_bready    (ic_m_bready),

        .stat_hits     (icache_hits),
        .stat_misses   (icache_misses)
    );

    // ========================================================================
    // [3] Data Cache
    // ========================================================================
    dcache_top u_dcache (
        .clk           (clk),
        .rst_n         (rst_n),

        // CPU side
        .cpu_addr      (cpu_dcache_addr),
        .cpu_wdata     (cpu_dcache_wdata),
        .cpu_wstrb     (cpu_dcache_wstrb),
        .cpu_req       (cpu_dcache_req),
        .cpu_we        (cpu_dcache_we),
        .cpu_rdata     (cpu_dcache_rdata),
        .cpu_ready     (cpu_dcache_ready),
        .fence         (1'b0),          // Tie off: fence.i / fence từ CPU nếu cần

        // Debug (không kết nối)
        .current_addr  (),
        .current_data  (),
        .current_valid (),

        // AXI4 master → Crossbar M1
        .mem_arid      (dc_m_arid),
        .mem_araddr    (dc_m_araddr),
        .mem_arlen     (dc_m_arlen),
        .mem_arsize    (dc_m_arsize),
        .mem_arburst   (dc_m_arburst),
        .mem_arprot    (dc_m_arprot),
        .mem_arvalid   (dc_m_arvalid),
        .mem_arready   (dc_m_arready),

        .mem_rid       (dc_m_rid),
        .mem_rdata     (dc_m_rdata),
        .mem_rresp     (dc_m_rresp),
        .mem_rlast     (dc_m_rlast),
        .mem_rvalid    (dc_m_rvalid),
        .mem_rready    (dc_m_rready),

        .mem_awid      (dc_m_awid),
        .mem_awaddr    (dc_m_awaddr),
        .mem_awlen     (dc_m_awlen),
        .mem_awsize    (dc_m_awsize),
        .mem_awburst   (dc_m_awburst),
        .mem_awprot    (dc_m_awprot),
        .mem_awvalid   (dc_m_awvalid),
        .mem_awready   (dc_m_awready),

        .mem_wdata     (dc_m_wdata),
        .mem_wstrb     (dc_m_wstrb),
        .mem_wlast     (dc_m_wlast),
        .mem_wvalid    (dc_m_wvalid),
        .mem_wready    (dc_m_wready),

        .mem_bid       (dc_m_bid),
        .mem_bresp     (dc_m_bresp),
        .mem_bvalid    (dc_m_bvalid),
        .mem_bready    (dc_m_bready),

        // Statistics → module output ports
        .stat_hits     (dcache_hits),
        .stat_misses   (dcache_misses),
        .stat_writes   (dcache_writes)
    );

    // ========================================================================
    // [4] AXI4 Crossbar 3M × 4S
    //     M0 = ICache, M1 = DCache, M2 = ASCON DMA
    //     S0 = IMEM,   S1 = DMEM,   S2 = ASCON,  S3 = SoC Ctrl
    // ========================================================================
    axi4_crossbar_3m4s #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH)
        // Giữ nguyên default address map
    ) xbar (
        .clk        (clk),
        .rst_n      (rst_n),

        // ── Master 0: ICache ─────────────────────────────────────────────
        .M0_AXI_ARID    (ic_m_arid),
        .M0_AXI_ARADDR  (ic_m_araddr),
        .M0_AXI_ARLEN   (ic_m_arlen),
        .M0_AXI_ARSIZE  (ic_m_arsize),
        .M0_AXI_ARBURST (ic_m_arburst),
        .M0_AXI_ARPROT  (ic_m_arprot),
        .M0_AXI_ARVALID (ic_m_arvalid),
        .M0_AXI_ARREADY (ic_m_arready),

        .M0_AXI_RID     (ic_m_rid),
        .M0_AXI_RDATA   (ic_m_rdata),
        .M0_AXI_RRESP   (ic_m_rresp),
        .M0_AXI_RLAST   (ic_m_rlast),
        .M0_AXI_RVALID  (ic_m_rvalid),
        .M0_AXI_RREADY  (ic_m_rready),

        .M0_AXI_AWID    (ic_m_awid),
        .M0_AXI_AWADDR  (ic_m_awaddr),
        .M0_AXI_AWLEN   (ic_m_awlen),
        .M0_AXI_AWSIZE  (ic_m_awsize),
        .M0_AXI_AWBURST (ic_m_awburst),
        .M0_AXI_AWPROT  (ic_m_awprot),
        .M0_AXI_AWVALID (ic_m_awvalid),
        .M0_AXI_AWREADY (ic_m_awready),

        .M0_AXI_WDATA   (ic_m_wdata),
        .M0_AXI_WSTRB   (ic_m_wstrb),
        .M0_AXI_WLAST   (ic_m_wlast),
        .M0_AXI_WVALID  (ic_m_wvalid),
        .M0_AXI_WREADY  (ic_m_wready),

        .M0_AXI_BID     (ic_m_bid),
        .M0_AXI_BRESP   (ic_m_bresp),
        .M0_AXI_BVALID  (ic_m_bvalid),
        .M0_AXI_BREADY  (ic_m_bready),

        // ── Master 1: DCache ─────────────────────────────────────────────
        .M1_AXI_ARID    (dc_m_arid),
        .M1_AXI_ARADDR  (dc_m_araddr),
        .M1_AXI_ARLEN   (dc_m_arlen),
        .M1_AXI_ARSIZE  (dc_m_arsize),
        .M1_AXI_ARBURST (dc_m_arburst),
        .M1_AXI_ARPROT  (dc_m_arprot),
        .M1_AXI_ARVALID (dc_m_arvalid),
        .M1_AXI_ARREADY (dc_m_arready),

        .M1_AXI_RID     (dc_m_rid),
        .M1_AXI_RDATA   (dc_m_rdata),
        .M1_AXI_RRESP   (dc_m_rresp),
        .M1_AXI_RLAST   (dc_m_rlast),
        .M1_AXI_RVALID  (dc_m_rvalid),
        .M1_AXI_RREADY  (dc_m_rready),

        .M1_AXI_AWID    (dc_m_awid),
        .M1_AXI_AWADDR  (dc_m_awaddr),
        .M1_AXI_AWLEN   (dc_m_awlen),
        .M1_AXI_AWSIZE  (dc_m_awsize),
        .M1_AXI_AWBURST (dc_m_awburst),
        .M1_AXI_AWPROT  (dc_m_awprot),
        .M1_AXI_AWVALID (dc_m_awvalid),
        .M1_AXI_AWREADY (dc_m_awready),

        .M1_AXI_WDATA   (dc_m_wdata),
        .M1_AXI_WSTRB   (dc_m_wstrb),
        .M1_AXI_WLAST   (dc_m_wlast),
        .M1_AXI_WVALID  (dc_m_wvalid),
        .M1_AXI_WREADY  (dc_m_wready),

        .M1_AXI_BID     (dc_m_bid),
        .M1_AXI_BRESP   (dc_m_bresp),
        .M1_AXI_BVALID  (dc_m_bvalid),
        .M1_AXI_BREADY  (dc_m_bready),

        // ── Master 2: Width Converter output (32-bit) → Crossbar M2 ─────────
        .M2_AXI_ARID    (wconv_m_arid),
        .M2_AXI_ARADDR  (wconv_m_araddr),
        .M2_AXI_ARLEN   (wconv_m_arlen),
        .M2_AXI_ARSIZE  (wconv_m_arsize),
        .M2_AXI_ARBURST (wconv_m_arburst),
        .M2_AXI_ARPROT  (wconv_m_arprot),
        .M2_AXI_ARVALID (wconv_m_arvalid),
        .M2_AXI_ARREADY (wconv_m_arready),

        .M2_AXI_RID     (wconv_m_rid),
        .M2_AXI_RDATA   (wconv_m_rdata),
        .M2_AXI_RRESP   (wconv_m_rresp),
        .M2_AXI_RLAST   (wconv_m_rlast),
        .M2_AXI_RVALID  (wconv_m_rvalid),
        .M2_AXI_RREADY  (wconv_m_rready),

        .M2_AXI_AWID    (wconv_m_awid),
        .M2_AXI_AWADDR  (wconv_m_awaddr),
        .M2_AXI_AWLEN   (wconv_m_awlen),
        .M2_AXI_AWSIZE  (wconv_m_awsize),
        .M2_AXI_AWBURST (wconv_m_awburst),
        .M2_AXI_AWPROT  (wconv_m_awprot),
        .M2_AXI_AWVALID (wconv_m_awvalid),
        .M2_AXI_AWREADY (wconv_m_awready),

        .M2_AXI_WDATA   (wconv_m_wdata),
        .M2_AXI_WSTRB   (wconv_m_wstrb),
        .M2_AXI_WLAST   (wconv_m_wlast),
        .M2_AXI_WVALID  (wconv_m_wvalid),
        .M2_AXI_WREADY  (wconv_m_wready),

        .M2_AXI_BID     (wconv_m_bid),
        .M2_AXI_BRESP   (wconv_m_bresp),
        .M2_AXI_BVALID  (wconv_m_bvalid),
        .M2_AXI_BREADY  (wconv_m_bready),

        // ── Slave 0: IMEM ────────────────────────────────────────────────
        .S0_AXI_ARID    (s0_arid),
        .S0_AXI_ARADDR  (s0_araddr),
        .S0_AXI_ARLEN   (s0_arlen),
        .S0_AXI_ARSIZE  (s0_arsize),
        .S0_AXI_ARBURST (s0_arburst),
        .S0_AXI_ARPROT  (s0_arprot),
        .S0_AXI_ARVALID (s0_arvalid),
        .S0_AXI_ARREADY (s0_arready),

        .S0_AXI_RID     (s0_rid),
        .S0_AXI_RDATA   (s0_rdata),
        .S0_AXI_RRESP   (s0_rresp),
        .S0_AXI_RLAST   (s0_rlast),
        .S0_AXI_RVALID  (s0_rvalid),
        .S0_AXI_RREADY  (s0_rready),

        .S0_AXI_AWID    (s0_awid),
        .S0_AXI_AWADDR  (s0_awaddr),
        .S0_AXI_AWLEN   (s0_awlen),
        .S0_AXI_AWSIZE  (s0_awsize),
        .S0_AXI_AWBURST (s0_awburst),
        .S0_AXI_AWPROT  (s0_awprot),
        .S0_AXI_AWVALID (s0_awvalid),
        .S0_AXI_AWREADY (s0_awready),

        .S0_AXI_WDATA   (s0_wdata),
        .S0_AXI_WSTRB   (s0_wstrb),
        .S0_AXI_WLAST   (s0_wlast),
        .S0_AXI_WVALID  (s0_wvalid),
        .S0_AXI_WREADY  (s0_wready),

        .S0_AXI_BID     (s0_bid),
        .S0_AXI_BRESP   (s0_bresp),
        .S0_AXI_BVALID  (s0_bvalid),
        .S0_AXI_BREADY  (s0_bready),

        // ── Slave 1: DMEM ────────────────────────────────────────────────
        .S1_AXI_ARID    (s1_arid_nc),
        .S1_AXI_ARADDR  (s1_araddr),
        .S1_AXI_ARLEN   (s1_arlen),
        .S1_AXI_ARSIZE  (s1_arsize),
        .S1_AXI_ARBURST (s1_arburst),
        .S1_AXI_ARPROT  (s1_arprot),
        .S1_AXI_ARVALID (s1_arvalid),
        .S1_AXI_ARREADY (s1_arready),

        .S1_AXI_RID     (s1_rid_nc),
        .S1_AXI_RDATA   (s1_rdata),
        .S1_AXI_RRESP   (s1_rresp),
        .S1_AXI_RLAST   (s1_rlast),
        .S1_AXI_RVALID  (s1_rvalid),
        .S1_AXI_RREADY  (s1_rready),

        .S1_AXI_AWID    (s1_awid_nc),
        .S1_AXI_AWADDR  (s1_awaddr),
        .S1_AXI_AWLEN   (s1_awlen),
        .S1_AXI_AWSIZE  (s1_awsize),
        .S1_AXI_AWBURST (s1_awburst),
        .S1_AXI_AWPROT  (s1_awprot),
        .S1_AXI_AWVALID (s1_awvalid),
        .S1_AXI_AWREADY (s1_awready),

        .S1_AXI_WDATA   (s1_wdata),
        .S1_AXI_WSTRB   (s1_wstrb),
        .S1_AXI_WLAST   (s1_wlast),
        .S1_AXI_WVALID  (s1_wvalid),
        .S1_AXI_WREADY  (s1_wready),

        .S1_AXI_BID     (s1_bid_nc),
        .S1_AXI_BRESP   (s1_bresp),
        .S1_AXI_BVALID  (s1_bvalid),
        .S1_AXI_BREADY  (s1_bready),

        // ── Slave 2: ASCON ───────────────────────────────────────────────
        .S2_AXI_ARID    (s2_arid),
        .S2_AXI_ARADDR  (s2_araddr),
        .S2_AXI_ARLEN   (s2_arlen),
        .S2_AXI_ARSIZE  (s2_arsize),
        .S2_AXI_ARBURST (s2_arburst),
        .S2_AXI_ARPROT  (s2_arprot),
        .S2_AXI_ARVALID (s2_arvalid),
        .S2_AXI_ARREADY (s2_arready),

        .S2_AXI_RID     (s2_rid),
        .S2_AXI_RDATA   (s2_rdata),
        .S2_AXI_RRESP   (s2_rresp),
        .S2_AXI_RLAST   (s2_rlast),
        .S2_AXI_RVALID  (s2_rvalid),
        .S2_AXI_RREADY  (s2_rready),

        .S2_AXI_AWID    (s2_awid),
        .S2_AXI_AWADDR  (s2_awaddr),
        .S2_AXI_AWLEN   (s2_awlen),
        .S2_AXI_AWSIZE  (s2_awsize),
        .S2_AXI_AWBURST (s2_awburst),
        .S2_AXI_AWPROT  (s2_awprot),
        .S2_AXI_AWVALID (s2_awvalid),
        .S2_AXI_AWREADY (s2_awready),

        .S2_AXI_WDATA   (s2_wdata),
        .S2_AXI_WSTRB   (s2_wstrb),
        .S2_AXI_WLAST   (s2_wlast),
        .S2_AXI_WVALID  (s2_wvalid),
        .S2_AXI_WREADY  (s2_wready),

        .S2_AXI_BID     (s2_bid),
        .S2_AXI_BRESP   (s2_bresp),
        .S2_AXI_BVALID  (s2_bvalid),
        .S2_AXI_BREADY  (s2_bready),

        // ── Slave 3: SoC Ctrl stub ───────────────────────────────────────
        .S3_AXI_ARID    (s3_arid),
        .S3_AXI_ARADDR  (s3_araddr),
        .S3_AXI_ARLEN   (s3_arlen),
        .S3_AXI_ARSIZE  (s3_arsize),
        .S3_AXI_ARBURST (s3_arburst),
        .S3_AXI_ARPROT  (s3_arprot),
        .S3_AXI_ARVALID (s3_arvalid),
        .S3_AXI_ARREADY (s3_arready),

        .S3_AXI_RID     (s3_rid),
        .S3_AXI_RDATA   (s3_rdata),
        .S3_AXI_RRESP   (s3_rresp),
        .S3_AXI_RLAST   (s3_rlast),
        .S3_AXI_RVALID  (s3_rvalid),
        .S3_AXI_RREADY  (s3_rready),

        .S3_AXI_AWID    (s3_awid),
        .S3_AXI_AWADDR  (s3_awaddr),
        .S3_AXI_AWLEN   (s3_awlen),
        .S3_AXI_AWSIZE  (s3_awsize),
        .S3_AXI_AWBURST (s3_awburst),
        .S3_AXI_AWPROT  (s3_awprot),
        .S3_AXI_AWVALID (s3_awvalid),
        .S3_AXI_AWREADY (s3_awready),

        .S3_AXI_WDATA   (s3_wdata),
        .S3_AXI_WSTRB   (s3_wstrb),
        .S3_AXI_WLAST   (s3_wlast),
        .S3_AXI_WVALID  (s3_wvalid),
        .S3_AXI_WREADY  (s3_wready),

        .S3_AXI_BID     (s3_bid),
        .S3_AXI_BRESP   (s3_bresp),
        .S3_AXI_BVALID  (s3_bvalid),
        .S3_AXI_BREADY  (s3_bready)
    );

    // ========================================================================
    // [5] Instruction Memory (AXI4 Full Slave)
    // ========================================================================
    inst_mem_axi_slave #(
        .ADDR_WIDTH    (AXI_ADDR_WIDTH),
        .DATA_WIDTH    (AXI_DATA_WIDTH),
        .ID_WIDTH      (AXI_ID_WIDTH),
        .MEM_SIZE      (IMEM_SIZE),
        .MEM_INIT_FILE (IMEM_INIT_FILE)
    ) imem (
        .clk           (clk),
        .rst_n         (rst_n),

        .S_AXI_AWID    (s0_awid),
        .S_AXI_AWADDR  (s0_awaddr),
        .S_AXI_AWLEN   (s0_awlen),
        .S_AXI_AWSIZE  (s0_awsize),
        .S_AXI_AWBURST (s0_awburst),
        .S_AXI_AWPROT  (s0_awprot),
        .S_AXI_AWVALID (s0_awvalid),
        .S_AXI_AWREADY (s0_awready),

        .S_AXI_WDATA   (s0_wdata),
        .S_AXI_WSTRB   (s0_wstrb),
        .S_AXI_WLAST   (s0_wlast),
        .S_AXI_WVALID  (s0_wvalid),
        .S_AXI_WREADY  (s0_wready),

        .S_AXI_BID     (s0_bid),
        .S_AXI_BRESP   (s0_bresp),
        .S_AXI_BVALID  (s0_bvalid),
        .S_AXI_BREADY  (s0_bready),

        .S_AXI_ARID    (s0_arid),
        .S_AXI_ARADDR  (s0_araddr),
        .S_AXI_ARLEN   (s0_arlen),
        .S_AXI_ARSIZE  (s0_arsize),
        .S_AXI_ARBURST (s0_arburst),
        .S_AXI_ARPROT  (s0_arprot),
        .S_AXI_ARVALID (s0_arvalid),
        .S_AXI_ARREADY (s0_arready),

        .S_AXI_RID     (s0_rid),
        .S_AXI_RDATA   (s0_rdata),
        .S_AXI_RRESP   (s0_rresp),
        .S_AXI_RLAST   (s0_rlast),
        .S_AXI_RVALID  (s0_rvalid),
        .S_AXI_RREADY  (s0_rready)
    );

    // ========================================================================
    // [6] Data Memory (AXI4 Full Slave — không có ID ports)
    // ========================================================================
    data_mem_axi4_slave #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH),
        .MEM_SIZE   (DMEM_SIZE)
    ) dmem (
        .clk           (clk),
        .rst_n         (rst_n),

        .S_AXI_AWID    (s1_awid_nc),
        .S_AXI_AWADDR  (s1_awaddr),
        .S_AXI_AWLEN   (s1_awlen),
        .S_AXI_AWSIZE  (s1_awsize),
        .S_AXI_AWBURST (s1_awburst),
        .S_AXI_AWPROT  (s1_awprot),
        .S_AXI_AWVALID (s1_awvalid),
        .S_AXI_AWREADY (s1_awready),

        .S_AXI_WDATA   (s1_wdata),
        .S_AXI_WSTRB   (s1_wstrb),
        .S_AXI_WLAST   (s1_wlast),
        .S_AXI_WVALID  (s1_wvalid),
        .S_AXI_WREADY  (s1_wready),

        .S_AXI_BRESP   (s1_bresp),
        .S_AXI_BVALID  (s1_bvalid),
        .S_AXI_BREADY  (s1_bready),

        .S_AXI_ARADDR  (s1_araddr),
        .S_AXI_ARLEN   (s1_arlen),
        .S_AXI_ARSIZE  (s1_arsize),
        .S_AXI_ARBURST (s1_arburst),
        .S_AXI_ARPROT  (s1_arprot),
        .S_AXI_ARVALID (s1_arvalid),
        .S_AXI_ARREADY (s1_arready),

        .S_AXI_RID     (s1_rid_nc),
        .S_AXI_RDATA   (s1_rdata),
        .S_AXI_RRESP   (s1_rresp),
        .S_AXI_RLAST   (s1_rlast),
        .S_AXI_RVALID  (s1_rvalid),
        .S_AXI_RREADY  (s1_rready)
    );
    // s1_rid_nc / s1_bid_nc được drive từ data_mem_axi4_slave (đã có port sau khi fix [W2])

    // ========================================================================
    // [7] ASCON IP Top
    //
    // S_AXI: AXI4-Lite slave từ crossbar S2.
    //   Bridge nội bộ: crossbar phát AXI4-Full (có AWLEN/ARLEN) nhưng
    //   ASCON slave chỉ nhận AXI4-Lite (AWLEN/ARLEN không có).
    //   Điều này ổn vì CPU chỉ truy cập ASCON bằng 1-beat transaction
    //   (AWLEN=0, ARLEN=0). Các signal AWLEN/ARLEN từ crossbar bị bỏ qua.
    //
    // M_AXI: AXI4-Full master 64-bit từ ASCON DMA → crossbar M2 (32-bit).
    //   Xem [W1] — chỉ kết nối 32-bit thấp.
    // ========================================================================
    ascon_ip_top #(
        .S_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .S_DATA_WIDTH (AXI_DATA_WIDTH),
        .S_ID_WIDTH   (AXI_ID_WIDTH),
        .M_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .M_DATA_WIDTH (64),              // Native 64-bit DMA master
        .M_ID_WIDTH   (AXI_ID_WIDTH)
    ) u_ascon_ip (
        .clk  (clk),
        .rst_n(rst_n),

        // ── S_AXI: Lite slave (kết nối với crossbar S2) ──────────────────
        .S_AXI_AWID    (s2_awid),
        .S_AXI_AWADDR  (s2_awaddr),
        .S_AXI_AWLEN   (s2_awlen),    // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_AWSIZE  (s2_awsize),   // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_AWBURST (s2_awburst),  // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_AWPROT  (s2_awprot),
        .S_AXI_AWVALID (s2_awvalid),
        .S_AXI_AWREADY (s2_awready),

        .S_AXI_WDATA   (s2_wdata),
        .S_AXI_WSTRB   (s2_wstrb),
        .S_AXI_WLAST   (s2_wlast),    // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_WVALID  (s2_wvalid),
        .S_AXI_WREADY  (s2_wready),

        .S_AXI_BID     (s2_bid),
        .S_AXI_BRESP   (s2_bresp),
        .S_AXI_BVALID  (s2_bvalid),
        .S_AXI_BREADY  (s2_bready),

        .S_AXI_ARID    (s2_arid),
        .S_AXI_ARADDR  (s2_araddr),
        .S_AXI_ARLEN   (s2_arlen),    // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_ARSIZE  (s2_arsize),   // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_ARBURST (s2_arburst),  // AXI4-Full compat — port mới trong ascon_top
        .S_AXI_ARPROT  (s2_arprot),
        .S_AXI_ARVALID (s2_arvalid),
        .S_AXI_ARREADY (s2_arready),

        .S_AXI_RID     (s2_rid),
        .S_AXI_RDATA   (s2_rdata),
        .S_AXI_RRESP   (s2_rresp),
        .S_AXI_RLAST   (s2_rlast),
        .S_AXI_RVALID  (s2_rvalid),
        .S_AXI_RREADY  (s2_rready),

        // ── M_AXI: Full master 64-bit → Width Converter ───────────────────
        .M_AXI_AWID    (ascon_m_awid),
        .M_AXI_AWADDR  (ascon_m_awaddr),
        .M_AXI_AWLEN   (ascon_m_awlen),
        .M_AXI_AWSIZE  (ascon_m_awsize),
        .M_AXI_AWBURST (ascon_m_awburst),
        .M_AXI_AWCACHE (ascon_m_awcache),
        .M_AXI_AWPROT  (ascon_m_awprot),
        .M_AXI_AWVALID (ascon_m_awvalid),
        .M_AXI_AWREADY (ascon_m_awready),

        .M_AXI_WDATA   (ascon_m_wdata),
        .M_AXI_WSTRB   (ascon_m_wstrb),
        .M_AXI_WLAST   (ascon_m_wlast),
        .M_AXI_WVALID  (ascon_m_wvalid),
        .M_AXI_WREADY  (ascon_m_wready),

        .M_AXI_BID     (ascon_m_bid),
        .M_AXI_BRESP   (ascon_m_bresp),
        .M_AXI_BVALID  (ascon_m_bvalid),
        .M_AXI_BREADY  (ascon_m_bready),

        .M_AXI_ARID    (ascon_m_arid),
        .M_AXI_ARADDR  (ascon_m_araddr),
        .M_AXI_ARLEN   (ascon_m_arlen),
        .M_AXI_ARSIZE  (ascon_m_arsize),
        .M_AXI_ARBURST (ascon_m_arburst),
        .M_AXI_ARCACHE (ascon_m_arcache),
        .M_AXI_ARPROT  (ascon_m_arprot),
        .M_AXI_ARVALID (ascon_m_arvalid),
        .M_AXI_ARREADY (ascon_m_arready),

        .M_AXI_RID     (ascon_m_rid),
        .M_AXI_RDATA   (ascon_m_rdata),
        .M_AXI_RRESP   (ascon_m_rresp),
        .M_AXI_RLAST   (ascon_m_rlast),
        .M_AXI_RVALID  (ascon_m_rvalid),
        .M_AXI_RREADY  (ascon_m_rready),

        // Interrupt
        .irq           (ascon_irq)
    );

    // ========================================================================
    // [8] AXI Width Converter: ASCON DMA 64-bit → Crossbar M2 32-bit
    // ========================================================================
    axi_width_converter_64to32 #(
        .ADDR_WIDTH   (AXI_ADDR_WIDTH),
        .ID_WIDTH     (AXI_ID_WIDTH),
        .M_DATA_WIDTH (64),
        .S_DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_wconv (
        .clk  (clk),
        .rst_n(rst_n),

        // Master side (64-bit) ← ASCON M_AXI
        .M_AXI_AWID    (ascon_m_awid),
        .M_AXI_AWADDR  (ascon_m_awaddr),
        .M_AXI_AWLEN   (ascon_m_awlen),
        .M_AXI_AWSIZE  (ascon_m_awsize),
        .M_AXI_AWBURST (ascon_m_awburst),
        .M_AXI_AWCACHE (ascon_m_awcache),
        .M_AXI_AWPROT  (ascon_m_awprot),
        .M_AXI_AWVALID (ascon_m_awvalid),
        .M_AXI_AWREADY (ascon_m_awready),

        .M_AXI_WDATA   (ascon_m_wdata),
        .M_AXI_WSTRB   (ascon_m_wstrb),
        .M_AXI_WLAST   (ascon_m_wlast),
        .M_AXI_WVALID  (ascon_m_wvalid),
        .M_AXI_WREADY  (ascon_m_wready),

        .M_AXI_BID     (ascon_m_bid),
        .M_AXI_BRESP   (ascon_m_bresp),
        .M_AXI_BVALID  (ascon_m_bvalid),
        .M_AXI_BREADY  (ascon_m_bready),

        .M_AXI_ARID    (ascon_m_arid),
        .M_AXI_ARADDR  (ascon_m_araddr),
        .M_AXI_ARLEN   (ascon_m_arlen),
        .M_AXI_ARSIZE  (ascon_m_arsize),
        .M_AXI_ARBURST (ascon_m_arburst),
        .M_AXI_ARCACHE (ascon_m_arcache),
        .M_AXI_ARPROT  (ascon_m_arprot),
        .M_AXI_ARVALID (ascon_m_arvalid),
        .M_AXI_ARREADY (ascon_m_arready),

        .M_AXI_RID     (ascon_m_rid),
        .M_AXI_RDATA   (ascon_m_rdata),
        .M_AXI_RRESP   (ascon_m_rresp),
        .M_AXI_RLAST   (ascon_m_rlast),
        .M_AXI_RVALID  (ascon_m_rvalid),
        .M_AXI_RREADY  (ascon_m_rready),

        // Slave side (32-bit) → Crossbar M2
        .S_AXI_AWID    (wconv_m_awid),
        .S_AXI_AWADDR  (wconv_m_awaddr),
        .S_AXI_AWLEN   (wconv_m_awlen),
        .S_AXI_AWSIZE  (wconv_m_awsize),
        .S_AXI_AWBURST (wconv_m_awburst),
        .S_AXI_AWPROT  (wconv_m_awprot),
        .S_AXI_AWVALID (wconv_m_awvalid),
        .S_AXI_AWREADY (wconv_m_awready),

        .S_AXI_WDATA   (wconv_m_wdata),
        .S_AXI_WSTRB   (wconv_m_wstrb),
        .S_AXI_WLAST   (wconv_m_wlast),
        .S_AXI_WVALID  (wconv_m_wvalid),
        .S_AXI_WREADY  (wconv_m_wready),

        .S_AXI_BID     (wconv_m_bid),
        .S_AXI_BRESP   (wconv_m_bresp),
        .S_AXI_BVALID  (wconv_m_bvalid),
        .S_AXI_BREADY  (wconv_m_bready),

        .S_AXI_ARID    (wconv_m_arid),
        .S_AXI_ARADDR  (wconv_m_araddr),
        .S_AXI_ARLEN   (wconv_m_arlen),
        .S_AXI_ARSIZE  (wconv_m_arsize),
        .S_AXI_ARBURST (wconv_m_arburst),
        .S_AXI_ARPROT  (wconv_m_arprot),
        .S_AXI_ARVALID (wconv_m_arvalid),
        .S_AXI_ARREADY (wconv_m_arready),

        .S_AXI_RID     (wconv_m_rid),
        .S_AXI_RDATA   (wconv_m_rdata),
        .S_AXI_RRESP   (wconv_m_rresp),
        .S_AXI_RLAST   (wconv_m_rlast),
        .S_AXI_RVALID  (wconv_m_rvalid),
        .S_AXI_RREADY  (wconv_m_rready)
    );

    // ========================================================================
    // [9] SoC Ctrl Stub — S3 (trả DECERR cho mọi transaction)
    //     Thay thế bằng module SoC Ctrl thực tế khi cần.
    // ========================================================================
    // Read: trả DECERR ngay lập tức
    assign s3_arready = 1'b1;
    assign s3_rdata   = {AXI_DATA_WIDTH{1'b0}};
    assign s3_rresp   = 2'b11;  // DECERR
    assign s3_rlast   = 1'b1;
    assign s3_rvalid  = s3_arvalid;
    assign s3_rid     = s3_arid;

    // Write: chấp nhận rồi trả DECERR
    assign s3_awready = 1'b1;
    assign s3_wready  = 1'b1;
    assign s3_bresp   = 2'b11;  // DECERR
    assign s3_bid     = s3_awid;

    reg s3_bvalid_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s3_bvalid_r <= 1'b0;
        else if (s3_awvalid && s3_awready)
            s3_bvalid_r <= 1'b1;
        else if (s3_bvalid_r && s3_bready)
            s3_bvalid_r <= 1'b0;
    end
    assign s3_bvalid = s3_bvalid_r;

    // S2 WLAST/RLAST tie-off (crossbar cần nhưng Lite bridge bỏ qua)
    // s2_rlast đã được ascon_ip_top drive (xem S_AXI_RLAST port)
    // s2_wlast từ crossbar đến ascon nhưng Lite slave không có port WLAST → ignored

endmodule