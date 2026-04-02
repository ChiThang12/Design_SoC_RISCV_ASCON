// ============================================================================
// tb_debug.v — Debug Testbench for RISC-V SoC ASCON
//
// Mô tả: Load program.hex, chạy simulation với detailed logging
// để debug crash và ASCON issues.
//
// Cách dùng:
//   1. Compile firmware: ./compile_c_to_hex.sh
//   2. Run: iverilog -o tb_debug.vvp tb_debug.v soc_top.v [other files]
//   3. ./tb_debug.vvp
// ============================================================================

`timescale 1ns / 1ps
`include "soc_top.v"  // Giả sử soc_top.v là top module của SoC
module tb_debug;

    // Clock and reset
    reg clk = 0;
    reg rst_n = 0;

    // UART output capture
    wire uart_tx;

    // SoC instance (giả sử soc_top là top module)
    soc_top u_soc (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_tx (uart_tx)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Reset sequence
    initial begin
        $display("TB: Starting simulation");
        rst_n = 0;
        #100;
        rst_n = 1;
        $display("TB: Reset released");
    end

    // UART monitor
    reg [7:0] uart_byte;
    reg uart_valid = 0;
    integer uart_bit_cnt = 0;
    reg [31:0] uart_shift_reg;

    always @(posedge clk) begin
        if (uart_tx == 0) begin  // Start bit
            uart_bit_cnt <= 1;
            uart_shift_reg <= 0;
        end else if (uart_bit_cnt > 0 && uart_bit_cnt < 9) begin
            uart_shift_reg <= {uart_tx, uart_shift_reg[31:1]};
            uart_bit_cnt <= uart_bit_cnt + 1;
        end else if (uart_bit_cnt == 9) begin
            uart_byte <= uart_shift_reg[7:0];
            uart_valid <= 1;
            uart_bit_cnt <= 0;
            $write("%c", uart_shift_reg[7:0]);
        end else begin
            uart_valid <= 0;
        end
    end

    // Simulation control
    initial begin
        #1000000;  // Run for 1ms
        $display("TB: Timeout - stopping simulation");
        $finish;
    end

    // Monitor PC and ra
    always @(posedge clk) begin
        if (u_soc.u_cpu.pc != 0) begin
            $display("TB: PC = %h, ra = %h", u_soc.u_cpu.pc, u_soc.u_cpu.ra);
        end
    end

endmodule