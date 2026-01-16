// ============================================================================
// ASCON_STATE_REGISTER Testbench
// Mô tả: Testbench đầy đủ để kiểm tra module ASCON_STATE_REGISTER
// ============================================================================

`timescale 1ns/1ps
`include "ascon_STATE_REG.v"
module tb_ASCON_STATE_REGISTER;

    // ========================================================================
    // Tín hiệu testbench
    // ========================================================================
    reg         clk;
    reg         rst_n;
    reg         load_init;
    reg  [319:0] init_value;
    reg  [319:0] permutation_out;
    reg         permutation_valid;
    reg  [63:0] xor_data;
    reg  [2:0]  xor_position;
    reg         xor_enable;
    
    wire [319:0] state;
    wire [63:0] state_x0;
    wire [63:0] state_x1;
    wire [63:0] state_x2;
    wire [63:0] state_x3;
    wire [63:0] state_x4;

    // ========================================================================
    // Khởi tạo DUT (Device Under Test)
    // ========================================================================
    ascon_STATE_REG dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_init(load_init),
        .init_value(init_value),
        .permutation_out(permutation_out),
        .permutation_valid(permutation_valid),
        .xor_data(xor_data),
        .xor_position(xor_position),
        .xor_enable(xor_enable),
        .state(state),
        .state_x0(state_x0),
        .state_x1(state_x1),
        .state_x2(state_x2),
        .state_x3(state_x3),
        .state_x4(state_x4)
    );

    // ========================================================================
    // Clock generation: 10ns period (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================================================
    // Test scenarios
    // ========================================================================
    integer test_num;
    
    initial begin
        // Khởi tạo waveform dump
        $dumpfile("ascon_state_register.vcd");
        $dumpvars(0, tb_ASCON_STATE_REGISTER);
        
        // Khởi tạo tín hiệu
        test_num = 0;
        rst_n = 0;
        load_init = 0;
        init_value = 320'h0;
        permutation_out = 320'h0;
        permutation_valid = 0;
        xor_data = 64'h0;
        xor_position = 3'h0;
        xor_enable = 0;
        
        // ====================================================================
        // TEST 1: Reset
        // ====================================================================
        test_num = 1;
        $display("\n[TEST %0d] Reset Test", test_num);
        #20;
        rst_n = 1;
        #10;
        check_state(320'h0, "After reset");
        
        // ====================================================================
        // TEST 2: Load Initial Value
        // ====================================================================
        test_num = 2;
        $display("\n[TEST %0d] Load Initial Value", test_num);
        init_value = 320'h0123456789ABCDEF_FEDCBA9876543210_AAAAAAAAAAAAAAAA_5555555555555555_FFFFFFFFFFFFFFFF;
        load_init = 1;
        #10;
        load_init = 0;
        #10;
        check_state(init_value, "After load_init");
        check_word(state_x0, 64'h0123456789ABCDEF, "x0");
        check_word(state_x1, 64'hFEDCBA9876543210, "x1");
        check_word(state_x2, 64'hAAAAAAAAAAAAAAAA, "x2");
        check_word(state_x3, 64'h5555555555555555, "x3");
        check_word(state_x4, 64'hFFFFFFFFFFFFFFFF, "x4");
        
        // ====================================================================
        // TEST 3: XOR vào word x0
        // ====================================================================
        test_num = 3;
        $display("\n[TEST %0d] XOR into x0", test_num);
        xor_data = 64'hFFFFFFFFFFFFFFFF;
        xor_position = 3'd0;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        check_word(state_x0, 64'hFEDCBA9876543210, "x0 after XOR");
        
        // ====================================================================
        // TEST 4: XOR vào word x1
        // ====================================================================
        test_num = 4;
        $display("\n[TEST %0d] XOR into x1", test_num);
        xor_data = 64'h1111111111111111;
        xor_position = 3'd1;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        check_word(state_x1, 64'hEFCDAB8967452301, "x1 after XOR");
        
        // ====================================================================
        // TEST 5: XOR vào word x2
        // ====================================================================
        test_num = 5;
        $display("\n[TEST %0d] XOR into x2", test_num);
        xor_data = 64'h5555555555555555;
        xor_position = 3'd2;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        check_word(state_x2, 64'hFFFFFFFFFFFFFFFF, "x2 after XOR");
        
        // ====================================================================
        // TEST 6: XOR vào word x3
        // ====================================================================
        test_num = 6;
        $display("\n[TEST %0d] XOR into x3", test_num);
        xor_data = 64'hAAAAAAAAAAAAAAAA;
        xor_position = 3'd3;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        check_word(state_x3, 64'hFFFFFFFFFFFFFFFF, "x3 after XOR");
        
        // ====================================================================
        // TEST 7: XOR vào word x4
        // ====================================================================
        test_num = 7;
        $display("\n[TEST %0d] XOR into x4", test_num);
        xor_data = 64'h0000000000000001;
        xor_position = 3'd4;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        check_word(state_x4, 64'hFFFFFFFFFFFFFFFE, "x4 after XOR");
        
        // ====================================================================
        // TEST 8: Permutation Update
        // ====================================================================
        test_num = 8;
        $display("\n[TEST %0d] Permutation Update", test_num);
        permutation_out = 320'h1111111111111111_2222222222222222_3333333333333333_4444444444444444_5555555555555555;
        permutation_valid = 1;
        #10;
        permutation_valid = 0;
        #10;
        check_state(permutation_out, "After permutation");
        check_word(state_x0, 64'h1111111111111111, "x0 from perm");
        check_word(state_x1, 64'h2222222222222222, "x1 from perm");
        check_word(state_x2, 64'h3333333333333333, "x2 from perm");
        check_word(state_x3, 64'h4444444444444444, "x3 from perm");
        check_word(state_x4, 64'h5555555555555555, "x4 from perm");
        
        // ====================================================================
        // TEST 9: Kiểm tra ưu tiên - load_init > permutation_valid
        // ====================================================================
        test_num = 9;
        $display("\n[TEST %0d] Priority: load_init > permutation_valid", test_num);
        init_value = 320'hAAAAAAAAAAAAAAAA_BBBBBBBBBBBBBBBB_CCCCCCCCCCCCCCCC_DDDDDDDDDDDDDDDD_EEEEEEEEEEEEEEEE;
        permutation_out = 320'h9999999999999999_8888888888888888_7777777777777777_6666666666666666_5555555555555555;
        load_init = 1;
        permutation_valid = 1;
        #10;
        load_init = 0;
        permutation_valid = 0;
        #10;
        check_state(320'hAAAAAAAAAAAAAAAA_BBBBBBBBBBBBBBBB_CCCCCCCCCCCCCCCC_DDDDDDDDDDDDDDDD_EEEEEEEEEEEEEEEE, "load_init wins");
        
        // ====================================================================
        // TEST 10: Kiểm tra ưu tiên - permutation_valid > xor_enable
        // ====================================================================
        test_num = 10;
        $display("\n[TEST %0d] Priority: permutation_valid > xor_enable", test_num);
        permutation_out = 320'h0F0F0F0F0F0F0F0F_F0F0F0F0F0F0F0F0_0F0F0F0F0F0F0F0F_F0F0F0F0F0F0F0F0_0F0F0F0F0F0F0F0F;
        xor_data = 64'hFFFFFFFFFFFFFFFF;
        xor_position = 3'd0;
        permutation_valid = 1;
        xor_enable = 1;
        #10;
        permutation_valid = 0;
        xor_enable = 0;
        #10;
        check_state(permutation_out, "permutation_valid wins");
        
        // ====================================================================
        // TEST 11: State giữ nguyên khi không có lệnh
        // ====================================================================
        test_num = 11;
        $display("\n[TEST %0d] State Hold", test_num);
        #50;
        check_state(permutation_out, "State unchanged");
        
        // ====================================================================
        // TEST 12: XOR position out of range
        // ====================================================================
        test_num = 12;
        $display("\n[TEST %0d] XOR Invalid Position", test_num);
        xor_data = 64'hFFFFFFFFFFFFFFFF;
        xor_position = 3'd7; // Invalid
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        check_state(permutation_out, "State unchanged with invalid position");
        
        // ====================================================================
        // TEST 13: Sequential XOR operations
        // ====================================================================
        test_num = 13;
        $display("\n[TEST %0d] Sequential XOR Operations", test_num);
        init_value = {5{64'h0}};
        load_init = 1;
        #10;
        load_init = 0;
        #10;
        
        // XOR x0
        xor_data = 64'h1111111111111111;
        xor_position = 3'd0;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        
        // XOR x1
        xor_data = 64'h2222222222222222;
        xor_position = 3'd1;
        xor_enable = 1;
        #10;
        xor_enable = 0;
        #10;
        
        check_word(state_x0, 64'h1111111111111111, "Sequential XOR x0");
        check_word(state_x1, 64'h2222222222222222, "Sequential XOR x1");
        
        // ====================================================================
        // Kết thúc simulation
        // ====================================================================
        #100;
        $display("\n========================================");
        $display("All tests completed successfully!");
        $display("========================================\n");
        $finish;
    end

    // ========================================================================
    // Task kiểm tra state
    // ========================================================================
    task check_state;
        input [319:0] expected;
        input [200*8:1] msg;
        begin
            if (state !== expected) begin
                $display("  [ERROR] %s", msg);
                $display("    Expected: %h", expected);
                $display("    Got:      %h", state);
                $stop;
            end else begin
                $display("  [PASS] %s: %h", msg, state);
            end
        end
    endtask

    // ========================================================================
    // Task kiểm tra từng word
    // ========================================================================
    task check_word;
        input [63:0] actual;
        input [63:0] expected;
        input [50*8:1] word_name;
        begin
            if (actual !== expected) begin
                $display("  [ERROR] Word %s mismatch", word_name);
                $display("    Expected: %h", expected);
                $display("    Got:      %h", actual);
                $stop;
            end else begin
                $display("  [PASS] Word %s = %h", word_name, actual);
            end
        end
    endtask

    // ========================================================================
    // Monitor changes
    // ========================================================================
    initial begin
        $monitor("Time=%0t | state=%h | x0=%h x1=%h x2=%h x3=%h x4=%h", 
                 $time, state, state_x0, state_x1, state_x2, state_x3, state_x4);
    end

endmodule