# Mục Tiêu Và Phạm Vi

## 1. Mục tiêu chính

Đề tài H hướng tới một SoC RISC-V có khối ASCON tăng tốc theo hướng streaming DMA pipeline, trong đó:

- H3 chỉ giữ vai trò reference control-plane
- datapath headline phải tiến từ DMA-first sang streaming overlap
- direction-aware coherence là policy mặc định của datapath mới
- firmware điều khiển việc start, chọn context, và kiểm tra kết quả
- mô phỏng xác nhận đúng chức năng và đo hiệu năng

Điều cần chốt rõ:

- `H` là nhánh triển khai streaming coherent accelerator datapath
- `H3` là baseline tham chiếu cho control-plane
- speedup headline của `H` phải đến từ overlap read/process/write và coherence theo hướng dữ liệu, không phải từ context banking

## 2. Mục tiêu phụ

- Chứng minh dữ liệu có thể đi qua pipeline từ memory đến ASCON và quay về memory theo kiểu streaming.
- Chứng minh thay đổi context không làm mất state cũ.
- Chứng minh cơ chế coherent DMA hoạt động đúng theo policy chọn cho từng hướng dữ liệu.
- Chứng minh thiết kế có thể demo được trong bối cảnh cuộc thi.

## 3. Phạm vi nên làm

### Phần reference baseline

- 2 context bank cho H3
- `CONTEXT_SEL`
- `context_id_active`
- benchmark context-switch/control-plane

### Phần headline implementation

- streaming DMA pipeline
- ping-pong ingress/egress buffering
- direction-aware coherence
- AD path sau khi streaming payload ổn định
- benchmark baseline payload vs streaming headline

## 4. Không nên mở rộng quá sớm

- Không cần multi-queue scheduler nếu chưa có nhu cầu rõ.
- Không cần 4 context nếu 2 context đã đủ cho câu chuyện.
- Không cần full descriptor queue ngay từ vòng đầu.
- Không cần thêm quá nhiều mode khiến firmware khó kiểm thử.

## 5. Tiêu chí chấp nhận

Đề tài được coi là đi đúng hướng khi:

- firmware chạy được trên mô phỏng
- RTL không deadlock
- output đúng với golden data
- benchmark có số liệu rõ ràng
- H3 metric được tách riêng khỏi baseline payload và streaming headline
- câu chuyện kiến trúc thể hiện rõ `control-plane baseline` khác `streaming data-plane headline`
