module branch_logic (
    // Control signal
    input branch,                     // Branch instruction signal
    
    // Branch type (funct3)
    input [2:0] funct3,              // Function code to determine branch type
    
    // Comparison flags from ALU
    input zero_flag,                 // Result is zero (rs1 == rs2)
    input less_than,                 // Signed comparison (rs1 < rs2)
    input less_than_u,               // Unsigned comparison (rs1 < rs2)
    
    // Output
    output reg taken                 // Branch taken decision
);

    // RISC-V Branch funct3 codes
    localparam [2:0] BEQ  = 3'b000;  // Branch if Equal
    localparam [2:0] BNE  = 3'b001;  // Branch if Not Equal
    localparam [2:0] BLT  = 3'b100;  // Branch if Less Than (signed)
    localparam [2:0] BGE  = 3'b101;  // Branch if Greater or Equal (signed)
    localparam [2:0] BLTU = 3'b110;  // Branch if Less Than (unsigned)
    localparam [2:0] BGEU = 3'b111;  // Branch if Greater or Equal (unsigned)

    // Branch decision logic
    always @(*) begin
        taken = 1'b0;  // Default: don't take branch
        
        if (branch) begin
            case (funct3)
                BEQ:  taken = zero_flag;        // Take if rs1 == rs2
                BNE:  taken = ~zero_flag;       // Take if rs1 != rs2
                BLT:  taken = less_than;        // Take if rs1 < rs2 (signed)
                BGE:  taken = ~less_than;       // Take if rs1 >= rs2 (signed)
                BLTU: taken = less_than_u;      // Take if rs1 < rs2 (unsigned)
                BGEU: taken = ~less_than_u;     // Take if rs1 >= rs2 (unsigned)
                default: taken = 1'b0;          // Invalid funct3
            endcase
        end
    end

endmodule
