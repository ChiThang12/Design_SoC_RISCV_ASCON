`timescale 1ns/1ps
// ============================================================================
// tb_layer1_pipeline.v — Layer 1 Debug: Pipeline Hazard Focused Tests
//
// Theo plan_debug.md Layer 1:
//   TC-L1A: Load-use hazard (lw → add immediate use)
//   TC-L1B: Load-use hazard với STORE (lw → sw) — CRT0 _copy_data pattern
//   TC-L1C: CRT0 multi-iteration (4 lần lw→sw liên tiếp)
//   TC-L1D: CRT0 loop (lw→sw trong vòng lặp có JAL)
//   TC-L1E: MUL hazard (mul → add immediate use)
//
// Pass criteria: in "[L1-PASS]" nếu tất cả pass
// ============================================================================
`include "cpu/riscv_cpu_core_v2.v"

module tb_layer1_pipeline;

// ── Clock / Reset ──────────────────────────────────────────────────────────
reg clk, rst;
initial clk = 0;
always #5 clk = ~clk;

// ── DUT I/O ─────────────────────────────────────────────────────────────────
wire [31:0] imem_addr;
wire        imem_valid;
reg  [31:0] imem_rdata;
reg         imem_ready;

wire [31:0] dcache_addr;
wire [31:0] dcache_wdata;
wire [3:0]  dcache_wstrb;
wire        dcache_req;
wire        dcache_we;
wire [1:0]  dcache_fence_type;
reg  [31:0] dcache_rdata;
reg         dcache_ready;

reg  external_irq, timer_irq, sw_irq;

// ── DUT ─────────────────────────────────────────────────────────────────────
riscv_cpu_core dut (
    .clk              (clk),
    .rst              (rst),
    .imem_addr        (imem_addr),
    .imem_valid       (imem_valid),
    .imem_rdata       (imem_rdata),
    .imem_ready       (imem_ready),
    .dcache_addr      (dcache_addr),
    .dcache_wdata     (dcache_wdata),
    .dcache_wstrb     (dcache_wstrb),
    .dcache_req       (dcache_req),
    .dcache_we        (dcache_we),
    .dcache_rdata     (dcache_rdata),
    .dcache_ready     (dcache_ready),
    .dcache_fence_type(dcache_fence_type),
    .external_irq     (external_irq),
    .timer_irq        (timer_irq),
    .sw_irq           (sw_irq),
    .debug_haltreq    (1'b0),
    .debug_resumereq  (1'b0),
    .debug_halted     (),
    .debug_running    (),
    .cpu_wfi_o        (),
    .perf_stall_o     (),
    .perf_instr_ret_o ()
);

// ── Register file probe ─────────────────────────────────────────────────────
wire [31:0] _rf [0:31];
genvar gi;
generate
    for (gi = 0; gi < 32; gi = gi + 1) begin : rf_probe
        assign _rf[gi] = dut.register_file.registers[gi];
    end
endgenerate

reg [31:0] rf_snap [0:31];
integer si;
always @(negedge clk) begin
    for (si = 0; si < 32; si = si + 1)
        rf_snap[si] <= _rf[si];
end

// ── Instruction Memory — COMBINATIONAL (matches IFU design) ─────────────────
reg [31:0] imem [0:1023];
reg [1:0]  imiss_cnt;
reg        imem_miss_en;

always @(posedge clk) begin
    if (rst)            imiss_cnt <= 2'd0;
    else if (imem_valid) begin
        if (imem_miss_en && imiss_cnt < 2'd2) imiss_cnt <= imiss_cnt + 2'd1;
        else                                   imiss_cnt <= 2'd0;
    end
end

always @(*) begin
    if (!imem_valid || rst) begin
        imem_rdata = 32'h0000_0013; imem_ready = 1'b0;
    end else if (imem_miss_en && imiss_cnt < 2'd2) begin
        imem_rdata = 32'h0000_0013; imem_ready = 1'b0;
    end else begin
        imem_rdata = imem[imem_addr[11:2]];
        imem_ready = 1'b1;
    end
end

// ── Data Memory — COMBINATIONAL ──────────────────────────────────────────────
reg [31:0] dmem [0:511];
reg [1:0]  dmiss_cnt;
reg        dcache_miss_en;

always @(posedge clk) begin
    if (rst)           dmiss_cnt <= 2'd0;
    else if (dcache_req) begin
        if (dcache_miss_en && dmiss_cnt < 2'd1) dmiss_cnt <= dmiss_cnt + 2'd1;
        else                                     dmiss_cnt <= 2'd0;
    end
end

always @(*) begin
    if (!dcache_req || rst) begin
        dcache_rdata = 32'h0; dcache_ready = 1'b0;
    end else if (dcache_miss_en && dmiss_cnt < 2'd1) begin
        dcache_rdata = 32'h0; dcache_ready = 1'b0;
    end else begin
        dcache_ready = 1'b1;
        dcache_rdata = dcache_we ? 32'h0 : dmem[(dcache_addr - 32'h1000_0000) >> 2];
    end
end

always @(posedge clk) begin
    if (!rst && dcache_req && dcache_we && dcache_ready) begin
        if (dcache_wstrb[0]) dmem[(dcache_addr-32'h1000_0000)>>2][ 7: 0] <= dcache_wdata[ 7: 0];
        if (dcache_wstrb[1]) dmem[(dcache_addr-32'h1000_0000)>>2][15: 8] <= dcache_wdata[15: 8];
        if (dcache_wstrb[2]) dmem[(dcache_addr-32'h1000_0000)>>2][23:16] <= dcache_wdata[23:16];
        if (dcache_wstrb[3]) dmem[(dcache_addr-32'h1000_0000)>>2][31:24] <= dcache_wdata[31:24];
    end
end

// ── Instruction encode helpers ───────────────────────────────────────────────
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
function [31:0] enc_b;
    input [12:0] imm; input [4:0] rs2,rs1; input [2:0] f3;
    enc_b = {imm[12],imm[10:5],rs2,rs1,f3,imm[4:1],imm[11],7'b1100011};
endfunction
function [31:0] enc_u;
    input [19:0] imm; input [4:0] rd; input [6:0] op;
    enc_u = {imm,rd,op};
endfunction
function [31:0] enc_j;
    input [20:0] imm; input [4:0] rd;
    enc_j = {imm[20],imm[10:1],imm[11],imm[19:12],rd,7'b1101111};
endfunction

localparam OP_LUI   = 7'b0110111;
localparam OP_LOAD  = 7'b0000011;
localparam OP_IMMED = 7'b0010011;
localparam OP_RTYPE = 7'b0110011;
localparam F3_ADD   = 3'b000;
localparam F3_LW    = 3'b010;
localparam F3_SW    = 3'b010;
localparam F3_BGE   = 3'b101;
localparam F3_BEQ   = 3'b000;
localparam F3_BNE   = 3'b001;
localparam F7_N     = 7'b0000000;
localparam F7_MUL   = 7'b0000001;

// ── imem helpers ────────────────────────────────────────────────────────────
integer wp, ii;
task wi; input [31:0] ins; begin imem[wp]=ins; wp=wp+1; end endtask
task wn; begin imem[wp]=32'h0000_0013; wp=wp+1; end endtask
task wns; input integer n;
    integer jj;
    begin for(jj=0;jj<n;jj=jj+1) begin imem[wp]=32'h0000_0013; wp=wp+1; end end
endtask
task clr_imem;
    integer jj;
    begin for(jj=0;jj<1024;jj=jj+1) imem[jj]=32'h0000_0013; end
endtask
task clr_dmem;
    integer jj;
    begin for(jj=0;jj< 512;jj=jj+1) dmem[jj]=32'h0; end
endtask

// ── Reset ────────────────────────────────────────────────────────────────────
task do_reset;
    begin
        rst<=1'b1; external_irq<=1'b0; timer_irq<=1'b0; sw_irq<=1'b0;
        imem_miss_en<=1'b0; dcache_miss_en<=1'b0;
        repeat(4) @(posedge clk);
        rst<=1'b0;
        @(posedge clk);
    end
endtask

// ── Check helpers ────────────────────────────────────────────────────────────
integer pass_cnt, fail_cnt, tc;

task chk_reg;
    input [4:0]  rn;
    input [31:0] exp;
    input [63:0] nm;
    reg [31:0] got;
    begin
        @(negedge clk);
        got = rf_snap[rn];
        if (got === exp) begin
            $display("  PASS [TC%02d] %-8s  x%0d = 0x%08h", tc, nm, rn, exp);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL [TC%02d] %-8s  x%0d got=0x%08h exp=0x%08h", tc, nm, rn, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task chk_dmem;
    input [31:0] addr, exp;
    input [63:0] nm;
    reg [31:0] got;
    begin
        @(negedge clk);
        got = dmem[(addr - 32'h1000_0000) >> 2];
        if (got === exp) begin
            $display("  PASS [TC%02d] %-8s  mem[0x%08h]=0x%08h", tc, nm, addr, exp);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL [TC%02d] %-8s  mem[0x%08h] got=0x%08h exp=0x%08h",
                     tc, nm, addr, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ============================================================================
// MAIN
// ============================================================================
initial begin
    pass_cnt=0; fail_cnt=0;
    rst=1'b1; external_irq=1'b0; timer_irq=1'b0; sw_irq=1'b0;
    imem_miss_en=1'b0; dcache_miss_en=1'b0;
    clr_imem(); clr_dmem();
    repeat(2) @(posedge clk);

    // =========================================================================
    // TC-01  Load-Use Hazard: lw → add (basic pattern)
    // x1=CAFE_BEEF loaded from dmem[0]
    // x2 = x1 + 1 = CAFE_BEF0  (load-use stall required)
    // x3 = x1 + 2 = CAFE_BEF1  (WB forwarding)
    // =========================================================================
    tc=1; $display("\n=== TC-01: Load-Use lw→add ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0] = 32'hCAFE_BEEF;
    wi(enc_u(20'h10000, 5'd1, OP_LUI));               // x1 = 0x10000000
    wi(enc_i(12'd0,  5'd1, F3_LW,  5'd2, OP_LOAD));  // LW x2, 0(x1)
    wi(enc_i(12'd1,  5'd2, F3_ADD, 5'd3, OP_IMMED)); // HAZARD: x3 = x2+1
    wi(enc_i(12'd2,  5'd2, F3_ADD, 5'd4, OP_IMMED)); // x4 = x2+2 (WB fwd)
    wns(15);
    do_reset();
    repeat(40) @(posedge clk);
    chk_reg(5'd2, 32'hCAFE_BEEF, "LW");
    chk_reg(5'd3, 32'hCAFE_BEF0, "LU+1");
    chk_reg(5'd4, 32'hCAFE_BEF1, "LU+2");

    // =========================================================================
    // TC-02  Load-Use Hazard với STORE — CRT0 _copy_data pattern
    //
    // Mô phỏng đúng 2 instruction trong CRT0:
    //   lw  x28, 0(x5)    ← load
    //   sw  x28, 0(x6)    ← HAZARD: store dùng x28 ngay sau lw
    //
    // Source: dmem[0x10000000] = 0xDEAD_1234
    // Dest:   dmem[0x10000100]
    // Expected: dmem[0x10000100] = 0xDEAD_1234
    // =========================================================================
    tc=2; $display("\n=== TC-02: Load-Use lw→sw (CRT0 pattern) ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0] = 32'hDEAD_1234;   // source: 0x10000000
    // setup x5=0x10000000 (source), x6=0x10000100 (dest)
    wi(enc_u(20'h10000, 5'd5, OP_LUI));               // x5 = 0x10000000
    wi(enc_u(20'h10000, 5'd6, OP_LUI));               // x6 = 0x10000000
    wi(enc_i(12'd256, 5'd6, F3_ADD, 5'd6, OP_IMMED)); // x6 = 0x10000100
    wi(enc_i(12'd0,  5'd5, F3_LW,  5'd28, OP_LOAD)); // lw x28, 0(x5)
    wi(enc_s(12'd0,  5'd28, 5'd6, F3_SW));             // sw x28, 0(x6) — HAZARD
    wns(15);
    do_reset();
    repeat(40) @(posedge clk);
    chk_reg(5'd28, 32'hDEAD_1234, "x28");
    chk_dmem(32'h1000_0100, 32'hDEAD_1234, "sw→mem");

    // =========================================================================
    // TC-03  CRT0 Multi-Iteration: 4 lần lw→sw liên tiếp (unrolled)
    //
    // Mô phỏng chính xác _copy_data loop body 4 lần:
    //   lw x28, 0(x5); sw x28, 0(x6)
    //   lw x28, 4(x5); sw x28, 4(x6)
    //   lw x28, 8(x5); sw x28, 8(x6)
    //   lw x28,12(x5); sw x28,12(x6)
    //
    // Mỗi lw→sw là 1 load-use hazard riêng biệt.
    // Source: dmem[0..3] = A0000001..A0000004
    // Dest:   dmem[64..67] (= 0x10000100..0x1000010C)
    // =========================================================================
    tc=3; $display("\n=== TC-03: CRT0 4-Iteration lw→sw ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0] = 32'hA000_0001;
    dmem[1] = 32'hA000_0002;
    dmem[2] = 32'hA000_0003;
    dmem[3] = 32'hA000_0004;
    // setup x5=0x10000000, x6=0x10000100
    wi(enc_u(20'h10000, 5'd5, OP_LUI));               // x5 = 0x10000000
    wi(enc_u(20'h10000, 5'd6, OP_LUI));               // x6 = 0x10000000
    wi(enc_i(12'd256, 5'd6, F3_ADD, 5'd6, OP_IMMED)); // x6 = 0x10000100
    // Iteration 1
    wi(enc_i(12'd0,  5'd5, F3_LW, 5'd28, OP_LOAD));  // lw x28, 0(x5)
    wi(enc_s(12'd0,  5'd28, 5'd6, F3_SW));             // sw x28, 0(x6) HAZARD
    // Iteration 2
    wi(enc_i(12'd4,  5'd5, F3_LW, 5'd28, OP_LOAD));  // lw x28, 4(x5)
    wi(enc_s(12'd4,  5'd28, 5'd6, F3_SW));             // sw x28, 4(x6) HAZARD
    // Iteration 3
    wi(enc_i(12'd8,  5'd5, F3_LW, 5'd28, OP_LOAD));  // lw x28, 8(x5)
    wi(enc_s(12'd8,  5'd28, 5'd6, F3_SW));             // sw x28, 8(x6) HAZARD
    // Iteration 4
    wi(enc_i(12'd12, 5'd5, F3_LW, 5'd28, OP_LOAD));  // lw x28,12(x5)
    wi(enc_s(12'd12, 5'd28, 5'd6, F3_SW));             // sw x28,12(x6) HAZARD
    wns(15);
    do_reset();
    repeat(60) @(posedge clk);
    chk_dmem(32'h1000_0100, 32'hA000_0001, "copy[0]");
    chk_dmem(32'h1000_0104, 32'hA000_0002, "copy[1]");
    chk_dmem(32'h1000_0108, 32'hA000_0003, "copy[2]");
    chk_dmem(32'h1000_010C, 32'hA000_0004, "copy[3]");

    // =========================================================================
    // TC-04  CRT0 Loop (lw→sw trong loop với JAL)
    //
    // Giống _copy_data thực tế nhất: vòng lặp 4 lần có branch guard và JAL
    // PC=0 : lui x5, 0x10000
    // PC=4 : lui x6, 0x10000
    // PC=8 : addi x6, x6, 256  (x6 = 0x10000100)
    // PC=12: lui x7, 0x10000
    // PC=16: addi x7, x7, 272  (x7 = 0x10000110 = dest+16, stop condition)
    // PC=20: bge x6, x7, +32   → done @ PC=52 (if x6>=x7)
    // PC=24: lw  x28, 0(x5)
    // PC=28: sw  x28, 0(x6)    HAZARD
    // PC=32: addi x5, x5, 4
    // PC=36: addi x6, x6, 4
    // PC=40: jal x0, -20       → PC=20
    // PC=44: nop (flush slot)
    // PC=48: nop (flush slot)
    // PC=52: nop (done)
    // =========================================================================
    tc=4; $display("\n=== TC-04: CRT0 Loop lw→sw (bge+jal) ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0] = 32'hB000_0001;
    dmem[1] = 32'hB000_0002;
    dmem[2] = 32'hB000_0003;
    dmem[3] = 32'hB000_0004;
    // PC=0..16: setup
    wi(enc_u(20'h10000, 5'd5, OP_LUI));                // PC=0
    wi(enc_u(20'h10000, 5'd6, OP_LUI));                // PC=4
    wi(enc_i(12'd256, 5'd6, F3_ADD, 5'd6, OP_IMMED)); // PC=8   x6=0x10000100
    wi(enc_u(20'h10000, 5'd7, OP_LUI));                // PC=12
    wi(enc_i(12'd272, 5'd7, F3_ADD, 5'd7, OP_IMMED)); // PC=16  x7=0x10000110
    // PC=20: loop guard (bge x6, x7, +32 → PC=52)
    wi(enc_b(13'd32, 5'd7, 5'd6, F3_BGE));             // PC=20
    // PC=24: lw x28, 0(x5)
    wi(enc_i(12'd0, 5'd5, F3_LW, 5'd28, OP_LOAD));    // PC=24
    // PC=28: sw x28, 0(x6) — HAZARD
    wi(enc_s(12'd0, 5'd28, 5'd6, F3_SW));              // PC=28
    // PC=32: addi x5, x5, 4
    wi(enc_i(12'd4, 5'd5, F3_ADD, 5'd5, OP_IMMED));   // PC=32
    // PC=36: addi x6, x6, 4
    wi(enc_i(12'd4, 5'd6, F3_ADD, 5'd6, OP_IMMED));   // PC=36
    // PC=40: jal x0, -20  (target=PC+offset=40-20=20 → loop start)
    // -20 in 21-bit 2's complement = 21'h1FFFEC
    wi(enc_j(21'h1FFFEC, 5'd0));                       // PC=40
    wns(20); // PC=44.. (flush + done area + drain)
    do_reset();
    repeat(120) @(posedge clk);
    chk_dmem(32'h1000_0100, 32'hB000_0001, "loop[0]");
    chk_dmem(32'h1000_0104, 32'hB000_0002, "loop[1]");
    chk_dmem(32'h1000_0108, 32'hB000_0003, "loop[2]");
    chk_dmem(32'h1000_010C, 32'hB000_0004, "loop[3]");

    // =========================================================================
    // TC-05  MUL Hazard: mul → add immediate use
    // x1=5, x2=3
    // x3 = mul(x1,x2) = 15
    // x4 = x3 + x1 = 20   (hazard: dùng x3 ngay sau mul)
    // =========================================================================
    tc=5; $display("\n=== TC-05: MUL hazard ===");
    clr_imem(); clr_dmem(); wp=0;
    wi(enc_i(12'd5, 5'd0, F3_ADD, 5'd1, OP_IMMED));         // x1=5
    wi(enc_i(12'd3, 5'd0, F3_ADD, 5'd2, OP_IMMED));         // x2=3
    wi(enc_r(F7_MUL, 5'd2, 5'd1, F3_ADD, 5'd3, OP_RTYPE)); // mul x3,x1,x2=15
    wi(enc_r(F7_N,   5'd1, 5'd3, F3_ADD, 5'd4, OP_RTYPE)); // add x4,x3,x1=20 HAZARD
    wns(15);
    do_reset();
    repeat(40) @(posedge clk);
    chk_reg(5'd3, 32'd15, "MUL");
    chk_reg(5'd4, 32'd20, "MUL+add");

    // =========================================================================
    // TC-06  Load-Use với DCache miss (latency > 1 cycle)
    // Giống TC-02 nhưng enable dcache_miss_inject → LSU đợi thêm 1 cycle
    // =========================================================================
    tc=6; $display("\n=== TC-06: Load-Use with DCache miss ===");
    clr_imem(); clr_dmem(); wp=0;
    dmem[0] = 32'hFEED_C0DE;
    wi(enc_u(20'h10000, 5'd5, OP_LUI));
    wi(enc_u(20'h10000, 5'd6, OP_LUI));
    wi(enc_i(12'd256, 5'd6, F3_ADD, 5'd6, OP_IMMED));
    wi(enc_i(12'd0, 5'd5, F3_LW, 5'd28, OP_LOAD));
    wi(enc_s(12'd0, 5'd28, 5'd6, F3_SW));
    wns(15);
    do_reset();
    dcache_miss_en = 1'b1;
    repeat(60) @(posedge clk);
    dcache_miss_en = 1'b0;
    repeat(10) @(posedge clk);
    chk_reg(5'd28, 32'hFEED_C0DE, "LW miss");
    chk_dmem(32'h1000_0100, 32'hFEED_C0DE, "SW miss");

    // =========================================================================
    // SUMMARY
    // =========================================================================
    $display("\n============================================================");
    $display(" PASS=%0d  FAIL=%0d  TOTAL=%0d", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    if (fail_cnt == 0) begin
        $display(" RESULT: [L1-PASS] ALL PIPELINE HAZARD TESTS PASSED");
    end else begin
        $display(" RESULT: [L1-FAIL] %0d TEST(S) FAILED", fail_cnt);
        $display(" Action: Fix pipeline bugs in PIPELINE_REG_MEM_WB.v / hazard_detection.v");
    end
    $display("============================================================");
    $finish;
end

initial begin
    #500_000;
    $display("[WATCHDOG] tb_layer1_pipeline timeout");
    $finish;
end

endmodule
