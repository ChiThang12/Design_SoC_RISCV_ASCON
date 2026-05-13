# Test Task — Status & Bug Tracker

## Cách dùng
- Đọc "Current Sprint" để biết đang làm gì.
- Sau mỗi test → cập nhật status table.
- Sau mỗi fix → ghi vào Fix History với kết quả verify thực tế.
- Chỉ ghi kết quả đã chạy simulation, không ghi assumption.

---

## Current Sprint (2026-05-13)

**Focus bug**: BUG-001 ✅ VERIFIED + BUG-MUL ✅ FIXED (2026-05-13)
**Layer hiện tại**: A1 ✅ PASS, A2 ✅ PASS — tiếp tục B1
**Bước tiếp theo**:
```
1. ✅ A1 PASS 17/17 (2026-05-13)
2. ✅ A2 PASS 61/61 (2026-05-13)
3. Chạy B1: ./workflow/run_layer_test.sh 2
4. Nếu B1 PASS → chạy B2 (run_layer_test.sh 4)
5. Nếu B2 PASS → chạy C2 (regression test_uart_simple) để confirm không regression
6. Tiếp tục leo thang lên C3, C4, ...
```

---

## Status Table

| ID | Test | Module | Lần cuối chạy | Kết quả | Ghi chú |
|----|------|--------|--------------|---------|--------|
| A1 | tb_layer1_pipeline | CPU pipeline | 2026-05-13 | ✅ PASS 17/17 | BUG-001 + BUG-MUL fixed |
| A2 | tb_riscv_cpu_core_v2 | CPU core full | 2026-05-13 | ✅ PASS 61/61 | All 15 TC passed |
| A3 | tb_instmem | IMEM AXI | chưa chạy | ❓ | — |
| A4 | tb_datamem | DMEM AXI | chưa chạy | ❓ | — |
| A5 | tb_axi4_crossbar | AXI crossbar | chưa chạy | ❓ | — |
| A6 | ascon_top_tb | ASCON core | session cũ | ❓ | Cần re-verify |
| A7 | tb_multi_block_dma | ASCON+DMA | session cũ | ❓ | Cần re-verify |
| A8 | tb_dma_top | GP-DMA | chưa chạy | ❓ | — |
| A9 | tb_plic_top | PLIC | chưa chạy | ❓ | — |
| A10 | tb_soc_ctrl_slave | SoC ctrl | chưa chạy | ❓ | — |
| B1 | layer2 CRT0 hazard | CPU+DCache | chưa chạy | ❓ | Blocked: A1 chưa pass |
| B2 | layer4 ICache boot | ICache+IMEM | 2026-05-12 | ⚠️ | Fix ICache deadlock applied |
| B3 | layer3 DCache | DCache+DMEM | chưa chạy | ❓ | Blocked: B1 chưa pass |
| C1 | test_crt0_verify | Boot+CRT0 | N/A | 🚫 | Firmware chưa tạo |
| C2 | test_uart_simple | UART TX basic | 2026-05-12 | ✅ PASS | Baseline |
| C3 | test_uart | UART IRQ W1C | 2026-05-12 | ❌ FAIL -2 | W1C không clear |
| C4 | test_gpio | GPIO+IRQ | 2026-05-12 | ⚠️ TIMEOUT | PC stuck |
| C5 | test_timer | Timer IRQ | 2026-05-12 | ⚠️ TIMEOUT | BUG-TIMER fix applied |
| C6 | test_clint | CLINT | 2026-05-12 | ⚠️ TIMEOUT | PC stuck |
| C7 | test_plic | PLIC routing | 2026-05-12 | ⚠️ TIMEOUT | PC stuck |
| C8 | test_ascon | ASCON DMA | 2026-05-12 | ⚠️ TIMEOUT | Blocked BUG-001 |
| C9 | test_dma_uart | GP-DMA | 2026-05-12 | ⚠️ TIMEOUT | PC stuck |
| C10 | test_integration | All IPs | 2026-05-12 | ⚠️ TIMEOUT | Blocked C2–C9 |

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

### BUG-002 — UART TX IRQ W1C Không Clear
- **Severity**: HIGH
- **Layer**: C3
- **File**: Chưa xác định — có thể là:
  - `peripheral/uart/rtl/uart_regs.v` (hoặc tên tương đương): W1C register logic
  - DCache NC bypass: 0x50000000 range có được bypass không?
- **Triệu chứng**: Sau W1C write tới 0x50000014, đọc lại vẫn thấy bit TX=1 → return -2
- **Root cause**: Chưa investigate
- **Debug procedure**:
  1. Kiểm tra UART RTL: W1C write có de-assert `irq_status[0]` không?
  2. Nếu RTL đúng → kiểm tra DCache: read từ 0x50000014 có bypass cache không?
  3. Trace waveform: signal `uart_irq_status` tại cycle sau W1C write
- **Test để verify**: C3 (`bash regression_full.sh test_uart`)
- **Status**: ❌ FAIL -2, root cause chưa xác định

---

### BUG-003 — ASCON Test Timeout
- **Severity**: HIGH
- **Layer**: C8
- **File**: Blocked by BUG-001
- **Triệu chứng**: `test_ascon.c` không complete trong 0x3FFFFF cycles
- **Root cause hypothesis**: CRT0 corrupt firmware buffer (BUG-001) → key/nonce sai → ASCON hung
- **Debug procedure** (sau khi BUG-001 fix):
  1. Chạy A6 (ASCON unit test) — verify core đúng độc lập
  2. Chạy A7 (multi-block DMA) — verify DMA pipeline
  3. Nếu A6+A7 pass nhưng C8 vẫn TIMEOUT → trace waveform: `pump_state`, `dma_done`, CTRL value
- **Test để verify**: A6 → A7 → C8
- **Status**: ⚠️ Blocked by BUG-001

---

### BUG-TIMER — Timer Channel Enable
- **Severity**: MEDIUM
- **Layer**: C5
- **File**: `peripheral/timer/rtl/timer_channel.v`
- **Triệu chứng**: Timer không load `count_val` khi enable → không countdown
- **Root cause**: `en` signal không detect rising edge
- **Fix applied (2026-05-12)**: Thêm `en_r` flip-flop, `en_rise = en && !en_r`
- **Test để verify**: C5 (`bash regression_full.sh test_timer`)
- **Status**: ❓ Fix applied, chưa verify

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

### [2026-05-12] APPLIED (chưa verify): BUG-TIMER Timer channel enable
- **Bug ID**: BUG-TIMER
- **File thay đổi**: `peripheral/timer/rtl/timer_channel.v`
- **Fix**: Thêm `en_r` FF, rising edge detect `en_rise = en && !en_r`
- **Verify**: CHƯA CHẠY — cần C5 pass
- **Kết quả**: ❓ Pending

---

### [2026-05-12] APPLIED (chưa verify): BUG-ICACHE ICache AXI deadlock
- **Bug ID**: BUG-ICACHE
- **File thay đổi**: `cache_interface/icache_axi_interface.v`
- **Fix**: Fix ARVALID latch logic (không de-assert sau handshake)
- **Verify**: CHƯA CHẠY đầy đủ — cần B2 pass
- **Kết quả**: ❓ Partial — C2 đã PASS nhưng cần verify B2 isolated

---

## Uncommitted Changes

```bash
rtk git status
# cpu/core/PIPELINE_REG_MEM_WB.v
# cpu/core/hazard_detection.v
# peripheral/timer/rtl/timer_channel.v
# cache_interface/icache_axi_interface.v
# gnu_toolchain/tests/*.hex  (rebuilt)
```

**Quy tắc commit**: Không commit cho đến khi A1 + A2 + B1 PASS.
Sau khi A1/A2/B1 pass → commit riêng từng bug fix với message rõ ràng.

---

## Thứ tự chạy tối thiểu để declare "SoC verified"

```
A1 ✅ → A2 ✅ → A6 ✅ → A7 ✅ → A8 ✅ → A9 ✅
    ↓
B1 ✅ → B2 ✅ → B3 ✅
    ↓
C1 ✅ → C2 ✅ → C3 ✅ → C4 ✅ → C5 ✅ → C6 ✅ → C7 ✅ → C8 ✅ → C9 ✅
    ↓
C10 ✅  →  SoC VERIFIED
```
