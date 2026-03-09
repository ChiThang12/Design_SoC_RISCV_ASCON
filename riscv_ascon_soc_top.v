// ============================================================================
// File: riscv_ascon_soc_top.v
// ============================================================================
// Top-level SoC: nối CPU core, ASCON core, và DMA controller
//
// Kiến trúc:
//
//   ┌─────────────────────────────────────────────────────────────────────┐
//   │                     riscv_ascon_soc_top                             │
//   │                                                                     │
//   │  ┌───────────────────────────────────────────────────────────────┐  │
//   │  │               riscv_soc_top_cached (cpu_core.v)               │  │
//   │  │                                                               │  │
//   │  │  CPU ─ ICache(M0) ─┐                                         │  │
//   │  │                    ├─ AXI4 Crossbar ─ S0: IMEM               │  │
//   │  │  CPU ─ DCache(M1) ─┘                ─ S1: DMEM               │  │
//   │  │                                     ─ S2: ASCON (stub→real)  │  │
//   │  │                                     ─ S3: SoC Ctrl (stub)    │  │
//   │  └───────────────────────────────────────────────────────────────┘  │
//   │         │ S2 wires (AXI4-Lite từ crossbar)                          │
//   │         ▼                                                           │
//   │  ┌──────────────────────────────────────────────────────────────┐   │
//   │  │  ascon_axi_bridge  (wrapper: AXI4-Lite → ascon_CORE ports)  │   │
//   │  │                     + kết nối DMA data path                  │   │
//   │  └──────────────────────────────────────────────────────────────┘   │
//   │         │ core_* signals                                            │
//   │         ▼                                                           │
//   │  ┌──────────────────┐      ┌──────────────────────────────────────┐ │
//   │  │   ascon_CORE     │      │  dma_top_axi4                        │ │
//   │  │  (crypto engine) │      │  S_AXI ← S2 (CPU cấu hình DMA)      │ │
//   │  └──────────────────┘      │  M_AXI → M2 → Crossbar → DMEM (S1) │ │
//   │                            └──────────────────────────────────────┘ │
//   └─────────────────────────────────────────────────────────────────────┘
//
// Lưu ý quan trọng:
//   - S2 của crossbar (0x2000_0000) phục vụ 2 mục đích:
//       [1] CPU ghi key/nonce/ctrl vào ascon_axi_bridge (offset 0x000-0x0FF)
//       [2] CPU ghi cấu hình DMA (offset 0x100-0x1FC) vào dma_top_axi4
//     => Cần thêm 1 address decoder nhỏ để split S2 thành 2 slave.
//
//   - DMA Master (M2) cần được thêm vào crossbar như Master thứ 3.
//     Hiện tại crossbar có M0 (ICache) và M1 (DCache).
//     Nếu crossbar chưa hỗ trợ M2, bạn cần mở rộng axi4_crossbar.v.
//
// ============================================================================

`include "cpu/riscv_cpu_core_v2.v"
`include "cpu/interface/icache/icache_top.v"
`include "cpu/interface/dcache/dcache_top.v"
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/memory_axi4full/data_mem_axi_slave.v"
`include "cpu/interconnect/axi4_crossbar.v"
`include "ascon_accelerator/rtl/ascon_CORE.v"
`include "dma/dma_defines_axi4.vh"
`include "dma/dma_top_axi4.v"

module riscv_ascon_soc_top (
    input wire clk,
    input wire rst_n,

    // Debug / performance counters (tuỳ chọn, có thể bỏ)
    output wire [31:0] icache_hits,
    output wire [31:0] icache_misses,
    output wire [31:0] dcache_hits,
    output wire [31:0] dcache_misses,
    output wire [31:0] dcache_writes,

    // Interrupt outputs từ DMA (nối ra ngoài nếu có PLIC)
    output wire [3:0]  dma_irq_done,
    output wire [3:0]  dma_irq_error
);

    localparam ID_WIDTH = 4;

    wire rst = ~rst_n;

    // ========================================================================
    // ── Tín hiệu CPU <-> ICache / DCache ────────────────────────────────────
    // ========================================================================
    wire [31:0] cpu_imem_addr,  cpu_imem_rdata;
    wire        cpu_imem_valid, cpu_imem_ready;

    wire [31:0] cpu_dcache_addr, cpu_dcache_wdata, cpu_dcache_rdata;
    wire [3:0]  cpu_dcache_wstrb;
    wire        cpu_dcache_req,  cpu_dcache_we,    cpu_dcache_ready;

    wire [31:0] dcache_current_addr, dcache_current_data;
    wire        dcache_current_valid;

    // ========================================================================
    // ── AXI4 Master wires ───────────────────────────────────────────────────
    // M0 = ICache, M1 = DCache, M2 = DMA
    // ========================================================================

    // M0 (ICache)
    wire [ID_WIDTH-1:0] m0_arid,  m0_rid,  m0_awid,  m0_bid;
    wire [31:0] m0_araddr, m0_rdata, m0_awaddr, m0_wdata;
    wire [7:0]  m0_arlen,  m0_awlen;
    wire [2:0]  m0_arsize, m0_awsize, m0_arprot, m0_awprot;
    wire [1:0]  m0_arburst,m0_awburst,m0_rresp,  m0_bresp;
    wire [3:0]  m0_wstrb;
    wire        m0_arvalid,m0_arready,m0_rvalid, m0_rready, m0_rlast;
    wire        m0_awvalid,m0_awready,m0_wvalid, m0_wready, m0_wlast;
    wire        m0_bvalid, m0_bready;

    // M1 (DCache)
    wire [ID_WIDTH-1:0] m1_arid,  m1_rid,  m1_awid,  m1_bid;
    wire [31:0] m1_araddr, m1_rdata, m1_awaddr, m1_wdata;
    wire [7:0]  m1_arlen,  m1_awlen;
    wire [2:0]  m1_arsize, m1_awsize, m1_arprot, m1_awprot;
    wire [1:0]  m1_arburst,m1_awburst,m1_rresp,  m1_bresp;
    wire [3:0]  m1_wstrb;
    wire        m1_arvalid,m1_arready,m1_rvalid, m1_rready, m1_rlast;
    wire        m1_awvalid,m1_awready,m1_wvalid, m1_wready, m1_wlast;
    wire        m1_bvalid, m1_bready;

    // M2 (DMA Master — đọc/ghi DMEM trực tiếp)
    wire [ID_WIDTH-1:0] m2_arid,  m2_rid,  m2_awid,  m2_bid;
    wire [31:0] m2_araddr, m2_rdata, m2_awaddr, m2_wdata;
    wire [7:0]  m2_arlen,  m2_awlen;
    wire [2:0]  m2_arsize, m2_awsize, m2_arprot, m2_awprot;
    wire [1:0]  m2_arburst,m2_awburst,m2_rresp,  m2_bresp;
    wire [3:0]  m2_wstrb;
    wire        m2_arvalid,m2_arready,m2_rvalid, m2_rready, m2_rlast;
    wire        m2_awvalid,m2_awready,m2_wvalid, m2_wready, m2_wlast;
    wire        m2_bvalid, m2_bready;

    // ========================================================================
    // ── AXI4 Slave wires ────────────────────────────────────────────────────
    // S0 = IMEM, S1 = DMEM, S2 = ASCON+DMA config, S3 = SoC Ctrl
    // ========================================================================

    // S0 (IMEM)
    wire [ID_WIDTH-1:0] s0_arid,  s0_rid,  s0_awid,  s0_bid;
    wire [31:0] s0_araddr, s0_rdata, s0_awaddr, s0_wdata;
    wire [7:0]  s0_arlen,  s0_awlen;
    wire [2:0]  s0_arsize, s0_awsize, s0_arprot, s0_awprot;
    wire [1:0]  s0_arburst,s0_awburst,s0_rresp,  s0_bresp;
    wire [3:0]  s0_wstrb;
    wire        s0_arvalid,s0_arready,s0_rvalid, s0_rready, s0_rlast;
    wire        s0_awvalid,s0_awready,s0_wvalid, s0_wready, s0_wlast;
    wire        s0_bvalid, s0_bready;

    // S1 (DMEM)
    wire [ID_WIDTH-1:0] s1_arid,  s1_rid,  s1_awid,  s1_bid;
    wire [31:0] s1_araddr, s1_rdata, s1_awaddr, s1_wdata;
    wire [7:0]  s1_arlen,  s1_awlen;
    wire [2:0]  s1_arsize, s1_awsize, s1_arprot, s1_awprot;
    wire [1:0]  s1_arburst,s1_awburst,s1_rresp,  s1_bresp;
    wire [3:0]  s1_wstrb;
    wire        s1_arvalid,s1_arready,s1_rvalid, s1_rready, s1_rlast;
    wire        s1_awvalid,s1_awready,s1_wvalid, s1_wready, s1_wlast;
    wire        s1_bvalid, s1_bready;

    // S2 (ASCON + DMA config — từ crossbar)
    wire [ID_WIDTH-1:0] s2_arid,  s2_rid,  s2_awid,  s2_bid;
    wire [31:0] s2_araddr, s2_rdata, s2_awaddr, s2_wdata;
    wire [7:0]  s2_arlen,  s2_awlen;
    wire [2:0]  s2_arsize, s2_awsize, s2_arprot, s2_awprot;
    wire [1:0]  s2_arburst,s2_awburst,s2_rresp,  s2_bresp;
    wire [3:0]  s2_wstrb;
    wire        s2_arvalid,s2_arready,s2_rvalid, s2_rready, s2_rlast;
    wire        s2_awvalid,s2_awready,s2_wvalid, s2_wready, s2_wlast;
    wire        s2_bvalid, s2_bready;

    // S3 (SoC Controller — stub)
    wire [ID_WIDTH-1:0] s3_arid,  s3_rid,  s3_awid,  s3_bid;
    wire [31:0] s3_araddr, s3_rdata, s3_awaddr, s3_wdata;
    wire [7:0]  s3_arlen,  s3_awlen;
    wire [2:0]  s3_arsize, s3_awsize, s3_arprot, s3_awprot;
    wire [1:0]  s3_arburst,s3_awburst,s3_rresp,  s3_bresp;
    wire [3:0]  s3_wstrb;
    wire        s3_arvalid,s3_arready,s3_rvalid, s3_rready, s3_rlast;
    wire        s3_awvalid,s3_awready,s3_wvalid, s3_wready, s3_wlast;
    wire        s3_bvalid, s3_bready;

    // ========================================================================
    // ── S2 Address Decoder ──────────────────────────────────────────────────
    // Phân tách S2 (0x2000_0000 ~ 0x2000_0FFF) thành 2 slave:
    //   Offset 0x000 ~ 0x0FF → ascon_axi_bridge  (ASCON core registers)
    //   Offset 0x100 ~ 0x1FF → dma_top_axi4      (DMA config registers)
    // ========================================================================
    // Dùng bit [8] của địa chỉ nội bộ (s2_araddr[8]) để phân tách:
    //   bit[8] = 0 → ASCON bridge
    //   bit[8] = 1 → DMA config
    wire s2_sel_dma = s2_awaddr[8]; // 0x100 trở lên → DMA

    // --- ASCON bridge slave wires ---
    wire        ascon_s_arready, ascon_s_rvalid, ascon_s_rlast;
    wire [31:0] ascon_s_rdata;
    wire [1:0]  ascon_s_rresp;
    wire [ID_WIDTH-1:0] ascon_s_rid;
    wire        ascon_s_awready, ascon_s_wready;
    wire        ascon_s_bvalid;
    wire [1:0]  ascon_s_bresp;
    wire [ID_WIDTH-1:0] ascon_s_bid;

    // --- DMA config slave wires ---
    wire        dma_s_arready, dma_s_rvalid, dma_s_rlast;
    wire [31:0] dma_s_rdata;
    wire [1:0]  dma_s_rresp;
    wire [ID_WIDTH-1:0] dma_s_rid;
    wire        dma_s_awready, dma_s_wready;
    wire        dma_s_bvalid;
    wire [1:0]  dma_s_bresp;
    wire [ID_WIDTH-1:0] dma_s_bid;

    // S2 Read mux: chọn response từ ASCON hoặc DMA
    // Dùng 1 register latch sel tại AR handshake để chọn đúng slave cho R
    reg  s2_rd_sel_dma_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s2_rd_sel_dma_r <= 1'b0;
        else if (s2_arvalid && s2_arready)
            s2_rd_sel_dma_r <= s2_araddr[8];
    end

    // AR channel routing
    assign ascon_s_arvalid = s2_arvalid & ~s2_araddr[8];
    assign dma_s_arvalid   = s2_arvalid &  s2_araddr[8];
    assign s2_arready      = s2_araddr[8] ? dma_s_arready : ascon_s_arready;

    // R channel mux
    assign s2_rdata        = s2_rd_sel_dma_r ? dma_s_rdata  : ascon_s_rdata;
    assign s2_rresp        = s2_rd_sel_dma_r ? dma_s_rresp  : ascon_s_rresp;
    assign s2_rvalid       = s2_rd_sel_dma_r ? dma_s_rvalid : ascon_s_rvalid;
    assign s2_rlast        = s2_rd_sel_dma_r ? dma_s_rlast  : ascon_s_rlast;
    assign s2_rid          = s2_rd_sel_dma_r ? dma_s_rid    : ascon_s_rid;

    // AW channel routing
    assign ascon_s_awvalid = s2_awvalid & ~s2_sel_dma;
    assign dma_s_awvalid   = s2_awvalid &  s2_sel_dma;
    assign s2_awready      = s2_sel_dma ? dma_s_awready : ascon_s_awready;

    // W channel routing (theo AW sel, latch tại AW handshake)
    reg s2_wr_sel_dma_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s2_wr_sel_dma_r <= 1'b0;
        else if (s2_awvalid && s2_awready)
            s2_wr_sel_dma_r <= s2_sel_dma;
    end

    assign ascon_s_wvalid  = s2_wvalid & ~s2_wr_sel_dma_r;
    assign dma_s_wvalid    = s2_wvalid &  s2_wr_sel_dma_r;
    assign s2_wready       = s2_wr_sel_dma_r ? dma_s_wready : ascon_s_wready;

    // B channel mux
    reg s2_b_sel_dma_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s2_b_sel_dma_r <= 1'b0;
        else if (s2_awvalid && s2_awready)
            s2_b_sel_dma_r <= s2_sel_dma;
    end

    assign s2_bvalid       = s2_b_sel_dma_r ? dma_s_bvalid  : ascon_s_bvalid;
    assign s2_bresp        = s2_b_sel_dma_r ? dma_s_bresp   : ascon_s_bresp;
    assign s2_bid          = s2_b_sel_dma_r ? dma_s_bid     : ascon_s_bid;

    assign ascon_s_bready  = s2_bready & ~s2_b_sel_dma_r;
    assign dma_s_bready    = s2_bready &  s2_b_sel_dma_r;

    // ========================================================================
    // ── ASCON CORE signals ──────────────────────────────────────────────────
    // ========================================================================
    wire         ascon_start;
    wire [1:0]   ascon_mode;
    wire         ascon_enc_dec;
    wire [127:0] ascon_key_in;
    wire [127:0] ascon_nonce_in;
    wire [127:0] ascon_ad_in;
    wire         ascon_ad_valid;
    wire         ascon_ad_last;
    wire [127:0] ascon_data_in;
    wire         ascon_data_last;
    wire [6:0]   ascon_data_len;
    wire [127:0] ascon_tag_received;

    wire [127:0] ascon_data_out;
    wire         ascon_data_out_valid;
    wire [127:0] ascon_tag_out;
    wire         ascon_tag_valid;
    wire         ascon_tag_match;
    wire         ascon_done;
    wire         ascon_busy;

    // ========================================================================
    // ── 1. CPU Core ─────────────────────────────────────────────────────────
    // ========================================================================
    riscv_cpu_core cpu (
        .clk          (clk),
        .rst          (rst),
        .imem_addr    (cpu_imem_addr),
        .imem_valid   (cpu_imem_valid),
        .imem_rdata   (cpu_imem_rdata),
        .imem_ready   (cpu_imem_ready),
        .dcache_addr  (cpu_dcache_addr),
        .dcache_wdata (cpu_dcache_wdata),
        .dcache_wstrb (cpu_dcache_wstrb),
        .dcache_req   (cpu_dcache_req),
        .dcache_we    (cpu_dcache_we),
        .dcache_rdata (cpu_dcache_rdata),
        .dcache_ready (cpu_dcache_ready)
    );

    // ========================================================================
    // ── 2. Instruction Cache — Master 0 ─────────────────────────────────────
    // ========================================================================
    icache_top #(.ID_WIDTH(ID_WIDTH)) icache (
        .clk         (clk),          .rst_n       (rst_n),
        .cpu_addr    (cpu_imem_addr),
        .cpu_req     (cpu_imem_valid),
        .cpu_rdata   (cpu_imem_rdata),
        .cpu_ready   (cpu_imem_ready),
        .flush       (1'b0),
        .mem_arid    (m0_arid),      .mem_araddr  (m0_araddr),
        .mem_arlen   (m0_arlen),     .mem_arsize  (m0_arsize),
        .mem_arburst (m0_arburst),   .mem_arprot  (m0_arprot),
        .mem_arvalid (m0_arvalid),   .mem_arready (m0_arready),
        .mem_rid     (m0_rid),       .mem_rdata   (m0_rdata),
        .mem_rresp   (m0_rresp),     .mem_rlast   (m0_rlast),
        .mem_rvalid  (m0_rvalid),    .mem_rready  (m0_rready),
        .mem_awid    (m0_awid),      .mem_awaddr  (m0_awaddr),
        .mem_awlen   (m0_awlen),     .mem_awsize  (m0_awsize),
        .mem_awburst (m0_awburst),   .mem_awprot  (m0_awprot),
        .mem_awvalid (m0_awvalid),   .mem_awready (m0_awready),
        .mem_wdata   (m0_wdata),     .mem_wstrb   (m0_wstrb),
        .mem_wlast   (m0_wlast),     .mem_wvalid  (m0_wvalid),
        .mem_wready  (m0_wready),
        .mem_bid     (m0_bid),       .mem_bresp   (m0_bresp),
        .mem_bvalid  (m0_bvalid),    .mem_bready  (m0_bready),
        .stat_hits   (icache_hits),
        .stat_misses (icache_misses)
    );

    // ========================================================================
    // ── 3. Data Cache — Master 1 ─────────────────────────────────────────────
    // ========================================================================
    dcache_top #(.ID_WIDTH(ID_WIDTH)) dcache (
        .clk           (clk),          .rst_n         (rst_n),
        .cpu_addr      (cpu_dcache_addr),
        .cpu_wdata     (cpu_dcache_wdata),
        .cpu_wstrb     (cpu_dcache_wstrb),
        .cpu_req       (cpu_dcache_req),
        .cpu_we        (cpu_dcache_we),
        .cpu_rdata     (cpu_dcache_rdata),
        .cpu_ready     (cpu_dcache_ready),
        .fence         (1'b0),
        .current_addr  (dcache_current_addr),
        .current_data  (dcache_current_data),
        .current_valid (dcache_current_valid),
        .mem_arid      (m1_arid),      .mem_araddr    (m1_araddr),
        .mem_arlen     (m1_arlen),     .mem_arsize    (m1_arsize),
        .mem_arburst   (m1_arburst),   .mem_arprot    (m1_arprot),
        .mem_arvalid   (m1_arvalid),   .mem_arready   (m1_arready),
        .mem_rid       (m1_rid),       .mem_rdata     (m1_rdata),
        .mem_rresp     (m1_rresp),     .mem_rlast     (m1_rlast),
        .mem_rvalid    (m1_rvalid),    .mem_rready    (m1_rready),
        .mem_awid      (m1_awid),      .mem_awaddr    (m1_awaddr),
        .mem_awlen     (m1_awlen),     .mem_awsize    (m1_awsize),
        .mem_awburst   (m1_awburst),   .mem_awprot    (m1_awprot),
        .mem_awvalid   (m1_awvalid),   .mem_awready   (m1_awready),
        .mem_wdata     (m1_wdata),     .mem_wstrb     (m1_wstrb),
        .mem_wlast     (m1_wlast),     .mem_wvalid    (m1_wvalid),
        .mem_wready    (m1_wready),
        .mem_bid       (m1_bid),       .mem_bresp     (m1_bresp),
        .mem_bvalid    (m1_bvalid),    .mem_bready    (m1_bready),
        .stat_hits     (dcache_hits),
        .stat_misses   (dcache_misses),
        .stat_writes   (dcache_writes)
    );

    // ========================================================================
    // ── 4. AXI4 Crossbar (3 Master × 4 Slave)
    // ────────────────────────────────────────────────────────────────────────
    // TODO: axi4_crossbar.v của bạn hiện chỉ có M0+M1.
    //       Cần mở rộng thêm cổng M2 (DMA) để DMA có thể đọc/ghi DMEM.
    //       Nếu chưa mở rộng crossbar, tạm thời nối M2 thẳng vào DMEM
    //       (xem phần S1 MUX bên dưới).
    // ========================================================================
    axi4_crossbar #(.ID_WIDTH(ID_WIDTH)) xbar (
        .clk            (clk),          .rst_n          (rst_n),
        // M0 — ICache
        .M0_AXI_ARID    (m0_arid),      .M0_AXI_ARADDR  (m0_araddr),
        .M0_AXI_ARLEN   (m0_arlen),     .M0_AXI_ARSIZE  (m0_arsize),
        .M0_AXI_ARBURST (m0_arburst),   .M0_AXI_ARPROT  (m0_arprot),
        .M0_AXI_ARVALID (m0_arvalid),   .M0_AXI_ARREADY (m0_arready),
        .M0_AXI_RID     (m0_rid),       .M0_AXI_RDATA   (m0_rdata),
        .M0_AXI_RRESP   (m0_rresp),     .M0_AXI_RLAST   (m0_rlast),
        .M0_AXI_RVALID  (m0_rvalid),    .M0_AXI_RREADY  (m0_rready),
        .M0_AXI_AWID    (m0_awid),      .M0_AXI_AWADDR  (m0_awaddr),
        .M0_AXI_AWLEN   (m0_awlen),     .M0_AXI_AWSIZE  (m0_awsize),
        .M0_AXI_AWBURST (m0_awburst),   .M0_AXI_AWPROT  (m0_awprot),
        .M0_AXI_AWVALID (m0_awvalid),   .M0_AXI_AWREADY (m0_awready),
        .M0_AXI_WDATA   (m0_wdata),     .M0_AXI_WSTRB   (m0_wstrb),
        .M0_AXI_WLAST   (m0_wlast),     .M0_AXI_WVALID  (m0_wvalid),
        .M0_AXI_WREADY  (m0_wready),
        .M0_AXI_BID     (m0_bid),       .M0_AXI_BRESP   (m0_bresp),
        .M0_AXI_BVALID  (m0_bvalid),    .M0_AXI_BREADY  (m0_bready),
        // M1 — DCache
        .M1_AXI_ARID    (m1_arid),      .M1_AXI_ARADDR  (m1_araddr),
        .M1_AXI_ARLEN   (m1_arlen),     .M1_AXI_ARSIZE  (m1_arsize),
        .M1_AXI_ARBURST (m1_arburst),   .M1_AXI_ARPROT  (m1_arprot),
        .M1_AXI_ARVALID (m1_arvalid),   .M1_AXI_ARREADY (m1_arready),
        .M1_AXI_RID     (m1_rid),       .M1_AXI_RDATA   (m1_rdata),
        .M1_AXI_RRESP   (m1_rresp),     .M1_AXI_RLAST   (m1_rlast),
        .M1_AXI_RVALID  (m1_rvalid),    .M1_AXI_RREADY  (m1_rready),
        .M1_AXI_AWID    (m1_awid),      .M1_AXI_AWADDR  (m1_awaddr),
        .M1_AXI_AWLEN   (m1_awlen),     .M1_AXI_AWSIZE  (m1_awsize),
        .M1_AXI_AWBURST (m1_awburst),   .M1_AXI_AWPROT  (m1_awprot),
        .M1_AXI_AWVALID (m1_awvalid),   .M1_AXI_AWREADY (m1_awready),
        .M1_AXI_WDATA   (m1_wdata),     .M1_AXI_WSTRB   (m1_wstrb),
        .M1_AXI_WLAST   (m1_wlast),     .M1_AXI_WVALID  (m1_wvalid),
        .M1_AXI_WREADY  (m1_wready),
        .M1_AXI_BID     (m1_bid),       .M1_AXI_BRESP   (m1_bresp),
        .M1_AXI_BVALID  (m1_bvalid),    .M1_AXI_BREADY  (m1_bready),
        // S0 — IMEM
        .S0_AXI_ARID    (s0_arid),      .S0_AXI_ARADDR  (s0_araddr),
        .S0_AXI_ARLEN   (s0_arlen),     .S0_AXI_ARSIZE  (s0_arsize),
        .S0_AXI_ARBURST (s0_arburst),   .S0_AXI_ARPROT  (s0_arprot),
        .S0_AXI_ARVALID (s0_arvalid),   .S0_AXI_ARREADY (s0_arready),
        .S0_AXI_RID     (s0_rid),       .S0_AXI_RDATA   (s0_rdata),
        .S0_AXI_RRESP   (s0_rresp),     .S0_AXI_RLAST   (s0_rlast),
        .S0_AXI_RVALID  (s0_rvalid),    .S0_AXI_RREADY  (s0_rready),
        .S0_AXI_AWID    (s0_awid),      .S0_AXI_AWADDR  (s0_awaddr),
        .S0_AXI_AWLEN   (s0_awlen),     .S0_AXI_AWSIZE  (s0_awsize),
        .S0_AXI_AWBURST (s0_awburst),   .S0_AXI_AWPROT  (s0_awprot),
        .S0_AXI_AWVALID (s0_awvalid),   .S0_AXI_AWREADY (s0_awready),
        .S0_AXI_WDATA   (s0_wdata),     .S0_AXI_WSTRB   (s0_wstrb),
        .S0_AXI_WLAST   (s0_wlast),     .S0_AXI_WVALID  (s0_wvalid),
        .S0_AXI_WREADY  (s0_wready),
        .S0_AXI_BID     (s0_bid),       .S0_AXI_BRESP   (s0_bresp),
        .S0_AXI_BVALID  (s0_bvalid),    .S0_AXI_BREADY  (s0_bready),
        // S1 — DMEM (chỉ từ DCache; DMA nối riêng bên dưới qua mux)
        .S1_AXI_ARID    (s1_arid),      .S1_AXI_ARADDR  (s1_araddr),
        .S1_AXI_ARLEN   (s1_arlen),     .S1_AXI_ARSIZE  (s1_arsize),
        .S1_AXI_ARBURST (s1_arburst),   .S1_AXI_ARPROT  (s1_arprot),
        .S1_AXI_ARVALID (s1_arvalid),   .S1_AXI_ARREADY (s1_arready),
        .S1_AXI_RID     (s1_rid),       .S1_AXI_RDATA   (s1_rdata),
        .S1_AXI_RRESP   (s1_rresp),     .S1_AXI_RLAST   (s1_rlast),
        .S1_AXI_RVALID  (s1_rvalid),    .S1_AXI_RREADY  (s1_rready),
        .S1_AXI_AWID    (s1_awid),      .S1_AXI_AWADDR  (s1_awaddr),
        .S1_AXI_AWLEN   (s1_awlen),     .S1_AXI_AWSIZE  (s1_awsize),
        .S1_AXI_AWBURST (s1_awburst),   .S1_AXI_AWPROT  (s1_awprot),
        .S1_AXI_AWVALID (s1_awvalid),   .S1_AXI_AWREADY (s1_awready),
        .S1_AXI_WDATA   (s1_wdata),     .S1_AXI_WSTRB   (s1_wstrb),
        .S1_AXI_WLAST   (s1_wlast),     .S1_AXI_WVALID  (s1_wvalid),
        .S1_AXI_WREADY  (s1_wready),
        .S1_AXI_BID     (s1_bid),       .S1_AXI_BRESP   (s1_bresp),
        .S1_AXI_BVALID  (s1_bvalid),    .S1_AXI_BREADY  (s1_bready),
        // S2 — ASCON + DMA config
        .S2_AXI_ARID    (s2_arid),      .S2_AXI_ARADDR  (s2_araddr),
        .S2_AXI_ARLEN   (s2_arlen),     .S2_AXI_ARSIZE  (s2_arsize),
        .S2_AXI_ARBURST (s2_arburst),   .S2_AXI_ARPROT  (s2_arprot),
        .S2_AXI_ARVALID (s2_arvalid),   .S2_AXI_ARREADY (s2_arready),
        .S2_AXI_RID     (s2_rid),       .S2_AXI_RDATA   (s2_rdata),
        .S2_AXI_RRESP   (s2_rresp),     .S2_AXI_RLAST   (s2_rlast),
        .S2_AXI_RVALID  (s2_rvalid),    .S2_AXI_RREADY  (s2_rready),
        .S2_AXI_AWID    (s2_awid),      .S2_AXI_AWADDR  (s2_awaddr),
        .S2_AXI_AWLEN   (s2_awlen),     .S2_AXI_AWSIZE  (s2_awsize),
        .S2_AXI_AWBURST (s2_awburst),   .S2_AXI_AWPROT  (s2_awprot),
        .S2_AXI_AWVALID (s2_awvalid),   .S2_AXI_AWREADY (s2_awready),
        .S2_AXI_WDATA   (s2_wdata),     .S2_AXI_WSTRB   (s2_wstrb),
        .S2_AXI_WLAST   (s2_wlast),     .S2_AXI_WVALID  (s2_wvalid),
        .S2_AXI_WREADY  (s2_wready),
        .S2_AXI_BID     (s2_bid),       .S2_AXI_BRESP   (s2_bresp),
        .S2_AXI_BVALID  (s2_bvalid),    .S2_AXI_BREADY  (s2_bready),
        // S3 — SoC Controller (stub)
        .S3_AXI_ARID    (s3_arid),      .S3_AXI_ARADDR  (s3_araddr),
        .S3_AXI_ARLEN   (s3_arlen),     .S3_AXI_ARSIZE  (s3_arsize),
        .S3_AXI_ARBURST (s3_arburst),   .S3_AXI_ARPROT  (s3_arprot),
        .S3_AXI_ARVALID (s3_arvalid),   .S3_AXI_ARREADY (s3_arready),
        .S3_AXI_RID     (s3_rid),       .S3_AXI_RDATA   (s3_rdata),
        .S3_AXI_RRESP   (s3_rresp),     .S3_AXI_RLAST   (s3_rlast),
        .S3_AXI_RVALID  (s3_rvalid),    .S3_AXI_RREADY  (s3_rready),
        .S3_AXI_AWID    (s3_awid),      .S3_AXI_AWADDR  (s3_awaddr),
        .S3_AXI_AWLEN   (s3_awlen),     .S3_AXI_AWSIZE  (s3_awsize),
        .S3_AXI_AWBURST (s3_awburst),   .S3_AXI_AWPROT  (s3_awprot),
        .S3_AXI_AWVALID (s3_awvalid),   .S3_AXI_AWREADY (s3_awready),
        .S3_AXI_WDATA   (s3_wdata),     .S3_AXI_WSTRB   (s3_wstrb),
        .S3_AXI_WLAST   (s3_wlast),     .S3_AXI_WVALID  (s3_wvalid),
        .S3_AXI_WREADY  (s3_wready),
        .S3_AXI_BID     (s3_bid),       .S3_AXI_BRESP   (s3_bresp),
        .S3_AXI_BVALID  (s3_bvalid),    .S3_AXI_BREADY  (s3_bready)
    );

    // ========================================================================
    // ── 5. Instruction Memory — Slave 0 ─────────────────────────────────────
    // ========================================================================
    inst_mem_axi_slave #(.ID_WIDTH(ID_WIDTH)) imem (
        .clk           (clk),            .rst_n         (rst_n),
        .S_AXI_ARID    (s0_arid),
        .S_AXI_ARADDR  (s0_araddr),      .S_AXI_ARLEN   (s0_arlen),
        .S_AXI_ARSIZE  (s0_arsize),      .S_AXI_ARBURST (s0_arburst),
        .S_AXI_ARPROT  (s0_arprot),      .S_AXI_ARVALID (s0_arvalid),
        .S_AXI_ARREADY (s0_arready),
        .S_AXI_RID     (s0_rid),
        .S_AXI_RDATA   (s0_rdata),       .S_AXI_RRESP   (s0_rresp),
        .S_AXI_RLAST   (s0_rlast),       .S_AXI_RVALID  (s0_rvalid),
        .S_AXI_RREADY  (s0_rready),
        .S_AXI_AWID    (s0_awid),
        .S_AXI_AWADDR  (s0_awaddr),      .S_AXI_AWLEN   (s0_awlen),
        .S_AXI_AWSIZE  (s0_awsize),      .S_AXI_AWBURST (s0_awburst),
        .S_AXI_AWPROT  (s0_awprot),      .S_AXI_AWVALID (s0_awvalid),
        .S_AXI_AWREADY (s0_awready),
        .S_AXI_WDATA   (s0_wdata),       .S_AXI_WSTRB   (s0_wstrb),
        .S_AXI_WLAST   (s0_wlast),       .S_AXI_WVALID  (s0_wvalid),
        .S_AXI_WREADY  (s0_wready),
        .S_AXI_BID     (s0_bid),
        .S_AXI_BRESP   (s0_bresp),       .S_AXI_BVALID  (s0_bvalid),
        .S_AXI_BREADY  (s0_bready)
    );

    // ========================================================================
    // ── 6. Data Memory — Slave 1 ─────────────────────────────────────────────
    // ────────────────────────────────────────────────────────────────────────
    // DMEM được truy cập bởi cả DCache (từ crossbar S1) và DMA (M2).
    // Vì crossbar hiện tại chỉ có M0+M1, DMA (M2) được nối thẳng vào
    // DMEM qua một AXI arbiter nhỏ 2-to-1 bên dưới.
    //
    // Nếu bạn mở rộng crossbar lên 3 master, xóa phần arbitration này
    // và nối m2_* trực tiếp vào crossbar port M2.
    // ========================================================================

    // --- 2-to-1 AXI Arbiter: DCache (port A) vs DMA (port B) → DMEM ---
    // Chiến lược đơn giản: DMA được ưu tiên khi DCache không có request
    // (round-robin hoặc fixed priority đều được, dùng fixed priority ở đây)

    wire [ID_WIDTH-1:0] dmem_arid,  dmem_rid,  dmem_awid,  dmem_bid;
    wire [31:0] dmem_araddr, dmem_rdata, dmem_awaddr, dmem_wdata;
    wire [7:0]  dmem_arlen,  dmem_awlen;
    wire [2:0]  dmem_arsize, dmem_awsize, dmem_arprot, dmem_awprot;
    wire [1:0]  dmem_arburst,dmem_awburst,dmem_rresp,  dmem_bresp;
    wire [3:0]  dmem_wstrb;
    wire        dmem_arvalid,dmem_arready,dmem_rvalid, dmem_rready, dmem_rlast;
    wire        dmem_awvalid,dmem_awready,dmem_wvalid, dmem_wready, dmem_wlast;
    wire        dmem_bvalid, dmem_bready;

    // Arbitration state: 0 = DCache owns bus, 1 = DMA owns bus
    reg  dmem_arb_owner; // 0=s1(DCache), 1=m2(DMA)
    wire s1_req  = s1_arvalid | s1_awvalid;
    wire m2_req  = m2_arvalid | m2_awvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dmem_arb_owner <= 1'b0;
        else begin
            // Chuyển sang DMA khi DCache không request và DMA đang chờ
            if (!s1_req && m2_req)
                dmem_arb_owner <= 1'b1;
            // Trả lại DCache khi DMA xong hoặc DCache có request mới
            else if (s1_req && !m2_req)
                dmem_arb_owner <= 1'b0;
        end
    end

    // Mux AXI signals vào DMEM
    assign dmem_arid    = dmem_arb_owner ? m2_arid    : s1_arid;
    assign dmem_araddr  = dmem_arb_owner ? m2_araddr  : s1_araddr;
    assign dmem_arlen   = dmem_arb_owner ? m2_arlen   : s1_arlen;
    assign dmem_arsize  = dmem_arb_owner ? m2_arsize  : s1_arsize;
    assign dmem_arburst = dmem_arb_owner ? m2_arburst : s1_arburst;
    assign dmem_arprot  = dmem_arb_owner ? m2_arprot  : s1_arprot;
    assign dmem_arvalid = dmem_arb_owner ? m2_arvalid : s1_arvalid;

    assign dmem_awid    = dmem_arb_owner ? m2_awid    : s1_awid;
    assign dmem_awaddr  = dmem_arb_owner ? m2_awaddr  : s1_awaddr;
    assign dmem_awlen   = dmem_arb_owner ? m2_awlen   : s1_awlen;
    assign dmem_awsize  = dmem_arb_owner ? m2_awsize  : s1_awsize;
    assign dmem_awburst = dmem_arb_owner ? m2_awburst : s1_awburst;
    assign dmem_awprot  = dmem_arb_owner ? m2_awprot  : s1_awprot;
    assign dmem_awvalid = dmem_arb_owner ? m2_awvalid : s1_awvalid;

    assign dmem_wdata   = dmem_arb_owner ? m2_wdata   : s1_wdata;
    assign dmem_wstrb   = dmem_arb_owner ? m2_wstrb   : s1_wstrb;
    assign dmem_wlast   = dmem_arb_owner ? m2_wlast   : s1_wlast;
    assign dmem_wvalid  = dmem_arb_owner ? m2_wvalid  : s1_wvalid;
    assign dmem_rready  = dmem_arb_owner ? m2_rready  : s1_rready;
    assign dmem_bready  = dmem_arb_owner ? m2_bready  : s1_bready;

    // Demux READY/response về đúng master
    assign s1_arready  = dmem_arb_owner ? 1'b0 : dmem_arready;
    assign s1_awready  = dmem_arb_owner ? 1'b0 : dmem_awready;
    assign s1_wready   = dmem_arb_owner ? 1'b0 : dmem_wready;
    assign s1_rvalid   = dmem_arb_owner ? 1'b0 : dmem_rvalid;
    assign s1_rdata    = dmem_rdata;
    assign s1_rresp    = dmem_rresp;
    assign s1_rlast    = dmem_rlast;
    assign s1_rid      = dmem_rid;
    assign s1_bvalid   = dmem_arb_owner ? 1'b0 : dmem_bvalid;
    assign s1_bresp    = dmem_bresp;
    assign s1_bid      = dmem_bid;

    assign m2_arready  = dmem_arb_owner ? dmem_arready : 1'b0;
    assign m2_awready  = dmem_arb_owner ? dmem_awready : 1'b0;
    assign m2_wready   = dmem_arb_owner ? dmem_wready  : 1'b0;
    assign m2_rvalid   = dmem_arb_owner ? dmem_rvalid  : 1'b0;
    assign m2_rdata    = dmem_rdata;
    assign m2_rresp    = dmem_rresp;
    assign m2_rlast    = dmem_rlast;
    assign m2_rid      = dmem_rid;
    assign m2_bvalid   = dmem_arb_owner ? dmem_bvalid  : 1'b0;
    assign m2_bresp    = dmem_bresp;
    assign m2_bid      = dmem_bid;

    // S1 RID/BID latch (giữ nguyên từ cpu_core.v BUG 3 fix)
    reg [ID_WIDTH-1:0] dmem_rid_r, dmem_bid_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_rid_r <= {ID_WIDTH{1'b0}};
            dmem_bid_r <= {ID_WIDTH{1'b0}};
        end else begin
            if (dmem_arvalid && dmem_arready) dmem_rid_r <= dmem_arid;
            if (dmem_awvalid && dmem_awready) dmem_bid_r <= dmem_awid;
        end
    end
    assign dmem_rid = dmem_rid_r;
    assign dmem_bid = dmem_bid_r;

    data_mem_axi4_slave dmem (
        .clk           (clk),            .rst_n         (rst_n),
        .S_AXI_ARADDR  (dmem_araddr),    .S_AXI_ARLEN   (dmem_arlen),
        .S_AXI_ARSIZE  (dmem_arsize),    .S_AXI_ARBURST (dmem_arburst),
        .S_AXI_ARPROT  (dmem_arprot),    .S_AXI_ARVALID (dmem_arvalid),
        .S_AXI_ARREADY (dmem_arready),
        .S_AXI_RDATA   (dmem_rdata),     .S_AXI_RRESP   (dmem_rresp),
        .S_AXI_RLAST   (dmem_rlast),     .S_AXI_RVALID  (dmem_rvalid),
        .S_AXI_RREADY  (dmem_rready),
        .S_AXI_AWADDR  (dmem_awaddr),    .S_AXI_AWLEN   (dmem_awlen),
        .S_AXI_AWSIZE  (dmem_awsize),    .S_AXI_AWBURST (dmem_awburst),
        .S_AXI_AWPROT  (dmem_awprot),    .S_AXI_AWVALID (dmem_awvalid),
        .S_AXI_AWREADY (dmem_awready),
        .S_AXI_WDATA   (dmem_wdata),     .S_AXI_WSTRB   (dmem_wstrb),
        .S_AXI_WLAST   (dmem_wlast),     .S_AXI_WVALID  (dmem_wvalid),
        .S_AXI_WREADY  (dmem_wready),
        .S_AXI_BRESP   (dmem_bresp),     .S_AXI_BVALID  (dmem_bvalid),
        .S_AXI_BREADY  (dmem_bready)
    );

    // ========================================================================
    // ── 7. S3 Stub — SoC Controller placeholder ─────────────────────────────
    // ========================================================================
    localparam S3_WR_IDLE = 2'b00, S3_WR_DATA = 2'b01, S3_WR_RESP = 2'b10;
    reg [1:0]          s3_wr_state;
    reg [ID_WIDTH-1:0] s3_bid_r;
    reg                s3_rvalid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s3_rvalid_r <= 1'b0;
        else        s3_rvalid_r <= s3_arvalid & s3_arready;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_wr_state <= S3_WR_IDLE;
            s3_bid_r    <= {ID_WIDTH{1'b0}};
        end else begin
            case (s3_wr_state)
                S3_WR_IDLE: if (s3_awvalid) begin s3_bid_r <= s3_awid; s3_wr_state <= S3_WR_DATA; end
                S3_WR_DATA: if (s3_wvalid && s3_wlast) s3_wr_state <= S3_WR_RESP;
                S3_WR_RESP: if (s3_bready) s3_wr_state <= S3_WR_IDLE;
                default:    s3_wr_state <= S3_WR_IDLE;
            endcase
        end
    end

    assign s3_arready = 1'b1;
    assign s3_rid     = s3_arid;
    assign s3_rdata   = 32'hDEAD_BEEF;
    assign s3_rresp   = 2'b10;
    assign s3_rlast   = 1'b1;
    assign s3_rvalid  = s3_rvalid_r;
    assign s3_awready = (s3_wr_state == S3_WR_IDLE);
    assign s3_wready  = (s3_wr_state == S3_WR_DATA);
    assign s3_bid     = s3_bid_r;
    assign s3_bresp   = 2'b10;
    assign s3_bvalid  = (s3_wr_state == S3_WR_RESP);

    // ========================================================================
    // ── 8. ASCON AXI Bridge ─────────────────────────────────────────────────
    // Chuyển đổi AXI4-Lite write (từ CPU qua S2, offset 0x000-0x0FF)
    // thành các tín hiệu điều khiển cho ascon_CORE.
    //
    // Register map tối thiểu (offset trong 4KB S2):
    //   0x00: CTRL       [0]=start, [1]=enc_dec
    //   0x04: MODE       [1:0]=mode
    //   0x08: STATUS     [0]=busy, [1]=done (read-only)
    //   0x10–0x1C: KEY   (128-bit = 4 × 32-bit, MSW first)
    //   0x20–0x2C: NONCE (128-bit)
    //   0x30–0x3C: AD    (128-bit)
    //   0x40–0x4C: DATA_IN (128-bit)
    //   0x50: DATA_LEN   [6:0]
    //   0x54: AD_VALID   [0]
    //   0x58: AD_LAST    [0]
    //   0x5C: DATA_LAST  [0]
    //   0x60–0x6C: DATA_OUT (read-only)
    //   0x70–0x7C: TAG_OUT  (read-only)
    // ========================================================================
    reg         ascon_start_r;
    reg [1:0]   ascon_mode_r;
    reg         ascon_enc_dec_r;
    reg [127:0] ascon_key_r;
    reg [127:0] ascon_nonce_r;
    reg [127:0] ascon_ad_r;
    reg [127:0] ascon_data_in_r;
    reg [6:0]   ascon_data_len_r;
    reg         ascon_ad_valid_r;
    reg         ascon_ad_last_r;
    reg         ascon_data_last_r;
    reg [127:0] ascon_tag_received_r;

    // AXI4-Lite write FSM cho ASCON bridge
    localparam AB_WR_IDLE = 2'b00, AB_WR_DATA = 2'b01, AB_WR_RESP = 2'b10;
    reg [1:0]          ab_wr_state;
    reg [7:0]          ab_wr_addr;
    reg [ID_WIDTH-1:0] ab_bid_r;

    assign ascon_s_awready = (ab_wr_state == AB_WR_IDLE);
    assign ascon_s_wready  = (ab_wr_state == AB_WR_DATA);
    assign ascon_s_bvalid  = (ab_wr_state == AB_WR_RESP);
    assign ascon_s_bresp   = 2'b00; // OKAY
    assign ascon_s_bid     = ab_bid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_wr_state       <= AB_WR_IDLE;
            ab_wr_addr        <= 8'h0;
            ab_bid_r          <= {ID_WIDTH{1'b0}};
            ascon_start_r     <= 1'b0;
            ascon_mode_r      <= 2'b00;
            ascon_enc_dec_r   <= 1'b0;
            ascon_key_r       <= 128'h0;
            ascon_nonce_r     <= 128'h0;
            ascon_ad_r        <= 128'h0;
            ascon_data_in_r   <= 128'h0;
            ascon_data_len_r  <= 7'h0;
            ascon_ad_valid_r  <= 1'b0;
            ascon_ad_last_r   <= 1'b0;
            ascon_data_last_r <= 1'b0;
            ascon_tag_received_r <= 128'h0;
        end else begin
            // Auto-clear start sau 1 cycle
            ascon_start_r <= 1'b0;

            case (ab_wr_state)
                AB_WR_IDLE: begin
                    if (ascon_s_awvalid) begin
                        ab_wr_addr  <= s2_awaddr[7:0]; // offset nội bộ
                        ab_bid_r    <= s2_awid;
                        ab_wr_state <= AB_WR_DATA;
                    end
                end

                AB_WR_DATA: begin
                    if (ascon_s_wvalid) begin
                        case (ab_wr_addr)
                            8'h00: begin
                                ascon_start_r   <= s2_wdata[0];
                                ascon_enc_dec_r <= s2_wdata[1];
                            end
                            8'h04: ascon_mode_r          <= s2_wdata[1:0];
                            8'h10: ascon_key_r[127:96]   <= s2_wdata;
                            8'h14: ascon_key_r[95:64]    <= s2_wdata;
                            8'h18: ascon_key_r[63:32]    <= s2_wdata;
                            8'h1C: ascon_key_r[31:0]     <= s2_wdata;
                            8'h20: ascon_nonce_r[127:96] <= s2_wdata;
                            8'h24: ascon_nonce_r[95:64]  <= s2_wdata;
                            8'h28: ascon_nonce_r[63:32]  <= s2_wdata;
                            8'h2C: ascon_nonce_r[31:0]   <= s2_wdata;
                            8'h30: ascon_ad_r[127:96]    <= s2_wdata;
                            8'h34: ascon_ad_r[95:64]     <= s2_wdata;
                            8'h38: ascon_ad_r[63:32]     <= s2_wdata;
                            8'h3C: ascon_ad_r[31:0]      <= s2_wdata;
                            8'h40: ascon_data_in_r[127:96] <= s2_wdata;
                            8'h44: ascon_data_in_r[95:64]  <= s2_wdata;
                            8'h48: ascon_data_in_r[63:32]  <= s2_wdata;
                            8'h4C: ascon_data_in_r[31:0]   <= s2_wdata;
                            8'h50: ascon_data_len_r        <= s2_wdata[6:0];
                            8'h54: ascon_ad_valid_r        <= s2_wdata[0];
                            8'h58: ascon_ad_last_r         <= s2_wdata[0];
                            8'h5C: ascon_data_last_r       <= s2_wdata[0];
                            8'h70: ascon_tag_received_r[127:96] <= s2_wdata;
                            8'h74: ascon_tag_received_r[95:64]  <= s2_wdata;
                            8'h78: ascon_tag_received_r[63:32]  <= s2_wdata;
                            8'h7C: ascon_tag_received_r[31:0]   <= s2_wdata;
                            default: ; // ignore
                        endcase
                        ab_wr_state <= AB_WR_RESP;
                    end
                end

                AB_WR_RESP: begin
                    if (ascon_s_bready)
                        ab_wr_state <= AB_WR_IDLE;
                end

                default: ab_wr_state <= AB_WR_IDLE;
            endcase
        end
    end

    // AXI4-Lite read cho ASCON bridge
    reg        ab_rvalid_r;
    reg [31:0] ab_rdata_r;
    reg [ID_WIDTH-1:0] ab_rid_r;

    assign ascon_s_arready = ~ab_rvalid_r;
    assign ascon_s_rvalid  = ab_rvalid_r;
    assign ascon_s_rdata   = ab_rdata_r;
    assign ascon_s_rresp   = 2'b00;
    assign ascon_s_rlast   = 1'b1;
    assign ascon_s_rid     = ab_rid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_rvalid_r <= 1'b0;
            ab_rdata_r  <= 32'h0;
            ab_rid_r    <= {ID_WIDTH{1'b0}};
        end else begin
            if (ascon_s_arvalid && ascon_s_arready) begin
                ab_rvalid_r <= 1'b1;
                ab_rid_r    <= s2_arid;
                case (s2_araddr[7:0])
                    8'h08: ab_rdata_r <= {30'h0, ascon_done, ascon_busy};
                    8'h60: ab_rdata_r <= ascon_data_out[127:96];
                    8'h64: ab_rdata_r <= ascon_data_out[95:64];
                    8'h68: ab_rdata_r <= ascon_data_out[63:32];
                    8'h6C: ab_rdata_r <= ascon_data_out[31:0];
                    8'h70: ab_rdata_r <= ascon_tag_out[127:96];
                    8'h74: ab_rdata_r <= ascon_tag_out[95:64];
                    8'h78: ab_rdata_r <= ascon_tag_out[63:32];
                    8'h7C: ab_rdata_r <= ascon_tag_out[31:0];
                    default: ab_rdata_r <= 32'h0;
                endcase
            end else if (ab_rvalid_r && ascon_s_rready) begin
                ab_rvalid_r <= 1'b0;
            end
        end
    end

    // Connect bridge registers → ascon_CORE ports
    assign ascon_start        = ascon_start_r;
    assign ascon_mode         = ascon_mode_r;
    assign ascon_enc_dec      = ascon_enc_dec_r;
    assign ascon_key_in       = ascon_key_r;
    assign ascon_nonce_in     = ascon_nonce_r;
    assign ascon_ad_in        = ascon_ad_r;
    assign ascon_ad_valid     = ascon_ad_valid_r;
    assign ascon_ad_last      = ascon_ad_last_r;
    assign ascon_data_in      = ascon_data_in_r;
    assign ascon_data_last    = ascon_data_last_r;
    assign ascon_data_len     = ascon_data_len_r;
    assign ascon_tag_received = ascon_tag_received_r;

    // ========================================================================
    // ── 9. ASCON Core ───────────────────────────────────────────────────────
    // ========================================================================
    ascon_CORE u_ascon (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (ascon_start),
        .mode          (ascon_mode),
        .enc_dec       (ascon_enc_dec),
        .key_in        (ascon_key_in),
        .nonce_in      (ascon_nonce_in),
        .ad_in         (ascon_ad_in),
        .ad_valid      (ascon_ad_valid),
        .ad_last       (ascon_ad_last),
        .data_in       (ascon_data_in),
        .data_last     (ascon_data_last),
        .data_len      (ascon_data_len),
        .tag_received  (ascon_tag_received),
        .data_out      (ascon_data_out),
        .data_out_valid(ascon_data_out_valid),
        .tag_out       (ascon_tag_out),
        .tag_valid     (ascon_tag_valid),
        .tag_match     (ascon_tag_match),
        .done          (ascon_done),
        .busy          (ascon_busy)
    );

    // ========================================================================
    // ── 10. DMA Controller ──────────────────────────────────────────────────
    // S_AXI  ← CPU qua S2 (offset 0x100-0x1FF, được decode ở trên)
    // M_AXI  → M2 → DMEM arbiter → data_mem_axi4_slave
    // ========================================================================
    dma_top_axi4 #(
        .ID_WIDTH  (ID_WIDTH),
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32)
    ) u_dma (
        .clk        (clk),
        .rst_n      (rst_n),

        // Config slave (từ CPU qua S2 decoder)
        .S_AXI_AWADDR (s2_awaddr),
        .S_AXI_AWPROT (s2_awprot),
        .S_AXI_AWVALID(dma_s_awvalid),
        .S_AXI_AWREADY(dma_s_awready),
        .S_AXI_WDATA  (s2_wdata),
        .S_AXI_WSTRB  (s2_wstrb),
        .S_AXI_WVALID (dma_s_wvalid),
        .S_AXI_WREADY (dma_s_wready),
        .S_AXI_BRESP  (dma_s_bresp),
        .S_AXI_BVALID (dma_s_bvalid),
        .S_AXI_BREADY (dma_s_bready),
        .S_AXI_ARADDR (s2_araddr),
        .S_AXI_ARPROT (s2_arprot),
        .S_AXI_ARVALID(dma_s_arvalid),
        .S_AXI_ARREADY(dma_s_arready),
        .S_AXI_RDATA  (dma_s_rdata),
        .S_AXI_RRESP  (dma_s_rresp),
        .S_AXI_RVALID (dma_s_rvalid),
        .S_AXI_RREADY (s2_rready),

        // Data master → DMEM arbiter
        .M_AXI_AWID   (m2_awid),    .M_AXI_AWADDR (m2_awaddr),
        .M_AXI_AWLEN  (m2_awlen),   .M_AXI_AWSIZE (m2_awsize),
        .M_AXI_AWBURST(m2_awburst), .M_AXI_AWLOCK (/* open */),
        .M_AXI_AWCACHE(/* open */), .M_AXI_AWPROT (m2_awprot),
        .M_AXI_AWQOS  (/* open */), .M_AXI_AWVALID(m2_awvalid),
        .M_AXI_AWREADY(m2_awready),
        .M_AXI_WDATA  (m2_wdata),   .M_AXI_WSTRB  (m2_wstrb),
        .M_AXI_WLAST  (m2_wlast),   .M_AXI_WVALID (m2_wvalid),
        .M_AXI_WREADY (m2_wready),
        .M_AXI_BID    (m2_bid),     .M_AXI_BRESP  (m2_bresp),
        .M_AXI_BVALID (m2_bvalid),  .M_AXI_BREADY (m2_bready),
        .M_AXI_ARID   (m2_arid),    .M_AXI_ARADDR (m2_araddr),
        .M_AXI_ARLEN  (m2_arlen),   .M_AXI_ARSIZE (m2_arsize),
        .M_AXI_ARBURST(m2_arburst), .M_AXI_ARLOCK (/* open */),
        .M_AXI_ARCACHE(/* open */), .M_AXI_ARPROT (m2_arprot),
        .M_AXI_ARQOS  (/* open */), .M_AXI_ARVALID(m2_arvalid),
        .M_AXI_ARREADY(m2_arready),
        .M_AXI_RID    (m2_rid),     .M_AXI_RDATA  (m2_rdata),
        .M_AXI_RRESP  (m2_rresp),   .M_AXI_RLAST  (m2_rlast),
        .M_AXI_RVALID (m2_rvalid),  .M_AXI_RREADY (m2_rready),

        .irq_done  (dma_irq_done),
        .irq_error (dma_irq_error)
    );

endmodule