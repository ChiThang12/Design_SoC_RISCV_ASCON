// ============================================================================
// ASCON_CONTROLLER Testbench
// Mô tả: Testbench đầy đủ cho FSM điều khiển ASCON
// ============================================================================

`timescale 1ns/1ps
`include "ascon_CONTROLLER.v"
module tb_ASCON_CONTROLLER;

    // ========================================================================
    // Test signals
    // ========================================================================
    reg        clk;
    reg        rst_n;
    reg  [1:0] mode;
    reg        start;
    reg        data_valid;
    reg        data_last;
    reg        ad_valid;
    reg        ad_last;
    reg        perm_done;
    
    wire [4:0] state;
    wire       load_init;
    wire [2:0] init_select;
    wire       start_perm;
    wire [3:0] perm_rounds;
    wire       xor_enable;
    wire [2:0] xor_position;
    wire       output_enable;
    wire       ready;
    wire       busy;

    // ========================================================================
    // Instantiate DUT
    // ========================================================================
    ASCON_CONTROLLER dut (
        .clk(clk),
        .rst_n(rst_n),
        .mode(mode),
        .start(start),
        .data_valid(data_valid),
        .data_last(data_last),
        .ad_valid(ad_valid),
        .ad_last(ad_last),
        .perm_done(perm_done),
        .state(state),
        .load_init(load_init),
        .init_select(init_select),
        .start_perm(start_perm),
        .perm_rounds(perm_rounds),
        .xor_enable(xor_enable),
        .xor_position(xor_position),
        .output_enable(output_enable),
        .ready(ready),
        .busy(busy)
    );

    // ========================================================================
    // Clock generation: 10ns period
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
    
    // State names for display
    reg [200:0] state_name;
    always @(*) begin
        case (state)
            5'd0:  state_name = "IDLE";
            5'd1:  state_name = "INIT";
            5'd2:  state_name = "INIT_PERM";
            5'd3:  state_name = "PROCESS_AD";
            5'd4:  state_name = "AD_PERM";
            5'd5:  state_name = "AD_FINAL";
            5'd6:  state_name = "PROCESS_DATA";
            5'd7:  state_name = "DATA_PERM";
            5'd8:  state_name = "FINALIZE";
            5'd9:  state_name = "FINAL_PERM";
            5'd10: state_name = "OUTPUT_TAG";
            5'd11: state_name = "HASH_INIT";
            5'd12: state_name = "HASH_ABSORB";
            5'd13: state_name = "HASH_SQUEEZE";
            5'd14: state_name = "WAIT_PERM";
            default: state_name = "UNKNOWN";
        endcase
    end

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        // Waveform dump
        $dumpfile("ascon_controller.vcd");
        $dumpvars(0, tb_ASCON_CONTROLLER);
        
        // Initialize
        test_num = 0;
        rst_n = 0;
        mode = 2'b00;
        start = 0;
        data_valid = 0;
        data_last = 0;
        ad_valid = 0;
        ad_last = 0;
        perm_done = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // ====================================================================
        // TEST 1: IDLE state check
        // ====================================================================
        test_num = 1;
        $display("\n========================================");
        $display("TEST %0d: IDLE State Check", test_num);
        $display("========================================");
        
        check_state(5'd0, "IDLE");
        check_signal(ready, 1'b1, "ready");
        check_signal(busy, 1'b0, "busy");
        #20;
        
        // ====================================================================
        // TEST 2: Encryption Flow WITHOUT Associated Data
        // ====================================================================
        test_num = 2;
        $display("\n========================================");
        $display("TEST %0d: Encryption Flow (No AD)", test_num);
        $display("========================================");
        
        // Start encryption
        mode = 2'b00;  // MODE_ENCRYPT
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Should go to INIT
        @(posedge clk);
        if (state == 5'd1) begin
            check_state(5'd1, "INIT");
            check_signal(load_init, 1'b1, "load_init");
        end
        
        // Then to INIT_PERM
        @(posedge clk);
        check_state(5'd2, "INIT_PERM");
        check_signal(start_perm, 1'b1, "start_perm");
        check_value(perm_rounds, 4'd12, "perm_rounds (p^12)");
        
        // Simulate permutation completion
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Should go to PROCESS_AD
        @(posedge clk);
        check_state(5'd3, "PROCESS_AD");
        
        // No AD, signal ad_last immediately
        ad_last = 1;
        @(posedge clk);
        ad_last = 0;
        
        // Should go to AD_FINAL
        @(posedge clk);
        check_state(5'd5, "AD_FINAL");
        
        // Then to PROCESS_DATA
        @(posedge clk);
        check_state(5'd6, "PROCESS_DATA");
        
        // Send data block
        data_valid = 1;
        data_last = 0;
        @(posedge clk);
        data_valid = 0;
        
        // Should go to DATA_PERM
        @(posedge clk);
        check_state(5'd7, "DATA_PERM");
        check_signal(start_perm, 1'b1, "start_perm");
        check_value(perm_rounds, 4'd6, "perm_rounds (p^6)");
        
        // Complete permutation
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Back to PROCESS_DATA for last block
        @(posedge clk);
        check_state(5'd6, "PROCESS_DATA");
        
        data_valid = 1;
        data_last = 1;
        @(posedge clk);
        data_valid = 0;
        data_last = 0;
        
        // Should go to DATA_PERM then FINALIZE
        @(posedge clk);
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        check_state(5'd8, "FINALIZE");
        
        // Then FINAL_PERM
        @(posedge clk);
        check_state(5'd9, "FINAL_PERM");
        check_value(perm_rounds, 4'd12, "perm_rounds (p^12)");
        
        // Complete final permutation
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // OUTPUT_TAG
        @(posedge clk);
        check_state(5'd10, "OUTPUT_TAG");
        check_signal(output_enable, 1'b1, "output_enable");
        
        // Back to IDLE
        @(posedge clk);
        check_state(5'd0, "IDLE");
        
        $display("[PASS] Encryption flow without AD completed");
        #20;
        
        // ====================================================================
        // TEST 3: Encryption Flow WITH Associated Data
        // ====================================================================
        test_num = 3;
        $display("\n========================================");
        $display("TEST %0d: Encryption Flow (With AD)", test_num);
        $display("========================================");
        
        // Start encryption
        mode = 2'b00;
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for INIT_PERM
        wait(state == 5'd2);
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Should be in PROCESS_AD
        @(posedge clk);
        check_state(5'd3, "PROCESS_AD");
        
        // Send first AD block
        ad_valid = 1;
        ad_last = 0;
        @(posedge clk);
        ad_valid = 0;
        
        // Should go to AD_PERM
        @(posedge clk);
        check_state(5'd4, "AD_PERM");
        check_value(perm_rounds, 4'd6, "perm_rounds (p^6)");
        
        // Complete AD permutation
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Back to PROCESS_AD for second block
        @(posedge clk);
        check_state(5'd3, "PROCESS_AD");
        
        // Send last AD block
        ad_valid = 1;
        ad_last = 1;
        @(posedge clk);
        ad_valid = 0;
        ad_last = 0;
        
        // Should go to AD_PERM
        @(posedge clk);
        check_state(5'd4, "AD_PERM");
        
        // Complete permutation
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Should go to AD_FINAL
        @(posedge clk);
        check_state(5'd5, "AD_FINAL");
        check_signal(xor_enable, 1'b1, "xor_enable");
        check_value(xor_position, 3'd4, "xor_position (domain sep)");
        
        // Continue to PROCESS_DATA
        @(posedge clk);
        check_state(5'd6, "PROCESS_DATA");
        
        // Send data and complete encryption
        data_valid = 1;
        data_last = 1;
        @(posedge clk);
        data_valid = 0;
        data_last = 0;
        
        // Wait for finalization
        wait(state == 5'd9);  // FINAL_PERM
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Should output tag
        @(posedge clk);
        check_state(5'd10, "OUTPUT_TAG");
        
        // Back to IDLE
        @(posedge clk);
        check_state(5'd0, "IDLE");
        
        $display("[PASS] Encryption flow with AD completed");
        #20;
        
        // ====================================================================
        // TEST 4: Decryption Flow
        // ====================================================================
        test_num = 4;
        $display("\n========================================");
        $display("TEST %0d: Decryption Flow", test_num);
        $display("========================================");
        
        // Start decryption
        mode = 2'b01;  // MODE_DECRYPT
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait for INIT_PERM
        wait(state == 5'd2);
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Skip AD phase
        @(posedge clk);
        ad_last = 1;
        @(posedge clk);
        ad_last = 0;
        
        // Wait for PROCESS_DATA
        wait(state == 5'd6);
        @(posedge clk);
        
        // Send ciphertext
        data_valid = 1;
        data_last = 1;
        @(posedge clk);
        data_valid = 0;
        data_last = 0;
        
        // Wait for tag output
        wait(state == 5'd10);
        @(posedge clk);
        check_state(5'd10, "OUTPUT_TAG");
        
        @(posedge clk);
        check_state(5'd0, "IDLE");
        
        $display("[PASS] Decryption flow completed");
        #20;
        
        // ====================================================================
        // TEST 5: Hash Mode
        // ====================================================================
        test_num = 5;
        $display("\n========================================");
        $display("TEST %0d: Hash Mode", test_num);
        $display("========================================");
        
        // Start hash
        mode = 2'b10;  // MODE_HASH
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Should go to HASH_INIT
        @(posedge clk);
        check_state(5'd11, "HASH_INIT");
        check_signal(load_init, 1'b1, "load_init");
        check_signal(start_perm, 1'b1, "start_perm");
        check_value(perm_rounds, 4'd12, "perm_rounds");
        
        // Complete init permutation
        @(posedge clk);
        check_state(5'd14, "WAIT_PERM");
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Should go to HASH_ABSORB
        @(posedge clk);
        check_state(5'd12, "HASH_ABSORB");
        
        // Absorb first block
        data_valid = 1;
        data_last = 0;
        @(posedge clk);
        data_valid = 0;
        check_signal(xor_enable, 1'b1, "xor_enable");
        
        // Should start permutation
        @(posedge clk);
        check_state(5'd14, "WAIT_PERM");
        check_signal(start_perm, 1'b1, "start_perm");
        
        // Complete permutation
        @(posedge clk);
        perm_done = 1;
        @(posedge clk);
        perm_done = 0;
        
        // Back to HASH_ABSORB
        @(posedge clk);
        check_state(5'd12, "HASH_ABSORB");
        
        // Absorb last block
        data_valid = 1;
        data_last = 1;
        @(posedge clk);
        data_valid = 0;
        data_last = 0;
        
        // Should go to HASH_SQUEEZE
        @(posedge clk);
        check_state(5'd13, "HASH_SQUEEZE");
        check_signal(output_enable, 1'b1, "output_enable");
        
        // Back to IDLE
        @(posedge clk);
        check_state(5'd0, "IDLE");
        
        $display("[PASS] Hash mode completed");
        #20;
        
        // ====================================================================
        // TEST 6: Multiple operations back-to-back
        // ====================================================================
        test_num = 6;
        $display("\n========================================");
        $display("TEST %0d: Back-to-back Operations", test_num);
        $display("========================================");
        
        for (i = 0; i < 3; i = i + 1) begin
            $display("\n--- Iteration %0d ---", i+1);
            
            // Start encryption
            mode = 2'b00;
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Fast-forward through encryption
            wait(state == 5'd2);
            @(posedge clk); perm_done = 1; @(posedge clk); perm_done = 0;
            
            wait(state == 5'd3);
            @(posedge clk); ad_last = 1; @(posedge clk); ad_last = 0;
            
            wait(state == 5'd6);
            @(posedge clk); data_valid = 1; data_last = 1;
            @(posedge clk); data_valid = 0; data_last = 0;
            
            wait(state == 5'd9);
            @(posedge clk); perm_done = 1; @(posedge clk); perm_done = 0;
            
            wait(state == 5'd0);
            $display("Iteration %0d completed", i+1);
            #20;
        end
        
        $display("[PASS] Back-to-back operations completed");
        #20;
        
        // ====================================================================
        // TEST 7: Reset during operation
        // ====================================================================
        test_num = 7;
        $display("\n========================================");
        $display("TEST %0d: Reset During Operation", test_num);
        $display("========================================");
        
        // Start encryption
        mode = 2'b00;
        start = 1;
        @(posedge clk);
        start = 0;
        
        // Wait until in the middle of processing
        wait(state == 5'd2);
        #20;
        
        // Assert reset
        $display("Asserting reset while in state: %s", state_name);
        rst_n = 0;
        #20;
        rst_n = 1;
        @(posedge clk);
        
        // Should be back in IDLE
        check_state(5'd0, "IDLE after reset");
        check_signal(ready, 1'b1, "ready after reset");
        
        $display("[PASS] Reset during operation completed");
        #20;
        
        // ====================================================================
        // Final summary
        // ====================================================================
        $display("\n========================================");
        $display("ALL TESTS COMPLETED SUCCESSFULLY");
        $display("Total tests run: %0d", test_num);
        $display("========================================\n");
        
        #100;
        $finish;
    end

    // ========================================================================
    // Helper tasks
    // ========================================================================
    task check_state;
        input [4:0] expected;
        input [200:0] msg;
        begin
            if (state !== expected) begin
                $display("  [ERROR] State check failed: %s", msg);
                $display("    Expected: %0d, Got: %0d (%s)", expected, state, state_name);
                $finish;
            end else begin
                $display("  [PASS] State: %s", state_name);
            end
        end
    endtask
    
    task check_signal;
        input actual;
        input expected;
        input [200:0] signal_name;
        begin
            if (actual !== expected) begin
                $display("  [ERROR] Signal %s check failed", signal_name);
                $display("    Expected: %b, Got: %b", expected, actual);
                $finish;
            end else begin
                $display("  [PASS] %s = %b", signal_name, actual);
            end
        end
    endtask
    
    task check_value;
        input [31:0] actual;
        input [31:0] expected;
        input [200:0] value_name;
        begin
            if (actual !== expected) begin
                $display("  [ERROR] Value %s check failed", value_name);
                $display("    Expected: %0d, Got: %0d", expected, actual);
                $finish;
            end else begin
                $display("  [PASS] %s = %0d", value_name, actual);
            end
        end
    endtask

    // ========================================================================
    // Monitor state transitions
    // ========================================================================
    always @(posedge clk) begin
        if (state !== dut.next_state) begin
            $display("Time=%0t | State transition: %s -> %s", 
                     $time, state_name, get_state_name(dut.next_state));
        end
    end
    
    function [200:0] get_state_name;
        input [4:0] s;
        begin
            case (s)
                5'd0:  get_state_name = "IDLE";
                5'd1:  get_state_name = "INIT";
                5'd2:  get_state_name = "INIT_PERM";
                5'd3:  get_state_name = "PROCESS_AD";
                5'd4:  get_state_name = "AD_PERM";
                5'd5:  get_state_name = "AD_FINAL";
                5'd6:  get_state_name = "PROCESS_DATA";
                5'd7:  get_state_name = "DATA_PERM";
                5'd8:  get_state_name = "FINALIZE";
                5'd9:  get_state_name = "FINAL_PERM";
                5'd10: get_state_name = "OUTPUT_TAG";
                5'd11: get_state_name = "HASH_INIT";
                5'd12: get_state_name = "HASH_ABSORB";
                5'd13: get_state_name = "HASH_SQUEEZE";
                5'd14: get_state_name = "WAIT_PERM";
                default: get_state_name = "UNKNOWN";
            endcase
        end
    endfunction

endmodule