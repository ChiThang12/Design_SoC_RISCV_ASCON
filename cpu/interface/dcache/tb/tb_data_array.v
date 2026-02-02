// ============================================================================
// Testbench: tb_dcache_data_array
// ============================================================================
// Description:
//   Test data array read/write with byte-enable support
// ============================================================================

`timescale 1ns/1ps
`include "dcache_defines.vh"
`include "dcache_data_array.v"

module tb_dcache_data_array;

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
    reg [3:0]  write_strb;
    
    // DUT Instance
    dcache_data_array dut (
        .clk(clk),
        .rst_n(rst_n),
        .read_index(read_index),
        .read_offset(read_offset),
        .read_data(read_data),
        .write_enable(write_enable),
        .write_index(write_index),
        .write_offset(write_offset),
        .write_data(write_data),
        .write_strb(write_strb)
    );
    
    // Clock Generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test Sequence
    initial begin
        $display("========================================");
        $display("DCache Data Array Testbench");
        $display("========================================");
        
        // Initialize
        rst_n = 0;
        read_index = 0;
        read_offset = 0;
        write_enable = 0;
        write_index = 0;
        write_offset = 0;
        write_data = 0;
        write_strb = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // Test 1: Full word write
        $display("\nTest 1: Full word write");
        write_enable = 1;
        write_index = 6'h00;
        write_offset = 2'b00;
        write_data = 32'hDEADBEEF;
        write_strb = 4'b1111;
        #10;
        write_enable = 0;
        #10;
        
        // Read back
        read_index = 6'h00;
        read_offset = 2'b00;
        #10;
        if (read_data == 32'hDEADBEEF)
            $display("  PASS: Full word write/read");
        else
            $display("  FAIL: Expected DEADBEEF, got %h", read_data);
        
        // Test 2: Byte write (byte 0)
        $display("\nTest 2: Byte write (byte 0)");
        write_enable = 1;
        write_index = 6'h01;
        write_offset = 2'b00;
        write_data = 32'h12345678;
        write_strb = 4'b0001;  // Only byte 0
        #10;
        write_enable = 0;
        #10;
        
        read_index = 6'h01;
        read_offset = 2'b00;
        #10;
        if (read_data[7:0] == 8'h78)
            $display("  PASS: Byte 0 write");
        else
            $display("  FAIL: Byte 0 incorrect");
        
        // Test 3: Halfword write (bytes 0-1)
        $display("\nTest 3: Halfword write");
        write_enable = 1;
        write_index = 6'h02;
        write_offset = 2'b00;
        write_data = 32'h12345678;
        write_strb = 4'b0011;  // Bytes 0-1
        #10;
        write_enable = 0;
        #10;
        
        read_index = 6'h02;
        read_offset = 2'b00;
        #10;
        if (read_data[15:0] == 16'h5678)
            $display("  PASS: Halfword write");
        else
            $display("  FAIL: Halfword incorrect: %h", read_data[15:0]);
        
        // Test 4: Partial write (bytes 2-3)
        $display("\nTest 4: Upper halfword write");
        write_enable = 1;
        write_index = 6'h03;
        write_offset = 2'b00;
        write_data = 32'hAABBCCDD;
        write_strb = 4'b1100;  // Bytes 2-3
        #10;
        write_enable = 0;
        #10;
        
        read_index = 6'h03;
        read_offset = 2'b00;
        #10;
        if (read_data[31:16] == 16'hAABB)
            $display("  PASS: Upper halfword write");
        else
            $display("  FAIL: Upper halfword incorrect: %h", read_data[31:16]);
        
        // Test 5: Write to different offsets
        $display("\nTest 5: Write to different offsets");
        write_enable = 1;
        write_strb = 4'b1111;
        
        write_index = 6'h04;
        write_offset = 2'b00;
        write_data = 32'h11111111;
        #10;
        
        write_offset = 2'b01;
        write_data = 32'h22222222;
        #10;
        
        write_offset = 2'b10;
        write_data = 32'h33333333;
        #10;
        
        write_offset = 2'b11;
        write_data = 32'h44444444;
        #10;
        
        write_enable = 0;
        #10;
        
        // Read back all offsets
        read_index = 6'h04;
        read_offset = 2'b00;
        #10;
        if (read_data == 32'h11111111)
            $display("  PASS: Offset 0");
        else
            $display("  FAIL: Offset 0 = %h", read_data);
        
        read_offset = 2'b01;
        #10;
        if (read_data == 32'h22222222)
            $display("  PASS: Offset 1");
        else
            $display("  FAIL: Offset 1 = %h", read_data);
        
        read_offset = 2'b10;
        #10;
        if (read_data == 32'h33333333)
            $display("  PASS: Offset 2");
        else
            $display("  FAIL: Offset 2 = %h", read_data);
        
        read_offset = 2'b11;
        #10;
        if (read_data == 32'h44444444)
            $display("  PASS: Offset 3");
        else
            $display("  FAIL: Offset 3 = %h", read_data);
        
        // Test 6: Multiple cache lines
        $display("\nTest 6: Multiple cache lines");
        write_enable = 1;
        write_strb = 4'b1111;
        write_offset = 2'b00;
        
        write_index = 6'h00;
        write_data = 32'hAAAAAAAA;
        #10;
        
        write_index = 6'h01;
        write_data = 32'hBBBBBBBB;
        #10;
        
        write_index = 6'h3F;  // Last line
        write_data = 32'hFFFFFFFF;
        #10;
        
        write_enable = 0;
        #10;
        
        // Verify
        read_offset = 2'b00;
        
        read_index = 6'h00;
        #10;
        if (read_data == 32'hAAAAAAAA)
            $display("  PASS: Line 0");
        else
            $display("  FAIL: Line 0 = %h", read_data);
        
        read_index = 6'h01;
        #10;
        if (read_data == 32'hBBBBBBBB)
            $display("  PASS: Line 1");
        else
            $display("  FAIL: Line 1 = %h", read_data);
        
        read_index = 6'h3F;
        #10;
        if (read_data == 32'hFFFFFFFF)
            $display("  PASS: Line 63");
        else
            $display("  FAIL: Line 63 = %h", read_data);
        
        #100;
        $display("\n========================================");
        $display("Test Complete");
        $display("========================================");
        $finish;
    end
    
    // Monitor
    initial begin
        $monitor("Time=%0t wr=%b wr_idx=%h wr_off=%b wr_data=%h wr_strb=%b | rd_idx=%h rd_off=%b rd_data=%h",
                 $time, write_enable, write_index, write_offset, write_data, write_strb,
                 read_index, read_offset, read_data);
    end

endmodule