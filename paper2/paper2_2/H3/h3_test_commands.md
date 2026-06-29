# Lệnh Test H3

Tại lap test H3 từ root repo:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_context.c -o tests_dualcore/test_dualcore_h3_context.hex -Ở 0
```

Elaborate testbench:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_context.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_context"' \
  -DEXPECT_SIG0="32'h3C000001" \
  -DEXPECT_SIG1="32'h3C000002" \
  -DHEARTBEAT_MIN=4 \
  -DDC_REQ_MIN=12 \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_context.out \
  tb_soc/tb_soc_dualcore_suite.v
```

Chạy mô phỏng:

```bash
vvp /tmp/test_dualcore_h3_context.out
```

Kết quả kỳ vọng:

```text
[PASS] test_dualcore_h3_context
```

## H3 Throughput / Context-Switch Benchmark

Build firmware benchmark:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON/gnu_toolchain
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_benchmark.c -o tests_dualcore/test_dualcore_h3_benchmark.hex -Ở 0
```

Elaborate với H3 event tracing:

```bash
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
iverilog -g2005 -I. \
  -DH3_BENCH_TRACE \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_benchmark.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_benchmark"' \
  -DEXPECT_SIG0="32'h3C00B001" \
  -DEXPECT_SIG1="32'h3C00B002" \
  -DHEARTBEAT_MIN=6 \
  -DDC_REQ_MIN=0 \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_benchmark.out \
  tb_soc/tb_soc_dualcore_suite.v
```

Chạy:

```bash
vvp /tmp/test_dualcore_h3_benchmark.out
```

Tóm tắt benchmark kỳ vọng:

```text
h3_core_ops=2 avg_active_cycles=13.00 min=13 max=13 avg_active_throughput_mbps=492.31
h3_context_switches=6 measured_intervals=5 avg_mmio_interval_cycles=36.00 min=36 max=36 rtl_select_latency_cycles=1
```

Ghi chú:

- Firmware dùng `-Ở 0` để tránh tối uu hóa MMIO.
- Benchmark H3 lay từ counter của testbench (`cycles`, DCache request, peer snoop, C2C forwarding).
- `AUX0/AUX1` chỉ là marker phụ; không dùng làm điều kiện PASS cho H3.
