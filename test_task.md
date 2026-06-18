# Test Task — Status & Bug Tracker

## Cách dùng
- Đọc "Current Sprint" để biết đang làm gì.
- Sau mỗi test → cập nhật status table.
- Sau mỗi fix → update Bug Tracker với kết quả verify thực tế.
- Chỉ ghi kết quả đã chạy simulation, không ghi assumption.

---

## Current Sprint (2026-05-26)

**Focus**: 6/10 C-layer PASS. Còn: C4 ⚠️ crash | C5 ⚠️ hang | C6 C7 ❓

**Bước tiếp theo**:
```
✅ A1–A10, B1–B3, C1 C2 C3 C8 C9 C10 PASS
⚠️ C5 — uart=38, ISR chạy 3× đúng, main loop hang vì timer_irq_count stale (BUG-C5-RAW)
   Quick test: thêm fence r,r trong while loop của test_timer.c
⚠️ C4 — uart=0, PC→0x01000000 crash trước uart_init trong PLIC setup (BUG-C4-GPIO-CRASH)
   Debug: đọc log/test_gpio.log cycle ~4900–5100, trace test_gpio.dump
❓ C6 C7 — re-run sau plic.h revert để có baseline log
```

---

## Status Table

| ID | Test | Module | Lần cuối chạy | Kết quả | Ghi chú |
|----|------|--------|--------------|---------|--------|
| A1 | tb_layer1_pipeline | CPU pipeline | 2026-05-13 | ✅ PASS 17/17 | BUG-001 + BUG-MUL fixed |
| A2 | tb_riscv_cpu_core_v2 | CPU core full | 2026-05-13 | ✅ PASS 61/61 | All 15 TC passed |
| A3 | tb_instmem | IMEM AXI | 2026-05-16 | ✅ PASS 64/64 | Fix: SLVERR on write |
| A4 | tb_datamem | DMEM AXI | (log cũ) | ✅ PASS 71/71 | log/tb_datamem.log |
| A5 | tb_axi4_crossbar | AXI crossbar | 2026-05-16 | ✅ PASS 21/21 | Fix: DECERR timing + BID/RID + ARBIT |
| A6 | ascon_top_tb | ASCON core | (log cũ) | ✅ PASS 9/9 | log/ascon_top_tb_v1.log |
| A7 | tb_multi_block_dma | ASCON+DMA | (session cũ) | ✅ PASS | User confirmed |
| A8 | tb_dma_top | GP-DMA | (log cũ) | ✅ PASS 108/108 | log/tb_dma_top.log |
| A9 | tb_plic_top | PLIC | (log cũ) | ✅ PASS 51/51 | log/tb_plic_top.log |
| A10 | tb_soc_ctrl_slave | SoC ctrl | (log cũ) | ✅ PASS 61/61 | log/tb_soc_ctrl_slave.log |
| B1 | layer2 CRT0 hazard | CPU+DCache | 2026-05-16 | ✅ PASS | 14/14 words đúng |
| B2 | layer4 ICache boot | ICache+IMEM | 2026-05-16 | ✅ PASS | DEADBEEF ✓ |
| B3 | layer3 DCache | DCache+DMEM | 2026-05-16 | ✅ PASS | s0=1 s1=2 s2=3 s3=4 |
| C1 | test_crt0_verify | Boot+CRT0 | 2026-05-18 | ✅ PASS | uart=13 |
| C2 | test_uart_simple | UART TX basic | 2026-05-18 | ✅ PASS | uart=29 |
| C3 | test_uart | UART IRQ W1C | 2026-05-19 | ✅ PASS | uart=28 |
| C4 | test_gpio | GPIO+IRQ | 2026-05-26 | ⚠️ CRASH | uart=0, PC→0x01000000 trong PLIC setup. BUG-C4-GPIO-CRASH |
| C4.1 | tb_gpio_top | GPIO RTL unit | 2026-05-22 | ✅ PASS 18/18 | TC01–TC06 OK |
| C4.3 | IFU redirect slip | cpu/core/IFU.v | 2026-05-25 | ✅ APPLIED | FIX-IFU-REDIRECT-SLIP |
| C4.4 | ICache last-word race | icache_controller.v | 2026-05-25 | ✅ APPLIED | FIX-ICACHE-LASTWORD-RACE |
| C5 | test_timer | Timer IRQ | 2026-05-26 | ⚠️ TIMEOUT | uart=38, ISR 3× đúng, main loop stale. BUG-C5-RAW |
| C6 | test_clint | CLINT | 2026-05-25 | ❓ | chưa debug lại sau plic.h revert |
| C7 | test_plic | PLIC routing | 2026-05-25 | ❓ | chưa debug lại |
| C8 | test_ascon | ASCON DMA | 2026-05-25 | ✅ PASS | uart=14 "[PASS] ascon.." |
| C9 | test_dma_uart | GP-DMA | 2026-05-25 | ✅ PASS | uart=74 |
| C10 | test_integration | All IPs | 2026-05-25 | ✅ PASS | uart=60 |

**Legend**: ✅ PASS | ❌ FAIL | ⚠️ TIMEOUT/CRASH | ❓ Not run

---

## Bug Tracker

### OPEN Bugs

---

### BUG-C4-GPIO-CRASH — test_gpio PC crash trước uart_init

- **Severity**: HIGH (blocks C4)
- **Layer**: C4 (`test_gpio`)
- **Triệu chứng**: uart=0. PC→0x01000000 (unmapped) crash xảy ra trong PLIC setup, giữa `plic_set_threshold(0)` và `plic_set_priority(PLIC_SRC_GPIO, 1)`.
- **Evidence (session cũ)**:
  ```
  cy4948: plic_set_threshold(0) → PLIC-WREXEC aw_off=200 ok
  cy5026: ICache burst tại 0x01000000 (unmapped) → DECERR M0 READ
  — plic_set_priority chưa chạy
  ```
- **Hypothesis**:
  1. `irq_set_mtvec(gpio_isr)` gọi trước PLIC setup → pending edge IRQ → CPU nhảy ISR tại địa chỉ sai
  2. Hoặc CPU pipeline bug làm PC nhảy sang `(arg << 12)` = `0x01000000`
  3. Hoặc stack frame của `run_gpio_test` bị corrupt bởi RAW hazard → ra bị corrupt
- **Debug path**:
  1. Đọc `log/test_gpio.log` cycle ~4900–5100 → xem PC trace trước crash
  2. Xem `test_gpio.dump` tại địa chỉ crash → instruction đang chạy là gì
  3. So sánh với `test_gpio.c` flow: `irq_set_mtvec` → `plic_set_threshold` → crash
- **Status**: ❌ NOT FIXED

---

### BUG-C5-RAW — timer_irq_count stale sau mret

- **Severity**: HIGH (blocks C5)
- **Layer**: C5 (`test_timer`)
- **File nghi ngờ**: `cpu/core/LSU.v` — DCache invalidation sau interrupt return
- **Triệu chứng**: uart=38 "[DBG] init→A ok→B wait" rồi timeout. ISR chạy đúng 3 lần (3× `plic_complete(5)` confirmed), nhưng `while (timer_irq_count < 3u)` không thoát.
- **Evidence**:
  ```
  [PLIC-WREXEC] aw_off=204 w_data=00000005 → 3 lần (ISR complete ×3)
  ISR disasm 0x5BC: lw+addi+sw timer_irq_count (0x1000009C) đúng
  main loop (0x6A8) đọc timer_irq_count = stale 0
  ```
- **Root cause hypothesis**: Sau `mret`, ISR store `timer_irq_count++` vào DCache. Main loop load lại từ 0x1000009C nhưng DCache line vẫn cache với giá trị cũ (0) → RAW không resolve qua interrupt boundary.
- **Quick fix để test**:
  ```c
  while (timer_irq_count < 3u) {
      __asm__ volatile ("fence r,r" ::: "memory");
      if (--timeout == 0u) { ... }
  }
  ```
  Nếu fix → confirm DCache line stale, cần fix DCache invalidation sau mret.
- **Debug path**:
  1. Thử `fence r,r` workaround trong firmware → nếu PASS xác nhận root cause
  2. Nếu vẫn fail → thêm `$display` vào LSU khi load từ 0x1000009C
  3. Kiểm tra DCache flush/invalidate khi CPU nhận interrupt → `mret`
- **Status**: ❌ NOT FIXED

---

### FIXED / CLOSED Bugs (tóm tắt)

| Bug ID | File thay đổi | Root cause tóm tắt | Status |
|--------|-------------|-------------------|--------|
| BUG-001 load-use hazard | `hazard_detection.v:117`, `PIPELINE_REG_MEM_WB.v:71` | `!lsu_result_valid` → `!lsu_committed`; flush double-clear | ✅ VERIFIED 2026-05-13 |
| BUG-MUL multiplier | `riscv_multiplier.v`, `cpu_core_v2.v:606` | E1 bị chặn bởi flush; E2 dùng registered thay vì comb | ✅ VERIFIED 2026-05-13 |
| BUG-002 LSU SB NC fwd | `LSU.v:134` | `fwd_hit` không check NC addr → MMIO read stale. Fix: `&& (req_addr[31:29]==3'b000)` | ✅ VERIFIED 2026-05-19 |
| BUG-TIMER timer enable | `timer_channel.v` | `en` không detect rising edge → không load count_val | ✅ VERIFIED 2026-05-25 |
| BUG-ICACHE AXI deadlock | `icache_axi_interface.v` | ARVALID không de-assert sau handshake | ✅ VERIFIED 2026-05-16 |
| BUG-JAL-STALL | `cpu_core_v2.v` | `pc_src_ex` combinational → lost khi stall_any=X. Fix: `pc_src_held_r` latch | ✅ VERIFIED 2026-05-16 |
| BUG-C4 IFU redirect slip | `IFU.v:100` | `redirect_pending=1` không gate NOP → stale instr slip. Fix: drive IFU_NOP | ✅ APPLIED C4.3 |
| BUG-C4 ICache last-word race | `icache_controller.v:344+` | `data_array` write commit end-of-Y, read thấy stale. Fix: `last_word_*` bypass | ✅ APPLIED C4.4 |
| BUG-PLIC-DECERR | — | CLOSED: PLIC HW đúng. TB monitor đọc s9_wdata tại AW-time (stale). Real bug = CPU pipeline | ✅ CLOSED 2026-05-26 |
| BUG-C8-DOT | `test_ascon.c` | Firmware 1 chấm `"ascon."`, TB match 2 chấm `"ascon.."` | ✅ RESOLVED 2026-05-25 |
| A3-SLVERR | `inst_mem_axi_slave.v` | ROM accept write + OKAY → fix: drain W, trả SLVERR | ✅ VERIFIED 2026-05-16 |
| BUG-UART-LINEBUF | `test_uart.c` | Byte 'A' không có `\n` → TB linebuf prefix `"A[PASS]"` → no match | ✅ VERIFIED 2026-05-19 |
| BUG-C9b TB linebuf | `test_dma_uart.c` | `[MSG]...bytes...[PASS]` thành 1 dòng → add `uart_puts("\r\n")` | ✅ VERIFIED 2026-05-20 |
| BUG-HEX-FLAG | `test_timer.hex` rebuilt | Hex build với `-c` flag → `.rodata` không copy sang DMEM → uart=0 | ✅ VERIFIED 2026-05-20 |

---

## Uncommitted Changes

```
cpu/core/PIPELINE_REG_MEM_WB.v     (BUG-001) ✅ verified
cpu/core/hazard_detection.v        (BUG-001) ✅ verified
cpu/core/LSU.v                     (BUG-002 NC fwd) ✅ verified C3
cpu/core/IFU.v                     (BUG-C4 sub1: FIX-IFU-REDIRECT-SLIP) ✅ applied
cpu/riscv_cpu_core_v2.v            (BUG-MUL + BUG-JAL-STALL) ✅ verified
peripheral/timer/rtl/timer_channel.v (BUG-TIMER) ✅ verified C5
cache_interface/icache_axi_interface.v (BUG-ICACHE) ✅ verified B2
cache_interface/icache/icache_controller.v (BUG-C4 sub2: FIX-ICACHE-LASTWORD-RACE) ✅ applied
memory/inst_mem_axi_slave.v        (A3 fix) ✅ verified
gnu_toolchain/tests/*.hex          (rebuilt)
```

**Quy tắc commit**: Commit IFU + ICache fix sau khi C4 PASS.

---

## Thứ tự chạy để declare "SoC verified"

```
✅ A1–A10 → B1–B3 → C1 C2 C3 C8 C9 C10 PASS

⚠️ C5: Fix BUG-C5-RAW (thử fence r,r workaround trước)
⚠️ C4: Fix BUG-C4-GPIO-CRASH (trace log/test_gpio.log)
❓ C6 C7: Re-run để có log baseline

→ C5 ✅ + C4 ✅ + C6 ✅ + C7 ✅ → C10 re-run → SoC VERIFIED
```
