module hazard_detection (
    // Inputs for Load-Use Hazard Detection
    input memread_id_ex,              // Signal indicating load instruction in EX stage
    input [4:0] rd_id_ex,             // Destination register in ID/EX stage
    input [4:0] rs1_id,               // Source register 1 in ID stage
    input [4:0] rs2_id,               // Source register 2 in ID stage
    
    // Input for Control Hazard Detection
    input branch_taken,               // Signal indicating branch is taken
    
    // Outputs
    output reg stall,                 // Stall signal for pipeline
    output reg flush_if_id,           // Flush IF/ID pipeline register
    output reg flush_id_ex            // Flush ID/EX pipeline register
);

    // Hazard Detection Logic
    always @(*) begin
        // Default values
        stall = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;
        
        // ===== Load-Use Hazard Detection =====
        // Check if there's a load instruction in EX stage that creates a data hazard
        // with the current instruction in ID stage
        if (memread_id_ex && 
            ((rd_id_ex == rs1_id && rs1_id != 5'b0) || 
             (rd_id_ex == rs2_id && rs2_id != 5'b0))) begin
            // Load-Use Hazard detected
            stall = 1'b1;           // Stall the pipeline (PC and IF/ID register)
            flush_id_ex = 1'b1;     // Insert bubble in ID/EX stage (NOP)
        end
        
        // ===== Control Hazard Detection =====
        // When branch is taken, flush the incorrectly fetched instructions
        if (branch_taken) begin
            flush_if_id = 1'b1;     // Flush IF/ID register
            flush_id_ex = 1'b1;     // Flush ID/EX register
            stall = 1'b0;           // No stall needed, just flush
        end
    end

endmodule