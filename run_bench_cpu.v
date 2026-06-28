`timescale 1ns/1ps

`include "soc_hs.v"

// ============================================================================
//  run_bench_cpu.v — CPU Integer Performance Benchmark Testbench
//
//  Firmware: gnu_toolchain/tests/bench_cpu_direct.hex
//  Build   : cd gnu_toolchain
//            ./compile_c_to_hex.sh -i tests/bench_cpu_direct.c \
//                                   -o tests/bench_cpu_direct.hex -O 1 -c
//  Run     : ~/workflow/urun_verilog.sh run_bench_cpu.v
//            rtk read run_bench_cpu.log
//
//  Flow:
//    1. SoC boot (POR → fabric_rst → boot_ctrl IMEM load → cpu_rst)
//    2. Firmware chạy 4 workload, output qua UART 8N1 @ 115200 baud
//    3. TB giải mã UART, in mỗi dòng ra log
//    4. Khi thấy "[BENCH-DONE]": in hardware counter report → $finish
//    5. Watchdog TIMEOUT = 5M cycles nếu firmware không hoàn thành
//
//  Metrics từ 2 nguồn (để cross-check):
//    FW: giá trị firmware report qua UART (từ SOC_CTRL registers)
//    TB: đếm trực tiếp từ RTL wire taps
// ============================================================================

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "gnu_toolchain/tests/bench_cpu_direct.hex"
`endif

`define TIMEOUT   5000000   /* 5M cycles — đủ cho 4 workloads + UART output */
`define BAUD_DIV  868       /* 115200 baud @ 100 MHz */
`define CLK_MHZ   100       /* clock frequency (for MIPS/throughput calc) */

// ============================================================================
// Top
// ============================================================================
module run_bench_cpu;

parameter CLK_PERIOD = 10;  /* 10 ns = 100 MHz */

// ── Clock & Reset ────────────────────────────────────────────────────────────
reg clk;
reg por_n_r;
reg ext_rst_n_r;

initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ── JTAG (idle: TMS=1 → TAP in Test-Logic-Reset) ────────────────────────────
reg  jtag_tck_r;
reg  jtag_tms_r;
reg  jtag_tdi_r;
wire jtag_tdo_w;

// ── UART ─────────────────────────────────────────────────────────────────────
wire uart_tx_w;
assign uart_rx_w = 1'b1;  /* idle high */

// ── GPIO (not driven in this TB) ─────────────────────────────────────────────
wire [31:0] gpio_w;
reg  [31:0] gpio_in_r;
assign gpio_w = gpio_in_r;

// ── WDT (intercept, not applied) ─────────────────────────────────────────────
wire wdt_rst_req_w;

// ── DUT ──────────────────────────────────────────────────────────────────────
soc_hs #(.SIM_MODE(1), .IMEM_INIT_FILE(`IMEM_INIT_FILE)) chip (
    .clk_in    (clk),
    .por_n     (por_n_r),
    .ext_rst_n (ext_rst_n_r),
    .uart_tx   (uart_tx_w),
    .uart_rx   (uart_rx_w),
    .tck       (jtag_tck_r),
    .tms       (jtag_tms_r),
    .tdi       (jtag_tdi_r),
    .tdo       (jtag_tdo_w),
    .spi_sck   (),
    .spi_mosi  (),
    .spi_miso  (1'b1),
    .spi_cs_n  (),
    .gpio      (gpio_w),
    .wdt_rst_req(wdt_rst_req_w)
);

// ============================================================================
// RTL Wire Taps — hardware counters để cross-check với FW report
// ============================================================================

// CPU pipeline
wire [31:0] pc_if    = chip.u_soc_top.u_cpu.pc_if;
wire [31:0] instr_if = chip.u_soc_top.u_cpu.instr_if;
wire        stall_if = chip.u_soc_top.u_cpu.stall_if;

// Cache stats (kumulativ từ SOC_CTRL internal counters)
wire [31:0] ic_hits_w  = chip.u_soc_top.icache_stat_hits;
wire [31:0] ic_miss_w  = chip.u_soc_top.icache_stat_misses;
wire [31:0] dc_hits_w  = chip.u_soc_top.dcache_stat_hits;
wire [31:0] dc_miss_w  = chip.u_soc_top.dcache_stat_misses;
wire [31:0] dc_wr_w    = chip.u_soc_top.dcache_stat_writes;

// Boot / reset domain
wire fabric_rst_n_w = chip.u_soc_top.fabric_rst_n;
wire cpu_rst_n_w    = chip.u_soc_top.cpu_rst_n;
wire boot_done_w    = chip.u_soc_top.boot_done;

// ============================================================================
// TB Counters
// ============================================================================
integer cycle_count;
integer tb_instr_cnt;    /* instructions retired (stall_if==0, instr != 0) */
integer tb_stall_cnt;    /* stall cycles */
reg     program_done;
reg [31:0] prev_pc;
integer    halt_cnt;

// ============================================================================
// Cycle Counter
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r) cycle_count = cycle_count + 1;
end

// ============================================================================
// Instruction Retire + Stall Counter
// ============================================================================
always @(posedge clk) begin
    if (ext_rst_n_r && cpu_rst_n_w) begin
        if (!stall_if && instr_if !== 32'h0)
            tb_instr_cnt = tb_instr_cnt + 1;
        if (stall_if)
            tb_stall_cnt = tb_stall_cnt + 1;
    end
end

// ============================================================================
// Halt / NOP-Loop Detection
// ============================================================================
always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        halt_cnt <= 0;
        prev_pc  <= 32'h0;
    end else if (cycle_count > 50 && cpu_rst_n_w) begin
        if (pc_if === prev_pc && !program_done) begin
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= 80) begin
                program_done = 1;
                print_bench_report("HALT LOOP DETECTED");
                #(CLK_PERIOD * 2);
                $finish;
            end
        end else begin
            halt_cnt <= 0;
        end
        prev_pc <= pc_if;
    end
end

// ============================================================================
// Watchdog
// ============================================================================
initial begin
    #(CLK_PERIOD * `TIMEOUT);
    if (!program_done) begin
        program_done = 1;
        print_bench_report("WATCHDOG TIMEOUT — firmware did not print [BENCH-DONE]");
    end
    $finish;
end

// ============================================================================
// Waveform
// ============================================================================
initial begin
    $dumpfile("waveform_bench_cpu.vcd");
    $dumpvars(0, run_bench_cpu);
end

// ============================================================================
// UART Monitor — 8N1, baud = BAUD_DIV × CLK_PERIOD ns
// Decode từng byte, accumulate thành line, parse "[BENCH-DONE]"
// ============================================================================
time baud_half;
time baud_full;

reg [7:0] uart_line_buf [0:127];
integer   uart_line_len;
integer   uart_byte_cnt;

// Line match helper: trả về 1 nếu uart_line_buf[0..len-1] == target string
// Implemented inline trong parse_uart_line task (không dùng string compare)

initial begin
    baud_half    = (`BAUD_DIV * CLK_PERIOD) / 2;
    baud_full    =  `BAUD_DIV * CLK_PERIOD;
    uart_line_len = 0;
    uart_byte_cnt = 0;

    forever begin
        @(negedge uart_tx_w);
        #(baud_half + baud_full);

        begin : uart_frame
            reg [7:0] rx_byte;
            integer   b;
            rx_byte = 8'h00;
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = uart_tx_w;
                if (b < 7) #baud_full;
            end
            #baud_full;

            uart_byte_cnt = uart_byte_cnt + 1;

            if (rx_byte >= 8'h20 && rx_byte <= 8'h7E)
                $display("[%7d] [UART] '%s' (0x%02h)", cycle_count, rx_byte, rx_byte);

            if (rx_byte == 8'h0A) begin   // '\n'
                parse_uart_line();
                uart_line_len = 0;
            end else if (rx_byte != 8'h0D) begin  // skip '\r'
                if (uart_line_len < 127) begin
                    uart_line_buf[uart_line_len] = rx_byte;
                    uart_line_len = uart_line_len + 1;
                end
            end
        end
    end
end

// ── parse_uart_line: print line, check for [BENCH-DONE] ──────────────────────
task parse_uart_line;
    integer k;
    reg match;
    // Print the assembled line
    begin
        $write("[%7d] [LINE] ", cycle_count);
        for (k = 0; k < uart_line_len; k = k + 1)
            $write("%s", uart_line_buf[k]);
        $display("");

        // Check for "[BENCH-DONE]" (12 chars)
        if (uart_line_len >= 12) begin
            match = (uart_line_buf[0]  == "[" &&
                     uart_line_buf[1]  == "B" &&
                     uart_line_buf[2]  == "E" &&
                     uart_line_buf[3]  == "N" &&
                     uart_line_buf[4]  == "C" &&
                     uart_line_buf[5]  == "H" &&
                     uart_line_buf[6]  == "-" &&
                     uart_line_buf[7]  == "D" &&
                     uart_line_buf[8]  == "O" &&
                     uart_line_buf[9]  == "N" &&
                     uart_line_buf[10] == "E" &&
                     uart_line_buf[11] == "]");
            if (match) begin
                program_done = 1;
                print_bench_report("BENCH COMPLETE");
                #(CLK_PERIOD * 5);
                $finish;
            end
        end
    end
endtask

// ============================================================================
// print_bench_report — hardware counter snapshot at end of simulation
// ============================================================================
task print_bench_report;
    input [255:0] reason;
    reg [31:0] ic_total, dc_total;
    begin
        ic_total = ic_hits_w + ic_miss_w;
        dc_total = dc_hits_w + dc_miss_w;

        $display("");
        $display("╔══════════════════════════════════════════════════════╗");
        $display("║           CPU BENCH SIMULATION REPORT                ║");
        $display("╚══════════════════════════════════════════════════════╝");
        $display("  Reason          : %0s", reason);
        $display("  Total sim cycles: %0d", cycle_count);
        $display("  UART bytes TX   : %0d", uart_byte_cnt);
        $display("");
        $display("  ── TB-counted CPU metrics ─────────────────────────");
        $display("  Instructions    : %0d", tb_instr_cnt);
        $display("  Stall cycles    : %0d", tb_stall_cnt);
        if (tb_instr_cnt > 0) begin
            $display("  Avg IPC (approx): %0d.%02d",
                     (tb_instr_cnt * 100) / (cycle_count + 1) / 100,
                     (tb_instr_cnt * 100) / (cycle_count + 1) % 100);
        end
        $display("");
        $display("  ── Hardware Cache Stats (cumulative from boot) ─────");
        $display("  ICache hits     : %-8d  misses : %-8d  total : %0d",
                 ic_hits_w, ic_miss_w, ic_total);
        $display("  DCache hits     : %-8d  misses : %-8d  total : %0d",
                 dc_hits_w, dc_miss_w, dc_total);
        $display("  DCache writes   : %0d", dc_wr_w);
        if (ic_total > 0)
            $display("  ICache hit-rate : %0d%%",
                     (ic_hits_w * 100) / ic_total);
        if (dc_total > 0)
            $display("  DCache hit-rate : %0d%%",
                     (dc_hits_w * 100) / dc_total);
        $display("");
        $display("  ── How to compute CPI from FW report ───────────────");
        $display("  CPI  = W_cyc / W_ins  (per workload)");
        $display("  IPC  = W_ins / W_cyc");
        $display("  MIPS = IPC × %0d  (@ %0dMHz)", `CLK_MHZ, `CLK_MHZ);
        $display("  Note: ins = minstret_approx (regwrite_wb only)");
        $display("        stl = stall_cycles from SOC_STALL_CNT");
        $display("════════════════════════════════════════════════════════");
    end
endtask

// ============================================================================
// Main Sequence — reset + boot
// ============================================================================
integer _j;
initial begin
    jtag_tck_r   = 1'b0;
    jtag_tms_r   = 1'b1;
    jtag_tdi_r   = 1'b0;
    gpio_in_r    = 32'h0;
    cycle_count  = 0;
    tb_instr_cnt = 0;
    tb_stall_cnt = 0;
    program_done = 0;
    prev_pc      = 32'h0;
    halt_cnt     = 0;
    uart_line_len = 0;
    uart_byte_cnt = 0;

    for (_j = 0; _j < 128; _j = _j + 1) uart_line_buf[_j] = 8'h00;

    $display("════════════════════════════════════════════════════════");
    $display("  run_bench_cpu.v — CPU Benchmark TB");
    $display("  IMEM: %s", `IMEM_INIT_FILE);
    $display("  CLK : %0d MHz    TIMEOUT: %0d cycles", `CLK_MHZ, `TIMEOUT);
    $display("  BAUD: %0d div    (~115200 @ 100MHz)", `BAUD_DIV);
    $display("════════════════════════════════════════════════════════");

    /* ── Reset sequence (giống run_soc_ascon.v) ──────────────────────────────
     * por_n=0 → 20cy → ext_rst_n=1 → 1020cy → por_n=1
     * → chờ fabric_rst_n → chờ boot_done → chờ cpu_rst_n               */
    por_n_r     = 1'b0;
    ext_rst_n_r = 1'b0;
    repeat(20) @(posedge clk);

    ext_rst_n_r = 1'b1;
    $display("[%7d] ext_rst_n released", cycle_count);

    repeat(1020) @(posedge clk);

    por_n_r = 1'b1;
    $display("[%7d] por_n released — waiting fabric_rst_n...", cycle_count);

    @(posedge fabric_rst_n_w);
    $display("[%7d] fabric_rst_n released — boot_ctrl loading IMEM...", cycle_count);

    @(posedge boot_done_w);
    $display("[%7d] boot_done — waiting cpu_rst_n...", cycle_count);

    @(posedge cpu_rst_n_w);
    repeat(3) @(posedge clk);
    $display("[%7d] cpu_rst_n released — CPU executing bench firmware\n", cycle_count);

    wait(program_done);
end

endmodule
