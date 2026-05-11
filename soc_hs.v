`timescale 1ns/1ps

// ============================================================================
// soc_hs.v  —  RISC-V Research SoC Physical Wrapper (Pad Ring)
//
// Đây là module top-level dành cho tổng hợp (Synthesis) và mô phỏng (Simulation).
// Nó bọc lấy `soc_top` và khởi tạo các cell vật lý (IO Pads) như IOBUF, OBUFT
// để giao tiếp với các chân 2 chiều (inout) trên chip thật.
// ============================================================================

`include "soc_top.v"

module soc_hs #(
    parameter SIM_MODE       = 0,                          // 0=UART boot (HW), 1=fast $readmemh (sim)
    parameter IMEM_INIT_FILE = "memory/program.hex"        // Hex image to load in SIM_MODE=1
)(
    // ── Clock & Reset ──────────────────────────────
    input  wire clk_in,      // Hoặc XTAL_IN (dao động thạch anh)
    input  wire por_n,       // Power-On Reset pad
    input  wire ext_rst_n,   // External reset pad

    // ── UART ───────────────────────────────────────
    output wire uart_tx,
    input  wire uart_rx,

    // ── JTAG (Debug) ───────────────────────────────
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output wire tdo,         // Tri-state output

    // ── SPI (Stub — chưa có module thực) ───────────
    output wire spi_sck,
    output wire spi_mosi,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire spi_miso,    // unused hiện tại (SPI stub)
    /* verilator lint_on  UNUSEDSIGNAL */
    output wire spi_cs_n,

    // ── GPIO ───────────────────────────────────────
    inout  wire [31:0] gpio, // Inout pad vật lý (Bi-directional)

    // ── WDT reset request ──────────────────────────
    output wire wdt_rst_req  // Active-high, từ watchdog → external supervisor/PMU
);

    // ========================================================================
    // Tín hiệu nội bộ giao tiếp với soc_top
    // ========================================================================
    wire [31:0] core_gpio_out;
    wire [31:0] core_gpio_oe;
    wire [31:0] core_gpio_in;

    wire core_tdo;
    wire core_tdo_en;

    wire core_wdt_rst_req;

    // ========================================================================
    // Khởi tạo soc_top
    // ========================================================================
    soc_top #(.SIM_MODE(SIM_MODE), .IMEM_INIT_FILE(IMEM_INIT_FILE)) u_soc_top (
        .clk         (clk_in),
        .por_n       (por_n),
        .ext_rst_n   (ext_rst_n),
        
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        
        .tck         (tck),
        .tms         (tms),
        .tdi         (tdi),
        .tdo         (core_tdo),
        .tdo_en      (core_tdo_en),
        
        .gpio_out    (core_gpio_out),
        .gpio_oe     (core_gpio_oe),
        .gpio_in     (core_gpio_in),
        
        .wdt_rst_req (core_wdt_rst_req)
    );

    assign wdt_rst_req = core_wdt_rst_req;

    // ========================================================================
    // Khởi tạo IO Pad Cells (Standard Verilog inference)
    // ========================================================================

    // ── GPIO (Bi-directional) ───────────────────────────────────────────────
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : gen_gpio_pad
            assign gpio[i] = core_gpio_oe[i] ? core_gpio_out[i] : 1'bz;
            assign core_gpio_in[i] = gpio[i];
        end
    endgenerate

    // ── JTAG TDO (Tri-state Output) ─────────────────────────────────────────
    assign tdo = core_tdo_en ? core_tdo : 1'bz;

    // ── SPI (Stub/Tie-off cho tương lai) ────────────────────────────────────
    assign spi_sck  = 1'b0;
    assign spi_mosi = 1'b0;
    assign spi_cs_n = 1'b1;
    // spi_miso is unused right now

endmodule
