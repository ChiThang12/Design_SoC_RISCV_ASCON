// src/FA_Reg.v
// Module Top-level: Full Adder tuần tự (có register ở ngõ ra)

module FA_Reg (
    input wire clk,      // Xung Clock
    input wire rst_n,    // Reset tích cực mức thấp (Asynchronous)
    input wire a,        // Ngõ vào A
    input wire b,        // Ngõ vào B
    input wire cin,      // Ngõ vào Carry In
    output reg sum,      // Ngõ ra Sum (Sequential)
    output reg cout      // Ngõ ra Carry Out (Sequential)
);

    // -- 1. Logic Tổ Hợp (Combinational logic) --
    // Các dây nối tạm thời cho kết quả tổ hợp
    wire sum_comb;
    wire cout_comb;

    // Phép toán Full Adder
    assign sum_comb  = a ^ b ^ cin;
    assign cout_comb = (a & b) | (cin & (a ^ b));


    // -- 2. Logic Tuần Tự (Sequential logic) --
    // D-Flip-Flop để chốt dữ liệu ngõ ra
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset state: Ngõ ra về 0
            sum  <= 1'b0;
            cout <= 1'b0;
        end else begin
            // Chốt kết quả tổ hợp vào Flip-Flop tại cạnh lên clk
            sum  <= sum_comb;
            cout <= cout_comb;
        end
    end

endmodule
