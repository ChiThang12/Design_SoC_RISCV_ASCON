# PYNQ-Z2 Notebook UART Flow

Tài liệu này ghi lại đúng flow để chạy FreeRTOS trên PYNQ-Z2 và quan sát trực quan bằng notebook.

## Mục tiêu

- Nạp bitstream lên PL.
- Nạp firmware FreeRTOS lên SoC.
- Quan sát log UART và dashboard telemetry trong notebook.
- Nhìn thấy tín hiệu sống bằng LED heartbeat trên board.

## Files liên quan

- Bitstream/top: `fpga/src/fpga_top.v`
- UART notebook top: `fpga/src/pynqz2_notebook_uart_top.v`
- Firmware smoke test: `fpga/os/source/test_freertos_kernel_smoke.c`
- Notebook demo: `fpga/notebook/pynq_notebook_uart_demo.py`
- Constraint board đầy đủ: `fpga/constraints/pynqz2_full.xdc`

## Lưu ý quan trọng về clock

- PYNQ-Z2 dùng clock board 125 MHz cho PL, nên XDC board-level đúng là `create_clock -period 8.000`.
- File `pynqz2_50mhz.xdc` chỉ nên dùng nếu bạn thật sự tạo clock nội bộ 50 MHz ở cấp thiết kế riêng.
- Nếu chạy overlay thật trên board, ưu tiên `fpga/constraints/pynqz2_full.xdc`.

## Flow đúng khi chạy trên notebook

1. Build bitstream với top `fpga_top` hoặc `pynqz2_notebook_uart_top`.
2. Copy bitstream lên PYNQ-Z2, đặt tên khớp với notebook, mặc định là `soc_rvas_notebook_uart.bit`.
3. Build firmware FreeRTOS ra file `test_freertos_kernel_smoke.bin`.
4. Mở notebook trên PYNQ-Z2.
5. Chạy script `fpga/notebook/pynq_notebook_uart_demo.py`.
6. Notebook sẽ:
   - load overlay,
   - đẩy firmware qua UART/DMA,
   - đọc log `[RTOS]`, `[TEL]`, `[PASS]`, `[FAIL]`,
   - render dashboard realtime.

## Trạng thái mong đợi khi boot

Sau khi chạy đúng, màn hình notebook sẽ đi theo chuỗi:

- `IDLE`
- `BOOTING`
- `RUNNING`
- `PASS`

Và log UART sẽ có các dòng như:

- `[RTOS] FreeRTOS kernel smoke boot`
- `[TEL] dashboard=armed`
- `[TEL] scheduler=starting`
- `[TEL] task=A tick=... a=... b=... beat=...`
- `[TEL] task=B tick=... a=... b=... beat=...`
- `[PASS] freertos_kernel_smoke`

## Hiệu ứng trên board

- LED0 được dùng làm `led_heartbeat`.
- `task A` cập nhật heartbeat theo tick để bạn nhìn thấy OS đang sống.
- Nếu scheduler không chạy hoặc task không được tạo, notebook sẽ hiện `[FAIL]`.

## Gợi ý thao tác nhanh

Trong notebook:

```python
from fpga.notebook.pynq_notebook_uart_demo import demo
demo()
```

Hoặc nếu muốn đi từng bước:

```python
from fpga.notebook.pynq_notebook_uart_demo import NotebookUartBridge

bridge = NotebookUartBridge()
bridge.boot("test_freertos_kernel_smoke.bin")
bridge.watch_dashboard(seconds=10.0)
```

## Khi nào cần sửa thêm

- Nếu notebook không thấy log telemetry, kiểm tra tên bitstream và overlay.
- Nếu LED không nhấp nháy, kiểm tra mapping `led_heartbeat` trong XDC và top module.
- Nếu muốn clock nội bộ 50 MHz, phải thêm clocking IP hoặc divider, không thể chỉ đổi XDC board clock.
