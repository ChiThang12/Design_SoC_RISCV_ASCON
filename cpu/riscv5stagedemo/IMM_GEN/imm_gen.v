// ============================================================================
// IMM_GEN.v - RISC-V Immediate Generator
// ============================================================================
// Mô tả: Trích xuất và sign-extend immediate từ instruction
// Hỗ trợ: I-type, S-type, B-type, U-type, J-type
// ============================================================================

module imm_gen (
    input wire [31:0] instr,        // Instruction 32-bit
    output reg [31:0] imm           // Immediate value (sign-extended)
);

    // ========================================================================
    // RISC-V Opcode Definition
    // ========================================================================
    localparam [6:0]
        OP_R_TYPE   = 7'b0110011,    // R-type (không có immediate)
        OP_I_TYPE   = 7'b0010011,    // I-type: ADDI, ANDI, ORI, etc.
        OP_LOAD     = 7'b0000011,    // I-type: LW, LH, LB
        OP_JALR     = 7'b1100111,    // I-type: JALR
        OP_STORE    = 7'b0100011,    // S-type: SW, SH, SB
        OP_BRANCH   = 7'b1100011,    // B-type: BEQ, BNE, BLT, etc.
        OP_LUI      = 7'b0110111,    // U-type: LUI
        OP_AUIPC    = 7'b0010111,    // U-type: AUIPC
        OP_JAL      = 7'b1101111;    // J-type: JAL
    
    wire [6:0] opcode = instr[6:0];
    
    // ========================================================================
    // Immediate Generation Logic
    // ========================================================================
    always @(*) begin
        case (opcode)
            // ================================================================
            // I-TYPE: 12-bit immediate
            // Format: imm[11:0] = instr[31:20]
            // Sign-extend từ bit 31
            // ================================================================
            OP_I_TYPE, OP_LOAD, OP_JALR: begin
                imm = {{20{instr[31]}}, instr[31:20]};
            end
            
            // ================================================================
            // S-TYPE: Store instructions (12-bit immediate)
            // Format: imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
            // Sign-extend từ bit 31
            // ================================================================
            OP_STORE: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            
            // ================================================================
            // B-TYPE: Branch instructions (13-bit immediate, always even)
            // Format: imm[12] = instr[31]
            //         imm[11] = instr[7]
            //         imm[10:5] = instr[30:25]
            //         imm[4:1] = instr[11:8]
            //         imm[0] = 0 (luôn chẵn)
            // Sign-extend từ bit 31
            // ================================================================
            OP_BRANCH: begin
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end
            
            // ================================================================
            // U-TYPE: Upper immediate (20-bit immediate)
            // Format: imm[31:12] = instr[31:12], imm[11:0] = 0
            // Dùng cho LUI và AUIPC
            // ================================================================
            OP_LUI, OP_AUIPC: begin
                imm = {instr[31:12], 12'b0};
            end
            
            // ================================================================
            // J-TYPE: Jump (JAL) (21-bit immediate, always even)
            // Format: imm[20] = instr[31]
            //         imm[19:12] = instr[19:12]
            //         imm[11] = instr[20]
            //         imm[10:1] = instr[30:21]
            //         imm[0] = 0 (luôn chẵn)
            // Sign-extend từ bit 31
            // ================================================================
            OP_JAL: begin
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end
            
            // ================================================================
            // R-TYPE và các opcode khác: không có immediate
            // ================================================================
            default: begin
                imm = 32'h00000000;
            end
        endcase
    end

endmodule