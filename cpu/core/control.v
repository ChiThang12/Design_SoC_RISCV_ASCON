// ============================================================================
// CONTROL.v - RISC-V Control Unit
// ============================================================================
// Mô tả: Sinh tất cả tín hiệu điều khiển dựa trên opcode, funct3, funct7
// Hỗ trợ: RV32I + RV32M (Integer + Multiply/Divide)
// ============================================================================

module control (
    // Input từ Instruction
    input wire [6:0] opcode,
    input wire [2:0] funct3,
    input wire [6:0] funct7,
    
    // Output: Control Signals
    output reg [3:0] alu_control,    // Điều khiển ALU operation
    output reg regwrite,             // Enable ghi register
    output reg alusrc,               // Chọn nguồn cho ALU: 0=reg, 1=imm
    output reg memread,              // Enable đọc memory
    output reg memwrite,             // Enable ghi memory
    output reg memtoreg,             // Chọn dữ liệu ghi vào reg: 0=alu, 1=mem
    output reg branch,               // Lệnh branch
    output reg jump,                 // Lệnh jump (JAL/JALR)
    output reg [1:0] aluop,          // Loại operation cho ALU decoder
    output reg [1:0] byte_size       // Kích thước data: 00=byte, 01=half, 10=word
);

    // ========================================================================
    // RISC-V Opcode Definition
    // ========================================================================
    localparam [6:0]
        OP_R_TYPE   = 7'b0110011,    // R-type: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
        OP_I_TYPE   = 7'b0010011,    // I-type: ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU
        OP_LOAD     = 7'b0000011,    // Load: LB, LH, LW, LBU, LHU
        OP_STORE    = 7'b0100011,    // Store: SB, SH, SW
        OP_BRANCH   = 7'b1100011,    // Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
        OP_JAL      = 7'b1101111,    // Jump: JAL
        OP_JALR     = 7'b1100111,    // Jump: JALR
        OP_LUI      = 7'b0110111,    // Load Upper Immediate
        OP_AUIPC    = 7'b0010111;    // Add Upper Immediate to PC
    
    // ========================================================================
    // ALU Control Codes
    // ========================================================================
    localparam [3:0]
        ALU_ADD   = 4'b0000,
        ALU_SUB   = 4'b0001,
        ALU_AND   = 4'b0010,
        ALU_OR    = 4'b0011,
        ALU_XOR   = 4'b0100,
        ALU_SLL   = 4'b0101,
        ALU_SRL   = 4'b0110,
        ALU_SRA   = 4'b0111,
        ALU_SLT   = 4'b1000,
        ALU_SLTU  = 4'b1001,
        ALU_MUL   = 4'b1010,
        ALU_MULH  = 4'b1011,
        ALU_DIV   = 4'b1100,
        ALU_DIVU  = 4'b1101,
        ALU_REM   = 4'b1110,
        ALU_REMU  = 4'b1111;
    
    // ========================================================================
    // Funct3 Codes
    // ========================================================================
    localparam [2:0]
        F3_ADD_SUB  = 3'b000,    // ADD/ADDI hoặc SUB
        F3_SLL      = 3'b001,    // SLL/SLLI
        F3_SLT      = 3'b010,    // SLT/SLTI
        F3_SLTU     = 3'b011,    // SLTU/SLTIU
        F3_XOR      = 3'b100,    // XOR/XORI
        F3_SRL_SRA  = 3'b101,    // SRL/SRLI hoặc SRA/SRAI
        F3_OR       = 3'b110,    // OR/ORI
        F3_AND      = 3'b111,    // AND/ANDI
        
        // Load/Store size
        F3_BYTE     = 3'b000,    // LB/SB
        F3_HALF     = 3'b001,    // LH/SH
        F3_WORD     = 3'b010,    // LW/SW
        F3_BYTE_U   = 3'b100,    // LBU
        F3_HALF_U   = 3'b101,    // LHU
        
        // Branch conditions
        F3_BEQ      = 3'b000,
        F3_BNE      = 3'b001,
        F3_BLT      = 3'b100,
        F3_BGE      = 3'b101,
        F3_BLTU     = 3'b110,
        F3_BGEU     = 3'b111,
        
        // M Extension (Multiply/Divide)
        F3_MUL      = 3'b000,
        F3_MULH     = 3'b001,
        F3_DIV      = 3'b100,
        F3_DIVU     = 3'b101,
        F3_REM      = 3'b110,
        F3_REMU     = 3'b111;
    
    // ========================================================================
    // Funct7 Codes
    // ========================================================================
    localparam [6:0]
        F7_DEFAULT  = 7'b0000000,    // ADD, SRL, etc.
        F7_SUB_SRA  = 7'b0100000,    // SUB, SRA
        F7_MULDIV   = 7'b0000001;    // M Extension
    
    // ========================================================================
    // Main Control Logic
    // ========================================================================
    always @(*) begin
        // Default values (tránh latch)
        regwrite   = 0;
        alusrc     = 0;
        memread    = 0;
        memwrite   = 0;
        memtoreg   = 0;
        branch     = 0;
        jump       = 0;
        aluop      = 2'b00;
        byte_size  = 2'b10;    // Default: word (32-bit)
        alu_control = ALU_ADD;
        
        case (opcode)
            // ================================================================
            // R-TYPE: Thanh ghi đến thanh ghi
            // ================================================================
            OP_R_TYPE: begin
                regwrite = 1;
                alusrc   = 0;    // ALU nguồn 2 từ register
                aluop    = 2'b10;
                
                // Kiểm tra M Extension (Multiply/Divide)
                if (funct7 == F7_MULDIV) begin
                    case (funct3)
                        F3_MUL:   alu_control = ALU_MUL;
                        F3_MULH:  alu_control = ALU_MULH;
                        F3_DIV:   alu_control = ALU_DIV;
                        F3_DIVU:  alu_control = ALU_DIVU;
                        F3_REM:   alu_control = ALU_REM;
                        F3_REMU:  alu_control = ALU_REMU;
                        default:  alu_control = ALU_ADD;
                    endcase
                end
                else begin
                    // R-type standard operations
                    case (funct3)
                        F3_ADD_SUB: begin
                            if (funct7 == F7_SUB_SRA)
                                alu_control = ALU_SUB;
                            else
                                alu_control = ALU_ADD;
                        end
                        F3_SLL:     alu_control = ALU_SLL;
                        F3_SLT:     alu_control = ALU_SLT;
                        F3_SLTU:    alu_control = ALU_SLTU;
                        F3_XOR:     alu_control = ALU_XOR;
                        F3_SRL_SRA: begin
                            if (funct7 == F7_SUB_SRA)
                                alu_control = ALU_SRA;
                            else
                                alu_control = ALU_SRL;
                        end
                        F3_OR:      alu_control = ALU_OR;
                        F3_AND:     alu_control = ALU_AND;
                        default:    alu_control = ALU_ADD;
                    endcase
                end
            end
            
            // ================================================================
            // I-TYPE: Immediate operations
            // ================================================================
            OP_I_TYPE: begin
                regwrite = 1;
                alusrc   = 1;    // ALU nguồn 2 từ immediate
                aluop    = 2'b10;
                
                case (funct3)
                    F3_ADD_SUB: alu_control = ALU_ADD;    // ADDI
                    F3_SLL:     alu_control = ALU_SLL;    // SLLI
                    F3_SLT:     alu_control = ALU_SLT;    // SLTI
                    F3_SLTU:    alu_control = ALU_SLTU;   // SLTIU
                    F3_XOR:     alu_control = ALU_XOR;    // XORI
                    F3_SRL_SRA: begin
                        if (funct7 == F7_SUB_SRA)
                            alu_control = ALU_SRA;        // SRAI
                        else
                            alu_control = ALU_SRL;        // SRLI
                    end
                    F3_OR:      alu_control = ALU_OR;     // ORI
                    F3_AND:     alu_control = ALU_AND;    // ANDI
                    default:    alu_control = ALU_ADD;
                endcase
            end
            
            // ================================================================
            // LOAD: Đọc từ memory
            // ================================================================
            OP_LOAD: begin
                regwrite  = 1;
                alusrc    = 1;       // Địa chỉ = rs1 + immediate
                memread   = 1;
                memtoreg  = 1;       // Dữ liệu từ memory vào register
                alu_control = ALU_ADD;
                
                case (funct3)
                    F3_BYTE:   byte_size = 2'b00;    // LB (8-bit)
                    F3_HALF:   byte_size = 2'b01;    // LH (16-bit)
                    F3_WORD:   byte_size = 2'b10;    // LW (32-bit)
                    F3_BYTE_U: byte_size = 2'b00;    // LBU
                    F3_HALF_U: byte_size = 2'b01;    // LHU
                    default:   byte_size = 2'b10;
                endcase
            end
            
            // ================================================================
            // STORE: Ghi vào memory
            // ================================================================
            OP_STORE: begin
                alusrc    = 1;       // Địa chỉ = rs1 + immediate
                memwrite  = 1;
                alu_control = ALU_ADD;
                
                case (funct3)
                    F3_BYTE: byte_size = 2'b00;    // SB (8-bit)
                    F3_HALF: byte_size = 2'b01;    // SH (16-bit)
                    F3_WORD: byte_size = 2'b10;    // SW (32-bit)
                    default: byte_size = 2'b10;
                endcase
            end
            
            // ================================================================
            // BRANCH: Điều kiện nhảy
            // ================================================================
            OP_BRANCH: begin
                branch = 1;
                alusrc = 0;          // So sánh 2 register
                alu_control = ALU_SUB;  // Dùng SUB để so sánh
            end
            
            // ================================================================
            // JAL: Jump and Link
            // ================================================================
            OP_JAL: begin
                regwrite = 1;
                jump     = 1;
                alu_control = ALU_ADD;
            end
            
            // ================================================================
            // JALR: Jump and Link Register
            // ================================================================
            OP_JALR: begin
                regwrite = 1;
                jump     = 1;
                alusrc   = 1;        // Địa chỉ = rs1 + immediate
                alu_control = ALU_ADD;
            end
            
            // ================================================================
            // LUI: Load Upper Immediate
            // ================================================================
            OP_LUI: begin
                regwrite = 1;
                alusrc   = 1;
                alu_control = ALU_ADD;  // Immediate << 12
            end
            
            // ================================================================
            // AUIPC: Add Upper Immediate to PC
            // ================================================================
            OP_AUIPC: begin
                regwrite = 1;
                alusrc   = 1;
                alu_control = ALU_ADD;  // PC + (immediate << 12)
            end
            
            // Default: NOP
            default: begin
                regwrite = 0;
                alusrc   = 0;
                memread  = 0;
                memwrite = 0;
                memtoreg = 0;
                branch   = 0;
                jump     = 0;
                alu_control = ALU_ADD;
            end
        endcase
    end

endmodule