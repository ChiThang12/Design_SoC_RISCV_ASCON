`timescale 1ps/1ps
`include "INST_MEM.v"

module tb_inst_mem;
    reg [31:0] PC;
    reg reset;
    wire [31:0] inst;
    
    INST_MEM uut (
        .PC(PC),
        .reset(reset),
        .Instruction_Code(inst)
    );
    
    initial begin
        $dumpfile("inst_mem.vcd");
        $dumpvars(0, tb_inst_mem);
        
        reset = 1;
        PC = 0;
        #10 reset = 0;
        
        // Test fetch
        PC = 32'h00000000; #10;
        $display("PC=0x%08h, Inst=0x%08h", PC, inst);
        
        PC = 32'h00000004; #10;
        $display("PC=0x%08h, Inst=0x%08h", PC, inst);
        
        PC = 32'h00000008; #10;
        $display("PC=0x%08h, Inst=0x%08h", PC, inst);
        
        $finish;
    end
endmodule