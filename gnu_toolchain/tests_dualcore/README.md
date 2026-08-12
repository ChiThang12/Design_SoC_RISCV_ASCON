# Dual-Core Firmware Scenarios

Current stable suite targets scenarios that are valid with the present P0/P3 RTL:
- both cores execute the same image
- `CPU0` reports `mhartid = 0`; `CPU1` reports `mhartid = 1`
- `CPU1` has shared IRQ/debug request wiring, but not a separate per-hart debug path yet
- automatic `CPU miss -> peer snoop` is implemented and covered by both the DCache protocol TB and a stable firmware suite case
- coherent ASCON DMA multicore proof still needs a stable SoC-level closure

Available tests:
- `test_dualcore_basic.c`: dual-core liveness and shared DMEM heartbeat
- `test_dualcore_cache_sweep.c`: multi-line DCache traffic on both cores
- `test_dualcore_fence_flush.c`: repeated writeback visibility using `fence w,w`
- `test_dualcore_peer_snoop.c`: firmware proof for `CPU0 dirty write -> CPU1 read same line` through automatic peer snoop
- `test_dualcore_h3_context.c`: H3 two-bank context isolation proof across CPU0/CPU1
- `test_dualcore_h3_benchmark.c`: H3 context-select interval and active crypto latency benchmark
- `test_dualcore_h3_busy_switch.c`: post-start context switch/reprogram regression using context-0 reference comparison
- `test_dualcore_h3_stress_switchback.c`: repeated `0 -> 1 -> 0 -> 1` context switch-back stress test
- `test_dualcore_h3_dma_context_smoke.c`: DMA start-context smoke test; testbench verifies `dma_context_id_active_w`

Experimental WIP:
- `test_dualcore_ascon_dma_coherent.c`: SoC-level ASCON DMA multicore coherency attempt for `CPU dirty source -> ASCON DMA coherent read` and `ASCON DMA coherent write -> invalidate stale output lines on both cores`
- `tb_soc/tb_soc_dualcore_suite.v` now has optional `GPIO_CHECK_ENABLE` / `EXPECT_GPIO` hooks to support non-cacheable completion signaling for that future closure
- `tb_soc/tb_soc_dualcore_suite.v` also has optional `DMA_CONTEXT_CHECK_ENABLE` / `EXPECT_DMA_CONTEXT` hooks for H3 DMA context sideband checks

Related RTL protocol check:
- `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`: DCache/snoop-bus protocol scenario covering automatic CPU read-miss peer snoop and DMA-style coherent read/invalidate outside the firmware flow

Build example:
```bash
cd gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_basic.c -o tests_dualcore/test_dualcore_basic.hex -c
```

Recommended validation order:
```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. -o /tmp/tb_dcache_dualcore_protocol.out cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v
vvp /tmp/tb_dcache_dualcore_protocol.out
bash run_dualcore_suite.sh
```
