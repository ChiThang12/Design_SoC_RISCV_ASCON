`timescale 1ns/1ps
// ============================================================================
// spi_top.v — SPI Master Peripheral (S7, base 0x5002_0000)
//
// Hierarchy:
//   spi_top
//   ├── spi_axi_slave  — AXI4-Full register file
//   ├── spi_core       — SPI master FSM (8-bit, MSB-first, 4 modes)
//   ├── uart_fifo (tx) — TX FIFO 8-bit × 16 deep (reuse từ UART)
//   └── uart_fifo (rx) — RX FIFO 8-bit × 16 deep
//
// Register map (offset từ 0x5002_0000):
//   0x00  TX_DATA    WO [7:0]   ghi byte vào TX FIFO
//   0x04  RX_DATA    RO [7:0]   đọc byte từ RX FIFO (auto-pop)
//   0x08  STATUS     RO [5:0]   {rx_overrun,rx_full,rx_empty,tx_full,tx_empty,busy}
//   0x0C  CTRL       RW [7:0]   {spi_en,cs_auto,cpol,cpha,--,--,rx_irq_en,tx_irq_en}
//   0x10  DIVIDER    RW [15:0]  SCK = clk/(2*(DIVIDER+1)), default=4→10MHz@100MHz
//   0x14  IRQ_STATUS RW1C [1:0] {rx_valid_irq, tx_empty_irq}
//   0x18  CS_CTRL    RW [3:0]   manual CS (khi CTRL[cs_auto]=0), active-low
//
// IO pads:
//   sck   — SPI clock output
//   mosi  — Master Out Slave In
//   miso  — Master In Slave Out
//   cs_n  — Chip Select[3:0], active-low
//
// Kết nối vào soc_top.v:
//   spi_top u_spi (
//       .clk      (clk),
//       .rst_n    (periph_rst_n),
//       .s_axi_*  (s7_*),
//       .sck      (spi_sck), .mosi (spi_mosi),
//       .miso     (spi_miso), .cs_n (spi_cs_n),
//       .irq_out  (spi_irq),
//       .tx_dma_req(spi_tx_dma_req),
//       .rx_dma_req(spi_rx_dma_req)
//   );
// ============================================================================

// `include "peripheral/spi/rtl/spi_axi_slave.v"
// `include "peripheral/spi/rtl/spi_core.v"
// `include "peripheral/uart/rtl/uart_fifo.v"

module spi_top #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter TX_FIFO_DEPTH  = 16,
    parameter RX_FIFO_DEPTH  = 16,
    parameter CS_WIDTH       = 4
)(
    input  wire clk,
    input  wire rst_n,

    // =========================================================================
    // AXI4-Full Slave (S7 từ crossbar)
    // =========================================================================
    input  wire [AXI_ID_WIDTH-1:0]    s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]                 s_axi_awlen,
    input  wire [2:0]                 s_axi_awsize,
    input  wire [1:0]                 s_axi_awburst,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]s_axi_wstrb,
    input  wire                       s_axi_wlast,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,
    output wire [AXI_ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]                 s_axi_bresp,
    output wire                       s_axi_bvalid,
    input  wire                       s_axi_bready,
    input  wire [AXI_ID_WIDTH-1:0]    s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]                 s_axi_arlen,
    input  wire [2:0]                 s_axi_arsize,
    input  wire [1:0]                 s_axi_arburst,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,
    output wire [AXI_ID_WIDTH-1:0]    s_axi_rid,
    output wire [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                       s_axi_rlast,
    output wire                       s_axi_rvalid,
    input  wire                       s_axi_rready,

    // =========================================================================
    // SPI IO pads
    // =========================================================================
    output wire                  sck,
    output wire                  mosi,
    input  wire                  miso,
    output wire [CS_WIDTH-1:0]   cs_n,

    // =========================================================================
    // IRQ → PLIC
    // =========================================================================
    output wire irq_out,

    // =========================================================================
    // DMA handshake — flow control cho periph mode
    // =========================================================================
    output wire tx_dma_req,   // TX FIFO có chỗ trống → DMA có thể ghi (mode 10)
    output wire rx_dma_req    // RX FIFO có data      → DMA có thể đọc (mode 01)
);

    // ── Internal wires ────────────────────────────────────────────────────────
    wire [7:0] reg_tx_data;
    wire       reg_tx_push;
    wire       tx_fifo_full, tx_fifo_empty;
    wire [7:0] tx_fifo_dout;
    wire       tx_fifo_pop;

    wire [7:0] reg_rx_data;
    wire       reg_rx_pop;
    wire       rx_fifo_full, rx_fifo_empty;
    wire [7:0] rx_fifo_din;
    wire       rx_fifo_push;
    wire       rx_overrun_w;

    wire [15:0] reg_divider;
    wire        reg_spi_en, reg_cs_auto, reg_cpol, reg_cpha;
    wire        reg_rx_irq_en, reg_tx_irq_en;
    wire [CS_WIDTH-1:0] reg_cs_ctrl;

    wire tx_empty_irq_w, rx_valid_irq_w;
    wire spi_busy_w;

    // DMA req: TX FIFO có chỗ / RX FIFO có data
    assign tx_dma_req = !tx_fifo_full;
    assign rx_dma_req = !rx_fifo_empty;

    // RX overrun: RX FIFO full nhưng core vẫn muốn push
    assign rx_overrun_w = rx_fifo_full & rx_fifo_push;

    // ── u_axi_slave ───────────────────────────────────────────────────────────
    spi_axi_slave #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH  (AXI_ID_WIDTH)
    ) u_axi_slave (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awid    (s_axi_awid),    .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awlen   (s_axi_awlen),   .s_axi_awsize  (s_axi_awsize),
        .s_axi_awburst (s_axi_awburst), .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),   .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wlast   (s_axi_wlast),   .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bid     (s_axi_bid),     .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),  .s_axi_bready  (s_axi_bready),
        .s_axi_arid    (s_axi_arid),    .s_axi_araddr  (s_axi_araddr),
        .s_axi_arlen   (s_axi_arlen),   .s_axi_arsize  (s_axi_arsize),
        .s_axi_arburst (s_axi_arburst), .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rid     (s_axi_rid),     .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),   .s_axi_rlast   (s_axi_rlast),
        .s_axi_rvalid  (s_axi_rvalid),  .s_axi_rready  (s_axi_rready),
        .reg_tx_data   (reg_tx_data),   .reg_tx_push   (reg_tx_push),
        .tx_fifo_full  (tx_fifo_full),  .tx_fifo_empty (tx_fifo_empty),
        .reg_rx_data   (reg_rx_data),   .reg_rx_pop    (reg_rx_pop),
        .rx_fifo_full  (rx_fifo_full),  .rx_fifo_empty (rx_fifo_empty),
        .rx_overrun    (rx_overrun_w),  .spi_busy      (spi_busy_w),
        .reg_divider   (reg_divider),
        .reg_spi_en    (reg_spi_en),    .reg_cs_auto   (reg_cs_auto),
        .reg_cpol      (reg_cpol),      .reg_cpha      (reg_cpha),
        .reg_rx_irq_en (reg_rx_irq_en), .reg_tx_irq_en (reg_tx_irq_en),
        .reg_cs_ctrl   (reg_cs_ctrl),
        .tx_empty_irq_in(tx_empty_irq_w),
        .rx_valid_irq_in(rx_valid_irq_w),
        .irq_out       (irq_out)
    );

    // ── TX FIFO ───────────────────────────────────────────────────────────────
    uart_fifo #(.DEPTH(TX_FIFO_DEPTH)) u_tx_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (reg_tx_data),
        .push       (reg_tx_push),
        .full       (tx_fifo_full),
        .almost_full(),
        .dout       (tx_fifo_dout),
        .pop        (tx_fifo_pop),
        .empty      (tx_fifo_empty),
        .count      ()
    );

    // ── RX FIFO ───────────────────────────────────────────────────────────────
    uart_fifo #(.DEPTH(RX_FIFO_DEPTH)) u_rx_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (rx_fifo_din),
        .push       (rx_fifo_push),
        .full       (rx_fifo_full),
        .almost_full(),
        .dout       (reg_rx_data),
        .pop        (reg_rx_pop),
        .empty      (rx_fifo_empty),
        .count      ()
    );

    // ── SPI Core ──────────────────────────────────────────────────────────────
    spi_core #(.CS_WIDTH(CS_WIDTH)) u_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .divider         (reg_divider),
        .spi_en          (reg_spi_en),
        .cpol            (reg_cpol),
        .cpha            (reg_cpha),
        .cs_auto         (reg_cs_auto),
        .cs_ctrl_manual  (reg_cs_ctrl),
        .tx_fifo_dout    (tx_fifo_dout),
        .tx_fifo_empty   (tx_fifo_empty),
        .tx_fifo_pop     (tx_fifo_pop),
        .rx_fifo_din     (rx_fifo_din),
        .rx_fifo_full    (rx_fifo_full),
        .rx_fifo_push    (rx_fifo_push),
        .sck             (sck),
        .mosi            (mosi),
        .miso            (miso),
        .cs_n            (cs_n),
        .busy            (spi_busy_w),
        .tx_empty_irq    (tx_empty_irq_w),
        .rx_valid_irq    (rx_valid_irq_w)
    );

endmodule
