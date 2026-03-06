// ============================================================================
// axi4_addr_decoder.v
// Giải mã địa chỉ AXI4 → chỉ số slave (0..NUM_SLAVES-1) hoặc NUM_SLAVES=DECERR
//
// Cách dùng: instantiate trong axi4_crossbar, dùng cho cả AR và AW channel.
// Logic: slave[i] được chọn khi (addr & SLAVE_MASK[i]) == SLAVE_BASE[i]
// ============================================================================

module axi4_addr_decoder #(
    parameter NUM_SLAVES  = 4,
    parameter ADDR_WIDTH  = 32,
    // Địa chỉ base và mask cho mỗi slave
    parameter [ADDR_WIDTH-1:0] S0_BASE = 32'h0000_0000,
    parameter [ADDR_WIDTH-1:0] S0_MASK = 32'hFFFF_0000,
    parameter [ADDR_WIDTH-1:0] S1_BASE = 32'h1000_0000,
    parameter [ADDR_WIDTH-1:0] S1_MASK = 32'hFFFF_0000,
    parameter [ADDR_WIDTH-1:0] S2_BASE = 32'h2000_0000,
    parameter [ADDR_WIDTH-1:0] S2_MASK = 32'hFFFF_F000,
    parameter [ADDR_WIDTH-1:0] S3_BASE = 32'h3000_0000,
    parameter [ADDR_WIDTH-1:0] S3_MASK = 32'hFFFF_F000
)(
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [2:0]            slave_sel   // 0-3: slave index, NUM_SLAVES=4: DECERR
);

    always @(*) begin
        // Default: không ánh xạ → DECERR
        slave_sel = NUM_SLAVES[2:0];

        if ((addr & S3_MASK) == S3_BASE)
            slave_sel = 3'd3;
        else if ((addr & S2_MASK) == S2_BASE)
            slave_sel = 3'd2;
        else if ((addr & S1_MASK) == S1_BASE)
            slave_sel = 3'd1;
        else if ((addr & S0_MASK) == S0_BASE)
            slave_sel = 3'd0;
    end

endmodule