module CONSTANT_ADDITION (
    input  wire [63:0] state_x2,
    input  wire [3:0]  round_number,
    output wire [63:0] state_x2_modified
);

    wire [7:0] round_constant;
    
    // Tính constant: 0xF0 - round*0x0F
    assign round_constant = 8'hF0 - (round_number * 4'hF);
    
    // XOR constant vào 8 bit thấp của x2
    assign state_x2_modified = state_x2 ^ {56'h0, round_constant};

endmodule
