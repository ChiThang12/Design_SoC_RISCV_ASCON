// ============================================================================
// riscv_soc_top_tb.v - Complete Testbench cho RISC-V SoC
// ============================================================================
// Comprehensive test suite for RISC-V SoC with AXI4-Lite
// ============================================================================

`timescale 1ns/1ps
`include "riscv_soc_top.v"
module riscv_soc_top_tb;

    // ========================================================================
    // Clock và Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // Debug Signals
    // ========================================================================
    wire [31:0] debug_pc;
    wire [31:0] debug_instr;
    wire [31:0] debug_alu_result;
    wire [31:0] debug_mem_data;
    wire        debug_branch_taken;
    wire [31:0] debug_branch_target;
    wire        debug_stall;
    wire [1:0]  debug_forward_a;
    wire [1:0]  debug_forward_b;
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    riscv_soc_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .debug_pc(debug_pc),
        .debug_instr(debug_instr),
        .debug_alu_result(debug_alu_result),
        .debug_mem_data(debug_mem_data),
        .debug_branch_taken(debug_branch_taken),
        .debug_branch_target(debug_branch_target),
        .debug_stall(debug_stall),
        .debug_forward_a(debug_forward_a),
        .debug_forward_b(debug_forward_b)
    );
    
    // ========================================================================
    // Test Variables
    // ========================================================================
    integer cycle_count;
    integer i;
    integer test_num;
    integer total_tests;
    integer passed_tests;
    reg [31:0] prev_pc;
    
    // ========================================================================
    // Quiet Mode Control
    // ========================================================================
    reg verbose_mode;
    
    // Monitor (only in verbose mode)
    always @(posedge clk) begin
        if (rst_n && verbose_mode) begin
            $display("[%3d] PC=%h IR=%h ALU=%h St=%b Fwd=%d/%d",
                     cycle_count, debug_pc, debug_instr, debug_alu_result, 
                     debug_stall, debug_forward_a, debug_forward_b);
        end
    end
    
    // ========================================================================
    // Test Programs
    // ========================================================================
    
    // Test 1: Basic ALU Operations
    task load_test_alu;
        begin
            $display("  Program: ALU Operations + Forwarding");
            dut.imem_slave.imem.memory[0] = 32'h00A00093;  // ADDI x1, x0, 10
            dut.imem_slave.imem.memory[1] = 32'h01400113;  // ADDI x2, x0, 20
            dut.imem_slave.imem.memory[2] = 32'h002081B3;  // ADD  x3, x1, x2
            dut.imem_slave.imem.memory[3] = 32'h40218233;  // SUB  x4, x3, x2
            dut.imem_slave.imem.memory[4] = 32'h0020F2B3;  // AND  x5, x1, x2
            dut.imem_slave.imem.memory[5] = 32'h0020E333;  // OR   x6, x1, x2
            dut.imem_slave.imem.memory[6] = 32'h0000006F;  // JAL  x0, 0
            for (i = 7; i < 1024; i = i + 1)
                dut.imem_slave.imem.memory[i] = 32'h00000013;
        end
    endtask
    
    // Test 2: Branch Instructions
    task load_test_branch;
        begin
            $display("  Program: Branch & Jump Instructions");
            dut.imem_slave.imem.memory[0] = 32'h00A00093;  // ADDI x1, x0, 10
            dut.imem_slave.imem.memory[1] = 32'h00A00113;  // ADDI x2, x0, 10
            dut.imem_slave.imem.memory[2] = 32'h00208463;  // BEQ  x1, x2, 8
            dut.imem_slave.imem.memory[3] = 32'h06300193;  // ADDI x3, x0, 99 (skip)
            dut.imem_slave.imem.memory[4] = 32'h04D00213;  // ADDI x4, x0, 77
            dut.imem_slave.imem.memory[5] = 32'h00100293;  // ADDI x5, x0, 1
            dut.imem_slave.imem.memory[6] = 32'hFE209EE3;  // BNE  x1, x2, -4
            dut.imem_slave.imem.memory[7] = 32'h0000006F;  // JAL  x0, 0
            for (i = 8; i < 1024; i = i + 1)
                dut.imem_slave.imem.memory[i] = 32'h00000013;
        end
    endtask
    
    // Test 3: Memory Store/Load
    task load_test_memory;
        begin
            $display("  Program: Store & Load Word");
            dut.imem_slave.imem.memory[0] = 32'h00A00093;  // ADDI x1, x0, 10
            dut.imem_slave.imem.memory[1] = 32'h01400113;  // ADDI x2, x0, 20
            dut.imem_slave.imem.memory[2] = 32'h002081B3;  // ADD  x3, x1, x2
            dut.imem_slave.imem.memory[3] = 32'h10000237;  // LUI  x4, 0x10000
            dut.imem_slave.imem.memory[4] = 32'h00322023;  // SW   x3, 0(x4)
            dut.imem_slave.imem.memory[5] = 32'h00500293;  // ADDI x5, x0, 5
            dut.imem_slave.imem.memory[6] = 32'h00022303;  // LW   x6, 0(x4)
            dut.imem_slave.imem.memory[7] = 32'h005303B3;  // ADD  x7, x6, x5
            dut.imem_slave.imem.memory[8] = 32'h0000006F;  // JAL  x0, 0
            for (i = 9; i < 1024; i = i + 1)
                dut.imem_slave.imem.memory[i] = 32'h00000013;
        end
    endtask
    
    // Test 4: Byte/Halfword Operations
    task load_test_byte_halfword;
        begin
            $display("  Program: Byte & Halfword Access");
            dut.imem_slave.imem.memory[0] = 32'h0FF00093;  // ADDI x1, x0, 255
            dut.imem_slave.imem.memory[1] = 32'h10000137;  // LUI  x2, 0x10000
            dut.imem_slave.imem.memory[2] = 32'h00110023;  // SB   x1, 0(x2)
            dut.imem_slave.imem.memory[3] = 32'h00111123;  // SH   x1, 2(x2)   // FIXED: funct3=001 for halfword
            dut.imem_slave.imem.memory[4] = 32'h00010183;  // LB   x3, 0(x2)
            dut.imem_slave.imem.memory[5] = 32'h00014203;  // LBU  x4, 0(x2)
            dut.imem_slave.imem.memory[6] = 32'h00212283;  // LH   x5, 2(x2)
            dut.imem_slave.imem.memory[7] = 32'h00216303;  // LHU  x6, 2(x2)
            dut.imem_slave.imem.memory[8] = 32'h00000013;  // NOP
            for (i = 9; i < 1024; i = i + 1)
                dut.imem_slave.imem.memory[i] = 32'h00000013;
        end
    endtask
    
    // Test 5: Comprehensive Test
    task load_test_comprehensive;
        begin
            $display("  Program: Comprehensive Test (ALU + Branch + Memory)");
            dut.imem_slave.imem.memory[0]  = 32'h00A00093;  // ADDI x1, x0, 10
            dut.imem_slave.imem.memory[1]  = 32'h01400113;  // ADDI x2, x0, 20
            dut.imem_slave.imem.memory[2]  = 32'h002081B3;  // ADD  x3, x1, x2
            dut.imem_slave.imem.memory[3]  = 32'h10000237;  // LUI  x4, 0x10000
            dut.imem_slave.imem.memory[4]  = 32'h00322023;  // SW   x3, 0(x4)
            dut.imem_slave.imem.memory[5]  = 32'h40218233;  // SUB  x4, x3, x2
            dut.imem_slave.imem.memory[6]  = 32'h10000337;  // LUI  x6, 0x10000
            dut.imem_slave.imem.memory[7]  = 32'h00032383;  // LW   x7, 0(x6)
            dut.imem_slave.imem.memory[8]  = 32'h00738433;  // ADD  x8, x7, x7
            dut.imem_slave.imem.memory[9]  = 32'h00208463;  // BEQ  x1, x2, 8
            dut.imem_slave.imem.memory[10] = 32'h00100493;  // ADDI x9, x0, 1
            dut.imem_slave.imem.memory[11] = 32'h00200513;  // ADDI x10,x0, 2
            dut.imem_slave.imem.memory[12] = 32'h00000013;  // NOP
            for (i = 13; i < 1024; i = i + 1)
                dut.imem_slave.imem.memory[i] = 32'h00000013;
        end
    endtask
    
    // ========================================================================
    // Run Test
    // ========================================================================
    task run_test;
        input [31:0] target_pc;
        input [31:0] max_cycles;
        input integer expected_pass;
        begin
            cycle_count = 0;
            while (debug_pc != target_pc && cycle_count < max_cycles) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
            end
            
            if (debug_pc == target_pc) begin
                $display("  Status: PASS - Reached target PC in %0d cycles", cycle_count);
                if (expected_pass) passed_tests = passed_tests + 1;
            end else begin
                $display("  Status: FAIL - Timeout at PC=%h after %0d cycles", 
                         debug_pc, cycle_count);
                if (!expected_pass) passed_tests = passed_tests + 1;
            end
        end
    endtask
    
    // ========================================================================
    // Verify Memory
    // ========================================================================
    task verify_memory;
        input [31:0] addr;
        input [31:0] expected;
        input [255:0] desc;
        reg [31:0] actual;
        begin
            actual = {dut.dmem_slave.dmem.memory[addr+3],
                     dut.dmem_slave.dmem.memory[addr+2],
                     dut.dmem_slave.dmem.memory[addr+1],
                     dut.dmem_slave.dmem.memory[addr+0]};
            
            if (actual == expected) begin
                $display("  ✓ %s: 0x%08h", desc, actual);
            end else begin
                $display("  ✗ %s: 0x%08h (expected 0x%08h)", desc, actual, expected);
            end
        end
    endtask
    
    // ========================================================================
    // Reset Sequence
    // ========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask
    
    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        $dumpfile("riscv_soc_top_tb.vcd");
        $dumpvars(0, riscv_soc_top_tb);
        
        $display("\n╔═══════════════════════════════════════════════════════╗");
        $display("║     RISC-V SoC AXI4-Lite Test Suite                 ║");
        $display("╚═══════════════════════════════════════════════════════╝\n");
        
        total_tests = 5;
        passed_tests = 0;
        verbose_mode = 0;  // Set to 1 for detailed output
        
        // ====================================================================
        // TEST 1: ALU Operations
        // ====================================================================
        test_num = 1;
        $display("┌───────────────────────────────────────────────────────┐");
        $display("│ Test %0d: ALU Operations & Forwarding                 │", test_num);
        $display("└───────────────────────────────────────────────────────┘");
        reset_dut();
        load_test_alu();
        run_test(32'h00000018, 100, 1);
        $display("");
        
        // ====================================================================
        // TEST 2: Branch Instructions
        // ====================================================================
        test_num = 2;
        $display("┌───────────────────────────────────────────────────────┐");
        $display("│ Test %0d: Branch & Control Flow                       │", test_num);
        $display("└───────────────────────────────────────────────────────┘");
        reset_dut();
        load_test_branch();
        run_test(32'h0000001C, 100, 1);
        $display("");
        
        // ====================================================================
        // TEST 3: Memory Operations
        // ====================================================================
        test_num = 3;
        $display("┌───────────────────────────────────────────────────────┐");
        $display("│ Test %0d: Memory Store & Load                         │", test_num);
        $display("└───────────────────────────────────────────────────────┘");
        reset_dut();
        load_test_memory();
        run_test(32'h00000020, 120, 1);
        verify_memory(0, 32'h0000001E, "DMEM[0x10000000]");
        $display("");
        
        // ====================================================================
        // TEST 4: Byte/Halfword Operations
        // ====================================================================
        test_num = 4;
        $display("┌───────────────────────────────────────────────────────┐");
        $display("│ Test %0d: Byte & Halfword Access                      │", test_num);
        $display("└───────────────────────────────────────────────────────┘");
        reset_dut();
        load_test_byte_halfword();
        run_test(32'h00000024, 150, 1);
        $display("  Memory Check:");
        $display("    Byte 0: 0x%02h (expected 0xFF)", dut.dmem_slave.dmem.memory[0]);
        $display("    Half 2: 0x%02h%02h (expected 0x00FF)", 
                 dut.dmem_slave.dmem.memory[3], dut.dmem_slave.dmem.memory[2]);
        $display("");
        
        // ====================================================================
        // TEST 5: Comprehensive Test
        // ====================================================================
        test_num = 5;
        $display("┌───────────────────────────────────────────────────────┐");
        $display("│ Test %0d: Comprehensive (ALU + Branch + Memory)       │", test_num);
        $display("└───────────────────────────────────────────────────────┘");
        reset_dut();
        load_test_comprehensive();
        run_test(32'h00000034, 200, 1);
        verify_memory(0, 32'h0000001E, "DMEM[0x10000000]");
        $display("");
        
        // ====================================================================
        // Summary
        // ====================================================================
        $display("\n╔═══════════════════════════════════════════════════════╗");
        $display("║                   Test Summary                        ║");
        $display("╠═══════════════════════════════════════════════════════╣");
        $display("║  Total Tests:  %2d                                     ║", total_tests);
        $display("║  Passed:       %2d                                     ║", passed_tests);
        $display("║  Failed:       %2d                                     ║", total_tests - passed_tests);
        $display("╠═══════════════════════════════════════════════════════╣");
        
        if (passed_tests == total_tests) begin
            $display("║           ✓✓✓ ALL TESTS PASSED ✓✓✓                   ║");
        end else begin
            $display("║           ✗✗✗ SOME TESTS FAILED ✗✗✗                  ║");
        end
        
        $display("╚═══════════════════════════════════════════════════════╝\n");
        
        $finish;
    end
    
    // ========================================================================
    // Timeout Protection
    // ========================================================================
    initial begin
        #1000000;
        $display("\n!!! GLOBAL TIMEOUT !!!");
        $finish;
    end

endmodule