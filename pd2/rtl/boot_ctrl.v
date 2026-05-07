`timescale 1ns/1ps

// ============================================================================
// boot_ctrl.v — Boot Controller (Top Wrapper)
//
// Hierarchy:
//   boot_ctrl
//   ├── boot_rom   — holds program image (loaded via $readmemh)
//   └── boot_fsm   — FSM that copies ROM → IMEM via sideband port
//
// Usage in soc_top:
//   boot_ctrl u_boot (
//       .clk       (clk),
//       .rst_n     (fabric_rst_n),
//       .boot_we   (imem_boot_we),
//       .boot_addr (imem_boot_addr),
//       .boot_wdata(imem_boot_wdata),
//       .boot_done (boot_done)
//   );
//   // CPU reset held until boot_done:
//   // combined_cpu_rst_n = combined_rst_n & ndm_rst_n & boot_done
// ============================================================================

// `include "boot/rtl/boot_rom.v"
// `include "boot/rtl/boot_fsm.v"

module boot_ctrl #(
    parameter BOOT_FILE  = "memory/program.hex",
    parameter PROG_WORDS = 2048          // must match IMEM_SIZE/4
)(
    input  wire        clk,
    input  wire        rst_n,            // fabric_rst_n

    // IMEM sideband write port
    output wire        boot_we,
    output wire [31:0] boot_addr,        // byte address into IMEM
    output wire [31:0] boot_wdata,

    // Signals CPU reset release
    output wire        boot_done
);

    localparam ADDR_W = $clog2(PROG_WORDS);

    wire [ADDR_W-1:0] rom_addr;
    wire [31:0]       rom_data;

    boot_rom #(
        .BOOT_FILE  (BOOT_FILE),
        .PROG_WORDS (PROG_WORDS)
    ) u_rom (
        .addr (rom_addr),
        .data (rom_data)
    );

    boot_fsm #(
        .PROG_WORDS (PROG_WORDS)
    ) u_fsm (
        .clk        (clk),
        .rst_n      (rst_n),
        .rom_addr   (rom_addr),
        .rom_data   (rom_data),
        .boot_we    (boot_we),
        .boot_addr  (boot_addr),
        .boot_wdata (boot_wdata),
        .boot_done  (boot_done)
    );

endmodule
