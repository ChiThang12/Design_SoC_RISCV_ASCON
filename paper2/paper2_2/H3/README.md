# H3 - Multi-Context ASCON

Thư mục này gồm nội dung triển khai, dữ liệu test và benchmark cho H3.

## Mục tiêu

H3 thêm khả năng lưu nhiều ASCON context trong register file của accelerator. Firmware chọn context bằng `CONTEXT_SEL`, sau đó cấu hình key, nonce, plaintext và start core như luồng cũ. Mục tiêu là chứng minh:

- Context 0 và context 1 độc lập về key, nonce, plaintext, ciphertext và tag.
- Dual-core có thể chia workload theo context: CPU0 dùng context 0, CPU1 dùng context 1.
- Sau khi CPU1 chạy context 1, firmware switch về context 0 và đọc lại output cũ, xác nhận context 0 không bị ghi đè.
- H3 kế thừa nên dual-core MESI/coherent DMA đã có từ Phase 3 và Phase 4.

## RTL đã thêm

- `ascon/interface/ascon_axi_slave.v`
  - Thêm register `CONTEXT_SEL` tại offset `0x008`.
  - Thêm hai bank context cho các thanh ghi core-facing: mode, data length, key, nonce, plaintext, ciphertext, tag, AD metadata.
  - Read/write register map đi qua bank đang được chọn bởi `CONTEXT_SEL`.
  - Latch `active_context` tại lúc start để input/output core không bị đổi bank nếu firmware đổi `CONTEXT_SEL` khi core/DMA đang busy.
  - Xuất `context_id_o` cho đường DMA/top-level.

- `ascon/ascon_top.v`
  - Nối `slave_context_id` từ AXI slave sang DMA.

- `ascon/dma/ascon_dma.v`
  - Thêm input `context_id` và output debug `context_id_active`.

- `ascon/dma/rtl/ascon_dma.v`
  - Đồng bộ interface với bản DMA wrapper.

- `ascon/dma/rtl/dma_ctrl_fsm.v`
  - Latch `context_id_active` khi `dma_start`.

## Firmware/test đã thêm

- `gnu_toolchain/include/ascon.h`
  - Thêm `ASCON_OFS_CONTEXT_SEL = 0x008`.
  - Thêm helper `ascon_select_context(context_id)`.

- `gnu_toolchain/tests_dualcore/test_dualcore_h3_context.c`
  - CPU0 cấu hình và chạy context 0.
  - CPU0 lưu snapshot ciphertext/tag của context 0 vào DMEM.
  - CPU1 cấu hình và chạy context 1.
  - CPU1 kiểm tra output context 1 khác context 0.
  - CPU1 switch lại context 0 và kiểm tra output context 0 vẫn giữ nguyên.

## Kết quả hiện tại

`test_dualcore_h3_context` đã PASS trên SoC dual-core:

- `cycles = 124220`
- `heartbeat = 4`
- `shared_count = 2`
- `core0_dc_req_count = 13166`
- `core1_dc_req_count = 12448`
- `dcache0 peer_snp_hits = 2`
- `dcache1 peer_snp_hits = 5`
- `dcache0 c2c_fwds = 2`
- `dcache1 c2c_fwds = 5`

Chi tiết command và log nằm trong:

- `h3_test_commands.md`
- `h3_results.md`
- `h3_benchmark.md`
- `h3_closure_checklist.md`

## Benchmark H3 bổ sung

`test_dualcore_h3_benchmark` đo riêng active crypto window và context-switch overhead:

- Active crypto latency: `13 cycles/context`
- Active throughput, 8B context: `492.31 Mbps @100 MHz`
- Firmware MMIO context-switch interval: `36 cycles`
- RTL context select latency: `1 cycle`
- Baseline software reload proxy: `12 MMIO writes x 36 cycles = 432 cycles`
- Context-switch speedup vs reload proxy: `12.0x`

Bảng fair cho multi-context payload nên dùng `DMA fair cycles + context overhead`, không dùng end-to-end diagnostic 8B:

| Payload | H3 + context select | No-CRF reload lower-bound | H3 speedup |
| ---: | ---: | ---: | ---: |
| 128B | 128 cycles / 800.00 Mbps | 524 cycles / 195.42 Mbps | 4.09x |
| 256B | 196 cycles / 1044.90 Mbps | 592 cycles / 345.95 Mbps | 3.02x |
| 512B | 348 cycles / 1177.01 Mbps | 744 cycles / 550.54 Mbps | 2.14x |
| 1024B | 620 cycles / 1321.29 Mbps | 1016 cycles / 806.30 Mbps | 1.64x |
