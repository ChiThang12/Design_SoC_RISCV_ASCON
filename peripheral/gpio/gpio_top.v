// ============================================================================
// gpio_top.v — GPIO Peripheral Top-Level (AXI4-Full Slave S6)
//
// Address: 0x5001_0000 (S6 in crossbar), 4 KB
// Clock: clk_periph domain
//
// Hierarchy:
//   gpio_top
//   ├── gpio_regfile  — AXI4-Full slave + register file
//   └── gpio_iocell   — 2-FF synchronizer + edge/level IRQ detector
//
// IO interface (split in/out/oe for simulation; use wrapper for inout pads):
//   gpio_out[31:0]  — driven to output pads when gpio_oe=1
//   gpio_oe[31:0]   — output enable (1=drive, 0=high-Z)
//   gpio_in[31:0]   — sampled from input pads
// ============================================================================

`include "peripheral/gpio/rtl/gpio_regfile.v"
`include "peripheral/gpio/rtl/gpio_iocell.v"

module gpio_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter GPIO_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    // ── AXI4-Full Slave (S6) ─────────────────────────────────────────────────
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

    // ── GPIO IO pads (split for simulation) ──────────────────────────────────
    output wire [GPIO_WIDTH-1:0]    gpio_out,   // pad output data
    output wire [GPIO_WIDTH-1:0]    gpio_oe,    // pad output enable
    input  wire [GPIO_WIDTH-1:0]    gpio_in,    // pad input data

    // ── IRQ to PLIC ───────────────────────────────────────────────────────────
    output wire                     gpio_irq
);

    // Internal wires between regfile and iocell
    wire [GPIO_WIDTH-1:0] dir_reg_w;
    wire [GPIO_WIDTH-1:0] dout_reg_w;
    wire [GPIO_WIDTH-1:0] irq_en_w;
    wire [GPIO_WIDTH-1:0] irq_mode_w;
    wire [GPIO_WIDTH-1:0] irq_pol_w;
    wire [GPIO_WIDTH-1:0] din_sync_w;
    wire [GPIO_WIDTH-1:0] irq_raw_w;

    gpio_regfile #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .GPIO_WIDTH (GPIO_WIDTH)
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

        .dir_reg   (dir_reg_w),
        .dout_reg  (dout_reg_w),
        .irq_en    (irq_en_w),
        .irq_mode  (irq_mode_w),
        .irq_pol   (irq_pol_w),
        .din_sync  (din_sync_w),
        .irq_raw   (irq_raw_w)
    );

    gpio_iocell #(
        .GPIO_WIDTH (GPIO_WIDTH)
    ) u_iocell (
        .clk          (clk),
        .rst_n        (rst_n),
        .gpio_in_pad  (gpio_in),
        .dir_reg      (dir_reg_w),
        .dout_reg     (dout_reg_w),
        .gpio_out_pad (gpio_out),
        .gpio_oe_pad  (gpio_oe),
        .din_sync     (din_sync_w),
        .irq_en       (irq_en_w),
        .irq_mode     (irq_mode_w),
        .irq_pol      (irq_pol_w),
        .irq_raw      (irq_raw_w),
        .gpio_irq     (gpio_irq)
    );

endmodule
