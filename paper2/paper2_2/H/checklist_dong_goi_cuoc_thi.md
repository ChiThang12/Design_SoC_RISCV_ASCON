# Checklist Đóng Gói Cuộc Thi

Quy ước trạng thái:

- `[x]`: đã chốt đủ để dùng cho narrative và tổng hợp hiện tại
- `[-]`: đã làm một phần, còn cần khóa thêm trước khi nộp
- `[ ]`: chưa chốt

## 1. Trước khi chốt RTL

- [x] Chốt narrative `H != H3`
  - Đã phản ánh rõ trong `README.md`, `roadmap_trien_khai_H.md`, `kien_truc_dot_pha_H.md`
- [x] Gắn nhãn rõ file nào là reference, file nào là baseline payload, file nào là streaming headline
  - Bộ tài liệu H đã tách rõ `H3 = reference control-plane`, `Dot C cũ = baseline payload`, `H mới = streaming headline`
- [x] Chốt kiến trúc streaming mới
  - Đã khóa hướng `streaming DMA pipeline + ping-pong buffering + direction-aware coherence`
- [x] Chốt register map cuối
  - Đã khóa trong `bang_dang_ky.md` theo đúng các thanh ghi hiện có ở RTL/interface hiện tại
- [-] Chốt path context baseline và streaming headline
  - Narrative đã rõ, nhưng vẫn nên khóa thêm mapping test/firmware theo từng path
- [x] Chốt ping-pong buffering
  - RTL đã có ingress/egress ping-pong cùng bank state/policy riêng
- [x] Chốt direction-aware coherence policy
  - Đã chốt ở mức kiến trúc, planner và write-path helper

Tóm tắt mục 1:

- Đã chốt: `6/7`
- Còn mở: phần context path mới ở mức `một phần`

## 2. Trước khi chốt firmware

- [x] Firmware H3 reference PASS
  - Đã xác nhận lại bằng `test_dualcore_h3_context` và `test_dualcore_h3_benchmark` trong ngày `2026-07-16`
- [x] Firmware baseline payload PASS
  - Đã xác nhận lại bằng `run_soc_fence_128b.v` trong ngày `2026-07-16`
- [x] Firmware streaming headline PASS
  - Đã xác nhận lại bằng `run_output_cachehit.sh 128` ở cả `COH_CTRL=1` và `COH_CTRL=3` trong ngày `2026-07-16`
- [x] Firmware benchmark được tách thành H3 / baseline payload / streaming headline
  - Đã có script gom chuẩn `run_h_firmware_benchmarks.sh` và báo cáo `bao_cao_firmware_H.md`
- [x] Golden data đã khóa
  - Đã khóa trong `golden_data_H.md` theo ba lớp: `H3 reference`, `baseline payload`, `streaming headline`

Tóm tắt mục 2:

- Đã chốt hoàn toàn: `5/5`
- Đã làm một phần: `0/5`
- Mục firmware đã được khóa trọn bộ ở mức package hiện tại

## 3. Trước khi chốt mô phỏng

- [x] Unit test PASS
  - `tb_ascon_dma.v`: giữ `66 PASS / 0 FAIL`
  - `tb_dma_overlap_metrics.v`: đã đo được `peak accepted outstanding AR = 2` và `peak pending BRESP = 2`
- [x] SoC reference test PASS
  - Đã xác nhận lại bằng `run_dualcore_suite.sh` trong ngày `2026-07-16`
  - Cả bốn case `test_dualcore_basic`, `test_dualcore_cache_sweep`, `test_dualcore_fence_flush`, `test_dualcore_peer_snoop` đều `PASS`
- [x] SoC baseline payload test PASS
  - Đã xác nhận lại bằng `run_soc_fence_128b.v` trong ngày `2026-07-16`
- [x] SoC streaming headline test PASS
  - Đã xác nhận lại ở mức SoC bằng `run_output_cachehit.sh 128`
  - `COH_CTRL=1` và `COH_CTRL=3` đều `PASS` trong ngày `2026-07-16`
- [x] Sweep test PASS
  - Đã xác nhận lại bằng `run_paper2_measurements.sh` trong ngày `2026-07-16`
  - Cả ba nhánh `COH_CTRL=0`, `COH_CTRL=3`, `COH_CTRL=1` đều có đủ `128B`, `256B`, `512B`, `1024B`
  - `Output-cache-hit control` cũng đã PASS lại ở cả `COH_CTRL=1` và `COH_CTRL=3`
- [x] Không còn warning nguy hiểm chưa giải thích
  - Đã audit lại các bài build đại diện trong ngày `2026-07-16`
  - `iverilog` cho `tb_ascon_dma.v`, `tb_dma_overlap_metrics.v`, `run_soc_fence_128b.v` không phát sinh warning mới cần giải thích
  - Phần tổng hợp warning đã được cập nhật trong `warning_audit_H.md`

Tóm tắt mục 3:

- Đã chốt: `6/6`
- Đã làm một phần: `0/6`
- Mục mô phỏng đã được khóa trọn bộ ở mức package hiện tại

## 4. Trước khi nộp cuộc thi

- [x] Có README tiếng Việt có dấu
  - `README.md` trong thư mục `H` đã được cập nhật lại
- [x] Có sơ đồ kiến trúc
  - Đã có tài liệu `so_do_kien_truc_H.md` với sơ đồ mermaid đủ dùng cho package hiện tại
- [x] Có bảng benchmark H3 baseline
  - Đã có khung tách lớp benchmark trong tài liệu
- [x] Có bảng benchmark baseline payload
  - Đã có khung benchmark riêng cho baseline payload
- [x] Có bảng benchmark streaming headline
  - Đã có khung benchmark và bằng chứng vi kiến trúc hỗ trợ claim
- [x] Có checklist tái hiện kết quả
  - Đã có `checklist_tai_tao_ket_qua_H.md` theo kiểu `lệnh chạy -> tiêu chí xác nhận -> đối chiếu golden`
- [-] Có kịch bản demo ngắn gọn
  - Hướng demo đã hình thành, nhưng chưa đóng gói thành script/quy trình cuối

Tóm tắt mục 4:

- Đã chốt: `6/7`
- Đã làm một phần: `1/7`
- Còn thiếu rõ nhất: `kịch bản demo ngắn gọn`

## 5. Tổng kết nhanh

- Mạnh nhất hiện tại là: `kiến trúc`, `RTL`, `unit test`, `SoC reference`, `SoC streaming headline`, `sweep hoàn chỉnh`, `README/tài liệu H`
- Còn thiếu nhiều nhất là: `demo package`

Nếu dùng checklist này để điều phối bước tiếp theo, thứ tự nên là:

1. cập nhật lại bảng `golden`/benchmark theo số đo mới
2. hoàn thiện `kịch bản demo`
