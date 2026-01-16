`include "hazard_detection.v"
`timescale 1ps/1ps

module tb_hazard_detection;

    // Testbench signals
    reg memread_id_ex;
    reg [4:0] rd_id_ex;
    reg [4:0] rs1_id;
    reg [4:0] rs2_id;
    reg branch_taken;
    
    wire stall;
    wire flush_if_id;
    wire flush_id_ex;
    
    // Instantiate the HAZARD_DETECTION module
    hazard_detection uut (
        .memread_id_ex(memread_id_ex),
        .rd_id_ex(rd_id_ex),
        .rs1_id(rs1_id),
        .rs2_id(rs2_id),
        .branch_taken(branch_taken),
        .stall(stall),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );
    
    // Test counter
    integer test_num;
    
    initial begin
        $display("========================================");
        $display("    HAZARD DETECTION TESTBENCH START   ");
        $display("========================================\n");
        
        test_num = 0;
        
        // Initialize all inputs
        memread_id_ex = 0;
        rd_id_ex = 0;
        rs1_id = 0;
        rs2_id = 0;
        branch_taken = 0;
        
        #10;
        
        // ===== TEST 1: No Hazard (Normal Operation) =====
        test_num = test_num + 1;
        $display("TEST %0d: No Hazard - Normal Operation", test_num);
        memread_id_ex = 0;
        rd_id_ex = 5'b00001;
        rs1_id = 5'b00010;
        rs2_id = 5'b00011;
        branch_taken = 0;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 0 && flush_if_id == 0 && flush_id_ex == 0)
            $display("  ✓ PASS: No hazard detected\n");
        else
            $display("  ✗ FAIL: Unexpected hazard signals\n");
        
        // ===== TEST 2: Load-Use Hazard (rs1 match) =====
        test_num = test_num + 1;
        $display("TEST %0d: Load-Use Hazard - rs1 match", test_num);
        memread_id_ex = 1;
        rd_id_ex = 5'b00101;      // x5
        rs1_id = 5'b00101;        // x5 (match!)
        rs2_id = 5'b00110;        // x6
        branch_taken = 0;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 1 && flush_id_ex == 1 && flush_if_id == 0)
            $display("  ✓ PASS: Load-Use hazard detected correctly\n");
        else
            $display("  ✗ FAIL: Load-Use hazard not handled properly\n");
        
        // ===== TEST 3: Load-Use Hazard (rs2 match) =====
        test_num = test_num + 1;
        $display("TEST %0d: Load-Use Hazard - rs2 match", test_num);
        memread_id_ex = 1;
        rd_id_ex = 5'b00111;      // x7
        rs1_id = 5'b00110;        // x6
        rs2_id = 5'b00111;        // x7 (match!)
        branch_taken = 0;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 1 && flush_id_ex == 1 && flush_if_id == 0)
            $display("  ✓ PASS: Load-Use hazard detected correctly\n");
        else
            $display("  ✗ FAIL: Load-Use hazard not handled properly\n");
        
        // ===== TEST 4: Load-Use Hazard with x0 (should NOT stall) =====
        test_num = test_num + 1;
        $display("TEST %0d: Load to x0 - No Hazard", test_num);
        memread_id_ex = 1;
        rd_id_ex = 5'b00000;      // x0
        rs1_id = 5'b00000;        // x0 (match but x0 is hardwired to 0)
        rs2_id = 5'b00001;
        branch_taken = 0;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 0 && flush_if_id == 0 && flush_id_ex == 0)
            $display("  ✓ PASS: x0 ignored correctly\n");
        else
            $display("  ✗ FAIL: x0 should not cause hazard\n");
        
        // ===== TEST 5: Branch Taken (Control Hazard) =====
        test_num = test_num + 1;
        $display("TEST %0d: Branch Taken - Control Hazard", test_num);
        memread_id_ex = 0;
        rd_id_ex = 5'b00001;
        rs1_id = 5'b00010;
        rs2_id = 5'b00011;
        branch_taken = 1;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 0 && flush_if_id == 1 && flush_id_ex == 1)
            $display("  ✓ PASS: Branch hazard handled correctly\n");
        else
            $display("  ✗ FAIL: Branch hazard not handled properly\n");
        
        // ===== TEST 6: Both Load-Use and Branch (Branch has priority) =====
        test_num = test_num + 1;
        $display("TEST %0d: Both Hazards - Branch Priority", test_num);
        memread_id_ex = 1;
        rd_id_ex = 5'b00101;
        rs1_id = 5'b00101;        // Would cause load-use hazard
        rs2_id = 5'b00110;
        branch_taken = 1;         // But branch taken
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 0 && flush_if_id == 1 && flush_id_ex == 1)
            $display("  ✓ PASS: Branch takes priority over load-use\n");
        else
            $display("  ✗ FAIL: Priority handling incorrect\n");
        
        // ===== TEST 7: Load but no register match =====
        test_num = test_num + 1;
        $display("TEST %0d: Load without register match", test_num);
        memread_id_ex = 1;
        rd_id_ex = 5'b01000;      // x8
        rs1_id = 5'b00001;        // x1 (no match)
        rs2_id = 5'b00010;        // x2 (no match)
        branch_taken = 0;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 0 && flush_if_id == 0 && flush_id_ex == 0)
            $display("  ✓ PASS: No hazard when registers don't match\n");
        else
            $display("  ✗ FAIL: False hazard detected\n");
        
        // ===== TEST 8: Non-load instruction with register match =====
        test_num = test_num + 1;
        $display("TEST %0d: Non-load with register match", test_num);
        memread_id_ex = 0;        // Not a load
        rd_id_ex = 5'b00101;
        rs1_id = 5'b00101;        // Match but not a load
        rs2_id = 5'b00110;
        branch_taken = 0;
        #10;
        $display("  Inputs: memread=%b, rd_ex=%d, rs1=%d, rs2=%d, branch=%b",
                 memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken);
        $display("  Outputs: stall=%b, flush_if_id=%b, flush_id_ex=%b",
                 stall, flush_if_id, flush_id_ex);
        if (stall == 0 && flush_if_id == 0 && flush_id_ex == 0)
            $display("  ✓ PASS: No stall for non-load instructions\n");
        else
            $display("  ✗ FAIL: Should not stall for non-load\n");
        
        #10;
        $display("\n========================================");
        $display("       TESTBENCH COMPLETED              ");
        $display("       Total Tests: %0d                  ", test_num);
        $display("========================================");
        
        $finish;
    end
    
    // Monitor for debugging
    initial begin
        $monitor("Time=%0t | memread=%b rd_ex=%d rs1=%d rs2=%d branch=%b | stall=%b flush_if_id=%b flush_id_ex=%b",
                 $time, memread_id_ex, rd_id_ex, rs1_id, rs2_id, branch_taken, 
                 stall, flush_if_id, flush_id_ex);
    end

endmodule