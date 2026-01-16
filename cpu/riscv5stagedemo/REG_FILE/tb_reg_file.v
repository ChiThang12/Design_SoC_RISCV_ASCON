// ============================================================================
// REG_FILE_tb.v - Testbench cho RISC-V Register File
// ============================================================================

`timescale 1ns/1ps
`include "reg_file.v"
module tb_reg_file;

    // Tín hiệu clock và reset
    reg clock;
    reg reset;
    
    // Tín hiệu đọc
    reg [4:0] read_reg_num1;
    reg [4:0] read_reg_num2;
    wire [31:0] read_data1;
    wire [31:0] read_data2;
    
    // Tín hiệu ghi
    reg regwrite;
    reg [4:0] write_reg;
    reg [31:0] write_data;
    
    // Khởi tạo DUT (Device Under Test)
    reg_file uut (
        .clock(clock),
        .reset(reset),
        .read_reg_num1(read_reg_num1),
        .read_reg_num2(read_reg_num2),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .regwrite(regwrite),
        .write_reg(write_reg),
        .write_data(write_data)
    );
    
    // Tạo clock 10ns (100MHz)
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end
    
    // Test sequence
    initial begin
        // Khởi tạo file dump cho GTKWave
        $dumpfile("tb_reg_file.vcd");
        $dumpvars(0, tb_reg_file);
        
        // Hiển thị header
        $display("============================================");
        $display("  RISC-V Register File Testbench");
        $display("============================================");
        $display("Time\t| Oper\t| Reg\t| Data\t\t| rd1\t\t| rd2");
        $display("--------------------------------------------");
        
        // Khởi tạo tín hiệu
        reset = 1;
        regwrite = 0;
        write_reg = 0;
        write_data = 0;
        read_reg_num1 = 0;
        read_reg_num2 = 0;
        
        // Reset hệ thống
        #20;
        reset = 0;
        #10;
        
        // ================================================================
        // TEST 1: Kiểm tra x0 luôn = 0
        // ================================================================
        $display("\n[TEST 1] Kiểm tra x0 luôn = 0");
        @(posedge clock);
        regwrite = 1;
        write_reg = 5'd0;  // x0
        write_data = 32'hDEADBEEF;
        #1;
        $display("%0t\t| WRITE\t| x%-2d\t| 0x%h\t| -\t\t| -", $time, write_reg, write_data);
        
        @(posedge clock);
        regwrite = 0;
        read_reg_num1 = 5'd0;
        #1;
        $display("%0t\t| READ\t| x%-2d\t| -\t\t| 0x%h\t| -", $time, read_reg_num1, read_data1);
        
        if (read_data1 == 32'h00000000)
            $display("✓ PASS: x0 = 0");
        else
            $display("✗ FAIL: x0 ≠ 0 (got 0x%h)", read_data1);
        
        // ================================================================
        // TEST 2: Ghi và đọc các thanh ghi thông thường
        // ================================================================
        $display("\n[TEST 2] Ghi và đọc thanh ghi x1-x31");
        
        // Ghi vào x1
        @(posedge clock);
        regwrite = 1;
        write_reg = 5'd1;
        write_data = 32'h12345678;
        #1;
        $display("%0t\t| WRITE\t| x%-2d\t| 0x%h\t| -\t\t| -", $time, write_reg, write_data);
        
        // Ghi vào x2
        @(posedge clock);
        write_reg = 5'd2;
        write_data = 32'hABCDEF00;
        #1;
        $display("%0t\t| WRITE\t| x%-2d\t| 0x%h\t| -\t\t| -", $time, write_reg, write_data);
        
        // Ghi vào x31
        @(posedge clock);
        write_reg = 5'd31;
        write_data = 32'hFFFFFFFF;
        #1;
        $display("%0t\t| WRITE\t| x%-2d\t| 0x%h\t| -\t\t| -", $time, write_reg, write_data);
        
        // Đọc x1 và x2
        @(posedge clock);
        regwrite = 0;
        read_reg_num1 = 5'd1;
        read_reg_num2 = 5'd2;
        #1;
        $display("%0t\t| READ\t| x%d,x%d\t| -\t\t| 0x%h\t| 0x%h", 
                 $time, read_reg_num1, read_reg_num2, read_data1, read_data2);
        
        if (read_data1 == 32'h12345678 && read_data2 == 32'hABCDEF00)
            $display("✓ PASS: Đọc x1, x2 đúng");
        else
            $display("✗ FAIL: Đọc sai (x1=0x%h, x2=0x%h)", read_data1, read_data2);
        
        // Đọc x31
        @(posedge clock);
        read_reg_num1 = 5'd31;
        read_reg_num2 = 5'd0;
        #1;
        $display("%0t\t| READ\t| x%d,x%d\t| -\t\t| 0x%h\t| 0x%h", 
                 $time, read_reg_num1, read_reg_num2, read_data1, read_data2);
        
        if (read_data1 == 32'hFFFFFFFF && read_data2 == 32'h00000000)
            $display("✓ PASS: Đọc x31, x0 đúng");
        else
            $display("✗ FAIL: Đọc sai (x31=0x%h, x0=0x%h)", read_data1, read_data2);
        
        // ================================================================
        // TEST 3: Kiểm tra regwrite enable
        // ================================================================
        $display("\n[TEST 3] Kiểm tra regwrite enable");
        
        // Ghi vào x3 với regwrite = 1
        @(posedge clock);
        regwrite = 1;
        write_reg = 5'd3;
        write_data = 32'h11111111;
        #1;
        $display("%0t\t| WRITE\t| x%-2d\t| 0x%h\t| (regwrite=1)", $time, write_reg, write_data);
        
        // Thử ghi vào x3 với regwrite = 0 (không nên ghi)
        @(posedge clock);
        regwrite = 0;
        write_data = 32'h22222222;
        #1;
        $display("%0t\t| WRITE\t| x%-2d\t| 0x%h\t| (regwrite=0)", $time, write_reg, write_data);
        
        // Đọc x3
        @(posedge clock);
        read_reg_num1 = 5'd3;
        #1;
        $display("%0t\t| READ\t| x%-2d\t| -\t\t| 0x%h\t| -", $time, read_reg_num1, read_data1);
        
        if (read_data1 == 32'h11111111)
            $display("✓ PASS: regwrite=0 không ghi được");
        else
            $display("✗ FAIL: regwrite=0 vẫn ghi (got 0x%h)", read_data1);
        
        // ================================================================
        // TEST 4: Đọc bất đồng bộ (asynchronous read)
        // ================================================================
        $display("\n[TEST 4] Kiểm tra đọc bất đồng bộ");
        
        // Ghi vào x10
        @(posedge clock);
        regwrite = 1;
        write_reg = 5'd10;
        write_data = 32'hAAAAAAAA;
        
        // Đọc ngay lập tức (không đợi clock)
        #1;
        read_reg_num1 = 5'd10;
        #1;
        $display("%0t\t| READ\t| x%-2d\t| -\t\t| 0x%h\t| (async)", $time, read_reg_num1, read_data1);
        
        // ================================================================
        // TEST 5: Ghi đồng thời và đọc
        // ================================================================
        $display("\n[TEST 5] Ghi và đọc đồng thời");
        
        @(posedge clock);
        regwrite = 1;
        write_reg = 5'd15;
        write_data = 32'h55555555;
        read_reg_num1 = 5'd15;
        read_reg_num2 = 5'd10;
        #1;
        $display("%0t\t| W+R\t| x%d\t| 0x%h\t| 0x%h\t| 0x%h", 
                 $time, write_reg, write_data, read_data1, read_data2);
        
        // Đọc lại sau khi ghi
        @(posedge clock);
        regwrite = 0;
        #1;
        $display("%0t\t| READ\t| x%d\t| -\t\t| 0x%h\t| 0x%h", 
                 $time, read_reg_num1, read_data1, read_data2);
        
        // ================================================================
        // Kết thúc simulation
        // ================================================================
        #20;
        $display("\n============================================");
        $display("  Testbench hoàn thành!");
        $display("============================================\n");
        $finish;
    end
    
    // Timeout protection
    initial begin
        #1000;
        $display("\n✗ TIMEOUT: Simulation quá lâu!");
        $finish;
    end

endmodule