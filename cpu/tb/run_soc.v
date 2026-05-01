`timescale 1ns/1ps

`timescale 1ns/1ps
`include "cpu/cpu_core.v"

// ============================================================================
//  run_soc.v  --  Universal Debug Testbench  v3.0
//  Nang cap tu v2.x -> v3.0 voi axi4_crossbar (2M x 4S)
// ============================================================================
//
//  THAY DOI SO VOI v2.x:
//    - Signal taps AXI cu (dcache_awaddr, dcache_wdata_axi, dcache_araddr...)
//      da duoc thay bang M0/M1 cua crossbar
//    - Them tap rieng cho M0 (ICache) va M1 (DCache)
//    - Them tap cho 4 slave ports: S0 IMEM / S1 DMEM / S2 ASCON / S3 SoC Ctrl
//    - Them crossbar internal taps: address decode sel, arbitration FSM state
//    - Them per-slave traffic counters & DECERR trap
//    - Them arbitration conflict detector
//    - DMEM_DUMP_BASE cap nhat = 0x1000_0000 (dia chi DMEM moi)
//
//  DIEU CHINH NHANH:
//    `define LOG_LEVEL   2   // 0=quiet  1=summary  2=events  3=every-cycle
//    `define TIMEOUT     15000
//    `define HALT_STABLE 60
// ============================================================================

// ── Tuning knobs ──────────────────────────────────────────────────────────────
`define LOG_LEVEL       2
`define TIMEOUT         15000
`define HALT_STABLE     60
`define DMEM_DUMP_BASE  32'h10000000   // v3.0: DMEM bat dau 0x1000_0000
`define DMEM_DUMP_WORDS 32
`define DMEM_ROW_WORDS  4
// ─────────────────────────────────────────────────────────────────────────────

module run_soc;

// ============================================================================
// Clock & Reset
// ============================================================================
parameter CLK_PERIOD = 10;   // 10 ns -> 100 MHz
reg clk, rst_n;
initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT
// ============================================================================
wire [31:0] icache_hits, icache_misses;
wire [31:0] dcache_hits, dcache_misses, dcache_writes;

// FIX: fence port để TB flush DCache trước khi đọc DMEM snapshot
reg  soc_dcache_fence;
wire soc_dcache_flush_done;

riscv_soc_top_cached soc (
    .clk                (clk),
    .rst_n              (rst_n),
    .icache_hits        (icache_hits),
    .icache_misses      (icache_misses),
    .dcache_hits        (dcache_hits),
    .dcache_misses      (dcache_misses),
    .dcache_writes      (dcache_writes)
);

// ============================================================================
// ============================================================================
//  SIGNAL TAPS  (tat ca cap nhat theo cpu_core.v v3.0 co crossbar)
// ============================================================================
// ============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// [A] CPU Pipeline
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] pc_if     = soc.cpu.pc_if;
wire [31:0] instr_if  = soc.cpu.instr_if;
wire        stall_if  = soc.cpu.stall_if;

// ─────────────────────────────────────────────────────────────────────────────
// [B] CPU <-> ICache (instruction side)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] ic_cpu_addr  = soc.cpu_imem_addr;
wire        ic_cpu_req   = soc.cpu_imem_valid;
wire [31:0] ic_cpu_rdata = soc.cpu_imem_rdata;
wire        ic_cpu_ready = soc.cpu_imem_ready;

// ─────────────────────────────────────────────────────────────────────────────
// [C] CPU <-> DCache (data side)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] dc_addr  = soc.cpu_dcache_addr;
wire [31:0] dc_wdata = soc.cpu_dcache_wdata;
wire [3:0]  dc_wstrb = soc.cpu_dcache_wstrb;
wire        dc_req   = soc.cpu_dcache_req;
wire        dc_we    = soc.cpu_dcache_we;
wire [31:0] dc_rdata = soc.cpu_dcache_rdata;
wire        dc_ready = soc.cpu_dcache_ready;

// ─────────────────────────────────────────────────────────────────────────────
// [D] M0 (ICache) -> Crossbar  --  AXI4 read-only (ICache khong ghi)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  m0_arid    = soc.m0_arid;
wire [31:0] m0_araddr  = soc.m0_araddr;
wire [7:0]  m0_arlen   = soc.m0_arlen;
wire [2:0]  m0_arsize  = soc.m0_arsize;
wire [1:0]  m0_arburst = soc.m0_arburst;
wire        m0_arvalid = soc.m0_arvalid;
wire        m0_arready = soc.m0_arready;
wire [3:0]  m0_rid     = soc.m0_rid;
wire [31:0] m0_rdata   = soc.m0_rdata;
wire [1:0]  m0_rresp   = soc.m0_rresp;
wire        m0_rlast   = soc.m0_rlast;
wire        m0_rvalid  = soc.m0_rvalid;
wire        m0_rready  = soc.m0_rready;
// (write channel M0 thuong tied-off, lay de bat DECERR neu ICache ghi nham)
wire        m0_awvalid = soc.m0_awvalid;
wire [31:0] m0_awaddr  = soc.m0_awaddr;
wire [1:0]  m0_bresp   = soc.m0_bresp;
wire        m0_bvalid  = soc.m0_bvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [E] M1 (DCache) -> Crossbar  --  AXI4 read + write
// ─────────────────────────────────────────────────────────────────────────────
// Read
wire [3:0]  m1_arid    = soc.m1_arid;
wire [31:0] m1_araddr  = soc.m1_araddr;
wire [7:0]  m1_arlen   = soc.m1_arlen;
wire [2:0]  m1_arsize  = soc.m1_arsize;
wire [1:0]  m1_arburst = soc.m1_arburst;
wire        m1_arvalid = soc.m1_arvalid;
wire        m1_arready = soc.m1_arready;
wire [3:0]  m1_rid     = soc.m1_rid;
wire [31:0] m1_rdata   = soc.m1_rdata;
wire [1:0]  m1_rresp   = soc.m1_rresp;
wire        m1_rlast   = soc.m1_rlast;
wire        m1_rvalid  = soc.m1_rvalid;
wire        m1_rready  = soc.m1_rready;
// Write
wire [3:0]  m1_awid    = soc.m1_awid;
wire [31:0] m1_awaddr  = soc.m1_awaddr;
wire [7:0]  m1_awlen   = soc.m1_awlen;
wire [2:0]  m1_awsize  = soc.m1_awsize;
wire [1:0]  m1_awburst = soc.m1_awburst;
wire        m1_awvalid = soc.m1_awvalid;
wire        m1_awready = soc.m1_awready;
wire [31:0] m1_wdata   = soc.m1_wdata;
wire [3:0]  m1_wstrb   = soc.m1_wstrb;
wire        m1_wlast   = soc.m1_wlast;
wire        m1_wvalid  = soc.m1_wvalid;
wire        m1_wready  = soc.m1_wready;
wire [3:0]  m1_bid     = soc.m1_bid;
wire [1:0]  m1_bresp   = soc.m1_bresp;
wire        m1_bvalid  = soc.m1_bvalid;
wire        m1_bready  = soc.m1_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [F] Crossbar -> S0 (IMEM -- 0x0000_0000)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s0_arid    = soc.s0_arid;
wire [31:0] s0_araddr  = soc.s0_araddr;
wire [7:0]  s0_arlen   = soc.s0_arlen;
wire        s0_arvalid = soc.s0_arvalid;
wire        s0_arready = soc.s0_arready;
wire [3:0]  s0_rid     = soc.s0_rid;
wire [31:0] s0_rdata   = soc.s0_rdata;
wire [1:0]  s0_rresp   = soc.s0_rresp;
wire        s0_rlast   = soc.s0_rlast;
wire        s0_rvalid  = soc.s0_rvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [G] Crossbar -> S1 (DMEM -- 0x1000_0000)
// ─────────────────────────────────────────────────────────────────────────────
wire [3:0]  s1_arid    = soc.s1_arid;
wire [31:0] s1_araddr  = soc.s1_araddr;
wire [7:0]  s1_arlen   = soc.s1_arlen;
wire        s1_arvalid = soc.s1_arvalid;
wire        s1_arready = soc.s1_arready;
wire [3:0]  s1_rid     = soc.s1_rid;
wire [31:0] s1_rdata   = soc.s1_rdata;
wire [1:0]  s1_rresp   = soc.s1_rresp;
wire        s1_rlast   = soc.s1_rlast;
wire        s1_rvalid  = soc.s1_rvalid;
wire [3:0]  s1_awid    = soc.s1_awid;
wire [31:0] s1_awaddr  = soc.s1_awaddr;
wire        s1_awvalid = soc.s1_awvalid;
wire        s1_awready = soc.s1_awready;
wire [31:0] s1_wdata   = soc.s1_wdata;
wire [3:0]  s1_wstrb   = soc.s1_wstrb;
wire        s1_wlast   = soc.s1_wlast;
wire        s1_wvalid  = soc.s1_wvalid;
wire        s1_wready  = soc.s1_wready;
wire [1:0]  s1_bresp   = soc.s1_bresp;
wire        s1_bvalid  = soc.s1_bvalid;
wire        s1_bready  = soc.s1_bready;

// ─────────────────────────────────────────────────────────────────────────────
// [H] Crossbar -> S2 (ASCON -- 0x2000_0000)  &  S3 (SoC Ctrl -- 0x3000_0000)
// ─────────────────────────────────────────────────────────────────────────────
wire [31:0] s2_araddr  = soc.s2_araddr;
wire        s2_arvalid = soc.s2_arvalid;
wire [31:0] s2_awaddr  = soc.s2_awaddr;
wire        s2_awvalid = soc.s2_awvalid;

wire [31:0] s3_araddr  = soc.s3_araddr;
wire        s3_arvalid = soc.s3_arvalid;
wire [31:0] s3_awaddr  = soc.s3_awaddr;
wire        s3_awvalid = soc.s3_awvalid;

// ─────────────────────────────────────────────────────────────────────────────
// [I] Crossbar internal -- address decode result (combinational)
//     sel: 0=S0, 1=S1, 2=S2, 3=S3, 4=DECERR
// ─────────────────────────────────────────────────────────────────────────────
wire [2:0]  xbar_m0_ar_sel = soc.xbar.m0_ar_slave_sel;
wire [2:0]  xbar_m0_aw_sel = soc.xbar.m0_aw_slave_sel;
wire [2:0]  xbar_m1_ar_sel = soc.xbar.m1_ar_slave_sel;
wire [2:0]  xbar_m1_aw_sel = soc.xbar.m1_aw_slave_sel;

// ─────────────────────────────────────────────────────────────────────────────
// [J] Crossbar internal -- arbitration FSM state per slave mux
//     0=IDLE  1=M0 granted  2=M1 granted
// ─────────────────────────────────────────────────────────────────────────────
wire [1:0]  xbar_s0_rd_arb   = soc.xbar.mux_s0.rd_arb;
wire [1:0]  xbar_s0_wr_arb   = soc.xbar.mux_s0.wr_arb;
wire [1:0]  xbar_s1_rd_arb   = soc.xbar.mux_s1.rd_arb;
wire [1:0]  xbar_s1_wr_arb   = soc.xbar.mux_s1.wr_arb;
wire [1:0]  xbar_s2_rd_arb   = soc.xbar.mux_s2.rd_arb;
wire [1:0]  xbar_s3_rd_arb   = soc.xbar.mux_s3.rd_arb;
// Burst-lock flags (arbiter locked khi dang trong burst)
wire        xbar_s0_rd_burst = soc.xbar.mux_s0.rd_burst_active;
wire        xbar_s1_rd_burst = soc.xbar.mux_s1.rd_burst_active;

// ─────────────────────────────────────────────────────────────────────────────
// [K] RAM write tap -- S1 DMEM (data_mem_burst)
// ─────────────────────────────────────────────────────────────────────────────
wire        ram_wr_en   = soc.dmem.dmem.burst_wr_valid;
wire [31:0] ram_wr_addr = soc.dmem.dmem.wr_effective_addr;
wire [31:0] ram_wr_data = soc.dmem.dmem.burst_wr_data;
wire [3:0]  ram_wr_strb = soc.dmem.dmem.burst_wr_strb;

// ─────────────────────────────────────────────────────────────────────────────
// [L] LSU Store Buffer
// ─────────────────────────────────────────────────────────────────────────────
wire        lsu_sb_empty   = soc.cpu.lsu_unit.sb_empty;
wire [2:0]  lsu_sb_count   = soc.cpu.lsu_unit.sb_count[2:0];
wire        lsu_drain_idle = (soc.cpu.lsu_unit.drain_state == 1'b0);

// ============================================================================
// Counters & State
// ============================================================================
integer cycle_count;
integer instr_retired;
integer stall_cycles;
integer flush_cycles;
integer dmem_rd_cnt;
integer dmem_wr_cnt;
integer post_halt_stores;
integer raw_hazard_cnt;
integer sb_cnt;
integer sb_errors;
integer cur_stall_run;
integer max_stall_run;

// Per-master burst counters
integer m0_ar_burst_cnt;     // ICache cache-refill bursts
integer m1_ar_burst_cnt;     // DCache read-refill bursts
integer m1_aw_burst_cnt;     // DCache write-through bursts

// Per-slave traffic counters
integer s0_ar_cnt;           // IMEM reads
integer s1_ar_cnt;           // DMEM reads
integer s1_aw_cnt;           // DMEM writes
integer s2_access_cnt;       // ASCON accesses (ar+aw, count per-handshake)
integer s3_access_cnt;       // SoC Ctrl accesses
integer decerr_cnt;          // RRESP or BRESP == 2'b11

// Crossbar arbitration conflict counter
integer xbar_conflict_cnt;

// AXI latency tracking
integer m0_ar_start;
integer m1_ar_start;
integer m1_aw_start;
integer m0_rd_lat_sum, m0_rd_lat_cnt;
integer m1_rd_lat_sum, m1_rd_lat_cnt;
integer m1_wr_lat_sum, m1_wr_lat_cnt;

// Halt detection
reg [31:0] prev_pc;
integer    halt_cnt;
reg        program_done;

// PC ring buffer
reg [31:0] pc_ring [0:7];
integer    ring_ptr;
integer    match2, match3, match4;

// Scoreboard
reg [31:0] sb_addr [0:255];
reg [31:0] sb_data [0:255];

// ============================================================================
// Waveform dump
// ============================================================================
initial begin
    $dumpfile("waveform_soc.vcd");
    $dumpvars(0, run_soc);
end

// ============================================================================
// (1) Cycle Counter
// ============================================================================
always @(posedge clk) begin
    if (rst_n) cycle_count = cycle_count + 1;
end

// ============================================================================
// (2) Instruction Retire & Stall
// NOTE: dem ca NOP (0x00000013) vi day la instruction hop le.
//       Chi bo qua bubble (32'h0 = gia tri reset cua pipeline register).
// ============================================================================
reg prev_stall;
always @(posedge clk) begin
    if (!rst_n) begin
        prev_stall <= 0;
    end else begin
        // Retire: bat ky instruction hop le, khong stall, khong phai bubble
        if (!stall_if && instr_if !== 32'h0)
            instr_retired = instr_retired + 1;

        // Stall tracking
        if (stall_if) begin
            stall_cycles  = stall_cycles + 1;
            cur_stall_run = cur_stall_run + 1;
            if (cur_stall_run > max_stall_run) max_stall_run = cur_stall_run;
        end else begin
            cur_stall_run = 0;
        end

        if (`LOG_LEVEL >= 3 && instr_if !== 32'h0)
            $display("[%6d] PC=0x%08h  INSTR=0x%08h%s",
                     cycle_count, pc_if, instr_if,
                     stall_if ? "  [STALL]" : "");

        prev_stall <= stall_if;
    end
end

// ============================================================================
// (3) DCache Load/Store Logger
// ============================================================================
always @(posedge clk) begin
    if (rst_n && dc_req && dc_ready) begin
        if (dc_we) begin
            if (!program_done) begin
                dmem_wr_cnt = dmem_wr_cnt + 1;
                sb_update(dc_addr, dc_wdata, dc_wstrb);
                if (`LOG_LEVEL >= 2)
                    $display("[%6d] [ST] addr=0x%08h  data=0x%08h  strb=%b",
                             cycle_count, dc_addr, dc_wdata, dc_wstrb);
            end else begin
                post_halt_stores = post_halt_stores + 1;
                if (`LOG_LEVEL >= 2)
                    $display("[%6d] [ST-DRAIN] addr=0x%08h  data=0x%08h",
                             cycle_count, dc_addr, dc_wdata);
            end
        end else begin
            dmem_rd_cnt = dmem_rd_cnt + 1;
            sb_check(dc_addr, dc_rdata);
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [LD] addr=0x%08h  data=0x%08h",
                         cycle_count, dc_addr, dc_rdata);
        end
    end
end

// ============================================================================
// (4) M0 (ICache) AXI Channel Logger  --  v3.0: qua crossbar toi S0 IMEM
// ============================================================================
// Luu ar_start bang reg de tranh same-cycle update lam lat = 0
reg [31:0] m0_ar_addr_lat;   // dia chi cua burst dang theo doi
always @(posedge clk) begin
    if (rst_n) begin
        // AR handshake
        if (m0_arvalid && m0_arready) begin
            m0_ar_burst_cnt = m0_ar_burst_cnt + 1;
            m0_ar_start     = cycle_count;
            m0_ar_addr_lat  <= m0_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M0-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m0_araddr, m0_arlen,
                         xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel));
            // Canh bao ICache doc ngoai S0
            if (xbar_m0_ar_sel !== 3'd0 && `LOG_LEVEL >= 1)
                $display("[%6d] [WARN] M0(ICache) AR -> S%0d(%s) instead of S0(IMEM)!",
                         cycle_count, xbar_m0_ar_sel, slave_name(xbar_m0_ar_sel));
        end
        // R beat
        if (m0_rvalid && m0_rready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M0-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m0_rdata, m0_rresp,
                         m0_rlast ? "  [LAST]" : "");
            // Latency = cycle_count - m0_ar_start (ar_start da duoc ghi truoc do)
            if (m0_rlast) begin
                m0_rd_lat_sum = m0_rd_lat_sum + (cycle_count - m0_ar_start + 1);
                m0_rd_lat_cnt = m0_rd_lat_cnt + 1;
            end
            // DECERR trap
            if (m0_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR  M0 READ   addr=0x%08h  sel=%0d",
                         cycle_count, m0_ar_addr_lat, xbar_m0_ar_sel);
            end
        end
        // ICache nham ghi -> DECERR tren B channel
        if (m0_bvalid && m0_bresp == 2'b11) begin
            decerr_cnt = decerr_cnt + 1;
            $display("[%6d] [!!!] DECERR  M0 WRITE  addr=0x%08h  (ICache should not write!)",
                     cycle_count, m0_awaddr);
        end
    end
end

// ============================================================================
// (5) M1 (DCache) AXI Channel Logger  --  v3.0: qua crossbar toi S1 DMEM
// ============================================================================
reg [31:0] m1_ar_addr_saved;  // luu lai de dung khi RLAST
reg [31:0] m1_aw_addr_saved;
always @(posedge clk) begin
    if (rst_n) begin
        // AR handshake
        if (m1_arvalid && m1_arready) begin
            m1_ar_burst_cnt  = m1_ar_burst_cnt + 1;
            m1_ar_start      = cycle_count;
            m1_ar_addr_saved <= m1_araddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AR] addr=0x%08h  len=%0d  -> S%0d(%s)",
                         cycle_count, m1_araddr, m1_arlen,
                         xbar_m1_ar_sel, slave_name(xbar_m1_ar_sel));
            // Canh bao DCache doc nham S0(IMEM) -- thuong la linker dung dia chi cu
            if (xbar_m1_ar_sel == 3'd0)
                $display("[%6d] [WARN] M1(DCache) AR -> S0(IMEM)! addr=0x%08h -- dia chi sai? (DMEM = 0x1000_0000)",
                         cycle_count, m1_araddr);
        end
        // R beat
        if (m1_rvalid && m1_rready) begin
            if (`LOG_LEVEL >= 3)
                $display("[%6d] [M1-R ] data=0x%08h  rresp=%0d%s",
                         cycle_count, m1_rdata, m1_rresp,
                         m1_rlast ? "  [LAST]" : "");
            if (m1_rlast) begin
                m1_rd_lat_sum = m1_rd_lat_sum + (cycle_count - m1_ar_start + 1);
                m1_rd_lat_cnt = m1_rd_lat_cnt + 1;
            end
            if (m1_rresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR  M1 READ   addr=0x%08h  sel=%0d",
                         cycle_count, m1_ar_addr_saved, xbar_m1_ar_sel);
            end
        end
        // AW handshake
        if (m1_awvalid && m1_awready) begin
            m1_aw_burst_cnt  = m1_aw_burst_cnt + 1;
            m1_aw_start      = cycle_count;
            m1_aw_addr_saved <= m1_awaddr;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-AW] addr=0x%08h  -> S%0d(%s)",
                         cycle_count, m1_awaddr,
                         xbar_m1_aw_sel, slave_name(xbar_m1_aw_sel));
            if (xbar_m1_aw_sel == 3'd0)
                $display("[%6d] [WARN] M1(DCache) AW -> S0(IMEM)! addr=0x%08h -- dia chi sai?",
                         cycle_count, m1_awaddr);
        end
        // W beat
        if (m1_wvalid && m1_wready && `LOG_LEVEL >= 3)
            $display("[%6d] [M1-W ] data=0x%08h  strb=%b%s",
                     cycle_count, m1_wdata, m1_wstrb,
                     m1_wlast ? "  [LAST]" : "");
        // B response
        if (m1_bvalid && m1_bready) begin
            m1_wr_lat_sum = m1_wr_lat_sum + (cycle_count - m1_aw_start + 1);
            m1_wr_lat_cnt = m1_wr_lat_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d] [M1-B ] bresp=%0d  lat=%0d cyc",
                         cycle_count, m1_bresp, cycle_count - m1_aw_start + 1);
            if (m1_bresp == 2'b11) begin
                decerr_cnt = decerr_cnt + 1;
                $display("[%6d] [!!!] DECERR  M1 WRITE  addr=0x%08h  sel=%0d",
                         cycle_count, m1_awaddr, xbar_m1_aw_sel);
            end
        end
    end
end

// ============================================================================
// (6) Per-Slave Traffic Counter + S2/S3 Alert
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        if (s0_arvalid && s0_arready) s0_ar_cnt = s0_ar_cnt + 1;
        if (s1_arvalid && s1_arready) s1_ar_cnt = s1_ar_cnt + 1;
        if (s1_awvalid && s1_awready) s1_aw_cnt = s1_aw_cnt + 1;

        // S2 ASCON
        if (s2_arvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [ASCON] READ   addr=0x%08h", cycle_count, s2_araddr);
        end
        if (s2_awvalid) begin
            s2_access_cnt = s2_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [ASCON] WRITE  addr=0x%08h", cycle_count, s2_awaddr);
        end

        // S3 SoC Ctrl
        if (s3_arvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [SOC_CTRL] READ   addr=0x%08h", cycle_count, s3_araddr);
        end
        if (s3_awvalid) begin
            s3_access_cnt = s3_access_cnt + 1;
            if (`LOG_LEVEL >= 1)
                $display("[%6d] [SOC_CTRL] WRITE  addr=0x%08h", cycle_count, s3_awaddr);
        end
    end
end

// ============================================================================
// (7) Crossbar Arbitration Conflict Detector
//     Khi M0 va M1 cung muon doc/ghi 1 slave cung luc -> M0 thang (fixed prio)
// ============================================================================
always @(posedge clk) begin
    if (rst_n && `LOG_LEVEL >= 2) begin
        // S0 read conflict
        if (m0_arvalid && !m0_arready &&
            m1_arvalid && (xbar_m1_ar_sel == xbar_m0_ar_sel) &&
            xbar_s0_rd_arb == 2'd1) begin
            xbar_conflict_cnt = xbar_conflict_cnt + 1;
            $display("[%6d] [ARB] S%0d RD conflict: M0=0x%08h M1=0x%08h  M1 stalled",
                     cycle_count, xbar_m0_ar_sel, m0_araddr, m1_araddr);
        end
        // S1 write conflict
        if (m1_awvalid && !m1_awready &&
            xbar_s1_wr_arb != 2'd0) begin
            xbar_conflict_cnt = xbar_conflict_cnt + 1;
            $display("[%6d] [ARB] S1 WR stall: M1=0x%08h  arb_state=%0d",
                     cycle_count, m1_awaddr, xbar_s1_wr_arb);
        end
    end
end

// ============================================================================
// (8) Halt / Loop Detection
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        halt_cnt <= 0; ring_ptr <= 0;
        match2 <= 0; match3 <= 0; match4 <= 0;
    end else if (cycle_count > 30) begin

        // Single-cycle halt (j halt)
        if (pc_if === prev_pc && instr_if !== 32'h00000013) begin
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= `HALT_STABLE && !program_done) begin
                program_done = 1;
                print_report("HALT LOOP");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else begin
            halt_cnt <= 0;
        end

        // 2-cycle loop
        if (pc_if === pc_ring[(ring_ptr + 6) % 8]) begin
            match2 = match2 + 1;
            if (match2 >= 16 && !program_done) begin
                program_done = 1;
                print_report("2-CYCLE LOOP");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else match2 = 0;

        // 4-cycle loop
        if (pc_if === pc_ring[(ring_ptr + 4) % 8]) begin
            match4 = match4 + 1;
            if (match4 >= 24 && !program_done) begin
                program_done = 1;
                print_report("4-CYCLE LOOP");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else match4 = 0;

        pc_ring[ring_ptr] <= pc_if;
        ring_ptr <= (ring_ptr + 1) % 8;
        prev_pc  <= pc_if;
    end
end

// ============================================================================
// (9) Watchdog
// ============================================================================
initial begin
    #(CLK_PERIOD * `TIMEOUT);
    if (!program_done) begin
        program_done = 1;
        print_report("TIMEOUT");
    end
    $finish;
end

// ============================================================================
// Main Sequence
// ============================================================================
integer i;
initial begin
    // Init all counters
    cycle_count       = 0;   instr_retired    = 0;
    stall_cycles      = 0;   flush_cycles     = 0;
    dmem_rd_cnt       = 0;   dmem_wr_cnt      = 0;
    post_halt_stores  = 0;   raw_hazard_cnt   = 0;
    sb_cnt            = 0;   sb_errors        = 0;
    cur_stall_run     = 0;   max_stall_run    = 0;
    program_done      = 0;   prev_pc          = 0;
    halt_cnt          = 0;   ring_ptr         = 0;
    soc_dcache_fence  = 0;
    match2 = 0; match3 = 0; match4 = 0;
    // AXI
    m0_ar_burst_cnt   = 0;
    m1_ar_burst_cnt   = 0;   m1_aw_burst_cnt  = 0;
    s0_ar_cnt         = 0;
    s1_ar_cnt         = 0;   s1_aw_cnt        = 0;
    s2_access_cnt     = 0;   s3_access_cnt    = 0;
    decerr_cnt        = 0;   xbar_conflict_cnt= 0;
    m0_ar_start       = 0;
    m1_ar_start       = 0;   m1_aw_start      = 0;
    m0_rd_lat_sum     = 0;   m0_rd_lat_cnt    = 0;
    m1_rd_lat_sum     = 0;   m1_rd_lat_cnt    = 0;
    m1_wr_lat_sum     = 0;   m1_wr_lat_cnt    = 0;

    for (i = 0; i < 256; i = i + 1) begin sb_addr[i] = 0; sb_data[i] = 0; end
    for (i = 0; i < 8;   i = i + 1) pc_ring[i] = 0;

    print_banner();

    rst_n = 0;
    repeat(12) @(posedge clk);
    rst_n = 1;
    repeat(5)  @(posedge clk);

    if (`LOG_LEVEL >= 1)
        $display("[%6d] Execution started\n", cycle_count);

    wait(program_done);
end

// ============================================================================
// SCOREBOARD TASKS
// ============================================================================
task sb_update;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    reg [31:0] al;
    integer    idx, found;
    reg [31:0] merged;
    begin
        al = {addr[31:2], 2'b00}; found = -1;
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al) found = idx;
        merged = (found >= 0) ? sb_data[found] : 32'h0;
        if (strb[0]) merged[ 7: 0] = data[ 7: 0];
        if (strb[1]) merged[15: 8] = data[15: 8];
        if (strb[2]) merged[23:16] = data[23:16];
        if (strb[3]) merged[31:24] = data[31:24];
        if (found >= 0) sb_data[found] = merged;
        else if (sb_cnt < 256) begin
            sb_addr[sb_cnt] = al; sb_data[sb_cnt] = merged;
            sb_cnt = sb_cnt + 1;
        end
    end
endtask

task sb_check;
    input [31:0] addr;
    input [31:0] got;
    reg [31:0] al;
    integer idx;
    begin
        al = {addr[31:2], 2'b00};
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al && sb_data[idx] !== got) begin
                sb_errors = sb_errors + 1;
                $display("[%6d] [ERR-RAW] addr=0x%08h  exp=0x%08h  got=0x%08h",
                         cycle_count, al, sb_data[idx], got);
            end
    end
endtask

// ============================================================================
// PRINT TASKS
// ============================================================================

task print_banner;
    begin
        $display("");
        $display("+=================================================================+");
        $display("|   RISC-V SoC v3.0  --  Universal Debug Testbench               |");
        $display("|   ICache 4KB | DCache 8KB | AXI4 Crossbar 2Mx4S | 100 MHz      |");
        $display("+-----------------------------------------------------------------+");
        $display("|   Address Map:                                                  |");
        $display("|     S0  IMEM     0x0000_0000 - 0x0000_FFFF  (64 KB)            |");
        $display("|     S1  DMEM     0x1000_0000 - 0x1000_FFFF  (64 KB)            |");
        $display("|     S2  ASCON    0x2000_0000 - 0x2000_0FFF  ( 4 KB)            |");
        $display("|     S3  SoCCtrl  0x3000_0000 - 0x3000_0FFF  ( 4 KB)            |");
        $display("|     --   other  -> DECERR (RDATA=0xDEAD_BEEF)                  |");
        $display("+-----------------------------------------------------------------+");
        $display("|   LOG_LEVEL=%0d   TIMEOUT=%0d cyc   HALT_STABLE=%0d cyc          |",
                 `LOG_LEVEL, `TIMEOUT, `HALT_STABLE);
        $display("+=================================================================+");
        $display("");
    end
endtask

// ─────────────────────────────────────────────────────────────────────────────
task print_report;
    input [127:0] reason;
    integer j, k, nz;
    real cpi, ipc, eff, ic_rate, dc_rate;
    integer ic_total, dc_total;
    reg [31:0] ret, wv;
    begin
        ret = soc.cpu.register_file.registers[10]; // a0

        $display("");
        $display("+=================================================================+");
        $display("|  STOP: %-57s|", reason);
        $display("+=================================================================+");

        // ── (1) PROGRAM RESULT ────────────────────────────────────────────────
        $display("");
        $display("+--- (1) PROGRAM RESULT -----------------------------------------+");
        $display("|  a0 (x10) = 0x%08h  =  %0d  (signed: %0d)",
                 ret, ret, $signed(ret));
        $display("|  Binary   = %032b", ret);
        if (ret === 32'h0)
            $display("|  ALL TESTS PASS  (a0 == 0)");
        else begin
            $display("|  FAIL BITMASK:");
            if (ret[0]) $display("|    bit0 = TEST 1 FAIL  (basic word r/w)");
            if (ret[1]) $display("|    bit1 = TEST 2 FAIL  (halfword)");
            if (ret[2]) $display("|    bit2 = TEST 3 FAIL  (byte + endian)");
            if (ret[3]) $display("|    bit3 = TEST 4 FAIL  (sequential)");
            if (ret[4]) $display("|    bit4 = TEST 5 FAIL  (stride/miss)");
            if (ret[5]) $display("|    bit5 = TEST 6 FAIL  (ASCON block)");
            if (ret[6]) $display("|    bit6 = TEST 7 FAIL  (RAW hazard)");
            if (ret[7]) $display("|    bit7 = TEST 8 FAIL  (boundary)");
        end
        $display("|  Final PC = 0x%08h", pc_if);
        $display("+----------------------------------------------------------------+");

        // ── (2) PERFORMANCE ───────────────────────────────────────────────────
        $display("");
        $display("+--- (2) PERFORMANCE --------------------------------------------+");
        if (instr_retired > 0) begin
            cpi = cycle_count * 1.0 / instr_retired;
            ipc = instr_retired * 1.0 / cycle_count;
            eff = ipc * 100.0;
            $display("|  Cycles        : %0d", cycle_count);
            $display("|  Instructions  : %0d", instr_retired);
            $display("|  CPI           : %.3f  (ideal = 1.000)", cpi);
            $display("|  IPC           : %.3f  (ideal = 1.000)", ipc);
            $display("|  Pipeline eff  : %.1f%%", eff);
            $display("|  Stall cycles  : %0d  (%.1f%%)",
                     stall_cycles, stall_cycles * 100.0 / cycle_count);
            $display("|  Max stall run : %0d cycles", max_stall_run);
            if      (eff >= 90.0) $display("|  Rating : ***** EXCELLENT  (>=90%%)");
            else if (eff >= 75.0) $display("|  Rating : ****  GOOD       (>=75%%)");
            else if (eff >= 55.0) $display("|  Rating : ***   FAIR       (>=55%%)");
            else                  $display("|  Rating : **    NEEDS WORK (<55%%)");
        end else
            $display("|  No instructions retired.");
        $display("+----------------------------------------------------------------+");

        // ── (3) CACHE STATISTICS ──────────────────────────────────────────────
        $display("");
        $display("+--- (3) CACHE STATISTICS ---------------------------------------+");
        ic_total = icache_hits + icache_misses;
        dc_total = dcache_hits + dcache_misses;
        ic_rate  = (ic_total > 0) ? icache_hits * 100.0 / ic_total : 0.0;
        dc_rate  = (dc_total > 0) ? dcache_hits * 100.0 / dc_total : 0.0;
        $display("|  ICache : hits=%-6d  misses=%-6d  hit%%=%.1f%%",
                 icache_hits, icache_misses, ic_rate);
        $display("|  DCache : hits=%-6d  misses=%-6d  hit%%=%.1f%%  writes=%0d",
                 dcache_hits, dcache_misses, dc_rate, dcache_writes);
        if (m0_rd_lat_cnt > 0)
            $display("|  ICache refill avg lat : %.1f cyc  (%0d bursts)",
                     m0_rd_lat_sum * 1.0 / m0_rd_lat_cnt, m0_rd_lat_cnt);
        if (m1_rd_lat_cnt > 0)
            $display("|  DCache refill avg lat : %.1f cyc  (%0d bursts)",
                     m1_rd_lat_sum * 1.0 / m1_rd_lat_cnt, m1_rd_lat_cnt);
        if (m1_wr_lat_cnt > 0)
            $display("|  DCache write avg lat  : %.1f cyc  (%0d bursts)",
                     m1_wr_lat_sum * 1.0 / m1_wr_lat_cnt, m1_wr_lat_cnt);
        if      (ic_rate >= 95.0) $display("|  ICache : ***** EXCELLENT");
        else if (ic_rate >= 80.0) $display("|  ICache : ****  GOOD");
        else                      $display("|  ICache : **    COLD/POOR");
        if      (dc_rate >= 95.0) $display("|  DCache : ***** EXCELLENT");
        else if (dc_rate >= 80.0) $display("|  DCache : ****  GOOD");
        else                      $display("|  DCache : **    COLD/POOR");
        $display("+----------------------------------------------------------------+");

        // ── (4) AXI4 CROSSBAR TRAFFIC ─────────────────────────────────────────
        $display("");
        $display("+--- (4) AXI4 CROSSBAR TRAFFIC ----------------------------------+");
        $display("|  Master 0 (ICache)  :  AR bursts = %0d", m0_ar_burst_cnt);
        $display("|  Master 1 (DCache)  :  AR bursts = %0d   AW bursts = %0d",
                 m1_ar_burst_cnt, m1_aw_burst_cnt);
        $display("|  Slave 0  IMEM      :  AR = %0d", s0_ar_cnt);
        $display("|  Slave 1  DMEM      :  AR = %0d   AW = %0d", s1_ar_cnt, s1_aw_cnt);
        $display("|  Slave 2  ASCON     :  accesses = %0d", s2_access_cnt);
        $display("|  Slave 3  SoC Ctrl  :  accesses = %0d", s3_access_cnt);
        $display("|  Arb conflicts      :  %0d", xbar_conflict_cnt);
        if (decerr_cnt > 0)
            $display("|  [!!!] DECERR count :  %0d  <- unmapped address!", decerr_cnt);
        else
            $display("|  DECERR count       :  0  (OK)");
        $display("+----------------------------------------------------------------+");

        // ── (5) MEMORY ACCESS SUMMARY ─────────────────────────────────────────
        $display("");
        $display("+--- (5) MEMORY ACCESS SUMMARY ----------------------------------+");
        $display("|  CPU Loads           : %0d", dmem_rd_cnt);
        $display("|  CPU Stores          : %0d", dmem_wr_cnt);
        $display("|  Post-halt SB drain  : %0d stores", post_halt_stores);
        $display("|  RAW hazard errors   : %0d  %s",
                 sb_errors, sb_errors == 0 ? "(OK)" : "[!!!] DATA ERRORS");
        $display("|  Scoreboard entries  : %0d", sb_cnt);
        $display("|  LSU SB remaining    : %0d entries at halt", lsu_sb_count);
        $display("+----------------------------------------------------------------+");

        // ── (6) REGISTER FILE ─────────────────────────────────────────────────
        $display("");
        $display("+--- (6) REGISTER FILE ------------------------------------------+");
        $display("|  Reg   ABI     Hex          Decimal (signed)");
        $display("|  -----------------------------------------");
        nz = 0;
        for (j = 0; j < 32; j = j + 1) begin
            wv = soc.cpu.register_file.registers[j];
            if (wv !== 32'h0 || j == 2 || j == 10) begin
                nz = nz + 1;
                $display("|  x%-2d  %-5s   0x%08h   %0d",
                         j, abi_name(j), wv, $signed(wv));
            end
        end
        if (nz == 0) $display("|  (all zero)");
        $display("+----------------------------------------------------------------+");

        // ── (7) DMEM SNAPSHOT ─────────────────────────────────────────────────
        flush_dcache();
        print_dmem_snapshot();

        // ── (8) SCOREBOARD DUMP ───────────────────────────────────────────────
        $display("");
        $display("+--- (8) STORE SCOREBOARD (%0d entries, %0d errors) ---------------+",
                 sb_cnt, sb_errors);
        k = 0;
        for (j = 0; j < sb_cnt && j < 48; j = j + 1) begin
            if (sb_data[j] !== 32'h0) begin
                $display("|  [0x%08h] = 0x%08h  (%0d)",
                         sb_addr[j], sb_data[j], sb_data[j]);
                k = k + 1;
            end
        end
        if (k == 0) $display("|  (no non-zero stores recorded)");
        if (sb_cnt > 48) $display("|  ... (%0d more entries)", sb_cnt - 48);
        $display("+----------------------------------------------------------------+");

        // ── FOOTER ────────────────────────────────────────────────────────────
        $display("");
        $display("=================================================================");
        $display("  SoC v3.0 done.  %0d cycles @ 100 MHz = %.2f us",
                 cycle_count, cycle_count * 10.0 / 1000.0);
        $display("=================================================================");
        $display("");
    end
endtask

// ─────────────────────────────────────────────────────────────────────────────
// Task: flush_dcache
//   Assert dcache_fence=1 qua SoC port, doi flush_done=1
// ─────────────────────────────────────────────────────────────────────────────
task flush_dcache;
    integer timeout_cnt;
    begin
        if (`LOG_LEVEL >= 1)
            $display("[%6d] [FLUSH] Asserting DCache fence to flush dirty lines...", cycle_count);
        soc_dcache_fence = 1'b1;
        @(posedge clk); #1;
        soc_dcache_fence = 1'b0;
        timeout_cnt = 0;
        while (!soc_dcache_flush_done && timeout_cnt < 2000) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end
        repeat(10) @(posedge clk);
        if (timeout_cnt >= 2000)
            $display("[%6d] [WARN] DCache flush TIMEOUT!", cycle_count);
        else if (`LOG_LEVEL >= 1)
            $display("[%6d] [FLUSH] DCache flush done (%0d cycles)", cycle_count, timeout_cnt);
    end
endtask
            reg [31:0] word_addr;
            reg [7:0]  byte_val;
            reg [1:0]  byte_off;
            integer    k;
task print_dmem_snapshot;
    integer wi, col, j;
    reg [31:0] base, addr, wval;
    reg        found;
    begin
        base = `DMEM_DUMP_BASE;
        $display("");
        $display("+--- (7) DMEM SNAPSHOT [0x%08h..0x%08h] (%0d words) -----------+",
                 base, base + `DMEM_DUMP_WORDS * 4 - 1, `DMEM_DUMP_WORDS);
        $display("|  (source: TB Scoreboard — DCache not flushed)");
        $display("|  Address       +0          +4          +8          +C");
        $display("|  ---------------------------------------------------------");

        for (wi = 0; wi < `DMEM_DUMP_WORDS; wi = wi + `DMEM_ROW_WORDS) begin
            addr = base + wi * 4;
            $write("|  0x%08h  ", addr);
            for (col = 0; col < `DMEM_ROW_WORDS; col = col + 1) begin
                // Tìm trong scoreboard
                wval = 32'h0; found = 0;
                for (j = 0; j < sb_cnt; j = j + 1) begin
                    if (sb_addr[j] === (base + (wi + col) * 4)) begin
                        wval  = sb_data[j];
                        found = 1;
                    end
                end
                $write("0x%08h  ", wval);
            end
            $display("");
        end

        // ASCII view từ scoreboard
        $display("|");
        $display("|  ASCII view (from scoreboard):");
        $write("|  ");
        for (wi = 0; wi < `DMEM_DUMP_WORDS * 4; wi = wi + 1) begin

            word_addr = base + (wi / 4) * 4;
            byte_off  = wi[1:0];
            byte_val  = 8'h2E; // default '.'
            for (k = 0; k < sb_cnt; k = k + 1) begin
                if (sb_addr[k] === word_addr) begin
                    case (byte_off)
                        2'd0: byte_val = sb_data[k][ 7: 0];
                        2'd1: byte_val = sb_data[k][15: 8];
                        2'd2: byte_val = sb_data[k][23:16];
                        2'd3: byte_val = sb_data[k][31:24];
                    endcase
                end
            end
            if (byte_val >= 8'h20 && byte_val <= 8'h7E) $write("%s", byte_val);
            else                                          $write(".");
            if ((wi & 15) == 15 && wi < `DMEM_DUMP_WORDS*4-1) begin
                $display(""); $write("|  ");
            end
        end
        $display("");
        $display("+----------------------------------------------------------------+");
    end
endtask

// ─────────────────────────────────────────────────────────────────────────────
// Slave name lookup  (dung trong $display inline)
function [63:0] slave_name;
    input [2:0] sel;
    begin
        case (sel)
            3'd0:    slave_name = "IMEM    ";
            3'd1:    slave_name = "DMEM    ";
            3'd2:    slave_name = "ASCON   ";
            3'd3:    slave_name = "SoCCtrl ";
            default: slave_name = "DECERR  ";
        endcase
    end
endfunction

// ─────────────────────────────────────────────────────────────────────────────
// ABI register name lookup
function [39:0] abi_name;
    input integer r;
    begin
        case (r)
            0:  abi_name = "zero ";   1:  abi_name = "ra   ";
            2:  abi_name = "sp   ";   3:  abi_name = "gp   ";
            4:  abi_name = "tp   ";   5:  abi_name = "t0   ";
            6:  abi_name = "t1   ";   7:  abi_name = "t2   ";
            8:  abi_name = "s0/fp";   9:  abi_name = "s1   ";
            10: abi_name = "a0   ";   11: abi_name = "a1   ";
            12: abi_name = "a2   ";   13: abi_name = "a3   ";
            14: abi_name = "a4   ";   15: abi_name = "a5   ";
            16: abi_name = "a6   ";   17: abi_name = "a7   ";
            18: abi_name = "s2   ";   19: abi_name = "s3   ";
            20: abi_name = "s4   ";   21: abi_name = "s5   ";
            22: abi_name = "s6   ";   23: abi_name = "s7   ";
            24: abi_name = "s8   ";   25: abi_name = "s9   ";
            26: abi_name = "s10  ";   27: abi_name = "s11  ";
            28: abi_name = "t3   ";   29: abi_name = "t4   ";
            30: abi_name = "t5   ";   31: abi_name = "t6   ";
            default: abi_name = "???  ";
        endcase
    end
endfunction

endmodule