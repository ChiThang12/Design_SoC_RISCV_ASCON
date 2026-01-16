// Debug forwarding and register values
`timescale 1ns/1ps
`include "datapath.v"
module debug_fwd;

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
        $display("=== FORWARDING DEBUG TESTBENCH ===\n");
        
        reset = 1;
        #20 reset = 0;
        
        cycle = 0;
        
        $display("Focus on cycles when BLT is in EX stage:");
        $display("Cycle | PC   | Instr_EX | rs1_ex | rs2_ex | read_data1_ex | read_data2_ex | fwd_a | fwd_b | alu_in1 | alu_in2");
        $display("------|------|----------|--------|--------|---------------|---------------|-------|-------|---------|--------");
        
        repeat(15) begin
            @(posedge clock);
            cycle = cycle + 1;
            
            $display("%5d | %04h | %08h | x%-5d | x%-5d | %-13d | %-13d | %02b    | %02b    | %-7d | %-7d",
                     cycle,
                     pc_current[15:0],
                     dut.instruction_id,
                     dut.rs1_ex,
                     dut.rs2_ex,
                     $signed(dut.read_data1_ex),
                     $signed(dut.read_data2_ex),
                     dut.forward_a,
                     dut.forward_b,
                     $signed(dut.alu_in1),
                     $signed(dut.alu_in2));
            
            // When BLT is in EX stage
            if (dut.branch_ex && dut.funct3_ex == 3'b100) begin
                $display("\n>>> BLT in EX stage (cycle %0d):", cycle);
                $display("    Instruction in ID/EX: 0x%08h", dut.instruction_id);
                $display("    rs1_ex = x%0d", dut.rs1_ex);
                $display("    rs2_ex = x%0d", dut.rs2_ex);
                $display("    read_data1_ex (from pipe reg) = %0d", $signed(dut.read_data1_ex));
                $display("    read_data2_ex (from pipe reg) = %0d", $signed(dut.read_data2_ex));
                $display("    Register file x%0d = %0d", dut.rs1_ex, $signed(dut.register_file.registers[dut.rs1_ex]));
                $display("    Register file x%0d = %0d", dut.rs2_ex, $signed(dut.register_file.registers[dut.rs2_ex]));
                $display("    forward_a = %02b", dut.forward_a);
                $display("    forward_b = %02b", dut.forward_b);
                $display("    forwarded_data2 = %0d", $signed(dut.forwarded_data2));
                $display("    alu_in1 (after fwd) = %0d", $signed(dut.alu_in1));
                $display("    alu_in2 (after fwd & mux) = %0d", $signed(dut.alu_in2));
                $display("    alusrc_ex = %b", dut.alusrc_ex);
                $display("    imm_ex = %0d", $signed(dut.imm_ex));
                
                $display("\n    Forwarding check:");
                $display("    rd_mem = x%0d, regwrite_mem = %b", dut.rd_mem, dut.regwrite_mem);
                $display("    rd_wb = x%0d, regwrite_wb = %b", dut.rd_wb, dut.regwrite_wb);
                $display("");
            end
        end
        
        $display("\n=== REGISTER STATE ===");
        $display("x0 = %0d", $signed(dut.register_file.registers[0]));
        $display("x1 = %0d (sum)", $signed(dut.register_file.registers[1]));
        $display("x2 = %0d (counter)", $signed(dut.register_file.registers[2]));
        $display("x3 = %0d (limit)", $signed(dut.register_file.registers[3]));
        
        $finish;
    end
    
endmodule