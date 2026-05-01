`timescale 1ns/1ps

`timescale 1ns/1ps
`include "soc_hs.v"

// ============================================================================
//  run_soc_ascon.v  —  Universal Debug Testbench  v6.0
//
//  Cập nhật từ v5.2 cho soc_top.v 5M×12S với UART, JTAG, PLIC, DMA mới:
//
//  [NEW-1] DUT port: thêm por_n, uart_tx/rx, tck/tms/tdi/tdo/tdo_en.
//          soc_top cũ chỉ có clk+ext_rst_n+soft_rst_pulse.
//          soft_rst_pulse giờ là internal wire (không còn là output port).
//
//  [NEW-2] UART Monitor: bắt uart_tx serial stream (8N1) → giải mã byte →
//          in ra console dạng [UART-TX] char='X' (0xNN).
//          BAUD_DIV mặc định 868 → 1 bit = 868 cy × 10 ns = 8680 ns.
//          Monitor tự tính bit period từ tham số CLK_PERIOD và BAUD_DIV.
//
//  [NEW-3] JTAG taps: monitor ndmreset, haltreq, resumereq, halted, running
//          từ chip.u_soc_top.u_jtag và chip.u_soc_top.jtag_ndmreset để log sự kiện debug session.
//
//  [NEW-4] PLIC taps: irq_src vector, meip output, per-source pending.
//          Log khi meip thay đổi để theo dõi interrupt flow.
//
//  [NEW-5] M3 (DMA Ctrl) + M4 (JTAG DM) AXI logger: giống M1/M2 cũ.
//
//  [NEW-6] S5 (UART) + S9 (PLIC) per-slave traffic counter.
//          S6/S7/S8/S10 là stub nên chỉ log SLVERR nếu có access.
//
//  [NEW-7] Reset sequence: soc_top cần por_n giữ LOW ≥ POR_CYCLES (1000cy)
//          sau đó ext_rst_n release. Sequence mới: por_n=0 → 20cy →
//          ext_rst_n release → 12cy → por_n release → 5cy → start.
//
//  [NEW-8] IRQ summary trong print_report: thêm PLIC meip count,
//          uart_irq count, dma_irq count. Sửa comment "soc_ctrl IRQ_MASK"
//          thành "PLIC meip" vì external_irq giờ đến từ PLIC.
//
//  [FIX-5..9] Giữ nguyên từ v5.2.
// ============================================================================
// ── Tuning knobs ──────────────────────────────────────────────────────────────
`define LOG_LEVEL       2       // 1=key events, 2=AXI detail, 3=every beat
`define TIMEOUT         200000 // boot overhead ~3100cy (POR+fabric_rst+boot_ctrl 2048w) + CPU
`define HALT_STABLE     60
`define DMEM_DUMP_BASE  32'h10000000
`define DMEM_DUMP_WORDS 32
`define DMEM_ROW_WORDS  4
`define MATCH2_THRESH   20000
`define MATCH4_THRESH   20000
`define BAUD_DIV        868     // 115200 baud @ 100 MHz → 1 bit = 868 cy
// ─────────────────────────────────────────────────────────────────────────────

module run_soc;

// ============================================================================
// Clock & Reset
// ============================================================================
parameter CLK_PERIOD = 10;   // 100 MHz

reg clk;
reg por_n_r;       // [NEW-1] Power-On Reset — phải giữ LOW ≥ 1000 cy
reg ext_rst_n_r;   // External reset button

initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT — soc_top
//
// [NEW-1] soc_top v6 có port mới:
//   - por_n         : Power-On Reset (active-low)
//   - uart_tx/rx    : UART IO pads
//   - tck/tms/tdi/tdo/tdo_en : JTAG IO pads
//   soft_rst_pulse không còn là output port (internal wire trong soc_top)
// ============================================================================
// JTAG pins — driven bởi testbench (idle = JTAG bypass mode)
reg  jtag_tck_r;
reg  jtag_tms_r;
reg  jtag_tdi_r;
wire jtag_tdo_w;
wire jtag_tdo_en_w;

// UART loopback: uart_tx → uart_rx để test TX path
// (firmware chỉ TX, TB monitor bắt trên uart_tx_w)
wire uart_tx_w;
wire uart_rx_w;
assign uart_rx_w = 1'b1;  // idle high — loopback gây echo làm nhiễu UART monitor

// GPIO — inout pad
wire [31:0] gpio_w;
reg  [31:0] gpio_in_r;
assign gpio_w = gpio_in_r;
wire [31:0] gpio_out_w = chip.core_gpio_out;
wire [31:0] gpio_oe_w  = chip.core_gpio_oe;

// WDT reset request — TB intercepts, NOT applied to DUT
wire wdt_rst_req_w;

assign jtag_tdo_en_w = chip.core_tdo_en; // To preserve the tap

soc_hs #(.SIM_MODE(1)) chip (
    .clk_in      (clk),
    .por_n       (por_n_r),
    .ext_rst_n   (ext_rst_n_r),
    // UART
    .uart_tx     (uart_tx_w),
    .uart_rx     (uart_rx_w),
    // JTAG
    .tck         (jtag_tck_r),
    .tms         (jtag_tms_r),
    .tdi         (jtag_tdi_r),
    .tdo         (jtag_tdo_w),
    // SPI (Stub)
    .spi_sck     (),
    .spi_mosi    (),
    .spi_miso    (1'b1),
    .spi_cs_n    (),
    // GPIO
    .gpio        (gpio_w),
    // WDT reset request
    .wdt_rst_req (wdt_rst_req_w)
);

// ============================================================================
// SIGNAL TAPS — lấy trực tiếp từ soc_top internal wires/instances
// ============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// [A] CPU Pipeline  (instance: chip.u_soc_top.u_cpu)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] pc_if     = chip.u_soc_top.u_cpu.pc_if;
wire [31:0] instr_if  = chip.u_soc_top.u_cpu.instr_if;
wire        stall_if  = chip.u_soc_top.u_cpu.stall_if;

// ─────────────────────────────────────────────────────────────────────────────
// [B] CPU ↔ ICache
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ic_cpu_addr  = chip.u_soc_top.cpu_imem_addr;
wire        ic_cpu_req   = chip.u_soc_top.cpu_imem_valid;
wire [31:0] ic_cpu_rdata = chip.u_soc_top.icache_imem_rdata;
wire        ic_cpu_ready = chip.u_soc_top.icache_imem_ready;

// ─────────────────────────────────────────────────────────────────────────────
// [C] CPU ↔ DCache
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] dc_addr  = chip.u_soc_top.cpu_dcache_addr;
wire [31:0] dc_wdata = chip.u_soc_top.cpu_dcache_wdata;
wire [3:0]  dc_wstrb = chip.u_soc_top.cpu_dcache_wstrb;
wire        dc_req   = chip.u_soc_top.cpu_dcache_req;
wire        dc_we    = chip.u_soc_top.cpu_dcache_we;
wire [31:0] dc_rdata = chip.u_soc_top.dcache_cpu_rdata;
wire        dc_ready = chip.u_soc_top.dcache_cpu_ready;

// ─────────────────────────────────────────────────────────────────────────────
// [D] M0 (ICache) → Crossbar
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m0_arid    = chip.u_soc_top.m0_arid;
wire [31:0] m0_araddr  = chip.u_soc_top.m0_araddr;
wire [7:0]  m0_arlen   = chip.u_soc_top.m0_arlen;
wire [2:0]  m0_arsize  = chip.u_soc_top.m0_arsize;
wire [1:0]  m0_arburst = chip.u_soc_top.m0_arburst;
wire        m0_arvalid = chip.u_soc_top.m0_arvalid;
wire        m0_arready = chip.u_soc_top.m0_arready;
wire [3:0]  m0_rid     = chip.u_soc_top.m0_rid;
wire [31:0] m0_rdata   = chip.u_soc_top.m0_rdata;
wire [1:0]  m0_rresp   = chip.u_soc_top.m0_rresp;
wire        m0_rlast   = chip.u_soc_top.m0_rlast;
wire        m0_rvalid  = chip.u_soc_top.m0_rvalid;
wire        m0_rready  = chip.u_soc_top.m0_rready;
wire        m0_awvalid = chip.u_soc_top.m0_awvalid;
wire [31:0] m0_awaddr  = chip.u_soc_top.m0_awaddr;
wire [1:0]  m0_bresp   = chip.u_soc_top.m0_bresp;
wire        m0_bvalid  = chip.u_soc_top.m0_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [E] M1 (DCache) → Crossbar
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m1_arid    = chip.u_soc_top.m1_arid;
wire [31:0] m1_araddr  = chip.u_soc_top.m1_araddr;
wire [7:0]  m1_arlen   = chip.u_soc_top.m1_arlen;
wire [2:0]  m1_arsize  = chip.u_soc_top.m1_arsize;
wire [1:0]  m1_arburst = chip.u_soc_top.m1_arburst;
wire        m1_arvalid = chip.u_soc_top.m1_arvalid;
wire        m1_arready = chip.u_soc_top.m1_arready;
wire [3:0]  m1_rid     = chip.u_soc_top.m1_rid;
wire [31:0] m1_rdata   = chip.u_soc_top.m1_rdata;
wire [1:0]  m1_rresp   = chip.u_soc_top.m1_rresp;
wire        m1_rlast   = chip.u_soc_top.m1_rlast;
wire        m1_rvalid  = chip.u_soc_top.m1_rvalid;
wire        m1_rready  = chip.u_soc_top.m1_rready;
wire [3:0]  m1_awid    = chip.u_soc_top.m1_awid;
wire [31:0] m1_awaddr  = chip.u_soc_top.m1_awaddr;
wire [7:0]  m1_awlen   = chip.u_soc_top.m1_awlen;
wire [2:0]  m1_awsize  = chip.u_soc_top.m1_awsize;
wire [1:0]  m1_awburst = chip.u_soc_top.m1_awburst;
wire        m1_awvalid = chip.u_soc_top.m1_awvalid;
wire        m1_awready = chip.u_soc_top.m1_awready;
wire [31:0] m1_wdata   = chip.u_soc_top.m1_wdata;
wire [3:0]  m1_wstrb   = chip.u_soc_top.m1_wstrb;
wire        m1_wlast   = chip.u_soc_top.m1_wlast;
wire        m1_wvalid  = chip.u_soc_top.m1_wvalid;
wire        m1_wready  = chip.u_soc_top.m1_wready;
wire [3:0]  m1_bid     = chip.u_soc_top.m1_bid;
wire [1:0]  m1_bresp   = chip.u_soc_top.m1_bresp;
wire        m1_bvalid  = chip.u_soc_top.m1_bvalid;
wire        m1_bready  = chip.u_soc_top.m1_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [F] M2 (ASCON DMA 32-bit, sau width converter) → Crossbar
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m2_arid    = chip.u_soc_top.m2_arid;
wire [31:0] m2_araddr  = chip.u_soc_top.m2_araddr;
wire [7:0]  m2_arlen   = chip.u_soc_top.m2_arlen;
wire [2:0]  m2_arsize  = chip.u_soc_top.m2_arsize;
wire [1:0]  m2_arburst = chip.u_soc_top.m2_arburst;
wire        m2_arvalid = chip.u_soc_top.m2_arvalid;
wire        m2_arready = chip.u_soc_top.m2_arready;
wire [3:0]  m2_rid     = chip.u_soc_top.m2_rid;
wire [31:0] m2_rdata   = chip.u_soc_top.m2_rdata;
wire [1:0]  m2_rresp   = chip.u_soc_top.m2_rresp;
wire        m2_rlast   = chip.u_soc_top.m2_rlast;
wire        m2_rvalid  = chip.u_soc_top.m2_rvalid;
wire        m2_rready  = chip.u_soc_top.m2_rready;
wire [3:0]  m2_awid    = chip.u_soc_top.m2_awid;
wire [31:0] m2_awaddr  = chip.u_soc_top.m2_awaddr;
wire [7:0]  m2_awlen   = chip.u_soc_top.m2_awlen;
wire [2:0]  m2_awsize  = chip.u_soc_top.m2_awsize;
wire [1:0]  m2_awburst = chip.u_soc_top.m2_awburst;
wire        m2_awvalid = chip.u_soc_top.m2_awvalid;
wire        m2_awready = chip.u_soc_top.m2_awready;
wire [31:0] m2_wdata   = chip.u_soc_top.m2_wdata;
wire [3:0]  m2_wstrb   = chip.u_soc_top.m2_wstrb;
wire        m2_wlast   = chip.u_soc_top.m2_wlast;
wire        m2_wvalid  = chip.u_soc_top.m2_wvalid;
wire        m2_wready  = chip.u_soc_top.m2_wready;
wire [3:0]  m2_bid     = chip.u_soc_top.m2_bid;
wire [1:0]  m2_bresp   = chip.u_soc_top.m2_bresp;
wire        m2_bvalid  = chip.u_soc_top.m2_bvalid;
wire        m2_bready  = chip.u_soc_top.m2_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [F2] M3 (DMA Controller) → Crossbar  [NEW-5]
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m3_arid    = chip.u_soc_top.m3_arid;
wire [31:0] m3_araddr  = chip.u_soc_top.m3_araddr;
wire [7:0]  m3_arlen   = chip.u_soc_top.m3_arlen;
wire        m3_arvalid = chip.u_soc_top.m3_arvalid;
wire        m3_arready = chip.u_soc_top.m3_arready;
wire [31:0] m3_rdata   = chip.u_soc_top.m3_rdata;
wire [1:0]  m3_rresp   = chip.u_soc_top.m3_rresp;
wire        m3_rlast   = chip.u_soc_top.m3_rlast;
wire        m3_rvalid  = chip.u_soc_top.m3_rvalid;
wire        m3_rready  = chip.u_soc_top.m3_rready;
wire [3:0]  m3_awid    = chip.u_soc_top.m3_awid;
wire [31:0] m3_awaddr  = chip.u_soc_top.m3_awaddr;
wire [7:0]  m3_awlen   = chip.u_soc_top.m3_awlen;
wire        m3_awvalid = chip.u_soc_top.m3_awvalid;
wire        m3_awready = chip.u_soc_top.m3_awready;
wire [31:0] m3_wdata   = chip.u_soc_top.m3_wdata;
wire [3:0]  m3_wstrb   = chip.u_soc_top.m3_wstrb;
wire        m3_wlast   = chip.u_soc_top.m3_wlast;
wire        m3_wvalid  = chip.u_soc_top.m3_wvalid;
wire        m3_wready  = chip.u_soc_top.m3_wready;
wire [3:0]  m3_bid     = chip.u_soc_top.m3_bid;
wire [1:0]  m3_bresp   = chip.u_soc_top.m3_bresp;
wire        m3_bvalid  = chip.u_soc_top.m3_bvalid;
wire        m3_bready  = chip.u_soc_top.m3_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [F3] M4 (JTAG Debug Module SBA) → Crossbar  [NEW-5]
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m4_arid    = chip.u_soc_top.m4_arid;
wire [31:0] m4_araddr  = chip.u_soc_top.m4_araddr;
wire [7:0]  m4_arlen   = chip.u_soc_top.m4_arlen;
wire        m4_arvalid = chip.u_soc_top.m4_arvalid;
wire        m4_arready = chip.u_soc_top.m4_arready;
wire [31:0] m4_rdata   = chip.u_soc_top.m4_rdata;
wire [1:0]  m4_rresp   = chip.u_soc_top.m4_rresp;
wire        m4_rlast   = chip.u_soc_top.m4_rlast;
wire        m4_rvalid  = chip.u_soc_top.m4_rvalid;
wire        m4_rready  = chip.u_soc_top.m4_rready;
wire [3:0]  m4_awid    = chip.u_soc_top.m4_awid;
wire [31:0] m4_awaddr  = chip.u_soc_top.m4_awaddr;
wire        m4_awvalid = chip.u_soc_top.m4_awvalid;
wire        m4_awready = chip.u_soc_top.m4_awready;
wire [31:0] m4_wdata   = chip.u_soc_top.m4_wdata;
wire        m4_wlast   = chip.u_soc_top.m4_wlast;
wire        m4_wvalid  = chip.u_soc_top.m4_wvalid;
wire        m4_wready  = chip.u_soc_top.m4_wready;
wire [1:0]  m4_bresp   = chip.u_soc_top.m4_bresp;
wire        m4_bvalid  = chip.u_soc_top.m4_bvalid;
wire        m4_bready  = chip.u_soc_top.m4_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [G] DMA raw 64-bit wires (ASCON M_AXI trước width converter)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  dma_awid    = chip.u_soc_top.dma_awid;
wire [31:0] dma_awaddr  = chip.u_soc_top.dma_awaddr;
wire [7:0]  dma_awlen   = chip.u_soc_top.dma_awlen;
wire        dma_awvalid = chip.u_soc_top.dma_awvalid;
wire        dma_awready = chip.u_soc_top.dma_awready;
wire [63:0] dma_wdata   = chip.u_soc_top.dma_wdata;
wire [7:0]  dma_wstrb   = chip.u_soc_top.dma_wstrb;
wire        dma_wlast   = chip.u_soc_top.dma_wlast;
wire        dma_wvalid  = chip.u_soc_top.dma_wvalid;
wire        dma_wready  = chip.u_soc_top.dma_wready;
wire [1:0]  dma_bresp   = chip.u_soc_top.dma_bresp;
wire        dma_bvalid  = chip.u_soc_top.dma_bvalid;
wire [3:0]  dma_arid    = chip.u_soc_top.dma_arid;
wire [31:0] dma_araddr  = chip.u_soc_top.dma_araddr;
wire [7:0]  dma_arlen   = chip.u_soc_top.dma_arlen;
wire        dma_arvalid = chip.u_soc_top.dma_arvalid;
wire        dma_arready = chip.u_soc_top.dma_arready;
wire [63:0] dma_rdata   = chip.u_soc_top.dma_rdata;
wire [1:0]  dma_rresp   = chip.u_soc_top.dma_rresp;
wire        dma_rlast   = chip.u_soc_top.dma_rlast;
wire        dma_rvalid  = chip.u_soc_top.dma_rvalid;
wire        dma_rready  = chip.u_soc_top.dma_rready;

// ─────────────────────────────────────────────────────────────────────────────
// [H] Crossbar → S0 (IMEM)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s0_arid    = chip.u_soc_top.s0_arid;
wire [31:0] s0_araddr  = chip.u_soc_top.s0_araddr;
wire [7:0]  s0_arlen   = chip.u_soc_top.s0_arlen;
wire        s0_arvalid = chip.u_soc_top.s0_arvalid;
wire        s0_arready = chip.u_soc_top.s0_arready;
wire [3:0]  s0_rid     = chip.u_soc_top.s0_rid;
wire [31:0] s0_rdata   = chip.u_soc_top.s0_rdata;
wire [1:0]  s0_rresp   = chip.u_soc_top.s0_rresp;
wire        s0_rlast   = chip.u_soc_top.s0_rlast;
wire        s0_rvalid  = chip.u_soc_top.s0_rvalid;
wire        s0_rready  = chip.u_soc_top.s0_rready;

// ─────────────────────────────────────────────────────────────────────────────
// [I] Crossbar → S1 (DMEM)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s1_arid    = chip.u_soc_top.s1_arid;
wire [31:0] s1_araddr  = chip.u_soc_top.s1_araddr;
wire [7:0]  s1_arlen   = chip.u_soc_top.s1_arlen;
wire        s1_arvalid = chip.u_soc_top.s1_arvalid;
wire        s1_arready = chip.u_soc_top.s1_arready;
wire [3:0]  s1_rid     = chip.u_soc_top.s1_rid;
wire [31:0] s1_rdata   = chip.u_soc_top.s1_rdata;
wire [1:0]  s1_rresp   = chip.u_soc_top.s1_rresp;
wire        s1_rlast   = chip.u_soc_top.s1_rlast;
wire        s1_rvalid  = chip.u_soc_top.s1_rvalid;
wire        s1_rready  = chip.u_soc_top.s1_rready;
wire [3:0]  s1_awid    = chip.u_soc_top.s1_awid;
wire [31:0] s1_awaddr  = chip.u_soc_top.s1_awaddr;
wire        s1_awvalid = chip.u_soc_top.s1_awvalid;
wire        s1_awready = chip.u_soc_top.s1_awready;
wire [31:0] s1_wdata   = chip.u_soc_top.s1_wdata;
wire [3:0]  s1_wstrb   = chip.u_soc_top.s1_wstrb;
wire        s1_wlast   = chip.u_soc_top.s1_wlast;
wire        s1_wvalid  = chip.u_soc_top.s1_wvalid;
wire        s1_wready  = chip.u_soc_top.s1_wready;
wire [1:0]  s1_bresp   = chip.u_soc_top.s1_bresp;
wire        s1_bvalid  = chip.u_soc_top.s1_bvalid;
wire        s1_bready  = chip.u_soc_top.s1_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [J] Crossbar → S2 (ASCON slave)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s2_araddr  = chip.u_soc_top.s2_araddr;
wire        s2_arvalid = chip.u_soc_top.s2_arvalid;
wire        s2_arready = chip.u_soc_top.s2_arready;
wire [31:0] s2_rdata   = chip.u_soc_top.s2_rdata;
wire [1:0]  s2_rresp   = chip.u_soc_top.s2_rresp;
wire        s2_rvalid  = chip.u_soc_top.s2_rvalid;
wire [31:0] s2_awaddr  = chip.u_soc_top.s2_awaddr;
wire        s2_awvalid = chip.u_soc_top.s2_awvalid;
wire        s2_awready = chip.u_soc_top.s2_awready;
wire [31:0] s2_wdata   = chip.u_soc_top.s2_wdata;
wire        s2_wvalid  = chip.u_soc_top.s2_wvalid;
wire [1:0]  s2_bresp   = chip.u_soc_top.s2_bresp;
wire        s2_bvalid  = chip.u_soc_top.s2_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [K] Crossbar → S3 (SoC Ctrl)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s3_araddr  = chip.u_soc_top.s3_araddr;
wire        s3_arvalid = chip.u_soc_top.s3_arvalid;
wire        s3_arready = chip.u_soc_top.s3_arready;
wire [31:0] s3_awaddr  = chip.u_soc_top.s3_awaddr;
wire        s3_awvalid = chip.u_soc_top.s3_awvalid;
wire        s3_awready = chip.u_soc_top.s3_awready;
wire [31:0] s3_wdata   = chip.u_soc_top.s3_wdata;
wire        s3_wvalid  = chip.u_soc_top.s3_wvalid;
wire [31:0] s3_rdata   = chip.u_soc_top.s3_rdata;
wire        s3_rvalid  = chip.u_soc_top.s3_rvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L] Crossbar → S4 (CLINT)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s4_araddr  = chip.u_soc_top.s4_araddr;
wire        s4_arvalid = chip.u_soc_top.s4_arvalid;
wire        s4_arready = chip.u_soc_top.s4_arready;
wire [31:0] s4_awaddr  = chip.u_soc_top.s4_awaddr;
wire        s4_awvalid = chip.u_soc_top.s4_awvalid;
wire        s4_awready = chip.u_soc_top.s4_awready;
wire [31:0] s4_wdata   = chip.u_soc_top.s4_wdata;
wire        s4_wvalid  = chip.u_soc_top.s4_wvalid;
wire [31:0] s4_rdata   = chip.u_soc_top.s4_rdata;
wire        s4_rvalid  = chip.u_soc_top.s4_rvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L2] Crossbar → S5 (UART)  [NEW-6]
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s5_araddr  = chip.u_soc_top.s5_araddr;
wire        s5_arvalid = chip.u_soc_top.s5_arvalid;
wire        s5_arready = chip.u_soc_top.s5_arready;
wire [31:0] s5_awaddr  = chip.u_soc_top.s5_awaddr;
wire        s5_awvalid = chip.u_soc_top.s5_awvalid;
wire        s5_awready = chip.u_soc_top.s5_awready;
wire [31:0] s5_wdata   = chip.u_soc_top.s5_wdata;
wire        s5_wvalid  = chip.u_soc_top.s5_wvalid;
wire        s5_wready  = chip.u_soc_top.s5_wready;
wire [31:0] s5_rdata   = chip.u_soc_top.s5_rdata;
wire        s5_rvalid  = chip.u_soc_top.s5_rvalid;
wire [1:0]  s5_bresp   = chip.u_soc_top.s5_bresp;
wire        s5_bvalid  = chip.u_soc_top.s5_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L3] Crossbar → S9 (PLIC)  [NEW-6]
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s9_araddr  = chip.u_soc_top.s9_araddr;
wire        s9_arvalid = chip.u_soc_top.s9_arvalid;
wire        s9_arready = chip.u_soc_top.s9_arready;
wire [31:0] s9_awaddr  = chip.u_soc_top.s9_awaddr;
wire        s9_awvalid = chip.u_soc_top.s9_awvalid;
wire        s9_awready = chip.u_soc_top.s9_awready;
wire [31:0] s9_wdata   = chip.u_soc_top.s9_wdata;
wire        s9_wvalid  = chip.u_soc_top.s9_wvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L4] Crossbar → S6 (GPIO)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s6_araddr  = chip.u_soc_top.s6_araddr;
wire        s6_arvalid = chip.u_soc_top.s6_arvalid;
wire        s6_arready = chip.u_soc_top.s6_arready;
wire [31:0] s6_awaddr  = chip.u_soc_top.s6_awaddr;
wire        s6_awvalid = chip.u_soc_top.s6_awvalid;
wire        s6_awready = chip.u_soc_top.s6_awready;
wire [31:0] s6_wdata   = chip.u_soc_top.s6_wdata;
wire        s6_wvalid  = chip.u_soc_top.s6_wvalid;
wire        s6_wready  = chip.u_soc_top.s6_wready;
wire [1:0]  s6_bresp   = chip.u_soc_top.s6_bresp;
wire        s6_bvalid  = chip.u_soc_top.s6_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L5] Crossbar → S8 (Timer/WDT)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s8_araddr  = chip.u_soc_top.s8_araddr;
wire        s8_arvalid = chip.u_soc_top.s8_arvalid;
wire        s8_arready = chip.u_soc_top.s8_arready;
wire [31:0] s8_awaddr  = chip.u_soc_top.s8_awaddr;
wire        s8_awvalid = chip.u_soc_top.s8_awvalid;
wire        s8_awready = chip.u_soc_top.s8_awready;
wire [31:0] s8_wdata   = chip.u_soc_top.s8_wdata;
wire        s8_wvalid  = chip.u_soc_top.s8_wvalid;
wire        s8_wready  = chip.u_soc_top.s8_wready;
wire [1:0]  s8_bresp   = chip.u_soc_top.s8_bresp;
wire        s8_bvalid  = chip.u_soc_top.s8_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [L6] Crossbar → S11 (DMA Ctrl Config @ 0x6001_0000)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s11_araddr  = chip.u_soc_top.s11_araddr;
wire        s11_arvalid = chip.u_soc_top.s11_arvalid;
wire        s11_arready = chip.u_soc_top.s11_arready;
wire [31:0] s11_awaddr  = chip.u_soc_top.s11_awaddr;
wire        s11_awvalid = chip.u_soc_top.s11_awvalid;
wire        s11_awready = chip.u_soc_top.s11_awready;
wire [31:0] s11_wdata   = chip.u_soc_top.s11_wdata;
wire        s11_wvalid  = chip.u_soc_top.s11_wvalid;
wire        s11_wready  = chip.u_soc_top.s11_wready;
wire [1:0]  s11_bresp   = chip.u_soc_top.s11_bresp;
wire        s11_bvalid  = chip.u_soc_top.s11_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [M] CLINT & Interrupt wires
// ─────────────────────────────────────────────────────────────────────────────
wire        mtime_tick   = chip.u_soc_top.mtime_tick;
wire        timer_irq    = chip.u_soc_top.timer_irq;
wire        sw_irq       = chip.u_soc_top.sw_irq;
wire        ext_irq      = chip.u_soc_top.external_irq;   // PLIC meip → CPU [NEW-8]
wire        uart_irq_w   = chip.u_soc_top.uart_irq;       // [NEW-8]
wire        dma_irq_w    = chip.u_soc_top.dma_irq;        // [NEW-8]
wire        ascon_irq_w  = chip.u_soc_top.ascon_irq;
wire        clint_timer_out = chip.u_soc_top.u_clint.timer_irq;
wire        clint_sw_out    = chip.u_soc_top.u_clint.sw_irq;

// soft_rst_pulse: không còn là output port — đọc từ internal wire
wire        soft_rst_pulse = chip.u_soc_top.soft_rst_pulse;

// ─────────────────────────────────────────────────────────────────────────────
// [N] SoC Ctrl internal
// ─────────────────────────────────────────────────────────────────────────────
wire        soc_ctrl_irq_out   = chip.u_soc_top.soc_ctrl_irq_out;  // deprecated, không dùng
wire        soc_ctrl_soft_rst  = chip.u_soc_top.u_soc_ctrl.soft_rst_pulse;
wire [31:0] icache_stat_hits   = chip.u_soc_top.icache_stat_hits;
wire [31:0] icache_stat_misses = chip.u_soc_top.icache_stat_misses;
wire [31:0] dcache_stat_hits   = chip.u_soc_top.dcache_stat_hits;
wire [31:0] dcache_stat_misses = chip.u_soc_top.dcache_stat_misses;
wire [31:0] dcache_stat_writes = chip.u_soc_top.dcache_stat_writes;

// ─────────────────────────────────────────────────────────────────────────────
// [O] ASCON IP internal
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ascon_status_word  = chip.u_soc_top.u_ascon.u_slave.status_word;
wire        ascon_core_busy    = chip.u_soc_top.u_ascon.u_slave.core_busy;
wire        ascon_core_done    = chip.u_soc_top.u_ascon.u_slave.core_done;
wire        ascon_dma_busy     = chip.u_soc_top.u_ascon.u_slave.dma_busy;
wire        ascon_dma_done_st  = chip.u_soc_top.u_ascon.u_slave.status_dma_done;
wire        ascon_dma_error    = chip.u_soc_top.u_ascon.u_slave.status_dma_error;
wire        ascon_core_start   = chip.u_soc_top.u_ascon.u_slave.core_start;
wire        ascon_dma_start    = chip.u_soc_top.u_ascon.u_slave.dma_start;
wire        ascon_soft_rst     = chip.u_soc_top.u_ascon.u_slave.core_soft_rst;
wire [31:0] ascon_dma_src_r    = chip.u_soc_top.u_ascon.u_slave.reg_dma_src;
wire [31:0] ascon_dma_dst_r    = chip.u_soc_top.u_ascon.u_slave.reg_dma_dst;
wire [31:0] ascon_dma_len_r    = chip.u_soc_top.u_ascon.u_slave.reg_dma_len;
wire        ascon_reg_dma_en   = chip.u_soc_top.u_ascon.u_slave.reg_dma_en;
wire        ascon_irq_wire     = chip.u_soc_top.ascon_irq;

wire [127:0] ascon_key_in     = chip.u_soc_top.u_ascon.u_slave.core_key;
wire [127:0] ascon_nonce_in   = chip.u_soc_top.u_ascon.u_slave.core_nonce;
wire [127:0] ascon_data_in    = chip.u_soc_top.u_ascon.core_data_in_mux;
wire [6:0]   ascon_data_len   = chip.u_soc_top.u_ascon.u_slave.core_data_len;
wire [1:0]   ascon_mode_w     = chip.u_soc_top.u_ascon.u_slave.core_mode;
wire         ascon_enc_dec_w  = chip.u_soc_top.u_ascon.u_slave.core_enc_dec;
wire         ascon_dma_en_w   = chip.u_soc_top.u_ascon.u_slave.reg_dma_en;
wire [31:0]  ascon_ptext_0    = chip.u_soc_top.u_ascon.dma_core_ptext_0;
wire [31:0]  ascon_ptext_1    = chip.u_soc_top.u_ascon.dma_core_ptext_1;
wire         ascon_dma_data_v = chip.u_soc_top.u_ascon.dma_core_data_valid;
wire [127:0] ascon_ctext_out  = chip.u_soc_top.u_ascon.core_data_out_w;
wire         ascon_ctext_v    = chip.u_soc_top.u_ascon.core_data_out_valid_w;
wire [127:0] ascon_tag_out    = chip.u_soc_top.u_ascon.core_tag_out_w;
wire         ascon_tag_v      = chip.u_soc_top.u_ascon.core_tag_valid_w;
wire [31:0]  ascon_reg_ctext0 = chip.u_soc_top.u_ascon.u_slave.reg_ctext_0;
wire [31:0]  ascon_reg_ctext1 = chip.u_soc_top.u_ascon.u_slave.reg_ctext_1;
wire [31:0]  ascon_reg_tag0   = chip.u_soc_top.u_ascon.u_slave.reg_tag_0;
wire [31:0]  ascon_reg_tag1   = chip.u_soc_top.u_ascon.u_slave.reg_tag_1;
wire [31:0]  ascon_reg_tag2   = chip.u_soc_top.u_ascon.u_slave.reg_tag_2;
wire [31:0]  ascon_reg_tag3   = chip.u_soc_top.u_ascon.u_slave.reg_tag_3;

// ─────────────────────────────────────────────────────────────────────────────
// [P] LSU Store Buffer  (instance: chip.u_soc_top.u_cpu)
// ─────────────────────────────────────────────────────────────────────────────
wire        lsu_sb_empty   = chip.u_soc_top.u_cpu.lsu_unit.sb_empty;
wire [2:0]  lsu_sb_count   = chip.u_soc_top.u_cpu.lsu_unit.sb_count[2:0];
wire        lsu_drain_idle = (chip.u_soc_top.u_cpu.lsu_unit.drain_state == 0);

// ─────────────────────────────────────────────────────────────────────────────
// [R] JTAG Debug taps  [NEW-3]
//
// WHY tap ở đây thay vì chỉ xem IO pad tck/tms/tdi:
//   jtag_ndmreset và halt/resume signal là internal — không có trên pad.
//   Tap vào chip.u_soc_top.jtag_ndmreset và chip.u_soc_top.u_jtag để monitor debug session.
// ─────────────────────────────────────────────────────────────────────────────
wire        jtag_ndmreset_w  = chip.u_soc_top.jtag_ndmreset;
wire        jtag_haltreq_w   = chip.u_soc_top.jtag_haltreq;
wire        jtag_resumereq_w = chip.u_soc_top.jtag_resumereq;
wire        jtag_halted_w    = chip.u_soc_top.jtag_halted;
wire        jtag_running_w   = chip.u_soc_top.jtag_running;
// CPU debug mode state (từ riscv_cpu_core FSM)
wire        cpu_debug_mode   = chip.u_soc_top.u_cpu.debug_mode;

// ─────────────────────────────────────────────────────────────────────────────
// [S] PLIC taps  [NEW-4]
// ─────────────────────────────────────────────────────────────────────────────
// IRQ source vector theo PLIC spec:
//   bit[0]=reserved, bit[1]=uart_irq, bit[2..3]=unused, bit[4]=gpio_irq,
//   bit[5..7]=timer/wdt, bit[8]=ascon_irq, bit[9]=dma_irq
wire [31:0] plic_irq_src     = {22'd0, chip.u_soc_top.dma_irq, chip.u_soc_top.ascon_irq,
                                 3'd0, chip.u_soc_top.gpio_irq, chip.u_soc_top.uart_irq, 1'b0};
wire        plic_meip        = chip.u_soc_top.external_irq;   // PLIC output → CPU
wire        gpio_irq_w       = chip.u_soc_top.gpio_irq;       // GPIO IRQ → PLIC src[4]

// ─────────────────────────────────────────────────────────────────────────────
// [T] UART internal taps  [NEW-2]
//   uart_tx_w: serial bit stream ra pad (đọc trực tiếp từ DUT output)
//   uart_top baud gen: 1 bit = BAUD_DIV × CLK_PERIOD ns
// ─────────────────────────────────────────────────────────────────────────────
// uart_tx_w đã khai báo ở trên (output DUT)

// ─────────────────────────────────────────────────────────────────────────────
// [U] Reset domain taps (từ clk_reset_ctrl)  [NEW-7]
// ─────────────────────────────────────────────────────────────────────────────
wire        fabric_rst_n_w   = chip.u_soc_top.fabric_rst_n;
wire        cpu_rst_n_w      = chip.u_soc_top.cpu_rst_n;
wire        periph_rst_n_w   = chip.u_soc_top.periph_rst_n;

// ─────────────────────────────────────────────────────────────────────────────
// [V] Boot Controller taps  [NEW-BOOT]
// ─────────────────────────────────────────────────────────────────────────────
wire        boot_done_w   = chip.u_soc_top.boot_done;
wire        boot_we_w     = chip.u_soc_top.imem_boot_we;
wire [31:0] boot_addr_w   = chip.u_soc_top.imem_boot_addr;

// ============================================================================
// Counters & State
// ============================================================================
integer cycle_count;
integer instr_retired;
integer stall_cycles;
integer dmem_rd_cnt;
integer dmem_wr_cnt;
integer post_halt_stores;
integer sb_errors;
integer cur_stall_run;
integer max_stall_run;

integer m0_ar_burst_cnt;
integer m1_ar_burst_cnt, m1_aw_burst_cnt;
integer m2_ar_burst_cnt, m2_aw_burst_cnt;
integer m3_ar_burst_cnt, m3_aw_burst_cnt;   // [NEW-5]
integer m4_ar_burst_cnt, m4_aw_burst_cnt;   // [NEW-5]
integer dma_raw_ar_cnt,  dma_raw_aw_cnt;

integer s0_ar_cnt;
integer s1_ar_cnt, s1_aw_cnt;
integer s2_access_cnt;
integer s3_access_cnt;
integer s4_access_cnt;
integer s5_access_cnt;   // [NEW-6] UART
integer s9_access_cnt;   // [NEW-6] PLIC
integer s6_access_cnt;   // GPIO accesses
integer s7_access_cnt;
integer s8_access_cnt;   // Timer/WDT accesses
integer s11_access_cnt;  // DMA Ctrl Config accesses
integer s11_dma_wr_cnt;  // DMA config write count
integer decerr_cnt;
integer xbar_conflict_cnt;
integer stub_slverr_cnt; // SLVERR từ stub slaves S7/S10 (S6 GPIO + S8 Timer đã real)

// GPIO / WDT event counters
integer gpio_irq_cnt;
integer wdt_rst_req_cnt;

// UART protocol result tracking
integer uart_pass_cnt;
integer uart_fail_cnt;
reg     uart_all_pass;
reg     uart_some_fail;

integer ascon_start_cnt;
integer ascon_dma_start_cnt;
integer ascon_done_cnt;
integer ascon_dma_done_cnt;
integer ascon_irq_cnt;
integer ascon_error_cnt;

// Bandwidth measurement arrays (up to 16 DMA operations)
integer ascon_bw_start_cyc [0:15];
integer ascon_bw_done_cyc  [0:15];
integer ascon_bw_bytes     [0:15];

integer clint_timer_irq_cnt;
integer clint_sw_irq_cnt;
integer soft_rst_cnt;

// [NEW] UART + JTAG + PLIC counters
integer uart_tx_byte_cnt;   // byte đã TX qua uart serial
integer uart_irq_cnt;       // UART IRQ raised
integer plic_meip_cnt;      // PLIC meip raised count
integer jtag_ndmreset_cnt;  // ndmreset pulses
integer jtag_halt_cnt;      // CPU entered D-mode (halted)
integer dma_irq_cnt;        // DMA controller IRQ count

integer m0_ar_start;
integer m1_ar_start, m1_aw_start;
integer m2_ar_start, m2_aw_start;
integer m3_ar_start, m3_aw_start;   // [NEW-5]
integer m4_ar_start, m4_aw_start;   // [NEW-5]
integer m0_rd_lat_sum, m0_rd_lat_cnt;
integer m1_rd_lat_sum, m1_rd_lat_cnt;
integer m1_wr_lat_sum, m1_wr_lat_cnt;
integer m2_rd_lat_sum, m2_rd_lat_cnt;
integer m2_wr_lat_sum, m2_wr_lat_cnt;
integer m3_rd_lat_sum, m3_rd_lat_cnt;
integer m3_wr_lat_sum, m3_wr_lat_cnt;
integer m4_wr_lat_sum, m4_wr_lat_cnt;

reg [31:0] prev_pc;
integer    halt_cnt;
reg        program_done;

reg [31:0] pc_ring [0:7];
integer    ring_ptr;
integer    match2, match4;

reg [31:0] sb_addr [0:255];
reg [31:0] sb_data [0:255];
integer    sb_cnt;

// Boot tracking
integer boot_word_cnt;
reg     prev_boot_done;

// Edge detection registers
reg prev_ascon_dma_done_st;
reg prev_ascon_core_done;
reg prev_ascon_dma_error;
reg prev_ascon_irq;
reg prev_ascon_ctext_v;
reg prev_ascon_tag_v;
reg prev_timer_irq;
reg prev_sw_irq;
reg prev_soft_rst;
reg prev_ext_irq;        // [NEW-8]
reg prev_uart_irq;       // [NEW-8]
reg prev_dma_irq;        // [NEW-8]
reg prev_jtag_ndmreset;  // [NEW-3]
reg prev_jtag_halted;    // [NEW-3]
reg prev_gpio_irq;       // GPIO IRQ edge detect
reg prev_wdt_rst_req;    // WDT reset request edge detect

// UART rx buffer  [NEW-2]
reg [7:0]  uart_rx_buf [0:255];
integer    uart_rx_count;

// UART line buffer for [PASS]/[FAIL] parsing
reg [7:0]  uart_line_buf [0:127];
integer    uart_line_len;

// ============================================================================
// Waveform dump
// ============================================================================
initial begin
    $dumpfile("waveform_soc.vcd");
    $dumpvars(0, run_soc);
end

// ============================================================================
// (1) Cycle Counter
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) cycle_count = cycle_count + 1;
end

// ============================================================================
// (2) Instruction Retire & Stall
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r && cpu_rst_n_w) begin
        if (!stall_if && instr_if !== 32'h0)
            instr_retired = instr_retired + 1;

        if (stall_if) begin
            stall_cycles  = stall_cycles + 1;
            cur_stall_run = cur_stall_run + 1;
            if (cur_stall_run > max_stall_run) max_stall_run = cur_stall_run;
        end else begin
            cur_stall_run = 0;
        end

        if (`LOG_LEVEL >= 3 && instr_if !== 32'h0)
            $display("[%6d] PC=0x%08h  INSTR=0x%08h%s",
                     cycle_count, pc_if, instr_if,
                     stall_if ? "  [STALL]" : "");
    end
end

// ============================================================================
// (3) DCache Load/Store Logger
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r && cpu_rst_n_w && dc_req && dc_ready) begin
        if (dc_we) begin
            if (!program_done) begin
                dmem_wr_cnt = dmem_wr_cnt + 1;
                if (`LOG_LEVEL >= 2)
                    $display("[%6d] [ST] addr=0x%08h  data=0x%08h  strb=%b",
                             cycle_count, dc_addr, dc_wdata, dc_wstrb);
            end else begin
                post_halt_stores = post_halt_stores + 1;
            end
        end else begin
            dmem_rd_cnt = dmem_rd_cnt + 1;
            sb_check(dc_addr, dc_rdata);
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [LD] addr=0x%08h  data=0x%08h",
                         cycle_count, dc_addr, dc_rdata);
        end
    end
end

// ============================================================================
// (3b) DMEM AXI Write Tracker — authoritative scoreboard source
// Tracks per-beat address for burst writes (AXI INCR, 32-bit bus, size=4B)
// ============================================================================
reg [31:0] s1_aw_addr_lat;
reg [7:0]  s1_wr_beat_cnt;

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        s1_aw_addr_lat <= 32'h0;
        s1_wr_beat_cnt <= 8'h0;
    end else begin
        if (s1_awvalid && s1_awready) begin
            s1_aw_addr_lat <= s1_awaddr;
            s1_wr_beat_cnt <= 8'h0;
        end else if (s1_wvalid && s1_wready) begin
            s1_wr_beat_cnt <= s1_wlast ? 8'h0 : s1_wr_beat_cnt + 8'h1;
        end
    end
end

wire [31:0] s1_wr_beat_addr = s1_aw_addr_lat + {s1_wr_beat_cnt, 2'b00};

always @(posedge clk) begin
    if (ext_rst_n_r && s1_wvalid && s1_wready && !program_done) begin
        sb_update(s1_wr_beat_addr, s1_wdata, s1_wstrb);
        if (`LOG_LEVEL >= 2)
            $display("[%6d] [DMEM-W] addr=0x%08h  data=0x%08h  strb=%b",
                     cycle_count, s1_wr_beat_addr, s1_wdata, s1_wstrb);
    end
end

// ============================================================================
// (4) M0 (ICache) AXI Logger
// ============================================================================
reg [31:0] m0_ar_addr_saved;
always @(posedge clk) begin
    if (ext_rst_n_r && fabric_rst_n_w) begin  // gate with fabric_rst_n to suppress X-state noise before reset
        if (m0_arvalid && m0_arready) begin
            m0_ar_burst_cnt  = m0_ar_burst_cnt + 1;
            m0_ar_start      = cycle_count;
            m0_ar_addr_saved <= m0_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M0-AR] addr=0x%08h  len=%0d  size=%0d",
                         cycle_count, m0_araddr, m0_arlen, m0_arsize);
            if (m0_araddr[31:16] !== 16'h0000 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M0(ICache) AR outside IMEM range! addr=0x%08h",
                         cycle_count, m0_araddr);
        end
        if (m0_rvalid && m0_rready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M0-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m0_rdata, m0_rresp,
                         m0_rlast ? "  [LAST]" : "");
            if (m0_rlast) begin
                m0_rd_lat_sum = m0_rd_lat_sum + (cycle_count - m0_ar_start + 1);
                m0_rd_lat_cnt = m0_rd_lat_cnt + 1;
            end
            if (m0_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M0 READ addr=0x%08h", cycle_count, m0_ar_addr_saved);
            end
        end
        if (m0_awvalid && `LOG_LEVEL >= 1)
            $display("[%6d] [WARN] M0(ICache) AW asserted! (ICache should NOT write)",
                     cycle_count);
    end
end

// ============================================================================
// (5) M1 (DCache) AXI Logger
// ============================================================================
reg [31:0] m1_ar_addr_saved;
reg [31:0] m1_aw_addr_saved;
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (m1_arvalid && m1_arready) begin
            m1_ar_burst_cnt  = m1_ar_burst_cnt + 1;
            m1_ar_start      = cycle_count;
            m1_ar_addr_saved <= m1_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AR] addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m1_araddr, m1_arlen,
                         slave_name_of_addr(m1_araddr));
        end
        if (m1_rvalid && m1_rready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M1-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m1_rdata, m1_rresp,
                         m1_rlast ? "  [LAST]" : "");
            if (m1_rlast) begin
                m1_rd_lat_sum = m1_rd_lat_sum + (cycle_count - m1_ar_start + 1);
                m1_rd_lat_cnt = m1_rd_lat_cnt + 1;
            end
            if (m1_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M1 READ addr=0x%08h",
                         cycle_count, m1_ar_addr_saved);
            end
        end
        if (m1_awvalid && m1_awready) begin
            m1_aw_burst_cnt  = m1_aw_burst_cnt + 1;
            m1_aw_start      = cycle_count;
            m1_aw_addr_saved <= m1_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AW] addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m1_awaddr, m1_awlen,
                         slave_name_of_addr(m1_awaddr));
        end
        if (m1_wvalid && m1_wready && `LOG_LEVEL >= 3)
            $display("[%6d] [M1-W ] data=0x%08h  strb=%b%s",
                     cycle_count, m1_wdata, m1_wstrb,
                     m1_wlast ? "  [LAST]" : "");
        if (m1_bvalid && m1_bready) begin
            m1_wr_lat_sum = m1_wr_lat_sum + (cycle_count - m1_aw_start + 1);
            m1_wr_lat_cnt = m1_wr_lat_cnt + 1;
            if (m1_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M1 WRITE addr=0x%08h",
                         cycle_count, m1_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (6) M2 (ASCON DMA 32-bit) AXI Logger
// ============================================================================
reg [31:0] m2_ar_addr_saved;
reg [31:0] m2_aw_addr_saved;
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (m2_arvalid && m2_arready) begin
            m2_ar_burst_cnt  = m2_ar_burst_cnt + 1;
            m2_ar_start      = cycle_count;
            m2_ar_addr_saved <= m2_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M2-AR] addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m2_araddr, m2_arlen,
                         slave_name_of_addr(m2_araddr));
        end
        if (m2_rvalid && m2_rready) begin
            if (m2_rlast) begin
                m2_rd_lat_sum = m2_rd_lat_sum + (cycle_count - m2_ar_start + 1);
                m2_rd_lat_cnt = m2_rd_lat_cnt + 1;
            end
            if (m2_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 READ addr=0x%08h",
                         cycle_count, m2_ar_addr_saved);
            end
        end
        if (m2_awvalid && m2_awready) begin
            m2_aw_burst_cnt  = m2_aw_burst_cnt + 1;
            m2_aw_start      = cycle_count;
            m2_aw_addr_saved <= m2_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M2-AW] addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m2_awaddr, m2_awlen,
                         slave_name_of_addr(m2_awaddr));
        end
        if (m2_bvalid && m2_bready) begin
            m2_wr_lat_sum = m2_wr_lat_sum + (cycle_count - m2_aw_start + 1);
            m2_wr_lat_cnt = m2_wr_lat_cnt + 1;
            if (m2_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M2 WRITE addr=0x%08h",
                         cycle_count, m2_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (6b) M3 (DMA Controller) AXI Logger  [NEW-5]
// ============================================================================
reg [31:0] m3_ar_addr_saved;
reg [31:0] m3_aw_addr_saved;
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (m3_arvalid && m3_arready) begin
            m3_ar_burst_cnt  = m3_ar_burst_cnt + 1;
            m3_ar_start      = cycle_count;
            m3_ar_addr_saved <= m3_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M3-AR] (DMA-Ctrl) addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m3_araddr, m3_arlen,
                         slave_name_of_addr(m3_araddr));
        end
        if (m3_rvalid && m3_rready) begin
            if (m3_rlast) begin
                m3_rd_lat_sum = m3_rd_lat_sum + (cycle_count - m3_ar_start + 1);
                m3_rd_lat_cnt = m3_rd_lat_cnt + 1;
            end
            if (m3_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M3(DMA) READ addr=0x%08h",
                         cycle_count, m3_ar_addr_saved);
            end
        end
        if (m3_awvalid && m3_awready) begin
            m3_aw_burst_cnt  = m3_aw_burst_cnt + 1;
            m3_aw_start      = cycle_count;
            m3_aw_addr_saved <= m3_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M3-AW] (DMA-Ctrl) addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m3_awaddr, m3_awlen,
                         slave_name_of_addr(m3_awaddr));
        end
        if (m3_bvalid && m3_bready) begin
            m3_wr_lat_sum = m3_wr_lat_sum + (cycle_count - m3_aw_start + 1);
            m3_wr_lat_cnt = m3_wr_lat_cnt + 1;
            if (m3_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M3(DMA) WRITE addr=0x%08h",
                         cycle_count, m3_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (6c) M4 (JTAG Debug Module SBA) AXI Logger  [NEW-5]
// WHY level 1 thay vì 2: JTAG SBA access quan trọng để debug — luôn log.
// ============================================================================
reg [31:0] m4_ar_addr_saved;
reg [31:0] m4_aw_addr_saved;
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (m4_arvalid && m4_arready) begin
            m4_ar_burst_cnt  = m4_ar_burst_cnt + 1;
            m4_ar_start      = cycle_count;
            m4_ar_addr_saved <= m4_araddr;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M4-AR] (JTAG-DM SBA) addr=0x%08h  len=%0d  -> %s",
                         cycle_count, m4_araddr, m4_arlen,
                         slave_name_of_addr(m4_araddr));
        end
        if (m4_rvalid && m4_rready) begin
            if (m4_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M4(JTAG) READ addr=0x%08h",
                         cycle_count, m4_ar_addr_saved);
            end
            if (m4_rlast && `LOG_LEVEL >= 1)
                $display("[%6d] [M4-R ] data=0x%08h  rresp=%0d [LAST]",
                         cycle_count, m4_rdata, m4_rresp);
        end
        if (m4_awvalid && m4_awready) begin
            m4_aw_burst_cnt  = m4_aw_burst_cnt + 1;
            m4_aw_start      = cycle_count;
            m4_aw_addr_saved <= m4_awaddr;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [M4-AW] (JTAG-DM SBA) addr=0x%08h  -> %s",
                         cycle_count, m4_awaddr,
                         slave_name_of_addr(m4_awaddr));
        end
        if (m4_wvalid && m4_wready && `LOG_LEVEL >= 1)
            $display("[%6d] [M4-W ] data=0x%08h%s",
                     cycle_count, m4_wdata,
                     m4_wlast ? "  [LAST]" : "");
        if (m4_bvalid && m4_bready) begin   // AXI: latch chỉ khi cả BVALID+BREADY
            m4_wr_lat_sum = m4_wr_lat_sum + (cycle_count - m4_aw_start + 1);
            m4_wr_lat_cnt = m4_wr_lat_cnt + 1;
            if (m4_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR M4(JTAG) WRITE addr=0x%08h",
                         cycle_count, m4_aw_addr_saved);
            end
        end
    end
end

// ============================================================================
// (7) DMA raw 64-bit Logger (ASCON side)
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (dma_awvalid && dma_awready) begin
            dma_raw_aw_cnt = dma_raw_aw_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [DMA64-AW] addr=0x%08h  len=%0d",
                         cycle_count, dma_awaddr, dma_awlen);
        end
        if (dma_arvalid && dma_arready) begin
            dma_raw_ar_cnt = dma_raw_ar_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [DMA64-AR] addr=0x%08h  len=%0d",
                         cycle_count, dma_araddr, dma_arlen);
        end
        if (dma_rvalid && dma_rready && `LOG_LEVEL >= 3)
            $display("[%6d] [DMA64-R ] data=0x%016h  rresp=%0d%s",
                     cycle_count, dma_rdata, dma_rresp,
                     dma_rlast ? "  [LAST]" : "");
        if (dma_wvalid && dma_wready && `LOG_LEVEL >= 3)
            $display("[%6d] [DMA64-W ] data=0x%016h  strb=%b%s",
                     cycle_count, dma_wdata, dma_wstrb,
                     dma_wlast ? "  [LAST]" : "");
    end
end

// ============================================================================
// (8) Per-Slave Traffic Counter
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (s0_arvalid && s0_arready) s0_ar_cnt = s0_ar_cnt + 1;
        if (s1_arvalid && s1_arready) s1_ar_cnt = s1_ar_cnt + 1;
        if (s1_awvalid && s1_awready) s1_aw_cnt = s1_aw_cnt + 1;

        if (s2_arvalid && s2_arready) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] READ  offset=0x%03h",
                         cycle_count, s2_araddr[11:0]);
        end
        if (s2_awvalid && s2_awready) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S2-ASCON] AW    offset=0x%03h",
                         cycle_count, s2_awaddr[11:0]);
        end
        if (s2_wvalid && `LOG_LEVEL >= 1)
            $display("[%6d] [S2-ASCON] WRITE offset=0x%03h  data=0x%08h",
                     cycle_count, s2_awaddr[11:0], s2_wdata);   // NOTE: s2_awaddr valid tại AW beat; nếu AW≠W cycle thì dùng s2_aw_addr_lat

        if (s3_arvalid && s3_arready) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S3-SOCCTRL] READ  addr=0x%08h", cycle_count, s3_araddr);
        end
        if (s3_awvalid && s3_awready) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S3-SOCCTRL] WRITE addr=0x%08h  data=0x%08h",
                         cycle_count, s3_awaddr, s3_wdata);
        end

        if (s4_arvalid && s4_arready) begin
            s4_access_cnt = s4_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S4-CLINT] READ  offset=0x%05h", cycle_count, s4_araddr[19:0]);
        end
        if (s4_awvalid && s4_awready) begin
            s4_access_cnt = s4_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [S4-CLINT] WRITE offset=0x%05h  data=0x%08h",
                         cycle_count, s4_awaddr[19:0], s4_wdata);
        end

        // ── [NEW-6] S5 UART traffic ──────────────────────────────────────────
        if (s5_arvalid && s5_arready) begin
            s5_access_cnt = s5_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S5-UART] READ  offset=0x%02h",
                         cycle_count, s5_araddr[7:0]);
        end
        if (s5_awvalid && s5_awready) begin
            s5_access_cnt = s5_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S5-UART] WRITE offset=0x%02h  data=0x%08h",
                         cycle_count, s5_awaddr[7:0], s5_wdata);
        end

        // ── [NEW-6] S9 PLIC traffic ──────────────────────────────────────────
        if (s9_arvalid && s9_arready) begin
            s9_access_cnt = s9_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S9-PLIC] READ  offset=0x%06h",
                         cycle_count, s9_araddr[21:0]);
        end
        if (s9_awvalid && s9_awready) begin
            s9_access_cnt = s9_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S9-PLIC] WRITE offset=0x%06h  data=0x%08h",
                         cycle_count, s9_awaddr[21:0], s9_wdata);
        end

        // ── S6 GPIO traffic ──────────────────────────────────────────────────
        if (s6_arvalid && s6_arready) begin
            s6_access_cnt = s6_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S6-GPIO] READ  offset=0x%02h",
                         cycle_count, s6_araddr[7:0]);
        end
        if (s6_awvalid && s6_awready) begin
            s6_access_cnt = s6_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S6-GPIO] WRITE offset=0x%02h  data=0x%08h",
                         cycle_count, s6_awaddr[7:0], s6_wdata);
        end

        // ── S8 Timer/WDT traffic ──────────────────────────────────────────────
        if (s8_arvalid && s8_arready) begin
            s8_access_cnt = s8_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S8-TIMER] READ  offset=0x%02h",
                         cycle_count, s8_araddr[7:0]);
        end
        if (s8_awvalid && s8_awready) begin
            s8_access_cnt = s8_access_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [S8-TIMER] WRITE offset=0x%02h  data=0x%08h",
                         cycle_count, s8_awaddr[7:0], s8_wdata);
        end

        // ── Stub slave SLVERR detection (S7=SPI stub, S10=OTP stub only) ────
        if ((chip.u_soc_top.s7_bvalid && chip.u_soc_top.s7_bresp == 2'b10) ||
            (chip.u_soc_top.s10_bvalid && chip.u_soc_top.s10_bresp == 2'b10)) begin
            stub_slverr_cnt = stub_slverr_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [WARN] Stub slave SLVERR (SPI/OTP not implemented)",
                         cycle_count);
        end
    end
end

// ============================================================================
// (9) ASCON IP Event Logger
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_ascon_dma_done_st <= 1'b0;
        prev_ascon_core_done   <= 1'b0;
        prev_ascon_dma_error   <= 1'b0;
        prev_ascon_irq         <= 1'b0;
        prev_ascon_ctext_v     <= 1'b0;
        prev_ascon_tag_v       <= 1'b0;
    end else begin
        prev_ascon_dma_done_st <= ascon_dma_done_st;
        prev_ascon_core_done   <= ascon_core_done;
        prev_ascon_dma_error   <= ascon_dma_error;
        prev_ascon_irq         <= ascon_irq_wire;
        prev_ascon_ctext_v     <= ascon_ctext_v;
        prev_ascon_tag_v       <= ascon_tag_v;
    end
end

always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (ascon_soft_rst)
            $display("[%6d] [ASCON] SOFT_RST asserted", cycle_count);

        if (ascon_core_start) begin
            ascon_start_cnt = ascon_start_cnt + 1;
            $display("[%6d] [ASCON] CORE START #%0d  dma_en=%0d  mode=%0d  enc_dec=%0d  data_len=%0d",
                     cycle_count, ascon_start_cnt, ascon_dma_en_w,
                     ascon_mode_w, ascon_enc_dec_w, ascon_data_len);
            $display("[%6d] [ASCON-IN] KEY   = %032h", cycle_count, ascon_key_in);
            $display("[%6d] [ASCON-IN] NONCE = %032h", cycle_count, ascon_nonce_in);
            $display("[%6d] [ASCON-IN] DATA  = %032h", cycle_count, ascon_data_in);
            if (ascon_dma_en_w)
                $display("[%6d] [ASCON-IN] ptext_0=0x%08h  ptext_1=0x%08h  (DMA)",
                         cycle_count, ascon_ptext_0, ascon_ptext_1);
        end

        if (ascon_dma_start) begin
            ascon_dma_start_cnt = ascon_dma_start_cnt + 1;
            if (ascon_dma_start_cnt <= 16) begin
                ascon_bw_start_cyc[ascon_dma_start_cnt - 1] = cycle_count;
                ascon_bw_bytes[ascon_dma_start_cnt - 1]     = ascon_dma_len_r;
            end
            $display("[%6d] [ASCON] DMA START #%0d  src=0x%08h  dst=0x%08h  len=%0d",
                     cycle_count, ascon_dma_start_cnt,
                     ascon_dma_src_r, ascon_dma_dst_r, ascon_dma_len_r);
        end

        if (ascon_dma_data_v && `LOG_LEVEL >= 2)
            $display("[%6d] [ASCON-DMA] ptext: 0x%08h 0x%08h",
                     cycle_count, ascon_ptext_0, ascon_ptext_1);

        if (ascon_ctext_v && !prev_ascon_ctext_v)
            $display("[%6d] [ASCON-OUT] CTEXT = %016h",
                     cycle_count, ascon_ctext_out[127:64]);

        if (ascon_tag_v && !prev_ascon_tag_v)
            $display("[%6d] [ASCON-OUT] TAG   = %032h",
                     cycle_count, ascon_tag_out);

        if (ascon_dma_done_st && !prev_ascon_dma_done_st) begin
            ascon_dma_done_cnt = ascon_dma_done_cnt + 1;
            if (ascon_dma_done_cnt <= 16)
                ascon_bw_done_cyc[ascon_dma_done_cnt - 1] = cycle_count;
            $display("[%6d] [ASCON] DMA DONE #%0d  STATUS=0x%08h",
                     cycle_count, ascon_dma_done_cnt, ascon_status_word);
        end

        if (ascon_core_done && !prev_ascon_core_done) begin
            ascon_done_cnt = ascon_done_cnt + 1;
            $display("[%6d] [ASCON] CORE DONE #%0d  STATUS=0x%08h",
                     cycle_count, ascon_done_cnt, ascon_status_word);
            $display("[%6d] [ASCON-REG] CTEXT_0=0x%08h  CTEXT_1=0x%08h",
                     cycle_count, ascon_reg_ctext0, ascon_reg_ctext1);
            $display("[%6d] [ASCON-REG] TAG_0  =0x%08h  TAG_1  =0x%08h",
                     cycle_count, ascon_reg_tag0, ascon_reg_tag1);
            $display("[%6d] [ASCON-REG] TAG_2  =0x%08h  TAG_3  =0x%08h",
                     cycle_count, ascon_reg_tag2, ascon_reg_tag3);
        end

        if (ascon_dma_error && !prev_ascon_dma_error) begin
            ascon_error_cnt = ascon_error_cnt + 1;
            $display("[%6d] [!!!] ASCON DMA ERROR  STATUS=0x%08h",
                     cycle_count, ascon_status_word);
        end

        if (ascon_irq_wire && !prev_ascon_irq) begin
            ascon_irq_cnt = ascon_irq_cnt + 1;
            $display("[%6d] [ASCON] IRQ raised #%0d → PLIC src[8]",
                     cycle_count, ascon_irq_cnt);
        end
    end
end

// ============================================================================
// (10) CLINT & Interrupt Event Logger
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_timer_irq   <= 1'b0;
        prev_sw_irq      <= 1'b0;
        prev_soft_rst    <= 1'b0;
        prev_ext_irq     <= 1'b0;
        prev_uart_irq    <= 1'b0;
        prev_dma_irq     <= 1'b0;
        prev_gpio_irq    <= 1'b0;
        prev_wdt_rst_req <= 1'b0;
    end else begin
        prev_timer_irq   <= timer_irq;
        prev_sw_irq      <= sw_irq;
        prev_soft_rst    <= soft_rst_pulse;
        prev_ext_irq     <= ext_irq;
        prev_uart_irq    <= uart_irq_w;
        prev_dma_irq     <= dma_irq_w;
        prev_gpio_irq    <= gpio_irq_w;
        prev_wdt_rst_req <= wdt_rst_req_w;
    end
end

always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (timer_irq && !prev_timer_irq) begin
            clint_timer_irq_cnt = clint_timer_irq_cnt + 1;
            $display("[%6d] [CLINT] TIMER_IRQ raised #%0d",
                     cycle_count, clint_timer_irq_cnt);
        end
        if (sw_irq && !prev_sw_irq) begin
            clint_sw_irq_cnt = clint_sw_irq_cnt + 1;
            $display("[%6d] [CLINT] SW_IRQ raised #%0d",
                     cycle_count, clint_sw_irq_cnt);
        end
        if (soft_rst_pulse && !prev_soft_rst) begin
            soft_rst_cnt = soft_rst_cnt + 1;
            $display("[%6d] [SOCCTRL] SOFT_RST_PULSE #%0d", cycle_count, soft_rst_cnt);
        end
        // [NEW-8] PLIC meip
        if (ext_irq && !prev_ext_irq) begin
            plic_meip_cnt = plic_meip_cnt + 1;
            $display("[%6d] [PLIC] meip raised #%0d  → CPU.external_irq",
                     cycle_count, plic_meip_cnt);
        end
        // [NEW-8] UART IRQ
        if (uart_irq_w && !prev_uart_irq) begin
            uart_irq_cnt = uart_irq_cnt + 1;
            $display("[%6d] [UART] irq_out raised #%0d  → PLIC src[1,2]",
                     cycle_count, uart_irq_cnt);
        end
        // [NEW-8] DMA IRQ
        if (dma_irq_w && !prev_dma_irq) begin
            dma_irq_cnt = dma_irq_cnt + 1;
            $display("[%6d] [DMA] irq_out raised #%0d  → PLIC src[9]",
                     cycle_count, dma_irq_cnt);
        end
        // GPIO IRQ
        if (gpio_irq_w && !prev_gpio_irq) begin
            gpio_irq_cnt = gpio_irq_cnt + 1;
            $display("[%6d] [GPIO] irq raised #%0d  → PLIC src[4]  gpio_in=0x%08h  gpio_out=0x%08h",
                     cycle_count, gpio_irq_cnt, gpio_in_r, gpio_out_w);
        end
        // WDT reset request interceptor
        if (wdt_rst_req_w && !prev_wdt_rst_req) begin
            wdt_rst_req_cnt = wdt_rst_req_cnt + 1;
            $display("[%6d] [WDT] wdt_rst_req asserted #%0d  (TB intercepts — DUT NOT reset)",
                     cycle_count, wdt_rst_req_cnt);
        end
    end
end

// ============================================================================
// (10b) Boot Controller Logger  [NEW-BOOT]
// ============================================================================
always @(posedge clk) begin
    if (!fabric_rst_n_w) begin
        boot_word_cnt <= 0;
        prev_boot_done <= 1'b0;
    end else begin
        prev_boot_done <= boot_done_w;
        if (boot_we_w) begin
            boot_word_cnt = boot_word_cnt + 1;
            if (boot_word_cnt == 1)
                $display("[%6d] [BOOT] boot_ctrl: START loading IMEM (2048 words)",
                         cycle_count);
        end
        if (boot_done_w && !prev_boot_done)
            $display("[%6d] [BOOT] boot_ctrl: DONE (%0d words written) → cpu_rst_n releasing",
                     cycle_count, boot_word_cnt);
    end
end

// ============================================================================
// (11) JTAG Debug Session Logger  [NEW-3]
//
// WHY monitor ndmreset: ndmreset xảy ra hoàn toàn bên trong SoC (không
// visible trên pad nào). Tap vào internal wire để biết khi nào JTAG DM
// reset CPU trong khi crossbar vẫn chạy.
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_jtag_ndmreset <= 1'b0;
        prev_jtag_halted   <= 1'b0;
    end else begin
        prev_jtag_ndmreset <= jtag_ndmreset_w;
        prev_jtag_halted   <= jtag_halted_w;
    end
end

always @(posedge clk) begin
    if (ext_rst_n_r) begin
        // ndmreset pulse
        if (jtag_ndmreset_w && !prev_jtag_ndmreset) begin
            jtag_ndmreset_cnt = jtag_ndmreset_cnt + 1;
            $display("[%6d] [JTAG] ndmreset ASSERTED #%0d  (cpu_rst_n=0, fabric_rst_n unchanged)",
                     cycle_count, jtag_ndmreset_cnt);
        end
        if (!jtag_ndmreset_w && prev_jtag_ndmreset)
            $display("[%6d] [JTAG] ndmreset RELEASED  (CPU resuming from JTAG reset)",
                     cycle_count);

        // haltreq
        if (jtag_haltreq_w && `LOG_LEVEL >= 2)
            $display("[%6d] [JTAG] haltreq HIGH  (DM requesting CPU halt)", cycle_count);

        // CPU entered D-mode
        if (jtag_halted_w && !prev_jtag_halted) begin
            jtag_halt_cnt = jtag_halt_cnt + 1;
            $display("[%6d] [JTAG] CPU halted #%0d  (D-mode, pipeline frozen  PC=0x%08h)",
                     cycle_count, jtag_halt_cnt, pc_if);
        end
        if (!jtag_halted_w && prev_jtag_halted)
            $display("[%6d] [JTAG] CPU resumed  (leaving D-mode  PC=0x%08h)",
                     cycle_count, pc_if);

        // resumereq
        if (jtag_resumereq_w && `LOG_LEVEL >= 2)
            $display("[%6d] [JTAG] resumereq HIGH  (DM releasing CPU)", cycle_count);
    end
end

// ============================================================================
// (11b) S11 DMA Config Slave Monitor
// Decode offset → CH/REG name; log WRITE operations to DMA registers.
// Register map: CH[0-3] × 4 regs (SRC/DST/LEN/CTRL) at offset 0x000..0x03F
//   STATUS=0x080, IRQ_EN=0x084, IRQ_STATUS=0x088
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) begin
        if (s11_awvalid && s11_awready) begin
            s11_access_cnt = s11_access_cnt + 1;
        end
        if (s11_arvalid && s11_arready) begin
            s11_access_cnt = s11_access_cnt + 1;
        end
        if (s11_wvalid && s11_wready) begin
            s11_dma_wr_cnt = s11_dma_wr_cnt + 1;
        end
        // Decode write: log when W channel fires together with latched AW addr
        if (s11_wvalid && s11_wready && chip.u_soc_top.s11_awvalid) begin
            begin : s11_decode
                reg [11:0] offset;
                reg [1:0]  ch;
                reg [1:0]  reg_sel;
                offset  = chip.u_soc_top.s11_awaddr[11:0];
                ch      = offset[5:4];
                reg_sel = offset[3:2];
                if (offset[11:6] == 6'b000000) begin
                    // Channel register range 0x000..0x03F
                    case (reg_sel)
                        2'd0: $display("[%6d] [S11-DMA] WRITE ch=%0d SRC  addr=0x%08h data=0x%08h",
                                       cycle_count, ch, chip.u_soc_top.s11_awaddr, s11_wdata);
                        2'd1: $display("[%6d] [S11-DMA] WRITE ch=%0d DST  addr=0x%08h data=0x%08h",
                                       cycle_count, ch, chip.u_soc_top.s11_awaddr, s11_wdata);
                        2'd2: $display("[%6d] [S11-DMA] WRITE ch=%0d LEN  addr=0x%08h data=0x%08h",
                                       cycle_count, ch, chip.u_soc_top.s11_awaddr, s11_wdata);
                        2'd3: $display("[%6d] [S11-DMA] WRITE ch=%0d CTRL addr=0x%08h data=0x%08h%s",
                                       cycle_count, ch, chip.u_soc_top.s11_awaddr, s11_wdata,
                                       s11_wdata[1] ? " (START!)" : "");
                    endcase
                end else if (offset[7:0] == 8'h80) begin
                    $display("[%6d] [S11-DMA] WRITE STATUS addr=0x%08h data=0x%08h",
                             cycle_count, chip.u_soc_top.s11_awaddr, s11_wdata);
                end else if (offset[7:0] == 8'h84) begin
                    $display("[%6d] [S11-DMA] WRITE IRQ_EN addr=0x%08h data=0x%08h",
                             cycle_count, chip.u_soc_top.s11_awaddr, s11_wdata);
                end else if (offset[7:0] == 8'h88) begin
                    $display("[%6d] [S11-DMA] WRITE IRQ_STATUS addr=0x%08h data=0x%08h (W1C clear)",
                             cycle_count, chip.u_soc_top.s11_awaddr, s11_wdata);
                end else begin
                    $display("[%6d] [S11-DMA] WRITE offset=0x%03h data=0x%08h (unknown)",
                             cycle_count, offset, s11_wdata);
                end
            end
        end
    end
end

// ============================================================================
// (11c) GPIO Output Change Monitor
// Log khi gpio_out hoặc gpio_oe thay đổi để theo dõi firmware output.
// ============================================================================
reg [31:0] prev_gpio_out;
reg [31:0] prev_gpio_oe;

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_gpio_out <= 32'h0;
        prev_gpio_oe  <= 32'h0;
    end else begin
        if (gpio_out_w !== prev_gpio_out || gpio_oe_w !== prev_gpio_oe) begin
            if (fabric_rst_n_w) begin
                $display("[%6d] [GPIO-OUT] gpio_out=0x%08h  OE=0x%08h",
                         cycle_count, gpio_out_w, gpio_oe_w);
            end
            prev_gpio_out <= gpio_out_w;
            prev_gpio_oe  <= gpio_oe_w;
        end
    end
end

// ============================================================================
// (12) UART TX Monitor — bắt serial stream 8N1  [NEW-2]
//
// WHY dùng procedural (initial + forever) thay vì always:
//   Serial protocol là event-driven theo thời gian, không theo clock.
//   Mỗi bit dài BAUD_DIV × CLK_PERIOD ns. Dùng #delay để sample chính giữa bit.
//
// Timing: uart_tx=1 idle → falling edge = start bit → sample 1.5 bit periods
//   sau = giữa bit 0, rồi mỗi 1 bit period tiếp theo = bit 1..7.
//   8N1: 8 data bits, no parity, 1 stop bit.
// ============================================================================
time baud_half;    // half bit period (ns) — dùng `time` để #delay chính xác
time baud_full;    // full bit period  (ns)

initial begin
    baud_half = (`BAUD_DIV * CLK_PERIOD) / 2;
    baud_full = `BAUD_DIV * CLK_PERIOD;
    uart_rx_count = 0;
    uart_tx_byte_cnt = 0;
    forever begin
        // Chờ start bit (falling edge trên uart_tx)
        @(negedge uart_tx_w);
        // Sample giữa bit 0: đợi 1.5 bit period
        #(baud_half + baud_full);
        begin : uart_rx_frame
            reg [7:0] rx_byte;
            integer   b;
            rx_byte = 8'h00;
            // Sample 8 data bits (LSB first)
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = uart_tx_w;
                if (b < 7) #baud_full;
            end
            // Skip stop bit
            #baud_full;
            // Log và lưu
            uart_tx_byte_cnt = uart_tx_byte_cnt + 1;
            if (rx_byte >= 8'h20 && rx_byte <= 8'h7E)
                $display("[%6d] [UART-TX] char='%s'  (0x%02h)  #%0d",
                         cycle_count, rx_byte, rx_byte, uart_tx_byte_cnt);
            else
                $display("[%6d] [UART-TX] byte=0x%02h  (non-printable)  #%0d",
                         cycle_count, rx_byte, uart_tx_byte_cnt);
            if (uart_rx_count < 256) begin
                uart_rx_buf[uart_rx_count] = rx_byte;
                uart_rx_count = uart_rx_count + 1;
            end
            // Line parser: accumulate until '\n', then parse
            if (rx_byte == 8'h0A) begin  // '\n'
                parse_uart_line();
                uart_line_len = 0;
            end else if (rx_byte != 8'h0D) begin  // skip '\r'
                if (uart_line_len < 127) begin
                    uart_line_buf[uart_line_len] = rx_byte;
                    uart_line_len = uart_line_len + 1;
                end
            end
        end
    end
end

// ============================================================================
// (12b) GPIO Stimulus Driver
// ============================================================================
initial begin
    gpio_in_r = 32'hz;
    gpio_in_r[8] = 1'b0;
    // Wait for cpu_rst_n to be released (boot_ctrl done)
    @(posedge cpu_rst_n_w);
    // Wait 5000 cycles after CPU starts to let firmware initialize
    repeat(5000) @(posedge clk);
    // Assert gpio_in[8]: rising edge → triggers GPIO edge IRQ for test_gpio
    gpio_in_r[8] = 1'b1;
    $display("[%6d] [GPIO-STIM] gpio_in[8] asserted (rising edge IRQ trigger)", cycle_count);
    repeat(100) @(posedge clk);
    gpio_in_r[8] = 1'b0;
    $display("[%6d] [GPIO-STIM] gpio_in[8] deasserted", cycle_count);
end

// ============================================================================
// (13) Halt / Loop Detection
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        halt_cnt <= 0; ring_ptr <= 0;
        match2   <= 0; match4   <= 0;
    end else if (cycle_count > 30 && cpu_rst_n_w) begin

        if (pc_if === prev_pc && !dc_req && lsu_sb_empty) begin
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= `HALT_STABLE && !program_done) begin
                program_done = 1;
                print_report("HALT LOOP DETECTED");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else begin
            halt_cnt <= 0;
        end

        if (pc_if === pc_ring[(ring_ptr + 6) % 8] && lsu_sb_empty && !dc_req) begin
            match2 = match2 + 1;
            if (match2 >= `MATCH2_THRESH && !program_done) begin
                program_done = 1;
                print_report("2-CYCLE LOOP DETECTED");
                #(CLK_PERIOD * 2); $finish;
            end
        end else match2 = 0;

        if (pc_if === pc_ring[(ring_ptr + 4) % 8] && lsu_sb_empty && !dc_req) begin
            match4 = match4 + 1;
            if (match4 >= `MATCH4_THRESH && !program_done) begin
                program_done = 1;
                print_report("4-CYCLE LOOP DETECTED");
                #(CLK_PERIOD * 2); $finish;
            end
        end else match4 = 0;

        pc_ring[ring_ptr] <= pc_if;
        ring_ptr <= (ring_ptr + 1) % 8;
        prev_pc  <= pc_if;
    end
end

// ============================================================================
// (14) Watchdog
// ============================================================================
initial begin
    #(CLK_PERIOD * `TIMEOUT);
    if (!program_done) begin
        program_done = 1;
        print_report("WATCHDOG TIMEOUT");
    end
    $finish;
end

// ============================================================================
// Main Sequence  [NEW-7]
//
// Reset sequence đúng cho clk_reset_ctrl:
//   por_n_r   = 0  (POR active) → giữ tối thiểu POR_CYCLES (1000 cy)
//   ext_rst_n_r = 0 (reset active)
//   Sau 20cy: release ext_rst_n → por_n vẫn LOW → clk_reset_ctrl nhận POR
//   Sau thêm POR_CYCLES cy: release por_n → clk_reset_ctrl release fabric_rst_n
//   Chờ thêm 5cy → execution start
//
// WHY thứ tự này:
//   por_n phải release SAU ext_rst_n (hoặc cùng lúc). Nếu por_n release trước,
//   clk_reset_ctrl có thể không giữ đủ POR duration.
// ============================================================================
integer i;
initial begin
    // Init JTAG pins — idle state (TMS=1 → reset TAP state machine)
    jtag_tck_r = 1'b0;
    jtag_tms_r = 1'b1;  // TMS=1: giữ TAP ở Test-Logic-Reset
    jtag_tdi_r = 1'b0;

    // Init counters
    cycle_count          = 0;   instr_retired        = 0;
    stall_cycles         = 0;   dmem_rd_cnt          = 0;
    dmem_wr_cnt          = 0;   post_halt_stores      = 0;
    sb_errors            = 0;   sb_cnt               = 0;
    cur_stall_run        = 0;   max_stall_run        = 0;
    program_done         = 0;   prev_pc              = 0;
    halt_cnt             = 0;   ring_ptr             = 0;
    match2               = 0;   match4               = 0;
    m0_ar_burst_cnt      = 0;
    m1_ar_burst_cnt      = 0;   m1_aw_burst_cnt      = 0;
    m2_ar_burst_cnt      = 0;   m2_aw_burst_cnt      = 0;
    m3_ar_burst_cnt      = 0;   m3_aw_burst_cnt      = 0;
    m4_ar_burst_cnt      = 0;   m4_aw_burst_cnt      = 0;
    dma_raw_ar_cnt       = 0;   dma_raw_aw_cnt       = 0;
    s0_ar_cnt            = 0;
    s1_ar_cnt            = 0;   s1_aw_cnt            = 0;
    s2_access_cnt        = 0;   s3_access_cnt        = 0;
    s4_access_cnt        = 0;   s5_access_cnt        = 0;
    s6_access_cnt        = 0;   s7_access_cnt        = 0;
    s8_access_cnt        = 0;   s9_access_cnt        = 0;
    s11_access_cnt       = 0;   s11_dma_wr_cnt       = 0;
    decerr_cnt           = 0;   xbar_conflict_cnt    = 0;
    stub_slverr_cnt      = 0;
    m0_ar_start          = 0;
    m1_ar_start          = 0;   m1_aw_start          = 0;
    m2_ar_start          = 0;   m2_aw_start          = 0;
    m3_ar_start          = 0;   m3_aw_start          = 0;
    m4_ar_start          = 0;   m4_aw_start          = 0;
    m0_rd_lat_sum        = 0;   m0_rd_lat_cnt        = 0;
    m1_rd_lat_sum        = 0;   m1_rd_lat_cnt        = 0;
    m1_wr_lat_sum        = 0;   m1_wr_lat_cnt        = 0;
    m2_rd_lat_sum        = 0;   m2_rd_lat_cnt        = 0;
    m2_wr_lat_sum        = 0;   m2_wr_lat_cnt        = 0;
    m3_rd_lat_sum        = 0;   m3_rd_lat_cnt        = 0;
    m3_wr_lat_sum        = 0;   m3_wr_lat_cnt        = 0;
    m4_wr_lat_sum        = 0;   m4_wr_lat_cnt        = 0;
    ascon_start_cnt      = 0;   ascon_dma_start_cnt  = 0;
    ascon_done_cnt       = 0;   ascon_dma_done_cnt   = 0;
    ascon_irq_cnt        = 0;   ascon_error_cnt      = 0;
    begin : bw_init
        integer _bi;
        for (_bi = 0; _bi < 16; _bi = _bi + 1) begin
            ascon_bw_start_cyc[_bi] = 0;
            ascon_bw_done_cyc[_bi]  = 0;
            ascon_bw_bytes[_bi]     = 0;
        end
    end
    clint_timer_irq_cnt  = 0;   clint_sw_irq_cnt     = 0;
    soft_rst_cnt         = 0;
    uart_tx_byte_cnt     = 0;   uart_irq_cnt         = 0;
    plic_meip_cnt        = 0;   jtag_ndmreset_cnt    = 0;
    jtag_halt_cnt        = 0;   dma_irq_cnt          = 0;
    boot_word_cnt        = 0;   prev_boot_done       = 0;
    gpio_irq_cnt         = 0;   wdt_rst_req_cnt      = 0;
    uart_pass_cnt        = 0;   uart_fail_cnt        = 0;
    uart_all_pass        = 1'b0; uart_some_fail      = 1'b0;
    uart_line_len        = 0;

    for (i = 0; i < 256; i = i + 1) begin
        sb_addr[i] = 0; sb_data[i] = 0;
        uart_rx_buf[i] = 0;
    end
    for (i = 0; i < 128; i = i + 1) uart_line_buf[i] = 0;
    for (i = 0; i < 8; i = i + 1) pc_ring[i] = 0;

    print_banner();

    // [NEW-7] Reset sequence cho clk_reset_ctrl
    por_n_r     = 1'b0;   // POR active
    ext_rst_n_r = 1'b0;   // ext reset active

    // Giữ cả hai thấp 20 cycle để VDD "ổn định"
    repeat(20) @(posedge clk);

    // Release ext_rst_n trước (por_n vẫn LOW — clk_reset_ctrl vẫn hold reset)
    ext_rst_n_r = 1'b1;
    $display("[%6d] ext_rst_n released (por_n still LOW)", cycle_count);

    // Chờ đủ POR_CYCLES để clk_reset_ctrl stretch por
    // POR_CYCLES=1000 nhưng dùng 1020 để chắc chắn
    repeat(1020) @(posedge clk);

    // Release por_n → clk_reset_ctrl bắt đầu release fabric_rst_n
    por_n_r = 1'b1;
    $display("[%6d] por_n released — waiting for fabric_rst_n...", cycle_count);

    // Chờ fabric_rst_n release → boot_ctrl bắt đầu copy IMEM
    @(posedge fabric_rst_n_w);
    $display("[%6d] fabric_rst_n released -> boot_ctrl loading IMEM (2048 words)...",
             cycle_count);

    // Chờ boot_ctrl hoàn tất (2048 cycles) → cpu_rst_n release
    @(posedge boot_done_w);
    $display("[%6d] boot_done asserted -> waiting for cpu_rst_n...", cycle_count);

    @(posedge cpu_rst_n_w);
    repeat(3) @(posedge clk);   // 3 cycle margin sau khi cpu_rst_n lên

    if (`LOG_LEVEL >= 1)
        $display("[%6d] cpu_rst_n released -> CPU execution started\n", cycle_count);

    // IRQ path monitor: phát hiện ascon_irq=1 nhưng plic_meip=0 (PLIC threshold/enable bug)
    $monitor("[MON %0t] ascon_irq=%b  plic_meip=%b  uart_irq=%b  dma_irq=%b",
             $time, ascon_irq_w, plic_meip, uart_irq_w, dma_irq_w);

    wait(program_done);
end

// ============================================================================
// SCOREBOARD TASKS
// ============================================================================
task sb_update;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    reg [31:0] al;
    integer    idx, found;
    reg [31:0] merged;
    begin
        al = {addr[31:2], 2'b00}; found = -1;
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al) found = idx;
        merged = (found >= 0) ? sb_data[found] : 32'h0;
        if (strb[0]) merged[ 7: 0] = data[ 7: 0];
        if (strb[1]) merged[15: 8] = data[15: 8];
        if (strb[2]) merged[23:16] = data[23:16];
        if (strb[3]) merged[31:24] = data[31:24];
        if (found >= 0) sb_data[found] = merged;
        else if (sb_cnt < 256) begin
            sb_addr[sb_cnt] = al; sb_data[sb_cnt] = merged;
            sb_cnt = sb_cnt + 1;
        end
    end
endtask

task sb_check;
    input [31:0] addr;
    input [31:0] got;
    reg [31:0] al;
    integer idx;
    begin
        al = {addr[31:2], 2'b00};
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al && sb_data[idx] !== got) begin
                sb_errors = sb_errors + 1;
                $display("[%6d] [ERR-RAW] addr=0x%08h  exp=0x%08h  got=0x%08h",
                         cycle_count, al, sb_data[idx], got);
            end
    end
endtask

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================
function [63:0] slave_name_of_addr;
    input [31:0] addr;
    begin
        if      (addr[31:16] == 16'h0000)            slave_name_of_addr = "IMEM    ";
        else if (addr[31:16] == 16'h1000)            slave_name_of_addr = "DMEM    ";
        else if (addr[31:12] == 20'h20000)           slave_name_of_addr = "ASCON   ";
        else if (addr[31:12] == 20'h30000)           slave_name_of_addr = "SoCCtrl ";
        else if (addr[31:16] == 16'h4000)            slave_name_of_addr = "CLINT   ";
        else if (addr[31:12] == 20'h50000)           slave_name_of_addr = "UART    ";
        else if (addr[31:12] == 20'h50010)           slave_name_of_addr = "GPIO    ";
        else if (addr[31:12] == 20'h50020)           slave_name_of_addr = "SPI     ";
        else if (addr[31:12] == 20'h50030)           slave_name_of_addr = "Timer   ";
        else if (addr[31:12] == 20'h50040)           slave_name_of_addr = "PLIC    ";
        else if (addr[31:12] == 20'h60000)           slave_name_of_addr = "OTP     ";
        else if (addr[31:12] == 20'h60010)           slave_name_of_addr = "DMA-Cfg ";
        else                                         slave_name_of_addr = "DECERR! ";
    end
endfunction

function [39:0] abi_name;
    input integer r;
    begin
        case (r)
            0:  abi_name = "zero ";   1:  abi_name = "ra   ";
            2:  abi_name = "sp   ";   3:  abi_name = "gp   ";
            4:  abi_name = "tp   ";   5:  abi_name = "t0   ";
            6:  abi_name = "t1   ";   7:  abi_name = "t2   ";
            8:  abi_name = "s0/fp";   9:  abi_name = "s1   ";
            10: abi_name = "a0   ";   11: abi_name = "a1   ";
            12: abi_name = "a2   ";   13: abi_name = "a3   ";
            14: abi_name = "a4   ";   15: abi_name = "a5   ";
            16: abi_name = "a6   ";   17: abi_name = "a7   ";
            18: abi_name = "s2   ";   19: abi_name = "s3   ";
            20: abi_name = "s4   ";   21: abi_name = "s5   ";
            22: abi_name = "s6   ";   23: abi_name = "s7   ";
            24: abi_name = "s8   ";   25: abi_name = "s9   ";
            26: abi_name = "s10  ";   27: abi_name = "s11  ";
            28: abi_name = "t3   ";   29: abi_name = "t4   ";
            30: abi_name = "t5   ";   31: abi_name = "t6   ";
            default: abi_name = "???  ";
        endcase
    end
endfunction

// ============================================================================
// PRINT REPORT
// ============================================================================
task print_report;
    input [255:0] reason;   // 32 chars — "2-CYCLE LOOP DETECTED" = 21 chars needs > 128 bits
    integer j, k, nz, dma_wi;
    real    cpi, ipc, eff, ic_rate, dc_rate;
    real    m0_rd_lat_avg, m1_rd_lat_avg, m1_wr_lat_avg, m3_rd_lat_avg, m3_wr_lat_avg;
    integer ic_total, dc_total;
    reg [31:0] ret, wv, dma_base_off, dma_word;
    integer bw_cycles, bw_bits;
    real    bw_bpc, bw_mbps;
    begin
        ret = chip.u_soc_top.u_cpu.register_file.registers[10];

        $display("");
        $display("+=================================================================+");
        $display("|  STOP: %-57s|", reason);
        $display("+=================================================================+");

        if (reason == "2-CYCLE LOOP DETECTED" || reason == "4-CYCLE LOOP DETECTED") begin
            $display("|  [DIAG] Final PC = 0x%08h", pc_if);
            if (pc_if >= 32'h00001000)
                $display("|  [DIAG] PC > 0x1000 → possible IMEM overflow (fetch NOP loop)");
            else if (pc_if >= 32'h00000400)
                $display("|  [DIAG] PC in code range → normal halt if a0==0");
        end

        // ── (1) Result ───────────────────────────────────────────────────────
        $display("");
        $display("+--- (1) PROGRAM RESULT -----------------------------------------+");
        $display("|  a0 (x10) = 0x%08h  =  %0d  (signed: %0d)",
                 ret, ret, $signed(ret));
        $display("|  Binary   = %032b", ret);
        if (ret === 32'h0)  $display("|  [OK]  a0 == 0");
        else                $display("|  [!!]  a0 != 0  -- firmware may have set error code");
        $display("|  Final PC = 0x%08h", pc_if);
        $display("+----------------------------------------------------------------+");

        // ── (2) Performance ──────────────────────────────────────────────────
        $display("");
        $display("+--- (2) PERFORMANCE --------------------------------------------+");
        if (instr_retired > 0) begin
            cpi = cycle_count * 1.0 / instr_retired;
            ipc = instr_retired * 1.0 / cycle_count;
            $display("|  Cycles           : %0d", cycle_count);
            $display("|  Instructions     : %0d", instr_retired);
            $display("|  CPI              : %.2f", cpi);
            $display("|  IPC              : %.2f", ipc);
        end
        $display("|  Stall cycles     : %0d  (%.1f%%)",
                 stall_cycles, cycle_count > 0 ? stall_cycles * 100.0 / cycle_count : 0.0);
        $display("|  Max stall run    : %0d cycles", max_stall_run);
        $display("+----------------------------------------------------------------+");

        // ── (3) Cache Stats ──────────────────────────────────────────────────
        $display("");
        $display("+--- (3) CACHE STATS --------------------------------------------+");
        ic_total = icache_stat_hits + icache_stat_misses;
        dc_total = dcache_stat_hits + dcache_stat_misses;
        ic_rate  = ic_total > 0 ? icache_stat_hits * 100.0 / ic_total : 0.0;
        dc_rate  = dc_total > 0 ? dcache_stat_hits * 100.0 / dc_total : 0.0;
        $display("|  ICache  hits=%0d  misses=%0d  rate=%.1f%%",
                 icache_stat_hits, icache_stat_misses, ic_rate);
        $display("|  DCache  hits=%0d  misses=%0d  rate=%.1f%%  writes=%0d",
                 dcache_stat_hits, dcache_stat_misses, dc_rate, dcache_stat_writes);
        $display("+----------------------------------------------------------------+");

        // ── (4) AXI Bus Stats ────────────────────────────────────────────────
        m0_rd_lat_avg = (m0_rd_lat_cnt > 0) ? (m0_rd_lat_sum * 1.0 / m0_rd_lat_cnt) : 0.0;
        m1_rd_lat_avg = (m1_rd_lat_cnt > 0) ? (m1_rd_lat_sum * 1.0 / m1_rd_lat_cnt) : 0.0;
        m1_wr_lat_avg = (m1_wr_lat_cnt > 0) ? (m1_wr_lat_sum * 1.0 / m1_wr_lat_cnt) : 0.0;
        m3_rd_lat_avg = (m3_rd_lat_cnt > 0) ? (m3_rd_lat_sum * 1.0 / m3_rd_lat_cnt) : 0.0;
        m3_wr_lat_avg = (m3_wr_lat_cnt > 0) ? (m3_wr_lat_sum * 1.0 / m3_wr_lat_cnt) : 0.0;
        $display("");
        $display("+--- (4) AXI BUS STATS ------------------------------------------+");
        if (m0_rd_lat_cnt > 0)
            $display("|  M0(ICache):  AR=%0d  rd_lat=%.1f cy", m0_ar_burst_cnt, m0_rd_lat_avg);
        else
            $display("|  M0(ICache):  AR=%0d  rd_lat=n/a cy", m0_ar_burst_cnt);
        if (m1_rd_lat_cnt > 0 && m1_wr_lat_cnt > 0)
            $display("|  M1(DCache):  AR=%0d  AW=%0d  rd_lat=%.1f cy  wr_lat=%.1f cy",
                     m1_ar_burst_cnt, m1_aw_burst_cnt, m1_rd_lat_avg, m1_wr_lat_avg);
        else if (m1_rd_lat_cnt > 0)
            $display("|  M1(DCache):  AR=%0d  AW=%0d  rd_lat=%.1f cy  wr_lat=n/a cy",
                     m1_ar_burst_cnt, m1_aw_burst_cnt, m1_rd_lat_avg);
        else if (m1_wr_lat_cnt > 0)
            $display("|  M1(DCache):  AR=%0d  AW=%0d  rd_lat=n/a cy  wr_lat=%.1f cy",
                     m1_ar_burst_cnt, m1_aw_burst_cnt, m1_wr_lat_avg);
        else
            $display("|  M1(DCache):  AR=%0d  AW=%0d  rd_lat=n/a cy  wr_lat=n/a cy",
                     m1_ar_burst_cnt, m1_aw_burst_cnt);
        $display("|  M2(ASCON-DMA32): AR=%0d  AW=%0d", m2_ar_burst_cnt, m2_aw_burst_cnt);
        if (m3_rd_lat_cnt > 0 && m3_wr_lat_cnt > 0)
            $display("|  M3(DMA-Ctrl):    AR=%0d  AW=%0d  rd_lat=%.1f cy  wr_lat=%.1f cy",
                     m3_ar_burst_cnt, m3_aw_burst_cnt, m3_rd_lat_avg, m3_wr_lat_avg);
        else if (m3_rd_lat_cnt > 0)
            $display("|  M3(DMA-Ctrl):    AR=%0d  AW=%0d  rd_lat=%.1f cy  wr_lat=n/a cy",
                     m3_ar_burst_cnt, m3_aw_burst_cnt, m3_rd_lat_avg);
        else if (m3_wr_lat_cnt > 0)
            $display("|  M3(DMA-Ctrl):    AR=%0d  AW=%0d  rd_lat=n/a cy  wr_lat=%.1f cy",
                     m3_ar_burst_cnt, m3_aw_burst_cnt, m3_wr_lat_avg);
        else
            $display("|  M3(DMA-Ctrl):    AR=%0d  AW=%0d  rd_lat=n/a cy  wr_lat=n/a cy",
                     m3_ar_burst_cnt, m3_aw_burst_cnt);
        $display("|  M4(JTAG-DM SBA): AR=%0d  AW=%0d  (debug memory accesses)",
                 m4_ar_burst_cnt, m4_aw_burst_cnt);
        $display("|  DMA64(raw):      AR=%0d  AW=%0d  (64-bit ASCON side)",
                 dma_raw_ar_cnt, dma_raw_aw_cnt);
        $display("|  DECERR count : %0d  (unmapped or stub-SLVERR: %0d)",
                 decerr_cnt, stub_slverr_cnt);
        $display("+----------------------------------------------------------------+");

        // ── (5) Per-Slave Access ─────────────────────────────────────────────
        $display("");
        $display("+--- (5) PER-SLAVE ACCESS COUNT ---------------------------------+");
        $display("|  S0 IMEM    AR=%0d", s0_ar_cnt);
        $display("|  S1 DMEM    AR=%0d  AW=%0d", s1_ar_cnt, s1_aw_cnt);
        $display("|  S2 ASCON   accesses=%0d", s2_access_cnt);
        $display("|  S3 SoCCtrl accesses=%0d", s3_access_cnt);
        $display("|  S4 CLINT   accesses=%0d", s4_access_cnt);
        $display("|  S5 UART    accesses=%0d", s5_access_cnt);
        $display("|  S6 GPIO    accesses=%0d  (irq_raised=%0d)", s6_access_cnt, gpio_irq_cnt);
        $display("|  S8 Timer   accesses=%0d  (wdt_rst_req=%0d)", s8_access_cnt, wdt_rst_req_cnt);
        $display("|  S9 PLIC    accesses=%0d", s9_access_cnt);
        $display("|  S11 DMA-Cfg accesses=%0d  (writes=%0d)", s11_access_cnt, s11_dma_wr_cnt);
        $display("|  S7/S10 stub SLVERR count: %0d", stub_slverr_cnt);
        $display("+----------------------------------------------------------------+");

        // ── (6) ASCON Summary ────────────────────────────────────────────────
        $display("");
        $display("+--- (6) ASCON SUMMARY ------------------------------------------+");
        $display("|  CORE start  : %0d", ascon_start_cnt);
        $display("|  CORE done   : %0d", ascon_done_cnt);
        $display("|  DMA start   : %0d", ascon_dma_start_cnt);
        $display("|  DMA done    : %0d", ascon_dma_done_cnt);
        $display("|  IRQ raised  : %0d  → PLIC src[8]", ascon_irq_cnt);
        $display("|  Errors      : %0d", ascon_error_cnt);
        if (ascon_done_cnt > 0 && ascon_dma_start_cnt == 0)
            $display("|  [OK] CPU-Direct encryption completed");
        if (ascon_dma_done_cnt > 0)
            $display("|  [OK] DMA-mode encryption completed");
        $display("|  --- OUTPUT (slave registers) ---");
        $display("|  CTEXT_0 = 0x%08h", ascon_reg_ctext0);
        $display("|  CTEXT_1 = 0x%08h", ascon_reg_ctext1);
        $display("|  TAG_0   = 0x%08h", ascon_reg_tag0);
        $display("|  TAG_1   = 0x%08h", ascon_reg_tag1);
        $display("|  TAG_2   = 0x%08h", ascon_reg_tag2);
        $display("|  TAG_3   = 0x%08h", ascon_reg_tag3);
        $display("|  --- DMA output in DMEM (direct read from memory array) ---");
        $display("|  DMA dst addr = 0x%08h  (20 words: 8x ctext_pair + 4x tag)", ascon_dma_dst_r);
        if (ascon_dma_done_cnt > 0) begin
            dma_base_off = ascon_dma_dst_r - 32'h10000000;
            for (dma_wi = 0; dma_wi < 20; dma_wi = dma_wi + 1) begin
                dma_word = { chip.u_soc_top.u_dmem.dmem.memory[dma_base_off + dma_wi*4 + 3],
                             chip.u_soc_top.u_dmem.dmem.memory[dma_base_off + dma_wi*4 + 2],
                             chip.u_soc_top.u_dmem.dmem.memory[dma_base_off + dma_wi*4 + 1],
                             chip.u_soc_top.u_dmem.dmem.memory[dma_base_off + dma_wi*4 + 0] };
                if (dma_wi < 16)
                    $display("|  [0x%08h] BLK%0d_%s = 0x%08h",
                             ascon_dma_dst_r + dma_wi*4, dma_wi/2,
                             (dma_wi[0] == 0) ? "CT0" : "CT1", dma_word);
                else
                    $display("|  [0x%08h] TAG_%0d   = 0x%08h",
                             ascon_dma_dst_r + dma_wi*4, dma_wi - 16, dma_word);
            end
        end
        $display("+----------------------------------------------------------------+");

        // ── (7) Interrupt Summary  [NEW-8] ───────────────────────────────────
        $display("");
        $display("+--- (7) INTERRUPT SUMMARY --------------------------------------+");
        $display("|  timer_irq     : %0d  (CLINT → CPU bypass PLIC)", clint_timer_irq_cnt);
        $display("|  sw_irq        : %0d  (CLINT → CPU bypass PLIC)", clint_sw_irq_cnt);
        $display("|  PLIC meip     : %0d  (PLIC → CPU.external_irq)", plic_meip_cnt);
        $display("|  ascon_irq     : %0d  → PLIC src[8]", ascon_irq_cnt);
        $display("|  uart_irq      : %0d  → PLIC src[1,2]", uart_irq_cnt);
        $display("|  gpio_irq      : %0d  → PLIC src[4]", gpio_irq_cnt);
        $display("|  dma_irq       : %0d  → PLIC src[9]", dma_irq_cnt);
        $display("|  wdt_rst_req   : %0d  (TB intercept, DUT not reset)", wdt_rst_req_cnt);
        $display("|  soft_rst_pulse: %0d", soft_rst_cnt);
        $display("|  mtime_tick period: 100 cycles (1 MHz @ 100 MHz)");
        $display("+----------------------------------------------------------------+");

        // ── (8) UART TX Summary  [NEW-2] ─────────────────────────────────────
        $display("");
        $display("+--- (8) UART TX SUMMARY ----------------------------------------+");
        $display("|  Bytes transmitted : %0d", uart_tx_byte_cnt);
        if (uart_tx_byte_cnt > 0) begin
            $write("|  Message: \"");
            for (j = 0; j < uart_rx_count && j < 64; j = j + 1)
                if (uart_rx_buf[j] >= 8'h20 && uart_rx_buf[j] <= 8'h7E)
                    $write("%s", uart_rx_buf[j]);
                else
                    $write(".");
            $display("\"");
        end else begin
            $display("|  (no UART output)");
        end
        $display("|  --- Test Protocol Results ---");
        $display("|  [PASS] count  : %0d", uart_pass_cnt);
        $display("|  [FAIL] count  : %0d", uart_fail_cnt);
        if (uart_all_pass)
            $display("|  >>> ALL_PASS seen in UART output <<<");
        else if (uart_some_fail)
            $display("|  >>> SOME_FAIL seen in UART output <<<");
        else if (uart_tx_byte_cnt > 0)
            $display("|  (no ALL_PASS/SOME_FAIL line seen yet)");
        $display("+----------------------------------------------------------------+");

        // ── TEST RESULTS ─────────────────────────────────────────────────────
        $display("");
        $display("+--- TEST RESULTS -----------------------------------------------+");
        $display("|  TESTS: PASS=%-4d FAIL=%-4d", uart_pass_cnt, uart_fail_cnt);
        if (uart_pass_cnt > 0 && uart_fail_cnt == 0)
            $display("|  [OK]  ALL %0d TEST(S) PASSED", uart_pass_cnt);
        else if (uart_fail_cnt > 0)
            $display("|  [!!]  %0d TEST(S) FAILED", uart_fail_cnt);
        else
            $display("|  (no test results detected)");
        $display("|  DMA config writes : %0d  (S11 accesses total: %0d)",
                 s11_dma_wr_cnt, s11_access_cnt);
        $display("|  DMA IRQ raised    : %0d  → PLIC src[9]", dma_irq_cnt);
        $display("+----------------------------------------------------------------+");

        // ── (9) JTAG Debug Summary  [NEW-3] ──────────────────────────────────
        $display("");
        $display("+--- (9) JTAG DEBUG SUMMARY -------------------------------------+");
        $display("|  ndmreset pulses  : %0d  (CPU reset by JTAG DM)", jtag_ndmreset_cnt);
        $display("|  CPU halted       : %0d  times (D-mode entries)", jtag_halt_cnt);
        if (jtag_halt_cnt == 0)
            $display("|  (no JTAG debug session detected — expected for pure SW simulation)");
        $display("+----------------------------------------------------------------+");

        // ── (10) Memory Access Summary ───────────────────────────────────────
        $display("");
        $display("+--- (10) MEMORY ACCESS SUMMARY ---------------------------------+");
        $display("|  CPU Loads      : %0d", dmem_rd_cnt);
        $display("|  CPU Stores     : %0d", dmem_wr_cnt);
        $display("|  Post-halt SB   : %0d stores", post_halt_stores);
        $display("|  RAW hazard err : %0d  %s",
                 sb_errors, sb_errors == 0 ? "(OK)" : "[!!!] DATA ERRORS DETECTED");
        $display("|  LSU SB remain  : %0d entries at halt", lsu_sb_count);
        $display("|  LSU drain idle : %0s",
                 lsu_drain_idle ? "YES (OK)" : "NO [!!!]");
        $display("+----------------------------------------------------------------+");

        // ── (11) Register File ───────────────────────────────────────────────
        $display("");
        $display("+--- (11) REGISTER FILE -----------------------------------------+");
        $display("|  Reg   ABI     Hex          Decimal (signed)");
        $display("|  -----------------------------------------");
        nz = 0;
        for (j = 0; j < 32; j = j + 1) begin
            wv = chip.u_soc_top.u_cpu.register_file.registers[j];
            if (wv !== 32'h0 || j == 2 || j == 10) begin
                nz = nz + 1;
                $display("|  x%-2d  %-5s   0x%08h   %0d",
                         j, abi_name(j), wv, $signed(wv));
            end
        end
        if (nz == 0) $display("|  (all zero)");
        $display("+----------------------------------------------------------------+");

        // ── (12) DMEM Snapshot ───────────────────────────────────────────────
        print_dmem_snapshot();

        // ── (13) Store Scoreboard ────────────────────────────────────────────
        $display("");
        $display("+--- (13) STORE SCOREBOARD (%0d entries, %0d errors) ─────────────+",
                 sb_cnt, sb_errors);
        k = 0;
        for (j = 0; j < sb_cnt && j < 48; j = j + 1) begin
            if (sb_data[j] !== 32'h0) begin
                $display("|  [0x%08h] = 0x%08h  (%0d)",
                         sb_addr[j], sb_data[j], sb_data[j]);
                k = k + 1;
            end
        end
        if (k == 0) $display("|  (no non-zero stores recorded)");
        if (sb_cnt > 48)
            $display("|  ... (%0d more entries truncated)", sb_cnt - 48);
        $display("+----------------------------------------------------------------+");

        // ── (14) ASCON Bandwidth Summary ─────────────────────────────────────
        $display("");
        $display("+--- (14) ASCON BANDWIDTH SUMMARY --------------------------------+");
        if (ascon_dma_done_cnt > 0) begin
            $display("|  %-6s  %-8s  %-8s  %-14s  %-14s",
                     "Op#", "Bytes", "Cycles", "Bits/Cycle", "Mbps@100MHz");
            $display("|  -------------------------------------------------------");
            for (j = 0; j < ascon_dma_done_cnt && j < 16; j = j + 1) begin
                bw_cycles = ascon_bw_done_cyc[j] - ascon_bw_start_cyc[j];
                bw_bits   = ascon_bw_bytes[j] * 8;
                bw_bpc    = (bw_cycles > 0) ? (1.0 * bw_bits / bw_cycles) : 0.0;
                bw_mbps   = (bw_cycles > 0) ? (1.0 * bw_bits * 100.0 / bw_cycles) : 0.0;
                $display("|  %-6d  %-8d  %-8d  %-14.6f  %-14.4f",
                         j+1, ascon_bw_bytes[j], bw_cycles, bw_bpc, bw_mbps);
            end
        end else begin
            $display("|  (no DMA operations recorded)");
        end
        $display("+----------------------------------------------------------------+");

        $display("");
        $display("=================================================================");
        $display("  RISC-V SoC  |  %0d cycles @ 100 MHz = %.2f us",
                 cycle_count, cycle_count * 10.0 / 1000.0);
        $display("=================================================================");
        $display("");
    end
endtask

task print_dmem_snapshot;
    integer wi, col;
    reg [31:0] base, addr, wval;
    reg [7:0]  byte_val;
    begin
        base = `DMEM_DUMP_BASE;
        $display("");
        $display("+--- (12) DMEM SNAPSHOT [0x%08h..0x%08h] (%0d words) ──────────+",
                 base, base + `DMEM_DUMP_WORDS * 4 - 1, `DMEM_DUMP_WORDS);
        $display("|  Address       +0          +4          +8          +C");
        $display("|  ---------------------------------------------------------");

        for (wi = 0; wi < `DMEM_DUMP_WORDS; wi = wi + `DMEM_ROW_WORDS) begin
            addr = base + wi * 4;
            $write("|  0x%08h  ", addr);
            for (col = 0; col < `DMEM_ROW_WORDS; col = col + 1) begin
                // Đọc thẳng từ DMEM memory array (bắt cả DMA write)
                wval = { chip.u_soc_top.u_dmem.dmem.memory[(wi+col)*4 + 3],
                         chip.u_soc_top.u_dmem.dmem.memory[(wi+col)*4 + 2],
                         chip.u_soc_top.u_dmem.dmem.memory[(wi+col)*4 + 1],
                         chip.u_soc_top.u_dmem.dmem.memory[(wi+col)*4 + 0] };
                $write("0x%08h  ", wval);
            end
            $display("");
        end

        $display("|");
        $display("|  ASCII view:");
        $write("|  ");
        for (wi = 0; wi < `DMEM_DUMP_WORDS * 4; wi = wi + 1) begin
            byte_val = chip.u_soc_top.u_dmem.dmem.memory[wi];
            if (byte_val >= 8'h20 && byte_val <= 8'h7E) $write("%s", byte_val);
            else                                          $write(".");
            if ((wi & 15) == 15 && wi < `DMEM_DUMP_WORDS*4-1) begin
                $display(""); $write("|  ");
            end
        end
        $display("");
        $display("+----------------------------------------------------------------+");
    end
endtask

// ============================================================================
// UART Line Parser — detect [PASS]/[FAIL]/ALL_PASS/SOME_FAIL
// Called after every '\n' received on UART TX serial stream.
// uart_line_buf[0..uart_line_len-1] contains the line without CR/LF.
// ============================================================================
task parse_uart_line;
    integer p;
    reg match_pass, match_fail, match_all_pass, match_some_fail;
    begin
        match_pass      = (uart_line_len >= 6 &&
                           uart_line_buf[0] == "[" && uart_line_buf[1] == "P" &&
                           uart_line_buf[2] == "A" && uart_line_buf[3] == "S" &&
                           uart_line_buf[4] == "S" && uart_line_buf[5] == "]");
        match_fail      = (uart_line_len >= 6 &&
                           uart_line_buf[0] == "[" && uart_line_buf[1] == "F" &&
                           uart_line_buf[2] == "A" && uart_line_buf[3] == "I" &&
                           uart_line_buf[4] == "L" && uart_line_buf[5] == "]");
        match_all_pass  = (uart_line_len >= 8 &&
                           uart_line_buf[0] == "A" && uart_line_buf[1] == "L" &&
                           uart_line_buf[2] == "L" && uart_line_buf[3] == "_" &&
                           uart_line_buf[4] == "P" && uart_line_buf[5] == "A" &&
                           uart_line_buf[6] == "S" && uart_line_buf[7] == "S");
        match_some_fail = (uart_line_len >= 9 &&
                           uart_line_buf[0] == "S" && uart_line_buf[1] == "O" &&
                           uart_line_buf[2] == "M" && uart_line_buf[3] == "E" &&
                           uart_line_buf[4] == "_" && uart_line_buf[5] == "F" &&
                           uart_line_buf[6] == "A" && uart_line_buf[7] == "I" &&
                           uart_line_buf[8] == "L");

        if (match_pass) begin
            uart_pass_cnt = uart_pass_cnt + 1;
            $write("[%6d] [TEST-RESULT] *** PASS #%0d *** : ", cycle_count, uart_pass_cnt);
            for (p = 0; p < uart_line_len; p = p + 1) $write("%s", uart_line_buf[p]);
            $display("");
        end else if (match_fail) begin
            uart_fail_cnt = uart_fail_cnt + 1;
            $write("[%6d] [TEST-RESULT] *** FAIL #%0d *** : ", cycle_count, uart_fail_cnt);
            for (p = 0; p < uart_line_len; p = p + 1) $write("%s", uart_line_buf[p]);
            $display("");
        end else if (match_all_pass) begin
            uart_all_pass = 1'b1;
            $write("[%6d] [RESULT] ", cycle_count);
            for (p = 0; p < uart_line_len; p = p + 1) $write("%s", uart_line_buf[p]);
            $display(" ← ALL_PASS");
            // Firmware finished successfully — print report and exit
            program_done = 1;
            print_report("ALL_PASS from firmware");
            #(CLK_PERIOD * 4);
            $finish(0);
        end else if (match_some_fail) begin
            uart_some_fail = 1'b1;
            $write("[%6d] [RESULT] ", cycle_count);
            for (p = 0; p < uart_line_len; p = p + 1) $write("%s", uart_line_buf[p]);
            $display(" ← SOME_FAIL");
            // Firmware finished with failures
            program_done = 1;
            print_report("SOME_FAIL from firmware");
            #(CLK_PERIOD * 4);
            $finish(1);
        end
    end
endtask

task print_banner;
    begin
        $display("");
        $display("+=================================================================+");
        $display("|   RISC-V SoC + ASCON — Debug Testbench  v6.0                   |");
        $display("|   5M × 12S Crossbar | UART | JTAG | PLIC | DMA | 100 MHz       |");
        $display("+-----------------------------------------------------------------+");
        $display("|   Masters:  M0=ICache  M1=DCache  M2=ASCON-DMA(64→32)          |");
        $display("|             M3=DMA-Ctrl  M4=JTAG-DM(SBA)                       |");
        $display("+-----------------------------------------------------------------+");
        $display("|   Address Map:                                                  |");
        $display("|     S0  IMEM     0x0000_0000 - 0x0000_1FFF  ( 8 KB)            |");
        $display("|     S1  DMEM     0x1000_0000 - 0x1000_1FFF  ( 8 KB)            |");
        $display("|     S2  ASCON    0x2000_0000 - 0x2000_0FFF  ( 4 KB)            |");
        $display("|     S3  SoCCtrl  0x3000_0000 - 0x3000_0FFF  ( 4 KB)            |");
        $display("|     S4  CLINT    0x4000_0000 - 0x4000_FFFF  (64 KB)            |");
        $display("|     S5  UART     0x5000_0000 - 0x5000_0FFF  ( 4 KB)  [NEW]     |");
        $display("|     S6  GPIO     0x5001_0000 - 0x5001_001F  (32-bit, IRQ)       |");
        $display("|     S7  SPI      0x5002_0000               stub→SLVERR         |");
        $display("|     S8  Timer    0x5003_0000 - 0x5003_002F  (T0/T1/WDT)        |");
        $display("|     S9  PLIC     0x5004_0000 - 0x5004_0FFF  ( 4 KB)  [NEW]     |");
        $display("|     S10 OTP      0x6000_0000               stub→SLVERR         |");
        $display("|     S11 DMA-Cfg  0x6001_0000 - 0x6001_0FFF  ( 4 KB)  [NEW]     |");
        $display("+-----------------------------------------------------------------+");
        $display("|   IRQ routing:  UART/ASCON/DMA → PLIC → CPU.external_irq       |");
        $display("|                 CLINT timer/sw → CPU (bypass PLIC)             |");
        $display("|   Reset:  por_n + ext_rst_n → clk_reset_ctrl →                 |");
        $display("|           fabric_rst_n / cpu_rst_n / periph_rst_n              |");
        $display("|   UART monitor: 8N1, BAUD_DIV=%0d (%.0f baud @ 100 MHz)         |",
                 `BAUD_DIV, 100_000_000.0 / `BAUD_DIV);
        $display("+-----------------------------------------------------------------+");
        $display("|   SoC instances: u_clkrst u_cpu u_icache u_dcache              |");
        $display("|     u_ascon u_width_conv u_crossbar u_imem u_dmem              |");
        $display("|     u_soc_ctrl u_clint u_uart u_plic u_jtag u_dma_ctrl         |");
        $display("|     u_gpio u_timer (real RTL)  u_spi_stub u_otp_stub           |");
        $display("|   GPIO: gpio_in driven from TB  |  WDT: TB intercepts rst_req  |");
        $display("+-----------------------------------------------------------------+");
        $display("|   LOG_LEVEL=%0d   TIMEOUT=%0d cyc   HALT_STABLE=%0d cyc         |",
                 `LOG_LEVEL, `TIMEOUT, `HALT_STABLE);
        $display("+=================================================================+");
        $display("");
    end
endtask

endmodule