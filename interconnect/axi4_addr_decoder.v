// ============================================================================
// axi4_addr_decoder.v
// [Fix 6] Mở rộng lên 12 slave: S9=PLIC, S10=OTP, S11=DMA_CTRL
//         slave_sel 4-bit (0-11=slave, 12=DECERR)
// ============================================================================

module axi4_addr_decoder #(
    parameter NUM_SLAVES  = 12,
    parameter ADDR_WIDTH  = 32,
    parameter [ADDR_WIDTH-1:0] S0_BASE  = 32'h0000_0000, parameter [ADDR_WIDTH-1:0] S0_MASK  = 32'hFFFF_E000,
    parameter [ADDR_WIDTH-1:0] S1_BASE  = 32'h1000_0000, parameter [ADDR_WIDTH-1:0] S1_MASK  = 32'hFFFF_E000,
    parameter [ADDR_WIDTH-1:0] S2_BASE  = 32'h2000_0000, parameter [ADDR_WIDTH-1:0] S2_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S3_BASE  = 32'h3000_0000, parameter [ADDR_WIDTH-1:0] S3_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S4_BASE  = 32'h4000_0000, parameter [ADDR_WIDTH-1:0] S4_MASK  = 32'hFFFF_0000,
    parameter [ADDR_WIDTH-1:0] S5_BASE  = 32'h5000_0000, parameter [ADDR_WIDTH-1:0] S5_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S6_BASE  = 32'h5001_0000, parameter [ADDR_WIDTH-1:0] S6_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S7_BASE  = 32'h5002_0000, parameter [ADDR_WIDTH-1:0] S7_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S8_BASE  = 32'h5003_0000, parameter [ADDR_WIDTH-1:0] S8_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S9_BASE  = 32'h5004_0000, parameter [ADDR_WIDTH-1:0] S9_MASK  = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S10_BASE = 32'h6000_0000, parameter [ADDR_WIDTH-1:0] S10_MASK = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S11_BASE = 32'h6001_0000, parameter [ADDR_WIDTH-1:0] S11_MASK = 32'hFFFF_F000
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [3:0]            slave_sel   // 0-11=slave, 12=DECERR
);

    always @(*) begin
        slave_sel = NUM_SLAVES[3:0]; // default DECERR
        if      ((addr & S11_MASK) == S11_BASE) slave_sel = 4'd11;
        else if ((addr & S10_MASK) == S10_BASE) slave_sel = 4'd10;
        else if ((addr & S9_MASK)  == S9_BASE)  slave_sel = 4'd9;
        else if ((addr & S8_MASK)  == S8_BASE)  slave_sel = 4'd8;
        else if ((addr & S7_MASK)  == S7_BASE)  slave_sel = 4'd7;
        else if ((addr & S6_MASK)  == S6_BASE)  slave_sel = 4'd6;
        else if ((addr & S5_MASK)  == S5_BASE)  slave_sel = 4'd5;
        else if ((addr & S4_MASK)  == S4_BASE)  slave_sel = 4'd4;
        else if ((addr & S3_MASK)  == S3_BASE)  slave_sel = 4'd3;
        else if ((addr & S2_MASK)  == S2_BASE)  slave_sel = 4'd2;
        else if ((addr & S1_MASK)  == S1_BASE)  slave_sel = 4'd1;
        else if ((addr & S0_MASK)  == S0_BASE)  slave_sel = 4'd0;
    end

endmodule