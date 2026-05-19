# SoC Test Plan — Bottom-Up Coverage

## Triết lý

```
Group A (RTL Unit)  →  Group B (CPU Integration)  →  Group C (SoC Firmware)
```

Khi firmware test fail → **không tự debug firmware ngay**. Chạy unit test tương ứng:

```
C fail → B (isolate: CPU lỗi hay peripheral lỗi?)
  B fail → A (isolate đến submodule cụ thể)
  peripheral C fail → A tương ứng (ASCON→A6/A7, DMA→A8, PLIC→A9)
A pass + C fail → firmware bug (check gnu_toolchain/tests/*.c)
A fail → RTL bug trong submodule đó
```

**Không skip layer.** Fix A trước khi chạy B. Fix B trước khi chạy C.

---

## Tổng quan 20 Test IDs

| ID | Group | Module | Testbench | Trạng thái |
|----|-------|--------|-----------|-----------|
| A1 | RTL Unit | CPU pipeline (ALU, forward, hazard, MUL) | `cpu/tb/tb_layer1_pipeline.v` | ❓ |
| A2 | RTL Unit | CPU core full (load-use, branch flush, CRT0) | `cpu/tb/tb_riscv_cpu_core_v2.v` | ❓ |
| A3 | RTL Unit | IMEM AXI slave | `memory/tb/tb_instmem.v` | ❓ |
| A4 | RTL Unit | DMEM AXI slave | `memory/tb/tb_datamem.v` | ❓ |
| A5 | RTL Unit | AXI crossbar routing + arbitration | `interconnect/tb/tb_axi4_crossbar.v` | ❓ |
| A6 | RTL Unit | ASCON core single-block AEAD | `ascon/tb/ascon_top_tb.v` | ❓ |
| A7 | RTL Unit | ASCON + DMA multi-block pipeline | `ascon/tb/tb_multi_block_dma.v` | ❓ |
| A8 | RTL Unit | GP-DMA memcpy (ch0 + ch1) | `dma/tb/tb_dma_top.v` | ❓ |
| A9 | RTL Unit | PLIC interrupt routing | `plic/tb/tb_plic_top.v` | ❓ |
| A10 | RTL Unit | SoC control registers | `controller/tb/tb_soc_ctrl_slave.v` | ❓ |
| B1 | CPU Integ | CRT0 lw/sw hazard qua DCache→DMEM | `cpu/tb/tb_riscv_cpu_core_v2.v` | ❓ |
| B2 | CPU Integ | ICache fetch + boot sequence | `run_soc_ascon.v` + minimal hex | ❓ |
| B3 | CPU Integ | DCache miss/hit + forwarding correctness | `run_soc_ascon.v` + test hex | ❓ |
| C1 | SoC FW | Boot + CRT0 .data init | `test_crt0_verify.c` (tạo mới) | 🚫 |
| C2 | SoC FW | UART TX basic | `test_uart_simple.c` | ✅ |
| C3 | SoC FW | UART TX IRQ + W1C clear | `test_uart.c` | ✅ PASS |
| C4 | SoC FW | GPIO r/w + edge IRQ | `test_gpio.c` | ⚠️ TIMEOUT |
| C5 | SoC FW | Timer0/1 countdown + IRQ | `test_timer.c` | ⚠️ TIMEOUT |
| C6 | SoC FW | CLINT mtime/mtimecmp | `test_clint.c` | ⚠️ TIMEOUT |
| C7 | SoC FW | PLIC 2-source routing | `test_plic.c` | ⚠️ TIMEOUT |
| C8 | SoC FW | ASCON DMA 16-block AEAD | `test_ascon.c` | ⚠️ TIMEOUT |
| C9 | SoC FW | GP-DMA memcpy via firmware | `test_dma_uart.c` | ⚠️ TIMEOUT |
| C10 | SoC FW | All IPs (Unity build) | `test_integration.c` | ⚠️ TIMEOUT |

---

## Group A — RTL Unit Tests

### A1 — CPU Pipeline Standalone
**Testbench**: `cpu/tb/tb_layer1_pipeline.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh cpu/tb/tb_layer1_pipeline.v
rtk read cpu/tb/tb_layer1_pipeline.log
```
**Test cases bắt buộc**:

| TC | Mô tả | Kiểm tra |
|----|-------|---------|
| TC-ALU | addi + add sequence với EX→EX forward | x3=8, x4=13 |
| TC-LU | lw sau sw, add dùng kết quả lw ngay | x8 = 8 (không phải 3) |
| TC-MUL | mul x5,x1,x2 → add dùng x5 ngay | x6 = 20 (stall MUL) |
| TC-BR | beq not-taken → instruction sau beq execute | x2=99, x3=7 |
| TC-CRT0 | Chuỗi lw/sw liên tiếp (mô phỏng _copy_data) | dmem[dst] == dmem[src] |

**Pass**: `[A1-PASS]` hoặc không có `FAIL` trong log.
**Nếu fail**: Dừng. Không chạy A2, B1, B2, B3. BUG-001 chưa fix đúng.

---

### A2 — CPU Core Full
**Testbench**: `cpu/tb/tb_riscv_cpu_core_v2.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh cpu/tb/tb_riscv_cpu_core_v2.v
rtk read cpu/tb/tb_riscv_cpu_core_v2.log
```
**Test cases bắt buộc**:

| TC | Mô tả | Kiểm tra |
|----|-------|---------|
| TC-FORWARD | EX/MEM/WB forwarding chains | register values correct |
| TC-LOAD-USE | lw → immediate use (1-cycle stall) | data không bị corrupted |
| TC-BRANCH | forward/backward branch, misprediction flush | PC recovery đúng |
| TC-CSR | csrr mcycle, csrw mtvec | CSR read/write OK |
| TC-MEM | store-then-load qua DCache | data consistency |

**Pass**: Không có `MISMATCH` hay `ERROR` trong log.
**Nếu fail**: Debug forwarding unit / hazard detection trước khi lên B.

---

### A3 — IMEM AXI Slave
**Testbench**: `memory/tb/tb_instmem.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh memory/tb/tb_instmem.v
rtk read memory/tb/tb_instmem.log
```
**Kiểm tra**: AXI AR handshake đúng, burst read trả đủ beats, RLAST đúng vị trí.
**Pass**: Không có `TIMEOUT` hay `ERR` trong log.

---

### A4 — DMEM AXI Slave
**Testbench**: `memory/tb/tb_datamem.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh memory/tb/tb_datamem.v
rtk read memory/tb/tb_datamem.log
```
**Kiểm tra**: AXI AW/W/B write + AR/R read round-trip, byte-enable (strobe) đúng.
**Pass**: Data read-back == data written.

---

### A5 — AXI Crossbar
**Testbench**: `interconnect/tb/tb_axi4_crossbar.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh interconnect/tb/tb_axi4_crossbar.v
rtk read interconnect/tb/tb_axi4_crossbar.log
```
**Test cases**:

| TC | Mô tả |
|----|-------|
| TC-M0-S0 | CPU M0 → IMEM S0 routing |
| TC-M1-S1 | CPU M1 → DMEM S1 routing |
| TC-M0-S5 | CPU → UART S5 routing |
| TC-ARBIT | M0 và M3 (DMA) cùng request → arbitration |
| TC-DECODE | Address out-of-range → DECERR response |

**Pass**: Tất cả routing đúng, không có xung đột B response sai ID.

---

### A6 — ASCON Core Single-Block
**Testbench**: `ascon/tb/ascon_top_tb.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh ascon/tb/ascon_top_tb.v
rtk read ascon/tb/ascon_top_tb.log
```
**Kiểm tra**:
- ASCON-128 encrypt: ciphertext và tag khớp golden model (`ascon/tb/sw_reference.py`)
- ASCON-128a encrypt/decrypt round-trip
- AD + plaintext combined mode

**Pass**: `[PASS]` từ testbench (so sánh với vectors trong `ascon_hw_vectors.tv`).
**Nếu fail**: Lỗi trong ASCON CONTROLLER FSM hoặc datapath. C8 sẽ FAIL ngay cả khi fix firmware.

---

### A7 — ASCON + DMA Multi-Block
**Testbench**: `ascon/tb/tb_multi_block_dma.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh ascon/tb/tb_multi_block_dma.v
rtk read ascon/tb/tb_multi_block_dma.log
```
**Kiểm tra**:
- DMA FSM: IDLE → WAIT_FIRST → STREAM → WAIT_TAG
- 16 blocks DMA transfer: AXI read burst, feed CORE, AXI write back
- `dma_done` assert đúng sau block cuối
- Ciphertext output khớp golden model

**Pass**: `[PASS]` hoặc `dma_done=1` và output match.
**Nếu fail trước A6 pass**: Fix A6 trước.

---

### A8 — GP-DMA
**Testbench**: `dma/tb/tb_dma_top.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh dma/tb/tb_dma_top.v
rtk read dma/tb/tb_dma_top.log
```
**Kiểm tra**:
- Channel 0 memcpy: src buffer → dst buffer đúng
- CH0 + CH1 parallel: không interference
- Error flag khi src address không hợp lệ

**Pass**: dst buffer == src buffer sau transfer.

---

### A9 — PLIC
**Testbench**: `plic/tb/tb_plic_top.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh plic/tb/tb_plic_top.v
rtk read plic/tb/tb_plic_top.log
```
**Kiểm tra**:
- Priority: source 8 (ASCON) priority 2, source 5 (UART) priority 1 → 8 thắng
- Threshold: nếu threshold=2 → source 5 bị mask
- Claim/Complete cycle đúng: PLIC.eip de-assert sau complete
- Gateway: edge-triggered, không re-assert khi chưa complete

**Pass**: Không có `MISMATCH` trong arbitration sequence.

---

### A10 — SoC Control
**Testbench**: `controller/tb/tb_soc_ctrl_slave.v`
**Chạy**:
```bash
~/workflow/urun_verilog.sh controller/tb/tb_soc_ctrl_slave.v
rtk read controller/tb/tb_soc_ctrl_slave.log
```
**Kiểm tra**: SYS_ID read, cycle counter increment, performance counter reset.
**Pass**: Không có `ERROR` trong log.

---

## Group B — CPU Integration Tests

### B1 — CRT0 Hazard Pattern (DCache)
**Mục đích**: Verify chuỗi lw→sw (CRT0 _copy_data) đúng khi đi qua DCache → DMEM AXI.
Cần A1, A2, A3, A4, A5 pass trước.

**Setup**: Dùng `cpu/tb/tb_riscv_cpu_core_v2.v` với config nạp hex từ `test_crt0_verify.hex`.
**Kiểm tra**: Sau loop, DMEM[DMEM_BASE..+0x34] == ROM[ROM_BASE..+0x34] (14 words).
**Run**:
```bash
./workflow/run_layer_test.sh 2
rtk read log/layer2_crt0.log
```
**Pass**: `[L2-PASS]` trong log.
**Nếu fail khi A1/A2 pass**: Lỗi DCache hoặc AXI crossbar (chạy A3/A4/A5 nếu chưa pass).

---

### B2 — ICache Boot Sequence
**Mục đích**: Verify ICache fetch + boot_ctrl load IMEM → CPU execute đúng.
Cần A3, A5 pass trước.

**Firmware**: Minimal hex — chỉ ghi `0xDEADBEEF` vào DMEM[0x10000000] rồi `while(1)`.
**Run**:
```bash
./workflow/run_layer_test.sh 4
rtk read log/layer4_icache.log
```
**Kiểm tra**: TB probe thấy write đến 0x10000000 với value 0xDEADBEEF.
**Pass**: `[L4-PASS]` trong log.
**Nếu fail**: Kiểm tra ICache AXI deadlock (`icache_axi_interface.v` ARVALID latch).

---

### B3 — DCache Miss/Hit Correctness
**Mục đích**: Verify DCache miss → AXI fetch → hit trên access tiếp theo, forwarding đúng.
Cần B2 pass.

**Firmware**: Minimal hex — store vào 4 địa chỉ khác nhau, load lại tất cả, compare.
**Run**:
```bash
./workflow/run_layer_test.sh 3
rtk read log/layer3_dcache.log
```
**Pass**: `[L3-PASS]` trong log, không có `MISMATCH`.

---

## Group C — SoC Firmware Tests

**Infrastructure**: `bash regression_full.sh <test_name>`

Tất cả C test cần B1 + B2 pass trước.

---

### C1 — Boot + CRT0 Data Init *(TB cần tạo)*
**Firmware**: `gnu_toolchain/tests/test_crt0_verify.c` (chưa có, cần tạo)
```c
static const char magic[] = "HELLO";   // .data section
int main(void) {
    DMEM->STATUS  = (uint32_t)magic[0]; // expect 0x48 ('H')
    DMEM->RETCODE = (uint32_t)magic[4]; // expect 0x4F ('O')
    while(1);
}
```
**Pass**: DMEM[STATUS]=0x48, DMEM[RETCODE]=0x4F.
**Nếu fail**: BUG-001 vẫn còn, hoặc toolchain `-c` flag sai.

---

### C2 — UART TX Basic
**Firmware**: `test_uart_simple.c`
**Run**: `bash regression_full.sh test_uart_simple`
**Pass**: `*** PASS` trong log.
**Trạng thái**: ✅ Đã PASS (baseline, dùng để sanity check sau mỗi RTL change).

---

### C3 — UART TX IRQ + W1C
**Firmware**: `test_uart.c`
**Run**: `bash regression_full.sh test_uart`
**Kiểm tra**: TX IRQ fire → CPU nhận → W1C clear → flag cleared.
**Pass**: `*** PASS`.
**Trạng thái**: ✅ Đã PASS (2026-05-19).
**Lưu ý verify thực tế**:
1. BUG-002 (LSU store-buffer forward vào MMIO/NC address) đã được fix trước đó nên W1C clear đã đúng ở hardware path.
2. Lần TIMEOUT gần nhất không còn là lỗi W1C clear; nguyên nhân là testbench UART line parser không flush khi test gửi 1 byte `'A'` không kèm `\n`.
3. Fix firmware: thêm `uart_puts("\r\n")` sau byte `'A'` để tách dòng trước marker `[PASS] uart`.
**Debug path nếu regress**:
1. Kiểm tra `cpu/core/LSU.v` cho NC/MMIO forwarding guard (0x5000_0000 range không được SB-forward như DMEM cacheable)
2. Kiểm tra `gnu_toolchain/tests/test_uart.c` có còn flush line buffer trước `[PASS] uart` không
3. Nếu vẫn fail thật sự ở IRQ/W1C thì mới quay lại UART RTL `peripheral/uart/rtl/` và PLIC path (A9)

---

### C4 — GPIO
**Firmware**: `test_gpio.c`
**Run**: `bash regression_full.sh test_gpio`
**Kiểm tra**: GPIO write → read-back, edge IRQ → PLIC → CPU ISR.
**Pass**: `*** PASS`.
**Debug path khi fail**: Cần A9 (PLIC unit) pass trước khi debug GPIO IRQ path.

---

### C5 — Timer
**Firmware**: `test_timer.c`
**Run**: `bash regression_full.sh test_timer`
**Kiểm tra**: Timer0 countdown → IRQ fire → ISR handler.
**Pass**: `*** PASS`.
**Known bug**: BUG-TIMER (timer_channel.v `en` rising edge detect) — fix applied, chưa verify.

---

### C6 — CLINT
**Firmware**: `test_clint.c`
**Run**: `bash regression_full.sh test_clint`
**Kiểm tra**: mtime increment, mtimecmp → M-mode timer interrupt, msip software interrupt.
**Pass**: `*** PASS`.

---

### C7 — PLIC
**Firmware**: `test_plic.c`
**Run**: `bash regression_full.sh test_plic`
**Kiểm tra**: 2 sources với priority khác nhau → correct claim order.
**Pass**: `*** PASS`.
**Debug path**: A9 (PLIC unit test) phải pass trước.

---

### C8 — ASCON DMA 16-block
**Firmware**: `test_ascon.c`
**Run**: `bash regression_full.sh test_ascon`
**Kiểm tra**: Plaintext 16×8B → ASCON-128 DMA encrypt → ciphertext+tag đúng.
**Pass**: `*** PASS`.
**Debug path khi fail**:
1. A6 pass? → ASCON core đúng
2. A7 pass? → DMA pipeline đúng
3. C1 pass? → CRT0 không corrupt buffer
4. Nếu A6+A7+C1 pass nhưng C8 fail → firmware config sai (CTRL=0x5, fence, DMA_BURST)

---

### C9 — GP-DMA
**Firmware**: `test_dma_uart.c`
**Run**: `bash regression_full.sh test_dma_uart`
**Kiểm tra**: CPU setup DMA memcpy → poll DONE → verify dst == src.
**Pass**: `*** PASS`.
**Debug path**: A8 (DMA unit test) phải pass trước.

---

### C10 — Integration
**Firmware**: `test_integration.c`
**Run**: `bash regression_full.sh test_integration`
**Kiểm tra**: 6 IPs sequentially, báo cáo `ALL_PASS 6/6`.
**Pass**: `ALL_PASS 6/6` trong log.
**Điều kiện**: C2–C9 tất cả pass trước khi chạy C10.

---

## Coverage Matrix

| Bug ID | Phát hiện tại | Isolated tại | Root cause |
|--------|-------------|-------------|-----------|
| BUG-001 load-use hazard | A1 TC-LU, A2 | **A1** | `hazard_detection.v` + `PIPELINE_REG_MEM_WB.v` |
| BUG-002 UART W1C | C3 | **C3** | `cpu/core/LSU.v` store-buffer forward sai vào MMIO/NC path |
| BUG-003 ASCON timeout | A7, C8 | **A6** (core) / **A7** (DMA) | ASCON CTRL=0x5 hoặc DMA FSM |
| BUG-TIMER timer enable | C5 | **C5** (không có unit TB) | `timer_channel.v` en rising edge |
| ICache AXI deadlock | B2 | **B2** | `icache_axi_interface.v` ARVALID latch |
| DCache stale | B1, B3 | **B1** | DCache miss path / forwarding |
| PLIC arbitration | A9, C7 | **A9** | `plic_top.v` priority logic |
| CRT0 _copy_data | A1 TC-CRT0, B1, C1 | **A1** | load-use hazard trong lw→sw loop |
| AXI crossbar routing | A5 | **A5** | `axi4_crossbar.v` address decode |

---

## Quick Reference — Run Commands

```bash
# Group A
~/workflow/urun_verilog.sh cpu/tb/tb_layer1_pipeline.v         # A1
~/workflow/urun_verilog.sh cpu/tb/tb_riscv_cpu_core_v2.v       # A2
~/workflow/urun_verilog.sh memory/tb/tb_instmem.v              # A3
~/workflow/urun_verilog.sh memory/tb/tb_datamem.v              # A4
~/workflow/urun_verilog.sh interconnect/tb/tb_axi4_crossbar.v  # A5
~/workflow/urun_verilog.sh ascon/tb/ascon_top_tb.v             # A6
~/workflow/urun_verilog.sh ascon/tb/tb_multi_block_dma.v       # A7
~/workflow/urun_verilog.sh dma/tb/tb_dma_top.v                 # A8
~/workflow/urun_verilog.sh plic/tb/tb_plic_top.v               # A9
~/workflow/urun_verilog.sh controller/tb/tb_soc_ctrl_slave.v   # A10
~/workflow/urun_verilog.sh peripheral/gpio/tb/tb_gpio_top.v    # A11
~/workflow/urun_verilog.sh peripheral/timer/tb/tb_timer_top.v  # A12
~/workflow/urun_verilog.sh peripheral/spi/tb/tb_spi_top.v      # A13
~/workflow/urun_verilog.sh peripheral/otp/tb/tb_otp_stub_slave.v # A14

# Group B (via run_layer_test.sh)
./workflow/run_layer_test.sh 2    # B1 — CRT0 hazard
./workflow/run_layer_test.sh 4    # B2 — ICache boot
./workflow/run_layer_test.sh 3    # B3 — DCache

# Group C (via regression_full.sh)
bash regression_full.sh test_uart_simple    # C2
bash regression_full.sh test_uart           # C3
bash regression_full.sh test_gpio           # C4
bash regression_full.sh test_timer          # C5
bash regression_full.sh test_clint          # C6
bash regression_full.sh test_plic           # C7
bash regression_full.sh test_ascon          # C8
bash regression_full.sh test_dma_uart       # C9
bash regression_full.sh test_integration    # C10

# Chạy tất cả Group C
bash regression_full.sh
```

---

## Quy tắc cho AI agent

1. Đọc `test_task.md` → biết test nào đang FAIL, đang focus bug nào.
2. Chạy test theo đúng group — KHÔNG chạy C khi A/B chưa pass.
3. Khi phát hiện fail: báo ngắn "Test X FAIL tại TC-Y: [mô tả 1 dòng]" → chờ user confirm trước khi phân tích sâu.
4. Sau mỗi fix → update `test_task.md` với kết quả verify thực tế.
5. Dùng escalation policy để tìm root cause, không trial-and-error.
