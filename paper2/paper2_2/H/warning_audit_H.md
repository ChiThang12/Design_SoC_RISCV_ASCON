# Warning Audit H

## Phạm vi audit

- `paper2/paper2_2/H/*`
- các file benchmark và checklist liên quan trực tiếp đến package cuộc thi

## Kết quả

- Không thấy warning compile mới cần giải thích ở các bài đại diện đã audit ngày `2026-07-16`.
- Các lệnh kiểm tra sạch warning:
  - `iverilog -g2012 -I. -o /tmp/warn_tb_ascon_dma.out ascon/dma/tb/tb_ascon_dma.v`
  - `iverilog -g2012 -I. -o /tmp/warn_tb_overlap.out ascon/dma/tb/tb_dma_overlap_metrics.v`
  - `iverilog -g2012 -I. -o /tmp/warn_soc_fence_128b.out run_soc_fence_128b.v`
- `run_output_cachehit.sh 128` ở `COH_CTRL=1` và `COH_CTRL=3` đều `PASS`, không xuất hiện warning runtime mới trong log.
- Các chuỗi chứa từ `warning` trong repo chủ yếu là comment mô tả, không phải lỗi mở.
- Các mốc PASS/FAIL quan trọng đã được tách thành H3 / baseline payload / streaming headline.

## Ghi chú

- Đây là audit phục vụ đóng gói tài liệu.
- Điểm còn mở của mục mô phỏng hiện tại là `sweep` dài `COH_CTRL=1` ở mức SoC, nhưng đây là hạng mục xác nhận hiệu năng/chạy lâu, không phải warning compile chưa giải thích.
- Nếu sau này RTL đổi, cần audit lại cùng bộ test tương ứng.
