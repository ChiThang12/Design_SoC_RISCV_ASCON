`timescale 1ns/1ps
// ============================================================================
// tb_cpu_crt0_pattern.v — Layer 2: CRT0 _copy_data hazard pattern
//
// Test: CPU executes lw→sw copy loop (14 words) with load-use stall.
// Verifies BUG-001 fix: hazard detection correctly stalls lw→sw sequence.
//
// IMEM: behavioral combinational (IFU expects same-cycle response)
// DMEM: behavioral combinational (instant, 0-latency)
// No real AXI — pure CPU test.
//
// Program in IMEM:
//   [0x00] addi a0, x0, 0x100    # a0 = src base (byte addr in DMEM)
//   [0x04] lui  a1, 0x10000      # a1 = 0x10000000 (dst base)
//   [0x08] addi a2, x0, 14       # a2 = count
//   [0x0C] lw   t0, 0(a0)        # ← LOAD (load-use hazard point)
//   [0x10] sw   t0, 0(a1)        # ← STORE (needs stall if hazard not handled)
//   [0x14] addi a0, a0, 4
//   [0x18] addi a1, a1, 4
//   [0x1C] addi a2, a2, -1
//   [0x20] bne  a2, x0, -20      # back to lw
//   [0x24] jal  x0, 0            # halt
//
// Source data: dmem[64..77] = 0x11111111..0xEEEEEEEE
// Expected:    dmem[0..13]  should match dmem[64..77] after loop
//
// Pass criterion: [L2-PASS] printed if all 14 words match
// ============================================================================
`include "cpu/riscv_cpu_core_v2.v"

module tb_cpu_crt0_pattern;

// ---------------------------------------------------------------------------
// Clock / Reset
// ---------------------------------------------------------------------------
reg clk, rst;
initial clk = 0;
always #5 clk = ~clk;  // 100 MHz

// ---------------------------------------------------------------------------
// CPU I/O
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
wire [1:0]  dcache_fence_type;
reg  [31:0] dcache_rdata;
reg         dcache_ready;

// Unused CPU ports
wire        debug_halted, debug_running, cpu_wfi_o;
wire        perf_stall_o, perf_instr_ret_o;

// ---------------------------------------------------------------------------
// DUT
// ---------------------------------------------------------------------------
riscv_cpu_core dut (
    .clk               (clk),
    .rst               (rst),
    .imem_addr         (imem_addr),
    .imem_valid        (imem_valid),
    .imem_rdata        (imem_rdata),
    .imem_ready        (imem_ready),
    .dcache_addr       (dcache_addr),
    .dcache_wdata      (dcache_wdata),
    .dcache_wstrb      (dcache_wstrb),
    .dcache_req        (dcache_req),
    .dcache_we         (dcache_we),
    .dcache_rdata      (dcache_rdata),
    .dcache_ready      (dcache_ready),
    .dcache_fence_type (dcache_fence_type),
    .external_irq      (1'b0),
    .timer_irq         (1'b0),
    .sw_irq            (1'b0),
    .debug_haltreq     (1'b0),
    .debug_resumereq   (1'b0),
    .debug_halted      (debug_halted),
    .debug_running     (debug_running),
    .cpu_wfi_o         (cpu_wfi_o),
    .perf_stall_o      (perf_stall_o),
    .perf_instr_ret_o  (perf_instr_ret_o)
);

// ---------------------------------------------------------------------------
// Register file probe
// ---------------------------------------------------------------------------
wire [31:0] rf_a2 = dut.register_file.registers[12]; // a2 (loop counter)
wire [31:0] rf_a0 = dut.register_file.registers[10]; // a0 (src ptr)
wire [31:0] rf_a1 = dut.register_file.registers[11]; // a1 (dst ptr)

// ---------------------------------------------------------------------------
// Instruction Memory — COMBINATIONAL (matches IFU design: same-cycle response)
// ---------------------------------------------------------------------------
reg [31:0] imem [0:1023];

always @(*) begin
    if (!imem_valid || rst) begin
        imem_rdata = 32'h0000_0013; // NOP
        imem_ready = 1'b0;
    end else begin
        imem_rdata = imem[imem_addr[11:2]];
        imem_ready = 1'b1;
    end
end

// ---------------------------------------------------------------------------
// Data Memory — COMBINATIONAL read, registered write
// ---------------------------------------------------------------------------
reg [31:0] dmem [0:511];

always @(*) begin
    dcache_rdata = dmem[dcache_addr[10:2]];
    dcache_ready = dcache_req;  // instant 0-latency
end

always @(posedge clk) begin
    if (dcache_req && dcache_we) begin
        if (dcache_wstrb[3]) dmem[dcache_addr[10:2]][31:24] <= dcache_wdata[31:24];
        if (dcache_wstrb[2]) dmem[dcache_addr[10:2]][23:16] <= dcache_wdata[23:16];
        if (dcache_wstrb[1]) dmem[dcache_addr[10:2]][15:8]  <= dcache_wdata[15:8];
        if (dcache_wstrb[0]) dmem[dcache_addr[10:2]][7:0]   <= dcache_wdata[7:0];
    end
end

// ---------------------------------------------------------------------------
// Test stimulus
// ---------------------------------------------------------------------------
integer i, fail_cnt;

initial begin
    // ── Load CRT0 program ──────────────────────────────────────────────────
    // Setup (words 0-2)
    imem[0]  = 32'h10000513; // addi a0, x0, 0x100   (src byte addr = 0x100)
    imem[1]  = 32'h100005B7; // lui  a1, 0x10000      (dst = 0x10000000)
    imem[2]  = 32'h00E00613; // addi a2, x0, 14       (count = 14)
    // Loop body (words 3-8, starts at byte 0x0C)
    imem[3]  = 32'h00052283; // lw   t0, 0(a0)        ← LOAD
    imem[4]  = 32'h0055A023; // sw   t0, 0(a1)        ← STORE (load-use hazard)
    imem[5]  = 32'h00450513; // addi a0, a0, 4
    imem[6]  = 32'h00458593; // addi a1, a1, 4
    imem[7]  = 32'hFFF60613; // addi a2, a2, -1
    imem[8]  = 32'hFE0616E3; // bne  a2, x0, -20      (branch to word 3)
    // Halt (word 9, byte 0x24)
    imem[9]  = 32'h0000006F; // jal  x0, 0

    // ── Initialize source data in DMEM (byte addr 0x100 → dmem word 64) ────
    // dcache_addr=0x100 → dmem[0x100[10:2]] = dmem[64]
    dmem[64] = 32'h11111111;
    dmem[65] = 32'h22222222;
    dmem[66] = 32'h33333333;
    dmem[67] = 32'h44444444;
    dmem[68] = 32'h55555555;
    dmem[69] = 32'h66666666;
    dmem[70] = 32'h77777777;
    dmem[71] = 32'h88888888;
    dmem[72] = 32'h99999999;
    dmem[73] = 32'hAAAAAAAA;
    dmem[74] = 32'hBBBBBBBB;
    dmem[75] = 32'hCCCCCCCC;
    dmem[76] = 32'hDDDDDDDD;
    dmem[77] = 32'hEEEEEEEE;

    // ── Reset sequence ─────────────────────────────────────────────────────
    rst = 1;
    repeat(5) @(posedge clk);
    rst = 0;

    // ── Run: wait for halt (CPU at 0x24 = jal x0,0) or timeout ────────────
    begin : wait_halt
        integer cyc;
        integer halt_cyc;
        halt_cyc = 0;
        for (cyc = 0; cyc < 10000; cyc = cyc + 1) begin
            @(posedge clk);
            if (imem_addr == 32'h00000024)
                halt_cyc = halt_cyc + 1;
            else
                halt_cyc = 0;
            if (halt_cyc >= 4) disable wait_halt; // stable halt detected
        end
    end

    // ── Allow last write to register ───────────────────────────────────────
    repeat(5) @(posedge clk);

    // ── Verify results ─────────────────────────────────────────────────────
    fail_cnt = 0;
    for (i = 0; i < 14; i = i + 1) begin
        if (dmem[i] !== dmem[64 + i]) begin
            $display("[L2-FAIL] word[%0d]: got 0x%08X, expected 0x%08X",
                     i, dmem[i], dmem[64+i]);
            fail_cnt = fail_cnt + 1;
        end
    end

    // Check loop counter ran to completion
    if (rf_a2 !== 32'h0) begin
        $display("[L2-FAIL] a2 = 0x%08X, expected 0 (loop not complete)", rf_a2);
        fail_cnt = fail_cnt + 1;
    end

    if (fail_cnt == 0)
        $display("[L2-PASS] CRT0 copy correct: 14/14 words match, a2=0");
    else
        $display("[L2-FAIL] %0d errors — load-use hazard or forwarding bug", fail_cnt);

    $finish;
end

// Watchdog
initial begin
    #500000; // 50000 cycles @ 10ns
    $display("[L2-FAIL] WATCHDOG timeout");
    $finish;
end

endmodule
