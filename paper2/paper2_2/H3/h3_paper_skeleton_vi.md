# H3 Paper Skeleton: DMA-Enabled Pipelined ASCON Engine with Multi-Context Reference

Tài liệu này gom lại nội dung, lệnh chạy test, kết quả, số liệu benchmark và nhận định nhanh cho kiến trúc H3. Mục tiêu là dùng như một sườn paper: có thể lấy trực tiếp để viết phần Introduction, Methodology, Experimental Results, Discussion và Appendix reproducibility.

Trong narrative mới, DMA stream/burst và pipeline của ASCON là headline chính. H3 multi-context/context banking vẫn được giữ lại như reference design để so sánh control-plane cost, context isolation, và end-to-end multi-session behavior.

## 1. Tóm Tắt Luận Điểm

DMA-first revision của đề tài nhắm vào ASCON engine được nuôi bởi DMA stream/burst có pipeline để tăng throughput end-to-end. Thay vì CPU copy từng mẩu dữ liệu qua MMIO, DMA sẽ coalesce và đẩy payload lớn hơn vào engine với ít idle hơn.

H3 đóng vai trò reference design cho phần control-plane của ASCON:

- H3 giữ được hai session ASCON độc lập trong phần cứng.
- Context switch bằng bank select có độ trễ RTL 1 cycle.
- Trên đường firmware/MMIO hiện tại, khoảng cách giữa hai lần ghi `CONTEXT_SEL` đo được là 36 cycles.
- So với no-CRF reload lower-bound 12 thanh ghi x 36 cycles = 432 cycles, H3 giảm context-switch overhead khoảng 12.0x.
- Với payload fair từ 128B đến 1024B, H3 đạt speedup 1.64x đến 4.09x so với baseline reload proxy.
- Các test bổ sung đã kiểm tra các corner case quan trọng: switch-back nhiều vòng, đổi context sau start, và DMA `context_id_active`.

Luận điểm chính cho paper mới phải là:

- DMA stream/burst giữ nhiều data hơn trong mỗi lần phục vụ ASCON.
- Pipelined ASCON engine giảm khoảng trống giữa các beat dữ liệu.
- H3 reference chứng minh control-plane và multi-session không phải bottleneck duy nhất, nhưng throughput thật sự phải đến từ data path.

## 2. Bối Cảnh Và Vấn Đề

Trong SoC dual-core có ASCON accelerator, nhiều software task/session có thể dùng ASCON với key/nonce khác nhau. Nếu accelerator chỉ có một bộ register, mỗi lần đổi session firmware phải ghi lại nhiều thanh ghi:

- `MODE`
- `KEY_0..KEY_3`
- `NONCE_0..NONCE_3`
- `PTEXT_0..PTEXT_1`
- `DATA_LEN`

Tối thiểu đã là 12 MMIO write cho một lần reload context. Với khoảng cách MMIO đo được 36 cycles/write trong benchmark H3, lower-bound reload overhead là 432 cycles, chưa tính kiểm tra status, đồng bộ cache, hoặc software control overhead.

H3 giải quyết bằng cách bank hóa core-facing state. Firmware cấu hình trước context 0 và context 1, sau đó chuyển session bằng `CONTEXT_SEL`.

Tuy nhiên, để đúng với title của đề tài, phần giới hạn chính hiện nay không chỉ nằm ở context switching mà còn ở đường dữ liệu. Nếu DMA không đủ thông minh để gom burst, giữ pipeline đầy, và tránh fallback chậm, thì SoC vẫn chưa đạt được "high-throughput" theo đúng nghĩa.

## 3. Kiến Trúc H3

### 3.1 Register Banking

H3 thêm thanh ghi `CONTEXT_SEL` tại offset `0x008`. Các nhóm thanh ghi sau được bank hóa theo context:

| Nhóm thanh ghi | Ý nghĩa |
| --- | --- |
| `MODE` | Chọn ASCON variant/direction |
| `KEY_0..KEY_3` | Key 128-bit |
| `NONCE_0..NONCE_3` | Nonce 128-bit |
| `PTEXT_0..PTEXT_1` | Plaintext CPU-direct |
| `DATA_LEN` | Số byte dữ liệu hợp lệ |
| `CTEXT_0..CTEXT_1` | Ciphertext output |
| `TAG_0..TAG_3` | Authentication tag output |
| `AD_LEN`, `AD_DATA_*`, `TAG_IN_*` | AEAD/decrypt support |

### 3.2 Active Context Latch

Khi `core_start` hoặc `dma_start`, RTL latch context hiện tại vào `reg_context_active`. Trong lúc operation đang chạy hoặc đang hoàn tất, core-facing mux dùng `reg_context_active`, không dùng `reg_context_sel` trực tiếp.

Điểm RTL quan trọng:

```verilog
wire core_context_sel = (core_start || dma_start ||
                         core_busy || dma_busy ||
                         core_done || core_data_out_valid || core_tag_valid)
                        ? reg_context_active
                        : reg_context_sel;
```

Ý nghĩa: nếu firmware đổi `CONTEXT_SEL` sau khi start, output/tag của operation đang chạy vẫn được capture theo active context đã latch.

### 3.3 DMA Context Sideband

DMA nhận `context_id` từ slave và latch vào `context_id_active` khi `dma_start`. Testbench đã có hook kiểm tra trực tiếp `dma_context_id_active_w` khi `dma_busy_w=1`.

Trong narrative mới, `context_id_active` chỉ là bảo chứng rằng DMA start đúng context. Cái chính vẫn phải là DMA stream/burst đủ "thông minh" để tối đa hóa lượng dữ liệu nạp vào ASCON engine.

## 4. Phương Pháp Đo

Môi trường mô phỏng:

- Simulator: `iverilog` + `vvp`
- Testbench: `tb_soc/tb_soc_dualcore_suite.v`
- Firmware: RISC-V C, build bằng `gnu_toolchain/compile_c_to_hex.sh`
- Optimization: `-O 0` để tránh compiler tối ưu/reorder MMIO
- Clock giả định khi tính throughput: 100 MHz

Các metric chính:

| Metric | Cách đọc |
| --- | --- |
| `cycles` | Chu kỳ từ reset/test start đến PASS |
| `heartbeat` | Marker tiến độ firmware |
| `shared_count` | Marker phase trong firmware |
| `core0_dc_req_count`, `core1_dc_req_count` | Số request DCache |
| `peer_snp_hits` | Snoop sang peer cache và hit |
| `c2c_fwds` | Cache-to-cache forwarding thành công |
| `avg_active_cycles` | Latency crypto active từ `core_start` đến `core_done` |
| `avg_mmio_interval_cycles` | Khoảng cách giữa các MMIO context select |
| `rtl_select_latency_cycles` | Độ trễ chọn bank trong RTL |

## 5. Bảng Kết Quả Tổng Hợp

### 5.0 Role of H3 in the new paper

| Vai trò | Nội dung |
| --- | --- |
| Headline mới | DMA-enabled pipelined ASCON engine |
| Reference control-plane | H3 multi-context / `CONTEXT_SEL` |
| Reference baseline | no-CRF reload path |
| Validation phụ | busy-switch, stress switch-back, DMA context smoke |

### 5.1 Functional And Reliability Tests

| Test | Mục tiêu | Kết quả | Cycles | Marker chính | Nhận định |
| --- | --- | ---: | ---: | --- | --- |
| `test_dualcore_h3_context` | Chứng minh context 0/1 độc lập qua dual-core | PASS | 124220 | `aux0=3c0a0000`, `aux1=00000000` | Functional proof chính |
| `test_dualcore_h3_benchmark` | Đo active latency và context-switch interval | PASS | 7129 | `aux0=3c0bee00`, `aux1=3c0bee01` | Benchmark headline |
| `test_dualcore_h3_busy_switch` | Đổi context ngay sau `core_start`, verify context 0 không bị lẫn | PASS | 7868 | `aux0=3c0c1000`, `aux1=3c0b1001` | Negative/regression test |
| `test_dualcore_h3_stress_switchback` | Lặp nhiều vòng `0 -> 1 -> 0 -> 1` | PASS | 13200 | `aux0=3c0d2000`, `aux1=3c0d2001` | Stress switch-back |
| `test_dualcore_h3_dma_context_smoke` | Start DMA context 1, đổi sang context 0, check DMA active context | PASS | 9253 | `aux0=3c0d3000` | Chứng minh `context_id_active` có tác dụng |

### 5.2 H3 Benchmark Core Metrics

| Metric | Giá trị |
| --- | ---: |
| Active crypto latency/context | 13 cycles |
| Active throughput cho 8B @100 MHz | 492.31 Mbps |
| Measured MMIO context-switch interval | 36 cycles |
| RTL context select latency | 1 cycle |
| No-CRF reload lower-bound | 432 cycles |
| Context-switch overhead speedup | 12.0x |

### 5.3 Fair Throughput Comparison

Fair comparison dùng cùng DMA baseline cycle và cộng overhead context. Không dùng end-to-end 8B diagnostic làm headline throughput vì payload quá nhỏ và bị setup/sync overhead chi phối.

| Payload | H3 DMA fair | H3 + context select | H3 fair throughput | No-CRF reload lower-bound | No-CRF throughput | H3 speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128B | 92 cycles | 128 cycles | 800.00 Mbps | 524 cycles | 195.42 Mbps | 4.09x |
| 256B | 160 cycles | 196 cycles | 1044.90 Mbps | 592 cycles | 345.95 Mbps | 3.02x |
| 512B | 312 cycles | 348 cycles | 1177.01 Mbps | 744 cycles | 550.54 Mbps | 2.14x |
| 1024B | 584 cycles | 620 cycles | 1321.29 Mbps | 1016 cycles | 806.30 Mbps | 1.64x |

### 5.4 Supporting Dual-Core Coherency Context

| Test | Kết quả | Số liệu nổi bật | Ý nghĩa |
| --- | --- | --- | --- |
| `test_dualcore_peer_snoop` | PASS | `peer_snp_hits=3`, `c2c_fwds=3` | CPU read miss có thể lấy dữ liệu từ peer cache |
| `test_dualcore_ascon_dma_coherent` | PASS | `heartbeat=4`, `aux0=0xac03d003` | ASCON DMA coherency end-to-end |
| `test_dualcore_contention_forward_dma` | PASS | `cycles=49957`, `c2c_fwds=10` | Forward-hit + DMA case |
| `test_dualcore_contention_fallback_dma` | PASS | `cycles=81320`, `c2c_fwds=2` | Fallback/reference case |
| `tb_dcache_dualcore_protocol` | 25 PASS / 0 FAIL | `mem_refills=0` trong peer forward path | Protocol-level proof |
| `tb_ascon_dma` | 66 PASS / 0 FAIL | Coherent read/write primitives | DMA-side proof |

## 6. Lệnh Chạy Test

Chạy từ root repo:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
```

### 6.1 H3 Context Isolation

Build:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_context.c -o tests_dualcore/test_dualcore_h3_context.hex -O 0
```

Run:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3'
iverilog -g2005 -I. \
  -DTEST_HEX='"gnu_toolchain/tests_dualcore/test_dualcore_h3_context.hex"' \
  -DSCENARIO_NAME='"test_dualcore_h3_context"' \
  -DEXPECT_SIG0="32'h3C000001" \
  -DEXPECT_SIG1="32'h3C000002" \
  -DHEARTBEAT_MIN=4 \
  -DDC_REQ_MIN=0 \
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0="32'h3C0A0000" \
  -DAUX1_CHECK_ENABLE=1 \
  -DEXPECT_AUX1="32'h00000000" \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_context.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_h3_context.out
```

Kết quả đã đo:

```text
[PASS] test_dualcore_h3_context
  cycles=124220
  heartbeat=4 shared_count=2
  aux0=3c0a0000 aux1=00000000
```

### 6.2 H3 Benchmark

Build:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_benchmark.c -o tests_dualcore/test_dualcore_h3_benchmark.hex -O 0
```

Run:

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
  -DAUX0_CHECK_ENABLE=1 \
  -DEXPECT_AUX0="32'h3C0BEE00" \
  -DAUX1_CHECK_ENABLE=1 \
  -DEXPECT_AUX1="32'h3C0BEE01" \
  -DTIMEOUT_CYCLES=500000 \
  -o /tmp/test_dualcore_h3_benchmark.out \
  tb_soc/tb_soc_dualcore_suite.v
vvp /tmp/test_dualcore_h3_benchmark.out
```

Kết quả đã đo:

```text
[PASS] test_dualcore_h3_benchmark
  cycles=7129
  heartbeat=6 shared_count=2
  aux0=3c0bee00 aux1=3c0bee01
  h3_core_ops=2 avg_active_cycles=13.00 min=13 max=13 avg_active_throughput_mbps=492.31
  h3_context_switches=6 measured_intervals=5 avg_mmio_interval_cycles=36.00 min=36 max=36 rtl_select_latency_cycles=1
```

### 6.3 Busy-Switch Negative Test

Build:

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

Kết quả đã đo:

```text
[PASS] test_dualcore_h3_busy_switch
  cycles=7868
  heartbeat=2 shared_count=3
  aux0=3c0c1000 aux1=3c0b1001
```

### 6.4 Multi-Round Switch-Back Stress

Build:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_stress_switchback.c -o tests_dualcore/test_dualcore_h3_stress_switchback.hex -O 0
```

Run:

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

Kết quả đã đo:

```text
[PASS] test_dualcore_h3_stress_switchback_final
  cycles=13200
  heartbeat=5 shared_count=6
  aux0=3c0d2000 aux1=3c0d2001
```

### 6.5 DMA Context Smoke Test

Build:

```bash
cd '/home/chithang/Project/Design_SoC_RISCV_ASCON H3/gnu_toolchain'
./compile_c_to_hex.sh -i tests_dualcore/test_dualcore_h3_dma_context_smoke.c -o tests_dualcore/test_dualcore_h3_dma_context_smoke.hex -O 0
```

Run:

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

Kết quả đã đo:

```text
[PASS] test_dualcore_h3_dma_context_smoke
  cycles=9253
  heartbeat=3 shared_count=3
  aux0=3c0d3000 aux1=00000000
```

## 7. Nhận Định Nhanh Cho Paper

### 7.1 Điểm Mạnh

- H3 có functional proof rõ ràng: hai context độc lập, output context 0 không bị ghi đè khi context 1 chạy.
- Benchmark có số liệu đẹp và dễ giải thích: `36 cycles` cho MMIO select, `1 cycle` ở RTL mux.
- So sánh fair với no-CRF reload có công thức đơn giản, reviewer dễ kiểm tra.
- Reliability test đã bao phủ các câu hỏi phản biện thường gặp: switch-back nhiều vòng, đổi context sau start, DMA active context.
- H3 nằm trên nền dual-core coherency đã có test riêng: peer snoop, C2C forwarding, ASCON DMA coherent path.
- Đây là reference rất tốt để chứng minh DMA-first revision tăng throughput thật sự chứ không chỉ đổi control logic.

### 7.2 Điểm Cần Nói Cẩn Thận

- Chưa nên dùng `cycles=7129` và throughput end-to-end 8B làm headline throughput, vì con số này gồm setup, sync, verify và payload quá nhỏ.
- Area/timing chưa có vì bạn sẽ chạy Vivado sau. Trong paper hiện tại nên để mục `Hardware Cost` là pending hoặc placeholder.
- `busy_switch` là post-start regression mạnh nhưng không nhất thiết chứng minh core vẫn busy tại thời điểm MMIO đổi context, vì core CPU-direct chạy rất nhanh. Giá trị của test là chứng minh context/output không lẫn sau chuỗi start-switch-reprogram.
- DMA context smoke test chứng minh `context_id_active` latch đúng ở mức sideband/testbench; nó là smoke test tối thiểu, không thay thế toàn bộ DMA coherency benchmark.
- Paper mới phải có benchmark DMA burst/pipeline riêng, nếu không title `high-throughput` sẽ bị reviewer bắt bẻ.

### 7.3 Cách Viết Claim An Toàn

Claim nên dùng:

- "H3 reduces context-switch overhead by replacing multi-register reloads with a single context bank selection."
- "The measured MMIO context-select interval is 36 cycles, while the RTL bank-select latency is one cycle."
- "Compared with a conservative no-CRF reload lower bound of 432 cycles, H3 provides a 12.0x reduction in context-switch overhead."
- "For 128B to 1024B fair DMA payloads, H3 improves effective throughput by 1.64x to 4.09x over the reload proxy."
- "Additional regression tests validate context isolation under repeated switch-back, post-start switching, and DMA context sideband latching."

Claim nên tránh hoặc cần ghi rõ điều kiện:

- Không nói "full hardware cost improved" trước khi có Vivado area/timing.
- Không nói DMA context smoke là full DMA isolation proof; hãy gọi là `smoke test` hoặc `sideband latch validation`.
- Không dùng diagnostic 8B end-to-end throughput làm kết quả đại diện cho throughput của accelerator.

## 8. Gợi Ý Bố Cục Paper

### Abstract

Nêu vấn đề data movement bottleneck trong ASCON accelerator khi phục vụ secure communications trên dual-core RISC-V SoC. Giới thiệu DMA-enabled, pipelined ASCON engine như headline chính, đồng thời nhắc H3 context banking như reference cho multi-session và control overhead.

### Introduction

Trình bày nhu cầu lightweight cryptography trong embedded/SoC, ASCON accelerator, dual-core workload, vấn đề nhiều session/key, và quan trọng hơn là bottleneck dữ liệu nếu chỉ dùng CPU-direct/MMIO. Nêu hạn chế single-context accelerator: reload nhiều MMIO register khi đổi session và không đủ thông minh để đẩy payload lớn bằng DMA.

### Related Work

So sánh với ASCON accelerator đơn context, DMA-based crypto accelerator, cache-coherent accelerator integration. Nhấn mạnh paper này tập trung vào DMA-first throughput, pipeline efficiency, và SoC-level validation; H3 multi-context chỉ là reference để so sánh control-plane.

### Proposed Architecture

Mô tả kiến trúc mục tiêu của paper:

- DMA stream/burst control
- pipelined ASCON datapath
- coherent delivery tới accelerator
- control-plane context banking của H3 làm reference

Sau đó đặt H3 reference side-by-side:

- `CONTEXT_SEL`
- 2-bank core-facing register file
- active context latch
- output/tag capture theo active context
- DMA `context_id_active`
- tích hợp trong dual-core RISC-V SoC

### Experimental Methodology

Mô tả simulation, firmware tests, testbench counters, clock 100 MHz, `-O0`, các nhóm test: functional, benchmark, stress, DMA smoke. Nên có thêm benchmark DMA burst/pipeline riêng cho headline mới.

### Results

Đưa các bảng:

- DMA bulk throughput và burst efficiency
- Functional reliability test table
- Core H3 benchmark metrics
- Fair throughput comparison 128B-1024B
- Supporting coherency table

### Discussion

Giải thích vì sao DMA-first design tốt nhất ở payload lớn và workload multi-session: burst overhead được amortize, pipeline được giữ đầy, và control overhead nhỏ hơn. H3 reference cho thấy context overhead vẫn hữu ích, nhưng headline throughput phải đến từ data plane. Nói rõ diagnostic vs fair throughput.

### Limitations And Future Work

Ghi area/timing Vivado pending, mở rộng nhiều hơn 2 context nếu cần, chạy FPGA validation, formal/property check cho context isolation, thêm DMA-context full data-output verification, và đặc biệt là benchmark DMA burst/pipeline thật.

### Conclusion

Kết luận paper mới là DMA-enabled, pipelined ASCON engine cải thiện throughput end-to-end cho secure communications, còn H3 là reference design chứng minh control-plane and multi-context behavior đúng và có ích.

## 9. Checklist Trước Khi Chốt Paper

- Chạy benchmark DMA bulk stream/burst để có số liệu headline.
- Chạy Vivado synthesis/implementation để lấy LUT, FF, BRAM, Fmax.
- Cập nhật bảng Hardware Cost.
- Chốt một bảng so sánh baseline vs H3 có cùng clock và cùng payload.
- Đưa `busy_switch`, `stress_switchback`, `dma_context_smoke` vào appendix hoặc validation subsection.
- Nếu có thời gian, thêm waveform hoặc sơ đồ timing cho `CONTEXT_SEL -> reg_context_active -> core_context_sel`.
- Rà lại tên claim: dùng "reload lower-bound/proxy" thay vì khẳng định baseline reload measured nếu baseline benchmark chưa ổn định.
- Rà lại câu chữ để headline chính luôn là DMA throughput, còn H3 chỉ là reference.

## 10. File Liên Quan

- [h3_test_commands.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_test_commands.md>)
- [h3_benchmark.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_benchmark.md>)
- [h3_results.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_results.md>)
- [h3_baseline_no_crf.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_baseline_no_crf.md>)
- [h3_dma_first_architecture.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_dma_first_architecture.md>)
- [h3_dma_benchmark_plan.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_dma_benchmark_plan.md>)
- [benchmark_tong_hop_vi.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/benchmark_tong_hop_vi.md>)
- [ascon_axi_slave.v](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/ascon/interface/ascon_axi_slave.v>)
- [tb_soc_dualcore_suite.v](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/tb_soc/tb_soc_dualcore_suite.v>)
