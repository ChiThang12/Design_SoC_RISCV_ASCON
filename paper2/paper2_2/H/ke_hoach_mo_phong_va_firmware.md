# Kế Hoạch Mô Phỏng Và Firmware

## 1. Mục tiêu

Mục tiêu của phần này là biến RTL thành bằng chứng chạy được trên firmware.

## 2. Phân tầng test

### Tầng unit

- test DMA read/write
- test burst packing
- test error latch
- test buffering handoff

### Tầng reference control-plane

- test H3 context isolation
- test đổi context khi busy
- test switch-back nhiều vòng
- test DMA context latch

### Tầng data-plane benchmark

- test baseline payload 128B, 256B, 512B, 1024B
- test streaming datapath steady-state
- test coherent mode theo source/destination policy
- test output cache-hit behavior

## 3. Firmware cần có

### Firmware reference

- firmware H3 reference
- firmware H3 benchmark

### Firmware headline

- firmware baseline payload
- firmware streaming payload
- firmware direction-aware coherence
- firmware AD trên nền streaming
- firmware benchmark so sánh baseline vs streaming

## 4. Tiêu chí pass

- log phải ra đúng signature
- output phải khớp golden
- cycle count phải ổn định trong phạm vi chấp nhận
- không được pass chỉ nhờ marker giả
- H3 result, baseline payload result, và streaming headline result phải được log thành ba nhóm khác nhau

## 5. Cách kiểm cứng

Kiểm cứng ở đây nên hiểu là:

- RTL đúng logic
- firmware đúng contract
- mô phỏng đúng trạng thái
- log dễ đối chiếu

Ngoài ra, trong nhánh `H` cần kiểm thêm:

- log nào là của H3 reference
- log nào là của baseline payload cũ
- log nào là của streaming headline
- benchmark nào được phép dùng để nói về throughput end-to-end
