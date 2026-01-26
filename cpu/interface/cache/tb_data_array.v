// ============================================================================
// Testbench: tb_icache_data_array
// ============================================================================
// Description:
//   Test data array read/write operations
// ============================================================================

`timescale 1ns/1ps
`include "icache_data_array.v"
module tb_icache_data_array;

    // Clock and Reset
    reg clk;
    reg rst_n;
    
    // Read Interface
    reg [5:0]  read_index;
    reg [1:0]  read_offset;
    wire [31:0] read_data;
    
    // Write Interface
    reg        write_enable;
    reg [5:0]  write_index;
    reg [1:0]  write_offset;
    reg [31:0] write_data;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    icache_data_array dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_index(read_index),
        .read_offset(read_offset),
        .read_data(read_data),
        .write_enable(write_enable),
        .write_index(write_index),
        .write_offset(write_offset),
        .write_data(write_data)
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
    integer i, j;
    reg [31:0] expected_data;
    
    initial begin
        $display("========================================");
        $display("Starting Data Array Testbench");
        $display("========================================");
        
        // Initialize signals
        rst_n = 0;
        read_index = 0;
        read_offset = 0;
        write_enable = 0;
        write_index = 0;
        write_offset = 0;
        write_data = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // ====================================================================
        // TEST 1: Write and read single word
        // ====================================================================
        $display("\n[TEST 1] Write and read single word");
        write_index = 6'd5;
        write_offset = 2'd2;
        write_data = 32'hDEADBEEF;
        write_enable = 1;
        #10;
        write_enable = 0;
        #10;
        
        // Read back
        read_index = 6'd5;
        read_offset = 2'd2;
        #1; // Combinational delay
        if (read_data !== 32'hDEADBEEF) begin
            $display("  [FAIL] Expected 0xDEADBEEF, got 0x%08h", read_data);
            $finish;
        end
        $display("  [PASS] Data read correctly: 0x%08h", read_data);
        
        // ====================================================================
        // TEST 2: Write complete cache line (4 words)
        // ====================================================================
        $display("\n[TEST 2] Write complete cache line");
        for (i = 0; i < 4; i = i + 1) begin
            write_index = 6'd10;
            write_offset = i;
            write_data = 32'h1000_0000 + (i << 8);
            write_enable = 1;
            #10;
            write_enable = 0;
            #10;
        end
        
        // Read back all words
        for (i = 0; i < 4; i = i + 1) begin
            read_index = 6'd10;
            read_offset = i;
            expected_data = 32'h1000_0000 + (i << 8);
            #1;
            if (read_data !== expected_data) begin
                $display("  [FAIL] Word %0d: Expected 0x%08h, got 0x%08h", 
                         i, expected_data, read_data);
                $finish;
            end
        end
        $display("  [PASS] Complete line written and read correctly");
        
        // ====================================================================
        // TEST 3: Multiple lines
        // ====================================================================
        $display("\n[TEST 3] Write multiple lines");
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                write_index = i;
                write_offset = j;
                write_data = {i[5:0], 10'h0, j[1:0], 14'h0};
                write_enable = 1;
                #10;
                write_enable = 0;
                #10;
            end
        end
        
        // Verify all lines
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                read_index = i;
                read_offset = j;
                expected_data = {i[5:0], 10'h0, j[1:0], 14'h0};
                #1;
                if (read_data !== expected_data) begin
                    $display("  [FAIL] Line %0d Word %0d: Expected 0x%08h, got 0x%08h", 
                             i, j, expected_data, read_data);
                    $finish;
                end
            end
        end
        $display("  [PASS] All %0d lines verified", 8);
        
        // ====================================================================
        // TEST 4: Overwrite test
        // ====================================================================
        $display("\n[TEST 4] Overwrite existing data");
        // Write initial value
        write_index = 6'd20;
        write_offset = 2'd1;
        write_data = 32'hAAAAAAAA;
        write_enable = 1;
        #10;
        write_enable = 0;
        #10;
        
        // Overwrite
        write_index = 6'd20;
        write_offset = 2'd1;
        write_data = 32'hBBBBBBBB;
        write_enable = 1;
        #10;
        write_enable = 0;
        #10;
        
        // Read back
        read_index = 6'd20;
        read_offset = 2'd1;
        #1;
        if (read_data !== 32'hBBBBBBBB) begin
            $display("  [FAIL] Expected 0xBBBBBBBB, got 0x%08h", read_data);
            $finish;
        end
        $display("  [PASS] Overwrite successful");
        
        // ====================================================================
        // TEST 5: Address calculation test
        // ====================================================================
        $display("\n[TEST 5] Verify address calculation");
        // Test edge cases of indexing
        for (i = 0; i < 4; i = i + 1) begin
            // Line 0
            write_index = 6'd0;
            write_offset = i;
            write_data = 32'h0000_0000 + i;
            write_enable = 1;
            #10;
            write_enable = 0;
            
            // Line 63 (last line)
            write_index = 6'd63;
            write_offset = i;
            write_data = 32'h3F00_0000 + i;
            write_enable = 1;
            #10;
            write_enable = 0;
            #10;
        end
        
        // Verify
        for (i = 0; i < 4; i = i + 1) begin
            read_index = 6'd0;
            read_offset = i;
            #1;
            if (read_data !== (32'h0000_0000 + i)) begin
                $display("  [FAIL] Line 0 Word %0d incorrect", i);
                $finish;
            end
            
            read_index = 6'd63;
            read_offset = i;
            #1;
            if (read_data !== (32'h3F00_0000 + i)) begin
                $display("  [FAIL] Line 63 Word %0d incorrect", i);
                $finish;
            end
        end
        $display("  [PASS] Address calculation correct");
        
        // ====================================================================
        // TEST 6: Simultaneous read/write different locations
        // ====================================================================
        $display("\n[TEST 6] Simultaneous read/write test");
        write_index = 6'd30;
        write_offset = 2'd3;
        write_data = 32'hCAFEBABE;
        write_enable = 1;
        read_index = 6'd10;
        read_offset = 2'd0;
        #10;
        write_enable = 0;
        #1;
        expected_data = 32'h1000_0000;
        if (read_data !== expected_data) begin
            $display("  [FAIL] Read during write failed");
            $finish;
        end
        $display("  [PASS] Simultaneous operations work correctly");
        
        // ====================================================================
        // Test Complete
        // ====================================================================
        #100;
        $display("\n========================================");
        $display("All Data Array Tests PASSED!");
        $display("========================================");
        $finish;
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_icache_data_array.vcd");
        $dumpvars(0, tb_icache_data_array);
    end
    
    // ========================================================================
    // Timeout
    // ========================================================================
    initial begin
        #100000;
        $display("\n[ERROR] Test timeout!");
        $finish;
    end

endmodule