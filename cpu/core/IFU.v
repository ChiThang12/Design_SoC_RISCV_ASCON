`include "src/inst_mem.v"
module IFU (
    input wire clock,
    input wire reset,
    
    // Control signals
    input wire pc_src,              // 0: PC+4 (sequential), 1: target_pc (branch/jump)
    input wire stall,               // 1: giữ nguyên PC (pipeline stall)
    
    // Branch/Jump target address
    input wire [31:0] target_pc,    // Địa chỉ nhảy đến
    
    // Outputs
    output reg [31:0] PC_out,       // Current PC
    output wire [31:0] Instruction_Code  // Instruction được fetch
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
    // - Nếu stall=1: giữ nguyên PC
    // - Nếu pc_src=1: nhảy đến target_pc (branch/jump)
    // - Nếu pc_src=0: PC + 4 (sequential)
    assign next_pc = stall ? PC : 
                     pc_src ? target_pc : 
                     PC + 32'd4;
    
    // ========================================================================
    // Program Counter Update
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            PC <= 32'h00000000;     // Reset PC về địa chỉ 0x00000000
        end
        else begin
            PC <= next_pc;          // Cập nhật PC
        end
    end
    
    // ========================================================================
    // Output Current PC
    // ========================================================================
    always @(*) begin
        PC_out = PC;
    end
    
    // ========================================================================
    // Instruction Memory (FIXED: Added reset signal)
    // ========================================================================
    inst_mem inst_memory (
        .PC({PC[31:2],2'b00}),       // Địa chỉ word (chia 4, bỏ 2 bit thấp)
        .reset(reset),               // ADDED: Reset signal
        .Instruction_Code(Instruction_Code)
    );

endmodule


