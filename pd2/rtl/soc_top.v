`timescale 1ns/1ps

// ============================================================================
// soc_top.v  —  RISC-V Research SoC Top-Level  (Full Integration)
//
// Phiên bản đầy đủ — kết nối toàn bộ các module:
//   ✅ clk_reset_ctrl   — clock/reset an toàn (thay wire fabric_rst_n=ext_rst_n)
//   ✅ riscv_cpu_core   — CPU RV32IM + debug interface
//   ✅ icache_top        — ICache (M0)
//   ✅ dcache_top        — DCache (M1)
//   ✅ ascon_ip_top      — ASCON accelerator (S2, M2 DMA)
//   ✅ axi_width_conv    — 64→32 bit converter cho ASCON DMA
//   ✅ axi4_crossbar_5m12s — crossbar mở rộng (5M × 12S)
//   ✅ inst_mem_axi_slave  — IMEM (S0, SRAM — loaded by boot_ctrl)
//   ✅ data_mem_axi4_slave — DMEM (S1)
//   ✅ soc_ctrl_slave    — SoC Control (S3)
//   ✅ clint             — CLINT (S4)
//   ✅ uart_top          — UART (S5)
//   ✅ plic_top          — PLIC (S9)
//   ✅ jtag_debug_top    — JTAG DTM + DM (M4)
//   ✅ dma_ctrl          — DMA Controller (S11, M3)
//   ✅ boot_ctrl         — Boot Controller (loads IMEM, gates cpu_rst_n)
//   ✅ gpio_top          — GPIO 32-bit (S6)
//   ✅ timer_top         — Timer0/1 + WDT (S8)
//
// Topology Bus:
//   Masters: M0=ICache, M1=DCache, M2=ASCON-DMA, M3=DMA-Ctrl, M4=JTAG-DM
//   Slaves:  S0=IMEM, S1=DMEM, S2=ASCON, S3=SoC-Ctrl, S4=CLINT,
//            S5=UART, S6=GPIO, S7=SPI*, S8=Timer/WDT, S9=PLIC,
//            S10=OTP*, S11=DMA-Ctrl-Config
//   (* = stub/tie-off, chưa có module thực)
//
// IRQ routing:
//   uart_irq    → plic irq_src[1] (tx) / [2] (rx)  [hợp nhất tại plic input]
//   spi_irq     → plic irq_src[3]   (stub=0)
//   gpio_irq    → plic irq_src[4]   (từ gpio_top)
//   timer0_irq  → plic irq_src[5]   (từ timer_top)
//   timer1_irq  → plic irq_src[6]   (từ timer_top)
//   wdt_irq     → plic irq_src[7]   (từ timer_top.wdt_core)
//   ascon_irq   → plic irq_src[8]
//   dma_irq     → plic irq_src[9]
//   plic.meip   → cpu.external_irq
//
// Reset domains (từ clk_reset_ctrl):
//   fabric_rst_n  → crossbar, ICache, DCache, ASCON, SRAM, CLINT, SoC-Ctrl
//   cpu_rst_n     → cpu_rst = ~cpu_rst_n (active-high)
//   periph_rst_n  → UART, PLIC, DMA, JTAG
//
// IO pad:
//   clk, por_n, ext_rst_n,
//   uart_tx, uart_rx,
//   tck, tms, tdi, tdo, tdo_en
// ============================================================================

// ============================================================================
// Include all sub-modules
//
// FIX: Đường dẫn `include phụ thuộc cấu trúc thư mục dự án của bạn.
// Mặc định dùng đường dẫn tương đối từ thư mục gốc dự án.
// Nếu compile từ thư mục khác, điều chỉnh đường dẫn cho phù hợp.
//
// Lệnh compile mẫu (từ thư mục gốc dự án):
//   iverilog -g2005 -I. -o sim.out interconnect/axi4_crossbar_5m12s.v soc_top.v
// Hoặc dùng filelist:
//   iverilog -g2005 -f filelist.f -o sim.out
// ============================================================================
// `include "cpu/riscv_cpu_core_v2.v"
// `include "cache_interface/icache/icache_top.v"
// `include "cache_interface/dcache/dcache_top.v"
// `include "memory/inst_mem_axi_slave.v"
// `include "memory/data_mem_axi_slave.v"
// `include "interconnect/axi4_crossbar_5m12s.v"
// `include "ascon/ascon_top.v"
// `include "axi_width_converter_64to32.v"
// `include "controller/soc_ctrl_slave.v"
// `include "clint.v"
// `include "clk_reset_ctrl/clk_reset_ctrl.v"
// `include "peripheral/uart/uart_top.v"
// `include "plic/plic_top.v"
// `include "jtag/jtag_debug_top.v"
// `include "dma/dma_ctrl.v"
// `include "boot/uart_boot_ctrl.v"
// `include "peripheral/gpio/gpio_top.v"
// `include "peripheral/timer/timer_top.v"
// `include "peripheral/otp/otp_stub_slave.v"
// `include "peripheral/spi/spi_top.v"

module soc_top #(
    // ── AXI parameters ────────────────────────────────────────────────────
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter ID_WIDTH      = 4,

    // ── Memory sizes ──────────────────────────────────────────────────────
    parameter IMEM_SIZE      = 8192,   // 8 KB
    parameter DMEM_SIZE      = 8192,   // 8 KB

    parameter IMEM_INIT_FILE = "memory/program.hex",

    // ── Clock/Reset ───────────────────────────────────────────────────────
    parameter POR_CYCLES       = 1000,  // 10µs @ 100 MHz
    parameter SOFT_RST_STRETCH = 8,

    // ── JTAG IDCODE ───────────────────────────────────────────────────────
    parameter [31:0] JTAG_IDCODE = 32'hDEAD_0001,

    // ── Boot mode ─────────────────────────────────────────────────────────
    parameter        SIM_MODE    = 0,     // 0=UART boot (HW), 1=fast $readmemh (sim)

    // ── Crossbar slave address map (S0–S11) ───────────────────────────────
    parameter [31:0] S0_BASE  = 32'h0000_0000,  // IMEM      8 KB
    parameter [31:0] S0_MASK  = 32'hFFFF_E000,
    parameter [31:0] S1_BASE  = 32'h1000_0000,  // DMEM      8 KB (→64KB mở rộng)
    parameter [31:0] S1_MASK  = 32'hFFFF_E000,
    parameter [31:0] S2_BASE  = 32'h2000_0000,  // ASCON     4 KB
    parameter [31:0] S2_MASK  = 32'hFFFF_F000,
    parameter [31:0] S3_BASE  = 32'h3000_0000,  // SoC Ctrl  4 KB
    parameter [31:0] S3_MASK  = 32'hFFFF_F000,
    parameter [31:0] S4_BASE  = 32'h4000_0000,  // CLINT     64 KB
    parameter [31:0] S4_MASK  = 32'hFFFF_0000,
    parameter [31:0] S5_BASE  = 32'h5000_0000,  // UART      4 KB
    parameter [31:0] S5_MASK  = 32'hFFFF_F000,
    parameter [31:0] S6_BASE  = 32'h5001_0000,  // GPIO      4 KB (stub)
    parameter [31:0] S6_MASK  = 32'hFFFF_F000,
    parameter [31:0] S7_BASE  = 32'h5002_0000,  // SPI       4 KB (stub)
    parameter [31:0] S7_MASK  = 32'hFFFF_F000,
    parameter [31:0] S8_BASE  = 32'h5003_0000,  // Timer/WDT 4 KB (stub)
    parameter [31:0] S8_MASK  = 32'hFFFF_F000,
    parameter [31:0] S9_BASE  = 32'h5004_0000,  // PLIC      4 KB
    parameter [31:0] S9_MASK  = 32'hFFFF_F000,
    parameter [31:0] S10_BASE = 32'h6000_0000,  // OTP       4 KB (stub)
    parameter [31:0] S10_MASK = 32'hFFFF_F000,
    parameter [31:0] S11_BASE = 32'h6001_0000,  // DMA Ctrl  4 KB
    parameter [31:0] S11_MASK = 32'hFFFF_F000
)(
    // ── Clock & Reset IO pads ─────────────────────────────────────────────
    input  wire clk,
    input  wire por_n,         // Power-On Reset từ pad (active-low)
    input  wire ext_rst_n,     // External reset button (active-low)

    // ── UART IO pads ──────────────────────────────────────────────────────
    output wire uart_tx,
    input  wire uart_rx,

    // ── JTAG IO pads ──────────────────────────────────────────────────────
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output wire tdo,
    output wire tdo_en,        // HIGH khi Shift-DR/IR (để điều khiển tri-state pad)

    // ── GPIO IO pads (split in/out/oe cho simulation) ─────────────────────────
    output wire [31:0] gpio_out,   // pad output data
    output wire [31:0] gpio_oe,    // output enable (1=drive, 0=hi-Z)
    input  wire [31:0] gpio_in,    // pad input data

    // ── SPI IO pads ───────────────────────────────────────────────────────────
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire [3:0]  spi_cs_n,

    // ── WDT reset request ─────────────────────────────────────────────────────
    output wire wdt_rst_req        // active-high, từ watchdog
);

// ============================================================================
// SECTION 1: Clock & Reset (từ clk_reset_ctrl)
//
// WHY: Code cũ dùng "wire fabric_rst_n = ext_rst_n" rất nguy hiểm trên silicon:
//   - ext_rst_n từ pad bên ngoài không đồng bộ với clk → metastability
//   - Không có POR stretching → reset có thể release khi VDD chưa ổn định
// clk_reset_ctrl giải quyết bằng 2-FF synchronizer cho mỗi reset domain.
//
// ndmreset: JTAG DM có thể reset CPU (ndmreset=1) mà KHÔNG reset crossbar,
// vì DM cần giữ kết nối AXI (M4) để load chương trình khi CPU đang reset.
// ============================================================================
wire fabric_rst_n;   // reset cho crossbar, cache, SRAM, CLINT, SoC-Ctrl
wire cpu_rst_n;      // reset cho CPU core (bị ảnh hưởng bởi ndmreset)
wire periph_rst_n;   // reset cho UART, PLIC, DMA (bị ảnh hưởng bởi ndmreset)
wire aon_rst_n;      // reset cho AON domain (chỉ POR+ext, không soft/ndm)
wire clk_core;       // gated clock cho CORE domain (CPU + cache + ASCON)
wire clk_periph;     // gated clock cho PERIPH domain (UART, SPI, GPIO, ...)
wire clk_aon;        // always-on clock = clk_in, không bao giờ gate
wire wake_ack;       // periph clock đang chạy → AON có thể clear wake_pend
wire periph_wake_req;// async wake request từ AON domain
wire uart_wake_req;  // AON start-bit FF từ uart_top
wire gpio_wake_req;  // AON edge-detect FF từ gpio_top
wire timer_wake_req; // AON timeout FF từ timer_top
wire soft_rst_pulse; // từ soc_ctrl_slave → clk_reset_ctrl (1-cycle pulse)
wire jtag_ndmreset;  // từ jtag_debug_top → clk_reset_ctrl
wire cpu_wfi;
wire cpu_perf_stall;      // [A2] = stall_any from CPU
wire cpu_perf_instr_ret;  // [A2] = regwrite_wb && !stall_any from CPU
wire uart_active;
wire timer_active;
wire gpio_wake_armed;
wire dma_busy;
// DMA peripheral handshake
// CH0: UART RX (periph-to-mem),  CH1: UART TX (mem-to-periph)
// CH2: SPI  RX (periph-to-mem),  CH3: SPI  TX (mem-to-periph)
wire uart_tx_dma_req, uart_rx_dma_req;
wire spi_tx_dma_req,  spi_rx_dma_req;
wire [3:0] dma_periph_req;
wire [3:0] dma_periph_ack;
assign dma_periph_req = {spi_tx_dma_req, spi_rx_dma_req,
                         uart_tx_dma_req, uart_rx_dma_req};
wire spi_irq;
wire core_bus_active;
wire core_wake_event;
wire periph_bus_active;
wire periph_busy;
wire periph_wake_event;
wire periph_gate_allow;

// Declare missing implicit wires
wire boot_done;
wire ascon_o_busy;
wire imem_boot_we;
wire [31:0] imem_boot_addr;
wire [31:0] imem_boot_wdata;

// WHY cpu_rst active-high: riscv_cpu_core dùng "rst" active-high convention
wire cpu_rst = ~cpu_rst_n;

clk_reset_ctrl #(
    .POR_CYCLES       (POR_CYCLES),
    .SOFT_RST_STRETCH (SOFT_RST_STRETCH)
) u_clkrst (
    .clk_in        (clk),
    .por_n         (por_n),
    .ext_rst_n     (ext_rst_n),
    .soft_rst_pulse(soft_rst_pulse),
    .ndmreset      (jtag_ndmreset), // JTAG DM → reset CPU+periph không reset fabric
    .boot_done     (boot_done),     // boot_ctrl → giữ cpu_rst_n cho đến khi IMEM loaded
    .test_en       (1'b0),
    .core_clk_en   (1'b1),
    .periph_clk_en (1'b1),
    .cpu_wfi       (cpu_wfi),
    .ascon_busy    (ascon_o_busy),
    .core_bus_active(core_bus_active),
    .core_wake_event(core_wake_event),
    .periph_bus_active(periph_bus_active),
    .periph_busy      (periph_busy),
    .periph_wake_event(periph_wake_event),
    .periph_gate_allow(periph_gate_allow),
    .periph_wake_req  (periph_wake_req),
    .clk_core         (clk_core),
    .clk_periph       (clk_periph),
    .clk_aon          (clk_aon),
    .fabric_rst_n     (fabric_rst_n),
    .cpu_rst_n        (cpu_rst_n),
    .periph_rst_n     (periph_rst_n),
    .aon_rst_n        (aon_rst_n),
    .wake_ack         (wake_ack)
);

// ============================================================================
// SECTION 1b: Boot Controller
//
// Chạy trên fabric_rst_n (giống crossbar). Copies boot ROM → IMEM via sideband
// port. Sau khi xong, asserts boot_done → clk_reset_ctrl releases cpu_rst_n.
// CPU chỉ bắt đầu fetch khi IMEM đã có nội dung hợp lệ.
// ============================================================================
uart_boot_ctrl #(
    .SIM_MODE   (SIM_MODE),
    .BOOT_FILE  (IMEM_INIT_FILE),
    .PROG_WORDS (IMEM_SIZE / 4)
) u_boot (
    .clk        (clk),
    .rst_n      (fabric_rst_n),
    .uart_rx    (uart_rx),        // shared với u_uart (S5 ở periph_rst=0 trong boot)
    .boot_we    (imem_boot_we),
    .boot_addr  (imem_boot_addr),
    .boot_wdata (imem_boot_wdata),
    .boot_done  (boot_done)
);

// ============================================================================
// SECTION 2: mtime_tick prescaler — 100 MHz → 1 MHz (chu kỳ 1µs)
//
// WHY: CLINT.mtime đếm theo µs (RISC-V spec yêu cầu). Prescaler chia 100
// cho clock 100 MHz để tạo tick 1 MHz đưa vào CLINT.
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
// SECTION 3: CPU ↔ ICache / DCache wires
// ============================================================================
wire [31:0] cpu_imem_addr;
wire        cpu_imem_valid;
wire [31:0] icache_imem_rdata;
wire        icache_imem_ready;

wire [31:0] cpu_dcache_addr;
wire [31:0] cpu_dcache_wdata;
wire [3:0]  cpu_dcache_wstrb;
wire        cpu_dcache_req;
wire        cpu_dcache_we;
wire [31:0] dcache_cpu_rdata;
wire        dcache_cpu_ready;
wire [1:0]  cpu_dcache_fence_type;

assign core_bus_active =
    m0_arvalid | m0_awvalid | m0_wvalid | m0_rvalid | m0_bvalid |
    m1_arvalid | m1_awvalid | m1_wvalid | m1_rvalid | m1_bvalid |
    m2_arvalid | m2_awvalid | m2_wvalid | m2_rvalid | m2_bvalid;

// ============================================================================
// SECTION 4: Interrupt wires
//
// WHY cấu trúc IRQ:
//   Tất cả peripheral IRQ → PLIC → meip → CPU.external_irq
//   SOC CTRL giữ irq_out wire nhưng không kết nối vào CPU nữa (PLIC thay thế).
//   CLINT timer_irq / sw_irq đi thẳng vào CPU (theo spec RISC-V, CLINT bypass PLIC).
// ============================================================================
wire external_irq;   // PLIC.meip → CPU (machine external interrupt)
wire timer_irq;      // CLINT → CPU (machine timer interrupt)
wire sw_irq;         // CLINT → CPU (machine software interrupt)
wire ascon_irq;      // ASCON → PLIC source[8]
wire uart_irq;       // UART  → PLIC source[1] (tx) & [2] (rx) — hợp nhất 1 wire
wire dma_irq;        // DMA   → PLIC source[9]
wire gpio_irq;       // GPIO  → PLIC source[4]
wire timer0_irq;     // Timer0 → PLIC source[5]
wire timer1_irq;     // Timer1 → PLIC source[6]
wire wdt_irq;        // WDT   → PLIC source[7]
wire soc_ctrl_irq_out; // soc_ctrl_slave.irq_out — giữ lại để tương thích,
                       // nhưng không dùng làm external_irq (PLIC đảm nhiệm)

assign core_wake_event = external_irq | timer_irq | sw_irq |
                         jtag_haltreq | jtag_resumereq | jtag_ndmreset |
                         !boot_done;

assign periph_bus_active =
    s5_awvalid | s5_wvalid | s5_arvalid | s5_bvalid | s5_rvalid |
    s6_awvalid | s6_wvalid | s6_arvalid | s6_bvalid | s6_rvalid |
    s8_awvalid | s8_wvalid | s8_arvalid | s8_bvalid | s8_rvalid |
    s9_awvalid | s9_wvalid | s9_arvalid | s9_bvalid | s9_rvalid |
    s11_awvalid | s11_wvalid | s11_arvalid | s11_bvalid | s11_rvalid |
    m3_arvalid | m3_awvalid | m3_wvalid | m3_rvalid | m3_bvalid;

assign periph_busy = uart_active | timer_active | dma_busy |
                     uart_irq | gpio_irq | timer0_irq | timer1_irq | wdt_irq |
                     external_irq;

assign periph_wake_event = uart_irq | gpio_irq | timer0_irq | timer1_irq |
                           wdt_irq | dma_irq | external_irq |
                           !uart_rx | jtag_haltreq | jtag_resumereq | jtag_ndmreset;

assign periph_gate_allow = !timer_active && !gpio_wake_armed && !dma_busy;

// periph_wake_req: chỉ dùng AON-domain FF outputs — valid kể cả khi clk_periph gate.
assign periph_wake_req = uart_wake_req | gpio_wake_req | timer_wake_req | external_irq;

// ── Boot controller signal ────────────────────────────────────────────────────
// (Wires declared at the top of the file to fix implicit definition warning)

// ============================================================================
// SECTION 5: JTAG Debug wires
// ============================================================================
wire jtag_haltreq;
wire jtag_resumereq;
wire jtag_halted;
wire jtag_running;

// ============================================================================
// SECTION 6: ASCON AXI-Stream wires (tied off — SoC không dùng stream mode)
// // ============================================================================
// wire [63:0] ascon_s_axis_tdata  = 64'h0;
// wire        ascon_s_axis_tvalid = 1'b0;
// wire        ascon_s_axis_tlast  = 1'b0;
// wire        ascon_s_axis_tready;   // output — không kết nối upstream

// wire [63:0] ascon_m_axis_tdata;
// wire        ascon_m_axis_tvalid;
// wire        ascon_m_axis_tlast;
// wire        ascon_m_axis_tready = 1'b1;  // luôn consume

wire [127:0] ascon_o_tag;
wire         ascon_o_tag_valid;
// ascon_o_busy declared at the top

// ============================================================================
// SECTION 7: Cache statistics wires
// ============================================================================
wire [31:0] icache_stat_hits;
wire [31:0] icache_stat_misses;
wire [31:0] dcache_stat_hits;
wire [31:0] dcache_stat_misses;
wire [31:0] dcache_stat_writes;

// ============================================================================
// SECTION 8: AXI4 Master wires (M0–M4)
//
// Naming convention: m{N}_{signal}
//   M0 = ICache, M1 = DCache, M2 = ASCON-DMA (32b), M3 = DMA-Ctrl, M4 = JTAG-DM
// ============================================================================

// ── M0: ICache ──────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]   m0_arid,  m0_awid,  m0_bid,  m0_rid;
wire [ADDR_WIDTH-1:0] m0_araddr, m0_awaddr;
wire [7:0]            m0_arlen,  m0_awlen;
wire [2:0]            m0_arsize, m0_awsize;
wire [1:0]            m0_arburst, m0_awburst;
wire [2:0]            m0_arprot, m0_awprot;
wire                  m0_arvalid, m0_arready;
wire                  m0_awvalid, m0_awready;
wire [DATA_WIDTH-1:0] m0_rdata,   m0_wdata;
wire [DATA_WIDTH/8-1:0] m0_wstrb;
wire [1:0]            m0_rresp,  m0_bresp;
wire                  m0_rlast,  m0_wlast;
wire                  m0_rvalid, m0_rready;
wire                  m0_wvalid, m0_wready;
wire                  m0_bvalid, m0_bready;

// ── M1: DCache ──────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]   m1_arid,  m1_awid,  m1_bid,  m1_rid;
wire [ADDR_WIDTH-1:0] m1_araddr, m1_awaddr;
wire [7:0]            m1_arlen,  m1_awlen;
wire [2:0]            m1_arsize, m1_awsize;
wire [1:0]            m1_arburst, m1_awburst;
wire [2:0]            m1_arprot, m1_awprot;
wire                  m1_arvalid, m1_arready;
wire                  m1_awvalid, m1_awready;
wire [DATA_WIDTH-1:0] m1_rdata,   m1_wdata;
wire [DATA_WIDTH/8-1:0] m1_wstrb;
wire [1:0]            m1_rresp,  m1_bresp;
wire                  m1_rlast,  m1_wlast;
wire                  m1_rvalid, m1_rready;
wire                  m1_wvalid, m1_wready;
wire                  m1_bvalid, m1_bready;

// ── M2: ASCON DMA (32-bit, saụ width converter) ──────────────────────────────
wire [ID_WIDTH-1:0]   m2_arid,  m2_awid,  m2_bid,  m2_rid;
wire [ADDR_WIDTH-1:0] m2_araddr, m2_awaddr;
wire [7:0]            m2_arlen,  m2_awlen;
wire [2:0]            m2_arsize, m2_awsize;
wire [1:0]            m2_arburst, m2_awburst;
wire [2:0]            m2_arprot, m2_awprot;
wire                  m2_arvalid, m2_arready;
wire                  m2_awvalid, m2_awready;
wire [DATA_WIDTH-1:0] m2_rdata,   m2_wdata;
wire [DATA_WIDTH/8-1:0] m2_wstrb;
wire [1:0]            m2_rresp,  m2_bresp;
wire                  m2_rlast,  m2_wlast;
wire                  m2_rvalid, m2_rready;
wire                  m2_wvalid, m2_wready;
wire                  m2_bvalid, m2_bready;

// ── M3: DMA Controller ───────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]   m3_arid,  m3_awid,  m3_bid,  m3_rid;
wire [ADDR_WIDTH-1:0] m3_araddr, m3_awaddr;
wire [7:0]            m3_arlen,  m3_awlen;
wire [2:0]            m3_arsize, m3_awsize;
wire [1:0]            m3_arburst, m3_awburst;
wire [2:0]            m3_arprot, m3_awprot;
wire                  m3_arvalid, m3_arready;
wire                  m3_awvalid, m3_awready;
wire [DATA_WIDTH-1:0] m3_rdata,   m3_wdata;
wire [DATA_WIDTH/8-1:0] m3_wstrb;
wire [1:0]            m3_rresp,  m3_bresp;
wire                  m3_rlast,  m3_wlast;
wire                  m3_rvalid, m3_rready;
wire                  m3_wvalid, m3_wready;
wire                  m3_bvalid, m3_bready;

// ── M4: JTAG Debug Module ────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]   m4_arid,  m4_awid,  m4_bid,  m4_rid;
wire [ADDR_WIDTH-1:0] m4_araddr, m4_awaddr;
wire [7:0]            m4_arlen,  m4_awlen;
wire [2:0]            m4_arsize, m4_awsize;
wire [1:0]            m4_arburst, m4_awburst;
wire [2:0]            m4_arprot, m4_awprot;
wire                  m4_arvalid, m4_arready;
wire                  m4_awvalid, m4_awready;
wire [DATA_WIDTH-1:0] m4_rdata,   m4_wdata;
wire [DATA_WIDTH/8-1:0] m4_wstrb;
wire [1:0]            m4_rresp,  m4_bresp;
wire                  m4_rlast,  m4_wlast;
wire                  m4_rvalid, m4_rready;
wire                  m4_wvalid, m4_wready;
wire                  m4_bvalid, m4_bready;

// ============================================================================
// SECTION 9: ASCON DMA 64-bit master wires (trước width converter)
// ============================================================================
wire [ID_WIDTH-1:0]   dma_awid,  dma_arid,  dma_bid,  dma_rid;
wire [ADDR_WIDTH-1:0] dma_awaddr, dma_araddr;
wire [7:0]            dma_awlen,  dma_arlen;
wire [2:0]            dma_awsize, dma_arsize;
wire [1:0]            dma_awburst, dma_arburst;
wire [3:0]            dma_awcache, dma_arcache;
wire [2:0]            dma_awprot, dma_arprot;
wire                  dma_awvalid, dma_awready;
wire                  dma_arvalid, dma_arready;
wire [63:0]           dma_wdata;
wire [7:0]            dma_wstrb;
wire                  dma_wlast,  dma_wvalid, dma_wready;
wire [1:0]            dma_bresp,  dma_rresp;
wire                  dma_bvalid, dma_bready;
wire [63:0]           dma_rdata;
wire                  dma_rlast,  dma_rvalid, dma_rready;

// ============================================================================
// SECTION 10: AXI4 Slave wires (S0–S11) — khai báo tường minh
//
// FIX: Macro DECL_SLAVE_WIRES dùng token-pasting (s``N``_arid) không hoạt
// động trên Icarus Verilog. Khai báo tường minh từng slave.
// Naming: s{N}_{signal}
// ============================================================================

// ── S0: IMEM ─────────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s0_arid,  s0_awid,  s0_bid,  s0_rid;
wire [ADDR_WIDTH-1:0]   s0_araddr, s0_awaddr;
wire [7:0]              s0_arlen,  s0_awlen;
wire [2:0]              s0_arsize, s0_awsize;
wire [1:0]              s0_arburst, s0_awburst;
wire [2:0]              s0_arprot,  s0_awprot;
wire                    s0_arvalid, s0_arready;
wire                    s0_awvalid, s0_awready;
wire [DATA_WIDTH-1:0]   s0_rdata,   s0_wdata;
wire [DATA_WIDTH/8-1:0] s0_wstrb;
wire [1:0]              s0_rresp,   s0_bresp;
wire                    s0_rlast,   s0_wlast;
wire                    s0_rvalid,  s0_rready;
wire                    s0_wvalid,  s0_wready;
wire                    s0_bvalid,  s0_bready;

// ── S1: DMEM ─────────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s1_arid,  s1_awid,  s1_bid,  s1_rid;
wire [ADDR_WIDTH-1:0]   s1_araddr, s1_awaddr;
wire [7:0]              s1_arlen,  s1_awlen;
wire [2:0]              s1_arsize, s1_awsize;
wire [1:0]              s1_arburst, s1_awburst;
wire [2:0]              s1_arprot,  s1_awprot;
wire                    s1_arvalid, s1_arready;
wire                    s1_awvalid, s1_awready;
wire [DATA_WIDTH-1:0]   s1_rdata,   s1_wdata;
wire [DATA_WIDTH/8-1:0] s1_wstrb;
wire [1:0]              s1_rresp,   s1_bresp;
wire                    s1_rlast,   s1_wlast;
wire                    s1_rvalid,  s1_rready;
wire                    s1_wvalid,  s1_wready;
wire                    s1_bvalid,  s1_bready;

// ── S2: ASCON ─────────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s2_arid,  s2_awid,  s2_bid,  s2_rid;
wire [ADDR_WIDTH-1:0]   s2_araddr, s2_awaddr;
wire [7:0]              s2_arlen,  s2_awlen;
wire [2:0]              s2_arsize, s2_awsize;
wire [1:0]              s2_arburst, s2_awburst;
wire [2:0]              s2_arprot,  s2_awprot;
wire                    s2_arvalid, s2_arready;
wire                    s2_awvalid, s2_awready;
wire [DATA_WIDTH-1:0]   s2_rdata,   s2_wdata;
wire [DATA_WIDTH/8-1:0] s2_wstrb;
wire [1:0]              s2_rresp,   s2_bresp;
wire                    s2_rlast,   s2_wlast;
wire                    s2_rvalid,  s2_rready;
wire                    s2_wvalid,  s2_wready;
wire                    s2_bvalid,  s2_bready;

// ── S3: SoC CTRL ──────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s3_arid,  s3_awid,  s3_bid,  s3_rid;
wire [ADDR_WIDTH-1:0]   s3_araddr, s3_awaddr;
wire [7:0]              s3_arlen,  s3_awlen;
wire [2:0]              s3_arsize, s3_awsize;
wire [1:0]              s3_arburst, s3_awburst;
wire [2:0]              s3_arprot,  s3_awprot;
wire                    s3_arvalid, s3_arready;
wire                    s3_awvalid, s3_awready;
wire [DATA_WIDTH-1:0]   s3_rdata,   s3_wdata;
wire [DATA_WIDTH/8-1:0] s3_wstrb;
wire [1:0]              s3_rresp,   s3_bresp;
wire                    s3_rlast,   s3_wlast;
wire                    s3_rvalid,  s3_rready;
wire                    s3_wvalid,  s3_wready;
wire                    s3_bvalid,  s3_bready;

// ── S4: CLINT ─────────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s4_arid,  s4_awid,  s4_bid,  s4_rid;
wire [ADDR_WIDTH-1:0]   s4_araddr, s4_awaddr;
wire [7:0]              s4_arlen,  s4_awlen;
wire [2:0]              s4_arsize, s4_awsize;
wire [1:0]              s4_arburst, s4_awburst;
wire [2:0]              s4_arprot,  s4_awprot;
wire                    s4_arvalid, s4_arready;
wire                    s4_awvalid, s4_awready;
wire [DATA_WIDTH-1:0]   s4_rdata,   s4_wdata;
wire [DATA_WIDTH/8-1:0] s4_wstrb;
wire [1:0]              s4_rresp,   s4_bresp;
wire                    s4_rlast,   s4_wlast;
wire                    s4_rvalid,  s4_rready;
wire                    s4_wvalid,  s4_wready;
wire                    s4_bvalid,  s4_bready;

// ── S5: UART ──────────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s5_arid,  s5_awid,  s5_bid,  s5_rid;
wire [ADDR_WIDTH-1:0]   s5_araddr, s5_awaddr;
wire [7:0]              s5_arlen,  s5_awlen;
wire [2:0]              s5_arsize, s5_awsize;
wire [1:0]              s5_arburst, s5_awburst;
wire [2:0]              s5_arprot,  s5_awprot;
wire                    s5_arvalid, s5_arready;
wire                    s5_awvalid, s5_awready;
wire [DATA_WIDTH-1:0]   s5_rdata,   s5_wdata;
wire [DATA_WIDTH/8-1:0] s5_wstrb;
wire [1:0]              s5_rresp,   s5_bresp;
wire                    s5_rlast,   s5_wlast;
wire                    s5_rvalid,  s5_rready;
wire                    s5_wvalid,  s5_wready;
wire                    s5_bvalid,  s5_bready;

// ── S6: GPIO (stub) ───────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s6_arid,  s6_awid,  s6_bid,  s6_rid;
wire [ADDR_WIDTH-1:0]   s6_araddr, s6_awaddr;
wire [7:0]              s6_arlen,  s6_awlen;
wire [2:0]              s6_arsize, s6_awsize;
wire [1:0]              s6_arburst, s6_awburst;
wire [2:0]              s6_arprot,  s6_awprot;
wire                    s6_arvalid, s6_arready;
wire                    s6_awvalid, s6_awready;
wire [DATA_WIDTH-1:0]   s6_rdata,   s6_wdata;
wire [DATA_WIDTH/8-1:0] s6_wstrb;
wire [1:0]              s6_rresp,   s6_bresp;
wire                    s6_rlast,   s6_wlast;
wire                    s6_rvalid,  s6_rready;
wire                    s6_wvalid,  s6_wready;
wire                    s6_bvalid,  s6_bready;

// ── S7: SPI (stub) ────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s7_arid,  s7_awid,  s7_bid,  s7_rid;
wire [ADDR_WIDTH-1:0]   s7_araddr, s7_awaddr;
wire [7:0]              s7_arlen,  s7_awlen;
wire [2:0]              s7_arsize, s7_awsize;
wire [1:0]              s7_arburst, s7_awburst;
wire [2:0]              s7_arprot,  s7_awprot;
wire                    s7_arvalid, s7_arready;
wire                    s7_awvalid, s7_awready;
wire [DATA_WIDTH-1:0]   s7_rdata,   s7_wdata;
wire [DATA_WIDTH/8-1:0] s7_wstrb;
wire [1:0]              s7_rresp,   s7_bresp;
wire                    s7_rlast,   s7_wlast;
wire                    s7_rvalid,  s7_rready;
wire                    s7_wvalid,  s7_wready;
wire                    s7_bvalid,  s7_bready;

// ── S8: Timer/WDT (stub) ──────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s8_arid,  s8_awid,  s8_bid,  s8_rid;
wire [ADDR_WIDTH-1:0]   s8_araddr, s8_awaddr;
wire [7:0]              s8_arlen,  s8_awlen;
wire [2:0]              s8_arsize, s8_awsize;
wire [1:0]              s8_arburst, s8_awburst;
wire [2:0]              s8_arprot,  s8_awprot;
wire                    s8_arvalid, s8_arready;
wire                    s8_awvalid, s8_awready;
wire [DATA_WIDTH-1:0]   s8_rdata,   s8_wdata;
wire [DATA_WIDTH/8-1:0] s8_wstrb;
wire [1:0]              s8_rresp,   s8_bresp;
wire                    s8_rlast,   s8_wlast;
wire                    s8_rvalid,  s8_rready;
wire                    s8_wvalid,  s8_wready;
wire                    s8_bvalid,  s8_bready;

// ── S9: PLIC ──────────────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s9_arid,  s9_awid,  s9_bid,  s9_rid;
wire [ADDR_WIDTH-1:0]   s9_araddr, s9_awaddr;
wire [7:0]              s9_arlen,  s9_awlen;
wire [2:0]              s9_arsize, s9_awsize;
wire [1:0]              s9_arburst, s9_awburst;
wire [2:0]              s9_arprot,  s9_awprot;
wire                    s9_arvalid, s9_arready;
wire                    s9_awvalid, s9_awready;
wire [DATA_WIDTH-1:0]   s9_rdata,   s9_wdata;
wire [DATA_WIDTH/8-1:0] s9_wstrb;
wire [1:0]              s9_rresp,   s9_bresp;
wire                    s9_rlast,   s9_wlast;
wire                    s9_rvalid,  s9_rready;
wire                    s9_wvalid,  s9_wready;
wire                    s9_bvalid,  s9_bready;

// ── S10: OTP (stub) ───────────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s10_arid,  s10_awid,  s10_bid,  s10_rid;
wire [ADDR_WIDTH-1:0]   s10_araddr, s10_awaddr;
wire [7:0]              s10_arlen,  s10_awlen;
wire [2:0]              s10_arsize, s10_awsize;
wire [1:0]              s10_arburst, s10_awburst;
wire [2:0]              s10_arprot,  s10_awprot;
wire                    s10_arvalid, s10_arready;
wire                    s10_awvalid, s10_awready;
wire [DATA_WIDTH-1:0]   s10_rdata,   s10_wdata;
wire [DATA_WIDTH/8-1:0] s10_wstrb;
wire [1:0]              s10_rresp,   s10_bresp;
wire                    s10_rlast,   s10_wlast;
wire                    s10_rvalid,  s10_rready;
wire                    s10_wvalid,  s10_wready;
wire                    s10_bvalid,  s10_bready;

// ── S11: DMA Ctrl Config ──────────────────────────────────────────────────────
wire [ID_WIDTH-1:0]     s11_arid,  s11_awid,  s11_bid,  s11_rid;
wire [ADDR_WIDTH-1:0]   s11_araddr, s11_awaddr;
wire [7:0]              s11_arlen,  s11_awlen;
wire [2:0]              s11_arsize, s11_awsize;
wire [1:0]              s11_arburst, s11_awburst;
wire [2:0]              s11_arprot,  s11_awprot;
wire                    s11_arvalid, s11_arready;
wire                    s11_awvalid, s11_awready;
wire [DATA_WIDTH-1:0]   s11_rdata,   s11_wdata;
wire [DATA_WIDTH/8-1:0] s11_wstrb;
wire [1:0]              s11_rresp,   s11_bresp;
wire                    s11_rlast,   s11_wlast;
wire                    s11_rvalid,  s11_rready;
wire                    s11_wvalid,  s11_wready;
wire                    s11_bvalid,  s11_bready;

// ============================================================================
// SECTION 11: Stub slaves — GPIO, SPI, Timer/WDT, OTP
//
// WHY stub: Các module này chưa có RTL. Thay vì để floating, gán
// DECERR response để CPU nhận lỗi rõ ràng khi access vào các địa chỉ này.
// Stub đủ đơn giản để synthesize an toàn.
//
// Stub pattern: awready/wready/arready=1 (accept ngay), bresp=SLVERR,
// rresp=SLVERR, bvalid/rvalid pulse sau 1 cycle.
// ============================================================================

// ── S6: GPIO ──────────────────────────────────────────────────────────────────
gpio_top #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .GPIO_WIDTH (32)
) u_gpio (
    .clk           (clk_periph),
    .rst_n         (periph_rst_n),
    .S_AXI_AWID    (s6_awid),   .S_AXI_AWADDR  (s6_awaddr),
    .S_AXI_AWLEN   (s6_awlen),  .S_AXI_AWSIZE  (s6_awsize),
    .S_AXI_AWBURST (s6_awburst),.S_AXI_AWPROT  (s6_awprot),
    .S_AXI_AWVALID (s6_awvalid),.S_AXI_AWREADY (s6_awready),
    .S_AXI_WDATA   (s6_wdata),  .S_AXI_WSTRB   (s6_wstrb),
    .S_AXI_WLAST   (s6_wlast),  .S_AXI_WVALID  (s6_wvalid),
    .S_AXI_WREADY  (s6_wready),
    .S_AXI_BID     (s6_bid),    .S_AXI_BRESP   (s6_bresp),
    .S_AXI_BVALID  (s6_bvalid), .S_AXI_BREADY  (s6_bready),
    .S_AXI_ARID    (s6_arid),   .S_AXI_ARADDR  (s6_araddr),
    .S_AXI_ARLEN   (s6_arlen),  .S_AXI_ARSIZE  (s6_arsize),
    .S_AXI_ARBURST (s6_arburst),.S_AXI_ARPROT  (s6_arprot),
    .S_AXI_ARVALID (s6_arvalid),.S_AXI_ARREADY (s6_arready),
    .S_AXI_RID     (s6_rid),    .S_AXI_RDATA   (s6_rdata),
    .S_AXI_RRESP   (s6_rresp),  .S_AXI_RLAST   (s6_rlast),
    .S_AXI_RVALID  (s6_rvalid), .S_AXI_RREADY  (s6_rready),
    .gpio_out      (gpio_out),
    .gpio_oe       (gpio_oe),
    .gpio_in       (gpio_in),
    .gpio_irq      (gpio_irq),
    .gpio_wake_armed_o(gpio_wake_armed),
    .clk_aon       (clk_aon),
    .aon_rst_n     (aon_rst_n),
    .wake_ack      (wake_ack),
    .gpio_wake_req (gpio_wake_req)
);

// ── S7: SPI Master ────────────────────────────────────────────────────────────
spi_top #(
    .AXI_ADDR_WIDTH(ADDR_WIDTH),
    .AXI_DATA_WIDTH(DATA_WIDTH),
    .AXI_ID_WIDTH  (ID_WIDTH)
) u_spi (
    .clk           (clk_periph),
    .rst_n         (periph_rst_n),
    .s_axi_awid    (s7_awid),    .s_axi_awaddr  (s7_awaddr),
    .s_axi_awlen   (s7_awlen),   .s_axi_awsize  (s7_awsize),
    .s_axi_awburst (s7_awburst), .s_axi_awvalid (s7_awvalid),
    .s_axi_awready (s7_awready),
    .s_axi_wdata   (s7_wdata),   .s_axi_wstrb   (s7_wstrb),
    .s_axi_wlast   (s7_wlast),   .s_axi_wvalid  (s7_wvalid),
    .s_axi_wready  (s7_wready),
    .s_axi_bid     (s7_bid),     .s_axi_bresp   (s7_bresp),
    .s_axi_bvalid  (s7_bvalid),  .s_axi_bready  (s7_bready),
    .s_axi_arid    (s7_arid),    .s_axi_araddr  (s7_araddr),
    .s_axi_arlen   (s7_arlen),   .s_axi_arsize  (s7_arsize),
    .s_axi_arburst (s7_arburst), .s_axi_arvalid (s7_arvalid),
    .s_axi_arready (s7_arready),
    .s_axi_rid     (s7_rid),     .s_axi_rdata   (s7_rdata),
    .s_axi_rresp   (s7_rresp),   .s_axi_rlast   (s7_rlast),
    .s_axi_rvalid  (s7_rvalid),  .s_axi_rready  (s7_rready),
    .sck           (spi_sck),
    .mosi          (spi_mosi),
    .miso          (spi_miso),
    .cs_n          (spi_cs_n),
    .irq_out       (spi_irq),
    .tx_dma_req    (spi_tx_dma_req),
    .rx_dma_req    (spi_rx_dma_req)
);

// ── S8: Timer/WDT ────────────────────────────────────────────────────────────
timer_top #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_timer (
    .clk           (clk_periph),
    .rst_n         (periph_rst_n),
    .S_AXI_AWID    (s8_awid),   .S_AXI_AWADDR  (s8_awaddr),
    .S_AXI_AWLEN   (s8_awlen),  .S_AXI_AWSIZE  (s8_awsize),
    .S_AXI_AWBURST (s8_awburst),.S_AXI_AWPROT  (s8_awprot),
    .S_AXI_AWVALID (s8_awvalid),.S_AXI_AWREADY (s8_awready),
    .S_AXI_WDATA   (s8_wdata),  .S_AXI_WSTRB   (s8_wstrb),
    .S_AXI_WLAST   (s8_wlast),  .S_AXI_WVALID  (s8_wvalid),
    .S_AXI_WREADY  (s8_wready),
    .S_AXI_BID     (s8_bid),    .S_AXI_BRESP   (s8_bresp),
    .S_AXI_BVALID  (s8_bvalid), .S_AXI_BREADY  (s8_bready),
    .S_AXI_ARID    (s8_arid),   .S_AXI_ARADDR  (s8_araddr),
    .S_AXI_ARLEN   (s8_arlen),  .S_AXI_ARSIZE  (s8_arsize),
    .S_AXI_ARBURST (s8_arburst),.S_AXI_ARPROT  (s8_arprot),
    .S_AXI_ARVALID (s8_arvalid),.S_AXI_ARREADY (s8_arready),
    .S_AXI_RID     (s8_rid),    .S_AXI_RDATA   (s8_rdata),
    .S_AXI_RRESP   (s8_rresp),  .S_AXI_RLAST   (s8_rlast),
    .S_AXI_RVALID  (s8_rvalid), .S_AXI_RREADY  (s8_rready),
    .timer0_irq    (timer0_irq),
    .timer1_irq    (timer1_irq),
    .wdt_irq       (wdt_irq),
    .wdt_rst_req   (wdt_rst_req),
    .timer_active_o(timer_active),
    .clk_aon       (clk_aon),
    .aon_rst_n     (aon_rst_n),
    .wake_ack      (wake_ack),
    .timer_wake_req(timer_wake_req)
);

// ── S10: OTP stub (DEVICE_ID=0xA5C0_CAFE, VER=1, others=0xDEADBEEF) ────────
otp_stub_slave #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
) u_otp_stub (
    .clk      (clk),
    .rst_n    (fabric_rst_n),
    .s_arid   (s10_arid),   .s_araddr (s10_araddr), .s_arlen  (s10_arlen),
    .s_arsize (s10_arsize), .s_arburst(s10_arburst),
    .s_arvalid(s10_arvalid),.s_arready(s10_arready),
    .s_rid    (s10_rid),    .s_rdata  (s10_rdata),  .s_rresp  (s10_rresp),
    .s_rlast  (s10_rlast),  .s_rvalid (s10_rvalid), .s_rready (s10_rready),
    .s_awid   (s10_awid),   .s_awaddr (s10_awaddr), .s_awlen  (s10_awlen),
    .s_awvalid(s10_awvalid),.s_awready(s10_awready),
    .s_wdata  (s10_wdata),  .s_wstrb  (s10_wstrb),
    .s_wlast  (s10_wlast),  .s_wvalid (s10_wvalid), .s_wready (s10_wready),
    .s_bid    (s10_bid),    .s_bresp  (s10_bresp),
    .s_bvalid (s10_bvalid), .s_bready (s10_bready)
);

// ============================================================================
// SECTION 12: INSTANCE — riscv_cpu_core  (RV32IM)
//
// WHY dùng clk_core thay vì clk: clk_core qua ICG cell — có thể gate khi
// chip vào sleep mode. Hiện tại core_clk_en=1 nên clk_core ≡ clk.
//
// WHY debug_haltreq/resumereq: JTAG DM cần pause CPU để đọc register file
// mà không dùng reset. Khi halted, CPU đóng băng pipeline nhưng giữ
// nguyên PC và register state — debugger có thể inspect và tiếp tục.
// ============================================================================
riscv_cpu_core u_cpu (
    .clk             (clk_core),
    .rst             (cpu_rst),

    .imem_addr       (cpu_imem_addr),
    .imem_valid      (cpu_imem_valid),
    .imem_rdata      (icache_imem_rdata),
    .imem_ready      (icache_imem_ready),

    .dcache_addr     (cpu_dcache_addr),
    .dcache_wdata    (cpu_dcache_wdata),
    .dcache_wstrb    (cpu_dcache_wstrb),
    .dcache_req      (cpu_dcache_req),
    .dcache_we       (cpu_dcache_we),
    .dcache_rdata    (dcache_cpu_rdata),
    .dcache_ready    (dcache_cpu_ready),
    .dcache_fence_type(cpu_dcache_fence_type),

    .external_irq    (external_irq),   // ← từ PLIC.meip
    .timer_irq       (timer_irq),      // ← từ CLINT
    .sw_irq          (sw_irq),         // ← từ CLINT

    .debug_haltreq   (jtag_haltreq),
    .debug_resumereq (jtag_resumereq),
    .debug_halted    (jtag_halted),
    .debug_running   (jtag_running),
    .cpu_wfi_o       (cpu_wfi),
    .perf_stall_o    (cpu_perf_stall),
    .perf_instr_ret_o(cpu_perf_instr_ret)
);

// ============================================================================
// SECTION 13: INSTANCE — icache_top  (Master M0)
// ============================================================================
icache_top u_icache (
    .clk         (clk_core),
    .rst_n       (cpu_rst_n),    // must use cpu_rst_n: keeps ICache in reset until boot_ctrl finishes loading IMEM

    .cpu_addr    (cpu_imem_addr),
    .cpu_req     (cpu_imem_valid),
    .cpu_rdata   (icache_imem_rdata),
    .cpu_ready   (icache_imem_ready),
    .flush       (1'b0),

    .mem_arid    (m0_arid),   .mem_araddr (m0_araddr),
    .mem_arlen   (m0_arlen),  .mem_arsize (m0_arsize),
    .mem_arburst (m0_arburst),.mem_arprot (m0_arprot),
    .mem_arvalid (m0_arvalid),.mem_arready(m0_arready),
    .mem_rid     (m0_rid),    .mem_rdata  (m0_rdata),
    .mem_rresp   (m0_rresp),  .mem_rlast  (m0_rlast),
    .mem_rvalid  (m0_rvalid), .mem_rready (m0_rready),
    .mem_awid    (m0_awid),   .mem_awaddr (m0_awaddr),
    .mem_awlen   (m0_awlen),  .mem_awsize (m0_awsize),
    .mem_awburst (m0_awburst),.mem_awprot (m0_awprot),
    .mem_awvalid (m0_awvalid),.mem_awready(m0_awready),
    .mem_wdata   (m0_wdata),  .mem_wstrb  (m0_wstrb),
    .mem_wlast   (m0_wlast),  .mem_wvalid (m0_wvalid),
    .mem_wready  (m0_wready),
    .mem_bid     (m0_bid),    .mem_bresp  (m0_bresp),
    .mem_bvalid  (m0_bvalid), .mem_bready (m0_bready),

    .stat_hits   (icache_stat_hits),
    .stat_misses (icache_stat_misses)
);

// ============================================================================
// SECTION 14: INSTANCE — dcache_top  (Master M1)
// ============================================================================
dcache_top u_dcache (
    .clk         (clk_core),
    .rst_n       (fabric_rst_n),

    .cpu_addr    (cpu_dcache_addr),
    .cpu_wdata   (cpu_dcache_wdata),
    .cpu_wstrb   (cpu_dcache_wstrb),
    .cpu_req     (cpu_dcache_req),
    .cpu_we      (cpu_dcache_we),
    .cpu_rdata   (dcache_cpu_rdata),
    .cpu_ready   (dcache_cpu_ready),
    .fence_type  (cpu_dcache_fence_type),

    .current_addr (),
    .current_data (),
    .current_valid(),

    .mem_arid    (m1_arid),   .mem_araddr (m1_araddr),
    .mem_arlen   (m1_arlen),  .mem_arsize (m1_arsize),
    .mem_arburst (m1_arburst),.mem_arprot (m1_arprot),
    .mem_arvalid (m1_arvalid),.mem_arready(m1_arready),
    .mem_rid     (m1_rid),    .mem_rdata  (m1_rdata),
    .mem_rresp   (m1_rresp),  .mem_rlast  (m1_rlast),
    .mem_rvalid  (m1_rvalid), .mem_rready (m1_rready),
    .mem_awid    (m1_awid),   .mem_awaddr (m1_awaddr),
    .mem_awlen   (m1_awlen),  .mem_awsize (m1_awsize),
    .mem_awburst (m1_awburst),.mem_awprot (m1_awprot),
    .mem_awvalid (m1_awvalid),.mem_awready(m1_awready),
    .mem_wdata   (m1_wdata),  .mem_wstrb  (m1_wstrb),
    .mem_wlast   (m1_wlast),  .mem_wvalid (m1_wvalid),
    .mem_wready  (m1_wready),
    .mem_bid     (m1_bid),    .mem_bresp  (m1_bresp),
    .mem_bvalid  (m1_bvalid), .mem_bready (m1_bready),

    .stat_hits   (dcache_stat_hits),
    .stat_misses (dcache_stat_misses),
    .stat_writes (dcache_stat_writes)
);

// ============================================================================
// SECTION 15: INSTANCE — ascon_ip_top  (Slave S2 + DMA Master M2 64-bit)
// ============================================================================
ascon_ip_top u_ascon (
    .clk            (clk_core),
    .rst_n          (fabric_rst_n),

    // AXI4-Full Slave (S2)
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

    // AXI4-Full Master 64-bit (→ width converter → M2)
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
    .M_AXI_ARBURST  (dma_arburst),.M_AXI_ARCACHE (dma_arcache),
    .M_AXI_ARPROT   (dma_arprot),.M_AXI_ARVALID (dma_arvalid),
    .M_AXI_ARREADY  (dma_arready),
    .M_AXI_RID      (dma_rid),   .M_AXI_RDATA   (dma_rdata),
    .M_AXI_RRESP    (dma_rresp), .M_AXI_RLAST   (dma_rlast),
    .M_AXI_RVALID   (dma_rvalid),.M_AXI_RREADY  (dma_rready),

    // // AXI4-Stream (tied off)
    // .s_axis_tdata   (ascon_s_axis_tdata),
    // .s_axis_tvalid  (ascon_s_axis_tvalid),
    // .s_axis_tlast   (ascon_s_axis_tlast),
    // .s_axis_tready  (ascon_s_axis_tready),
    // .m_axis_tdata   (ascon_m_axis_tdata),
    // .m_axis_tvalid  (ascon_m_axis_tvalid),
    // .m_axis_tlast   (ascon_m_axis_tlast),
    // .m_axis_tready  (ascon_m_axis_tready),

    .o_tag          (ascon_o_tag),
    .o_tag_valid    (ascon_o_tag_valid),
    .o_busy         (ascon_o_busy),
    .irq            (ascon_irq)
);

// ============================================================================
// SECTION 16: INSTANCE — axi_width_converter_64to32
//
// WHY: ASCON DMA master dùng 64-bit data bus (hiệu quả hơn cho mật mã),
// nhưng crossbar chỉ hỗ trợ 32-bit. Converter ghép/tách các beat AXI.
// Kết nối: ASCON.M_AXI (64b) → converter → M2 (32b) → crossbar
// ============================================================================
axi_width_converter_64to32 u_width_conv (
    .clk      (clk_core),
    .rst_n    (fabric_rst_n),

    // Slave side: nhận từ ASCON DMA (64-bit)
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
    .M_AXI_ARBURST  (dma_arburst),.M_AXI_ARCACHE (dma_arcache),
    .M_AXI_ARPROT   (dma_arprot),.M_AXI_ARVALID (dma_arvalid),
    .M_AXI_ARREADY  (dma_arready),
    .M_AXI_RID      (dma_rid),   .M_AXI_RDATA   (dma_rdata),
    .M_AXI_RRESP    (dma_rresp), .M_AXI_RLAST   (dma_rlast),
    .M_AXI_RVALID   (dma_rvalid),.M_AXI_RREADY  (dma_rready),

    // Master side: ra crossbar M2 (32-bit)
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
// SECTION 17: INSTANCE — axi4_crossbar_5m12s
//
// WHY 5 masters: M0 ICache (priority cao nhất), M1 DCache, M2 ASCON-DMA,
// M3 DMA-Ctrl, M4 JTAG-DM (priority thấp nhất — chỉ active khi debug).
// Fixed priority: M0 > M1 > M2 > M3 > M4. Không cut burst.
// ============================================================================
axi4_crossbar_5m12s #(
    .DATA_WIDTH (DATA_WIDTH),
    .ADDR_WIDTH (ADDR_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .S0_BASE (S0_BASE),  .S0_MASK (S0_MASK),
    .S1_BASE (S1_BASE),  .S1_MASK (S1_MASK),
    .S2_BASE (S2_BASE),  .S2_MASK (S2_MASK),
    .S3_BASE (S3_BASE),  .S3_MASK (S3_MASK),
    .S4_BASE (S4_BASE),  .S4_MASK (S4_MASK),
    .S5_BASE (S5_BASE),  .S5_MASK (S5_MASK),
    .S6_BASE (S6_BASE),  .S6_MASK (S6_MASK),
    .S7_BASE (S7_BASE),  .S7_MASK (S7_MASK),
    .S8_BASE (S8_BASE),  .S8_MASK (S8_MASK),
    .S9_BASE (S9_BASE),  .S9_MASK (S9_MASK),
    .S10_BASE(S10_BASE), .S10_MASK(S10_MASK),
    .S11_BASE(S11_BASE), .S11_MASK(S11_MASK)
) u_crossbar (
    .clk   (clk),
    .rst_n (fabric_rst_n),

    // ── Master 0: ICache ──────────────────────────────────────────────────
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

    // ── Master 1: DCache ──────────────────────────────────────────────────
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

    // ── Master 2: ASCON DMA (32-bit sau width converter) ──────────────────
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

    // ── Master 3: DMA Controller ──────────────────────────────────────────
    .M3_AXI_ARID    (m3_arid),   .M3_AXI_ARADDR (m3_araddr),
    .M3_AXI_ARLEN   (m3_arlen),  .M3_AXI_ARSIZE (m3_arsize),
    .M3_AXI_ARBURST (m3_arburst),.M3_AXI_ARPROT (m3_arprot),
    .M3_AXI_ARVALID (m3_arvalid),.M3_AXI_ARREADY(m3_arready),
    .M3_AXI_RID     (m3_rid),    .M3_AXI_RDATA  (m3_rdata),
    .M3_AXI_RRESP   (m3_rresp),  .M3_AXI_RLAST  (m3_rlast),
    .M3_AXI_RVALID  (m3_rvalid), .M3_AXI_RREADY (m3_rready),
    .M3_AXI_AWID    (m3_awid),   .M3_AXI_AWADDR (m3_awaddr),
    .M3_AXI_AWLEN   (m3_awlen),  .M3_AXI_AWSIZE (m3_awsize),
    .M3_AXI_AWBURST (m3_awburst),.M3_AXI_AWPROT (m3_awprot),
    .M3_AXI_AWVALID (m3_awvalid),.M3_AXI_AWREADY(m3_awready),
    .M3_AXI_WDATA   (m3_wdata),  .M3_AXI_WSTRB  (m3_wstrb),
    .M3_AXI_WLAST   (m3_wlast),  .M3_AXI_WVALID (m3_wvalid),
    .M3_AXI_WREADY  (m3_wready),
    .M3_AXI_BID     (m3_bid),    .M3_AXI_BRESP  (m3_bresp),
    .M3_AXI_BVALID  (m3_bvalid), .M3_AXI_BREADY (m3_bready),

    // ── Master 4: JTAG Debug Module ───────────────────────────────────────
    .M4_AXI_ARID    (m4_arid),   .M4_AXI_ARADDR (m4_araddr),
    .M4_AXI_ARLEN   (m4_arlen),  .M4_AXI_ARSIZE (m4_arsize),
    .M4_AXI_ARBURST (m4_arburst),.M4_AXI_ARPROT (m4_arprot),
    .M4_AXI_ARVALID (m4_arvalid),.M4_AXI_ARREADY(m4_arready),
    .M4_AXI_RID     (m4_rid),    .M4_AXI_RDATA  (m4_rdata),
    .M4_AXI_RRESP   (m4_rresp),  .M4_AXI_RLAST  (m4_rlast),
    .M4_AXI_RVALID  (m4_rvalid), .M4_AXI_RREADY (m4_rready),
    .M4_AXI_AWID    (m4_awid),   .M4_AXI_AWADDR (m4_awaddr),
    .M4_AXI_AWLEN   (m4_awlen),  .M4_AXI_AWSIZE (m4_awsize),
    .M4_AXI_AWBURST (m4_awburst),.M4_AXI_AWPROT (m4_awprot),
    .M4_AXI_AWVALID (m4_awvalid),.M4_AXI_AWREADY(m4_awready),
    .M4_AXI_WDATA   (m4_wdata),  .M4_AXI_WSTRB  (m4_wstrb),
    .M4_AXI_WLAST   (m4_wlast),  .M4_AXI_WVALID (m4_wvalid),
    .M4_AXI_WREADY  (m4_wready),
    .M4_AXI_BID     (m4_bid),    .M4_AXI_BRESP  (m4_bresp),
    .M4_AXI_BVALID  (m4_bvalid), .M4_AXI_BREADY (m4_bready),

    // ── Slave 0: IMEM ─────────────────────────────────────────────────────
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

    // ── Slave 1: DMEM ─────────────────────────────────────────────────────
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

    // ── Slave 2: ASCON ────────────────────────────────────────────────────
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

    // ── Slave 3: SoC CTRL ─────────────────────────────────────────────────
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

    // ── Slave 4: CLINT ────────────────────────────────────────────────────
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
    .S4_AXI_BVALID  (s4_bvalid), .S4_AXI_BREADY (s4_bready),

    // ── Slave 5: UART ─────────────────────────────────────────────────────
    .S5_AXI_ARID    (s5_arid),   .S5_AXI_ARADDR (s5_araddr),
    .S5_AXI_ARLEN   (s5_arlen),  .S5_AXI_ARSIZE (s5_arsize),
    .S5_AXI_ARBURST (s5_arburst),.S5_AXI_ARPROT (s5_arprot),
    .S5_AXI_ARVALID (s5_arvalid),.S5_AXI_ARREADY(s5_arready),
    .S5_AXI_RID     (s5_rid),    .S5_AXI_RDATA  (s5_rdata),
    .S5_AXI_RRESP   (s5_rresp),  .S5_AXI_RLAST  (s5_rlast),
    .S5_AXI_RVALID  (s5_rvalid), .S5_AXI_RREADY (s5_rready),
    .S5_AXI_AWID    (s5_awid),   .S5_AXI_AWADDR (s5_awaddr),
    .S5_AXI_AWLEN   (s5_awlen),  .S5_AXI_AWSIZE (s5_awsize),
    .S5_AXI_AWBURST (s5_awburst),.S5_AXI_AWPROT (s5_awprot),
    .S5_AXI_AWVALID (s5_awvalid),.S5_AXI_AWREADY(s5_awready),
    .S5_AXI_WDATA   (s5_wdata),  .S5_AXI_WSTRB  (s5_wstrb),
    .S5_AXI_WLAST   (s5_wlast),  .S5_AXI_WVALID (s5_wvalid),
    .S5_AXI_WREADY  (s5_wready),
    .S5_AXI_BID     (s5_bid),    .S5_AXI_BRESP  (s5_bresp),
    .S5_AXI_BVALID  (s5_bvalid), .S5_AXI_BREADY (s5_bready),

    // ── Slave 6: GPIO (stub) ──────────────────────────────────────────────
    .S6_AXI_ARID    (s6_arid),   .S6_AXI_ARADDR (s6_araddr),
    .S6_AXI_ARLEN   (s6_arlen),  .S6_AXI_ARSIZE (s6_arsize),
    .S6_AXI_ARBURST (s6_arburst),.S6_AXI_ARPROT (s6_arprot),
    .S6_AXI_ARVALID (s6_arvalid),.S6_AXI_ARREADY(s6_arready),
    .S6_AXI_RID     (s6_rid),    .S6_AXI_RDATA  (s6_rdata),
    .S6_AXI_RRESP   (s6_rresp),  .S6_AXI_RLAST  (s6_rlast),
    .S6_AXI_RVALID  (s6_rvalid), .S6_AXI_RREADY (s6_rready),
    .S6_AXI_AWID    (s6_awid),   .S6_AXI_AWADDR (s6_awaddr),
    .S6_AXI_AWLEN   (s6_awlen),  .S6_AXI_AWSIZE (s6_awsize),
    .S6_AXI_AWBURST (s6_awburst),.S6_AXI_AWPROT (s6_awprot),
    .S6_AXI_AWVALID (s6_awvalid),.S6_AXI_AWREADY(s6_awready),
    .S6_AXI_WDATA   (s6_wdata),  .S6_AXI_WSTRB  (s6_wstrb),
    .S6_AXI_WLAST   (s6_wlast),  .S6_AXI_WVALID (s6_wvalid),
    .S6_AXI_WREADY  (s6_wready),
    .S6_AXI_BID     (s6_bid),    .S6_AXI_BRESP  (s6_bresp),
    .S6_AXI_BVALID  (s6_bvalid), .S6_AXI_BREADY (s6_bready),

    // ── Slave 7: SPI (stub) ───────────────────────────────────────────────
    .S7_AXI_ARID    (s7_arid),   .S7_AXI_ARADDR (s7_araddr),
    .S7_AXI_ARLEN   (s7_arlen),  .S7_AXI_ARSIZE (s7_arsize),
    .S7_AXI_ARBURST (s7_arburst),.S7_AXI_ARPROT (s7_arprot),
    .S7_AXI_ARVALID (s7_arvalid),.S7_AXI_ARREADY(s7_arready),
    .S7_AXI_RID     (s7_rid),    .S7_AXI_RDATA  (s7_rdata),
    .S7_AXI_RRESP   (s7_rresp),  .S7_AXI_RLAST  (s7_rlast),
    .S7_AXI_RVALID  (s7_rvalid), .S7_AXI_RREADY (s7_rready),
    .S7_AXI_AWID    (s7_awid),   .S7_AXI_AWADDR (s7_awaddr),
    .S7_AXI_AWLEN   (s7_awlen),  .S7_AXI_AWSIZE (s7_awsize),
    .S7_AXI_AWBURST (s7_awburst),.S7_AXI_AWPROT (s7_awprot),
    .S7_AXI_AWVALID (s7_awvalid),.S7_AXI_AWREADY(s7_awready),
    .S7_AXI_WDATA   (s7_wdata),  .S7_AXI_WSTRB  (s7_wstrb),
    .S7_AXI_WLAST   (s7_wlast),  .S7_AXI_WVALID (s7_wvalid),
    .S7_AXI_WREADY  (s7_wready),
    .S7_AXI_BID     (s7_bid),    .S7_AXI_BRESP  (s7_bresp),
    .S7_AXI_BVALID  (s7_bvalid), .S7_AXI_BREADY (s7_bready),

    // ── Slave 8: Timer/WDT (stub) ─────────────────────────────────────────
    .S8_AXI_ARID    (s8_arid),   .S8_AXI_ARADDR (s8_araddr),
    .S8_AXI_ARLEN   (s8_arlen),  .S8_AXI_ARSIZE (s8_arsize),
    .S8_AXI_ARBURST (s8_arburst),.S8_AXI_ARPROT (s8_arprot),
    .S8_AXI_ARVALID (s8_arvalid),.S8_AXI_ARREADY(s8_arready),
    .S8_AXI_RID     (s8_rid),    .S8_AXI_RDATA  (s8_rdata),
    .S8_AXI_RRESP   (s8_rresp),  .S8_AXI_RLAST  (s8_rlast),
    .S8_AXI_RVALID  (s8_rvalid), .S8_AXI_RREADY (s8_rready),
    .S8_AXI_AWID    (s8_awid),   .S8_AXI_AWADDR (s8_awaddr),
    .S8_AXI_AWLEN   (s8_awlen),  .S8_AXI_AWSIZE (s8_awsize),
    .S8_AXI_AWBURST (s8_awburst),.S8_AXI_AWPROT (s8_awprot),
    .S8_AXI_AWVALID (s8_awvalid),.S8_AXI_AWREADY(s8_awready),
    .S8_AXI_WDATA   (s8_wdata),  .S8_AXI_WSTRB  (s8_wstrb),
    .S8_AXI_WLAST   (s8_wlast),  .S8_AXI_WVALID (s8_wvalid),
    .S8_AXI_WREADY  (s8_wready),
    .S8_AXI_BID     (s8_bid),    .S8_AXI_BRESP  (s8_bresp),
    .S8_AXI_BVALID  (s8_bvalid), .S8_AXI_BREADY (s8_bready),

    // ── Slave 9: PLIC ─────────────────────────────────────────────────────
    .S9_AXI_ARID    (s9_arid),   .S9_AXI_ARADDR (s9_araddr),
    .S9_AXI_ARLEN   (s9_arlen),  .S9_AXI_ARSIZE (s9_arsize),
    .S9_AXI_ARBURST (s9_arburst),.S9_AXI_ARPROT (s9_arprot),
    .S9_AXI_ARVALID (s9_arvalid),.S9_AXI_ARREADY(s9_arready),
    .S9_AXI_RID     (s9_rid),    .S9_AXI_RDATA  (s9_rdata),
    .S9_AXI_RRESP   (s9_rresp),  .S9_AXI_RLAST  (s9_rlast),
    .S9_AXI_RVALID  (s9_rvalid), .S9_AXI_RREADY (s9_rready),
    .S9_AXI_AWID    (s9_awid),   .S9_AXI_AWADDR (s9_awaddr),
    .S9_AXI_AWLEN   (s9_awlen),  .S9_AXI_AWSIZE (s9_awsize),
    .S9_AXI_AWBURST (s9_awburst),.S9_AXI_AWPROT (s9_awprot),
    .S9_AXI_AWVALID (s9_awvalid),.S9_AXI_AWREADY(s9_awready),
    .S9_AXI_WDATA   (s9_wdata),  .S9_AXI_WSTRB  (s9_wstrb),
    .S9_AXI_WLAST   (s9_wlast),  .S9_AXI_WVALID (s9_wvalid),
    .S9_AXI_WREADY  (s9_wready),
    .S9_AXI_BID     (s9_bid),    .S9_AXI_BRESP  (s9_bresp),
    .S9_AXI_BVALID  (s9_bvalid), .S9_AXI_BREADY (s9_bready),

    // ── Slave 10: OTP (stub) ──────────────────────────────────────────────
    .S10_AXI_ARID    (s10_arid),   .S10_AXI_ARADDR (s10_araddr),
    .S10_AXI_ARLEN   (s10_arlen),  .S10_AXI_ARSIZE (s10_arsize),
    .S10_AXI_ARBURST (s10_arburst),.S10_AXI_ARPROT (s10_arprot),
    .S10_AXI_ARVALID (s10_arvalid),.S10_AXI_ARREADY(s10_arready),
    .S10_AXI_RID     (s10_rid),    .S10_AXI_RDATA  (s10_rdata),
    .S10_AXI_RRESP   (s10_rresp),  .S10_AXI_RLAST  (s10_rlast),
    .S10_AXI_RVALID  (s10_rvalid), .S10_AXI_RREADY (s10_rready),
    .S10_AXI_AWID    (s10_awid),   .S10_AXI_AWADDR (s10_awaddr),
    .S10_AXI_AWLEN   (s10_awlen),  .S10_AXI_AWSIZE (s10_awsize),
    .S10_AXI_AWBURST (s10_awburst),.S10_AXI_AWPROT (s10_awprot),
    .S10_AXI_AWVALID (s10_awvalid),.S10_AXI_AWREADY(s10_awready),
    .S10_AXI_WDATA   (s10_wdata),  .S10_AXI_WSTRB  (s10_wstrb),
    .S10_AXI_WLAST   (s10_wlast),  .S10_AXI_WVALID (s10_wvalid),
    .S10_AXI_WREADY  (s10_wready),
    .S10_AXI_BID     (s10_bid),    .S10_AXI_BRESP  (s10_bresp),
    .S10_AXI_BVALID  (s10_bvalid), .S10_AXI_BREADY (s10_bready),

    // ── Slave 11: DMA Ctrl Config ─────────────────────────────────────────
    .S11_AXI_ARID    (s11_arid),   .S11_AXI_ARADDR (s11_araddr),
    .S11_AXI_ARLEN   (s11_arlen),  .S11_AXI_ARSIZE (s11_arsize),
    .S11_AXI_ARBURST (s11_arburst),.S11_AXI_ARPROT (s11_arprot),
    .S11_AXI_ARVALID (s11_arvalid),.S11_AXI_ARREADY(s11_arready),
    .S11_AXI_RID     (s11_rid),    .S11_AXI_RDATA  (s11_rdata),
    .S11_AXI_RRESP   (s11_rresp),  .S11_AXI_RLAST  (s11_rlast),
    .S11_AXI_RVALID  (s11_rvalid), .S11_AXI_RREADY (s11_rready),
    .S11_AXI_AWID    (s11_awid),   .S11_AXI_AWADDR (s11_awaddr),
    .S11_AXI_AWLEN   (s11_awlen),  .S11_AXI_AWSIZE (s11_awsize),
    .S11_AXI_AWBURST (s11_awburst),.S11_AXI_AWPROT (s11_awprot),
    .S11_AXI_AWVALID (s11_awvalid),.S11_AXI_AWREADY(s11_awready),
    .S11_AXI_WDATA   (s11_wdata),  .S11_AXI_WSTRB  (s11_wstrb),
    .S11_AXI_WLAST   (s11_wlast),  .S11_AXI_WVALID (s11_wvalid),
    .S11_AXI_WREADY  (s11_wready),
    .S11_AXI_BID     (s11_bid),    .S11_AXI_BRESP  (s11_bresp),
    .S11_AXI_BVALID  (s11_bvalid), .S11_AXI_BREADY (s11_bready)
);

// ============================================================================
// SECTION 18: INSTANCE — inst_mem_axi_slave  (S0 — IMEM)
// ============================================================================
inst_mem_axi_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .MEM_SIZE   (IMEM_SIZE)
    // MEM_INIT_FILE not used — boot_ctrl loads at runtime
) u_imem (
    .clk            (clk),
    .rst_n          (fabric_rst_n),
    // Boot sideband write port
    .boot_we        (imem_boot_we),
    .boot_addr      (imem_boot_addr),
    .boot_wdata     (imem_boot_wdata),
    .S_AXI_AWID    (s0_awid),   .S_AXI_AWADDR  (s0_awaddr),
    .S_AXI_AWLEN   (s0_awlen),  .S_AXI_AWSIZE  (s0_awsize),
    .S_AXI_AWBURST (s0_awburst),.S_AXI_AWPROT  (s0_awprot),
    .S_AXI_AWVALID (s0_awvalid),.S_AXI_AWREADY (s0_awready),
    .S_AXI_WDATA   (s0_wdata),  .S_AXI_WSTRB   (s0_wstrb),
    .S_AXI_WLAST   (s0_wlast),  .S_AXI_WVALID  (s0_wvalid),
    .S_AXI_WREADY  (s0_wready),
    .S_AXI_BID     (s0_bid),    .S_AXI_BRESP   (s0_bresp),
    .S_AXI_BVALID  (s0_bvalid), .S_AXI_BREADY  (s0_bready),
    .S_AXI_ARID    (s0_arid),   .S_AXI_ARADDR  (s0_araddr),
    .S_AXI_ARLEN   (s0_arlen),  .S_AXI_ARSIZE  (s0_arsize),
    .S_AXI_ARBURST (s0_arburst),.S_AXI_ARPROT  (s0_arprot),
    .S_AXI_ARVALID (s0_arvalid),.S_AXI_ARREADY (s0_arready),
    .S_AXI_RID     (s0_rid),    .S_AXI_RDATA   (s0_rdata),
    .S_AXI_RRESP   (s0_rresp),  .S_AXI_RLAST   (s0_rlast),
    .S_AXI_RVALID  (s0_rvalid), .S_AXI_RREADY  (s0_rready)
);

// ============================================================================
// SECTION 19: INSTANCE — data_mem_axi4_slave  (S1 — DMEM)
// ============================================================================
data_mem_axi4_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH),
    .MEM_SIZE   (DMEM_SIZE)
) u_dmem (
    .clk           (clk),
    .rst_n         (fabric_rst_n),
    .S_AXI_AWID    (s1_awid),   .S_AXI_AWADDR  (s1_awaddr),
    .S_AXI_AWLEN   (s1_awlen),  .S_AXI_AWSIZE  (s1_awsize),
    .S_AXI_AWBURST (s1_awburst),.S_AXI_AWPROT  (s1_awprot),
    .S_AXI_AWVALID (s1_awvalid),.S_AXI_AWREADY (s1_awready),
    .S_AXI_WDATA   (s1_wdata),  .S_AXI_WSTRB   (s1_wstrb),
    .S_AXI_WLAST   (s1_wlast),  .S_AXI_WVALID  (s1_wvalid),
    .S_AXI_WREADY  (s1_wready),
    .S_AXI_BID     (s1_bid),    .S_AXI_BRESP   (s1_bresp),
    .S_AXI_BVALID  (s1_bvalid), .S_AXI_BREADY  (s1_bready),
    .S_AXI_ARID    (s1_arid),   .S_AXI_ARADDR  (s1_araddr),
    .S_AXI_ARLEN   (s1_arlen),  .S_AXI_ARSIZE  (s1_arsize),
    .S_AXI_ARBURST (s1_arburst),.S_AXI_ARPROT  (s1_arprot),
    .S_AXI_ARVALID (s1_arvalid),.S_AXI_ARREADY (s1_arready),
    .S_AXI_RID     (s1_rid),    .S_AXI_RDATA   (s1_rdata),
    .S_AXI_RRESP   (s1_rresp),  .S_AXI_RLAST   (s1_rlast),
    .S_AXI_RVALID  (s1_rvalid), .S_AXI_RREADY  (s1_rready)
);

// ============================================================================
// SECTION 20: INSTANCE — soc_ctrl_slave  (S3)
//
// WHY giữ soc_ctrl: vẫn cần soft reset, cache stats, SYS_ID.
// IRQ output (soc_ctrl_irq_out) KHÔNG dùng làm external_irq nữa —
// external_irq bây giờ đến từ PLIC.meip.
// ============================================================================
soc_ctrl_slave #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
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
    .uart_irq       (uart_irq),
    .gpio_irq       (gpio_irq),
    .spi_irq        (spi_irq),
    .timer_irq      (timer_irq),
    .wdt_irq        (wdt_irq),
    .perf_stall_in     (cpu_perf_stall),
    .perf_instr_ret_in (cpu_perf_instr_ret),
    .irq_out        (soc_ctrl_irq_out),   // WHY không dùng: PLIC thay thế vai trò này
    .soft_rst_pulse (soft_rst_pulse)
);

// ============================================================================
// SECTION 21: INSTANCE — clint  (S4)
// ============================================================================
clint #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
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

// ============================================================================
// SECTION 22: INSTANCE — uart_top  (S5)
//
// WHY periph_rst_n thay vì fabric_rst_n: UART nằm trong PERIPH domain,
// bị reset khi ndmreset (JTAG debug reset) để tránh stale TX state.
// ============================================================================
uart_top #(
    .AXI_ADDR_WIDTH (ADDR_WIDTH),
    .AXI_DATA_WIDTH (DATA_WIDTH),
    .AXI_ID_WIDTH   (ID_WIDTH)
) u_uart (
    .clk            (clk_periph),
    .rst_n          (periph_rst_n),
    .s_axi_awid     (s5_awid),   .s_axi_awaddr  (s5_awaddr),
    .s_axi_awlen    (s5_awlen),  .s_axi_awsize  (s5_awsize),
    .s_axi_awburst  (s5_awburst),
    .s_axi_awvalid  (s5_awvalid),.s_axi_awready (s5_awready),
    .s_axi_wdata    (s5_wdata),  .s_axi_wstrb   (s5_wstrb),
    .s_axi_wlast    (s5_wlast),  .s_axi_wvalid  (s5_wvalid),
    .s_axi_wready   (s5_wready),
    .s_axi_bid      (s5_bid),    .s_axi_bresp   (s5_bresp),
    .s_axi_bvalid   (s5_bvalid), .s_axi_bready  (s5_bready),
    .s_axi_arid     (s5_arid),   .s_axi_araddr  (s5_araddr),
    .s_axi_arlen    (s5_arlen),  .s_axi_arsize  (s5_arsize),
    .s_axi_arburst  (s5_arburst),
    .s_axi_arvalid  (s5_arvalid),.s_axi_arready (s5_arready),
    .s_axi_rid      (s5_rid),    .s_axi_rdata   (s5_rdata),
    .s_axi_rresp    (s5_rresp),  .s_axi_rlast   (s5_rlast),
    .s_axi_rvalid   (s5_rvalid), .s_axi_rready  (s5_rready),
    .uart_tx        (uart_tx),
    .uart_rx        (uart_rx),
    .irq_out        (uart_irq),
    .uart_active    (uart_active),
    .tx_dma_req     (uart_tx_dma_req),
    .rx_dma_req     (uart_rx_dma_req),
    .clk_aon        (clk_aon),
    .aon_rst_n      (aon_rst_n),
    .wake_ack       (wake_ack),
    .uart_wake_req  (uart_wake_req)
);

// ============================================================================
// SECTION 23: INSTANCE — plic_top  (S9)
//
// IRQ source assignment (từ SoC_Register_Map_5m12s.docx section 6a):
//   [0]  = reserved (always 0)
//   [1]  = UART_TX_IRQ  — uart_irq hợp nhất TX+RX vào 1 wire từ uart_top
//   [2]  = UART_RX_IRQ  — dùng chung uart_irq (uart_top phát 1 wire OR)
//   [3]  = SPI_IRQ      — stub 0
//   [4]  = GPIO_IRQ     — stub 0
//   [5]  = TIMER0_IRQ   — stub 0
//   [6]  = TIMER1_IRQ   — stub 0
//   [7]  = WDT_WARN_IRQ — stub 0
//   [8]  = ASCON_IRQ    — từ ascon_ip_top
//   [9]  = DMA_IRQ      — từ dma_ctrl
//   [10..31] = reserved 0
//
// WHY uart_irq vào cả [1] và [2]: uart_top expose 1 wire irq_out (TX|RX).
// Khi có gpio_top và uart_top riêng, tách ra 2 wire riêng biệt.
// ============================================================================
plic_top #(
    .NUM_SRC    (32),
    .PRIO_W     (3),
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_plic (
    .clk            (clk_periph),
    .rst_n          (periph_rst_n),
    .s_axi_awid     (s9_awid),   .s_axi_awaddr  (s9_awaddr),
    .s_axi_awlen    (s9_awlen),  .s_axi_awsize  (s9_awsize),
    .s_axi_awburst  (s9_awburst),.s_axi_awprot  (s9_awprot),
    .s_axi_awvalid  (s9_awvalid),.s_axi_awready (s9_awready),
    .s_axi_wdata    (s9_wdata),  .s_axi_wstrb   (s9_wstrb),
    .s_axi_wlast    (s9_wlast),  .s_axi_wvalid  (s9_wvalid),
    .s_axi_wready   (s9_wready),
    .s_axi_bid      (s9_bid),    .s_axi_bresp   (s9_bresp),
    .s_axi_bvalid   (s9_bvalid), .s_axi_bready  (s9_bready),
    .s_axi_arid     (s9_arid),   .s_axi_araddr  (s9_araddr),
    .s_axi_arlen    (s9_arlen),  .s_axi_arsize  (s9_arsize),
    .s_axi_arburst  (s9_arburst),.s_axi_arprot  (s9_arprot),
    .s_axi_arvalid  (s9_arvalid),.s_axi_arready (s9_arready),
    .s_axi_rid      (s9_rid),    .s_axi_rdata   (s9_rdata),
    .s_axi_rresp    (s9_rresp),  .s_axi_rlast   (s9_rlast),
    .s_axi_rvalid   (s9_rvalid), .s_axi_rready  (s9_rready),
    // irq_src[31:0]: bit 0 luôn = 0 (reserved per PLIC spec)
    .irq_src        ({22'd0,         // [31:10] reserved
                      dma_irq,       // [9]  DMA done/error
                      ascon_irq,     // [8]  ASCON crypto done
                      wdt_irq,       // [7]  WDT warning
                      timer1_irq,    // [6]  Timer 1 timeout
                      timer0_irq,    // [5]  Timer 0 timeout
                      gpio_irq,      // [4]  GPIO edge/level
                      1'b0,          // [3]  SPI (stub)
                      uart_irq,      // [2]  UART RX (hợp nhất)
                      uart_irq,      // [1]  UART TX (hợp nhất)
                      1'b0}),        // [0]  reserved
    .meip           (external_irq)   // → CPU.external_irq
);

// ============================================================================
// SECTION 24: INSTANCE — jtag_debug_top  (Master M4)
//
// WHY clk thay vì clk_core: JTAG DM dùng clk thẳng (không qua ICG) vì
// DM cần hoạt động ngay cả khi CORE domain bị gate (debug attach trước boot).
// Trong thiết kế này clk_core≡clk (core_clk_en=1), nhưng convention đúng
// là dùng clk để DM luôn có clock khi kết nối debugger.
//
// ndmreset flow: JTAG→u_jtag.ndmreset → u_clkrst.ndmreset → cpu_rst_n low
//   → cpu_rst high → CPU reset. Crossbar (fabric_rst_n) KHÔNG bị ảnh hưởng.
// ============================================================================
jtag_debug_top #(
    .ADDR_WIDTH  (ADDR_WIDTH),
    .DATA_WIDTH  (DATA_WIDTH),
    .ID_WIDTH    (ID_WIDTH),
    .IDCODE_VAL  (JTAG_IDCODE)
) u_jtag (
    .clk          (clk),
    .rst_n        (periph_rst_n),  // DM reset theo PERIPH domain

    // JTAG pads
    .tck          (tck),
    .tms          (tms),
    .tdi          (tdi),
    .tdo          (tdo),
    .tdo_en       (tdo_en),

    // CPU debug interface
    .ndmreset     (jtag_ndmreset),
    .haltreq      (jtag_haltreq),
    .resumereq    (jtag_resumereq),
    .halted       (jtag_halted),
    .running      (jtag_running),

    // AXI4-Full Master M4 → crossbar
    .M_AXI_ARID   (m4_arid),   .M_AXI_ARADDR  (m4_araddr),
    .M_AXI_ARLEN  (m4_arlen),  .M_AXI_ARSIZE  (m4_arsize),
    .M_AXI_ARBURST(m4_arburst),.M_AXI_ARPROT  (m4_arprot),
    .M_AXI_ARVALID(m4_arvalid),.M_AXI_ARREADY (m4_arready),
    .M_AXI_RID    (m4_rid),    .M_AXI_RDATA   (m4_rdata),
    .M_AXI_RRESP  (m4_rresp),  .M_AXI_RLAST   (m4_rlast),
    .M_AXI_RVALID (m4_rvalid), .M_AXI_RREADY  (m4_rready),
    .M_AXI_AWID   (m4_awid),   .M_AXI_AWADDR  (m4_awaddr),
    .M_AXI_AWLEN  (m4_awlen),  .M_AXI_AWSIZE  (m4_awsize),
    .M_AXI_AWBURST(m4_awburst),.M_AXI_AWPROT  (m4_awprot),
    .M_AXI_AWVALID(m4_awvalid),.M_AXI_AWREADY (m4_awready),
    .M_AXI_WDATA  (m4_wdata),  .M_AXI_WSTRB   (m4_wstrb),
    .M_AXI_WLAST  (m4_wlast),  .M_AXI_WVALID  (m4_wvalid),
    .M_AXI_WREADY (m4_wready),
    .M_AXI_BID    (m4_bid),    .M_AXI_BRESP   (m4_bresp),
    .M_AXI_BVALID (m4_bvalid), .M_AXI_BREADY  (m4_bready)
);

// ============================================================================
// SECTION 25: INSTANCE — dma_ctrl  (Slave S11 + Master M3)
//
// dma_ctrl có 2 giao diện:
//   S11 slave (0x6001_0000): CPU config các kênh DMA (src/dst/len/ctrl)
//   M3  master: DMA thực hiện burst transfer qua crossbar
// ============================================================================
dma_ctrl #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .ID_WIDTH   (ID_WIDTH)
) u_dma_ctrl (
    .clk        (clk_periph),
    .rst_n      (periph_rst_n),

    // AXI4-Full Slave S11 ← crossbar (CPU cấu hình DMA)
    .S_AXI_AWID    (s11_awid),   .S_AXI_AWADDR  (s11_awaddr),
    .S_AXI_AWLEN   (s11_awlen),  .S_AXI_AWSIZE  (s11_awsize),
    .S_AXI_AWBURST (s11_awburst),.S_AXI_AWPROT  (s11_awprot),
    .S_AXI_AWVALID (s11_awvalid),.S_AXI_AWREADY (s11_awready),
    .S_AXI_WDATA   (s11_wdata),  .S_AXI_WSTRB   (s11_wstrb),
    .S_AXI_WLAST   (s11_wlast),  .S_AXI_WVALID  (s11_wvalid),
    .S_AXI_WREADY  (s11_wready),
    .S_AXI_BID     (s11_bid),    .S_AXI_BRESP   (s11_bresp),
    .S_AXI_BVALID  (s11_bvalid), .S_AXI_BREADY  (s11_bready),
    .S_AXI_ARID    (s11_arid),   .S_AXI_ARADDR  (s11_araddr),
    .S_AXI_ARLEN   (s11_arlen),  .S_AXI_ARSIZE  (s11_arsize),
    .S_AXI_ARBURST (s11_arburst),.S_AXI_ARPROT  (s11_arprot),
    .S_AXI_ARVALID (s11_arvalid),.S_AXI_ARREADY (s11_arready),
    .S_AXI_RID     (s11_rid),    .S_AXI_RDATA   (s11_rdata),
    .S_AXI_RRESP   (s11_rresp),  .S_AXI_RLAST   (s11_rlast),
    .S_AXI_RVALID  (s11_rvalid), .S_AXI_RREADY  (s11_rready),

    // AXI4-Full Master M3 → crossbar (DMA thực hiện transfer)
    .M_AXI_ARID    (m3_arid),   .M_AXI_ARADDR  (m3_araddr),
    .M_AXI_ARLEN   (m3_arlen),  .M_AXI_ARSIZE  (m3_arsize),
    .M_AXI_ARBURST (m3_arburst),.M_AXI_ARPROT  (m3_arprot),
    .M_AXI_ARVALID (m3_arvalid),.M_AXI_ARREADY (m3_arready),
    .M_AXI_RID     (m3_rid),    .M_AXI_RDATA   (m3_rdata),
    .M_AXI_RRESP   (m3_rresp),  .M_AXI_RLAST   (m3_rlast),
    .M_AXI_RVALID  (m3_rvalid), .M_AXI_RREADY  (m3_rready),
    .M_AXI_AWID    (m3_awid),   .M_AXI_AWADDR  (m3_awaddr),
    .M_AXI_AWLEN   (m3_awlen),  .M_AXI_AWSIZE  (m3_awsize),
    .M_AXI_AWBURST (m3_awburst),.M_AXI_AWPROT  (m3_awprot),
    .M_AXI_AWVALID (m3_awvalid),.M_AXI_AWREADY (m3_awready),
    .M_AXI_WDATA   (m3_wdata),  .M_AXI_WSTRB   (m3_wstrb),
    .M_AXI_WLAST   (m3_wlast),  .M_AXI_WVALID  (m3_wvalid),
    .M_AXI_WREADY  (m3_wready),
    .M_AXI_BID     (m3_bid),    .M_AXI_BRESP   (m3_bresp),
    .M_AXI_BVALID  (m3_bvalid), .M_AXI_BREADY  (m3_bready),

    .irq_out       (dma_irq),   // → PLIC source[9]
    .dma_busy_o    (dma_busy),
    .dma_req       (dma_periph_req),  // CH0=UART_RX, CH1=UART_TX, CH2=SPI_RX, CH3=SPI_TX
    .dma_ack       (dma_periph_ack)
);

endmodule
// ============================================================================
// END: soc_top.v
//
// Checklist kết nối:
//   ✅ clk_reset_ctrl: thay wire fabric_rst_n=ext_rst_n nguy hiểm
//   ✅ boot_ctrl: load IMEM, giữ cpu_rst_n cho đến khi boot_done
//   ✅ CPU: kết nối debug_halt/resume + external_irq từ PLIC
//   ✅ ICache/DCache: dùng clk_core
//   ✅ ASCON + width_conv: giống cũ, giữ nguyên
//   ✅ Crossbar 5m12s: giữ nguyên 5M×12S
//   ✅ UART: S5, clk_periph, periph_rst_n, irq→PLIC[1,2]
//   ✅ GPIO: S6, 32-bit, clk_periph, irq→PLIC[4]
//   ✅ Timer/WDT: S8, clk_periph, timer0_irq→PLIC[5], timer1_irq→PLIC[6], wdt_irq→PLIC[7]
//   ✅ PLIC: S9, tổng hợp tất cả IRQ, meip→CPU
//   ✅ JTAG: M4, ndmreset→clk_reset_ctrl, halt/resume←→CPU
//   ✅ DMA: S11(config)+M3(transfer), irq→PLIC[9]
//   ✅ Stub slaves: S7(SPI), S10(OTP) → DECERR
//   ✅ soc_ctrl: giữ lại (soft_rst, cache stats), irq_out không dùng
//   ✅ CLINT: giữ nguyên, timer_irq/sw_irq→CPU bypass PLIC
// ============================================================================
