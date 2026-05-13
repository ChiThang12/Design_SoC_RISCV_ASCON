# Task Debug — Lịch sử Fix & Kết quả
> **SUPERSEDED**: File này đã được thay thế bởi `test_task.md` (20 test IDs, bug tracker đầy đủ).
> Giữ lại để tham khảo lịch sử fix cũ.


## Cách dùng
- Mỗi khi fix bug và verify pass → agent ghi vào đây
- Format: [DATE] LAYER — BUG-ID — MÔ TẢ — KẾT QUẢ
- Không ghi assumption, chỉ ghi kết quả đã verify bằng simulation

---

## Template ghi task

```
### [YYYY-MM-DD] BUGFIX: <tên bug>
- **Layer**: L<N>
- **Bug ID**: BUG-XXX
- **File thay đổi**: `path/to/file.v` line XX
- **Root cause**: <1 câu>
- **Fix**: <diff ngắn hoặc mô tả thay đổi>
- **Verify**: chạy `./workflow/run_layer_test.sh <N>` → output
- **Kết quả**: PASS / FAIL
- **Side effect**: <có ảnh hưởng gì đến layer khác không>
```

---

## Lịch sử

### [2026-05-12] APPLIED (chưa verify): Load-use hazard fix
- **Layer**: L1/L2 (cần verify)
- **Bug ID**: BUG-001
- **File thay đổi**:
  - `cpu/core/PIPELINE_REG_MEM_WB.v` line 71
  - `cpu/core/hazard_detection.v` line 117
- **Root cause**:
  - MEM/WB dùng `!lsu_result_valid` thay vì `!lsu_committed` → ghi đè load data sau 1 cycle
  - `flush_id_ex` không check `!lsu_dep_stall` → double-flush khi cả 2 stall đồng thời
- **Fix**:
  ```verilog
  // PIPELINE_REG_MEM_WB.v:71 — trước: !lsu_result_valid, sau:
  end else if (!stall_ex_mem && !lsu_committed) begin

  // hazard_detection.v:117 — trước: load_use_hazard ||, sau:
  assign flush_id_ex = (load_use_hazard && !lsu_dep_stall) || ...
  ```
- **Verify**: CHƯA CHẠY isolated test
- **Kết quả**: ❓ Pending — cần chạy L1 test
- **Side effect**: Chưa biết

---

### [2026-05-12] APPLIED (chưa verify): Timer channel fix
- **Layer**: L6 (timer peripheral)
- **Bug ID**: BUG-TIMER
- **File thay đổi**: `peripheral/timer/rtl/timer_channel.v`
- **Root cause**: `en` signal không detect rising edge → không load count_val khi enable
- **Fix**: Thêm `en_r` flip-flop, `en_rise = en && !en_r`, load count_val khi `en_rise`
- **Verify**: CHƯA CHẠY
- **Kết quả**: ❓ Pending

---

## Layer Status Summary

| Layer | Test | Lần cuối chạy | Kết quả |
|-------|------|--------------|---------|
| L1 — CPU standalone | tb_riscv_cpu_core_v2.v | chưa chạy | ❓ |
| L2 — CRT0 pattern | tb_cpu_crt0_pattern.v | chưa có | ❌ TB chưa tạo |
| L3 — DCache | tb_riscv_soc_top.v | chưa chạy | ❓ |
| L4 — ICache | run_soc_ascon.v | session cũ | ⚠️ Fix applied |
| L5 — Full SoC CRT0 | run_soc_ascon.v | session hiện tại | ❌ Wrong output |
| L6a — UART simple | regression | session cũ | ✅ PASS |
| L6b — UART IRQ | regression | session cũ | ❌ FAIL -2 |
| L6c — ASCON | regression | session hiện tại | ❌ TIMEOUT |

---

## Uncommitted Changes (cần commit khi L1 pass)

```bash
git diff --stat
# cpu/core/PIPELINE_REG_MEM_WB.v
# cpu/core/hazard_detection.v
# peripheral/timer/rtl/timer_channel.v
# gnu_toolchain/tests/*.hex  (rebuilt)
```

**Không commit** cho đến khi ít nhất L1 và L2 pass.
