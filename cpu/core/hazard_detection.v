module hazard_detection (
    input wire        memread_id_ex,
    input wire [4:0]  rd_id_ex,
    input wire [4:0]  rs1_id,
    input wire [4:0]  rs2_id,

    input wire        memread_mem,
    input wire [4:0]  rd_mem,

    input wire        branch_taken,
    input wire        imem_ready,
    input wire [31:0] lsu_scoreboard,

    input wire        fence_id,
    input wire        lsu_idle,

    output wire       stall,
    output wire       stall_if,
    output wire       flush_if_id,
    output wire       flush_id_ex,
    output wire       fence_stall
);

    wire load_use_hazard;
    assign load_use_hazard = memread_id_ex &&
                             (rd_id_ex != 5'b0) &&
                             ((rd_id_ex == rs1_id) || (rd_id_ex == rs2_id));

    wire mem_load_stall;
    assign mem_load_stall = memread_mem &&
                            (rd_mem != 5'b0) &&
                            ((rd_mem == rs1_id) || (rd_mem == rs2_id));

    wire lsu_dependency_stall;
    assign lsu_dependency_stall = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                                  (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);

    wire imem_stall;
    assign imem_stall = !imem_ready;

    // fence_stall: giữ pipeline khi FENCE ở ID cho đến khi LSU hoàn toàn idle
    // (store buffer rỗng, load queue rỗng, không có in-flight transaction)
    assign fence_stall = fence_id && !lsu_idle;

    assign stall    = load_use_hazard || mem_load_stall || lsu_dependency_stall || fence_stall;
    assign stall_if = imem_stall;

    assign flush_if_id = branch_taken;
    // [FIX-BUG-FLUSH] Thêm mem_load_stall vào flush_id_ex.
    // mem_load_stall stall pipeline nhưng không insert NOP vào EX:
    //   - Load đang ở MEM stage (memread_mem=1), instruction tiếp trong ID
    //     cần rd đó → stall=1, nhưng flush_id_ex=0 → instruction ở EX
    //     execute với operand chưa forward → kết quả sai vào MEM.
    // Với LSU scoreboard: scoreboard set khi load vào LQ, nên
    // lsu_dependency_stall cũng sẽ fire, nhưng flush vẫn cần thiết
    // để insert bubble đúng vị trí trong pipeline.
    assign flush_id_ex = load_use_hazard || mem_load_stall || branch_taken || fence_stall;

endmodule