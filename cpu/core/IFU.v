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

    // ========================================================================
    // [FIX-REDIRECT-STALL] Redirect Latch
    //
    // BUG (pre-fix): pc_src is a combinational pulse from EX stage, active for
    // exactly 1 cycle when a branch/jump resolves.  If the IFU is stalled
    // during that cycle (ICache miss or pipeline stall), the PC update is
    // blocked and the redirect target is lost.  The IFU then continues
    // sequential execution from the wrong PC.
    //
    // FIX: Latch the redirect target when pc_src fires but the IFU cannot
    // accept it.  When the stall clears, apply the latched target instead of
    // PC+4.  A new pc_src always overwrites any pending latch (latest wins).
    // ========================================================================
    reg        redirect_pending;
    reg [31:0] redirect_target;

    wire       ifu_can_advance = !stall && imem_ready;
    wire       redirect_now    = pc_src || redirect_pending;
    wire [31:0] next_pc        = redirect_now
                                 ? (pc_src ? target_pc : redirect_target)
                                 : (PC + 32'd4);

    // ========================================================================
    // Instruction Memory Interface
    // ========================================================================
    assign imem_addr  = PC;
    assign imem_valid = 1'b1;

    // ========================================================================
    // PC Update + Redirect Latch
    // ========================================================================
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            PC               <= 32'h00000000;
            redirect_pending <= 1'b0;
            redirect_target  <= 32'h0;
        end else if (ifu_can_advance) begin
            // IFU is advancing: apply next_pc (which includes any redirect)
            PC               <= next_pc;
            redirect_pending <= 1'b0;
        end else if (pc_src) begin
            // IFU is stalled but a redirect arrived: latch it
            redirect_pending <= 1'b1;
            redirect_target  <= target_pc;
        end
        // else: stalled, no new redirect — hold PC and pending state
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