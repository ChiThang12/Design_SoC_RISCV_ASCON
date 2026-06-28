# Dual-Core Firmware Scenarios

Current suite is limited to scenarios that are valid with the present P0/P3 RTL:
- both cores execute the same image
- `CPU1` does not yet have a separate `hart_id`, interrupt path, or debug path
- coherent DMA multicore scenarios remain a later-phase item
- top-level automatic `CPU miss -> peer snoop` is not wired yet

Available tests:
- `test_dualcore_basic.c`: dual-core liveness and shared DMEM heartbeat
- `test_dualcore_cache_sweep.c`: multi-line DCache traffic on both cores
- `test_dualcore_fence_flush.c`: repeated writeback visibility using `fence w,w`

Related RTL protocol check:
- `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`: directed `CPU0 write -> CPU1 observe` coherency-protocol scenario outside the firmware flow

Build example:
```bash
cd gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_basic.c -o tests_dualcore/test_dualcore_basic.hex -c
```

Recommended validation order:
```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. -o /tmp/tb_dcache_dualcore_protocol.out cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v
vvp /tmp/tb_dcache_dualcore_protocol.out
bash run_dualcore_suite.sh
```
