// ============================================================================
// Testbench: tb_icache_controller_fixed (AXI4 Compatible)
// ============================================================================
// Description:
//   Test cache controller state machine and integration
//   Updated for fixed controller with proper timing
//   Compatible with combinational cache HIT response
// ============================================================================

`timescale 1ns/1ps
`include "icache_defines.vh"
`include "icache_controller.v"
module tb_icache_controller_fixed;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // CPU Interface
    // ========================================================================
    reg [31:0] cpu_addr;
    reg        cpu_req;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    reg        flush;
    
    // ========================================================================
    // Tag Array Interface
    // ========================================================================
    wire [5:0]  tag_lookup_index;
    wire [21:0] tag_lookup_tag;
    reg         tag_hit;
    wire        tag_update_valid;
    wire [5:0]  tag_update_index;
    wire [21:0] tag_update_tag;
    wire        tag_flush_all;
    
    // ========================================================================
    // Data Array Interface
    // ========================================================================
    wire [5:0]  data_read_index;
    wire [1:0]  data_read_offset;
    reg [31:0]  data_read_data;
    wire        data_write_enable;
    wire [5:0]  data_write_index;
    wire [1:0]  data_write_offset;
    wire [31:0] data_write_data;
    
    // ========================================================================
    // AXI Refill Interface
    // ========================================================================
    wire [31:0] refill_addr;
    wire        refill_start;
    reg         refill_busy;
    reg         refill_done;
    reg [31:0]  refill_data;
    reg [1:0]   refill_word;
    reg         refill_data_valid;
    
    // ========================================================================
    // Statistics
    // ========================================================================
    wire [31:0] stat_hits;
    wire [31:0] stat_misses;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    icache_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .flush(flush),
        .tag_lookup_index(tag_lookup_index),
        .tag_lookup_tag(tag_lookup_tag),
        .tag_hit(tag_hit),
        .tag_update_valid(tag_update_valid),
        .tag_update_index(tag_update_index),
        .tag_update_tag(tag_update_tag),
        .tag_flush_all(tag_flush_all),
        .data_read_index(data_read_index),
        .data_read_offset(data_read_offset),
        .data_read_data(data_read_data),
        .data_write_enable(data_write_enable),
        .data_write_index(data_write_index),
        .data_write_offset(data_write_offset),
        .data_write_data(data_write_data),
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        .stat_hits(stat_hits),
        .stat_misses(stat_misses)
    );
    
    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // Simulated Tag/Data Arrays
    // ========================================================================
    reg [31:0] sim_data [0:255];
    integer i;
    
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            sim_data[i] = 32'hD000_0000 + i;
        end
    end
    
    // Simulate data read (combinational)
    wire [7:0] data_addr;
    assign data_addr = {data_read_index, data_read_offset};
    
    always @(*) begin
        data_read_data = sim_data[data_addr];
    end
    
    // Simulate data write (sequential)
    always @(posedge clk) begin
        if (data_write_enable) begin
            sim_data[{data_write_index, data_write_offset}] <= data_write_data;
        end
    end
    
    // ========================================================================
    // Simulated Memory (for Refill)
    // ========================================================================
    reg [31:0] memory [0:1023];
    integer j;
    
    initial begin
        for (j = 0; j < 1024; j = j + 1) begin
            memory[j] = 32'h1000_0000 + (j << 2);
        end
    end
    
    // ========================================================================
    // AXI4 Burst Refill Simulator
    // ========================================================================
    reg [2:0] refill_state;
    reg [1:0] refill_cnt;
    reg [31:0] refill_base_addr;
    
    localparam REFILL_IDLE = 3'd0;
    localparam REFILL_AR   = 3'd1;
    localparam REFILL_R    = 3'd2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refill_busy       <= 1'b0;
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            refill_data       <= 32'h0;
            refill_word       <= 2'b00;
            refill_state      <= REFILL_IDLE;
            refill_cnt        <= 2'b00;
            refill_base_addr  <= 32'h0;
        end else begin
            // Default: clear one-shot signals
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            
            case (refill_state)
                REFILL_IDLE: begin
                    if (refill_start) begin
                        refill_busy      <= 1'b1;
                        refill_base_addr <= refill_addr;
                        refill_cnt       <= 2'b00;
                        refill_state     <= REFILL_AR;
                    end
                end
                
                REFILL_AR: begin
                    // Simulate AR channel delay
                    refill_state <= REFILL_R;
                end
                
                REFILL_R: begin
                    // Simulate AXI4 burst: deliver all 4 beats
                    refill_data       <= memory[refill_base_addr[11:2] + refill_cnt];
                    refill_word       <= refill_cnt;
                    refill_data_valid <= 1'b1;
                    
                    if (refill_cnt == 2'b11) begin
                        // Last beat (RLAST)
                        refill_done  <= 1'b1;
                        refill_busy  <= 1'b0;
                        refill_state <= REFILL_IDLE;
                    end else begin
                        // Continue burst
                        refill_cnt <= refill_cnt + 1;
                    end
                end
                
                default: refill_state <= REFILL_IDLE;
            endcase
        end
    end
    
    // ========================================================================
    // Test Tasks
    // ========================================================================
    
    // Task for CPU read request (CACHE HIT - FIXED TIMING)
    task cpu_read_hit;
        input [31:0] addr;
        input [31:0] expected_data;
        begin
            $display("  Testing HIT: Addr=0x%08h", addr);
            
            cpu_addr = addr;
            cpu_req = 1;
            tag_hit = 1;
            
            @(posedge clk);  // IDLE → COMPARE transition
            @(posedge clk);  // COMPARE state, cpu_ready should be 1
            
            if (!cpu_ready) begin
                $display("  [FAIL] cpu_ready not asserted for HIT at addr 0x%08h", addr);
                $display("        State: %0d, tag_hit: %0b", dut.state, tag_hit);
                $finish;
            end
            
            if (cpu_rdata !== expected_data) begin
                $display("  [FAIL] Wrong data for HIT");
                $display("        Expected: 0x%08h, Got: 0x%08h", expected_data, cpu_rdata);
                $finish;
            end
            
            $display("  [OK] HIT: Data=0x%08h", cpu_rdata);
            
            cpu_req = 0;
            @(posedge clk);
        end
    endtask
    
    // Task for CPU read request (CACHE MISS)
    task cpu_read_miss;
        input [31:0] addr;
        begin
            $display("  Testing MISS: Addr=0x%08h", addr);
            
            cpu_addr = addr;
            cpu_req = 1;
            tag_hit = 0;
            
            // Wait for refill to start
            wait(refill_start);
            $display("    Refill started at 0x%08h", refill_addr);
            
            // Wait for refill to complete
            wait(refill_done);
            @(posedge clk);
            
            if (!cpu_ready) begin
                $display("  [FAIL] cpu_ready not asserted after refill");
                $finish;
            end
            
            $display("  [OK] MISS refilled: Data=0x%08h", cpu_rdata);
            
            cpu_req = 0;
            @(posedge clk);
        end
    endtask
    integer beat_count;
    // ========================================================================
    // Test Stimulus
    // ========================================================================
    integer test_count = 0;
    integer pass_count = 0;
    
    initial begin
        $display("========================================");
        $display("Cache Controller Testbench (FIXED)");
        $display("========================================\n");
        
        // Initialize signals
        rst_n = 0;
        cpu_addr = 0;
        cpu_req = 0;
        flush = 0;
        tag_hit = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #20;
        
        // ====================================================================
        // TEST 1: Simple Cache HIT
        // ====================================================================
        $display("[TEST 1] Simple Cache HIT");
        test_count = test_count + 1;
        
        cpu_read_hit(32'h0000_0140, 32'hD000_0050);
        
        if (stat_hits !== 1) begin
            $display("  [FAIL] Hit counter wrong. Expected: 1, Got: %0d", stat_hits);
            $finish;
        end
        
        $display("  [PASS] Cache HIT works correctly\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 2: Simple Cache MISS
        // ====================================================================
        $display("[TEST 2] Simple Cache MISS");
        test_count = test_count + 1;
        
        cpu_read_miss(32'h0000_0240);
        
        if (stat_misses !== 1) begin
            $display("  [FAIL] Miss counter wrong. Expected: 1, Got: %0d", stat_misses);
            $finish;
        end
        
        $display("  [PASS] Cache MISS and refill work correctly\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 3: Verify refilled data becomes HIT
        // ====================================================================
        $display("[TEST 3] Refilled line becomes HIT");
        test_count = test_count + 1;
        
        // Access same line again - should be HIT
        cpu_addr = 32'h0000_0240;
        cpu_req = 1;
        tag_hit = 1;
        
        @(posedge clk);
        @(posedge clk);
        
        if (!cpu_ready) begin
            $display("  [FAIL] Should be HIT after refill");
            $finish;
        end
        
        if (stat_hits !== 2) begin
            $display("  [FAIL] Hit counter wrong after refill");
            $finish;
        end
        
        cpu_req = 0;
        $display("  [PASS] Refilled data accessible as HIT\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 4: Multiple sequential HITs
        // ====================================================================
        $display("[TEST 4] Multiple sequential HITs");
        test_count = test_count + 1;
        
        cpu_read_hit(32'h0000_0140, 32'hD000_0050);
        #20;
        cpu_read_hit(32'h0000_0144, 32'hD000_0051);
        #20;
        cpu_read_hit(32'h0000_0148, 32'hD000_0052);
        
        if (stat_hits !== 5) begin
            $display("  [FAIL] Hit counter wrong. Expected: 5, Got: %0d", stat_hits);
            $finish;
        end
        
        $display("  [PASS] Multiple HITs work correctly\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 5: Back-to-back MISSes
        // ====================================================================
        $display("[TEST 5] Back-to-back MISSes");
        test_count = test_count + 1;
        
        cpu_read_miss(32'h0000_0340);
        #20;
        cpu_read_miss(32'h0000_0440);
        
        if (stat_misses !== 3) begin
            $display("  [FAIL] Miss counter wrong. Expected: 3, Got: %0d", stat_misses);
            $finish;
        end
        
        $display("  [PASS] Back-to-back MISSes handled\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 6: Different offsets in same line
        // ====================================================================
        $display("[TEST 6] Different word offsets in same cache line");
        test_count = test_count + 1;
        
        cpu_read_hit(32'h0000_0140, 32'hD000_0050); // offset=0
        #20;
        cpu_read_hit(32'h0000_0144, 32'hD000_0051); // offset=1
        #20;
        cpu_read_hit(32'h0000_0148, 32'hD000_0052); // offset=2
        #20;
        cpu_read_hit(32'h0000_014C, 32'hD000_0053); // offset=3
        
        $display("  [PASS] All offsets accessible\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 7: Flush operation
        // ====================================================================
        $display("[TEST 7] Cache flush");
        test_count = test_count + 1;
        
        flush = 1;
        @(posedge clk);
        
        if (!tag_flush_all) begin
            $display("  [FAIL] Flush signal not propagated");
            $finish;
        end
        
        flush = 0;
        @(posedge clk);
        
        $display("  [PASS] Flush operation works\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 8: Tag update verification
        // ====================================================================
        $display("[TEST 8] Tag update on refill");
        test_count = test_count + 1;
        
        cpu_addr = 32'h0000_0540;
        cpu_req = 1;
        tag_hit = 0;
        
        wait(tag_update_valid);
        @(posedge clk);
        
        if (tag_update_index !== cpu_addr[9:4]) begin
            $display("  [FAIL] Wrong tag index. Expected: %0d, Got: %0d", 
                     cpu_addr[9:4], tag_update_index);
            $finish;
        end
        
        if (tag_update_tag !== cpu_addr[31:10]) begin
            $display("  [FAIL] Wrong tag value. Expected: 0x%06h, Got: 0x%06h",
                     cpu_addr[31:10], tag_update_tag);
            $finish;
        end
        
        wait(cpu_ready);
        cpu_req = 0;
        @(posedge clk);
        
        $display("  [PASS] Tag updated correctly");
        $display("        Index=%0d, Tag=0x%06h\n", tag_update_index, tag_update_tag);
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 9: AXI4 burst verification
        // ====================================================================
        $display("[TEST 9] AXI4 burst refill (4 beats)");
        test_count = test_count + 1;
        
        cpu_addr = 32'h0000_0640;
        cpu_req = 1;
        tag_hit = 0;
        
        wait(refill_start);
        $display("  Burst started for line at 0x%08h", refill_addr);
        
        
        beat_count = 0;
        
        while (!refill_done) begin
            @(posedge clk);
            if (refill_data_valid) begin
                $display("    Beat %0d: Word[%0d]=0x%08h", 
                         beat_count, refill_word, refill_data);
                beat_count = beat_count + 1;
            end
        end
        
        if (beat_count !== 4) begin
            $display("  [FAIL] Expected 4 beats, got %0d", beat_count);
            $finish;
        end
        
        wait(cpu_ready);
        cpu_req = 0;
        @(posedge clk);
        
        $display("  [PASS] All 4 beats received\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // TEST 10: Stress test - Random accesses
        // ====================================================================
        $display("[TEST 10] Stress test - Random HIT/MISS pattern");
        test_count = test_count + 1;
        
        // Pattern: HIT, MISS, HIT, HIT, MISS
        cpu_read_hit(32'h0000_0140, 32'hD000_0050);
        #20;
        cpu_read_miss(32'h0000_0740);
        #20;
        cpu_read_hit(32'h0000_0144, 32'hD000_0051);
        #20;
        cpu_read_hit(32'h0000_0740, 32'h1000_01D0);
        #20;
        cpu_read_miss(32'h0000_0840);
        
        $display("  [PASS] Mixed HIT/MISS pattern handled\n");
        pass_count = pass_count + 1;
        #50;
        
        // ====================================================================
        // Final Report
        // ====================================================================
        $display("========================================");
        $display("     TEST SUMMARY");
        $display("========================================");
        $display("Tests Passed: %0d / %0d", pass_count, test_count);
        $display("----------------------------------------");
        $display("Total Cache Hits:   %0d", stat_hits);
        $display("Total Cache Misses: %0d", stat_misses);
        $display("Hit Rate: %.1f%%", 
                 (stat_hits * 100.0) / (stat_hits + stat_misses));
        $display("========================================");
        
        if (pass_count == test_count) begin
            $display("✓ ALL TESTS PASSED!");
        end else begin
            $display("✗ SOME TESTS FAILED!");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    // ========================================================================
    // Monitor (Debug)
    // ========================================================================
    always @(posedge clk) begin
        if (cpu_req && cpu_ready) begin
            $display("    [CPU] Addr: 0x%08h → Data: 0x%08h (%s)", 
                     cpu_addr, cpu_rdata, tag_hit ? "HIT" : "MISS");
        end
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_icache_controller_fixed.vcd");
        $dumpvars(0, tb_icache_controller_fixed);
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #500000;
        $display("\n[ERROR] Simulation timeout!");
        $display("Current state: %0d", dut.state);
        $finish;
    end

endmodule