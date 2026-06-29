# Dual-Core Missing Items

Tài liệu này gồm lại các phần còn thiếu trong flow `paper2_2`, dựa trên:
- `paper2/paper2_2/dualcore_test_commands.md`
- `paper2/paper2_2/dualcore_test_results.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`
- `paper2/paper2_2/rtl_coherency_audit.md`
- `gnu_toolchain/tests_dualcore/README.md`

Mục tiêu là phân bịệt rõ:
- phần nàở đã chứng minh xong
- phần nàở mới dừng ở directed TB
- phần nàở vẫn chưa có top-level proof

Lưu ý:
- Tài liệu này là cầu nối từ baseline dual-core sang H1/H3.
- Các mục liên quan tới H3 và H1 mới là phần cần ưu tiên chốt tiếp theo.

## 1. Phần đã ổn

- DCache coherency core đã hoàn thành ở mức unit/regression.
- `tb_dcache.v`, `tb_dcache_snoop.v`, `tb_dcache_mesi.v` đều đã pass.
- Dual-core firmware suite đã pass:
  - `test_dualcore_basic`
  - `test_dualcore_cache_sweep`
  - `test_dualcore_fence_flush`
  - `test_dualcore_peer_snoop`
- Directed protocol TB `tb_dcache_dualcore_protocol.v` đã chứng minh:
  - `CPU0` refill vào `E`
  - `CPU0` write lên `M`
  - directed snoop-read lấy được line mới nhất từ owner
  - `CPU1` read miss tự động phát peer snoop qua snoop bus
  - dirty owner bị writeback/invalidate trước khi core miss refill
  - `CPU1` refills sau đó thấy data mới nhất
  - DMA-style coherent read lấy được line mới nhất từ cache owner
  - DMA-style coherent invalidate buộc dirty writeback và invalidate owner
- `ascon/dma/tb/tb_ascon_dma.v` đã pass `66 PASS / 0 FAIL`.
- DMA standalone TB hiện đã chứng minh:
  - coherent read snoop-hit hoạt động qua `coh_ctrl=2'b11`
  - coherent write path issue invalidate trước khi AXI write
  - AXI backpressure/error path vẫn ổn sau khi cập nhật snoop arbiter
- Full ASCON DMA SoC dual-core firmware đã pass:
  - `test_dualcore_ascon_dma_coherent`
  - `heartbeat=4`
  - `shared_count=1`
  - `aux0=0xac03d003`
  - `gpio=0xac03d003`
  - `core0_dc_req_count=12437`
  - `core1_dc_req_count=12527`
  - `dcache0 writes=4191 hits=12398`
  - `dcache1 writes=4183 hits=12522`
- `soc_top.v` đã có đường nối `CPU miss -> peer snoop` cho cả hai DCache thông qua arbiter 3 nguồn.
- Snoop fabric đã được siết lại:
  - top-level arbiter chuyển sang grant công bằng hơn
  - DMA snoop arbiter tránh fixed read-priority kéở dài
  - snoop bus có thêm kiểm tra collision dữ liệu bất thường
- `CPU1` đã có `mhartid = 1`; `CPU0` có `mhartid = 0`.
- `CPU1` đã được nối vào shared IRQ/debug request cơ bản.

## 2. Những thứ còn thiếu theo ưu tiên

### 2.1 Automatic `CPU miss -> peer snoop` ở top-level

Trạng thái hiện tại: đã làm và đã có firmware/top-level proof ổn định.

Đã làm:
- `dcache_top.v` và `dcache_controller.v` có port `miss_snoop_*`.
- Khi cacheable read miss và `miss_snoop_enable=1`, DCache phát snoop invalidate/read-ownership sang peer trước khi refill.
- `soc_top.v` nối `miss_snoop_*` của `DCache0`, `DCache1`, và snoop DMA/upstream vào `dcache_snoop_arb_3to1`.
- `tb_dcache_dualcore_protocol.v` đã verify case `CPU1 read miss -> snoop CPU0 dirty owner -> writeback/invalidate -> CPU1 refill latest data`.
- `test_dualcore_peer_snoop.c` đã pass trong `tb_soc/tb_soc_dualcore_suite.v`, với `aux0=0xfaceb00c` chứng minh CPU1 đọc được data mới nhất do CPU0 giữ dirty.
- Đã sửa starvation/race ở snoop path:
  - responder DCache không còn để CPU traffic chặn snoop vô hạn
  - snoop bus không drop response sớm trong lúc còn ở pha request

Tài liệu liên quan:
- `paper2/paper2_2/dualcore_test_commands.md`
- `paper2/paper2_2/dualcore_test_results.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`
- `paper2/paper2_2/rtl_coherency_audit.md`

Việc còn thiếu/chưa hoàn thiện:
- direct cache-to-cache data forwarding đã có cho CPU read miss khi peer snoop hit
- dirty owner vẫn writeback/invalidate để giữ correctness, nhưng requester không cần refill từ memory ở case forward-hit

### 2.2 Top-level CPU-CPU ownership transfer proof

Trạng thái hiện tại: đã đóng ở cả protocol TB và firmware/top-level suite.

Đã làm:
- `tb_dcache_dualcore_protocol.v` chứng minh ownership transfer ở mức DCache/snoop bus.
- Test này không chỉ còn là responder-only: nó đã có automatic miss-snoop từ `CPU1`.
- SoC dual-core suite pass 4 test firmware, gồm `test_dualcore_peer_snoop`.
- `test_dualcore_peer_snoop` chứng minh `CPU0 dirty write -> CPU1 read same line` với kết quả `aux0=0xfaceb00c`.

Việc còn thiếu cụ thể:
- datapath direct cache-to-cache forwarding đã có ở requester fill path và đã được protocol TB chứng minh

### 2.3 DMA multicore coherency

Đây là phần paper-level tiếp theo sau CPU-CPU coherency.

Trạng thái hiện tại: đã đóng functional proof ở cả protocol TB, standalone ASCON DMA TB, và full SoC dual-core firmware/TB.

Đã làm:
- `tb_dcache_dualcore_protocol.v` dùng nguồn upstream/DMA-style qua cùng snoop arbiter.
- DMA-style coherent read đã lấy được data mới nhất từ cache owner.
- DMA-style coherent invalidate đã buộc dirty writeback và invalidate owner.
- `tb_ascon_dma.v` đã verify standalone coherent DMA primitives ở mức DMA engine / sideband snoop path.
- `test_dualcore_ascon_dma_coherent.c` đã pass qua `tb_soc/tb_soc_dualcore_suite.v`.
- Full ASCON DMA coherent read đã đọc đúng input do CPU giữ dirty trong DCache.
- Full ASCON DMA coherent write đã đi qua case output/tag từng bị cache touch bởi cả hai core.
- `GPIO` và `AUX0` đều báở marker pass `0xac03d003`, nên chưa cần chuyển sang UART cho case này.

Việc còn thiếu cụ thể:
- benchmark contention CPU/DMA để có số liệu paper-level
- thêm bảng snoop-count/cache-miss/throughput cho phần Results
- việc còn thiếu cho paper-level bây giờ là benchmark so sánh direct forwarding với các case fallback/refill dưới contention

### 2.4 `CPU1` control-plane support

Phần này đã khá hơn trước, nhưng vẫn chưa phải SMP/debug đầy đủ.

Đã làm:
- `CPU1` vẫn chạy chung image với `CPU0`
- `CPU1` đã có `mhartid = 1`; `CPU0` có `mhartid = 0`
- `CPU1` đã nhận shared `external_irq`, `timer_irq`, `sw_irq`
- `CPU1` đã nhận shared `jtag_haltreq` và `jtag_resumereq`

Việc còn thiếu/chưa hoàn thiện:
- chưa có interrupt routing riêng theo từng hart
- chưa có debug register/path riêng cho từng hart
- shared debug hiện phù hợp mức stop-the-world cơ bản, chưa phải multi-hart debug hoàn chỉnh

Tài liệu liên quan:
- `gnu_toolchain/tests_dualcore/README.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`

### 2.5 Testbench coverage cho case paper-level

Đã có directed/protocol TB, standalone ASCON DMA TB, firmware suite, và full ASCON DMA SoC proof. Phần còn thiếu chủ yếu là coverage định lượng và contention.

Đã ổn định:
- full ASCON DMA `CPU0 dirty line`, `DMA coherent read`
- full ASCON DMA `DMA coherent write`, kiểm tra visibility/invalidate trên output/tag cache pressure

Thiếu hoặc chưa ổn định các test top-level sau:
- contention giữa CPU và DMA để đo ảnh hưởng throughput

### 2.6 Số liệu benchmark cho paper

Hiện có PASS logs, nhưng chưa có bộ số liệu paper-level đầy đủ cho multicore.

Thiếu các metric:
- throughput khi có contention
- số snoop transaction
- miss rate của từng core
- so sánh coherent path với fallback/software path

## 3. File nàở đang là trọng tâm

- `soc_top.v`
- `interconnect/axi4_crossbar_5m12s.v`
- `cache_interface/dcache/dcache_tag_array.v`
- `cache_interface/dcache/dcache_controller.v`
- `cache_interface/dcache/dcache_top.v`
- `ascon/dma/rtl/ascon_dma.v`
- `ascon/dma/rtl/dma_read_engine.v`
- `ascon/dma/rtl/dma_write_engine.v`
- `ascon/dma/rtl/dma_snoop_arb.v`
- `cache_interface/dcache/dcache_snoop_arb_3to1.v`
- `cache_interface/dcache/dcache_snoop_bus_2way.v`

## 4. Bước tiếp theo đề xuất

1. Chốt `context_id` plumbing cho H3
2. Viết TB/firmware cho 2 context độc lập và đo context-switch overhead
3. Mở `crypto_pending`/queueing cho H1
4. Viết TB H1 cho plaintext -> cache -> ciphertext
5. Bổ sung benchmark paper-ready cho baseline vs H3 vs H1
6. Chỉ cân nhắc UART completion marker nếu GPIO/AUX marker lại không ổn trong các test mới

## 5. Kết luận ngắn

Flow hiện tại đã ổn ở mức:
- unit coherency
- directed protocol
- automatic CPU miss-snoop ở RTL/protocol TB
- automatic CPU miss-snoop ở firmware/top-level suite
- DMA-style snoop protocol ở RTL/protocol TB
- standalone ASCON DMA coherent primitive regression
- full ASCON DMA engine end-to-end coherency ở SoC dual-core
- dual-core liveness

Nhưng để gọi là full paper-level dual-core package thì vẫn còn 2 mảng chính:
- multi-hart interrupt/debug path hoàn chỉnh hơn
- benchmark và số liệu định lượng cho paper

## 7. Phần mới theo hướng H1 + H3

Những mục dưới đây chưa phải là missing items của baseline dual-core, nhưng là phần cần chuẩn bị khi chuyển sang briefing H1+H3:

### 7.1 H3 - Multi-Context ASCON

- chưa có `context_id` plumbing xuyên qua ASCON top, DMA, và firmware
- chưa có `CONTEXT_SEL` / context bank / CRF
- chưa có test dual-core để chứng minh 2 core giữ 2 context độc lập
- chưa có số liệu context-switch latency hoặc throughput theo số context

### 7.2 H1 - Compute-in-Cache

- chưa có `crypto_pending` metadata trong DCache
- chưa có queue/batching cho line crypto
- chưa có in-cache ASCON datapath hoặc micro-architecture prototype
- chưa có benchmark latency/throughput/energy proxy cho compute-in-cache

### 7.3 Cách đọc tài liệu hiện tại

- `paper2_2` vẫn là flow dual-core và ASCON DMA coherency
- `H1+H3.md` là briefing mở rộng sau khi dual-core closure đã ổn
- không nên trộn H1/H3 vào checklist dual-core nếu chưa có prototype hoặc testbench tương ứng
