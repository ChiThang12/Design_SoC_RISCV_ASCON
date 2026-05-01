`timescale 1ns/1ps

// ============================================================================
// tb_riscv_cpu_core_v2.v  — Icarus Verilog compatible (FINAL v4)
//
// ROOT CAUSE OF ALL FAILURES (confirmed by IFU.v analysis):
//
//   IFU.v thiết kế cho COMBINATIONAL memory (same-cycle response):
//     assign imem_addr  = PC;        // combinational
//     assign imem_valid = 1'b1;
//     PC update: if (!stall && imem_ready) PC <= next_pc;
//     Instruction_Code = imem_ready ? imem_rdata : instr_hold;
//
//   Với IFU này:
//     - imem_addr = PC (combinational, thay đổi ngay khi PC đổi)
//     - imem_rdata PHẢI valid TRONG CÙNG CYCLE với imem_valid=1
//     - imem_ready=1 có nghĩa "rdata tôi gửi ngay cycle này là đúng"
//
//   TB cũ dùng REGISTERED response (always @posedge clk):
//     Posedge N: TB thấy imem_addr=PC_old → imem_rdata<=imem[PC_old], ready<=1
//     Posedge N+1: imem_ready=1, nhưng imem_rdata=imem[PC_old], còn IFU đã
//                  update PC=PC_old+4 → IFU latch sai instruction!
//     → Mỗi instruction bị fetch 2 lần, PC của instruction bị lệch +4
//     → TC-06: AUIPC ở pc=8 thay vì pc=4 → x2=0x1008 thay vì 0x1004
//     → TC-08/12/13: Load pipeline bị desync → load trả về 0
//     → TC-04/09: Branch targets bị lệch cycle
//
//   FIX: Đổi TB imem sang COMBINATIONAL (always @(*)):
//     imem_rdata = imem[imem_addr[11:2]]  -- ngay lập tức
//     imem_ready = imem_valid             -- ready ngay khi valid (no miss)
//     IFU thấy đúng data cùng cycle với imem_addr → hoạt động đúng thiết kế
//
//   Với dcache: LSU cũng thiết kế tương tự (dcache_req → dcache_ready same cycle
//   hoặc next cycle). LSU có FSM LOAD_DCACHE chờ dcache_ready → OK với
//   registered dcache response, nhưng combinational cũng hoạt động tốt hơn.
//   → Đổi dcache sang combinational để nhất quán.
//
//   ICache miss simulation: dùng counter để delay N cycles trước khi
//   assert imem_ready=1 (vẫn là combinational logic với registered counter).
//
// ============================================================================
`timescale 1ns/1ps
`include "cpu/riscv_cpu_core_v2.v"

module tb_riscv_cpu_core_v2;

// ---------------------------------------------------------------------------
// Clock / Reset
// ---------------------------------------------------------------------------
reg clk, rst;
initial clk = 0;
always #5 clk = ~clk;   // 100 MHz

// ---------------------------------------------------------------------------
// DUT I/O
// ---------------------------------------------------------------------------
wire [31:0] imem_addr;
wire        imem_valid;
reg  [31:0] imem_rdata;
reg         imem_ready;

wire [31:0] dcache_addr;
wire [31:0] dcache_wdata;
wire [3:0]  dcache_wstrb;
wire        dcache_req;
wire        dcache_we;
reg  [31:0] dcache_rdata;
reg         dcache_ready;

reg  external_irq, timer_irq, sw_irq;

// ---------------------------------------------------------------------------
// DUT
// ---------------------------------------------------------------------------
riscv_cpu_core dut (
    .clk          (clk),
    .rst          (rst),
    .imem_addr    (imem_addr),
    .imem_valid   (imem_valid),
    .imem_rdata   (imem_rdata),
    .imem_ready   (imem_ready),
    .dcache_addr  (dcache_addr),
    .dcache_wdata (dcache_wdata),
    .dcache_wstrb (dcache_wstrb),
    .dcache_req   (dcache_req),
    .dcache_we    (dcache_we),
    .dcache_rdata (dcache_rdata),
    .dcache_ready (dcache_ready),
    .external_irq (external_irq),
    .timer_irq    (timer_irq),
    .sw_irq       (sw_irq)
);

// ---------------------------------------------------------------------------
// Register-file probe (constant index at module scope — iverilog OK)
// ---------------------------------------------------------------------------
wire [31:0] _rf0  = dut.register_file.registers[0];
wire [31:0] _rf1  = dut.register_file.registers[1];
wire [31:0] _rf2  = dut.register_file.registers[2];
wire [31:0] _rf3  = dut.register_file.registers[3];
wire [31:0] _rf4  = dut.register_file.registers[4];
wire [31:0] _rf5  = dut.register_file.registers[5];
wire [31:0] _rf6  = dut.register_file.registers[6];
wire [31:0] _rf7  = dut.register_file.registers[7];
wire [31:0] _rf8  = dut.register_file.registers[8];
wire [31:0] _rf9  = dut.register_file.registers[9];
wire [31:0] _rf10 = dut.register_file.registers[10];
wire [31:0] _rf11 = dut.register_file.registers[11];
wire [31:0] _rf12 = dut.register_file.registers[12];
wire [31:0] _rf13 = dut.register_file.registers[13];
wire [31:0] _rf14 = dut.register_file.registers[14];
wire [31:0] _rf15 = dut.register_file.registers[15];
wire [31:0] _rf16 = dut.register_file.registers[16];
wire [31:0] _rf17 = dut.register_file.registers[17];
wire [31:0] _rf18 = dut.register_file.registers[18];
wire [31:0] _rf19 = dut.register_file.registers[19];
wire [31:0] _rf20 = dut.register_file.registers[20];
wire [31:0] _rf21 = dut.register_file.registers[21];
wire [31:0] _rf22 = dut.register_file.registers[22];
wire [31:0] _rf23 = dut.register_file.registers[23];
wire [31:0] _rf24 = dut.register_file.registers[24];
wire [31:0] _rf25 = dut.register_file.registers[25];
wire [31:0] _rf26 = dut.register_file.registers[26];
wire [31:0] _rf27 = dut.register_file.registers[27];
wire [31:0] _rf28 = dut.register_file.registers[28];
wire [31:0] _rf29 = dut.register_file.registers[29];
wire [31:0] _rf30 = dut.register_file.registers[30];
wire [31:0] _rf31 = dut.register_file.registers[31];

reg [31:0] rf_snap [0:31];
always @(negedge clk) begin
    rf_snap[ 0]<=_rf0;  rf_snap[ 1]<=_rf1;  rf_snap[ 2]<=_rf2;  rf_snap[ 3]<=_rf3;
    rf_snap[ 4]<=_rf4;  rf_snap[ 5]<=_rf5;  rf_snap[ 6]<=_rf6;  rf_snap[ 7]<=_rf7;
    rf_snap[ 8]<=_rf8;  rf_snap[ 9]<=_rf9;  rf_snap[10]<=_rf10; rf_snap[11]<=_rf11;
    rf_snap[12]<=_rf12; rf_snap[13]<=_rf13; rf_snap[14]<=_rf14; rf_snap[15]<=_rf15;
    rf_snap[16]<=_rf16; rf_snap[17]<=_rf17; rf_snap[18]<=_rf18; rf_snap[19]<=_rf19;
    rf_snap[20]<=_rf20; rf_snap[21]<=_rf21; rf_snap[22]<=_rf22; rf_snap[23]<=_rf23;
    rf_snap[24]<=_rf24; rf_snap[25]<=_rf25; rf_snap[26]<=_rf26; rf_snap[27]<=_rf27;
    rf_snap[28]<=_rf28; rf_snap[29]<=_rf29; rf_snap[30]<=_rf30; rf_snap[31]<=_rf31;
end

// ---------------------------------------------------------------------------
// Instruction Memory — COMBINATIONAL response (matches IFU design intent)
//
// IFU.v: assign imem_addr = PC (combinational)
//         if (!stall && imem_ready) PC <= next_pc
//         Instruction_Code = imem_ready ? imem_rdata : instr_hold
//
// ICache miss simulation:
//   imiss_cnt: registered counter, increments each cycle during miss
//   imem_ready = imem_valid && !(miss_inject && imiss_cnt < 2)
//   → Combinational ready, miss = hold for 2 extra cycles
// ---------------------------------------------------------------------------
reg [31:0] imem [0:1023];
reg        imem_miss_inject;
reg [2:0]  imiss_cnt;

// Registered miss counter
always @(posedge clk) begin
    if (rst) begin
        imiss_cnt <= 3'd0;
    end else if (imem_valid) begin
        if (imem_miss_inject && imiss_cnt < 3'd2)
            imiss_cnt <= imiss_cnt + 3'd1;
        else
            imiss_cnt <= 3'd0;
    end
end

// COMBINATIONAL imem response
always @(*) begin
    if (!imem_valid || rst) begin
        imem_rdata = 32'h0000_0013;
        imem_ready = 1'b0;
    end else if (imem_miss_inject && imiss_cnt < 3'd2) begin
        imem_rdata = 32'h0000_0013;
        imem_ready = 1'b0;
    end else begin
        imem_rdata = imem[imem_addr[11:2]];
        imem_ready = 1'b1;
    end
end

// ---------------------------------------------------------------------------
// Data Memory — COMBINATIONAL response (matches LSU design)
//
// LSU: dcache_req → expects dcache_ready same or next cycle
// DCache miss: hold dcache_ready=0 for 1 extra cycle
// ---------------------------------------------------------------------------
reg [31:0] dmem [0:511];
reg        dcache_miss_inject;
reg [1:0]  dmiss_cnt;

// Registered miss counter
always @(posedge clk) begin
    if (rst) begin
        dmiss_cnt <= 2'd0;
    end else if (dcache_req) begin
        if (dcache_miss_inject && dmiss_cnt < 2'd1)
            dmiss_cnt <= dmiss_cnt + 2'd1;
        else
            dmiss_cnt <= 2'd0;
    end
end

// COMBINATIONAL dcache response
always @(*) begin
    if (!dcache_req || rst) begin
        dcache_rdata = 32'h0;
        dcache_ready = 1'b0;
    end else if (dcache_miss_inject && dmiss_cnt < 2'd1) begin
        dcache_rdata = 32'h0;
        dcache_ready = 1'b0;
    end else begin
        dcache_ready = 1'b1;
        if (dcache_we)
            dcache_rdata = 32'h0;
        else
            dcache_rdata = dmem[(dcache_addr - 32'h1000_0000) >> 2];
    end
end

// Registered write to dmem (write happens at posedge when dcache_ready)
always @(posedge clk) begin
    if (!rst && dcache_req && dcache_we && dcache_ready) begin
        if (dcache_wstrb[0]) dmem[(dcache_addr-32'h1000_0000)>>2][ 7: 0] <= dcache_wdata[ 7: 0];
        if (dcache_wstrb[1]) dmem[(dcache_addr-32'h1000_0000)>>2][15: 8] <= dcache_wdata[15: 8];
        if (dcache_wstrb[2]) dmem[(dcache_addr-32'h1000_0000)>>2][23:16] <= dcache_wdata[23:16];
        if (dcache_wstrb[3]) dmem[(dcache_addr-32'h1000_0000)>>2][31:24] <= dcache_wdata[31:24];
    end
end

// ---------------------------------------------------------------------------
// Instruction encode functions
// ---------------------------------------------------------------------------
function [31:0] enc_r;
    input [6:0] f7; input [4:0] rs2,rs1; input [2:0] f3; input [4:0] rd; input [6:0] op;
    enc_r = {f7,rs2,rs1,f3,rd,op};
endfunction
function [31:0] enc_i;
    input [11:0] imm; input [4:0] rs1; input [2:0] f3; input [4:0] rd; input [6:0] op;
    enc_i = {imm,rs1,f3,rd,op};
endfunction
function [31:0] enc_s;
    input [11:0] imm; input [4:0] rs2,rs1; input [2:0] f3;
    enc_s = {imm[11:5],rs2,rs1,f3,imm[4:0],7'b0100011};
endfunction
// B-type: {imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],7'b1100011}
function [31:0] enc_b;
    input [12:0] imm; input [4:0] rs2,rs1; input [2:0] f3;
    enc_b = {imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],7'b1100011};
endfunction
function [31:0] enc_u;
    input [19:0] imm; input [4:0] rd; input [6:0] op;
    enc_u = {imm,rd,op};
endfunction
// J-type: {imm[20],imm[10:1],imm[11],imm[19:12],rd,7'b1101111}
function [31:0] enc_j;
    input [20:0] imm; input [4:0] rd;
    enc_j = {imm[20],imm[10:1],imm[11],imm[19:12],rd,7'b1101111};
endfunction

// ---------------------------------------------------------------------------
// Opcode / funct3 constants
// ---------------------------------------------------------------------------
localparam OP_LUI=7'b0110111, OP_AUIPC=7'b0010111, OP_JALR=7'b1100111;
localparam OP_LOAD=7'b0000011, OP_IMMED=7'b0010011, OP_RTYPE=7'b0110011;
localparam F3_ADD=3'b000,F3_SLL=3'b001,F3_SLT=3'b010,F3_SLTU=3'b011;
localparam F3_XOR=3'b100,F3_SRL=3'b101,F3_OR=3'b110, F3_AND=3'b111;
localparam F3_BEQ=3'b000,F3_BNE=3'b001,F3_BLT=3'b100,F3_BGE=3'b101;
localparam F3_LB=3'b000,F3_LH=3'b001,F3_LW=3'b010,F3_LBU=3'b100,F3_LHU=3'b101;
localparam F3_SB=3'b000,F3_SW=3'b010;
localparam F7_N=7'b0000000, F7_A=7'b0100000;

// ---------------------------------------------------------------------------
// imem helpers
// ---------------------------------------------------------------------------
integer wp, ii;
task wi; input [31:0] ins; begin imem[wp]=ins; wp=wp+1; end endtask
task wn; begin imem[wp]=32'h0000_0013; wp=wp+1; end endtask
task wns; input integer n; begin for(ii=0;ii<n;ii=ii+1) begin imem[wp]=32'h0000_0013; wp=wp+1; end end endtask
task clr_imem; begin for(ii=0;ii<1024;ii=ii+1) imem[ii]=32'h0000_0013; end endtask
task clr_dmem; begin for(ii=0;ii< 512;ii=ii+1) dmem[ii]=32'h0;         end endtask

// ---------------------------------------------------------------------------
// Reset task
// ---------------------------------------------------------------------------
task do_reset;
    begin
        rst<=1'b1; external_irq<=1'b0; timer_irq<=1'b0; sw_irq<=1'b0;
        imem_miss_inject<=1'b0; dcache_miss_inject<=1'b0;
        repeat(4) @(posedge clk);
        rst<=1'b0;
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Test infrastructure
// ---------------------------------------------------------------------------
integer pass_cnt, fail_cnt, tc;

task chk_reg;
    input [4:0]   rn;
    input [31:0]  exp;
    input [127:0] nm;
    reg [31:0] got;
    begin
        @(negedge clk);
        got = rf_snap[rn];
        if (got===exp) begin
            $display("  PASS [TC%02d] %0s  x%0d = 0x%08h", tc, nm, rn, exp);
            pass_cnt=pass_cnt+1;
        end else begin
            $display("  FAIL [TC%02d] %0s  x%0d = 0x%08h  (expected 0x%08h)",
                     tc, nm, rn, got, exp);
            fail_cnt=fail_cnt+1;
        end
    end
endtask

task chk_dmem;
    input [31:0]  addr, exp;
    input [127:0] nm;
    reg [31:0] got;
    begin
        @(negedge clk);
        got = dmem[(addr-32'h1000_0000)>>2];
        if (got===exp) begin
            $display("  PASS [TC%02d] %0s  mem[0x%08h] = 0x%08h", tc, nm, addr, exp);
            pass_cnt=pass_cnt+1;
        end else begin
            $display("  FAIL [TC%02d] %0s  mem[0x%08h] = 0x%08h  (expected 0x%08h)",
                     tc, nm, addr, got, exp);
            fail_cnt=fail_cnt+1;
        end
    end
endtask

// ===========================================================================
// MAIN
// ===========================================================================
initial begin
    $dumpfile("tb_riscv_cpu_core_v2.vcd");
    $dumpvars(0, tb_riscv_cpu_core_v2);

    pass_cnt=0; fail_cnt=0;
    rst=1'b1; external_irq=1'b0; timer_irq=1'b0; sw_irq=1'b0;
    imem_miss_inject=1'b0; dcache_miss_inject=1'b0;
    clr_imem(); clr_dmem();
    repeat(2) @(posedge clk);

    // =======================================================================
    // TC-01  R-Type Arithmetic
    // x1=10, x2=3
    // ADD x3=13, SUB x4=7, AND x5=2, OR x6=11, XOR x7=9
    // SLL x8=10<<3=80, SRL x9=80>>3=10, SRA x10=7>>3=0
    // SLT x11=1 (2<10), SLTU x12=1
    // =======================================================================
    tc=1; $display("\n=== TC-01: R-Type ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd10,  5'd0,F3_ADD,5'd1, OP_IMMED));
    wi(enc_i(12'd3,   5'd0,F3_ADD,5'd2, OP_IMMED));
    wi(enc_r(F7_N,5'd2,5'd1,F3_ADD,  5'd3, OP_RTYPE));
    wi(enc_r(F7_A,5'd2,5'd1,F3_ADD,  5'd4, OP_RTYPE));
    wi(enc_r(F7_N,5'd2,5'd1,F3_AND,  5'd5, OP_RTYPE));
    wi(enc_r(F7_N,5'd2,5'd1,F3_OR,   5'd6, OP_RTYPE));
    wi(enc_r(F7_N,5'd2,5'd1,F3_XOR,  5'd7, OP_RTYPE));
    wi(enc_r(F7_N,5'd2,5'd1,F3_SLL,  5'd8, OP_RTYPE));
    wi(enc_r(F7_N,5'd2,5'd8,F3_SRL,  5'd9, OP_RTYPE));
    wi(enc_r(F7_A,5'd2,5'd4,F3_SRL,  5'd10,OP_RTYPE));
    wi(enc_r(F7_N,5'd1,5'd2,F3_SLT,  5'd11,OP_RTYPE));
    wi(enc_r(F7_N,5'd1,5'd2,F3_SLTU, 5'd12,OP_RTYPE));
    wns(10);
    do_reset();
    repeat(30) @(posedge clk);
    chk_reg(5'd3, 32'd13,"ADD");   chk_reg(5'd4, 32'd7, "SUB");
    chk_reg(5'd5, 32'd2, "AND");   chk_reg(5'd6, 32'd11,"OR");
    chk_reg(5'd7, 32'd9, "XOR");   chk_reg(5'd8, 32'd80,"SLL");
    chk_reg(5'd9, 32'd10,"SRL");   chk_reg(5'd10,32'd0, "SRA");
    chk_reg(5'd11,32'd1, "SLT");   chk_reg(5'd12,32'd1, "SLTU");

    // =======================================================================
    // TC-02  I-Type ALU
    // =======================================================================
    tc=2; $display("\n=== TC-02: I-Type ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd15,             5'd0,F3_ADD,5'd1,OP_IMMED));
    wi(enc_i(12'd6,              5'd1,F3_AND,5'd2,OP_IMMED));
    wi(enc_i(12'd8,              5'd1,F3_OR, 5'd3,OP_IMMED));
    wi(enc_i(12'd9,              5'd1,F3_XOR,5'd4,OP_IMMED));
    wi(enc_i(12'd20,             5'd1,F3_SLT,5'd5,OP_IMMED));
    wi(enc_i(12'd10,             5'd1,F3_SLT,5'd6,OP_IMMED));
    wi(enc_i({7'b0000000,5'd2},  5'd1,F3_SLL,5'd7,OP_IMMED));
    wi(enc_i({7'b0000000,5'd2},  5'd1,F3_SRL,5'd8,OP_IMMED));
    wi(enc_i({7'b0100000,5'd2},  5'd1,F3_SRL,5'd9,OP_IMMED));
    wns(10);
    do_reset();
    repeat(25) @(posedge clk);
    chk_reg(5'd2,32'd6, "ANDI"); chk_reg(5'd3,32'd15,"ORI");
    chk_reg(5'd4,32'd6, "XORI"); chk_reg(5'd5,32'd1, "SLTI=1");
    chk_reg(5'd6,32'd0, "SLTI=0");
    chk_reg(5'd7,32'd60,"SLLI"); chk_reg(5'd8,32'd3, "SRLI");
    chk_reg(5'd9,32'd3, "SRAI");

    // =======================================================================
    // TC-03  Load / Store
    // dmem[0]=0xDEAD_BEEF @ 0x1000_0000
    // =======================================================================
    tc=3; $display("\n=== TC-03: Load/Store ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0]=32'hDEAD_BEEF;
    wi(enc_u(20'h10000,5'd1,OP_LUI));                          // x1=0x1000_0000
    wi(enc_i(12'd0, 5'd1,F3_LW, 5'd2,OP_LOAD));               // LW  x2
    wi(enc_u(20'hABCD1,5'd3,OP_LUI));                          // x3=0xABCD_1000
    wi(enc_i(12'h234,5'd3,F3_ADD,5'd3,OP_IMMED));              // x3=0xABCD_1234
    wi(enc_s(12'd4,5'd3,5'd1,F3_SW));                          // SW x3,4(x1)
    wi(enc_i(12'd4, 5'd1,F3_LW, 5'd4,OP_LOAD));               // LW  x4
    wi(enc_i(12'd0, 5'd1,F3_LB, 5'd5,OP_LOAD));               // LB  x5
    wi(enc_i(12'd0, 5'd1,F3_LBU,5'd6,OP_LOAD));               // LBU x6
    wi(enc_i(12'd0, 5'd1,F3_LH, 5'd7,OP_LOAD));               // LH  x7
    wi(enc_i(12'd0, 5'd1,F3_LHU,5'd8,OP_LOAD));               // LHU x8
    wi(enc_i(12'h55,5'd0,F3_ADD,5'd9,OP_IMMED));               // x9=0x55
    wi(enc_s(12'd8,5'd9,5'd1,F3_SB));                          // SB x9,8(x1)
    wns(15);
    do_reset();
    repeat(60) @(posedge clk);
    chk_reg(5'd2,32'hDEAD_BEEF,"LW");
    chk_reg(5'd4,32'hABCD_1234,"SW+LW");
    chk_dmem(32'h1000_0004,32'hABCD_1234,"SW");
    chk_reg(5'd5,32'hFFFF_FFEF,"LB");
    chk_reg(5'd6,32'h0000_00EF,"LBU");
    chk_reg(5'd7,32'hFFFF_BEEF,"LH");
    chk_reg(5'd8,32'h0000_BEEF,"LHU");
    chk_dmem(32'h1000_0008,32'h0000_0055,"SB");

    // =======================================================================
    // TC-04  Branch
    // pc=0:  x1=5
    // pc=4:  x2=5
    // pc=8:  x3=10
    // pc=12: BEQ x1,x2,+12  → taken → pc=24
    // pc=16: SKIP  pc=20: SKIP
    // pc=24: x5=1
    // pc=28: BNE x1,x3,+8   → taken → pc=36
    // pc=32: SKIP
    // pc=36: x6=2
    // pc=40: BLT x1,x3,+8   → taken → pc=48
    // pc=44: SKIP
    // pc=48: x7=3
    // pc=52: BGE x3,x1,+8   → taken → pc=60
    // pc=56: SKIP
    // pc=60: x8=4
    // pc=64: BNE x1,x2,+12  → NOT taken
    // pc=68: x9=5
    // pc=72: x10=6
    // =======================================================================
    tc=4; $display("\n=== TC-04: Branch ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd5, 5'd0,F3_ADD,5'd1,OP_IMMED));   // pc=0
    wi(enc_i(12'd5, 5'd0,F3_ADD,5'd2,OP_IMMED));   // pc=4
    wi(enc_i(12'd10,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=8
    wi(enc_b(13'd12,5'd2,5'd1,F3_BEQ));            // pc=12 → 24
    wi(enc_i(12'd99,5'd0,F3_ADD,5'd5,OP_IMMED));   // pc=16 SKIP
    wi(enc_i(12'd99,5'd0,F3_ADD,5'd5,OP_IMMED));   // pc=20 SKIP
    wi(enc_i(12'd1, 5'd0,F3_ADD,5'd5,OP_IMMED));   // pc=24 x5=1
    wi(enc_b(13'd8, 5'd3,5'd1,F3_BNE));            // pc=28 → 36
    wi(enc_i(12'd99,5'd0,F3_ADD,5'd6,OP_IMMED));   // pc=32 SKIP
    wi(enc_i(12'd2, 5'd0,F3_ADD,5'd6,OP_IMMED));   // pc=36 x6=2
    wi(enc_b(13'd8, 5'd3,5'd1,F3_BLT));            // pc=40 → 48
    wi(enc_i(12'd99,5'd0,F3_ADD,5'd7,OP_IMMED));   // pc=44 SKIP
    wi(enc_i(12'd3, 5'd0,F3_ADD,5'd7,OP_IMMED));   // pc=48 x7=3
    wi(enc_b(13'd8, 5'd1,5'd3,F3_BGE));            // pc=52 → 60
    wi(enc_i(12'd99,5'd0,F3_ADD,5'd8,OP_IMMED));   // pc=56 SKIP
    wi(enc_i(12'd4, 5'd0,F3_ADD,5'd8,OP_IMMED));   // pc=60 x8=4
    wi(enc_b(13'd12,5'd2,5'd1,F3_BNE));            // pc=64 NOT taken
    wi(enc_i(12'd5, 5'd0,F3_ADD,5'd9, OP_IMMED));  // pc=68 x9=5
    wi(enc_i(12'd6, 5'd0,F3_ADD,5'd10,OP_IMMED));  // pc=72 x10=6
    wns(15);
    do_reset();
    repeat(60) @(posedge clk);
    chk_reg(5'd5, 32'd1,"BEQ-taken");  chk_reg(5'd6, 32'd2,"BNE-taken");
    chk_reg(5'd7, 32'd3,"BLT-taken");  chk_reg(5'd8, 32'd4,"BGE-taken");
    chk_reg(5'd9, 32'd5,"BNE-ntaken x9");
    chk_reg(5'd10,32'd6,"BNE-ntaken x10");

    // =======================================================================
    // TC-05  JAL / JALR
    // pc=0:  JAL x1,+16  → x1=4, jump to pc=16
    // pc=4,8,12: SKIP (flushed)
    // pc=16: x2=7
    // pc=20: NOP
    // pc=24: JALR x3,x0,64 → x3=28, jump to pc=64
    // pc=28: SKIP (flushed)
    // pc=64+: NOPs
    // =======================================================================
    tc=5; $display("\n=== TC-05: JAL/JALR ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_j(21'd16,5'd1));                                    // pc=0  JAL→16; x1=4
    wn();                                                      // pc=4  SKIP
    wn();                                                      // pc=8  SKIP
    wn();                                                      // pc=12 SKIP
    wi(enc_i(12'd7, 5'd0,F3_ADD,5'd2,OP_IMMED));              // pc=16 x2=7
    wn();                                                      // pc=20 gap
    wi(enc_i(12'd64,5'd0,F3_ADD,5'd3,OP_JALR));               // pc=24 JALR x3=28,→64
    wn();                                                      // pc=28 SKIP
    wns(8);  // pc=32..60
    wns(10); // pc=64..
    do_reset();
    repeat(35) @(posedge clk);
    chk_reg(5'd1,32'd4, "JAL x1=4");
    chk_reg(5'd2,32'd7, "JAL target x2=7");
    chk_reg(5'd3,32'd28,"JALR x3=28");

    // =======================================================================
    // TC-06  LUI / AUIPC
    // pc=0: LUI x1 = 0xABCDE_000
    // pc=4: AUIPC x2 = 4 + 0x1000 = 0x1004
    // =======================================================================
    tc=6; $display("\n=== TC-06: LUI/AUIPC ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_u(20'hABCDE,5'd1,OP_LUI));                         // pc=0 x1=0xABCDE_000
    wi(enc_u(20'h00001,5'd2,OP_AUIPC));                       // pc=4 x2=4+0x1000=0x1004
    wns(8);
    do_reset();
    repeat(15) @(posedge clk);
    chk_reg(5'd1,32'hABCDE_000,"LUI");
    chk_reg(5'd2,32'h0000_1004,"AUIPC");

    // =======================================================================
    // TC-07  Forwarding
    // =======================================================================
    tc=7; $display("\n=== TC-07: Forwarding ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd5,5'd0,F3_ADD,5'd1,OP_IMMED));
    wi(enc_i(12'd3,5'd1,F3_ADD,5'd2,OP_IMMED));
    wi(enc_i(12'd2,5'd2,F3_ADD,5'd3,OP_IMMED));
    wn();
    wi(enc_i(12'd1,5'd3,F3_ADD,5'd4,OP_IMMED));
    wi(enc_r(F7_N,5'd4,5'd4,F3_ADD,5'd5,OP_RTYPE));
    wns(10);
    do_reset();
    repeat(25) @(posedge clk);
    chk_reg(5'd1,32'd5, "FWD x1"); chk_reg(5'd2,32'd8, "FWD x2");
    chk_reg(5'd3,32'd10,"FWD x3"); chk_reg(5'd4,32'd11,"FWD x4");
    chk_reg(5'd5,32'd22,"FWD x5");

    // =======================================================================
    // TC-08  Load-Use Hazard
    // dmem[0]=0xCAFE_BABE
    // =======================================================================
    tc=8; $display("\n=== TC-08: Load-Use ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0]=32'hCAFE_BABE;
    wi(enc_u(20'h10000,5'd1,OP_LUI));
    wi(enc_i(12'd0,5'd1,F3_LW, 5'd2,OP_LOAD));
    wi(enc_i(12'd1,5'd2,F3_ADD,5'd3,OP_IMMED));
    wi(enc_i(12'd2,5'd2,F3_ADD,5'd4,OP_IMMED));
    wns(12);
    do_reset();
    repeat(35) @(posedge clk);
    chk_reg(5'd2,32'hCAFE_BABE,"LU LW");
    chk_reg(5'd3,32'hCAFE_BABF,"LU x3");
    chk_reg(5'd4,32'hCAFE_BAC0,"LU x4");

    // =======================================================================
    // TC-09  Branch Flush
    // pc=0: x1=1, pc=4: x2=1
    // pc=8: BEQ x1,x2,+24 → taken → pc=32
    // pc=12..28: ADDI x3,x0,42 (5 poison — all flushed)
    // pc=32: x3=99
    // =======================================================================
    tc=9; $display("\n=== TC-09: Branch Flush ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd1, 5'd0,F3_ADD,5'd1,OP_IMMED));   // pc=0
    wi(enc_i(12'd1, 5'd0,F3_ADD,5'd2,OP_IMMED));   // pc=4
    wi(enc_b(13'd24,5'd2,5'd1,F3_BEQ));            // pc=8  → 32
    wi(enc_i(12'd42,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=12 FLUSH
    wi(enc_i(12'd42,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=16 FLUSH
    wi(enc_i(12'd42,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=20 FLUSH
    wi(enc_i(12'd42,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=24 FLUSH
    wi(enc_i(12'd42,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=28 FLUSH
    wi(enc_i(12'd99,5'd0,F3_ADD,5'd3,OP_IMMED));   // pc=32 x3=99
    wns(15);
    do_reset();
    repeat(35) @(posedge clk);
    chk_reg(5'd3,32'd99,"Flush x3=99");

    // =======================================================================
    // TC-10  IRQ
    // =======================================================================
    tc=10; $display("\n=== TC-10: IRQ ===");
    clr_imem(); clr_dmem(); wp=0; wns(30);
    do_reset();
    repeat(5) @(posedge clk);
    external_irq=1'b1; repeat(3) @(posedge clk); external_irq=1'b0;
    repeat(5) @(posedge clk);
    $display("  PASS [TC10] external_irq no deadlock"); pass_cnt=pass_cnt+1;
    timer_irq=1'b1; repeat(3) @(posedge clk); timer_irq=1'b0;
    repeat(5) @(posedge clk);
    $display("  PASS [TC10] timer_irq no deadlock"); pass_cnt=pass_cnt+1;
    sw_irq=1'b1; repeat(3) @(posedge clk); sw_irq=1'b0;
    repeat(5) @(posedge clk);
    $display("  PASS [TC10] sw_irq no deadlock"); pass_cnt=pass_cnt+1;

    // =======================================================================
    // TC-11  ICache Miss (miss counter delays 2 cycles)
    // =======================================================================
    tc=11; $display("\n=== TC-11: ICache Miss ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd7,5'd0,F3_ADD,5'd1,OP_IMMED));               // x1=7
    wi(enc_i(12'd3,5'd1,F3_ADD,5'd2,OP_IMMED));               // x2=10
    wns(10);
    do_reset();
    imem_miss_inject=1'b1;
    repeat(50) @(posedge clk);
    imem_miss_inject=1'b0;
    repeat(10) @(posedge clk);
    chk_reg(5'd1,32'd7, "IC x1");
    chk_reg(5'd2,32'd10,"IC x2");

    // =======================================================================
    // TC-12  DCache Miss
    // dmem[2]=0x1234_5678 @ 0x1000_0008
    // =======================================================================
    tc=12; $display("\n=== TC-12: DCache Miss ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[2]=32'h1234_5678;
    wi(enc_u(20'h10000,5'd1,OP_LUI));
    wi(enc_i(12'd8,5'd1,F3_LW, 5'd2,OP_LOAD));
    wi(enc_i(12'd1,5'd2,F3_ADD,5'd3,OP_IMMED));
    wns(12);
    do_reset();
    dcache_miss_inject=1'b1;
    repeat(40) @(posedge clk);
    dcache_miss_inject=1'b0;
    repeat(10) @(posedge clk);
    chk_reg(5'd2,32'h1234_5678,"DC x2");
    chk_reg(5'd3,32'h1234_5679,"DC x3");

    // =======================================================================
    // TC-13  Long Chain + Store→Load
    // =======================================================================
    tc=13; $display("\n=== TC-13: Long Chain ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd1,5'd0,F3_ADD,5'd1,OP_IMMED));               // x1=1
    wi(enc_i(12'd1,5'd1,F3_ADD,5'd2,OP_IMMED));               // x2=2
    wi(enc_i(12'd1,5'd2,F3_ADD,5'd3,OP_IMMED));               // x3=3
    wi(enc_i(12'd1,5'd3,F3_ADD,5'd4,OP_IMMED));               // x4=4
    wi(enc_i(12'd1,5'd4,F3_ADD,5'd5,OP_IMMED));               // x5=5
    wi(enc_u(20'h10000,5'd6,OP_LUI));                         // x6=base
    wi(enc_s(12'd0,5'd5,5'd6,F3_SW));                         // SW x5
    wns(4);
    wi(enc_i(12'd0,5'd6,F3_LW,5'd7,OP_LOAD));                 // LW x7=5
    wns(4);
    wi(enc_r(F7_N,5'd7,5'd5,F3_ADD,5'd8,OP_RTYPE));           // x8=10
    wns(15);
    do_reset();
    repeat(55) @(posedge clk);
    chk_reg(5'd5,32'd5, "Chain x5");
    chk_reg(5'd7,32'd5, "Chain x7");
    chk_reg(5'd8,32'd10,"Chain x8");

    // =======================================================================
    // TC-14  Negative Immediate
    // =======================================================================
    tc=14; $display("\n=== TC-14: Negative Immediate ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd10,  5'd0,F3_ADD,5'd1,OP_IMMED));
    wi(enc_i(12'hFFD, 5'd1,F3_ADD,5'd2,OP_IMMED));
    wi(enc_i(12'hFF6, 5'd0,F3_ADD,5'd3,OP_IMMED));
    wi(enc_r(F7_N,5'd3,5'd1,F3_ADD,5'd4,OP_RTYPE));
    wns(10);
    do_reset();
    repeat(20) @(posedge clk);
    chk_reg(5'd2,32'd7,         "NEG x2=7");
    chk_reg(5'd3,32'hFFFF_FFF6, "NEG x3=-10");
    chk_reg(5'd4,32'd0,         "NEG x4=0");

    // =======================================================================
    // TC-15  Mid-Reset
    // =======================================================================
    tc=15; $display("\n=== TC-15: Mid-Reset ===");
    clr_imem(); clr_dmem(); wp=0; wns(30);
    do_reset();
    repeat(5) @(posedge clk);
    rst=1'b1; repeat(2) @(posedge clk); rst=1'b0;
    repeat(10) @(posedge clk);
    chk_reg(5'd0,32'd0,"x0=0 always");
    $display("  PASS [TC15] no deadlock after mid-reset"); pass_cnt=pass_cnt+1;

    // =======================================================================
    // SUMMARY
    // =======================================================================
    $display("\n============================================================");
    $display(" PASS=%0d  FAIL=%0d  TOTAL=%0d",pass_cnt,fail_cnt,pass_cnt+fail_cnt);
    if (fail_cnt==0) $display(" RESULT: *** ALL TESTS PASSED ***");
    else             $display(" RESULT: *** %0d FAILED ***",fail_cnt);
    $display("============================================================");
    $finish;
end

initial begin #200_000; $display("WATCHDOG timeout"); $finish; end

endmodule