`include "forwarding_unit.v"
`timescale 1ps/1ps

module tb_forwarding_unit;

    reg [4:0] rs1_ex;
    reg [4:0] rs2_ex;
    reg [4:0] rd_mem;
    reg [4:0] rd_wb;
    reg regwrite_mem;
    reg regwrite_wb;
    
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    // Instantiate module
    forwarding_unit uut (
        .rs1_ex(rs1_ex),
        .rs2_ex(rs2_ex),
        .rd_mem(rd_mem),
        .rd_wb(rd_wb),
        .regwrite_mem(regwrite_mem),
        .regwrite_wb(regwrite_wb),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    // Helper function to display forwarding source
    function [63:0] fwd_source;
        input [1:0] fwd;
        begin
            case(fwd)
                2'b00: fwd_source = "REG_FILE";
                2'b01: fwd_source = "WB_STAGE";
                2'b10: fwd_source = "MEM_STGE";
                default: fwd_source = "UNKNOWN ";
            endcase
        end
    endfunction

    initial begin
        $display("=== Testbench for FORWARDING_UNIT ===\n");
        
        // Initialize
        rs1_ex = 5'd0;
        rs2_ex = 5'd0;
        rd_mem = 5'd0;
        rd_wb = 5'd0;
        regwrite_mem = 0;
        regwrite_wb = 0;
        #10;

        // ================================================
        // Test 1: No hazard (no forwarding needed)
        // ================================================
        $display("Test 1: No hazard");
        $display("Instruction: ADD R5, R1, R2");
        rs1_ex = 5'd1;
        rs2_ex = 5'd2;
        rd_mem = 5'd3;
        rd_wb = 5'd4;
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b00 && forward_b == 2'b00)
            $display("✓ PASS - No forwarding needed\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 2: EX-EX hazard (forward from MEM stage)
        // ================================================
        $display("Test 2: EX-EX hazard (1 cycle apart)");
        $display("MEM: ADD R3, R1, R2  (writes R3)");
        $display("EX:  SUB R5, R3, R4  (reads R3) <- needs R3 from MEM");
        rs1_ex = 5'd3;    // SUB reads R3
        rs2_ex = 5'd4;
        rd_mem = 5'd3;    // ADD writes R3
        rd_wb = 5'd10;
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b10 && forward_b == 2'b00)
            $display("✓ PASS - Forward from MEM for rs1\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 3: MEM-EX hazard (forward from WB stage)
        // ================================================
        $display("Test 3: MEM-EX hazard (2 cycles apart)");
        $display("WB:  ADD R3, R1, R2  (writes R3)");
        $display("EX:  SUB R5, R3, R4  (reads R3) <- needs R3 from WB");
        rs1_ex = 5'd3;
        rs2_ex = 5'd4;
        rd_mem = 5'd10;
        rd_wb = 5'd3;     // ADD writes R3
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b01 && forward_b == 2'b00)
            $display("✓ PASS - Forward from WB for rs1\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 4: Double hazard (both operands need forwarding)
        // ================================================
        $display("Test 4: Double hazard");
        $display("MEM: ADD R3, R1, R2  (writes R3)");
        $display("EX:  SUB R5, R3, R3  (reads R3 twice)");
        rs1_ex = 5'd3;
        rs2_ex = 5'd3;
        rd_mem = 5'd3;
        rd_wb = 5'd10;
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b10 && forward_b == 2'b10)
            $display("✓ PASS - Forward from MEM for both operands\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 5: Priority (MEM has priority over WB)
        // ================================================
        $display("Test 5: Priority test (MEM over WB)");
        $display("WB:  ADD R3, R1, R2  (writes R3)");
        $display("MEM: SUB R3, R5, R6  (writes R3) <- more recent");
        $display("EX:  AND R7, R3, R4  (reads R3) <- should get from MEM");
        rs1_ex = 5'd3;
        rs2_ex = 5'd4;
        rd_mem = 5'd3;    // MEM writes R3
        rd_wb = 5'd3;     // WB also writes R3
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b10)
            $display("✓ PASS - MEM has priority over WB\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 6: Write to x0 (no forwarding)
        // ================================================
        $display("Test 6: Write to x0 (hardware zero)");
        $display("MEM: ADD R0, R1, R2  (writes R0 - invalid)");
        $display("EX:  SUB R5, R0, R4  (reads R0) <- should always be 0");
        rs1_ex = 5'd0;
        rs2_ex = 5'd4;
        rd_mem = 5'd0;    // Write to x0
        rd_wb = 5'd10;
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b00)
            $display("✓ PASS - No forwarding for x0\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 7: regwrite disabled
        // ================================================
        $display("Test 7: regwrite disabled (SW, Branch)");
        $display("MEM: SW R3, 0(R5)    (no write)");
        $display("EX:  ADD R7, R3, R4  (reads R3)");
        rs1_ex = 5'd3;
        rs2_ex = 5'd4;
        rd_mem = 5'd3;
        rd_wb = 5'd10;
        regwrite_mem = 0;  // Store doesn't write
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b00)
            $display("✓ PASS - No forwarding when regwrite=0\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 8: Complex scenario (different sources)
        // ================================================
        $display("Test 8: Complex scenario");
        $display("WB:  ADD R2, R1, R3  (writes R2)");
        $display("MEM: SUB R4, R5, R6  (writes R4)");
        $display("EX:  AND R7, R2, R4  (reads R2 from WB, R4 from MEM)");
        rs1_ex = 5'd2;    // From WB
        rs2_ex = 5'd4;    // From MEM
        rd_mem = 5'd4;
        rd_wb = 5'd2;
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("forward_a=%b (%s), forward_b=%b (%s)", 
                 forward_a, fwd_source(forward_a), forward_b, fwd_source(forward_b));
        if (forward_a == 2'b01 && forward_b == 2'b10)
            $display("✓ PASS - Different forwarding sources\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 9: Real code sequence
        // ================================================
        $display("Test 9: Real code sequence");
        $display("Code:");
        $display("  ADD R2, R1, R3   # I1");
        $display("  SUB R4, R2, R5   # I2 (RAW hazard on R2)");
        $display("  AND R6, R4, R7   # I3 (RAW hazard on R4)");
        $display("");
        
        // Cycle 1: I1 in MEM, I2 in EX
        $display("Cycle 1: I1 in MEM, I2 in EX");
        rs1_ex = 5'd2;    // I2 reads R2
        rs2_ex = 5'd5;
        rd_mem = 5'd2;    // I1 writes R2
        rd_wb = 5'd10;
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("I2 needs R2: forward_a=%b (%s)", forward_a, fwd_source(forward_a));
        if (forward_a == 2'b10)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");
        
        // Cycle 2: I2 in MEM, I3 in EX
        $display("Cycle 2: I2 in MEM, I3 in EX");
        rs1_ex = 5'd4;    // I3 reads R4
        rs2_ex = 5'd7;
        rd_mem = 5'd4;    // I2 writes R4
        rd_wb = 5'd2;     // I1 writes R2
        regwrite_mem = 1;
        regwrite_wb = 1;
        #10;
        $display("I3 needs R4: forward_a=%b (%s)", forward_a, fwd_source(forward_a));
        if (forward_a == 2'b10)
            $display("✓ PASS\n");
        else
            $display("✗ FAIL\n");

        // ================================================
        // Test 10: All combinations
        // ================================================
        $display("Test 10: Forwarding combinations summary");
        $display("Testing all 4 combinations for forward_a:");
        
        // Case 00: No forwarding
        rs1_ex = 5'd1; rd_mem = 5'd2; rd_wb = 5'd3;
        regwrite_mem = 1; regwrite_wb = 1;
        #10;
        $display("  Case 00: forward_a=%b %s", forward_a, (forward_a == 2'b00) ? "✓" : "✗");
        
        // Case 01: From WB
        rs1_ex = 5'd3; rd_mem = 5'd2; rd_wb = 5'd3;
        regwrite_mem = 1; regwrite_wb = 1;
        #10;
        $display("  Case 01: forward_a=%b %s", forward_a, (forward_a == 2'b01) ? "✓" : "✗");
        
        // Case 10: From MEM
        rs1_ex = 5'd2; rd_mem = 5'd2; rd_wb = 5'd3;
        regwrite_mem = 1; regwrite_wb = 1;
        #10;
        $display("  Case 10: forward_a=%b %s", forward_a, (forward_a == 2'b10) ? "✓" : "✗");
        
        // Case 10: MEM priority when both match
        rs1_ex = 5'd2; rd_mem = 5'd2; rd_wb = 5'd2;
        regwrite_mem = 1; regwrite_wb = 1;
        #10;
        $display("  Priority: forward_a=%b (MEM over WB) %s", forward_a, (forward_a == 2'b10) ? "✓" : "✗");

        $display("\n=== All tests completed ===");
        $finish;
    end

    // Monitor changes
    initial begin
        $monitor("Time=%0t | rs1=%d rs2=%d | rd_mem=%d rd_wb=%d | rw_mem=%b rw_wb=%b | fwd_a=%b fwd_b=%b", 
                 $time, rs1_ex, rs2_ex, rd_mem, rd_wb, regwrite_mem, regwrite_wb, forward_a, forward_b);
    end

endmodule