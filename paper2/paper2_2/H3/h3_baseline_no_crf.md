# Baseline no-CRF Reference

Ngày cập nhật: 2026-06-30

## Mục tiêu P0

Baseline no-CRF dùng cùng SoC dual-core testbench, cùng đường AXI/MMIO, cùng CPU-direct ASCON workload với H3, nhưng không dùng `CONTEXT_SEL`/CRF. Mỗi lần đổi session, firmware phải `SOFT_RST` core và reload toàn bộ register:

- `MODE`
- `KEY_0..KEY_3`
- `NONCE_0..NONCE_3`
- `PTEXT_0..PTEXT_1`
- `DATA_LEN`

## RTL/Firmware đã chỉnh

- `soc_top.v`: thêm `-DUSE_ASCON_BASELINE` để chọn `ascon_baseline/ascon_top.v`.
- `ascon/ascon_top.v` và `ascon_baseline/ascon_top.v`: nối `slave_core_soft_rst` vào reset nội bộ của `ascon_CORE`.
- `ascon/interface/ascon_axi_slave.v` và `ascon_baseline/interface/ascon_axi_slave.v`: clear sticky `STATUS.CORE_DONE` khi có `core_start`, tránh firmware đọc DONE cũ.
- `test_dualcore_baseline_reload_context.c`: dùng `configure_s0()`/`configure_s1()` hardcoded, tránh lỗi truyền quá nhiều tham số trên RV32 path.

## Lệnh build

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_baseline_reload_context.c -o tests_dualcore/test_dualcore_baseline_reload_context.hex -O 2
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_context.c -o tests_dualcore/test_dualcore_h3_context.hex -O 2
```

## Lệnh simulate baseline no-CRF

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DUSE_ASCON_BASELINE \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_baseline_reload_context.hex"' \
  -DSCENARIO_NAME='"test_dualcore_baseline_reload_context"' \
  -DEXPECT_SIG0="32'h3C100001" \
  -DEXPECT_SIG1="32'h3C100002" \
  -DHEARTBEAT_MIN=4 \
  -DDC_REQ_MIN=12 \
  -DTIMEOUT_CYCLES=300000 \
  -o /tmp/test_dualcore_baseline_context.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_baseline_context.out
```

## Kết quả PASS

Baseline no-CRF:

```text
[PASS] test_dualcore_baseline_reload_context
cycles=25078
heartbeat=4 shared_count=2
core0_dc_req_count=1871 core1_dc_req_count=95
```

H3 cùng context proof:

```text
[PASS] test_dualcore_h3_context
cycles=24680
heartbeat=4 shared_count=2
core0_dc_req_count=1835 core1_dc_req_count=73
```

## Control overhead

Từ `BASELINE_REG_TRACE` trên baseline proof:

| Segment | Window | Cycles |
|---|---:|---:|
| S0 initial reload | `SOFT_RST` write cycle 3429 -> `DATA_LEN` write cycle 3657 | 228 |
| S1 reload | `SOFT_RST` write cycle 23875 -> `DATA_LEN` write cycle 24058 | 183 |
| S0 reload again | `SOFT_RST` write cycle 24497 -> `DATA_LEN` write cycle 24693 | 196 |

Average baseline reload control overhead: `(228 + 183 + 196) / 3 = 202.3 cycles`.

Reference H3 context switch from existing H3 benchmark doc: `CONTEXT_SEL` interval `36 cycles`.

Direct control-overhead reduction: `202.3 / 36 = 5.62x`.

## Throughput note

CPU-direct active wait from trace is about `23..40 cycles` for a 64-bit block depending on firmware polling alignment. At 100 MHz:

- best observed: `64 bits / 23 cycles = 278.3 Mbps`
- average observed from S0/S1/S0 windows approx: `64 bits / 32 cycles = 200 Mbps`

This is a firmware-visible polling throughput, not raw standalone core throughput.

## Ghi chú benchmark

`test_dualcore_baseline_reload_benchmark.c` hiện được giữ trong tree nhưng chưa dùng làm headline chính: reload sweep dùng `rdcycle` + nhiều MMIO write dồn dập có thể làm DCache/MMIO replay trong mô phỏng. P0 headline dùng functional context proof có trace, vì nó chạy đúng workload S0 -> S1 -> S0 và chứng minh reload no-CRF thật.

Trong paper mới, baseline này là reference control-plane model để so với DMA-first path, không phải trung tâm câu chuyện.
