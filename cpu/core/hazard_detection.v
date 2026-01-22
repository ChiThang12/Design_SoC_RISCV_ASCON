module hazard_detection (
    // Load-use hazard inputs
    input wire memread_id_ex,
    input wire [4:0] rd_id_ex,
    input wire [4:0] rs1_id,
    input wire [4:0] rs2_id,
    
    // Branch/Jump control
    input wire branch_taken,
    
    // Memory interface (NEW)
    input wire imem_ready,
    input wire dmem_ready,
    input wire dmem_valid,
    
    // Control outputs
    output reg stall,
    output reg flush_if_id,
    output reg flush_id_ex
);

    // ========================================================================
    // Detect Load-Use Hazard
    // ========================================================================
    wire load_use_hazard;
    
    assign load_use_hazard = memread_id_ex && 
                            ((rd_id_ex == rs1_id && rs1_id != 5'b0) ||
                             (rd_id_ex == rs2_id && rs2_id != 5'b0));
    
    // ========================================================================
    // Detect Memory Stall
    // CRITICAL: Stall khi đang đợi memory response
    // ========================================================================
    wire imem_stall = !imem_ready;
    wire dmem_stall = dmem_valid && !dmem_ready;
    
    // ========================================================================
    // Combine All Stall Conditions
    // ========================================================================
    always @(*) begin
        // Stall nếu:
        // 1. Load-use hazard
        // 2. Instruction memory chưa ready
        // 3. Data memory đang được access nhưng chưa ready
        stall = load_use_hazard || imem_stall || dmem_stall;
    end
    
    // ========================================================================
    // Flush Control
    // ========================================================================
    always @(*) begin
        // Flush IF/ID khi branch/jump taken
        flush_if_id = branch_taken;
        
        // Flush ID/EX khi branch/jump taken hoặc load-use hazard
        flush_id_ex = branch_taken || load_use_hazard;
    end

endmodule