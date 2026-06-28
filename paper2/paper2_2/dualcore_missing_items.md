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
- Directed protocol TB `tb_dcache_dualcore_protocol.v` đã chứng minh:
  - `CPU0` refill vào `E`
  - `CPU0` write lên `M`
  - snoop-read lấy được line mới nhất
  - invalidate buộc dirty writeback
  - `CPU1` refills sau đó thấy data mới nhất

## 2. Những thứ còn thiếu theo ưu tiên

### 2.1 Automatic `CPU miss -> peer snoop` ở top-level

Đây là lỗ hổng quan trọng nhất hiện tại.

Hiện trạng:
- `soc_top.v` chưa có path tự động để CPU miss kích hoạt snoop sang cache peer.
- Luồng hiện có vẫn dựa vào directed protocol TB để chứng minh responder side.

Tài liệu liên quan:
- `paper2/paper2_2/dualcore_test_commands.md`
- `paper2/paper2_2/dualcore_test_results.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`
- `paper2/paper2_2/rtl_coherency_audit.md`

Việc còn thiếu cụ thể:
- `CPU1 miss` tự động tìm owner của line ở cache peer
- trả line mới nhất về core đang miss
- chuyển ownership mà không cần stimulus snoop bên ngoài

### 2.2 Top-level CPU-CPU ownership transfer proof

Hiện tại đã có proof ở mức DCache/snoop bus, nhưng chưa có proof top-level end-to-end.

Hiện trạng:
- Directed TB chứng minh responder path
- SoC dual-core suite mới chứng minh execution + shared memory + fence/writeback visibility

Việc còn thiếu cụ thể:
- test top-level kiểu `CPU0 write line`
- `CPU1 read same line`
- xác nhận line được lấy từ peer cache chứ không chỉ từ directed external snoop

### 2.3 DMA multicore coherency

Đây là phần paper-level tiếp theo sau CPU-CPU coherency.

Hiện trạng:
- Tài liệu đã nói rõ DMA multicore vẫn là bước sau
- Chưa có log/proof cho snoop correctness của DMA trên cả 2 DCache

Việc còn thiếu cụ thể:
- coherent DMA read lấy data mới nhất từ cache owner
- coherent DMA write invalidate/downgrade cả `DCache0` và `DCache1`
- thứ tự response phải deterministic

### 2.4 `CPU1` control-plane support

Phần này chưa phải blocker cho P0, nhưng là thiếu nếu muốn SMP đầy đủ hơn.

Hiện trạng:
- `CPU1` vẫn chạy chung image với `CPU0`
- chưa có `hart_id` riêng
- chưa có interrupt routing riêng
- chưa có debug path riêng

Tài liệu liên quan:
- `gnu_toolchain/tests_dualcore/README.md`
- `paper2/paper2_2/rtl_coherency_checklist.md`

### 2.5 Testbench coverage cho case paper-level

Đã có directed TB và firmware suite, nhưng chưa đủ để claim flow hoàn chỉnh.

Thiếu các test top-level sau:
- `CPU0 write line`, `CPU1 read same line`
- `CPU0 dirty line`, `DMA coherent read`
- `DMA coherent write`, kiểm tra invalidate/downgrade trên cả hai cache
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

## 4. Suggested next steps

1. Khóa path `CPU miss -> peer snoop` trong `soc_top.v`
2. Viết top-level TB cho `CPU0 write -> CPU1 read`
3. Viết top-level TB cho `DMA coherent read`
4. Viết top-level TB cho `DMA coherent write`
5. Thu thập log và số liệu để đưa vào paper

## 5. Kết luận ngắn

Flow hiện tại đã ổn ở mức:
- unit coherency
- directed protocol
- dual-core liveness

Nhưng để gọi là full dual-core coherency flow thì vẫn còn 3 mảng lớn:
- automatic CPU-CPU transfer ở top-level
- DMA multicore coherency
- control-plane / benchmark hoàn chỉnh cho paper
