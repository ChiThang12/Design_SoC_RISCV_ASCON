# Kết Quả Đạt Được Của H

Tài liệu này gom các kết quả quan trọng nhất của nhánh `H` vào một chỗ để phục vụ:

- viết báo cáo
- làm slide
- đối chiếu nhanh giữa `reference`, `baseline`, và `headline`

Phần trình bày được chia thành ba lớp:

1. kết quả mới đã khóa
2. kết quả so sánh
3. kết luận về hiệu năng đạt được

## 1. Kết quả mới đã khóa

### 1.1 Reference control-plane H3

`H3` được giữ như mốc tham chiếu control-plane, không dùng làm headline throughput của `H`.

| Scenario | Kết quả |
| --- | --- |
| `test_dualcore_h3_context` | `PASS`, `cycles=124241`, `heartbeat=4` |
| `test_dualcore_h3_benchmark` | `PASS`, `cycles=7150`, `avg_active_throughput_mbps=492.31`, `h3_context_switches=6`, `avg_mmio_interval_cycles=36.00`, `rtl_select_latency_cycles=1` |

Ý nghĩa:

- control-plane hai context đã chạy ổn định
- chi phí chọn bank ở RTL đã xuống `1 cycle`
- khoảng cách firmware-visible giữa hai lần đổi context giữ ở `36 cycles`

### 1.2 Baseline payload datapath, `COH_CTRL=0`

Đây là mốc payload baseline để so với kiến trúc streaming mới.

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 91 | 1125.27 Mbps | 2 | 2 |
| 256B | 159 | 1288.05 Mbps | 4 | 3 |
| 512B | 295 | 1388.47 Mbps | 8 | 5 |
| 1024B | 567 | 1444.80 Mbps | 16 | 9 |

### 1.3 Streaming headline datapath, performance mode `COH_CTRL=1`

Đây là mode hiệu năng chính của `H`.

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 95 | 1077.89 Mbps | 0 | 2 |
| 256B | 165 | 1241.21 Mbps | 0 | 3 |
| 512B | 357 | 1147.34 Mbps | 6 | 5 |
| 1024B | 629 | 1302.38 Mbps | 6 | 9 |

### 1.4 Full coherent fallback, `COH_CTRL=3`

Đây là mode coherence đầy đủ để ưu tiên correctness đầu ra.

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 203 | 504.43 Mbps | 0 | 2 |
| 256B | 342 | 598.83 Mbps | 0 | 3 |
| 512B | 683 | 599.71 Mbps | 6 | 5 |
| 1024B | 1306 | 627.26 Mbps | 6 | 9 |

### 1.5 Output cache-hit control, payload 128B

Đây là bài kiểm tra quan trọng để chứng minh policy coherence đầu ra.

| Mode | Fair cycles | Throughput fair | Snoop read | Snoop inv | Kết luận |
| --- | ---: | ---: | ---: | ---: | --- |
| `COH_CTRL=1` | 94 | 1089.36 Mbps | 8 | 0 | giữ contract stale/non-temporal output |
| `COH_CTRL=3` | 315 | 325.08 Mbps | 8 | 9 | giữ contract fresh output với full invalidate |

### 1.6 Overlap ở mức engine

Hai bằng chứng vi kiến trúc đã khóa:

- `peak accepted outstanding AR = 2`
- `peak pending BRESP = 2`

Ý nghĩa:

- read side đã có hành vi multi-outstanding thực sự
- write side đã bắt đầu tách issue khỏi completion tốt hơn
- kiến trúc không còn là luồng tuần tự đọc xong rồi mới ghi tiếp theo kiểu cũ

## 2. Kết quả so sánh

### 2.1 So sánh `COH_CTRL=1` với `COH_CTRL=3`

Đây là so sánh quan trọng nhất của headline `H`, vì nó cho thấy selective coherence policy có ý nghĩa hiệu năng rõ ràng.

| Payload | `COH_CTRL=1` cycles | `COH_CTRL=3` cycles | Giảm chu kỳ | Tăng throughput |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 95 | 203 | 53.20% | 2.14x |
| 256B | 165 | 342 | 51.75% | 2.07x |
| 512B | 357 | 683 | 47.73% | 1.91x |
| 1024B | 629 | 1306 | 51.84% | 2.08x |

Kết luận:

- `COH_CTRL=1` nhanh hơn rất rõ so với `COH_CTRL=3`
- khác biệt nằm đúng ở chỗ `H` muốn nhấn mạnh: không để full invalidate luôn chặn critical path
- `COH_CTRL=3` vẫn có giá trị như mode fallback/correctness, nhưng không phù hợp để làm mode headline hiệu năng

### 2.2 So sánh `COH_CTRL=1` với baseline `COH_CTRL=0`

So sánh này cho thấy chi phí phải trả khi thêm coherence policy hiệu năng vào pipeline.

| Payload | Baseline cycles | `COH_CTRL=1` cycles | Chênh lệch chu kỳ | Tỷ lệ throughput của `COH_CTRL=1` so với baseline |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 91 | 95 | +4.40% | 0.958x |
| 256B | 159 | 165 | +3.77% | 0.964x |
| 512B | 295 | 357 | +21.02% | 0.826x |
| 1024B | 567 | 629 | +10.93% | 0.901x |

Kết luận:

- `COH_CTRL=1` chưa vượt baseline software-fenced ở mọi payload
- nhưng nó đạt được điều baseline không có: bỏ được `fence` như contract vận hành chính, đồng thời vẫn giữ được throughput gần baseline ở các payload ngắn và trung bình
- vì vậy giá trị của `H` không chỉ nằm ở số Mbps tuyệt đối, mà ở chỗ giữ hiệu năng cao trong khi đẩy coherence vào datapath phần cứng

### 2.3 So sánh lớp control-plane H3 với lớp headline H

| Hạng mục | Throughput chính |
| --- | ---: |
| `H3 reference control-plane` | `492.31 Mbps` |
| `Baseline payload 128B` | `1125.27 Mbps` |
| `H headline 128B, COH_CTRL=1` | `1089.36 Mbps` |
| `H fallback 128B, COH_CTRL=3` | `325.08 Mbps` |

Diễn giải:

- baseline payload 128B cao hơn H3 khoảng `2.29x`
- headline `H`, `COH_CTRL=1`, cao hơn H3 khoảng `2.21x`
- `COH_CTRL=3` thấp hơn H3, nên chỉ nên dùng như mode correctness fallback

## 3. Hiệu năng đạt được

Từ các kết quả trên, có thể chốt ngắn gọn phần hiệu năng như sau:

### 3.1 Mức throughput đạt được

- throughput cao nhất đã khóa trong package hiện tại là `1444.80 Mbps` ở baseline `COH_CTRL=0`, payload `1024B`
- throughput headline của kiến trúc `H` là `1302.38 Mbps` ở `COH_CTRL=1`, payload `1024B`
- với bài output contract 128B, mode hiệu năng `COH_CTRL=1` đạt `1089.36 Mbps`

### 3.2 Mức cải thiện quan trọng nhất

Cải thiện quan trọng nhất của `H` không phải là thắng baseline cũ ở mọi payload, mà là:

- duy trì throughput mức cao trong mode coherence phần cứng
- giảm mạnh chi phí so với full coherent fallback `COH_CTRL=3`
- tạo được bằng chứng overlap thực sự ở mức engine và runtime policy

Nói cách khác, điểm mạnh của `H` là:

- `performance mode` có thể chạy gần baseline cũ
- nhưng không còn phụ thuộc vào software fence như con đường vận hành chính
- trong khi vẫn giữ một mode `full coherent fallback` riêng cho correctness đầu ra

### 3.3 Claim hiệu năng phù hợp để dùng

Cách nói an toàn và đúng với số đo hiện tại:

- `H` đạt throughput hơn `1.30 Gbps` ở mode hiệu năng `COH_CTRL=1` với payload `1024B`
- ở các payload `128B`, `256B`, `512B`, `1024B`, mode `COH_CTRL=1` nhanh hơn mode `COH_CTRL=3` khoảng `1.91x` đến `2.14x`
- engine đã chứng minh được overlap với `AR outstanding = 2` và `pending BRESP = 2`

Không nên claim:

- `H` luôn nhanh hơn baseline software-fenced ở mọi payload
- `COH_CTRL=3` là mode hiệu năng

## 4. Tổng kết ngắn

Phần kết quả đạt được của `H` hiện có thể chốt bằng bốn ý:

1. `H3` đã được giữ sạch như reference control-plane riêng
2. datapath baseline đã có mốc payload rõ ràng để đối chiếu
3. kiến trúc `H` đã chứng minh được mode hiệu năng phần cứng `COH_CTRL=1` với throughput hơn `1.30 Gbps`
4. selective coherence giúp giảm khoảng `48%` đến `53%` số chu kỳ so với full coherent fallback, đồng thời tạo ra bằng chứng overlap thật ở mức engine

## 5. Nguồn đối chiếu

- `paper2/paper2_2/H/benchmark_va_tieu_chi.md`
- `paper2/paper2_2/H/bao_cao_firmware_H.md`
- `paper2/paper2_2/H/golden_data_H.md`
- `paper2/01_baseline_old_arch.md`
