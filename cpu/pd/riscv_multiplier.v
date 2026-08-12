`timescale 1ns/1ps

// ============================================================================
// riscv_multiplier.v — 2-stage Pipelined Multiplier for RV32M
// ============================================================================
// Supports MUL, MULH, MULHSU, MULHU via mul_op_i encoding.
// Pipeline: operands latch at E1 → 33×33 signed multiply (combinational)
//           → result register at E2 = writeback_value_o.
//
// Timing: result valid 2 cycles after mul_valid_i pulse.
// hold_i (= stall_any) freezes both pipeline stages.
// ============================================================================

module riscv_multiplier (
    input           clk_i,
    input           rst_i,

    // Dispatch: high for exactly 1 cycle when MUL instruction enters EX
    // (must not be asserted when stall_any is high)
    input           mul_valid_i,

    // Operation select: 00=MUL, 01=MULH, 10=MULHSU, 11=MULHU
    input  [1:0]    mul_op_i,

    input  [31:0]   operand_a_i,     // rs1 (forwarded)
    input  [31:0]   operand_b_i,     // rs2 (forwarded)

    // Freeze both pipeline stages when CPU is stalled
    input           hold_i,

    output [31:0]   writeback_value_o
);

    // ========================================================================
    // E1: Sign-extend operands and latch
    // ========================================================================
    reg  [32:0] operand_a_e1_q;
    reg  [32:0] operand_b_e1_q;
    reg         mulhi_sel_e1_q;

    reg  [32:0] operand_a_r;
    reg  [32:0] operand_b_r;

    // Sign-extend based on operation type
    always @* begin
        case (mul_op_i)
            2'b01,          // MULH:   signed A × signed B
            2'b10:          // MULHSU: signed A × unsigned B
                operand_a_r = {operand_a_i[31], operand_a_i};
            default:        // MUL / MULHU: unsigned A
                operand_a_r = {1'b0, operand_a_i};
        endcase
    end

    always @* begin
        case (mul_op_i)
            2'b01:          // MULH: signed B
                operand_b_r = {operand_b_i[31], operand_b_i};
            default:        // MUL / MULHSU / MULHU: unsigned B
                operand_b_r = {1'b0, operand_b_i};
        endcase
    end

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            operand_a_e1_q <= 33'b0;
            operand_b_e1_q <= 33'b0;
            mulhi_sel_e1_q <= 1'b0;
        end else if (!hold_i) begin
            if (mul_valid_i) begin
                operand_a_e1_q <= operand_a_r;
                operand_b_e1_q <= operand_b_r;
                mulhi_sel_e1_q <= (mul_op_i != 2'b00); // high for MULH/MULHSU/MULHU
            end else begin
                operand_a_e1_q <= 33'b0;
                operand_b_e1_q <= 33'b0;
                mulhi_sel_e1_q <= 1'b0;
            end
        end
    end

    // ========================================================================
    // E1→E2: 33×33 signed multiply (combinational)
    // ========================================================================
    wire [64:0] mult_result_w = {{32{operand_a_e1_q[32]}}, operand_a_e1_q}
                              * {{32{operand_b_e1_q[32]}}, operand_b_e1_q};

    wire [31:0] result_r = mulhi_sel_e1_q ? mult_result_w[63:32]
                                           : mult_result_w[31:0];

    // ========================================================================
    // E2: Output register
    // ========================================================================
    reg [31:0] result_e2_q;

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            result_e2_q <= 32'b0;
        else if (!hold_i)
            result_e2_q <= result_r;
    end

    assign writeback_value_o = result_e2_q;

endmodule
