// ============================================================================
// Testbench: tb_dmem_access_unit
// ----------------------------------------------------------------------------
// Description:
//   Testbench để kiểm tra dmem_access_unit với AXI4-Lite protocol
//
// Test Cases:
//   1. Single WRITE request (word)
//   2. Single READ request
//   3. WRITE followed by READ (verify data)
//   4. Byte-enable WRITE (partial word)
//   5. Multiple consecutive operations
//   6. Back-to-back READ/WRITE
//   7. Error response handling
//
// Author: ChiThang
// ============================================================================

`timescale 1ns / 1ps
`include "interface/dmem_access_unit.v"
module tb_dmem_access_unit;

    // ========================================================================
    // Clock and Reset
    // ========================================================================
    reg clk;
    reg rst_n;
    
    // ========================================================================
    // Data Memory Interface
    // ========================================================================
    reg [31:0]  mem_addr;
    reg [31:0]  mem_wdata;
    reg [3:0]   mem_wstrb;
    reg         mem_req;
    reg         mem_wr;
    wire [31:0] mem_rdata;
    wire        mem_ready;
    wire        mem_error;
    
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
    
    // Debug flag
    reg debug_enable;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    dmem_access_unit dut (
        .clk(clk),
        .rst_n(rst_n),
        
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_req(mem_req),
        .mem_wr(mem_wr),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .mem_error(mem_error),
        
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
    // Debug Monitor
    // ========================================================================
    always @(posedge clk) begin
        if (debug_enable) begin
            if (M_AXI_AWVALID)
                $display("  [AXI] AWVALID=1, AWADDR=0x%08h, AWREADY=%b", M_AXI_AWADDR, M_AXI_AWREADY);
            if (M_AXI_WVALID)
                $display("  [AXI] WVALID=1, WDATA=0x%08h, WSTRB=0b%04b, WREADY=%b", M_AXI_WDATA, M_AXI_WSTRB, M_AXI_WREADY);
            if (M_AXI_BVALID)
                $display("  [AXI] BVALID=1, BRESP=%b, BREADY=%b", M_AXI_BRESP, M_AXI_BREADY);
            if (M_AXI_ARVALID)
                $display("  [AXI] ARVALID=1, ARADDR=0x%08h, ARREADY=%b", M_AXI_ARADDR, M_AXI_ARREADY);
            if (M_AXI_RVALID)
                $display("  [AXI] RVALID=1, RDATA=0x%08h, RRESP=%b, RREADY=%b", M_AXI_RDATA, M_AXI_RRESP, M_AXI_RREADY);
            if (mem_ready)
                $display("  [CPU] mem_ready=1, mem_rdata=0x%08h, mem_error=%b", mem_rdata, mem_error);
        end
    end
    
    // ========================================================================
    // Clock Generation: 100MHz (10ns period)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // AXI Slave Behavioral Model (Read/Write)
    // ========================================================================
    reg [31:0] aw_addr_latch;
    reg [31:0] ar_addr_latch;
    reg        aw_received;
    
    // Write Address Channel
    initial begin
        M_AXI_AWREADY = 0;
        aw_received = 0;
        forever begin
            @(posedge clk);
            if (M_AXI_AWVALID && !M_AXI_AWREADY && !aw_received) begin
                M_AXI_AWREADY <= 1'b1;
                aw_addr_latch <= M_AXI_AWADDR;
                aw_received <= 1'b1;
                if (debug_enable) $display("  [SLAVE] Received AW, addr=0x%08h", M_AXI_AWADDR);
            end else begin
                M_AXI_AWREADY <= 1'b0;
            end
        end
    end
    
    // Write Data Channel
    initial begin
        M_AXI_WREADY = 0;
        M_AXI_BRESP  = 2'b00;
        M_AXI_BVALID = 0;
        
        forever begin
            @(posedge clk);
            if (M_AXI_WVALID && !M_AXI_WREADY && aw_received) begin
                M_AXI_WREADY <= 1'b1;
                
                if (debug_enable) $display("  [SLAVE] Received W, data=0x%08h, strb=0b%04b", M_AXI_WDATA, M_AXI_WSTRB);
                
                // Write to memory with byte strobes
                if (M_AXI_WSTRB[0]) test_memory[aw_addr_latch[9:2]][7:0]   <= M_AXI_WDATA[7:0];
                if (M_AXI_WSTRB[1]) test_memory[aw_addr_latch[9:2]][15:8]  <= M_AXI_WDATA[15:8];
                if (M_AXI_WSTRB[2]) test_memory[aw_addr_latch[9:2]][23:16] <= M_AXI_WDATA[23:16];
                if (M_AXI_WSTRB[3]) test_memory[aw_addr_latch[9:2]][31:24] <= M_AXI_WDATA[31:24];
                
                if (debug_enable) $display("  [SLAVE] Wrote to memory[%0d] = 0x%08h", aw_addr_latch[9:2], test_memory[aw_addr_latch[9:2]]);
                
                @(posedge clk);
                M_AXI_WREADY <= 1'b0;
                aw_received <= 1'b0;
                
                // Send write response
                M_AXI_BRESP  <= 2'b00; // OKAY
                M_AXI_BVALID <= 1'b1;
                
                if (debug_enable) $display("  [SLAVE] Sending B response");
                
                @(posedge clk);
                while (!M_AXI_BREADY) @(posedge clk);
                M_AXI_BVALID <= 1'b0;
            end else begin
                M_AXI_WREADY <= 1'b0;
            end
        end
    end
    
    // Read Address & Data Channel
    initial begin
        M_AXI_ARREADY = 0;
        M_AXI_RDATA   = 32'h0;
        M_AXI_RRESP   = 2'b00;
        M_AXI_RVALID  = 0;
        
        forever begin
            @(posedge clk);
            if (M_AXI_ARVALID && !M_AXI_ARREADY) begin
                M_AXI_ARREADY <= 1'b1;
                ar_addr_latch <= M_AXI_ARADDR;
                
                if (debug_enable) $display("  [SLAVE] Received AR, addr=0x%08h", M_AXI_ARADDR);
                
                @(posedge clk);
                M_AXI_ARREADY <= 1'b0;
                
                // Send read data
                M_AXI_RDATA  <= test_memory[ar_addr_latch[9:2]];
                M_AXI_RRESP  <= 2'b00; // OKAY
                M_AXI_RVALID <= 1'b1;
                
                if (debug_enable) $display("  [SLAVE] Sending R, data=0x%08h from memory[%0d]", test_memory[ar_addr_latch[9:2]], ar_addr_latch[9:2]);
                
                @(posedge clk);
                while (!M_AXI_RREADY) @(posedge clk);
                M_AXI_RVALID <= 1'b0;
            end else begin
                M_AXI_ARREADY <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // Initialize Test Memory
    // ========================================================================
    integer i;
    initial begin
        
        for (i = 0; i < 256; i = i + 1) begin
            test_memory[i] = 32'h0000_0000;
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
        debug_enable = 0;
        
        mem_addr  = 32'h0;
        mem_wdata = 32'h0;
        mem_wstrb = 4'h0;
        mem_req   = 1'b0;
        mem_wr    = 1'b0;
        
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;
        
        $display("========================================");
        $display("DMEM Access Unit Testbench");
        $display("========================================");
        
        // ====================================================================
        // Test 1: Single WRITE Request (Full Word)
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Single WRITE Request (Word)", test_num);
        debug_enable = 1;
        
        @(posedge clk);
        mem_addr  = 32'h0000_0000;
        mem_wdata = 32'hDEAD_BEEF;
        mem_wstrb = 4'b1111;
        mem_req   = 1'b1;
        mem_wr    = 1'b1;
        $display("  [TB] Sending WRITE request: addr=0x%08h, data=0x%08h", mem_addr, mem_wdata);
        
        @(posedge clk);
        mem_req   = 1'b0;
        
        wait(mem_ready);
        @(posedge clk);
        
        $display("  [TB] Memory[0] = 0x%08h", test_memory[0]);
        
        if (test_memory[0] === 32'hDEAD_BEEF && !mem_error) begin
            $display("✓ PASS: Memory[0] = 0x%08h", test_memory[0]);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Memory[0] = 0x%08h (expected 0xDEADBEEF), error=%b", test_memory[0], mem_error);
            fail_count = fail_count + 1;
        end
        
        debug_enable = 0;
        #50;
        
        // ====================================================================
        // Test 2: Single READ Request
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Single READ Request", test_num);
        
        @(posedge clk);
        mem_addr  = 32'h0000_0000;
        mem_req   = 1'b1;
        mem_wr    = 1'b0;
        
        @(posedge clk);
        mem_req   = 1'b0;
        
        wait(mem_ready);
        @(posedge clk);
        
        if (mem_rdata === 32'hDEAD_BEEF && !mem_error) begin
            $display("✓ PASS: Read data = 0x%08h", mem_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Read data = 0x%08h (expected 0xDEADBEEF)", mem_rdata);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test 3: WRITE then READ (Verify)
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] WRITE then READ", test_num);
        
        // Write
        @(posedge clk);
        mem_addr  = 32'h0000_0010;
        mem_wdata = 32'hCAFE_BABE;
        mem_wstrb = 4'b1111;
        mem_req   = 1'b1;
        mem_wr    = 1'b1;
        
        @(posedge clk);
        mem_req   = 1'b0;
        
        wait(mem_ready);
        #30;
        
        // Read back
        @(posedge clk);
        mem_addr  = 32'h0000_0010;
        mem_req   = 1'b1;
        mem_wr    = 1'b0;
        
        @(posedge clk);
        mem_req   = 1'b0;
        
        wait(mem_ready);
        @(posedge clk);
        
        if (mem_rdata === 32'hCAFE_BABE) begin
            $display("✓ PASS: Read back data = 0x%08h", mem_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Read back data = 0x%08h (expected 0xCAFEBABE)", mem_rdata);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test 4: Byte-Enable WRITE (Lower byte only)
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Byte-Enable WRITE (wstrb = 4'b0001)", test_num);
        
        // First, write full word
        @(posedge clk);
        mem_addr  = 32'h0000_0020;
        mem_wdata = 32'h1234_5678;
        mem_wstrb = 4'b1111;
        mem_req   = 1'b1;
        mem_wr    = 1'b1;
        
        @(posedge clk);
        mem_req   = 1'b0;
        wait(mem_ready);
        #30;
        
        // Then, write only lower byte
        @(posedge clk);
        mem_addr  = 32'h0000_0020;
        mem_wdata = 32'h0000_00AB;
        mem_wstrb = 4'b0001;  // Only byte 0
        mem_req   = 1'b1;
        mem_wr    = 1'b1;
        
        @(posedge clk);
        mem_req   = 1'b0;
        wait(mem_ready);
        #30;
        
        // Read back
        @(posedge clk);
        mem_addr  = 32'h0000_0020;
        mem_req   = 1'b1;
        mem_wr    = 1'b0;
        
        @(posedge clk);
        mem_req   = 1'b0;
        wait(mem_ready);
        @(posedge clk);
        
        if (mem_rdata === 32'h1234_56AB) begin
            $display("✓ PASS: Byte write successful, data = 0x%08h", mem_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("✗ FAIL: Data = 0x%08h (expected 0x123456AB)", mem_rdata);
            fail_count = fail_count + 1;
        end
        
        #50;
        
        // ====================================================================
        // Test 5: Multiple Consecutive Operations
        // ====================================================================
        test_num = test_num + 1;
        $display("\n[Test %0d] Multiple Consecutive Operations", test_num);
        
        begin: consecutive_ops
            integer i;
            integer errors;
            errors = 0;
            
            // Write sequence
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge clk);
                mem_addr  = i * 4;
                mem_wdata = 32'hA000_0000 + i;
                mem_wstrb = 4'b1111;
                mem_req   = 1'b1;
                mem_wr    = 1'b1;
                
                @(posedge clk);
                mem_req   = 1'b0;
                wait(mem_ready);
                #20;
            end
            
            // Read and verify sequence
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge clk);
                mem_addr  = i * 4;
                mem_req   = 1'b1;
                mem_wr    = 1'b0;
                
                @(posedge clk);
                mem_req   = 1'b0;
                wait(mem_ready);
                @(posedge clk);
                
                if (mem_rdata !== (32'hA000_0000 + i)) begin
                    $display("  Error at addr 0x%08h: got 0x%08h, expected 0x%08h",
                             i*4, mem_rdata, 32'hA000_0000 + i);
                    errors = errors + 1;
                end
                #20;
            end
            
            if (errors == 0) begin
                $display("✓ PASS: All operations successful");
                pass_count = pass_count + 1;
            end else begin
                $display("✗ FAIL: %0d errors in operations", errors);
                fail_count = fail_count + 1;
            end
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
        $dumpfile("tb_dmem_access_unit.vcd");
        $dumpvars(0, tb_dmem_access_unit);
    end
    
    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #100000;
        $display("\n*** TIMEOUT: Test took too long! ***");
        $finish;
    end

endmodule