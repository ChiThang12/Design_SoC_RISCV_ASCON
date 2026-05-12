# SoC Debug Plan — Layer-by-Layer

## Mục đích
File này dùng cho AI agent đọc để biết:
- Đang debug layer nào
- Test case nào cần chạy
- Pass criteria của từng layer
- Trạng thái hiện tại

## Quy tắc bắt buộc cho AI agent

> **QUAN TRỌNG**: Khi phát hiện lỗi, agent PHẢI báo cáo ngắn gọn cho user trước
> (1–2 dòng: "Phát hiện lỗi X tại Y") rồi hỏi user có muốn phân tích sâu không.
> KHÔNG tự phân tích dài trước khi hỏi.

> **Thứ tự**: Fix Layer N xong, pass, rồi mới lên Layer N+1. Không skip.

---

## Tổng quan các Layer

| Layer | Tên | Testbench | Trạng thái |
|-------|-----|-----------|-----------|
| L1 | CPU Pipeline standalone | `cpu/tb/tb_riscv_cpu_core_v2.v` | ❓ Cần verify |
| L2 | CPU + CRT0 assembly pattern | `cpu/tb/tb_cpu_crt0_pattern.v` (tạo mới) | ❌ Chưa có |
| L3 | CPU + DCache + DMEM via AXI | `cpu/tb/tb_riscv_soc_top.v` | ❓ Cần verify |
| L4 | CPU + ICache + IMEM via AXI | trong SoC tb (boot sequence) | ❓ Cần verify |
| L5 | Full SoC + minimal firmware | `run_soc_ascon.v` với hex đơn giản | ❓ Cần verify |
| L6a | SoC + UART peripheral | `regression_full.sh test_uart_simple` | ⚠️ Đang lỗi |
| L6b | SoC + UART IRQ | `regression_full.sh test_uart` | ❌ FAIL -2 |
| L6c | SoC + ASCON DMA | `regression_full.sh test_ascon` | ❌ FAIL TIMEOUT |

---

## Layer 1 — CPU Pipeline Standalone

**Mục tiêu**: Verify pipeline hazard handling không cần cache, không cần AXI.

**Testbench**: `cpu/tb/tb_riscv_cpu_core_v2.v`
**Chạy**: `./workflow/run_layer_test.sh 1`
**Log output**: `log/layer1_cpu.log`

### Test cases (theo thứ tự)

#### TC-1A: ALU basic + register forwarding
```asm
addi x1, x0, 5      # x1 = 5
addi x2, x0, 3      # x2 = 3
add  x3, x1, x2     # x3 = 8 (EX→EX forward từ x1, x2)
add  x4, x3, x1     # x4 = 13 (EX→EX forward từ x3)
```
**Check**: x3=8, x4=13 sau cycle ổn định

#### TC-1B: Load-use hazard (QUAN TRỌNG — đây là bug hiện tại)
```asm
sw x1, 0(x6)         # store 5 vào dmem[0]
lw x7, 0(x6)         # load x7 = 5
add x8, x7, x2       # HAZARD: dùng x7 ngay sau lw
```
**Check**: x8 = 5+3 = 8 (không phải 3 = 0+3)
**Bug nếu sai**: load-use hazard không stall đúng hoặc forwarding lsu→EX sai

#### TC-1C: Load-use hazard kiểu CRT0 (_copy_data pattern)
```asm
# Mô phỏng: lw x28, 0(x5) → sw x28, 0(x6)
lw  x28, 0(x5)       # load từ source
sw  x28, 0(x6)       # store ngay sau — HAZARD
lw  x28, 4(x5)       # tiếp tục loop
sw  x28, 4(x6)       # HAZARD tiếp
```
**Check**: dmem[x6] == dmem[x5], dmem[x6+4] == dmem[x5+4]

#### TC-1D: MUL hazard
```asm
mul  x5, x1, x2      # x5 = 5*3 = 15
add  x6, x5, x1      # phải stall chờ MUL
```
**Check**: x6 = 20

#### TC-1E: Branch misprediction flush
```asm
addi x1, x0, 1
beq  x1, x0, skip    # NOT taken (predict taken vì backward? hoặc forward)
addi x2, x0, 99      # phải execute
skip:
addi x3, x0, 7
```
**Check**: x2=99, x3=7

### Pass criteria L1
```
[L1-PASS] ALL TC-1A through TC-1E: register values correct
```
Nếu bất kỳ TC nào fail → DỪNG, báo user, không lên L2.

---

## Layer 2 — CPU + CRT0 Pattern (Assembly Level)

**Mục đích**: Verify CRT0 `_copy_data` loop hoạt động đúng với load-use hazard thực tế.

**Testbench**: `cpu/tb/tb_cpu_crt0_pattern.v` — **CẦN TẠO MỚI**
**Chạy**: `./workflow/run_layer_test.sh 2`
**Log output**: `log/layer2_crt0.log`

### Test pattern
Load exact `_copy_data` hex sequence từ test_ascon binary (PC 0x38–0x4c):
```
instruction_mem[0x38] = 32'h00735c63  // bge x6,x7,50
instruction_mem[0x3c] = 32'h0002ae03  // lw  x28,0(x5)
instruction_mem[0x40] = 32'h01c32023  // sw  x28,0(x6)
instruction_mem[0x44] = 32'h00428293  // addi x5,x5,4
instruction_mem[0x48] = 32'h00430313  // addi x6,x6,4
instruction_mem[0x4c] = 32'hfedff06f  // jal  0x38
```

**Setup**: x5=ROM_BASE, x6=DMEM_BASE, x7=DMEM_BASE+0x38
- ROM: chứa 14 words với giá trị known (e.g. 0x01020304, 0x05060708, ...)
**Check**: Sau loop kết thúc, DMEM[DMEM_BASE..DMEM_BASE+0x34] == ROM[ROM_BASE..ROM_BASE+0x34]

### Pass criteria L2
```
[L2-PASS] DMEM copy correct: all 14 words match source ROM
```

---

## Layer 3 — CPU + DCache + DMEM qua AXI

**Mục đích**: Verify load-use hazard vẫn đúng khi load đi qua DCache (latency không cố định).

**Testbench**: `cpu/tb/tb_riscv_soc_top.v` hoặc sub-test trong SoC tb
**Chạy**: `./workflow/run_layer_test.sh 3`
**Log output**: `log/layer3_dcache.log`

### Test pattern
Giống TC-1C nhưng địa chỉ load/store đi qua DCache → AXI → DMEM slave.
**Check**: DCache miss → AXI M1-AR transaction → data return đúng → forward đến dependent instruction.

### Pass criteria L3
```
[L3-PASS] Load via DCache + forwarding correct (cache hit and miss both)
```

---

## Layer 4 — CPU + ICache + IMEM qua AXI

**Mục đích**: Verify instruction fetch qua ICache hoạt động đúng.

**Testbench**: `run_soc_ascon.v` với program đơn giản (loop, branch)
**Chạy**: `./workflow/run_layer_test.sh 4`
**Log output**: `log/layer4_icache.log`

### Test pattern
Firmware nhỏ chỉ ghi 1 giá trị vào DMEM rồi halt:
```c
int main(void) {
    *(volatile uint32_t*)0x10000000 = 0xDEADBEEF;
    while(1);
}
```
**Check**: `log/layer4_icache.log` chứa `[DMEM] 0x10000000 = 0xDEADBEEF`

### Pass criteria L4
```
[L4-PASS] DMEM[0x10000000] = 0xDEADBEEF confirmed by testbench probe
```

---

## Layer 5 — Full SoC + CRT0 + Minimal Firmware

**Mục đích**: Verify `.data` copy (CRT0) hoạt động đúng trên full SoC với ICache + DCache.

**Testbench**: `run_soc_ascon.v` với firmware test_crt0_verify
**Chạy**: `./workflow/run_layer_test.sh 5`
**Log output**: `log/layer5_crt0_soc.log`

### Test firmware
```c
// test_crt0_verify.c
static const char magic[] = "HELLO";   // .data section (copied by CRT0)
int main(void) {
    // Nếu CRT0 đúng: magic[0]='H', magic[4]='O'
    DMEM->STATUS  = (uint32_t)magic[0];   // nên = 0x48 ('H')
    DMEM->RETCODE = (uint32_t)magic[4];   // nên = 0x4F ('O')
    while(1);
}
```
**Check**: DMEM[STATUS_OFFSET] == 0x48 và DMEM[RETCODE_OFFSET] == 0x4F

### Pass criteria L5
```
[L5-PASS] CRT0 data copy correct: STATUS=0x48, RETCODE=0x4F
```

---

## Layer 6a — SoC + UART (uart_puts đơn giản)

**Mục đích**: Verify UART TX path hoạt động đúng từ đầu đến cuối.

**Test**: `gnu_toolchain/tests/test_uart_simple.c`
**Chạy**: `./workflow/run_layer_test.sh 6a`
**Log output**: `log/layer6a_uart_simple.log`

### Pass criteria L6a
```
[L6a-PASS] *** PASS found in log
```
**Trạng thái hiện tại**: Đã PASS (từ regression cũ).

---

## Layer 6b — SoC + UART IRQ (W1C clear)

**Mục đích**: Verify UART TX IRQ enable → fire → W1C clear hoạt động đúng.

**Test**: `gnu_toolchain/tests/test_uart.c`
**Chạy**: `./workflow/run_layer_test.sh 6b`
**Log output**: `log/layer6b_uart_irq.log`

### Known bug
W1C clear tại 0x50000014 sau khi TX IRQ fires → CPU đọc lại vẫn thấy 1 → trả về -2.
Root cause chưa xác định: DCache stale hit hay UART RTL W1C logic sai.

### Pass criteria L6b
```
[L6b-PASS] *** PASS found in log (currently FAIL -2)
```

---

## Layer 6c — SoC + ASCON DMA

**Mục đích**: Verify full ASCON DMA 16-block encrypt pipeline.

**Test**: `gnu_toolchain/tests/test_ascon.c`
**Chạy**: `./workflow/run_layer_test.sh 6c`
**Log output**: `log/layer6c_ascon.log`

### Known bug
- CRT0 copy fail → strings không đúng trong DMEM → uart_puts in sai
- ASCON có thể không start nếu firmware bị corrupt

### Pass criteria L6c
```
[L6c-PASS] *** PASS found in log
```

---

## Known Bugs (cần fix theo thứ tự)

### BUG-001: Load-use hazard forwarding (CPU Pipeline)
- **Layer**: L1/L2
- **File**: `cpu/core/PIPELINE_REG_MEM_WB.v`, `cpu/core/hazard_detection.v`
- **Triệu chứng**: CRT0 _copy_data stores 0 thay vì đúng value
- **Fix applied**: `!lsu_committed` thay vì `!lsu_result_valid` — UNCOMMITTED
- **Status**: Fix applied nhưng chưa verify bằng isolated test

### BUG-002: UART TX IRQ W1C clear
- **Layer**: L6b
- **File**: Có thể `peripheral/uart/rtl/uart_*.v` hoặc DCache NC bypass
- **Triệu chứng**: `uart_irq_status()` sau W1C clear vẫn trả về 1 (TX bit)
- **Status**: Chưa investigate

### BUG-003: ASCON test timeout
- **Layer**: L6c
- **File**: Depend on BUG-001 — nếu CRT0 fix thì test có thể pass
- **Status**: Blocked by BUG-001

---

## Trạng thái hiện tại (cập nhật: 2026-05-12)

**Đang làm**: BUG-001 — load-use hazard
**Layer hiện tại**: L1 — cần verify CPU pipeline standalone
**Bước tiếp theo**: Chạy `./workflow/run_layer_test.sh 1` để confirm L1 pass

---

## Hướng dẫn cho AI agent khi nhận task

1. Đọc section "Trạng thái hiện tại" để biết đang ở layer nào
2. Chạy `./workflow/run_layer_test.sh <layer>` để lấy kết quả
3. Nếu PASS → cập nhật trạng thái layer → suggest lên layer tiếp theo
4. Nếu FAIL → báo ngắn gọn cho user: "Layer X FAIL tại TC-Y: [mô tả ngắn]"
5. Chờ user confirm trước khi phân tích sâu
6. Sau khi fix → ghi vào `task_debug.md`
