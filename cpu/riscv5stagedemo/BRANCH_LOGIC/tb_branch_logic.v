`timescale 1ps/1ps
`include "branch_logic.v"

module tb_branch_logic;

    // Testbench signals
    reg branch;
    reg [2:0] funct3;
    reg zero_flag;
    reg less_than;
    reg less_than_u;
    
    wire taken;
    
    // Instantiate the BRANCH_LOGIC module
    branch_logic uut (
        .branch(branch),
        .funct3(funct3),
        .zero_flag(zero_flag),
        .less_than(less_than),
        .less_than_u(less_than_u),
        .taken(taken)
    );
    
    // RISC-V Branch funct3 codes
    localparam [2:0] BEQ  = 3'b000;
    localparam [2:0] BNE  = 3'b001;
    localparam [2:0] BLT  = 3'b100;
    localparam [2:0] BGE  = 3'b101;
    localparam [2:0] BLTU = 3'b110;
    localparam [2:0] BGEU = 3'b111;
    
    // Test counter
    integer test_num;
    integer pass_count;
    integer fail_count;
    
    // Task to check result
    task check_result;
        input expected;
        input [8*20:1] test_name;
        begin
            if (taken === expected) begin
                $display("  ✓ PASS: %s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  ✗ FAIL: %s (Expected: %b, Got: %b)", test_name, expected, taken);
                fail_count = fail_count + 1;
            end
        end
    endtask
    
    initial begin
        $display("========================================");
        $display("    BRANCH LOGIC TESTBENCH START       ");
        $display("========================================\n");
        
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize all inputs
        branch = 0;
        funct3 = 3'b000;
        zero_flag = 0;
        less_than = 0;
        less_than_u = 0;
        
        #10;
        
        // ===== TEST 1: No Branch Instruction =====
        test_num = test_num + 1;
        $display("TEST %0d: No Branch Instruction", test_num);
        branch = 0;
        funct3 = BEQ;
        zero_flag = 1;  // Even if condition is true
        less_than = 0;
        less_than_u = 0;
        #10;
        $display("  Inputs: branch=%b, funct3=%b, zero=%b, lt=%b, ltu=%b",
                 branch, funct3, zero_flag, less_than, less_than_u);
        $display("  Output: taken=%b", taken);
        check_result(0, "Not a branch");
        $display("");
        
        // ===== TEST 2: BEQ - Branch if Equal =====
        test_num = test_num + 1;
        $display("TEST %0d: BEQ (Branch if Equal)", test_num);
        branch = 1;
        funct3 = BEQ;
        
        // Test 2a: Equal (should take)
        zero_flag = 1;
        less_than = 0;
        less_than_u = 0;
        #10;
        $display("  [2a] rs1 == rs2 (zero_flag=1)");
        $display("  Inputs: branch=%b, funct3=%b, zero=%b", branch, funct3, zero_flag);
        $display("  Output: taken=%b", taken);
        check_result(1, "BEQ taken");
        
        // Test 2b: Not equal (should not take)
        zero_flag = 0;
        #10;
        $display("  [2b] rs1 != rs2 (zero_flag=0)");
        $display("  Inputs: branch=%b, funct3=%b, zero=%b", branch, funct3, zero_flag);
        $display("  Output: taken=%b", taken);
        check_result(0, "BEQ not taken");
        $display("");
        
        // ===== TEST 3: BNE - Branch if Not Equal =====
        test_num = test_num + 1;
        $display("TEST %0d: BNE (Branch if Not Equal)", test_num);
        funct3 = BNE;
        
        // Test 3a: Not equal (should take)
        zero_flag = 0;
        #10;
        $display("  [3a] rs1 != rs2 (zero_flag=0)");
        $display("  Inputs: branch=%b, funct3=%b, zero=%b", branch, funct3, zero_flag);
        $display("  Output: taken=%b", taken);
        check_result(1, "BNE taken");
        
        // Test 3b: Equal (should not take)
        zero_flag = 1;
        #10;
        $display("  [3b] rs1 == rs2 (zero_flag=1)");
        $display("  Inputs: branch=%b, funct3=%b, zero=%b", branch, funct3, zero_flag);
        $display("  Output: taken=%b", taken);
        check_result(0, "BNE not taken");
        $display("");
        
        // ===== TEST 4: BLT - Branch if Less Than (signed) =====
        test_num = test_num + 1;
        $display("TEST %0d: BLT (Branch if Less Than - Signed)", test_num);
        funct3 = BLT;
        zero_flag = 0;
        
        // Test 4a: rs1 < rs2 (should take)
        less_than = 1;
        less_than_u = 0;
        #10;
        $display("  [4a] rs1 < rs2 signed (less_than=1)");
        $display("  Inputs: branch=%b, funct3=%b, lt=%b", branch, funct3, less_than);
        $display("  Output: taken=%b", taken);
        check_result(1, "BLT taken");
        
        // Test 4b: rs1 >= rs2 (should not take)
        less_than = 0;
        #10;
        $display("  [4b] rs1 >= rs2 signed (less_than=0)");
        $display("  Inputs: branch=%b, funct3=%b, lt=%b", branch, funct3, less_than);
        $display("  Output: taken=%b", taken);
        check_result(0, "BLT not taken");
        $display("");
        
        // ===== TEST 5: BGE - Branch if Greater or Equal (signed) =====
        test_num = test_num + 1;
        $display("TEST %0d: BGE (Branch if Greater/Equal - Signed)", test_num);
        funct3 = BGE;
        
        // Test 5a: rs1 >= rs2 (should take)
        less_than = 0;
        #10;
        $display("  [5a] rs1 >= rs2 signed (less_than=0)");
        $display("  Inputs: branch=%b, funct3=%b, lt=%b", branch, funct3, less_than);
        $display("  Output: taken=%b", taken);
        check_result(1, "BGE taken");
        
        // Test 5b: rs1 < rs2 (should not take)
        less_than = 1;
        #10;
        $display("  [5b] rs1 < rs2 signed (less_than=1)");
        $display("  Inputs: branch=%b, funct3=%b, lt=%b", branch, funct3, less_than);
        $display("  Output: taken=%b", taken);
        check_result(0, "BGE not taken");
        $display("");
        
        // ===== TEST 6: BLTU - Branch if Less Than (unsigned) =====
        test_num = test_num + 1;
        $display("TEST %0d: BLTU (Branch if Less Than - Unsigned)", test_num);
        funct3 = BLTU;
        less_than = 0;
        
        // Test 6a: rs1 < rs2 unsigned (should take)
        less_than_u = 1;
        #10;
        $display("  [6a] rs1 < rs2 unsigned (less_than_u=1)");
        $display("  Inputs: branch=%b, funct3=%b, ltu=%b", branch, funct3, less_than_u);
        $display("  Output: taken=%b", taken);
        check_result(1, "BLTU taken");
        
        // Test 6b: rs1 >= rs2 unsigned (should not take)
        less_than_u = 0;
        #10;
        $display("  [6b] rs1 >= rs2 unsigned (less_than_u=0)");
        $display("  Inputs: branch=%b, funct3=%b, ltu=%b", branch, funct3, less_than_u);
        $display("  Output: taken=%b", taken);
        check_result(0, "BLTU not taken");
        $display("");
        
        // ===== TEST 7: BGEU - Branch if Greater or Equal (unsigned) =====
        test_num = test_num + 1;
        $display("TEST %0d: BGEU (Branch if Greater/Equal - Unsigned)", test_num);
        funct3 = BGEU;
        
        // Test 7a: rs1 >= rs2 unsigned (should take)
        less_than_u = 0;
        #10;
        $display("  [7a] rs1 >= rs2 unsigned (less_than_u=0)");
        $display("  Inputs: branch=%b, funct3=%b, ltu=%b", branch, funct3, less_than_u);
        $display("  Output: taken=%b", taken);
        check_result(1, "BGEU taken");
        
        // Test 7b: rs1 < rs2 unsigned (should not take)
        less_than_u = 1;
        #10;
        $display("  [7b] rs1 < rs2 unsigned (less_than_u=1)");
        $display("  Inputs: branch=%b, funct3=%b, ltu=%b", branch, funct3, less_than_u);
        $display("  Output: taken=%b", taken);
        check_result(0, "BGEU not taken");
        $display("");
        
        // ===== TEST 8: Invalid funct3 =====
        test_num = test_num + 1;
        $display("TEST %0d: Invalid funct3", test_num);
        funct3 = 3'b010;  // Invalid code
        zero_flag = 1;
        less_than = 1;
        less_than_u = 1;
        #10;
        $display("  Inputs: branch=%b, funct3=%b (invalid)", branch, funct3);
        $display("  Output: taken=%b", taken);
        check_result(0, "Invalid funct3");
        $display("");
        
        // ===== TEST 9: Edge case - All flags set =====
        test_num = test_num + 1;
        $display("TEST %0d: Edge Case - All flags true with different branches", test_num);
        zero_flag = 1;
        less_than = 1;
        less_than_u = 1;
        
        // BEQ with all flags
        funct3 = BEQ;
        #10;
        $display("  [9a] BEQ with all flags=1");
        check_result(1, "BEQ checks zero only");
        
        // BLT with all flags
        funct3 = BLT;
        #10;
        $display("  [9b] BLT with all flags=1");
        check_result(1, "BLT checks lt only");
        
        // BLTU with all flags
        funct3 = BLTU;
        #10;
        $display("  [9c] BLTU with all flags=1");
        check_result(1, "BLTU checks ltu only");
        $display("");
        
        // ===== TEST 10: Realistic scenarios =====
        test_num = test_num + 1;
        $display("TEST %0d: Realistic Scenarios", test_num);
        
        // Scenario 1: Comparing positive numbers (5 < 10)
        $display("  [10a] Compare 5 < 10 (both signed and unsigned)");
        zero_flag = 0;
        less_than = 1;
        less_than_u = 1;
        funct3 = BLT;
        #10;
        check_result(1, "5 < 10 signed");
        
        // Scenario 2: Comparing with negative number (-5 < 10)
        $display("  [10b] Compare -5 < 10 (signed true, unsigned false)");
        zero_flag = 0;
        less_than = 1;
        less_than_u = 0;  // Unsigned: -5 is very large
        funct3 = BLT;
        #10;
        check_result(1, "-5 < 10 signed");
        funct3 = BLTU;
        #10;
        check_result(0, "-5 >= 10 unsigned");
        $display("");
        
        #10;
        $display("\n========================================");
        $display("       TESTBENCH COMPLETED              ");
        $display("========================================");
        $display("  Total Tests: %0d", test_num);
        $display("  Passed: %0d", pass_count);
        $display("  Failed: %0d", fail_count);
        if (fail_count == 0)
            $display("  🎉 ALL TESTS PASSED! 🎉");
        else
            $display("  ⚠️  SOME TESTS FAILED");
        $display("========================================\n");
        
        $finish;
    end
    
    // Monitor for debugging
    initial begin
        $monitor("Time=%0t | branch=%b funct3=%b zero=%b lt=%b ltu=%b | taken=%b",
                 $time, branch, funct3, zero_flag, less_than, less_than_u, taken);
    end

endmodule