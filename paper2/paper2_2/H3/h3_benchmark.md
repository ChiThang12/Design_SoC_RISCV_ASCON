# Benchmark Throughput và Context-Switch H3

Ngày chạy: 2026-06-29

## Mục tiêu

Functional proof `test_dualcore_h3_context` chứng minh isolation, nhưng không nên dùng trực tiếp để tính throughput vì nó gom boot, sync dual-core và verify. Benchmark này tách riêng:

- Active crypto latency: `core_start -> core_done`
- Context-switch latency: các lần ghi `CONTEXT_SEL` liên tiếp
- End-to-end cycles: setup + switch loop + 2 context operations + verify

Quan trọng: H3 là có che multi-context/CRF, không phải một datapath ASCON mới. Vi vay benchmark công bằng phải so:

- Bulk payload throughput bảng cùng DMA fair metric `DMA_START -> last M2_B`.
- Context switch overhead riêng: H3 `CONTEXT_SEL` vs baseline/no-CRF reload key/nonce/state qua MMIO.
- Functional proof/end-to-end 2-context chỉ dùng để chứng minh isolation, không dùng làm throughput chính.

## Lệnh chạy

Xem `h3_test_commands.md`, phần `H3 Throughput / Context-Switch Benchmark`.

## Log thô

```text
[SIM] Loaded: gnu_toolchain/tests_dualcore/test_dualcore_h3_benchmark.hex  mem[0]=10002117 mem[8]=06c28293 mem[16]=00730e63
[H3-BENCH] context_switch idx=1 cycle=4602 context=1 interval_cycles=N/A stage=0
[H3-BENCH] context_switch idx=2 window_idx=1 cycle=5074 context=0 interval_cycles=N/A
[H3-BENCH] context_switch idx=3 window_idx=2 cycle=5110 context=1 interval_cycles=36
[H3-BENCH] context_switch idx=4 window_idx=3 cycle=5146 context=0 interval_cycles=36
[H3-BENCH] context_switch idx=5 window_idx=4 cycle=5182 context=1 interval_cycles=36
[H3-BENCH] context_switch idx=6 window_idx=5 cycle=5218 context=0 interval_cycles=36
[H3-BENCH] context_switch idx=7 window_idx=6 cycle=5254 context=1 interval_cycles=36
[H3-BENCH] context_switch idx=8 cycle=5358 context=0 interval_cycles=N/A stage=19
[H3-BENCH] core_start cycle=5433 context=0
[H3-BENCH] core_done op=1 cycle=5446 context=0 active_cycles=13 throughput_mbps=492.31
[H3-BENCH] context_switch idx=9 cycle=6125 context=1 interval_cycles=N/A stage=21
[H3-BENCH] core_start cycle=6164 context=1
[H3-BENCH] core_done op=2 cycle=6177 context=1 active_cycles=13 throughput_mbps=492.31
[H3-BENCH] context_switch idx=10 cycle=6723 context=0 interval_cycles=N/A stage=31
[PASS] test_dualcore_h3_benchmark
  cycles=7129
  heartbeat=6 shared_count=2
  aux0=00000000 aux1=00000000
  core0_dc_req_count=286 core1_dc_req_count=9
  dcache0 writes=180 hits=207
  dcache1 writes=7 hits=3
  dcache0 peer_snp_reqs=2 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=16
  dcache1 peer_snp_reqs=1 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=6
  h3_core_ops=2 avg_active_cycles=13.00 min=13 max=13 avg_active_throughput_mbps=492.31
  h3_context_switches=6 measured_intervals=5 avg_mmio_interval_cycles=36.00 min=36 max=36 rtl_select_latency_cycles=1
```

## Tính toán

Clock: `100 MHz`

Active throughput for one 8B context:

```text
payload_bits = 64
active_cycles = 13
throughput = 64 bits / 13 cycles * 100 MHz
           = 492.31 Mbps
```

End-to-end payload throughput for two 8B contexts:

```text
payload_bits = 2 * 64 = 128
cycles = 7129
throughput = 128 bits / 7129 cycles * 100 MHz
           = 1.80 Mbps
```

Context-switch control overhead:

```text
H3 MMIO context switch = 36 cycles
RTL bank select latency = 1 cycle

baseline reload lower-bound = 12 MMIO writes * 36 cycles/write
                            = 432 cycles

speedup = 432 / 36 = 12.0x
```

Lower-bound `12 MMIO writes` chỉ gồm state context tối thiểu cho benchmark này:

- `MODE`
- `KEY_0..KEY_3`
- `NONCE_0..NONCE_3`
- `PTEXT_0..PTEXT_1`
- `DATA_LEN`

## Phương pháp so sánh công bằng

H3 bulk datapath dùng lại selective coherent DMA (`COH_CTRL=1`), nên fair payload cycles lay từ sweep đã có:

| Payload | Selective coherent DMA fair cycles | Throughput |
| ---: | ---: | ---: |
| 128B | 92 | 1113.04 Mbps |
| 256B | 160 | 1280.00 Mbps |
| 512B | 312 | 1312.82 Mbps |
| 1024B | 584 | 1402.74 Mbps |

Sau đó cộng context overhead:

```text
H3 per-message cycles       = DMA fair cycles + 36
no-CRF reload lower-bound   = DMA fair cycles + 432
```

Trong đó:

- `36 cycles`: firmware-visible H3 `CONTEXT_SEL` interval đo được bằng `test_dualcore_h3_benchmark`.
- `432 cycles`: lower-bound no-CRF reload = 12 MMIO writes x 36 cycles/write.

## Bảng H3 công bằng

| Payload | H3 DMA fair | H3 + context select | H3 fair throughput | No-CRF reload lower-bound | No-CRF throughput | H3 speedup vs reload |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128B | 92 cycles | 128 cycles | 800.00 Mbps | 524 cycles | 195.42 Mbps | 4.09x |
| 256B | 160 cycles | 196 cycles | 1044.90 Mbps | 592 cycles | 345.95 Mbps | 3.02x |
| 512B | 312 cycles | 348 cycles | 1177.01 Mbps | 744 cycles | 550.54 Mbps | 2.14x |
| 1024B | 584 cycles | 620 cycles | 1321.29 Mbps | 1016 cycles | 806.30 Mbps | 1.64x |

## Metric chỉ dùng tham khảo

| Metric | Value | Lý do không dùng làm so sánh chính |
| --- | ---: | --- |
| `test_dualcore_h3_context` | 124220 cycles | boot + dual-core sync + isolation verify |
| `test_dualcore_h3_benchmark` end-to-end | 7129 cycles / 1.80 Mbps | 2 tiny 8B contexts + setup + verify |
| H3 CPU-direct active 8B | 13 cycles / 492.31 Mbps | sanity for core active window, not DMA fair metric |

## Diễn giải

- Lợi ích chính của H3 là tránh reload toàn bộ context qua MMIO khi đổi session.
- Headline công bằng nên là bảng `H3 + context select`, không phải diagnostic end-to-end 8B rất nhỏ.
- H3 không vượt baseline DMA single-context về raw bulk throughput; H3 làm workload multi-session rẻ hơn bằng cách thay reload bằng `CONTEXT_SEL`.
- Switch interval firmware thấy được là `36 cycles`, còn hardware bank select là `1 cycle`.
- Không có CRF, ngay cả đường reload tối thiểu cũng cần ít nhất `12` MMIO writes, nên chi phí software reload lower-bound khoảng `432 cycles`.

## Claim sẵn sàng cho paper

Với workload ASCON multi-context, H3 giảm overhead điều khiển context switch từ lower-bound reload `432 cycles` xuống một lần ghi `CONTEXT_SEL` `36 cycles`. Khi kết hợp với cùng cửa sổ selective coherent DMA fair, H3 cải thiện throughput multi-context theo từng message `4.09x` ở 128B và vẫn nhanh hơn trên sweep 128B-1024B.

