# RTL coherency checklist

Mục tiêu: giữ baseline dual-core + snoop coherency ổn định, rồi dùng nền đó để chốt H3 trước và H1 sau.

Tiến độ hiện tại:
- Đã hoàn thành phần DCache coherency core trong P0
- Đã bổ sung regression TB để giữ function cũ không vỡ
- Đã đóng full ASCON DMA end-to-end coherency proof ở mức SoC dual-core
- Phan còn lại tap trung vào H3 context plumbing, sau đó mới mở sang H1 compute-in-cache và benchmark paper-ready

## P0 - Bắt buộc làm trước

- [x] Chốt kiến trúc top-level trong `soc_top.v`
  - Đã thêm `CPU Core 1`
  - Đã thêm `ICache 1`
  - Đã thêm `DCache 1`
  - Đã chen `axi4_master_mux_2m` để gom `ICache0/1` và `DCache0/1` vào fabric 5-master hiện tại
  - Đã thêm `dcache_snoop_bus_2way` để DMA snoop/invalidate được cả `DCache0` và `DCache1`

- [x] Sửa `cache_interface/dcache/dcache_tag_array.v`
  - Đã đổi từ `valid/dirty` sang state 2-bit `I/S/E/M`
  - Đã giữ logic hit/miss tương thích với test cũ
  - Đã thêm state update cho snoop downgrade/invalidate

- [x] Sửa `cache_interface/dcache/dcache_controller.v`
  - Đã thêm FSM cho snoop read / invalidate / response
  - Đã xử lý downgrade `E -> S` khi snoop read
  - Đã chặn race giữa CPU request, flush, và snoop

- [x] Sửa `cache_interface/dcache/dcache_top.v`
  - Đã luồng hóa toàn bộ tín hiệu coherency qua top
  - Đã giữ API CPU-facing ổn định

- [x] Bổ sung testbench cho DCache
  - Đã sửa `cache_interface/dcache/tb/tb_dcache.v` để match interface hiện tại
  - Đã mở rộng `cache_interface/dcache/tb/tb_dcache_snoop.v`
  - Đã thêm `cache_interface/dcache/tb/tb_dcache_mesi.v`
  - Regression hiện tại:
  - `tb_dcache.v`: `59 PASS / 0 FAIL`
  - `tb_dcache_snoop.v`: `14 PASS / 0 FAIL`
  - `tb_dcache_mesi.v`: `14 PASS / 0 FAIL`

- [x] Chốt lại pham vi P0 còn lại
  - Đã tích hợp `CPU1 + ICache1 + DCache1` vào `soc_top.v`
  - Đã định nghĩa `snoop bus / coherency controller` 2-way ở mức top
  - Đã chốt cách nối DMA vào 2 DCache thay vì 1 DCache
  - Đã thêm đường `CPU miss -> peer snoop` qua snoop arbiter 3 nguồn
  - Đã thêm `mhartid` riêng cho `CPU0/CPU1`
  - Ghi chú P0: `CPU1` mới có shared IRQ/debug request cơ bản; per-hart debug/interrupt routing để lại cho pha sau của control-plane SMP

## P1 - Ghép đường dữ liệu chính

- [x] Sửa `ascon/dma/rtl/ascon_dma.v`
  - Nối snoop request/response vào bus mới
  - Đồng bộ `coh_ctrl` với kiến trúc multicore
  - Đã verify lại qua `tb_ascon_dma.v` và `test_dualcore_ascon_dma_coherent`

- [x] Sửa `ascon/dma/rtl/dma_read_engine.v`
  - Snooping read trước khi fallback AXI
  - Nhận dữ liệu từ cache đang giữ line mới nhất
  - Full SoC proof đã xác nhận ASCON DMA coherent read thấy dữ liệu input mới nhất từ dirty CPU cache line

- [x] Sửa `ascon/dma/rtl/dma_write_engine.v`
  - Invalidate / downgrade các cache khác trước khi write
  - Giữ mode coherent và non-coherent tách bạch
  - Full SoC proof đã xác nhận output/tag visible đúng sau cache-hit pressure từ cả hai core

- [ ] Sửa `ascon/dma/rtl/dma_snoop_arb.v`
  - Đã sửa arbitration giữa DMA read snoop và write invalidate theo hướng công bằng hơn
  - Đã giữ response collection ổn định sau cập nhật arbiter
  - Đã có top-level SoC proof cho contention CPU/DMA thực tế qua `test_dualcore_contention_forward_dma` và `test_dualcore_contention_fallback_dma`
  - Số liệu chot:
  - `forward-hit + DMA`: `cycles=49957`, `core1 peer_snp_hits=10`, `core1 c2c_fwds=10`
  - `fallback-refill + DMA`: `cycles=81320`, `core1 peer_snp_hits=2`, `core1 c2c_fwds=2`
  - Direct forwarding cho thấy completion time giảm còn `61.4%` so với fallback, tương ứng nhanh hơn khoảng `1.63x`

- [ ] Sửa `interconnect/axi4_crossbar_5m12s.v`
  - Thêm master path cho `Core 1`
  - Kiểm tra decode / arbitration / response routing

## P2 - Mở rộng hệ thống

- [ ] Sửa `interconnect/axi4_master_mux_5m.v`
  - Mở rộng select logic nếu crossbar/sub-fabric còn dùng mux master

- [ ] Sửa `cpu/riscv_cpu_core_v2.v` nếu cần
  - Chỉ thêm port nếu cần core ID, debug riêng, hoặc hook coherency

- [ ] Rà `cpu/core/LSU.v`
  - Kiểm tra fence, MMIO, và non-cacheable behavior
  - Đảm bảở không phá timing của snoop path

- [ ] Rà `dma/dma_ctrl.v` và submodule DMA legacy
  - Chỉ sửa nếu DMA SoC cũ cũng phải tham gia snoop fabric
  - Nếu không, giữ nguyên để tránh mở rộng phạm vi

## P3 - Kiểm thử và tính chỉnh

- [x] Mở rộng `cache_interface/dcache/tb/tb_dcache_snoop.v`
  - Đã test snoop read hit
  - Đã test invalidate hit
  - Đã test dirty-line response

- [x] Thêm `cache_interface/dcache/tb/tb_dcache_mesi.v`
  - Đã test các chuyển trạng thái `I/E/S/M`
  - Đã test clean invalidate và dirty invalidate

- [x] Cập nhật testbench liên quan tới DMA / cache coherency
  - Đã có `tb_soc/tb_soc_dualcore_suite.v` cho các bài dual-core cơ bản
  - Đã có firmware trong `gnu_toolchain/tests_dualcore/`
  - Đã có `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v` cho case `CPU0 write -> CPU1 observe` ở mức DCache/snoop bus
  - Case protocol hiện tại đã chứng minh automatic `CPU1 read miss -> peer snoop -> dirty writeback/invalidate -> refill latest data`
  - Đã có protocol proof cho DMA-style coherent read và DMA-style invalidate qua upstream snoop source
  - Đã có `ascon/dma/tb/tb_ascon_dma.v` pass `66 PASS / 0 FAIL` cho standalone DMA coherent primitive path
  - Đã có firmware `test_dualcore_ascon_dma_coherent.c` pass ở mức SoC dual-core
  - Đã có GPIO/AUX completion hook trong TB
  - Đã đóng stable SoC-level closure cho full ASCON DMA engine input coherency
  - Đã đóng stable SoC-level closure cho full ASCON DMA engine output w/ cache-hit pressure

- [x] Chạy mô phỏng và ghi log PASS ở mức dual-core
  - Đã xong regression DCache đơn lẻ
  - Đã có regression `soc_top` dual-core cơ bản qua `tb_soc/tb_soc_dualcore_suite.v`
  - Kết quả hiện tại:
  - `test_dualcore_basic`: `PASS`
  - `test_dualcore_cache_sweep`: `PASS`
  - `test_dualcore_fence_flush`: `PASS`
  - `test_dualcore_peer_snoop`: `PASS`
  - `test_dualcore_ascon_dma_coherent`: `PASS`
  - `test_dualcore_contention_forward_dma`: `PASS`
  - `test_dualcore_contention_fallback_dma`: `PASS`
  - `tb_dcache_dualcore_protocol.v`: `22 PASS / 0 FAIL`
  - `tb_ascon_dma.v`: `66 PASS / 0 FAIL`
  - Đã có log cho snoop bus multicore protocol-level với DMA-style read/invalidate
  - Đã có log standalone ASCON DMA coherent primitive path
  - Đã có log full ASCON DMA engine end-to-end qua SoC dual-core:
  - `heartbeat=4 shared_count=1 aux0=0xac03d003 gpio=0xac03d003`
  - Đã có bảng contention benchmark paper-ready trong `dualcore_contention_benchmark.md`
  - `forward-hit + DMA`: `49957 cycles`
  - `fallback-refill + DMA`: `81320 cycles`

## P4 - Chốt H3

- [ ] Sửa `ascon/ascon_top.v`
  - Thêm Context Register File (CRF) hoặc context bank nhỏ cho nhiều session ASCON
  - Giữ luồng hiện tại không vỡ trong khi thêm `context_id`

- [ ] Sửa `ascon/interface/rtl/ascon_axi_slave.v`
  - Thêm `CONTEXT_SEL` / register map để CPU chọn context
  - Giữ backward compatibility với firmware dual-core hiện tại

- [ ] Sửa `ascon/dma/rtl/dma_ctrl_fsm.v` và DMA sideband
  - Gắn `context_id` vào flow khởi tạo DMA
  - Bảở đảm context switch 1-cycle ở control plane nếu khả thi

- [ ] Viết TB cho H3
  - Core0 và Core1 dùng 2 context khác nhau
  - Đở throughput và context switch overhead

## P5 - Mở H1

- [ ] Sửa `cache_interface/dcache/dcache_tag_array.v`
  - Thêm bit `crypto_pending` hoặc trạng thái phụ cho line đang chờ xử lý crypto

- [ ] Sửa `cache_interface/dcache/dcache_controller.v`
  - Thêm queue/batching cho line crypto
  - Giữ đường coherency hiện tại không bị phá

- [ ] Sửa `cache_interface/dcache/dcache_top.v`
  - Cắm datapath crypto thử nghiệm vào đường cache line nếu paper H1 thật sự cần

- [ ] Viết TB cho H1
  - CPU ghi plaintext, cache tự xử lý, CPU đọc ciphertext
  - Đở latency/throughput/energy proxy so với baseline DMA

## Thứ tự nên làm ngay

1. Thêm `context_id` plumbing cho H3
2. Viết TB/firmware cho 2 context độc lập và đo context-switch overhead
3. Thu throughput/miss-rate/contend metrics cho baseline vs H3
4. Mở H1 với `crypto_pending` và queue/batching
5. Viết TB H1 cho plaintext -> cache -> ciphertext
6. Chốt bảng số liệu paper-ready cho cả H3 lẫn H1

## Van để hiện tại cần đóng

- Đã có đường tự động `CPU miss -> snoop peer cache owner` trong RTL/protocol path
- Đã có firmware/top-level test ổn định chứng minh ownership transfer CPU-CPU
- Đã có direct cache-to-cache data forwarding cho CPU read miss khi peer snoop hit
- Peer dirty owner vẫn writeback/invalidate để giữ correctness, nhưng requester không cần refill lại từ memory trong case forward-hit
- Đã có DMA-style protocol TB cho `coherent read` và `coherent invalidate`
- Đã có standalone ASCON DMA TB xác nhận coherent primitive read/write snoop path vẫn on sau cập nhật arbiter
- Đã có SoC firmware/TB full ASCON DMA engine end-to-end ở mức stable/pass
- `CPU1` đã có `mhartid` riêng và shared IRQ/debug request, nhưng chưa có per-hart interrupt/debug path đầy đủ

## Duong hoàn thiện để dan đến dual-core đầy đủ

1. Chốt H3 context path và benchmark trước
2. Mở H1 khi baseline H3 đã ổn định
3. Thêm top-level counters cho snoop transaction/cache miss/cache hit nếu cần bảng số liệu đầy đủ
4. Mở rộng per-hart interrupt/debug cho `CPU1` nếu paper cần claim SMP control-plane đầy đủ
5. Tiếp theo nên thu contention benchmark để đo lợi ích của direct cache-to-cache forwarding so với memory-refill fallback
6. Hoàn thiện H3 context benchmark và thêm bảng số liệu so sánh với baseline đã có

## Ghi chú

- Nếu MESI trong DCache quá nặng, tạm chuyển sang hướng snoop filter / directory nhỏ bên ngoài.
- Không nên đụng vào các bản copy trong `pd2/` hoặc `cpu/pd/` trước khi xác nhận đó là nhánh đang build.
- Ở thời điểm hiện tại, hướng thực tế nhất là giữ DCache state machine đã ổn định, rồi tích hợp snoop fabric ở top thay vì mở rộng thêm trong từng block nhỏ.
