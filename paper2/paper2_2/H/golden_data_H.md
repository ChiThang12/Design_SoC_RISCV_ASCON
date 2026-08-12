# Golden Data H

Tài liệu này khóa các mốc golden data dùng cho package cuộc thi của nhánh `H`.

Nguyên tắc đọc tài liệu này:

- golden ở đây là tập mốc chuẩn để xác nhận `đúng narrative`, `đúng mode`, `đúng số đo chính`
- không phải mọi golden đều là dump đầy đủ từng word dữ liệu
- có golden kiểu `functional pass`, kiểu `micro-architectural metric`, và kiểu `policy contract`

## 1. H3 control-plane golden

- Scenario: `test_dualcore_h3_context`
- PASS
- `cycles=124220`
- `heartbeat=4`
- `shared_count=2`
- `dcache0 peer_snp_hits=2`
- `dcache1 peer_snp_hits=5`
- `dcache0 c2c_fwds=2`
- `dcache1 c2c_fwds=5`

Ý nghĩa:

- dùng để khóa correctness của `reference control-plane`
- không được dùng các số này để claim throughput headline của `H`

## 2. H3 benchmark golden

- Scenario: `test_dualcore_h3_benchmark`
- PASS
- `cycles=7129`
- `h3_core_ops=2`
- `avg_active_cycles=13.00`
- `avg_active_throughput_mbps=492.31`
- `h3_context_switches=6`
- `avg_mmio_interval_cycles=36.00`
- `rtl_select_latency_cycles=1`

Ý nghĩa:

- dùng để chốt lớp baseline H3 tách biệt khỏi streaming datapath

## 3. Baseline payload golden

- Scenario: `run_soc_fence_128b.v`
- PASS
- `fair write-complete cyc = 91`
- `M2 AR/AW = 2/2`
- `dma_start/done/error = 1/1/0`

Tiêu chí pass:

- transaction hoàn tất đúng
- không báo `dma_error`
- số liệu baseline này phải đứng riêng, không gộp vào headline streaming

## 4. Streaming payload golden

Scenario: `run_output_cachehit.sh 128`

- `COH_CTRL=1` phải giữ output contract kiểu stale/non-temporal khi bài test yêu cầu
- `COH_CTRL=3` phải refresh output và invalidate dirty cached lines theo policy fallback

Scenario: `tb_dma_overlap_metrics.v`

- `peak accepted outstanding AR = 2`
- `peak pending BRESP = 2`

Tiêu chí pass:

- policy coherence phải đúng hành vi ở từng mode
- overlap metric phải đạt ít nhất hai mốc:
  - `peak accepted outstanding AR = 2`
  - `peak pending BRESP = 2`

## 5. Streaming sweep golden

Trạng thái rerun ngày `2026-07-16`:

### 5.1 Baseline payload, `COH_CTRL=0`

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 91 | 1125.27 Mbps | 2 | 2 |
| 256B | 159 | 1288.05 Mbps | 4 | 3 |
| 512B | 295 | 1388.47 Mbps | 8 | 5 |
| 1024B | 567 | 1444.80 Mbps | 16 | 9 |

### 5.2 Full coherent fallback, `COH_CTRL=3`

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 203 | 504.43 Mbps | 0 | 2 |
| 256B | 342 | 598.83 Mbps | 0 | 3 |
| 512B | 683 | 599.71 Mbps | 6 | 5 |
| 1024B | 1306 | 627.26 Mbps | 6 | 9 |

### 5.3 Performance mode, `COH_CTRL=1`

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW | Trạng thái |
| ---: | ---: | ---: | ---: | ---: | :--- |
| 128B | 95 | 1077.89 Mbps | 0 | 2 | đã xác nhận |
| 256B | 165 | 1241.21 Mbps | 0 | 3 | đã xác nhận |
| 512B | 357 | 1147.34 Mbps | 6 | 5 | đã xác nhận |
| 1024B | 629 | 1302.38 Mbps | 6 | 9 | đã xác nhận |

Quy ước dùng bảng này:

- bảng trên là mốc tham chiếu hiện thời của package sau rerun ngày `2026-07-16`
- `COH_CTRL=1` là mode hiệu năng chính của headline `H`
- nhánh `COH_CTRL=1` đã được khóa lại sau khi sửa routing snoop để tránh deadlock do dcache không liên quan chặn read-snoop path

## 6. Golden output/data markers

Các marker dữ liệu hoặc cấu trúc đầu ra đã được khóa ở mức tài liệu và testbench:

- baseline payload và DMA unit test dùng quy ước output là `ciphertext + tag`
- trong `tb_ascon_dma.v`, tag marker hiện dùng:
  - `TAG_0 = DEADBEEF`
  - `TAG_1 = CAFEBABE`
  - `TAG_2 = 01234567`
  - `TAG_3 = 89ABCDEF`
- ở các test unit, dữ liệu ghi ra memory phải phản ánh đúng thứ tự:
  - beat ciphertext trước
  - các beat tag sau

Ý nghĩa:

- đây là golden data đủ để khóa contract output cho regression/unit test
- với package cuộc thi, không cần biến mọi case thành dump hex dài nếu benchmark hoặc policy marker đã đủ rõ và tái tạo được

## 7. Golden markers cho demo

- `H3`: context isolation và switch-back correctness
- `Dot C`: baseline payload DMA pass
- `H`: streaming overlap and direction-aware coherence
- `Overlap`: `AR=2`, `BRESP=2`

## 8. Kết luận chốt golden

Từ thời điểm này, `golden_data_H.md` là mốc chuẩn để:

- kiểm tra kết quả tái tạo
- đối chiếu log benchmark
- giữ claim của `H` không vượt quá số đo hiện có

Checklist cuộc thi có thể xem mục `golden data` là đã được khóa ở mức package tài liệu hiện tại.
