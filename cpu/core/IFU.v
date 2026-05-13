`timescale 1ns/1ps

module IFU (
    // --- Clock & Reset ---
    input  wire        clock,
    input  wire        reset,
    
    // --- Control inputs ---
    input  wire        pc_src,           // 0: PC+4, 1: target_pc (branch/jump)
    input  wire        stall,            // 1: hold PC (pipeline stall)
    
    // --- Data inputs ---
    input  wire [31:0] target_pc,        // Branch/jump target address

    // --- Instruction Memory Interface ---
    output wire [31:0] imem_addr,       // Address to instruction memory
    output wire        imem_valid,      // Request valid (always 1)
    input  wire [31:0] imem_rdata,      // Instruction data from memory
    input  wire        imem_ready,      // Memory ready signal

    // --- Outputs to pipeline ---
    output wire [31:0] PC_out,          // Current PC
    output wire [31:0] Instruction_Code // Fetched instruction (combinational)
);

    // ========================================================================
    // Program Counter Register
    // ========================================================================
    reg [31:0] PC;

    wire [31:0] next_pc;
    assign next_pc = pc_src ? target_pc : (PC + 32'd4);

    // ========================================================================
    // Instruction Memory Interface
    // ========================================================================
    assign imem_addr  = PC;
    assign imem_valid = 1'b1;

    // ========================================================================
    // PC Update
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset)
            PC <= 32'h00000000;
        else if (!stall && imem_ready)
            PC <= next_pc;
        else
            PC <= PC; 
    end

    // ========================================================================
    // Instruction Hold Register — keeps last valid instruction on cache miss
    // ========================================================================
    reg [31:0] instr_hold;

    always @(posedge clock or posedge reset) begin
        if (reset)
            instr_hold <= 32'h00000013; // NOP
        else if (imem_ready && !stall)
            instr_hold <= imem_rdata;
        else 
            instr_hold <= instr_hold;
    end

    // Combinational output: direct from memory when ready, else held value
    assign Instruction_Code = (imem_ready && !stall) ? imem_rdata : instr_hold;

    // PC output: directly from PC register
    assign PC_out = PC;

endmodule