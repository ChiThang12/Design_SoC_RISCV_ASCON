`timescale 1ns/1ps

module fpga_top (
    input  wire        clk_in,
    input  wire        por_n,
    input  wire        ext_rst_n,

    output wire        uart_tx,
    input  wire        uart_rx,

    input  wire        tck,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo,

    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    inout  wire [31:0] gpio,

    output wire        wdt_rst_req,
    output wire        led_heartbeat
);

    soc_hs #(
        .SIM_MODE(0),
        .ENABLE_CPU1(0)
    ) u_soc_hs (
        .clk_in     (clk_in),
        .por_n      (por_n),
        .ext_rst_n  (ext_rst_n),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
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
