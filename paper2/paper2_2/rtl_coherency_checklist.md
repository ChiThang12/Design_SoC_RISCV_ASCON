# RTL coherency checklist

Mục tiêu: đi từ chỗ rủi ro cao nhất đến chỗ tích hợp hệ thống, để dual-core + snoop coherency tiến triển theo từng nấc rõ ràng.

Tiến độ hiện tại:
- Da hoan thanh phan DCache coherency core trong P0
- Da bo sung regression TB de giu function cu khong vo
- P0 con lai tap trung vao `soc_top.v` va tich hop da nhan

## P0 - Bắt buộc làm trước

- [x] Chốt kiến trúc top-level trong `soc_top.v`
  - Da them `CPU Core 1`
  - Da them `ICache 1`
  - Da them `DCache 1`
  - Da chen `axi4_master_mux_2m` de gom `ICache0/1` va `DCache0/1` vao fabric 5-master hien tai
  - Da them `dcache_snoop_bus_2way` de DMA snoop/invalidate duoc ca `DCache0` va `DCache1`

- [x] Sửa `cache_interface/dcache/dcache_tag_array.v`
  - Da doi tu `valid/dirty` sang state 2-bit `I/S/E/M`
  - Da giu logic hit/miss tuong thich voi test cu
  - Da them state update cho snoop downgrade/invalidate

- [x] Sửa `cache_interface/dcache/dcache_controller.v`
  - Da them FSM cho snoop read / invalidate / response
  - Da xu ly downgrade `E -> S` khi snoop read
  - Da chan race giua CPU request, flush, va snoop

- [x] Sửa `cache_interface/dcache/dcache_top.v`
  - Da thread toan bo tin hieu coherency qua top
  - Da giu API CPU-facing on dinh

- [x] Bo sung testbench cho DCache
  - Da sua `cache_interface/dcache/tb/tb_dcache.v` de match interface hien tai
  - Da mo rong `cache_interface/dcache/tb/tb_dcache_snoop.v`
  - Da them `cache_interface/dcache/tb/tb_dcache_mesi.v`
  - Regression hien tai:
  - `tb_dcache.v`: `59 PASS / 0 FAIL`
  - `tb_dcache_snoop.v`: `14 PASS / 0 FAIL`
  - `tb_dcache_mesi.v`: `14 PASS / 0 FAIL`

- [x] Chot lai pham vi P0 con lai
  - Da tich hop `CPU1 + ICache1 + DCache1` vao `soc_top.v`
  - Da dinh nghia `snoop bus / coherency controller` 2-way o muc top
  - Da chot cach noi DMA vao 2 DCache thay vi 1 DCache
  - Ghi chu P0: `CPU1` hien chua noi vao debug/interrupt multi-hart; phan nay de lai cho pha sau cua control-plane SMP

## P1 - Ghép đường dữ liệu chính

- [ ] Sửa `ascon/dma/rtl/ascon_dma.v`
  - Nối snoop request/response vào bus mới
  - Đồng bộ `coh_ctrl` với kiến trúc multicore

- [ ] Sửa `ascon/dma/rtl/dma_read_engine.v`
  - Snooping read trước khi fallback AXI
  - Nhận dữ liệu từ cache đang giữ line mới nhất

- [ ] Sửa `ascon/dma/rtl/dma_write_engine.v`
  - Invalidate / downgrade các cache khác trước khi write
  - Giữ mode coherent và non-coherent tách bạch

- [ ] Sửa `ascon/dma/rtl/dma_snoop_arb.v`
  - Arbitrate nhiều snoop target
  - Tổng hợp response theo thứ tự xác định

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
  - Đảm bảo không phá timing của snoop path

- [ ] Rà `dma/dma_ctrl.v` và submodule DMA legacy
  - Chỉ sửa nếu DMA SoC cũ cũng phải tham gia snoop fabric
  - Nếu không, giữ nguyên để tránh mở rộng phạm vi

## P3 - Kiểm thử và tinh chỉnh

- [x] Mở rộng `cache_interface/dcache/tb/tb_dcache_snoop.v`
  - Da test snoop read hit
  - Da test invalidate hit
  - Da test dirty-line response

- [x] Them `cache_interface/dcache/tb/tb_dcache_mesi.v`
  - Da test cac chuyen trang thai `I/E/S/M`
  - Da test clean invalidate va dirty invalidate

- [ ] Cập nhật testbench liên quan tới DMA / cache coherency
  - Da co `tb_soc/tb_soc_dualcore_suite.v` cho cac bai dual-core co ban
  - Da co firmware trong `gnu_toolchain/tests_dualcore/`
  - Da co `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v` cho case `CPU0 write -> CPU1 observe` o muc DCache/snoop bus
  - Case protocol hien tai duoc chung minh theo huong directed snoop-read + invalidate/writeback
  - Duong tu dong `CPU1 miss -> snoop peer cache` ben trong `soc_top` van con la buoc tiep theo
  - Test DMA input coherency
  - Test DMA output w/ cache-hit

- [x] Chạy mô phỏng và ghi log PASS ở mức dual-core
  - Da xong regression DCache don le
  - Da co regression `soc_top` dual-core co ban qua `tb_soc/tb_soc_dualcore_suite.v`
  - Ket qua hien tai:
  - `test_dualcore_basic`: `PASS`
  - `test_dualcore_cache_sweep`: `PASS`
  - `test_dualcore_fence_flush`: `PASS`
  - `tb_dcache_dualcore_protocol.v`: `16 PASS / 0 FAIL`
  - Chua co log cho snoop bus multicore protocol-level voi DMA

## Thứ tự nên làm ngay

1. `soc_top.v`
2. `interconnect/axi4_crossbar_5m12s.v`
3. Tao `snoop_bus` hoac `coherency_controller` moi
4. `ascon/dma/rtl/ascon_dma.v`
5. `ascon/dma/rtl/dma_read_engine.v`
6. `ascon/dma/rtl/dma_write_engine.v`
7. TB dual-core / DMA coherency o muc top

## Van de hien tai can dong

- Chua co duong tu dong `CPU miss -> snoop peer cache owner` trong `soc_top`
- Chua co co che tra line moi nhat tu peer cache ve cho core dang miss o muc top-level
- Chua co bai test top-level chung minh ownership transfer CPU-CPU ma khong can directed external snoop stimulus
- Chua co bai test DMA multicore cho `coherent read` va `coherent write invalidate`
- `CPU1` chua duoc tach rieng `hart_id`, interrupt path, debug path

## Duong hoan thien de dan den dual-core day du

1. Noi xong path `CPU miss -> peer snoop` trong `soc_top` hoac trong coherency controller moi
2. Them top-level TB cho `CPU0 write line`, `CPU1 read same line`, va xac nhan khong can directed snoop tu ben ngoai
3. Them top-level TB cho `CPU0 dirty line`, `DMA coherent read`, va xac nhan DMA lay du lieu moi nhat
4. Them top-level TB cho `DMA coherent write`, va xac nhan invalidate/downgrade dung tren ca `DCache0` va `DCache1`
5. Sau khi on dinh du lieu, moi mo rong `hart_id`, interrupt, debug cho `CPU1`

## Ghi chú

- Nếu MESI trong DCache quá nặng, tạm chuyển sang hướng snoop filter / directory nhỏ bên ngoài.
- Không nên đụng vào các bản copy trong `pd2/` hoặc `cpu/pd/` trước khi xác nhận đó là nhánh đang build.
- O thoi diem hien tai, huong thuc te nhat la giu DCache state machine da on dinh, roi tich hop snoop fabric o top thay vi mo rong them trong tung block nho.
