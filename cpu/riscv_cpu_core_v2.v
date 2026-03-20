`include "cpu/core/IFU.v"
`include "cpu/core/reg_file.v"
`include "cpu/core/imm_gen.v"
`include "cpu/core/control.v"
`include "cpu/core/alu.v"
`include "cpu/core/branch_logic.v"
`include "cpu/core/forwarding_unit.v"
`include "cpu/core/hazard_detection.v"
`include "cpu/core/PIPELINE_REG_IF_ID.v"
`include "cpu/core/PIPELINE_REG_ID_EX.v"
`include "cpu/core/PIPELINE_REG_EX_WB.v"
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
    output wire [1:0]      dcache_fence_type,

    input  wire external_irq,
    input  wire timer_irq,
    input  wire sw_irq
);

    // ========================================================================
    // IRQ aggregation
    // ========================================================================
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
    wire irq_flush      = irq_pending_lat & ~irq_flush_done_r;

    // ========================================================================
    // Pipeline stage wires
    // ========================================================================
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
    // FENCE encoding: instr[31:28]=fm, instr[27:24]=pred, instr[23:20]=succ
    //   pred bit3=I, bit2=O, bit1=R, bit0=W
    // fence w,w   : pred=0001, succ=0001 → fence_type=2'b01 (flush only)
    // fence r,r   : pred=0010, succ=0010 → fence_type=2'b10 (invalidate only)
    // fence iorw  : pred=1111, succ=1111 → fence_type=2'b11 (flush+invalidate)
    // fence.i     : funct3=1             → fence_type=2'b11 (full flush+invalidate)
    // fence_type[0]=1 → flush dirty lines (write-back)  ← pred has W(bit0) or I(bit3)
    // fence_type[1]=1 → invalidate read cache            ← pred has R(bit1) or I(bit3)
    // =========================================================================
    wire [3:0] fence_pred    = instr_id[27:24]; // pred field
    wire       fence_is_fencei = funct3_id[0];  // FENCE.I: funct3=001

    wire fence_active = fence_id && !fence_stall;
    // flush dirty  : pred W(bit0) OR pred I(bit3) OR FENCE.I
    // invalidate   : pred R(bit1) OR pred I(bit3) OR FENCE.I
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

    wire [31:0] alu_in1, alu_in2, alu_in2_pre_mux;
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

    wire [1:0] forward_a, forward_b;
    wire stall, stall_if, stall_any;
    wire fence_stall;
    wire flush_if_id, flush_id_ex;

    assign stall_any = stall | stall_if;

    // [FIX-EXMEM-GATE] EX/MEM phải freeze chọn lọc:
    //   - lsu_dependency_stall: in-flight load ở LSU, instruction mới cần
    //     register đó → EX/MEM phải freeze (pipeline stall thực sự).
    //   - fence_stall: chờ LSU drain → EX/MEM phải freeze.
    //   - load_use_hazard: load ở EX, next instruction cần rd →
    //     EX/MEM PHẢI ADVANCE để load vào MEM, ID/EX được flush (NOP).
    //     Nếu freeze EX/MEM, load bị kẹt ở EX mãi → không bao giờ execute!
    //   - mem_load_stall: tương tự → EX/MEM advance.
    //   - stall_if (ICache miss): EX/MEM không liên quan → advance.
    //
    // stall_ex_mem = 1 → freeze; = 0 → advance
    // Chỉ freeze khi: lsu_dependency_stall OR fence_stall
    wire lsu_dependency_stall_w = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                                   (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);
    wire stall_ex_mem = lsu_dependency_stall_w | fence_stall;

    wire flush_if_id_final = flush_if_id | irq_flush;
    wire flush_id_ex_final = flush_id_ex | irq_flush;

    // dcache_fence_type: expose ra soc_top để nối vào dcache_top.fence_type
    // (logic decode ở wire fence_active + dcache_fence_type[1:0] phía trên)

    // ========================================================================
    // STAGE 1: IF
    // ========================================================================
    IFU instruction_fetch (
        .clock            (clk),
        .reset            (rst),
        .pc_src           (pc_src_ex),
        .stall            (stall_any),
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

    // ========================================================================
    // STAGE 2: ID
    // ========================================================================
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

    // ========================================================================
    // ID/EX PIPELINE REGISTER
    // ========================================================================
    reg regwrite_id_ex, alusrc_id_ex, memread_id_ex, memwrite_id_ex;
    reg memtoreg_id_ex, branch_id_ex, jump_id_ex;
    reg [31:0] read_data1_id_ex, read_data2_id_ex, imm_id_ex, pc_id_ex;
    reg [4:0]  rs1_id_ex, rs2_id_ex, rd_id_ex;
    reg [2:0]  funct3_id_ex;
    reg [6:0]  funct7_id_ex;
    reg [3:0]  alu_control_id_ex;
    reg [1:0]  byte_size_id_ex;
    reg [6:0]  opcode_id_ex;

    always @(posedge clk or posedge rst) begin
        if (rst || flush_id_ex_final) begin
            regwrite_id_ex    <= 1'b0; alusrc_id_ex      <= 1'b0;
            memread_id_ex     <= 1'b0; memwrite_id_ex    <= 1'b0;
            memtoreg_id_ex    <= 1'b0; branch_id_ex      <= 1'b0;
            jump_id_ex        <= 1'b0; read_data1_id_ex  <= 32'h0;
            read_data2_id_ex  <= 32'h0; imm_id_ex        <= 32'h0;
            pc_id_ex          <= 32'h0; rs1_id_ex        <= 5'b0;
            rs2_id_ex         <= 5'b0; rd_id_ex          <= 5'b0;
            funct3_id_ex      <= 3'b0; funct7_id_ex      <= 7'b0;
            alu_control_id_ex <= 4'b0; byte_size_id_ex   <= 2'b0;
            opcode_id_ex      <= 7'b0;
        end else if (!stall_any) begin
            regwrite_id_ex    <= regwrite_id;    alusrc_id_ex      <= alusrc_id;
            memread_id_ex     <= memread_id;     memwrite_id_ex    <= memwrite_id;
            memtoreg_id_ex    <= memtoreg_id;    branch_id_ex      <= branch_id;
            jump_id_ex        <= jump_id;        read_data1_id_ex  <= read_data1_id;
            read_data2_id_ex  <= read_data2_id;  imm_id_ex         <= imm_id;
            pc_id_ex          <= pc_id;          rs1_id_ex         <= rs1_id;
            rs2_id_ex         <= rs2_id;         rd_id_ex          <= rd_id;
            funct3_id_ex      <= funct3_id;      funct7_id_ex      <= funct7_id;
            alu_control_id_ex <= alu_control_id;  byte_size_id_ex  <= byte_size_id;
            opcode_id_ex      <= opcode_id;
        end
    end

    assign regwrite_ex    = regwrite_id_ex;    assign alusrc_ex      = alusrc_id_ex;
    assign memread_ex     = memread_id_ex;     assign memwrite_ex    = memwrite_id_ex;
    assign memtoreg_ex    = memtoreg_id_ex;    assign branch_ex      = branch_id_ex;
    assign jump_ex        = jump_id_ex;        assign read_data1_ex  = read_data1_id_ex;
    assign read_data2_ex  = read_data2_id_ex;  assign imm_ex         = imm_id_ex;
    assign pc_ex          = pc_id_ex;          assign rs1_ex         = rs1_id_ex;
    assign rs2_ex         = rs2_id_ex;         assign rd_ex          = rd_id_ex;
    assign funct3_ex      = funct3_id_ex;      assign funct7_ex      = funct7_id_ex;
    assign alu_control_ex = alu_control_id_ex; assign byte_size_ex   = byte_size_id_ex;
    assign opcode_ex      = opcode_id_ex;

    // ========================================================================
    // STAGE 3: EX
    // ========================================================================
    forwarding_unit fwd_unit (
        .rs1_ex      (rs1_ex),       .rs2_ex      (rs2_ex),
        .rd_mem      (rd_mem),       .rd_wb       (rd_wb),
        .regwrite_mem(regwrite_mem), .regwrite_wb (regwrite_wb),
        .forward_a   (forward_a),    .forward_b   (forward_b)
    );

    wire [31:0] alu_in1_forwarded;
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

    assign pc_plus_4_ex = pc_ex + 32'd4;

    wire [31:0] jalr_target;
    assign jalr_target  = (alu_in1 + imm_ex) & 32'hFFFFFFFE;
    assign target_pc_ex = (opcode_ex == 7'b1100111) ? jalr_target : pc_ex + imm_ex;
    assign pc_src_ex    = (branch_ex & branch_taken_ex) | jump_ex;

    // ========================================================================
    // EX/MEM PIPELINE REGISTER
    // ========================================================================
    reg regwrite_ex_mem, memread_ex_mem, memwrite_ex_mem, memtoreg_ex_mem, jump_ex_mem;
    reg [31:0] alu_result_ex_mem, write_data_ex_mem, pc_plus_4_ex_mem;
    reg [4:0]  rd_ex_mem;
    reg [1:0]  byte_size_ex_mem;
    reg [2:0]  funct3_ex_mem;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regwrite_ex_mem   <= 1'b0; memread_ex_mem    <= 1'b0;
            memwrite_ex_mem   <= 1'b0; memtoreg_ex_mem   <= 1'b0;
            jump_ex_mem       <= 1'b0; alu_result_ex_mem <= 32'h0;
            write_data_ex_mem <= 32'h0; pc_plus_4_ex_mem <= 32'h0;
            rd_ex_mem         <= 5'b0; byte_size_ex_mem  <= 2'b0;
            funct3_ex_mem     <= 3'b0;
        end else if (!stall_ex_mem) begin  // [FIX-BUG-EXMEM] advance trừ khi lsu_dependency/fence
            // EX/MEM chỉ freeze khi lsu_dependency_stall hoặc fence_stall.
            // load_use_hazard/mem_load_stall: EX/MEM PHẢI advance (load vào MEM),
            // ID/EX được flush tạo NOP. Nếu freeze EX/MEM, load kẹt ở EX mãi.
            regwrite_ex_mem   <= regwrite_ex;
            memread_ex_mem    <= memread_ex;
            memwrite_ex_mem   <= memwrite_ex;
            memtoreg_ex_mem   <= memtoreg_ex;
            jump_ex_mem       <= jump_ex;
            alu_result_ex_mem <= alu_result_ex;
            write_data_ex_mem <= alu_in2_pre_mux;
            pc_plus_4_ex_mem  <= pc_plus_4_ex;
            rd_ex_mem         <= rd_ex;
            byte_size_ex_mem  <= byte_size_ex;
            funct3_ex_mem     <= funct3_ex;
        end
    end

    assign regwrite_mem   = regwrite_ex_mem;   assign memread_mem    = memread_ex_mem;
    assign memwrite_mem   = memwrite_ex_mem;   assign memtoreg_mem   = memtoreg_ex_mem;
    assign jump_mem       = jump_ex_mem;       assign alu_result_mem = alu_result_ex_mem;
    assign write_data_mem = write_data_ex_mem; assign pc_plus_4_mem  = pc_plus_4_ex_mem;
    assign rd_mem         = rd_ex_mem;         assign byte_size_mem  = byte_size_ex_mem;
    assign funct3_mem     = funct3_ex_mem;

    // ========================================================================
    // STAGE 4: MEM — via LSU
    // ========================================================================
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

    reg lsu_req_sent;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lsu_req_sent <= 1'b0;
        else begin
            // [FIX-LSU-SENT] Đúng priority: CLEAR khi pipeline advance,
            // SET khi LSU nhận.
            //
            // lsu_req_valid = (mem_op) & !(lsu_req_sent & stall_any)
            //   - stall_any=0 (no hazard): pipeline advance → luôn valid,
            //     lsu_req_sent không block → mỗi instruction chỉ gửi 1 lần
            //     vì EX/MEM advance ngay cycle sau khi instruction vào MEM.
            //   - stall_any=1 (stall): pipeline frozen → lsu_req_sent block
            //     gửi lần 2, ngăn double-enqueue vào LQ.
            //
            // CLEAR phải có priority cao hơn SET:
            //   Cycle A: stall_any=0, LSU nhận req → SET fire
            //   → lsu_req_sent=1, NHƯNG EX/MEM advance ngay cycle này.
            //   Cycle A+1: instruction mới ở MEM, lsu_req_sent=1.
            //   Nếu SET thắng: lsu_req_valid = op & !(1 & 0) = 1 → OK
            //   nhưng lsu_req_sent vẫn=1 → next cycle vẫn block dù
            //   instruction mới. Phải CLEAR khi !stall_any.
            if (!stall_any)
                lsu_req_sent <= 1'b0;
            else if (lsu_req_valid && lsu_req_ready)
                lsu_req_sent <= 1'b1;
        end
    end
    // [FIX-LSU-VALID] Gate bằng !(lsu_req_sent & stall_any), không phải !lsu_req_sent.
    //   - Khi stall_any=0: req luôn valid (pipeline advance = new instruction)
    //   - Khi stall_any=1: req chỉ valid nếu chưa gửi (ngăn double-enqueue)
    assign lsu_req_valid = (memread_mem | memwrite_mem) & !(lsu_req_sent & stall_any);

    LSU lsu_unit (
        .clk         (clk),           .rst         (rst),
        .req_valid   (lsu_req_valid),  .req_ready   (lsu_req_ready),
        .req_addr    (alu_result_mem), .req_wdata   (write_data_mem),
        .req_wstrb   (lsu_req_wstrb),  .req_is_load (memread_mem),
        .req_rd      (rd_mem),         .req_funct3  (funct3_mem),
        .fence       (|dcache_fence_type),  // any fence → stall LSU
        .result_valid(lsu_result_valid), .result_data(lsu_result_data),
        .result_rd   (lsu_result_rd),  .result_ack  (lsu_result_ack),
        .scoreboard  (lsu_scoreboard), .lsu_idle    (lsu_idle),
        .dcache_req  (dcache_req),     .dcache_we   (dcache_we),
        .dcache_addr (dcache_addr),    .dcache_wdata(dcache_wdata),
        .dcache_wstrb(dcache_wstrb),   .dcache_rdata(dcache_rdata),
        .dcache_ready(dcache_ready)
    );

    // ========================================================================
    // MEM/WB REGISTER
    // ========================================================================
    reg regwrite_mem_wb, memtoreg_mem_wb, jump_mem_wb;
    reg [31:0] alu_result_mem_wb, mem_data_mem_wb, pc_plus_4_mem_wb;
    reg [4:0]  rd_mem_wb;

    // [FIX-MEMWB-GUARD] 1-cycle flag: ngăn else-if overwrite ngay sau lsu_result commit.
    // Set = 1 khi lsu_result commit xảy ra (lsu_result_valid && !stall_if).
    // Được dùng làm guard trong else-if (!stall_any && !lsu_committed_r).
    reg lsu_committed_r;
    always @(posedge clk or posedge rst) begin
        if (rst)
            lsu_committed_r <= 1'b0;
        else
            lsu_committed_r <= lsu_result_valid && !stall_if;
    end

    assign lsu_result_ack = lsu_result_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regwrite_mem_wb   <= 1'b0; memtoreg_mem_wb   <= 1'b0;
            jump_mem_wb       <= 1'b0; alu_result_mem_wb <= 32'h0;
            mem_data_mem_wb   <= 32'h0; pc_plus_4_mem_wb <= 32'h0;
            rd_mem_wb         <= 5'b0;
        end else begin
            // [FIX-MEMWB-GATE] Xử lý đúng hai trường hợp conflict:
            //
            // VẤN ĐỀ 1 (bug gốc): else-if overwrite sau khi lsu_result commit.
            //   Cycle N: lsu_result_valid=1, stall_any=1 (scoreboard[rd]=1)
            //     → lsu_result branch fire → WB = load result ✓
            //   Cycle N+1: stall_any=0 (scoreboard cleared), lsu_result_valid=0
            //     → else-if fire → rd_mem_wb <= rd_mem (instruction MỚI ở MEM)
            //     → OVERWRITE load result → epilogue đọc stack sai → jalr corrupt
            //
            // VẤN ĐỀ 2 (nếu dùng !stall_any cho lsu_result):
            //   Deadlock: stall_any=1 vì đang chờ load, lsu_result không commit
            //   → stall không bao giờ clear → pipeline đóng băng.
            //
            // FIX ĐÚNG:
            //   - lsu_result branch: giữ !stall_if (original) để tránh deadlock.
            //     Load PHẢI commit kể cả khi pipeline stall vì đang chờ chính load đó.
            //   - else-if branch: thêm guard !lsu_committed_r để ngăn overwrite
            //     ngay sau cycle lsu_result commit.
            //
            // lsu_committed_r = 1 chu kỳ sau khi lsu_result commit:
            //   Cycle N: lsu_result fire → lsu_committed_r <= 1
            //   Cycle N+1: else-if KHÔNG fire (guard lsu_committed_r=1)
            //              WB giữ nguyên load result ✓
            //   Cycle N+2: lsu_committed_r = 0 → else-if có thể fire bình thường
            if (lsu_result_valid && !stall_if) begin
                mem_data_mem_wb   <= lsu_result_data;
                rd_mem_wb         <= lsu_result_rd;
                regwrite_mem_wb   <= 1'b1;
                memtoreg_mem_wb   <= 1'b1;
                jump_mem_wb       <= 1'b0;
                alu_result_mem_wb <= alu_result_mem;
                pc_plus_4_mem_wb  <= pc_plus_4_mem;
            end else if (!stall_any && !lsu_committed_r) begin
                alu_result_mem_wb <= alu_result_mem;
                pc_plus_4_mem_wb  <= pc_plus_4_mem;
                regwrite_mem_wb   <= regwrite_mem & ~memread_mem;
                memtoreg_mem_wb   <= 1'b0;
                jump_mem_wb       <= jump_mem;
                rd_mem_wb         <= rd_mem;
            end
            // else: stall_any=1 (không phải lsu_result) OR lsu_committed_r=1
            //       → MEM/WB giữ nguyên (implicit freeze)
        end
    end

    assign regwrite_wb   = regwrite_mem_wb;  assign memtoreg_wb   = memtoreg_mem_wb;
    assign jump_wb       = jump_mem_wb;      assign alu_result_wb = alu_result_mem_wb;
    assign mem_data_wb   = mem_data_mem_wb;  assign pc_plus_4_wb  = pc_plus_4_mem_wb;
    assign rd_wb         = rd_mem_wb;

    // ========================================================================
    // STAGE 5: WB
    // ========================================================================
    wire [31:0] wb_data_before_jump;
    assign wb_data_before_jump = memtoreg_wb ? mem_data_wb : alu_result_wb;
    assign write_back_data_wb  = jump_wb ? pc_plus_4_wb : wb_data_before_jump;
    
    // ========================================================================
    // HAZARD DETECTION UNIT
    // ========================================================================
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
        .stall          (stall),
        .stall_if       (stall_if),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex),
        .fence_stall    (fence_stall)
    );

endmodule