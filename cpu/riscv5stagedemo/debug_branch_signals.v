// Debug testbench - Focus on branch behavior
`timescale 1ns/1ps
`include "datapath.v"
module debug_branch_signals;

    reg clock, reset;
    wire [31:0] pc_current, alu_result_debug, mem_out_debug;
    
    datapath dut (
        .clock(clock),
        .reset(reset),
        .pc_current(pc_current),
        .alu_result_debug(alu_result_debug),
        .mem_out_debug(mem_out_debug)
    );
    
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end
    
    integer cycle;
    
    initial begin
        $display("=== BRANCH DEBUG TESTBENCH ===\n");
        
        reset = 1;
        #20 reset = 0;
        
        cycle = 0;
        
        $display("Monitoring Branch-related signals:");
        $display("Cycle | PC   | Instr    | branch_ex | funct3 | zero | lt | ltu | decision | taken | target");
        $display("------|------|----------|-----------|--------|------|----|----|----------|-------|--------");
        
        repeat(30) begin
            @(posedge clock);
            cycle = cycle + 1;
            
            // Display detailed branch signals
            $display("%5d | %04h | %08h | %b         | %03b    | %b    | %b  | %b   | %b        | %b     | %08h",
                     cycle,
                     pc_current[15:0],
                     dut.instruction_if,
                     dut.branch_ex,
                     dut.funct3_ex,
                     dut.zero_flag,
                     dut.less_than,
                     dut.less_than_u,
                     dut.branch_decision,
                     dut.branch_taken,
                     dut.branch_target);
            
            // Special detection for BLT instruction
            if (dut.instruction_if == 32'hfe314ae3) begin
                $display("\n>>> BLT instruction detected at PC=0x%08h", pc_current);
            end
            
            // When branch should be evaluated in EX stage
            if (dut.branch_ex) begin
                $display("\n>>> Branch in EX stage:");
                $display("    funct3 = %03b (BLT = 100, BGE = 101, BEQ = 000, BNE = 001)", dut.funct3_ex);
                $display("    ALU operand A = %0d (x2 = rs1)", $signed(dut.alu_in1));
                $display("    ALU operand B = %0d (x3 = rs2)", $signed(dut.alu_in2));
                $display("    zero_flag = %b (A == B)", dut.zero_flag);
                $display("    less_than = %b (A < B signed)", dut.less_than);
                $display("    less_than_u = %b (A < B unsigned)", dut.less_than_u);
                $display("    branch_decision = %b", dut.branch_decision);
                $display("    branch_taken = %b", dut.branch_taken);
                $display("    branch_target = 0x%08h", dut.branch_target);
                $display("    Expected: x2=%0d < x3=%0d should be TRUE, so branch should be taken\n", 
                         $signed(dut.register_file.registers[2]),
                         $signed(dut.register_file.registers[3]));
            end
            
            if (dut.branch_taken) begin
                $display("\n*** BRANCH TAKEN to 0x%08h ***\n", dut.branch_target);
            end
        end
        
        $display("\n=== REGISTER STATE ===");
        $display("x1 = %0d (sum)", $signed(dut.register_file.registers[1]));
        $display("x2 = %0d (counter)", $signed(dut.register_file.registers[2]));
        $display("x3 = %0d (limit)", $signed(dut.register_file.registers[3]));
        
        $finish;
    end
    
endmodule