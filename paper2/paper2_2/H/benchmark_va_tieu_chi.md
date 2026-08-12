# Benchmark Và Tiêu Chí Chấm

## 1. Số đo chính

### Nhóm reference control-plane

- số chu kỳ context switch
- số lần firmware can thiệp khi đổi session

### Nhóm headline data-plane

- latency
- throughput
- steady-state overlap efficiency
- số burst AXI
- số snoop hit/invalidate
- số lần payload chain-feed
- số lần write chain-issue
- số lần ingress/egress bank swap
- số chu kỳ core wait / datapath busy
- số AR outstanding cực đại
- số pending BRESP cực đại

## 2. Bảng benchmark nên có

| Hạng mục | Mục tiêu |
| --- | --- |
| H3 context switch | Chứng minh control-plane reference rẻ và ổn định |
| H3 context isolation | Chứng minh multi-session correctness |
| Baseline payload sweep | Chứng minh payload path hiện tại đã khóa được baseline |
| Streaming payload sweep | Chứng minh kiến trúc mới thực sự tạo khác biệt |
| Direction-aware coherence sweep | Chứng minh policy ảnh hưởng đúng |
| Output cache-hit | Chứng minh contract đầu ra |
| Engine overlap metrics | Chứng minh micro-architecture thực sự overlap |

## 2.1 Bảng số đã khóa

### H3 reference control-plane

| Scenario | Kết quả chính |
| --- | --- |
| `test_dualcore_h3_context` | `PASS`, `cycles=124241`, `heartbeat=4` |
| `test_dualcore_h3_benchmark` | `PASS`, `cycles=7150`, `avg_active_throughput_mbps=492.31`, `h3_context_switches=6` |

### Baseline payload sweep, `COH_CTRL=0`

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 91 | 1125.27 Mbps | 2 | 2 |
| 256B | 159 | 1288.05 Mbps | 4 | 3 |
| 512B | 295 | 1388.47 Mbps | 8 | 5 |
| 1024B | 567 | 1444.80 Mbps | 16 | 9 |

### Full coherent fallback, `COH_CTRL=3`

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 203 | 504.43 Mbps | 0 | 2 |
| 256B | 342 | 598.83 Mbps | 0 | 3 |
| 512B | 683 | 599.71 Mbps | 6 | 5 |
| 1024B | 1306 | 627.26 Mbps | 6 | 9 |

### Performance mode, `COH_CTRL=1`

| Payload | Fair cycles | Throughput fair | M2 AR | M2 AW |
| ---: | ---: | ---: | ---: | ---: |
| 128B | 95 | 1077.89 Mbps | 0 | 2 |
| 256B | 165 | 1241.21 Mbps | 0 | 3 |
| 512B | 357 | 1147.34 Mbps | 6 | 5 |
| 1024B | 629 | 1302.38 Mbps | 6 | 9 |

### Output cache-hit control, `run_output_cachehit.sh 128`

| Mode | Fair cycles | Throughput fair | Snoop read | Snoop inv | Ý nghĩa |
| --- | ---: | ---: | ---: | ---: | --- |
| `COH_CTRL=1` | 94 | 1089.36 Mbps | 8 | 0 | stale/non-temporal output contract |
| `COH_CTRL=3` | 315 | 325.08 Mbps | 8 | 9 | fresh output contract với full invalidate |

## 3. Cách đọc kết quả

- Số lớn hơn chưa chắc tốt hơn nếu overhead tăng sai chỗ.
- Throughput phải tính trên đường dữ liệu chính.
- Nếu headline là streaming thì phải có số steady-state riêng, không chỉ số transaction ngắn.
- Context switch phải tách riêng khỏi benchmark bulk.
- Không dùng số H3 để đại diện cho headline throughput của H.
- Không dùng số baseline payload để nói thay cho streaming headline.
- Nếu claim là “multi-outstanding” hoặc “write pipeline”, phải có số vi kiến trúc tương ứng.

## 4. Tiêu chí thuyết phục ban giám khảo

Thiết kế sẽ dễ thuyết phục hơn nếu có:

- kiến trúc rõ
- RTL rõ
- firmware rõ
- benchmark rõ
- demo rõ

Trong đó, benchmark rõ nghĩa là:

- bảng H3 đứng riêng như baseline
- bảng baseline payload đứng riêng như mốc cũ
- bảng streaming headline đứng riêng như implementation đột phá
- bảng overlap metrics đứng riêng như bằng chứng vi kiến trúc

## 5. Tài liệu benchmark đã khóa

- `H3 control-plane baseline`: doc trong `h3_reference_control_plane.md`
- `baseline payload datapath`: doc trong `dot_c_dma_payload_path.md`
- `streaming headline architecture`: doc trong `kien_truc_dot_pha_H.md`
- `streaming sweep golden`: doc trong `golden_data_H.md`

## 6. Hook RTL hiện đã có cho benchmark

Trong RTL hiện tại đã có lớp hook nội bộ để hỗ trợ benchmark:

- `payload_feed_pulse`
- `payload_chain_pulse`
- `write_chain_pulse`
- `ingress_swap_pulse`
- `egress_swap_pulse`
- counter cho read issue / read done / write done
- counter cho busy cycle / core wait cycle

Ngoài các hook trong RTL, testbench cũng đã có thêm lớp đo chuyên dụng:

- `tb_ascon_dma.v`: regression functional chính
- `tb_dma_overlap_metrics.v`: đo dấu hiệu overlap ở mức engine

Hai bằng chứng mới đã được khóa:

- `peak accepted outstanding AR = 2`
- `peak pending BRESP = 2`

## 7. Ý nghĩa của hai bằng chứng mới

### 7.1 `peak accepted outstanding AR = 2`

Ý nghĩa:

- read side không còn chỉ là “một burst xong mới xin burst tiếp”
- datapath đã bắt đầu có hành vi multi-outstanding thật sự
- credit-based issue không chỉ là ý tưởng trên tài liệu

### 7.2 `peak pending BRESP = 2`

Ý nghĩa:

- write side đã bắt đầu tách issue khỏi completion tốt hơn
- `BVALID` không còn là nút chặn tuyệt đối của steady-state
- write chain đã có bằng chứng pipeline ở mức engine

## 8. Điều benchmark của H không nên chỉ nhìn

Benchmark của H không nên chỉ nhìn:

- `dma_done`
- latency cuối transaction

Mà cần nhìn thêm:

- steady-state behavior
- khả năng chain giữa các burst
- mức giảm bubble trong datapath
- mức `outstanding` và `pending response` ở thời điểm runtime

## 9. Ghi chú diễn giải

- `COH_CTRL=1` là mode headline hiệu năng chính của `H`.
- `COH_CTRL=3` là mode fallback coherence đầy đủ để ưu tiên correctness đầu ra.
- Trong mốc chốt ngày `2026-07-16`, nhánh `COH_CTRL=1` payload dài đã phải được khóa lại bằng sửa routing snoop để không bị dcache không liên quan chặn read-snoop path.

## 10. Kết luận

Từ sau mốc cập nhật này, benchmark của H có thể được chia thành 3 lớp rõ:

1. benchmark reference control-plane
2. benchmark payload/throughput ở mức hệ thống
3. benchmark overlap ở mức engine

Việc tách ba lớp này giúp phần trình bày của H chặt hơn, trung thực hơn, và bám đúng tinh thần “đột phá kiến trúc có bằng chứng đo được”.
