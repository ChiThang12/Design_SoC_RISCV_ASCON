`timescale 1ns/1ps
`include "cpu/riscv_cpu_core_v1.v"

// ============================================================================
// tb_riscv_cpu_core_v2.v
// Testbench cho riscv_cpu_core_v2
// ============================================================================
// Fixes so với tb gốc:
//   - clear_imem() gọi đầu mỗi test: tránh instruction cũ leak sang test mới
//   - do_reset() chuẩn: rst=1 giữ 4 cycle, sau đó rst=0
//   - Mỗi test tự reset CPU → isolate hoàn toàn
//   - BEQ/BNE offset fix: +12 để skip đúng 2 instruction (imem[3] và imem[4])
//   - AUIPC expected value tính đúng theo PC của instruction
//   - Timeout tăng lên 50000 ns để đủ cho LSU latency
//   - 12 test cases bao phủ đầy đủ: R-type, I-type, shift, load, store,
//     branch (BEQ/BNE/BLT/BGE), JAL, JALR, LUI/AUIPC, load-use hazard,
//     forwarding chain
// ============================================================================

module tb_riscv_cpu_core_v2;

// ============================================================================
// Parameters
// ============================================================================
parameter CLK_PERIOD = 10;   // ns
parameter TIMEOUT    = 50000; // ns

// ============================================================================
// Signals
// ============================================================================
reg clk;
reg rst;

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

integer pass_count;
integer fail_count;

// ============================================================================
// DUT
// ============================================================================
riscv_cpu_core dut (
    .clk      (clk),
    .rst      (rst),
    .imem_addr(imem_addr),
    .imem_valid(imem_valid),
    .imem_rdata(imem_rdata),
    .imem_ready(imem_ready),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_wstrb(dmem_wstrb),
    .dmem_valid(dmem_valid),
    .dmem_we  (dmem_we),
    .dmem_rdata(dmem_rdata),
    .dmem_ready(dmem_ready)
);

// ============================================================================
// Instruction Memory
// ============================================================================
reg [31:0] imem [0:255];

always @(posedge clk) begin
    if (imem_valid && imem_ready)
        imem_rdata <= imem[imem_addr[9:2]];
end

// ============================================================================
// Data Memory
// ============================================================================
reg [31:0] dmem [0:255];

always @(posedge clk) begin
    if (dmem_valid && dmem_ready) begin
        if (dmem_we) begin
            case (dmem_wstrb)
                4'b0001: dmem[dmem_addr[9:2]][7:0]   <= dmem_wdata[7:0];
                4'b0010: dmem[dmem_addr[9:2]][15:8]  <= dmem_wdata[15:8];
                4'b0100: dmem[dmem_addr[9:2]][23:16] <= dmem_wdata[23:16];
                4'b1000: dmem[dmem_addr[9:2]][31:24] <= dmem_wdata[31:24];
                4'b0011: dmem[dmem_addr[9:2]][15:0]  <= dmem_wdata[15:0];
                4'b1100: dmem[dmem_addr[9:2]][31:16] <= dmem_wdata[31:16];
                4'b1111: dmem[dmem_addr[9:2]]        <= dmem_wdata;
            endcase
        end else begin
            dmem_rdata <= dmem[dmem_addr[9:2]];
        end
    end
end

// ============================================================================
// Clock
// ============================================================================
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// VCD dump
// ============================================================================
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_riscv_cpu_core_v2);
end

// ============================================================================
// Timeout watchdog
// ============================================================================
initial begin
    #TIMEOUT;
    $display("\n!!! TIMEOUT sau %0d ns !!!", TIMEOUT);
    print_summary();
    $finish;
end

// ============================================================================
// Utilities
// ============================================================================
integer _i;

// fill toàn bộ imem bằng NOP (ADDI x0,x0,0)
task clear_imem;
    begin
        for (_i = 0; _i < 256; _i = _i + 1)
            imem[_i] = 32'h00000013;
    end
endtask

// fill toàn bộ dmem bằng 0
task clear_dmem;
    begin
        for (_i = 0; _i < 256; _i = _i + 1)
            dmem[_i] = 32'h00000000;
    end
endtask

// reset CPU và chờ pipeline ổn định
task do_reset;
    begin
        rst = 1;
        #(CLK_PERIOD * 4);
        rst = 0;
 
    end
endtask

// ============================================================================
// Main
// ============================================================================
initial begin
    pass_count = 0;
    fail_count = 0;
    imem_ready = 1;
    dmem_ready = 1;
    imem_rdata = 32'h00000013;
    dmem_rdata = 32'h00000000;

    clear_imem();
    clear_dmem();

    $display("\n╔═══════════════════════════════════════════════════╗");
    $display("║   RISC-V CPU Core Testbench v2                   ║");
    $display("╚═══════════════════════════════════════════════════╝");

    do_reset();

    test_01_r_type();
    test_02_i_type();
    test_03_load();
    test_04_store();
    test_05_branch_beq();
    test_06_branch_bne();
    test_07_branch_blt_bge();
    test_08_jal();
    test_09_jalr();
    test_10_lui_auipc();
    test_11_load_use_hazard();
    test_12_forwarding_chain();

    #(CLK_PERIOD * 5);
    print_summary();
    $finish;
end

// ============================================================================
// TEST 01: R-Type
// x1=10, x2=20
// ADD  x3 = x1+x2 = 30
// SUB  x4 = x2-x1 = 10
// AND  x5 = x1&x2 = 0
// OR   x6 = x1|x2 = 30
// XOR  x7 = x1^x2 = 30
// SLT  x8 = (x1<x2) = 1
// SLTU x9 = (x1<x2) = 1
// x11=1, x12=3
// SLL x13 = x11<<x12 = 8
// SRL x14 = x1>>x12  = 1
// SRA x15 = x1>>>x12 = 1
// ============================================================================
task test_01_r_type;
    begin
        $display("\n┌─── TEST 01: R-Type ─────────────────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h00A00093; // ADDI x1, x0, 10
        imem[1]  = 32'h01400113; // ADDI x2, x0, 20
        imem[2]  = 32'h002081B3; // ADD  x3, x1, x2   → 30
        imem[3]  = 32'h40110233; // SUB  x4, x2, x1   → 10
        imem[4]  = 32'h0020F2B3; // AND  x5, x1, x2   → 0
        imem[5]  = 32'h0020E333; // OR   x6, x1, x2   → 30
        imem[6]  = 32'h0020C3B3; // XOR  x7, x1, x2   → 30
        imem[7]  = 32'h0020A433; // SLT  x8, x1, x2   → 1
        imem[8]  = 32'h0020B4B3; // SLTU x9, x1, x2   → 1
        imem[9]  = 32'h00100593; // ADDI x11, x0, 1
        imem[10] = 32'h00300613; // ADDI x12, x0, 3
        imem[11] = 32'h00C596B3; // SLL  x13, x11, x12 → 1<<3 = 8
        imem[12] = 32'h00C0D733; // SRL  x14, x1,  x12 → 10>>3 = 1
        imem[13] = 32'h40C0D7B3; // SRA  x15, x1,  x12 → 10>>>3 = 1
        imem[14] = 32'h0000006F; // JAL  x0, 0  (halt)

        #(CLK_PERIOD * 45);

        check_reg(3,  32'd30, "ADD  x3=x1+x2");
        check_reg(4,  32'd10, "SUB  x4=x2-x1");
        check_reg(5,  32'd0,  "AND  x5=x1&x2");
        check_reg(6,  32'd30, "OR   x6=x1|x2");
        check_reg(7,  32'd30, "XOR  x7=x1^x2");
        check_reg(8,  32'd1,  "SLT  x8=(x1<x2)");
        check_reg(9,  32'd1,  "SLTU x9=(x1<x2)");
        check_reg(13, 32'd8,  "SLL  x13=1<<3");
        check_reg(14, 32'd1,  "SRL  x14=10>>3");
        check_reg(15, 32'd1,  "SRA  x15=10>>>3");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 02: I-Type ALU
// x1=10
// ADDI x2=x1+5=15  (RAW forwarding test)
// ANDI x3=x1&15=10
// ORI  x4=x1|30=30
// XORI x5=x1^15=5
// SLTI x6=(x1<15)=1
// SLTIU x7=(x1<15)=1
// SLLI x8=x1<<2=40
// SRLI x9=x1>>1=5
// SRAI x10=x1>>>1=5
// ============================================================================
task test_02_i_type;
    begin
        $display("\n┌─── TEST 02: I-Type ALU ─────────────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h00A00093; // ADDI x1, x0, 10
        imem[1]  = 32'h00508113; // ADDI x2, x1, 5    → 15  (RAW hazard)
        imem[2]  = 32'h00F0F193; // ANDI x3, x1, 15   → 10
        imem[3]  = 32'h01E0E213; // ORI  x4, x1, 30   → 30
        imem[4]  = 32'h00F0C293; // XORI x5, x1, 15   → 5
        imem[5]  = 32'h00F0A313; // SLTI x6, x1, 15   → 1
        imem[6]  = 32'h00F0B393; // SLTIU x7, x1, 15  → 1
        imem[7]  = 32'h00209413; // SLLI x8, x1, 2    → 40
        imem[8]  = 32'h0010D493; // SRLI x9, x1, 1    → 5
        imem[9]  = 32'h4010D513; // SRAI x10, x1, 1   → 5
        imem[10] = 32'h0000006F; // halt

        #(CLK_PERIOD * 35);

        check_reg(2,  32'd15, "ADDI x2=x1+5  (forwarding)");
        check_reg(3,  32'd10, "ANDI x3=x1&15");
        check_reg(4,  32'd30, "ORI  x4=x1|30");
        check_reg(5,  32'd5,  "XORI x5=x1^15");
        check_reg(6,  32'd1,  "SLTI x6=(x1<15)");
        check_reg(7,  32'd1,  "SLTIU x7=(x1<15)");
        check_reg(8,  32'd40, "SLLI x8=x1<<2");
        check_reg(9,  32'd5,  "SRLI x9=x1>>1");
        check_reg(10, 32'd5,  "SRAI x10=x1>>>1");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 03: Load
// dmem[0]=0xDEADBEEF, dmem[1]=0x12345678
// x1=base addr=0
// LW  x2,0(x1) → 0xDEADBEEF
// LH  x3,4(x1) → sign_ext(0x5678) = 0x00005678
// LB  x4,4(x1) → sign_ext(0x78)   = 0x00000078
// LHU x5,4(x1) → zero_ext(0x5678) = 0x00005678
// LBU x6,4(x1) → zero_ext(0x78)   = 0x00000078
// ============================================================================
task test_03_load;
    begin
        $display("\n┌─── TEST 03: Load ───────────────────────────────────┐");
        clear_imem();
        do_reset();

        dmem[0] = 32'hDEADBEEF;
        dmem[1] = 32'h12345678;

        imem[0]  = 32'h00000093; // ADDI x1, x0, 0
        imem[1]  = 32'h0000A103; // LW   x2, 0(x1) → 0xDEADBEEF
        imem[2]  = 32'h00409183; // LH   x3, 4(x1) → 0x00005678
        imem[3]  = 32'h00408203; // LB   x4, 4(x1) → 0x00000078
        imem[4]  = 32'h0040D283; // LHU  x5, 4(x1) → 0x00005678
        imem[5]  = 32'h0040C303; // LBU  x6, 4(x1) → 0x00000078
        imem[6]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 50);

        check_reg(2, 32'hDEADBEEF, "LW   x2=mem[0]");
        check_reg(3, 32'h00005678, "LH   x3=sign(mem[4][15:0])");
        check_reg(4, 32'h00000078, "LB   x4=sign(mem[4][7:0])");
        check_reg(5, 32'h00005678, "LHU  x5=zero(mem[4][15:0])");
        check_reg(6, 32'h00000078, "LBU  x6=zero(mem[4][7:0])");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 04: Store
// x1=0x123, x2=addr=0
// SW x1,0(x2) → dmem[0] = 0x00000123
// ============================================================================
task test_04_store;
    begin
        $display("\n┌─── TEST 04: Store ──────────────────────────────────┐");
        clear_imem();
        clear_dmem();
        do_reset();

        imem[0]  = 32'h12300093; // ADDI x1, x0, 0x123
        imem[1]  = 32'h00000113; // ADDI x2, x0, 0
        imem[2]  = 32'h00112023; // SW   x1, 0(x2) → dmem[0]=0x123
        imem[3]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 40);

        check_mem(0, 32'h00000123, "SW dmem[0]=0x123");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 05: Branch BEQ taken
// imem[0] PC=0x00: ADDI x1,x0,10
// imem[1] PC=0x04: ADDI x2,x0,10
// imem[2] PC=0x08: BEQ x1,x2,+12  → target=0x08+12=0x14=imem[5]
// imem[3] PC=0x0C: ADDI x3,x0,1  ← SKIP
// imem[4] PC=0x10: ADDI x4,x0,2  ← SKIP
// imem[5] PC=0x14: ADDI x5,x0,5  ← EXECUTE
// ============================================================================
task test_05_branch_beq;
    begin
        $display("\n┌─── TEST 05: Branch BEQ taken ───────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h00A00093; // ADDI x1, x0, 10
        imem[1]  = 32'h00A00113; // ADDI x2, x0, 10
        imem[2]  = 32'h00208663; // BEQ  x1, x2, +12  → 0x14
        imem[3]  = 32'h00100193; // ADDI x3, x0, 1   ← SKIP
        imem[4]  = 32'h00200213; // ADDI x4, x0, 2   ← SKIP
        imem[5]  = 32'h00500293; // ADDI x5, x0, 5   ← EXECUTE
        imem[6]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 35);

        check_reg(3, 32'd0, "BEQ taken: x3 skipped");
        check_reg(4, 32'd0, "BEQ taken: x4 skipped");
        check_reg(5, 32'd5, "BEQ taken: x5 executed");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 06: Branch BNE taken
// x1=5, x2=10, BNE x1,x2,+12 → taken (5≠10)
// layout same as TEST 05
// ============================================================================
task test_06_branch_bne;
    begin
        $display("\n┌─── TEST 06: Branch BNE taken ───────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h00500093; // ADDI x1, x0, 5
        imem[1]  = 32'h00A00113; // ADDI x2, x0, 10
        imem[2]  = 32'h00209663; // BNE  x1, x2, +12  → 0x14
        imem[3]  = 32'h00100193; // ADDI x3, x0, 1   ← SKIP
        imem[4]  = 32'h00200213; // ADDI x4, x0, 2   ← SKIP
        imem[5]  = 32'h00500293; // ADDI x5, x0, 5   ← EXECUTE
        imem[6]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 35);

        check_reg(3, 32'd0, "BNE taken: x3 skipped");
        check_reg(4, 32'd0, "BNE taken: x4 skipped");
        check_reg(5, 32'd5, "BNE taken: x5 executed");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 07: BLT taken, BGE not taken
// x1=5, x2=10
// BLT x1,x2,+12  → taken   (5<10)
// BGE x1,x2,+12  → not taken (5<10, not >=)
// ============================================================================
task test_07_branch_blt_bge;
    begin
        $display("\n┌─── TEST 07: Branch BLT/BGE ─────────────────────────┐");
        clear_imem();
        do_reset();

        // --- BLT taken: skip x3, skip x4, run x5 ---
        imem[0]  = 32'h00500093; // ADDI x1, x0, 5
        imem[1]  = 32'h00A00113; // ADDI x2, x0, 10
        imem[2]  = 32'h0020C663; // BLT  x1, x2, +12  → 0x14
        imem[3]  = 32'h00100193; // ADDI x3, x0, 1   ← SKIP
        imem[4]  = 32'h00200213; // ADDI x4, x0, 2   ← SKIP
        imem[5]  = 32'h00500293; // ADDI x5, x0, 5   ← EXECUTE

        // --- BGE not taken: x1=5 < x2=10 nên BGE không taken ---
        // imem[6] PC=0x18: BGE x1,x2,+12 → not taken → x6,x7 đều chạy
        imem[6]  = 32'h0020D663; // BGE  x1, x2, +12  → NOT taken
        imem[7]  = 32'h00100313; // ADDI x6, x0, 1   ← EXECUTE (not skipped)
        imem[8]  = 32'h00200393; // ADDI x7, x0, 2   ← EXECUTE (not skipped)
        imem[9]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 45);

        check_reg(3, 32'd0, "BLT taken: x3 skipped");
        check_reg(4, 32'd0, "BLT taken: x4 skipped");
        check_reg(5, 32'd5, "BLT taken: x5 executed");
        check_reg(6, 32'd1, "BGE not taken: x6 executed");
        check_reg(7, 32'd2, "BGE not taken: x7 executed");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 08: JAL
// imem[0] PC=0x00: JAL x1, +8  → jump to 0x08, x1=0x04
// imem[1] PC=0x04: ADDI x2,x0,1 ← SKIP
// imem[2] PC=0x08: ADDI x3,x0,10 ← EXECUTE
// ============================================================================
task test_08_jal;
    begin
        $display("\n┌─── TEST 08: JAL ────────────────────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h008000EF; // JAL  x1, +8
        imem[1]  = 32'h00100113; // ADDI x2, x0, 1   ← SKIP
        imem[2]  = 32'h00A00193; // ADDI x3, x0, 10  ← EXECUTE
        imem[3]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 30);

        check_reg(1, 32'h00000004, "JAL: x1=return_addr=0x04");
        check_reg(2, 32'd0,        "JAL: x2 skipped");
        check_reg(3, 32'd10,       "JAL: x3 executed");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 09: JALR
// imem[0] PC=0x00: ADDI x1,x0,8 → x1=8
// imem[1] PC=0x04: JALR x2,x1,0 → jump to x1+0=0x08, x2=0x08
// imem[2] PC=0x08: ADDI x3,x0,10 ← EXECUTE
// ============================================================================
task test_09_jalr;
    begin
        $display("\n┌─── TEST 09: JALR ───────────────────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h00800093; // ADDI x1, x0, 8
        imem[1]  = 32'h00008167; // JALR x2, x1, 0  → jump to 0x08, x2=0x08
        imem[2]  = 32'h00A00193; // ADDI x3, x0, 10 ← EXECUTE
        imem[3]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 30);

        check_reg(2, 32'h00000008, "JALR: x2=return_addr=0x08");
        check_reg(3, 32'd10,       "JALR: x3 executed");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 10: LUI + ADDI, AUIPC
// LUI x1,0x12345   → x1 = 0x12345000
// ADDI x1,x1,0x678 → x1 = 0x12345678
// AUIPC x2,1  PC=0x08 → x2 = 0x08 + 0x1000 = 0x00001008
// ============================================================================
task test_10_lui_auipc;
    begin
        $display("\n┌─── TEST 10: LUI + AUIPC ────────────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h123450B7; // LUI  x1, 0x12345   → 0x12345000
        imem[1]  = 32'h67808093; // ADDI x1, x1, 0x678 → 0x12345678
        imem[2]  = 32'h00001117; // AUIPC x2, 1  PC=0x08 → 0x00001008
        imem[3]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 28);

        check_reg(1, 32'h12345678, "LUI+ADDI: x1=0x12345678");
        check_reg(2, 32'h00001008, "AUIPC:    x2=0x08+0x1000");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 11: Load-Use Hazard
// dmem[0]=42
// LW x2,0(x1)    → x2=42
// ADDI x3,x2,2   → x3=44  (phụ thuộc trực tiếp LW → phải stall)
// ADDI x4,x3,3   → x4=47  (forward từ EX)
// ============================================================================
task test_11_load_use_hazard;
    begin
        $display("\n┌─── TEST 11: Load-Use Hazard ────────────────────────┐");
        clear_imem();
        clear_dmem();
        do_reset();

        dmem[0] = 32'h0000002A; // 42

        imem[0]  = 32'h00000093; // ADDI x1, x0, 0
        imem[1]  = 32'h0000A103; // LW   x2, 0(x1)  → x2=42
        imem[2]  = 32'h00210193; // ADDI x3, x2, 2  → x3=44 (load-use!)
        imem[3]  = 32'h00318213; // ADDI x4, x3, 3  → x4=47 (forward)
        imem[4]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 55);

        check_reg(2, 32'd42, "LW:            x2=42");
        check_reg(3, 32'd44, "ADDI x3=x2+2=44  (load-use stall)");
        check_reg(4, 32'd47, "ADDI x4=x3+3=47  (forwarding)");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// TEST 12: Forwarding Chain
// x1=5, x2=x1+3=8, x3=x2+x1=13, x4=x3-x2=5, x5=x3+x4=18
// ============================================================================
task test_12_forwarding_chain;
    begin
        $display("\n┌─── TEST 12: Forwarding Chain ───────────────────────┐");
        clear_imem();
        do_reset();

        imem[0]  = 32'h00500093; // ADDI x1, x0, 5     → x1=5
        imem[1]  = 32'h00308113; // ADDI x2, x1, 3     → x2=8   (EX→EX fwd)
        imem[2]  = 32'h001101B3; // ADD  x3, x2, x1    → x3=13  (EX→EX + WB→EX)
        imem[3]  = 32'h40218233; // SUB  x4, x3, x2    → x4=5
        imem[4]  = 32'h004182B3; // ADD  x5, x3, x4    → x5=18
        imem[5]  = 32'h0000006F; // halt

        #(CLK_PERIOD * 35);

        check_reg(1, 32'd5,  "ADDI x1=5");
        check_reg(2, 32'd8,  "ADDI x2=x1+3=8  (fwd EX→EX)");
        check_reg(3, 32'd13, "ADD  x3=x2+x1=13");
        check_reg(4, 32'd5,  "SUB  x4=x3-x2=5");
        check_reg(5, 32'd18, "ADD  x5=x3+x4=18");
        $display("└─────────────────────────────────────────────────────┘");
    end
endtask

// ============================================================================
// Helpers
// ============================================================================
task check_reg;
    input [4:0]   rn;
    input [31:0]  expected;
    input [511:0] name;
    reg   [31:0]  actual;
    begin
        actual = dut.register_file.registers[rn];
        if (actual === expected) begin
            $display("  \u2713 PASS  %-40s  x%02d = 0x%08h", name, rn, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  \u2717 FAIL  %-40s  x%02d = 0x%08h  (expected 0x%08h)",
                     name, rn, actual, expected);
            fail_count = fail_count + 1;
        end
    end
endtask

task check_mem;
    input [31:0]  word_idx;
    input [31:0]  expected;
    input [511:0] name;
    reg   [31:0]  actual;
    begin
        actual = dmem[word_idx];
        if (actual === expected) begin
            $display("  \u2713 PASS  %-40s  mem[%0d] = 0x%08h", name, word_idx, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  \u2717 FAIL  %-40s  mem[%0d] = 0x%08h  (expected 0x%08h)",
                     name, word_idx, actual, expected);
            fail_count = fail_count + 1;
        end
    end
endtask

task print_summary;
    begin
        $display("\n╔═══════════════════════════════════════════════════╗");
        $display("║                  Test Summary                     ║");
        $display("╠═══════════════════════════════════════════════════╣");
        $display("║  Total : %-4d    PASS : %-4d    FAIL : %-4d      ║",
                 pass_count + fail_count, pass_count, fail_count);
        if (fail_count == 0)
            $display("║              ALL TESTS PASSED                     ║");
        else
            $display("║              %0d TEST(S) FAILED                     ║", fail_count);
        $display("╚═══════════════════════════════════════════════════╝");
    end
endtask

endmodule