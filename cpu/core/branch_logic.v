// module branch_logic (
//     // Control signal
//     input branch,                     // Branch instruction signal
    
//     // Branch type (funct3)
//     input [2:0] funct3,              // Function code to determine branch type
    
//     // Comparison flags from ALU
//     input zero_flag,                 // Result is zero (rs1 == rs2)
//     input less_than,                 // Signed comparison (rs1 < rs2)
//     input less_than_u,               // Unsigned comparison (rs1 < rs2)
    
//     // Output
//     output reg taken                 // Branch taken decision
// );

//     // RISC-V Branch funct3 codes
//     localparam [2:0] BEQ  = 3'b000;  // Branch if Equal
//     localparam [2:0] BNE  = 3'b001;  // Branch if Not Equal
//     localparam [2:0] BLT  = 3'b100;  // Branch if Less Than (signed)
//     localparam [2:0] BGE  = 3'b101;  // Branch if Greater or Equal (signed)
//     localparam [2:0] BLTU = 3'b110;  // Branch if Less Than (unsigned)
//     localparam [2:0] BGEU = 3'b111;  // Branch if Greater or Equal (unsigned)

//     // Branch decision logic
//     always @(*) begin
//         taken = 1'b0;  // Default: don't take branch
        
//         // Only evaluate branch condition if branch signal is asserted
//         // This prevents non-branch instructions from being mistakenly detected as branches
//         if (branch == 1'b1) begin
//             case (funct3)
//                 BEQ:  taken = zero_flag;        // Take if rs1 == rs2
//                 BNE:  taken = ~zero_flag;       // Take if rs1 != rs2
//                 BLT:  taken = less_than;        // Take if rs1 < rs2 (signed)
//                 BGE:  taken = ~less_than;       // Take if rs1 >= rs2 (signed)
//                 BLTU: taken = less_than_u;      // Take if rs1 < rs2 (unsigned)
//                 BGEU: taken = ~less_than_u;     // Take if rs1 >= rs2 (unsigned)
//                 default: taken = 1'b0;          // Invalid funct3
//             endcase
//         end
//         // If branch == 0, taken stays 0 (no branch for non-branch instructions)
//     end

// endmodule
// ============================================================================
// branch_logic.v - Branch Condition Evaluator (FIXED)
// ============================================================================

module branch_logic (
    input wire        branch,        // Branch instruction (from control)
    input wire [2:0]  funct3,        // Function field (branch type)
    input wire        zero_flag,     // Zero flag from ALU
    input wire        less_than,     // Signed less than from ALU
    input wire        less_than_u,   // Unsigned less than from ALU
    output reg        taken          // Branch taken signal
);

    // ========================================================================
    // Branch Condition Evaluation
    // ========================================================================
    // funct3 encoding:
    //   000 = BEQ  (branch if equal)
    //   001 = BNE  (branch if not equal)
    //   100 = BLT  (branch if less than, signed)
    //   101 = BGE  (branch if greater or equal, signed)
    //   110 = BLTU (branch if less than, unsigned)
    //   111 = BGEU (branch if greater or equal, unsigned)
    // ========================================================================
    
    always @(*) begin
        if (branch) begin
            case (funct3)
                3'b000:  taken = zero_flag;           // BEQ:  rs1 == rs2
                3'b001:  taken = ~zero_flag;          // BNE:  rs1 != rs2
                3'b100:  taken = less_than;           // BLT:  rs1 < rs2 (signed)
                3'b101:  taken = ~less_than;          // BGE:  rs1 >= rs2 (signed)
                3'b110:  taken = less_than_u;         // BLTU: rs1 < rs2 (unsigned)
                3'b111:  taken = ~less_than_u;        // BGEU: rs1 >= rs2 (unsigned)
                default: taken = 1'b0;
            endcase
        end else begin
            taken = 1'b0;  // Not a branch instruction
        end
    end

endmodule