`timescale 1ps/1ps
`include "PIPELINE_REG_EX_WB.v"
module tb_PIPELINE_REG_EX_WB;

    reg clock;
    reg reset;
    reg regwrite_in;
    reg memtoreg_in;
    reg [31:0] alu_result_in;
    reg [31:0] mem_data_in;
    reg [4:0] rd_in;
    
    wire regwrite_out;
    wire memtoreg_out;
    wire [31:0] alu_result_out;
    wire [31:0] mem_data_out;
    wire [4:0] rd_out;

    // Instantiate module
    PIPELINE_REG_EX_WB uut (
        .clock(clock),
        .reset(reset),
        .regwrite_in(regwrite_in),
        .memtoreg_in(memtoreg_in),
        .alu_result_in(alu_result_in),
        .mem_data_in(mem_data_in),
        .rd_in(rd_in),
        .regwrite_out(regwrite_out),
        .memtoreg_out(memtoreg_out),
        .alu_result_out(alu_result_out),
        .mem_data_out(mem_data_out),
        .rd_out(rd_out)
    );

    // Clock generation (10ns period)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    // Helper task to set inputs
    task set_inputs;
        input rw, m2r;
        input [31:0] alu_res, mem_data;
        input [4:0] rd;
        begin
            regwrite_in = rw;
            memtoreg_in = m2r;
            alu_result_in = alu_res;
            mem_data_in = mem_data;
            rd_in = rd;
        end
    endtask

    // Test scenarios
    initial begin
        $display("=== Testbench for PIPELINE_REG_EX_WB ===\n");
        
        // Initialize
        reset = 0;
        set_inputs(0, 0, 32'h0, 32'h0, 5'd0);

        // Test 1: Reset
        $display("Test 1: Reset");
        reset = 1;
        #10;
        $display("During reset: regwrite=%b memtoreg=%b alu_result=0x%h rd=%d", 
                 regwrite_out, memtoreg_out, alu_result_out, rd_out);
        if (regwrite_out == 0 && alu_result_out == 0 && rd_out == 0)
            $display("✓ PASS - All outputs cleared\n");
        else
            $display("✗ FAIL\n");
        reset = 0;
        #10;

        // Test 2: R-type instruction (ADD) - Write ALU result
        $display("Test 2: R-type (ADD R5 = R1 + R2, result=0x30)");
        set_inputs(1, 0, 32'h00000030, 32'h00000000, 5'd5);
        #10;
        $display("Output: regwrite=%b memtoreg=%b alu_result=0x%h rd=%d", 
                 regwrite_out, memtoreg_out, alu_result_out, rd_out);
        if (regwrite_out == 1 && memtoreg_out == 0 && alu_result_out == 32'h30 && rd_out == 5)
            $display("✓ PASS - ALU result ready for writeback\n");
        else
            $display("✗ FAIL\n");

        // Test 3: Load instruction - Write memory data
        $display("Test 3: LOAD (LW R3, loaded_data=0xDEADBEEF)");
        set_inputs(1, 1, 32'h00000100, 32'hDEADBEEF, 5'd3);
        #10;
        $display("Output: regwrite=%b memtoreg=%b mem_data=0x%h rd=%d", 
                 regwrite_out, memtoreg_out, mem_data_out, rd_out);
        if (regwrite_out == 1 && memtoreg_out == 1 && mem_data_out == 32'hDEADBEEF && rd_out == 3)
            $display("✓ PASS - Memory data ready for writeback\n");
        else
            $display("✗ FAIL\n");

        // Test 4: Store instruction - No writeback
        $display("Test 4: STORE (SW - no register write)");
        set_inputs(0, 0, 32'h00000200, 32'hCAFEBABE, 5'd0);
        #10;
        $display("Output: regwrite=%b (should be 0)", regwrite_out);
        if (regwrite_out == 0)
            $display("✓ PASS - No writeback for store\n");
        else
            $display("✗ FAIL\n");

        // Test 5: I-type immediate instruction (ADDI)
        $display("Test 5: I-type (ADDI R7 = R1 + 100, result=0x164)");
        set_inputs(1, 0, 32'h00000164, 32'h00000000, 5'd7);
        #10;
        $display("Output: regwrite=%b alu_result=0x%h rd=%d", 
                 regwrite_out, alu_result_out, rd_out);
        if (regwrite_out == 1 && alu_result_out == 32'h164 && rd_out == 7)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 6: Sequential operations
        $display("Test 6: Sequential instructions");
        
        // Cycle 1: ADD
        set_inputs(1, 0, 32'h00000010, 32'h00000000, 5'd1);
        #10;
        $display("Cycle 1: ADD  - rd=%d alu_result=0x%h", rd_out, alu_result_out);
        
        // Cycle 2: LW
        set_inputs(1, 1, 32'h00000100, 32'h12345678, 5'd2);
        #10;
        $display("Cycle 2: LW   - rd=%d mem_data=0x%h", rd_out, mem_data_out);
        
        // Cycle 3: SUB
        set_inputs(1, 0, 32'hFFFFFFF0, 32'h00000000, 5'd3);
        #10;
        $display("Cycle 3: SUB  - rd=%d alu_result=0x%h", rd_out, alu_result_out);
        
        // Cycle 4: SW (no writeback)
        set_inputs(0, 0, 32'h00000200, 32'hAAAAAAAA, 5'd0);
        #10;
        $display("Cycle 4: SW   - regwrite=%b (no writeback)", regwrite_out);
        
        if (regwrite_out == 0)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 7: Large values
        $display("Test 7: Maximum values");
        set_inputs(1, 1, 32'hFFFFFFFF, 32'hFFFFFFFF, 5'd31);
        #10;
        $display("Output: alu_result=0x%h mem_data=0x%h rd=%d", 
                 alu_result_out, mem_data_out, rd_out);
        if (alu_result_out == 32'hFFFFFFFF && mem_data_out == 32'hFFFFFFFF && rd_out == 31)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 8: Write to x0 (should still propagate but register file will ignore)
        $display("Test 8: Write to x0 (hardware zero register)");
        set_inputs(1, 0, 32'h12345678, 32'h00000000, 5'd0);
        #10;
        $display("Output: regwrite=%b rd=%d alu_result=0x%h", 
                 regwrite_out, rd_out, alu_result_out);
        $display("Note: Pipeline propagates, but REG_FILE should ignore writes to x0");
        if (regwrite_out == 1 && rd_out == 0)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 9: Different memtoreg scenarios
        $display("Test 9: MUX selection for writeback");
        
        // Case 1: memtoreg=0 (select ALU result)
        set_inputs(1, 0, 32'hAAAAAAAA, 32'hBBBBBBBB, 5'd10);
        #10;
        $display("memtoreg=0: Should write alu_result=0x%h to rd=%d", alu_result_out, rd_out);
        
        // Case 2: memtoreg=1 (select memory data)
        set_inputs(1, 1, 32'hCCCCCCCC, 32'hDDDDDDDD, 5'd11);
        #10;
        $display("memtoreg=1: Should write mem_data=0x%h to rd=%d", mem_data_out, rd_out);
        
        if (mem_data_out == 32'hDDDDDDDD && rd_out == 11)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        $display("=== All tests completed ===");
        #20;
        $finish;
    end

    // Monitor changes
    initial begin
        $monitor("Time=%0t | regwrite=%b memtoreg=%b | alu_result=0x%h mem_data=0x%h | rd=%d", 
                 $time, regwrite_out, memtoreg_out, alu_result_out, mem_data_out, rd_out);
    end

    // Dump waveform
    initial begin
        $dumpfile("tb_PIPELINE_REG_EX_WB.vcd");
        $dumpvars(0, tb_PIPELINE_REG_EX_WB);
    end

endmodule