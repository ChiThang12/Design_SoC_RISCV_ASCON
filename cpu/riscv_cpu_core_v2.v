// ============================================================================
// riscv_cpu_core_v2.v - RISC-V 5-Stage Pipelined CPU Core
// ============================================================================
// FIXES so với v1:
//   FIX-1: EX/MEM register - data path chỉ update khi !stall (giống control)
//          Tránh overwrite alu_result/write_data khi pipeline bị stall
//   FIX-2: lsu_req_valid dùng one-shot pulse thay vì level signal liên tục
//          Tránh LSU nhận duplicate request mỗi cycle khi EX/MEM đứng yên
//   FIX-3: MEM/WB register - alu_result và pc_plus4 update đúng timing
//          Tách rõ path cho non-mem vs LSU result
//   FIX-4: LSU.v PROCESS state giữ result_valid thêm 1 cycle cho pipeline kịp capture
// ============================================================================
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

    // INSTRUCTION MEMORY INTERFACE
    output wire [31:0] imem_addr,
    output wire        imem_valid,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,

    // DATA MEMORY INTERFACE
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_valid,
    output wire        dmem_we,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_ready
);

    // ========================================================================
    // IF Stage
    // ========================================================================
    wire [31:0] pc_if;
    wire [31:0] instr_if;

    // ========================================================================
    // IF/ID Pipeline Register
    // ========================================================================
    wire [31:0] pc_id;
    wire [31:0] instr_id;

    // ========================================================================
    // ID Stage Decode
    // ========================================================================
    wire [6:0] opcode_id = instr_id[6:0];
    wire [4:0] rd_id     = instr_id[11:7];
    wire [2:0] funct3_id = instr_id[14:12];
    wire [4:0] rs1_id    = instr_id[19:15];
    wire [4:0] rs2_id    = instr_id[24:20];
    wire [6:0] funct7_id = instr_id[31:25];

    // ========================================================================
    // ID Stage Control Signals
    // ========================================================================
    wire [3:0] alu_control_id;
    wire regwrite_id;
    wire alusrc_id;
    wire memread_id;
    wire memwrite_id;
    wire memtoreg_id;
    wire branch_id;
    wire jump_id;
    wire [1:0] byte_size_id;

    // Register File
    wire [31:0] read_data1_id;
    wire [31:0] read_data2_id;

    // Immediate
    wire [31:0] imm_id;

    // ========================================================================
    // ID/EX Pipeline Register outputs
    // ========================================================================
    wire regwrite_ex;
    wire alusrc_ex;
    wire memread_ex;
    wire memwrite_ex;
    wire memtoreg_ex;
    wire branch_ex;
    wire jump_ex;
    wire [31:0] read_data1_ex;
    wire [31:0] read_data2_ex;
    wire [31:0] imm_ex;
    wire [31:0] pc_ex;
    wire [4:0]  rs1_ex;
    wire [4:0]  rs2_ex;
    wire [4:0]  rd_ex;
    wire [2:0]  funct3_ex;
    wire [6:0]  funct7_ex;
    wire [3:0]  alu_control_ex;
    wire [1:0]  byte_size_ex;
    wire [6:0]  opcode_ex;

    // ========================================================================
    // EX Stage
    // ========================================================================
    wire [31:0] alu_in1;
    wire [31:0] alu_in2;
    wire [31:0] alu_in2_pre_mux;
    wire [31:0] alu_result_ex;
    wire zero_flag_ex;
    wire less_than_ex;
    wire less_than_u_ex;
    wire branch_taken_ex;
    wire [31:0] target_pc_ex;
    wire pc_src_ex;
    wire [31:0] pc_plus_4_ex;

    // ========================================================================
    // EX/MEM Pipeline Register outputs
    // ========================================================================
    wire regwrite_mem;
    wire memread_mem;
    wire memwrite_mem;
    wire memtoreg_mem;
    wire [31:0] alu_result_mem;
    wire [31:0] write_data_mem;
    wire [31:0] pc_plus_4_mem;
    wire [4:0]  rd_mem;
    wire [1:0]  byte_size_mem;
    wire [2:0]  funct3_mem;
    wire jump_mem;

    // ========================================================================
    // MEM Stage - LSU Interface
    // ========================================================================
    wire [31:0] mem_read_data_extended;

    // LSU pipeline interface
    wire        lsu_req_valid;
    wire        lsu_req_ready;
    wire [3:0]  lsu_req_wstrb;

    // LSU result interface
    wire        lsu_result_valid;
    wire [31:0] lsu_result_data;
    wire [4:0]  lsu_result_rd;

    // LSU scoreboard
    wire [31:0] lsu_scoreboard;

    // LSU memory interface
    wire [31:0] lsu_dmem_addr;
    wire [31:0] lsu_dmem_wdata;
    wire [3:0]  lsu_dmem_wstrb_out;
    wire        lsu_dmem_valid;
    wire        lsu_dmem_we;

    // ========================================================================
    // MEM/WB Pipeline Register outputs
    // ========================================================================
    wire regwrite_wb;
    wire memtoreg_wb;
    wire jump_wb;
    wire [31:0] alu_result_wb;
    wire [31:0] mem_data_wb;
    wire [31:0] pc_plus_4_wb;
    wire [4:0]  rd_wb;

    // ========================================================================
    // WB Stage
    // ========================================================================
    wire [31:0] write_back_data_wb;

    // ========================================================================
    // Hazard / Stall / Flush
    // ========================================================================
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    wire stall;        // Pipeline hazard stall (load-use, LSU dep)
    wire stall_if;     // IF-only stall (imem not ready)
    wire stall_any;    // stall | stall_if
    wire flush_if_id;
    wire flush_id_ex;

    assign stall_any = stall | stall_if;

    // ========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // ========================================================================
    IFU instruction_fetch (
        .clock(clk),
        .reset(rst),
        .pc_src(pc_src_ex),
        .stall(stall_any),
        .target_pc(target_pc_ex),
        .imem_addr(imem_addr),
        .imem_valid(imem_valid),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        .PC_out(pc_if),
        .Instruction_Code(instr_if)
    );

    // ========================================================================
    // IF/ID PIPELINE REGISTER
    // ========================================================================
    PIPELINE_REG_IF_ID if_id_reg (
        .clock(clk),
        .reset(rst),
        .flush(flush_if_id),
        .stall(stall_any),
        .instr_in(instr_if),
        .pc_in(pc_if),
        .instr_out(instr_id),
        .pc_out(pc_id)
    );

    // ========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // ========================================================================
    control control_unit (
        .opcode(opcode_id),
        .funct3(funct3_id),
        .funct7(funct7_id),
        .alu_control(alu_control_id),
        .regwrite(regwrite_id),
        .alusrc(alusrc_id),
        .memread(memread_id),
        .memwrite(memwrite_id),
        .memtoreg(memtoreg_id),
        .branch(branch_id),
        .jump(jump_id),
        .aluop(),
        .byte_size(byte_size_id)
    );

    reg_file register_file (
        .clock(clk),
        .reset(rst),
        .read_reg_num1(rs1_id),
        .read_reg_num2(rs2_id),
        .read_data1(read_data1_id),
        .read_data2(read_data2_id),
        .regwrite(regwrite_wb),
        .write_reg(rd_wb),
        .write_data(write_back_data_wb)
    );

    imm_gen immediate_generator (
        .instr(instr_id),
        .imm(imm_id)
    );

    // ========================================================================
    // ID/EX PIPELINE REGISTER
    // ========================================================================
    reg regwrite_id_ex;
    reg alusrc_id_ex;
    reg memread_id_ex;
    reg memwrite_id_ex;
    reg memtoreg_id_ex;
    reg branch_id_ex;
    reg jump_id_ex;
    reg [31:0] read_data1_id_ex;
    reg [31:0] read_data2_id_ex;
    reg [31:0] imm_id_ex;
    reg [31:0] pc_id_ex;
    reg [4:0]  rs1_id_ex;
    reg [4:0]  rs2_id_ex;
    reg [4:0]  rd_id_ex;
    reg [2:0]  funct3_id_ex;
    reg [6:0]  funct7_id_ex;
    reg [3:0]  alu_control_id_ex;
    reg [1:0]  byte_size_id_ex;
    reg [6:0]  opcode_id_ex;

    always @(posedge clk or posedge rst) begin
        if (rst || flush_id_ex) begin
            regwrite_id_ex    <= 1'b0;
            alusrc_id_ex      <= 1'b0;
            memread_id_ex     <= 1'b0;
            memwrite_id_ex    <= 1'b0;
            memtoreg_id_ex    <= 1'b0;
            branch_id_ex      <= 1'b0;
            jump_id_ex        <= 1'b0;
            read_data1_id_ex  <= 32'h0;
            read_data2_id_ex  <= 32'h0;
            imm_id_ex         <= 32'h0;
            pc_id_ex          <= 32'h0;
            rs1_id_ex         <= 5'b0;
            rs2_id_ex         <= 5'b0;
            rd_id_ex          <= 5'b0;
            funct3_id_ex      <= 3'b0;
            funct7_id_ex      <= 7'b0;
            alu_control_id_ex <= 4'b0;
            byte_size_id_ex   <= 2'b0;
            opcode_id_ex      <= 7'b0;
        end else if (!stall) begin
            regwrite_id_ex    <= regwrite_id;
            alusrc_id_ex      <= alusrc_id;
            memread_id_ex     <= memread_id;
            memwrite_id_ex    <= memwrite_id;
            memtoreg_id_ex    <= memtoreg_id;
            branch_id_ex      <= branch_id;
            jump_id_ex        <= jump_id;
            read_data1_id_ex  <= read_data1_id;
            read_data2_id_ex  <= read_data2_id;
            imm_id_ex         <= imm_id;
            pc_id_ex          <= pc_id;
            rs1_id_ex         <= rs1_id;
            rs2_id_ex         <= rs2_id;
            rd_id_ex          <= rd_id;
            funct3_id_ex      <= funct3_id;
            funct7_id_ex      <= funct7_id;
            alu_control_id_ex <= alu_control_id;
            byte_size_id_ex   <= byte_size_id;
            opcode_id_ex      <= opcode_id;
        end
    end

    assign regwrite_ex    = regwrite_id_ex;
    assign alusrc_ex      = alusrc_id_ex;
    assign memread_ex     = memread_id_ex;
    assign memwrite_ex    = memwrite_id_ex;
    assign memtoreg_ex    = memtoreg_id_ex;
    assign branch_ex      = branch_id_ex;
    assign jump_ex        = jump_id_ex;
    assign read_data1_ex  = read_data1_id_ex;
    assign read_data2_ex  = read_data2_id_ex;
    assign imm_ex         = imm_id_ex;
    assign pc_ex          = pc_id_ex;
    assign rs1_ex         = rs1_id_ex;
    assign rs2_ex         = rs2_id_ex;
    assign rd_ex          = rd_id_ex;
    assign funct3_ex      = funct3_id_ex;
    assign funct7_ex      = funct7_id_ex;
    assign alu_control_ex = alu_control_id_ex;
    assign byte_size_ex   = byte_size_id_ex;
    assign opcode_ex      = opcode_id_ex;

    // ========================================================================
    // STAGE 3: EXECUTE (EX)
    // ========================================================================
    forwarding_unit fwd_unit (
        .rs1_ex(rs1_ex),
        .rs2_ex(rs2_ex),
        .rd_mem(rd_mem),
        .rd_wb(rd_wb),
        .regwrite_mem(regwrite_mem),
        .regwrite_wb(regwrite_wb),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    // ALU Input 1 with Forwarding
    wire [31:0] alu_in1_forwarded;
    assign alu_in1_forwarded = (forward_a == 2'b10) ? alu_result_mem :
                               (forward_a == 2'b01) ? write_back_data_wb :
                               read_data1_ex;

    assign alu_in1 = (opcode_ex == 7'b0110111) ? 32'h0  :  // LUI
                     (opcode_ex == 7'b0010111) ? pc_ex  :  // AUIPC
                     alu_in1_forwarded;

    // ALU Input 2 Pre-Mux with Forwarding
    assign alu_in2_pre_mux = (forward_b == 2'b10) ? alu_result_mem :
                             (forward_b == 2'b01) ? write_back_data_wb :
                             read_data2_ex;

    assign alu_in2 = alusrc_ex ? imm_ex : alu_in2_pre_mux;

    alu arithmetic_logic_unit (
        .in1(alu_in1),
        .in2(alu_in2),
        .alu_control(alu_control_ex),
        .alu_result(alu_result_ex),
        .zero_flag(zero_flag_ex),
        .less_than(less_than_ex),
        .less_than_u(less_than_u_ex)
    );

    branch_logic branch_unit (
        .branch(branch_ex),
        .funct3(funct3_ex),
        .zero_flag(zero_flag_ex),
        .less_than(less_than_ex),
        .less_than_u(less_than_u_ex),
        .taken(branch_taken_ex)
    );

    assign pc_plus_4_ex = pc_ex + 32'd4;

    wire [31:0] jalr_target;
    assign jalr_target  = (alu_in1 + imm_ex) & 32'hFFFFFFFE;

    assign target_pc_ex = (opcode_ex == 7'b1100111) ? jalr_target :
                          pc_ex + imm_ex;   // JAL và branch đều dùng PC+imm

    assign pc_src_ex = (branch_ex & branch_taken_ex) | jump_ex;

    // ========================================================================
    // EX/MEM PIPELINE REGISTER
    // FIX-1: Tất cả fields (kể cả data path) chỉ update khi !stall
    //        Tránh alu_result/write_data bị overwrite bởi bubble khi stall
    // ========================================================================
    reg regwrite_ex_mem;
    reg memread_ex_mem;
    reg memwrite_ex_mem;
    reg memtoreg_ex_mem;
    reg jump_ex_mem;
    reg [31:0] alu_result_ex_mem;
    reg [31:0] write_data_ex_mem;
    reg [31:0] pc_plus_4_ex_mem;
    reg [4:0]  rd_ex_mem;
    reg [1:0]  byte_size_ex_mem;
    reg [2:0]  funct3_ex_mem;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regwrite_ex_mem   <= 1'b0;
            memread_ex_mem    <= 1'b0;
            memwrite_ex_mem   <= 1'b0;
            memtoreg_ex_mem   <= 1'b0;
            jump_ex_mem       <= 1'b0;
            alu_result_ex_mem <= 32'h0;
            write_data_ex_mem <= 32'h0;
            pc_plus_4_ex_mem  <= 32'h0;
            rd_ex_mem         <= 5'b0;
            byte_size_ex_mem  <= 2'b0;
            funct3_ex_mem     <= 3'b0;
        // FIX-1: mọi field update cùng điều kiện !stall
        end else if (!stall) begin
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
        // stall: giữ nguyên toàn bộ EX/MEM register
    end

    assign regwrite_mem   = regwrite_ex_mem;
    assign memread_mem    = memread_ex_mem;
    assign memwrite_mem   = memwrite_ex_mem;
    assign memtoreg_mem   = memtoreg_ex_mem;
    assign jump_mem       = jump_ex_mem;
    assign alu_result_mem = alu_result_ex_mem;
    assign write_data_mem = write_data_ex_mem;
    assign pc_plus_4_mem  = pc_plus_4_ex_mem;
    assign rd_mem         = rd_ex_mem;
    assign byte_size_mem  = byte_size_ex_mem;
    assign funct3_mem     = funct3_ex_mem;

    // ========================================================================
    // STAGE 4: MEMORY ACCESS (MEM) - via LSU
    // ========================================================================

    // Write Strobe Generation (combinational, fed into LSU)
    reg [3:0] dmem_wstrb_comb;
    always @(*) begin
        case (byte_size_mem)
            2'b00:   dmem_wstrb_comb = 4'b0001 << alu_result_mem[1:0];
            2'b01:   dmem_wstrb_comb = 4'b0011 << {alu_result_mem[1], 1'b0};
            2'b10:   dmem_wstrb_comb = 4'b1111;
            default: dmem_wstrb_comb = 4'b0000;
        endcase
    end
    assign lsu_req_wstrb = dmem_wstrb_comb;

    // -------------------------------------------------------------------------
    // FIX-2: One-shot pulse cho lsu_req_valid
    // Vấn đề cũ: lsu_req_valid = (memread_mem | memwrite_mem) luôn = 1 khi
    //   EX/MEM register đứng yên → LSU nhận duplicate request mỗi cycle.
    // Fix: chỉ phát valid=1 đúng 1 cycle khi EX/MEM vừa advance (cạnh !stall→stall
    //   hoặc instruction mới vào MEM stage).
    // Cách implement: theo dõi khi nào EX/MEM register vừa được ghi (tức !stall
    //   ở cycle trước). Dùng reg lsu_sent để track đã gửi request chưa.
    // -------------------------------------------------------------------------
    reg lsu_req_sent;  // 1 = đã gửi request cho lệnh mem hiện tại trong EX/MEM

    // lsu_req_valid: chỉ 1 khi có mem op VÀ chưa gửi request cho lệnh này
    assign lsu_req_valid = (memread_mem | memwrite_mem) & ~lsu_req_sent;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lsu_req_sent <= 1'b0;
        end else begin
            if (!stall) begin
                // Pipeline advance: EX/MEM register sẽ nhận instruction mới
                // Reset lsu_req_sent để sẵn sàng gửi request cho instruction tiếp theo
                lsu_req_sent <= 1'b0;
            end else if (lsu_req_valid && lsu_req_ready) begin
                // LSU đã accept request, đánh dấu đã gửi
                lsu_req_sent <= 1'b1;
            end
        end
    end

    // LSU Module
    LSU lsu_unit (
        .clk          (clk),
        .rst          (rst),

        // Pipeline → LSU request
        .req_valid    (lsu_req_valid),
        .req_ready    (lsu_req_ready),
        .req_addr     (alu_result_mem),
        .req_wdata    (write_data_mem),
        .req_wstrb    (lsu_req_wstrb),
        .req_is_load  (memread_mem),
        .req_rd       (rd_mem),
        .req_funct3   (funct3_mem),

        // LSU → WB result
        .result_valid (lsu_result_valid),
        .result_data  (lsu_result_data),
        .result_rd    (lsu_result_rd),

        // Scoreboard
        .scoreboard   (lsu_scoreboard),

        // LSU → External memory
        .dmem_addr    (lsu_dmem_addr),
        .dmem_wdata   (lsu_dmem_wdata),
        .dmem_wstrb   (lsu_dmem_wstrb_out),
        .dmem_valid   (lsu_dmem_valid),
        .dmem_we      (lsu_dmem_we),
        .dmem_rdata   (dmem_rdata),
        .dmem_ready   (dmem_ready)
    );

    // Connect LSU outputs to top-level dmem ports
    assign dmem_addr  = lsu_dmem_addr;
    assign dmem_wdata = lsu_dmem_wdata;
    assign dmem_wstrb = lsu_dmem_wstrb_out;
    assign dmem_valid = lsu_dmem_valid;
    assign dmem_we    = lsu_dmem_we;

    assign mem_read_data_extended = lsu_result_data;

    // ========================================================================
    // UNIFIED MEM/WB REGISTER
    // FIX-3: Tách rõ 2 path:
    //   (a) Non-mem instructions: update tất cả fields khi !stall
    //   (b) LSU load result: chỉ update WB control + mem_data khi lsu_result_valid
    //       alu_result và pc_plus4 được latch trước đó (khi !stall) và giữ nguyên
    // ========================================================================
    reg regwrite_mem_wb;
    reg memtoreg_mem_wb;
    reg jump_mem_wb;
    reg [31:0] alu_result_mem_wb;
    reg [31:0] mem_data_mem_wb;
    reg [31:0] pc_plus_4_mem_wb;
    reg [4:0]  rd_mem_wb;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regwrite_mem_wb   <= 1'b0;
            memtoreg_mem_wb   <= 1'b0;
            jump_mem_wb       <= 1'b0;
            alu_result_mem_wb <= 32'h0;
            mem_data_mem_wb   <= 32'h0;
            pc_plus_4_mem_wb  <= 32'h0;
            rd_mem_wb         <= 5'b0;
        end else begin
            // FIX-3a: LSU trả về load data → capture vào WB
            if (lsu_result_valid) begin
                mem_data_mem_wb <= lsu_result_data;
                rd_mem_wb       <= lsu_result_rd;
                regwrite_mem_wb <= 1'b1;
                memtoreg_mem_wb <= 1'b1;
                jump_mem_wb     <= 1'b0;
            // FIX-3b: Normal pipeline advance (non-mem hoặc store)
            end else if (!stall) begin
                alu_result_mem_wb <= alu_result_mem;
                pc_plus_4_mem_wb  <= pc_plus_4_mem;
                // regwrite: loại load ra (load được handle bởi lsu_result_valid path)
                regwrite_mem_wb   <= regwrite_mem & ~memread_mem;
                memtoreg_mem_wb   <= 1'b0;
                jump_mem_wb       <= jump_mem;
                rd_mem_wb         <= rd_mem;
            end
            // stall và không có LSU result → giữ nguyên WB register
        end
    end

    assign regwrite_wb   = regwrite_mem_wb;
    assign memtoreg_wb   = memtoreg_mem_wb;
    assign jump_wb       = jump_mem_wb;
    assign alu_result_wb = alu_result_mem_wb;
    assign mem_data_wb   = mem_data_mem_wb;
    assign pc_plus_4_wb  = pc_plus_4_mem_wb;
    assign rd_wb         = rd_mem_wb;

    // ========================================================================
    // STAGE 5: WRITE BACK (WB)
    // ========================================================================
    wire [31:0] wb_data_before_jump;
    assign wb_data_before_jump = memtoreg_wb ? mem_data_wb : alu_result_wb;
    assign write_back_data_wb  = jump_wb ? pc_plus_4_wb : wb_data_before_jump;

    // ========================================================================
    // HAZARD DETECTION UNIT
    // ========================================================================
    hazard_detection hazard_unit (
        .memread_id_ex(memread_ex),
        .rd_id_ex(rd_ex),
        .rs1_id(rs1_id),
        .rs2_id(rs2_id),
        .branch_taken(pc_src_ex),
        .imem_ready(imem_ready),
        .lsu_scoreboard(lsu_scoreboard),
        .stall(stall),
        .stall_if(stall_if),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

endmodule