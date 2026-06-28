# Paper 2 — Kế hoạch kiến trúc mới

## Mục tiêu
Nâng cấp SoC lên kiến trúc **Hardware-Coherent DMA** theo hướng **Sideband Snoop** và bổ sung **ATU** để DMA dùng địa chỉ đã dịch.

Mục tiêu kỹ thuật gốc cần giữ nguyên:
1. Loại bỏ phụ thuộc vào `fence` để flush/invalidate cache trong firmware
2. Cho DMA snoop trực tiếp DCache qua sideband, không đi qua AXI crossbar
3. Ban đầu cân nhắc MESI/MEI; quyết định hiện tại chọn snoop responder tối thiểu để giảm rủi ro
4. Bổ sung ATU cho DMA

## Nguyên tắc kiến trúc
- Không thay đổi mục tiêu kỹ thuật ban đầu
- Không biến baseline thành “đã coherent”
- Mọi thay đổi phải phục vụ mục tiêu đồng nhất dữ liệu giữa CPU cache và DMA
- Sideband snoop là đường điều khiển bổ sung, không thay thế hoàn toàn AXI

## Phạm vi thay đổi
### 1. DCache
- giữ `valid/dirty` trong implementation hiện tại
- bổ sung snoop hit/miss responder cho DMA
- hỗ trợ invalidate an toàn; dirty invalidate phải writeback full line trước khi invalidate

### 2. DMA
- chèn trạng thái `SNOOP_REQ` và `SNOOP_WAIT`
- ưu tiên snoop trước khi phát AXI read/write
- đọc trúng cache thì nạp thẳng vào FIFO

### 3. ATU
- nhận địa chỉ ảo từ phần mềm
- xuất địa chỉ vật lý cho DMA
- mọi luồng snoop và AXI dùng địa chỉ vật lý

### 4. Top-level routing
- kéo sideband từ DMA tới DCache
- thêm wire snoop giữa các module liên quan

### 5. Firmware
- bỏ các `fence` không còn cần thiết sau khi kiến trúc mới hoạt động đúng
- giữ benchmark và test flow nhất quán để so sánh với baseline

## Tiêu chí hoàn thành
- dữ liệu ASCON đúng mà không cần flush cache bằng phần mềm
- DMA đọc được dữ liệu sạch từ DCache khi có snoop hit
- DMA invalidate đúng khi ghi đè
- kết quả benchmark có thể so sánh trực tiếp với baseline

## Ghi chú
Tài liệu này là **kế hoạch kiến trúc mới**, không phải kết quả đo đạc.
Số liệu chỉ được đưa vào sau khi triển khai và chạy lại benchmark.

## Trạng thái triển khai (cập nhật 2026-06-28)

### ✅ Đã làm xong

#### RTL / kiến trúc

| Khối | File chính | Việc đã làm |
|---|---|---|
| **DMA ATU** | `ascon/dma/rtl/dma_atu.v` | Tách logic dịch địa chỉ base/window thành module riêng. DMA dùng địa chỉ đã dịch cho cả AXI và snoop. |
| **DMA read snoop FSM** | `ascon/dma/rtl/dma_read_engine.v` | Thêm luồng `RD_SNP_REQ` / `RD_SNP_WAIT`: nếu coherence bật thì snoop DCache trước; snoop hit dùng data trả về, snoop miss hoặc coherence off thì fallback AXI read. |
| **DMA write snoop FSM** | `ascon/dma/rtl/dma_write_engine.v` | Thêm invalidate trước mỗi DMA write beat khi coherence bật. Coherence mode dùng single-beat write để invalidate chính xác từng beat. |
| **Selective coherent sweep mode** | `run_coherent_sweep.sh`, `run_soc_coherent_nofence_sweep.v`, `gnu_toolchain/tests/test_ascon_dma_coherent_nofence_sweep.c` | Thêm tham số `COH_CTRL`: `3` = read snoop + write invalidate đầy đủ; `1` = read-coherent/no-fence + non-temporal output, dùng để định lượng bottleneck write-invalidate. |
| **DMA snoop arbitration** | `ascon/dma/rtl/dma_snoop_arb.v` | Tách arbiter shared `DC_SNOOP_*` giữa read/write engine. |
| **DMA error latch** | `ascon/dma/rtl/dma_err_latch.v` | Tách latch lỗi, giữ `dma_err_addr`, tạo trạng thái lỗi ổn định cho slave/status. |
| **ASCON DMA top** | `ascon/dma/rtl/ascon_dma.v`, `ascon/dma/ascon_dma.v` | Refactor wiring sang các submodule DMA/ATU/snoop/error; giữ interface coherent. |
| **DCache snoop responder** | `cache_interface/dcache/dcache_controller.v` | Thêm cổng `dc_snoop_*`, nhận snoop read/invalidate an toàn khi cache idle; trả `resp_hit`, `resp_data`. |
| **DCache invalidate line** | `cache_interface/dcache/dcache_tag_array.v` | Thêm khả năng invalidate một cache line theo index từ snoop path. |
| **DCache top interface** | `cache_interface/dcache/dcache_top.v` | Expose sideband snoop port lên top DCache. |
| **Top-level routing** | `soc_top.v` | Nối `DC_SNOOP_*` từ ASCON DMA sang DCache. |
| **ASCON core-start comment** | `ascon/ascon_top.v` | Sửa comment cho khớp RTL hiện tại: DMA start core sớm, core chờ `dma_core_data_valid` trong data-load. Đã thử gate start bằng data_valid nhưng flow bị kẹt nên không giữ thay đổi đó. |

#### Điểm an toàn DCache đã xử lý

- Snoop read hit trên dirty line trả data trực tiếp từ cache line, không cần AXI read.
- Snoop invalidate hit clean line thì invalidate line.
- Snoop invalidate hit dirty line thì **writeback full cache line trước khi invalidate**.
- Unit test đã kiểm dirty word và clean half-line đều được giữ đúng sau writeback.

#### Firmware / testbench đã tạo

| File | Mục đích |
|---|---|
| `gnu_toolchain/tests/test_ascon_dma_coherent_nofence.c` | Firmware smoke test: CPU ghi plaintext dirty trong DCache, sau đó start DMA bằng raw MMIO không có `fence` sau dirty stores. `DMA_COH_CTRL_VALUE=3`. |
| `gnu_toolchain/tests/test_ascon_dma_coherent_nofence.hex` | Hex build cho coherent no-fence SoC test. |
| `gnu_toolchain/tests/test_ascon_dma_nocoherent_nofence.c` | Negative firmware: cùng flow nhưng `DMA_COH_CTRL_VALUE=0` để tắt coherence. |
| `gnu_toolchain/tests/test_ascon_dma_nocoherent_nofence.hex` | Hex build cho negative no-coherent SoC test. |
| `run_soc_coherent_nofence.v` | SoC-level demo/test: yêu cầu snoop read hit dirty plaintext, `M2_AR=0`, DMA write output OK. |
| `run_soc_nocoherent_nofence.v` | SoC-level đối chứng: yêu cầu không có snoop, có `M2_AR`, core không thấy dirty plaintext; firmware phải báo `RET_BADOUT` vì no-fence + no-coherence đọc stale memory. |
| `gnu_toolchain/tests/test_ascon_dma_coherent_nofence_128b.c/.hex` | Firmware 128B: ghi 16 block dirty trong DCache, start DMA no-fence với coherence bật. |
| `run_soc_coherent_nofence_128b.v` | SoC-level benchmark 128B: chờ mailbox PASS + internal `dma_done_w`; chứng minh read-side full-line snoop 128-bit (`8/8`, `M2_AR=0`) và ghi output bằng 2 AXI bursts. |
| `run_coherent_sweep.sh` | Sweep payload và mode coherence. Mặc định `COH_CTRL=3`; có thể chạy `COH_CTRL=1 bash run_coherent_sweep.sh 128` để đo read-coherent + non-temporal output. |
| `gnu_toolchain/tests/test_ascon_dma_output_cachehit.c`, `run_output_cachehit.sh` | Test đối chứng output-cache-hit: chứng minh `COH_CTRL=1` cần contract output producer-owned/cold, còn `COH_CTRL=3` xử lý đúng khi output dirty trong DCache. |
| `run_paper2_measurements.sh` | Script gom các phép đo chính cho paper2: sweep `128/256/512/1024B` với `COH_CTRL=3/1` và output-cache-hit control. |
| `gnu_toolchain/tests/test_ascon_dma_fence_sweep.c`, `run_fence_sweep.sh` | Sweep baseline software-fenced/kiến trúc cũ với `COH_CTRL=0`, cùng metric `DMA_START→last M2_B` để so sánh trực tiếp với kiến trúc mới. |
| `gnu_toolchain/tests/test_ascon_dma_fence_128b.c/.hex` | Firmware 128B có software fence: dirty DCache được flush trước DMA, coherence tắt. |
| `run_soc_fence_128b.v` | Fair software-fenced 128B control: internal DMA done = 90 cycles. |
| `cache_interface/dcache/tb/tb_dcache_snoop.v` | Unit test DCache snoop: read dirty hit, invalidate dirty writeback full line, invalidate xong thì read snoop miss. |

#### Kết quả đã chạy

| Test | Kết quả | Ý nghĩa |
|---|---:|---|
| `tb_dcache_snoop` | 10 PASS / 0 FAIL | DCache snoop responder và dirty invalidate writeback OK. |
| `tb_dcache` | 59 PASS / 0 FAIL | Không phá regression DCache hiện có. |
| `tb_ascon_dma` | 66 PASS / 0 FAIL | DMA/ATU/snoop/error regression OK. Có warning cũ `sync_fifo count` width 4 vs 6, không làm fail test. |
| `run_soc_coherent_nofence` | PASS | DMA đọc dirty plaintext bằng snoop, không dùng AXI read fallback. |
| `run_soc_nocoherent_nofence` | PASS | Negative-control đúng: firmware báo `RET_BADOUT=0xffff0003`, DMA fallback AXI read, không snoop, core không thấy dirty DCache. |
| `run_soc_fence_128b` | PASS | Fair software-fenced 128B control: `DMA_START→last M2_B = 91 cycles`, ~1125.27 Mbps, `M2_AR=2`, no snoop. |
| `COH_CTRL=3 bash run_coherent_sweep.sh 128` | PASS | Full coherent no-fence: `DMA_START→last M2_B = 171 cycles`, ~598.83 Mbps, `8/8` full-line snoop read hit, `9` invalidate requests, `M2_AR=0`, `M2_AW=2`. |
| `COH_CTRL=1 bash run_coherent_sweep.sh 128` | PASS | Selective coherent no-fence: read snoop vẫn bật, write-invalidate tắt theo non-temporal output mode; `DMA_START→last M2_B = 92 cycles`, ~1113.04 Mbps, `8/8` snoop read, `0` invalidate, `M2_AR=0`, `M2_AW=2`. |
| `run_paper2_measurements.sh` | PASS | Sweep baseline `COH_CTRL=0`, full coherent `COH_CTRL=3`, selective `COH_CTRL=1` cho `128/256/512/1024B` và output-cache-hit control đều chạy xong; số liệu đã cập nhật trong `paper2/03_comparison_results.md`. |
| `git diff --check` | PASS | Không có lỗi whitespace trong các file liên quan. |

### Kết luận hiện tại

- Chọn **Phương án B: giữ nguyên DCache `valid/dirty` + Sideband Snoop Responder**.
- Đường **Hardware-Coherent DMA tối thiểu** đã hoạt động end-to-end cho ASCON DMA.
- Firmware có thể start DMA sau dirty DCache stores mà không cần `fence` ở đoạn quan trọng.
- Coherent path không phải pass tình cờ: negative test tắt coherence cho thấy DMA không thấy dirty data, phải dùng AXI read, và firmware báo `RET_BADOUT` như mong đợi.
- DCache data array lưu full line 16B/128-bit, không phải 64B/512-bit; vì vậy tối ưu snoop read được triển khai là full-line 128-bit, giảm 128B source read từ 16 snoop beat xuống 8 snoop line.
- Kết quả mới cho thấy bottleneck lớn nhất ở 128B là **write-side invalidate**: full coherent `COH_CTRL=3` mất 171 cycles, trong khi read-coherent + non-temporal output `COH_CTRL=1` chỉ mất 92 cycles, gần ngang software-fenced control 91 cycles.
- Firmware/STATUS polling 128B đã được sửa: lỗi gốc là `load_use_hazard` flush ID/EX trong lúc `stall_if` freeze EX/MEM, làm mất lệnh load STATUS từ stack; fix ở `cpu/core/hazard_detection.v` giữ ID/EX khi front-end đang stall.
- Không gọi đây là MESI/MEI đầy đủ. Thuật ngữ phù hợp hơn: **minimal hardware-coherent DMA**, **sideband snoop responder**, hoặc **writeback DCache with DMA snoop support**.

### Cải tiến đề xuất cho paper: Selective Coherent DMA

| Nội dung | Đánh giá |
|---|---|
| **Mô tả** | Tách coherence theo vai trò buffer: source/input dùng read snoop để DMA thấy dirty DCache data không cần `fence`; destination/output dùng non-temporal producer-owned mode để tránh invalidate miss trên critical path. |
| **Cơ sở số liệu** | Với 128B, full coherent `COH_CTRL=3` có `9` invalidate request nhưng `0` hit; khi bỏ write-invalidate (`COH_CTRL=1`), latency giảm từ `171` xuống `92` cycles, throughput tăng từ `598.83` lên `1113.04 Mbps`. |
| **Luận điểm paper** | Không chỉ thêm coherence, mà chọn lọc coherence theo hướng dữ liệu: bảo toàn correctness cho input dirty-cache, đồng thời tránh chi phí coherence không sinh lợi cho output buffer lạnh/producer-owned. |
| **Điều kiện áp dụng** | Output buffer không được CPU giữ bản copy dirty/valid cần đọc lại ngay mà không invalidate. Nếu CPU đã cache output trước DMA, cần dùng `COH_CTRL=3` hoặc software invalidate sau DMA. |
| **Tên đề xuất** | “Selective Coherent DMA”, “Read-Coherent Non-Temporal DMA”, hoặc “Direction-Aware Coherent DMA for ASCON Acceleration”. |

### Quyết định kiến trúc: Phương án B

| Nội dung | Đánh giá |
|---|---|
| **Mô tả** | Giữ tag cache dạng `valid/dirty`, bổ sung snoop responder để DMA đọc dirty line. Với output, hỗ trợ cả full write-invalidate (`COH_CTRL=3`) và selective non-temporal mode (`COH_CTRL=1`) cho buffer producer-owned. |
| **Lý do chọn** | Đáp ứng đúng mục tiêu paper ở mức hệ thống: DMA thấy dữ liệu mới nhất mà không cần firmware flush/fence, đồng thời giảm rủi ro sửa lớn vào DCache. |
| **Ưu điểm** | Khối lượng sửa đổi nhỏ, dễ kiểm chứng, regression hiện đã PASS. Mode selective đưa throughput 128B về gần baseline software-fenced nhưng vẫn giữ no-fence read-side coherence. |
| **Nhược điểm** | Không phải MESI/MEI đúng nghĩa; `COH_CTRL=1` cần contract rõ về output buffer. Reviewer có thể xem đây là direction-aware DMA coherence thay vì full cache-coherence protocol. |
| **Cách diễn đạt đề xuất** | “Selective read-coherent DMA with non-temporal output writes” hoặc “direction-aware sideband snoop mechanism for DMA-cache coherence”. |

### ⚠️ Còn thiếu / cần quyết định

#### Bắt buộc nếu muốn chốt paper với số liệu

| Việc còn thiếu | Lý do |
|---|---|
| **Mốc 4KB** | Chưa đo được với layout hiện tại vì `PT + CT + tag` vượt vùng DMEM an toàn trước stack. Cần mở rộng memory map hoặc thêm external memory model nếu paper bắt buộc có 4KB. |
| **Đo CPU stall cycles do fence** | Cần so sánh baseline có flush/invalidate bằng `fence` với kiến trúc mới không fence, dùng stall cycles/cycle count để phản ánh chi phí phần mềm. |
| **Đo firmware lines of code** | Cần thống kê baseline firmware phải giữ code flush/invalidate/fence so với kiến trúc mới, để định lượng mức đơn giản hóa phía phần mềm. |
| **End-to-end firmware benchmark ổn định** | `run_perf_bench.v` đo được active DMA 8B=34 cycles nhưng UART PASS chưa được bắt ổn định; cần sửa nếu muốn số end-to-end firmware trong paper. |
| **Điều chỉnh wording paper** | Thay các chỗ gọi MESI/MEI bằng “sideband snoop responder”, “minimal hardware-coherent DMA”, hoặc “writeback DCache with DMA snoop support”. |
| **Nêu giới hạn rõ ràng** | Paper cần nói đây không phải full multicore MESI; mục tiêu là DMA-cache coherence cho single CPU + ASCON DMA. |

#### Không làm trong hướng hiện tại, chỉ để mở rộng sau

| Việc mở rộng | Ghi chú |
|---|---|
| **Refactor MESI/MEI đầy đủ** | Không cần cho demo/paper hiện tại. Chỉ làm nếu muốn claim full cache coherency protocol. |
| **Refactor tag state** | Đổi `valid/dirty` thành `mesi_state[1:0]` là thay đổi lớn, rủi ro cao hơn so với lợi ích hiện tại. |
| **Downgrade policy M→S/E** | Không triển khai trong phương án B. DMA read hit dirty trả data nhưng không model state downgrade MESI. |
| **Test MESI state transition** | Không áp dụng khi không claim MESI/MEI. Test hiện tập trung vào data coherence behavior. |

#### Nợ kỹ thuật / cleanup

| Việc còn thiếu | Ghi chú |
|---|---|
| **Build artifacts** | Build `-k` để lại `.elf/.dump/.map/.bin/.s` trong `gnu_toolchain/`. Có ích cho debug/demo, nhưng nên quyết định file nào giữ trong repo trước khi commit. |
| **Regression script gộp** | Hiện demo chạy bằng lệnh rời. Có thể thêm script `run_coherent_demo.sh` nếu cần thao tác nhanh khi trình diễn. |

### Log test quan trọng

```text
SoC coherent no-fence:
  SNOOP_RD_REQ addr=100001c0
  SNOOP_RESP hit=1 data=5a5a0002a5a50001
  DMA_CORE_DATA ptext0=a5a50001 ptext1=5a5a0002
  snoop inv req/hit = 2/1
  M2 AR/AW = 0/1
  DMA_START→DMA_DONE = 48 cycles (~133.33 Mbps)
  PASS

SoC no-coherent negative:
  DMA_COH_CTRL=0
  result_mailbox = 0xffff0003 (expected RET_BADOUT)
  snoop read req/hit = 0/0
  M2 AR/AW = 1/1
  DMA_CORE_DATA ptext0=00000000 ptext1=00000000
  PASS

SoC coherent no-fence 128B:
  DMA_START at cycle 6987
  SNOOP_RD_REQ/HIT = 8/8
  M2 AR/AW = 0/2
  SNOOP_INV_REQ/HIT = 9/0
  DMA_DONE at cycle 7157
  last M2 B = 7158
  fair write-complete = 171 cycles (~598.83 Mbps)
  max STATUS = 0x0000000a, slave STATUS reads = 3
  poll loop iterations = 5
  PASS

Selective coherent no-fence 128B (COH_CTRL=1):
  DMA_START at cycle 6987
  SNOOP_RD_REQ/HIT = 8/8
  M2 AR/AW = 0/2
  SNOOP_INV_REQ/HIT = 0/0
  DMA_DONE at cycle 7078
  last M2 B = 7079
  fair write-complete = 92 cycles (~1113.04 Mbps)
  PASS
```

### Lệnh chạy demo / regression

Chạy từ root repo:

```sh
cd /home/chithang/Project/Design_SoC_RISCV_ASCON
```

Build firmware no-fence:

```sh
cd gnu_toolchain
./compile_c_to_hex.sh -i tests/test_ascon_dma_coherent_nofence.c -o tests/test_ascon_dma_coherent_nofence.hex -k -O 0 -c
./compile_c_to_hex.sh -i tests/test_ascon_dma_nocoherent_nofence.c -o tests/test_ascon_dma_nocoherent_nofence.hex -k -O 0 -c
cd ..
```

Demo chính: coherent DMA không cần fence. Kỳ vọng: có snoop read hit dirty plaintext, không có `M2_AR` fallback.

```sh
iverilog -g2012 -I. -o /tmp/run_soc_coherent_nofence.vvp run_soc_coherent_nofence.v
vvp /tmp/run_soc_coherent_nofence.vvp
```

Demo đối chứng: tắt coherence. Kỳ vọng: không có snoop, có `M2_AR`, core không thấy dirty plaintext.

```sh
iverilog -g2012 -I. -o /tmp/run_soc_nocoherent_nofence.vvp run_soc_nocoherent_nofence.v
vvp /tmp/run_soc_nocoherent_nofence.vvp
```

Regression tối thiểu trước khi chốt kết quả:

```sh
iverilog -g2012 -I. -o /tmp/tb_dcache_snoop.vvp cache_interface/dcache/tb/tb_dcache_snoop.v
vvp /tmp/tb_dcache_snoop.vvp

iverilog -g2012 -I. -o /tmp/tb_dcache.vvp cache_interface/dcache/tb/tb_dcache.v
vvp /tmp/tb_dcache.vvp

iverilog -g2012 -I. -o /tmp/tb_ascon_dma.vvp ascon/dma/tb/tb_ascon_dma.v
vvp /tmp/tb_ascon_dma.vvp
```

Sweep 128B theo mode coherence:

```sh
COH_CTRL=3 bash run_coherent_sweep.sh 128
COH_CTRL=1 bash run_coherent_sweep.sh 128
```

Kiểm tra no-fence trong disassembly:

```sh
rg -n "<dirty_plaintext_without_fence>|# 1ec <dirty_plaintext_without_fence>|<ascon_write_raw>|fence" gnu_toolchain/test_ascon_dma_coherent_nofence.dump
rg -n "<dirty_plaintext_without_fence>|# 1ec <dirty_plaintext_without_fence>|<ascon_write_raw>|fence" gnu_toolchain/test_ascon_dma_nocoherent_nofence.dump
```

### Việc tiếp theo

1. Nếu cần điểm 4KB, mở rộng DMEM/testbench hoặc thêm external memory model rồi chạy lại `run_coherent_sweep.sh 4096`.
2. Đo CPU stall cycles do fence ở baseline và so với no-fence trong kiến trúc mới.
3. Thống kê firmware lines of code baseline vs kiến trúc mới để định lượng phần mềm được giản lược.
4. Nếu cần số end-to-end firmware, sửa `run_perf_bench.v` để UART PASS/halt detection ổn định hơn.
5. Trước khi commit, quyết định giữ hoặc dọn các build artifacts `.elf/.dump/.map/.bin/.s`.
