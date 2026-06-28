# Paper 2 — Bảng so sánh kết quả

## Mục đích
Tài liệu này dùng để so sánh **baseline kiến trúc cũ** với **kiến trúc mới Phương án B**: writeback DCache `valid/dirty` + sideband snoop responder cho ASCON DMA.

Kết quả mới bổ sung thêm một biến thể cải tiến: **Selective Coherent DMA** (`COH_CTRL=1`), trong đó DMA vẫn snoop read source/input để đọc dirty DCache data không cần `fence`, nhưng dùng non-temporal output mode để tránh write-invalidate khi output buffer là producer-owned/cold.

## Quy tắc so sánh
- cùng toolchain RISC-V và clock 100 MHz
- cùng SoC/testbench khi so active DMA window
- tách rõ metric **core-only**, **SoC DMA active**, và **end-to-end firmware**
- không gọi Phương án B là full MESI/MEI; đây là minimal hardware-coherent DMA cho single CPU + ASCON DMA

## Bảng kết quả hiện tại

| Metric | Baseline cũ | Kiến trúc mới | Chênh lệch | Ghi chú |
|---|---:|---:|---:|---|
| ASCON core-only peak, 16B/block | ~4.25 Gbps | không đổi | 0 | Core trần lý thuyết, không qua SoC/DMA/AXI/cache |
| ASCON core-only peak, 8B/block | ~2.125 Gbps | không đổi | 0 | Core-only upper bound |
| SoC ASCON-DMA write-complete, 128B payload, full coherent `COH_CTRL=3` | ~1.13 Gbps | ~598.83 Mbps | ~-46.8% throughput | Fair metric for both: DMA_START→last `M2_B`. Fenced: 91 cycles. Full coherent no-fence: 171 cycles, `8/8` full-line snoop read hits, `9` output invalidates, `M2_AR=0`, `M2_AW=2`. |
| SoC ASCON-DMA write-complete, 128B payload, selective coherent `COH_CTRL=1` | ~1.13 Gbps | ~1113.04 Mbps | ~-1.1% throughput | Read snoop vẫn bảo toàn no-fence input coherence: `8/8` snoop read hits, `0` output invalidates, `M2_AR=0`, `M2_AW=2`; 92 cycles so với baseline 91 cycles. |
| SoC ASCON-DMA active, 8B legacy/fence | ~188.24 Mbps | ~188.24 Mbps | ~0 | `run_perf_bench.v`, DMA_START→DMA_DONE = 34 cycles; kiến trúc mới không bật coherent path trong firmware bench này |
| SoC ASCON-DMA active, 8B no-coherent no-fence | N/A | ~237.04 Mbps | N/A | `run_soc_nocoherent_nofence.v`, 64 bit / 27 cycles @100MHz; đối chứng tắt `DMA_COH_CTRL`, có `M2_AR=1`, core không thấy dirty DCache |
| SoC ASCON-DMA active, 8B coherent no-fence | N/A | ~133.33 Mbps | N/A | `run_soc_coherent_nofence.v`, 64 bit / 48 cycles @100MHz; snoop read hit dirty data, `M2_AR=0`, `M2_AW=1`, 2 output invalidates. |
| Latency DMA start→last M2_B, 128B full coherent `COH_CTRL=3` | 91 cycles | 171 cycles | +80 cycles | Same externally visible write-completion metric for both tests. Chi phí chính đến từ `9` output invalidate miss. |
| Latency DMA start→last M2_B, 128B selective coherent `COH_CTRL=1` | 91 cycles | 92 cycles | +1 cycle | Gần ngang baseline software-fenced nhưng vẫn không phát AXI read cho source (`M2_AR=0`) vì DMA lấy dirty input qua snoop. |
| Latency DMA start→done, 8B legacy/fence | 34 cycles | 34 cycles | 0 | Legacy firmware path vẫn dùng fence và AXI read |
| Latency DMA start→done, 8B no-coherent no-fence | N/A | 27 cycles | N/A | Negative control; không bảo toàn dirty DCache data |
| Latency DMA start→done, 8B coherent no-fence | N/A | 48 cycles | N/A | Giá của snoop read + 2 output invalidates + 1 AXI write burst trong smoke test |
| ASCON M2 AXI read count, 8B coherent no-fence | N/A | 0 | N/A | Chứng minh DMA lấy plaintext bằng snoop hit thay vì AXI read |
| ASCON M2 AXI read count, 8B no-coherent no-fence | N/A | 1 | N/A | Đối chứng: tắt coherence thì DMA fallback AXI read |
| Số `fence` cần sau dirty plaintext trước DMA start | 1 software flush/fence path | 0 | bỏ được fence | Coherent firmware start DMA bằng raw MMIO sau dirty stores, không có `fence` xen giữa |
| Functional coherent no-fence | không hỗ trợ | PASS | đạt mục tiêu | Dirty plaintext `a5a50001/5a5a0002` được DMA/core thấy qua snoop |
| Functional no-coherent negative | N/A | PASS | kiểm chứng đối chứng | Tắt coherence thì core nhận `00000000/00000000`, không thấy dirty data |

## Log nguồn số đo

### Software-fenced baseline sweep bằng `run_fence_sweep.sh`

Đây là nhánh **kiến trúc cũ/software-managed coherence**: firmware ghi dirty plaintext vào DCache, sau đó dùng `ASCON_WRITE(CTRL, DMA_START)` để có `fence w,w` trước MMIO start. DMA không dùng sideband snoop (`COH_CTRL=0`) và đọc source qua AXI.

| Payload | Fair cycles | Throughput fair | Snoop read | Snoop inv | M2 AR | M2 AW | Ghi chú |
|---:|---:|---:|---:|---:|---:|---:|---|
| 128B | 91 | 1125.27 Mbps | 0 | 0 | 2 | 2 | Baseline fair control đã dùng trong so sánh 128B |
| 256B | 159 | 1288.05 Mbps | 0 | 0 | 4 | 3 | AXI read/write burst path, không coherence hardware |
| 512B | 295 | 1388.47 Mbps | 0 | 0 | 8 | 5 | Throughput tăng khi overhead start/write tag được amortize |
| 1024B | 567 | 1444.80 Mbps | 0 | 0 | 16 | 9 | Mốc baseline cao nhất trong sweep hiện tại |

### Sweep payload mới bằng `run_coherent_sweep.sh`

Regular no-fence coherent sweep, output buffer không bị CPU cache-hit trước DMA:

| Payload | Mode | Fair cycles | Throughput fair | Snoop read | Snoop inv | M2 AR | M2 AW | Ghi chú |
|---:|---|---:|---:|---:|---:|---:|---:|---|
| 128B | Full coherent `COH_CTRL=3` | 171 | 598.83 Mbps | 8 | 9 | 0 | 2 | Full write-invalidate, output invalidate đều miss trong mốc 128B |
| 128B | Selective coherent `COH_CTRL=1` | 92 | 1113.04 Mbps | 8 | 0 | 0 | 2 | Read snoop no-fence, non-temporal output |
| 256B | Full coherent `COH_CTRL=3` | 296 | 691.89 Mbps | 16 | 17 | 0 | 3 | Source vẫn snoop-hit toàn bộ trong mốc này |
| 256B | Selective coherent `COH_CTRL=1` | 160 | 1280.00 Mbps | 16 | 0 | 0 | 3 | Cải thiện nhờ bỏ write-invalidate |
| 512B | Full coherent `COH_CTRL=3` | 592 | 691.89 Mbps | 35 | 33 | 6 | 5 | Bắt đầu có conflict/capacity fallback AXI read |
| 512B | Selective coherent `COH_CTRL=1` | 312 | 1312.82 Mbps | 35 | 0 | 6 | 5 | Vẫn nhanh hơn full coherent nhờ bỏ invalidate |
| 1024B | Full coherent `COH_CTRL=3` | 1129 | 725.60 Mbps | 67 | 65 | 6 | 9 | Payload lớn bị ảnh hưởng bởi cache conflict và invalidate |
| 1024B | Selective coherent `COH_CTRL=1` | 584 | 1402.74 Mbps | 67 | 0 | 6 | 9 | Throughput cao nhất trong sweep hiện tại |

Lưu ý về 4KB: firmware sweep hiện chặn build vì `PT + CT + tag` vượt layout DMEM an toàn trước stack. Lỗi build cụ thể là `Sweep PT/CT buffers overlap DMEM stack region`. Muốn đo 4KB cần mở rộng DMEM/testbench hoặc chuyển buffer sang vùng memory ngoài đủ lớn; không nên ghi số 4KB khi chưa thay đổi memory map.

### Bảng so sánh để vẽ biểu đồ

Dữ liệu CSV nằm ở `paper2/sweep_results.csv`.

| Payload | Software-fenced baseline | Full coherent `COH_CTRL=3` | Selective coherent `COH_CTRL=1` | Selective vs baseline |
|---:|---:|---:|---:|---:|
| 128B | 1125.27 Mbps | 598.83 Mbps | 1113.04 Mbps | -1.1% |
| 256B | 1288.05 Mbps | 691.89 Mbps | 1280.00 Mbps | -0.6% |
| 512B | 1388.47 Mbps | 691.89 Mbps | 1312.82 Mbps | -5.4% |
| 1024B | 1444.80 Mbps | 725.60 Mbps | 1402.74 Mbps | -2.9% |

Diễn giải biểu đồ: full coherent mode giảm khoảng một nửa throughput vì write-invalidate nằm trên critical path. Selective coherent mode gần baseline hơn nhiều, nhưng vẫn giữ lợi ích chính là no-fence input coherence.

### `run_perf_bench.v` legacy/fence 8B

```text
DMA START #1 at cycle 5076, len=8
DMA DONE  #1 at cycle 5110
DMA active latency = 34 cycles
Bandwidth = 188.24 Mbps @100MHz
M2 AR/AW = 1/1
```

Lưu ý: bench này hiện halt trước khi UART PASS được bắt (`PASS count=0`) nhưng ASCON DMA event hoàn tất không lỗi. Dùng số này như legacy active-window sanity, không dùng để claim end-to-end PASS.

### `run_soc_coherent_nofence.v`

```text
DMA_START at cycle 3770, coh_ctrl=3
SNOOP_RD_REQ addr=100001c0
SNOOP_RESP hit=1 data=5a5a0002a5a50001
DMA_CORE_DATA ptext0=a5a50001 ptext1=5a5a0002
DMA_DONE at cycle 3818
snoop inv req/hit = 2/1
M2 AR/AW = 0/1
PASS
```

Tính toán: 64 bits / 48 cycles * 100 MHz = ~133.33 Mbps.

### `run_soc_nocoherent_nofence.v`

```text
DMA_START at cycle 3770, coh_ctrl=0
M2_AR addr=100001c0
DMA_CORE_DATA ptext0=00000000 ptext1=00000000
DMA_DONE at cycle 3797
M2 AR/AW = 1/1
PASS
```

Tính toán: 64 bits / 27 cycles * 100 MHz = ~237.04 Mbps. Đây là negative control, không phải kết quả đúng về coherence vì DMA không thấy dirty DCache data.


### `run_soc_fence_128b.v` — fair software-fenced control

```text
DMA_START at cycle 7055, coh_ctrl=0
M2 AR/AW = 2/2
last M2 AW/WLAST/B = 7136/7145/7146
fair write-complete = 91 cycles
PASS
```

Calculation: 1024 bits / 91 cycles * 100 MHz = ~1125.27 Mbps. This is a valid software-fenced control: dirty DCache data is flushed before DMA, then DMA uses AXI reads.

### `COH_CTRL=3 bash run_coherent_sweep.sh 128` — full coherent fair metric

```text
DMA_START at cycle 6987, coh_ctrl=3
SNOOP_RD_REQ/HIT = 8/8
M2 AR/AW = 0/2
SNOOP_INV_REQ/HIT = 9/0
last M2 B = 7158
fair write-complete = 171 cycles
max STATUS = 0x0000000a, slave STATUS reads = 3
firmware STATUS.DMA_DONE + internal dma_done_w observed
```

Calculation: 1024 bits / 171 cycles * 100 MHz = ~598.83 Mbps. This is fair against the fenced control because both use `DMA_START→last M2_B`. The full coherent path uses 8 full-line 128-bit snoop reads, pre-invalidates 9 DCache lines, and emits 2 AXI write bursts.

### `COH_CTRL=1 bash run_coherent_sweep.sh 128` — selective coherent fair metric

```text
DMA_START at cycle 6987, coh_ctrl=1
SNOOP_RD_REQ/HIT = 8/8
M2 AR/AW = 0/2
SNOOP_INV_REQ/HIT = 0/0
last M2 B = 7079
fair write-complete = 92 cycles
PASS
```

Calculation: 1024 bits / 92 cycles * 100 MHz = ~1113.04 Mbps. This keeps the critical no-fence property for source/input data (`M2_AR=0`, snoop read hits dirty DCache data) while removing write-side invalidates for producer-owned output buffers.

### Output-cache-hit control

Firmware/testbench mới:
- `gnu_toolchain/tests/test_ascon_dma_output_cachehit.c`
- `run_output_cachehit.sh`

Mục tiêu là chứng minh điều kiện áp dụng của `COH_CTRL=1`. Firmware cố tình cho CPU ghi bẩn output buffer trước DMA. Nếu dùng selective mode (`COH_CTRL=1`), CPU đọc lại output sau DMA vẫn thấy stale cache line; firmware coi đây là PASS vì nó chứng minh non-temporal output cần software contract. Nếu dùng full mode (`COH_CTRL=3`), DCache phải invalidate/writeback dirty output line trước DMA write, nên CPU đọc lại output mới.

| Test | Kết quả | Fair cycles | Throughput fair | Snoop inv req/hit | Ý nghĩa |
|---|---:|---:|---:|---:|---|
| Output-cache-hit `COH_CTRL=1` | PASS | 92 | 1113.04 Mbps | 0/0 | Chứng minh giới hạn: selective mode không bảo vệ output đã cache-hit/dirty |
| Output-cache-hit `COH_CTRL=3` | PASS | 244 | 419.67 Mbps | 9/9 | Full coherent sửa đúng trường hợp output dirty-cache nhưng trả giá writeback/invalidate lớn |

## Diễn giải

- Phương án B đã đạt mục tiêu chính: **DMA đọc được dirty DCache data không cần software fence/flush**.
- Coherent 8B smoke test chậm hơn legacy 8B active window vì thêm snoop read và snoop invalidate cho output writes. Đây là overhead dự kiến của coherence path ở payload nhỏ.
- Negative no-coherent path nhanh hơn coherent path nhưng sai về mặt dữ liệu khi nguồn nằm dirty trong DCache; do đó không phải phương án hợp lệ cho mục tiêu no-fence.
- Full coherent 128B (`COH_CTRL=3`) vẫn chậm vì trả giá cho `9` output invalidate request dù tất cả đều miss (`snoop inv hit = 0`). Đây là bottleneck được định lượng rõ, không phải suy đoán.
- Selective coherent 128B (`COH_CTRL=1`) là cải tiến chính: bỏ write-invalidate khỏi critical path cho output producer-owned/cold, giảm latency từ `171` xuống `92` cycles và đưa throughput từ `598.83` lên `1113.04 Mbps`.
- Luận điểm paper nên nhấn mạnh **direction-aware coherence**: input/source cần read snoop để đúng dữ liệu no-fence; output/destination có thể dùng non-temporal write khi software contract đảm bảo CPU không giữ cache copy cần đọc ngay.
- Hướng pipelined snoop request chỉ cải thiện nhỏ ở 128B (`172→171 cycles`), cho thấy read-side snoop không phải bottleneck chính trong mốc này. Muốn tăng thêm cho full coherent cần tối ưu write-invalidate hoặc thêm cơ chế range invalidate có hit-filter.
- Output-cache-hit control làm rõ trade-off: `COH_CTRL=1` là mode hiệu năng cho output producer-owned/cold; `COH_CTRL=3` là fallback đúng đắn khi output có thể đang dirty trong DCache.

## Việc còn cần đo

1. Mở rộng memory map hoặc thêm external memory model nếu thật sự cần điểm 4KB; hiện DMEM 8KB/test firmware không đủ chỗ an toàn cho `PT + CT + tag + stack`.
2. Nếu cần end-to-end firmware number, sửa `run_perf_bench.v` halt detection/UART capture để bench báo `[PASS]` ổn định.
3. Ghi lại log đầy đủ vào `log/` nếu chuẩn bị nộp paper.
