`timescale 1ns/1ps

`include "cpu/core/IFU.v"
`include "cpu/core/reg_file.v"
`include "cpu/core/imm_gen.v"
`include "cpu/core/control.v"
`include "cpu/core/alu.v"
`include "cpu/core/riscv_multiplier.v"
`include "cpu/core/branch_logic.v"
`include "cpu/core/forwarding_unit.v"
`include "cpu/core/hazard_detection.v"
`include "cpu/core/PIPELINE_REG_IF_ID.v"
`include "cpu/core/PIPELINE_REG_ID_EX.v"
`include "cpu/core/PIPELINE_REG_EX_MEM.v"
`include "cpu/core/PIPELINE_REG_MEM_WB.v"
`include "cpu/core/LSU.v"
module riscv_cpu_core #(
    parameter [31:0] HART_ID = 32'd0
) (
    input wire clk,
    input wire rst,


    output wire [31:0] imem_addr,
    output wire        imem_valid,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,

    output wire [31:0] dcache_addr,
    output wire [31:0] dcache_wdata,
    output wire [3:0]  dcache_wstrb,
    output wire        dcache_req,
    output wire        dcache_we,
    input  wire [31:0] dcache_rdata,
    input  wire        dcache_ready,
    input  wire        dcache_fence_busy,
    output wire [1:0]  dcache_fence_type,

    input  wire external_irq,
    input  wire timer_irq,
    input  wire sw_irq,


    input  wire debug_haltreq,    // DM → CPU: yêu cầu vào D-mode
    input  wire debug_resumereq,  // DM → CPU: yêu cầu thoát D-mode
    output wire debug_halted,     // CPU → DM: đang trong D-mode, pipeline frozen
    output wire debug_running,    // CPU → DM: đang chạy bình thường
    output wire cpu_wfi_o,        // CPU → SoC: đang chờ interrupt
    output wire perf_stall_o,     // CPU → SoC: pipeline stalled (stall_any)
    output wire perf_instr_ret_o  // CPU → SoC: instruction retired (regwrite_wb approx)
);

    localparam [6:0]
        OP_R_TYPE = 7'b0110011,
        OP_I_TYPE = 7'b0010011,
        OP_LOAD   = 7'b0000011,
        OP_STORE  = 7'b0100011,
        OP_BRANCH = 7'b1100011,
        OP_JALR   = 7'b1100111,
        OP_SYSTEM = 7'b1110011;

    localparam [11:0]
        CSR_MSTATUS = 12'h300,
        CSR_MIE     = 12'h304,
        CSR_MTVEC   = 12'h305,
        CSR_MEPC    = 12'h341,
        CSR_MCAUSE  = 12'h342,
        CSR_MHARTID = 12'hF14;

    // =========================================================================
    // INTERRUPT SYNCHRONIZATION & PENDING LOGIC
    // Synchronizes external/timer/software interrupts into the CPU clock domain.
    // Handles flush counter to clear the pipeline upon interrupt detection.
    // =========================================================================
    reg ext_irq_s1, ext_irq_s2;
    reg tmr_irq_s1, tmr_irq_s2;
    reg sw_irq_s1,  sw_irq_s2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ext_irq_s1 <= 1'b0; ext_irq_s2 <= 1'b0;
            tmr_irq_s1 <= 1'b0; tmr_irq_s2 <= 1'b0;
            sw_irq_s1  <= 1'b0; sw_irq_s2  <= 1'b0;
        end else begin
            ext_irq_s1 <= external_irq; ext_irq_s2 <= ext_irq_s1;
            tmr_irq_s1 <= timer_irq;    tmr_irq_s2 <= tmr_irq_s1;
            sw_irq_s1  <= sw_irq;       sw_irq_s2  <= sw_irq_s1;
        end
    end

    reg [31:0] csr_mstatus_r, csr_mie_r, csr_mtvec_r, csr_mepc_r, csr_mcause_r;

    wire irq_pending = ext_irq_s2 | tmr_irq_s2 | sw_irq_s2;
    wire irq_source_pending = (ext_irq_s2 && csr_mie_r[11]) ||
                              (tmr_irq_s2 && csr_mie_r[7])  ||
                              (sw_irq_s2  && csr_mie_r[3]);
    wire irq_take_req = csr_mstatus_r[3] && irq_source_pending;

    reg irq_pending_lat;
    always @(posedge clk or posedge rst) begin
        if (rst)
            irq_pending_lat <= 1'b0;
        else if (irq_take)
            irq_pending_lat <= 1'b0;
        else if (irq_take_req)
            irq_pending_lat <= 1'b1;
    end

    // irq_take is the precise one-cycle trap flush. Extending this flush after
    // redirect can squash the first instruction at mtvec (observed ISR sp frame loss).
    wire irq_flush = 1'b0;

    // =========================================================================
    // DEBUG MODE FSM
    //
    // 2-FF CDC synchronizers for debug_haltreq / debug_resumereq coming from
    // the JTAG clock domain. Without synchronization, metastability in the FSM
    // can cause undefined state transitions.
    reg dbg_halt_s1,   dbg_halt_s2;
    reg dbg_resume_s1, dbg_resume_s2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dbg_halt_s1   <= 1'b0; dbg_halt_s2   <= 1'b0;
            dbg_resume_s1 <= 1'b0; dbg_resume_s2 <= 1'b0;
        end else begin
            dbg_halt_s1   <= debug_haltreq;   dbg_halt_s2   <= dbg_halt_s1;
            dbg_resume_s1 <= debug_resumereq; dbg_resume_s2 <= dbg_resume_s1;
        end
    end

    // 3 trạng thái:
    //   DBG_RUNNING : CPU chạy bình thường
    //   DBG_HALTING : CPU nhận haltreq, đang chờ pipeline + LSU drain
    //   DBG_HALTED  : Pipeline đóng băng hoàn toàn, DM có thể đọc/ghi regs
    //
    // Điều kiện chuyển RUNNING → HALTING:
    //   debug_haltreq=1 AND lsu_sb_empty=1 AND dc_req=0
    //   WHY: Không halt giữa chừng khi LSU đang có in-flight transaction
    //   trên AXI bus — DMA của ASCON hoặc DCache evict có thể đang dùng
    //   bus → cắt ngang gây DECERR hoặc data corruption trên DMEM.
    //
    // Điều kiện chuyển HALTING → HALTED:
    //   Sau 1 cycle delay để pipeline stages drain (NOP propagate qua EX→MEM→WB).
    //   WHY 1 cycle đủ: HALTING đã đảm bảo LSU idle, pipeline stall = 1
    //   nên không có instruction mới vào. 1 cycle cho phép stall_any propagate.
    //
    // Điều kiện chuyển HALTED → RUNNING:
    //   debug_resumereq=1 (pulse từ DM sau khi debugger ghi xong)
    //
    // debug_mode=1 khi DBG_HALTED: inject vào stall_any để freeze pipeline
    // =========================================================================
    localparam DBG_RUNNING = 2'b00;
    localparam DBG_HALTING = 2'b01;
    localparam DBG_HALTED  = 2'b10;

    reg [1:0] dbg_state;
    reg       debug_mode;   // 1 khi đang trong D-mode

    // WHY cần lsu_sb_empty và dc_req từ bên ngoài FSM:
    //   lsu_sb_empty: Store Buffer rỗng → không còn pending write nào trên bus
    //   dc_req: DCache không có request đang chờ DCache ready
    //   Cả hai phải đồng thời thỏa trước khi halt an toàn.
    wire lsu_sb_empty_w = soc_lsu_sb_empty;   // wire từ LSU (xem bên dưới)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dbg_state  <= DBG_RUNNING;
            debug_mode <= 1'b0;
        end else begin
            case (dbg_state)
                DBG_RUNNING: begin
                    // Chờ bus idle trước khi bước vào HALTING
                    if (dbg_halt_s2 && lsu_sb_empty_w && !dcache_req) begin
                        dbg_state <= DBG_HALTING;
                    end
                end
                DBG_HALTING: begin
                    // 1-cycle drain: stall đã được assert từ cycle trước
                    // (debug_mode chưa set nhưng haltreq làm flush_id_ex_final đúng)
                    // Sang HALTED và bật debug_mode để freeze pipeline hoàn toàn
                    dbg_state  <= DBG_HALTED;
                    debug_mode <= 1'b1;
                end
                DBG_HALTED: begin
                    // WHY check !dbg_halt_s2: DM có thể giữ haltreq=1 nhiều
                    // cycle. Chỉ resume khi resumereq pulse xuất hiện.
                    if (dbg_resume_s2) begin
                        dbg_state  <= DBG_RUNNING;
                        debug_mode <= 1'b0;
                    end
                end
                default: begin
                    dbg_state  <= DBG_RUNNING;
                    debug_mode <= 1'b0;
                end
            endcase
        end
    end

    // Output signals cho jtag_debug_top
    assign debug_halted  = (dbg_state == DBG_HALTED);
    assign debug_running = (dbg_state == DBG_RUNNING);

    reg cpu_wfi_r;

    // =========================================================================
    // Pipeline stage wires
    // =========================================================================
    wire [31:0] pc_if;
    wire [31:0] instr_if;
    wire [31:0] pc_id;
    wire [31:0] instr_id;

    wire [6:0] opcode_id = instr_id[6:0];
    wire [4:0] rd_id     = instr_id[11:7];
    wire [2:0] funct3_id = instr_id[14:12];
    wire [4:0] rs1_id    = instr_id[19:15];
    wire [4:0] rs2_id    = instr_id[24:20];
    wire [6:0] funct7_id = instr_id[31:25];

    wire [3:0] alu_control_id;
    wire regwrite_id, alusrc_id, memread_id, memwrite_id;
    wire branch_id, jump_id, fence_id;
    wire [1:0] byte_size_id;
    wire rs1_used_id;
    wire rs2_used_id;

    // =========================================================================
    // [FENCE-TYPE] Decode pred/succ bits từ FENCE instruction
    // =========================================================================
    wire fence_pred_w    = instr_id[24];  // W — memory write
    wire fence_pred_r    = instr_id[25];  // R — memory read
    wire fence_pred_i    = instr_id[27];  // I — input device
    wire       fence_is_fencei = funct3_id[0];

    reg fence_wait_r;
    reg fence_wait_seen_busy_r;
    wire fence_launch = fence_id && !fence_stall && !fence_wait_r;
    wire fence_wait_done = fence_wait_r && fence_wait_seen_busy_r && !dcache_fence_busy;
    wire fence_wait_stall = fence_wait_r && !fence_wait_done;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fence_wait_r           <= 1'b0;
            fence_wait_seen_busy_r <= 1'b0;
        end else if (fence_wait_done) begin
            fence_wait_r           <= 1'b0;
            fence_wait_seen_busy_r <= 1'b0;
        end else if (fence_launch) begin
            fence_wait_r           <= 1'b1;
            fence_wait_seen_busy_r <= dcache_fence_busy;
        end else if (fence_wait_r && dcache_fence_busy) begin
            fence_wait_seen_busy_r <= 1'b1;
        end
    end

    assign dcache_fence_type[0] = fence_launch && (fence_is_fencei | fence_pred_w | fence_pred_i);
    assign dcache_fence_type[1] = fence_launch && (fence_is_fencei | fence_pred_r | fence_pred_i);

`ifdef DEBUG_FENCE_TRACE
    always @(posedge clk) begin
        if (!rst && (fence_launch || fence_wait_r || dcache_fence_busy)) begin
            $display("[FENCE t=%0t] pc_id=%h instr_id=%h launch=%b wait=%b seen=%b busy=%b done=%b type=%02b stall_any=%b",
                     $time, pc_id, instr_id, fence_launch, fence_wait_r,
                     fence_wait_seen_busy_r, dcache_fence_busy, fence_wait_done,
                     dcache_fence_type, stall_any);
        end
    end
`endif

    wire [31:0] read_data1_id, read_data2_id, imm_id;
    wire [31:0] read_data1_rf, read_data2_rf;

    // =========================================================================
    // REGISTER SOURCE DEPENDENCY DECODE (ID STAGE)
    // Decodes which source registers (rs1, rs2) are actually used by the instruction.
    // Used by hazard detection logic to avoid false data dependencies.
    // =========================================================================
    // Decode true source usage early so hazard detection does not treat
    // immediate bits as rs2 dependencies on I-type instructions.
    wire is_csr_id = (opcode_id == OP_SYSTEM) && (funct3_id != 3'b000);
    wire csr_uses_rs1_id = is_csr_id && !funct3_id[2];

    assign rs1_used_id = (opcode_id == OP_R_TYPE) ||
                         (opcode_id == OP_I_TYPE) ||
                         (opcode_id == OP_LOAD)   ||
                         (opcode_id == OP_STORE)  ||
                         (opcode_id == OP_BRANCH) ||
                         (opcode_id == OP_JALR)   ||
                         csr_uses_rs1_id;

    assign rs2_used_id = (opcode_id == OP_R_TYPE) ||
                         (opcode_id == OP_STORE)  ||
                         (opcode_id == OP_BRANCH);

    wire regwrite_ex, alusrc_ex, memread_ex, memwrite_ex;
    wire branch_ex, jump_ex;
    wire [31:0] read_data1_ex, read_data2_ex, imm_ex, pc_ex;
    wire [4:0]  rs1_ex, rs2_ex, rd_ex;
    wire [2:0]  funct3_ex;
    wire [3:0]  alu_control_ex;
    wire [1:0]  byte_size_ex;
    wire [6:0]  opcode_ex;

    wire [31:0] alu_in1, alu_in2, alu_in2_pre_mux, alu_in1_forwarded;
    wire [31:0] alu_result_ex;
    wire zero_flag_ex, less_than_ex, less_than_u_ex;
    wire branch_taken_ex;
    wire [31:0] target_pc_ex;
    wire [31:0] branch_target_ex;
    wire pc_src_ex;
    wire [31:0] pc_plus_4_ex;

    wire regwrite_mem, memread_mem, memwrite_mem;
    wire [31:0] alu_result_mem, write_data_mem, pc_plus_4_mem;
    wire [4:0]  rd_mem;
    wire [1:0]  byte_size_mem;
    wire [2:0]  funct3_mem;
    wire jump_mem;

    wire        lsu_req_valid, lsu_req_ready;
    wire [3:0]  lsu_req_wstrb;
    wire        lsu_result_valid;
    wire [31:0] lsu_result_data;
    wire [4:0]  lsu_result_rd;
    wire        lsu_result_ack;
    wire        lsu_result_commit;
    wire [31:0] lsu_scoreboard;
    wire        lsu_idle;

    wire regwrite_wb, memtoreg_wb, jump_wb;
    wire [31:0] alu_result_wb, mem_data_wb, pc_plus_4_wb;
    wire [4:0]  rd_wb;
    wire [31:0] write_back_data_wb;

    // MUL pipeline tracking
    wire        is_mul_mem, is_mul_wb;
    wire [31:0] mul_result_direct;  // writeback_value_o from multiplier (2-cycle delay)

    wire [1:0] forward_a, forward_b;
    wire stall, stall_if, stall_any;
    wire fence_stall;
    wire lsu_dep_stall;
    wire mul_ex_stall_wire;
    wire flush_if_id, flush_id_ex;

    // =========================================================================
    // WAIT FOR INTERRUPT (WFI) & PIPELINE STALL CONTROL
    // Determines when the CPU should enter sleep state (WFI) and wake up.
    // Aggregates all stall conditions to freeze the entire pipeline (stall_any).
    // =========================================================================
    // [FIX-LSU-BACKPRESSURE] Nếu MEM stage đã phát sinh LSU request nhưng LSU
    // chưa ready (ví dụ SB full), phải giữ nguyên toàn pipeline cho đến khi
    // handshake xong. Nếu không, MEM instruction hiện tại bị overwrite bởi
    // younger instruction và store/load request bị rơi.
    wire mem_stage_wait;
    // When an enabled IRQ is pending but the core is not yet at a precise
    // trap point, stop admitting younger work so LSU/store-buffer can drain.
    // Assigned after irq_control_busy is known; do not freeze a branch/jump in
    // EX before it resolves, or the core can deadlock on a tight task loop.
    wire irq_drain_stall;

    // stall_any includes debug_mode, WFI idle state, LSU backpressure, and IRQ drain.
    assign stall_any = stall | stall_if | debug_mode | cpu_wfi_r |
                       mem_stage_wait | irq_drain_stall | fence_wait_stall;

    wire is_wfi_id = (opcode_id == OP_SYSTEM) &&
                     (funct3_id == 3'b000) &&
                     (rs1_id == 5'b00000) &&
                     (rd_id == 5'b00000) &&
                     (instr_id[31:20] == 12'h105);
    wire wfi_wake = irq_take_req | irq_pending_lat | dbg_halt_s2 | debug_mode;
    wire wfi_enter = is_wfi_id && !cpu_wfi_r && !wfi_wake && !stall_any;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cpu_wfi_r <= 1'b0;
        end else if (wfi_wake) begin
            cpu_wfi_r <= 1'b0;
        end else if (wfi_enter) begin
            cpu_wfi_r <= 1'b1;
        end
    end

    assign cpu_wfi_o        = cpu_wfi_r;
    assign perf_stall_o     = stall_any;
    assign perf_instr_ret_o = regwrite_wb && !stall_any;

    // =========================================================================
    // BRANCH HISTORY TABLE (BHT) PREDICTOR
    // 2-bit saturating counter branch predictor with 256 entries.
    // Predicts branch outcome in ID stage; resolves and updates in EX stage.
    // =========================================================================
    // 2-bit BHT predictor: 256 entries, indexed by PC[9:2].
    wire predict_taken_ex;
    wire predict_taken_id;
    wire mispredict_ex;
    reg [1:0] bht_r [0:255];
    integer bht_i;
    wire [7:0] bht_idx_id = pc_id[9:2];
    wire [7:0] bht_idx_ex = pc_ex[9:2];
    wire [1:0] bht_state_id = bht_r[bht_idx_id];
    wire bht_taken_id = bht_state_id[1];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (bht_i = 0; bht_i < 256; bht_i = bht_i + 1)
                bht_r[bht_i] <= 2'b01;
        end else if (branch_ex) begin
            case ({branch_taken_ex, bht_r[bht_idx_ex]})
                3'b0_00: bht_r[bht_idx_ex] <= 2'b00;
                3'b0_01: bht_r[bht_idx_ex] <= 2'b00;
                3'b0_10: bht_r[bht_idx_ex] <= 2'b01;
                3'b0_11: bht_r[bht_idx_ex] <= 2'b10;
                3'b1_00: bht_r[bht_idx_ex] <= 2'b01;
                3'b1_01: bht_r[bht_idx_ex] <= 2'b10;
                3'b1_10: bht_r[bht_idx_ex] <= 2'b11;
                3'b1_11: bht_r[bht_idx_ex] <= 2'b11;
                default: bht_r[bht_idx_ex] <= 2'b01;
            endcase
        end
    end

    // Guard with !stall_any to prevent re-predicting the same stalled branch.
    assign predict_taken_id = branch_id && bht_taken_id && !stall_any;
    assign mispredict_ex    = predict_taken_ex && !branch_taken_ex && branch_ex;

    // =========================================================================
    // IFU REDIRECT & PIPELINE FLUSH CONTROL
    // Determines the next PC source based on priority (recovery > branch > wfi > predict).
    // Generates flush signals to invalidate pipeline stages when control flow changes.
    // =========================================================================
    // IFU redirect priority: mispredict recovery > actual branch/jump > WFI consume > prediction
    wire [31:0] wfi_resume_pc = pc_id + 32'd4;

    wire is_system_ex = (opcode_ex == OP_SYSTEM);
    wire is_csr_ex = is_system_ex && (funct3_ex != 3'b000);
    wire is_mret_ex = is_system_ex && (funct3_ex == 3'b000) && (imm_ex[11:0] == 12'h302);
    wire is_ecall_ex = is_system_ex && (funct3_ex == 3'b000) && (imm_ex[11:0] == 12'h000);

    // EX can temporarily hold stale/wrong-path work while branch redirects are
    // flushing younger stages. Take IRQ only at a precise, non-control-flow EX point.
    wire ex_valid_for_irq = (opcode_ex != 7'b0000000) && (pc_ex[31:2] != 30'h0);
    wire id_valid_for_irq = (opcode_id != 7'b0000000) && (pc_id[31:2] != 30'h0);
    // A resolved branch is a precise commit point for interrupts as long as
    // mepc is the resolved next PC. Blocking all branch_ex cycles starves IRQs
    // in tight polling loops (for example while(timer_irq_count < N)).
    wire irq_control_busy = jump_ex || is_mret_ex || is_ecall_ex ||
                            predict_taken_id ||
                            (((pc_src_ex || mispredict_ex || flush_if_id || flush_id_ex) &&
                              !branch_ex));
    wire irq_eligible = lsu_sb_empty_w && !dcache_req && !debug_mode &&
                        (ex_valid_for_irq || id_valid_for_irq) && !irq_control_busy;
    wire irq_take = irq_pending_lat && irq_eligible;
    assign irq_drain_stall = irq_pending_lat && !irq_take && !debug_mode &&
                              !irq_control_busy &&
                              (ex_valid_for_irq || id_valid_for_irq);
    wire ecall_take = is_ecall_ex && !stall_any && !debug_mode;
    wire trap_take = ecall_take || irq_take;

`ifdef DEBUG_IRQ_DRAIN
    always @(posedge clk) begin
        if (!rst && (ext_irq_s2 || tmr_irq_s2 || sw_irq_s2 ||
                     irq_take_req || irq_pending_lat || irq_take || irq_drain_stall)) begin
            $display("[%0t] [IRQ-DRAIN] req=%b lat=%b take=%b drain=%b elig=%b mstatus_mie=%b meie=%b mtie=%b msie=%b ext=%b tmr=%b sw=%b lsu_idle=%b dc_req=%b ctrl=%b ex_valid=%b pc_ex=%h op_ex=%b pc_id=%h",
                     $time, irq_take_req, irq_pending_lat, irq_take, irq_drain_stall,
                     irq_eligible, csr_mstatus_r[3], csr_mie_r[11], csr_mie_r[7], csr_mie_r[3],
                     ext_irq_s2, tmr_irq_s2, sw_irq_s2,
                     lsu_sb_empty_w, dcache_req, irq_control_busy,
                     (ex_valid_for_irq || id_valid_for_irq), pc_ex, opcode_ex, pc_id);
        end
    end
`endif
    wire [31:0] irq_target_pc = {csr_mtvec_r[31:2], 2'b00};

    wire        ifu_pc_src    = trap_take || mispredict_ex || pc_src_ex || wfi_enter || predict_taken_id;
    wire [31:0] ifu_target_pc = trap_take     ? irq_target_pc :
                                mispredict_ex ? pc_plus_4_ex  :
                                pc_src_ex     ? target_pc_ex  :
                                wfi_enter     ? wfi_resume_pc :
                                                branch_target_id;

    // Fix 10C: Multiplier stall — don't freeze multiplier during its own extra cycle
    wire mul_hold = stall_any && !mul_ex_stall_wire;

    // stall_ex_mem: freeze EX/MEM only when the MEM/LSU side cannot accept work.
    // Front-end stalls after redirects must not freeze EX/MEM: otherwise the
    // previous instruction can occupy MEM while a JALR/IRQ/MRET in EX loses its
    // link/commit. PIPELINE_REG_EX_MEM already pass-once/bubbles duplicate EX
    // replays during stall_any.
    wire stall_ex_mem = lsu_dep_stall | mem_stage_wait;

    // [FIX-JALR-TARGET] JALR predicted taken đến pc+imm (sai). EX sẽ correct
    // đến rs1+imm. Flush IF/ID tại cycle JALR-in-EX để xóa instruction fetched
    // từ wrong predicted target.
    wire is_jalr_ex = (opcode_ex == 7'b1100111);
    wire jalr_wrong_target = is_jalr_ex && jump_ex && predict_taken_ex;

    // FIX-MRET-FLUSH: MRET must squash both the instruction in ID (→ flush_id_ex) and
    // the instruction in IF (→ flush_if_id) that were fetched speculatively after MRET.
    // FIX-JAL-FLUSH: Unpredicted JAL/JALR (predict_taken_ex=0) must also flush IF and ID
    // to prevent wrong-path instructions from corrupting register values via forwarding.
    wire jump_unpredicted_ex = jump_ex && !predict_taken_ex;
    wire flush_if_id_final = flush_if_id | irq_flush | trap_take | wfi_enter | jalr_wrong_target | is_mret_ex | jump_unpredicted_ex;
    wire flush_id_ex_final = flush_id_ex | irq_flush | trap_take | wfi_enter | is_mret_ex | jump_unpredicted_ex;

    // =========================================================================
    // STAGE 1: IF
    // =========================================================================
    IFU instruction_fetch (
        .clock            (clk),
        .reset            (rst),
        .pc_src           (ifu_pc_src),
        .stall            (stall_any),      // debug_mode → stall_any → IFU dừng fetch
        .target_pc        (ifu_target_pc),
        .imem_addr        (imem_addr),
        .imem_valid       (imem_valid),
        .imem_rdata       (imem_rdata),
        .imem_ready       (imem_ready),
        .PC_out           (pc_if),
        .Instruction_Code (instr_if)
    );

    PIPELINE_REG_IF_ID if_id_reg (
        .clock    (clk),
        .reset    (rst),
        .flush    (flush_if_id_final),
        .stall    (stall_any),
        .instr_in (instr_if),
        .pc_in    (pc_if),
        .instr_out(instr_id),
        .pc_out   (pc_id)
    );

    // =========================================================================
    // STAGE 2: ID
    // =========================================================================
    control control_unit (
        .opcode     (opcode_id),
        .funct3     (funct3_id),
        .funct7     (funct7_id),
        .alu_control(alu_control_id),
        .regwrite   (regwrite_id),
        .alusrc     (alusrc_id),
        .memread    (memread_id),
        .memwrite   (memwrite_id),
        .branch     (branch_id),
        .jump       (jump_id),
        .byte_size  (byte_size_id),
        .fence      (fence_id)
    );

    wire regwrite_id_final = regwrite_id || is_csr_id;

    reg_file register_file (
        .clock        (clk),
        .reset        (rst),
        .read_reg_num1(rs1_id),
        .read_reg_num2(rs2_id),
        .read_data1   (read_data1_rf),
        .read_data2   (read_data2_rf),
        .regwrite     (regwrite_wb),
        .write_reg    (rd_wb),
        .write_data   (write_back_data_wb)
    );

    // LSU completion can occur in the same cycle that ID samples its source
    // registers. Bypass that result directly so load->JALR/CALL does not
    // capture the pre-load register value for one cycle.
    assign read_data1_id = (lsu_result_commit && (lsu_result_rd != 5'd0) &&
                            (lsu_result_rd == rs1_id)) ? lsu_result_data : read_data1_rf;
    assign read_data2_id = (lsu_result_commit && (lsu_result_rd != 5'd0) &&
                            (lsu_result_rd == rs2_id)) ? lsu_result_data : read_data2_rf;

    imm_gen immediate_generator (
        .instr(instr_id),
        .imm  (imm_id)
    );

    // =========================================================================
    // ID/EX PIPELINE REGISTER (standalone module)
    // =========================================================================
    // Pre-compute branch target in ID stage to remove adder from EX critical path.
    // pc_id and imm_id are both available here; result passes through ID/EX register.
    wire [31:0] branch_target_id = pc_id + imm_id;
    wire fwd_a_lsu = lsu_result_commit && (lsu_result_rd != 5'd0) &&
                     (lsu_result_rd == rs1_ex);
    wire fwd_b_lsu = lsu_result_commit && (lsu_result_rd != 5'd0) &&
                     (lsu_result_rd == rs2_ex);

    PIPELINE_REG_ID_EX id_ex_reg (
        .clock           (clk),
        .reset           (rst),
        .flush           (flush_id_ex_final),
        .stall           (stall_any),
        // Forwarding capture (FIX-FWD-STALL)
        .fwd_a_sel       (forward_a),
        .fwd_b_sel       (forward_b),
        .fwd_a_data      (alu_in1_forwarded),
        .fwd_b_data      (alu_in2_pre_mux),
        .lsu_fwd_a_valid (fwd_a_lsu),
        .lsu_fwd_b_valid (fwd_b_lsu),
        .lsu_fwd_data    (lsu_result_data),
        .fwd_a_self_replay(fwd_a_mem_self_replay | fwd_a_wb_self_replay),
        .fwd_b_self_replay(fwd_b_mem_self_replay | fwd_b_wb_self_replay),
        // Control inputs
        .regwrite_in     (regwrite_id_final),
        .alusrc_in       (alusrc_id),
        .memread_in      (memread_id),
        .memwrite_in     (memwrite_id),
        .branch_in       (branch_id),
        .predict_taken_in(predict_taken_id),
        .jump_in         (jump_id),
        // Data inputs
        .read_data1_in   (read_data1_id),
        .read_data2_in   (read_data2_id),
        .imm_in          (imm_id),
        .pc_in           (pc_id),
        .branch_target_in(branch_target_id),
        // Register addresses
        .rs1_in          (rs1_id),
        .rs2_in          (rs2_id),
        .rd_in           (rd_id),
        // Function codes
        .funct3_in       (funct3_id),
        .alu_control_in  (alu_control_id),
        .byte_size_in    (byte_size_id),
        .opcode_in       (opcode_id),
        // Control outputs
        .regwrite_out    (regwrite_ex),
        .alusrc_out      (alusrc_ex),
        .memread_out     (memread_ex),
        .memwrite_out    (memwrite_ex),
        .branch_out      (branch_ex),
        .predict_taken_out(predict_taken_ex),
        .jump_out        (jump_ex),
        // Data outputs
        .read_data1_out  (read_data1_ex),
        .read_data2_out  (read_data2_ex),
        .imm_out         (imm_ex),
        .pc_out          (pc_ex),
        .branch_target_out(branch_target_ex),
        // Register address outputs
        .rs1_out         (rs1_ex),
        .rs2_out         (rs2_ex),
        .rd_out          (rd_ex),
        // Function code outputs
        .funct3_out      (funct3_ex),
        .alu_control_out (alu_control_ex),
        .byte_size_out   (byte_size_ex),
        .opcode_out      (opcode_ex)
    );

    // =========================================================================
    // STAGE 3: EX
    // =========================================================================
    forwarding_unit fwd_unit (
        .rs1_ex      (rs1_ex),       .rs2_ex      (rs2_ex),
        .rd_mem      (rd_mem),       .rd_wb       (rd_wb),
        .regwrite_mem(regwrite_mem), .regwrite_wb (regwrite_wb),
        .forward_a   (forward_a),    .forward_b   (forward_b)
    );

    // =========================================================================
    // ALU OPERAND MULTIPLEXING & FORWARDING LOGIC
    // Resolves data hazards by bypassing data from MEM or WB stages back to EX.
    // Uses a flat AND-OR mux design to reduce critical path delay.
    // =========================================================================
    // Flat AND-OR mux: expand WB source inline to eliminate cascaded mux levels.
    // OLD: alu_in1_forwarded (3-way) → alu_in1 (3-way) = 4 extra gate levels on critical path.
    // NEW: single 8-way OR of AND terms, all selectors mutually exclusive.
    wire fwd_a_mem  = (forward_a == 2'b10);
    wire fwd_a_wb   = (forward_a == 2'b01);
    wire fwd_a_none = (forward_a == 2'b00);
    wire fwd_b_mem  = (forward_b == 2'b10);
    wire fwd_b_wb   = (forward_b == 2'b01);
    wire fwd_b_none = (forward_b == 2'b00);
    // During a global stall, the same EX instruction can also be present in a
    // later pipeline register. If rd==rs*, plain forwarding would feed the
    // instruction's own replayed result back into itself (e.g. addi a4,a4,28).
    wire fwd_a_mem_self_replay = fwd_a_mem && regwrite_ex && regwrite_mem &&
                                 (rd_ex != 5'd0) && (rd_ex == rs1_ex) &&
                                 (rd_mem == rd_ex) &&
                                 (pc_plus_4_mem == pc_plus_4_ex);
    wire fwd_b_mem_self_replay = fwd_b_mem && regwrite_ex && regwrite_mem &&
                                 (rd_ex != 5'd0) && (rd_ex == rs2_ex) &&
                                 (rd_mem == rd_ex) &&
                                 (pc_plus_4_mem == pc_plus_4_ex);
    wire fwd_a_wb_self_replay  = fwd_a_wb && regwrite_ex && regwrite_wb &&
                                 (rd_ex != 5'd0) && (rd_ex == rs1_ex) &&
                                 (rd_wb == rd_ex) &&
                                 (pc_plus_4_wb == pc_plus_4_ex);
    wire fwd_b_wb_self_replay  = fwd_b_wb && regwrite_ex && regwrite_wb &&
                                 (rd_ex != 5'd0) && (rd_ex == rs2_ex) &&
                                 (rd_wb == rd_ex) &&
                                 (pc_plus_4_wb == pc_plus_4_ex);
    wire fwd_a_mem_eff  = fwd_a_mem && !fwd_a_mem_self_replay && !is_mul_mem;
    wire fwd_b_mem_eff  = fwd_b_mem && !fwd_b_mem_self_replay && !is_mul_mem;
    wire fwd_a_wb_eff   = fwd_a_wb  && !fwd_a_wb_self_replay;
    wire fwd_b_wb_eff   = fwd_b_wb  && !fwd_b_wb_self_replay;
    wire fwd_a_none_eff = fwd_a_none || fwd_a_mem_self_replay || fwd_a_wb_self_replay;
    wire fwd_b_none_eff = fwd_b_none || fwd_b_mem_self_replay || fwd_b_wb_self_replay;
    // Kept for multiplier operands, store data, and ID/EX forwarding-capture port
    assign alu_in1_forwarded = fwd_a_lsu ? lsu_result_data :
                               (({32{fwd_a_mem_eff}}  & alu_result_mem)    |
                                ({32{fwd_a_wb_eff}}   & write_back_data_wb) |
                                ({32{fwd_a_none_eff}} & read_data1_ex));
    assign alu_in2_pre_mux   = fwd_b_lsu ? lsu_result_data :
                               (({32{fwd_b_mem_eff}}  & alu_result_mem)    |
                                ({32{fwd_b_wb_eff}}   & write_back_data_wb) |
                                ({32{fwd_b_none_eff}} & read_data2_ex));

    wire is_lui_ex      = (opcode_ex == 7'b0110111);
    wire is_auipc_ex    = (opcode_ex == 7'b0010111);
    wire not_lui_auipc  = !is_lui_ex && !is_auipc_ex;

    // WB source selectors (shared between alu_in1 and alu_in2 paths)
    wire wb_sel_jump = jump_wb;
    wire wb_sel_mul  = is_mul_wb;
    wire wb_sel_load = memtoreg_wb;
    wire wb_sel_alu  = !jump_wb && !is_mul_wb && !memtoreg_wb;

    // alu_in1: 8 mutually exclusive cases (LUI / AUIPC / MEM-fwd / WB×4 / RF)
    wire alu1_lui      = is_lui_ex;
    wire alu1_auipc    = is_auipc_ex;
    wire alu1_lsu      = not_lui_auipc && fwd_a_lsu;
    wire alu1_fwdmem   = not_lui_auipc && !fwd_a_lsu && fwd_a_mem_eff;
    wire alu1_wb_jump  = not_lui_auipc && !fwd_a_lsu && fwd_a_wb_eff && wb_sel_jump;
    wire alu1_wb_mul   = not_lui_auipc && !fwd_a_lsu && fwd_a_wb_eff && wb_sel_mul;
    wire alu1_wb_load  = not_lui_auipc && !fwd_a_lsu && fwd_a_wb_eff && wb_sel_load;
    wire alu1_wb_alu   = not_lui_auipc && !fwd_a_lsu && fwd_a_wb_eff && wb_sel_alu;
    wire alu1_rf       = not_lui_auipc && !fwd_a_lsu && fwd_a_none_eff;

    assign alu_in1 = ({32{alu1_lui}}     & 32'h0)            |
                     ({32{alu1_auipc}}   & pc_ex)             |
                     ({32{alu1_lsu}}     & lsu_result_data)   |
                     ({32{alu1_fwdmem}}  & alu_result_mem)    |
                     ({32{alu1_wb_jump}} & pc_plus_4_wb)      |
                     ({32{alu1_wb_mul}}  & mul_result_direct) |
                     ({32{alu1_wb_load}} & mem_data_wb)       |
                     ({32{alu1_wb_alu}}  & alu_result_wb)     |
                     ({32{alu1_rf}}      & read_data1_ex);

    // alu_in2: 7 mutually exclusive cases (IMM / MEM-fwd / WB×4 / RF)
    wire alu2_imm      = alusrc_ex;
    wire alu2_lsu      = !alusrc_ex && fwd_b_lsu;
    wire alu2_fwdmem   = !alusrc_ex && !fwd_b_lsu && fwd_b_mem_eff;
    wire alu2_wb_jump  = !alusrc_ex && !fwd_b_lsu && fwd_b_wb_eff && wb_sel_jump;
    wire alu2_wb_mul   = !alusrc_ex && !fwd_b_lsu && fwd_b_wb_eff && wb_sel_mul;
    wire alu2_wb_load  = !alusrc_ex && !fwd_b_lsu && fwd_b_wb_eff && wb_sel_load;
    wire alu2_wb_alu   = !alusrc_ex && !fwd_b_lsu && fwd_b_wb_eff && wb_sel_alu;
    wire alu2_rf       = !alusrc_ex && !fwd_b_lsu && fwd_b_none_eff;

    assign alu_in2 = ({32{alu2_imm}}     & imm_ex)            |
                     ({32{alu2_lsu}}     & lsu_result_data)   |
                     ({32{alu2_fwdmem}}  & alu_result_mem)    |
                     ({32{alu2_wb_jump}} & pc_plus_4_wb)      |
                     ({32{alu2_wb_mul}}  & mul_result_direct) |
                     ({32{alu2_wb_load}} & mem_data_wb)       |
                     ({32{alu2_wb_alu}}  & alu_result_wb)     |
                     ({32{alu2_rf}}      & read_data2_ex);

    alu arithmetic_logic_unit (
        .in1        (alu_in1),     .in2        (alu_in2),
        .alu_control(alu_control_ex),
        .alu_result (alu_result_ex),
        .zero_flag  (zero_flag_ex),
        .less_than  (less_than_ex), .less_than_u(less_than_u_ex)
    );

    branch_logic branch_unit (
        .branch     (branch_ex),    .funct3     (funct3_ex),
        .zero_flag  (zero_flag_ex), .less_than  (less_than_ex),
        .less_than_u(less_than_u_ex), .taken    (branch_taken_ex)
    );

    // =========================================================================
    // 2-stage Pipelined Multiplier (tách khỏi ALU critical path)
    // =========================================================================
    // is_mul_ex: MUL/MULH instruction at EX stage
    // mul_op_ex: 00=MUL, 01=MULH (signed×signed high)
    // mul_valid_ex: dispatch pulse — high for 1 cycle when MUL enters EX
    localparam [3:0] ALU_MUL_CODE  = 4'b1010;
    localparam [3:0] ALU_MULH_CODE = 4'b1011;

    wire        is_mul_ex  = (alu_control_ex == ALU_MUL_CODE) | (alu_control_ex == ALU_MULH_CODE);
    wire [1:0]  mul_op_ex  = (alu_control_ex == ALU_MULH_CODE) ? 2'b01 : 2'b00;
    // mul_valid_ex uses mul_hold (not stall_any) so E1 fires on cycle N even
    // though mul_ex_stall=1 makes stall_any=1 on that cycle.
    // [FIX-MUL-VALID] Allow E1 to fire during mul_ex_stall_wire cycle even if
    // flush_id_ex_final=1: mul_result_stall inserts NOP for the NEXT instruction
    // but must not prevent MUL itself from dispatching to the multiplier E1 stage.
    wire        mul_valid_ex = is_mul_ex & !mul_hold & !(flush_id_ex_final & !mul_ex_stall_wire);

    riscv_multiplier multiplier_unit (
        .clk_i            (clk),
        .rst_i            (rst),
        .mul_valid_i      (mul_valid_ex),
        .mul_op_i         (mul_op_ex),
        .operand_a_i      (alu_in1_forwarded),  // forwarded rs1 (pre-LUI/AUIPC mux)
        .operand_b_i      (alu_in2_pre_mux),    // forwarded rs2 (pre-alusrc mux)
        .hold_i           (mul_hold),
        .mul_hold_e15_i   (mul_hold),
        .writeback_value_o(mul_result_direct)   // valid at WB stage (3 cycles after EX)
    );

    assign pc_plus_4_ex = pc_ex + 32'd4;

    // =========================================================================
    // BRANCH TARGET & PC SOURCE SELECTION (EX STAGE)
    // Calculates exact branch and JALR targets.
    // Determines if the branch is actually taken to control the PC source.
    // =========================================================================
    wire [31:0] jalr_target;
    wire [11:0] csr_addr_ex = imm_ex[11:0];
    wire [31:0] csr_src_ex = funct3_ex[2] ? {27'b0, rs1_ex} : alu_in1_forwarded;

    reg [31:0] csr_read_data_ex;
    always @(*) begin
        case (csr_addr_ex)
            CSR_MSTATUS: csr_read_data_ex = csr_mstatus_r;
            CSR_MIE:     csr_read_data_ex = csr_mie_r;
            CSR_MTVEC:   csr_read_data_ex = csr_mtvec_r;
            CSR_MEPC:    csr_read_data_ex = csr_mepc_r;
            CSR_MCAUSE:  csr_read_data_ex = csr_mcause_r;
            CSR_MHARTID: csr_read_data_ex = HART_ID;
            default:     csr_read_data_ex = 32'h00000000;
        endcase
    end

    reg        csr_write_req_ex;
    reg [31:0] csr_write_data_ex;
    wire       csr_rs1_nonzero_ex = (rs1_ex != 5'd0);
    wire       csr_uimm_nonzero_ex = (rs1_ex != 5'd0);
    always @(*) begin
        csr_write_req_ex  = 1'b0;
        csr_write_data_ex = csr_read_data_ex;
        case (funct3_ex)
            3'b001, 3'b101: begin
                csr_write_req_ex  = 1'b1;
                csr_write_data_ex = csr_src_ex;
            end
            3'b010: begin
                csr_write_req_ex  = csr_rs1_nonzero_ex;
                csr_write_data_ex = csr_read_data_ex | csr_src_ex;
            end
            3'b110: begin
                csr_write_req_ex  = csr_uimm_nonzero_ex;
                csr_write_data_ex = csr_read_data_ex | csr_src_ex;
            end
            3'b011: begin
                csr_write_req_ex  = csr_rs1_nonzero_ex;
                csr_write_data_ex = csr_read_data_ex & ~csr_src_ex;
            end
            3'b111: begin
                csr_write_req_ex  = csr_uimm_nonzero_ex;
                csr_write_data_ex = csr_read_data_ex & ~csr_src_ex;
            end
            default: begin
                csr_write_req_ex  = 1'b0;
                csr_write_data_ex = csr_read_data_ex;
            end
        endcase
    end

    wire [31:0] alu_result_ex_final = is_csr_ex ? csr_read_data_ex : alu_result_ex;
    assign jalr_target  = (alu_in1_forwarded + imm_ex) & 32'hFFFFFFFE;
    // branch_target_ex = pc_id + imm_id, pre-computed in ID stage to remove
    // this adder from the EX stage critical path.
    assign target_pc_ex = is_mret_ex              ? {csr_mepc_r[31:2], 2'b00} :
                          (opcode_ex == OP_JALR)  ? jalr_target               :
                                                    branch_target_ex;
    assign pc_src_ex    = (branch_ex & branch_taken_ex) | jump_ex | is_mret_ex;

    wire csr_commit_ex  = is_csr_ex && csr_write_req_ex && !stall_any;
    wire mret_commit_ex = is_mret_ex && !stall_any;

    // =========================================================================
    // DEBUG DISPLAY — optional trace for IRQ/MRET/RA tracking
    // =========================================================================
    always @(posedge clk) begin
        if (!rst) begin
`ifdef DEBUG_CPU_TRACE
            if (irq_take)
                $display("[%0t] [IRQ-TAKE] mepc<=%h mtvec=%h pc_ex=%h pc_id=%h pc_if=%h opcode=%b",
                    $time, irq_resume_pc, csr_mtvec_r, pc_ex, pc_id, pc_if, opcode_ex);
            if (ecall_take)
                $display("[%0t] [ECALL-TAKE] mepc<=%h mtvec=%h pc_id=%h pc_if=%h",
                    $time, pc_ex, csr_mtvec_r, pc_id, pc_if);
            if (mret_commit_ex)
                $display("[%0t] [MRET-EX] ret->%h flush_if=%b flush_id=%b pc_id=%h pc_if=%h mstatus=%h",
                    $time, {csr_mepc_r[31:2],2'b00}, flush_if_id_final, flush_id_ex_final, pc_id, pc_if, csr_mstatus_r);
`ifdef DEBUG_CSR_TRACE
            if (csr_commit_ex)
                $display("[%0t] [CSR-WR] pc=%h csr=%h data=%h old_mstatus=%h old_mie=%h old_mepc=%h",
                    $time, pc_ex, csr_addr_ex, csr_write_data_ex, csr_mstatus_r, csr_mie_r, csr_mepc_r);
`endif
`ifdef DEBUG_RA_TRACE
            if (regwrite_wb && (rd_wb == 5'd1))
                $display("[%0t] [WB-RA] ra <= %h", $time, write_back_data_wb);
`endif
`ifdef DEBUG_SP_TRACE
            if (regwrite_wb && (rd_wb == 5'd2))
                $display("[%0t] [WB-SP] sp <= %h pc4_wb=%h", $time, write_back_data_wb, pc_plus_4_wb);
`endif
`ifdef DEBUG_RESTORE_TRACE
            if (((pc_ex >= 32'h000005f0) && (pc_ex <= 32'h000006f0)) ||
                ((pc_plus_4_wb >= 32'h000005f0) && (pc_plus_4_wb <= 32'h000006f4))) begin
                $display("[%0t] [RESTORE-TRACE] pc_ex=%h op_ex=%b rd_ex=%0d alu=%h | wb_rw=%b rd_wb=%0d wb_data=%h pc4_wb=%h mepc=%h mstatus=%h",
                    $time, pc_ex, opcode_ex, rd_ex, alu_result_ex,
                    regwrite_wb, rd_wb, write_back_data_wb, pc_plus_4_wb,
                    csr_mepc_r, csr_mstatus_r);
            end
`endif
`ifdef DEBUG_BRANCH_TRACE
            if (branch_ex)
                $display("[%0t] [BR-EX] pc=%h taken=%b pred=%b a=%h b=%h funct3=%b target=%h",
                    $time, pc_ex, branch_taken_ex, predict_taken_ex,
                    alu_in1_forwarded, alu_in2_pre_mux, funct3_ex, branch_target_ex);
            if (jump_ex)
                $display("[%0t] [JMP-EX] pc=%h opcode=%b rd=%0d rs1=%0d a_raw=%h a_fwd=%h imm=%h target=%h pc4=%h",
                    $time, pc_ex, opcode_ex, rd_ex, rs1_ex, alu_in1,
                    alu_in1_forwarded, imm_ex, target_pc_ex, pc_plus_4_ex);
`endif
`ifdef DEBUG_ALU_TRACE
            if (regwrite_ex && ((rd_ex == 5'd15 || rd_ex == 5'd14 || rd_ex == 5'd12) ||
                                (pc_ex >= 32'h00000340 && pc_ex < 32'h00000390) ||
                                (pc_ex >= 32'h00000bdc && pc_ex < 32'h00000c00)))
                $display("[%0t] [ALU-EX] pc=%h opcode=%b rd=%0d alu=%h mem_rw=%b mem_rd=%0d wb_rw=%b wb_rd=%0d fwd_a=%b fwd_b=%b",
                    $time, pc_ex, opcode_ex, rd_ex, alu_result_ex,
                    regwrite_mem, rd_mem, regwrite_wb, rd_wb, forward_a, forward_b);
`endif
`ifdef DEBUG_STORE_TRACE
            if (memwrite_mem)
                $display("[%0t] [STORE-MEM] pc=%h addr=%h data=%h rd=%0d funct3=%b pc_ex=%h op_ex=%b",
                    $time, pc_plus_4_mem - 32'd4, alu_result_mem, wdata_shifted,
                    rd_mem, funct3_mem, pc_ex, opcode_ex);
`endif
`ifdef DEBUG_PHASE4_TRACE
            if (((pc_ex >= 32'h000009e0) && (pc_ex <= 32'h00000a04)) ||
                ((pc_plus_4_mem >= 32'h000009e0) && (pc_plus_4_mem <= 32'h00000a04)) ||
                ((pc_ex >= 32'h00000da4) && (pc_ex <= 32'h00000e30)) ||
                ((pc_plus_4_mem >= 32'h00000da4) && (pc_plus_4_mem <= 32'h00000e30))) begin
                $display("[%0t] [PH4] stall=%b lsu_dep=%b pc_ex=%h op=%b rd=%0d rs1=%0d rs2=%0d fa=%b fb=%b a=%h af=%h b=%h bf=%h imm=%h alu=%h | mem_pc=%h mr=%b mw=%b mem_rd=%0d addr=%h wdata=%h wstrb=%b | wb_rw=%b wb_rd=%0d wb_data=%h",
                    $time, stall_any, lsu_dep_stall,
                    pc_ex, opcode_ex, rd_ex, rs1_ex, rs2_ex, forward_a, forward_b,
                    alu_in1, alu_in1_forwarded, alu_in2_pre_mux, alu_in2,
                    imm_ex, alu_result_ex,
                    pc_plus_4_mem - 32'd4, memread_mem, memwrite_mem, rd_mem,
                    alu_result_mem, wdata_shifted, lsu_req_wstrb,
                    regwrite_wb, rd_wb, write_back_data_wb);
            end
`endif
`endif
        end
    end

    // =========================================================================
    // EX/MEM PIPELINE REGISTER (standalone module)
    // =========================================================================
    PIPELINE_REG_EX_MEM ex_mem_reg (
        .clock          (clk),
        .reset          (rst),
        .stall_ex_mem   (stall_ex_mem),
        .stall_any      (stall_any),
        .fence_stall    (fence_stall),
        // Control inputs
        .regwrite_in    (regwrite_ex),
        .memread_in     (memread_ex),
        .memwrite_in    (memwrite_ex),
        .jump_in        (jump_ex),
        // Data inputs
        .alu_result_in  (alu_result_ex_final),
        .write_data_in  (alu_in2_pre_mux),
        .pc_plus_4_in   (pc_plus_4_ex),
        .rd_in          (rd_ex),
        .byte_size_in   (byte_size_ex),
        .funct3_in      (funct3_ex),
        .is_mul_in      (is_mul_ex),
        // Control outputs
        .regwrite_out   (regwrite_mem),
        .memread_out    (memread_mem),
        .memwrite_out   (memwrite_mem),
        .jump_out       (jump_mem),
        // Data outputs
        .alu_result_out (alu_result_mem),
        .write_data_out (write_data_mem),
        .pc_plus_4_out  (pc_plus_4_mem),
        .rd_out         (rd_mem),
        .byte_size_out  (byte_size_mem),
        .funct3_out     (funct3_mem),
        .is_mul_out     (is_mul_mem)
    );

    // =========================================================================
    // STAGE 4: MEM — via LSU
    // =========================================================================

    // =========================================================================
    // LSU REQUEST GENERATION & BYTE LANE CONTROL
    // Formats byte strobes and shifts store data according to the memory address.
    // Handles LSU request firing and deduplication to avoid double issues.
    // =========================================================================
    // [FIX-BYTELANE] Store byte strobe
    reg [3:0] wstrb_comb;
    always @(*) begin
        case (byte_size_mem)
            2'b00:   wstrb_comb = 4'b0001 << alu_result_mem[1:0];
            2'b01:   wstrb_comb = 4'b0011 << {alu_result_mem[1], 1'b0};
            2'b10:   wstrb_comb = 4'b1111;
            default: wstrb_comb = 4'b0000;
        endcase
    end
    assign lsu_req_wstrb = wstrb_comb;

    // [FIX-BYTELANE] Store data shift
    reg [31:0] wdata_shifted;
    always @(*) begin
        case (byte_size_mem)
            2'b00:   wdata_shifted = {24'b0, write_data_mem[7:0]} << (alu_result_mem[1:0] * 8);
            2'b01:   wdata_shifted = {16'b0, write_data_mem[15:0]} << (alu_result_mem[1] ? 16 : 0);
            2'b10:   wdata_shifted = write_data_mem;
            default: wdata_shifted = write_data_mem;
        endcase
    end

    // [FIX-DOUBLE-ISSUE] Track which MEM-stage request has already been
    // accepted by LSU. Signature includes PC+4 so consecutive identical
    // loads/stores still issue independently.
    reg        lsu_req_sent;
    reg [74:0] lsu_req_sig_r;
    wire       lsu_req_valid_raw = memread_mem | memwrite_mem;
    wire [74:0] lsu_req_sig = {memread_mem, memwrite_mem, rd_mem, lsu_req_wstrb, alu_result_mem, pc_plus_4_mem};
    wire       lsu_req_new  = (lsu_req_sig != lsu_req_sig_r);
    wire       lsu_req_fire;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lsu_req_sent  <= 1'b0;
            lsu_req_sig_r <= 75'b0;
        end else begin
            if (lsu_req_fire) begin
                lsu_req_sent  <= 1'b1;
                lsu_req_sig_r <= lsu_req_sig;
            end else if (!lsu_req_valid_raw) begin
                lsu_req_sent <= 1'b0;
            end else if (lsu_req_new) begin
                lsu_req_sent  <= 1'b0;
                lsu_req_sig_r <= lsu_req_sig;
            end
        end
    end
    assign lsu_req_valid = lsu_req_valid_raw & (!lsu_req_sent || lsu_req_new);
    assign lsu_req_fire  = lsu_req_valid && lsu_req_ready;
    assign mem_stage_wait = lsu_req_valid && !lsu_req_ready;

    wire soc_lsu_sb_empty;

    LSU lsu_unit (
        .clk         (clk),           .rst         (rst),
        .req_valid   (lsu_req_valid),  .req_ready   (lsu_req_ready),
        .req_addr    (alu_result_mem), .req_wdata   (wdata_shifted),
        .req_wstrb   (lsu_req_wstrb),  .req_is_load (memread_mem),
        .req_rd      (rd_mem),         .req_funct3  (funct3_mem),
        // fence reaches LSU only after hazard logic has observed quiescent LSU.
        // This keeps FENCE from blocking pre-existing load/store drain activity.
        .fence       (|dcache_fence_type),
        .result_valid(lsu_result_valid), .result_data(lsu_result_data),
        .result_rd   (lsu_result_rd),  .result_ack  (lsu_result_ack),
        .scoreboard  (lsu_scoreboard), .lsu_idle    (lsu_idle),
        .dcache_req  (dcache_req),     .dcache_we   (dcache_we),
        .dcache_addr (dcache_addr),    .dcache_wdata(dcache_wdata),
        .dcache_wstrb(dcache_wstrb),   .dcache_rdata(dcache_rdata),
        .dcache_ready(dcache_ready)
    );

    assign soc_lsu_sb_empty = lsu_idle;

    // =========================================================================
    // MEM/WB REGISTER (standalone module)
    // =========================================================================

    // =========================================================================
    // MEM/WB WRITE-BACK CONTROL & LSU COMMIT LOGIC
    // Tracks when an LSU memory transaction completes and is ready to be written back.
    // Synchronizes data propagation from the MEM stage down to the WB stage.
    // =========================================================================
    reg lsu_committed_r;
    wire wb_passthrough_valid = !stall_ex_mem && !lsu_committed_r && !memread_mem && regwrite_mem && (rd_mem != 5'b0); // [FIX-WB-NOP] NOP (rd=x0) must not block LSU commit
    assign lsu_result_commit = lsu_result_valid && !wb_passthrough_valid;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lsu_committed_r <= 1'b0;
        else
            lsu_committed_r <= lsu_result_commit;
    end

    // Hold LSU result until MEM/WB is free so loads do not clobber ALU/MUL WB.
    assign lsu_result_ack = lsu_result_commit;

    PIPELINE_REG_MEM_WB mem_wb_reg (
        .clock            (clk),
        .reset            (rst),
        .stall_ex_mem     (stall_ex_mem),
        .lsu_committed    (lsu_committed_r),
        // LSU result path (priority)
        .lsu_result_valid (lsu_result_commit),
        .lsu_result_data  (lsu_result_data),
        .lsu_result_rd    (lsu_result_rd),
        // Normal MEM stage path
        .regwrite_in      (regwrite_mem),
        .memread_in       (memread_mem),
        .jump_in          (jump_mem),
        .alu_result_in    (alu_result_mem),
        .pc_plus_4_in     (pc_plus_4_mem),
        .rd_in            (rd_mem),
        .is_mul_in        (is_mul_mem),
        // Outputs to WB
        .regwrite_out     (regwrite_wb),
        .memtoreg_out     (memtoreg_wb),
        .jump_out         (jump_wb),
        .alu_result_out   (alu_result_wb),
        .mem_data_out     (mem_data_wb),
        .pc_plus_4_out    (pc_plus_4_wb),
        .rd_out           (rd_wb),
        .is_mul_out       (is_mul_wb)
    );

    // =========================================================================
    // STAGE 5: WB
    // =========================================================================

    // =========================================================================
    // WRITE-BACK DATA MULTIPLEXING (WB STAGE)
    // Selects the final data to be written into the destination register (RD).
    // Mutually exclusive sources: ALU result, Load Data, PC+4 (Jump), or MUL result.
    // =========================================================================
    // AND-OR MUX: 4 cases mutually exclusive (jump/mul/load/alu can't overlap).
    // is_alu_wb is the complement so selectors are exhaustive (Fix 11).
    wire is_alu_wb = !jump_wb && !is_mul_wb && !memtoreg_wb;
    assign write_back_data_wb = ({32{jump_wb}}     & pc_plus_4_wb)     |
                                ({32{is_mul_wb}}   & mul_result_direct) |
                                ({32{memtoreg_wb}} & mem_data_wb)       |
                                ({32{is_alu_wb}}   & alu_result_wb);

`ifdef DEBUG_WB_TRACE
    always @(posedge clk) begin
        if (!rst && ((regwrite_mem && rd_mem == 5'd1) || (regwrite_wb && rd_wb == 5'd1))) begin
            $display("[%0t] [WB-PIPE] mem:rw=%b j=%b rd=%0d alu=%h pc4=%h | wb:rw=%b j=%b rd=%0d alu=%h pc4=%h data=%h",
                     $time, regwrite_mem, jump_mem, rd_mem, alu_result_mem, pc_plus_4_mem,
                     regwrite_wb, jump_wb, rd_wb, alu_result_wb, pc_plus_4_wb, write_back_data_wb);
        end
    end
`ifdef DEBUG_REG_TRACE
    always @(posedge clk) begin
        if (!rst && ((regwrite_mem && (rd_mem == 5'd15 || rd_mem == 5'd12)) ||
                     (regwrite_wb && (rd_wb == 5'd15 || rd_wb == 5'd12)))) begin
            $display("[%0t] [REG-PIPE] mem:rw=%b rd=%0d alu=%h | wb:rw=%b rd=%0d alu=%h data=%h",
                     $time, regwrite_mem, rd_mem, alu_result_mem,
                     regwrite_wb, rd_wb, alu_result_wb, write_back_data_wb);
        end
    end
`endif
`endif

    // =========================================================================
    // HAZARD DETECTION UNIT
    // =========================================================================
    hazard_detection hazard_unit (
        .clk            (clk),
        .rst            (rst),
        .memread_id_ex  (memread_ex),
        .rd_id_ex       (rd_ex),
        .rs1_id         (rs1_id),
        .rs2_id         (rs2_id),
        .rs1_used_id    (rs1_used_id),
        .rs2_used_id    (rs2_used_id),
        .branch_taken   (pc_src_ex),
        .imem_ready     (imem_ready),
        .lsu_scoreboard (lsu_scoreboard),
        .mem_stage_pending(lsu_req_valid),
        .memread_mem_stage(memread_mem),
        .rd_mem_stage   (rd_mem),
        .fence_id       (fence_id),
        .lsu_idle       (lsu_idle),
        .mul_in_ex      (is_mul_ex),
        .mul_in_mem_stage(is_mul_mem),
        .predict_taken_ex(predict_taken_ex),
        .predict_taken_id(predict_taken_id),
        .mispredict_ex  (mispredict_ex),
        .stall          (stall),
        .stall_if       (stall_if),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex),
        .fence_stall    (fence_stall),
        .lsu_dep_stall  (lsu_dep_stall),
        .mul_ex_stall   (mul_ex_stall_wire)
    );

    wire [31:0] irq_cause_code = ext_irq_s2 ? 32'h8000000B :
                                 tmr_irq_s2 ? 32'h80000007 :
                                              32'h80000003;
    wire [31:0] irq_resume_pc = ex_valid_for_irq
                               ? (branch_ex
                                  ? (branch_taken_ex ? branch_target_ex : pc_plus_4_ex)
                                  : pc_plus_4_ex)
                               : pc_id;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            csr_mstatus_r <= 32'h00000000;
            csr_mie_r     <= 32'h00000000;
            csr_mtvec_r   <= 32'h00000000;
            csr_mepc_r    <= 32'h00000000;
            csr_mcause_r  <= 32'h00000000;
        end else begin
            if (trap_take) begin
                csr_mepc_r       <= ecall_take ? pc_ex : irq_resume_pc;
                csr_mcause_r     <= ecall_take ? 32'h0000000b : irq_cause_code;
                csr_mstatus_r[7] <= csr_mstatus_r[3];
                csr_mstatus_r[3] <= 1'b0;
            end else if (mret_commit_ex) begin
                csr_mstatus_r[3] <= csr_mstatus_r[7];
                csr_mstatus_r[7] <= 1'b1;
            end

            if (csr_commit_ex) begin
                case (csr_addr_ex)
                    CSR_MSTATUS: csr_mstatus_r <= csr_write_data_ex;
                    CSR_MIE:     csr_mie_r     <= csr_write_data_ex;
                    CSR_MTVEC:   csr_mtvec_r   <= csr_write_data_ex;
                    CSR_MEPC:    csr_mepc_r    <= csr_write_data_ex;
                    CSR_MCAUSE:  csr_mcause_r  <= csr_write_data_ex;
                    default: begin end
                endcase
            end
        end
    end

endmodule
