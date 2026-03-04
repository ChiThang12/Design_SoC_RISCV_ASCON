`timescale 1ns/1ps
`include "cpu/cpu_core.v"

// ============================================================================
//  run_soc.v  —  Universal Debug Testbench  (RISC-V SoC + ICache + DCache)
// ============================================================================
//
//  TÍNH NĂNG:
//    ► Tự động detect halt loop & in kết quả cuối
//    ► Live PC trace (mỗi N cycle in 1 dòng)
//    ► Pipeline event log: stall, flush, hazard
//    ► Memory snapshot: in nội dung DMEM theo vùng địa chỉ
//    ► Scoreboard read-after-write: ghi log mỗi store/load
//    ► Register file diff: so sánh trước/sau từng đoạn test
//    ► Cache event: mỗi hit/miss đều được log
//    ► Performance dashboard: CPI, IPC, throughput, hit rate
//    ► Tự nhận diện loại chương trình: a+b, memory test, ASCON…
//
//  ĐIỀU CHỈNH NHANH (đầu file):
//    `define LOG_LEVEL  2    // 0=quiet 1=normal 2=verbose 3=trace
//    `define MEM_DUMP_BASE   // Địa chỉ đầu vùng in DMEM
//    `define MEM_DUMP_WORDS  // Số words cần in
//    `define TIMEOUT    10000
// ============================================================================

// ── Tuning knobs ─────────────────────────────────────────────────────────────
`define LOG_LEVEL       2       // 0=quiet 1=summary 2=events 3=every-cycle
`define TIMEOUT         15000   // cycles tối đa
`define HALT_STABLE     60      // số cycles PC bất động → halt
`define DMEM_BASE       32'h00001000   // đầu vùng RAM (theo linker)
`define DMEM_DUMP_BASE  32'h00001100   // đầu vùng print
`define DMEM_DUMP_WORDS 32             // số 32-bit words cần dump
`define DMEM_ROW_WORDS  4              // words mỗi hàng khi in
// ─────────────────────────────────────────────────────────────────────────────

module run_soc;

// ============================================================================
// Parameters & Timings
// ============================================================================
parameter CLK_PERIOD = 10;     // 10 ns → 100 MHz

// ============================================================================
// Clock & Reset
// ============================================================================
reg clk, rst_n;
initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT
// ============================================================================
wire [31:0] icache_hits, icache_misses;
wire [31:0] dcache_hits, dcache_misses, dcache_writes;

riscv_soc_top_cached soc (
    .clk           (clk),
    .rst_n         (rst_n),
    .icache_hits   (icache_hits),
    .icache_misses (icache_misses),
    .dcache_hits   (dcache_hits),
    .dcache_misses (dcache_misses),
    .dcache_writes (dcache_writes)
);

// ============================================================================
// Signal Taps
// ============================================================================

// ── CPU Pipeline ─────────────────────────────────────────────────────────────
wire [31:0] pc_if     = soc.cpu.pc_if;
wire [31:0] instr_if  = soc.cpu.instr_if;
wire        stall_if  = soc.cpu.stall_if;

// ── DCache ↔ CPU interface ───────────────────────────────────────────────────
wire [31:0] dc_addr   = soc.cpu_dcache_addr;
wire [31:0] dc_wdata  = soc.cpu_dcache_wdata;
wire [3:0]  dc_wstrb  = soc.cpu_dcache_wstrb;
wire        dc_req    = soc.cpu_dcache_req;
wire        dc_we     = soc.cpu_dcache_we;
wire [31:0] dc_rdata  = soc.cpu_dcache_rdata;
wire        dc_ready  = soc.cpu_dcache_ready;

// ── AXI Write (DCache → DMEM) ────────────────────────────────────────────────
wire [31:0] axi_awaddr  = soc.dcache_awaddr;
wire        axi_awvalid = soc.dcache_awvalid;
wire        axi_awready = soc.dcache_awready;
wire [31:0] axi_wdata   = soc.dcache_wdata_axi;
wire [3:0]  axi_wstrb   = soc.dcache_wstrb_axi;
wire        axi_wvalid  = soc.dcache_wvalid;
wire        axi_wready  = soc.dcache_wready;
wire        axi_wlast   = soc.dcache_wlast;
wire        axi_bvalid  = soc.dcache_bvalid;
wire        axi_bready  = soc.dcache_bready;

// ── AXI Read (DCache → DMEM) ─────────────────────────────────────────────────
wire [31:0] axi_araddr  = soc.dcache_araddr;
wire        axi_arvalid = soc.dcache_arvalid;
wire        axi_arready = soc.dcache_arready;
wire [31:0] axi_rdata   = soc.dcache_rdata;
wire        axi_rvalid  = soc.dcache_rvalid;
wire        axi_rready  = soc.dcache_rready;
wire        axi_rlast   = soc.dcache_rlast;

// ── RAM array tap (data_mem_burst) ──────────────────────────────────────────
wire        ram_wr_en   = soc.dmem.dmem.burst_wr_valid;
wire [31:0] ram_wr_addr = soc.dmem.dmem.wr_effective_addr;
wire [31:0] ram_wr_data = soc.dmem.dmem.burst_wr_data;
wire [3:0]  ram_wr_strb = soc.dmem.dmem.burst_wr_strb;

// ── Store Buffer drain tap (LSU internal) ────────────────────────────────────
wire        lsu_sb_empty   = soc.cpu.lsu_unit.sb_empty;
wire [2:0]  lsu_sb_count   = soc.cpu.lsu_unit.sb_count[2:0];
wire        lsu_drain_idle = (soc.cpu.lsu_unit.drain_state == 1'b0);

// ============================================================================
// Counters & State
// ============================================================================
integer cycle_count;
integer instr_retired;         // instructions kết thúc thành công
integer stall_cycles;          // cycles bị stall
integer flush_cycles;          // cycles bị flush (branch mispred)
integer dmem_rd_cnt;           // CPU loads
integer dmem_wr_cnt;           // CPU stores
integer axi_rd_burst_cnt;      // AXI read bursts (cache refill)
integer axi_wr_burst_cnt;      // AXI write bursts (write-through)
integer raw_hazard_cnt;        // RAW hazard count
integer post_halt_stores;      // stores xảy ra SAU khi program_done=1 (SB drain)

// Halt detection
reg [31:0] prev_pc;
integer    halt_cnt;
reg        program_done;

// PC history ring buffer (halt pattern 1–4 cycles)
reg [31:0] pc_ring [0:7];
integer    ring_ptr;
integer    match2, match3, match4;

// DCache scoreboard (store → verify on load)
reg [31:0] sb_addr [0:255];
reg [31:0] sb_data [0:255];
integer    sb_cnt;
integer    sb_errors;

// AXI latency tracking
integer aw_start;
integer ar_start;
integer wr_lat_sum, wr_lat_cnt;
integer rd_lat_sum, rd_lat_cnt;

// Stall run tracking
integer cur_stall_run;
integer max_stall_run;

// ============================================================================
// Waveform
// ============================================================================
initial begin
    $dumpfile("waveform_soc.vcd");
    $dumpvars(0, run_soc);
end

// ============================================================================
// ❶ Cycle Counter
// ============================================================================
always @(posedge clk) begin
    if (rst_n) cycle_count = cycle_count + 1;
end

// ============================================================================
// ❷ Instruction Retire & Pipeline Events
// ============================================================================
reg prev_stall;
always @(posedge clk) begin
    if (!rst_n) begin
        prev_stall <= 0;
    end else begin
        // Retire: valid instruction, not NOP, not stalled
        if (!stall_if && instr_if !== 32'h0 && instr_if !== 32'h00000013)
            instr_retired = instr_retired + 1;

        // Stall event
        if (stall_if) begin
            stall_cycles = stall_cycles + 1;
            cur_stall_run = cur_stall_run + 1;
            if (cur_stall_run > max_stall_run) max_stall_run = cur_stall_run;
        end else begin
            cur_stall_run = 0;
        end

        // ── VERBOSE: log every instruction ──────────────────────────────
        if (`LOG_LEVEL >= 3 && !stall_if && instr_if !== 32'h0) begin
            $display("[%6d] PC=0x%08h  INSTR=0x%08h%s",
                     cycle_count, pc_if, instr_if,
                     stall_if ? "  [STALL]" : "");
        end

        prev_stall <= stall_if;
    end
end

// ============================================================================
// ❸ DCache Load/Store Event Logger  (LOG_LEVEL >= 2)
// FIX: Phân biệt store trước halt (dmem_wr_cnt) và sau halt (post_halt_stores)
//      Store sau halt là SB drain — không count vào CPU stores
// ============================================================================
always @(posedge clk) begin
    if (rst_n && dc_req && dc_ready) begin
        if (dc_we) begin
            if (!program_done) begin
                // Store trước halt: count vào CPU stores
                dmem_wr_cnt = dmem_wr_cnt + 1;
                sb_update(dc_addr, dc_wdata, dc_wstrb);
            end else begin
                // Store SAU halt: Store Buffer drain — log riêng, không count
                post_halt_stores = post_halt_stores + 1;
                if (`LOG_LEVEL >= 2)
                    $display("[%6d] ▲ POST-HALT STORE (SB drain)  addr=0x%08h  data=0x%08h",
                             cycle_count, dc_addr, dc_wdata);
            end

            if (`LOG_LEVEL >= 2 && !program_done)
                $display("[%6d] ▲ STORE  addr=0x%08h  data=0x%08h  strb=%b",
                         cycle_count, dc_addr, dc_wdata, dc_wstrb);
        end else begin
            dmem_rd_cnt = dmem_rd_cnt + 1;
            sb_check(dc_addr, dc_rdata);

            if (`LOG_LEVEL >= 2)
                $display("[%6d] ▼ LOAD   addr=0x%08h  data=0x%08h",
                         cycle_count, dc_addr, dc_rdata);
        end
    end
end

// ============================================================================
// ❹ AXI Write Burst Logger  (LOG_LEVEL >= 2)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // AW handshake
        if (axi_awvalid && axi_awready) begin
            axi_wr_burst_cnt = axi_wr_burst_cnt + 1;
            aw_start = cycle_count;
            if (`LOG_LEVEL >= 2)
                $display("[%6d]   ↑ AXI-AW  addr=0x%08h", cycle_count, axi_awaddr);
        end
        // W beat
        if (axi_wvalid && axi_wready) begin
            if (`LOG_LEVEL >= 2)
                $display("[%6d]   ↑ AXI-W   data=0x%08h  strb=%b%s",
                         cycle_count, axi_wdata, axi_wstrb,
                         axi_wlast ? "  [LAST]" : "");
        end
        // B response
        if (axi_bvalid && axi_bready) begin
            wr_lat_sum = wr_lat_sum + (cycle_count - aw_start);
            wr_lat_cnt = wr_lat_cnt + 1;
            if (`LOG_LEVEL >= 2)
                $display("[%6d]   ↑ AXI-B   OK  lat=%0d cyc",
                         cycle_count, cycle_count - aw_start);
        end
    end
end

// ============================================================================
// ❺ AXI Read Burst Logger  (LOG_LEVEL >= 2)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        if (axi_arvalid && axi_arready) begin
            axi_rd_burst_cnt = axi_rd_burst_cnt + 1;
            ar_start = cycle_count;
            if (`LOG_LEVEL >= 2)
                $display("[%6d]   ↓ AXI-AR  addr=0x%08h  (refill)", cycle_count, axi_araddr);
        end
        if (axi_rvalid && axi_rready) begin
            if (`LOG_LEVEL >= 2)
                $display("[%6d]   ↓ AXI-R   data=0x%08h%s",
                         cycle_count, axi_rdata,
                         axi_rlast ? "  [LAST]" : "");
        end
        if (axi_rvalid && axi_rready && axi_rlast) begin
            rd_lat_sum = rd_lat_sum + (cycle_count - ar_start);
            rd_lat_cnt = rd_lat_cnt + 1;
        end
    end
end

// ============================================================================
// ❻ Halt / Loop Detection
// ============================================================================
always @(posedge clk) begin
    if (!rst_n) begin
        halt_cnt   <= 0;
        ring_ptr   <= 0;
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
// ❼ Watchdog
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
    cycle_count      = 0;   instr_retired    = 0;
    stall_cycles     = 0;   flush_cycles     = 0;
    dmem_rd_cnt      = 0;   dmem_wr_cnt      = 0;
    axi_rd_burst_cnt = 0;   axi_wr_burst_cnt = 0;
    wr_lat_sum       = 0;   wr_lat_cnt       = 0;
    rd_lat_sum       = 0;   rd_lat_cnt       = 0;
    raw_hazard_cnt   = 0;   sb_cnt           = 0;
    post_halt_stores = 0;
    sb_errors        = 0;   max_stall_run    = 0;
    cur_stall_run    = 0;   program_done     = 0;
    prev_pc          = 0;   halt_cnt         = 0;
    ring_ptr         = 0;
    match2 = 0; match3 = 0; match4 = 0;
    for (i = 0; i < 256; i = i + 1) begin sb_addr[i] = 0; sb_data[i] = 0; end
    for (i = 0; i < 8;   i = i + 1) pc_ring[i] = 0;
    aw_start = 0; ar_start = 0;

    print_banner();

    // Reset
    rst_n = 0;
    repeat(12) @(posedge clk);
    rst_n = 1;
    repeat(5)  @(posedge clk);

    if (`LOG_LEVEL >= 1)
        $display("[%6d] ▶ Execution started\n", cycle_count);

    wait(program_done);
end

// ============================================================================
// ══ SCOREBOARD TASKS ══
// ============================================================================

task sb_update;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    reg [31:0] al;
    integer    idx, found;
    reg [31:0] merged;
    begin
        al    = {addr[31:2], 2'b00};
        found = -1;
        for (idx = 0; idx < sb_cnt; idx = idx + 1)
            if (sb_addr[idx] === al) found = idx;
        merged = (found >= 0) ? sb_data[found] : 32'h0;
        if (strb[0]) merged[ 7: 0] = data[ 7: 0];
        if (strb[1]) merged[15: 8] = data[15: 8];
        if (strb[2]) merged[23:16] = data[23:16];
        if (strb[3]) merged[31:24] = data[31:24];
        if (found >= 0) begin
            sb_data[found] = merged;
        end else if (sb_cnt < 256) begin
            sb_addr[sb_cnt] = al;
            sb_data[sb_cnt] = merged;
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
        for (idx = 0; idx < sb_cnt; idx = idx + 1) begin
            if (sb_addr[idx] === al) begin
                if (sb_data[idx] !== got) begin
                    sb_errors = sb_errors + 1;
                    $display("[%6d] ✗ RAW-ERR  addr=0x%08h  expected=0x%08h  got=0x%08h",
                             cycle_count, al, sb_data[idx], got);
                end
            end
        end
    end
endtask

// ============================================================================
// ══ PRINT TASKS ══
// ============================================================================

task print_banner;
    begin
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║        RISC-V SoC  ─  Universal Debug Testbench                 ║");
        $display("║        ICache 4KB  │  DCache 8KB  │  AXI4-Full  │  100 MHz      ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  LOG_LEVEL = %0d  │  TIMEOUT = %0d cyc  │  HALT_STABLE = %0d cyc  ║",
                 `LOG_LEVEL, `TIMEOUT, `HALT_STABLE);
        $display("╚══════════════════════════════════════════════════════════════════╝");
        $display("");
    end
endtask

// ──────────────────────────────────────────────────────────────────────────────
task print_report;
    input [127:0] reason;
    integer j, k, nz;
    real cpi, ipc, eff;
    real ic_rate, dc_rate;
    integer ic_total, dc_total;
    integer avg_wr_lat, avg_rd_lat;
    reg [31:0] ret;
    reg [31:0] wv;
    reg [7:0]  bv;
    begin
        ret = soc.cpu.register_file.registers[10];   // a0

        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║  STOP: %-58s║", reason);
        $display("╚══════════════════════════════════════════════════════════════════╝");

        // ── ① PROGRAM RESULT ─────────────────────────────────────────────────
        $display("");
        $display("┌─── ① PROGRAM RESULT ───────────────────────────────────────────┐");
        $display("│  a0 (x10) = 0x%08h  =  %0d  (signed: %0d)",
                 ret, ret, $signed(ret));
        $display("│  Binary   = %032b", ret);
        // bit-mask decode se nếu là test suite
        if (ret === 32'h0)
            $display("│  ✓ ALL TESTS PASS  (a0 == 0)");
        else begin
            $display("│  ✗ FAIL BITMASK:");
            if (ret[0]) $display("│      bit0 = TEST 1 FAIL  (basic word r/w)");
            if (ret[1]) $display("│      bit1 = TEST 2 FAIL  (halfword)");
            if (ret[2]) $display("│      bit2 = TEST 3 FAIL  (byte + endian)");
            if (ret[3]) $display("│      bit3 = TEST 4 FAIL  (sequential)");
            if (ret[4]) $display("│      bit4 = TEST 5 FAIL  (stride/miss)");
            if (ret[5]) $display("│      bit5 = TEST 6 FAIL  (ASCON block)");
            if (ret[6]) $display("│      bit6 = TEST 7 FAIL  (RAW hazard)");
            if (ret[7]) $display("│      bit7 = TEST 8 FAIL  (boundary)");
        end
        $display("│  Final PC = 0x%08h", pc_if);
        $display("└────────────────────────────────────────────────────────────────┘");

        // ── ② PERFORMANCE ────────────────────────────────────────────────────
        $display("");
        $display("┌─── ② PERFORMANCE ──────────────────────────────────────────────┐");
        if (instr_retired > 0) begin
            cpi = cycle_count * 1.0 / instr_retired;
            ipc = instr_retired * 1.0 / cycle_count;
            eff = ipc * 100.0;
            $display("│  Cycles        : %0d", cycle_count);
            $display("│  Instructions  : %0d", instr_retired);
            $display("│  CPI           : %.3f  (ideal = 1.000)", cpi);
            $display("│  IPC           : %.3f  (ideal = 1.000)", ipc);
            $display("│  Pipeline eff  : %.1f%%  (instr/cycle)", eff);
            $display("│  Stall cycles  : %0d  (%.1f%%)",
                     stall_cycles, stall_cycles * 100.0 / cycle_count);
            $display("│  Max stall run : %0d cycles", max_stall_run);
            // Throughput rating
            if (eff >= 90.0)
                $display("│  Rating        : ★★★★★  EXCELLENT  (≥90%% eff)");
            else if (eff >= 75.0)
                $display("│  Rating        : ★★★★☆  GOOD       (≥75%%)");
            else if (eff >= 55.0)
                $display("│  Rating        : ★★★☆☆  FAIR       (≥55%%)");
            else
                $display("│  Rating        : ★★☆☆☆  NEEDS WORK (<55%%)");
        end else
            $display("│  No instructions retired.");
        $display("└────────────────────────────────────────────────────────────────┘");

        // ── ③ CACHE STATISTICS ───────────────────────────────────────────────
        $display("");
        $display("┌─── ③ CACHE STATISTICS ─────────────────────────────────────────┐");
        ic_total = icache_hits + icache_misses;
        dc_total = dcache_hits + dcache_misses;
        ic_rate  = (ic_total > 0) ? icache_hits * 100.0 / ic_total : 0.0;
        dc_rate  = (dc_total > 0) ? dcache_hits * 100.0 / dc_total : 0.0;

        $display("│  ICache (4KB):  hits=%-6d  misses=%-6d  hit%%=%.1f%%",
                 icache_hits, icache_misses, ic_rate);
        $display("│  DCache (8KB):  hits=%-6d  misses=%-6d  hit%%=%.1f%%  writes=%0d",
                 dcache_hits, dcache_misses, dc_rate, dcache_writes);
        $display("│  AXI refill bursts : %0d", axi_rd_burst_cnt);
        $display("│  AXI write-through : %0d", axi_wr_burst_cnt);

        if (rd_lat_cnt > 0)
            $display("│  Avg refill latency: %.1f cyc", rd_lat_sum * 1.0 / rd_lat_cnt);
        if (wr_lat_cnt > 0)
            $display("│  Avg write latency : %.1f cyc", wr_lat_sum * 1.0 / wr_lat_cnt);

        if (ic_rate >= 95.0) $display("│  ICache rating : ★★★★★  EXCELLENT");
        else if (ic_rate >= 80.0) $display("│  ICache rating : ★★★★☆  GOOD");
        else $display("│  ICache rating : ★★☆☆☆  COLD/POOR");

        if (dc_rate >= 95.0) $display("│  DCache rating : ★★★★★  EXCELLENT");
        else if (dc_rate >= 80.0) $display("│  DCache rating : ★★★★☆  GOOD");
        else $display("│  DCache rating : ★★☆☆☆  COLD/POOR");
        $display("└────────────────────────────────────────────────────────────────┘");

        // ── ④ MEMORY ACCESS SUMMARY ─────────────────────────────────────────
        $display("");
        $display("┌─── ④ MEMORY ACCESS SUMMARY ────────────────────────────────────┐");
        $display("│  CPU Loads  (lw/lh/lb) : %0d", dmem_rd_cnt);
        $display("│  CPU Stores (sw/sh/sb) : %0d", dmem_wr_cnt);
        $display("│  Post-halt SB drain    : %0d stores (after program done)", post_halt_stores);
        $display("│  RAW hazard violations : %0d %s",
                 sb_errors, sb_errors == 0 ? "✓" : "✗ DATA ERRORS");
        $display("│  Scoreboard entries    : %0d", sb_cnt);
        $display("│  LSU SB remaining      : %0d entries at halt", lsu_sb_count);
        $display("└────────────────────────────────────────────────────────────────┘");

        // ── ⑤ REGISTER FILE ──────────────────────────────────────────────────
        $display("");
        $display("┌─── ⑤ REGISTER FILE ────────────────────────────────────────────┐");
        $display("│  Reg   ABI     Hex          Decimal (signed)");
        $display("│  ─────────────────────────────────────────");
        nz = 0;
        for (j = 0; j < 32; j = j + 1) begin
            wv = soc.cpu.register_file.registers[j];
            if (wv !== 32'h0 || j == 2 || j == 10) begin
                nz = nz + 1;
                $display("│  x%-2d  %-5s   0x%08h   %0d",
                         j, abi_name(j), wv, $signed(wv));
            end
        end
        if (nz == 0) $display("│  (all zero)");
        $display("└────────────────────────────────────────────────────────────────┘");

        // ── ⑥ DMEM SNAPSHOT ──────────────────────────────────────────────────
        print_dmem_snapshot();

        // ── ⑦ SCOREBOARD DUMP (non-zero entries) ────────────────────────────
        $display("");
        $display("┌─── ⑦ STORE SCOREBOARD  (%0d entries, %0d errors) ───────────────┐",
                 sb_cnt, sb_errors);
        k = 0;
        for (j = 0; j < sb_cnt && j < 48; j = j + 1) begin
            if (sb_data[j] !== 32'h0) begin
                $display("│  [0x%08h] = 0x%08h  (%0d)", sb_addr[j], sb_data[j], sb_data[j]);
                k = k + 1;
            end
        end
        if (k == 0) $display("│  (no non-zero stores recorded)");
        if (sb_cnt > 48) $display("│  ... (%0d more entries)", sb_cnt - 48);
        $display("└────────────────────────────────────────────────────────────────┘");

        // ── FOOTER ───────────────────────────────────────────────────────────
        $display("");
        $display("══════════════════════════════════════════════════════════════════");
        $display("  SoC simulation complete.  %0d cycles @ 100 MHz = %.1f µs",
                 cycle_count, cycle_count * 10.0 / 1000.0);
        $display("══════════════════════════════════════════════════════════════════");
        $display("");
    end
endtask

// ──────────────────────────────────────────────────────────────────────────────
task print_dmem_snapshot;
    integer wi, col;
    reg [31:0] base, addr;
    reg [7:0]  b0, b1, b2, b3;
    reg [31:0] wval;
    begin
        base = `DMEM_DUMP_BASE;
        $display("");
        $display("┌─── ⑥ DMEM SNAPSHOT  [0x%08h .. 0x%08h]  (%0d words) ────────────┐",
                 base, base + `DMEM_DUMP_WORDS * 4 - 1, `DMEM_DUMP_WORDS);
        $display("│  Address       +0          +4          +8          +C");
        $display("│  ─────────────────────────────────────────────────────────────");

        for (wi = 0; wi < `DMEM_DUMP_WORDS; wi = wi + `DMEM_ROW_WORDS) begin
            addr = base + wi * 4;
            $write("│  0x%08h  ", addr);
            for (col = 0; col < `DMEM_ROW_WORDS; col = col + 1) begin
                // Đọc từ byte array của data_mem_burst
                b0 = soc.dmem.dmem.memory[base + (wi+col)*4 + 0];
                b1 = soc.dmem.dmem.memory[base + (wi+col)*4 + 1];
                b2 = soc.dmem.dmem.memory[base + (wi+col)*4 + 2];
                b3 = soc.dmem.dmem.memory[base + (wi+col)*4 + 3];
                wval = {b3, b2, b1, b0};
                $write("0x%08h  ", wval);
            end
            $display("");
        end

        // ASCII view
        $display("│");
        $display("│  ASCII view (printable bytes):");
        $write("│  ");
        for (wi = 0; wi < `DMEM_DUMP_WORDS * 4; wi = wi + 1) begin
            b0 = soc.dmem.dmem.memory[base + wi];
            if (b0 >= 8'h20 && b0 <= 8'h7E)
                $write("%s", b0);
            else
                $write(".");
            if ((wi & 15) == 15 && wi < `DMEM_DUMP_WORDS * 4 - 1) begin
                $display("");
                $write("│  ");
            end
        end
        $display("");
        $display("└────────────────────────────────────────────────────────────────┘");
    end
endtask

// ──────────────────────────────────────────────────────────────────────────────
// ABI register name lookup
function [39:0] abi_name;
    input integer r;
    begin
        case (r)
            0:  abi_name = "zero ";
            1:  abi_name = "ra   ";
            2:  abi_name = "sp   ";
            3:  abi_name = "gp   ";
            4:  abi_name = "tp   ";
            5:  abi_name = "t0   ";
            6:  abi_name = "t1   ";
            7:  abi_name = "t2   ";
            8:  abi_name = "s0/fp";
            9:  abi_name = "s1   ";
            10: abi_name = "a0   ";
            11: abi_name = "a1   ";
            12: abi_name = "a2   ";
            13: abi_name = "a3   ";
            14: abi_name = "a4   ";
            15: abi_name = "a5   ";
            16: abi_name = "a6   ";
            17: abi_name = "a7   ";
            18: abi_name = "s2   ";
            19: abi_name = "s3   ";
            20: abi_name = "s4   ";
            21: abi_name = "s5   ";
            22: abi_name = "s6   ";
            23: abi_name = "s7   ";
            24: abi_name = "s8   ";
            25: abi_name = "s9   ";
            26: abi_name = "s10  ";
            27: abi_name = "s11  ";
            28: abi_name = "t3   ";
            29: abi_name = "t4   ";
            30: abi_name = "t5   ";
            31: abi_name = "t6   ";
            default: abi_name = "???  ";
        endcase
    end
endfunction

endmodule