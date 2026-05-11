# Handoff Log


## 2026-05-12 Session Summary — Fix LSU drain-race regression failures

### Mục tiêu sprint
Sau khi fix LSU drain-race (cũ, đã merge ở `LSU.v:177-179`), 8/9 regression tests
vẫn TIMEOUT. CPU stuck PC=0x98. Tìm và fix.

### Đã làm

1. **Fix #1 (RTL — ICache AXI deadlock)** ✅
   - File: `cache_interface/icache/icache_axi_interface.v`
   - Root cause: ARVALID combinational từ `refill_start` (1-cycle pulse). Khi
     crossbar bận serve DCache cùng cycle → ARREADY=0 → AR bị drop. Controller
     đã commit `pf_active<=1` → deadlock: `pf_active=1, refill_busy=0,
     refill_done=0` forever, Phase 1 gate `(!pf_active || refill_done)`=0 chặn
     refill_start.
   - Fix: latch `arvalid_r` + `araddr_r`, giữ ARVALID high tới khi `ar_handshake`
     (đúng chuẩn AXI4: VALID phải hold tới READY).
   - Đây là **AXI protocol violation** — ICache là master M0 duy nhất có lỗi
     này. DCache (M1) đã có FSM proper.

2. **Fix #2 (Toolchain — .data init)** ✅
   - File: `regression_full.sh:91` — bỏ flag `-c`
   - Root cause: regression build với `-c` (NO_CRT0=1) → bare-metal startup KHÔNG
     copy .data ROM→DMEM. Nhưng firmware tests dùng `uart_puts("string")` đọc
     string từ DMEM[0x10000014+] → uninitialized → in rác.
   - Fix: build với full CRT0 (bỏ `-c`) để `_start` copy .data trước khi gọi main.
   - test_uart_simple PASS với `-c` chỉ vì nó dùng char literals (không truy
     cập .data).

3. **DEBUG_STALL instrumentation** (gated, giữ lại cho session sau)
   - `cpu/core/hazard_detection.v` — trace stall signals mỗi cycle khi pipeline
     freeze (run > 50 cycles). Phân biệt rõ `lsu_dep`, `fence`, `mul`, `imem_rdy`.
   - `cache_interface/icache/icache_controller.v` — dump ICache FSM khi stuck
     (pf_active, refill_busy, refill_done, ctrl_hit, …).
   - `cpu/core/LSU.v` — dump LSU FSM khi `!lsu_idle` quá lâu.
   - Bật bằng: `iverilog -g2005 -DDEBUG_STALL ...` hoặc thêm define vào workflow.

### Kết quả Regression sau 2 fix

```
Total: 9 | PASS: 1 | FAIL: 0 | TIMEOUT: 8
```

| Test | Final PC | UART# | Last chars / Vấn đề |
|------|----------|-------|---------------------|
| test_uart_simple | — | 29 | **PASS** ✅ |
| test_uart | 0x168 | 30 | "Hello UART..A[FAIL] uart err=0" — đến tận end, fail tại IRQ check |
| test_gpio | 0x460 | 0 | Stuck sớm, 0 UART |
| test_timer | 0x458 | 0 | Stuck sớm, 0 UART |
| test_clint | 0x408 | 0 | Stuck sớm, 0 UART |
| test_plic | 0x638 | 0 | Stuck sớm, 0 UART |
| test_ascon | 0x58c | 16 | In "0123456789ABCDEF" rồi stuck |
| test_dma_uart | 0x63c | 0 | Stuck sớm, 0 UART |
| test_integration | 0x178 | 30 | "...AuartuartBHello U" — loop infinite |

### Còn làm (cho session sau)

Các test TIMEOUT còn lại **KHÔNG còn do ICache/CRT0** — bug khác:

- **test_uart (PC=0x168)**: firmware đi đến cuối, in "[FAIL] uart err=0" → logic
  IRQ test fail. PC=0x168 nằm trong vòng polling UART STATUS. Debug:
  - `gnu_toolchain/tests/test_uart.c` hàm `run_uart_test` test TX IRQ
  - Check UART IRQ register layout (S5 slave) vs firmware expectation
  - PLIC routing src=1,2 cho UART

- **test_gpio/timer/clint/plic/dma_uart (0 UART)**: stuck rất sớm, chưa kịp in.
  Final PC khác nhau (0x460, 0x458, 0x408, 0x638, 0x63c) → mỗi test stuck ở
  function khác trong firmware. Có thể là:
  - MMIO không trả ready → CPU stuck ở `lw status_reg` loop
  - Peripheral chưa init đúng → IRQ không fire
  - Cần chạy với `-DDEBUG_STALL` để xem signal nào ghim pipeline

- **test_integration (PC=0x178, loop)**: đang chạy lặp các test con — có thể
  một sub-test infinite loop trong busy-wait. PC=0x178 = uart_puts polling
  TX_READY. Có thể UART TX bị stuck (full hoặc busy không clear).

- **test_ascon (PC=0x58c)**: in được data table nhưng stuck. PC=0x58c có thể
  ở ASCON DMA wait loop. Debug bằng waveform + dump pump_state.

### Files thay đổi

| File | Loại | Mô tả |
|------|------|-------|
| `cache_interface/icache/icache_axi_interface.v` | **RTL FIX** | Sticky ARVALID/ARADDR |
| `regression_full.sh` | **Build FIX** | Bỏ `-c` → full CRT0 cho mọi test |
| `cpu/core/hazard_detection.v` | DEBUG (gated) | `\`ifdef DEBUG_STALL` trace |
| `cache_interface/icache/icache_controller.v` | DEBUG (gated) | `\`ifdef DEBUG_STALL` trace |
| `cpu/core/LSU.v` | DEBUG (gated) | `\`ifdef DEBUG_STALL` trace |
| `gnu_toolchain/tests/*.hex` | Rebuilt | 8 test hex rebuilt với CRT0 |

### Design decisions

- **KHÔNG** áp dụng đề xuất sửa `LOAD_DCACHE` thêm `drain_state==DRAIN_IDLE`
  gate. FSM hiện đã đúng (mux ưu tiên load + drain rút lui khi
  `load_using_dcache`). Thêm gate đó sẽ deadlock theo chiều ngược.
- Giữ DEBUG_STALL trace (gated bằng `\`ifdef`) thay vì xoá — instrumentation
  ổn định, không ảnh hưởng prod, dùng được cho debug pipeline stuck tương lai.

### Known bugs chưa fix
- 8 tests TIMEOUT (xem bảng trên)
- LSU.v còn một entry `cur_load_addr` flow chưa hoàn toàn clean nhưng không
  blocking

---

## 📘 Debug Methodology (cho session sau follow)

### Quy trình đã dùng — KHUYẾN NGHỊ áp dụng cho mọi bug stuck/timeout

**Bước 1 — Đọc log có sẵn TRƯỚC khi instrument**

`log/<test>.log` chứa summary cuối: Final PC, cycle count, LSU state, cache
stats, AXI counters. Trước khi đoán, đọc 4 mục:
- `Final PC` → biết stuck ở đâu
- `LSU drain idle YES/NO, SB remain N entries` → loại trừ LSU
- `ICache hits/misses, DCache hits/misses` → cache có hoạt động không
- `Max stall run` → biết pipeline freeze bao lâu

**Bước 2 — Đối chiếu PC với `.dump` mới nhất**

```bash
cd gnu_toolchain && ./compile_c_to_hex.sh -i tests/<t>.c -o tests/<t>.hex -O 0 -k
grep "  <pc_hex>:" <t>.dump
```

⚠️ **CẨN THẬN**: `.dump` cũ trong git có thể outdated. **Luôn rebuild với `-k`**
trước khi đối chiếu. Tôi đã suýt sai vì so với dump cũ (lệch tới mức 0x14 trong
dump cũ là `addi x5,x5,108`, dump mới là `addi x5,x5,24`).

**Bước 3 — Phủ định giả thuyết bằng evidence**

Trước khi fix, viết ra **mọi giả thuyết** và check evidence từng cái. Ví dụ
session này, giả thuyết "LSU load capture-ready race" bị phủ nhận bởi:
`LSU drain idle YES, SB remain 0` ⇒ LSU rỗng, không race.

**Bước 4 — Instrument có chủ đích (DEBUG_STALL pattern)**

Dùng `\`ifdef DEBUG_STALL` pattern (tham khảo 3 file đã làm):
- Counter đếm cycle khi signal stuck (`dbg_stall_run`, `icache_dbg_stuck`)
- Chỉ `$display` khi counter > threshold (60+ cycles) → tránh noise
- Print TẤT CẢ signal liên quan trên 1 dòng → grep ra nhanh

Build với define:
```bash
iverilog -g2005 -DDEBUG_STALL -o /tmp/sim.vvp run_soc_ascon.v && vvp /tmp/sim.vvp > /tmp/dbg.log
grep "^\[STALL" /tmp/dbg.log | tail -20    # xem signal nào stuck
grep "^\[ICACHE" /tmp/dbg.log | tail -10   # xem ICache state
grep "^\[LSU"    /tmp/dbg.log | tail -10   # xem LSU state
```

**Bước 5 — Trace từ stuck signal về source**

Tín hiệu nào stuck high/low → trace ngược về module phát ra nó:
1. Tìm `assign <signal>` hoặc `<signal> <=` trong file
2. Verify điều kiện set/clear có chạy không
3. Tìm scenario làm điều kiện không bao giờ thoả

**Bước 6 — Phân biệt RTL bug vs Firmware/Toolchain bug**

Khi data sai (load returns wrong value):
- So `program.hex` với fresh `objdump -d` của ELF — match? → RTL bug
- Không match? → toolchain bug (hex stale, build mode wrong)
- Cụ thể session này: `program.hex` line 6 = `01828293`, dump cũ nói
  `06c28293` — TƯỞNG là RTL bug nhưng thực ra dump cũ outdated. Dump mới
  match `01828293` → firmware đúng, bug ở chỗ khác (.data không copy).

**Bước 7 — Fix có scope nhỏ nhất**

- Sửa 1 file đầu tiên rồi test ngay
- Không refactor xung quanh
- Comment fix với tag `// [FIX-<NAME>] ...` để session sau hiểu why

**Bước 8 — Verify bằng regression**

```bash
bash regression_full.sh -b      # rebuild + chạy 9 tests
```

So sánh PASS/FAIL/TIMEOUT trước-sau. Verify fix không phá test khác.

### Anti-patterns (đã suýt mắc, tránh)

- ❌ Đoán bug → fix → chạy → fail → đoán tiếp. **Phải có evidence trước fix.**
- ❌ Tin tưởng dump file cũ trong repo. **Always rebuild với `-k`.**
- ❌ Áp dụng fix do agent đề xuất mà không verify. Ví dụ Explore agent đề xuất
  sửa `LOAD_DCACHE` state — sai (đã phân tích FSM, sẽ deadlock ngược).
- ❌ Refactor RTL khi chưa biết root cause. Bug có thể nằm ở toolchain hoặc
  firmware build flag.

### Quick-Start cho session mới

```bash
# 1. Đọc log mới nhất
ls -t log/*.log | head -1 | xargs rtk read | head -150

# 2. Identify stuck signal
grep "Final PC\|LSU drain idle\|Max stall run" log/<test>.log

# 3. Rebuild dump để verify firmware
cd gnu_toolchain && ./compile_c_to_hex.sh -i tests/<t>.c -o /tmp/<t>.hex -O 0 -k

# 4. Nếu cần instrument: kích DEBUG_STALL
iverilog -g2005 -DDEBUG_STALL -o /tmp/sim.vvp run_soc_ascon.v && vvp /tmp/sim.vvp > /tmp/dbg.log

# 5. Verify fix
bash regression_full.sh -b
```
