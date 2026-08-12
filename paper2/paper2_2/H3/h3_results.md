# H3 Results Reference for DMA-First Comparison

Ngày chạy: 2026-06-29

Scenario: `test_dualcore_h3_context`

## PASS Log

```text
[SIM] Loaded: gnu_toolchain/tests_dualcore/test_dualcore_h3_context.hex  mem[0]=10002117 mem[8]=06c28293 mem[16]=00730e63
[PASS] test_dualcore_h3_context
  cycles=124220
  heartbeat=4 shared_count=2
  aux0=3c0a0000 aux1=00000000
  core0_dc_req_count=13166 core1_dc_req_count=12448
  dcache0 writes=5671 hits=13123
  dcache1 writes=4184 hits=12395
  dcache0 peer_snp_reqs=2 peer_snp_hits=2 c2c_fwds=2 c2c_fill_cycles=8 mem_refills=13
  dcache1 peer_snp_reqs=9 peer_snp_hits=5 c2c_fwds=5 c2c_fill_cycles=20 mem_refills=16
tb_soc/tb_soc_dualcore_suite.v:241: $finish called at 1242205000 (1ps)
```

## Ý nghĩa kết quả

- `heartbeat=4`, `shared_count=2`: CPU0 đã publish context 0, CPU1 đã hoàn tất context 1 và bước verify switch-back về context 0.
- `cycles=124220`: benchmark SoC-level cho luồng H3 dual-core context proof.
- `core0_dc_req_count/core1_dc_req_count`: cả hai core đều có hoạt động DCache thực tế, tránh false-pass một core.
- `peer_snp_hits` và `c2c_fwds` khác 0: test vẫn chạy trên nền dual-core coherent có peer snoop/cache-to-cache forwarding.
- `aux1=00000000`: không dùng làm điều kiện pass. PASS của H3 dựa trên signature, heartbeat, shared_count, DCache counters và nội dung verify trong firmware.

## Cách dùng trong paper mới

- Giữ đây là reference result để so sánh với DMA-first engine.
- Dùng nó để chứng minh control-plane context banking đã hoạt động đúng, nhưng không dùng làm headline throughput.
- Khi viết paper mới, chuyển phần chính sang bulk DMA throughput, burst behavior, và end-to-end secure communication latency.

## Bảng số liệu

| Metric | Value |
| --- | ---: |
| SoC cycles | 124220 |
| Heartbeat | 4 |
| Shared count | 2 |
| CPU0 DCache requests | 13166 |
| CPU1 DCache requests | 12448 |
| DCache0 writes | 5671 |
| DCache1 writes | 4184 |
| DCache0 hits | 13123 |
| DCache1 hits | 12395 |
| DCache0 peer snoop hits | 2 |
| DCache1 peer snoop hits | 5 |
| DCache0 C2C forwards | 2 |
| DCache1 C2C forwards | 5 |

## Kết luận H3

H3 đã đặt mốc functional proof: ASCON register file có thể giữ hai context độc lập, firmware dual-core có thể chọn context bằng `CONTEXT_SEL`, và việc switch giữa context không làm mất output của context cũ. Trong đề tài mới, đây là baseline tham chiếu để so với DMA-first revision.

## Benchmark Throughput / Context Switch

Scenario: `test_dualcore_h3_benchmark`

```text
[PASS] test_dualcore_h3_benchmark
  cycles=7129
  heartbeat=6 shared_count=2
  core0_dc_req_count=286 core1_dc_req_count=9
  dcache0 writes=180 hits=207
  dcache1 writes=7 hits=3
  h3_core_ops=2 avg_active_cycles=13.00 min=13 max=13 avg_active_throughput_mbps=492.31
  h3_context_switches=6 measured_intervals=5 avg_mmio_interval_cycles=36.00 min=36 max=36 rtl_select_latency_cycles=1
```

Bảng benchmark H3 diagnostic:

| Metric | Value | Ghi chú |
| --- | ---: | --- |
| Active crypto latency/context | 13 cycles | `core_start -> core_done` |
| Active throughput/context | 492.31 Mbps | 64 bit / 13 cycles @ 100 MHz |
| H3 MMIO context-switch interval | 36 cycles | back-to-back `CONTEXT_SEL` writes |
| RTL context select latency | 1 cycle | register select update + combinational bank mux |
| End-to-end benchmark cycles | 7129 cycles | diagnostic only: setup, switch loop, 2 core ops, verify |
| End-to-end payload throughput | 1.80 Mbps | diagnostic only; not fair vs DMA bulk throughput |

## Ghi chú cho DMA-first revision

- Các số này mô tả control-plane reference của H3, không phải headline cuối cùng của paper.
- DMA-first revision nên dùng các bảng bulk payload và burst service để chứng minh high-throughput.
- H3 vẫn hữu ích để giữ câu chuyện nhất quán: context switch rẻ hơn reload, nhưng throughput cao thật sự phải đến từ DMA/pipeline.

So sánh fair với baseline/no-CRF:

| Payload | H3 DMA fair | H3 + context select | H3 fair throughput | No-CRF reload lower-bound | No-CRF throughput | H3 speedup |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128B | 92 cycles | 128 cycles | 800.00 Mbps | 524 cycles | 195.42 Mbps | 4.09x |
| 256B | 160 cycles | 196 cycles | 1044.90 Mbps | 592 cycles | 345.95 Mbps | 3.02x |
| 512B | 312 cycles | 348 cycles | 1177.01 Mbps | 744 cycles | 550.54 Mbps | 2.14x |
| 1024B | 584 cycles | 620 cycles | 1321.29 Mbps | 1016 cycles | 806.30 Mbps | 1.64x |

Context-switch control path:

| Metric | No-CRF baseline lower-bound | H3 |
| --- | ---: | ---: |
| Context switch control | `12 x 36 = 432 cycles` | `36 cycles` |
| RTL context select | N/A | `1 cycle` |
| Control overhead reduction | 1.0x | `12.0x` lower |

Ghi chú công bằng:

- H3 bulk throughput dùng cùng selective coherent DMA fair metric `DMA_START -> last M2_B` đã có trong `paper2/03_comparison_results.md`.
- H3 fair per-message cycles = DMA fair cycles + `36 cycles` context select.
- Context reload proxy dùng số MMIO interval đo được trong H3 (`36 cycles/write`) nhân với số register tối thiểu phải reload khi không có CRF: `MODE`, `KEY_0..3`, `NONCE_0..3`, `PTEXT_0..1`, `DATA_LEN` = 12 writes.
- Nếu baseline cần reload thêm AD/tag/decrypt metadata, overhead sẽ lon hơn `432 cycles`; bảng trên là lower-bound cho baseline software reload.
- Không dùng `7129 cycles / 1.80 Mbps` làm throughput headline; đẩy là diagnostic end-to-end proof cho 2 context 8B.
