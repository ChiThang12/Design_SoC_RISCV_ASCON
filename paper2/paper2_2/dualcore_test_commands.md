# Lệnh Test Dual-Core

Thư mục gốc workspace:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
```

## 1. Build một firmware image

Ví dụ cho `test_dualcore_basic`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_basic.c -o tests_dualcore/test_dualcore_basic.hex -c
```

Ví dụ cho `test_dualcore_cache_sweep`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_cache_sweep.c -o tests_dualcore/test_dualcore_cache_sweep.hex -c
```

Ví dụ cho `test_dualcore_fence_flush`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_fence_flush.c -o tests_dualcore/test_dualcore_fence_flush.hex -c
```

## 2. Chạy một kịch bản SoC dual-core

Ví dụ cho `test_dualcore_basic`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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

Ví dụ cho `test_dualcore_cache_sweep`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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

Ví dụ cho `test_dualcore_fence_flush`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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

Ví dụ cho `test_dualcore_peer_snoop`:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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

## 3. Chạy toàn bộ SoC dual-core suite

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
bash run_dualcore_suite.sh
```

## 3a. Chạy proof ASCON dual-core DMA coherency ổn định

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_ascon_dma_coherent.c -o tests_dualcore/test_dualcore_ascon_dma_coherent.hex -c
```

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.hex"' \
  -DSCENARIO_NAME='"test_dualcore_ascon_dma_coherent"' \
  -DEXPECT_SIG0=32'hA5C0_2301 \
  -DEXPECT_SIG1=32'hD24A_6003 \
  -DHEARTBEAT_MIN=4 \
  -DDC_REQ_MIN=8 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0=32'hAC03_D003 \
  -DGPIO_CHECK_ENABLE=1 \
  -DEXPECT_GPIO=32'hAC03_D003 \
  -DTIMEOUT_CYCLES=260000 \
  -o /tmp/test_dualcore_ascon_dma_coherent.out tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_ascon_dma_coherent.out
```

Trạng thái kỳ vọng hiện tại:
- build PASS
- SoC-level run PASS
- Snapshot PASS kỳ vọng:
  - `heartbeat=4`
  - `shared_count=1`
  - `aux0=ac03d003`
  - `aux1=00000000`
  - `core0_dc_req_count=12437`
  - `core1_dc_req_count=12527`
  - `dcache0 writes=4191 hits=12398`
  - `dcache1 writes=4183 hits=12522`
  - `dcache0 peer_snp_reqs=1 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=11`
  - `dcache1 peer_snp_reqs=0 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=5`

## 4. Chạy coherency-protocol TB

Đây là kiểm tra nhỏ nhất, tập trung vào:
- `CPU0 write dirty line -> CPU1 read miss -> automatic peer snoop -> CPU1 observe latest data`
- direct cache-to-cache forwarding on peer-snoop hit without requester memory refill
- DMA-style coherent read from latest cache owner
- DMA-style coherent invalidate forcing dirty writeback and invalidation

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -o /tmp/tb_dcache_dualcore_protocol.out \
  cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v
vvp /tmp/tb_dcache_dualcore_protocol.out
```

## 5. Chạy standalone DCache regressions

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. -o /tmp/tb_dcache.out cache_interface/dcache/tb/tb_dcache.v
vvp /tmp/tb_dcache.out
```

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. -o /tmp/tb_dcache_snoop.out cache_interface/dcache/tb/tb_dcache_snoop.v
vvp /tmp/tb_dcache_snoop.out
```

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. -o /tmp/tb_dcache_mesi.out cache_interface/dcache/tb/tb_dcache_mesi.v
vvp /tmp/tb_dcache_mesi.out
```

## 6. Chạy standalone ASCON DMA regression

Phần này kiểm tra primitive path coherent của DMA engine, gồm:
- coherent read snoop hit through `coh_ctrl=2'b11`
- coherent write invalidate before AXI writeback
- error handling and AXI backpressure behavior after snoop-arbiter updates

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. -o /tmp/tb_ascon_dma.out ascon/dma/tb/tb_ascon_dma.v
vvp /tmp/tb_ascon_dma.out
```

## 7. Thứ tự chạy đề xuất khi xác thực dual-core

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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

## 8. Khoảng trống hiện tại trước H1/H3

- `tb_dcache_dualcore_protocol.v` hiện chứng minh automatic CPU read-miss peer snoop at DCache/snoop-bus level.
- `tb_dcache_dualcore_protocol.v` hiện cũng chứng minh direct cache-to-cache forwarding with:
  - `peer_snoop_reqs`
  - `peer_snoop_hits`
  - `c2c_fwds`
  - `c2c_fill_cycles`
  - `mem_refills`
- `tb_ascon_dma.v` hiện chứng minh standalone ASCON DMA coherent primitive path.
- `soc_top.v` hiện nối cả hai DCache miss-snoop initiator qua snoop arbiter.
- Bộ firmware ổn định hiện cũng có `test_dualcore_peer_snoop.c`, chứng minh `CPU0 dirty write -> CPU1 read same line` at top-level firmware level.
- `test_dualcore_ascon_dma_coherent.c` hiện chứng minh full ASCON DMA engine end-to-end coherency at SoC dual-core level.
- Các snoop arbiter và snoop bus đã được cập nhật và verify lại to reduce starvation risk and improve response robustness.
- Đường CPU miss hiện hỗ trợ direct cache-to-cache forwarding when peer snoop returns a hit.
- `CPU1` now has `mhartid = 1` and shared IRQ/debug request wiring, but separate per-hart interrupt routing and debug path are still partial.
- Phần còn lại trước khi có gói paper H1/H3 hoàn chỉnh là:
  - H3 context plumbing and context-switch benchmarks
  - H1 compute-in-cache metadata and latency/throughput benchmarks
  - throughput contention khi CPU và DMA cùng hoạt động
  - báo cáo cache miss/hit theo từng core
