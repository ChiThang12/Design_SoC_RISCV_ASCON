`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_debug_data  (v2.0 — khớp soc_top.v 5M×12S)
//
// ĐÃ SỬA so với v1.0:
//   [FIX-1] DUT port: bỏ por_n + tất cả JTAG/UART port → chỉ còn clk, ext_rst_n,
//           soft_rst_pulse (khớp soc_top.v cũ 3M×5S trong file được upload).
//           NHƯNG soc_top.v thực tế (file project) có por_n, uart_tx/rx, tck/tms/tdi/tdo
//           → TB này dùng soc_top 5M×12S đầy đủ.
//   [FIX-2] Reset: clk_reset_ctrl bên trong soc_top cần POR_HOLD=1020 cycle trước
//           khi fabric_rst_n release. TB chờ posedge fabric_rst_n thay vì fixed delay.
//   [FIX-3] Bỏ toàn bộ dut.m3_*, dut.s5_*, dut.s9_*, dut.s11_*,
//           dut.cpu_rst_n, dut.periph_rst_n, dut.uart_irq, dut.dma_irq
//           vì những wire này không tồn tại trong soc_top.v cũ (3M×5S).
//           → Đã thêm lại đầy đủ cho soc_top 5M×12S.
//   [FIX-4] IMEM_INIT_FILE: soc_top cũ dùng "cpu/memory_axi4full/program.hex",
//           soc_top 5M×12S dùng "memory/program.hex" → đồng bộ.
//   [FIX-5] Consistency check trong print_summary: công thức
//           S1 AW = M1+M2+M3 đúng cho 5M×12S (có M3=DMA-Ctrl).
//   [FIX-6] s2_wdata log tại S2-AW: AW và W channel độc lập trong AXI4,
//           data tại thời điểm AW có thể chưa valid. Đổi sang log tại W channel.
//   [FIX-7] Thêm tap cpu_pc = dut.u_cpu.pc_if (không phải dut.u_cpu.pc).
//   [FIX-8] prev_fabric_rst / prev_cpu_rst: dùng reg riêng, không dùng wire.
//   [FIX-9] Hạt nhân soc_top.v trong document = 3M×5S (soc_top cũ).
//           TB này để chạy với soc_top 5M×12S (soc_top.v trong /mnt/project/).
//           Nếu muốn chạy với soc_top 3M×5S trong document,
//           bật macro `define USE_OLD_SOC_TOP và xem hướng dẫn cuối file.
//
// Các luồng được theo dõi:
//   [1] CPU → DCache (M1) → Crossbar → DMEM (S1)
//   [2] CPU → ICache (M0) → Crossbar → IMEM (S0)
//   [3] CPU → DCache (M1) → Crossbar → ASCON (S2)   [MMIO config]
//   [4] ASCON DMA 64-bit (raw) → Width Converter → M2 → Crossbar → DMEM (S1)
//   [5] DMA Controller (M3)   → Crossbar → DMEM (S1)
//   [6] UART AXI writes (S5)  ← Crossbar ← DCache (M1)
//   [7] Reset domain: fabric_rst_n / cpu_rst_n / periph_rst_n
//   [8] Interrupt flow: ASCON IRQ → PLIC → CPU meip
//
// Topo bus (5M × 12S):
//   Masters : M0=ICache  M1=DCache  M2=ASCON-DMA(32b)  M3=DMA-Ctrl  M4=JTAG-DM
//   Slaves  : S0=IMEM  S1=DMEM  S2=ASCON  S3=SoC-Ctrl  S4=CLINT
//             S5=UART  S6=GPIO*  S7=SPI*  S8=Timer*  S9=PLIC
//             S10=OTP*  S11=DMA-Cfg  (* = stub DECERR)
//
// Compile (từ thư mục gốc project):
//   iverilog -g2005 -I. -o tb_debug_data.vvp tb_debug_data.v
// Run:
//   vvp tb_debug_data.vvp
// Wave:
//   gtkwave tb_debug_data.vcd
// =============================================================================

`include "soc_top.v"

module tb_debug_data;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
parameter CLK_PERIOD = 10;          // 100 MHz → 10 ns/cycle
parameter POR_HOLD   = 1020;        // giữ por_n=0 ít nhất POR_CYCLES(1000)+margin
parameter SIM_CYCLES = 20000;       // chu kỳ chạy sau khi reset xong

// ---------------------------------------------------------------------------
// Clock & Reset
// ---------------------------------------------------------------------------
reg clk        = 0;
reg por_n_r    = 0;
reg ext_rst_n_r= 0;

always #(CLK_PERIOD/2) clk = ~clk;

// JTAG idle — TMS=1 giữ TAP ở Test-Logic-Reset, không làm gì
reg jtag_tck_r = 0;
reg jtag_tms_r = 1;
reg jtag_tdi_r = 0;

// UART loopback (TX nối thẳng vào RX để tránh treo)
wire uart_tx_w;
wire uart_rx_w;
assign uart_rx_w = uart_tx_w;

// ---------------------------------------------------------------------------
// Reset sequence — khớp với clk_reset_ctrl bên trong soc_top (POR_CYCLES=1000):
//   Bước 1: por_n=0 + ext_rst_n=0  (20 cy) — mô phỏng power-up
//   Bước 2: ext_rst_n=1, por_n vẫn=0  (POR_HOLD cy) — POR đang đếm
//   Bước 3: por_n=1 → clk_reset_ctrl release fabric_rst_n sau 2-FF sync
//   TB chờ posedge fabric_rst_n thay vì fixed delay để không bị sai
//   khi POR_CYCLES thay đổi.
// ---------------------------------------------------------------------------
initial begin
    por_n_r      = 1'b0;
    ext_rst_n_r  = 1'b0;
    repeat(20) @(posedge clk);
    ext_rst_n_r  = 1'b1;
    repeat(POR_HOLD) @(posedge clk);
    por_n_r = 1'b1;
    $display("[%0t] por_n released — đang chờ fabric_rst_n...", $time);
    @(posedge fabric_rst_n_w);         // chờ clk_reset_ctrl release
    repeat(3) @(posedge clk);
    $display("[%0t] Reset sequence hoàn tất — CPU đang chạy", $time);
end

// ---------------------------------------------------------------------------
// DUT — soc_top 5M×12S
// ---------------------------------------------------------------------------
soc_top #(
    .DATA_WIDTH       (32),
    .ADDR_WIDTH       (32),
    .ID_WIDTH         (4),
    .IMEM_SIZE        (8192),
    .DMEM_SIZE        (8192),
    .IMEM_INIT_FILE   ("memory/program.hex"),
    .POR_CYCLES       (1000),
    .SOFT_RST_STRETCH (8),
    // Slave address map — giữ nguyên default soc_top 5M×12S
    .S0_BASE  (32'h0000_0000), .S0_MASK  (32'hFFFF_E000),  // IMEM  8 KB
    .S1_BASE  (32'h1000_0000), .S1_MASK  (32'hFFFF_E000),  // DMEM  8 KB
    .S2_BASE  (32'h2000_0000), .S2_MASK  (32'hFFFF_F000),  // ASCON 4 KB
    .S3_BASE  (32'h3000_0000), .S3_MASK  (32'hFFFF_F000),  // SoC-Ctrl 4 KB
    .S4_BASE  (32'h4000_0000), .S4_MASK  (32'hFFFF_0000),  // CLINT 64 KB
    .S5_BASE  (32'h5000_0000), .S5_MASK  (32'hFFFF_F000),  // UART  4 KB
    .S6_BASE  (32'h5001_0000), .S6_MASK  (32'hFFFF_F000),  // GPIO  stub
    .S7_BASE  (32'h5002_0000), .S7_MASK  (32'hFFFF_F000),  // SPI   stub
    .S8_BASE  (32'h5003_0000), .S8_MASK  (32'hFFFF_F000),  // Timer stub
    .S9_BASE  (32'h5004_0000), .S9_MASK  (32'hFFFF_F000),  // PLIC  4 KB
    .S10_BASE (32'h6000_0000), .S10_MASK (32'hFFFF_F000),  // OTP   stub
    .S11_BASE (32'h6001_0000), .S11_MASK (32'hFFFF_F000)   // DMA-Cfg 4 KB
) dut (
    .clk       (clk),
    .por_n     (por_n_r),
    .ext_rst_n (ext_rst_n_r),
    .uart_tx   (uart_tx_w),
    .uart_rx   (uart_rx_w),
    .tck       (jtag_tck_r),
    .tms       (jtag_tms_r),
    .tdi       (jtag_tdi_r),
    .tdo       (),
    .tdo_en    ()
);

// ---------------------------------------------------------------------------
// SECTION 0: Reset domain taps
// [FIX-1] soc_top 5M×12S expose 3 reset domain:
//   fabric_rst_n → crossbar, cache, SRAM, CLINT, SoC-Ctrl, ASCON
//   cpu_rst_n    → CPU core (cũng bị ảnh hưởng bởi JTAG ndmreset)
//   periph_rst_n → UART, PLIC, DMA, JTAG
//   cpu_rst      → active-high version = ~cpu_rst_n (dùng trong CPU instance)
// ---------------------------------------------------------------------------
wire fabric_rst_n_w  = dut.fabric_rst_n;
wire cpu_rst_n_w     = dut.cpu_rst_n;
wire periph_rst_n_w  = dut.periph_rst_n;
wire cpu_rst_w       = dut.cpu_rst;        // active-high, = ~cpu_rst_n

// ---------------------------------------------------------------------------
// SECTION A: CPU ↔ ICache / DCache interface taps
// ---------------------------------------------------------------------------

// ICache side — wire names khớp soc_top.v
wire [31:0] cpu_imem_addr     = dut.cpu_imem_addr;
wire        cpu_imem_valid    = dut.cpu_imem_valid;
wire [31:0] icache_imem_rdata = dut.icache_imem_rdata;
wire        icache_imem_ready = dut.icache_imem_ready;

// DCache side
wire [31:0] cpu_dc_addr  = dut.cpu_dcache_addr;
wire [31:0] cpu_dc_wdata = dut.cpu_dcache_wdata;
wire [3:0]  cpu_dc_wstrb = dut.cpu_dcache_wstrb;
wire        cpu_dc_req   = dut.cpu_dcache_req;
wire        cpu_dc_we    = dut.cpu_dcache_we;
wire [31:0] dc_cpu_rdata = dut.dcache_cpu_rdata;
wire        dc_cpu_ready = dut.dcache_cpu_ready;
wire [1:0]  cpu_dc_fence = dut.cpu_dcache_fence_type;

// ---------------------------------------------------------------------------
// SECTION B: AXI Master taps (M0–M4)
// ---------------------------------------------------------------------------

// ── M0: ICache ──────────────────────────────────────────────────────────────
wire [3:0]  m0_arid    = dut.m0_arid;
wire [31:0] m0_araddr  = dut.m0_araddr;
wire [7:0]  m0_arlen   = dut.m0_arlen;
wire [2:0]  m0_arsize  = dut.m0_arsize;
wire        m0_arvalid = dut.m0_arvalid;
wire        m0_arready = dut.m0_arready;
wire [3:0]  m0_rid     = dut.m0_rid;
wire [31:0] m0_rdata   = dut.m0_rdata;
wire [1:0]  m0_rresp   = dut.m0_rresp;
wire        m0_rlast   = dut.m0_rlast;
wire        m0_rvalid  = dut.m0_rvalid;
wire        m0_rready  = dut.m0_rready;
wire        m0_awvalid = dut.m0_awvalid;   // should NEVER assert (ICache read-only)

// ── M1: DCache ──────────────────────────────────────────────────────────────
wire [3:0]  m1_awid    = dut.m1_awid;
wire [31:0] m1_awaddr  = dut.m1_awaddr;
wire [7:0]  m1_awlen   = dut.m1_awlen;
wire        m1_awvalid = dut.m1_awvalid;
wire        m1_awready = dut.m1_awready;
wire [31:0] m1_wdata   = dut.m1_wdata;
wire [3:0]  m1_wstrb   = dut.m1_wstrb;
wire        m1_wlast   = dut.m1_wlast;
wire        m1_wvalid  = dut.m1_wvalid;
wire        m1_wready  = dut.m1_wready;
wire [3:0]  m1_bid     = dut.m1_bid;
wire [1:0]  m1_bresp   = dut.m1_bresp;
wire        m1_bvalid  = dut.m1_bvalid;
wire        m1_bready  = dut.m1_bready;
wire [3:0]  m1_arid    = dut.m1_arid;
wire [31:0] m1_araddr  = dut.m1_araddr;
wire [7:0]  m1_arlen   = dut.m1_arlen;
wire        m1_arvalid = dut.m1_arvalid;
wire        m1_arready = dut.m1_arready;
wire [3:0]  m1_rid     = dut.m1_rid;
wire [31:0] m1_rdata   = dut.m1_rdata;
wire [1:0]  m1_rresp   = dut.m1_rresp;
wire        m1_rlast   = dut.m1_rlast;
wire        m1_rvalid  = dut.m1_rvalid;
wire        m1_rready  = dut.m1_rready;

// ── M2: ASCON DMA 32-bit (sau width converter) ──────────────────────────────
wire [3:0]  m2_awid    = dut.m2_awid;
wire [31:0] m2_awaddr  = dut.m2_awaddr;
wire [7:0]  m2_awlen   = dut.m2_awlen;
wire        m2_awvalid = dut.m2_awvalid;
wire        m2_awready = dut.m2_awready;
wire [31:0] m2_wdata   = dut.m2_wdata;
wire [3:0]  m2_wstrb   = dut.m2_wstrb;
wire        m2_wlast   = dut.m2_wlast;
wire        m2_wvalid  = dut.m2_wvalid;
wire        m2_wready  = dut.m2_wready;
wire [3:0]  m2_bid     = dut.m2_bid;
wire [1:0]  m2_bresp   = dut.m2_bresp;
wire        m2_bvalid  = dut.m2_bvalid;
wire        m2_bready  = dut.m2_bready;
wire [3:0]  m2_arid    = dut.m2_arid;
wire [31:0] m2_araddr  = dut.m2_araddr;
wire [7:0]  m2_arlen   = dut.m2_arlen;
wire        m2_arvalid = dut.m2_arvalid;
wire        m2_arready = dut.m2_arready;
wire [3:0]  m2_rid     = dut.m2_rid;
wire [31:0] m2_rdata   = dut.m2_rdata;
wire [1:0]  m2_rresp   = dut.m2_rresp;
wire        m2_rlast   = dut.m2_rlast;
wire        m2_rvalid  = dut.m2_rvalid;
wire        m2_rready  = dut.m2_rready;

// ── M3: DMA Controller ──────────────────────────────────────────────────────
// [FIX-3] M3 là master mới trong soc_top 5M×12S, không có trong phiên bản cũ
wire [3:0]  m3_awid    = dut.m3_awid;
wire [31:0] m3_awaddr  = dut.m3_awaddr;
wire [7:0]  m3_awlen   = dut.m3_awlen;
wire        m3_awvalid = dut.m3_awvalid;
wire        m3_awready = dut.m3_awready;
wire [31:0] m3_wdata   = dut.m3_wdata;
wire [3:0]  m3_wstrb   = dut.m3_wstrb;
wire        m3_wlast   = dut.m3_wlast;
wire        m3_wvalid  = dut.m3_wvalid;
wire        m3_wready  = dut.m3_wready;
wire [3:0]  m3_bid     = dut.m3_bid;
wire [1:0]  m3_bresp   = dut.m3_bresp;
wire        m3_bvalid  = dut.m3_bvalid;
wire        m3_bready  = dut.m3_bready;
wire [3:0]  m3_arid    = dut.m3_arid;
wire [31:0] m3_araddr  = dut.m3_araddr;
wire [7:0]  m3_arlen   = dut.m3_arlen;
wire        m3_arvalid = dut.m3_arvalid;
wire        m3_arready = dut.m3_arready;
wire [3:0]  m3_rid     = dut.m3_rid;
wire [31:0] m3_rdata   = dut.m3_rdata;
wire [1:0]  m3_rresp   = dut.m3_rresp;
wire        m3_rlast   = dut.m3_rlast;
wire        m3_rvalid  = dut.m3_rvalid;
wire        m3_rready  = dut.m3_rready;

// ── ASCON DMA raw 64-bit (trước width converter) ────────────────────────────
wire [3:0]  dma_awid    = dut.dma_awid;
wire [31:0] dma_awaddr  = dut.dma_awaddr;
wire [7:0]  dma_awlen   = dut.dma_awlen;
wire        dma_awvalid = dut.dma_awvalid;
wire        dma_awready = dut.dma_awready;
wire [63:0] dma_wdata   = dut.dma_wdata;
wire [7:0]  dma_wstrb   = dut.dma_wstrb;
wire        dma_wlast   = dut.dma_wlast;
wire        dma_wvalid  = dut.dma_wvalid;
wire        dma_wready  = dut.dma_wready;
wire [1:0]  dma_bresp   = dut.dma_bresp;
wire        dma_bvalid  = dut.dma_bvalid;
wire [3:0]  dma_arid    = dut.dma_arid;
wire [31:0] dma_araddr  = dut.dma_araddr;
wire [7:0]  dma_arlen   = dut.dma_arlen;
wire        dma_arvalid = dut.dma_arvalid;
wire        dma_arready = dut.dma_arready;
wire [63:0] dma_rdata   = dut.dma_rdata;
wire [1:0]  dma_rresp   = dut.dma_rresp;
wire        dma_rlast   = dut.dma_rlast;
wire        dma_rvalid  = dut.dma_rvalid;
wire        dma_rready  = dut.dma_rready;

// ---------------------------------------------------------------------------
// SECTION C: AXI Slave taps (S0–S5, S9, S11)
// [FIX-3] Thêm đầy đủ S5/S9/S11 cho soc_top 5M×12S
// ---------------------------------------------------------------------------

// ── S0: IMEM ────────────────────────────────────────────────────────────────
wire [3:0]  s0_rid     = dut.s0_rid;
wire [31:0] s0_araddr  = dut.s0_araddr;
wire        s0_arvalid = dut.s0_arvalid;
wire        s0_arready = dut.s0_arready;
wire [31:0] s0_rdata   = dut.s0_rdata;
wire [1:0]  s0_rresp   = dut.s0_rresp;
wire        s0_rlast   = dut.s0_rlast;
wire        s0_rvalid  = dut.s0_rvalid;
wire        s0_rready  = dut.s0_rready;

// ── S1: DMEM ────────────────────────────────────────────────────────────────
wire [3:0]  s1_awid    = dut.s1_awid;
wire [31:0] s1_awaddr  = dut.s1_awaddr;
wire [7:0]  s1_awlen   = dut.s1_awlen;
wire        s1_awvalid = dut.s1_awvalid;
wire        s1_awready = dut.s1_awready;
wire [31:0] s1_wdata   = dut.s1_wdata;
wire [3:0]  s1_wstrb   = dut.s1_wstrb;
wire        s1_wlast   = dut.s1_wlast;
wire        s1_wvalid  = dut.s1_wvalid;
wire        s1_wready  = dut.s1_wready;
wire [1:0]  s1_bresp   = dut.s1_bresp;
wire        s1_bvalid  = dut.s1_bvalid;
wire        s1_bready  = dut.s1_bready;
wire [3:0]  s1_arid    = dut.s1_arid;
wire [31:0] s1_araddr  = dut.s1_araddr;
wire [7:0]  s1_arlen   = dut.s1_arlen;
wire        s1_arvalid = dut.s1_arvalid;
wire        s1_arready = dut.s1_arready;
wire [31:0] s1_rdata   = dut.s1_rdata;
wire [1:0]  s1_rresp   = dut.s1_rresp;
wire        s1_rlast   = dut.s1_rlast;
wire        s1_rvalid  = dut.s1_rvalid;
wire        s1_rready  = dut.s1_rready;

// ── S2: ASCON slave ─────────────────────────────────────────────────────────
wire [3:0]  s2_awid    = dut.s2_awid;
wire [31:0] s2_awaddr  = dut.s2_awaddr;
wire        s2_awvalid = dut.s2_awvalid;
wire        s2_awready = dut.s2_awready;
wire [31:0] s2_wdata   = dut.s2_wdata;   // [FIX-6] dùng tap này log tại W channel
wire [3:0]  s2_wstrb   = dut.s2_wstrb;
wire        s2_wvalid  = dut.s2_wvalid;
wire        s2_wready  = dut.s2_wready;
wire [1:0]  s2_bresp   = dut.s2_bresp;
wire        s2_bvalid  = dut.s2_bvalid;
wire [31:0] s2_araddr  = dut.s2_araddr;
wire        s2_arvalid = dut.s2_arvalid;
wire        s2_arready = dut.s2_arready;
wire [31:0] s2_rdata   = dut.s2_rdata;
wire [1:0]  s2_rresp   = dut.s2_rresp;
wire        s2_rvalid  = dut.s2_rvalid;
wire        s2_rready  = dut.s2_rready;

// ── S3: SoC Ctrl ────────────────────────────────────────────────────────────
wire [31:0] s3_awaddr  = dut.s3_awaddr;
wire        s3_awvalid = dut.s3_awvalid;
wire        s3_awready = dut.s3_awready;
wire [31:0] s3_wdata   = dut.s3_wdata;
wire        s3_wvalid  = dut.s3_wvalid;
wire [31:0] s3_araddr  = dut.s3_araddr;
wire        s3_arvalid = dut.s3_arvalid;
wire        s3_arready = dut.s3_arready;
wire [31:0] s3_rdata   = dut.s3_rdata;
wire        s3_rvalid  = dut.s3_rvalid;

// ── S4: CLINT ────────────────────────────────────────────────────────────────
wire [31:0] s4_awaddr  = dut.s4_awaddr;
wire        s4_awvalid = dut.s4_awvalid;
wire        s4_awready = dut.s4_awready;
wire [31:0] s4_wdata   = dut.s4_wdata;
wire        s4_wvalid  = dut.s4_wvalid;
wire [31:0] s4_araddr  = dut.s4_araddr;
wire        s4_arvalid = dut.s4_arvalid;
wire        s4_arready = dut.s4_arready;
wire [31:0] s4_rdata   = dut.s4_rdata;
wire        s4_rvalid  = dut.s4_rvalid;

// ── S5: UART ────────────────────────────────────────────────────────────────
// [FIX-3] S5 chỉ có trong soc_top 5M×12S
wire [31:0] s5_awaddr  = dut.s5_awaddr;
wire        s5_awvalid = dut.s5_awvalid;
wire        s5_awready = dut.s5_awready;
wire [31:0] s5_wdata   = dut.s5_wdata;
wire        s5_wvalid  = dut.s5_wvalid;
wire        s5_wready  = dut.s5_wready;
wire [1:0]  s5_bresp   = dut.s5_bresp;
wire        s5_bvalid  = dut.s5_bvalid;
wire [31:0] s5_araddr  = dut.s5_araddr;
wire        s5_arvalid = dut.s5_arvalid;
wire        s5_arready = dut.s5_arready;
wire [31:0] s5_rdata   = dut.s5_rdata;
wire        s5_rvalid  = dut.s5_rvalid;

// ── S9: PLIC ────────────────────────────────────────────────────────────────
wire [31:0] s9_awaddr  = dut.s9_awaddr;
wire        s9_awvalid = dut.s9_awvalid;
wire        s9_awready = dut.s9_awready;
wire [31:0] s9_araddr  = dut.s9_araddr;
wire        s9_arvalid = dut.s9_arvalid;
wire        s9_arready = dut.s9_arready;

// ── S11: DMA Ctrl Config ────────────────────────────────────────────────────
wire [31:0] s11_awaddr  = dut.s11_awaddr;
wire        s11_awvalid = dut.s11_awvalid;
wire        s11_awready = dut.s11_awready;
wire [31:0] s11_araddr  = dut.s11_araddr;
wire        s11_arvalid = dut.s11_arvalid;
wire        s11_arready = dut.s11_arready;

// ---------------------------------------------------------------------------
// SECTION D: Interrupt & IRQ taps
// [FIX-3] Thêm uart_irq, dma_irq cho soc_top 5M×12S
// ---------------------------------------------------------------------------
wire        ascon_irq_w    = dut.ascon_irq;
wire        uart_irq_w     = dut.uart_irq;     // uart_top → plic irq_src[1/2]
wire        dma_irq_w      = dut.dma_irq;      // dma_ctrl → plic irq_src[9]
wire        timer_irq_w    = dut.timer_irq;    // clint → cpu
wire        sw_irq_w       = dut.sw_irq;       // clint → cpu
wire        external_irq_w = dut.external_irq; // plic meip → cpu

// ---------------------------------------------------------------------------
// SECTION E: ASCON internal taps
// ---------------------------------------------------------------------------
wire        ascon_core_start  = dut.u_ascon.u_slave.core_start;
wire        ascon_dma_start   = dut.u_ascon.u_slave.dma_start;
wire        ascon_core_busy   = dut.u_ascon.u_slave.core_busy;
wire        ascon_core_done   = dut.u_ascon.u_slave.core_done;
wire        ascon_dma_busy    = dut.u_ascon.u_slave.dma_busy;
wire        ascon_dma_done    = dut.u_ascon.u_slave.status_dma_done;
wire [31:0] ascon_status_word = dut.u_ascon.u_slave.status_word;
wire [31:0] ascon_dma_src     = dut.u_ascon.u_slave.reg_dma_src;
wire [31:0] ascon_dma_dst     = dut.u_ascon.u_slave.reg_dma_dst;
wire [31:0] ascon_dma_len     = dut.u_ascon.u_slave.reg_dma_len;
wire [31:0] ascon_reg_ctext0  = dut.u_ascon.u_slave.reg_ctext_0;
wire [31:0] ascon_reg_ctext1  = dut.u_ascon.u_slave.reg_ctext_1;
wire [31:0] ascon_reg_tag0    = dut.u_ascon.u_slave.reg_tag_0;
wire [31:0] ascon_reg_tag1    = dut.u_ascon.u_slave.reg_tag_1;
wire [31:0] ascon_reg_tag2    = dut.u_ascon.u_slave.reg_tag_2;
wire [31:0] ascon_reg_tag3    = dut.u_ascon.u_slave.reg_tag_3;

// ---------------------------------------------------------------------------
// SECTION F: CPU PC tap
// [FIX-7] Dùng pc_if (PC ở IF stage) — đây là wire tồn tại trong riscv_cpu_core
// ---------------------------------------------------------------------------
wire [31:0] cpu_pc = dut.u_cpu.pc_if;

// ---------------------------------------------------------------------------
// VCD dump
// ---------------------------------------------------------------------------
initial begin
    $dumpfile("tb_debug_data.vcd");
    $dumpvars(0, tb_debug_data);
end

// ---------------------------------------------------------------------------
// Counters — đặt ở đây để tất cả monitor block phía dưới có thể dùng
// ---------------------------------------------------------------------------
integer cnt_cpu_dc_req = 0;
integer cnt_cpu_dc_wr  = 0;
integer cnt_cpu_dc_rd  = 0;
integer cnt_m0_ar      = 0;
integer cnt_m1_aw      = 0;
integer cnt_m1_w       = 0;
integer cnt_m1_ar      = 0;
integer cnt_m2_aw      = 0;
integer cnt_m2_ar      = 0;
integer cnt_m3_aw      = 0;   // [FIX-3] M3 DMA-Ctrl
integer cnt_m3_ar      = 0;
integer cnt_dma_aw     = 0;   // ASCON DMA 64-bit raw side
integer cnt_dma_ar     = 0;
integer cnt_s0_ar      = 0;
integer cnt_s1_aw      = 0;
integer cnt_s1_ar      = 0;
integer cnt_s2_aw      = 0;
integer cnt_s2_ar      = 0;
integer cnt_s5_aw      = 0;   // [FIX-3] UART
integer cnt_s5_ar      = 0;
integer cnt_s9_aw      = 0;   // [FIX-3] PLIC
integer cnt_s11_aw     = 0;   // [FIX-3] DMA-Cfg
integer cnt_decerr     = 0;
integer cnt_ascon_start= 0;
integer cnt_ascon_done = 0;
integer cnt_plic_meip  = 0;
integer cnt_uart_irq   = 0;

// ---------------------------------------------------------------------------
// Edge-detect registers
// ---------------------------------------------------------------------------
reg prev_ascon_core_done = 0;
reg prev_ascon_dma_done  = 0;
reg prev_ascon_irq       = 0;
reg prev_uart_irq        = 0;
reg prev_meip            = 0;
reg prev_timer_irq       = 0;
// [FIX-8] Dùng reg riêng cho reset domain edge detect, không lẫn vào wire
reg prev_fabric_rst      = 0;
reg prev_cpu_rst         = 0;

always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        prev_ascon_core_done <= ascon_core_done;
        prev_ascon_dma_done  <= ascon_dma_done;
        prev_ascon_irq       <= ascon_irq_w;
        prev_uart_irq        <= uart_irq_w;
        prev_meip            <= external_irq_w;
        prev_timer_irq       <= timer_irq_w;
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 1: CPU ↔ DCache
// Hiển thị mọi load/store từ CPU, kể cả MMIO (ASCON, UART, PLIC, CLINT)
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w && cpu_dc_req) begin
        if (cpu_dc_we)
            $display("[%0t] [CPU→DC] WRITE  addr=0x%08h data=0x%08h strb=%04b  → %s",
                     $time, cpu_dc_addr, cpu_dc_wdata, cpu_dc_wstrb,
                     slave_of_addr(cpu_dc_addr));
        else
            $display("[%0t] [CPU→DC] READ   addr=0x%08h  → %s",
                     $time, cpu_dc_addr, slave_of_addr(cpu_dc_addr));
        cnt_cpu_dc_req = cnt_cpu_dc_req + 1;
        if (cpu_dc_we) cnt_cpu_dc_wr = cnt_cpu_dc_wr + 1;
        else           cnt_cpu_dc_rd = cnt_cpu_dc_rd + 1;
    end
    if (fabric_rst_n_w && dc_cpu_ready && !cpu_dc_we && cpu_dc_req)
        $display("[%0t] [DC→CPU] RDATA  data=0x%08h", $time, dc_cpu_rdata);
    if (fabric_rst_n_w && |cpu_dc_fence)
        $display("[%0t] [CPU→DC] FENCE  type=%02b", $time, cpu_dc_fence);
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 2: M0 ICache AXI
// ICache chỉ dùng kênh AR/R — nếu AW assert là lỗi nghiêm trọng
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (m0_arvalid && m0_arready) begin
            $display("[%0t] [M0-AR] ICache  addr=0x%08h len=%0d size=%0d",
                     $time, m0_araddr, m0_arlen, m0_arsize);
            cnt_m0_ar = cnt_m0_ar + 1;
            if (m0_araddr[31:16] != 16'h0000)
                $display("[%0t] [WARN]  M0 fetch ngoài IMEM! addr=0x%08h  → kiểm tra ICache tag",
                         $time, m0_araddr);
        end
        if (m0_rvalid && m0_rready && m0_rresp != 2'b00) begin
            $display("[%0t] [ERR]   M0 RRESP=%02b (non-OKAY) addr=0x%08h",
                     $time, m0_rresp, m0_araddr);
            cnt_decerr = cnt_decerr + 1;
        end
        if (m0_awvalid)
            $display("[%0t] [ERR!!!] M0 AW assert — ICache không được write!", $time);
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 3: M1 DCache AXI (write & read)
// Bao gồm write-back (DCache dirty evict) và read-miss refill
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (m1_awvalid && m1_awready) begin
            $display("[%0t] [M1-AW] DCache  addr=0x%08h len=%0d  → %s",
                     $time, m1_awaddr, m1_awlen, slave_of_addr(m1_awaddr));
            cnt_m1_aw = cnt_m1_aw + 1;
        end
        if (m1_wvalid && m1_wready) begin
            $display("[%0t] [M1-W ] DCache  data=0x%08h strb=%04b last=%b",
                     $time, m1_wdata, m1_wstrb, m1_wlast);
            cnt_m1_w = cnt_m1_w + 1;
        end
        if (m1_bvalid && m1_bready) begin
            if (m1_bresp != 2'b00) begin
                $display("[%0t] [ERR]   M1 BRESP=%02b (non-OKAY) — kiểm tra addr decode",
                         $time, m1_bresp);
                cnt_decerr = cnt_decerr + 1;
            end else
                $display("[%0t] [M1-B ] DCache  id=%0d OKAY", $time, m1_bid);
        end
        if (m1_arvalid && m1_arready) begin
            $display("[%0t] [M1-AR] DCache  addr=0x%08h len=%0d  → %s",
                     $time, m1_araddr, m1_arlen, slave_of_addr(m1_araddr));
            cnt_m1_ar = cnt_m1_ar + 1;
        end
        if (m1_rvalid && m1_rready) begin
            if (m1_rresp != 2'b00) begin
                $display("[%0t] [ERR]   M1 RRESP=%02b (non-OKAY)", $time, m1_rresp);
                cnt_decerr = cnt_decerr + 1;
            end else
                $display("[%0t] [M1-R ] DCache  data=0x%08h last=%b", $time, m1_rdata, m1_rlast);
        end
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 4: ASCON DMA 64-bit raw (trước width converter)
// Dùng để debug converter: số burst 64-bit phải tương ứng số burst 32-bit ×2
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (dma_awvalid && dma_awready) begin
            $display("[%0t] [DMA64-AW] ASCON-DMA  addr=0x%08h len=%0d  (64-bit)",
                     $time, dma_awaddr, dma_awlen);
            cnt_dma_aw = cnt_dma_aw + 1;
        end
        if (dma_wvalid && dma_wready)
            $display("[%0t] [DMA64-W ] data=0x%016h strb=%08b last=%b",
                     $time, dma_wdata, dma_wstrb, dma_wlast);
        if (dma_bvalid) begin
            if (dma_bresp != 2'b00) begin
                $display("[%0t] [ERR]   DMA64 BRESP=%02b (non-OKAY)", $time, dma_bresp);
                cnt_decerr = cnt_decerr + 1;
            end
        end
        if (dma_arvalid && dma_arready) begin
            $display("[%0t] [DMA64-AR] ASCON-DMA  addr=0x%08h len=%0d  (64-bit)",
                     $time, dma_araddr, dma_arlen);
            cnt_dma_ar = cnt_dma_ar + 1;
        end
        if (dma_rvalid && dma_rready)
            $display("[%0t] [DMA64-R ] data=0x%016h last=%b rresp=%02b",
                     $time, dma_rdata, dma_rlast, dma_rresp);
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 5: M2 Width Converter output → Crossbar (32-bit)
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (m2_awvalid && m2_awready) begin
            $display("[%0t] [M2-AW ] WConv→Xbar  addr=0x%08h len=%0d  → %s",
                     $time, m2_awaddr, m2_awlen, slave_of_addr(m2_awaddr));
            cnt_m2_aw = cnt_m2_aw + 1;
        end
        if (m2_wvalid && m2_wready)
            $display("[%0t] [M2-W  ] WConv→Xbar  data=0x%08h strb=%04b last=%b",
                     $time, m2_wdata, m2_wstrb, m2_wlast);
        if (m2_bvalid && m2_bresp != 2'b00) begin
            $display("[%0t] [ERR]   M2 BRESP=%02b (non-OKAY)", $time, m2_bresp);
            cnt_decerr = cnt_decerr + 1;
        end
        if (m2_arvalid && m2_arready) begin
            $display("[%0t] [M2-AR ] WConv→Xbar  addr=0x%08h  → %s",
                     $time, m2_araddr, slave_of_addr(m2_araddr));
            cnt_m2_ar = cnt_m2_ar + 1;
        end
        if (m2_rvalid && m2_rready && m2_rresp != 2'b00) begin
            $display("[%0t] [ERR]   M2 RRESP=%02b (non-OKAY)", $time, m2_rresp);
            cnt_decerr = cnt_decerr + 1;
        end
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 6: M3 DMA Controller
// [FIX-3] M3 là master mới, không có trong soc_top 3M×5S cũ
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (m3_awvalid && m3_awready) begin
            $display("[%0t] [M3-AW ] DMA-Ctrl    addr=0x%08h len=%0d  → %s",
                     $time, m3_awaddr, m3_awlen, slave_of_addr(m3_awaddr));
            cnt_m3_aw = cnt_m3_aw + 1;
        end
        if (m3_wvalid && m3_wready)
            $display("[%0t] [M3-W  ] DMA-Ctrl    data=0x%08h strb=%04b last=%b",
                     $time, m3_wdata, m3_wstrb, m3_wlast);
        if (m3_arvalid && m3_arready) begin
            $display("[%0t] [M3-AR ] DMA-Ctrl    addr=0x%08h len=%0d  → %s",
                     $time, m3_araddr, m3_arlen, slave_of_addr(m3_araddr));
            cnt_m3_ar = cnt_m3_ar + 1;
        end
        if (m3_bvalid && m3_bready && m3_bresp != 2'b00) begin
            $display("[%0t] [ERR]   M3 BRESP=%02b (non-OKAY)", $time, m3_bresp);
            cnt_decerr = cnt_decerr + 1;
        end
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 7: Slave ports (S0, S1, S2, S5, S9, S11)
// ---------------------------------------------------------------------------

// S0 IMEM
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (s0_arvalid && s0_arready) begin
            $display("[%0t] [S0-AR ] IMEM  addr=0x%08h", $time, s0_araddr);
            cnt_s0_ar = cnt_s0_ar + 1;
        end
        if (s0_rvalid && s0_rready && s0_rresp != 2'b00) begin
            $display("[%0t] [ERR]   S0 RRESP=%02b non-OKAY  addr=0x%08h",
                     $time, s0_rresp, s0_araddr);
            cnt_decerr = cnt_decerr + 1;
        end
    end
end

// S1 DMEM — log đầy đủ cả read và write
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (s1_awvalid && s1_awready) begin
            $display("[%0t] [S1-AW ] DMEM  addr=0x%08h len=%0d  *** DMEM AW ***",
                     $time, s1_awaddr, s1_awlen);
            cnt_s1_aw = cnt_s1_aw + 1;
            if ((s1_awaddr & 32'hFFFF_E000) != 32'h1000_0000)
                $display("[%0t] [WARN]  S1 AW addr=0x%08h ngoài DMEM range!", $time, s1_awaddr);
        end
        if (s1_wvalid && s1_wready)
            $display("[%0t] [S1-W  ] DMEM  data=0x%08h strb=%04b last=%b",
                     $time, s1_wdata, s1_wstrb, s1_wlast);
        if (s1_bvalid && s1_bready) begin
            if (s1_bresp != 2'b00) begin
                $display("[%0t] [ERR]   S1 BRESP=%02b non-OKAY", $time, s1_bresp);
                cnt_decerr = cnt_decerr + 1;
            end else
                $display("[%0t] [S1-B  ] DMEM  OKAY", $time);
        end
        if (s1_arvalid && s1_arready) begin
            $display("[%0t] [S1-AR ] DMEM  addr=0x%08h len=%0d",
                     $time, s1_araddr, s1_arlen);
            cnt_s1_ar = cnt_s1_ar + 1;
        end
        if (s1_rvalid && s1_rready)
            $display("[%0t] [S1-R  ] DMEM  data=0x%08h last=%b rresp=%02b",
                     $time, s1_rdata, s1_rlast, s1_rresp);
    end
end

// S2 ASCON — log mọi register access với offset decode
// [FIX-6] Log data tại W channel (s2_wvalid), KHÔNG tại AW channel
//   Lý do: AW và W là hai kênh độc lập trong AXI4 — W data có thể đến
//   muộn hơn AW nhiều cycle (back-pressure từ slave). Log data tại AW
//   sẽ đọc giá trị chưa valid, gây debug sai.
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (s2_awvalid && s2_awready) begin
            $display("[%0t] [S2-AW ] ASCON  offset=0x%03h  [%s]  — W data sẽ log riêng",
                     $time, s2_awaddr[11:0], ascon_reg_name(s2_awaddr[11:0]));
            cnt_s2_aw = cnt_s2_aw + 1;
        end
        // [FIX-6] Log data tại đây — khi W channel handshake
        if (s2_wvalid && s2_wready)
            $display("[%0t] [S2-W  ] ASCON  data=0x%08h strb=%04b  offset→[%s]",
                     $time, s2_wdata, s2_wstrb, ascon_reg_name(s2_awaddr[11:0]));
        if (s2_arvalid && s2_arready) begin
            $display("[%0t] [S2-AR ] ASCON  offset=0x%03h  [%s]",
                     $time, s2_araddr[11:0], ascon_reg_name(s2_araddr[11:0]));
            cnt_s2_ar = cnt_s2_ar + 1;
        end
        if (s2_rvalid && s2_rready)
            $display("[%0t] [S2-R  ] ASCON  data=0x%08h  STATUS bits=%08b",
                     $time, s2_rdata, s2_rdata[7:0]);
        if (s2_bvalid && s2_bresp != 2'b00) begin
            $display("[%0t] [ERR]   S2 BRESP=%02b non-OKAY", $time, s2_bresp);
            cnt_decerr = cnt_decerr + 1;
        end
    end
end

// S5 UART — dùng periph_rst_n
always @(posedge clk) begin
    if (periph_rst_n_w) begin
        if (s5_awvalid && s5_awready) begin
            $display("[%0t] [S5-AW ] UART  offset=0x%02h  [%s]",
                     $time, s5_awaddr[7:0], uart_reg_name(s5_awaddr[7:0]));
            cnt_s5_aw = cnt_s5_aw + 1;
        end
        if (s5_wvalid && s5_wready)
            $display("[%0t] [S5-W  ] UART  data=0x%08h", $time, s5_wdata);
        if (s5_arvalid && s5_arready) begin
            $display("[%0t] [S5-AR ] UART  offset=0x%02h  [%s]",
                     $time, s5_araddr[7:0], uart_reg_name(s5_araddr[7:0]));
            cnt_s5_ar = cnt_s5_ar + 1;
        end
        if (s5_rvalid)
            $display("[%0t] [S5-R  ] UART  data=0x%08h", $time, s5_rdata);
        if (s5_bvalid && s5_bresp != 2'b00)
            $display("[%0t] [ERR]   S5 UART BRESP=%02b non-OKAY", $time, s5_bresp);
    end
end

// S9 PLIC, S11 DMA-Cfg — dùng periph_rst_n
always @(posedge clk) begin
    if (periph_rst_n_w) begin
        if (s9_awvalid && s9_awready) begin
            $display("[%0t] [S9-AW ] PLIC  offset=0x%06h", $time, s9_awaddr[21:0]);
            cnt_s9_aw = cnt_s9_aw + 1;
        end
        if (s9_arvalid && s9_arready)
            $display("[%0t] [S9-AR ] PLIC  offset=0x%06h", $time, s9_araddr[21:0]);
        if (s11_awvalid && s11_awready) begin
            $display("[%0t] [S11-AW] DMA-Cfg  offset=0x%03h", $time, s11_awaddr[11:0]);
            cnt_s11_aw = cnt_s11_aw + 1;
        end
        if (s11_arvalid && s11_arready)
            $display("[%0t] [S11-AR] DMA-Cfg  offset=0x%03h", $time, s11_araddr[11:0]);
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 8: ASCON IP events
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (ascon_core_start) begin
            $display("[%0t] [ASCON] CORE START  STATUS=0x%08h", $time, ascon_status_word);
            cnt_ascon_start = cnt_ascon_start + 1;
        end
        if (ascon_dma_start)
            $display("[%0t] [ASCON] DMA  START  src=0x%08h dst=0x%08h len=%0d",
                     $time, ascon_dma_src, ascon_dma_dst, ascon_dma_len);
        if (ascon_core_done && !prev_ascon_core_done) begin
            $display("[%0t] [ASCON] CORE DONE   STATUS=0x%08h  CTEXT=%08h_%08h",
                     $time, ascon_status_word, ascon_reg_ctext0, ascon_reg_ctext1);
            $display("[%0t] [ASCON] TAG = %08h_%08h_%08h_%08h",
                     $time, ascon_reg_tag0, ascon_reg_tag1, ascon_reg_tag2, ascon_reg_tag3);
            cnt_ascon_done = cnt_ascon_done + 1;
        end
        if (ascon_dma_done && !prev_ascon_dma_done)
            $display("[%0t] [ASCON] DMA  DONE   STATUS=0x%08h", $time, ascon_status_word);
        if (ascon_irq_w && !prev_ascon_irq)
            $display("[%0t] [ASCON] IRQ raised  → PLIC src[8]", $time);
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 9: Interrupt flow
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (periph_rst_n_w) begin
        if (uart_irq_w && !prev_uart_irq) begin
            $display("[%0t] [IRQ]  UART irq raised  → PLIC src[1,2]", $time);
            cnt_uart_irq = cnt_uart_irq + 1;
        end
        if (dma_irq_w)
            $display("[%0t] [IRQ]  DMA irq raised   → PLIC src[9]", $time);
        if (external_irq_w && !prev_meip) begin
            $display("[%0t] [IRQ]  PLIC meip → CPU external_irq asserted", $time);
            cnt_plic_meip = cnt_plic_meip + 1;
        end
        if (timer_irq_w && !prev_timer_irq)
            $display("[%0t] [IRQ]  CLINT timer_irq → CPU (bypass PLIC)", $time);
    end
end

// ---------------------------------------------------------------------------
// Monitor — STAGE 10: Reset domain events
// [FIX-8] Dùng reg prev_fabric_rst / prev_cpu_rst riêng, không lẫn wire
//   Lý do: so sánh wire !== reg cần reg lưu giá trị cycle trước.
//   Trong v1.0, prev_fabric_rst được khai báo reg nhưng KHÔNG có always block
//   để update → luôn = 0 → phát hiện edge sai mỗi cycle.
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    prev_fabric_rst <= fabric_rst_n_w;
    prev_cpu_rst    <= cpu_rst_n_w;
end

always @(posedge clk) begin
    if (fabric_rst_n_w !== prev_fabric_rst)
        $display("[%0t] [RST]  fabric_rst_n = %b", $time, fabric_rst_n_w);
    if (cpu_rst_n_w !== prev_cpu_rst)
        $display("[%0t] [RST]  cpu_rst_n    = %b  (cpu_rst=%b)", $time, cpu_rst_n_w, cpu_rst_w);
end

// ---------------------------------------------------------------------------
// Monitor — AXI consistency check
// Kiểm tra S1 AW count == M1 AW + M2 AW + M3 AW
// [FIX-5] Công thức đúng cho 5M×12S: cả 3 master M1/M2/M3 đều có thể write DMEM
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (fabric_rst_n_w) begin
        if (m1_bvalid && m1_bready && m1_bresp == 2'b11)
            $display("[%0t] [!!!] DECERR M1 write — addr=0x%08h chưa decode",
                     $time, m1_awaddr);
        if (m1_rvalid && m1_rready && m1_rresp == 2'b11)
            $display("[%0t] [!!!] DECERR M1 read  — addr=0x%08h chưa decode",
                     $time, m1_araddr);
        if (m2_bvalid && m2_bready && m2_bresp == 2'b11)
            $display("[%0t] [!!!] DECERR M2 (ASCON-DMA write) — addr=0x%08h",
                     $time, m2_awaddr);
        if (m3_bvalid && m3_bready && m3_bresp == 2'b11)
            $display("[%0t] [!!!] DECERR M3 (DMA-Ctrl write)  — addr=0x%08h",
                     $time, m3_awaddr);
    end
end

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------
function [63:0] slave_of_addr;
    input [31:0] addr;
    begin
        if      ((addr & 32'hFFFF_E000) == 32'h0000_0000) slave_of_addr = "IMEM    ";
        else if ((addr & 32'hFFFF_E000) == 32'h1000_0000) slave_of_addr = "DMEM    ";
        else if ((addr & 32'hFFFF_F000) == 32'h2000_0000) slave_of_addr = "ASCON   ";
        else if ((addr & 32'hFFFF_F000) == 32'h3000_0000) slave_of_addr = "SoC-Ctrl";
        else if ((addr & 32'hFFFF_0000) == 32'h4000_0000) slave_of_addr = "CLINT   ";
        else if ((addr & 32'hFFFF_F000) == 32'h5000_0000) slave_of_addr = "UART    ";
        else if ((addr & 32'hFFFF_F000) == 32'h5001_0000) slave_of_addr = "GPIO-stb";
        else if ((addr & 32'hFFFF_F000) == 32'h5002_0000) slave_of_addr = "SPI-stb ";
        else if ((addr & 32'hFFFF_F000) == 32'h5003_0000) slave_of_addr = "TMR-stb ";
        else if ((addr & 32'hFFFF_F000) == 32'h5004_0000) slave_of_addr = "PLIC    ";
        else if ((addr & 32'hFFFF_F000) == 32'h6000_0000) slave_of_addr = "OTP-stb ";
        else if ((addr & 32'hFFFF_F000) == 32'h6001_0000) slave_of_addr = "DMA-Cfg ";
        else                                               slave_of_addr = "DECERR! ";
    end
endfunction

function [79:0] ascon_reg_name;
    input [11:0] offset;
    begin
        case (offset)
            12'h000: ascon_reg_name = "CTRL      ";
            12'h004: ascon_reg_name = "STATUS    ";
            12'h008: ascon_reg_name = "MODE      ";
            12'h00C: ascon_reg_name = "IRQ_EN    ";
            12'h010: ascon_reg_name = "KEY_0     ";
            12'h014: ascon_reg_name = "KEY_1     ";
            12'h018: ascon_reg_name = "KEY_2     ";
            12'h01C: ascon_reg_name = "KEY_3     ";
            12'h020: ascon_reg_name = "NONCE_0   ";
            12'h024: ascon_reg_name = "NONCE_1   ";
            12'h028: ascon_reg_name = "NONCE_2   ";
            12'h02C: ascon_reg_name = "NONCE_3   ";
            12'h030: ascon_reg_name = "PTEXT_0   ";
            12'h034: ascon_reg_name = "PTEXT_1   ";
            12'h040: ascon_reg_name = "CTEXT_0   ";
            12'h044: ascon_reg_name = "CTEXT_1   ";
            12'h048: ascon_reg_name = "TAG_0     ";
            12'h04C: ascon_reg_name = "TAG_1     ";
            12'h050: ascon_reg_name = "TAG_2     ";
            12'h054: ascon_reg_name = "TAG_3     ";
            12'h05C: ascon_reg_name = "DATA_LEN  ";
            12'h100: ascon_reg_name = "DMA_SRC   ";
            12'h104: ascon_reg_name = "DMA_DST   ";
            12'h108: ascon_reg_name = "DMA_LEN   ";
            default: ascon_reg_name = "UNKNOWN   ";
        endcase
    end
endfunction

function [63:0] uart_reg_name;
    input [7:0] offset;
    begin
        case (offset[7:2])
            6'h00: uart_reg_name = "TX_DATA ";
            6'h01: uart_reg_name = "RX_DATA ";
            6'h02: uart_reg_name = "STATUS  ";
            6'h03: uart_reg_name = "CTRL    ";
            6'h04: uart_reg_name = "BAUD_DIV";
            6'h05: uart_reg_name = "IRQ_STS ";
            default: uart_reg_name = "UNKNOWN ";
        endcase
    end
endfunction

// ---------------------------------------------------------------------------
// Watchdog timeout
// ---------------------------------------------------------------------------
initial begin
    #((POR_HOLD + SIM_CYCLES + 100) * CLK_PERIOD);
    $display("[%0t] [WATCHDOG] Hết thời gian simulation.", $time);
    print_summary();
    $finish;
end

// ---------------------------------------------------------------------------
// Task: print_summary
// ---------------------------------------------------------------------------
task print_summary;
    begin
        $display("");
        $display("+=============================================================+");
        $display("|           DATA PATH TRANSACTION SUMMARY  (5M×12S)          |");
        $display("+=============================================================+");
        $display("|  CPU DCache req total   : %0d  (wr=%0d rd=%0d)",
                 cnt_cpu_dc_req, cnt_cpu_dc_wr, cnt_cpu_dc_rd);
        $display("|  --- Masters ---");
        $display("|  M0 ICache  AR          : %0d", cnt_m0_ar);
        $display("|  M1 DCache  AW/W/AR     : %0d / %0d / %0d",
                 cnt_m1_aw, cnt_m1_w, cnt_m1_ar);
        $display("|  M2 ASCON-DMA(32b) AW/AR: %0d / %0d", cnt_m2_aw, cnt_m2_ar);
        $display("|  M3 DMA-Ctrl  AW/AR     : %0d / %0d", cnt_m3_aw, cnt_m3_ar);
        $display("|  DMA64 raw   AW/AR      : %0d / %0d  (trước width conv)",
                 cnt_dma_aw, cnt_dma_ar);
        $display("|  --- Slaves ---");
        $display("|  S0 IMEM    AR          : %0d", cnt_s0_ar);
        $display("|  S1 DMEM    AW/AR       : %0d / %0d", cnt_s1_aw, cnt_s1_ar);
        $display("|  S2 ASCON   AW/AR       : %0d / %0d", cnt_s2_aw, cnt_s2_ar);
        $display("|  S5 UART    AW/AR       : %0d / %0d", cnt_s5_aw, cnt_s5_ar);
        $display("|  S9 PLIC    AW          : %0d", cnt_s9_aw);
        $display("|  S11 DMA-Cfg AW         : %0d", cnt_s11_aw);
        $display("|  --- ASCON ---");
        $display("|  CORE start / done      : %0d / %0d", cnt_ascon_start, cnt_ascon_done);
        $display("|  CTEXT = %08h_%08h", ascon_reg_ctext0, ascon_reg_ctext1);
        $display("|  TAG   = %08h_%08h_%08h_%08h",
                 ascon_reg_tag0, ascon_reg_tag1, ascon_reg_tag2, ascon_reg_tag3);
        $display("|  --- Interrupts ---");
        $display("|  PLIC meip (ext_irq)    : %0d times", cnt_plic_meip);
        $display("|  UART irq               : %0d times", cnt_uart_irq);
        $display("|  --- Errors ---");
        $display("|  DECERR / non-OKAY resp : %0d", cnt_decerr);
        $display("+=============================================================+");

        // Consistency checks
        // [FIX-5] S1 AW = M1 + M2 + M3 (cả 3 master đều ghi được DMEM)
        if (cnt_s1_aw != (cnt_m1_aw + cnt_m2_aw + cnt_m3_aw))
            $display("|  [WARN] S1 AW (%0d) != M1+M2+M3 AW (%0d+%0d+%0d=%0d)",
                     cnt_s1_aw, cnt_m1_aw, cnt_m2_aw, cnt_m3_aw,
                     cnt_m1_aw + cnt_m2_aw + cnt_m3_aw);
        else
            $display("|  [OK]   S1 AW count khớp với M1+M2+M3");

        if (cnt_s2_aw == 0 && cnt_ascon_start == 0)
            $display("|  [WARN] ASCON không nhận write nào — firmware chưa cấu hình ASCON?");
        if (cnt_s5_aw == 0)
            $display("|  [WARN] UART không nhận write nào — firmware chưa gọi uart_putc?");

        $display("+-------------------------------------------------------------+");
        $display("|  Final CPU PC = 0x%08h", cpu_pc);
        $display("+=============================================================+");
        $display("");
    end
endtask

// ---------------------------------------------------------------------------
// Main — chạy sau khi reset xong
// ---------------------------------------------------------------------------
initial begin
    $display("=== tb_debug_data v2.0: start ===");
    $display("    SoC topology: 5M × 12S");
    $display("    Theo dõi: CPU→ICache→IMEM | CPU→DCache→DMEM/ASCON/UART");
    $display("              ASCON-DMA→WConv→M2→DMEM | DMA-Ctrl→M3→DMEM");
    $display("              Reset: fabric_rst_n / cpu_rst_n / periph_rst_n");
    $display("              IRQ: UART/ASCON/DMA → PLIC → CPU meip");

    @(posedge fabric_rst_n_w);         // chờ clk_reset_ctrl release reset
    repeat(3) @(posedge clk);
    $display("[%0t] fabric_rst_n released — CPU đang chạy...", $time);

    repeat(SIM_CYCLES) @(posedge clk);

    $display("[%0t] === Simulation ended normally ===", $time);
    print_summary();
    $finish;
end

endmodule

// =============================================================================
// HƯỚNG DẪN SỬ DỤNG VỚI SOC_TOP 3M×5S CŨ (trong document):
//
// soc_top 3M×5S (file được upload) CHỈ có:
//   port : clk, ext_rst_n, soft_rst_pulse (output)
//   wires: fabric_rst_n = ext_rst_n (không có clk_reset_ctrl)
//   masters: M0, M1, M2 (không có M3, M4)
//   slaves : S0–S4 (không có S5–S11)
//
// Để dùng TB này với soc_top 3M×5S:
//   1. Thay DUT instantiation: bỏ por_n, JTAG, UART port
//      soc_top dut (.clk(clk), .ext_rst_n(ext_rst_n_r), .soft_rst_pulse());
//   2. Thay reset sequence: bỏ por_n logic, dùng ext_rst_n_r trực tiếp
//   3. Comment các tap M3, S5–S11, uart_irq, dma_irq, periph_rst_n
//   4. Thay wire fabric_rst_n_w = dut.fabric_rst_n bằng:
//      wire fabric_rst_n_w = ext_rst_n_r;
// =============================================================================