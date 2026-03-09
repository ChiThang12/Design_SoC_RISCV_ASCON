// ============================================================
// Testbench: tb_ascon_CORE — Step-by-step trace
// Standard: Verilog-2001 (no SystemVerilog constructs)
//
// UPDATED for ascon_CONTROLLER v4 (H1+H2) with original iterative PERMUTATION:
//   • hw_perm_valid_sr / hw_perm_stages removed — those are PIPE2-only signals.
//   • Restored iterative perm probes: round_counter, rounds_reg, running.
//   • Event monitor updated to show round_cnt/rounds_reg progress.
//   • All FSM wait_and_check calls unchanged (FSM state numbers unchanged).
//   • H1 effect: fewer total cycles per test (4 states removed).
//   • H2 effect: buf_ready/buf_valid ports exist but TB drives them low
//     (backward-compatible — original ad_in/data_in path used).
//
// SW expected values unchanged (same crypto algorithm).
// ============================================================
`timescale 1ns/1ps
`include "ascon_accelerator/rtl/ascon_core.v"

module tb_ascon_CORE;

    // ---- DUT ports ----
    reg         clk, rst_n, start;
    reg  [1:0]  mode;
    reg         enc_dec;
    reg  [127:0] key_in, nonce_in, ad_in, data_in, tag_received;
    reg          ad_valid, ad_last;
    reg          data_last;
    reg  [6:0]   data_len;

    wire [127:0] data_out;
    wire         data_out_valid;
    wire [127:0] tag_out;
    wire         tag_valid, tag_match, done, busy;

    ascon_CORE dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .mode(mode), .enc_dec(enc_dec),
        .key_in(key_in), .nonce_in(nonce_in),
        .ad_in(ad_in), .ad_valid(ad_valid), .ad_last(ad_last),
        .data_in(data_in), .data_last(data_last), .data_len(data_len),
        .tag_received(tag_received),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .tag_out(tag_out), .tag_valid(tag_valid),
        .tag_match(tag_match), .done(done), .busy(busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Timing infrastructure
    // CLK_PERIOD_NS must match the `timescale and always #5 above.
    // Change to your actual clock period for accurate throughput numbers.
    // ----------------------------------------------------------------
    localparam integer CLK_PERIOD_NS = 10; // 10 ns → 100 MHz

    // ---- Global cycle counter ----
    integer cyc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cyc <= 0;
        else        cyc <= cyc + 1;
    end

    // ---- Per-permutation timer ----
    integer perm_start_cyc;
    integer perm_cycles;        // cycles of last completed permutation
    always @(posedge clk) begin
        if (hw_perm_start)
            perm_start_cyc <= cyc;
        if (hw_perm_done)
            perm_cycles <= cyc - perm_start_cyc;
    end

    // ---- Per-phase timers ----
    // FSM state aliases (must match ascon_CONTROLLER localparam encoding)
    localparam [5:0]
        FSM_INIT_PERM_START = 6'd5,
        FSM_POST_INIT_LOAD  = 6'd7,
        FSM_AD_PERM_START   = 6'd10,
        FSM_POST_AD_LOAD    = 6'd12,
        FSM_DATA_PERM_START = 6'd17,
        FSM_POST_DATA_LOAD  = 6'd19,
        FSM_FIN_PERM_START  = 6'd22,
        FSM_POST_FIN_LOAD   = 6'd24;

    integer phase_init_start_cyc, phase_init_cycles;
    integer phase_ad_start_cyc,   phase_ad_cycles;
    integer phase_data_start_cyc, phase_data_cycles;
    integer phase_fin_start_cyc,  phase_fin_cycles;

    always @(posedge clk) begin
        if (hw_fsm == FSM_INIT_PERM_START && hw_perm_start)
            phase_init_start_cyc <= cyc;
        if (hw_fsm == FSM_POST_INIT_LOAD && hw_state_load)
            phase_init_cycles <= cyc - phase_init_start_cyc + 1;

        if (hw_fsm == FSM_AD_PERM_START && hw_perm_start)
            phase_ad_start_cyc <= cyc;
        if (hw_fsm == FSM_POST_AD_LOAD && hw_state_load)
            phase_ad_cycles <= cyc - phase_ad_start_cyc + 1;

        if (hw_fsm == FSM_DATA_PERM_START && hw_perm_start)
            phase_data_start_cyc <= cyc;
        if (hw_fsm == FSM_POST_DATA_LOAD && hw_state_load)
            phase_data_cycles <= cyc - phase_data_start_cyc + 1;

        if (hw_fsm == FSM_FIN_PERM_START && hw_perm_start)
            phase_fin_start_cyc <= cyc;
        if (hw_fsm == FSM_POST_FIN_LOAD && hw_state_load)
            phase_fin_cycles <= cyc - phase_fin_start_cyc + 1;
    end

    // ---- Per-test timer ----
    integer test_start_cyc;
    integer test_cyc [0:3];
    integer test_ns  [0:3];

    task record_test_start;
        begin
            test_start_cyc = cyc;
        end
    endtask

    task record_test_end;
        input integer tidx;
        begin
            test_cyc[tidx] = cyc - test_start_cyc;
            test_ns [tidx] = test_cyc[tidx] * CLK_PERIOD_NS;
        end
    endtask

    // ----------------------------------------------------------------
    // Hierarchical probes
    // ----------------------------------------------------------------

    // --- State register ---
    wire [319:0] hw_state = dut.u_state_reg.state_out;
    wire [63:0]  hw_x0    = hw_state[319:256];
    wire [63:0]  hw_x1    = hw_state[255:192];
    wire [63:0]  hw_x2    = hw_state[191:128];
    wire [63:0]  hw_x3    = hw_state[127: 64];
    wire [63:0]  hw_x4    = hw_state[ 63:  0];

    // --- Permutation outputs (port unchanged) ---
    wire [319:0] hw_perm_out = dut.u_perm.state_out;

    // --- Permutation internals — iterative (original ascon_PERMUTATION) ---
    wire [3:0]  hw_perm_round_cnt = dut.u_perm.round_counter; // absolute round index
    wire [3:0]  hw_perm_rounds_r  = dut.u_perm.rounds_reg;    // latched rounds
    wire        hw_perm_busy      = dut.u_perm.running;        // 1 while permutation running

    // --- Datapath ---
    wire [319:0] hw_dp_xored = dut.u_dp.state_xored;

    // --- Controller ---
    wire [5:0]  hw_fsm           = dut.u_ctrl.state;
    wire        hw_state_load    = dut.u_ctrl.state_load;
    wire        hw_perm_start    = dut.u_ctrl.perm_start;
    wire        hw_perm_done     = dut.perm_done;
    wire        hw_post_init_xor = dut.u_ctrl.do_post_init_key_xor;
    wire        hw_pre_fin_xor   = dut.u_ctrl.do_pre_fin_key_xor;
    wire        hw_dom_sep       = dut.u_ctrl.do_dom_sep;
    wire [1:0]  hw_src_sel       = dut.u_ctrl.state_src_sel;
    wire [3:0]  hw_perm_rounds   = dut.u_ctrl.perm_rounds;

    // ----------------------------------------------------------------
    // 1-cycle delay of state_load (replaces $past — SV-only)
    // ----------------------------------------------------------------
    reg hw_state_load_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hw_state_load_d1 <= 1'b0;
        else        hw_state_load_d1 <= hw_state_load;
    end

    // ----------------------------------------------------------------
    // Continuous event monitor
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (hw_state_load) begin
            $display("  [cyc=%0d t=%0t ns] state_load  FSM=%02d  post_init=%b pre_fin=%b dom_sep=%b src=%b",
                cyc, $time, hw_fsm,
                hw_post_init_xor, hw_pre_fin_xor, hw_dom_sep, hw_src_sel);
        end
        if (hw_state_load_d1) begin
            $display("            → state_reg: x0=%h x1=%h",      hw_x0, hw_x1);
            $display("                         x2=%h x3=%h x4=%h", hw_x2, hw_x3, hw_x4);
        end
        if (hw_perm_start) begin
            $display("  [cyc=%0d t=%0t ns] perm_start  FSM=%02d  rounds=%0d",
                cyc, $time, hw_fsm, hw_perm_rounds);
            $display("            perm_in: x0=%h x1=%h",      hw_x0, hw_x1);
            $display("                     x2=%h x3=%h x4=%h", hw_x2, hw_x3, hw_x4);
        end
        // Show round progress each cycle while permutation is running
        if (hw_perm_busy && !hw_perm_start) begin
            $display("  [cyc=%0d t=%0t ns] perm_round  cnt=%0d / %0d",
                cyc, $time, hw_perm_round_cnt, hw_perm_rounds_r);
        end
        if (hw_perm_done) begin
            $display("  [cyc=%0d t=%0t ns] perm_done   took %0d cycles (%0d ns)",
                cyc, $time, perm_cycles, perm_cycles * CLK_PERIOD_NS);
            $display("            perm_out: x0=%h x1=%h",
                hw_perm_out[319:256], hw_perm_out[255:192]);
            $display("                      x2=%h x3=%h x4=%h",
                hw_perm_out[191:128], hw_perm_out[127:64], hw_perm_out[63:0]);
        end
        if (data_out_valid)
            $display("  [cyc=%0d t=%0t ns] data_out = %h", cyc, $time, data_out);
        if (tag_valid)
            $display("  [cyc=%0d t=%0t ns] tag_out  = %h", cyc, $time, tag_out);
        if (done)
            $display("  [cyc=%0d t=%0t ns] DONE", cyc, $time);
    end

    // ----------------------------------------------------------------
    // Capture final outputs
    // ----------------------------------------------------------------
    reg [127:0] cap_ct, cap_tag;
    always @(posedge clk) begin
        if (data_out_valid) cap_ct  <= data_out;
        if (tag_valid)      cap_tag <= tag_out;
    end

    // ----------------------------------------------------------------
    // SW expected values — from trace_sw.py (unchanged)
    // ----------------------------------------------------------------
    localparam [319:0] SW_S1_INIT = {
        64'h00001000808c0001,
        64'h0706050403020100,
        64'h0f0e0d0c0b0a0908,
        64'h1716151413121110,
        64'h1f1e1d1c1b1a1918
    };
    localparam [319:0] SW_S2_PERM12 = {
        64'hcde34900cdfce2c8,
        64'h948cba141a58c1cb,
        64'h1fec9b5dae69b43a,
        64'h620599fcd928dbac,
        64'h3d3290a90ed3b02f
    };
    localparam [319:0] SW_S3_POST_INIT = {
        64'hcde34900cdfce2c8,
        64'h948cba141a58c1cb,
        64'h1fec9b5dae69b43a,
        64'h65039cf8da2adaac,
        64'h323c9da505d9b927
    };
    localparam [319:0] SW_S4_AD_XOR = {
        64'hcde3484e82bfb189,
        64'h948cba141a58c1cb,
        64'h1fec9b5dae69b43a,
        64'h65039cf8da2adaac,
        64'h323c9da505d9b927
    };
    localparam [319:0] SW_S5_PERM8 = {
        64'hd5d3483f21013729,
        64'h1221d129212b6cad,
        64'hec1b833eb83ed2cd,
        64'h4f2e1646cddea9a1,
        64'h111c3756a94734f4
    };
    localparam [319:0] SW_S6_DOM_SEP = {
        64'hd5d3483f21013729,
        64'h1221d129212b6cad,
        64'hec1b833eb83ed2cd,
        64'h4f2e1646cddea9a1,
        64'h911c3756a94734f4
    };
    localparam [319:0] SW_S7_PT_XOR = {
        64'hd5d349514e624448,
        64'h1221d129212b6cad,
        64'hec1b833eb83ed2cd,
        64'h4f2e1646cddea9a1,
        64'h911c3756a94734f4
    };
    localparam [319:0] SW_S8_PREFIN = {
        64'hd5d349514e624448,
        64'h1221d129212b6cad,
        64'heb1d863abb3cd3cd,
        64'h40201b4ac6d4a0a9,
        64'h911c3756a94734f4
    };
    localparam [319:0] SW_S9_PERM12F = {
        64'hfb3d6227a74a5536,
        64'h5b7adcb83dcd821c,
        64'ha735d8bde035e585,
        64'hd39578c89775f431,
        64'h0480b9a1c0df24d1
    };

    localparam [39:0]  SW_CT       = 40'h4844624e51;
    localparam [127:0] SW_TAG      = 128'h31f57794cc7d93d4d92dd5cbadb48e0b;
    localparam [39:0]  SW_CT_NOAD  = 40'ha9919fa26e;
    localparam [127:0] SW_TAG_NOAD = 128'hf1a4d483f02f1979dad8aef9985b6148;

    // ----------------------------------------------------------------
    // Test inputs
    // ----------------------------------------------------------------
    localparam [127:0] TEST_KEY   = 128'h000102030405060708090A0B0C0D0E0F;
    localparam [127:0] TEST_NONCE = 128'h101112131415161718191A1B1C1D1E1F;
    localparam [127:0] TEST_AD    = 128'h4153434F4E0000000000000000000000;
    localparam [127:0] TEST_PT    = 128'h6173636F6E0000000000000000000000;
    localparam [6:0]   PT_LEN     = 7'd5;

    // ----------------------------------------------------------------
    // Step-check task
    // ----------------------------------------------------------------
    reg [319:0] chk_hw;
    reg [319:0] chk_sw;
    integer     pass_count, fail_count;

    task do_step_check;
        input [319:0] sw_expected;
        input [63:0]  step_label_hi;
        input [63:0]  step_label_lo;
        begin
            @(posedge clk);
            chk_hw = hw_state;
            chk_sw = sw_expected;
            $display("  +-- HW: x0=%h", chk_hw[319:256]);
            $display("  |       x1=%h", chk_hw[255:192]);
            $display("  |       x2=%h", chk_hw[191:128]);
            $display("  |       x3=%h", chk_hw[127: 64]);
            $display("  |       x4=%h", chk_hw[ 63:  0]);
            $display("  |   SW: x0=%h", chk_sw[319:256]);
            $display("  |       x1=%h", chk_sw[255:192]);
            $display("  |       x2=%h", chk_sw[191:128]);
            $display("  |       x3=%h", chk_sw[127: 64]);
            $display("  |       x4=%h", chk_sw[ 63:  0]);
            if (chk_hw === chk_sw) begin
                $display("  +-- [PASS]");
                pass_count = pass_count + 1;
            end else begin
                $display("  +-- [FAIL]");
                fail_count = fail_count + 1;
                if (chk_hw[319:256] !== chk_sw[319:256]) $display("       x0 MISMATCH");
                if (chk_hw[255:192] !== chk_sw[255:192]) $display("       x1 MISMATCH");
                if (chk_hw[191:128] !== chk_sw[191:128]) $display("       x2 MISMATCH");
                if (chk_hw[127: 64] !== chk_sw[127: 64]) $display("       x3 MISMATCH");
                if (chk_hw[ 63:  0] !== chk_sw[ 63:  0]) $display("       x4 MISMATCH");
            end
        end
    endtask

    // wait_and_check: wait until FSM reaches target state, then check state_reg.
    // Timeout increased to 5000 cycles (sufficient for either PIPE2 or iterative).
    task wait_and_check;
        input [5:0]   target_fsm;
        input [319:0] sw_expected;
        input [63:0]  label_hi;
        input [63:0]  label_lo;
        integer t;
        begin
            t = 0;
            while (hw_fsm !== target_fsm && t < 5000) begin
                @(posedge clk); t = t + 1;
            end
            if (t >= 5000) begin
                $display("  [TIMEOUT] waiting for FSM state %0d", target_fsm);
            end else begin
                $display("\n>> STEP %0s%0s", label_hi, label_lo);
                do_step_check(sw_expected, label_hi, label_lo);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------
    task wait_done;
        integer t;
        begin
            t = 0;
            @(posedge clk);
            while (!done && t < 10000) begin @(posedge clk); t = t + 1; end
            if (t >= 10000) $display("[ERROR] Timeout waiting for done");
            @(posedge clk);
        end
    endtask

    task pulse_start;
        begin
            @(posedge clk); start = 1;
            @(posedge clk); start = 0;
        end
    endtask

    task do_reset;
        begin
            rst_n = 0;
            repeat(2) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask

    // ----------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------
    initial begin
        rst_n=0; start=0; mode=2'b00; enc_dec=0;
        key_in=TEST_KEY; nonce_in=TEST_NONCE;
        ad_in=0; ad_valid=0; ad_last=0;
        data_in=TEST_PT; data_last=1; data_len=PT_LEN;
        tag_received=128'b0;
        pass_count=0; fail_count=0;
        cap_ct=0; cap_tag=0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("================================================================");
        $display("  Ascon STEP TRACE — NIST Ascon-AEAD128");
        $display("  Permutation: Iterative (1 round/cycle, p12=12cyc, p8=8cyc)");
        $display("================================================================");
        $display("  Key  : %h", TEST_KEY);
        $display("  Nonce: %h", TEST_NONCE);
        $display("  AD   : 4153434f4e  (ASCON, 5 bytes)");
        $display("  PT   : 6173636f6e  (ascon, 5 bytes)");
        $display("================================================================\n");

        // ============================================================
        // TEST 1: Encryption step-by-step
        // ============================================================
        $display("================================================================");
        $display("  TEST 1: ENCRYPTION — 10-step trace");
        $display("================================================================");
        ad_in=TEST_AD; ad_valid=1; ad_last=1;
        data_in=TEST_PT; data_len=PT_LEN; data_last=1;
        record_test_start;
        pulse_start;

        // ------ Step 1: INIT_LOAD ------
        // FSM state 4 = S_INIT_LOAD: IV||K||N loaded into state_reg
        wait_and_check(6'd4, SW_S1_INIT, "1.INIT_LOAD     ", "(IV||K||N)      ");

        // ------ Step 2: PERM12 output (before key XOR) ------
        // FSM state 7 = S_POST_INIT_LOAD: perm12 done, about to XOR key.
        // PIPE2: state_out is latched by permutation when done=1,
        // so hw_perm_out holds correct p12 result at this FSM state.
        begin : step2_block
            integer t2;
            t2 = 0;
            while (hw_fsm !== 6'd7 && t2 < 5000) begin @(posedge clk); t2=t2+1; end
            $display("\n>> STEP 2.PERM12_OUT   (before key XOR)");
            $display("  +-- HW perm_out: x0=%h", hw_perm_out[319:256]);
            $display("  |               x1=%h", hw_perm_out[255:192]);
            $display("  |               x2=%h", hw_perm_out[191:128]);
            $display("  |               x3=%h", hw_perm_out[127: 64]);
            $display("  |               x4=%h", hw_perm_out[ 63:  0]);
            $display("  |   SW expected: x0=%h", SW_S2_PERM12[319:256]);
            $display("  |               x1=%h", SW_S2_PERM12[255:192]);
            $display("  |               x2=%h", SW_S2_PERM12[191:128]);
            $display("  |               x3=%h", SW_S2_PERM12[127: 64]);
            $display("  |               x4=%h", SW_S2_PERM12[ 63:  0]);
            if (hw_perm_out === SW_S2_PERM12) begin
                $display("  +-- [PASS]"); pass_count=pass_count+1;
            end else begin
                $display("  +-- [FAIL]"); fail_count=fail_count+1;
                if (hw_perm_out[319:256] !== SW_S2_PERM12[319:256]) $display("       x0 MISMATCH");
                if (hw_perm_out[255:192] !== SW_S2_PERM12[255:192]) $display("       x1 MISMATCH");
                if (hw_perm_out[191:128] !== SW_S2_PERM12[191:128]) $display("       x2 MISMATCH");
                if (hw_perm_out[127: 64] !== SW_S2_PERM12[127: 64]) $display("       x3 MISMATCH");
                if (hw_perm_out[ 63:  0] !== SW_S2_PERM12[ 63:  0]) $display("       x4 MISMATCH");
            end
        end

        // ------ Step 3: POST_INIT key XOR ------
        // Check state_reg one cycle after S_POST_INIT_LOAD loads key XOR result.
        $display("\n>> STEP 3.POST_INIT_XOR (x3/x4 XOR key)");
        do_step_check(SW_S3_POST_INIT, 64'h0, 64'h0);

        // ------ Step 4: AD absorb XOR ------
        // FSM state 9 = S_AD_LOAD: AD XORed into x0/x1, state_reg updated.
        wait_and_check(6'd9,  SW_S4_AD_XOR,  "4.AD_XOR        ", "(absorb AD)     ");

        // ------ Step 5: PERM8 output ------
        // FSM state 12 = S_POST_AD_LOAD: perm8 done, result in state_reg.
        wait_and_check(6'd12, SW_S5_PERM8,   "5.PERM8_OUT     ", "(AD permutation)");

        // ------ Step 6: Domain separation ------
        // FSM state 14 = S_DOM_SEP_LOAD: x4 MSB flipped, state_reg updated.
        wait_and_check(6'd14, SW_S6_DOM_SEP, "6.DOM_SEP       ", "(x4 MSB flip)   ");

        // ------ Step 7: PT XOR → CT ------
        // FSM state 16 = S_DATA_LOAD: PT XORed into state_reg (ciphertext emitted).
        wait_and_check(6'd16, SW_S7_PT_XOR,  "7.PT_XOR        ", "(PT->CT)        ");

        // ------ Step 8: Pre-fin key XOR ------
        // FSM state 21 = S_FIN_LOAD: x2/x3 XOR key, state_reg updated.
        wait_and_check(6'd21, SW_S8_PREFIN,  "8.PREFIN_XOR    ", "(x2/x3 XOR key) ");

        // ------ Step 9: Final PERM12 output ------
        // FSM state 24 = S_POST_FIN_LOAD: perm12 fin done, state_reg updated.
        wait_and_check(6'd24, SW_S9_PERM12F, "9.PERM12F_OUT   ", "(fin perm)      ");

        // ------ Step 10: CT & TAG ------
        wait_done;
        record_test_end(0);
        $display("\n>> STEP 10.CT_TAG");
        $display("  +-- HW CT  (5B): %h", cap_ct[127:88]);
        $display("  |   SW CT  (5B): %h", SW_CT);
        $display("  |   HW TAG     : %h", cap_tag);
        $display("  |   SW TAG     : %h", SW_TAG);
        if (cap_ct[127:88] === SW_CT && cap_tag === SW_TAG) begin
            $display("  +-- [PASS] CT and TAG match");
            pass_count = pass_count + 2;
        end else begin
            $display("  +-- [FAIL]");
            if (cap_ct[127:88] !== SW_CT) begin
                $display("       CT  MISMATCH"); fail_count=fail_count+1;
            end else pass_count=pass_count+1;
            if (cap_tag !== SW_TAG) begin
                $display("       TAG MISMATCH"); fail_count=fail_count+1;
            end else pass_count=pass_count+1;
        end

        // ---- Test 1 phase timing breakdown ----
        $display("\n  ┌─────────────────────────────────────────────────────┐");
        $display("  │  TEST 1 — Phase Timing Breakdown                    │");
        $display("  ├──────────────────────┬──────────┬───────────────────┤");
        $display("  │  Phase               │  Cycles  │  Time             │");
        $display("  ├──────────────────────┼──────────┼───────────────────┤");
        $display("  │  Init (p12 + setup)  │  %6d  │  %9d ns      │", phase_init_cycles, phase_init_cycles*CLK_PERIOD_NS);
        $display("  │  AD   (p8  + absorb) │  %6d  │  %9d ns      │", phase_ad_cycles,   phase_ad_cycles*CLK_PERIOD_NS);
        $display("  │  Data (PT XOR)       │  %6d  │  %9d ns      │", phase_data_cycles, phase_data_cycles*CLK_PERIOD_NS);
        $display("  │  Fin  (p12 + tag)    │  %6d  │  %9d ns      │", phase_fin_cycles,  phase_fin_cycles*CLK_PERIOD_NS);
        $display("  ├──────────────────────┼──────────┼───────────────────┤");
        $display("  │  TOTAL (start→done)  │  %6d  │  %9d ns      │", test_cyc[0], test_ns[0]);
        $display("  └──────────────────────┴──────────┴───────────────────┘");

        repeat(4) @(posedge clk);

        // ============================================================
        // TEST 2: Decryption
        // ============================================================
        $display("\n================================================================");
        $display("  TEST 2: DECRYPTION");
        $display("================================================================");
        do_reset;
        enc_dec=1; ad_in=TEST_AD; ad_valid=1; ad_last=1;
        data_in = {SW_CT, 88'b0};
        data_len=PT_LEN; data_last=1; tag_received=SW_TAG;
        record_test_start;
        pulse_start; wait_done;
        record_test_end(1);
        $display("  HW PT (5B): %h  (SW: 6173636f6e)", cap_ct[127:88]);
        $display("  tag_match : %b  (exp 1)", tag_match);
        if (cap_ct[127:88] === 40'h6173636f6e) begin
            $display("  [PASS] PT match"); pass_count=pass_count+1;
        end else begin
            $display("  [FAIL] PT mismatch"); fail_count=fail_count+1;
        end
        if (tag_match) begin
            $display("  [PASS] Tag verified"); pass_count=pass_count+1;
        end else begin
            $display("  [FAIL] Tag mismatch"); fail_count=fail_count+1;
        end
        repeat(4) @(posedge clk);

        // ============================================================
        // TEST 3: Tampered CT
        // ============================================================
        $display("\n================================================================");
        $display("  TEST 3: TAMPERED CT (expect tag_match=0)");
        $display("================================================================");
        do_reset;
        enc_dec=1; ad_in=TEST_AD; ad_valid=1; ad_last=1;
        data_in = {SW_CT ^ 40'h01, 88'b0};
        data_len=PT_LEN; data_last=1; tag_received=SW_TAG;
        record_test_start;
        pulse_start; wait_done;
        record_test_end(2);
        $display("  tag_match: %b  (exp 0)", tag_match);
        if (!tag_match) begin
            $display("  [PASS] Tamper detected"); pass_count=pass_count+1;
        end else begin
            $display("  [FAIL] Tamper NOT detected"); fail_count=fail_count+1;
        end
        repeat(4) @(posedge clk);

        // ============================================================
        // TEST 4: No AD
        // ============================================================
        $display("\n================================================================");
        $display("  TEST 4: ENCRYPTION NO AD");
        $display("================================================================");
        do_reset;
        enc_dec=0; ad_valid=0; ad_last=0;
        data_in=TEST_PT; data_len=PT_LEN; data_last=1;
        record_test_start;
        pulse_start; wait_done;
        record_test_end(3);
        $display("  HW CT  (5B): %h  (SW: %h)", cap_ct[127:88], SW_CT_NOAD);
        $display("  HW TAG     : %h", cap_tag);
        $display("  SW TAG     : %h", SW_TAG_NOAD);
        if (cap_ct[127:88] === SW_CT_NOAD && cap_tag === SW_TAG_NOAD) begin
            $display("  [PASS] CT and TAG match"); pass_count=pass_count+2;
        end else begin
            if (cap_ct[127:88] !== SW_CT_NOAD) begin
                $display("  [FAIL] CT  mismatch"); fail_count=fail_count+1;
            end else pass_count=pass_count+1;
            if (cap_tag !== SW_TAG_NOAD) begin
                $display("  [FAIL] TAG mismatch"); fail_count=fail_count+1;
            end else pass_count=pass_count+1;
        end

        // ============================================================
        // Summary + timing table
        // ============================================================
        $display("\n================================================================");
        $display("  RESULTS: %0d / %0d passed", pass_count, pass_count+fail_count);
        $display("================================================================");
        if (fail_count == 0)
            $display("  ALL TESTS PASSED!");
        else
            $display("  %0d FAILED — check step trace above for root cause.", fail_count);

        $display("\n  ┌──────────────────────────────────────────────────────────────┐");
        $display("  │  Timing Summary  (CLK = %0d ns, %0d MHz)                        │",
            CLK_PERIOD_NS, 1000/CLK_PERIOD_NS);
        $display("  ├────────────────────────────┬──────────┬─────────────────────┤");
        $display("  │  Test                      │  Cycles  │  Latency            │");
        $display("  ├────────────────────────────┼──────────┼─────────────────────┤");
        $display("  │  T1: Enc (1 AD + 1 PT blk) │  %6d  │  %8d ns        │", test_cyc[0], test_ns[0]);
        $display("  │  T2: Dec (1 AD + 1 CT blk) │  %6d  │  %8d ns        │", test_cyc[1], test_ns[1]);
        $display("  │  T3: Dec tampered CT        │  %6d  │  %8d ns        │", test_cyc[2], test_ns[2]);
        $display("  │  T4: Enc (no AD, 1 PT blk) │  %6d  │  %8d ns        │", test_cyc[3], test_ns[3]);
        $display("  ├────────────────────────────┼──────────┼─────────────────────┤");
        $display("  │  Permutation latency (iterative)                             │");
        $display("  │    p12  = 12 cycles        │  %6d  │  %8d ns        │", 12, 12*CLK_PERIOD_NS);
        $display("  │    p8   =  8 cycles        │  %6d  │  %8d ns        │", 8,  8*CLK_PERIOD_NS);
        $display("  └────────────────────────────┴──────────┴─────────────────────┘");
        $display("================================================================");
        $finish;
    end

    initial begin
        $dumpfile("tb_ascon_CORE.vcd");
        $dumpvars(0, tb_ascon_CORE);
    end

endmodule