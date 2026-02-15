// ============================================================================
// hazard_detection.v - Fixed v2 (Correct imem_stall Handling)
// ============================================================================
// FIX LOG:
//   BUG #3 FIX: imem_stall trước đây được merge vào signal `stall` chung,
//               điều này freeze toàn bộ pipeline (PC, IF/ID, ID/EX, ...).
//
//   Vấn đề cũ:
//     assign stall = load_use_hazard || lsu_dependency_stall || imem_stall;
//     → Khi imem_stall=1: toàn pipeline đóng băng, kể cả ID/EX/MEM/WB
//     → Khi imem_ready=1 trở lại: cần thêm 1 cycle để pipeline "thức dậy"
//     → Mất 2 cycle tổng cộng xung quanh mỗi imem stall event
//
//   FIX MỚI: Tách thành 2 tín hiệu độc lập:
//     - `stall_pipeline`: stall TOÀN pipeline (PC + IF/ID + ID/EX)
//       Dùng cho: load_use_hazard, lsu_dependency_stall
//     - `stall_if`:       stall CHỈ IF stage (PC + IF/ID)
//       Dùng cho: imem_stall (ICache chưa ready)
//
//   Tại sao điều này đúng?
//     Khi ICache đang fetch instruction mới (imem_stall=1):
//     - PC không nên cập nhật (chờ fetch xong)
//     - IF/ID không nên nhận instruction mới (chưa có)
//     - Nhưng ID/EX/MEM/WB KHÔNG CẦN STALL, chúng vẫn đang xử lý
//       các instruction đã fetch trước đó một cách bình thường
//
//   Lưu ý về `stall` output:
//     `stall` = stall_pipeline (cho IFU, IF/ID, ID/EX)
//     `stall_if_only` = stall_if (chỉ cho IFU và IF/ID khi chỉ imem stall)
//
//   Trong IFU và PIPELINE_REG_IF_ID:
//     Sử dụng (stall_pipeline || stall_if_only) để freeze IF stage
//
// ============================================================================

module hazard_detection (
    // Load-use hazard detection (EX stage load)
    input wire        memread_id_ex,    // EX stage is doing load
    input wire [4:0]  rd_id_ex,         // EX stage destination register
    input wire [4:0]  rs1_id,           // ID stage source 1
    input wire [4:0]  rs2_id,           // ID stage source 2
    
    // Branch/Jump flush
    input wire        branch_taken,     // Branch or jump taken in EX stage
    
    // Memory interface
    input wire        imem_ready,       // Instruction memory ready
    
    // LSU scoreboard
    input wire [31:0] lsu_scoreboard,   // Bitmask: registers đang chờ LSU
    
    // ========================================================================
    // Control Outputs
    // ========================================================================
    
    // [FIX] stall: Chỉ dùng cho pipeline hazard (load-use, LSU dep)
    //             KHÔNG bao gồm imem_stall nữa
    //             → ID/EX vẫn chạy khi ICache đang fetch
    output wire       stall,            // Pipeline stall (load-use + LSU)
    
    // [FIX MỚI] stall_if: Stall riêng cho IF stage khi imem chưa ready
    //           Kết hợp với stall ở IFU và PIPELINE_REG_IF_ID
    output wire       stall_if,         // IF stage stall (imem not ready)
    
    output wire       flush_if_id,      // Flush IF/ID register
    output wire       flush_id_ex       // Flush ID/EX register (insert bubble)
);

    // ========================================================================
    // Load-Use Hazard Detection
    // ========================================================================
    wire load_use_hazard;
    assign load_use_hazard = memread_id_ex && 
                             (rd_id_ex != 5'b0) &&
                             ((rd_id_ex == rs1_id) || (rd_id_ex == rs2_id));
    
    // ========================================================================
    // LSU Dependency Stall
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
    // [FIX] Combined Stall Signals - Tách biệt rõ ràng
    // ========================================================================
    
    // stall: PIPELINE hazard stall
    // Dùng để: freeze PC, freeze IF/ID, bubble ID/EX
    // KHÔNG bao gồm imem_stall (ICache stall)
    assign stall = load_use_hazard || lsu_dependency_stall;
    
    // stall_if: IF-ONLY stall khi ICache chưa ready
    // Dùng để: freeze PC và IF/ID khi waiting for ICache
    // Không ảnh hưởng ID/EX/MEM/WB stages
    assign stall_if = imem_stall;
    
    // ========================================================================
    // Flush Signals
    // ========================================================================
    // Flush IF/ID khi branch/jump taken
    assign flush_if_id = branch_taken;
    
    // Flush ID/EX (insert bubble) khi:
    //   1. Load-use hazard
    //   2. Branch/jump taken
    assign flush_id_ex = load_use_hazard || branch_taken;

endmodule