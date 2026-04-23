# Plan: CPI Optimization – RISC-V CPU Core v2

## Background

Sau khi hoàn thành 7 Fmax fixes (zero_flag bypass, flatten MUX chains, pre-compute
branch_target, CDC synchronizers), full SoC simulation cho kết quả CPI = 1.71
(cycles=4980, instr_retired≈2910).

Phân tích firmware `gnu_toolchain/main.s` xác định 2 nguồn wasted cycles chính:

| Nguồn | Cycles lãng phí | Loại |
|-------|-----------------|------|
| `.L2` loop `bne a5,a2,.L2` → 15 backward taken branches | 15×2 = **30 cycles** | branch flush |
| `.L4` polling `beq a3,zero,.L4` → 2 backward taken branches | 2×2 = **4 cycles** | branch flush |
| `mem_load_stall` double-stall cho load-use pairs | 1 cycle mỗi cặp | redundant stall |
| `fence_stall` 17 FENCE instructions (ASCON writes) | ~17×AXI latency | AXI speed (không phải CPU) |

---

## Fix 8: Remove redundant `mem_load_stall`

**File:** `cpu/core/hazard_detection.v`

**Vấn đề hiện tại:**
```
Cycle N  : load in EX,  use in ID  → load_use_hazard → stall (bubble) → cần thiết
Cycle N+1: load in MEM, use in ID  → mem_load_stall  → stall (extra)  → KHÔNG cần
Cycle N+2: use in EX, load in WB → WB→EX forward đúng                → an toàn
```
`mem_load_stall` gây stall thêm 1 cycle không cần thiết vì WB→EX forwarding
(`forward_a=2'b01 → write_back_data_wb`) đã xử lý đúng trường hợp này.

**Thay đổi (3 dòng):**
```verilog
// Xóa wire mem_load_stall (dòng 33–36)
// Modify dòng 58:
assign stall    = load_use_hazard || lsu_dependency_stall || fence_stall || mul_result_stall;
// Modify dòng 70:
assign flush_id_ex = load_use_hazard || branch_taken || fence_stall || mul_result_stall;
```

**Impact:** Saves 1 stall cycle per load-use pair. Firmware ASCON không có close
load-use (lw trong .L4 có 3 instructions gap) nên tác động nhỏ ở đây, nhưng
hữu ích cho general workloads.

---

## Fix 9: Static Backward Branch Prediction

**Nguyên lý:** Backward branches (imm < 0 → `imm_id[31]=1`) là loop branches,
thường TAKEN. Phát hiện từ ID stage, redirect IFU ngay → giảm penalty từ 2→1 cycle.

**Penalty breakdown:**
```
Correctly predicted TAKEN (loop iterates): 1 cycle  (vs 2 hiện tại → TIẾT KIỆM 1)
Mispredicted NOT TAKEN (loop exits):       2 cycles  (vs 0 hiện tại → TỐN thêm 2)
```

**Expected savings (firmware):**
- `.L2`: 15×1 + 1×2 = 17 vs 15×2 = 30 → **tiết kiệm 13 cycles**
- `.L4`: 2×1 + 1×2 = 4 vs 2×2 = 4 → **hòa vốn**
- **Net: ~13 cycles / ~4980 total → 0.26% improvement**

### Pipeline timing với prediction:

```
Cycle N:   Branch in ID  → predict_taken_id=1 → flush IF/ID (squash PC_branch+4)
                         → IFU redirects to branch_target_id (pre-computed)
                         → latch predict_taken=1 vào ID/EX register

Cycle N+1: Branch in EX  → evaluate actual branch_taken_ex
  Case CORRECT (taken=1): không flush thêm → total 1 cycle penalty ✓
  Case WRONG   (taken=0): flush IF/ID + ID/EX, redirect IFU→pc_plus_4_ex (fall-through)
                         → total 2 cycle penalty (1 prediction + 1 recovery)
```

### Fix 9A – `cpu/core/PIPELINE_REG_ID_EX.v`

Thêm `predict_taken` port để carry flag từ ID→EX:

```verilog
// Port additions:
input  wire predict_taken_in,
output reg  predict_taken_out,

// flush block: predict_taken_out <= 1'b0;
// latch block: predict_taken_out <= predict_taken_in;
```

### Fix 9B – `cpu/core/hazard_detection.v`

Thêm 3 inputs, modify 2 assigns:

```verilog
// New inputs:
input wire predict_taken_ex,   // branch was predicted taken (từ ID/EX reg)
input wire predict_taken_id,   // new backward branch prediction in ID
input wire mispredict_ex,      // predicted taken but actually not taken

// Modified flush_if_id (dòng 61):
assign flush_if_id = (branch_taken && !predict_taken_ex) || mispredict_ex || predict_taken_id;
//   → Khi correctly predicted: branch_taken=1 nhưng predict_taken_ex=1 → KHÔNG flush ✓

// Modified flush_id_ex (dòng 70, kết hợp với Fix 8):
assign flush_id_ex = load_use_hazard || (branch_taken && !predict_taken_ex) || mispredict_ex || fence_stall || mul_result_stall;
```

### Fix 9C – `cpu/riscv_cpu_core_v2.v`

Thêm wires + modify IFU connections + hazard_detection instantiation:

```verilog
// Wires mới (sau dòng 258):
wire predict_taken_ex;
wire predict_taken_id;
wire mispredict_ex;

assign predict_taken_id = branch_id && imm_id[31] && !stall_any;
assign mispredict_ex    = predict_taken_ex && !branch_taken_ex && branch_ex;

// IFU priority MUX (thay .pc_src + .target_pc):
wire        ifu_pc_src    = mispredict_ex || pc_src_ex || predict_taken_id;
wire [31:0] ifu_target_pc = mispredict_ex  ? pc_plus_4_ex  :
                            pc_src_ex      ? target_pc_ex  :
                                             branch_target_id;

// PIPELINE_REG_ID_EX thêm:
.predict_taken_in (predict_taken_id),
.predict_taken_out(predict_taken_ex),

// hazard_detection thêm:
.predict_taken_ex(predict_taken_ex),
.predict_taken_id(predict_taken_id),
.mispredict_ex   (mispredict_ex),
```

**Lưu ý:**
- `pc_plus_4_ex` đã có (dòng 510: `assign pc_plus_4_ex = pc_ex + 32'd4`)
- `branch_ex` đã có (output từ PIPELINE_REG_ID_EX)
- `!stall_any` guard trong `predict_taken_id` ngăn double-prediction khi branch bị stall trong ID

---

## Fix 10: Multiplier Logic-Depth Timing Fix

**Vấn đề (từ báo cáo physical design):**
- Logic depth 27 gates trong đường E1→E2 của multiplier (vượt budget 6ns)
- Fanout 133 tại bit sign `operand_a_e1_q[32]` → slew rate 3.28ns
- OR3/NAND4 standard cells với delay 1.14–1.5ns mỗi cổng

**Nguyên nhân gốc:** `wire [64:0] mult_result_w = ... * ...` (dòng 83–84, riscv_multiplier.v)
là phép nhân 65×65 bit hoàn toàn tổ hợp giữa 2 flip-flop E1 và E2.

**Giải pháp: 3-stage multiplier + mul_ex_stall**

Chèn thanh ghi trung gian E1.5 bằng cách phân rã 33×33 thành 4 phép nhân 17×17:

| Stage | Path | Gate depth |
|-------|------|------------|
| E1→E1.5 | 4× partial products (17×17 each) | ~10–12 |
| E1.5→E2 | CSA tree + final adder (sum 4 PP) | ~12–14 |

`mul_ex_stall` cho phép MUL ở lại EX 1 cycle bổ sung để E1.5 hoàn thành,
trong khi pipeline (IF/ID) bị freeze nhưng multiplier KHÔNG bị hold.

**Pipeline timing mới:**
```
Cycle N:   EX (cycle 1) → E1 latch, mul_ex_stall=1 (pipeline frozen, multiplier tiếp tục)
Cycle N+1: EX (cycle 2) → E1.5 latch (partial products); nếu dep đọc rd → mul_result_stall=1
Cycle N+2: MEM          → E2 latch (sum partial products); dep vào EX tại posedge N+2→N+3
Cycle N+3: WB           → result_e2_q valid, WB→EX forwarding đến dep ✓
```

**CPI impact:** +1 cycle per MUL instruction (mul_ex_stall); dependent stall vẫn 1 cycle (không đổi).

### Fix 10A – `cpu/core/riscv_multiplier.v`

Thêm port `mul_hold_e15_i`. Chèn stage E1.5 với 4 partial products từ E1 outputs:

```verilog
input wire mul_hold_e15_i,  // (stall_any && !mul_ex_stall) — allow E1.5 to advance during mul_ex_stall

// E1.5: split 33-bit operands into 17-bit halves
wire [16:0] a_lo = operand_a_e1_q[16:0];
wire [16:0] a_hi = operand_a_e1_q[32:16];
wire [16:0] b_lo = {1'b0, operand_b_e1_q[15:0]};
wire [16:0] b_hi = operand_b_e1_q[32:16];

// 4 partial products, each 17×17 ≤ 34 bits (~10–12 gate levels)
wire [33:0] pp_ll_w = $signed(a_lo) * $signed({1'b0, b_lo[15:0]});
wire [33:0] pp_lh_w = $signed(a_lo) * $signed(b_hi);
wire [33:0] pp_hl_w = $signed(a_hi) * $signed({1'b0, b_lo[15:0]});
wire [33:0] pp_hh_w = $signed(a_hi) * $signed(b_hi);

reg [33:0] pp_ll_e15_q, pp_lh_e15_q, pp_hl_e15_q, pp_hh_e15_q;
reg        mulhi_sel_e15_q;

always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
        pp_ll_e15_q <= 0; pp_lh_e15_q <= 0;
        pp_hl_e15_q <= 0; pp_hh_e15_q <= 0;
        mulhi_sel_e15_q <= 0;
    end else if (!mul_hold_e15_i) begin
        pp_ll_e15_q     <= pp_ll_w;
        pp_lh_e15_q     <= pp_lh_w;
        pp_hl_e15_q     <= pp_hl_w;
        pp_hh_e15_q     <= pp_hh_w;
        mulhi_sel_e15_q <= mulhi_sel_e1_q;
    end
end
```

Thay phép nhân tổ hợp bằng tổng partial products (E1.5→E2):

```verilog
// Sum 4 partial products with shifts (~12–14 gate levels via CSA tree)
wire [64:0] mult_result_w =
    {{31{pp_ll_e15_q[33]}}, pp_ll_e15_q}
  + {{14{pp_lh_e15_q[33]}}, pp_lh_e15_q, 17'b0}
  + {{14{pp_hl_e15_q[33]}}, pp_hl_e15_q, 16'b0}
  + {{14{pp_hh_e15_q[33]}}, pp_hh_e15_q, 32'b0};

wire [31:0] result_r = mulhi_sel_e15_q ? mult_result_w[63:32] : mult_result_w[31:0];
```

Thêm `(* keep=1 *)` trên sign bits để giảm fanout từ 133:

```verilog
(* keep = 1 *) wire sign_a = operand_a_e1_q[32];
(* keep = 1 *) wire sign_b = operand_b_e1_q[32];
```

> **Lưu ý:** Bit widths và sign handling của 4 partial products cần được verify bằng
> testbench (MUL / MULH / MULHSU / MULHU với positive/negative operands) trước khi tích hợp.

### Fix 10B – `cpu/core/hazard_detection.v`

Thêm `clk/rst` ports, output `mul_ex_stall`, register `mul_ex_stall_done_r`:

```verilog
input  wire clk,
input  wire rst,
output wire mul_ex_stall,

reg mul_ex_stall_done_r;

always @(posedge clk or posedge rst) begin
    if (rst)             mul_ex_stall_done_r <= 1'b0;
    else if (!mul_in_ex) mul_ex_stall_done_r <= 1'b0;  // reset khi MUL rời EX
    else                 mul_ex_stall_done_r <= 1'b1;  // latch sau cycle đầu tiên
end

assign mul_ex_stall = mul_in_ex && !mul_ex_stall_done_r;

// Thêm mul_ex_stall vào assign stall:
assign stall = load_use_hazard || mem_load_stall || lsu_dependency_stall
             || fence_stall || mul_result_stall || mul_ex_stall;
// KHÔNG thêm mul_ex_stall vào flush_id_ex (chỉ freeze, không insert bubble)
```

### Fix 10C – `cpu/riscv_cpu_core_v2.v`

```verilog
// Wire mới:
wire mul_ex_stall_wire;
wire mul_hold = stall_any && !mul_ex_stall_wire;  // don't freeze multiplier during its own stall

// hazard_detection: thêm clk/rst/mul_ex_stall
.clk         (clk),
.rst         (rst),
.mul_ex_stall(mul_ex_stall_wire),

// multiplier_unit: thay hold_i, thêm mul_hold_e15_i
.hold_i         (mul_hold),        // was: stall_any
.mul_hold_e15_i (mul_hold),        // NEW
```

---

## Files thay đổi

| File | Changes |
|------|---------|
| `cpu/core/hazard_detection.v` | Fix 8: remove mem_load_stall; Fix 9B: prediction-aware flush; Fix 10B: mul_ex_stall |
| `cpu/core/PIPELINE_REG_ID_EX.v` | Fix 9A: add predict_taken port |
| `cpu/riscv_cpu_core_v2.v` | Fix 9C: wires + IFU mux + instantiation updates; Fix 10C: mul_ex_stall wiring |
| `cpu/core/riscv_multiplier.v` | Fix 10A: E1.5 stage, partial product decomposition, fanout fix |

---

## Verification

Sau khi implement, chạy lại simulation và kiểm tra:
1. Cycle count giảm ~13 cycles so với baseline 4980 (Fix 9, expect ~4967)
2. `.L2` loop hoàn thành đúng 16 iterations (kết quả ASCON không đổi)
3. `.L4` loop exit đúng, S2 ASCON reads vẫn = 3
4. BNE/BEQ với forward branch (imm dương) không bị predict → hoạt động bình thường
5. JAL/JALR không bị ảnh hưởng (branch_id=0 → predict_taken_id=0)
6. MUL / MULH / MULHSU / MULHU cho kết quả đúng với positive/negative operands (Fix 10)
7. Back-to-back `MUL x3,x1,x2 / ADD x4,x3,x5` stall đúng 1 cycle (Fix 10 hazard)
8. Synthesis timing report: critical path E1→E1.5 và E1.5→E2 đều < 6ns
9. Fanout report: không còn net nào > 50 trong multiplier path
