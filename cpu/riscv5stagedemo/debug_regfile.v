// Debug register file writes
`timescale 1ns/1ps
`include "datapath.v"
module debug_regfile;

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
        $display("=== REGISTER FILE WRITE DEBUG ===\n");
        
        reset = 1;
        #20 reset = 0;
        
        cycle = 0;
        
        $display("Monitoring register writes and reads:");
        $display("Cycle | PC_IF | Instr_IF | PC_ID | Instr_ID | rs1_id | rs2_id | rd_wb | regwrite_wb | write_data_wb | x1  | x2  | x3");
        $display("------|-------|----------|-------|----------|--------|--------|-------|-------------|---------------|-----|-----|----");
        
        repeat(12) begin
            @(posedge clock);
            cycle = cycle + 1;
            
            $display("%5d | %04h  | %08h | %04h  | %08h | x%-5d | x%-5d | x%-4d | %b           | %-13d | %-3d | %-3d | %-3d",
                     cycle,
                     pc_current[15:0],
                     dut.instruction_if,
                     dut.pc_id[15:0],
                     dut.instruction_id,
                     dut.rs1_id,
                     dut.rs2_id,
                     dut.rd_wb,
                     dut.regwrite_wb,
                     $signed(dut.write_data_wb),
                     $signed(dut.register_file.registers[1]),
                     $signed(dut.register_file.registers[2]),
                     $signed(dut.register_file.registers[3]));
            
            // Show register file read operation
            if (dut.instruction_id == 32'hfe314ae3) begin
                $display("\n>>> BLT instruction in ID stage (cycle %0d):", cycle);
                $display("    Reading registers:");
                $display("    rs1 = x%0d, value from reg_file = %0d", dut.rs1_id, $signed(dut.register_file.registers[dut.rs1_id]));
                $display("    rs2 = x%0d, value from reg_file = %0d", dut.rs2_id, $signed(dut.register_file.registers[dut.rs2_id]));
                $display("    read_data1 (output) = %0d", $signed(dut.read_data1_id));
                $display("    read_data2 (output) = %0d", $signed(dut.read_data2_id));
                $display("");
            end
            
            // Monitor writes to x3
            if (dut.regwrite_wb && dut.rd_wb == 5'd3) begin
                $display("\n*** Writing to x3: value = %0d ***\n", $signed(dut.write_data_wb));
            end
        end
        
        $display("\n=== FINAL REGISTER STATE ===");
        $display("x1 = %0d", $signed(dut.register_file.registers[1]));
        $display("x2 = %0d", $signed(dut.register_file.registers[2]));
        $display("x3 = %0d", $signed(dut.register_file.registers[3]));
        
        $finish;
    end
    
endmodule