// ============================================================
// Module: ascon_STATE_REGISTER  (v3)
// Pure 320-bit register. The mux is entirely in ascon_CORE,
// which computes the correct data_in before asserting load.
// ============================================================
module ascon_STATE_REGISTER (
    input  wire         clk,
    input  wire         rst_n,

    // src_sel kept for port compatibility; actual mux is in CORE
    input  wire [1:0]   src_sel,
    input  wire         load,

    // All three driven by the same pre-muxed wire from CORE
    input  wire [319:0] init_state,
    input  wire [319:0] dp_state,
    input  wire [319:0] perm_state,

    output reg  [319:0] state_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_out <= 320'b0;
        else if (load) state_out <= init_state; // init_state = pre-muxed value from CORE
    end

endmodule