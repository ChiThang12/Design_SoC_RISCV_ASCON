// ============================================================
// Module: ascon_PERMUTATION_PIPE2
//
// Pipelined Ascon permutation — 2 rounds per clock cycle.
//
// Architecture:
//   - 6 pipeline stages (supports p6/p8/p12).
//   - Each stage: 2 × ascon_ROUND_STAGE (combinational) + output register.
//   - A 6-bit valid shift-register tracks which stage holds live data.
//   - 'rounds' is latched at start_perm to prevent the bug in the
//     original iterative version (controller changes 'rounds' mid-perm).
//
// Latency (cycles after start_perm):
//   p12 (rounds=12) → 6 cycles
//   p8  (rounds= 8) → 4 cycles
//   p6  (rounds= 6) → 3 cycles
//
// Cycle timing for p8 (stages=4):
//   Cycle 0: start_perm=1  → pipe_reg[0] ← state_in,  valid_sr = 000001
//   Cycle 1:                  pipe_reg[1] ← wire_out[0], valid_sr = 000010
//   Cycle 2:                  pipe_reg[2] ← wire_out[1], valid_sr = 000100
//   Cycle 3:                  pipe_reg[3] ← wire_out[2], valid_sr = 001000
//   Cycle 4: done=1, valid=1  state_out   ← wire_out[3], valid_sr = 010000
//
// Drop-in replacement for ascon_PERMUTATION (identical port list).
// Only change needed in ascon_CORE.v: swap the instance name.
// ============================================================
`include "ascon_accelerator/rtl/PERMUTATION/ascon_ROUND_STAGE.v"

module ascon_PERMUTATION_PIPE2 (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [319:0] state_in,
    input  wire [3:0]   rounds,       // 6, 8, or 12 (always even)
    input  wire         start_perm,
    input  wire         mode,         // unused — kept for port compatibility

    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    // ----------------------------------------------------------------
    // MAX_STAGES = 6 supports p12 (12 rounds / 2 per stage)
    // ----------------------------------------------------------------
    localparam integer MAX_STAGES = 6;

    // ----------------------------------------------------------------
    // Pipeline state
    // ----------------------------------------------------------------
    reg [319:0] pipe_reg         [0:MAX_STAGES-1]; // input register of each stage
    reg [3:0]   stage_rbase      [0:MAX_STAGES-1]; // absolute round index for round-0 of stage s
    reg [5:0]   valid_sr;                           // valid_sr[s]=1: pipe_reg[s] holds live data
    reg [3:0]   rounds_reg;                         // latched rounds (prevents bug if input changes)
    reg [2:0]   stages_reg;                         // rounds_reg / 2

    // ----------------------------------------------------------------
    // Combinational wires between round stages
    //   wire_mid[s] : output of round-0 of stage s (input to round-1)
    //   wire_out[s] : output of round-1 of stage s (result of stage s)
    // ----------------------------------------------------------------
    wire [319:0] wire_mid [0:MAX_STAGES-1];
    wire [319:0] wire_out [0:MAX_STAGES-1];

    // ----------------------------------------------------------------
    // Generate 6 pipeline stages
    // ----------------------------------------------------------------
    genvar s;
    generate
        for (s = 0; s < MAX_STAGES; s = s + 1) begin : pipe_stages
            // Round 0 of stage s
            ascon_ROUND_STAGE u_r0 (
                .state_in  (pipe_reg[s]),
                .round_idx (stage_rbase[s]),
                .state_out (wire_mid[s])
            );
            // Round 1 of stage s (round_idx = rbase + 1)
            ascon_ROUND_STAGE u_r1 (
                .state_in  (wire_mid[s]),
                .round_idx (stage_rbase[s] + 4'd1),
                .state_out (wire_out[s])
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // Output mux: wire_out of the last active stage
    //   stages_reg-1 is the index of the last active stage
    // ----------------------------------------------------------------
    reg [319:0] final_out;
    always @(*) begin
        case (stages_reg)
            3'd1:    final_out = wire_out[0];
            3'd2:    final_out = wire_out[1];
            3'd3:    final_out = wire_out[2];
            3'd4:    final_out = wire_out[3];
            3'd5:    final_out = wire_out[4];
            default: final_out = wire_out[5];   // 3'd6 and fallback
        endcase
    end

    // ----------------------------------------------------------------
    // Sequential: pipeline registers, valid shift, done detection
    // ----------------------------------------------------------------
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_sr   <= 6'h0;
            valid      <= 1'b0;
            done       <= 1'b0;
            state_out  <= 320'h0;
            rounds_reg <= 4'h0;
            stages_reg <= 3'h0;
            for (j = 0; j < MAX_STAGES; j = j + 1) begin
                pipe_reg[j]    <= 320'h0;
                stage_rbase[j] <= 4'h0;
            end
        end
        else begin
            // Default: single-cycle pulse outputs deasserted
            valid <= 1'b0;
            done  <= 1'b0;

            if (start_perm) begin
                // ---- Latch configuration ----
                rounds_reg <= rounds;
                stages_reg <= rounds[3:1];          // rounds/2

                // ---- Stage 0 input register ----
                pipe_reg[0] <= state_in;

                // ---- Pre-compute absolute round base for each stage ----
                // stage s processes rounds: (12-rounds+2s) and (12-rounds+2s+1)
                stage_rbase[0] <= 4'd12 - rounds;
                stage_rbase[1] <= 4'd12 - rounds + 4'd2;
                stage_rbase[2] <= 4'd12 - rounds + 4'd4;
                stage_rbase[3] <= 4'd12 - rounds + 4'd6;
                stage_rbase[4] <= 4'd12 - rounds + 4'd8;
                stage_rbase[5] <= 4'd12 - rounds + 4'd10;

                // ---- Kick valid shift register ----
                valid_sr <= 6'b000001;
            end
            else begin
                // ---- Propagate pipeline registers ----
                // pipe_reg[j] captures wire_out[j-1] when stage j-1 is valid.
                // Non-blocking reads: valid_sr on RHS is the OLD (pre-shift) value.
                for (j = 1; j < MAX_STAGES; j = j + 1) begin
                    if (valid_sr[j-1])
                        pipe_reg[j] <= wire_out[j-1];
                end

                // ---- Shift valid token left (stage s → stage s+1) ----
                valid_sr <= {valid_sr[MAX_STAGES-2:0], 1'b0};

                // ---- Done detection (uses pre-shift valid_sr via NBA read) ----
                // When valid_sr[stages_reg-1] is 1, wire_out[stages_reg-1] is
                // combinationally valid this cycle — capture it.
                case (stages_reg)
                    3'd1: if (valid_sr[0]) begin state_out<=final_out; valid<=1'b1; done<=1'b1; end
                    3'd2: if (valid_sr[1]) begin state_out<=final_out; valid<=1'b1; done<=1'b1; end
                    3'd3: if (valid_sr[2]) begin state_out<=final_out; valid<=1'b1; done<=1'b1; end
                    3'd4: if (valid_sr[3]) begin state_out<=final_out; valid<=1'b1; done<=1'b1; end
                    3'd5: if (valid_sr[4]) begin state_out<=final_out; valid<=1'b1; done<=1'b1; end
                    3'd6: if (valid_sr[5]) begin state_out<=final_out; valid<=1'b1; done<=1'b1; end
                    default: ;
                endcase
            end
        end
    end

endmodule