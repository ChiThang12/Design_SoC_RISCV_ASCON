// ============================================================================
// ALU.v - RISC-V Arithmetic Logic Unit (RV32IM)
// ============================================================================
// Mô tả:
//   - Thực hiện các phép toán số học, logic, dịch bit, so sánh, nhân và chia
//   - Hỗ trợ tập lệnh: RV32I (Integer) + RV32M (Multiply/Divide)
//
// Tác giả: 
// Ngày: 
// ============================================================================

module alu (
    input  wire [31:0] in1,              // Toán hạng 1 (operand A)
    input  wire [31:0] in2,              // Toán hạng 2 (operand B)
    input  wire [3:0]  alu_control,      // Mã điều khiển xác định phép toán

    output reg  [31:0] alu_result,       // Kết quả đầu ra của ALU
    output wire         zero_flag,       // Cờ báo: kết quả = 0
    output wire         less_than,       // Cờ báo: in1 < in2 (signed)
    output wire         less_than_u      // Cờ báo: in1 < in2 (unsigned)
);

    // ========================================================================
    // 1. Mã điều khiển cho các phép toán ALU
    // ========================================================================
    localparam [3:0]
        ALU_ADD   = 4'b0000,    // Cộng:            in1 + in2
        ALU_SUB   = 4'b0001,    // Trừ:             in1 - in2
        ALU_AND   = 4'b0010,    // AND:             in1 & in2
        ALU_OR    = 4'b0011,    // OR:              in1 | in2
        ALU_XOR   = 4'b0100,    // XOR:             in1 ^ in2
        ALU_SLL   = 4'b0101,    // Dịch trái logic: in1 << in2[4:0]
        ALU_SRL   = 4'b0110,    // Dịch phải logic: in1 >> in2[4:0]
        ALU_SRA   = 4'b0111,    // Dịch phải có dấu: in1 >>> in2[4:0]
        ALU_SLT   = 4'b1000,    // So sánh có dấu:  (in1 < in2) ? 1 : 0
        ALU_SLTU  = 4'b1001,    // So sánh không dấu
        ALU_MUL   = 4'b1010,    // Nhân 32-bit thấp (signed)
        ALU_MULH  = 4'b1011,    // Nhân 32-bit cao (signed)
        ALU_DIV   = 4'b1100,    // Chia có dấu
        ALU_DIVU  = 4'b1101,    // Chia không dấu
        ALU_REM   = 4'b1110,    // Lấy dư có dấu
        ALU_REMU  = 4'b1111;    // Lấy dư không dấu

    // ========================================================================
    // 2. Khai báo biến trung gian cho phép nhân (64-bit)
    // ========================================================================
    wire signed [63:0] mul_result_signed;    // Kết quả nhân có dấu
    wire        [63:0] mul_result_unsigned;  // Kết quả nhân không dấu

    // Chuyển kiểu sang signed để xử lý phép toán có dấu
    wire signed [31:0] in1_signed = $signed(in1);
    wire signed [31:0] in2_signed = $signed(in2);

    // Tính kết quả nhân (có và không dấu)
    assign mul_result_signed   = in1_signed * in2_signed;
    assign mul_result_unsigned = in1 * in2;

    // ========================================================================
    // 3. Khối xử lý chính - ALU Operations
    // ========================================================================
    always @(*) begin
        case (alu_control)

            // ------------------- RV32I: Phép toán số học ---------------------
            ALU_ADD:  alu_result = in1 + in2;           // Cộng
            ALU_SUB:  alu_result = in1 - in2;           // Trừ

            // ------------------- RV32I: Phép toán logic ---------------------
            ALU_AND:  alu_result = in1 & in2;           // AND
            ALU_OR:   alu_result = in1 | in2;           // OR
            ALU_XOR:  alu_result = in1 ^ in2;           // XOR

            // ------------------- RV32I: Phép dịch bit -----------------------
            ALU_SLL:  alu_result = in1 << in2[4:0];     // Dịch trái logic
            ALU_SRL:  alu_result = in1 >> in2[4:0];     // Dịch phải logic
            ALU_SRA:  alu_result = $signed(in1) >>> in2[4:0]; // Dịch phải có dấu

            // ------------------- RV32I: Phép so sánh ------------------------
            ALU_SLT:  alu_result = (in1_signed < in2_signed) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_result = (in1 < in2) ? 32'd1 : 32'd0;

            // ------------------- RV32M: Phép nhân ---------------------------
            ALU_MUL:  alu_result = mul_result_signed[31:0];   // Lấy 32-bit thấp
            ALU_MULH: alu_result = mul_result_signed[63:32];  // Lấy 32-bit cao

            // ------------------- RV32M: Phép chia có dấu --------------------
            // ALU_DIV: begin
            //     if (in2 == 32'd0)
            //         alu_result = 32'hFFFFFFFF; // Chia cho 0 -> -1 (theo spec)
            //     else if (in1 == 32'h80000000 && in2 == 32'hFFFFFFFF)
            //         alu_result = 32'h80000000; // Trường hợp overflow đặc biệt
            //     else
            //         alu_result = $signed(in1) / $signed(in2);
            // end

            // // ------------------- RV32M: Lấy dư có dấu -----------------------
            // ALU_REM: begin
            //     if (in2 == 32'd0)
            //         alu_result = in1;          // Chia 0 -> trả về dividend
            //     else if (in1 == 32'h80000000 && in2 == 32'hFFFFFFFF)
            //         alu_result = 32'd0;        // Overflow -> dư = 0
            //     else
            //         alu_result = $signed(in1) % $signed(in2);
            // end

            // // ------------------- RV32M: Phép chia không dấu -----------------
            // ALU_DIVU: begin
            //     if (in2 == 32'd0)
            //         alu_result = 32'hFFFFFFFF; // Chia 0 -> trả về 2^32-1
            //     else
            //         alu_result = in1 / in2;
            // end

            // ------------------- RV32M: Lấy dư không dấu --------------------
            // ALU_REMU: begin
            //     if (in2 == 32'd0)
            //         alu_result = in1;          // Chia 0 -> trả về dividend
            //     else
            //         alu_result = in1 % in2;
                
            //     alu_result = 32'd0;
            // end

            // ------------------- Mặc định -----------------------------------
            default:  alu_result = 32'd0;
        endcase
    end

    // ========================================================================
    // 4. Các tín hiệu cờ (flags)
    // ========================================================================
    assign zero_flag   = (alu_result == 32'd0);   // Kết quả bằng 0
    assign less_than   = (in1_signed < in2_signed); // So sánh signed
    assign less_than_u = (in1 < in2);               // So sánh unsigned

endmodule
