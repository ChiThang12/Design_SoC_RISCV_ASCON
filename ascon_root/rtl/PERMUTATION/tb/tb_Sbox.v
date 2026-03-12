`timescale 1ns/1ps
`include "ascon/rtl/PERMUTATION/ascon_SBOX.v"
module tb_sbox;
    reg [4:0] in;
    wire [4:0] out;
    reg [4:0] expected;
    integer errors;
    
    // Include SBOX module
    ASCON_SBOX dut (
        .in(in),
        .out(out)
    );
    
    initial begin
        errors = 0;
        $display("========================================");
        $display("ASCON S-BOX TEST - All 32 cases");
        $display("========================================");
        $display("in    | out   | expected | status");
        $display("----------------------------------------");
        
        // Test case 0: 00000 => 00100
        in = 5'b00000; expected = 5'b00100; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 1: 00001 => 01111
        in = 5'b00001; expected = 5'b01111; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 2: 00010 => 11011
        in = 5'b00010; expected = 5'b11011; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 3: 00011 => 00001
        in = 5'b00011; expected = 5'b00001; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 4: 00100 => 01011
        in = 5'b00100; expected = 5'b01011; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 5: 00101 => 00000
        in = 5'b00101; expected = 5'b00000; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 6: 00110 => 10111
        in = 5'b00110; expected = 5'b10111; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 7: 00111 => 01101
        in = 5'b00111; expected = 5'b01101; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 8: 01000 => 11111
        in = 5'b01000; expected = 5'b11111; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 9: 01001 => 11100
        in = 5'b01001; expected = 5'b11100; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 10: 01010 => 00010
        in = 5'b01010; expected = 5'b00010; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 11: 01011 => 10000
        in = 5'b01011; expected = 5'b10000; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 12: 01100 => 10010
        in = 5'b01100; expected = 5'b10010; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 13: 01101 => 10001
        in = 5'b01101; expected = 5'b10001; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 14: 01110 => 01100
        in = 5'b01110; expected = 5'b01100; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 15: 01111 => 11110
        in = 5'b01111; expected = 5'b11110; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 16: 10000 => 11010
        in = 5'b10000; expected = 5'b11010; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 17: 10001 => 11001
        in = 5'b10001; expected = 5'b11001; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 18: 10010 => 10100
        in = 5'b10010; expected = 5'b10100; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 19: 10011 => 00110
        in = 5'b10011; expected = 5'b00110; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 20: 10100 => 10101
        in = 5'b10100; expected = 5'b10101; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 21: 10101 => 10110
        in = 5'b10101; expected = 5'b10110; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 22: 10110 => 11000
        in = 5'b10110; expected = 5'b11000; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 23: 10111 => 01010
        in = 5'b10111; expected = 5'b01010; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 24: 11000 => 00101
        in = 5'b11000; expected = 5'b00101; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 25: 11001 => 01110
        in = 5'b11001; expected = 5'b01110; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 26: 11010 => 01001
        in = 5'b11010; expected = 5'b01001; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 27: 11011 => 10011
        in = 5'b11011; expected = 5'b10011; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 28: 11100 => 01000
        in = 5'b11100; expected = 5'b01000; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 29: 11101 => 00011
        in = 5'b11101; expected = 5'b00011; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 30: 11110 => 00111
        in = 5'b11110; expected = 5'b00111; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Test case 31: 11111 => 11101
        in = 5'b11111; expected = 5'b11101; #10;
        if (out !== expected) begin
            $display("%b | %b | %b    | FAIL", in, out, expected);
            errors = errors + 1;
        end else $display("%b | %b | %b    | PASS", in, out, expected);
        
        // Summary
        $display("----------------------------------------");
        if (errors == 0) begin
            $display("✓ ALL 32 TESTS PASSED!");
        end else begin
            $display("✗ FAILED: %0d/%0d tests failed", errors, 32);
        end
        $display("========================================");
        
        $finish;
    end
    
endmodule