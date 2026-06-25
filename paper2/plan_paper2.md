# IMPLEMENTATION PLAN: Hardware-Coherent DMA with Snoop + ATU (Sideband Approach)

Tài liệu này là bản đặc tả kỹ thuật chi tiết (Specification & Action Plan) nhằm hướng dẫn một AI Agent khác thực hiện nâng cấp SoC hiện tại lên kiến trúc "Hardware-Coherent DMA" theo cách "Sideband Snoop" và thêm "ATU" (Address Translation Unit).

## Mục tiêu (Objective)
1. **Loại bỏ Software Coherency:** Xóa bỏ sự phụ thuộc vào lệnh `fence` để flush/invalidate cache trong firmware.
2. **Snoop qua Sideband:** Kéo dây tín hiệu trực tiếp giữa DMA và DCache để kiểm tra dữ liệu trước khi DMA phát lệnh AXI. Không đụng tới AXI Crossbar.
3. **Thêm MESI/MEI State:** Nâng cấp Tag Array của DCache để quản lý trạng thái đường truyền đa nhân/thiết bị.
4. **Thêm ATU:** Cung cấp khối chuyển đổi Virtual Address sang Physical Address cho DMA.

---

## Giai đoạn 1: Nâng cấp DCache (`cache_interface/dcache/`)

### 1. Sửa đổi `dcache_tag_array.v` (MESI/MEI Upgrade)
- **Thay đổi:** Loại bỏ cờ `valid` (1-bit) và cờ `dirty` (1-bit) hiện tại. Thay thế bằng một thanh ghi 2-bit `mesi_state [0:NUM_SETS-1]`.
- **Trạng thái:**
  - `2'b00` (I - Invalid): Dòng trống hoặc không hợp lệ.
  - `2'b01` (S/E - Shared/Exclusive Clean): Dòng chứa dữ liệu sạch (giống RAM).
  - `2'b10` (M - Modified): Dòng chứa dữ liệu bẩn (CPU đã ghi, RAM chưa cập nhật).
- **Logic:**
  - Hit = (`mesi_state != I`) & (`tags == lookup_tag`).
  - Lệnh CPU Write sẽ chuyển state S/E thành M.

### 2. Sửa đổi `dcache_controller.v` (Snoop Interface & FSM)
- **Port mới thêm vào module:**
  - `input  wire        snoop_req`
  - `input  wire [31:0] snoop_addr`
  - `input  wire        snoop_is_write`
  - `output reg         snoop_hit`
  - `output reg         snoop_data_valid`
  - `output reg  [31:0] snoop_data`
- **Logic FSM (trong Main FSM hoặc FSM độc lập ưu tiên cao):**
  - Khi đang ở `DCACHE_STATE_IDLE` và thấy `snoop_req == 1`:
    - Chuyển state sang `DCACHE_STATE_SNOOP`. Tạm dừng phục vụ `cpu_req` bằng cách giữ `cpu_ready = 0`.
    - Lấy `snoop_addr` đưa vào `tag_lookup`.
    - **Nếu Snoop Hit & State == M:**
      - Trả dữ liệu của line tương ứng (hoặc word tương ứng) ra `snoop_data`. Bật `snoop_data_valid = 1`. Bật `snoop_hit = 1`.
      - Downgrade state: Nếu DMA đọc (`snoop_is_write == 0`), hạ state từ M -> S/E. Nếu DMA ghi (`snoop_is_write == 1`), hạ state từ M -> I (Invalidate).
    - **Nếu Snoop Miss (hoặc State == S/E):**
      - Bật `snoop_hit = 0`. (DMA sẽ tự hiểu và phải ra RAM đọc/ghi qua AXI).
      - Nếu DMA ghi (`snoop_is_write == 1`) và Hit ở state S/E: hạ state -> I.
    - Xong việc, quay lại `DCACHE_STATE_IDLE`.

---

## Giai đoạn 2: Bổ sung khối ATU (Address Translation Unit)

- **Tạo file mới:** `ascon/dma/rtl/atu.v` (hoặc nhúng thẳng vào `ascon_dma.v`).
- **Nhiệm vụ:** Trong SoC này hiện chưa có MMU phức tạp, ta sẽ thiết lập một mô hình Base/Bound hoặc Lookup table cực kỳ đơn giản (hoặc một hàm ánh xạ 1-1 tạm thời nhưng có module riêng biệt để thể hiện kiến trúc ATU).
- **Giao diện (Interface):**
  - Nhận `virt_src_addr`, `virt_dst_addr` từ thanh ghi của phần mềm.
  - Trả ra `phys_src_addr`, `phys_dst_addr`.
- **Logic:** Khi phần mềm cấu hình `DMA_SRC_ADDR` và `DMA_DST_ADDR`, địa chỉ này đi qua khối ATU trước khi được chốt vào DMA FSM. Các luồng Snoop và AXI sau đó BẮT BUỘC dùng địa chỉ Physical.

---

## Giai đoạn 3: Nâng cấp DMA FSM (`ascon/dma/rtl/dma_ctrl_fsm.v`)

- **Port mới thêm vào module:** Các tín hiệu tương ứng với Snoop Interface của DCache.
- **Sửa đổi FSM (`dma_ctrl_fsm.v`):**
  - Chèn 2 state mới trước khi phát AXI Read/Write: `SNOOP_REQ` và `SNOOP_WAIT`.
  - **Luồng Read:** Trước khi bật `rd_start` cho AXI Read Engine, DMA FSM giơ `snoop_req = 1`, `snoop_addr = phys_src_addr`, `snoop_is_write = 0`.
    - Chờ DCache phản hồi.
    - Nếu `snoop_hit == 1` & `snoop_data_valid == 1`: Lấy `snoop_data` nạp thẳng vào `RD_FIFO`. Bỏ qua việc gọi AXI Read Engine. Tăng pointer lên 4 byte và lặp lại snoop cho từ (word) tiếp theo.
    - Nếu `snoop_hit == 0`: Gọi AXI Read Engine như cũ để ra Memory đọc.
  - **Luồng Write:** Tương tự, nếu DMA chuẩn bị ghi, giơ `snoop_req = 1` với `snoop_is_write = 1` để DCache tự invalidate line của nó (nếu có). Sau đó DMA mới gọi AXI Write Engine đẩy dữ liệu xuống RAM.

---

## Giai đoạn 4: Tích hợp Top-Level (`soc_top.v` & Core Level)

- Sửa đổi các file ghép nối (instantiation) để kéo dây Sideband từ `ascon_dma` tới `dcache_controller` (có thể phải đi xuyên qua `riscv_cpu_core_v2` nếu dcache nằm sâu bên trong).
- Khai báo các wire: `w_snoop_req`, `w_snoop_addr`, `w_snoop_is_write`, `w_snoop_hit`, `w_snoop_data_valid`, `w_snoop_data`.
- Chèn module `atu` nếu viết tách rời.

---

## Giai đoạn 5: Cập nhật Firmware & Testing (`gnu_toolchain/tests/`)

- Tìm file `test_ascon_dma_ad.c` và `test_dma_uart.c`.
- **Hành động:** 
  - Xóa toàn bộ các lệnh `__asm__ volatile ("fence rw,rw" ::: "memory");` được gọi trước `ascon_dma_start()`.
  - Xóa lệnh `__asm__ volatile ("fence r,r" ::: "memory");` sau quá trình chờ DMA xong.
- **Biên dịch và chạy thử Regression:** Chạy lại `test_integration.c` hoặc `test_ascon_dma_ad.c`. Nếu mô hình Hardware Coherency hoạt động đúng, Data của ASCON Ctext/Tag sẽ khớp hoàn toàn mà không cần flush bằng phần mềm.

---
## Tóm tắt các thay đổi File cần thiết:
1. `[MODIFY]` `cache_interface/dcache/dcache_tag_array.v`
2. `[MODIFY]` `cache_interface/dcache/dcache_controller.v`
3. `[NEW]`    `ascon/dma/rtl/atu.v`
4. `[MODIFY]` `ascon/dma/rtl/dma_ctrl_fsm.v`
5. `[MODIFY]` `ascon/dma/ascon_dma.v` (Để thêm ports)
6. `[MODIFY]` `soc_top.v` / `riscv_cpu_core_v2.v` (Routing dây snoop)
7. `[MODIFY]` `gnu_toolchain/tests/test_ascon_dma_ad.c` (Xóa fence)
8. `[MODIFY]` `gnu_toolchain/tests/test_dma_uart.c` (Xóa fence)
