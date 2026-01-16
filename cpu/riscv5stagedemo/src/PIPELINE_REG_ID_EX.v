module PIPELINE_REG_ID_EX (
    input clock,
    input reset,
    input flush,
    input stall,
    
    // Control signals input
    input regwrite_in,
    input alusrc_in,
    input memread_in,
    input memwrite_in,
    input memtoreg_in,
    input branch_in,
    input jump_in,
    
    // Data inputs
    input [31:0] read_data1_in,
    input [31:0] read_data2_in,
    input [31:0] imm_in,
    input [31:0] pc_in,
    
    // Register addresses
    input [4:0] rs1_in,
    input [4:0] rs2_in,
    input [4:0] rd_in,
    
    // Function codes
    input [2:0] funct3_in,
    input [6:0] funct7_in,
    
    // Control signals output
    output reg regwrite_out,
    output reg alusrc_out,
    output reg memread_out,
    output reg memwrite_out,
    output reg memtoreg_out,
    output reg branch_out,
    output reg jump_out,
    
    // Data outputs
    output reg [31:0] read_data1_out,
    output reg [31:0] read_data2_out,
    output reg [31:0] imm_out,
    output reg [31:0] pc_out,
    
    // Register addresses
    output reg [4:0] rs1_out,
    output reg [4:0] rs2_out,
    output reg [4:0] rd_out,
    
    // Function codes
    output reg [2:0] funct3_out,
    output reg [6:0] funct7_out
);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            // Reset: Clear all control signals and data
            regwrite_out <= 1'b0;
            alusrc_out <= 1'b0;
            memread_out <= 1'b0;
            memwrite_out <= 1'b0;
            memtoreg_out <= 1'b0;
            branch_out <= 1'b0;
            jump_out <= 1'b0;
            
            read_data1_out <= 32'h00000000;
            read_data2_out <= 32'h00000000;
            imm_out <= 32'h00000000;
            pc_out <= 32'h00000000;
            
            rs1_out <= 5'b00000;
            rs2_out <= 5'b00000;
            rd_out <= 5'b00000;
            
            funct3_out <= 3'b000;
            funct7_out <= 7'b0000000;
        end
        else if (flush) begin
            // Flush: Clear control signals to NOP (data can be kept)
            regwrite_out <= 1'b0;
            alusrc_out <= 1'b0;
            memread_out <= 1'b0;
            memwrite_out <= 1'b0;
            memtoreg_out <= 1'b0;
            branch_out <= 1'b0;
            jump_out <= 1'b0;
            
            read_data1_out <= 32'h00000000;
            read_data2_out <= 32'h00000000;
            imm_out <= 32'h00000000;
            pc_out <= 32'h00000000;
            
            rs1_out <= 5'b00000;
            rs2_out <= 5'b00000;
            rd_out <= 5'b00000;
            
            funct3_out <= 3'b000;
            funct7_out <= 7'b0000000;
        end
        else if (!stall) begin
            // Normal operation: Update all signals
            regwrite_out <= regwrite_in;
            alusrc_out <= alusrc_in;
            memread_out <= memread_in;
            memwrite_out <= memwrite_in;
            memtoreg_out <= memtoreg_in;
            branch_out <= branch_in;
            jump_out <= jump_in;
            
            read_data1_out <= read_data1_in;
            read_data2_out <= read_data2_in;
            imm_out <= imm_in;
            pc_out <= pc_in;
            
            rs1_out <= rs1_in;
            rs2_out <= rs2_in;
            rd_out <= rd_in;
            
            funct3_out <= funct3_in;
            funct7_out <= funct7_in;
        end
        // If stall=1: Hold current values (no else clause)
    end

endmodule