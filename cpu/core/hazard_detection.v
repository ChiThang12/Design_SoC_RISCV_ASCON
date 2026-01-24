// ============================================================================
// hazard_detection.v - Pipeline Hazard Detection Unit (FIXED)
// ============================================================================
// Description:
//   Detects and handles pipeline hazards:
//   1. Load-use hazard (stall 1 cycle)
//   2. Branch/Jump taken (flush IF/ID and ID/EX)
//   3. Memory access not ready (stall until dmem_ready)
//   4. Instruction fetch not ready (stall until imem_ready)
//
// CRITICAL FIX: Memory stall only when transaction is PENDING
//   - Stall when: dmem_valid && !dmem_ready (transaction in progress)
//   - Continue when: dmem_ready (transaction complete)
// ============================================================================

module hazard_detection (
    // Load-use hazard detection
    input wire        memread_id_ex,    // EX stage is doing load
    input wire [4:0]  rd_id_ex,         // EX stage destination register
    input wire [4:0]  rs1_id,           // ID stage source 1
    input wire [4:0]  rs2_id,           // ID stage source 2
    
    // Branch/Jump flush
    input wire        branch_taken,     // Branch or jump taken in EX stage
    
    // Memory interface
    input wire        imem_ready,       // Instruction memory ready
    input wire        dmem_ready,       // Data memory ready
    input wire        dmem_valid,       // Data memory request valid
    
    // Control outputs
    output wire       stall,            // Stall pipeline (PC, IF/ID)
    output wire       flush_if_id,      // Flush IF/ID register
    output wire       flush_id_ex       // Flush ID/EX register (insert bubble)
);

    // ========================================================================
    // Load-Use Hazard Detection
    // ========================================================================
    // Detect when:
    //   - EX stage has a LOAD instruction (memread_id_ex = 1)
    //   - ID stage instruction uses the load result (rs1 or rs2 == rd_ex)
    // Solution: Stall 1 cycle to allow load to reach MEM stage
    
    wire load_use_hazard;
    assign load_use_hazard = memread_id_ex && 
                             (rd_id_ex != 5'b0) &&
                             ((rd_id_ex == rs1_id) || (rd_id_ex == rs2_id));
    
    // ========================================================================
    // Memory Access Stall
    // ========================================================================
    // CRITICAL FIX: Only stall when memory transaction is PENDING
    // - dmem_valid = 1: CPU wants to access memory
    // - dmem_ready = 0: Memory is not ready yet
    // - Stall until dmem_ready = 1
    
    wire dmem_stall;
    assign dmem_stall = dmem_valid && !dmem_ready;
    
    // ========================================================================
    // Instruction Fetch Stall
    // ========================================================================
    // Stall when instruction memory is not ready
    
    wire imem_stall;
    assign imem_stall = !imem_ready;
    
    // ========================================================================
    // Combined Stall Signal
    // ========================================================================
    // Stall pipeline when:
    //   1. Load-use hazard detected
    //   2. Data memory access pending (dmem_valid && !dmem_ready)
    //   3. Instruction memory not ready
    
    assign stall = load_use_hazard || dmem_stall || imem_stall;
    
    // ========================================================================
    // Flush Signals
    // ========================================================================
    // Flush IF/ID when branch/jump taken
    assign flush_if_id = branch_taken;
    
    // Flush ID/EX (insert bubble) when:
    //   1. Load-use hazard (convert ID instruction to NOP)
    //   2. Branch/jump taken (kill instruction in ID stage)
    assign flush_id_ex = load_use_hazard || branch_taken;

endmodule