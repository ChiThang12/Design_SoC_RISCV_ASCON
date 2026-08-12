# H3 Closure Checklist

Ngày cập nhật: 2026-06-29

## Trạng thái tổng quan

H3 hiện là reference design cho phần ASCON của đề tài. Nó đủ để chốt phase nếu mục tiêu là:

- có một mốc so sánh rõ cho kiến trúc DMA-first mới
- thêm `CONTEXT_SEL`/CRF 2 context vào ASCON register file
- chứng minh 2 context độc lập trên dual-core firmware
- đo context-switch latency
- báo cáo benchmark fair theo `DMA fair cycles + context overhead`

## Đã hoàn thành

| Hạng mục | Trạng thái | Bằng chứng |
| --- | --- | --- |
| `CONTEXT_SEL` register | Done | `ASCON_OFS_CONTEXT_SEL = 0x008` |
| 2 context banks | Done | mode, key, nonce, ptext, ctext, tag, AD metadata được bank |
| Active-context latch | Done | latch context tại `core_start`/`dma_start` để tránh đổi bank khi busy |
| Firmware helper | Done | `ascon_select_context(context_id)` |
| Functional dual-core test | PASS | `test_dualcore_h3_context` |
| Context-switch benchmark | PASS | `test_dualcore_h3_benchmark` |
| Fair comparison table | Done | `h3_benchmark.md`, `h3_fair_comparison.csv` |
| H3 documentation | Done | README, register map, results, benchmark, commands |

## Kết quả nên đưa vào paper như reference

| Metric | Value | Ghi chú |
| --- | ---: | --- |
| Functional proof | PASS | 2 context độc lập, switch-back verify |
| H3 MMIO context switch | 36 cycles | firmware-visible `CONTEXT_SEL` interval |
| RTL context select | 1 cycle | CRF bank select |
| Reload lower-bound không có CRF | 432 cycles | 12 MMIO writes x 36 cycles |
| H3 128B fair multi-context | 128 cycles / 800.00 Mbps | DMA fair 92 + context 36 |
| No-CRF 128B lower-bound | 524 cycles / 195.42 Mbps | DMA fair 92 + reload 432 |
| H3 speedup vs reload, 128B | 4.09x | multi-context control-overhead benefit |

## Ý nghĩa trong paper mới

- H3 không còn là headline chính.
- H3 là reference để chứng minh DMA-first revision thật sự cải thiện end-to-end throughput chứ không chỉ đổi câu chữ.
- Nếu reviewer hỏi vì sao còn giữ H3, câu trả lời là: H3 cho thấy control-plane multi-context là có ích, nhưng paper mới tập trung vào data-plane DMA/pipeline để đẩy throughput cao hơn.

## Điểm cần nói rõ để tránh bị bắt bẻ

1. H3 không làm ASCON datapath nhanh hơn.

H3 giảm chi phí đổi context/session. Raw bulk DMA throughput vẫn kế thừa selective coherent DMA (`COH_CTRL=1`).

2. `test_dualcore_h3_context` không phải throughput benchmark.

Test này gom boot, dual-core sync, verify và cache traffic. Dùng nó làm functional proof, không dùng `cycles=124220` làm throughput headline.

3. `test_dualcore_h3_benchmark` có metric diagnostic.

`7129 cycles / 1.80 Mbps` chỉ là diagnostic end-to-end cho 2 context 8B. Headline fair là bảng `DMA fair cycles + context overhead`.

4. `context_id` trong DMA hiện tại là sideband/debug latch.

DMA đã nhận và latch `context_id_active`, nhưng H3 chưa có hardware scheduler/queue để chạy nhiều DMA context song song. Nếu reviewer hỏi, câu trả lời dùng là: H3 này là CRF/context-bank support, không phải multi-tenant DMA scheduler.

5. Baseline reload là lower-bound.

`432 cycles` tính từ 12 MMIO writes tối thiểu. Nếu decrypt/AD/tag hoặc state lớn hơn, baseline reload sẽ còn đắt hơn.

## Nên làm thêm nếu còn thời gian

| Ưu tiên | Hạng mục | Lý do |
| ---: | --- | --- |
| P1 | Thêm benchmark DMA burst/pipeline | Chứng minh throughput cao là do data path, không phải chỉ control path |
| P1 | Thêm waveform/log cho `reg_context_active` | Giữ H3 reference sạch và dễ kiểm chứng |
| P2 | Chạy lại `run_coherent_sweep.sh` và lưu log vào H3 | Làm bảng tham chiếu cho DMA-first comparison |
| P2 | Thêm H3 DMA-context smoke test | Chứng minh `context_id_active` latched khi DMA start |
| P3 | Mở rộng lên 4 context | Nếu cần claim "multi-context" mạnh hơn 2-bank prototype |
| P3 | Hardware queue/scheduler cho DMA context | Nếu muốn claim multi-tenant DMA thật sự |

## Kết luận

H3 hiện tại có thể đóng gói là:

> A two-context ASCON Context Register File with firmware-visible `CONTEXT_SEL`, verified on a dual-core coherent SoC. It preserves per-context state across switches and reduces context-switch control overhead from a no-CRF reload lower-bound of 432 cycles to a 36-cycle MMIO context select, with a 1-cycle RTL bank-select latency. In the DMA-first paper story, this design is the reference point, not the headline.
