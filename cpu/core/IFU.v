module IFU (
    input wire clock,
    input wire reset,
    
    // Control signals
    input wire pc_src,              // 0: PC+4 (sequential), 1: target_pc (branch/jump)
    input wire stall,               // 1: giữ nguyên PC (pipeline stall)
    
    // Branch/Jump target address
    input wire [31:0] target_pc,    // Địa chỉ nhảy đến
    
    // AXI-Like Instruction Memory Interface
    output reg [31:0] imem_addr,    // Address to instruction memory
    output reg imem_valid,          // Request valid
    input wire [31:0] imem_rdata,   // Instruction data from memory
    input wire imem_ready,          // Memory ready signal
    
    // Outputs
    output reg [31:0] PC_out,       // Current PC (PC của instruction đang được fetch)
    output reg [31:0] Instruction_Code  // Instruction được fetch
);

    // ========================================================================
    // Program Counter Register
    // ========================================================================
    reg [31:0] PC;
    
    // CRITICAL FIX: Lưu PC của instruction hiện tại trước khi advance
    reg [31:0] PC_current_instr;
    
    // ========================================================================
    // Next PC Calculation
    // ========================================================================
    wire [31:0] next_pc;
    
    // Logic tính next_pc:
    // - Nếu stall=1: giữ nguyên PC
    // - Nếu pc_src=1: nhảy đến target_pc (branch/jump)
    // - Nếu pc_src=0: PC + 4 (sequential)
    assign next_pc = stall ? PC : 
                     pc_src ? target_pc : 
                     PC + 32'd4;
    
    // ========================================================================
    // Simplified Memory Interface
    // ========================================================================
    // Always output current PC and request instruction
    always @(*) begin
        imem_addr = PC;
        imem_valid = 1'b1;  // Always valid
    end
    
    // ========================================================================
    // Program Counter Update
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            PC <= 32'h00000000;
            PC_current_instr <= 32'h00000000;
        end else begin
            // CRITICAL: Lưu PC hiện tại TRƯỚC KHI cập nhật
            // PC này tương ứng với instruction sẽ được latch ở cycle này
            if (!stall) begin
                PC_current_instr <= PC;
            end
            
            // Cập nhật PC cho cycle tiếp theo
            if (stall) begin
                PC <= PC;  // Hold PC when stalled
            end else if (pc_src) begin
                PC <= target_pc;  // Branch/Jump takes priority
            end else begin
                PC <= PC + 32'd4;  // Sequential increment
            end
        end
    end
    
    // ========================================================================
    // Instruction Latch
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            Instruction_Code <= 32'h00000013; // NOP
        end else if (stall) begin
            Instruction_Code <= Instruction_Code;  // Hold instruction
        end else begin
            Instruction_Code <= imem_rdata;  // Always latch new instruction
        end
    end
    
    // ========================================================================
    // Output Current PC - PC của instruction hiện tại được output
    // ========================================================================
    always @(*) begin
        // CRITICAL FIX: Output PC của instruction hiện tại, không phải PC đã advance
        PC_out = PC_current_instr;
    end

endmodule