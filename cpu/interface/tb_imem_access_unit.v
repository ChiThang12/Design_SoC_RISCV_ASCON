// ============================================================================
// Testbench: tb_imem_access_unit
// ----------------------------------------------------------------------------
// Description:
//   Testbench để kiểm tra imem_access_unit với AXI4-Lite protocol
//
// Test Cases:
//   1. Single READ request
//   2. Multiple consecutive READ requests
//   3. Back-to-back READ requests (stress test)
//   4. READ with AXI slave delay
//   5. Error response handling
//
// Author: ChiThang
// ============================================================================

`timescale 1ns / 1ps
`include "interface/imem_access_unit.v"
module tb_imem_access_unit;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // Instruction Fetch Interface
    // ========================================================================
    reg [31:0]  if_addr;
    reg         if_req;
    wire [31:0] if_data;
    wire        if_ready;
    wire        if_error;
    
    // ========================================================================
    // AXI4-Lite Master Interface
    // ========================================================================
    wire [31:0] M_AXI_AWADDR;
    wire [2:0]  M_AXI_AWPROT;
    wire        M_AXI_AWVALID;
    reg         M_AXI_AWREADY;
    
    wire [31:0] M_AXI_WDATA;
    wire [3:0]  M_AXI_WSTRB;
    wire        M_AXI_WVALID;
    reg         M_AXI_WREADY;
    
    reg [1:0]   M_AXI_BRESP;
    reg         M_AXI_BVALID;
    wire        M_AXI_BREADY;
    
    wire [31:0] M_AXI_ARADDR;
    wire [2:0]  M_AXI_ARPROT;
    wire        M_AXI_ARVALID;
    reg         M_AXI_ARREADY;
    
    reg [31:0]  M_AXI_RDATA;
    reg [1:0]   M_AXI_RRESP;
    reg         M_AXI_RVALID;
    wire        M_AXI_RREADY;
    
    // ========================================================================
    // Testbench Variables
    // ========================================================================
    integer test_num;
    integer pass_count;
    integer fail_count;
    
    // Simple memory model for testing
    reg [31:0] test_memory [0:255];
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    imem_access_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .if_addr(if_addr),
        .if_req(if_req),
        .if_data(if_data),
        .if_ready(if_ready),
        .if_error(if_error),
        
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );
    
    // ========================================================================
    // Clock Generation: 100MHz (10ns period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // AXI Slave Behavioral Model (Read-Only)
    // ========================================================================
    initial begin
        // Initialize AXI slave signals
        M_AXI_ARREADY = 0;
        M_AXI_RDATA   = 32'h0;
        M_AXI_RRESP   = 2'b00;
        M_AXI_RVALID  = 0;
        
        // Write channels (not used for IMEM)
        M_AXI_AWREADY = 0;
        M_AXI_WREADY  = 0;
        M_AXI_BRESP   = 2'b00;
        M_AXI_BVALID  = 0;
        
        forever begin
            @(posedge clk);
            
            // Read Address Channel
            if (M_AXI_ARVALID && !M_AXI_ARREADY) begin
                // Accept address immediately (can add delay for testing)
                M_AXI_ARREADY <= 1'b1;
                
                // Prepare read data from test memory
                @(posedge clk);
                M_AXI_ARREADY <= 1'b0;
                
                // Send read data after 1 cycle (can add more delay)
                #1; // Small delta delay
                M_AXI_RDATA  <= test_memory[M_AXI_ARADDR[9:2]]; // Word-aligned
                M_AXI_RRESP  <= 2'b00; // OKAY response
                M_AXI_RVALID <= 1'b1;
                
                @(posedge clk);
                while (!M_AXI_RREADY) @(posedge clk);
                M_AXI_RVALID <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // Initialize Test Memory
    // ========================================================================
    integer i;
    initial begin
        
        for (i = 0; i < 256; i = i + 1) begin
            test_memory[i] = 32'hDEAD0000 + i;
        end
    end
    
    // ========================================================================
    // Test Stimulus
    // ========================================================================
    initial begin
        // Initialize
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        if_addr = 32'h0;
        if_req  = 1'b0;
        
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;
        
        $display("========================================");
        $display("IMEM Access Unit Testbench");
        $display("========================================");
        
        // ====================================================================
        // Test 1: Single READ Request
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Single READ Request", test_num);
        
        @(posedge clk);
        if_addr = 32'h0000_0000;
        if_req  = 1'b1;
        
        @(posedge clk);
        if_req  = 1'b0;
        
        // Wait for ready
        wait(if_ready);
        @(posedge clk);
        
        if (if_data === test_memory[0] && !if_error) begin
            $display("✓ PASS: Data = 0x%08h (expected 0x%08h)", if_data, test_memory[0]);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Data = 0x%08h (expected 0x%08h), Error = %b", 
                     if_data, test_memory[0], if_error);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test 2: Read from Different Address
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Read from Address 0x100", test_num);
        
        @(posedge clk);
        if_addr = 32'h0000_0100;
        if_req  = 1'b1;
        
        @(posedge clk);
        if_req  = 1'b0;
        
        wait(if_ready);
        @(posedge clk);
        
        if (if_data === test_memory[32'h40] && !if_error) begin
            $display("✓ PASS: Data = 0x%08h (expected 0x%08h)", if_data, test_memory[32'h40]);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Data = 0x%08h (expected 0x%08h)", if_data, test_memory[32'h40]);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test 3: Multiple Consecutive Reads
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Multiple Consecutive Reads", test_num);
        
        begin: consecutive_reads
            integer i;
            integer errors;
            errors = 0;
            
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge clk);
                if_addr = i * 4;
                if_req  = 1'b1;
                
                @(posedge clk);
                if_req  = 1'b0;
                
                wait(if_ready);
                @(posedge clk);
                
                if (if_data !== test_memory[i]) begin
                    $display("  Error at addr 0x%08h: got 0x%08h, expected 0x%08h", 
                             i*4, if_data, test_memory[i]);
                    errors = errors + 1;
                end
                
                #20;
            end
            
            if (errors == 0) begin
                $display("✓ PASS: All 5 reads successful");
                pass_count = pass_count + 1;
            end else begin
                $display("✗ FAIL: %0d errors in consecutive reads", errors);
                fail_count = fail_count + 1;
            end
        end
        
        #50;
        
        // ====================================================================
        // Test 4: Back-to-back Requests (without waiting)
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Back-to-back Requests", test_num);
        
        @(posedge clk);
        if_addr = 32'h0000_0010;
        if_req  = 1'b1;
        
        @(posedge clk);
        if_addr = 32'h0000_0014;  // New request while previous is pending
        if_req  = 1'b1;
        
        @(posedge clk);
        if_req  = 1'b0;
        
        wait(if_ready);
        @(posedge clk);
        
        if (if_data === test_memory[4]) begin
            $display("✓ PASS: First request completed with data 0x%08h", if_data);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: First request got 0x%08h, expected 0x%08h", 
                     if_data, test_memory[4]);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test 5: Request during reset
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Request during Reset", test_num);
        
        rst_n = 0;
        #10;
        
        @(posedge clk);
        if_addr = 32'h0000_0020;
        if_req  = 1'b1;
        
        @(posedge clk);
        if_req  = 1'b0;
        
        #30;
        rst_n = 1;
        #50;
        
        if (!if_ready) begin
            $display("✓ PASS: No spurious ready during reset");
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Unexpected ready signal during reset");
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test Summary
        // ====================================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED! ***");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
        end
        $display("========================================\n");
        
        #100;
        $finish;
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_imem_access_unit.vcd");
        $dumpvars(0, tb_imem_access_unit);
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #50000;
        $display("\n*** TIMEOUT: Test took too long! ***");
        $finish;
    end

endmodule