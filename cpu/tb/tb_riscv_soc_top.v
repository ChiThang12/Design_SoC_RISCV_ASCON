`timescale 1ns/1ps
// ============================================================================
// tb_riscv_soc_top.v — Layer 3: CPU + DCache + DMEM via AXI
//
// Test: Store 4 words to 4 different cache lines, load back, verify match.
// This exercises: DCache write-miss + refill, subsequent read hit, AXI path.
//
// DUT structure:
//   riscv_cpu_core  →(dcache signals)→  dcache_top  →(AXI)→  data_mem_axi4_slave
//   IMEM: behavioral combinational (IFU expects same-cycle response)
//
// Program in IMEM:
//   0x00: lui  a0, 0x10000        # a0 = 0x10000000 (DMEM base)
//   0x04: addi t0, x0, 1          # t0 = 1
//   0x08: sw   t0, 0(a0)          # mem[0x10000000] = 1   (miss→refill)
//   0x0C: addi t1, x0, 2          # t1 = 2
//   0x10: sw   t1, 16(a0)         # mem[0x10000010] = 2   (miss, different line)
//   0x14: addi t2, x0, 3          # t2 = 3
//   0x18: sw   t2, 0x100(a0)      # mem[0x10000100] = 3   (miss, different index)
//   0x1C: addi t3, x0, 4          # t3 = 4
//   0x20: sw   t3, 0x200(a0)      # mem[0x10000200] = 4   (miss)
//   0x24: lw   s0, 0(a0)          # s0 = mem[0x10000000]  (hit)
//   0x28: lw   s1, 16(a0)         # s1 = mem[0x10000010]  (hit)
//   0x2C: lw   s2, 0x100(a0)      # s2 = mem[0x10000100]  (hit)
//   0x30: lw   s3, 0x200(a0)      # s3 = mem[0x10000200]  (hit)
//   0x34: jal  x0, 0              # halt
//
// Pass: s0==1, s1==2, s2==3, s3==4 → [L3-PASS]
// ============================================================================
`include "cpu/riscv_cpu_core_v2.v"
`include "cache_interface/dcache/dcache_top.v"
`include "memory/data_mem_axi_slave.v"

module tb_riscv_soc_top;

// ---------------------------------------------------------------------------
// Clock / Reset
// ---------------------------------------------------------------------------
reg  clk, rst;
wire rst_n = ~rst;
initial clk = 0;
always #5 clk = ~clk;  // 100 MHz

// ---------------------------------------------------------------------------
// CPU ↔ IMEM (behavioral)
// ---------------------------------------------------------------------------
wire [31:0] imem_addr;
wire        imem_valid;
reg  [31:0] imem_rdata;
reg         imem_ready;

// ---------------------------------------------------------------------------
// CPU ↔ DCache signals
// ---------------------------------------------------------------------------
wire [31:0] cpu_dcache_addr;
wire [31:0] cpu_dcache_wdata;
wire [3:0]  cpu_dcache_wstrb;
wire        cpu_dcache_req;
wire        cpu_dcache_we;
wire [31:0] cpu_dcache_rdata;
wire        cpu_dcache_ready;
wire [1:0]  cpu_dcache_fence_type;

// ---------------------------------------------------------------------------
// DCache ↔ DMEM AXI4
// ---------------------------------------------------------------------------
wire [3:0]  dc_arid;
wire [31:0] dc_araddr;
wire [7:0]  dc_arlen;
wire [2:0]  dc_arsize;
wire [1:0]  dc_arburst;
wire [2:0]  dc_arprot;
wire        dc_arvalid;
wire        dc_arready;

wire [3:0]  dc_rid;
wire [31:0] dc_rdata;
wire [1:0]  dc_rresp;
wire        dc_rlast;
wire        dc_rvalid;
wire        dc_rready;

wire [3:0]  dc_awid;
wire [31:0] dc_awaddr;
wire [7:0]  dc_awlen;
wire [2:0]  dc_awsize;
wire [1:0]  dc_awburst;
wire [2:0]  dc_awprot;
wire        dc_awvalid;
wire        dc_awready;

wire [31:0] dc_wdata;
wire [3:0]  dc_wstrb;
wire        dc_wlast;
wire        dc_wvalid;
wire        dc_wready;

wire [3:0]  dc_bid;
wire [1:0]  dc_bresp;
wire        dc_bvalid;
wire        dc_bready;

// DCache debug (unused)
wire [31:0] dc_debug_addr;
wire [31:0] dc_debug_data;
wire        dc_debug_valid;

// Unused CPU outputs
wire debug_halted, debug_running, cpu_wfi_o;
wire perf_stall_o, perf_instr_ret_o;

// ---------------------------------------------------------------------------
// DUT 1: CPU core
// ---------------------------------------------------------------------------
riscv_cpu_core u_cpu (
    .clk               (clk),
    .rst               (rst),
    .imem_addr         (imem_addr),
    .imem_valid        (imem_valid),
    .imem_rdata        (imem_rdata),
    .imem_ready        (imem_ready),
    .dcache_addr       (cpu_dcache_addr),
    .dcache_wdata      (cpu_dcache_wdata),
    .dcache_wstrb      (cpu_dcache_wstrb),
    .dcache_req        (cpu_dcache_req),
    .dcache_we         (cpu_dcache_we),
    .dcache_rdata      (cpu_dcache_rdata),
    .dcache_ready      (cpu_dcache_ready),
    .dcache_fence_type (cpu_dcache_fence_type),
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
// DUT 2: Data cache
// ---------------------------------------------------------------------------
dcache_top #(
    .CACHE_SIZE (8192),
    .LINE_SIZE  (16),
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_WIDTH   (4)
) u_dcache (
    .clk         (clk),
    .rst_n       (rst_n),
    // CPU interface
    .cpu_addr    (cpu_dcache_addr),
    .cpu_wdata   (cpu_dcache_wdata),
    .cpu_wstrb   (cpu_dcache_wstrb),
    .cpu_req     (cpu_dcache_req),
    .cpu_we      (cpu_dcache_we),
    .cpu_rdata   (cpu_dcache_rdata),
    .cpu_ready   (cpu_dcache_ready),
    .fence_type  (cpu_dcache_fence_type),
    // Debug
    .current_addr  (dc_debug_addr),
    .current_data  (dc_debug_data),
    .current_valid (dc_debug_valid),
    // AXI Read
    .mem_arid    (dc_arid),
    .mem_araddr  (dc_araddr),
    .mem_arlen   (dc_arlen),
    .mem_arsize  (dc_arsize),
    .mem_arburst (dc_arburst),
    .mem_arprot  (dc_arprot),
    .mem_arvalid (dc_arvalid),
    .mem_arready (dc_arready),
    .mem_rid     (dc_rid),
    .mem_rdata   (dc_rdata),
    .mem_rresp   (dc_rresp),
    .mem_rlast   (dc_rlast),
    .mem_rvalid  (dc_rvalid),
    .mem_rready  (dc_rready),
    // AXI Write
    .mem_awid    (dc_awid),
    .mem_awaddr  (dc_awaddr),
    .mem_awlen   (dc_awlen),
    .mem_awsize  (dc_awsize),
    .mem_awburst (dc_awburst),
    .mem_awprot  (dc_awprot),
    .mem_awvalid (dc_awvalid),
    .mem_awready (dc_awready),
    .mem_wdata   (dc_wdata),
    .mem_wstrb   (dc_wstrb),
    .mem_wlast   (dc_wlast),
    .mem_wvalid  (dc_wvalid),
    .mem_wready  (dc_wready),
    .mem_bid     (dc_bid),
    .mem_bresp   (dc_bresp),
    .mem_bvalid  (dc_bvalid),
    .mem_bready  (dc_bready)
);

// ---------------------------------------------------------------------------
// DUT 3: DMEM AXI slave (8KB)
// ---------------------------------------------------------------------------
data_mem_axi4_slave #(
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_WIDTH   (4),
    .MEM_SIZE   (8192)
) u_dmem (
    .clk          (clk),
    .rst_n        (rst_n),
    // Write address
    .S_AXI_AWID    (dc_awid),
    .S_AXI_AWADDR  (dc_awaddr),
    .S_AXI_AWLEN   (dc_awlen),
    .S_AXI_AWSIZE  (dc_awsize),
    .S_AXI_AWBURST (dc_awburst),
    .S_AXI_AWPROT  (dc_awprot),
    .S_AXI_AWVALID (dc_awvalid),
    .S_AXI_AWREADY (dc_awready),
    // Write data
    .S_AXI_WDATA   (dc_wdata),
    .S_AXI_WSTRB   (dc_wstrb),
    .S_AXI_WLAST   (dc_wlast),
    .S_AXI_WVALID  (dc_wvalid),
    .S_AXI_WREADY  (dc_wready),
    // Write response
    .S_AXI_BID     (dc_bid),
    .S_AXI_BRESP   (dc_bresp),
    .S_AXI_BVALID  (dc_bvalid),
    .S_AXI_BREADY  (dc_bready),
    // Read address
    .S_AXI_ARID    (dc_arid),
    .S_AXI_ARADDR  (dc_araddr),
    .S_AXI_ARLEN   (dc_arlen),
    .S_AXI_ARSIZE  (dc_arsize),
    .S_AXI_ARBURST (dc_arburst),
    .S_AXI_ARPROT  (dc_arprot),
    .S_AXI_ARVALID (dc_arvalid),
    .S_AXI_ARREADY (dc_arready),
    // Read data
    .S_AXI_RID     (dc_rid),
    .S_AXI_RDATA   (dc_rdata),
    .S_AXI_RRESP   (dc_rresp),
    .S_AXI_RLAST   (dc_rlast),
    .S_AXI_RVALID  (dc_rvalid),
    .S_AXI_RREADY  (dc_rready)
);

// ---------------------------------------------------------------------------
// IMEM — COMBINATIONAL response (IFU requires same-cycle data)
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
// Register file probes (for result checking)
// ---------------------------------------------------------------------------
wire [31:0] rf_s0 = u_cpu.register_file.registers[8];  // s0
wire [31:0] rf_s1 = u_cpu.register_file.registers[9];  // s1
wire [31:0] rf_s2 = u_cpu.register_file.registers[18]; // s2
wire [31:0] rf_s3 = u_cpu.register_file.registers[19]; // s3

// ---------------------------------------------------------------------------
// Test stimulus
// ---------------------------------------------------------------------------
integer fail_cnt;

initial begin
    // ── Load program ───────────────────────────────────────────────────────
    // Encoding reference (RV32I):
    //   lui  a0, 0x10000   → 0x100005B7
    //   addi t0, x0, 1     → 0x00100293  (t0=x5)
    //   sw   t0, 0(a0)     → 0x00552023
    //   addi t1, x0, 2     → 0x00200313  (t1=x6)
    //   sw   t1, 16(a0)    → 0x00652823  imm=0x10
    //   addi t2, x0, 3     → 0x00300393  (t2=x7)
    //   sw   t2, 0x100(a0) → 0x10752023
    //   addi t3, x0, 4     → 0x00400E13  (t3=x28)
    //   sw   t3, 0x200(a0) → 0x21C52023
    //   lw   s0, 0(a0)     → 0x00052403  (s0=x8)
    //   lw   s1, 16(a0)    → 0x01052483  (s1=x9)
    //   lw   s2, 0x100(a0) → 0x10052903  (s2=x18)
    //   lw   s3, 0x200(a0) → 0x20052983  (s3=x19)
    //   jal  x0, 0         → 0x0000006F
    imem[0]  = 32'h100005B7; // lui  a0, 0x10000
    imem[1]  = 32'h00100293; // addi t0, x0, 1
    imem[2]  = 32'h00552023; // sw   t0, 0(a0)
    imem[3]  = 32'h00200313; // addi t1, x0, 2
    imem[4]  = 32'h00652823; // sw   t1, 16(a0)
    imem[5]  = 32'h00300393; // addi t2, x0, 3
    imem[6]  = 32'h10752023; // sw   t2, 0x100(a0)
    imem[7]  = 32'h00400E13; // addi t3, x0, 4
    imem[8]  = 32'h21C52023; // sw   t3, 0x200(a0)
    imem[9]  = 32'h00052403; // lw   s0, 0(a0)
    imem[10] = 32'h01052483; // lw   s1, 16(a0)
    imem[11] = 32'h10052903; // lw   s2, 0x100(a0)
    imem[12] = 32'h20052983; // lw   s3, 0x200(a0)
    imem[13] = 32'h0000006F; // jal  x0, 0 (halt)

    // Initialize all remaining IMEM entries to NOP (prevent X-propagation
    // from uninitialized entries when JAL speculatively fetches past 0x34).
    begin : init_nop
        integer k;
        for (k = 14; k < 1024; k = k + 1)
            imem[k] = 32'h00000013; // NOP
    end

    // ── Reset ──────────────────────────────────────────────────────────────
    rst = 1;
    repeat(10) @(posedge clk);
    rst = 0;

    // ── Wait for CPU to reach halt instruction (imem_addr == 0x34) ─────────
    begin : wait_halt
        integer cyc;
        integer halt_cnt;
        halt_cnt = 0;
        for (cyc = 0; cyc < 200000; cyc = cyc + 1) begin
            @(posedge clk);
            if (imem_addr == 32'h00000034)
                halt_cnt = halt_cnt + 1;
            // Note: JAL creates 0x34/0x38/0x3C/0x34... pattern — consecutive
            // count can never reach 4. Accept first detection (halt_cnt >= 1).
            if (halt_cnt >= 1) disable wait_halt;
        end
    end

    // ── Wait for LSU to drain SB and commit all LQ results ─────────────────
    // SB has 4 entries draining at ~11 cycles each = ~44 cycles. Last LQ
    // dequeue happens in DRAIN_IDLE window after 4th store drain (~cycle 60).
    // 200 cycles gives ample margin for all loads to commit to register file.
    repeat(200) @(posedge clk);

    // ── Verify register results ─────────────────────────────────────────────
    fail_cnt = 0;

    if (rf_s0 !== 32'h00000001) begin
        $display("[L3-FAIL] s0=0x%08X, expected 0x00000001 (sw/lw 0(a0))", rf_s0);
        fail_cnt = fail_cnt + 1;
    end
    if (rf_s1 !== 32'h00000002) begin
        $display("[L3-FAIL] s1=0x%08X, expected 0x00000002 (sw/lw 16(a0))", rf_s1);
        fail_cnt = fail_cnt + 1;
    end
    if (rf_s2 !== 32'h00000003) begin
        $display("[L3-FAIL] s2=0x%08X, expected 0x00000003 (sw/lw 0x100(a0))", rf_s2);
        fail_cnt = fail_cnt + 1;
    end
    if (rf_s3 !== 32'h00000004) begin
        $display("[L3-FAIL] s3=0x%08X, expected 0x00000004 (sw/lw 0x200(a0))", rf_s3);
        fail_cnt = fail_cnt + 1;
    end

    if (fail_cnt == 0)
        $display("[L3-PASS] DCache miss/hit correct: s0=%0d s1=%0d s2=%0d s3=%0d",
                 rf_s0, rf_s1, rf_s2, rf_s3);
    else
        $display("[L3-FAIL] MISMATCH: %0d register(s) wrong", fail_cnt);

    $finish;
end

// Per-cycle diagnostics for first 120 cycles (critical window)
integer diag_cyc;
initial begin
    diag_cyc = 0;
    begin : diag_block
        forever begin
            @(posedge clk);
            diag_cyc = diag_cyc + 1;
            if (diag_cyc <= 120) begin
                $display("[C%0d] pc=%08X req=%b we=%b rdy=%b awv=%b arv=%b arr=%b rv=%b",
                    diag_cyc, imem_addr,
                    cpu_dcache_req, cpu_dcache_we, cpu_dcache_ready,
                    dc_awvalid, dc_arvalid, dc_arready, dc_rvalid);
            end
            if (diag_cyc >= 120) disable diag_block;
        end
    end
end

// Watchdog — also prints register file values for diagnosis
initial begin
    #4000000; // 400000 cycles @ 10ns — enough margin after halt_cnt fix
    $display("[L3-FAIL] WATCHDOG timeout — DCache or AXI may be stuck");
    $display("[DBG] rf_s0=0x%08X (exp 0x00000001)", rf_s0);
    $display("[DBG] rf_s1=0x%08X (exp 0x00000002)", rf_s1);
    $display("[DBG] rf_s2=0x%08X (exp 0x00000003)", rf_s2);
    $display("[DBG] rf_s3=0x%08X (exp 0x00000004)", rf_s3);
    $finish;
end

endmodule
