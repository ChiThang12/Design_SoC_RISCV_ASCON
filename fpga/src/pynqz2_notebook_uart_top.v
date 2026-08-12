`timescale 1ns/1ps

module pynqz2_notebook_uart_top #(
    parameter integer BAUD_DIV = 868
)(
    input  wire       clk_in,
    input  wire       por_n,
    input  wire       ext_rst_n,

    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tkeep,
    input  wire       s_axis_tvalid,
    input  wire       s_axis_tlast,
    output wire       s_axis_tready,

    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tkeep,
    output wire       m_axis_tvalid,
    output wire       m_axis_tlast,
    input  wire       m_axis_tready,

    input  wire       tck,
    input  wire       tms,
    input  wire       tdi,
    output wire       tdo,

    output wire       spi_sck,
    output wire       spi_mosi,
    input  wire       spi_miso,
    output wire       spi_cs_n,

    inout  wire [31:0] gpio,
    output wire       wdt_rst_req,
    output wire       led_heartbeat
);
    wire soc_uart_rx;
    wire soc_uart_tx;

    axis_uart_bridge #(
        .BAUD_DIV(BAUD_DIV)
    ) u_notebook_uart_bridge (
        .clk             (clk_in),
        .rst_n           (ext_rst_n),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tkeep    (s_axis_tkeep),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tlast    (s_axis_tlast),
        .s_axis_tready   (s_axis_tready),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tkeep    (m_axis_tkeep),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tlast    (m_axis_tlast),
        .m_axis_tready   (m_axis_tready),
        .uart_tx_to_soc  (soc_uart_rx),
        .uart_rx_from_soc(soc_uart_tx)
    );

    soc_hs #(
        .SIM_MODE(0),
        .ENABLE_CPU1(0)
    ) u_soc_hs (
        .clk_in     (clk_in),
        .por_n      (por_n),
        .ext_rst_n  (ext_rst_n),
        .uart_tx    (soc_uart_tx),
        .uart_rx    (soc_uart_rx),
        .tck        (tck),
        .tms        (tms),
        .tdi        (tdi),
        .tdo        (tdo),
        .spi_sck    (spi_sck),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n),
        .gpio       (gpio),
        .wdt_rst_req(wdt_rst_req),
        .led_heartbeat(led_heartbeat)
    );
endmodule
