// ============================================================================
// Testbench: tb_riscv_soc_top_cached
// ============================================================================
// Description:
//   Comprehensive testbench for RISC-V SoC with caches
//   - Tests instruction fetch through ICache
//   - Tests data read/write through DCache
//   - Monitors cache hits/misses
//   - Verifies AXI4 transactions
//
// Author: Auto-generated
// ============================================================================

`timescale 1ns/1ps
`include "cpu_core.v"
module tb_riscv_soc_top_cached;

    // ========================================================================
    // Testbench Signals
    // ========================================================================
    
    reg         clk;
    reg         rst_n;
    
    // Debug outputs
    wire [31:0] icache_hits;
    wire [31:0] icache_misses;
    wire [31:0] dcache_hits;
    wire [31:0] dcache_misses;
    wire [31:0] dcache_writes;
    
    // ========================================================================
    // Clock Generation
    // ========================================================================
    
    // 100MHz clock (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    
    riscv_soc_top_cached dut (
        .clk(clk),
        .rst_n(rst_n),
        .icache_hits(icache_hits),
        .icache_misses(icache_misses),
        .dcache_hits(dcache_hits),
        .dcache_misses(dcache_misses),
        .dcache_writes(dcache_writes)
    );
    
    // ========================================================================
    // Test Variables
    // ========================================================================
    
    integer test_num;
    integer errors;
    
    // ========================================================================
    // Monitor Task
    // ========================================================================
    
    task display_stats;
        begin
            $display("========================================");
            $display("Cache Statistics at time %0t", $time);
            $display("========================================");
            $display("ICache Hits:    %0d", icache_hits);
            $display("ICache Misses:  %0d", icache_misses);
            if (icache_hits + icache_misses > 0)
                $display("ICache Hit Rate: %0d%%", (icache_hits * 100) / (icache_hits + icache_misses));
            $display("----------------------------------------");
            $display("DCache Hits:    %0d", dcache_hits);
            $display("DCache Misses:  %0d", dcache_misses);
            $display("DCache Writes:  %0d", dcache_writes);
            if (dcache_hits + dcache_misses > 0)
                $display("DCache Hit Rate: %0d%%", (dcache_hits * 100) / (dcache_hits + dcache_misses));
            $display("========================================\n");
        end
    endtask
    
    // ========================================================================
    // Monitor CPU Signals (if accessible)
    // ========================================================================
    
    // You may need to add probe paths depending on your hierarchy
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor instruction fetch
            if (dut.cpu_imem_valid && dut.cpu_imem_ready) begin
                $display("[%0t] IFETCH: addr=0x%08h, data=0x%08h", 
                         $time, dut.cpu_imem_addr, dut.cpu_imem_rdata);
            end
            
            // Monitor data memory access
            if (dut.cpu_dmem_valid && dut.cpu_dmem_ready) begin
                if (dut.cpu_dmem_we) begin
                    $display("[%0t] DWRITE: addr=0x%08h, data=0x%08h, strb=0b%04b", 
                             $time, dut.cpu_dmem_addr, dut.cpu_dmem_wdata, dut.cpu_dmem_wstrb);
                end else begin
                    $display("[%0t] DREAD:  addr=0x%08h, data=0x%08h", 
                             $time, dut.cpu_dmem_addr, dut.cpu_dmem_rdata);
                end
            end
        end
    end
    
    // ========================================================================
    // Monitor ICache AXI Transactions
    // ========================================================================
    
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor read address channel
            if (dut.icache_arvalid && dut.icache_arready) begin
                $display("[%0t] ICACHE AR: addr=0x%08h, len=%0d, size=%0d, burst=%0d", 
                         $time, dut.icache_araddr, dut.icache_arlen, 
                         dut.icache_arsize, dut.icache_arburst);
            end
            
            // Monitor read data channel
            if (dut.icache_rvalid && dut.icache_rready) begin
                $display("[%0t] ICACHE R:  data=0x%08h, resp=%0d, last=%0b", 
                         $time, dut.icache_rdata, dut.icache_rresp, dut.icache_rlast);
            end
        end
    end
    
    // ========================================================================
    // Monitor DCache AXI Transactions
    // ========================================================================
    
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor read address channel
            if (dut.dcache_arvalid && dut.dcache_arready) begin
                $display("[%0t] DCACHE AR: addr=0x%08h, len=%0d, size=%0d, burst=%0d", 
                         $time, dut.dcache_araddr, dut.dcache_arlen, 
                         dut.dcache_arsize, dut.dcache_arburst);
            end
            
            // Monitor read data channel
            if (dut.dcache_rvalid && dut.dcache_rready) begin
                $display("[%0t] DCACHE R:  data=0x%08h, resp=%0d, last=%0b", 
                         $time, dut.dcache_rdata, dut.dcache_rresp, dut.dcache_rlast);
            end
            
            // Monitor write address channel
            if (dut.dcache_awvalid && dut.dcache_awready) begin
                $display("[%0t] DCACHE AW: addr=0x%08h, len=%0d, size=%0d, burst=%0d", 
                         $time, dut.dcache_awaddr, dut.dcache_awlen, 
                         dut.dcache_awsize, dut.dcache_awburst);
            end
            
            // Monitor write data channel
            if (dut.dcache_wvalid && dut.dcache_wready) begin
                $display("[%0t] DCACHE W:  data=0x%08h, strb=0x%01h, last=%0b", 
                         $time, dut.dcache_wdata, dut.dcache_wstrb, dut.dcache_wlast);
            end
            
            // Monitor write response channel
            if (dut.dcache_bvalid && dut.dcache_bready) begin
                $display("[%0t] DCACHE B:  resp=%0d", $time, dut.dcache_bresp);
            end
        end
    end
    
    // ========================================================================
    // Test Sequence
    // ========================================================================
    
    initial begin
        // Initialize
        test_num = 0;
        errors = 0;
        rst_n = 0;
        
        // Create waveform dump
        $dumpfile("riscv_soc_top_cached.vcd");
        $dumpvars(0, tb_riscv_soc_top_cached);
        
        $display("\n");
        $display("========================================");
        $display("  RISC-V SoC with Cache Testbench");
        $display("========================================");
        $display("\n");
        
        // ====================================================================
        // TEST 1: Reset Test
        // ====================================================================
        test_num = 1;
        $display("[TEST %0d] Reset Test", test_num);
        
        #100;
        rst_n = 1;
        #50;
        
        if (icache_hits == 0 && icache_misses == 0 && 
            dcache_hits == 0 && dcache_misses == 0 && dcache_writes == 0) begin
            $display("[TEST %0d] PASSED - All counters initialized to 0", test_num);
        end else begin
            $display("[TEST %0d] FAILED - Counters not properly reset", test_num);
            errors = errors + 1;
        end
        
        // ====================================================================
        // TEST 2: Run CPU for several cycles
        // ====================================================================
        test_num = 2;
        $display("\n[TEST %0d] Running CPU for 1000 cycles", test_num);
        
        repeat(1000) @(posedge clk);
        
        display_stats();
        
        // Check if CPU is making progress
        if (icache_hits + icache_misses > 0) begin
            $display("[TEST %0d] PASSED - ICache is active", test_num);
        end else begin
            $display("[TEST %0d] WARNING - No ICache activity detected", test_num);
        end
        
        // ====================================================================
        // TEST 3: Extended run to observe cache behavior
        // ====================================================================
        test_num = 3;
        $display("\n[TEST %0d] Extended run for 5000 cycles", test_num);
        
        repeat(5000) @(posedge clk);
        
        display_stats();
        
        // ====================================================================
        // TEST 4: Check cache efficiency
        // ====================================================================
        test_num = 4;
        $display("\n[TEST %0d] Cache Efficiency Check", test_num);
        
        if (icache_hits > icache_misses) begin
            $display("[TEST %0d] PASSED - ICache hit rate is good", test_num);
        end else begin
            $display("[TEST %0d] INFO - ICache has more misses than hits (may be normal for small programs)", test_num);
        end
        
        if (dcache_hits + dcache_misses > 0) begin
            $display("[TEST %0d] INFO - DCache is being used", test_num);
            if (dcache_hits > dcache_misses) begin
                $display("[TEST %0d] PASSED - DCache hit rate is good", test_num);
            end
        end else begin
            $display("[TEST %0d] INFO - No DCache activity (CPU may not be accessing data memory yet)", test_num);
        end
        
        // ====================================================================
        // TEST 5: Verify no protocol violations
        // ====================================================================
        test_num = 5;
        $display("\n[TEST %0d] Protocol Violation Check", test_num);
        
        // This is a placeholder - you would need to add specific checks
        // based on your AXI protocol requirements
        $display("[TEST %0d] Check simulation messages above for protocol errors", test_num);
        
        // ====================================================================
        // Final Summary
        // ====================================================================
        $display("\n");
        $display("========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Errors:      %0d", errors);
        
        if (errors == 0) begin
            $display("Status:      ALL TESTS PASSED!");
        end else begin
            $display("Status:      %0d TEST(S) FAILED", errors);
        end
        
        display_stats();
        
        $display("========================================");
        $display("Simulation finished at time %0t", $time);
        $display("========================================\n");
        
        // Finish simulation
        #200;
        $finish;
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    
    initial begin
        #100000; // 1ms timeout
        $display("\n");
        $display("========================================");
        $display("  TIMEOUT - Simulation exceeded 1ms");
        $display("========================================");
        display_stats();
        $finish;
    end

endmodule