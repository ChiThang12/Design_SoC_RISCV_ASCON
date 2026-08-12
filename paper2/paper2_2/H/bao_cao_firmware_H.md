# Báo Cáo Firmware H

Tài liệu này khóa trạng thái thực thi firmware cho nhánh `H` theo ba lớp:

- `H3 reference control-plane`
- `baseline payload datapath`
- `streaming headline datapath`

## 1. Script chuẩn để chạy

Script gom chuẩn hiện tại:

```bash
bash run_h_firmware_benchmarks.sh
```

Script này chạy lần lượt:

1. `test_dualcore_h3_context`
2. `test_dualcore_h3_benchmark`
3. `run_soc_fence_128b.v`
4. `run_output_cachehit.sh 128` với `COH_CTRL=1`
5. `run_output_cachehit.sh 128` với `COH_CTRL=3`

## 2. Kết quả xác nhận ngày 2026-07-16

### 2.1 H3 reference control-plane

- `test_dualcore_h3_context`: `PASS`
  - `cycles=124241`
  - `heartbeat=4`
  - `shared_count=2`
  - `aux0=3c0a0000`
  - `aux1=3c0b0001`
- `test_dualcore_h3_benchmark`: `PASS`
  - `cycles=7150`
  - `heartbeat=6`
  - `shared_count=2`
  - `h3_core_ops=2`
  - `avg_active_cycles=13.00`
  - `avg_active_throughput_mbps=492.31`
  - `h3_context_switches=6`
  - `avg_mmio_interval_cycles=36.00`
  - `rtl_select_latency_cycles=1`

Kết luận:

- `Firmware H3 reference PASS` có thể xem là đã khóa
- H3 vẫn giữ đúng vai trò `reference control-plane`, không dùng các số này làm headline throughput của H

### 2.2 Baseline payload datapath

- `run_soc_fence_128b.v`: `PASS`
  - `dma_start/done/error = 1/1/0`
  - `M2 AR/AW = 2/2`
  - `fair write-complete cyc = 91`

Kết luận:

- `Firmware baseline payload PASS` có thể xem là đã khóa
- baseline payload đã có bài firmware riêng và không còn chỉ suy ra từ các test khác

### 2.3 Streaming headline datapath

Kết quả chạy `run_output_cachehit.sh 128` sau khi khóa lại đường `DMA_COH_CTRL`:

- `COH_CTRL=1`: `PASS`
  - `dma_start/done/error = 1/1/0`
  - `snoop read req/hit = 8/8`
  - `snoop inv req/hit = 0/0`
  - `fair write-complete cyc = 94`
  - `throughput fair = 1089.36 Mbps`
- `COH_CTRL=3`: `PASS`
  - `dma_start/done/error = 1/1/0`
  - `snoop read req/hit = 8/8`
  - `snoop inv req/hit = 9/9`
  - `fair write-complete cyc = 315`
  - `throughput fair = 325.08 Mbps`

Kết luận:

- `Firmware streaming headline PASS` đã được khóa
- hai mode policy quan trọng của headline `H` đều đã có bài firmware riêng và log PASS riêng

## 3. Trạng thái checklist firmware sau mốc này

Sau khi chạy xác nhận ngày `2026-07-16`, trạng thái hợp lý là:

- `Firmware H3 reference PASS`: đã khóa
- `Firmware baseline payload PASS`: đã khóa
- `Firmware streaming headline PASS`: đã khóa
- `Firmware benchmark được tách thành H3 / baseline payload / streaming headline`: đã khóa về mặt tổ chức thực thi
- `Golden data đã khóa`: đã khóa

## 4. Ý nghĩa thực tế

Điểm tích cực:

- lớp firmware của `H3 reference` và `baseline payload` đã có bằng chứng chạy riêng, không còn chỉ là suy luận từ tài liệu cũ
- benchmark firmware đã được tách thành ba nhóm đúng tinh thần nhánh `H`

Điểm cần nhớ:

- đường `DMA_COH_CTRL` đã phải được khóa lại theo hướng firmware helper/readback để bài selective coherence chạy đúng
- ở mức SoC, read-snoop path của mode hiệu năng cũng đã được khóa lại để không bị dcache không liên quan chặn deadlock
- đây là mốc quan trọng vì từ đây checklist firmware của `H` đã có thể chốt trọn 5/5

## 5. Bước kế tiếp nên làm

Thứ tự hợp lý tiếp theo:

1. dùng `run_h_firmware_benchmarks.sh` làm đường chạy chuẩn cho package
2. đồng bộ bảng benchmark/tài liệu trình bày theo số đo cuối
3. hoàn thiện `kịch bản demo`
