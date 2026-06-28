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

## 3. Run the whole SoC dual-core suite

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
bash run_dualcore_suite.sh
```

## 4. Run the directed coherency-protocol TB

This is the smallest targeted check for `CPU0 write -> CPU1 observe` at DCache/snoop level.

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

## 6. Suggested execution order when validating dual-core

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
bash run_dualcore_suite.sh
```

## 7. Current gaps before claiming a complete dual-core coherency flow

- `tb_soc/tb_soc_dualcore_suite.v` proves dual-core execution and shared-memory traffic, but not automatic cache-to-cache snoop on a CPU miss.
- `tb_dcache_dualcore_protocol.v` proves the responder side of the protocol, but it is still a directed TB, not a full top-level CPU-initiated coherency path.
- `soc_top.v` still needs the path for `CPU1 miss -> snoop peer cache owner -> return latest line / force ownership transition`.
- DMA multicore coherency is still pending for both read-side snoop and write-side invalidate ordering.
- `CPU1` control-plane support is still partial: no separate `hart_id`, interrupt routing, or debug path yet.
