`timescale 1ns/1ps
`include "cpu/riscv_cpu_core_v2.v"

// ============================================================================
// tb_riscv_cpu_core_v2_DEBUG.v - Detailed Logging Version
// ============================================================================

module tb_riscv_cpu_core_v2_DEBUG;

parameter CLK_PERIOD = 10;
parameter TIMEOUT    = 100_000;
parameter LOG_CYCLES = 100;  // Log first 100 cycles in detail

reg clk, rst;

wire [31:0] imem_addr;
wire        imem_valid;
reg  [31:0] imem_rdata;
reg         imem_ready;

wire [31:0] dmem_addr;
wire [31:0] dmem_wdata;
wire [3:0]  dmem_wstrb;
wire        dmem_valid;
wire        dmem_we;
reg  [31:0] dmem_rdata;
reg         dmem_ready;

integer pass_count, fail_count;
integer cycle_count;

// ============================================================================
// DUT
// ============================================================================
riscv_cpu_core dut (
    .clk(clk), .rst(rst),
    .imem_addr(imem_addr), .imem_valid(imem_valid),
    .imem_rdata(imem_rdata), .imem_ready(imem_ready),
    .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
    .dmem_wstrb(dmem_wstrb), .dmem_valid(dmem_valid),
    .dmem_we(dmem_we), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready)
);

// ============================================================================
// Memories
// ============================================================================
reg [31:0] imem [0:255];
reg [31:0] dmem [0:4095];

always @(*) begin
    if (imem_valid && imem_ready)
        imem_rdata = imem[imem_addr[9:2]];
    else
        imem_rdata = 32'h00000013;
end

always @(posedge clk) begin
    if (dmem_valid && dmem_ready) begin
        if (dmem_we) begin
            if (dmem_wstrb[0]) dmem[dmem_addr[13:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_addr[13:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_addr[13:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_addr[13:2]][31:24] <= dmem_wdata[31:24];
        end else begin
            dmem_rdata <= dmem[dmem_addr[13:2]];
        end
    end
end

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

initial begin 
    $dumpfile("dump_gcc_debug.vcd"); 
    $dumpvars(0, tb_riscv_cpu_core_v2_DEBUG); 
end

initial begin #TIMEOUT; $display("\n⚠️  TIMEOUT"); print_summary(); $finish; end

// ============================================================================
// Cycle Monitor - Log every cycle
// ============================================================================
always @(posedge clk) begin
    if (!rst && cycle_count < LOG_CYCLES) begin
        $display("════════════════════════════════════════════════════════════════");
        $display("CYCLE %3d @ %0t ns", cycle_count, $time);
        $display("────────────────────────────────────────────────────────────────");
        
        // Pipeline stages
        $display("  IF:  PC=0x%03X  Instr=0x%08X  %s", 
                 dut.pc_if, dut.instr_if, decode_instr(dut.instr_if));
        $display("  ID:  PC=0x%03X  Instr=0x%08X", 
                 dut.pc_id, dut.instr_id);
        $display("  EX:  PC=0x%03X  opcode=0x%02X", 
                 dut.pc_ex, dut.opcode_ex);
        
        // Control signals
        $display("  Control: stall=%b  flush_IF/ID=%b  flush_ID/EX=%b  pc_src=%b",
                 dut.stall, dut.flush_if_id, dut.flush_id_ex, dut.pc_src_ex);
        
        // Key registers (only show non-zero)
        if (dut.register_file.registers[1] != 0)
            $display("  x1  (ra) = 0x%08X", dut.register_file.registers[1]);
        if (dut.register_file.registers[2] != 0)
            $display("  x2  (sp) = 0x%08X", dut.register_file.registers[2]);
        if (dut.register_file.registers[5] != 0)
            $display("  x5  (t0) = 0x%08X", dut.register_file.registers[5]);
        if (dut.register_file.registers[6] != 0)
            $display("  x6  (t1) = 0x%08X", dut.register_file.registers[6]);
        if (dut.register_file.registers[10] != 0)
            $display("  x10 (a0) = 0x%08X", dut.register_file.registers[10]);
        if (dut.register_file.registers[14] != 0)
            $display("  x14 (a4) = 0x%08X", dut.register_file.registers[14]);
        if (dut.register_file.registers[15] != 0)
            $display("  x15 (a5) = 0x%08X", dut.register_file.registers[15]);
        
        // Memory operations
        if (dmem_valid && dmem_we) begin
            $display("  DMEM WRITE: addr=0x%04X  data=0x%08X  strb=%b", 
                     dmem_addr, dmem_wdata, dmem_wstrb);
        end
        if (dmem_valid && !dmem_we) begin
            $display("  DMEM READ:  addr=0x%04X", dmem_addr);
        end
        
        // Branch/Jump detection
        if (dut.branch_ex && dut.branch_taken_ex) begin
            $display("  🔀 BRANCH TAKEN: target=0x%03X", dut.target_pc_ex);
        end
        if (dut.jump_ex) begin
            $display("  🔀 JUMP: target=0x%03X", dut.target_pc_ex);
        end
    end
end

// Increment cycle counter
always @(posedge clk) begin
    if (!rst) cycle_count <= cycle_count + 1;
    else cycle_count <= 0;
end

// ============================================================================
// Instruction Decoder (for human-readable output)
// ============================================================================
function [255:0] decode_instr;
    input [31:0] instr;
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg [4:0] rd, rs1, rs2;
    begin
        opcode = instr[6:0];
        rd = instr[11:7];
        funct3 = instr[14:12];
        rs1 = instr[19:15];
        rs2 = instr[24:20];
        
        case (opcode)
            7'b0010111: decode_instr = "AUIPC";
            7'b0110111: decode_instr = "LUI";
            7'b1101111: decode_instr = "JAL";
            7'b1100111: decode_instr = "JALR";
            7'b1100011: begin
                case (funct3)
                    3'b000: decode_instr = "BEQ";
                    3'b001: decode_instr = "BNE";
                    3'b100: decode_instr = "BLT";
                    3'b101: decode_instr = "BGE";
                    3'b110: decode_instr = "BLTU";
                    3'b111: decode_instr = "BGEU";
                    default: decode_instr = "BRANCH";
                endcase
            end
            7'b0000011: begin
                case (funct3)
                    3'b000: decode_instr = "LB";
                    3'b001: decode_instr = "LH";
                    3'b010: decode_instr = "LW";
                    3'b100: decode_instr = "LBU";
                    3'b101: decode_instr = "LHU";
                    default: decode_instr = "LOAD";
                endcase
            end
            7'b0100011: begin
                case (funct3)
                    3'b000: decode_instr = "SB";
                    3'b001: decode_instr = "SH";
                    3'b010: decode_instr = "SW";
                    default: decode_instr = "STORE";
                endcase
            end
            7'b0010011: begin
                case (funct3)
                    3'b000: decode_instr = "ADDI";
                    3'b010: decode_instr = "SLTI";
                    3'b011: decode_instr = "SLTIU";
                    3'b100: decode_instr = "XORI";
                    3'b110: decode_instr = "ORI";
                    3'b111: decode_instr = "ANDI";
                    3'b001: decode_instr = "SLLI";
                    3'b101: decode_instr = "SRLI/SRAI";
                    default: decode_instr = "ALU_IMM";
                endcase
            end
            7'b0110011: begin
                case (funct3)
                    3'b000: decode_instr = "ADD/SUB";
                    3'b001: decode_instr = "SLL";
                    3'b010: decode_instr = "SLT";
                    3'b011: decode_instr = "SLTU";
                    3'b100: decode_instr = "XOR";
                    3'b101: decode_instr = "SRL/SRA";
                    3'b110: decode_instr = "OR";
                    3'b111: decode_instr = "AND";
                    default: decode_instr = "ALU_REG";
                endcase
            end
            7'b0000000: decode_instr = "INVALID";
            7'b0001111: decode_instr = "FENCE";
            7'b1110011: decode_instr = "ECALL/EBREAK";
            default: begin
                if (instr == 32'h00000013)
                    decode_instr = "NOP";
                else
                    decode_instr = "UNKNOWN";
            end
        endcase
    end
endfunction

// ============================================================================
// Main Test
// ============================================================================
integer i;

initial begin
    pass_count = 0;
    fail_count = 0;
    cycle_count = 0;
    imem_ready = 1;
    dmem_ready = 1;
    dmem_rdata = 32'h0;
    
    for (i = 0; i < 256;  i = i + 1) imem[i] = 32'h00000013;
    for (i = 0; i < 4096; i = i + 1) dmem[i] = 32'h00000000;

    // Load program
    imem[0]  = 32'h00001117; // AUIPC  x2, 0x1
    imem[1]  = 32'h00010113; // ADDI   x2, x2, 0
    imem[2]  = 32'h00001297; // AUIPC  x5, 0x1
    imem[3]  = 32'hFFC28293; // ADDI   x5, x5, -4
    imem[4]  = 32'h00001317; // AUIPC  x6, 0x1
    imem[5]  = 32'h03430313; // ADDI   x6, x6, 52
    imem[6]  = 32'h0062D863; // BGE    x5, x6, +16
    imem[7]  = 32'h0002A023; // SW     x0, 0(x5)
    imem[8]  = 32'h00428293; // ADDI   x5, x5, 4
    imem[9]  = 32'hFF5FF06F; // JAL    x0, -12
    imem[10] = 32'h008000EF; // JAL    x1, +8
    imem[11] = 32'h0000006F; // JAL    x0, 0
    imem[12] = 32'hFE010113; // ADDI   x2, x2, -32
    imem[13] = 32'h00812E23; // SW     x8, 28(x2)
    imem[14] = 32'h02010413; // ADDI   x8, x2, 32
    imem[15] = 32'h00A00793; // ADDI   x15, x0, 10
    imem[16] = 32'hFEF42623; // SW     x15, -20(x8)
    imem[17] = 32'h00500793; // ADDI   x15, x0, 5
    imem[18] = 32'hFEF42423; // SW     x15, -24(x8)
    imem[19] = 32'hFEC42703; // LW     x14, -20(x8)
    imem[20] = 32'hFE842783; // LW     x15, -24(x8)
    imem[21] = 32'h00F707B3; // ADD    x15, x14, x15
    imem[22] = 32'hFEF42223; // SW     x15, -28(x8)
    imem[23] = 32'hFE442783; // LW     x15, -28(x8)
    imem[24] = 32'h00078513; // ADDI   x10, x15, 0
    imem[25] = 32'h01C12403; // LW     x8, 28(x2)
    imem[26] = 32'h02010113; // ADDI   x2, x2, 32
    imem[27] = 32'h00008067; // JALR   x0, x1, 0
    imem[28] = 32'h00002000;
    imem[29] = 32'h00000013;
    imem[30] = 32'h00000013;

    rst = 1;
    #(CLK_PERIOD * 4);
    rst = 0;

    $display("\n╔═══════════════════════════════════════════════════╗");
    $display("║   GCC Program Debug Test                          ║");
    $display("║   Cycle-by-cycle logging enabled                  ║");
    $display("╚═══════════════════════════════════════════════════╝\n");

    // Wait for execution
    #(CLK_PERIOD * 600);
    
    $display("\n\n");
    $display("════════════════════════════════════════════════════════════════");
    $display("FINAL STATE AFTER %0d CYCLES", cycle_count);
    $display("════════════════════════════════════════════════════════════════");
    $display("");
    $display("=== Register Dump ===");
    $display("  x1  (ra) = 0x%08X", dut.register_file.registers[1]);
    $display("  x2  (sp) = 0x%08X", dut.register_file.registers[2]);
    $display("  x5  (t0) = 0x%08X", dut.register_file.registers[5]);
    $display("  x6  (t1) = 0x%08X", dut.register_file.registers[6]);
    $display("  x8  (s0) = 0x%08X", dut.register_file.registers[8]);
    $display("  x10 (a0) = 0x%08X", dut.register_file.registers[10]);
    $display("  x14 (a4) = 0x%08X", dut.register_file.registers[14]);
    $display("  x15 (a5) = 0x%08X", dut.register_file.registers[15]);
    $display("");
    $display("=== PC Status ===");
    $display("  PC = 0x%08X", dut.pc_if);
    $display("");

    $display("=== Verification ===");
    check_reg(10, 32'd15,       "x10 = add(10,5) = 15");
    check_reg(2,  32'h00001000, "x2 (sp) = 0x1000");
    check_reg(1,  32'h0000002C, "x1 (ra) = 0x2C");
    check_dmem(1019, 32'd10,    "dmem[fp-20] = a = 10");
    check_dmem(1018, 32'd5,     "dmem[fp-24] = b = 5");
    check_dmem(1017, 32'd15,    "dmem[fp-28] = result = 15");
    check_dmem(1025, 32'd0,     "BSS dmem[0x1004/4] = 0");
    check_dmem(1030, 32'd0,     "BSS dmem[0x1018/4] = 0");

    print_summary();
    $finish;
end

task check_reg;
    input [4:0] rn; input [31:0] expected; input [511:0] name;
    reg [31:0] actual;
    begin
        actual = dut.register_file.registers[rn];
        if (actual === expected) begin
            $display("  ✅ PASS  %-40s  x%02d = 0x%08X", name, rn, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  ❌ FAIL  %-40s  x%02d = 0x%08X  (exp 0x%08X)", name, rn, actual, expected);
            fail_count = fail_count + 1;
        end
    end
endtask

task check_dmem;
    input [31:0] widx; input [31:0] expected; input [511:0] name;
    reg [31:0] actual;
    begin
        actual = dmem[widx];
        if (actual === expected) begin
            $display("  ✅ PASS  %-40s  mem[%0d] = 0x%08X", name, widx, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  ❌ FAIL  %-40s  mem[%0d] = 0x%08X  (exp 0x%08X)", name, widx, actual, expected);
            fail_count = fail_count + 1;
        end
    end
endtask

task print_summary;
    begin
        $display("");
        $display("╔═══════════════════════════════════════════════════╗");
        $display("║              Test Summary                         ║");
        $display("╠═══════════════════════════════════════════════════╣");
        $display("║  Total: %3d    PASS: %3d    FAIL: %3d            ║", 
                 pass_count+fail_count, pass_count, fail_count);
        if (fail_count == 0)
            $display("║           ALL CHECKS PASSED ✅                    ║");
        else
            $display("║           %0d CHECK(S) FAILED ❌                   ║", fail_count);
        $display("╚═══════════════════════════════════════════════════╝");
    end
endtask

endmodule