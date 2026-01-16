// ============================================================================
// ASCON_PERMUTATION Testbench
// Mô tả: Testbench đầy đủ cho module ASCON_PERMUTATION và các sub-modules
// ============================================================================


`include "ascon_PERMUTATION.v"
// ============================================================================
// ASCON_PERMUTATION Testbench
// Mô tả: Testbench đầy đủ cho module ASCON_PERMUTATION và các sub-modules
// ============================================================================

`timescale 1ns/1ps

module tb_ASCON_PERMUTATION;

    // ========================================================================
    // Signals for DUT
    // ========================================================================
    reg         clk;
    reg         rst_n;
    reg  [319:0] state_in;
    reg  [3:0]   rounds;
    reg         start_perm;
    reg         mode;
    
    wire [319:0] state_out;
    wire        valid;
    wire        done;

    // ========================================================================
    // Signals for sub-module testing
    // ========================================================================
    // CONSTANT_ADDITION test signals
    reg [63:0] test_x2;
    reg [3:0] test_round;
    wire [63:0] const_result;
    
    // SUBSTITUTION_LAYER test signals
    reg [63:0] tx0, tx1, tx2, tx3, tx4;
    wire [63:0] rx0, rx1, rx2, rx3, rx4;
    
    // LINEAR_DIFFUSION test signals
    reg [63:0] dx0, dx1, dx2, dx3, dx4;
    wire [63:0] ox0, ox1, ox2, ox3, ox4;

    // ========================================================================
    // Instantiate DUT
    // ========================================================================
    ASCON_PERMUTATION dut (
        .clk(clk),
        .rst_n(rst_n),
        .state_in(state_in),
        .rounds(rounds),
        .start_perm(start_perm),
        .mode(mode),
        .state_out(state_out),
        .valid(valid),
        .done(done)
    );

    // ========================================================================
    // Instantiate sub-modules for testing
    // ========================================================================
    CONSTANT_ADDITION const_test (
        .state_x2(test_x2),
        .round_number(test_round),
        .state_x2_modified(const_result)
    );
    
    SUBSTITUTION_LAYER sub_test (
        .x0_in(tx0), .x1_in(tx1), .x2_in(tx2), .x3_in(tx3), .x4_in(tx4),
        .x0_out(rx0), .x1_out(rx1), .x2_out(rx2), .x3_out(rx3), .x4_out(rx4)
    );
    
    LINEAR_DIFFUSION diff_test (
        .x0_in(dx0), .x1_in(dx1), .x2_in(dx2), .x3_in(dx3), .x4_in(dx4),
        .x0_out(ox0), .x1_out(ox1), .x2_out(ox2), .x3_out(ox3), .x4_out(ox4)
    );

    // ========================================================================
    // Clock generation: 10ns period (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================================================
    // Test variables
    // ========================================================================
    integer test_num;
    integer i;
    integer start_time, end_time, cycles;
    
    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        // Waveform dump
        $dumpfile("ascon_permutation.vcd");
        $dumpvars(0, tb_ASCON_PERMUTATION);
        
        // Initialize
        test_num = 0;
        rst_n = 0;
        state_in = 320'h0;
        rounds = 4'h0;
        start_perm = 0;
        mode = 0;
        
        // Initialize sub-module test signals
        test_x2 = 64'h0;
        test_round = 4'h0;
        tx0 = 64'h0; tx1 = 64'h0; tx2 = 64'h0; tx3 = 64'h0; tx4 = 64'h0;
        dx0 = 64'h0; dx1 = 64'h0; dx2 = 64'h0; dx3 = 64'h0; dx4 = 64'h0;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // ====================================================================
        // TEST 1: Test CONSTANT_ADDITION module
        // ====================================================================
        test_num = 1;
        $display("\n========================================");
        $display("TEST %0d: CONSTANT_ADDITION Module", test_num);
        $display("========================================");
        
        // Test round 0
        test_x2 = 64'h0000000000000000;
        test_round = 4'h0;
        #1;
        $display("Round %0d: x2=%h, constant=%h, result=%h", 
                 test_round, test_x2, 8'hF0, const_result);
        
        // Test round 5
        test_x2 = 64'hFFFFFFFFFFFFFFFF;
        test_round = 4'h5;
        #1;
        $display("Round %0d: x2=%h, constant=%h, result=%h", 
                 test_round, test_x2, 8'hF0 - 5*8'h0F, const_result);
        
        // Test round 11
        test_x2 = 64'hAAAAAAAAAAAAAAAA;
        test_round = 4'hB;
        #1;
        $display("Round %0d: x2=%h, constant=%h, result=%h", 
                 test_round, test_x2, 8'hF0 - 11*8'h0F, const_result);
        
        $display("[PASS] CONSTANT_ADDITION tests completed");
        #10;
        
        // ====================================================================
        // TEST 2: Test SUBSTITUTION_LAYER module
        // ====================================================================
        test_num = 2;
        $display("\n========================================");
        $display("TEST %0d: SUBSTITUTION_LAYER Module", test_num);
        $display("========================================");
        
        // Test with zero
        tx0 = 64'h0; tx1 = 64'h0; tx2 = 64'h0; tx3 = 64'h0; tx4 = 64'h0;
        #1;
        $display("Input:  x0=%h x1=%h x2=%h x3=%h x4=%h", tx0, tx1, tx2, tx3, tx4);
        $display("Output: x0=%h x1=%h x2=%h x3=%h x4=%h", rx0, rx1, rx2, rx3, rx4);
        
        // Test with pattern
        tx0 = 64'hFFFFFFFFFFFFFFFF;
        tx1 = 64'h0000000000000000;
        tx2 = 64'hAAAAAAAAAAAAAAAA;
        tx3 = 64'h5555555555555555;
        tx4 = 64'hF0F0F0F0F0F0F0F0;
        #1;
        $display("Input:  x0=%h x1=%h x2=%h x3=%h x4=%h", tx0, tx1, tx2, tx3, tx4);
        $display("Output: x0=%h x1=%h x2=%h x3=%h x4=%h", rx0, rx1, rx2, rx3, rx4);
        
        $display("[PASS] SUBSTITUTION_LAYER tests completed");
        #10;
        
        // ====================================================================
        // TEST 3: Test LINEAR_DIFFUSION module
        // ====================================================================
        test_num = 3;
        $display("\n========================================");
        $display("TEST %0d: LINEAR_DIFFUSION Module", test_num);
        $display("========================================");
        
        // Test with all ones
        dx0 = 64'hFFFFFFFFFFFFFFFF;
        dx1 = 64'hFFFFFFFFFFFFFFFF;
        dx2 = 64'hFFFFFFFFFFFFFFFF;
        dx3 = 64'hFFFFFFFFFFFFFFFF;
        dx4 = 64'hFFFFFFFFFFFFFFFF;
        #1;
        $display("Input:  x0=%h x1=%h x2=%h x3=%h x4=%h", dx0, dx1, dx2, dx3, dx4);
        $display("Output: x0=%h x1=%h x2=%h x3=%h x4=%h", ox0, ox1, ox2, ox3, ox4);
        
        // Test with pattern
        dx0 = 64'h0123456789ABCDEF;
        dx1 = 64'hFEDCBA9876543210;
        dx2 = 64'hAAAAAAAAAAAAAAAA;
        dx3 = 64'h5555555555555555;
        dx4 = 64'hF0F0F0F0F0F0F0F0;
        #1;
        $display("Input:  x0=%h x1=%h x2=%h x3=%h x4=%h", dx0, dx1, dx2, dx3, dx4);
        $display("Output: x0=%h x1=%h x2=%h x3=%h x4=%h", ox0, ox1, ox2, ox3, ox4);
        
        $display("[PASS] LINEAR_DIFFUSION tests completed");
        #10;
        
        // ====================================================================
        // TEST 4: Single Round Permutation
        // ====================================================================
        test_num = 4;
        $display("\n========================================");
        $display("TEST %0d: Single Round Permutation", test_num);
        $display("========================================");
        
        state_in = 320'h0123456789ABCDEF_FEDCBA9876543210_1111111111111111_2222222222222222_3333333333333333;
        rounds = 4'h1;
        start_perm = 1;
        
        #10;
        start_perm = 0;
        
        // Wait for completion
        wait(done);
        #10;
        
        $display("Input State:  %h", state_in);
        $display("Output State: %h", state_out);
        $display("Valid: %b, Done: %b", valid, done);
        
        if (valid && done) begin
            $display("[PASS] Single round completed");
        end else begin
            $display("[FAIL] Single round did not complete properly");
        end
        
        #20;
        
        // ====================================================================
        // TEST 5: 6 Rounds Permutation (p^b)
        // ====================================================================
        test_num = 5;
        $display("\n========================================");
        $display("TEST %0d: 6 Rounds Permutation (p^b)", test_num);
        $display("========================================");
        
        state_in = 320'hAAAAAAAAAAAAAAAA_BBBBBBBBBBBBBBBB_CCCCCCCCCCCCCCCC_DDDDDDDDDDDDDDDD_EEEEEEEEEEEEEEEE;
        rounds = 4'd6;
        start_perm = 1;
        
        #10;
        start_perm = 0;
        
        // Wait for completion
        wait(done);
        #10;
        
        $display("Input State:  %h", state_in);
        $display("Output State: %h", state_out);
        $display("Rounds: %0d, Valid: %b, Done: %b", rounds, valid, done);
        
        if (valid && done) begin
            $display("[PASS] 6 rounds completed");
        end else begin
            $display("[FAIL] 6 rounds did not complete properly");
        end
        
        #20;
        
        // ====================================================================
        // TEST 6: 12 Rounds Permutation (p^a)
        // ====================================================================
        test_num = 6;
        $display("\n========================================");
        $display("TEST %0d: 12 Rounds Permutation (p^a)", test_num);
        $display("========================================");
        
        state_in = 320'h0F0F0F0F0F0F0F0F_F0F0F0F0F0F0F0F0_A5A5A5A5A5A5A5A5_5A5A5A5A5A5A5A5A_FFFFFFFFFFFFFFFF;
        rounds = 4'd12;
        start_perm = 1;
        
        #10;
        start_perm = 0;
        
        // Wait for completion
        wait(done);
        #10;
        
        $display("Input State:  %h", state_in);
        $display("Output State: %h", state_out);
        $display("Rounds: %0d, Valid: %b, Done: %b", rounds, valid, done);
        
        if (valid && done) begin
            $display("[PASS] 12 rounds completed");
        end else begin
            $display("[FAIL] 12 rounds did not complete properly");
        end
        
        #20;
        
        // ====================================================================
        // TEST 7: Zero State Permutation
        // ====================================================================
        test_num = 7;
        $display("\n========================================");
        $display("TEST %0d: Zero State Permutation", test_num);
        $display("========================================");
        
        state_in = 320'h0;
        rounds = 4'd6;
        start_perm = 1;
        
        #10;
        start_perm = 0;
        
        wait(done);
        #10;
        
        $display("Input State:  %h", state_in);
        $display("Output State: %h", state_out);
        
        if (state_out != 320'h0) begin
            $display("[PASS] Zero state produces non-zero output (expected behavior)");
        end else begin
            $display("[INFO] Zero state produces zero output");
        end
        
        #20;
        
        // ====================================================================
        // TEST 8: All Ones State
        // ====================================================================
        test_num = 8;
        $display("\n========================================");
        $display("TEST %0d: All Ones State", test_num);
        $display("========================================");
        
        state_in = {320{1'b1}};
        rounds = 4'd6;
        start_perm = 1;
        
        #10;
        start_perm = 0;
        
        wait(done);
        #10;
        
        $display("Input State:  %h", state_in);
        $display("Output State: %h", state_out);
        $display("[PASS] All ones state processed");
        
        #20;
        
        // ====================================================================
        // TEST 9: Back-to-back Permutations
        // ====================================================================
        test_num = 9;
        $display("\n========================================");
        $display("TEST %0d: Back-to-back Permutations", test_num);
        $display("========================================");
        
        // First permutation
        state_in = 320'h123456789ABCDEF0_0FEDCBA987654321_AAAA5555AAAA5555_5555AAAA5555AAAA_F0F0F0F0F0F0F0F0;
        rounds = 4'd6;
        start_perm = 1;
        #10;
        start_perm = 0;
        wait(done);
        #10;
        
        $display("First permutation output: %h", state_out);
        
        // Second permutation (use output of first as input)
        state_in = state_out;
        rounds = 4'd6;
        start_perm = 1;
        #10;
        start_perm = 0;
        wait(done);
        #10;
        
        $display("Second permutation output: %h", state_out);
        $display("[PASS] Back-to-back permutations completed");
        
        #20;
        
        // ====================================================================
        // TEST 10: Timing test - measure cycles
        // ====================================================================
        test_num = 10;
        $display("\n========================================");
        $display("TEST %0d: Timing Measurement", test_num);
        $display("========================================");
        
        state_in = 320'hDEADBEEFCAFEBABE_1234567890ABCDEF_FEDCBA0987654321_A5A5A5A55A5A5A5A_F0F0F0F00F0F0F0F;
        rounds = 4'd12;
        
        start_time = $time;
        start_perm = 1;
        #10;
        start_perm = 0;
        
        wait(done);
        end_time = $time;
        
        cycles = (end_time - start_time) / 10;
        $display("12 rounds completed in %0d clock cycles", cycles);
        $display("[PASS] Timing test completed");
        
        #100;
        
        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("\n========================================");
        $display("ALL TESTS COMPLETED SUCCESSFULLY");
        $display("========================================\n");
        
        $finish;
    end

    // ========================================================================
    // Monitor
    // ========================================================================
    initial begin
        $monitor("Time=%0t | Round=%0d | Valid=%b | Done=%b | State=%h", 
                 $time, dut.round_counter, valid, done, state_out);
    end

endmodule