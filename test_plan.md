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
| A1 | RTL Unit | CPU pipeline (ALU, forward, hazard, MUL) | `cpu/tb/tb_layer1_pipeline.v` | ✅ PASS 17/17 |
| A2 | RTL Unit | CPU core full (load-use, branch flush, CRT0) | `cpu/tb/tb_riscv_cpu_core_v2.v` | ✅ PASS 61/61 |
| A3 | RTL Unit | IMEM AXI slave | `memory/tb/tb_instmem.v` | ✅ PASS 64/64 |
| A4 | RTL Unit | DMEM AXI slave | `memory/tb/tb_datamem.v` | ✅ PASS 71/71 |
| A5 | RTL Unit | AXI crossbar routing + arbitration | `interconnect/tb/tb_axi4_crossbar.v` | ✅ PASS 21/21 |
| A6 | RTL Unit | ASCON core single-block AEAD | `ascon/tb/ascon_top_tb.v` | ✅ PASS 9/9 |
| A7 | RTL Unit | ASCON + DMA multi-block pipeline | `ascon/tb/tb_multi_block_dma.v` | ✅ PASS |
| A8 | RTL Unit | GP-DMA memcpy (ch0 + ch1) | `dma/tb/tb_dma_top.v` | ✅ PASS 108/108 |
| A9 | RTL Unit | PLIC interrupt routing | `plic/tb/tb_plic_top.v` | ✅ PASS 51/51 |
| A10 | RTL Unit | SoC control registers | `controller/tb/tb_soc_ctrl_slave.v` | ✅ PASS 61/61 |
| B1 | CPU Integ | CRT0 lw/sw hazard qua DCache→DMEM | `cpu/tb/tb_riscv_cpu_core_v2.v` | ✅ PASS |
| B2 | CPU Integ | ICache fetch + boot sequence | `run_soc_ascon.v` + minimal hex | ✅ PASS |
| B3 | CPU Integ | DCache miss/hit + forwarding correctness | `run_soc_ascon.v` + test hex | ✅ PASS |
| C1 | SoC FW | Boot + CRT0 .data init | `test_crt0_verify.c` | ✅ PASS |
| C2 | SoC FW | UART TX basic | `test_uart_simple.c` | ✅ PASS |
| C3 | SoC FW | UART TX IRQ + W1C clear | `test_uart.c` | ✅ PASS |
| C4 | SoC FW | GPIO r/w + edge IRQ | `test_gpio.c` | ⚠️ CRASH (BUG-C4-GPIO-CRASH) |
| C5 | SoC FW | Timer0/1 countdown + IRQ | `test_timer.c` | ⚠️ TIMEOUT (BUG-C5-RAW) |
| C6 | SoC FW | CLINT mtime/mtimecmp | `test_clint.c` | ❓ chưa debug |
| C7 | SoC FW | PLIC 2-source routing | `test_plic.c` | ❓ chưa debug |
| C8 | SoC FW | ASCON DMA 16-block AEAD | `test_ascon.c` | ✅ PASS |
| C9 | SoC FW | GP-DMA memcpy via firmware | `test_dma_uart.c` | ✅ PASS |
| C10 | SoC FW | All IPs (Unity build) | `test_integration.c` | ✅ PASS |

---

## Group A — RTL Unit Tests (tất cả đã PASS)

| ID | Run command | Pass condition | Ghi chú |
|----|-------------|---------------|---------|
| A1 | `~/workflow/urun_verilog.sh cpu/tb/tb_layer1_pipeline.v` | Không có FAIL | Nếu fail → dừng toàn bộ A2/B1-B3 |
| A2 | `~/workflow/urun_verilog.sh cpu/tb/tb_riscv_cpu_core_v2.v` | Không có MISMATCH/ERROR | — |
| A3 | `~/workflow/urun_verilog.sh memory/tb/tb_instmem.v` | Không có TIMEOUT/ERR | AXI AR burst, RLAST đúng |
| A4 | `~/workflow/urun_verilog.sh memory/tb/tb_datamem.v` | Data read-back == written | AW/W/B + AR/R, byte-enable |
| A5 | `~/workflow/urun_verilog.sh interconnect/tb/tb_axi4_crossbar.v` | Tất cả routing đúng | Routing, DECERR, arbitration |
| A6 | `~/workflow/urun_verilog.sh ascon/tb/ascon_top_tb.v` | `[PASS]` vs golden | Nếu fail → C8 sẽ fail dù fix FW |
| A7 | `~/workflow/urun_verilog.sh ascon/tb/tb_multi_block_dma.v` | `[PASS]` / dma_done=1 | Cần A6 pass trước |
| A8 | `~/workflow/urun_verilog.sh dma/tb/tb_dma_top.v` | dst == src | CH0+CH1 parallel |
| A9 | `~/workflow/urun_verilog.sh plic/tb/tb_plic_top.v` | Không có MISMATCH | Priority, threshold, claim/complete |
| A10 | `~/workflow/urun_verilog.sh controller/tb/tb_soc_ctrl_slave.v` | Không có ERROR | SYS_ID, cycle cnt, perf cnt |

---

## Group B — CPU Integration Tests (tất cả đã PASS)

| ID | Mục đích | Run | Pass |
|----|---------|-----|------|
| B1 | CRT0 lw→sw hazard qua DCache→DMEM AXI. Cần A1-A5. | `./workflow/run_layer_test.sh 2` | `[L2-PASS]` |
| B2 | ICache fetch + boot_ctrl load IMEM. Cần A3, A5. | `./workflow/run_layer_test.sh 4` | `[L4-PASS]` |
| B3 | DCache miss→fetch→hit, forwarding. Cần B2. | `./workflow/run_layer_test.sh 3` | `[L3-PASS]` |

---

## Group C — SoC Firmware Tests

**Infrastructure**: `bash regression_full.sh <test_name>`. Cần B1+B2 pass.

| ID | Firmware | Run | Trạng thái | Ghi chú |
|----|---------|-----|-----------|---------|
| C1 | test_crt0_verify.c | `bash regression_full.sh test_crt0_verify` | ✅ PASS | uart=13 |
| C2 | test_uart_simple.c | `bash regression_full.sh test_uart_simple` | ✅ PASS | Sanity check baseline |
| C3 | test_uart.c | `bash regression_full.sh test_uart` | ✅ PASS | uart=28 |
| C4 | test_gpio.c | `bash regression_full.sh test_gpio` | ⚠️ CRASH | uart=0, PC→0x01000000 trước uart_init. **BUG-C4-GPIO-CRASH** |
| C5 | test_timer.c | `bash regression_full.sh test_timer` | ⚠️ TIMEOUT | uart=38, ISR runs 3× đúng nhưng main loop stale. **BUG-C5-RAW** |
| C6 | test_clint.c | `bash regression_full.sh test_clint` | ❓ | Re-run sau plic.h revert để có baseline |
| C7 | test_plic.c | `bash regression_full.sh test_plic` | ❓ | Re-run để xem log. A9 phải pass trước |
| C8 | test_ascon.c | `bash regression_full.sh test_ascon` | ✅ PASS | uart=14 "[PASS] ascon.." |
| C9 | test_dma_uart.c | `bash regression_full.sh test_dma_uart` | ✅ PASS | uart=74 |
| C10 | test_integration.c | `bash regression_full.sh test_integration` | ✅ PASS | uart=60 |

---

## Coverage Matrix

| Bug ID | Phát hiện tại | Root cause | Status |
|--------|-------------|-----------|--------|
| BUG-001 load-use hazard | A1/B1/C1 | `hazard_detection.v` + `PIPELINE_REG_MEM_WB.v` | ✅ FIXED |
| BUG-002 UART W1C | C3 | `LSU.v` store-buffer forward vào MMIO/NC | ✅ FIXED |
| BUG-003 ASCON timeout | A7, C8 | CTRL=0x5, blocked by BUG-001 | ✅ FIXED |
| BUG-TIMER timer enable | C5 | `timer_channel.v` en rising edge | ✅ FIXED |
| BUG-ICACHE AXI deadlock | B2 | `icache_axi_interface.v` ARVALID latch | ✅ FIXED |
| BUG-C4 IFU redirect slip | C4 | `IFU.v` redirect_pending không gate NOP | ✅ FIXED |
| BUG-C4 ICache last-word race | C4 | `icache_controller.v` NBA timing data_array | ✅ FIXED |
| BUG-PLIC-DECERR | C4.5 | CLOSED — PLIC HW đúng, bug là CPU pipeline | ✅ CLOSED |
| BUG-C8-DOT | C8 | Firmware 1 chấm vs TB 2 chấm | ✅ FIXED |
| BUG-MUL multiplier | A1 TC-05 | `riscv_multiplier.v` dispatch + timing | ✅ FIXED |
| BUG-JAL-STALL | B3 | `cpu_core_v2.v` pc_src_ex lost khi stall_any=X | ✅ FIXED |
| BUG-C4-GPIO-CRASH | C4 | CPU pipeline / mtvec corruption trước uart_init | ❌ OPEN |
| BUG-C5-RAW | C5 | `timer_irq_count` stale sau mret (DCache RAW) | ❌ OPEN |

---

## Quick Reference

### Parallel regression (~80–90s)
```bash
bash regression_full.sh -j                              # tất cả song song
bash regression_full.sh -b -j                           # rebuild FW + parallel
bash regression_full.sh -j test_gpio test_clint test_plic  # subset
```

### Single test (74s)
```bash
bash regression_full.sh test_timer
bash regression_full.sh test_gpio
rtk read log/test_timer.log
```

### Group A & B
```bash
~/workflow/urun_verilog.sh cpu/tb/tb_layer1_pipeline.v         # A1
~/workflow/urun_verilog.sh cpu/tb/tb_riscv_cpu_core_v2.v       # A2
~/workflow/urun_verilog.sh ascon/tb/ascon_top_tb.v             # A6
~/workflow/urun_verilog.sh plic/tb/tb_plic_top.v               # A9
./workflow/run_layer_test.sh 2    # B1
./workflow/run_layer_test.sh 4    # B2
./workflow/run_layer_test.sh 3    # B3
```

---

## Quy tắc cho AI agent

1. Đọc `test_task.md` → biết test nào đang FAIL, đang focus bug nào.
2. Chạy test theo đúng group — KHÔNG chạy C khi A/B chưa pass.
3. Khi phát hiện fail: báo ngắn "Test X FAIL tại TC-Y: [mô tả 1 dòng]" → chờ user confirm.
4. Sau mỗi fix → update `test_task.md` với kết quả verify thực tế.
5. **Verify nhanh**: dùng `bash regression_full.sh -j` (parallel, ~90s) thay vì serial (10 phút).
