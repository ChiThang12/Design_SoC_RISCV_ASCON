`timescale 1ns/1ps
// ============================================================================
// tb_cpu_jalr_flush.v — Kiểm tra JALR pipeline flush
//
// Bug được phát hiện trong C4 (test_gpio):
//   Sau JALR, lệnh addi x10=0xAA (chuẩn bị cho gpio_write) không bị flush
//   → execute trước sw của gpio_set_dir → GPIO DIR = 0xAA thay vì 0xFF
//
// TC-JALR: set x10=0xFF, JALR→func, [addi x10=0xAA should flush], func: sw x10
//   PASS nếu dmem[0x100] == 0xFF
// TC-JAL:  tương tự với JAL (direct jump, sanity check)
//   PASS nếu dmem[0x200] == 0xFF
// ============================================================================
`include "cpu/riscv_cpu_core_v2.v"

module tb_cpu_jalr_flush;

reg clk, rst;
initial clk = 0;
always #5 clk = ~clk;

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
    .external_irq     (1'b0),
    .timer_irq        (1'b0),
    .sw_irq           (1'b0),
    .debug_haltreq    (1'b0),
    .debug_resumereq  (1'b0),
    .debug_halted     (),
    .debug_running    (),
    .cpu_wfi_o        (),
    .perf_stall_o     (),
    .perf_instr_ret_o ()
);

// ── IMEM ────────────────────────────────────────────────────────────────────
// TC-JALR (0x00-0x28):
//   0x00: addi x10, x0, 0xFF       x10=255
//   0x04: addi x11, x0, 0x100      x11=0x100 (dst addr)
//   0x08: jalr x1, x0, 0x20        jump to 0x20, flush 0x0C
//   0x0C: addi x10, x0, 0xAA       MUST BE FLUSHED
//   0x10-0x1C: nop
//   0x20: sw x10, 0(x11)           dmem[0x100] = x10
//   0x24: jal x0, 0                halt
//
// TC-JAL (0x100-0x128):
//   0x100: addi x12, x0, 0xFF      x12=255
//   0x104: addi x13, x0, 0x200     x13=0x200
//   0x108: jal x0, 0x18            jump to 0x120
//   0x10C: addi x12, x0, 0xAA      MUST BE FLUSHED
//   0x110-0x11C: nop
//   0x120: sw x12, 0(x13)          dmem[0x200] = x12
//   0x124: jal x0, 0               halt

reg [31:0] imem [0:255];
reg [31:0] dmem [0:255];

integer i_init;
initial begin
    for (i_init = 0; i_init < 256; i_init = i_init + 1) begin
        imem[i_init] = 32'h00000013; // NOP
        dmem[i_init] = 32'hDEADBEEF;
    end

    // TC-JALR
    imem[8'h00 >> 2] = 32'h0FF00513; // addi x10, x0, 255
    imem[8'h04 >> 2] = 32'h10000593; // addi x11, x0, 256
    imem[8'h08 >> 2] = 32'h020000E7; // jalr x1, x0, 0x20
    imem[8'h0C >> 2] = 32'h0AA00513; // addi x10, x0, 170 ← flush target
    imem[8'h20 >> 2] = 32'h00A5A023; // sw x10, 0(x11)
    imem[8'h24 >> 2] = 32'h0000006F; // jal x0, 0 (halt)

    // TC-JAL (imem index 0x40..0x49 = addr 0x100..0x124)
    imem[8'hFF & (9'h100 >> 2)] = 32'h0FF00613; // addi x12, x0, 255
    imem[8'hFF & (9'h104 >> 2)] = 32'h20000693; // addi x13, x0, 512
    // jal x0, +0x18 → target = 0x108 + 0x18 = 0x120
    // J-imm = 0x18: imm[20]=0, imm[10:1]=0b0001100, imm[11]=0, imm[19:12]=0
    // = 0<<31 | 00000000<<12 | 0<<20 | 0011000000<<21 = 0x01800000|0x6F
    imem[8'hFF & (9'h108 >> 2)] = 32'h0180006F; // jal x0, 0x18
    imem[8'hFF & (9'h10C >> 2)] = 32'h0AA00613; // addi x12, x0, 170 ← flush target
    imem[8'hFF & (9'h120 >> 2)] = 32'h00D6A023; // sw x12, 0(x13)
    imem[8'hFF & (9'h124 >> 2)] = 32'h0000006F; // jal x0, 0 (halt)
end

always @(*) begin
    imem_rdata = imem[imem_addr[9:2]];
    imem_ready = 1'b1;
    dcache_ready = 1'b1;
    dcache_rdata = dmem[dcache_addr[9:2]];
end

always @(posedge clk) begin
    if (dcache_req && dcache_we)
        dmem[dcache_addr[9:2]] <= dcache_wdata;
end

// ── Test control ─────────────────────────────────────────────────────────────
integer pass_count;
integer fail_count;
integer wait_cnt;
reg [31:0] prev_pc;
integer stable_cnt;

initial begin
    rst        = 1;
    pass_count = 0;
    fail_count = 0;
    @(posedge clk); #1;
    @(posedge clk); #1;
    rst = 0;

    // ── TC-JALR: wait for halt at 0x24 ──────────────────────────────────
    $display("[TC-JALR] JALR flush: x10 must be 0xFF when target executes sw");
    prev_pc = 0; stable_cnt = 0;
    for (wait_cnt = 0; wait_cnt < 300; wait_cnt = wait_cnt + 1) begin
        @(posedge clk); #1;
        if (imem_addr === 32'h24) stable_cnt = stable_cnt + 1;
        else                      stable_cnt = 0;
    end

    if (dmem[32'h100 >> 2] === 32'h000000FF) begin
        $display("[TC-JALR] PASS: dmem[0x100]=0x%08X (0xFF — flush OK)", dmem[32'h100 >> 2]);
        pass_count = pass_count + 1;
    end else begin
        $display("[TC-JALR] FAIL: dmem[0x100]=0x%08X (expect 0xFF, flush BROKEN)", dmem[32'h100 >> 2]);
        fail_count = fail_count + 1;
    end

    // ── TC-JAL: patch imem[0] to jal→0x100, reset ───────────────────────
    $display("[TC-JAL]  JAL flush: x12 must be 0xFF when target executes sw");
    imem[0] = 32'h1000006F; // jal x0, 0x100
    rst = 1; @(posedge clk); #1; @(posedge clk); #1;
    rst = 0;

    stable_cnt = 0;
    for (wait_cnt = 0; wait_cnt < 300; wait_cnt = wait_cnt + 1) begin
        @(posedge clk); #1;
        if (imem_addr === 32'h124) stable_cnt = stable_cnt + 1;
        else                       stable_cnt = 0;
    end

    if (dmem[32'h200 >> 2] === 32'h000000FF) begin
        $display("[TC-JAL]  PASS: dmem[0x200]=0x%08X (0xFF — flush OK)", dmem[32'h200 >> 2]);
        pass_count = pass_count + 1;
    end else begin
        $display("[TC-JAL]  FAIL: dmem[0x200]=0x%08X (expect 0xFF, flush BROKEN)", dmem[32'h200 >> 2]);
        fail_count = fail_count + 1;
    end

    $display("-------------------------------------");
    if (fail_count == 0)
        $display("[JALR-FLUSH-PASS] %0d/%0d", pass_count, pass_count + fail_count);
    else
        $display("[JALR-FLUSH-FAIL] %0d failed / %0d total", fail_count, pass_count + fail_count);
    $display("-------------------------------------");
    $finish;
end

initial begin
    #100000;
    $display("[TIMEOUT] tb_cpu_jalr_flush exceeded 100000ns");
    $finish;
end

endmodule
