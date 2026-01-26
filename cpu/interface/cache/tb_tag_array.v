// ============================================================================
// Testbench: tb_icache_tag_array
// ============================================================================
// Description:
//   Test tag array lookup, update, and flush operations
// ============================================================================

`timescale 1ns/1ps
`include "icache_tag_array.v"
module tb_icache_tag_array;

    // Clock and Reset
    reg clk;
    reg rst_n;
    
    // Lookup Interface
    reg [5:0]  lookup_index;
    reg [21:0] lookup_tag;
    wire       hit;
    
    // Update Interface
    reg        update_valid;
    reg [5:0]  update_index;
    reg [21:0] update_tag;
    
    // Flush Interface
    reg        flush_all;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    icache_tag_array dut (
        .clk(clk),
        .rst_n(rst_n),
        .lookup_index(lookup_index),
        .lookup_tag(lookup_tag),
        .hit(hit),
        .update_valid(update_valid),
        .update_index(update_index),
        .update_tag(update_tag),
        .flush_all(flush_all)
    );
    
    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // Test Stimulus
    // ========================================================================
    integer i;
    
    initial begin
        $display("========================================");
        $display("Starting Tag Array Testbench");
        $display("========================================");
        
        // Initialize signals
        rst_n = 0;
        lookup_index = 0;
        lookup_tag = 0;
        update_valid = 0;
        update_index = 0;
        update_tag = 0;
        flush_all = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // ====================================================================
        // TEST 1: Verify all entries invalid after reset
        // ====================================================================
        $display("\n[TEST 1] Checking all entries invalid after reset");
        for (i = 0; i < 64; i = i + 1) begin
            lookup_index = i;
            lookup_tag = 22'hABCDE;
            #10;
            if (hit) begin
                $display("  [FAIL] Entry %0d should be invalid!", i);
                $finish;
            end
        end
        $display("  [PASS] All entries invalid after reset");
        
        // ====================================================================
        // TEST 2: Write and verify single entry
        // ====================================================================
        $display("\n[TEST 2] Write and verify single entry");
        update_index = 6'd10;
        update_tag = 22'h12345;
        update_valid = 1;
        #10;
        update_valid = 0;
        
        // Lookup same entry (should hit)
        lookup_index = 6'd10;
        lookup_tag = 22'h12345;
        #10;
        if (!hit) begin
            $display("  [FAIL] Should hit on matching tag!");
            $finish;
        end
        $display("  [PASS] Tag match detected");
        
        // Lookup different tag (should miss)
        lookup_tag = 22'h54321;
        #10;
        if (hit) begin
            $display("  [FAIL] Should miss on different tag!");
            $finish;
        end
        $display("  [PASS] Tag mismatch detected");
        
        // ====================================================================
        // TEST 3: Write multiple entries
        // ====================================================================
        $display("\n[TEST 3] Write multiple entries");
        for (i = 0; i < 10; i = i + 1) begin
            update_index = i;
            update_tag = 22'h10000 + i;
            update_valid = 1;
            #10;
            update_valid = 0;
            #10;
        end
        
        // Verify all written entries
        for (i = 0; i < 10; i = i + 1) begin
            lookup_index = i;
            lookup_tag = 22'h10000 + i;
            #10;
            if (!hit) begin
                $display("  [FAIL] Entry %0d should hit!", i);
                $finish;
            end
        end
        $display("  [PASS] All entries verified");
        
        // ====================================================================
        // TEST 4: Flush all entries
        // ====================================================================
        $display("\n[TEST 4] Flush all entries");
        flush_all = 1;
        #10;
        flush_all = 0;
        #10;
        
        // Verify all entries invalid
        for (i = 0; i < 10; i = i + 1) begin
            lookup_index = i;
            lookup_tag = 22'h10000 + i;
            #10;
            if (hit) begin
                $display("  [FAIL] Entry %0d should be invalid after flush!", i);
                $finish;
            end
        end
        $display("  [PASS] All entries invalidated");
        
        // ====================================================================
        // TEST 5: Overwrite existing entry
        // ====================================================================
        $display("\n[TEST 5] Overwrite existing entry");
        // Write first tag
        update_index = 6'd20;
        update_tag = 22'hAAAAA;
        update_valid = 1;
        #10;
        update_valid = 0;
        #10;
        
        // Overwrite with new tag
        update_index = 6'd20;
        update_tag = 22'hBBBBB;
        update_valid = 1;
        #10;
        update_valid = 0;
        #10;
        
        // Old tag should miss
        lookup_index = 6'd20;
        lookup_tag = 22'hAAAAA;
        #10;
        if (hit) begin
            $display("  [FAIL] Old tag should miss!");
            $finish;
        end
        
        // New tag should hit
        lookup_tag = 22'hBBBBB;
        #10;
        if (!hit) begin
            $display("  [FAIL] New tag should hit!");
            $finish;
        end
        $display("  [PASS] Entry overwrite successful");
        
        // ====================================================================
        // TEST 6: Full cache test (all 64 entries)
        // ====================================================================
        $display("\n[TEST 6] Full cache test (64 entries)");
        for (i = 0; i < 64; i = i + 1) begin
            update_index = i;
            update_tag = 22'h20000 + i;
            update_valid = 1;
            #10;
            update_valid = 0;
            #10;
        end
        
        for (i = 0; i < 64; i = i + 1) begin
            lookup_index = i;
            lookup_tag = 22'h20000 + i;
            #10;
            if (!hit) begin
                $display("  [FAIL] Entry %0d should hit!", i);
                $finish;
            end
        end
        $display("  [PASS] All 64 entries working correctly");
        
        // ====================================================================
        // Test Complete
        // ====================================================================
        #100;
        $display("\n========================================");
        $display("All Tag Array Tests PASSED!");
        $display("========================================");
        $finish;
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_icache_tag_array.vcd");
        $dumpvars(0, tb_icache_tag_array);
    end
    
    // ========================================================================
    // Timeout
    // ========================================================================
    initial begin
        #50000;
        $display("\n[ERROR] Test timeout!");
        $finish;
    end

endmodule