# Kế hoạch can thiệp các IP để xây dựng SoC-HS (High-Efficiency)

> Mục tiêu: Dựa trên các file lưu trữ trong `plan/archive/`, đây là kế hoạch tổng quan về các thay đổi cần thiết ở các module IP thành phần để biến thiết kế SoC hiện tại thành một **High-Speed/High-Efficiency SoC (soc-hs)**.

## 1. RISC-V CPU Core (`riscv_cpu_core_v2.v`)
Để đạt chuẩn HS (tối ưu Power & Performance), CPU cần được nâng cấp:
- **Hỗ trợ lệnh WFI (Wait For Interrupt):** Nhận định này đúng. Core hiện chưa decode `SYSTEM/WFI`, nên cần thêm `cpu_wfi_o` và cơ chế idle/wake bởi interrupt hoặc debug halt.
- **Branch Predictor:** Nhận định đúng nhưng cần nói chính xác hơn: core hiện đã có dự đoán tĩnh kiểu "backward branch taken". BHT 2-bit 256-entry là nâng cấp hiệu năng, không phải bug fix.
- **Sửa các lỗi logic:** Nhận định đúng. `irq_flush` cần giữ 2 chu kỳ để quét sạch IF/ID và ID/EX, còn `lsu_result_ack` phải được bắt tay theo khả năng nhận của MEM/WB để không đè kết quả ALU/MUL.

## 2. ASCON Accelerator (`ascon_ip_top.v` & submodules)
Biến ASCON thành một Co-processor hoàn toàn độc lập và thông minh:
- **Clock Gating:** Thêm input `clk_en`. Nếu không mã hóa và CPU không cấu hình, ASCON phải được tắt clock hoàn toàn để tiết kiệm động năng (Dynamic Power). Thêm bit `POWER_DOWN` ở CTRL register.
- **Tối ưu DMA Streaming (Pipeline & Burst):** Thay vì xử lý tuần tự (sequential) từng block, DMA FSM cần overlap giữa việc đọc từ RAM (Prefetch RD) và mã hóa ở CORE. Tách Burst Write ctext và tag ra để giảm overhead trên bus AXI.
- **Auto-Increment & Sticky Key:** Thêm `DMA_BLOCK_COUNT` và chức năng tự tăng địa chỉ nguồn/đích. Cung cấp bit `KEY_VALID` để không phải nạp lại key 128-bit liên tục cho nhiều chuỗi dữ liệu.

## 3. Clock & Reset Controller và Always-On (AON) Mini-Domain
Thay vì cung cấp clock liên tục cho mọi thứ, kiến trúc quản lý xung nhịp phải thông minh và an toàn hơn:
- **Dynamic `core_clk_en`:** Gating an toàn dựa trên sự kết hợp của `cpu_wfi_o`, `ascon_o_busy`, AXI activity của M0/M1/M2 và các wake event (`external_irq/timer_irq/sw_irq/debug`). Chỉ gate khi vùng CORE thực sự quiescent (nghỉ ngơi hoàn toàn). Có thêm idle-hold counter để tránh hiện tượng rung clock (clock trashing).
- **Giải pháp Always-On (AON) Mini-Domain (CHƯA LÀM):** Để giải quyết bài toán gate `periph_clk` mà không làm mất khả năng wake-up (đánh thức hệ thống) từ ngoại vi, cần tách cấu trúc xung nhịp ngoại vi thành 2 miền:
  - `clk_always_on` (hoặc `clk_rtc`/`clk_wake`): Luôn luôn chạy. Miền này cấp xung nhịp cho PLIC, logic nhận diện UART RX wake (start-bit edge detector), và bộ đếm Timer/WDT.
  - `periph_clk`: Cấp cho các thanh ghi AXI, DMA Controller, UART TX, GPIO TX... Có thể bị cắt (gate) tối đa để tiết kiệm điện.
  - *Cơ chế Wake-up:* Khi có sự kiện trên miền AON (ví dụ: chân RX kéo xuống 0, Timer tràn, ngắt ngoại vi đến PLIC), một tín hiệu `wake_req` bất đồng bộ sẽ được gửi tới `clk_reset_ctrl` để bật lại `periph_clk` và `core_clk`.

## 4. SoC Top-Level (`soc_top.v`)
- Khởi tạo thêm xung nhịp `clk_always_on` từ `clk_reset_ctrl` và định tuyến (route) chính xác tới PLIC, Timer và khối đánh thức của UART/GPIO.
- Nối dây tín hiệu `wake_req` từ miền AON về lại `clk_reset_ctrl`.
- Đảm bảo định tuyến ngắt (Interrupt Routing) chính xác qua PLIC để khi có dữ liệu UART hoặc ASCON mã hóa xong, nó có thể kích hoạt `wake_req` và đánh thức CPU đang trong trạng thái WFI.

## 5. Tổng kết Workflow thực hiện
1. **P1 - Correctness:** Sửa bug CPU (`irq_flush`, MUL). (ĐÃ SỬA)
2. **P2 - Power (Gating):** Thêm lệnh WFI, thiết kế ICG (Integrated Clock Gating) cho ASCON. (ĐÃ SỬA)
3. **P3 - Thiết kế Always-On Mini-Domain (CẦN LÀM):** Tách `clk_always_on` cho PLIC/Timer/UART RX, xử lý tín hiệu `wake_req` để gate mạnh tay `periph_clk` mà vẫn đảm bảo tính đúng đắn.
4. **P4 - Performance:** Cải tiến DMA của ASCON (Prefetching, Auto-inc), nâng cấp Branch Predictor cho CPU. (CẦN LÀM)
5. **P5 - Verification:** Benchmarking mức tiêu thụ điện năng/throughput và hoàn thiện đóng gói `soc_hs.v` (Pad Ring).
