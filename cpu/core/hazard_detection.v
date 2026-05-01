module hazard_detection (
    input wire        clk,
    input wire        rst,

    input wire        memread_id_ex,
    input wire [4:0]  rd_id_ex,
    input wire [4:0]  rs1_id,
    input wire [4:0]  rs2_id,
    input wire        rs1_used_id,
    input wire        rs2_used_id,

    input wire        branch_taken,
    input wire        imem_ready,
    input wire [31:0] lsu_scoreboard,
    input wire        mem_stage_pending,
    input wire        memread_mem_stage,
    input wire [4:0]  rd_mem_stage,

    input wire        fence_id,
    input wire        lsu_idle,

    // MUL in EX: result ready 2 cycles later (same as load-use pattern)
    input wire        mul_in_ex,

    // Static backward branch prediction signals (Fix 9)
    input wire        predict_taken_ex,
    input wire        predict_taken_id,
    input wire        mispredict_ex,

    output wire       stall,
    output wire       stall_if,
    output wire       flush_if_id,
    output wire       flush_id_ex,
    output wire       fence_stall,
    output wire       lsu_dep_stall,
    output wire       mul_ex_stall
);

    wire load_use_hazard;
    assign load_use_hazard = memread_id_ex &&
                             (rd_id_ex != 5'b0) &&
                             ((rs1_used_id && (rd_id_ex == rs1_id)) ||
                              (rs2_used_id && (rd_id_ex == rs2_id)));

    wire lsu_dependency_stall;
    assign lsu_dependency_stall = (rs1_used_id && (rs1_id != 5'b0) && lsu_scoreboard[rs1_id]) ||
                                  (rs2_used_id && (rs2_id != 5'b0) && lsu_scoreboard[rs2_id]);

    // Close the 1-cycle gap between EX load-use stall and LSU scoreboard set.
    wire mem_load_issue_hazard;
    assign mem_load_issue_hazard = mem_stage_pending &&
                                   memread_mem_stage &&
                                   (rd_mem_stage != 5'b0) &&
                                   ((rs1_used_id && (rd_mem_stage == rs1_id)) ||
                                    (rs2_used_id && (rd_mem_stage == rs2_id)));
    assign lsu_dep_stall = lsu_dependency_stall || mem_load_issue_hazard;

    wire imem_stall;
    assign imem_stall = !imem_ready;

    assign fence_stall = fence_id && (!lsu_idle || mem_stage_pending);

    // MUL result stall: stall 1 cycle if instruction after MUL reads MUL destination
    wire mul_result_stall;
    assign mul_result_stall = mul_in_ex &&
                              (rd_id_ex != 5'b0) &&
                              ((rs1_used_id && (rs1_id != 5'b0) && (rs1_id == rd_id_ex)) ||
                               (rs2_used_id && (rs2_id != 5'b0) && (rs2_id == rd_id_ex)));

    // mul_ex_stall: hold pipeline 1 extra cycle when MUL first enters EX (Fix 10B)
    // Allows E1.5 partial-product stage to compute before E2 captures result.
    reg mul_ex_stall_done_r;
    always @(posedge clk or posedge rst) begin
        if (rst)             mul_ex_stall_done_r <= 1'b0;
        else if (!mul_in_ex) mul_ex_stall_done_r <= 1'b0;
        else                 mul_ex_stall_done_r <= 1'b1;
    end
    assign mul_ex_stall = mul_in_ex && !mul_ex_stall_done_r;

    assign stall    = load_use_hazard || lsu_dep_stall || fence_stall || mul_result_stall || mul_ex_stall;
    assign stall_if = imem_stall;

    // Fix 9B: prediction-aware flush
    // Correctly-predicted taken branch: no IF/ID flush (prediction already redirected IFU)
    // Mispredicted (predicted taken but actually not): flush IF+ID, redirect to fall-through
    // New backward branch predicted taken in ID: flush IF/ID, redirect IFU to target
    assign flush_if_id = (branch_taken && !predict_taken_ex) || mispredict_ex || predict_taken_id;
    assign flush_id_ex = load_use_hazard || (branch_taken && !predict_taken_ex) || mispredict_ex || fence_stall || mul_result_stall;

endmodule
