# Tổng hợp số liệu benchmark paper2_2

Tài liệu này gồm các số liệu quan trọng đã thu thập trong `paper2_2` để bạn đọc nhanh bằng tiếng Việt.

## Mục tiêu

- Có một file duy nhất chứa số liệu chính
- Dễ dùng cho phần kết quả của paper
- Tách rõ baseline dual-core, ASCON DMA coherency, và contention forward-hit/fallback

## Quy ước đọc số liệu

- `cycles`: số chu kỳ để benchmark hoàn tất hoặc PASS
- `core0_dc_req_count`, `core1_dc_req_count`: số request DCache của từng core
- `peer_snp_hits`: số lần snoop sang peer cache và lấy được dữ liệu hợp lệ
- `c2c_fwds`: số lần direct cache-to-cache forwarding thành công
- `c2c_fill_cycles`: số chu kỳ tiêu tốn cho luồng fill từ peer cache
- `mem_refills`: số lần refill từ memory thấy vì lấy từ peer cache

## 1. Benchmark dual-core cơ bản

### `test_dualcore_basic`

- Kết quả: `PASS`
- `heartbeat=16`
- `shared_count=16`
- `core0_dc_req_count=262`
- `core1_dc_req_count=261`
- `dcache0 writes=131 hits=255`
- `dcache1 writes=131 hits=255`

Ý nghĩa:
- Đây là sanity check cho hoạt động dual-core cơ bản
- Cho thấy cả hai core đều hoạt động ổn định trên shared memory

### `test_dualcore_cache_sweep`

- Kết quả: `PASS`
- `heartbeat=20`
- `shared_count=20`
- `aux0=0x00000000`
- `aux1=0x00000012`
- `core0_dc_req_count=12575`
- `core1_dc_req_count=12574`
- `dcache0 writes=4716 hits=12559`
- `dcache1 writes=4716 hits=12559`

Ý nghĩa:
- Benchmark tải cache lớn hơn để kiểm tra độ ổn định của dual-core path
- Hit count cao, phù hợp để quan sát hành vi cache dưới tải

### `test_dualcore_fence_flush`

- Kết quả: `PASS`
- `heartbeat=20`
- `shared_count=20`
- `aux0=0xff000036`
- `aux1=0xff0000d8`
- `core0_dc_req_count=899`
- `core1_dc_req_count=899`
- `dcache0 writes=347 hits=890`
- `dcache1 writes=347 hits=890`

Ý nghĩa:
- Dùng để kiểm tra hành vi `fence` và làm sạch cache
- Là baseline software-managed coherence

### `test_dualcore_peer_snoop`

- Kết quả: `PASS`
- `heartbeat=2`
- `shared_count=1`
- `aux0=0xfaceb00c`
- `aux1=0x22220001`
- `core0_dc_req_count=15`
- `core1_dc_req_count=16406`
- `dcache0 writes=13 hits=9`
- `dcache1 writes=8204 hits=16398`
- `dcache1 peer_snp_reqs=3`
- `dcache1 peer_snp_hits=3`
- `dcache1 c2c_fwds=3`
- `dcache1 c2c_fill_cycles=12`
- `dcache1 mem_refills=4`

Ý nghĩa:
- Đây là bằng chứng CPU1 read miss có thể snoop sang CPU0
- Dữ liệu được chuyển trực tiếp cache-to-cache thấy vì phải refill từ memory

## 2. Benchmark coherency ở mức protocol và DMA

### `tb_dcache_dualcore_protocol`

- Kết quả: `25 PASS / 0 FAIL`
- Xác nhận chuỗi hành vi:
- CPU0 refill line -> state `E`
- CPU0 write line -> state `M`
- CPU1 read miss -> peer snoop
- CPU0 dirty owner writeback/invalidate
- CPU1 fill trực tiếp từ snoop response
- DMA-style coherent read và invalidate cũng hoạt động

Số liệu quan trọng:
- `stat1_peer_snoop_reqs = 1`
- `stat1_peer_snoop_hits = 1`
- `stat1_c2c_forwards = 1`
- `stat1_mem_refills = 0`

Ý nghĩa:
- Đây là proof ở mức protocol cho direct cache-to-cache forwarding
- Chứng minh flow không chỉ pass ở firmware mà còn đúng ở DCache/snoop bus

### `tb_ascon_dma`

- Kết quả: `66 PASS / 0 FAIL`
- Xác nhận các primitive DMA coherency:
- coherent read snoop hit path
- coherent write invalidate path
- arbitration giữa read snoop và write invalidate vẫn ổn

Ý nghĩa:
- Đây là nền tảng DMA-side trước khi đưa lên SoC dual-core

### `test_dualcore_ascon_dma_coherent`

- Kết quả: `PASS`
- `heartbeat=4`
- `shared_count=1`
- `aux0=0xac03d003`
- `aux1=0x00000000`
- `core0_dc_req_count=12437`
- `core1_dc_req_count=12527`
- `dcache0 writes=4191 hits=12398`
- `dcache1 writes=4183 hits=12522`
- `dcache0 peer_snp_reqs=1`
- `dcache0 mem_refills=11`
- `dcache1 mem_refills=5`

Ý nghĩa:
- Đây là full SoC dual-core proof cho ASCON DMA coherency
- CPU0 giữ plaintext dirty trong cache, DMA vẫn đọc được dữ liệu mới nhất
- Output/tag vùng dữ liệu cũng được kiểm tra lại sau DMA write

## 3. Benchmark contention CPU/DMA

### `test_dualcore_contention_forward_dma`

- Kết quả: `PASS`
- `cycles=49957`
- `heartbeat=3`
- `shared_count=0`
- `core0_dc_req_count=4597`
- `core1_dc_req_count=4728`
- `dcache0 peer_snp_reqs=5`
- `dcache0 mem_refills=59`
- `dcache1 peer_snp_reqs=24`
- `dcache1 peer_snp_hits=10`
- `dcache1 c2c_fwds=10`
- `dcache1 c2c_fill_cycles=40`
- `dcache1 mem_refills=32`

Ý nghĩa:
- Đây là case `forward-hit + DMA`
- CPU1 nhận nhiều peer-snoop hit và có direct forwarding rõ ràng
- Là case chính để đưa vào paper khi muốn chứng minh lợi ích forwarding

### `test_dualcore_contention_fallback_dma`

- Kết quả: `PASS`
- `cycles=81320`
- `heartbeat=2`
- `shared_count=12`
- `core0_dc_req_count=7788`
- `core1_dc_req_count=8101`
- `dcache0 peer_snp_reqs=10`
- `dcache0 mem_refills=82`
- `dcache1 peer_snp_reqs=2`
- `dcache1 peer_snp_hits=2`
- `dcache1 c2c_fwds=2`
- `dcache1 c2c_fill_cycles=8`
- `dcache1 mem_refills=6`

Ý nghĩa:
- Đây là case fallback/reference
- Số forwarded fills giảm mạnh so với case forward
- Thời gian hoàn tất tăng lên đáng kể

### Bảng so sánh contention

| Scenario | Cycles | Core1 Peer Snoop Hits | Core1 C2C Forwards | Core1 C2C Fill Cycles | Core0 Mem Refills | Core1 Mem Refills |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| forward-hit + DMA | 49957 | 10 | 10 | 40 | 59 | 32 |
| fallback-refill + DMA | 81320 | 2 | 2 | 8 | 82 | 6 |

### Kết luận từ contention benchmark

- Direct forwarding nhanh hơn fallback khoảng `1.63x`
- `c2c_fwds` phía consumer tăng từ `2` lên `10`
- Đây là số liệu rất tốt để dùng trong phần kết quả của paper

## 4. Benchmark H3 Multi-Context ASCON

### `test_dualcore_h3_context`

- Kết quả: `PASS`
- `cycles=124220`
- `heartbeat=4`
- `shared_count=2`
- `core0_dc_req_count=13166`
- `core1_dc_req_count=12448`
- `dcache0 peer_snp_hits=2`
- `dcache1 peer_snp_hits=5`
- `dcache0 c2c_fwds=2`
- `dcache1 c2c_fwds=5`

Ý nghĩa:
- Functional proof cho H3: context 0 và context 1 độc lập
- CPU1 switch về context 0 và verify output cũ không bị ghi đè
- Test vẫn chạy trên nền dual-core coherent có peer snoop/C2C forwarding

### `test_dualcore_h3_benchmark`

- Kết quả: `PASS`
- `cycles=7129`
- Active crypto latency: `13 cycles/context`
- Active throughput 8B: `492.31 Mbps @100 MHz`
- H3 MMIO context-switch interval: `36 cycles`
- RTL context select latency: `1 cycle`
- Baseline reload lower-bound: `12 x 36 = 432 cycles`
- Context-switch speedup vs reload proxy: `12.0x`

Ý nghĩa:
- H3 giảm overhead đổi session bằng CRF/context bank
- Thay vì reload tối thiểu 12 register qua MMIO, firmware chỉ ghi `CONTEXT_SEL`
- Không dùng `7129 cycles / 1.80 Mbps` làm throughput chính; đây chỉ là diagnostic end-to-end cho payload rất nhỏ
- Throughput fair của H3 nên tính bằng `DMA fair cycles + context overhead`

### Bảng so sánh H3 với baseline

| Payload | H3 DMA fair | H3 + context select | H3 fair throughput | No-CRF reload lower-bound | No-CRF throughput | H3 speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128B | 92 cycles | 128 cycles | 800.00 Mbps | 524 cycles | 195.42 Mbps | 4.09x |
| 256B | 160 cycles | 196 cycles | 1044.90 Mbps | 592 cycles | 345.95 Mbps | 3.02x |
| 512B | 312 cycles | 348 cycles | 1177.01 Mbps | 744 cycles | 550.54 Mbps | 2.14x |
| 1024B | 584 cycles | 620 cycles | 1321.29 Mbps | 1016 cycles | 806.30 Mbps | 1.64x |

### Bảng phụ: các metric không dùng làm headline

| Metric | Value | Ghi chú |
| --- | ---: | --- |
| H3 functional proof | 124220 cycles | includes dual-core sync + verify |
| H3 diagnostic end-to-end | 7129 cycles / 1.80 Mbps | 2 context x 8B + setup + verify |
| RTL context select | 1 cycle | CRF bank mux |

## 5. Số liệu paper-ready nổi bật nhất

Nếu cần chọn số ít để đưa vào paper, ưu tiên các số này:

- `test_dualcore_peer_snoop`: `peer_snp_hits=3`, `c2c_fwds=3`
- `test_dualcore_ascon_dma_coherent`: `heartbeat=4`, `aux0=0xac03d003`
- `test_dualcore_contention_forward_dma`: `cycles=49957`, `c2c_fwds=10`
- `test_dualcore_contention_fallback_dma`: `cycles=81320`, `c2c_fwds=2`
- `test_dualcore_h3_context`: `cycles=124220`, `shared_count=2`, context isolation PASS
- `test_dualcore_h3_benchmark`: `36-cycle context switch`, fair 128B H3 multi-context `800.00 Mbps`, `4.09x` vs reload lower-bound
- `tb_dcache_dualcore_protocol`: `25 PASS / 0 FAIL`
- `tb_ascon_dma`: `66 PASS / 0 FAIL`

## 6. Tóm tắt ngắn

- Baseline dual-core đã ổn
- DMA coherency end-to-end đã pass
- Direct cache-to-cache forwarding đã có số liệu rõ ràng
- Contention benchmark đã cho thấy forward-hit tốt hơn fallback một cách định lượng
- H3 đã có functional proof và benchmark throughput/context-switch latency

## 7. File liên quan

- [dualcore_test_results.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/dualcore_test_results.md>)
- [dualcore_contention_benchmark.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/dualcore_contention_benchmark.md>)
- [rtl_coherency_checklist.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/rtl_coherency_checklist.md>)
- [H1+H3.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H1+H3.md>)
- [H3/h3_benchmark.md](</home/chithang/Project/Design_SoC_RISCV_ASCON H3/paper2/paper2_2/H3/h3_benchmark.md>)
