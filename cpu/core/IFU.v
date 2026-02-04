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
    
    // ========================================================================
    // Next PC Calculation
    // ========================================================================
    wire [31:0] next_pc;
    
    // Logic tính next_pc:
    // - Nếu pc_src=1: nhảy đến target_pc (branch/jump)
    // - Nếu pc_src=0: PC + 4 (sequential)
    assign next_pc = pc_src ? target_pc : (PC + 32'd4);
    
    // ========================================================================
    // Memory Interface - Always output current PC and request
    // ========================================================================
    always @(*) begin
        imem_addr = PC;
        imem_valid = 1'b1;  // Always requesting
    end
    
    // ========================================================================
    // Program Counter Update
    // CRITICAL FIX: Chỉ cập nhật PC khi imem_ready=1 (instruction fetch complete)
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            PC <= 32'h00000000;
        end else begin
            // Chỉ cập nhật PC khi:
            // 1. Không bị stall
            // 2. Memory đã sẵn sàng (imem_ready = 1)
            if (!stall && imem_ready) begin
                PC <= next_pc;
            end
            // Nếu stall hoặc memory chưa ready, giữ nguyên PC
        end
    end
    
    // ========================================================================
    // Instruction Latch
    // CRITICAL FIX: Chỉ latch instruction mới khi imem_ready=1
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            Instruction_Code <= 32'h00000013; // NOP
        end else if (stall) begin
            Instruction_Code <= Instruction_Code;  // Hold instruction khi stall
        end else if (imem_ready) begin
            Instruction_Code <= imem_rdata;  // Latch instruction mới khi ready
        end
        // Nếu không ready và không stall, giữ nguyên instruction cũ
    end
    
    // ========================================================================
    // PC Output - Output PC hiện tại
    // ========================================================================
    always @(*) begin
        PC_out = PC;
    end

endmodule