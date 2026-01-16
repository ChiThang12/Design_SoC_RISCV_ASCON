// ============================================================================
// IMM_GEN_tb.v - Testbench cho RISC-V Immediate Generator
// ============================================================================

`timescale 1ns/1ps
`include "imm_gen.v"
module tb_imm_gen;

    // Tín hiệu
    reg [31:0] instr;
    wire [31:0] imm;
    
    // Biến đếm test
    integer passed, failed;
    
    // Opcode định nghĩa
    localparam [6:0]
        OP_R_TYPE   = 7'b0110011,
        OP_I_TYPE   = 7'b0010011,
        OP_LOAD     = 7'b0000011,
        OP_JALR     = 7'b1100111,
        OP_STORE    = 7'b0100011,
        OP_BRANCH   = 7'b1100011,
        OP_LUI      = 7'b0110111,
        OP_AUIPC    = 7'b0010111,
        OP_JAL      = 7'b1101111;
    
    // Khởi tạo DUT
    imm_gen uut (
        .instr(instr),
        .imm(imm)
    );
    
    // Task để kiểm tra kết quả
    task check_immediate;
        input [31:0] expected;
        input [200*8:1] test_name;
        begin
            #1;
            if (imm === expected) begin
                $display("  ✓ PASS: %0s", test_name);
                $display("      Instruction: 0x%h", instr);
                $display("      Immediate:   0x%h (dec: %0d)", imm, $signed(imm));
                passed = passed + 1;
            end
            else begin
                $display("  ✗ FAIL: %0s", test_name);
                $display("      Instruction: 0x%h", instr);
                $display("      Expected:    0x%h (dec: %0d)", expected, $signed(expected));
                $display("      Got:         0x%h (dec: %0d)", imm, $signed(imm));
                failed = failed + 1;
            end
            $display("");
        end
    endtask
    
    // Test sequence
    initial begin
        $dumpfile("tb_imm_gen.vcd");
        $dumpvars(0, tb_imm_gen);
        
        passed = 0;
        failed = 0;
        instr = 0;
        
        $display("\n============================================");
        $display("  RISC-V Immediate Generator Testbench");
        $display("============================================\n");
        
        // ================================================================
        // TEST 1: I-Type Instructions (12-bit immediate)
        // ================================================================
        $display("[TEST 1] I-Type Instructions (12-bit immediate)\n");
        
        // ADDI x5, x0, 100
        // Format: imm[11:0] | rs1 | 000 | rd | 0010011
        // imm = 100 = 0x064
        instr = {12'd100, 5'd0, 3'b000, 5'd5, OP_I_TYPE};
        check_immediate(32'd100, "ADDI with positive immediate (100)");
        
        // ADDI x5, x0, -50
        // imm = -50 = 0xFCE (12-bit two's complement)
        instr = {12'hFCE, 5'd0, 3'b000, 5'd5, OP_I_TYPE};
        check_immediate(32'hFFFFFFCE, "ADDI with negative immediate (-50)");
        
        // ADDI x5, x0, 2047 (max positive)
        instr = {12'd2047, 5'd0, 3'b000, 5'd5, OP_I_TYPE};
        check_immediate(32'd2047, "ADDI with max positive (2047)");
        
        // ADDI x5, x0, -2048 (min negative)
        instr = {12'h800, 5'd0, 3'b000, 5'd5, OP_I_TYPE};
        check_immediate(32'hFFFFF800, "ADDI with min negative (-2048)");
        
        // LW x10, 20(x2)
        // imm = 20
        instr = {12'd20, 5'd2, 3'b010, 5'd10, OP_LOAD};
        check_immediate(32'd20, "LW with offset 20");
        
        // JALR x1, x5, -4
        instr = {12'hFFC, 5'd5, 3'b000, 5'd1, OP_JALR};
        check_immediate(32'hFFFFFFFC, "JALR with offset -4");
        
        // ================================================================
        // TEST 2: S-Type Instructions (12-bit immediate)
        // ================================================================
        $display("[TEST 2] S-Type Instructions (12-bit immediate)\n");
        
        // SW x10, 40(x2)
        // Format: imm[11:5] | rs2 | rs1 | 010 | imm[4:0] | 0100011
        // imm = 40 = 0x028
        instr = {7'b0000001, 5'd10, 5'd2, 3'b010, 5'b01000, OP_STORE};
        check_immediate(32'd40, "SW with offset 40");
        
        // SW x15, -8(x3)
        // imm = -8 = 0xFF8 (12-bit)
        instr = {7'b1111111, 5'd15, 5'd3, 3'b010, 5'b11000, OP_STORE};
        check_immediate(32'hFFFFFFF8, "SW with negative offset -8");
        
        // SH x7, 100(x4)
        // imm = 100 = 0x064
        instr = {7'b0000011, 5'd7, 5'd4, 3'b001, 5'b00100, OP_STORE};
        check_immediate(32'd100, "SH with offset 100");
        
        // SB x8, -1(x5)
        // imm = -1 = 0xFFF (12-bit)
        instr = {7'b1111111, 5'd8, 5'd5, 3'b000, 5'b11111, OP_STORE};
        check_immediate(32'hFFFFFFFF, "SB with offset -1");
        
        // ================================================================
        // TEST 3: B-Type Instructions (13-bit immediate, always even)
        // ================================================================
        $display("[TEST 3] B-Type Instructions (13-bit immediate)\n");
        
        // BEQ x5, x6, 8
        // Format: imm[12|10:5] | rs2 | rs1 | 000 | imm[4:1|11] | 1100011
        // imm = 8 = 0b0000_0000_1000
        // imm[12] = 0, imm[11] = 0, imm[10:5] = 000000, imm[4:1] = 0100
        instr = {1'b0, 6'b000000, 5'd6, 5'd5, 3'b000, 4'b0100, 1'b0, OP_BRANCH};
        check_immediate(32'd8, "BEQ with offset 8");
        
        // BNE x7, x8, -4
        // imm = -4 = 0b1_1111_1111_1100 (13-bit)
        instr = {1'b1, 6'b111111, 5'd8, 5'd7, 3'b001, 4'b1110, 1'b1, OP_BRANCH};
        check_immediate(32'hFFFFFFFC, "BNE with offset -4");
        
        // BLT x1, x2, 16
        // imm = 16 = 0x010
        instr = {1'b0, 6'b000000, 5'd2, 5'd1, 3'b100, 4'b1000, 1'b0, OP_BRANCH};
        check_immediate(32'd16, "BLT with offset 16");
        
        // BGE x3, x4, -12
        // -12 in decimal = ...11110100 in binary
        // As 13-bit immediate (with bit 0 implicit 0): 1_111111_1101_0
        // Wait, let me recalculate: -12 / 2 = -6 (since bit 0 is implicit)
        // But actually: -12 = 0b1111_1111_1111_1111_1111_1111_1111_0100 (32-bit)
        // Take bits [12:1] for B-type (bit 0 is implicit 0):
        // Bits [12:1] of -12 = bits [12:1] of 0xFFFFFFF4
        // 0xFFFFFFF4 >> 1 = 0xFFFFFFFA, take low 12 bits = 0xFFA = 1111_1111_1010
        // So: imm[12:1] = 1_1111_1111_010
        // imm[12]=1, imm[11]=1, imm[10:5]=111111, imm[4:1]=1010
        // B-type format: imm[12] imm[10:5] rs2 rs1 funct3 imm[4:1] imm[11] opcode
        instr = {1'b1, 6'b111111, 5'd4, 5'd3, 3'b101, 4'b1010, 1'b1, OP_BRANCH};
        check_immediate(32'hFFFFFFF4, "BGE with offset -12");
        
        // ================================================================
        // TEST 4: U-Type Instructions (20-bit immediate)
        // ================================================================
        $display("[TEST 4] U-Type Instructions (20-bit immediate)\n");
        
        // LUI x10, 0x12345
        // Format: imm[31:12] | rd | 0110111
        // Result: 0x12345000
        instr = {20'h12345, 5'd10, OP_LUI};
        check_immediate(32'h12345000, "LUI with 0x12345");
        
        // LUI x5, 0xFFFFF (max value)
        instr = {20'hFFFFF, 5'd5, OP_LUI};
        check_immediate(32'hFFFFF000, "LUI with 0xFFFFF");
        
        // AUIPC x7, 0x10000
        instr = {20'h10000, 5'd7, OP_AUIPC};
        check_immediate(32'h10000000, "AUIPC with 0x10000");
        
        // AUIPC x8, 0x00001
        instr = {20'h00001, 5'd8, OP_AUIPC};
        check_immediate(32'h00001000, "AUIPC with 0x00001");
        
        // ================================================================
        // TEST 5: J-Type Instructions (21-bit immediate, always even)
        // ================================================================
        $display("[TEST 5] J-Type Instructions (21-bit immediate)\n");
        
        // JAL x1, 20
        // Format: imm[20|10:1|11|19:12] | rd | 1101111
        // imm = 20 = 0b0_0000_0000_0000_0001_0100
        // imm[20] = 0, imm[19:12] = 00000000, imm[11] = 0, imm[10:1] = 0000001010
        instr = {1'b0, 10'b0000001010, 1'b0, 8'b00000000, 5'd1, OP_JAL};
        check_immediate(32'd20, "JAL with offset 20");
        
        // JAL x5, -8
        // imm = -8 = 0b1_1111_1111_1111_1111_1000 (21-bit)
        instr = {1'b1, 10'b1111111100, 1'b1, 8'b11111111, 5'd5, OP_JAL};
        check_immediate(32'hFFFFFFF8, "JAL with offset -8");
        
        // JAL x10, 1024
        // imm = 1024 (decimal) = 0x400 = 0b010_0000_0000 (bit 10 is set)
        // Immediate bits: imm[20:1] (imm[0] is implicit 0)
        // imm[10]=1, all other bits=0
        // Encoding in instruction:
        //   instr[31] = imm[20] = 0
        //   instr[30:21] = imm[10:1] = 10_0000_0000 (bit position 30 = imm[10] = 1)
        //   instr[20] = imm[11] = 0
        //   instr[19:12] = imm[19:12] = 00000000
        // J-type format: imm[20] imm[10:1] imm[11] imm[19:12] rd opcode
        instr = {1'b0, 10'b1000000000, 1'b0, 8'b00000000, 5'd10, OP_JAL};
        check_immediate(32'd1024, "JAL with offset 1024");
        
        // JAL x15, -2048
        // imm = -2048 = 0x800 (in 21-bit)
        instr = {1'b1, 10'b0000000000, 1'b1, 8'b11111111, 5'd15, OP_JAL};
        check_immediate(32'hFFFFF800, "JAL with offset -2048");
        
        // ================================================================
        // TEST 6: R-Type (no immediate)
        // ================================================================
        $display("[TEST 6] R-Type Instructions (no immediate)\n");
        
        // ADD x5, x6, x7
        instr = {7'b0000000, 5'd7, 5'd6, 3'b000, 5'd5, OP_R_TYPE};
        check_immediate(32'h00000000, "ADD (R-type, no immediate)");
        
        // SUB x10, x11, x12
        instr = {7'b0100000, 5'd12, 5'd11, 3'b000, 5'd10, OP_R_TYPE};
        check_immediate(32'h00000000, "SUB (R-type, no immediate)");
        
        // ================================================================
        // TEST 7: Edge Cases
        // ================================================================
        $display("[TEST 7] Edge Cases\n");
        
        // Tất cả bit 1 trong immediate field (I-type)
        instr = {12'hFFF, 5'd0, 3'b000, 5'd5, OP_I_TYPE};
        check_immediate(32'hFFFFFFFF, "I-type with all 1s (-1)");
        
        // Immediate = 0
        instr = {12'h000, 5'd0, 3'b000, 5'd5, OP_I_TYPE};
        check_immediate(32'h00000000, "I-type with immediate = 0");
        
        // ================================================================
        // Kết quả
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