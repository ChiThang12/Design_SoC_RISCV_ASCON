`timescale 1ps/1ps
`include "PIPELINE_REG_IF_ID.v"
module tb_PIPELINE_REG_IF_ID;

    reg clock;
    reg reset;
    reg flush;
    reg stall;
    reg [31:0] instr_in;
    reg [31:0] pc_in;
    wire [31:0] instr_out;
    wire [31:0] pc_out;

    // Khởi tạo module
    PIPELINE_REG_IF_ID uut (
        .clock(clock),
        .reset(reset),
        .flush(flush),
        .stall(stall),
        .instr_in(instr_in),
        .pc_in(pc_in),
        .instr_out(instr_out),
        .pc_out(pc_out)
    );

    // Tạo clock 10ns period (100MHz)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    // Test scenarios
    initial begin
        $display("=== Testbench for PIPELINE_REG_IF_ID ===\n");
        
        // Khởi tạo signals
        reset = 0;
        flush = 0;
        stall = 0;
        instr_in = 32'h00000000;
        pc_in = 32'h00000000;

        // Test 1: Reset
        $display("Test 1: Reset");
        reset = 1;
        #10;
        $display("During reset: instr_out = 0x%h (expected NOP=0x00000013), pc_out = 0x%h", instr_out, pc_out);
        if (instr_out == 32'h00000013 && pc_out == 32'h00000000)
            $display("✓ PASS (Reset state correct)\n");
        else
            $display("✗ FAIL\n");
        reset = 0;
        #10;

        // Test 2: Normal operation (cập nhật giá trị)
        $display("Test 2: Normal operation");
        instr_in = 32'h12345678;
        pc_in = 32'h00000004;
        #10;
        $display("After normal update: instr_out = 0x%h, pc_out = 0x%h", instr_out, pc_out);
        if (instr_out == 32'h12345678 && pc_out == 32'h00000004)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 3: Stall (giữ nguyên giá trị)
        $display("Test 3: Stall");
        stall = 1;
        instr_in = 32'hAAAAAAAA;
        pc_in = 32'h00000008;
        #10;
        $display("During stall: instr_out = 0x%h (should be 0x12345678), pc_out = 0x%h (should be 0x00000004)", instr_out, pc_out);
        if (instr_out == 32'h12345678 && pc_out == 32'h00000004)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 4: Stall off → cập nhật giá trị mới
        $display("Test 4: Stall off");
        stall = 0;
        #10;
        $display("After stall off: instr_out = 0x%h, pc_out = 0x%h", instr_out, pc_out);
        if (instr_out == 32'hAAAAAAAA && pc_out == 32'h00000008)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 5: Flush (chèn NOP)
        $display("Test 5: Flush");
        flush = 1;
        instr_in = 32'hBBBBBBBB;
        pc_in = 32'h0000000C;
        #10;
        $display("After flush: instr_out = 0x%h (expected NOP=0x00000013), pc_out = 0x%h", instr_out, pc_out);
        if (instr_out == 32'h00000013 && pc_out == 32'h00000000)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 6: Flush off → hoạt động bình thường
        $display("Test 6: Flush off");
        flush = 0;
        instr_in = 32'hCCCCCCCC;
        pc_in = 32'h00000010;
        #10;
        $display("After flush off: instr_out = 0x%h, pc_out = 0x%h", instr_out, pc_out);
        if (instr_out == 32'hCCCCCCCC && pc_out == 32'h00000010)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // Test 7: Stall và Flush cùng lúc (flush ưu tiên)
        $display("Test 7: Stall and Flush together");
        stall = 1;
        flush = 1;
        instr_in = 32'hDDDDDDDD;
        pc_in = 32'h00000014;
        #10;
        $display("With stall=1 and flush=1: instr_out = 0x%h (expected NOP=0x00000013)", instr_out);
        if (instr_out == 32'h00000013)
            $display("✓ PASS (flush has priority)\n");
        else
            $display("✗ FAIL\n");

        // Test 8: Chuỗi instructions liên tiếp
        $display("Test 8: Sequential instructions");
        stall = 0;
        flush = 0;
        instr_in = 32'h00000001; pc_in = 32'h00000000; #10;
        $display("Cycle 1: instr_out = 0x%h, pc_out = 0x%h", instr_out, pc_out);
        
        instr_in = 32'h00000002; pc_in = 32'h00000004; #10;
        $display("Cycle 2: instr_out = 0x%h, pc_out = 0x%h", instr_out, pc_out);
        
        instr_in = 32'h00000003; pc_in = 32'h00000008; #10;
        $display("Cycle 3: instr_out = 0x%h, pc_out = 0x%h", instr_out, pc_out);
        
        if (instr_out == 32'h00000003 && pc_out == 32'h00000008)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        $display("=== All tests completed ===");
        #20;
        $finish;
    end

    // Monitor để theo dõi thay đổi
    initial begin
        $monitor("Time=%0t | reset=%b flush=%b stall=%b | instr_in=0x%h pc_in=0x%h | instr_out=0x%h pc_out=0x%h", 
                 $time, reset, flush, stall, instr_in, pc_in, instr_out, pc_out);
    end

    // Dump waveform
    initial begin
        $dumpfile("tb_PIPELINE_REG_IF_ID.vcd");
        $dumpvars(0, tb_PIPELINE_REG_IF_ID);
    end

endmodule