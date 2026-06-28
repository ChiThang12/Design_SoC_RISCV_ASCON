# Dual-Core Test Commands

Workspace root:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
```

## 1. Build a single firmware image

Example for `test_dualcore_basic`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_basic.c -o tests_dualcore/test_dualcore_basic.hex -c
```

Example for `test_dualcore_cache_sweep`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_cache_sweep.c -o tests_dualcore/test_dualcore_cache_sweep.hex -c
```

Example for `test_dualcore_fence_flush`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_fence_flush.c -o tests_dualcore/test_dualcore_fence_flush.hex -c
```

## 2. Run one SoC dual-core scenario

Example for `test_dualcore_basic`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_basic.hex"' \
  -DSCENARIO_NAME='"test_dualcore_basic"' \
  -DEXPECT_SIG0=32'hD00D_CAFE \
  -DEXPECT_SIG1=32'h1357_9BDF \
  -DHEARTBEAT_MIN=16 \
  -DDC_REQ_MIN=8 \
  -o /tmp/test_dualcore_basic.out tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_basic.out
```

Example for `test_dualcore_cache_sweep`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_cache_sweep.hex"' \
  -DSCENARIO_NAME='"test_dualcore_cache_sweep"' \
  -DEXPECT_SIG0=32'hCACE_0001 \
  -DEXPECT_SIG1=32'h2468_ACE0 \
  -DHEARTBEAT_MIN=20 \
  -DDC_REQ_MIN=24 \
  -o /tmp/test_dualcore_cache_sweep.out tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_cache_sweep.out
```

Example for `test_dualcore_fence_flush`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_fence_flush.hex"' \
  -DSCENARIO_NAME='"test_dualcore_fence_flush"' \
  -DEXPECT_SIG0=32'hFEC1_0001 \
  -DEXPECT_SIG1=32'h0BAD_F00D \
  -DHEARTBEAT_MIN=20 \
  -DDC_REQ_MIN=20 \
  -o /tmp/test_dualcore_fence_flush.out tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_fence_flush.out
```

Example for `test_dualcore_peer_snoop`:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_peer_snoop.hex"' \
  -DSCENARIO_NAME='"test_dualcore_peer_snoop"' \
  -DEXPECT_SIG0=32'h5A11_0001 \
  -DEXPECT_SIG1=32'hC001_D00D \
  -DHEARTBEAT_MIN=2 \
  -DDC_REQ_MIN=4 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0=32'hFACE_B00C \
  -DAUX1_CHECK_ENABLE=1 \
  -DEXPECT_AUX1=32'h2222_0001 \
  -o /tmp/test_dualcore_peer_snoop.out tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_peer_snoop.out
```

## 3. Run the whole SoC dual-core suite

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
bash run_dualcore_suite.sh
```

## 3a. Run the experimental ASCON dual-core coherency attempt

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_ascon_dma_coherent.c -o tests_dualcore/test_dualcore_ascon_dma_coherent.hex -c
```

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.hex"' \
  -DSCENARIO_NAME='"test_dualcore_ascon_dma_coherent"' \
  -DEXPECT_SIG0=32'hA5C0_2301 \
  -DEXPECT_SIG1=32'hD24A_6003 \
  -DHEARTBEAT_MIN=0 \
  -DDC_REQ_MIN=8 \
  -DGPIO_CHECK_ENABLE=1 \
  -DEXPECT_GPIO=32'hAC03_D003 \
  -DTIMEOUT_CYCLES=300000 \
  -o /tmp/test_dualcore_ascon_dma_coherent.out tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_ascon_dma_coherent.out
```

Expected current status:
- build PASS
- SoC-level run still TIMEOUT

## 4. Run the coherency-protocol TB

This is the smallest targeted check for:
- `CPU0 write dirty line -> CPU1 read miss -> automatic peer snoop -> CPU1 observe latest data`
- DMA-style coherent read from latest cache owner
- DMA-style coherent invalidate forcing dirty writeback and invalidation

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -o /tmp/tb_dcache_dualcore_protocol.out \
  cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v
vvp /tmp/tb_dcache_dualcore_protocol.out
```

## 5. Run the standalone DCache regressions

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. -o /tmp/tb_dcache.out cache_interface/dcache/tb/tb_dcache.v
vvp /tmp/tb_dcache.out
```

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. -o /tmp/tb_dcache_snoop.out cache_interface/dcache/tb/tb_dcache_snoop.v
vvp /tmp/tb_dcache_snoop.out
```

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. -o /tmp/tb_dcache_mesi.out cache_interface/dcache/tb/tb_dcache_mesi.v
vvp /tmp/tb_dcache_mesi.out
```

## 6. Run the standalone ASCON DMA regression

This verifies the DMA engine's coherent primitive path, including:
- coherent read snoop hit through `coh_ctrl=2'b11`
- coherent write invalidate before AXI writeback
- error handling and AXI backpressure behavior after snoop-arbiter updates

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. -o /tmp/tb_ascon_dma.out ascon/dma/tb/tb_ascon_dma.v
vvp /tmp/tb_ascon_dma.out
```

## 7. Suggested execution order when validating dual-core

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. -o /tmp/tb_dcache.out cache_interface/dcache/tb/tb_dcache.v
vvp /tmp/tb_dcache.out
iverilog -g2005 -I. -o /tmp/tb_dcache_snoop.out cache_interface/dcache/tb/tb_dcache_snoop.v
vvp /tmp/tb_dcache_snoop.out
iverilog -g2005 -I. -o /tmp/tb_dcache_mesi.out cache_interface/dcache/tb/tb_dcache_mesi.v
vvp /tmp/tb_dcache_mesi.out
iverilog -g2005 -I. -o /tmp/tb_dcache_dualcore_protocol.out cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v
vvp /tmp/tb_dcache_dualcore_protocol.out
iverilog -g2005 -I. -o /tmp/tb_ascon_dma.out ascon/dma/tb/tb_ascon_dma.v
vvp /tmp/tb_ascon_dma.out
bash run_dualcore_suite.sh
```

## 8. Current gaps before claiming a complete dual-core coherency flow

- `tb_dcache_dualcore_protocol.v` now proves automatic CPU read-miss peer snoop at DCache/snoop-bus level.
- `tb_ascon_dma.v` now proves the standalone ASCON DMA coherent primitive path.
- `soc_top.v` now wires both DCache miss-snoop initiators through the snoop arbiter.
- The stable firmware suite now also includes `test_dualcore_peer_snoop.c`, proving `CPU0 dirty write -> CPU1 read same line` at top-level firmware level.
- The snoop arbiters and snoop bus were refreshed and re-verified to reduce starvation risk and improve response robustness.
- The CPU miss path currently uses peer invalidate/writeback followed by refill; direct cache-to-cache data forwarding is not implemented.
- DMA-style snoop protocol is proven in the DCache protocol TB, but full ASCON DMA engine end-to-end coherency remains pending.
- `CPU1` now has `mhartid = 1` and shared IRQ/debug request wiring, but separate per-hart interrupt routing and debug path are still partial.
