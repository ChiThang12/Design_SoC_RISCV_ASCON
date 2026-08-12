# Lệnh Test H3 Reference và DMA Comparison

Tại lab test H3 từ root repo:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_context.c -o tests_dualcore/test_dualcore_h3_context.hex -O 0
```

Elaborate testbench:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_benchmark.c -o tests_dualcore/test_dualcore_h3_benchmark.hex -O 0
```

Elaborate với H3 event tracing:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
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

- Firmware dùng `-O 0` để tránh tối ưu hóa MMIO.
- Benchmark H3 lấy từ counter của testbench (`cycles`, DCache request, peer snoop, C2C forwarding).
- `AUX0/AUX1` chỉ là marker phụ; không dùng làm điều kiện PASS cho H3.
- Trong paper mới, phần này là reference benchmark cho control plane, còn benchmark chính cần bổ sung cho DMA bulk path, burst efficiency, và end-to-end secure communication throughput.

## H3 Busy-Switch Negative Test

Build firmware:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_busy_switch.c -o tests_dualcore/test_dualcore_h3_busy_switch.hex -O 0
```

Run:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_busy_switch.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_busy_switch"' \
  -DEXPECT_SIG0="32'h3C00C101" \
  -DEXPECT_SIG1="32'h3C00C102" \
  -DHEARTBEAT_MIN=0 \
  -DDC_REQ_MIN=0 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0="32'h3C0C1000" \
  -DAUX1_CHECK_ENABLE=1 \
  -DEXPECT_AUX1="32'h3C0B1001" \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_busy_switch.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_h3_busy_switch.out
```

Kết quả hiện tại:

```text
[PASS] test_dualcore_h3_busy_switch
  cycles=7868
  heartbeat=2 shared_count=3
  aux0=3c0c1000 aux1=3c0b1001
```

Diễn giải:

- Đây là regression test cho trường hợp đổi `CONTEXT_SEL` ngay sau `core_start`.
- Test dùng clean reference của context 0, sau đó start context 0, đổi/gắn context 1, rồi đọc lại context 0.
- `AUX0=3c0c1000` là final marker: output context 0 sau switch khớp reference.
- Trace debug ban đầu cho thấy lỗi fail cũ đến từ reference chạy quá sát sau `soft_reset`; firmware hiện cấu hình context 0 hai lần trước reference để ổn định thứ tự MMIO ở `-O0`.

## H3 DMA Context Smoke

Build firmware:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_dma_context_smoke.c -o tests_dualcore/test_dualcore_h3_dma_context_smoke.hex -O 0
```

Run với kiểm tra trực tiếp `dma_context_id_active_w` trong testbench:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_dma_context_smoke.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_dma_context_smoke"' \
  -DEXPECT_SIG0="32'h3C00E101" \
  -DEXPECT_SIG1="32'h3C00E102" \
  -DHEARTBEAT_MIN=3 \
  -DDC_REQ_MIN=0 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0="32'h3C0D3000" \
  -DDMA_CONTEXT_CHECK_ENABLE=1 \
  -DEXPECT_DMA_CONTEXT="1'b1" \
  -DTIMEOUT_CYCLES=800000 \
  -o /tmp/test_dualcore_h3_dma_context_smoke.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_h3_dma_context_smoke.out
```

Kết quả hiện tại:

```text
[PASS] test_dualcore_h3_dma_context_smoke
  cycles=9253
  heartbeat=3 shared_count=3
  aux0=3c0d3000 aux1=00000000
```

Diễn giải:

- Firmware start DMA khi `CONTEXT_SEL=1`, rồi đổi sang context 0 và ghi bank 0 trong lúc DMA đang chạy.
- Testbench chỉ PASS nếu thấy `dma_context_id_active_w == 1` khi `dma_busy_w=1`.
- Đây là smoke test tối thiểu để chứng minh `context_id_active` không chỉ là signal trang trí.

Trong narrative DMA-first, đây là test phụ để giữ coherency/control correctness. Benchmark chính vẫn phải là data volume, burst behavior, và throughput end-to-end.

## H3 Multi-Round Switch-Back Stress

Build firmware:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_stress_switchback.c -o tests_dualcore/test_dualcore_h3_stress_switchback.hex -O 0
```

Run với final markers:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_stress_switchback.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_stress_switchback_final"' \
  -DEXPECT_SIG0="32'h3C00D101" \
  -DEXPECT_SIG1="32'h3C00D102" \
  -DHEARTBEAT_MIN=0 \
  -DDC_REQ_MIN=0 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0="32'h3C0D2000" \
  -DAUX1_CHECK_ENABLE=1 \
  -DEXPECT_AUX1="32'h3C0D2001" \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_stress_switchback_final.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_h3_stress_switchback_final.out
```

Kết quả hiện tại:

```text
[PASS] test_dualcore_h3_stress_switchback_final
  cycles=13200
  heartbeat=5 shared_count=6
  aux0=3c0d2000 aux1=3c0d2001
```

Diễn giải:

- Test này chạy nhiều vòng `context 0 -> context 1 -> context 0 -> context 1`.
- Mỗi lần chạy lại đều reload context tương ứng rồi so với snapshot reference đầu tiên.
- Dùng `AUX0/AUX1` làm final pass marker để tránh pass sớm ở heartbeat trung gian.

Trong paper mới, test này nên đặt vào appendix hoặc validation subsection để chứng minh control-plane reference vẫn ổn định khi DMA-first path được thêm vào.
