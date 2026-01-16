// ============================================================================
// Module TOP: ASCON_PERMUTATION
// Mô tả: Thực hiện permutation p^a hoặc p^b
// Hỗ trợ cả chế độ pipelined và iterative
// ============================================================================
`include "ascon_CONSTANT_ADDITION.v"
`include "ascon_SUBTITUTION_LAYER.v"
`include "ascon_LINEAR_DIFFUSION.v"

module ASCON_PERMUTATION (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [319:0] state_in,
    input  wire [3:0]   rounds,
    input  wire         start_perm,
    input  wire         mode,        // 0: iterative, 1: pipelined
    
    output reg  [319:0] state_out,
    output reg          valid,
    output reg          done
);

    // ========================================================================
    // Internal signals
    // ========================================================================
    reg [319:0] current_state;
    reg [3:0]   round_counter;
    reg         running;
    
    // Wires for current round computation
    wire [63:0] x0, x1, x2, x3, x4;
    wire [63:0] x2_const;
    wire [63:0] x0_sub, x1_sub, x2_sub, x3_sub, x4_sub;
    wire [63:0] x0_diff, x1_diff, x2_diff, x3_diff, x4_diff;
    
    // Extract words from current state
    assign x0 = current_state[319:256];
    assign x1 = current_state[255:192];
    assign x2 = current_state[191:128];
    assign x3 = current_state[127:64];
    assign x4 = current_state[63:0];
    
    // ========================================================================
    // Instantiate sub-modules
    // ========================================================================
    
    // Constant Addition
    CONSTANT_ADDITION const_add (
        .state_x2(x2),
        .round_number(round_counter),
        .state_x2_modified(x2_const)
    );
    
    // Substitution Layer
    SUBSTITUTION_LAYER sub_layer (
        .x0_in(x0),
        .x1_in(x1),
        .x2_in(x2_const),
        .x3_in(x3),
        .x4_in(x4),
        .x0_out(x0_sub),
        .x1_out(x1_sub),
        .x2_out(x2_sub),
        .x3_out(x3_sub),
        .x4_out(x4_sub)
    );
    
    // Linear Diffusion
    LINEAR_DIFFUSION diff_layer (
        .x0_in(x0_sub),
        .x1_in(x1_sub),
        .x2_in(x2_sub),
        .x3_in(x3_sub),
        .x4_in(x4_sub),
        .x0_out(x0_diff),
        .x1_out(x1_diff),
        .x2_out(x2_diff),
        .x3_out(x3_diff),
        .x4_out(x4_diff)
    );
    
    // ========================================================================
    // Control Logic - Iterative Mode
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= 320'h0;
            round_counter <= 4'h0;
            running <= 1'b0;
            state_out <= 320'h0;
            valid <= 1'b0;
            done <= 1'b0;
        end
        else begin
            // Default: deassert control signals
            valid <= 1'b0;
            done <= 1'b0;
            
            if (start_perm && !running) begin
                // Start new permutation
                current_state <= state_in;
                round_counter <= 4'h0;
                running <= 1'b1;
            end
            else if (running) begin
                if (round_counter < rounds) begin
                    // Perform one round
                    current_state <= {x0_diff, x1_diff, x2_diff, x3_diff, x4_diff};
                    round_counter <= round_counter + 1'b1;
                    
                    // Check if this is the last round
                    if (round_counter + 1'b1 == rounds) begin
                        state_out <= {x0_diff, x1_diff, x2_diff, x3_diff, x4_diff};
                        valid <= 1'b1;
                        done <= 1'b1;
                        running <= 1'b0;
                    end
                end
            end
        end
    end
    
    // Note: Pipelined mode would require a different architecture
    // with pipeline registers between stages. This implementation
    // focuses on the iterative mode which is more area-efficient.

endmodule