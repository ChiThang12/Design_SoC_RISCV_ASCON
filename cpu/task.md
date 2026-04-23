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

## Phase 2: Microarchitecture Optimization ✅

- [x] **2.1** Multi-cycle MUL unit (tách khỏi ALU) — 2-stage pipelined riscv_multiplier, xóa riscv_defs.v, MUL stall trong hazard_detection, WB mux mở rộng
- [x] **2.2** Negedge write register file — đã hoàn thành từ Phase 1 (reg_file.v dùng negedge, không còn forwarding MUX)
- [x] **2.3** Register IRQ flush output — thêm `irq_flush_r` flop, loại bỏ combinational feedback vào pipeline flush
- [x] **2.4** Optimize LSU store buffer — đã hoàn thành (SB_DEPTH=4, LQ_DEPTH=4)
- [x] **2.5** Clean hazard_detection duplicate logic — đã clean (lsu_dep_stall duy nhất từ hazard_detection, kết nối trong Phase 2.1)

## Phase 3: Critical Path Optimization (Fmax) ✅

- [x] **3.1 Fix 1** `alu.v` — zero_flag bypass adder path (`in1==in2` thay vì `alu_result==0`)
- [x] **3.2 Fix 2** `alu.v` — Pre-compute add_result/sub_result + synthesis `parallel_case full_case`
- [x] **3.3 Fix 3** `riscv_cpu_core_v2.v` — Flatten alu_in1 MUX chain (2-level → 1-level priority)
- [x] **3.4 Fix 4** `riscv_cpu_core_v2.v` — Flatten alu_in2 MUX chain (2-level → 1-level priority)
- [x] **3.5 Fix 5** `PIPELINE_REG_ID_EX.v` + `riscv_cpu_core_v2.v` — Pre-compute branch_target trong ID stage
- [x] **3.6 Fix 6** `riscv_cpu_core_v2.v` — 2-FF CDC synchronizer cho IRQ signals
- [x] **3.7 Fix 7** `riscv_cpu_core_v2.v` — 2-FF CDC synchronizer cho debug signals

## Phase 4: CPI Optimization (sau khi đo được CPI=1.71) ✅

### Fix 8 — Remove redundant `mem_load_stall` (hazard_detection.v) ✅

Lý do: WB→EX forwarding đã xử lý đúng, 1 stall từ load_use_hazard là đủ.

- [x] **8.1** Xóa wire `mem_load_stall` declaration
- [x] **8.2** Remove `mem_load_stall ||` khỏi `assign stall`
- [x] **8.3** Remove `mem_load_stall ||` khỏi `assign flush_id_ex`
- [x] **8.4** Xóa comment block `[FIX-BUG-FLUSH]`
- [x] **8.5** `memread_mem` / `rd_mem` không còn dùng riêng — đã xóa khỏi hazard_detection

### Fix 9A — Add `predict_taken` port (PIPELINE_REG_ID_EX.v) ✅

- [x] **9A.1** Thêm `input wire predict_taken_in` vào port list
- [x] **9A.2** Thêm `output reg predict_taken_out` vào port list
- [x] **9A.3** Thêm `predict_taken_out <= 1'b0;` trong flush/reset block
- [x] **9A.4** Thêm `predict_taken_out <= predict_taken_in;` trong normal latch block

### Fix 9B — Prediction-aware flush (hazard_detection.v) ✅

- [x] **9B.1** Thêm 3 inputs mới: `predict_taken_ex`, `predict_taken_id`, `mispredict_ex`
- [x] **9B.2** `assign flush_if_id = (branch_taken && !predict_taken_ex) || mispredict_ex || predict_taken_id`
- [x] **9B.3** `assign flush_id_ex = load_use_hazard || (branch_taken && !predict_taken_ex) || mispredict_ex || fence_stall || mul_result_stall`

### Fix 9C — Wiring (riscv_cpu_core_v2.v) ✅

- [x] **9C.1** Khai báo wires: `predict_taken_ex`, `predict_taken_id`, `mispredict_ex`
- [x] **9C.2** `predict_taken_id = branch_id && imm_id[31] && !stall_any` / `mispredict_ex = predict_taken_ex && !branch_taken_ex && branch_ex`
- [x] **9C.3** IFU priority MUX wires `ifu_pc_src` / `ifu_target_pc` (mispredict > pc_src > predict)
- [x] **9C.4** IFU instantiation dùng `ifu_pc_src` / `ifu_target_pc`
- [x] **9C.5** PIPELINE_REG_ID_EX: `.predict_taken_in` / `.predict_taken_out` connected
- [x] **9C.6** hazard_detection: `.predict_taken_ex` / `.predict_taken_id` / `.mispredict_ex` connected

## Phase 5: Multiplier Timing Fix (Logic Depth Violation từ Physical Design Report) ✅

### Fix 10A — 3-stage multiplier (riscv_multiplier.v) ✅

- [x] **10A.1** Thêm port `input wire mul_hold_e15_i`
- [x] **10A.2** Wires a_lo/a_hi/b_lo/b_hi từ E1 outputs (17-bit halves, sign bit ở [16])
- [x] **10A.3** 4 partial product wires pp_ll/lh/hl/hh_w (signed 17×17 → 34-bit)
- [x] **10A.4** Registers pp_ll/lh/hl/hh_e15_q và mulhi_sel_e15_q
- [x] **10A.5** E1.5 always block gated by `!mul_hold_e15_i`
- [x] **10A.6** mult_result_w = tổng 4 partial products với sign-extension + shifts
- [x] **10A.7** result_r dùng mulhi_sel_e15_q
- [x] **10A.8** `(* keep=1 *)` wires sign_a/sign_b để giảm fanout từ 133

### Fix 10B — mul_ex_stall (hazard_detection.v) ✅

- [x] **10B.1** `input wire clk, rst` vào port list
- [x] **10B.2** `output wire mul_ex_stall` vào port list
- [x] **10B.3** Register `mul_ex_stall_done_r`
- [x] **10B.4** always block: reset khi `!mul_in_ex`, set sau cycle đầu tiên
- [x] **10B.5** `assign mul_ex_stall = mul_in_ex && !mul_ex_stall_done_r`
- [x] **10B.6** `|| mul_ex_stall` trong `assign stall` (không có trong `flush_id_ex`)

### Fix 10C — Wiring (riscv_cpu_core_v2.v) ✅

- [x] **10C.1** Wire `mul_ex_stall_wire`
- [x] **10C.2** Wire `mul_hold = stall_any && !mul_ex_stall_wire`
- [x] **10C.3** hazard_detection: `.clk` / `.rst` / `.mul_ex_stall(mul_ex_stall_wire)` connected
- [x] **10C.4** multiplier_unit: `.hold_i(mul_hold)`
- [x] **10C.5** multiplier_unit: `.mul_hold_e15_i(mul_hold)`

## Phase 6: WB + Forwarding MUX Critical Path Fix (15.8 ns violation)

**Nguyên nhân:** `is_mul_wb` (FF) → WB `?:` priority chain → `write_back_data_wb` →
forwarding `?:` chain → `alu_in1_forwarded` → D-input của `read_data1_out` trong
PIPELINE_REG_ID_EX. Yosys gộp 3 tầng MUX 32-bit thành chuỗi carry ~30 cổng → 15.8 ns.

**Giải pháp (Fix 11):** Chuyển tất cả MUX `?:` priority thành AND-OR one-hot.
Với selector mutually exclusive, synthesis ánh xạ trực tiếp thành 2 tầng cổng
(AND sign-extend rồi OR) → ~1–2 ns.

### Fix 11 — AND-OR MUX flattening (riscv_cpu_core_v2.v)

- [x] **11.1** `alu_in1_forwarded`: thêm `fwd_a_mem/fwd_a_wb/fwd_a_none` wires, chuyển sang AND-OR
- [x] **11.2** `alu_in1`: thêm `alu_in1_use_fwd`, chuyển sang AND-OR dùng `alu_in1_forwarded`
- [x] **11.3** `alu_in2_pre_mux`: thêm `fwd_b_mem/fwd_b_wb/fwd_b_none` wires, chuyển sang AND-OR
- [x] **11.4** `alu_in2`: chuyển sang 2-input AND-OR (`alusrc_ex` / `!alusrc_ex`)
- [x] **11.5** `write_back_data_wb`: thêm `is_alu_wb` wire, chuyển sang AND-OR (4-input)

## Verification

- [x] **V1** Simulation regression test — PASS=56 FAIL=5 (pre-existing, không regression)
- [ ] **V2** Waveform comparison
- [ ] **V3** Chạy full SoC sau Fix 8+9 — firmware hoàn thành, DONE bit set
- [ ] **V4** Cycle count giảm ~13 so với baseline 4980 (expect ~4967)
- [ ] **V5** S2 ASCON reads vẫn = 3, output CT data không thay đổi
- [ ] **V6** Load-use test case verify Fix 8 an toàn (WB→EX forward đúng)
- [ ] **V7** Chạy simulation sau Fix 10 — MUL / MULH / MULHSU / MULHU cho kết quả đúng
- [ ] **V8** Back-to-back `MUL x3,x1,x2 / ADD x4,x3,x5` stall đúng 1 cycle (không 0 hoặc 2)
- [ ] **V9** Timing report sau synthesis: critical path E1→E1.5 và E1.5→E2 đều < 6ns
- [ ] **V10** Fanout report: không còn net nào > 50 trong multiplier path
- [ ] **V11** Timing report sau Fix 11: critical path is_mul_wb→write_back_data_wb→alu_in1_forwarded→ID/EX-reg < 6ns (was 15.8ns)
- [ ] **V12** Simulation regression sau Fix 11 — kết quả ALU / MUL / load / branch không thay đổi
