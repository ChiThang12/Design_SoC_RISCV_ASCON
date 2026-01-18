// ============================================================================
// datapath.v - RISC-V 5-Stage Pipelined CPU Core (Standalone)
// ============================================================================

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

module datapath (
    input wire clk,
    input wire reset,           // Active high reset
    
    // ========================================================================
    // Instruction Memory Interface (Simple)
    // ========================================================================
    output wire [31:0] imem_addr,
    output wire        imem_req,
    input wire [31:0]  imem_data,
    input wire         imem_ready,
    
    // ========================================================================
    // Data Memory Interface (Simple)
    // ========================================================================
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_req,
    output wire        dmem_wr,
    input wire [31:0]  dmem_rdata,
    input wire         dmem_ready,
    
    // ========================================================================
    // Debug Outputs
    // ========================================================================
    output wire [31:0] pc_current,
    output wire [31:0] instruction_current,
    output wire [31:0] alu_result_debug,
    output wire [31:0] mem_out_debug,
    output wire        branch_taken_debug,
    output wire [31:0] branch_target_debug,
    output wire        stall_debug,
    output wire [1:0]  forward_a_debug,
    output wire [1:0]  forward_b_debug
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    wire branch_taken_reg;
    wire [31:0] branch_target_reg;
    wire branch_taken_detected;
    wire [31:0] branch_target_calc;
    
    wire stall;
    wire hazard_stall;
    wire mem_stall;
    wire flush_if_id;
    wire flush_id_ex;

    // ========================================================================
    // IF STAGE - Instruction Fetch
    // ========================================================================
    wire [31:0] pc_if;
    wire [31:0] instruction_if;
    
    // PC Register - SIMPLIFIED VERSION
    reg [31:0] pc_reg;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_reg <= 32'h00000000;
        end else if (!stall) begin
            if (branch_taken_reg) begin
                pc_reg <= branch_target_reg;
            end else begin
                pc_reg <= pc_reg + 32'd4;
            end
        end
    end
    
    assign pc_if = pc_reg;
    assign instruction_if = imem_data;  // Direct connection, no NOP substitution
    assign imem_addr = pc_reg;
    assign imem_req = 1'b1;  // Always request
    
    // Stall conditions - FIXED
    assign mem_stall = !imem_ready;  // Only stall when imem not ready
    // assign stall = hazard_stall || mem_stall;
    assign stall = hazard_stall;
    // ========================================================================
    // IF/ID Pipeline Register
    // ========================================================================
    wire [31:0] instruction_id;
    wire [31:0] pc_id;
    
    PIPELINE_REG_IF_ID if_id_reg (
        .clock(clk),
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
        .clock(clk),
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
    
    hazard_detection hazard_unit (
        .memread_id_ex(memread_ex),
        .rd_id_ex(rd_ex),
        .rs1_id(rs1_id),
        .rs2_id(rs2_id),
        .branch_taken(branch_taken_reg),
        .stall(hazard_stall),
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
    
    PIPELINE_REG_ID_EX id_ex_reg (
        .clock(clk),
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
    
    // Store control signals
    reg [3:0] alu_control_ex_reg;
    reg [1:0] byte_size_ex_reg;
    reg [6:0] opcode_ex_reg;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            alu_control_ex_reg <= 4'b0000;
            byte_size_ex_reg <= 2'b10;
            opcode_ex_reg <= 7'b0000000;
        end else if (!stall) begin  // ⬅️ THÊM ĐIỀU KIỆN
            alu_control_ex_reg <= alu_control_id;
            byte_size_ex_reg <= byte_size_id;
            opcode_ex_reg <= opcode_id;
        end
    end
    
    wire [3:0] alu_control_ex = alu_control_ex_reg;
    wire [1:0] byte_size_ex = byte_size_ex_reg;
    wire [6:0] opcode_ex = opcode_ex_reg;
    
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
    
    // ALU input selection
    wire [31:0] alu_in1, alu_in2;
    wire is_auipc = (opcode_ex == 7'b0010111);
    wire is_lui = (opcode_ex == 7'b0110111);
    wire is_jalr = (opcode_ex == 7'b1100111);
    wire is_branch = (opcode_ex == 7'b1100011);
    
    assign alu_in1 = is_auipc ? pc_ex :
                     is_lui ? 32'h00000000 :
                     alu_in1_forwarded;
    
    assign alu_in2 = alusrc_ex ? imm_ex : forwarded_data2;
    
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
    assign branch_taken_detected = (branch_ex && branch_decision) || jump_ex;
    
    // Branch Register
    reg branch_taken_reg_reg;
    reg [31:0] branch_target_reg_reg;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_taken_reg_reg <= 1'b0;
            branch_target_reg_reg <= 32'h0;
        end else begin
            branch_taken_reg_reg <= branch_taken_detected;
            branch_target_reg_reg <= branch_target_calc;
        end
    end
    
    assign branch_taken_reg = branch_taken_reg_reg;
    assign branch_target_reg = branch_target_reg_reg;
    
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
    
    always @(posedge clk or posedge reset) begin
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
        end else if(!stall) begin
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
    
    // Align write data based on byte_size and address
    reg [31:0] aligned_write_data;
    always @(*) begin
        case (byte_size_mem)
            2'b00: begin  // Byte
                case (alu_result_mem[1:0])
                    2'b00: aligned_write_data = {24'b0, write_data_mem[7:0]};
                    2'b01: aligned_write_data = {16'b0, write_data_mem[7:0], 8'b0};
                    2'b10: aligned_write_data = {8'b0, write_data_mem[7:0], 16'b0};
                    2'b11: aligned_write_data = {write_data_mem[7:0], 24'b0};
                endcase
            end
            2'b01: begin  // Halfword
                aligned_write_data = alu_result_mem[1] ? 
                                    {write_data_mem[15:0], 16'b0} : 
                                    {16'b0, write_data_mem[15:0]};
            end
            2'b10: aligned_write_data = write_data_mem;  // Word
            default: aligned_write_data = write_data_mem;
        endcase
    end
    
    // Generate byte strobes
    reg [3:0] byte_strobe;
    always @(*) begin
        if (memwrite_mem) begin
            case (byte_size_mem)
                2'b00: begin  // Byte
                    case (alu_result_mem[1:0])
                        2'b00: byte_strobe = 4'b0001;
                        2'b01: byte_strobe = 4'b0010;
                        2'b10: byte_strobe = 4'b0100;
                        2'b11: byte_strobe = 4'b1000;
                    endcase
                end
                2'b01: begin  // Halfword
                    case (alu_result_mem[1:0])
                        2'b00: byte_strobe = 4'b0011;
                        2'b10: byte_strobe = 4'b1100;
                        default: byte_strobe = 4'b0011;
                    endcase
                end
                2'b10: byte_strobe = 4'b1111;
                default: byte_strobe = 4'b1111;
            endcase
        end else begin
            byte_strobe = 4'b1111;
        end
    end
    
    // Memory Interface Outputs
    assign dmem_addr  = alu_result_mem;
    assign dmem_wdata = aligned_write_data;
    assign dmem_wstrb = byte_strobe;
    assign dmem_req   = memread_mem | memwrite_mem;
    assign dmem_wr    = memwrite_mem;
    
    // ========================================================================
    // MEM/WB Pipeline Register
    // ========================================================================
    wire memtoreg_wb, jump_wb;
    wire [31:0] alu_result_wb, mem_data_wb, pc_plus_4_wb;
    wire [1:0] byte_size_wb;
    wire [2:0] funct3_wb;
    
    reg regwrite_wb_reg, memtoreg_wb_reg, jump_wb_reg;
    reg [31:0] alu_result_wb_reg, mem_data_wb_reg, pc_plus_4_wb_reg;
    reg [4:0] rd_wb_reg;
    reg [1:0] byte_size_wb_reg;
    reg [2:0] funct3_wb_reg;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            regwrite_wb_reg <= 1'b0;
            memtoreg_wb_reg <= 1'b0;
            jump_wb_reg <= 1'b0;
            alu_result_wb_reg <= 32'h0;
            mem_data_wb_reg <= 32'h0;
            pc_plus_4_wb_reg <= 32'h0;
            rd_wb_reg <= 5'b0;
            byte_size_wb_reg <= 2'b10;
            funct3_wb_reg <= 3'b010;
        end else if(!mem_stall) begin
            regwrite_wb_reg <= regwrite_mem;
            memtoreg_wb_reg <= memtoreg_mem;
            jump_wb_reg <= jump_mem;
            alu_result_wb_reg <= alu_result_mem;
            mem_data_wb_reg <= dmem_rdata;
            pc_plus_4_wb_reg <= pc_plus_4_mem;
            rd_wb_reg <= rd_mem;
            byte_size_wb_reg <= byte_size_mem;
            funct3_wb_reg <= funct3_mem;
        end
    end
    
    assign regwrite_wb = regwrite_wb_reg;
    assign memtoreg_wb = memtoreg_wb_reg;
    assign jump_wb = jump_wb_reg;
    assign alu_result_wb = alu_result_wb_reg;
    assign mem_data_wb = mem_data_wb_reg;
    assign pc_plus_4_wb = pc_plus_4_wb_reg;
    assign rd_wb = rd_wb_reg;
    assign byte_size_wb = byte_size_wb_reg;
    assign funct3_wb = funct3_wb_reg;
    
    // ========================================================================
    // WB STAGE - Write Back
    // ========================================================================
    
    // Sign/Zero extend loaded data
    reg [31:0] extended_mem_data;
    always @(*) begin
        case (byte_size_wb)
            2'b00: begin  // Byte
                case (alu_result_wb[1:0])
                    2'b00: extended_mem_data = funct3_wb[2] ? 
                           {24'b0, mem_data_wb[7:0]} :              // LBU
                           {{24{mem_data_wb[7]}}, mem_data_wb[7:0]};  // LB
                    2'b01: extended_mem_data = funct3_wb[2] ? 
                           {24'b0, mem_data_wb[15:8]} : 
                           {{24{mem_data_wb[15]}}, mem_data_wb[15:8]};
                    2'b10: extended_mem_data = funct3_wb[2] ? 
                           {24'b0, mem_data_wb[23:16]} : 
                           {{24{mem_data_wb[23]}}, mem_data_wb[23:16]};
                    2'b11: extended_mem_data = funct3_wb[2] ? 
                           {24'b0, mem_data_wb[31:24]} : 
                           {{24{mem_data_wb[31]}}, mem_data_wb[31:24]};
                endcase
            end
            2'b01: begin  // Halfword
                extended_mem_data = alu_result_wb[1] ? 
                    (funct3_wb[2] ? {16'b0, mem_data_wb[31:16]} :       // LHU
                                    {{16{mem_data_wb[31]}}, mem_data_wb[31:16]}) :  // LH
                    (funct3_wb[2] ? {16'b0, mem_data_wb[15:0]} : 
                                    {{16{mem_data_wb[15]}}, mem_data_wb[15:0]});
            end
            2'b10: extended_mem_data = mem_data_wb;  // Word (LW)
            default: extended_mem_data = mem_data_wb;
        endcase
    end
    
    wire [31:0] wb_data_temp = memtoreg_wb ? extended_mem_data : alu_result_wb;
    assign write_data_wb = jump_wb ? pc_plus_4_wb : wb_data_temp;
    
    // ========================================================================
    // Debug Outputs
    // ========================================================================
    assign pc_current = pc_if;
    assign instruction_current = instruction_if;
    assign alu_result_debug = alu_result_mem;      // ⬅️ ĐỔI TỪ _ex SANG _mem
    assign mem_out_debug = mem_data_wb;            // ⬅️ ĐỔI TỪ dmem_rdata SANG _wb
    assign branch_taken_debug = branch_taken_reg;
    assign branch_target_debug = branch_target_reg;
    assign stall_debug = stall;
    assign forward_a_debug = forward_a;
    assign forward_b_debug = forward_b;

endmodule