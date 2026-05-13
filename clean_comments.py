import re

with open('/home/chithang/Project/Design_SoC_RISCV_ASCON/cpu/riscv_cpu_core_v2.v', 'r') as f:
    content = f.read()

# Replace IRQ block
content = re.sub(
    r'// =========================================================================\n\s*// IRQ aggregation [^\n]+\n\s*// Prevents metastability [^\n]+\n\s*// Adds 2-cycle latency [^\n]+\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: IRQ Synchronizer\n    // STAGE: Global\n    // =========================================================================',
    content
)

# Replace Debug Mode FSM block
content = re.sub(
    r'// =========================================================================\n\s*// DEBUG MODE FSM.*?(?=reg dbg_halt_s1)',
    '// =========================================================================\n    // BLOCK: Debug Mode FSM\n    // STAGE: Global\n    // =========================================================================\n    ',
    content,
    flags=re.DOTALL
)

# Remove the long Vietnamese states comment
content = re.sub(
    r'\s*// 3 trạng thái:.*?(?=localparam DBG_RUNNING = 2\'b00;)',
    '\n    ',
    content,
    flags=re.DOTALL
)

# Remove WHY cần lsu_sb_empty
content = re.sub(
    r'\s*// WHY cần lsu_sb_empty.*?(?=wire lsu_sb_empty_w)',
    '\n    ',
    content,
    flags=re.DOTALL
)

# Remove inline FSM comments
content = re.sub(r'\s*// Chờ bus idle trước khi bước vào HALTING', '', content)
content = re.sub(r'\s*// 1-cycle drain: stall đã được assert từ cycle trước.*?\n\s*// Sang HALTED và bật debug_mode để freeze pipeline hoàn toàn', '', content, flags=re.DOTALL)
content = re.sub(r'\s*// WHY check !dbg_halt_s2: DM có thể giữ haltreq=1 nhiều.*?\n\s*// cycle. Chỉ resume khi resumereq pulse xuất hiện.', '', content, flags=re.DOTALL)

# Replace Pipeline stage wires
content = re.sub(
    r'// =========================================================================\n\s*// Pipeline stage wires\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Pipeline Stage Wires\n    // STAGE: Global\n    // =========================================================================',
    content
)

# Replace FENCE-TYPE
content = re.sub(
    r'// =========================================================================\n\s*// \[FENCE-TYPE\] Decode pred/succ bits từ FENCE instruction\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Fence Type Decoder\n    // STAGE: 2 (ID)\n    // =========================================================================',
    content
)

# Remove Decode true source usage early...
content = re.sub(r'\s*// Decode true source usage early so hazard detection does not treat\n\s*// immediate bits as rs2 dependencies on I-type instructions.', '', content)

# Remove MUL pipeline tracking comment
content = re.sub(r'\s*// MUL pipeline tracking', '', content)

# Remove stall_any includes...
content = re.sub(r'\s*// stall_any includes debug_mode and WFI idle state to freeze the pipeline.', '', content)

# Remove 2-bit BHT predictor comment
content = re.sub(r'\s*// 2-bit BHT predictor: 256 entries, indexed by PC\[9:2\]\.', '', content)

# Remove Guard with !stall_any...
content = re.sub(r'\s*// Guard with !stall_any to prevent re-predicting the same stalled branch\.', '', content)

# Remove IFU redirect priority...
content = re.sub(r'\s*// IFU redirect priority: mispredict recovery > actual branch/jump > WFI consume > prediction', '', content)

# Remove Fix 10C...
content = re.sub(r'\s*// Fix 10C: Multiplier stall — don\'t freeze multiplier during its own extra cycle', '', content)

# Remove stall_ex_mem: only LSU...
content = re.sub(r'\s*// stall_ex_mem: only LSU dependency stall freezes EX/MEM\n\s*// \(fence_stall must NOT freeze — pre-fence store must reach MEM\)', '', content)

# Remove [FIX-JALR-TARGET]...
content = re.sub(r'\s*// \[FIX-JALR-TARGET\].*?(?=wire is_jalr_ex)', '\n    ', content, flags=re.DOTALL)

# STAGE 1: IF
content = re.sub(
    r'// =========================================================================\n\s*// STAGE 1: IF\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Instruction Fetch Unit (IFU)\n    // STAGE: 1 (IF)\n    // =========================================================================',
    content
)

# STAGE 2: ID
content = re.sub(
    r'// =========================================================================\n\s*// STAGE 2: ID\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Decode Unit & Register File\n    // STAGE: 2 (ID)\n    // =========================================================================',
    content
)

# ID/EX PIPELINE REGISTER
content = re.sub(
    r'// =========================================================================\n\s*// ID/EX PIPELINE REGISTER \(standalone module\)\n\s*// =========================================================================\n\s*// Pre-compute branch target in ID stage to remove adder from EX critical path\.\n\s*// pc_id and imm_id are both available here; result passes through ID/EX register\.',
    '// =========================================================================\n    // BLOCK: ID/EX Pipeline Register\n    // STAGE: 2-3 (ID/EX)\n    // =========================================================================',
    content
)

# STAGE 3: EX
content = re.sub(
    r'// =========================================================================\n\s*// STAGE 3: EX\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: ALU & Forwarding Unit\n    // STAGE: 3 (EX)\n    // =========================================================================',
    content
)

# Remove Flat AND-OR mux...
content = re.sub(r'\s*// Flat AND-OR mux: expand WB source inline to eliminate cascaded mux levels\.\n\s*// OLD: alu_in1_forwarded \(3-way\) → alu_in1 \(3-way\) = 4 extra gate levels on critical path\.\n\s*// NEW: single 8-way OR of AND terms, all selectors mutually exclusive\.', '', content)

content = re.sub(r'\s*// Kept for multiplier operands, store data, and ID/EX forwarding-capture port', '', content)
content = re.sub(r'\s*// WB source selectors \(shared between alu_in1 and alu_in2 paths\)', '', content)
content = re.sub(r'\s*// alu_in1: 8 mutually exclusive cases \(LUI / AUIPC / MEM-fwd / WB×4 / RF\)', '', content)
content = re.sub(r'\s*// alu_in2: 7 mutually exclusive cases \(IMM / MEM-fwd / WB×4 / RF\)', '', content)

# 2-stage Pipelined Multiplier
content = re.sub(
    r'// =========================================================================\n\s*// 2-stage Pipelined Multiplier \(tách khỏi ALU critical path\)\n\s*// =========================================================================\n\s*// is_mul_ex: MUL/MULH instruction at EX stage\n\s*// mul_op_ex: 00=MUL, 01=MULH \(signed×signed high\)\n\s*// mul_valid_ex: dispatch pulse — high for 1 cycle when MUL enters EX',
    '// =========================================================================\n    // BLOCK: Multiplier Unit\n    // STAGE: 3 (EX)\n    // =========================================================================',
    content
)
content = re.sub(r'\s*// mul_valid_ex uses mul_hold \(not stall_any\) so E1 fires on cycle N even\n\s*// though mul_ex_stall=1 makes stall_any=1 on that cycle\.', '', content)

content = re.sub(r'\s*// branch_target_ex = pc_id \+ imm_id, pre-computed in ID stage to remove\n\s*// this adder from the EX stage critical path\.', '', content)


# EX/MEM PIPELINE REGISTER
content = re.sub(
    r'// =========================================================================\n\s*// EX/MEM PIPELINE REGISTER \(standalone module\)\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: EX/MEM Pipeline Register\n    // STAGE: 3-4 (EX/MEM)\n    // =========================================================================',
    content
)

# STAGE 4: MEM
content = re.sub(
    r'// =========================================================================\n\s*// STAGE 4: MEM — via LSU\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Load Store Unit (LSU)\n    // STAGE: 4 (MEM)\n    // =========================================================================',
    content
)

content = re.sub(r'\s*// \[FIX-BYTELANE\] Store byte strobe', '', content)
content = re.sub(r'\s*// \[FIX-BYTELANE\] Store data shift', '', content)
content = re.sub(r'\s*// \[FIX-DOUBLE-ISSUE\].*?(?=reg        lsu_req_sent;)', '\n    ', content, flags=re.DOTALL)
content = re.sub(r'\s*// fence reaches LSU only after hazard logic has observed quiescent LSU\.\n\s*// This keeps FENCE from blocking pre-existing load/store drain activity\.', '', content)

# MEM/WB REGISTER
content = re.sub(
    r'// =========================================================================\n\s*// MEM/WB REGISTER \(standalone module\)\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: MEM/WB Pipeline Register\n    // STAGE: 4-5 (MEM/WB)\n    // =========================================================================',
    content
)

content = re.sub(r'\s*// Hold LSU result until MEM/WB is free so loads do not clobber ALU/MUL WB\.', '', content)

# STAGE 5: WB
content = re.sub(
    r'// =========================================================================\n\s*// STAGE 5: WB\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Write Back Unit\n    // STAGE: 5 (WB)\n    // =========================================================================',
    content
)

content = re.sub(r'\s*// AND-OR MUX: 4 cases mutually exclusive \(jump/mul/load/alu can\'t overlap\)\.\n\s*// is_alu_wb is the complement so selectors are exhaustive \(Fix 11\)\.', '', content)

# HAZARD DETECTION UNIT
content = re.sub(
    r'// =========================================================================\n\s*// HAZARD DETECTION UNIT\n\s*// =========================================================================',
    '// =========================================================================\n    // BLOCK: Hazard Detection Unit\n    // STAGE: Global\n    // =========================================================================',
    content
)

# Specific inline comments removal (like inline // [FIX-WB-NOP])
content = re.sub(r'\s*// \[FIX-WB-NOP\].*?(?=\n)', '', content)
content = re.sub(r'\s*// \(debug_mode → stall_any → IFU dừng fetch\)', '', content)
content = re.sub(r'\s*// Forwarding capture \(FIX-FWD-STALL\)', '', content)
content = re.sub(r'\s*// Control inputs', '', content)
content = re.sub(r'\s*// Data inputs', '', content)
content = re.sub(r'\s*// Register addresses', '', content)
content = re.sub(r'\s*// Function codes', '', content)
content = re.sub(r'\s*// Control outputs', '', content)
content = re.sub(r'\s*// Data outputs', '', content)
content = re.sub(r'\s*// Register address outputs', '', content)
content = re.sub(r'\s*// Function code outputs', '', content)
content = re.sub(r'\s*// Output signals cho jtag_debug_top', '', content)

with open('/home/chithang/Project/Design_SoC_RISCV_ASCON/cpu/riscv_cpu_core_v2.v', 'w') as f:
    f.write(content)

print("Done")
