// ============================================================================
// hazard_detection.v - Fixed v3
// ============================================================================
// FIX LOG v3:
//   BUG #4 FIX: mem_load_stall — 1-cycle gap giữa load_use_hazard và scoreboard
//
//   Vấn đề:
//     Cycle C:   LW ở EX → load_use_hazard=1 → stall=1, flush_id_ex=1
//                ADDI ở ID → bị hold (stall=1)
//                posedge C: ID/EX flushed (bubble), EX/MEM advances (LW captured)
//
//     Cycle C+1: LW ở MEM, bubble ở EX
//                load_use_hazard=0 (bubble in EX), scoreboard[x2]=0 (not set yet!)
//                → stall=0 → ADDI slips into EX with stale x2=0 !
//                → lsu_req_valid=1 → scoreboard[x2]←1 at posedge C+1
//                → Too late: ADDI already latched x2=0 into ID/EX
//
//   Nguyên nhân: scoreboard set tại posedge của cycle LW ở MEM,
//                nhưng trước posedge đó stall đã=0 → ADDI vào EX.
//                Có 1-cycle window không được bảo vệ bởi hazard nào.
//
//   FIX MỚI: Thêm mem_load_stall:
//     Khi LW ở MEM stage (memread_mem=1) và rd_mem match rs1/rs2 ở ID
//     → stall=1, giữ ADDI ở ID thêm 1 cycle
//     → Cycle C+1: scoreboard[x2] được set tại posedge
//     → Cycle C+2: lsu_dependency_stall=1 → tiếp tục stall cho đến khi
//                  LSU hoàn thành và scoreboard clear
//     → Không còn window hở
//
//   Tại sao chỉ 1 cycle gap?
//     - load_use_hazard (EX stage) → flush + stall → bubble vào EX
//     - Cycle sau: bubble ở EX → load_use=0
//     - scoreboard set cùng posedge LW gửi req → effective cycle sau
//     - → Gap 1 cycle giữa load_use=0 và scoreboard=1
//     - mem_load_stall lấp gap này bằng cách detect LW ở MEM stage trực tiếp
//
//   BUG #3 FIX (v2, giữ nguyên):
//     Tách stall và stall_if để ICache miss không freeze toàn pipeline.
// ============================================================================

module hazard_detection (
    // Load-use hazard detection (EX stage load)
    input wire        memread_id_ex,    // EX stage is doing load
    input wire [4:0]  rd_id_ex,         // EX stage destination register
    input wire [4:0]  rs1_id,           // ID stage source 1
    input wire [4:0]  rs2_id,           // ID stage source 2

    // [FIX v3] MEM stage load info — để detect 1-cycle gap
    input wire        memread_mem,      // MEM stage is a load (LW in MEM)
    input wire [4:0]  rd_mem,           // MEM stage destination register

    // Branch/Jump flush
    input wire        branch_taken,     // Branch or jump taken in EX stage

    // Memory interface
    input wire        imem_ready,       // Instruction memory ready

    // LSU scoreboard
    input wire [31:0] lsu_scoreboard,   // Bitmask: registers đang chờ LSU

    // ========================================================================
    // Control Outputs
    // ========================================================================
    output wire       stall,            // Pipeline stall (load-use + LSU dep + mem_load)
    output wire       stall_if,         // IF stage stall (imem not ready)
    output wire       flush_if_id,      // Flush IF/ID register
    output wire       flush_id_ex       // Flush ID/EX register (insert bubble)
);

    // ========================================================================
    // Load-Use Hazard Detection (EX stage)
    // LW ở EX → instruction ở ID dùng kết quả → stall 1 cycle
    // ========================================================================
    wire load_use_hazard;
    assign load_use_hazard = memread_id_ex &&
                             (rd_id_ex != 5'b0) &&
                             ((rd_id_ex == rs1_id) || (rd_id_ex == rs2_id));

    // ========================================================================
    // [FIX v3] MEM Load Stall (MEM stage)
    // LW ở MEM (cycle sau load_use) → scoreboard chưa set → cần stall thêm
    // Lấp 1-cycle gap giữa load_use_hazard=0 và lsu_dependency_stall=1
    // ========================================================================
    wire mem_load_stall;
    assign mem_load_stall = memread_mem &&
                            (rd_mem != 5'b0) &&
                            ((rd_mem == rs1_id) || (rd_mem == rs2_id));

    // ========================================================================
    // LSU Dependency Stall (Scoreboard)
    // Register đang chờ LSU hoàn thành → stall cho đến khi scoreboard clear
    // ========================================================================
    wire lsu_dependency_stall;
    assign lsu_dependency_stall = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                                  (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);

    // ========================================================================
    // Instruction Fetch Stall
    // ========================================================================
    wire imem_stall;
    assign imem_stall = !imem_ready;

    // ========================================================================
    // Combined Stall Signals
    // ========================================================================

    // stall: PIPELINE hazard stall (load-use + mem_load gap + LSU scoreboard)
    // KHÔNG bao gồm imem_stall
    assign stall = load_use_hazard || mem_load_stall || lsu_dependency_stall;

    // stall_if: IF-ONLY stall khi ICache chưa ready
    assign stall_if = imem_stall;

    // ========================================================================
    // Flush Signals
    // ========================================================================
    assign flush_if_id = branch_taken;
    assign flush_id_ex = load_use_hazard || branch_taken;

endmodule