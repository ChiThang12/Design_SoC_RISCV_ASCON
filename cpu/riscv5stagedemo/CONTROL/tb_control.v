// ============================================================================
// CONTROL_tb.v - Testbench cho RISC-V Control Unit
// ============================================================================

`timescale 1ns/1ps
`include "control.v"
module tb_control;

    // Tín hiệu input
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg [6:0] funct7;
    
    // Tín hiệu output
    wire [3:0] alu_control;
    wire regwrite;
    wire alusrc;
    wire memread;
    wire memwrite;
    wire memtoreg;
    wire branch;
    wire jump;
    wire [1:0] aluop;
    wire [1:0] byte_size;
    
    // Biến đếm test
    integer passed, failed;
    
    // Opcode định nghĩa
    localparam [6:0]
        OP_R_TYPE   = 7'b0110011,
        OP_I_TYPE   = 7'b0010011,
        OP_LOAD     = 7'b0000011,
        OP_STORE    = 7'b0100011,
        OP_BRANCH   = 7'b1100011,
        OP_JAL      = 7'b1101111,
        OP_JALR     = 7'b1100111,
        OP_LUI      = 7'b0110111,
        OP_AUIPC    = 7'b0010111;
    
    // ALU control codes
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
    control uut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .alu_control(alu_control),
        .regwrite(regwrite),
        .alusrc(alusrc),
        .memread(memread),
        .memwrite(memwrite),
        .memtoreg(memtoreg),
        .branch(branch),
        .jump(jump),
        .aluop(aluop),
        .byte_size(byte_size)
    );
    
    // Task để kiểm tra tín hiệu
    task check_signals;
        input [200*8:1] instr_name;
        input exp_regwrite;
        input exp_alusrc;
        input exp_memread;
        input exp_memwrite;
        input exp_memtoreg;
        input exp_branch;
        input exp_jump;
        input [3:0] exp_alu_control;
        begin
            #1;
            if (regwrite === exp_regwrite &&
                alusrc === exp_alusrc &&
                memread === exp_memread &&
                memwrite === exp_memwrite &&
                memtoreg === exp_memtoreg &&
                branch === exp_branch &&
                jump === exp_jump &&
                alu_control === exp_alu_control) begin
                $display("  ✓ PASS: %0s", instr_name);
                passed = passed + 1;
            end
            else begin
                $display("  ✗ FAIL: %0s", instr_name);
                $display("      Expected: rw=%b as=%b mr=%b mw=%b mt=%b br=%b jp=%b alu=%b",
                         exp_regwrite, exp_alusrc, exp_memread, exp_memwrite,
                         exp_memtoreg, exp_branch, exp_jump, exp_alu_control);
                $display("      Got:      rw=%b as=%b mr=%b mw=%b mt=%b br=%b jp=%b alu=%b",
                         regwrite, alusrc, memread, memwrite,
                         memtoreg, branch, jump, alu_control);
                failed = failed + 1;
            end
        end
    endtask
    
    // Test sequence
    initial begin
        $dumpfile("tb_control.vcd");
        $dumpvars(0, tb_control);
        
        passed = 0;
        failed = 0;
        
        $display("\n============================================");
        $display("  RISC-V Control Unit Testbench");
        $display("============================================\n");
        
        // ================================================================
        // TEST 1: R-Type Instructions
        // ================================================================
        $display("[TEST 1] R-Type Instructions");
        
        // ADD: add rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b000; funct7 = 7'b0000000;
        check_signals("ADD", 1, 0, 0, 0, 0, 0, 0, ALU_ADD);
        
        // SUB: sub rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b000; funct7 = 7'b0100000;
        check_signals("SUB", 1, 0, 0, 0, 0, 0, 0, ALU_SUB);
        
        // AND: and rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b111; funct7 = 7'b0000000;
        check_signals("AND", 1, 0, 0, 0, 0, 0, 0, ALU_AND);
        
        // OR: or rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b110; funct7 = 7'b0000000;
        check_signals("OR", 1, 0, 0, 0, 0, 0, 0, ALU_OR);
        
        // XOR: xor rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b100; funct7 = 7'b0000000;
        check_signals("XOR", 1, 0, 0, 0, 0, 0, 0, ALU_XOR);
        
        // SLL: sll rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b001; funct7 = 7'b0000000;
        check_signals("SLL", 1, 0, 0, 0, 0, 0, 0, ALU_SLL);
        
        // SRL: srl rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b101; funct7 = 7'b0000000;
        check_signals("SRL", 1, 0, 0, 0, 0, 0, 0, ALU_SRL);
        
        // SRA: sra rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b101; funct7 = 7'b0100000;
        check_signals("SRA", 1, 0, 0, 0, 0, 0, 0, ALU_SRA);
        
        // SLT: slt rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b010; funct7 = 7'b0000000;
        check_signals("SLT", 1, 0, 0, 0, 0, 0, 0, ALU_SLT);
        
        // SLTU: sltu rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b011; funct7 = 7'b0000000;
        check_signals("SLTU", 1, 0, 0, 0, 0, 0, 0, ALU_SLTU);
        
        // ================================================================
        // TEST 2: R-Type M Extension (Multiply/Divide)
        // ================================================================
        $display("\n[TEST 2] R-Type M Extension");
        
        // MUL: mul rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b000; funct7 = 7'b0000001;
        check_signals("MUL", 1, 0, 0, 0, 0, 0, 0, ALU_MUL);
        
        // MULH: mulh rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b001; funct7 = 7'b0000001;
        check_signals("MULH", 1, 0, 0, 0, 0, 0, 0, ALU_MULH);
        
        // DIV: div rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b100; funct7 = 7'b0000001;
        check_signals("DIV", 1, 0, 0, 0, 0, 0, 0, ALU_DIV);
        
        // DIVU: divu rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b101; funct7 = 7'b0000001;
        check_signals("DIVU", 1, 0, 0, 0, 0, 0, 0, ALU_DIVU);
        
        // REM: rem rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b110; funct7 = 7'b0000001;
        check_signals("REM", 1, 0, 0, 0, 0, 0, 0, ALU_REM);
        
        // REMU: remu rd, rs1, rs2
        opcode = OP_R_TYPE; funct3 = 3'b111; funct7 = 7'b0000001;
        check_signals("REMU", 1, 0, 0, 0, 0, 0, 0, ALU_REMU);
        
        // ================================================================
        // TEST 3: I-Type Instructions
        // ================================================================
        $display("\n[TEST 3] I-Type Instructions");
        
        // ADDI: addi rd, rs1, imm
        opcode = OP_I_TYPE; funct3 = 3'b000; funct7 = 7'b0000000;
        check_signals("ADDI", 1, 1, 0, 0, 0, 0, 0, ALU_ADD);
        
        // ANDI: andi rd, rs1, imm
        opcode = OP_I_TYPE; funct3 = 3'b111; funct7 = 7'b0000000;
        check_signals("ANDI", 1, 1, 0, 0, 0, 0, 0, ALU_AND);
        
        // ORI: ori rd, rs1, imm
        opcode = OP_I_TYPE; funct3 = 3'b110; funct7 = 7'b0000000;
        check_signals("ORI", 1, 1, 0, 0, 0, 0, 0, ALU_OR);
        
        // XORI: xori rd, rs1, imm
        opcode = OP_I_TYPE; funct3 = 3'b100; funct7 = 7'b0000000;
        check_signals("XORI", 1, 1, 0, 0, 0, 0, 0, ALU_XOR);
        
        // SLLI: slli rd, rs1, shamt
        opcode = OP_I_TYPE; funct3 = 3'b001; funct7 = 7'b0000000;
        check_signals("SLLI", 1, 1, 0, 0, 0, 0, 0, ALU_SLL);
        
        // SRLI: srli rd, rs1, shamt
        opcode = OP_I_TYPE; funct3 = 3'b101; funct7 = 7'b0000000;
        check_signals("SRLI", 1, 1, 0, 0, 0, 0, 0, ALU_SRL);
        
        // SRAI: srai rd, rs1, shamt
        opcode = OP_I_TYPE; funct3 = 3'b101; funct7 = 7'b0100000;
        check_signals("SRAI", 1, 1, 0, 0, 0, 0, 0, ALU_SRA);
        
        // SLTI: slti rd, rs1, imm
        opcode = OP_I_TYPE; funct3 = 3'b010; funct7 = 7'b0000000;
        check_signals("SLTI", 1, 1, 0, 0, 0, 0, 0, ALU_SLT);
        
        // SLTIU: sltiu rd, rs1, imm
        opcode = OP_I_TYPE; funct3 = 3'b011; funct7 = 7'b0000000;
        check_signals("SLTIU", 1, 1, 0, 0, 0, 0, 0, ALU_SLTU);
        
        // ================================================================
        // TEST 4: Load Instructions
        // ================================================================
        $display("\n[TEST 4] Load Instructions");
        
        // LW: lw rd, offset(rs1)
        opcode = OP_LOAD; funct3 = 3'b010; funct7 = 7'b0000000;
        #1;
        if (regwrite && alusrc && memread && memtoreg && byte_size == 2'b10) begin
            $display("  ✓ PASS: LW");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: LW");
            failed = failed + 1;
        end
        
        // LH: lh rd, offset(rs1)
        opcode = OP_LOAD; funct3 = 3'b001; funct7 = 7'b0000000;
        #1;
        if (byte_size == 2'b01) begin
            $display("  ✓ PASS: LH (byte_size=01)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: LH");
            failed = failed + 1;
        end
        
        // LB: lb rd, offset(rs1)
        opcode = OP_LOAD; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (byte_size == 2'b00) begin
            $display("  ✓ PASS: LB (byte_size=00)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: LB");
            failed = failed + 1;
        end
        
        // ================================================================
        // TEST 5: Store Instructions
        // ================================================================
        $display("\n[TEST 5] Store Instructions");
        
        // SW: sw rs2, offset(rs1)
        opcode = OP_STORE; funct3 = 3'b010; funct7 = 7'b0000000;
        #1;
        if (alusrc && memwrite && !regwrite && byte_size == 2'b10) begin
            $display("  ✓ PASS: SW");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: SW");
            failed = failed + 1;
        end
        
        // SH: sh rs2, offset(rs1)
        opcode = OP_STORE; funct3 = 3'b001; funct7 = 7'b0000000;
        #1;
        if (byte_size == 2'b01) begin
            $display("  ✓ PASS: SH (byte_size=01)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: SH");
            failed = failed + 1;
        end
        
        // SB: sb rs2, offset(rs1)
        opcode = OP_STORE; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (byte_size == 2'b00) begin
            $display("  ✓ PASS: SB (byte_size=00)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: SB");
            failed = failed + 1;
        end
        
        // ================================================================
        // TEST 6: Branch Instructions
        // ================================================================
        $display("\n[TEST 6] Branch Instructions");
        
        // BEQ, BNE, BLT, BGE, BLTU, BGEU
        opcode = OP_BRANCH; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (branch && !regwrite && !memread && !memwrite) begin
            $display("  ✓ PASS: BRANCH instructions (BEQ)");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: BRANCH");
            failed = failed + 1;
        end
        
        // ================================================================
        // TEST 7: Jump Instructions
        // ================================================================
        $display("\n[TEST 7] Jump Instructions");
        
        // JAL: jal rd, offset
        opcode = OP_JAL; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (jump && regwrite) begin
            $display("  ✓ PASS: JAL");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: JAL");
            failed = failed + 1;
        end
        
        // JALR: jalr rd, rs1, offset
        opcode = OP_JALR; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (jump && regwrite && alusrc) begin
            $display("  ✓ PASS: JALR");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: JALR");
            failed = failed + 1;
        end
        
        // ================================================================
        // TEST 8: Upper Immediate Instructions
        // ================================================================
        $display("\n[TEST 8] Upper Immediate Instructions");
        
        // LUI: lui rd, imm
        opcode = OP_LUI; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (regwrite && alusrc) begin
            $display("  ✓ PASS: LUI");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: LUI");
            failed = failed + 1;
        end
        
        // AUIPC: auipc rd, imm
        opcode = OP_AUIPC; funct3 = 3'b000; funct7 = 7'b0000000;
        #1;
        if (regwrite && alusrc) begin
            $display("  ✓ PASS: AUIPC");
            passed = passed + 1;
        end else begin
            $display("  ✗ FAIL: AUIPC");
            failed = failed + 1;
        end
        
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