# Task: RISC-V CPU Core Frequency Optimization

## Phase 1: Clean Code & Remove Obvious Bottlenecks ✅

- [x] **1.1** Clean `alu.v` — Merged 2→1 MUL, gated enable, removed dead DIV/REM
- [x] **1.2** Clean `branch_logic.v` — Removed 45 lines of commented-out old code
- [x] **1.3** Clean `IFU.v` — Removed 73 lines of commented-out old code
- [x] **1.4** Clean `riscv_cpu_core_v2.v`:
  - [x] 1.4a Move `lsu_store_count` into `translate_off` block
  - [x] 1.4b Removed duplicate `translate_off` blocks, cleaned debug monitors
  - [x] 1.4c Refactored inline ID/EX register → standalone `PIPELINE_REG_ID_EX` module
  - [x] 1.4d Refactored inline EX/MEM register → standalone `PIPELINE_REG_EX_MEM` module (NEW file)
  - [x] 1.4e Refactored inline MEM/WB register → standalone `PIPELINE_REG_MEM_WB` module (NEW file)
  - [x] 1.4f Fixed alu_in1_forwarded forward declaration
- [x] **1.5** Full SoC compilation test — 0 errors ✅

## Phase 2: Microarchitecture Optimization

- [x] **2.1** Multi-cycle MUL unit (tách khỏi ALU) — 2-stage pipelined riscv_multiplier, xóa riscv_defs.v, MUL stall trong hazard_detection, WB mux mở rộng
- [x] **2.2** Negedge write register file — đã hoàn thành từ Phase 1 (reg_file.v dùng negedge, không còn forwarding MUX)
- [x] **2.3** Register IRQ flush output — thêm `irq_flush_r` flop, loại bỏ combinational feedback vào pipeline flush
- [x] **2.4** Optimize LSU store buffer — đã hoàn thành (SB_DEPTH=4, LQ_DEPTH=4)
- [x] **2.5** Clean hazard_detection duplicate logic — đã clean (lsu_dep_stall duy nhất từ hazard_detection, kết nối trong Phase 2.1)

## Verification

- [x] **V1** Simulation regression test — PASS=56 FAIL=5 (5 failures là pre-existing, không regression)
- [ ] **V2** Waveform comparison
