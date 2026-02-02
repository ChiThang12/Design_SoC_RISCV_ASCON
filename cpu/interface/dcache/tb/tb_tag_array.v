// ============================================================================
// Testbench: tb_dcache_tag_array
// ============================================================================
// Description:
//   Test tag array lookup, update, and flush operations
// ============================================================================

`timescale 1ns/1ps
`include "dcache_defines.vh"
`include "dcache_tag_array.v"

module tb_dcache_tag_array;

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
    
    // DUT Instance
    dcache_tag_array dut (
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
    
    // Clock Generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test Sequence
    initial begin
        $display("========================================");
        $display("DCache Tag Array Testbench");
        $display("========================================");
        
        // Initialize
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
        
        // Test 1: Lookup on empty cache (should miss)
        $display("\nTest 1: Lookup on empty cache");
        lookup_index = 6'h00;
        lookup_tag = 22'h12345;
        #10;
        if (!hit) $display("  PASS: Miss on empty cache");
        else $display("  FAIL: Expected miss");
        
        // Test 2: Update entry
        $display("\nTest 2: Update entry at index 0");
        update_valid = 1;
        update_index = 6'h00;
        update_tag = 22'h12345;
        #10;
        update_valid = 0;
        #10;
        
        // Test 3: Lookup after update (should hit)
        $display("\nTest 3: Lookup after update");
        lookup_index = 6'h00;
        lookup_tag = 22'h12345;
        #10;
        if (hit) $display("  PASS: Hit after update");
        else $display("  FAIL: Expected hit");
        
        // Test 4: Lookup with wrong tag (should miss)
        $display("\nTest 4: Lookup with wrong tag");
        lookup_index = 6'h00;
        lookup_tag = 22'h99999;
        #10;
        if (!hit) $display("  PASS: Miss with wrong tag");
        else $display("  FAIL: Expected miss");
        
        // Test 5: Update multiple entries
        $display("\nTest 5: Update multiple entries");
        update_valid = 1;
        update_index = 6'h01;
        update_tag = 22'hABCDE;
        #10;
        update_index = 6'h02;
        update_tag = 22'h11111;
        #10;
        update_index = 6'h3F;  // Last entry
        update_tag = 22'hFFFFF;
        #10;
        update_valid = 0;
        #10;
        
        // Test 6: Verify multiple entries
        $display("\nTest 6: Verify multiple entries");
        lookup_index = 6'h01;
        lookup_tag = 22'hABCDE;
        #10;
        if (hit) $display("  PASS: Entry 1 hit");
        else $display("  FAIL: Entry 1 miss");
        
        lookup_index = 6'h02;
        lookup_tag = 22'h11111;
        #10;
        if (hit) $display("  PASS: Entry 2 hit");
        else $display("  FAIL: Entry 2 miss");
        
        lookup_index = 6'h3F;
        lookup_tag = 22'hFFFFF;
        #10;
        if (hit) $display("  PASS: Entry 63 hit");
        else $display("  FAIL: Entry 63 miss");
        
        // Test 7: Flush all entries
        $display("\nTest 7: Flush all entries");
        flush_all = 1;
        #10;
        flush_all = 0;
        #10;
        
        // Test 8: Verify all flushed
        $display("\nTest 8: Verify all entries flushed");
        lookup_index = 6'h00;
        lookup_tag = 22'h12345;
        #10;
        if (!hit) $display("  PASS: Entry 0 flushed");
        else $display("  FAIL: Entry 0 not flushed");
        
        lookup_index = 6'h01;
        lookup_tag = 22'hABCDE;
        #10;
        if (!hit) $display("  PASS: Entry 1 flushed");
        else $display("  FAIL: Entry 1 not flushed");
        
        #100;
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================");
        $finish;
    end
    
    // Monitor
    initial begin
        $monitor("Time=%0t lookup_idx=%h lookup_tag=%h hit=%b update=%b update_idx=%h update_tag=%h",
                 $time, lookup_index, lookup_tag, hit, update_valid, update_index, update_tag);
    end

endmodule