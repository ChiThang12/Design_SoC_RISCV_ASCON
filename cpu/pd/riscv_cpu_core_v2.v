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

module riscv_cpu_core (
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
    output wire [1:0]  dcache_fence_type,

    input  wire external_irq,
    input  wire timer_irq,
    input  wire sw_irq,

    // =========================================================================
    // JTAG Debug Interface  (kết nối với jtag_debug_top → riscv_dm)
    //
    // WHY cần 4 tín hiệu này:
    //   haltreq   : JTAG DM yêu cầu CPU dừng để debugger đọc/ghi registers.
    //               CPU phải drain pipeline và LSU store buffer trước khi báo halted.
    //   resumereq : DM yêu cầu CPU tiếp tục chạy bình thường.
    //   halted    : CPU báo cho DM biết đã vào D-mode (pipeline đóng băng hoàn toàn).
    //               DM chỉ được phép truy cập register file khi halted=1.
    //   running   : CPU báo đang chạy bình thường (halted=0 chưa đủ vì còn HALTING).
    //
    // WHY KHÔNG dùng rst để halt:
    //   rst xóa toàn bộ trạng thái CPU (PC, registers) → không thể resume.
    //   Debug mode chỉ đóng băng, không xóa — debugger có thể đọc PC, regs,
    //   rồi set breakpoint và resume từ đúng chỗ đã dừng.
    //
    // Kết nối trong soc_top.v:
    //   .debug_haltreq   (jtag_haltreq),    // từ u_jtag.haltreq
    //   .debug_resumereq (jtag_resumereq),   // từ u_jtag.resumereq
    //   .debug_halted    (jtag_halted),      // → u_jtag.halted
    //   .debug_running   (jtag_running)      // → u_jtag.running
    // =========================================================================
    input  wire debug_haltreq,    // DM → CPU: yêu cầu vào D-mode
    input  wire debug_resumereq,  // DM → CPU: yêu cầu thoát D-mode
    output wire debug_halted,     // CPU → DM: đang trong D-mode, pipeline frozen
    output wire debug_running     // CPU → DM: đang chạy bình thường
);

    // =========================================================================
    // IRQ aggregation
    // =========================================================================
    wire irq_pending = external_irq | timer_irq | sw_irq;

    reg irq_pending_lat;
    always @(posedge clk or posedge rst) begin
        if (rst)
            irq_pending_lat <= 1'b0;
        else if (irq_pending)
            irq_pending_lat <= 1'b1;
        else if (irq_flush_done)
            irq_pending_lat <= 1'b0;
    end

    reg irq_flush_done_r;
    always @(posedge clk or posedge rst) begin
        if (rst)
            irq_flush_done_r <= 1'b0;
        else
            irq_flush_done_r <= irq_pending_lat & ~irq_flush_done_r;
    end
    wire irq_flush_done = irq_flush_done_r;

    // Register irq_flush: removes combinational feedback into pipeline flush
    // signals, trading 1 extra cycle of IRQ latency for better Fmax.
    reg irq_flush_r;
    always @(posedge clk or posedge rst) begin
        if (rst) irq_flush_r <= 1'b0;
        else     irq_flush_r <= irq_pending_lat & ~irq_flush_done_r;
    end
    wire irq_flush = irq_flush_r;

    // =========================================================================
    // DEBUG MODE FSM
    //
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
                    if (debug_haltreq && lsu_sb_empty_w && !dcache_req) begin
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
                    // WHY check !debug_haltreq: DM có thể giữ haltreq=1 nhiều
                    // cycle. Chỉ resume khi resumereq pulse xuất hiện.
                    if (debug_resumereq) begin
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
    wire regwrite_id, alusrc_id, memread_id, memwrite_id, memtoreg_id;
    wire branch_id, jump_id, fence_id;
    wire [1:0] byte_size_id;

    // =========================================================================
    // [FENCE-TYPE] Decode pred/succ bits từ FENCE instruction
    // =========================================================================
    wire [3:0] fence_pred      = instr_id[27:24];
    wire       fence_is_fencei = funct3_id[0];

    wire fence_active = fence_id && !fence_stall;
    assign dcache_fence_type[0] = fence_active && (fence_is_fencei | fence_pred[0] | fence_pred[3]);
    assign dcache_fence_type[1] = fence_active && (fence_is_fencei | fence_pred[1] | fence_pred[3]);

    wire [31:0] read_data1_id, read_data2_id, imm_id;

    wire regwrite_ex, alusrc_ex, memread_ex, memwrite_ex, memtoreg_ex;
    wire branch_ex, jump_ex;
    wire [31:0] read_data1_ex, read_data2_ex, imm_ex, pc_ex;
    wire [4:0]  rs1_ex, rs2_ex, rd_ex;
    wire [2:0]  funct3_ex;
    wire [6:0]  funct7_ex;
    wire [3:0]  alu_control_ex;
    wire [1:0]  byte_size_ex;
    wire [6:0]  opcode_ex;

    wire [31:0] alu_in1, alu_in2, alu_in2_pre_mux, alu_in1_forwarded;
    wire [31:0] alu_result_ex;
    wire zero_flag_ex, less_than_ex, less_than_u_ex;
    wire branch_taken_ex;
    wire [31:0] target_pc_ex;
    wire pc_src_ex;
    wire [31:0] pc_plus_4_ex;

    wire regwrite_mem, memread_mem, memwrite_mem, memtoreg_mem;
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
    wire flush_if_id, flush_id_ex;

    // stall_any includes debug_mode to freeze entire pipeline during D-mode
    assign stall_any = stall | stall_if | debug_mode;

    // stall_ex_mem: only LSU dependency stall freezes EX/MEM
    // (fence_stall must NOT freeze — pre-fence store must reach MEM)
    wire stall_ex_mem = lsu_dep_stall;

    wire flush_if_id_final = flush_if_id | irq_flush;
    wire flush_id_ex_final = flush_id_ex | irq_flush;

    // =========================================================================
    // STAGE 1: IF
    // =========================================================================
    IFU instruction_fetch (
        .clock            (clk),
        .reset            (rst),
        .pc_src           (pc_src_ex),
        .stall            (stall_any),      // debug_mode → stall_any → IFU dừng fetch
        .target_pc        (target_pc_ex),
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
        .memtoreg   (memtoreg_id),
        .branch     (branch_id),
        .jump       (jump_id),
        .aluop      (),
        .byte_size  (byte_size_id),
        .fence      (fence_id)
    );

    reg_file register_file (
        .clock        (clk),
        .reset        (rst),
        .read_reg_num1(rs1_id),
        .read_reg_num2(rs2_id),
        .read_data1   (read_data1_id),
        .read_data2   (read_data2_id),
        .regwrite     (regwrite_wb),
        .write_reg    (rd_wb),
        .write_data   (write_back_data_wb)
    );

    imm_gen immediate_generator (
        .instr(instr_id),
        .imm  (imm_id)
    );

    // =========================================================================
    // ID/EX PIPELINE REGISTER (standalone module)
    // =========================================================================
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
        // Control inputs
        .regwrite_in     (regwrite_id),
        .alusrc_in       (alusrc_id),
        .memread_in      (memread_id),
        .memwrite_in     (memwrite_id),
        .memtoreg_in     (memtoreg_id),
        .branch_in       (branch_id),
        .jump_in         (jump_id),
        // Data inputs
        .read_data1_in   (read_data1_id),
        .read_data2_in   (read_data2_id),
        .imm_in          (imm_id),
        .pc_in           (pc_id),
        // Register addresses
        .rs1_in          (rs1_id),
        .rs2_in          (rs2_id),
        .rd_in           (rd_id),
        // Function codes
        .funct3_in       (funct3_id),
        .funct7_in       (funct7_id),
        .alu_control_in  (alu_control_id),
        .byte_size_in    (byte_size_id),
        .opcode_in       (opcode_id),
        // Control outputs
        .regwrite_out    (regwrite_ex),
        .alusrc_out      (alusrc_ex),
        .memread_out     (memread_ex),
        .memwrite_out    (memwrite_ex),
        .memtoreg_out    (memtoreg_ex),
        .branch_out      (branch_ex),
        .jump_out        (jump_ex),
        // Data outputs
        .read_data1_out  (read_data1_ex),
        .read_data2_out  (read_data2_ex),
        .imm_out         (imm_ex),
        .pc_out          (pc_ex),
        // Register address outputs
        .rs1_out         (rs1_ex),
        .rs2_out         (rs2_ex),
        .rd_out          (rd_ex),
        // Function code outputs
        .funct3_out      (funct3_ex),
        .funct7_out      (funct7_ex),
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

    assign alu_in1_forwarded = (forward_a == 2'b10) ? alu_result_mem :
                               (forward_a == 2'b01) ? write_back_data_wb :
                               read_data1_ex;

    assign alu_in1 = (opcode_ex == 7'b0110111) ? 32'h0 :
                     (opcode_ex == 7'b0010111) ? pc_ex  :
                     alu_in1_forwarded;

    assign alu_in2_pre_mux = (forward_b == 2'b10) ? alu_result_mem :
                             (forward_b == 2'b01) ? write_back_data_wb :
                             read_data2_ex;

    assign alu_in2 = alusrc_ex ? imm_ex : alu_in2_pre_mux;

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
    wire        mul_valid_ex = is_mul_ex & !stall_any & !flush_id_ex_final;

    riscv_multiplier multiplier_unit (
        .clk_i            (clk),
        .rst_i            (rst),
        .mul_valid_i      (mul_valid_ex),
        .mul_op_i         (mul_op_ex),
        .operand_a_i      (alu_in1_forwarded),  // forwarded rs1 (pre-LUI/AUIPC mux)
        .operand_b_i      (alu_in2_pre_mux),    // forwarded rs2 (pre-alusrc mux)
        .hold_i           (stall_any),
        .writeback_value_o(mul_result_direct)   // valid at WB stage (2 cycles after EX)
    );

    assign pc_plus_4_ex = pc_ex + 32'd4;

    wire [31:0] jalr_target;
    assign jalr_target  = (alu_in1 + imm_ex) & 32'hFFFFFFFE;
    assign target_pc_ex = (opcode_ex == 7'b1100111) ? jalr_target : pc_ex + imm_ex;
    assign pc_src_ex    = (branch_ex & branch_taken_ex) | jump_ex;

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
        .memtoreg_in    (memtoreg_ex),
        .jump_in        (jump_ex),
        // Data inputs
        .alu_result_in  (alu_result_ex),
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
        .memtoreg_out   (memtoreg_mem),
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

    // [FIX-DOUBLE-ISSUE] lsu_req_sent
    reg lsu_req_sent;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lsu_req_sent <= 1'b0;
        else begin
            if (!stall_ex_mem && !stall_any)
                lsu_req_sent <= 1'b0;
            else if (lsu_req_valid && lsu_req_ready)
                lsu_req_sent <= 1'b1;
        end
    end
    assign lsu_req_valid = (memread_mem | memwrite_mem) & !lsu_req_sent;

    wire soc_lsu_sb_empty;

    LSU lsu_unit (
        .clk         (clk),           .rst         (rst),
        .req_valid   (lsu_req_valid),  .req_ready   (lsu_req_ready),
        .req_addr    (alu_result_mem), .req_wdata   (wdata_shifted),
        .req_wstrb   (lsu_req_wstrb),  .req_is_load (memread_mem),
        .req_rd      (rd_mem),         .req_funct3  (funct3_mem),
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
    reg lsu_committed_r;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lsu_committed_r <= 1'b0;
        else
            lsu_committed_r <= lsu_result_valid;
    end

    // LSU result always ACK'd immediately
    assign lsu_result_ack = lsu_result_valid;

    PIPELINE_REG_MEM_WB mem_wb_reg (
        .clock            (clk),
        .reset            (rst),
        .stall_ex_mem     (stall_ex_mem),
        .lsu_committed    (lsu_committed_r),
        // LSU result path (priority)
        .lsu_result_valid (lsu_result_valid),
        .lsu_result_data  (lsu_result_data),
        .lsu_result_rd    (lsu_result_rd),
        // Normal MEM stage path
        .regwrite_in      (regwrite_mem),
        .memread_in       (memread_mem),
        .memtoreg_in      (memtoreg_mem),
        .jump_in          (jump_mem),
        .alu_result_in    (alu_result_mem),
        .pc_plus_4_in     (pc_plus_4_mem),
        .rd_in            (rd_mem),
        .is_mul_in        (is_mul_mem),
        .mul_result_in    (32'h0),       // unused: multiplier output timed via writeback_value_o
        // Outputs to WB
        .regwrite_out     (regwrite_wb),
        .memtoreg_out     (memtoreg_wb),
        .jump_out         (jump_wb),
        .alu_result_out   (alu_result_wb),
        .mem_data_out     (mem_data_wb),
        .pc_plus_4_out    (pc_plus_4_wb),
        .rd_out           (rd_wb),
        .is_mul_out       (is_mul_wb),
        .mul_result_out   ()              // unused: direct multiplier output used in WB mux
    );

    // =========================================================================
    // STAGE 5: WB
    // =========================================================================
    // Priority: jump (link reg) > MUL result > load data > ALU result
    assign write_back_data_wb = jump_wb     ? pc_plus_4_wb    :
                                is_mul_wb   ? mul_result_direct :
                                memtoreg_wb ? mem_data_wb      :
                                              alu_result_wb;

    // =========================================================================
    // HAZARD DETECTION UNIT
    // =========================================================================
    hazard_detection hazard_unit (
        .memread_id_ex  (memread_ex),
        .rd_id_ex       (rd_ex),
        .rs1_id         (rs1_id),
        .rs2_id         (rs2_id),
        .memread_mem    (memread_mem),
        .rd_mem         (rd_mem),
        .branch_taken   (pc_src_ex),
        .imem_ready     (imem_ready),
        .lsu_scoreboard (lsu_scoreboard),
        .fence_id       (fence_id),
        .lsu_idle       (lsu_idle),
        .mul_in_ex      (is_mul_ex),
        .stall          (stall),
        .stall_if       (stall_if),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex),
        .fence_stall    (fence_stall),
        .lsu_dep_stall  (lsu_dep_stall)
    );

// synopsys translate_off
// ── Debug monitors (simulation only) ──
reg [31:0] lsu_store_count;
always @(posedge clk or posedge rst) begin
    if (rst) lsu_store_count <= 0;
    else if (lsu_req_valid && lsu_req_ready && memwrite_mem)
        lsu_store_count <= lsu_store_count + 1;
end

always @(posedge clk) begin
    if (!rst && lsu_req_valid && lsu_req_ready && memwrite_mem)
        $display("[%0t] [LSU-STORE] addr=0x%08h data=0x%08h strb=%04b sent=%b stall_any=%b stall_ex=%b",
                 $time, alu_result_mem, wdata_shifted, lsu_req_wstrb,
                 lsu_req_sent, stall_any, stall_ex_mem);
end

always @(posedge clk) begin
    if (!rst && (forward_a == 2'b10 || forward_b == 2'b10))
        $display("[%0t] [FWD-MEM] fwd_a=%b fwd_b=%b rd_mem=x%0d alu_mem=0x%08h rs1=%0d rs2=%0d stall_any=%b regwrite_mem=%b pc_ex=0x%08h",
                 $time, forward_a, forward_b, rd_mem, alu_result_mem,
                 rs1_ex, rs2_ex, stall_any, regwrite_mem, pc_ex);
end

always @(posedge clk) begin
    if (!rst && regwrite_wb && rd_wb != 0 && (write_back_data_wb[31:8] != 0) && write_back_data_wb != 32'h10001ff0 && write_back_data_wb != 32'h10000100)
        $display("[%0t] [WB] x%0d <= 0x%08h  memtoreg=%b jump=%b",
                 $time, rd_wb, write_back_data_wb, memtoreg_wb, jump_wb);
end

initial $display("[RTL-VERSION] riscv_cpu_core CLEAN-v3 + modular pipeline registers loaded");
// synopsys translate_on

endmodule