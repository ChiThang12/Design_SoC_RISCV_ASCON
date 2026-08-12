# Firmware Load Contract

Updated: 2026-08-02

This note locks the firmware loading mechanism for the current SoC/FreeRTOS bring-up.

## Current Contract

- The CPU does not fetch from an IMEM that directly initializes itself with a fixed internal `program.hex`.
- `soc_top` holds `cpu_rst_n` low until `boot_done`.
- `uart_boot_ctrl` loads firmware into IMEM through the IMEM sideband write port.
- After the sideband copy is complete, `boot_done` releases CPU reset and the CPU starts fetching from IMEM address `0x00000000`.

## Simulation Flow

Simulation uses `SIM_MODE=1` for speed:

- `run_soc_ascon.v` instantiates `soc_hs` with `.SIM_MODE(1)`.
- The firmware image is selected from the testbench side through `IMEM_INIT_FILE` or runtime plusarg `+IMEM_HEX=<path>`.
- `uart_boot_ctrl.g_sim` reads that external hex file and copies it into IMEM one word per cycle.
- `memory/inst_mem_axi_slave.v` treats `MEM_INIT_FILE` as unused; IMEM is loaded by the boot sideband path.

Preferred regression flow:

```bash
bash regression_full.sh -b test_timer test_gpio test_clint test_plic
```

Preferred one-off runtime-override flow:

```bash
iverilog -g2005 -o /tmp/run_soc_ascon.vvp run_soc_ascon.v
vvp /tmp/run_soc_ascon.vvp +IMEM_HEX=gnu_toolchain/tests/test_plic.hex
```

## FPGA Flow

Synthesis/default hardware uses `SIM_MODE=0`:

- `uart_boot_ctrl.g_uart` receives bytes from UART RX.
- Host sends exactly `PROG_WORDS * 4` bytes, little-endian per 32-bit word.
- Each completed word is written to IMEM through the sideband boot port.
- `boot_done` asserts only after the full image is received.

## Phase 1 Decision

For pre-RTOS simulation, firmware selection from the testbench is considered closed when:

- P0 tests pass using `regression_full.sh -b ...`.
- At least one smoke run passes using runtime `+IMEM_HEX=<hex>` without copying into `memory/program.hex`.
- No production IMEM SRAM path directly depends on a fixed internal `$readmemh("program.hex", ...)`.
