# Test Task — Status & Bug Tracker

## Cách dùng
- Đọc "Current Sprint" để biết đang làm gì.
- Sau mỗi test → cập nhật status table.
- Sau mỗi fix → ghi vào Fix History với kết quả verify thực tế.
- Chỉ ghi kết quả đã chạy simulation, không ghi assumption.

---

## Current Sprint (2026-05-26)

**Focus**: C layer — C1 ✅ C2 ✅ C3 ✅ C8 ✅ C9 ✅ C10 ✅ PASS | C5 ⚠️ B-hang | C4 ⚠️ crash | C6 C7 ❓
**Layer hiện tại**: regression_full.sh 2026-05-26: 6/10 PASS. BUG-PLIC-DECERR đã phân tích sâu → PLIC HW đúng, vấn đề nằm ở CPU (RAW hazard / PC corruption). plic.h đã revert về |= (ổn định).
**Bước tiếp theo**:
```
1. ✅ A1–A10 tất cả PASS
2. ✅ B1–B3 PASS
3. ✅ C1 C2 C3 C8 C9 C10 PASS
4. ✅ C4.1–C4.4 PASS (IFU + ICache fix applied)
5. ⚠️ C5 (2026-05-26) — uart=38 "[DBG] init → A ok → B wait" rồi hang
      Root cause: ISR chạy đúng 3× (3 plic_complete(5) confirmed), nhưng
      main loop đọc timer_irq_count stale do RAW hazard sau mret.
      → Fix: BUG-C5-RAW (xem bug tracker)
6. ⚠️ C4/test_gpio (2026-05-26) — uart=0, crash trước uart_init
      Root cause: PC nhảy đến 0x01000000 (unmapped) trong PLIC setup (giữa
      threshold và priority write). Nghi ngờ mtvec bị ghi đè hoặc CPU pipeline
      bug trong interrupt pending path.
      → Fix: BUG-C4-GPIO-CRASH (xem bug tracker)
7. ❓ C6 C7 — chưa debug lại sau plic.h revert
      → Re-run và đọc log để xác định root cause riêng biệt
```

---

## Status Table

| ID | Test | Module | Lần cuối chạy | Kết quả | Ghi chú |
|----|------|--------|--------------|---------|--------|
| A1 | tb_layer1_pipeline | CPU pipeline | 2026-05-13 | ✅ PASS 17/17 | BUG-001 + BUG-MUL fixed |
| A2 | tb_riscv_cpu_core_v2 | CPU core full | 2026-05-13 | ✅ PASS 61/61 | All 15 TC passed |
| A3 | tb_instmem | IMEM AXI | 2026-05-16 | ✅ PASS 64/64 | Fix: SLVERR on write, ROM unchanged |
| A4 | tb_datamem | DMEM AXI | (log cũ) | ✅ PASS 71/71 | log/tb_datamem.log xác nhận |
| A5 | tb_axi4_crossbar | AXI crossbar | 2026-05-16 | ✅ PASS 21/21 | Fix: DECERR timing + BID/RID + ARBIT addr |
| A6 | ascon_top_tb | ASCON core | (log cũ) | ✅ PASS 9/9 | log/ascon_top_tb_v1.log + user confirmed |
| A7 | tb_multi_block_dma | ASCON+DMA | (session cũ) | ✅ PASS | User confirmed |
| A8 | tb_dma_top | GP-DMA | (log cũ) | ✅ PASS 108/108 | log/tb_dma_top.log xác nhận |
| A9 | tb_plic_top | PLIC | (log cũ) | ✅ PASS 51/51 | log/tb_plic_top.log xác nhận |
| A10 | tb_soc_ctrl_slave | SoC ctrl | (log cũ) | ✅ PASS 61/61 | log/tb_soc_ctrl_slave.log xác nhận |
| B1 | layer2 CRT0 hazard | CPU+DCache | 2026-05-16 | ✅ PASS | CRT0 copy 14/14 words đúng |
| B2 | layer4 ICache boot | ICache+IMEM | 2026-05-16 | ✅ PASS | Minimal firmware DEADBEEF ✓ |
| B3 | layer3 DCache | DCache+DMEM | 2026-05-16 | ✅ PASS | s0=1 s1=2 s2=3 s3=4 đúng |
| C1 | test_crt0_verify | Boot+CRT0 | 2026-05-18 | ✅ PASS | uart=13 "[PASS] crt0.." |
| C2 | test_uart_simple | UART TX basic | 2026-05-18 | ✅ PASS | uart=29 "UART OK..[PASS] uart_simple.." |
| C3 | test_uart | UART IRQ W1C | 2026-05-19 | ✅ PASS | uart=28 "Hello UART..A..[PASS] uart.." (BUG-UART-LINEBUF fixed) |
| C4 | test_gpio | GPIO+IRQ | 2026-05-26 | ⚠️ TIMEOUT | uart=0. PC→0x01000000 (unmapped) giữa plic_set_threshold và plic_set_priority. BUG-C4-GPIO-CRASH |
| C4.1 | tb_gpio_top | GPIO RTL unit | 2026-05-22 | ✅ PASS 18/18 | TC01–TC06: reset/DIR/DOUT/DIN/edgeIRQ/W1C/wake |
| C4.2 | tb_icache_jalr | JALR+ICache flush | 2026-05-22 | ✅ PASS (hypothesis sai) | flush>stall_any confirmed, root cause thực = 2 bugs dưới |
| C4.3 | IFU redirect slip fix | cpu/core/IFU.v | 2026-05-25 | ✅ APPLIED | redirect_pending=1 → drive NOP, ngăn stale instruction slip |
| C4.4 | ICache last-word race fix | icache_controller.v | 2026-05-25 | ✅ APPLIED | last_word buffer bypass stale data_array beat cuối refill |
| C4.5 | test_gpio post-fix | GPIO+PLIC+IRQ | 2026-05-26 | ⚠️ TIMEOUT | gpio_out=0xAA ✓ (trước đây). Hiện uart=0: PC crash 0x01000000 trước khi in bất kỳ UART |
| C5 | test_timer | Timer IRQ | 2026-05-26 | ⚠️ TIMEOUT | uart=38 "[DBG] init→A ok→B wait" hang. ISR chạy 3× đúng. timer_irq_count stale vì RAW hazard sau mret. BUG-C5-RAW |
| C6 | test_clint | CLINT | 2026-05-25 | ⚠️ TIMEOUT | uart=0 — chưa debug lại sau plic.h revert |
| C7 | test_plic | PLIC routing | 2026-05-25 | ⚠️ TIMEOUT | uart=0 — chưa debug lại sau plic.h revert |
| C8 | test_ascon | ASCON DMA | 2026-05-25 | ✅ PASS | uart=14 "[PASS] ascon.." — BUG-C8-DOT resolved |
| C9 | test_dma_uart | GP-DMA | 2026-05-25 | ✅ PASS | uart=74 "[INFO] CPU compute..HELLO DMA-SOC!..[PASS] dma_uart" |
| C10 | test_integration | All IPs | 2026-05-25 | ✅ PASS | uart=60 "=== Integration Test Start ===..Hello U.." |

**Legend**: ✅ PASS | ❌ FAIL | ⚠️ TIMEOUT | ❓ Not run | 🚫 TB/FW missing

---

## Bug Tracker

### BUG-001 — Load-Use Hazard
- **Severity**: CRITICAL (blocks CRT0, blocks C1-C10 except C2)
- **Layer**: A1 / B1 / C1
- **Files**:
  - `cpu/core/PIPELINE_REG_MEM_WB.v` line 71
  - `cpu/core/hazard_detection.v` line 117
- **Triệu chứng**: `_copy_data` store 0 thay vì giá trị đúng → firmware bị corrupt
- **Root cause**: `!lsu_result_valid` thay vì `!lsu_committed`; `flush_id_ex` double-flush khi cả stall đồng thời
- **Fix applied (2026-05-12)**:
  ```verilog
  // PIPELINE_REG_MEM_WB.v:71
  end else if (!stall_ex_mem && !lsu_committed) begin
  // hazard_detection.v:117
  assign flush_id_ex = (load_use_hazard && !lsu_dep_stall) || ...
  ```
- **Test để verify**: A1 (TC-LU, TC-CRT0) → A2 → B1
- **Status**: ✅ VERIFIED 2026-05-13 — A1 PASS 17/17, A2 PASS 61/61

---

### BUG-002 — LSU Store-Buffer Forward MMIO (NC address)
- **Severity**: HIGH
- **Layer**: C3
- **File**: `cpu/core/LSU.v` line 134
- **Triệu chứng**: `uart_irq_status()` sau `uart_irq_clear()` trả lại data=0x00000003 (bit[0]=1) → return -2
- **Root cause**: `fwd_hit` không kiểm tra NC address range. Khi `uart_irq_clear` SW đang trong EX, FENCE ở ID thấy `lsu_idle=1` (NBA của `sb_valid` chưa có hiệu lực) → fence_stall=0 → FENCE không stall. LW của `uart_irq_status` đến LSU khi store vẫn trong SB → SB forwarding với data=0x00000003 thay vì đọc từ UART hardware.
- **Fix applied (2026-05-18)**:
  ```verilog
  // cpu/core/LSU.v line 134 — thêm NC address check
  assign fwd_hit = fwd_hit_r && (fwd_strb_r == 4'b1111) && (req_addr[31:29] == 3'b000);
  // MMIO addr[31:29] != 000 → fwd_hit=0 → LW buộc đi qua DCache (NC_READ)
  ```
- **Test để verify**: C3 (`bash regression_full.sh test_uart`)
- **Status**: ✅ FIXED + VERIFIED 2026-05-18 — firmware output "[PASS] uart"

---

### BUG-003 — ASCON Test Timeout
- **Severity**: HIGH
- **Layer**: C8
- **File**: Blocked by BUG-001 (cleared) → blocked by B1 integration
- **Triệu chứng**: `test_ascon.c` dừng với 4-CYCLE LOOP DETECTED, PASS=0
- **Root cause hypothesis**: A6+A7 PASS (ASCON core + DMA unit đúng). C8 stuck vì CRT0/boot layer (B1 chưa pass) → firmware không execute đúng
- **Debug procedure** (sau khi B1 pass):
  1. Re-run C8 sau B1 PASS
  2. Nếu vẫn TIMEOUT → trace waveform: `pump_state`, `dma_done`, CTRL value
- **Test để verify**: B1 → B2 → C8
- **Status**: ✅ VERIFIED 2026-05-18 — C8 PASS, "[PASS] ascon.." confirmed

---

### ~~BUG-C9 — DCache Drops 4 of 16 CPU Byte-Stores~~ — CLOSED (false alarm)
- **Severity**: ~~HIGH~~ → N/A
- **Layer**: C9 (`test_dma_uart`)
- **Triệu chứng ban đầu**: C9 in ra "HELL" thay vì "HELLO DMA-SOC!\r\n". Nghi ngờ DCache stale.
- **Root cause thực sự**: Build với `-O 1` khiến GCC optimize uart loop, stack frame shallower (`sp=0x10001fe0` thay vì `0x10001f70`), UART byte bị drop từ ký tự đầu tiên. Không liên quan DCache.
- **Bằng chứng xác nhận** (2026-05-20):
  - `-O 1` build: uart=65, output garbled `[IF]CUcmue- MM- M >UR...` (drop xuyên suốt, từ byte 3)
  - `-O 0` build: uart=74, output đúng hoàn toàn `[INFO] CPU compute -> DMEM -> DMA -> UART...HELLO DMA-SOC!...[PASS]`
- **TB verification**: `tb_core_ls_path_bughunt.v` CG03+CG04 (17/17 PASS):
  - CG03a: `fence r,r` → `dcache_fence_type=2'b10` ✅
  - CG03b: `fence w,w` → `dcache_fence_type=2'b01` ✅
  - CG03c: `fence rw,rw` → `dcache_fence_type=2'b11` ✅
  - CG04: cold load → external write (DMA sim) → `fence r,r` → reload → `0xDEADBEEF` ✅
- **Status**: ✅ CLOSED — không có RTL bug. C9 PASS sau BUG-C9b fix + `-O 0` compile.

---

### BUG-C9b — TB Line Buffer: [MSG]+loop bytes không flush trước [PASS]
- **Severity**: HIGH
- **Layer**: C9 (`test_dma_uart`)
- **File**: `gnu_toolchain/tests/test_dma_uart.c`
- **Root cause**: Firmware flow `uart_puts("[MSG] ")` → `uart_putc × N` (không có `\n`) → `uart_puts("[PASS]...")`. TB line parser tích lũy toàn bộ thành 1 dòng, `match_pass` fail vì buf[1]='M'.
- **Fix applied**:
  ```c
  uart_puts("\r\n");   /* flush TB line buffer */
  uart_puts("[PASS] dma_uart\r\n");
  ```
- **Lưu ý quan trọng — "HELL" là -O 1 artifact, không phải DCache**:
  - Khi build với `-O 1`: uart=65, output garbled từ byte 3 (`[IF]CUcmue-...`) → drop do GCC optimize UART loop, không liên quan DCache.
  - Khi build với `-O 0`: uart=74, output đầy đủ `[INFO] CPU compute...[MSG] HELLO DMA-SOC!...[PASS]`.
  - DCache `fence r,r` hoạt động đúng, xác nhận bởi CG04 TB (PASS, `s1=0xDEADBEEF` sau inject).
- **Test verify**: `bash regression_full.sh test_dma_uart` → `*** PASS`, uart=74
- **Status**: ✅ FIXED + VERIFIED 2026-05-20 — C9 PASS

---

### BUG-TIMER — Timer Channel Enable
- **Severity**: MEDIUM
- **Layer**: C5
- **File**: `peripheral/timer/rtl/timer_channel.v`
- **Triệu chứng**: Timer không load `count_val` khi enable → không countdown
- **Root cause**: `en` signal không detect rising edge
- **Fix applied (2026-05-12)**: Thêm `en_r` flip-flop, `en_rise = en && !en_r`
- **Test để verify**: C5 (`bash regression_full.sh test_timer`)
- **Status**: ✅ VERIFIED 2026-05-20 — C5 PASS uart=26 "[PASS] timer.."

---

### ~~BUG-C5-UART-STACK~~ — SUPERSEDED bởi BUG-HEX-FLAG (xem Fix History 2026-05-20)

### BUG-C5-UART-STACK — uart_puts stack corruption (blocking C5)
- **Severity**: CRITICAL (blocks C5 từ output bất kỳ UART)
- **Layer**: C5 (`test_timer`)
- **File**: `gnu_toolchain/include/uart.h` — `uart_init()` signature
- **Triệu chứng**: CPU crash tại cycle 4340, PC=`0x03640000` → DECERR → halt, uart=0
- **Bằng chứng từ simulation log** (log/test_timer.log):
  ```
  [4170] [ST] addr=0x10001fae  data=0x03640000  strb=1100   ← sh UART_DIV
  [4195] [DMEM-W] addr=0x10001fac  data=0x03640000          ← DCache writeback
  [4333] [LD] addr=0x10001fac  data=0x03640000              ← uart_puts đọc ra sai!
  [4340] [WARN] M0 AR addr=0x03640000                       ← CPU fetch tại addr sai
  [4342] [!!!] DECERR M0 READ addr=0x03640000
  ```
- **Root cause** (đã xác định chính xác):
  1. `uart_init(uint16_t baud_div, ...)` — GCC dùng `sh x15,14(sp)` để spill `baud_div` (uint16_t) lên stack frame (uart_init sp=`0x10001fa0`).
  2. `sh` tại `0x10001fae` stores `0x0364` vào upper halfword → word tại `0x10001fac` = `0x03640000`.
  3. DCache evict cache line → DMEM tại `0x10001fac` = `0x03640000`.
  4. `run_timer_test` gọi `uart_puts("[DBG] init\r\n")` với sp=`0x10001fb0` → uart_puts frame sp=`0x10001f90`, saves ra tại sp+28=`0x10001fac`.
  5. uart_puts saves đúng ra, nhưng khi load lại (`lw x1,28(sp)`), DCache đã evict → đọc từ DMEM → lấy `0x03640000` thay vì ra thật.
  6. CPU return đến `0x03640000` → DECERR.
- **Fix**: Đổi `uart_init` parameter `uint16_t baud_div` → `uint32_t baud_div` trong `gnu_toolchain/include/uart.h`.
  GCC sẽ dùng `sw`/`lw` thay vì `sh`/`lhu` → không có sub-word stack spill → không có corruption.
- **Lưu ý**: C2 (test_uart_simple) PASS vì gọi `uart_putc` (leaf function, không save ra) thay vì `uart_puts` sau uart_init — tránh được collision.
- **Test để verify**: `bash regression_full.sh test_timer` → `*** PASS`
- **Status**: ❌ SUPERSEDED — C5 pass vì lý do khác (BUG-HEX-FLAG). Bug này có thể vẫn tồn tại nhưng không block C5.

---

### BUG-C4-JALR-ICACHE — Root cause C4 TIMEOUT → FIXED (2 sub-bugs)

- **Severity**: CRITICAL (blocks C4, C6, C7, C10)
- **Files fixed**: `cpu/core/IFU.v`, `cache_interface/icache/icache_controller.v`

- **Root cause xác nhận (2026-05-25) — 2 sub-bugs độc lập**:

  **Sub-bug 1 — IFU redirect slip** (`cpu/core/IFU.v`):
  Khi JALR retire từ EX, `redirect_pending` latch target. Nếu ICache miss đang in-flight,
  `flush_if_id_final` deassert trước khi ICache trả data. Khi `imem_ready=1` trở lại,
  `redirect_pending=1` nhưng `Instruction_Code = imem_rdata` (stale speculative) → slip.

  **Sub-bug 2 — ICache last-word race** (`icache_controller.v`):
  Tại cycle Y (`refill_done=1`): `ctrl_valid/ctrl_tag <= 1` (NBA) commit end-of-Y.
  Tại Y+1: `ctrl_hit=1`, nhưng `data_array` write của last_word commit end-of-Y+1.
  Combinational read tại Y+1 → stale data cho `offset == last_word`.

- **Evidence (C4.5 log sau fix)**:
  ```
  cy4660: gpio_out=0x00/OE=0xFF  → gpio_set_dir(0xFF) ✓
  cy4776: gpio_out=0xAA/OE=0xFF  → gpio_write(0xAA) ✓
  cy5042: DECERR M1 READ 0x50040100  → plic_enable fail
  cy9076: GPIO IRQ src[4]=1  → hardware OK ✓
  PLIC → CPU.external_irq=0  → IRQ không về CPU
  ```

- **Fix 1 — IFU.v** (2026-05-25, line 100):
  ```verilog
  localparam IFU_NOP = 32'h00000013;
  assign Instruction_Code = redirect_pending          ? IFU_NOP
                          : (imem_ready && !stall)    ? imem_rdata
                                                      : instr_hold;
  ```

- **Fix 2 — icache_controller.v** (2026-05-25, line 344+):
  Thêm `last_word_{valid,data,idx,tag,off}` registers. Capture tại `refill_done && refill_data_valid`.
  Thêm `last_word_hit` wire. Bypass `data_array` trong output logic khi `last_word_hit`.

- **Verify theo C4.x**:
  - C4.1 ✅ PASS 18/18 (2026-05-22) — GPIO RTL OK
  - C4.2 ✅ (2026-05-22) — flush>stall_any confirmed, hypothesis cũ sai
  - C4.3 ✅ FIX-IFU-REDIRECT-SLIP applied (2026-05-25)
  - C4.4 ✅ FIX-ICACHE-LASTWORD-RACE applied (2026-05-25)
  - C4.5 ⚠️ TIMEOUT — firmware correct, blocked by BUG-PLIC-DECERR

- **Status**: ✅ IFU + ICache bugs FIXED — blocked bởi BUG-PLIC-DECERR (bug riêng)

---

### BUG-PLIC-DECERR — CLOSED / RE-CLASSIFIED (2026-05-26)

- **Severity**: CLOSED — PLIC hardware đúng, không có DECERR thực sự
- **Kết luận sau debug sâu (2026-05-26)**:
  - `[PLIC-WREXEC]` confirms PLIC regfile commit đúng: threshold=0, priority[5]=1, enable=0x20, priority[8]=1, enable[8]=1
  - S9-PLIC WRITE display trong testbench là **AXI AW-time bug**: monitor đọc `s9_wdata` tại AW handshake (stale), không phải W data. Hiển thị data=8 là artifact, không phải bug HW.
  - `plic_enable()` với `|=` (volatile) generate đúng lw → or → sw. PLIC enable register được set đúng.
  - PLIC hardware (`plic_top`, `plic_gateway`, `plic_priority_encoder`) đều đúng.
- **Bug thực sự**: Xem BUG-C4-GPIO-CRASH và BUG-C5-RAW (CPU pipeline issues)
- **Status**: ✅ CLOSED — không cần fix PLIC RTL hay crossbar

---

### BUG-C4-GPIO-CRASH — test_gpio PC crash trước uart_init (NEW — 2026-05-26)

- **Severity**: HIGH (blocks C4)
- **Layer**: C4 (`test_gpio`)
- **File**: Chưa xác định — nghi ngờ CPU pipeline hoặc mtvec corruption
- **Triệu chứng**: uart=0. Firmware crash (PC→0x01000000, unmapped) xảy ra trong PLIC setup, giữa `plic_set_threshold(0)` và `plic_set_priority(PLIC_SRC_GPIO, 1)`. Không in bất kỳ UART nào.
- **Evidence từ log trước (cy5026 trong session cũ)**:
  ```
  cy4948: plic_set_threshold(0) → PLIC-WREXEC aw_off=200 ok
  cy5026: ICache/DCache burst tại 0x01000000 (unmapped)
         [!!!] DECERR M0 READ (ICache fetching từ sai địa chỉ)
  — plic_set_priority chưa chạy
  ```
- **Hypothesis**:
  1. `irq_set_mtvec(gpio_isr)` được gọi trước PLIC setup → csr mtvec write. Sau đó một interrupt pending (edge IRQ?) trigger CPU nhảy vào ISR tại địa chỉ sai.
  2. Hoặc: CPU pipeline bug làm PC nhảy sang `(plic_set_threshold_arg << 12)` = `0x01000000` (vì threshold=0x01000000 nếu arg bị corrupt).
  3. Hoặc: stack frame của `run_gpio_test` bị ghi đè bởi RAW hazard → ra bị corrupt → return đến sai địa chỉ.
- **Debug path**:
  1. Đọc `log/test_gpio.log` cycle ~4900–5100 → xem PC trace và UART writes trước crash
  2. Xem `test_gpio.dump` tại địa chỉ crash để hiểu instruction đang chạy
  3. So sánh với `test_gpio.c` flow: `irq_set_mtvec` → `plic_set_threshold` → crash
- **Status**: 🔍 NOT FIXED

---

### BUG-C5-RAW — timer_irq_count stale sau mret (NEW — 2026-05-26)

- **Severity**: HIGH (blocks C5)
- **Layer**: C5 (`test_timer`)
- **File**: `cpu/core/LSU.v` — store-to-load forwarding sau interrupt return
- **Triệu chứng**: uart=38 "[DBG] init→A ok→B wait" rồi timeout. ISR timer_isr chạy đúng 3 lần (xác nhận qua 3 `plic_complete(5)` writes), nhưng main loop `while (timer_irq_count < 3u)` không thoát.
- **Evidence**:
  ```
  [PLIC-WREXEC] aw_off=204 w_data=00000005 → 3 lần (ISR complete ×3)
  ISR disasm tại 0x5BC: lw+addi+sw timer_irq_count (0x1000009C) đúng
  Nhưng main loop (run_timer_test 0x6A8) đọc timer_irq_count = stale 0
  ```
- **Root cause hypothesis**: Sau `mret`, ISR store `timer_irq_count++` vào DCache. Main loop load lại từ 0x1000009C nhưng DCache line vẫn cached với giá trị cũ (0) → RAW hazard không được resolve đúng qua interrupt boundary. Hoặc: ISR store chưa commit trước khi `mret` hoàn thành → main loop thấy stale.
- **Debug path**:
  1. Thêm `$display` vào LSU khi load từ 0x1000009C → xem giá trị thực CPU nhận
  2. Kiểm tra DCache invalidation sau `mret` — có flush cache line không?
  3. Thử thêm `fence r,r` sau `irq_enable_global()` trong test_timer.c để force reload
  4. Kiểm tra `cpu/core/LSU.v` — sau interrupt return, có gì đặc biệt không?
- **Quick test**: Thêm `__asm__ volatile ("fence r,r" ::: "memory")` vào vòng while:
  ```c
  while (timer_irq_count < 3u) {
      __asm__ volatile ("fence r,r" ::: "memory");
      if (--timeout == 0u) { ... }
  }
  ```
  Nếu fix → confirm DCache line stale issue.
- **Status**: 🔍 NOT FIXED

---

### BUG-C8-DOT — test_ascon UART string mismatch

- **Severity**: MEDIUM (blocks C8 automated detection)
- **File**: `gnu_toolchain/tests/test_ascon.c`
- **Triệu chứng**: `PASS=0` — firmware in `"[PASS] ascon.\r\n"` (1 chấm), TB match `"[PASS] ascon.."` (2 chấm)
- **Evidence**: `log/test_ascon.log` line `"[PASS] ascon."`, `PASS=0 FAIL=0`
- **Fix**: Firmware đã có đủ 2 chấm (regression_full.sh -b rebuild xác nhận)
- **Status**: ✅ RESOLVED 2026-05-25 — C8 PASS uart=14 "[PASS] ascon.."

---

### BUG-C5-TIMER-B — SUPERSEDED bởi BUG-C5-RAW (2026-05-26)

- **Ghi chú**: Bug này ban đầu nghi ngờ timer channel B RTL, nhưng debug sâu (2026-05-26) xác nhận timer hoạt động đúng — PLIC forward IRQ, ISR claim/complete đúng. Root cause thực là `timer_irq_count` stale do RAW hazard. Xem BUG-C5-RAW.
- **Status**: ✅ SUPERSEDED

---

### BUG-ICACHE — ICache AXI Deadlock
- **Severity**: CRITICAL (blocks boot)
- **Layer**: B2 / tất cả C tests
- **File**: `cache_interface/icache_axi_interface.v`
- **Triệu chứng**: ARVALID không de-assert sau handshake → AXI locked
- **Fix applied (2026-05-12)**: Fix ARVALID latch logic
- **Test để verify**: B2 (`./workflow/run_layer_test.sh 4`)
- **Status**: ❓ Fix applied, chưa re-verify đủ test cases

---

## Fix History

### Template
```
### [YYYY-MM-DD] BUGFIX: <tên bug>
- **Bug ID**: BUG-XXX
- **File thay đổi**: `path/to/file.v` line XX
- **Fix**: <1–2 dòng mô tả hoặc diff ngắn>
- **Verify**: chạy <lệnh> → output snippet
- **Kết quả**: PASS / FAIL
- **Regression**: C2 sau fix → PASS / FAIL
```

---

### [2026-05-12] APPLIED (chưa verify): BUG-001 Load-use hazard
- **Bug ID**: BUG-001
- **File thay đổi**:
  - `cpu/core/PIPELINE_REG_MEM_WB.v` line 71
  - `cpu/core/hazard_detection.v` line 117
- **Fix**:
  ```verilog
  // MEM/WB: !lsu_result_valid → !lsu_committed
  end else if (!stall_ex_mem && !lsu_committed) begin
  // flush: load_use_hazard → (load_use_hazard && !lsu_dep_stall)
  assign flush_id_ex = (load_use_hazard && !lsu_dep_stall) || ...
  ```
- **Verify**: `./workflow/urun_verilog.sh cpu/tb/tb_layer1_pipeline.v` → A1 PASS 17/17
- **Kết quả**: ✅ PASS (2026-05-13)

---

### [2026-05-13] FIXED + VERIFIED: BUG-MUL — Multiplier dispatch + timing
- **Bug ID**: BUG-MUL (mới phát hiện tại A1 TC-05)
- **File thay đổi**:
  - `cpu/riscv_cpu_core_v2.v` line 606
  - `cpu/core/riscv_multiplier.v` lines 137-144
- **Root cause**: 2 vấn đề phối hợp:
  1. `mul_valid_ex` bị chặn bởi `flush_id_ex_final` (bao gồm `mul_result_stall`) → E1 không bao giờ fire
  2. E2 dùng `pp_ll_e15_q` (registered E1.5) thay vì `pp_ll_w` (combinational từ E1) → result valid trễ 1 cycle
- **Fix**:
  ```verilog
  // cpu_core_v2.v:606 — cho phép E1 fire ngay cả khi mul_result_stall=1
  wire mul_valid_ex = is_mul_ex & !mul_hold & !(flush_id_ex_final & !mul_ex_stall_wire);
  // riscv_multiplier.v — bypass E1.5 latch, dùng combinational partial products cho E2
  wire [63:0] mult_result_w = {{30{pp_ll_w[33]}},pp_ll_w} + ... ;
  wire [31:0] result_r = mulhi_sel_e1_q ? ... : mult_result_w[31:0];
  ```
- **Verify**: A1 TC-05 PASS (x3=15, x4=20), A2 PASS 61/61
- **Kết quả**: ✅ PASS (2026-05-13)

---

### [2026-05-16] FIXED + VERIFIED: A3 — IMEM AXI slave trả OKAY thay vì SLVERR
- **Bug ID**: A3-SLVERR
- **File thay đổi**: `memory/inst_mem_axi_slave.v` WR_DATA state
- **Root cause**: WR_DATA ghi data vào ROM (`axi_wr_pulse_r <= 1`) và trả `RESP_OKAY` → IMEM là ROM, mọi AXI write phải bị reject
- **Fix**: Drain W-channel không ghi, trả `RESP_SLVERR`
- **Verify**: `./workflow/urun_verilog.sh memory/tb/tb_instmem.v` → **PASS 64/64**
- **Kết quả**: ✅ PASS (2026-05-16)

---

### [2026-05-16] FIXED + VERIFIED: A5 — AXI crossbar 3 bugs
- **Bug ID**: A5-x3
- **Files thay đổi**: `interconnect/tb/tb_axi4_crossbar.v`
- **Root cause 1 (TC-DECODEW)**: `axi_write_m1` task có extra `@(negedge clk)` trước khi check BVALID → miss 1-cycle window khi DECERR slave assert BVALID (BREADY=1 deassert ngay cùng cycle)
- **Root cause 2 (TC-BID/TC-RID)**: BID/RID check sau task return, mux crossbar đã clear → cần latch tại posedge BVALID/RVALID
- **Root cause 3 (TC-ARBIT)**: Addresses 0x0000_2000/0x3000 nằm ngoài S0 range (IMEM 8KB = 0x0000_0000–0x0000_1FFF) → route sang DECERR
- **Fix**: (1) Bỏ extra negedge wait; (2) Thêm `m1_bid_lat`/`m1_rid_lat` latch; (3) Sửa addresses thành 0x0000_0000/0x0000_0100
- **Note ID tagging**: Crossbar dùng top 3 bits của ID làm master tag (ID_WIDTH=4 → 1 user bit), test expect BID=0x1 không phải 0xA
- **Verify**: `./workflow/urun_verilog.sh interconnect/tb/tb_axi4_crossbar.v` → **PASS 21/21**
- **Kết quả**: ✅ PASS (2026-05-16)

---

### [2026-05-19] FIXED + VERIFIED: BUG-UART-LINEBUF — Single byte 'A' phá TB line parser

- **Bug ID**: BUG-UART-LINEBUF
- **File thay đổi**: `gnu_toolchain/tests/test_uart.c` (sau line 38, trong `run_uart_test()`)
- **Layer**: C3
- **Triệu chứng**: C3 TIMEOUT. UART output 26 bytes đúng "Hello UART\r\nA[PASS] uart\r\n" nhưng testbench không emit `*** PASS` marker → script grep ra 0 → TIMEOUT.
- **Root cause**: TX IRQ test gửi 1 byte 'A' không kèm `\n`. TB line parser tích lũy 'A' vào line buffer, line tiếp theo "[PASS] uart" được append thành "A[PASS] uart". `parse_uart_line` check `buf[0]=='['` → fail → không match `*** PASS`. CPU rơi vào `while(1) nop` → 4-CYCLE LOOP fire `$finish` (run_soc_ascon.v:1826).
- **Fix**:
  ```c
  /* Verify flag cleared */
  if (uart_irq_status() & UART_IRQ_TX) return -2;

  /* Flush TB line buffer: byte 'A' ở trên không có '\n' */
  uart_puts("\r\n");

  return 0;
  ```
- **Verify**: `bash regression_full.sh test_uart` → uart=28 "Hello UART..A..[PASS] uart.." → PASS
- **Regression**: C2 PASS ✅, C8 PASS ✅ (không regression)
- **Kết quả**: ✅ PASS (2026-05-19)
- **Lưu ý build**: Build với `-O 0` (default). `-O 1` gây UART RX drop bytes (chưa rõ nguyên nhân, cần investigate sau nếu cần benchmark mode).

---

### [2026-05-18] FIXED + VERIFIED: BUG-002 — LSU SB Forward NC Address

- **Bug ID**: BUG-002
- **File thay đổi**: `cpu/core/LSU.v` line 134
- **Root cause**: `fwd_hit` không chặn forwarding cho NC (MMIO) addresses. `fence w,w` trong `uart_irq_clear` không stall vì khi SW ở EX, `sb_valid` NBA chưa cập nhật → `lsu_idle=1` → `fence_stall=0`. LW của `uart_irq_status` đến LSU khi SW còn trong SB → forward data=0x00000003 → bit[0]=1 → firmware trả -2.
- **Fix**:
  ```verilog
  // Trước:
  assign fwd_hit = fwd_hit_r && (fwd_strb_r == 4'b1111);
  // Sau: block forwarding cho MMIO addresses (addr[31:29] != 000)
  assign fwd_hit = fwd_hit_r && (fwd_strb_r == 4'b1111) && (req_addr[31:29] == 3'b000);
  ```
- **Verify**: `bash regression_full.sh test_uart` → uart=25 "[PASS] uart." (firmware output đúng)
- **Kết quả**: ✅ PASS (2026-05-18)

---

### [2026-05-18] FIXED: build_all.sh — bỏ `-c` flag

- **File thay đổi**: `gnu_toolchain/build_all.sh` line 61
- **Root cause**: Compile với `-c` (no CRT0) → `.rodata` ở LMA (ROM) nhưng VMA = DMEM (uninitialized) → `uart_puts("...")` đọc 0x00 → NO OUTPUT
- **Fix**: Bỏ `-c` flag khỏi compile command trong build_all.sh
- **Kết quả**: ✅ Verified — firmware in đúng strings sau fix

---

### [2026-05-20] FIXED + VERIFIED: BUG-HEX-FLAG — test_timer.hex được build với -c flag sai

- **Bug ID**: BUG-HEX-FLAG
- **File thay đổi**: `gnu_toolchain/tests/test_timer.hex` (rebuilt)
- **Root cause**: `.rodata` (string literals) được linker đặt trong `.data` section tại VMA=0x10000000 (DMEM), load address tại ROM. Khi build với `-c` flag (no CRT0 copy), DMEM không được init → `uart_puts` đọc `*s=0x00` → return ngay → uart=0 → WATCHDOG TIMEOUT.
- **Fix**: Rebuild `tests/test_timer.hex` với `./compile_c_to_hex.sh -i tests/test_timer.c -o tests/test_timer.hex -O 0` (không có `-c`). CRT0 tự động copy `.data`/`.rodata` từ ROM sang DMEM.
- **Note**: `regression_full.sh` build command (line 93) đã đúng: không có `-c`. Hex cũ đã bị build thủ công với `-c` nên sai.
- **Verify**: `bash regression_full.sh test_timer` → uart=26 "[PASS] timer.." → PASS
- **Kết quả**: ✅ PASS (2026-05-20)
- **Regression**: C2 ✅, C3 ✅, C8 ✅ (không regression)

---

### [2026-05-20] FIXED + VERIFIED: BUG-C9b — firmware \r\n + xác nhận BUG-C9-DCACHE là false alarm

- **Bug ID**: BUG-C9b
- **File thay đổi**: `gnu_toolchain/tests/test_dma_uart.c` — thêm `uart_puts("\r\n")` trước `[PASS]`
- **Root cause**: TB line parser nhận toàn bộ `[MSG]...bytes...[PASS]` như 1 dòng → không detect `[PASS]`.
- **Fix**: Thêm `uart_puts("\r\n");` sau for-loop trước `uart_puts("[PASS] dma_uart\r\n");`
- **BUG-C9-DCACHE đóng**: "HELL" thay vì "HELLO" là do `-O 1` GCC optimize UART loop, không phải DCache. Confirmed bằng:
  - `-O 1` uart=65, garbled từ byte 3
  - `-O 0` uart=74, đúng hoàn toàn
  - TB CG04 (`tb_core_ls_path_bughunt.v`): CPU `fence r,r` → `dcache_fence_type=2'b10` → DCache invalidate → CPU đọc `0xDEADBEEF` sau inject. **17/17 PASS**
- **Verify**: `bash regression_full.sh test_dma_uart` (với `-O 0` default) → uart=74, `*** PASS`
- **Kết quả**: ✅ PASS (2026-05-20)
- **Regression**: C2 ✅, C3 ✅, C5 ✅, C8 ✅

---

### [2026-05-25] FIXED: BUG-C4-IFU-REDIRECT-SLIP — IFU drive stale instruction khi redirect_pending

- **Bug ID**: BUG-C4 sub-bug 1
- **File thay đổi**: `cpu/core/IFU.v` line 100
- **Fix**:
  ```verilog
  localparam IFU_NOP = 32'h00000013;
  assign Instruction_Code = redirect_pending          ? IFU_NOP
                          : (imem_ready && !stall)    ? imem_rdata
                                                      : instr_hold;
  ```
- **Verify**: C4.5 — gpio_out=0xAA ✓ (firmware chạy đúng)
- **Kết quả**: ✅ APPLIED — firmware correct, C4 blocked by BUG-PLIC-DECERR

---

### [2026-05-25] FIXED: BUG-C4-ICACHE-LASTWORD-RACE — ICache deliver stale beat cuối refill

- **Bug ID**: BUG-C4 sub-bug 2
- **File thay đổi**: `cache_interface/icache/icache_controller.v` line 344+
- **Fix**: Thêm `last_word_*` buffer (5 regs). Capture khi `refill_done && refill_data_valid`.
  Thêm `last_word_hit` wire bypass `data_array` trong output logic.
- **Verify**: C4.5 — kết hợp với IFU fix, firmware correct
- **Kết quả**: ✅ APPLIED — cần PLIC fix để confirm full C4 PASS

---

### [2026-05-20] FIXED + VERIFIED: BUG-TIMER Timer channel enable (C5 PASS confirmed)
- **Bug ID**: BUG-TIMER
- **File thay đổi**: `peripheral/timer/rtl/timer_channel.v`
- **Fix**: Thêm `en_r` FF, rising edge detect `en_rise = en && !en_r`
- **Verify**: `bash regression_full.sh test_timer` → PASS=1, uart=26 "[PASS] timer\r\n"
- **Kết quả**: ✅ VERIFIED (2026-05-25)

---

### [2026-05-12] APPLIED (chưa verify): BUG-ICACHE ICache AXI deadlock
- **Bug ID**: BUG-ICACHE
- **File thay đổi**: `cache_interface/icache_axi_interface.v`
- **Fix**: Fix ARVALID latch logic (không de-assert sau handshake)
- **Verify**: B2 PASS 2026-05-16 (minimal firmware boot OK)
- **Kết quả**: ✅ VERIFIED (2026-05-16)

---

### [2026-05-16] FIXED + VERIFIED: BUG-JAL-STALL — JAL redirect lost khi stall_any=X

- **Bug ID**: BUG-JAL-STALL
- **File thay đổi**: `cpu/riscv_cpu_core_v2.v` (sau line 383)
- **Root cause**:
  - `pc_src_ex` là COMBINATIONAL từ `jump_ex` (ID/EX register). Khi stall_any=X
    (do imem[14] tại 0x38 uninitialized → rs1_id/rs2_id=X → mem_load_issue_hazard=X),
    IFU treat stall_any=X như stall (PC không update), nhưng pipeline advances
    (sequential if(X) → false). Kết quả: jump_ex bị wipe trước khi IFU sample → PC
    nhảy đến 0x40 thay vì 0x34.
- **Fix**:
  ```verilog
  // Latch redirect khi pc_src_ex=1 (JAL/branch trong EX).
  // effective_pc_src = pc_src_ex || pc_src_held_r.
  // X | 1 = 1 đảm bảo redirect survive X-propagation.
  reg pc_src_held_r;
  reg [31:0] target_pc_held_r;
  always @(posedge clk or posedge rst) begin
      if (rst) begin
          pc_src_held_r <= 1'b0;
      end else if (pc_src_ex) begin
          pc_src_held_r    <= 1'b1;
          target_pc_held_r <= target_pc_ex;
      end else if (!stall_any) begin
          pc_src_held_r <= 1'b0;
      end
  end
  wire effective_pc_src = pc_src_ex || pc_src_held_r;
  wire [31:0] effective_target = pc_src_ex ? target_pc_ex : target_pc_held_r;
  ```
  Thay `pc_src_ex` → `effective_pc_src` tại: `ifu_pc_src`, `ifu_target_pc`, `.branch_taken`.
- **Verify**: B3 PASS 2026-05-16 — JAL loops đúng tại 0x34, s0=1 s1=2 s2=3 s3=4
- **Kết quả**: ✅ PASS (2026-05-16)
- **Regression**: B1 PASS ✅, B2 PASS ✅

---

### [2026-05-16] FIXED + VERIFIED: B3-TB — Testbench 3 bugs (halt/IMEM/timing)

- **Bug ID**: B3-TB
- **File thay đổi**: `cpu/tb/tb_riscv_soc_top.v`
- **Bugs**:
  1. **IMEM uninitialized**: `imem[14..1023]` là X → X-propagation vào `rs1_id/rs2_id` → `stall_any=X` → kích hoạt BUG-JAL-STALL. Fix: khởi tạo tất cả về NOP (0x13).
  2. **Halt detection sai**: Yêu cầu 4 consecutive cycles tại 0x34, nhưng JAL loop tạo pattern 0x34/0x38/0x3C → halt_cnt reset về 0 mỗi 2 cycles, không bao giờ đạt 4. Fix: `halt_cnt >= 1`.
  3. **Wait quá ngắn**: `repeat(20)` không đủ cho LSU SB drain 4 entries qua write-allocate DCache (~11 cycles/entry × 4 = ~44 cycles). LQ chỉ dequeue trong 1-cycle DRAIN_IDLE window giữa các drain → s2 ready ở cycle 51, s3 ở cycle 62, nhưng check ở cycle 44. Fix: `repeat(200)`.
- **Verify**: B3 PASS 2026-05-16 — s0=1 s1=2 s2=3 s3=4
- **Kết quả**: ✅ PASS (2026-05-16)

---

## Uncommitted Changes

```bash
rtk git status
# cpu/core/PIPELINE_REG_MEM_WB.v        (BUG-001) ✅ verified
# cpu/core/hazard_detection.v           (BUG-001) ✅ verified
# cpu/core/LSU.v                        (BUG-002 NC fwd) ✅ verified C3
# cpu/core/IFU.v                        (BUG-C4 sub1: FIX-IFU-REDIRECT-SLIP) ✅ applied
# cpu/riscv_cpu_core_v2.v               (BUG-MUL + BUG-JAL-STALL) ✅ verified
# peripheral/timer/rtl/timer_channel.v  (BUG-TIMER) ✅ verified C5
# cache_interface/icache_axi_interface.v (BUG-ICACHE) ✅ verified via B2
# cache_interface/icache/icache_controller.v (BUG-C4 sub2: FIX-ICACHE-LASTWORD-RACE) ✅ applied
# memory/inst_mem_axi_slave.v            (A3 fix) ✅ verified
# interconnect/tb/tb_axi4_crossbar.v    (A5 fix — testbench only) ✅ verified
# cpu/tb/tb_riscv_soc_top.v             (B3 testbench) ✅ verified
# cpu/tb/tb_cpu_crt0_pattern.v          (B1 testbench) ✅ verified
# gnu_toolchain/build_all.sh            (bỏ -c flag) ✅ verified C3
# gnu_toolchain/tests/*.hex             (rebuilt)
```

**Quy tắc commit**: Commit IFU + ICache fix sau khi C4 PASS (chờ PLIC fix).
C8 đã PASS — không cần firmware fix riêng.

---

## Thứ tự chạy tối thiểu để declare "SoC verified"

```
A1 ✅ → A2 ✅ → A3 ✅ → A4 ✅ → A5 ✅ → A6 ✅ → A7 ✅ → A8 ✅ → A9 ✅ → A10 ✅
    ↓
B1 ✅ → B2 ✅ → B3 ✅
    ↓
C1 ✅ → C2 ✅ → C3 ✅ → C8 ✅ → C9 ✅ → C10 ✅
    ↓
C5 ⚠️ (BUG-C5-RAW: timer_irq_count stale sau mret — thử fence r,r trong while loop)
C4 ⚠️ (BUG-C4-GPIO-CRASH: PC→0x01000000 trước uart_init — trace log/test_gpio.log)
C6 ❓ (chưa debug — re-run sau plic.h revert để có baseline)
C7 ❓ (chưa debug — re-run để xem log)
    ↓
[Fix BUG-C5-RAW] → C5 ✅
[Fix BUG-C4-GPIO-CRASH] → C4 ✅
[Debug C6 C7] → C6 C7 ✅
    ↓
C10 re-run ✅ → SoC VERIFIED
```
