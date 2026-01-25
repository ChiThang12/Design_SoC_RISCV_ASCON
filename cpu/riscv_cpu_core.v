// ============================================================================
// riscv_cpu_core.v - RISC-V 5-Stage Pipelined CPU Core (FIXED)
// ============================================================================
// Mô tả:
//   - 5-stage pipeline: IF -> ID -> EX -> MEM -> WB
//   - Hỗ trợ: RV32I base
//   - Forwarding Unit: Xử lý data hazards
//   - Hazard Detection: Load-use hazard, branch flush
//   - FIXED: Memory snapshot logic để tránh duplicate write-back
// ============================================================================
`include "core/IFU.v"
`include "core/reg_file.v"
`include "core/imm_gen.v"
`include "core/control.v"
`include "core/alu.v"
`include "core/branch_logic.v"
`include "core/forwarding_unit.v"
`include "core/hazard_detection.v"
`include "core/PIPELINE_REG_IF_ID.v"
`include "core/PIPELINE_REG_ID_EX.v"
`include "core/PIPELINE_REG_EX_WB.v"

module riscv_cpu_core (
    input wire clk,
    input wire rst,
    
    // ========================================================================
    // INSTRUCTION MEMORY INTERFACE
    // ========================================================================
    output wire [31:0] imem_addr,
    output wire        imem_valid,
    input  wire [31:0] imem_rdata,
    input  wire        imem_ready,
    
    // ========================================================================
    // DATA MEMORY INTERFACE
    // ========================================================================
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
    // ID/EX Pipeline Register
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
    wire [4:0] rs1_ex;
    wire [4:0] rs2_ex;
    wire [4:0] rd_ex;
    wire [2:0] funct3_ex;
    wire [6:0] funct7_ex;
    wire [3:0] alu_control_ex;
    wire [1:0] byte_size_ex;
    wire [6:0] opcode_ex;
    
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
    // EX/MEM Pipeline Register
    // ========================================================================
    wire regwrite_mem;
    wire memread_mem;
    wire memwrite_mem;
    wire memtoreg_mem;
    wire [31:0] alu_result_mem;
    wire [31:0] write_data_mem;
    wire [31:0] pc_plus_4_mem;
    wire [4:0] rd_mem;
    wire [1:0] byte_size_mem;
    wire [2:0] funct3_mem;
    wire jump_mem;
    
    // ========================================================================
    // MEM Stage - Snapshot Registers
    // ========================================================================
    wire [31:0] mem_read_data_extended;
    reg mem_req_pending;
    reg [4:0] rd_mem_snapshot;
    reg regwrite_mem_snapshot;
    reg memtoreg_mem_snapshot;
    reg jump_mem_snapshot;
    reg wb_done;
    
    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    wire regwrite_wb;
    wire memtoreg_wb;
    wire jump_wb;
    wire [31:0] alu_result_wb;
    wire [31:0] mem_data_wb;
    wire [31:0] pc_plus_4_wb;
    wire [4:0] rd_wb;
    
    // ========================================================================
    // WB Stage
    // ========================================================================
    wire [31:0] write_back_data_wb;
    
    // ========================================================================
    // Forwarding and Hazard Control
    // ========================================================================
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    wire stall;
    wire flush_if_id;
    wire flush_id_ex;
    
    // ========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // ========================================================================
    IFU instruction_fetch (
        .clock(clk),
        .reset(rst),
        .pc_src(pc_src_ex),
        .stall(stall),
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
        .stall(stall),
        .instr_in(instr_if),
        .pc_in(pc_if),
        .instr_out(instr_id),
        .pc_out(pc_id)
    );
    
    // ========================================================================
    // STAGE 2: INSTRUCTION DECODE (ID)
    // ========================================================================
    
    // Control Unit
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
    
    // Register File
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
    
    // Immediate Generator
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
    reg [4:0] rs1_id_ex;
    reg [4:0] rs2_id_ex;
    reg [4:0] rd_id_ex;
    reg [2:0] funct3_id_ex;
    reg [6:0] funct7_id_ex;
    reg [3:0] alu_control_id_ex;
    reg [1:0] byte_size_id_ex;
    reg [6:0] opcode_id_ex;
    
    always @(posedge clk or posedge rst) begin
        if (rst || flush_id_ex) begin
            regwrite_id_ex <= 1'b0;
            alusrc_id_ex <= 1'b0;
            memread_id_ex <= 1'b0;
            memwrite_id_ex <= 1'b0;
            memtoreg_id_ex <= 1'b0;
            branch_id_ex <= 1'b0;
            jump_id_ex <= 1'b0;
            read_data1_id_ex <= 32'h0;
            read_data2_id_ex <= 32'h0;
            imm_id_ex <= 32'h0;
            pc_id_ex <= 32'h0;
            rs1_id_ex <= 5'b0;
            rs2_id_ex <= 5'b0;
            rd_id_ex <= 5'b0;
            funct3_id_ex <= 3'b0;
            funct7_id_ex <= 7'b0;
            alu_control_id_ex <= 4'b0;
            byte_size_id_ex <= 2'b0;
            opcode_id_ex <= 7'b0;
        end else if (!stall) begin
            regwrite_id_ex <= regwrite_id;
            alusrc_id_ex <= alusrc_id;
            memread_id_ex <= memread_id;
            memwrite_id_ex <= memwrite_id;
            memtoreg_id_ex <= memtoreg_id;
            branch_id_ex <= branch_id;
            jump_id_ex <= jump_id;
            read_data1_id_ex <= read_data1_id;
            read_data2_id_ex <= read_data2_id;
            imm_id_ex <= imm_id;
            pc_id_ex <= pc_id;
            rs1_id_ex <= rs1_id;
            rs2_id_ex <= rs2_id;
            rd_id_ex <= rd_id;
            funct3_id_ex <= funct3_id;
            funct7_id_ex <= funct7_id;
            alu_control_id_ex <= alu_control_id;
            byte_size_id_ex <= byte_size_id;
            opcode_id_ex <= opcode_id;
        end
    end
    
    assign regwrite_ex = regwrite_id_ex;
    assign alusrc_ex = alusrc_id_ex;
    assign memread_ex = memread_id_ex;
    assign memwrite_ex = memwrite_id_ex;
    assign memtoreg_ex = memtoreg_id_ex;
    assign branch_ex = branch_id_ex;
    assign jump_ex = jump_id_ex;
    assign read_data1_ex = read_data1_id_ex;
    assign read_data2_ex = read_data2_id_ex;
    assign imm_ex = imm_id_ex;
    assign pc_ex = pc_id_ex;
    assign rs1_ex = rs1_id_ex;
    assign rs2_ex = rs2_id_ex;
    assign rd_ex = rd_id_ex;
    assign funct3_ex = funct3_id_ex;
    assign funct7_ex = funct7_id_ex;
    assign alu_control_ex = alu_control_id_ex;
    assign byte_size_ex = byte_size_id_ex;
    assign opcode_ex = opcode_id_ex;
    
    // ========================================================================
    // STAGE 3: EXECUTE (EX)
    // ========================================================================
    
    // Forwarding Unit
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
    
    assign alu_in1 = (opcode_ex == 7'b0110111) ? 32'h0 :      // LUI: always use 0
                     (opcode_ex == 7'b0010111) ? pc_ex :      // AUIPC: use PC
                     alu_in1_forwarded;                       // Normal: use forwarded rs1
    
    // ALU Input 2 Pre-Mux with Forwarding
    assign alu_in2_pre_mux = (forward_b == 2'b10) ? alu_result_mem :
                             (forward_b == 2'b01) ? write_back_data_wb :
                             read_data2_ex;
    
    // ALU Input 2 Mux: Register vs Immediate
    wire [31:0] alu_in2_imm;
    assign alu_in2_imm = imm_ex;
    
    assign alu_in2 = alusrc_ex ? alu_in2_imm : alu_in2_pre_mux;
    
    // ALU
    alu arithmetic_logic_unit (
        .in1(alu_in1),
        .in2(alu_in2),
        .alu_control(alu_control_ex),
        .alu_result(alu_result_ex),
        .zero_flag(zero_flag_ex),
        .less_than(less_than_ex),
        .less_than_u(less_than_u_ex)
    );
    
    // Branch Logic
    branch_logic branch_unit (
        .branch(branch_ex),
        .funct3(funct3_ex),
        .zero_flag(zero_flag_ex),
        .less_than(less_than_ex),
        .less_than_u(less_than_u_ex),
        .taken(branch_taken_ex)
    );
    
    // PC+4 calculation for JAL/JALR
    assign pc_plus_4_ex = pc_ex + 32'd4;
    
    // Target PC calculation
    wire [31:0] branch_target;
    wire [31:0] jal_target;
    wire [31:0] jalr_target;
    
    assign branch_target = pc_ex + imm_ex;
    assign jal_target = pc_ex + imm_ex;
    assign jalr_target = (alu_in1 + imm_ex) & 32'hFFFFFFFE;
    
    assign target_pc_ex = (opcode_ex == 7'b1100111) ? jalr_target :
                          (jump_ex) ? jal_target :
                          branch_target;
    
    assign pc_src_ex = (branch_ex & branch_taken_ex) | jump_ex;
    
    // ========================================================================
    // EX/MEM PIPELINE REGISTER
    // ========================================================================
    reg regwrite_ex_mem;
    reg memread_ex_mem;
    reg memwrite_ex_mem;
    reg memtoreg_ex_mem;
    reg jump_ex_mem;
    reg [31:0] alu_result_ex_mem;
    reg [31:0] write_data_ex_mem;
    reg [31:0] pc_plus_4_ex_mem;
    reg [4:0] rd_ex_mem;
    reg [1:0] byte_size_ex_mem;
    reg [2:0] funct3_ex_mem;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            regwrite_ex_mem <= 1'b0;
            memread_ex_mem <= 1'b0;
            memwrite_ex_mem <= 1'b0;
            memtoreg_ex_mem <= 1'b0;
            jump_ex_mem <= 1'b0;
            alu_result_ex_mem <= 32'h0;
            write_data_ex_mem <= 32'h0;
            pc_plus_4_ex_mem <= 32'h0;
            rd_ex_mem <= 5'b0;
            byte_size_ex_mem <= 2'b0;
            funct3_ex_mem <= 3'b0;
        end else begin
            // Data paths - ALWAYS update
            alu_result_ex_mem <= alu_result_ex;
            write_data_ex_mem <= alu_in2_pre_mux;
            pc_plus_4_ex_mem <= pc_plus_4_ex;
            
            // Control signals logic
            if (!stall) begin
                // Pipeline advance normally
                regwrite_ex_mem <= regwrite_ex;
                memread_ex_mem <= memread_ex;
                memwrite_ex_mem <= memwrite_ex;
                memtoreg_ex_mem <= memtoreg_ex;
                jump_ex_mem <= jump_ex;
                rd_ex_mem <= rd_ex;
                byte_size_ex_mem <= byte_size_ex;
                funct3_ex_mem <= funct3_ex;
            end
            // Khi stall - giữ nguyên giá trị (không thêm else)
        end
    end
    assign regwrite_mem = regwrite_ex_mem;
    assign memread_mem = memread_ex_mem;
    assign memwrite_mem = memwrite_ex_mem;
    assign memtoreg_mem = memtoreg_ex_mem;
    assign jump_mem = jump_ex_mem;
    assign alu_result_mem = alu_result_ex_mem;
    assign write_data_mem = write_data_ex_mem;
    assign pc_plus_4_mem = pc_plus_4_ex_mem;
    assign rd_mem = rd_ex_mem;
    assign byte_size_mem = byte_size_ex_mem;
    assign funct3_mem = funct3_ex_mem;
    
    // ========================================================================
    // STAGE 4: MEMORY ACCESS (MEM)
    // ========================================================================
    
    // Data Memory Interface
    assign dmem_addr = alu_result_mem;
    assign dmem_wdata = write_data_mem;
    assign dmem_valid = (memread_mem | memwrite_mem) && !mem_req_pending;
    assign dmem_we = memwrite_mem;
    
    // Write Strobe Generation
    reg [3:0] dmem_wstrb_reg;
    always @(*) begin
        case (byte_size_mem)
            2'b00: dmem_wstrb_reg = 4'b0001 << alu_result_mem[1:0];
            2'b01: dmem_wstrb_reg = 4'b0011 << {alu_result_mem[1], 1'b0};
            2'b10: dmem_wstrb_reg = 4'b1111;
            default: dmem_wstrb_reg = 4'b0000;
        endcase
    end
    assign dmem_wstrb = dmem_wstrb_reg;
    
    // Read Data Extension
    reg [31:0] mem_read_extended;
    always @(*) begin
        case (funct3_mem)
            3'b000: mem_read_extended = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
            3'b001: mem_read_extended = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
            3'b010: mem_read_extended = dmem_rdata;
            3'b100: mem_read_extended = {24'h0, dmem_rdata[7:0]};
            3'b101: mem_read_extended = {16'h0, dmem_rdata[15:0]};
            default: mem_read_extended = dmem_rdata;
        endcase
    end
    assign mem_read_data_extended = mem_read_extended;
    
    // ========================================================================
    // UNIFIED MEM/WB REGISTER + SNAPSHOT LOGIC
    // ========================================================================
    reg regwrite_mem_wb;
    reg memtoreg_mem_wb;
    reg jump_mem_wb;
    reg [31:0] alu_result_mem_wb;
    reg [31:0] mem_data_mem_wb;
    reg [31:0] pc_plus_4_mem_wb;
    reg [4:0] rd_mem_wb;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_req_pending <= 1'b0;
            rd_mem_snapshot <= 5'b0;
            regwrite_mem_snapshot <= 1'b0;
            memtoreg_mem_snapshot <= 1'b0;
            jump_mem_snapshot <= 1'b0;
            wb_done <= 1'b0;
            
            regwrite_mem_wb <= 1'b0;
            memtoreg_mem_wb <= 1'b0;
            jump_mem_wb <= 1'b0;
            alu_result_mem_wb <= 32'h0;
            mem_data_mem_wb <= 32'h0;
            pc_plus_4_mem_wb <= 32'h0;
            rd_mem_wb <= 5'b0;
            
        end else begin
            // ================================================================
            // DATA PATHS - Chỉ update khi !stall
            // ================================================================
            if (!stall) begin
                alu_result_mem_wb <= alu_result_mem;
                mem_data_mem_wb <= mem_read_data_extended;
                pc_plus_4_mem_wb <= pc_plus_4_mem;
            end
            
            // ================================================================
            // SNAPSHOT FSM - 3 STATES
            // ================================================================
            if (dmem_valid && dmem_ready && !mem_req_pending) begin
                // ============================================================
                // STATE 1: HANDSHAKE → Capture snapshot
                // ============================================================
                mem_req_pending <= 1'b1;
                wb_done <= 1'b0;
                
                // Snapshot MEM stage control signals
                rd_mem_snapshot <= rd_mem;
                regwrite_mem_snapshot <= regwrite_mem;
                memtoreg_mem_snapshot <= memtoreg_mem;
                jump_mem_snapshot <= jump_mem;
                
                // KHÔNG CLEAR WB stage - để old instruction hoàn thành
                // regwrite_mem_wb giữ nguyên
                
            end else if (mem_req_pending && !wb_done) begin
                // ============================================================
                // STATE 2: WRITEBACK → Apply snapshot to WB stage
                // ============================================================
                regwrite_mem_wb <= regwrite_mem_snapshot;
                memtoreg_mem_wb <= memtoreg_mem_snapshot;
                jump_mem_wb <= jump_mem_snapshot;
                rd_mem_wb <= rd_mem_snapshot;
                wb_done <= 1'b1;
                
            end else if (mem_req_pending && wb_done) begin
                // ============================================================
                // STATE 3: CLEAR → Reset FSM, transition to normal pipeline
                // ============================================================
                if (!stall) begin
                    // Chỉ clear khi pipeline sẵn sàng advance
                    mem_req_pending <= 1'b0;
                    wb_done <= 1'b0;
                    
                    // Transition sang normal pipeline flow
                    regwrite_mem_wb <= regwrite_mem;
                    memtoreg_mem_wb <= memtoreg_mem;
                    jump_mem_wb <= jump_mem;
                    rd_mem_wb <= rd_mem;
                end
                // Nếu vẫn stall → giữ nguyên tất cả
                
            end else if (!stall && !mem_req_pending) begin
                // ============================================================
                // NORMAL PIPELINE ADVANCE
                // ============================================================
                regwrite_mem_wb <= regwrite_mem;
                memtoreg_mem_wb <= memtoreg_mem;
                jump_mem_wb <= jump_mem;
                rd_mem_wb <= rd_mem;
            end
            // Nếu stall và không có FSM transition → giữ nguyên
        end
    end
    assign regwrite_wb = regwrite_mem_wb;
    assign memtoreg_wb = memtoreg_mem_wb;
    assign jump_wb = jump_mem_wb;
    assign alu_result_wb = alu_result_mem_wb;
    assign mem_data_wb = mem_data_mem_wb;
    assign pc_plus_4_wb = pc_plus_4_mem_wb;
    assign rd_wb = rd_mem_wb;
    
    // ========================================================================
    // STAGE 5: WRITE BACK (WB)
    // ========================================================================
    wire [31:0] wb_data_before_jump;
    assign wb_data_before_jump = memtoreg_wb ? mem_data_wb : alu_result_wb;
    assign write_back_data_wb = jump_wb ? pc_plus_4_wb : wb_data_before_jump;
    
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
        .dmem_ready(dmem_ready),
        .dmem_valid(dmem_valid),
        .stall(stall),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

endmodule