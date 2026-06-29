# Timeline phát triển kiến trúc — từ Baseline đến H3

Tài liệu này trình bày lộ trình phát triển từ kiến trúc cũ (Paper 2 baseline) đến trạng thái hiện tại (H3 Multi-Context ASCON), để giảng viên hướng dẫn thấy được các bước trung gian và logic chuyển tiếp.

```
2026-05                    2026-06                    2026-07
│                          │                          │
├─ Phase 1 ────────────────┤                          │
│  Baseline single-core    │                          │
│  (software fence)        │                          │
│                          │                          │
├─ Phase 2 ────────────────┤                          │
│  Hardware-coherent DMA   │                          │
│  (sideband snoop + ATU)  │                          │
│                          │                          │
├─ Phase 3 ────────────────┤                          │
│  Dual-core + MESI        │                          │
│  (snoop bus, CPU-CPU     │                          │
│   coherency)             │                          │
│                          │                          │
├─ Phase 4 ────────────────┤                          │
│  ASCON DMA dual-core     │                          │
│  end-to-end coherency    │                          │
│                          │                          │
├─ Phase 5 (NOW) ──────────┤──────────────────────────┤
│  H3: Multi-Context ASCON  │                          │
│  (context_id, CRF,       │                          │
│   dual-core context)      │                          │
│                          │                          │
├─ Phase 6 (NEXT) ─────────┤──────────────────────────┤
│  H1: Compute-in-Cache    │                          │
│  (crypto_pending,        │                          │
│   in-place processing)    │                          │
│                          │                          │
```

---

## Phase 1: Baseline — Single-Core + Software-Managed Coherence

**Mục tiêu:** Thiết lập mốc đo cho kiến trúc cũ.

**Kiến trúc:**
- CPU RISC-V 5-stage + DCache/ICache
- ASCON DMA qua AXI crossbar, không có hardware coherence
- Firmware phải dùng `fence` để flush dirty cache trước khi start DMA

**Số liệu chính (128B, 100 MHz):**
- Throughput: ~1.125 Gbps (91 cycles, software-fenced)
- Core-only peak: ~4.25 Gbps (trần lý thuyết)

**File tham chiếu:** `paper2/01_baseline_old_arch.md`

---

## Phase 2: Hardware-Coherent DMA (Sideband Snoop + ATU)

**Mục tiêu:** Loại bỏ `fence` trong firmware — DMA đọc trực tiếp từ dirty DCache qua sideband snoop.

**Thay đổi kiến trúc:**
- Thêm `dma_atu.v` — Address Translation Unit cho DMA
- Thêm snoop responder trong `dcache_controller.v`
- Thêm `dma_snoop_arb.v` — arbiter giữa DMA read snoop và write invalidate
- Giữ nguyên DCache `valid/dirty` (không nâng lên MESI đầy đủ)

**Phát hiện quan trọng:**
- Full coherent (`COH_CTRL=3`): 171 cycles, 598.83 Mbps — write-invalidate là bottleneck
- Selective coherent (`COH_CTRL=1`): 92 cycles, 1113.04 Mbps — gần baseline, vì bỏ write-invalidate cho output buffer

**Luận điểm paper:** Direction-aware coherence — input cần read snoop, output có thể non-temporal.

**File tham chiếu:** `paper2/02_plan_new_arch.md`, `paper2/03_comparison_results.md`

---

## Phase 3: Dual-Core + MESI Coherency

**Mục tiêu:** Mở rộng lên 2 CPU core với cache coherency đầy đủ qua snoop bus.

**Thay đổi kiến trúc:**
- `soc_top.v` tích hợp CPU Core 1, ICache 1, DCache 1
- DCache nâng cấp từ `valid/dirty` → MESI 2-bit (`I/S/E/M`)
- `dcache_snoop_bus_2way.v` — broadcast snoop request đến cả 2 DCache
- `dcache_snoop_arb_3to1.v` — arbiter cho 2 CPU miss-snoop + 1 DMA upstream
- CPU miss tự động phát peer snoop trước khi refill

**Kết quả:**
- `test_dualcore_basic`, `test_dualcore_cache_sweep`, `test_dualcore_fence_flush`: PASS
- `test_dualcore_peer_snoop`: CPU0 dirty write → CPU1 read → peer snoop hit
- Direct cache-to-cache forwarding: CPU1 nhận data từ CPU0 mà không cần refill memory

---

## Phase 4: ASCON DMA Dual-Core End-to-End

**Mục tiêu:** Chứng minh ASCON DMA hoạt động đúng trên nền dual-coherency.

**Kết quả:**
- `test_dualcore_ascon_dma_coherent`: PASS — heartbeat=4, aux0=0xac03d003
- CPU0 giữ plaintext dirty trong DCache, DMA coherent read lấy đúng data
- Output/tag vùng bị cache-hit từ cả 2 core vẫn được DMA write đúng
- Protocol TB `tb_dcache_dualcore_protocol`: 25 PASS / 0 FAIL
- `tb_ascon_dma`: 66 PASS / 0 FAIL

---

## Phase 5: H3 — Multi-Context ASCON (HIỆN TẠI)

**Mục tiêu:** Cho phép ASCON core lưu nhiều context (key, nonce, state) trong Context Register File (CRF). CPU/DMA chỉ cần gửi `context_id` khi khởi tạo.

**Đang triển khai:**
- Thêm `context_id` plumbing từ ASCON top → DMA → firmware
- Thêm `CONTEXT_SEL` / CRF trong ASCON register map
- Firmware dual-core với 2 context độc lập (CPU0 context A, CPU1 context B)
- Đo context-switch latency và throughput theo số context

**Kế thừa từ Phase 3+4:**
- Dual-core đã ổn định để chia workload theo core
- DMA `coh_ctrl` và sideband path sẵn sàng để thread thêm `context_id`
- Framework firmware/testbench đã có sẵn để đo overhead

**File tham chiếu:** `paper2/paper2_2/H1+H3.md`, `paper2/paper2_2/goal.txt`, `paper2/paper2_2/rtl_coherency_checklist.md`

---

## Phase 6: H1 — Compute-in-Cache (TIẾP THEO)

**Mục tiêu:** Đưa ASCON datapath vào DCache Controller — CPU ghi plaintext, cache tự xử lý, CPU đọc ciphertext.

**Dự kiến:**
- Thêm `crypto_pending` metadata trong DCache tag array
- Queue/batching cho các line crypto
- ASCON datapath nhúng trong cache controller
- Giảm data movement giữa cache và accelerator

**File tham chiếu:** `paper2/paper2_2/H1+H3.md`, `paper2/paper2_2/rtl_coherency_audit.md`

---

## Tổng quan: Câu chuyện kiến trúc xuyên suốt

```
[Phase 1]                         [Phase 2]                         [Phase 3+4]                        [Phase 5+6]
Single-core                       Hardware-Coherent                 Dual-Core                          Multi-Context
Software fence                    DMA (sideband snoop)              MESI + Snoop Bus                   + Compute-in-Cache
│                                 │                                 │                                  │
├─ CPU + DCache                   ├─ + DMA ATU                      ├─ + CPU1, ICache1, DCache1        ├─ + CRF (H3)
├─ ASCON DMA (AXI only)           ├─ + Snoop responder              ├─ + dcache_snoop_bus_2way         ├─ + context_id (H3)
├─ fence before DMA               ├─ + dma_snoop_arb                ├─ + dcache_snoop_arb_3to1         ├─ + crypto_pending (H1)
└─ 91 cycles / 1.125 Gbps        ├─ Full: 171 cyc / 599 Mbps       ├─ + MESI state (I/S/E/M)          └─ + in-cache datapath (H1)
                                  └─ Selective: 92 cyc / 1.113 Gbps ├─ + CPU miss → peer snoop
                                                                    └─ + DMA dual-core end-to-end
```

**Khoảng hở cần giải thích với giảng viên:**

Giảng viên có thể thấy từ Phase 1 (baseline cũ, software fence) nhảy thẳng đến H3 là một bước xa. Thực tế có 3 phase trung gian:

1. **Phase 2** giải quyết vấn đề DMA-cache coherence trên single-core — đây là phần lõi "selective coherent DMA" làm luận điểm chính cho Paper 2.
2. **Phase 3** mở rộng lên dual-core với MESI và snoop bus — đây là hạ tầng để H3 có thể chạy 2 context trên 2 core riêng biệt.
3. **Phase 4** chứng minh ASCON DMA end-to-end trên nền dual-core — đảm bảo H3 kế thừa được toàn bộ coherency đã kiểm chứng.

H3 không phải là một bước nhảy từ baseline cũ, mà là đỉnh của một chuỗi mở rộng có hệ thống: single-core coherent → dual-core coherent → multi-context.
