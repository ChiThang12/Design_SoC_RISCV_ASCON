// ============================================================================
// Module: ASCON_PERMUTATION  (FIXED v2)
//
// BUG FIX 1 — round_counter khởi đầu sai (đã fix ở version trước):
//   p^8 : rounds 4..11  → round_counter bắt đầu tại 4   (FIX)
//   Fix: round_counter = 12 - rounds khi start_perm.
//
// BUG FIX 2 — 'rounds' input thay đổi giữa chừng (NEW FIX):
//   Vấn đề: 'rounds' là INPUT WIRE từ CONTROLLER combinational logic.
//   Tại S_AD_PERM_START: rounds=8, perm_start=1 → round_counter latched = 4  ✓
//   Tại S_AD_PERM_W:     rounds=12 (DEFAULT trong CONTROLLER!)
//   → Check "rounds_done + 1 == rounds" dùng rounds=12, không phải 8
//   → Perm chạy 12 vòng thay vì 8 (rounds 4..15 thay vì 4..11)
//   → Output SAI hoàn toàn.
//   → perm12 vô tình đúng vì default rounds=12 = số rounds cần chạy.
//
//   Fix: latch 'rounds' vào reg 'rounds_reg' khi start_perm,
//        dùng rounds_reg để kiểm tra done condition.
// ============================================================================

`include "ascon/rtl/PERMUTATION/ascon_CONSTANT_ADDITION.v"
`include "ascon/rtl/PERMUTATION/ascon_SUBTITUTION_LAYER.v"
`include "ascon/rtl/PERMUTATION/ascon_LINEAR_DIFFUSION.v"

module ascon_PERMUTATION (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [319:0] state_in,
    input  wire [3:0]   rounds,       // số rounds: 6, 8, hoặc 12
    input  wire         start_perm,
    input  wire         mode,         // 0: iterative (only mode supported)

    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    // ========================================================================
    // Internal signals
    // ========================================================================
    reg [319:0] current_state;
    reg [3:0]   round_counter;    // ABSOLUTE round index: (12-rounds)..15
    reg [3:0]   rounds_reg;       // FIX2: snapshot of 'rounds' at start_perm
    reg [3:0]   rounds_done;      // count of rounds executed
    reg         running;

    // Combinational round computation
    wire [63:0] x0 = current_state[319:256];
    wire [63:0] x1 = current_state[255:192];
    wire [63:0] x2 = current_state[191:128];
    wire [63:0] x3 = current_state[127:64];
    wire [63:0] x4 = current_state[63:0];

    wire [63:0] x2_const;
    wire [63:0] x0_sub, x1_sub, x2_sub, x3_sub, x4_sub;
    wire [63:0] x0_diff, x1_diff, x2_diff, x3_diff, x4_diff;

    // ========================================================================
    // Sub-modules
    // ========================================================================
    CONSTANT_ADDITION const_add (
        .state_x2         (x2),
        .round_number     (round_counter),
        .state_x2_modified(x2_const)
    );

    SUBSTITUTION_LAYER sub_layer (
        .x0_in(x0),     .x1_in(x1), .x2_in(x2_const),
        .x3_in(x3),     .x4_in(x4),
        .x0_out(x0_sub),.x1_out(x1_sub),.x2_out(x2_sub),
        .x3_out(x3_sub),.x4_out(x4_sub)
    );

    LINEAR_DIFFUSION diff_layer (
        .x0_in(x0_sub), .x1_in(x1_sub), .x2_in(x2_sub),
        .x3_in(x3_sub), .x4_in(x4_sub),
        .x0_out(x0_diff),.x1_out(x1_diff),.x2_out(x2_diff),
        .x3_out(x3_diff),.x4_out(x4_diff)
    );

    // ========================================================================
    // Control logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= 320'h0;
            round_counter <= 4'h0;
            rounds_reg    <= 4'h0;
            rounds_done   <= 4'h0;
            running       <= 1'b0;
            state_out     <= 320'h0;
            valid         <= 1'b0;
            done          <= 1'b0;
        end
        else begin
            valid <= 1'b0;
            done  <= 1'b0;

            if (start_perm && !running) begin
                current_state <= state_in;
                round_counter <= 4'd12 - rounds;   // FIX1: absolute start index
                rounds_reg    <= rounds;            // FIX2: snapshot rounds input
                rounds_done   <= 4'h0;
                running       <= 1'b1;
            end
            else if (running) begin
                current_state <= {x0_diff, x1_diff, x2_diff, x3_diff, x4_diff};
                round_counter <= round_counter + 1'b1;
                rounds_done   <= rounds_done + 1'b1;

                // FIX2: compare against rounds_reg (latched), NOT 'rounds' input
                if (rounds_done + 1'b1 == rounds_reg) begin
                    state_out <= {x0_diff, x1_diff, x2_diff, x3_diff, x4_diff};
                    valid     <= 1'b1;
                    done      <= 1'b1;
                    running   <= 1'b0;
                end
            end
        end
    end

endmodule