// ============================================================================
// ALU_tb.v - Testbench cho RISC-V ALU
// ============================================================================

`timescale 1ns/1ps
`include "alu.v"
module tb_alu;

    // Tín hiệu kết nối với ALU
    reg [31:0] in1, in2;
    reg [3:0] alu_control;
    wire [31:0] alu_result;
    wire zero_flag, less_than, less_than_u;
    
    // Biến để kiểm tra kết quả
    reg [31:0] expected;
    integer passed, failed;
    
    // ALU Control Code
    localparam [3:0]
        ALU_ADD   = 4'b0000,
        ALU_SUB   = 4'b0001,
        ALU_AND   = 4'b0010,
        ALU_OR    = 4'b0011,
        ALU_XOR   = 4'b0100,
        ALU_SLL   = 4'b0101,
        ALU_SRL   = 4'b0110,
        ALU_SRA   = 4'b0111,
        ALU_SLT   = 4'b1000,
        ALU_SLTU  = 4'b1001,
        ALU_MUL   = 4'b1010,
        ALU_MULH  = 4'b1011,
        ALU_DIV   = 4'b1100,
        ALU_DIVU  = 4'b1101,
        ALU_REM   = 4'b1110,
        ALU_REMU  = 4'b1111;
    
    // Khởi tạo DUT
    alu uut (
        .in1(in1),
        .in2(in2),
        .alu_control(alu_control),
        .alu_result(alu_result),
        .zero_flag(zero_flag),
        .less_than(less_than),
        .less_than_u(less_than_u)
    );
    
    // Task để kiểm tra kết quả
    task check_result;
        input [31:0] exp;
        input [200*8:1] operation_name;
        begin
            #1;
            if (alu_result === exp) begin
                $display("  ✓ PASS: %0s | in1=0x%h, in2=0x%h → result=0x%h", 
                         operation_name, in1, in2, alu_result);
                passed = passed + 1;
            end
            else begin
                $display("  ✗ FAIL: %0s | in1=0x%h, in2=0x%h → expected=0x%h, got=0x%h", 
                         operation_name, in1, in2, exp, alu_result);
                failed = failed + 1;
            end
        end
    endtask
    
    // Test sequence
    initial begin
        // Khởi tạo
        $dumpfile("tb_alu.vcd");
        $dumpvars(0, tb_alu);
        
        passed = 0;
        failed = 0;
        in1 = 0;
        in2 = 0;
        alu_control = 0;
        
        $display("\n============================================");
        $display("  RISC-V ALU (RV32IM) Testbench");
        $display("============================================\n");
        
        // ================================================================
        // TEST 1: Phép toán số học (ADD, SUB)
        // ================================================================
        $display("[TEST 1] Phép toán số học");
        
        // ADD: 10 + 20 = 30
        in1 = 32'd10; in2 = 32'd20; alu_control = ALU_ADD;
        check_result(32'd30, "ADD: 10 + 20");
        
        // ADD: overflow test
        in1 = 32'hFFFFFFFF; in2 = 32'd1; alu_control = ALU_ADD;
        check_result(32'd0, "ADD: 0xFFFFFFFF + 1 (overflow)");
        
        // SUB: 50 - 20 = 30
        in1 = 32'd50; in2 = 32'd20; alu_control = ALU_SUB;
        check_result(32'd30, "SUB: 50 - 20");
        
        // SUB: underflow test
        in1 = 32'd0; in2 = 32'd1; alu_control = ALU_SUB;
        check_result(32'hFFFFFFFF, "SUB: 0 - 1 (underflow)");
        
        // ================================================================
        // TEST 2: Phép toán logic (AND, OR, XOR)
        // ================================================================
        $display("\n[TEST 2] Phép toán logic");
        
        // AND
        in1 = 32'hF0F0F0F0; in2 = 32'hFFFF0000; alu_control = ALU_AND;
        check_result(32'hF0F00000, "AND: 0xF0F0F0F0 & 0xFFFF0000");
        
        // OR
        in1 = 32'hF0F0F0F0; in2 = 32'h0F0F0F0F; alu_control = ALU_OR;
        check_result(32'hFFFFFFFF, "OR: 0xF0F0F0F0 | 0x0F0F0F0F");
        
        // XOR
        in1 = 32'hAAAAAAAA; in2 = 32'h55555555; alu_control = ALU_XOR;
        check_result(32'hFFFFFFFF, "XOR: 0xAAAAAAAA ^ 0x55555555");
        
        // XOR (same values = 0)
        in1 = 32'h12345678; in2 = 32'h12345678; alu_control = ALU_XOR;
        check_result(32'd0, "XOR: 0x12345678 ^ 0x12345678");
        
        // ================================================================
        // TEST 3: Phép dịch bit (SLL, SRL, SRA)
        // ================================================================
        $display("\n[TEST 3] Phép dịch bit");
        
        // SLL: shift left logical
        in1 = 32'h00000001; in2 = 32'd4; alu_control = ALU_SLL;
        check_result(32'h00000010, "SLL: 0x1 << 4");
        
        in1 = 32'hF0000000; in2 = 32'd1; alu_control = ALU_SLL;
        check_result(32'hE0000000, "SLL: 0xF0000000 << 1");
        
        // SRL: shift right logical
        in1 = 32'h80000000; in2 = 32'd1; alu_control = ALU_SRL;
        check_result(32'h40000000, "SRL: 0x80000000 >> 1 (logical)");
        
        in1 = 32'hF0000000; in2 = 32'd4; alu_control = ALU_SRL;
        check_result(32'h0F000000, "SRL: 0xF0000000 >> 4 (logical)");
        
        // SRA: shift right arithmetic (với dấu)
        in1 = 32'h80000000; in2 = 32'd1; alu_control = ALU_SRA;
        check_result(32'hC0000000, "SRA: 0x80000000 >>> 1 (arithmetic)");
        
        in1 = 32'hF0000000; in2 = 32'd4; alu_control = ALU_SRA;
        check_result(32'hFF000000, "SRA: 0xF0000000 >>> 4 (arithmetic)");
        
        // ================================================================
        // TEST 4: Phép so sánh (SLT, SLTU)
        // ================================================================
        $display("\n[TEST 4] Phép so sánh");
        
        // SLT: signed comparison
        in1 = 32'd10; in2 = 32'd20; alu_control = ALU_SLT;
        check_result(32'd1, "SLT: 10 < 20 (signed)");
        
        in1 = 32'd20; in2 = 32'd10; alu_control = ALU_SLT;
        check_result(32'd0, "SLT: 20 < 10 (signed)");
        
        in1 = 32'hFFFFFFFF; in2 = 32'd1; alu_control = ALU_SLT;  // -1 < 1
        check_result(32'd1, "SLT: -1 < 1 (signed)");
        
        // SLTU: unsigned comparison
        in1 = 32'd10; in2 = 32'd20; alu_control = ALU_SLTU;
        check_result(32'd1, "SLTU: 10 < 20 (unsigned)");
        
        in1 = 32'hFFFFFFFF; in2 = 32'd1; alu_control = ALU_SLTU;
        check_result(32'd0, "SLTU: 0xFFFFFFFF < 1 (unsigned)");
        
        // ================================================================
        // TEST 5: Phép nhân (MUL, MULH)
        // ================================================================
        $display("\n[TEST 5] Phép nhân (RV32M)");
        
        // MUL: 32-bit thấp
        in1 = 32'd100; in2 = 32'd200; alu_control = ALU_MUL;
        check_result(32'd20000, "MUL: 100 * 200");
        
        in1 = 32'h10000; in2 = 32'h10000; alu_control = ALU_MUL;
        check_result(32'h00000000, "MUL: 0x10000 * 0x10000 (lower 32-bit)");
        
        // MULH: 32-bit cao
        in1 = 32'h10000; in2 = 32'h10000; alu_control = ALU_MULH;
        check_result(32'h00000001, "MULH: 0x10000 * 0x10000 (upper 32-bit)");
        
        in1 = 32'hFFFFFFFF; in2 = 32'hFFFFFFFF; alu_control = ALU_MULH;  // (-1) * (-1) = 1
        check_result(32'd0, "MULH: (-1) * (-1) signed");
        
        // ================================================================
        // TEST 6: Phép chia signed (DIV, REM)
        // ================================================================
        $display("\n[TEST 6] Phép chia signed (RV32M)");
        
        // DIV: chia có dấu
        in1 = 32'd100; in2 = 32'd10; alu_control = ALU_DIV;
        check_result(32'd10, "DIV: 100 / 10");
        
        in1 = 32'd100; in2 = 32'd3; alu_control = ALU_DIV;
        check_result(32'd33, "DIV: 100 / 3");
        
        // DIV: chia cho 0
        in1 = 32'd100; in2 = 32'd0; alu_control = ALU_DIV;
        check_result(32'hFFFFFFFF, "DIV: 100 / 0 (returns -1)");
        
        // REM: chia lấy dư có dấu
        in1 = 32'd100; in2 = 32'd3; alu_control = ALU_REM;
        check_result(32'd1, "REM: 100 % 3");
        
        in1 = 32'd100; in2 = 32'd0; alu_control = ALU_REM;
        check_result(32'd100, "REM: 100 % 0 (returns dividend)");
        
        // ================================================================
        // TEST 7: Phép chia unsigned (DIVU, REMU)
        // ================================================================
        $display("\n[TEST 7] Phép chia unsigned (RV32M)");
        
        // DIVU: chia không dấu
        in1 = 32'd100; in2 = 32'd10; alu_control = ALU_DIVU;
        check_result(32'd10, "DIVU: 100 / 10");
        
        in1 = 32'hFFFFFFFF; in2 = 32'd2; alu_control = ALU_DIVU;
        check_result(32'h7FFFFFFF, "DIVU: 0xFFFFFFFF / 2");
        
        // DIVU: chia cho 0
        in1 = 32'd100; in2 = 32'd0; alu_control = ALU_DIVU;
        check_result(32'hFFFFFFFF, "DIVU: 100 / 0 (returns 0xFFFFFFFF)");
        
        // REMU: chia lấy dư không dấu
        in1 = 32'd100; in2 = 32'd3; alu_control = ALU_REMU;
        check_result(32'd1, "REMU: 100 % 3");
        
        // ================================================================
        // TEST 8: Kiểm tra flags
        // ================================================================
        $display("\n[TEST 8] Kiểm tra flags");
        
        // Zero flag
        in1 = 32'd10; in2 = 32'd10; alu_control = ALU_SUB;
        #1;
        if (zero_flag && alu_result == 32'd0) begin
            $display("  ✓ PASS: zero_flag = 1 when result = 0");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: zero_flag test");
            failed = failed + 1;
        end
        
        // Less than (signed)
        in1 = 32'd10; in2 = 32'd20; alu_control = ALU_ADD;
        #1;
        if (less_than == 1) begin
            $display("  ✓ PASS: less_than = 1 for 10 < 20 (signed)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: less_than test");
            failed = failed + 1;
        end
        
        // Less than unsigned
        in1 = 32'd10; in2 = 32'd20; alu_control = ALU_ADD;
        #1;
        if (less_than_u == 1) begin
            $display("  ✓ PASS: less_than_u = 1 for 10 < 20 (unsigned)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: less_than_u test");
            failed = failed + 1;
        end
        
        // ================================================================
        // Kết quả tổng kết
        // ================================================================
        #10;
        $display("\n============================================");
        $display("  Testbench Summary");
        $display("============================================");
        $display("  Total tests: %0d", passed + failed);
        $display("  ✓ Passed: %0d", passed);
        $display("  ✗ Failed: %0d", failed);
        
        if (failed == 0) begin
            $display("\n  🎉 ALL TESTS PASSED! 🎉");
        end else begin
            $display("\n  ⚠️  SOME TESTS FAILED");
        end
        $display("============================================\n");
        
        $finish;
    end

endmodule