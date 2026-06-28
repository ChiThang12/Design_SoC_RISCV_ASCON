# Dual-Core Missing Items

Tài liệu này gom lại các phần còn thiếu trong flow `paper2_2`, dựa trên:
- `paper2/paper2_2/dualcore_test_commands.md`
- `paper2/paper2_2/dualcore_test_results.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`
- `paper2/paper2_2/rtl_coherency_audit.md`
- `gnu_toolchain/tests_dualcore/README.md`

Mục tiêu là phân biệt rõ:
- phần nào đã chứng minh xong
- phần nào mới dừng ở directed TB
- phần nào vẫn chưa có top-level proof

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
- `soc_top.v` đã có đường nối `CPU miss -> peer snoop` cho cả hai DCache thông qua arbiter 3 nguồn.
- Snoop fabric đã được siết lại:
  - top-level arbiter chuyển sang grant công bằng hơn
  - DMA snoop arbiter tránh fixed read-priority kéo dài
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
- chưa có direct cache-to-cache data forwarding; hiện path an toàn là peer dirty writeback/invalidate rồi core miss refill từ memory

### 2.2 Top-level CPU-CPU ownership transfer proof

Trạng thái hiện tại: đã đóng ở cả protocol TB và firmware/top-level suite.

Đã làm:
- `tb_dcache_dualcore_protocol.v` chứng minh ownership transfer ở mức DCache/snoop bus.
- Test này không chỉ còn là responder-only: nó đã có automatic miss-snoop từ `CPU1`.
- SoC dual-core suite pass 4 test firmware, gồm `test_dualcore_peer_snoop`.
- `test_dualcore_peer_snoop` chứng minh `CPU0 dirty write -> CPU1 read same line` với kết quả `aux0=0xfaceb00c`.

Việc còn thiếu cụ thể:
- nếu muốn claim cache-to-cache forwarding, cần thêm datapath forwarding thật; hiện chưa có

### 2.3 DMA multicore coherency

Đây là phần paper-level tiếp theo sau CPU-CPU coherency.

Trạng thái hiện tại: DMA-style protocol đã được chứng minh trong DCache/snoop-bus TB, nhưng full ASCON DMA engine end-to-end vẫn chưa đóng.

Đã làm:
- `tb_dcache_dualcore_protocol.v` dùng nguồn upstream/DMA-style qua cùng snoop arbiter.
- DMA-style coherent read đã lấy được data mới nhất từ cache owner.
- DMA-style coherent invalidate đã buộc dirty writeback và invalidate owner.
- `tb_ascon_dma.v` đã verify standalone coherent DMA primitives ở mức DMA engine / sideband snoop path.

Việc còn thiếu cụ thể:
- chạy full ASCON DMA engine qua SoC path thật, không chỉ stimulus upstream trong DCache TB
- firmware/TB end-to-end cho `CPU dirty line -> ASCON DMA coherent read`
- firmware/TB end-to-end cho `ASCON DMA coherent write -> invalidate/downgrade DCache0/DCache1`
- benchmark contention CPU/DMA để có số liệu paper-level
- Đã thêm scaffold WIP:
  - `gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.c`
  - optional `GPIO` completion check trong `tb_soc/tb_soc_dualcore_suite.v`
  - trạng thái hiện tại: case này vẫn timeout ở SoC-level verify, nên chưa được đưa vào stable suite

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

Đã có directed/protocol TB và firmware suite, nhưng vẫn chưa đủ để claim toàn bộ flow paper-level.

Thiếu hoặc chưa ổn định các test top-level sau:
- full ASCON DMA `CPU0 dirty line`, `DMA coherent read`
- full ASCON DMA `DMA coherent write`, kiểm tra invalidate/downgrade trên cả hai cache
- contention giữa CPU và DMA để đo ảnh hưởng throughput

### 2.6 Số liệu benchmark cho paper

Hiện có PASS logs, nhưng chưa có bộ số liệu paper-level đầy đủ cho multicore.

Thiếu các metric:
- throughput khi có contention
- số snoop transaction
- miss rate của từng core
- so sánh coherent path với fallback/software path

## 3. File nào đang là trọng tâm

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

## 4. Suggested next steps

1. Viết full ASCON DMA TB cho coherent read
2. Viết full ASCON DMA TB cho coherent write/invalidate
3. Thêm scoreboard/counter cho snoop transaction ở top-level
4. Thu thập log, snoop count, miss count, và throughput để đưa vào paper
5. Nếu paper cần hiệu năng cao hơn, cân nhắc direct cache-to-cache forwarding thay vì writeback/refill

## 5. Kết luận ngắn

Flow hiện tại đã ổn ở mức:
- unit coherency
- directed protocol
- automatic CPU miss-snoop ở RTL/protocol TB
- automatic CPU miss-snoop ở firmware/top-level suite
- DMA-style snoop protocol ở RTL/protocol TB
- standalone ASCON DMA coherent primitive regression
- dual-core liveness

Nhưng để gọi là full paper-level dual-core coherency flow thì vẫn còn 3 mảng:
- full ASCON DMA engine end-to-end coherency
- multi-hart interrupt/debug path hoàn chỉnh hơn
- benchmark và số liệu định lượng cho paper
