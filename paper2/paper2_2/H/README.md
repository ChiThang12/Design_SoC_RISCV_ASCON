# H - Đề Tài Dự Thi Thiết Kế Vi Mạch

Thư mục này là bộ tài liệu làm việc cho hướng `H`, tách khỏi narrative paper. Mục tiêu ở đây là phục vụ trực tiếp cho cuộc thi thiết kế vi mạch: rõ phạm vi, rõ đầu việc, rõ test, rõ tiêu chí hoàn thành.

## 1. Mục tiêu của hướng H

H là hướng triển khai tập trung vào hệ thống ASCON trên SoC RISC-V theo kiểu:

- H3 làm reference control-plane
- streaming DMA pipeline làm data-plane đột phá
- direction-aware coherence làm policy hiệu năng mặc định
- DCache coherence fabric dùng snoop sideband giữa DMA và CPU DCache
- firmware là lớp điều khiển và kiểm chứng
- mô phỏng là lớp xác nhận cứng trước khi chốt demo

Mục tiêu thực tế của đề tài dự thi là:

1. Có một RTL chạy được, mô phỏng được, và chứng minh được bằng firmware.
2. Có câu chuyện kiến trúc rõ ràng để trình bày với ban giám khảo.
3. Có benchmark và test case đủ mạnh để chứng minh thiết kế không chỉ “chạy được” mà còn có tính tối ưu.

## 2. Cách đọc bộ tài liệu

- Đọc [Mục tiêu và phạm vi](./muc_tieu_va_pham_vi.md) trước để chốt hướng.
- Đọc [Roadmap triển khai H](./roadmap_trien_khai_H.md) ngay sau đó để tránh hiểu nhầm `H = H3`.
- Đọc [Kiến trúc đột phá H](./kien_truc_dot_pha_H.md) để nắm trục triển khai mới.
- Đọc [H3 reference control-plane](./h3_reference_control_plane.md) để khóa rõ vai trò baseline của H3.
- Đọc [Dot C - baseline payload datapath](./dot_c_dma_payload_path.md) như mốc tham chiếu đã khóa, không phải đích cuối của H.
- Đọc [Kiến trúc đề tài](./kien_truc_de_tai.md) để hiểu dòng dữ liệu.
- Đọc [Bản đồ thanh ghi](./bang_dang_ky.md) để biết firmware phải ghi gì.
- Đọc [Kế hoạch RTL](./ke_hoach_rtl.md) để biết phải sửa file nào trước.
- Đọc [Kế hoạch mô phỏng và firmware](./ke_hoach_mo_phong_va_firmware.md) để biết test nào phải xanh.
- Đọc [Benchmark và tiêu chí chấm](./benchmark_va_tieu_chi.md) để biết số nào sẽ dùng khi báo cáo.
- Đọc [Checklist đóng gói cuộc thi](./checklist_dong_goi_cuoc_thi.md) để chốt deliverable cuối.

## 3. Nguyên tắc triển khai

- Không đồng nhất `H` với `H3`.
- Không lấy H3 làm headline throughput của đề tài.
- Không để narrative cũ kiểu “payload pass là đủ” làm loãng mục tiêu streaming mới.
- Không đẩy claim vượt quá số đo hiện có.
- Không để RTL và firmware lệch nhau.
- Không để test pass giả do dùng nhầm top hoặc nhầm register map.

## 4. Trạng thái mong muốn

Khi hoàn thành, bộ H nên cho ra được:

- một top-level RTL rõ ràng
- một kiến trúc streaming rõ ràng thay vì chỉ phase-based DMA
- một bộ test mô phỏng unit và SoC
- một bộ firmware kiểm chứng được từng đường dữ liệu
- một bảng benchmark đủ để trình bày cho cuộc thi
- một checklist cuối để đóng gói bài dự thi

## 5. Trạng thái RTL hiện tại

Nhánh RTL hiện tại đã đi xa hơn mức "DMA phase-based chạy được".

Các lớp đã được tách tương đối rõ:

- `ping-pong bank state`
- `read/write policy`
- `bank credit planner`
- `scheduler / engine`

Cụ thể ở DMA datapath:

- ingress buffer và egress buffer đã chuyển sang ping-pong bank
- state swap/readiness của bank đã tách ra submodule riêng
- read side có `dma_read_refill_policy` và `dma_read_bank_credit_planner`
- write side có `dma_write_drain_policy` và `dma_write_bank_credit_planner`
- `dma_read_scheduler` và `dma_write_engine` đã bắt đầu dùng target burst theo bank

Cụ thể ở DCache/coherence path:

- SoC đã có `dcache_snoop_arb_3to1` và `dcache_snoop_bus_2way`
- ASCON DMA nối sideband `DC_SNOOP_*` vào DCache fabric
- CPU0/CPU1 DCache có đường sideband snoop và miss-snoop/C2C fill
- DCache tag array theo dõi trạng thái kiểu `I/S/E/M` để phục vụ shared/owned/modified line handling
- Firmware chọn policy bằng `DMA_COH_CTRL`, trong đó `COH_CTRL=1` là mode hiệu năng và `COH_CTRL=3` là fallback coherent mạnh hơn cho output

Điều này rất quan trọng cho narrative của H:

- headline không còn là "payload DMA pass"
- headline là `bank-aware streaming DMA control`
- coherence không còn chỉ là thao tác phần mềm/fence, mà đã có phần cứng snoop-based hỗ trợ trực tiếp
- H3 vẫn chỉ là control-plane baseline

## 6. Trạng thái chứng minh mới nhất

Sau các bước nâng cấp gần đây, H không chỉ có mô tả kiến trúc mà đã có thêm bằng chứng cụ thể từ testbench:

- suite functional chính `tb_ascon_dma.v` vẫn giữ `66 PASS / 0 FAIL`
- suite chuyên dụng `tb_dma_overlap_metrics.v` đã đo được:
  - `peak accepted outstanding AR = 2`
  - `peak pending BRESP = 2`

Ý nghĩa của hai số này:

- read side đã bắt đầu có hành vi multi-outstanding thực sự
- write side đã bắt đầu tách issue khỏi completion tốt hơn
- narrative của H có thể nói về overlap dựa trên số đo, không chỉ dựa trên ý tưởng

## 7. Cách đọc nhanh bộ H sau cập nhật này

Nếu anh muốn đọc nhanh để tổng hợp, thứ tự hợp lý là:

1. [Roadmap triển khai H](./roadmap_trien_khai_H.md)
2. [Kiến trúc đột phá H](./kien_truc_dot_pha_H.md)
3. [Kế hoạch RTL](./ke_hoach_rtl.md)
4. [Benchmark và tiêu chí chấm](./benchmark_va_tieu_chi.md)

Chuỗi này sẽ giúp anh nắm:

- H đang định vị thế nào
- RTL đã tiến đến đâu
- đâu là bằng chứng mới nhất
- các claim nào đã đủ chắc để đưa vào phần tổng hợp
