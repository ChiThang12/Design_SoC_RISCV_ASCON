# FreeRTOS Minimal Port Notes

This directory is the staging area for the real FreeRTOS machine-mode port.

Current Phase 4 status:

- `gnu_toolchain/test_os/test_freertos_smoke.c` is the executable smoke test.
- It validates the port contract before importing the upstream FreeRTOS kernel.
- `gnu_toolchain/test_os/test_freertos_kernel_smoke.c` is the real
  FreeRTOS-Kernel smoke test.
- `soc_os/run_phase4_freertos_kernel_smoke.sh` links the kernel objects and
  runs the simulation gate.
- Phase 4 simulation is closed: 3/3 runs PASS with two same-priority tasks,
  CLINT tick, `taskYIELD()`, `ecall` trap, context switch, and UART PASS.
- Firmware is loaded from the testbench through `IMEM_INIT_FILE`; no RTL-side
  hardcoded firmware path is required.
- Latest simulation sweep on 2026-08-03: Phase 1 P0, Phase 2, Phase 3, and
  Phase 4 all PASS.

Bring-up contract:

- ISA: RV32IM + Zicsr
- Privilege: machine mode only
- Tick source: CLINT `mtime/mtimecmp`
- Synchronous yield trap: machine-mode `ecall`, `mcause=11`
- UART: `0x50000000`
- CLINT: `0x40000000`
- DMEM data/bss budget: first 4 KB for the real kernel smoke
- Stack region: `0x10001000..0x10001FEF`

Closed simulation gate:

```sh
bash soc_os/run_phase1_p0.sh
bash soc_os/run_phase2_minirtos.sh
bash soc_os/run_phase3_freertos_smoke.sh
bash soc_os/run_phase4_freertos_kernel_smoke.sh
```

Next hardware step:

1. Build the same single-core profile for FPGA.
2. Load `gnu_toolchain/test_os/test_freertos_kernel_smoke.hex` through the
   established firmware-load path.
3. Capture UART boot/PASS log on board.
4. Only after board PASS, start timing push toward 125/150/200 MHz.
