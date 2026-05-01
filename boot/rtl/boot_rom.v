`timescale 1ns/1ps

// ============================================================================
// boot_rom.v — Boot ROM
//
// Stores program image loaded from a hex file at elaboration time.
// This is the ONLY place $readmemh is used in the SoC — IMEM itself is a
// blank SRAM; boot_ctrl copies this ROM into IMEM before releasing the CPU.
//
// Parameters:
//   BOOT_FILE  : path to Intel HEX / Verilog hex image
//   PROG_WORDS : number of 32-bit words in the boot image (default 2048 = 8 KB)
// ============================================================================

module boot_rom #(
    parameter BOOT_FILE  = "memory/program.hex",
    parameter PROG_WORDS = 2048
)(
    input  wire [$clog2(PROG_WORDS)-1:0] addr,
    output wire [31:0]                   data
);

    reg [31:0] rom [0:PROG_WORDS-1];

    initial begin : load_rom
        reg [8*256-1:0] hex_file;
        if (!$value$plusargs("IMEM_HEX=%s", hex_file))
            hex_file = BOOT_FILE;
        $readmemh(hex_file, rom);
        $display("[BOOT] Loaded: %0s (%0d words)", hex_file, PROG_WORDS);
    end

    assign data = rom[addr];

endmodule
