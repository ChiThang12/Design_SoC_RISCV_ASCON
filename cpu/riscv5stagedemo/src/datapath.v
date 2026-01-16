`include "IFU.v"
`include "reg_file.v"
`include "imm_gen.v"
`include "control.v"
`include "alu.v"
`include "data_mem.v"
`include "branch_logic.v"
`include "forwarding_unit.v"
`include "hazard_detection.v"
`include "PIPELINE_REG_IF_ID.v"
`include "PIPELINE_REG_ID_EX.v"
`include "PIPELINE_REG_EX_WB.v"

module datapath (
    input wire clock,
    input wire reset,
    
    // Debug outputs
    output wire [31:0] pc_current,
    output wire [31:0] instruction_current,
    output wire [31:0] alu_result_debug,
    output wire [31:0] mem_out_debug,
    output wire branch_taken_debug,
    output wire [31:0] branch_target_debug,
    output wire stall_debug,
    output wire [1:0] forward_a_debug,
    output wire [1:0] forward_b_debug
);

    // ========================================================================
    // CRITICAL: Branch/Jump control signals
    // Changed from reg to wire - apply branch immediately without delay
    // ========================================================================
    wire branch_taken_reg;
    wire [31:0] branch_target_reg;
    
    wire branch_taken_detected;
    wire [31:0] branch_target_calc;

    // ========================================================================
    // IF STAGE - Instruction Fetch
    // ========================================================================
    wire [31:0] pc_if;
    wire [31:0] instruction_if;
    wire stall;
    wire flush_if_id;
    
    IFU ifu (
        .clock(clock),
        .reset(reset),
        .pc_src(branch_taken_reg),
        .stall(stall),
        .target_pc(branch_target_reg),
        .PC_out(pc_if),
        .Instruction_Code(instruction_if)
    );
    
    // ========================================================================
    // IF/ID Pipeline Register
    // ========================================================================
    wire [31:0] instruction_id;
    wire [31:0] pc_id;
    
    PIPELINE_REG_IF_ID if_id_reg (
        .clock(clock),
        .reset(reset),
        .flush(flush_if_id),
        .stall(stall),
        .instr_in(instruction_if),
        .pc_in(pc_if),
        .instr_out(instruction_id),
        .pc_out(pc_id)
    );
    
    // ========================================================================
    // ID STAGE - Instruction Decode
    // ========================================================================
    
    // Instruction fields
    wire [6:0] opcode_id = instruction_id[6:0];
    wire [4:0] rd_id = instruction_id[11:7];
    wire [2:0] funct3_id = instruction_id[14:12];
    wire [4:0] rs1_id = instruction_id[19:15];
    wire [4:0] rs2_id = instruction_id[24:20];
    wire [6:0] funct7_id = instruction_id[31:25];
    
    // Control Unit
    wire [3:0] alu_control_id;
    wire regwrite_id, alusrc_id, memread_id, memwrite_id;
    wire memtoreg_id, branch_id, jump_id;
    wire [1:0] aluop_id;
    wire [1:0] byte_size_id;
    
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
        .aluop(aluop_id),
        .byte_size(byte_size_id)
    );
    
    // Register File
    wire [31:0] read_data1_id, read_data2_id;
    wire regwrite_wb;
    wire [4:0] rd_wb;
    wire [31:0] write_data_wb;
    
    reg_file register_file (
        .clock(clock),
        .reset(reset),
        .read_reg_num1(rs1_id),
        .read_reg_num2(rs2_id),
        .read_data1(read_data1_id),
        .read_data2(read_data2_id),
        .regwrite(regwrite_wb),
        .write_reg(rd_wb),
        .write_data(write_data_wb)
    );
    
    // Immediate Generator
    wire [31:0] imm_id;
    
    imm_gen immediate_gen (
        .instr(instruction_id),
        .imm(imm_id)
    );
    
    // Hazard Detection Unit
    wire memread_ex;
    wire [4:0] rd_ex;
    wire flush_id_ex;
    
    hazard_detection hazard_unit (
        .memread_id_ex(memread_ex),
        .rd_id_ex(rd_ex),
        .rs1_id(rs1_id),
        .rs2_id(rs2_id),
        .branch_taken(branch_taken_reg),
        .stall(stall),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );
    
    // ========================================================================
    // ID/EX Pipeline Register
    // ========================================================================
    wire regwrite_ex, alusrc_ex, memwrite_ex, memtoreg_ex;
    wire branch_ex, jump_ex;
    wire [31:0] read_data1_ex, read_data2_ex, imm_ex, pc_ex;
    wire [4:0] rs1_ex, rs2_ex;
    wire [2:0] funct3_ex;
    wire [6:0] funct7_ex;
    wire [3:0] alu_control_ex;
    wire [1:0] byte_size_ex;
    wire [6:0] opcode_ex;
    
    PIPELINE_REG_ID_EX id_ex_reg (
        .clock(clock),
        .reset(reset),
        .flush(flush_id_ex),
        .stall(1'b0),
        .regwrite_in(regwrite_id),
        .alusrc_in(alusrc_id),
        .memread_in(memread_id),
        .memwrite_in(memwrite_id),
        .memtoreg_in(memtoreg_id),
        .branch_in(branch_id),
        .jump_in(jump_id),
        .read_data1_in(read_data1_id),
        .read_data2_in(read_data2_id),
        .imm_in(imm_id),
        .pc_in(pc_id),
        .rs1_in(rs1_id),
        .rs2_in(rs2_id),
        .rd_in(rd_id),
        .funct3_in(funct3_id),
        .funct7_in(funct7_id),
        .regwrite_out(regwrite_ex),
        .alusrc_out(alusrc_ex),
        .memread_out(memread_ex),
        .memwrite_out(memwrite_ex),
        .memtoreg_out(memtoreg_ex),
        .branch_out(branch_ex),
        .jump_out(jump_ex),
        .read_data1_out(read_data1_ex),
        .read_data2_out(read_data2_ex),
        .imm_out(imm_ex),
        .pc_out(pc_ex),
        .rs1_out(rs1_ex),
        .rs2_out(rs2_ex),
        .rd_out(rd_ex),
        .funct3_out(funct3_ex),
        .funct7_out(funct7_ex)
    );
    
    // Store additional signals separately
    reg [3:0] alu_control_ex_reg;
    reg [1:0] byte_size_ex_reg;
    reg [6:0] opcode_ex_reg;
    
    always @(posedge clock or posedge reset) begin
        if (reset || flush_id_ex) begin
            alu_control_ex_reg <= 4'b0000;
            byte_size_ex_reg <= 2'b10;
            opcode_ex_reg <= 7'b0000000;
        end else begin
            alu_control_ex_reg <= alu_control_id;
            byte_size_ex_reg <= byte_size_id;
            opcode_ex_reg <= opcode_id;
        end
    end
    
    assign alu_control_ex = alu_control_ex_reg;
    assign byte_size_ex = byte_size_ex_reg;
    assign opcode_ex = opcode_ex_reg;
    
    // ========================================================================
    // EX STAGE - Execute
    // ========================================================================
    
    // Forwarding Unit
    wire [1:0] forward_a, forward_b;
    wire regwrite_mem;
    wire [4:0] rd_mem;
    wire [31:0] alu_result_mem;
    
    forwarding_unit forward_unit (
        .rs1_ex(rs1_ex),
        .rs2_ex(rs2_ex),
        .rd_mem(rd_mem),
        .rd_wb(rd_wb),
        .regwrite_mem(regwrite_mem),
        .regwrite_wb(regwrite_wb),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );
    
    // Forwarding Mux for ALU input A
    reg [31:0] alu_in1_forwarded;
    always @(*) begin
        case (forward_a)
            2'b00: alu_in1_forwarded = read_data1_ex;
            2'b01: alu_in1_forwarded = write_data_wb;
            2'b10: alu_in1_forwarded = alu_result_mem;
            default: alu_in1_forwarded = read_data1_ex;
        endcase
    end
    
    // Forwarding Mux for register data 2
    reg [31:0] forwarded_data2;
    always @(*) begin
        case (forward_b)
            2'b00: forwarded_data2 = read_data2_ex;
            2'b01: forwarded_data2 = write_data_wb;
            2'b10: forwarded_data2 = alu_result_mem;
            default: forwarded_data2 = read_data2_ex;
        endcase
    end
    
    // ALU input selection based on instruction type
    wire [31:0] alu_in1, alu_in2;
    wire is_auipc = (opcode_ex == 7'b0010111);
    wire is_lui = (opcode_ex == 7'b0110111);
    wire is_jalr = (opcode_ex == 7'b1100111);
    wire is_branch = (opcode_ex == 7'b1100011);
    
    // ALU Input 1: PC for AUIPC, 0 for LUI, forwarded register for others
    assign alu_in1 = is_auipc ? pc_ex :
                     is_lui ? 32'h00000000 :
                     alu_in1_forwarded;
    
    // ALU Input 2: 
    // - For BRANCH: MUST use forwarded_data2 (not immediate!)
    // - For I-type/Load/Store/AUIPC/LUI: use immediate
    // - For R-type: use forwarded_data2
    assign alu_in2 = (alusrc_ex && !is_branch) ? imm_ex : forwarded_data2;
    
    // ALU
    wire [31:0] alu_result_ex;
    wire zero_flag, less_than, less_than_u;
    
    alu alu_unit (
        .in1(alu_in1),
        .in2(alu_in2),
        .alu_control(alu_control_ex),
        .alu_result(alu_result_ex),
        .zero_flag(zero_flag),
        .less_than(less_than),
        .less_than_u(less_than_u)
    );
    
    // Branch Logic
    wire branch_decision;
    
    branch_logic branch_unit (
        .branch(branch_ex),
        .funct3(funct3_ex),
        .zero_flag(zero_flag),
        .less_than(less_than),
        .less_than_u(less_than_u),
        .taken(branch_decision)
    );
    
    // Branch/Jump target calculation
    wire is_jal = (opcode_ex == 7'b1101111);
    wire [31:0] jalr_target = alu_in1_forwarded + imm_ex;
    wire [31:0] branch_target_pc_based = pc_ex + imm_ex;
    
    assign branch_target_calc = is_jalr ? jalr_target : branch_target_pc_based;
    assign branch_taken_detected = branch_decision | jump_ex;
    
    // CRITICAL FIX: Apply branch immediately, don't register
    // When branch is detected in EX stage, update PC in the SAME cycle
    // to avoid losing PC_EX and IMM_EX information
    assign branch_taken_reg = branch_taken_detected;
    assign branch_target_reg = branch_target_calc;
    
    // Calculate PC+4 for JAL/JALR writeback
    wire [31:0] pc_plus_4_ex = pc_ex + 32'd4;
    
    // ========================================================================
    // EX/MEM Pipeline Register
    // ========================================================================
    reg regwrite_mem_reg, memwrite_mem, memread_mem, memtoreg_mem;
    reg [31:0] alu_result_mem_reg, write_data_mem, pc_plus_4_mem;
    reg [4:0] rd_mem_reg;
    reg [1:0] byte_size_mem;
    reg [2:0] funct3_mem;
    reg jump_mem;
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            regwrite_mem_reg <= 1'b0;
            memwrite_mem <= 1'b0;
            memread_mem <= 1'b0;
            memtoreg_mem <= 1'b0;
            alu_result_mem_reg <= 32'h0;
            write_data_mem <= 32'h0;
            rd_mem_reg <= 5'b0;
            byte_size_mem <= 2'b10;
            funct3_mem <= 3'b000;
            jump_mem <= 1'b0;
            pc_plus_4_mem <= 32'h0;
        end else begin
            regwrite_mem_reg <= regwrite_ex;
            memwrite_mem <= memwrite_ex;
            memread_mem <= memread_ex;
            memtoreg_mem <= memtoreg_ex;
            alu_result_mem_reg <= alu_result_ex;
            write_data_mem <= forwarded_data2;
            rd_mem_reg <= rd_ex;
            byte_size_mem <= byte_size_ex;
            funct3_mem <= funct3_ex;
            jump_mem <= jump_ex;
            pc_plus_4_mem <= pc_plus_4_ex;
        end
    end
    
    assign regwrite_mem = regwrite_mem_reg;
    assign alu_result_mem = alu_result_mem_reg;
    assign rd_mem = rd_mem_reg;
    
    // ========================================================================
    // MEM STAGE - Memory Access
    // ========================================================================
    wire [31:0] mem_read_data;
    wire sign_ext = (funct3_mem != 3'b100 && funct3_mem != 3'b101);
    
    data_mem data_memory (
        .clock(clock),
        .address(alu_result_mem),
        .write_data(write_data_mem),
        .memwrite(memwrite_mem),
        .memread(memread_mem),
        .byte_size(byte_size_mem),
        .sign_ext(sign_ext),
        .read_data(mem_read_data)
    );
    
    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    wire memtoreg_wb, jump_wb;
    wire [31:0] alu_result_wb, mem_data_wb, pc_plus_4_wb;
    
    reg regwrite_wb_reg, memtoreg_wb_reg, jump_wb_reg;
    reg [31:0] alu_result_wb_reg, mem_data_wb_reg, pc_plus_4_wb_reg;
    reg [4:0] rd_wb_reg;
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            regwrite_wb_reg <= 1'b0;
            memtoreg_wb_reg <= 1'b0;
            jump_wb_reg <= 1'b0;
            alu_result_wb_reg <= 32'h0;
            mem_data_wb_reg <= 32'h0;
            pc_plus_4_wb_reg <= 32'h0;
            rd_wb_reg <= 5'b0;
        end else begin
            regwrite_wb_reg <= regwrite_mem;
            memtoreg_wb_reg <= memtoreg_mem;
            jump_wb_reg <= jump_mem;
            alu_result_wb_reg <= alu_result_mem;
            mem_data_wb_reg <= mem_read_data;
            pc_plus_4_wb_reg <= pc_plus_4_mem;
            rd_wb_reg <= rd_mem;
        end
    end
    
    assign regwrite_wb = regwrite_wb_reg;
    assign memtoreg_wb = memtoreg_wb_reg;
    assign jump_wb = jump_wb_reg;
    assign alu_result_wb = alu_result_wb_reg;
    assign mem_data_wb = mem_data_wb_reg;
    assign pc_plus_4_wb = pc_plus_4_wb_reg;
    assign rd_wb = rd_wb_reg;
    
    // ========================================================================
    // WB STAGE - Write Back
    // ========================================================================
    wire [31:0] wb_data_temp = memtoreg_wb ? mem_data_wb : alu_result_wb;
    assign write_data_wb = jump_wb ? pc_plus_4_wb : wb_data_temp;
    
    // ========================================================================
    // Debug Outputs
    // ========================================================================
    assign pc_current = pc_if;
    assign instruction_current = instruction_if;
    assign alu_result_debug = alu_result_ex;
    assign mem_out_debug = mem_read_data;
    assign branch_taken_debug = branch_taken_reg;
    assign branch_target_debug = branch_target_reg;
    assign stall_debug = stall;
    assign forward_a_debug = forward_a;
    assign forward_b_debug = forward_b;

endmodule
