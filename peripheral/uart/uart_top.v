// ============================================================================
// Module  : uart_top
// Project : RISC-V SoC
//
// UART peripheral 8N1 với AXI4-Full slave interface.
// Địa chỉ: S5 = 0x5000_0000, kích thước 4KB
//
// Hierarchy:
//   uart_top
//   ├── uart_axi_slave   — AXI4-Full register access + thanh ghi CTRL/STATUS
//   ├── uart_baud_gen    — baud rate divider, tạo tick_tx và tick_rx16
//   ├── uart_fifo (tx)   — TX FIFO 8-bit × 16 deep
//   ├── uart_fifo (rx)   — RX FIFO 8-bit × 16 deep
//   ├── uart_tx          — TX shift register FSM (8N1)
//   ├── uart_rx          — RX sampler FSM (x16 oversample)
//   └── uart_irq_gen     — edge-detect IRQ generator
//
// Bản đồ thanh ghi (offset từ base 0x5000_0000):
//   0x00  TX_DATA    WO  [7:0]   ghi byte ra UART TX
//   0x04  RX_DATA    RO  [7:0]   đọc byte từ UART RX
//   0x08  STATUS     RO  [4:0]   {rx_overrun, rx_full, rx_empty, tx_full, tx_empty}
//   0x0C  CTRL       RW  [1:0]   {rx_irq_en, tx_irq_en}
//   0x10  BAUD_DIV   RW  [15:0]  divisor = clk_freq/baud - 1 (default 867 = 115200@100MHz)
//   0x14  IRQ_STATUS RW1C[1:0]   {rx_valid_irq, tx_empty_irq} ghi 1 để xóa
//
// Kết nối vào soc_top.v:
//   uart_top #(
//       .AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32), .AXI_ID_WIDTH(4)
//   ) u_uart (
//       .clk        (clk),
//       .rst_n      (periph_rst_n),    // từ clk_reset_ctrl
//       .s_axi_*    (s5_*),            // Slave port S5 của crossbar
//       .uart_tx    (uart_tx_pad),
//       .uart_rx    (uart_rx_pad),
//       .irq_out    (uart_irq)         // → PLIC source [0]
//   );
// ============================================================================

`include "peripheral/uart/rtl/uart_axi_slave.v"
`include "peripheral/uart/rtl/uart_baud_gen.v"
`include "peripheral/uart/rtl/uart_fifo.v"
`include "peripheral/uart/rtl/uart_tx.v"
`include "peripheral/uart/rtl/uart_rx.v"
`include "peripheral/uart/rtl/uart_irq_gen.v"

module uart_top #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4,
    parameter TX_FIFO_DEPTH  = 16,
    parameter RX_FIFO_DEPTH  = 16
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // =========================================================================
    // AXI4-Full Slave Interface (từ crossbar S5)
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
    // UART IO pads
    // =========================================================================
    output wire uart_tx,
    input  wire uart_rx,

    // =========================================================================
    // Interrupt → PLIC source [0]
    // =========================================================================
    output wire irq_out,
    output wire uart_active
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // Baud gen → TX, RX
    wire tick_tx, tick_rx16;

    // AXI slave → TX FIFO
    wire [7:0] reg_tx_data;
    wire       reg_tx_push;

    // AXI slave → RX FIFO (pop)
    wire       reg_rx_pop;

    // TX FIFO → TX shift
    wire [7:0] tx_fifo_dout;
    wire       tx_fifo_full, tx_fifo_empty;
    wire       tx_fifo_pop;   // từ uart_tx
    wire       tx_busy_w;

    // RX FIFO ← RX sampler
    wire [7:0] rx_fifo_din;
    wire       rx_fifo_push;
    wire       rx_fifo_full, rx_fifo_empty;

    // AXI slave → RX FIFO dout
    wire [7:0] rx_fifo_dout;

    // Status
    wire rx_overrun_w;

    // Config
    wire [15:0] reg_baud_div;
    wire        reg_rx_irq_en, reg_tx_irq_en;

    // IRQ
    wire tx_empty_irq_w, rx_valid_irq_w;

    // =========================================================================
    // uart_axi_slave
    // =========================================================================
    uart_axi_slave #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH)
    ) u_axi (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rid       (s_axi_rid),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .reg_tx_data     (reg_tx_data),
        .reg_tx_push     (reg_tx_push),
        .tx_fifo_full    (tx_fifo_full),
        .tx_fifo_empty   (tx_fifo_empty),
        .reg_rx_data     (rx_fifo_dout),
        .reg_rx_pop      (reg_rx_pop),
        .rx_fifo_full    (rx_fifo_full),
        .rx_fifo_empty   (rx_fifo_empty),
        .rx_overrun      (rx_overrun_w),
        .reg_baud_div    (reg_baud_div),
        .reg_rx_irq_en   (reg_rx_irq_en),
        .reg_tx_irq_en   (reg_tx_irq_en),
        .tx_empty_irq_in (tx_empty_irq_w),
        .rx_valid_irq_in (rx_valid_irq_w),
        .irq_out         (irq_out)
    );

    // =========================================================================
    // uart_baud_gen
    // =========================================================================
    uart_baud_gen u_baud (
        .clk      (clk),
        .rst_n    (rst_n),
        .divisor  (reg_baud_div),
        .tick_tx  (tick_tx),
        .tick_rx16(tick_rx16)
    );

    // =========================================================================
    // TX FIFO
    // =========================================================================
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

    // =========================================================================
    // uart_tx
    // =========================================================================
    uart_tx u_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick_tx   (tick_tx),
        .fifo_dout (tx_fifo_dout),
        .fifo_empty(tx_fifo_empty),
        .fifo_pop  (tx_fifo_pop),
        .tx_out    (uart_tx),
        .tx_busy   (tx_busy_w)
    );

    // =========================================================================
    // RX FIFO
    // =========================================================================
    uart_fifo #(.DEPTH(RX_FIFO_DEPTH)) u_rx_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .din        (rx_fifo_din),
        .push       (rx_fifo_push),
        .full       (rx_fifo_full),
        .almost_full(),
        .dout       (rx_fifo_dout),
        .pop        (reg_rx_pop),
        .empty      (rx_fifo_empty),
        .count      ()
    );

    // =========================================================================
    // uart_rx
    // =========================================================================
    uart_rx u_rx (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick_rx16 (tick_rx16),
        .rx_in     (uart_rx),
        .fifo_full (rx_fifo_full),
        .fifo_din  (rx_fifo_din),
        .fifo_push (rx_fifo_push),
        .rx_overrun(rx_overrun_w)
    );

    // =========================================================================
    // uart_irq_gen
    // =========================================================================
    uart_irq_gen u_irq (
        .clk          (clk),
        .rst_n        (rst_n),
        .tx_fifo_empty(tx_fifo_empty),
        .rx_fifo_empty(rx_fifo_empty),
        .tx_empty_irq (tx_empty_irq_w),
        .rx_valid_irq (rx_valid_irq_w)
    );

    assign uart_active = tx_busy_w | !tx_fifo_empty | !rx_fifo_empty;

endmodule
