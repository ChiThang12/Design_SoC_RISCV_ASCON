# Plan + Task: Testbench Signals & DMA Firmware

## Context
Testbench `run_soc_ascon.v` thiếu cơ chế nhận diện PASS/FAIL từ UART output của firmware. Các test uart/gpio/timer/clint/plic chạy nhưng không biết đúng/sai. DMA controller (S11 @ 0x60010000, M3 master) đã có trong hardware nhưng chưa có firmware test. Driver `dma.h` đã tồn tại trong `include/`.

---

## Kế hoạch tổng thể

### Phần 1 — run_soc_ascon.v (thêm output signals)
Mục tiêu: Nhìn vào log là biết ngay test nào PASS/FAIL, peripheral nào được access.

**1a. UART Pass/Fail Pattern Matcher**
- Sau mỗi newline trong UART monitor → quét `uart_line` tìm `[PASS]`, `[FAIL]`, `ALL_PASS`, `SOME_FAIL`
- Thêm counter: `pass_cnt`, `fail_cnt`
- $display: `[TEST-RESULT] *** PASS #N ***` hoặc `[TEST-RESULT] *** FAIL #N ***`
- Thêm vào `print_report()`: `TESTS: PASS=%d FAIL=%d`

**1b. S11 DMA Slave Monitor**
- Wire tap vào crossbar S11 (DMA config port @ 0x60010000)
- Decode offset → `CH0-SRC / CH0-DST / CH0-LEN / CH0-CTRL / STATUS / IRQ_EN`
- $display: `[S11-DMA] WRITE offset=0xXXX ch=N reg=CTRL data=0x1 (START!)`

**1c. GPIO Change Monitor**
- Khi `gpio_out` thay đổi → $display `[GPIO-OUT] gpio_out=0xXXXXXXXX OE=0xXXXXXXXX`

**1d. print_report() update**
- Thêm dòng tổng kết: pass/fail count, DMA access count, DMA IRQ count

---

### Phần 2 — test_dma.c (firmware mới)
File: `gnu_toolchain/tests/test_dma.c`  
Driver dùng: `include/dma.h`, `include/uart.h`, `include/plic.h`, `include/irq.h`

**Test 1 — CH0: Polling mem-to-mem (256 bytes)**
- src=`0x10000400` (điền pattern 0xA5A5A5A5), dst=`0x10000500`
- Start, poll STATUS[0] DONE, verify từng word
- Fail nếu timeout hoặc mismatch

**Test 2 — CH1: IRQ-driven (64 bytes)**
- Setup PLIC src 9 (DMA irq) + enable MEIE
- Start CH1, chờ ISR volatile flag
- ISR: plic_claim() → clear IRQ_STATUS[1] → plic_complete(9)
- Fail nếu timeout

**Test 3 — CH2+CH3: Dual simultaneous (64 bytes mỗi kênh)**
- Start cả hai → poll STATUS[2] và STATUS[3]
- Verify data cả hai channel
- Fail nếu ERROR bit set

**Test 4 — Error test (alignment lỗi)**
- CH0 với LEN=3 (không chia hết 4)
- Expect ERROR[0] set → PASS nếu báo lỗi đúng

**Output:** `[PASS] dma\r\n` hoặc `[FAIL] dma err=0xXX\r\n`

**DMEM buffer layout** (không overlap với DmemLayout_t @ 0x1C0, stack @ 0x1000):
```
0x10000200–0x1000027F  CH3 src (128B)
0x10000280–0x100002FF  CH3 dst (128B)
0x10000300–0x1000037F  CH2 src (128B)
0x10000380–0x100003FF  CH2 dst (128B)
0x10000400–0x100004FF  CH0 src (256B)
0x10000500–0x100005FF  CH0 dst (256B)
0x10000600–0x1000063F  CH1 src (64B)
0x10000700–0x1000073F  CH1 dst (64B)
```

---

### Phần 3 — Integration + Build
- `test_integration.c`: thêm `#include "test_dma.c"` + `run_dma_test()` → summary `7/7`
- `build_all.sh`: thêm build target `test_dma` với `-O0`
- Không cần đổi gì trong `run_soc_ascon.v` vì pattern matcher chấp nhận bất kỳ `ALL_PASS N/N`

---

## Files bị thay đổi

| File | Thay đổi |
|------|---------|
| `run_soc_ascon.v` | Thêm pass/fail matcher, S11 monitor, GPIO monitor, report update |
| `gnu_toolchain/tests/test_dma.c` | **Tạo mới** |
| `gnu_toolchain/tests/test_integration.c` | Thêm include + call test_dma |
| `gnu_toolchain/build_all.sh` | Thêm test_dma build target |

