// ============================================================================
// timer_top.v — Timer/WDT Peripheral Top-Level (AXI4-Full Slave S8)
//
// Address: 0x5003_0000 (S8 in crossbar), 4 KB
// Clock: clk_periph domain
//
// Hierarchy:
//   timer_top
//   ├── timer_regfile  — AXI4-Full slave + register decode
//   ├── timer_channel  u_t0 — Timer 0 (32-bit)
//   ├── timer_channel  u_t1 — Timer 1 (32-bit)
//   └── wdt_core            — Watchdog timer
//
// IRQ sources to PLIC:
//   timer0_irq → plic irq_src[5]
//   timer1_irq → plic irq_src[6]
//   wdt_irq    → plic irq_src[7]
//
// wdt_rst_req (active-high) can be fed to soc_top as additional reset source.
// ============================================================================

`include "peripheral/timer/rtl/timer_regfile.v"
`include "peripheral/timer/rtl/timer_channel.v"
`include "peripheral/timer/rtl/wdt_core.v"

module timer_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire clk,
    input  wire rst_n,

    // ── AXI4-Full Slave (S8) ─────────────────────────────────────────────────
    input  wire [ID_WIDTH-1:0]      S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]    S_AXI_AWADDR,
    input  wire [7:0]               S_AXI_AWLEN,
    input  wire [2:0]               S_AXI_AWSIZE,
    input  wire [1:0]               S_AXI_AWBURST,
    input  wire [2:0]               S_AXI_AWPROT,
    input  wire                     S_AXI_AWVALID,
    output wire                     S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]    S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0]  S_AXI_WSTRB,
    input  wire                     S_AXI_WLAST,
    input  wire                     S_AXI_WVALID,
    output wire                     S_AXI_WREADY,

    output wire [ID_WIDTH-1:0]      S_AXI_BID,
    output wire [1:0]               S_AXI_BRESP,
    output wire                     S_AXI_BVALID,
    input  wire                     S_AXI_BREADY,

    input  wire [ID_WIDTH-1:0]      S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]    S_AXI_ARADDR,
    input  wire [7:0]               S_AXI_ARLEN,
    input  wire [2:0]               S_AXI_ARSIZE,
    input  wire [1:0]               S_AXI_ARBURST,
    input  wire [2:0]               S_AXI_ARPROT,
    input  wire                     S_AXI_ARVALID,
    output wire                     S_AXI_ARREADY,

    output wire [ID_WIDTH-1:0]      S_AXI_RID,
    output wire [DATA_WIDTH-1:0]    S_AXI_RDATA,
    output wire [1:0]               S_AXI_RRESP,
    output wire                     S_AXI_RLAST,
    output wire                     S_AXI_RVALID,
    input  wire                     S_AXI_RREADY,

    // ── IRQ outputs to PLIC ──────────────────────────────────────────────────
    output wire timer0_irq,
    output wire timer1_irq,
    output wire wdt_irq,

    // ── WDT reset request (active-high) ──────────────────────────────────────
    output wire wdt_rst_req,
    output wire timer_active_o
);

    // ── Timer 0 wires ────────────────────────────────────────────────────────
    wire        t0_en, t0_auto_reload, t0_irq_en, t0_count_dir;
    wire [31:0] t0_load;
    wire [31:0] t0_count;
    wire        t0_timeout_flag;
    wire        t0_timeout_clr;

    // ── Timer 1 wires ────────────────────────────────────────────────────────
    wire        t1_en, t1_auto_reload, t1_irq_en, t1_count_dir;
    wire [31:0] t1_load;
    wire [31:0] t1_count;
    wire        t1_timeout_flag;
    wire        t1_timeout_clr;

    // ── WDT wires ────────────────────────────────────────────────────────────
    wire        wdt_en, wdt_irq_en_w;
    wire [31:0] wdt_load;
    wire        wdt_feed_pulse;
    wire [31:0] wdt_count;
    wire        wdt_expired_flag;
    wire        wdt_expired_clr;

    timer_regfile #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_regfile (
        .clk           (clk),
        .rst_n         (rst_n),

        .S_AXI_AWID    (S_AXI_AWID),   .S_AXI_AWADDR  (S_AXI_AWADDR),
        .S_AXI_AWLEN   (S_AXI_AWLEN),  .S_AXI_AWSIZE  (S_AXI_AWSIZE),
        .S_AXI_AWBURST (S_AXI_AWBURST),.S_AXI_AWPROT  (S_AXI_AWPROT),
        .S_AXI_AWVALID (S_AXI_AWVALID),.S_AXI_AWREADY (S_AXI_AWREADY),
        .S_AXI_WDATA   (S_AXI_WDATA),  .S_AXI_WSTRB   (S_AXI_WSTRB),
        .S_AXI_WLAST   (S_AXI_WLAST),  .S_AXI_WVALID  (S_AXI_WVALID),
        .S_AXI_WREADY  (S_AXI_WREADY),
        .S_AXI_BID     (S_AXI_BID),    .S_AXI_BRESP   (S_AXI_BRESP),
        .S_AXI_BVALID  (S_AXI_BVALID), .S_AXI_BREADY  (S_AXI_BREADY),
        .S_AXI_ARID    (S_AXI_ARID),   .S_AXI_ARADDR  (S_AXI_ARADDR),
        .S_AXI_ARLEN   (S_AXI_ARLEN),  .S_AXI_ARSIZE  (S_AXI_ARSIZE),
        .S_AXI_ARBURST (S_AXI_ARBURST),.S_AXI_ARPROT  (S_AXI_ARPROT),
        .S_AXI_ARVALID (S_AXI_ARVALID),.S_AXI_ARREADY (S_AXI_ARREADY),
        .S_AXI_RID     (S_AXI_RID),    .S_AXI_RDATA   (S_AXI_RDATA),
        .S_AXI_RRESP   (S_AXI_RRESP),  .S_AXI_RLAST   (S_AXI_RLAST),
        .S_AXI_RVALID  (S_AXI_RVALID), .S_AXI_RREADY  (S_AXI_RREADY),

        .t0_en          (t0_en),        .t0_auto_reload  (t0_auto_reload),
        .t0_irq_en      (t0_irq_en),    .t0_count_dir    (t0_count_dir),
        .t0_load        (t0_load),
        .t0_count       (t0_count),     .t0_timeout_flag (t0_timeout_flag),
        .t0_timeout_clr (t0_timeout_clr),

        .t1_en          (t1_en),        .t1_auto_reload  (t1_auto_reload),
        .t1_irq_en      (t1_irq_en),    .t1_count_dir    (t1_count_dir),
        .t1_load        (t1_load),
        .t1_count       (t1_count),     .t1_timeout_flag (t1_timeout_flag),
        .t1_timeout_clr (t1_timeout_clr),

        .wdt_en         (wdt_en),       .wdt_irq_en      (wdt_irq_en_w),
        .wdt_load       (wdt_load),     .wdt_feed_pulse  (wdt_feed_pulse),
        .wdt_count      (wdt_count),    .wdt_expired_flag(wdt_expired_flag),
        .wdt_expired_clr(wdt_expired_clr)
    );

    timer_channel u_t0 (
        .clk          (clk),       .rst_n        (rst_n),
        .en           (t0_en),     .auto_reload  (t0_auto_reload),
        .irq_en       (t0_irq_en), .count_dir    (t0_count_dir),
        .load_val     (t0_load),
        .count        (t0_count),  .timeout_flag (t0_timeout_flag),
        .timeout_clr  (t0_timeout_clr),
        .irq          (timer0_irq)
    );

    timer_channel u_t1 (
        .clk          (clk),       .rst_n        (rst_n),
        .en           (t1_en),     .auto_reload  (t1_auto_reload),
        .irq_en       (t1_irq_en), .count_dir    (t1_count_dir),
        .load_val     (t1_load),
        .count        (t1_count),  .timeout_flag (t1_timeout_flag),
        .timeout_clr  (t1_timeout_clr),
        .irq          (timer1_irq)
    );

    wdt_core u_wdt (
        .clk           (clk),           .rst_n        (rst_n),
        .en            (wdt_en),        .irq_en       (wdt_irq_en_w),
        .load_val      (wdt_load),      .feed_pulse   (wdt_feed_pulse),
        .count         (wdt_count),     .expired_flag (wdt_expired_flag),
        .expired_clr   (wdt_expired_clr),
        .wdt_irq       (wdt_irq),
        .wdt_rst_req   (wdt_rst_req)
    );

    assign timer_active_o = t0_en | t1_en | wdt_en;

endmodule
