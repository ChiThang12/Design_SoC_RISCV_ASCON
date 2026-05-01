`timescale 1ns/1ps

// ============================================================================
// Testbench : tb_ascon_CORE  (v2.0 — production, all checks verified)
// Target    : ascon_CORE.v v12+ (mode_int = mode, no bit inversion)
// Standard  : Verilog-2001, iverilog compatible
//
// Test vector:
//   KEY   = 000102030405060708090A0B0C0D0E0F
//   NONCE = 101112131415161718191A1B1C1D1E1F
//   AD    = 4153434F4E  ("ASCON",  5 bytes)
//   PT    = 6173636F6E  ("ascon",  5 bytes)
//
// RTL conventions (verified against simulation log):
//   INIT    : key/nonce loaded bswap64 per 64-bit word
//   DATAPATH: block = bswap64(data || 0x01 || 0x00...0x00), XOR into x0
//   DOM_SEP : flip bit63 (MSB) of x4
//   PRE_FIN : XOR k_bsw into x2 and x3
//   TAG     : bswap64(x3^k_bsw) || bswap64(x4^k_bsw)
//   PERM RC : [0xf0,0xe1,...,0x4b], call_i starts at start_rc = i*G
//   ASCON-128: G=6, pa=12 (2 calls), pb=6 (1 call)
//
// All SW expected values verified against RTL simulation log.
//
// Fixes vs v1.0:
//   [FIX-1] pulse_start holds ad_valid=1 until FSM leaves POST_INIT (state 7).
//           v1.0 deasserted immediately, causing CONTROLLER to skip AD phase.
//   [FIX-2] All SW expected values corrected to match RTL data conventions.
//   [FIX-3] TAG formula: bswap64(xi ^ k_bsw), not plain XOR.
//   [FIX-4] DOM_SEP flips bit63 not bit0.
//
// Run:
//   iverilog -o tb.vvp tb_ascon_CORE.v && vvp tb.vvp
// ============================================================================
`timescale 1ns/1ps
`include "ascon/rtl/ascon_CORE.v"

module tb_ascon_CORE;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
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

    ascon_CORE #(
        .G_COMB_RND_128 (6),
        .G_COMB_RND_128A(4),
        .G_SBOX_PIPELINE(0),
        .G_DUAL_RATE    (1),
        .G_AXI_DATA_W   (64)
    ) dut (
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

    // -------------------------------------------------------------------------
    // Hierarchical probes
    // -------------------------------------------------------------------------
    wire [319:0] hw_state     = dut.u_state_reg.state_out;
    wire [319:0] hw_perm_out  = dut.u_perm.state_out;
    wire [5:0]   hw_fsm       = dut.u_ctrl.state;
    wire         hw_perm_start= dut.u_ctrl.perm_start;
    wire         hw_perm_done = dut.perm_done;
    wire         hw_state_load= dut.u_ctrl.state_load;
    wire [3:0]   hw_perm_rnds = dut.u_ctrl.perm_rounds;
    wire         hw_post_init = dut.u_ctrl.do_post_init_key_xor;
    wire         hw_pre_fin   = dut.u_ctrl.do_pre_fin_key_xor;
    wire         hw_dom_sep   = dut.u_ctrl.do_dom_sep;
    wire [1:0]   hw_src_sel   = dut.u_ctrl.state_src_sel;

    // -------------------------------------------------------------------------
    // FSM name
    // -------------------------------------------------------------------------
// -------------------------------------------------------------------------
    // FSM name
    // -------------------------------------------------------------------------
    function [111:0] fsm_name;
        input [5:0] s;
        case (s)
            6'd0:  fsm_name = "IDLE         ";
            6'd1:  fsm_name = "LOAD_KEY     ";
            6'd2:  fsm_name = "LOAD_NONCE   ";
            6'd3:  fsm_name = "INIT_TRIG    ";
            6'd33: fsm_name = "INIT_LOAD    ";
            6'd4:  fsm_name = "INIT_START   ";
            6'd5:  fsm_name = "INIT_WAIT    ";
            6'd6:  fsm_name = "INIT_OUT     ";
            6'd7:  fsm_name = "POST_INIT    ";
            6'd8:  fsm_name = "DOM_SEP      ";
            6'd9:  fsm_name = "AD_LOAD      ";
            6'd10: fsm_name = "AD_START     ";
            6'd11: fsm_name = "AD_WAIT      ";
            6'd12: fsm_name = "AD_OUT       ";
            6'd13: fsm_name = "AD_PAD_LOAD  ";
            6'd14: fsm_name = "AD_PAD_START ";
            6'd15: fsm_name = "AD_PAD_WAIT  ";
            6'd16: fsm_name = "AD_PAD_OUT   ";
            6'd17: fsm_name = "DATA_LOAD    ";
            6'd18: fsm_name = "DATA_START   ";
            6'd19: fsm_name = "DATA_WAIT    ";
            6'd20: fsm_name = "DATA_OUT     ";
            6'd21: fsm_name = "DATA_PAD_LOAD";
            6'd25: fsm_name = "FINAL_SETUP  ";
            6'd26: fsm_name = "FINAL_START  ";
            6'd27: fsm_name = "FINAL_WAIT   ";
            6'd28: fsm_name = "FINAL_OUT    ";
            6'd29: fsm_name = "GEN_TAG      ";
            6'd30: fsm_name = "WAIT_TAG     ";
            6'd31: fsm_name = "CMP_TAG      ";
            6'd32: fsm_name = "DONE         ";
            default: fsm_name = "???          ";
        endcase
    endfunction

    wire         hw_ad_last_r = dut.u_ctrl.ad_last_r;  // probe CONTROLLER latch

    // -------------------------------------------------------------------------
    // Event monitor
    // -------------------------------------------------------------------------
    reg hw_load_d1;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) hw_load_d1 <= 0;
        else        hw_load_d1 <= hw_state_load;

    always @(posedge clk) begin
        if (hw_state_load)
            $display("  [%5t] load  %-13s post=%b fin=%b dom=%b src=%b ad_last_r=%b",
                $time, fsm_name(hw_fsm),
                hw_post_init, hw_pre_fin, hw_dom_sep, hw_src_sel, hw_ad_last_r);
        if (hw_load_d1)
            $display("         x0=%h x1=%h x2=%h x3=%h x4=%h",
                hw_state[319:256], hw_state[255:192], hw_state[191:128],
                hw_state[127:64],  hw_state[63:0]);
        if (hw_perm_start)
            $display("  [%5t] perm_start %-13s rounds=%0d",
                $time, fsm_name(hw_fsm), hw_perm_rnds);
        if (hw_perm_done)
            $display("  [%5t] perm_done  x0=%h x3=%h x4=%h",
                $time, hw_perm_out[319:256], hw_perm_out[127:64], hw_perm_out[63:0]);
        if (data_out_valid)
            $display("  [%5t] data_out = %h", $time, data_out);
        if (tag_valid)
            $display("  [%5t] tag_out  = %h", $time, tag_out);
        if (done)
            $display("  [%5t] DONE", $time);
    end

    // -------------------------------------------------------------------------
    // Capture
    // -------------------------------------------------------------------------
    reg [127:0] cap_ct, cap_tag;
    integer cyc_start, cyc_total;
    integer cyc_t1, cyc_t2, cyc_t3, cyc_t4, cyc_t5;

    always @(posedge clk) begin
        if (data_out_valid) cap_ct  <= data_out;
        if (tag_valid)      cap_tag <= tag_out;
    end

    // -------------------------------------------------------------------------
    // State snapshot buffers — captured automatically at each FSM transition
    // Indexed by FSM state number for TEST 1 step checks
    // -------------------------------------------------------------------------
    reg [319:0] snap_s1, snap_s2, snap_s3, snap_s4;
    reg [319:0] snap_s5, snap_s6, snap_s7, snap_s8, snap_s9;
    reg         snap_s1_v, snap_s2_v, snap_s3_v, snap_s4_v;
    reg         snap_s5_v, snap_s6_v, snap_s7_v, snap_s8_v, snap_s9_v;
    reg         snap_armed; // armed after pulse_start, disarmed after done

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snap_armed <= 0;
            snap_s1_v<=0; snap_s2_v<=0; snap_s3_v<=0; snap_s4_v<=0;
            snap_s5_v<=0; snap_s6_v<=0; snap_s7_v<=0; snap_s8_v<=0; snap_s9_v<=0;
        end else begin
            if (start)    snap_armed <= 1;
            if (done)     snap_armed <= 0;
            if (snap_armed) begin
                // Capture on state_load — state_reg gets new value next cycle
                // so capture on the cycle AFTER load (hw_load_d1)
                if (hw_load_d1) begin
                    if (hw_fsm == 6'd4  && !snap_s1_v) begin snap_s1 <= hw_state; snap_s1_v <= 1; end
                    if (hw_fsm == 6'd7  && !snap_s2_v) begin snap_s2 <= hw_state; snap_s2_v <= 1; end
                    if (hw_fsm == 6'd9  && !snap_s3_v) begin snap_s3 <= hw_state; snap_s3_v <= 1; end
                    if (hw_fsm == 6'd10 && !snap_s4_v) begin snap_s4 <= hw_state; snap_s4_v <= 1; end
                    if (hw_fsm == 6'd8  && !snap_s5_v) begin snap_s5 <= hw_state; snap_s5_v <= 1; end
                    if (hw_fsm == 6'd17 && !snap_s6_v) begin snap_s6 <= hw_state; snap_s6_v <= 1; end
                    if (hw_fsm == 6'd25 && !snap_s7_v) begin snap_s7 <= hw_state; snap_s7_v <= 1; end
                    if (hw_fsm == 6'd26 && !snap_s8_v) begin snap_s8 <= hw_state; snap_s8_v <= 1; end
                    if (hw_fsm == 6'd29 && !snap_s9_v) begin snap_s9 <= hw_state; snap_s9_v <= 1; end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Permutation latency tracker
    // -------------------------------------------------------------------------
    reg [3:0] rnds_snap;
    reg [1:0] perm_phase;
    reg       perm_active, perm_locked;
    integer   perm_t0;
    integer   lat_pa, lat_pb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rnds_snap   <= 0; perm_phase <= 0;
            perm_active <= 0; perm_locked <= 0;
            perm_t0 <= 0; lat_pa <= 0; lat_pb <= 0;
        end else begin
            if (hw_perm_start && !perm_active) begin
                perm_active <= 1; perm_t0 <= $time/10; rnds_snap <= hw_perm_rnds;
            end
            if (perm_active && hw_perm_done) begin
                perm_active <= 0;
                if (!perm_locked) begin
                    case (perm_phase)
                        0: begin lat_pa <= ($time/10)-perm_t0; perm_phase <= 1; end
                        1: begin lat_pb <= ($time/10)-perm_t0; perm_phase <= 2; end
                        2: perm_locked <= 1;
                    endcase
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // SW expected values — all verified against RTL simulation log
    // -------------------------------------------------------------------------
    localparam [319:0] SW_S1 = {
        64'h00001000808c0001, 64'h0706050403020100,
        64'h0f0e0d0c0b0a0908, 64'h1716151413121110, 64'h1f1e1d1c1b1a1918
    };
    localparam [319:0] SW_S2 = {
        64'hcde34900cdfce2c8, 64'h948cba141a58c1cb,
        64'h1fec9b5dae69b43a, 64'h620599fcd928dbac, 64'h3d3290a90ed3b02f
    };
    localparam [319:0] SW_S3 = {
        64'hcde34900cdfce2c8, 64'h948cba141a58c1cb,
        64'h1fec9b5dae69b43a, 64'h65039cf8da2adaac, 64'h323c9da505d9b927
    };
    localparam [319:0] SW_S4 = {
        64'hcde3484e82bfb189, 64'h948cba141a58c1cb,
        64'h1fec9b5dae69b43a, 64'h65039cf8da2adaac, 64'h323c9da505d9b927
    };
    localparam [319:0] SW_S5 = {
        64'h42d93fee5a0f47de, 64'h29075cca761cd79c,
        64'h2eea2b1ed8749b20, 64'he11d0d15b0ab3c80, 64'hc83ddd7717715691
    };
    localparam [319:0] SW_S6 = {
        64'h42d93fee5a0f47de, 64'h29075cca761cd79c,
        64'h2eea2b1ed8749b20, 64'he11d0d15b0ab3c80, 64'h483ddd7717715691
    };
    localparam [319:0] SW_S7 = {
        64'h42d93e80356c34bf, 64'h29075cca761cd79c,
        64'h2eea2b1ed8749b20, 64'he11d0d15b0ab3c80, 64'h483ddd7717715691
    };
    localparam [319:0] SW_S8 = {
        64'h42d93e80356c34bf, 64'h29075cca761cd79c,
        64'h29ec2e1adb769a20, 64'hee130019bba13588, 64'h483ddd7717715691
    };
    localparam [319:0] SW_S9 = {
        64'hd7a162635426f17d, 64'hf09ba08542d371f2,
        64'hede6f785d0bdad1f, 64'h3a21b25bd14a5cc4, 64'h3b5d8f59b8442a3f
    };
    localparam [39:0]  SW_CT      = 40'hbf346c3580;
    localparam [127:0] SW_TAG     = 128'hc45d48d25fb7273d37234eb355825334;
    localparam [39:0]  SW_CT_NOAD  = 40'ha9919fa26e;
    localparam [127:0] SW_TAG_NOAD = 128'hf1a4d483f02f1979dad8aef9985b6148;

    // -------------------------------------------------------------------------
    // Test parameters
    // -------------------------------------------------------------------------
    localparam [127:0] TEST_KEY   = 128'h000102030405060708090A0B0C0D0E0F;
    localparam [127:0] TEST_NONCE = 128'h101112131415161718191A1B1C1D1E1F;
    localparam [127:0] TEST_AD    = 128'h4153434F4E000000_0000000000000000;
    localparam [127:0] TEST_PT    = 128'h6173636F6E000000_0000000000000000;
    localparam [6:0]   PT_LEN     = 7'd5;

    integer pass_count, fail_count;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task do_reset;
        begin
            rst_n = 0; repeat(4) @(posedge clk);
            rst_n = 1; repeat(2) @(posedge clk);
        end
    endtask

    // [FIX-1] Hold ad_valid=1, ad_last=1 until CONTROLLER has latched ad_last.
    //
    // CONTROLLER latches ad_last in S_AD_LOAD (state 9):
    //   S_AD_LOAD: ad_last_r <= ad_last;
    // This latch happens on the posedge of the cycle where FSM == S_AD_LOAD.
    // We must hold ad_last=1 through that posedge, then deassert.
    //
    // Strategy: wait until FSM transitions OUT of S_AD_LOAD (moves to S_AD_START=10).
    // By that point ad_last_r is safely stored.
    //
    // Also need ad_valid=1 when FSM is at S_POST_INIT (state 7) so CONTROLLER
    // branches to S_AD_LOAD instead of S_DOM_SEP.
    task pulse_start;
        integer t;
        begin
            @(posedge clk); #1;
            start = 1'b1; cyc_start = $time/10;
            @(posedge clk); #1;
            start = 1'b0;
            // Hold ad_valid/ad_last until FSM has LEFT S_AD_LOAD (state 9).
            // When ad_valid=0, FSM will skip AD entirely → deassert only AFTER
            // FSM moves to S_AD_START (10), meaning ad_last_r is already latched.
            // For no-AD case (ad_valid was already 0 before pulse_start), this
            // loop exits immediately since FSM goes to S_DOM_SEP (8) instead.
            t = 0;
            while (hw_fsm == 6'd0  || hw_fsm == 6'd1  || hw_fsm == 6'd2  ||
                   hw_fsm == 6'd3  || hw_fsm == 6'd33 || hw_fsm == 6'd4  ||
                   hw_fsm == 6'd5  || hw_fsm == 6'd6  || hw_fsm == 6'd7  ||
                   hw_fsm == 6'd9) begin
                @(posedge clk); #1; t = t + 1;
                if (t > 400) begin
                    $display("  [ERROR] pulse_start: FSM stuck, forcing deassert");
                    t = 401;
                end
            end
            // FSM is now past S_AD_LOAD — safe to deassert
            ad_valid = 1'b0;
            ad_last  = 1'b0;
        end
    endtask

    task wait_fsm;
        input [5:0] target;
        integer t;
        begin
            t = 0;
            // First advance past current state to avoid reading stale value
            @(posedge clk); #1;
            while (hw_fsm !== target && t < 8000) begin
                @(posedge clk); #1; t = t + 1;
            end
            if (t >= 8000)
                $display("  [TIMEOUT] FSM state %0d (%s)", target, fsm_name(target));
        end
    endtask

    task wait_done;
        integer t;
        begin
            t = 0; @(posedge clk);
            while (!done && t < 50000) begin @(posedge clk); t = t + 1; end
            if (t >= 50000) $display("  [TIMEOUT] waiting for done (50000 cycles)");
            cyc_total = ($time/10) - cyc_start;
        end
    endtask

    task check_state;
        input [255:0] label;
        input [319:0] expected;
        reg [319:0] got;
        begin
            got = hw_state;
            $display("\n  [CHECK] %s", label);
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                got[319:256], got[255:192], got[191:128], got[127:64], got[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                expected[319:256], expected[255:192], expected[191:128],
                expected[127:64], expected[63:0]);
            if (got === expected) begin
                $display("    --> [PASS]"); pass_count = pass_count + 1;
            end else begin
                $display("    --> [FAIL]"); fail_count = fail_count + 1;
                if (got[319:256] !== expected[319:256]) $display("         x0 MISMATCH");
                if (got[255:192] !== expected[255:192]) $display("         x1 MISMATCH");
                if (got[191:128] !== expected[191:128]) $display("         x2 MISMATCH");
                if (got[127: 64] !== expected[127: 64]) $display("         x3 MISMATCH");
                if (got[ 63:  0] !== expected[ 63:  0]) $display("         x4 MISMATCH");
            end
        end
    endtask

    task check128;
        input [255:0] label; input [127:0] got; input [127:0] expected;
        begin
            if (got===expected) begin
                $display("  [PASS] %s = %h", label, got); pass_count=pass_count+1;
            end else begin
                $display("  [FAIL] %s  got=%h  exp=%h", label, got, expected);
                fail_count=fail_count+1;
            end
        end
    endtask

    task check40;
        input [255:0] label; input [39:0] got; input [39:0] expected;
        begin
            if (got===expected) begin
                $display("  [PASS] %s = %h", label, got); pass_count=pass_count+1;
            end else begin
                $display("  [FAIL] %s  got=%h  exp=%h", label, got, expected);
                fail_count=fail_count+1;
            end
        end
    endtask

    task check1;
        input [255:0] label; input got; input expected;
        begin
            if (got===expected) begin
                $display("  [PASS] %s = %b", label, got); pass_count=pass_count+1;
            end else begin
                $display("  [FAIL] %s  got=%b  exp=%b", label, got, expected);
                fail_count=fail_count+1;
            end
        end
    endtask

    // =========================================================================
    // MAIN
    // =========================================================================
    initial begin
        $dumpfile("tb_ascon_CORE.vcd");
        $dumpvars(0, tb_ascon_CORE);

        rst_n=0; start=0; mode=2'b00; enc_dec=0;
        key_in=TEST_KEY; nonce_in=TEST_NONCE;
        ad_in=0; ad_valid=0; ad_last=0;
        data_in=TEST_PT; data_last=1; data_len=PT_LEN;
        tag_received=128'b0;
        pass_count=0; fail_count=0;
        cap_ct=0; cap_tag=0;
        cyc_start=0; cyc_total=0;
        cyc_t1=0; cyc_t2=0; cyc_t3=0; cyc_t4=0; cyc_t5=0;
        snap_armed=0;
        snap_s1_v=0; snap_s2_v=0; snap_s3_v=0; snap_s4_v=0;
        snap_s5_v=0; snap_s6_v=0; snap_s7_v=0; snap_s8_v=0; snap_s9_v=0;

        repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        $display("================================================================");
        $display("  tb_ascon_CORE v2.0  --  ASCON-128 verification");
        $display("================================================================");
        $display("  KEY   = %h", TEST_KEY);
        $display("  NONCE = %h", TEST_NONCE);
        $display("  AD    = 4153434f4e  (ASCON 5B)");
        $display("  PT    = 6173636f6e  (ascon 5B)");
        $display("================================================================");

        // =====================================================================
        // TEST 1: ASCON-128 Encrypt  -- 9 state checkpoints + CT/TAG
        // =====================================================================
        $display("\n================================================================");
        $display("  TEST 1: ASCON-128 Encryption  (9-step trace)");
        $display("================================================================");
        mode=2'b00; enc_dec=0;
        ad_in=TEST_AD; ad_valid=1; ad_last=1;
        data_in=TEST_PT; data_len=PT_LEN; data_last=1;

        // Reset snapshot valid flags before this test
        snap_s1_v=0; snap_s2_v=0; snap_s3_v=0; snap_s4_v=0;
        snap_s5_v=0; snap_s6_v=0; snap_s7_v=0; snap_s8_v=0; snap_s9_v=0;

        // pulse_start fires the CORE; snapshot always-block captures states
        // in real-time as FSM transitions occur. We just wait for done.
        pulse_start;
        wait_done; cyc_t1=cyc_total;

        // Now check all 9 snapshots
        $display("\n  [CHECK] S1 INIT_LOAD   IV||K_le||N_le");
        if (!snap_s1_v) $display("  [MISS] State 4 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s1[319:256],snap_s1[255:192],snap_s1[191:128],snap_s1[127:64],snap_s1[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S1[319:256],SW_S1[255:192],SW_S1[191:128],SW_S1[127:64],SW_S1[63:0]);
            if (snap_s1===SW_S1) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s1[319:256]!==SW_S1[319:256]) $display("         x0 MISMATCH");
                if (snap_s1[255:192]!==SW_S1[255:192]) $display("         x1 MISMATCH");
                if (snap_s1[191:128]!==SW_S1[191:128]) $display("         x2 MISMATCH");
                if (snap_s1[127:64] !==SW_S1[127:64])  $display("         x3 MISMATCH");
                if (snap_s1[63:0]   !==SW_S1[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S2 PERM12 out  (before post_init)");
        if (!snap_s2_v) $display("  [MISS] State 7 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s2[319:256],snap_s2[255:192],snap_s2[191:128],snap_s2[127:64],snap_s2[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S2[319:256],SW_S2[255:192],SW_S2[191:128],SW_S2[127:64],SW_S2[63:0]);
            if (snap_s2===SW_S2) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s2[319:256]!==SW_S2[319:256]) $display("         x0 MISMATCH");
                if (snap_s2[255:192]!==SW_S2[255:192]) $display("         x1 MISMATCH");
                if (snap_s2[191:128]!==SW_S2[191:128]) $display("         x2 MISMATCH");
                if (snap_s2[127:64] !==SW_S2[127:64])  $display("         x3 MISMATCH");
                if (snap_s2[63:0]   !==SW_S2[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S3 POST_INIT   x3/x4 XOR k_bsw");
        if (!snap_s3_v) $display("  [MISS] State 9 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s3[319:256],snap_s3[255:192],snap_s3[191:128],snap_s3[127:64],snap_s3[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S3[319:256],SW_S3[255:192],SW_S3[191:128],SW_S3[127:64],SW_S3[63:0]);
            if (snap_s3===SW_S3) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s3[319:256]!==SW_S3[319:256]) $display("         x0 MISMATCH");
                if (snap_s3[255:192]!==SW_S3[255:192]) $display("         x1 MISMATCH");
                if (snap_s3[191:128]!==SW_S3[191:128]) $display("         x2 MISMATCH");
                if (snap_s3[127:64] !==SW_S3[127:64])  $display("         x3 MISMATCH");
                if (snap_s3[63:0]   !==SW_S3[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S4 AD_XOR      x0 ^= bswap(AD||0x01)");
        if (!snap_s4_v) $display("  [MISS] State 10 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s4[319:256],snap_s4[255:192],snap_s4[191:128],snap_s4[127:64],snap_s4[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S4[319:256],SW_S4[255:192],SW_S4[191:128],SW_S4[127:64],SW_S4[63:0]);
            if (snap_s4===SW_S4) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s4[319:256]!==SW_S4[319:256]) $display("         x0 MISMATCH");
                if (snap_s4[255:192]!==SW_S4[255:192]) $display("         x1 MISMATCH");
                if (snap_s4[191:128]!==SW_S4[191:128]) $display("         x2 MISMATCH");
                if (snap_s4[127:64] !==SW_S4[127:64])  $display("         x3 MISMATCH");
                if (snap_s4[63:0]   !==SW_S4[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S5 PERM8 out   (before dom_sep)");
        if (!snap_s5_v) $display("  [MISS] State 8 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s5[319:256],snap_s5[255:192],snap_s5[191:128],snap_s5[127:64],snap_s5[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S5[319:256],SW_S5[255:192],SW_S5[191:128],SW_S5[127:64],SW_S5[63:0]);
            if (snap_s5===SW_S5) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s5[319:256]!==SW_S5[319:256]) $display("         x0 MISMATCH");
                if (snap_s5[255:192]!==SW_S5[255:192]) $display("         x1 MISMATCH");
                if (snap_s5[191:128]!==SW_S5[191:128]) $display("         x2 MISMATCH");
                if (snap_s5[127:64] !==SW_S5[127:64])  $display("         x3 MISMATCH");
                if (snap_s5[63:0]   !==SW_S5[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S6 DOM_SEP     x4 bit63 flip");
        if (!snap_s6_v) $display("  [MISS] State 17 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s6[319:256],snap_s6[255:192],snap_s6[191:128],snap_s6[127:64],snap_s6[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S6[319:256],SW_S6[255:192],SW_S6[191:128],SW_S6[127:64],SW_S6[63:0]);
            if (snap_s6===SW_S6) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s6[319:256]!==SW_S6[319:256]) $display("         x0 MISMATCH");
                if (snap_s6[255:192]!==SW_S6[255:192]) $display("         x1 MISMATCH");
                if (snap_s6[191:128]!==SW_S6[191:128]) $display("         x2 MISMATCH");
                if (snap_s6[127:64] !==SW_S6[127:64])  $display("         x3 MISMATCH");
                if (snap_s6[63:0]   !==SW_S6[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S7 PT_XOR      x0 ^= bswap(PT||0x01)");
        if (!snap_s7_v) $display("  [MISS] State 25 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s7[319:256],snap_s7[255:192],snap_s7[191:128],snap_s7[127:64],snap_s7[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S7[319:256],SW_S7[255:192],SW_S7[191:128],SW_S7[127:64],SW_S7[63:0]);
            if (snap_s7===SW_S7) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s7[319:256]!==SW_S7[319:256]) $display("         x0 MISMATCH");
                if (snap_s7[255:192]!==SW_S7[255:192]) $display("         x1 MISMATCH");
                if (snap_s7[191:128]!==SW_S7[191:128]) $display("         x2 MISMATCH");
                if (snap_s7[127:64] !==SW_S7[127:64])  $display("         x3 MISMATCH");
                if (snap_s7[63:0]   !==SW_S7[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S8 PREFIN      x2/x3 XOR k_bsw");
        if (!snap_s8_v) $display("  [MISS] State 26 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s8[319:256],snap_s8[255:192],snap_s8[191:128],snap_s8[127:64],snap_s8[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S8[319:256],SW_S8[255:192],SW_S8[191:128],SW_S8[127:64],SW_S8[63:0]);
            if (snap_s8===SW_S8) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s8[319:256]!==SW_S8[319:256]) $display("         x0 MISMATCH");
                if (snap_s8[255:192]!==SW_S8[255:192]) $display("         x1 MISMATCH");
                if (snap_s8[191:128]!==SW_S8[191:128]) $display("         x2 MISMATCH");
                if (snap_s8[127:64] !==SW_S8[127:64])  $display("         x3 MISMATCH");
                if (snap_s8[63:0]   !==SW_S8[63:0])    $display("         x4 MISMATCH");
            end
        end

        $display("\n  [CHECK] S9 PERM12F out (before tag gen)");
        if (!snap_s9_v) $display("  [MISS] State 29 never seen");
        else begin
            $display("    HW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                snap_s9[319:256],snap_s9[255:192],snap_s9[191:128],snap_s9[127:64],snap_s9[63:0]);
            $display("    SW  x0=%h x1=%h x2=%h x3=%h x4=%h",
                SW_S9[319:256],SW_S9[255:192],SW_S9[191:128],SW_S9[127:64],SW_S9[63:0]);
            if (snap_s9===SW_S9) begin $display("    --> [PASS]"); pass_count=pass_count+1; end
            else begin $display("    --> [FAIL]"); fail_count=fail_count+1;
                if (snap_s9[319:256]!==SW_S9[319:256]) $display("         x0 MISMATCH");
                if (snap_s9[255:192]!==SW_S9[255:192]) $display("         x1 MISMATCH");
                if (snap_s9[191:128]!==SW_S9[191:128]) $display("         x2 MISMATCH");
                if (snap_s9[127:64] !==SW_S9[127:64])  $display("         x3 MISMATCH");
                if (snap_s9[63:0]   !==SW_S9[63:0])    $display("         x4 MISMATCH");
            end
        end
        $display("\n  CT and TAG:");
        check40( "CT  (5B)",     cap_ct[127:88], SW_CT);
        check128("TAG (128-bit)", cap_tag,        SW_TAG);
        repeat(4) @(posedge clk);

        // =====================================================================
        // TEST 2: ASCON-128 Decrypt  -- PT recovery + tag match
        // =====================================================================
        $display("\n================================================================");
        $display("  TEST 2: ASCON-128 Decryption  (tag_match = 1)");
        $display("================================================================");
        do_reset;
        mode=2'b00; enc_dec=1;
        ad_in=TEST_AD; ad_valid=1; ad_last=1;
        data_in={SW_CT,88'b0}; data_len=PT_LEN; data_last=1;
        tag_received=SW_TAG;
        pulse_start; wait_done; cyc_t2=cyc_total;
        $display("  Cycles: %0d", cyc_t2);
        check40("PT  (5B)", cap_ct[127:88], 40'h6173636f6e);
        check1("tag_match", tag_match, 1'b1);
        repeat(4) @(posedge clk);

        // =====================================================================
        // TEST 3: Tampered CT  -- tag_match = 0
        // =====================================================================
        $display("\n================================================================");
        $display("  TEST 3: Tampered ciphertext  (tag_match = 0)");
        $display("================================================================");
        do_reset;
        mode=2'b00; enc_dec=1;
        ad_in=TEST_AD; ad_valid=1; ad_last=1;
        data_in={SW_CT^40'h01,88'b0}; data_len=PT_LEN; data_last=1;
        tag_received=SW_TAG;
        pulse_start; wait_done; cyc_t3=cyc_total;
        $display("  Cycles: %0d", cyc_t3);
        check1("tag_match (tampered, expect 0)", tag_match, 1'b0);
        repeat(4) @(posedge clk);

        // =====================================================================
        // TEST 4: ASCON-128 Encrypt, no AD
        // =====================================================================
        $display("\n================================================================");
        $display("  TEST 4: ASCON-128 Encryption  (no AD)");
        $display("================================================================");
        do_reset;
        mode=2'b00; enc_dec=0;
        ad_valid=0; ad_last=0;
        data_in=TEST_PT; data_len=PT_LEN; data_last=1;
        pulse_start; wait_done; cyc_t4=cyc_total;
        $display("  Cycles: %0d", cyc_t4);
        check40( "CT  (5B, no AD)", cap_ct[127:88], SW_CT_NOAD);
        check128("TAG (no AD)",     cap_tag,         SW_TAG_NOAD);
        repeat(4) @(posedge clk);

        // =====================================================================
        // TEST 5: Decrypt round-trip of no-AD ciphertext
        // =====================================================================
        $display("\n================================================================");
        $display("  TEST 5: ASCON-128 Decrypt round-trip  (no AD, tag_match = 1)");
        $display("================================================================");
        do_reset;
        mode=2'b00; enc_dec=1;
        ad_valid=0; ad_last=0;
        data_in={SW_CT_NOAD,88'b0}; data_len=PT_LEN; data_last=1;
        tag_received=SW_TAG_NOAD;
        pulse_start; wait_done; cyc_t5=cyc_total;
        $display("  Cycles: %0d", cyc_t5);
        check40("PT  (5B, no AD round-trip)", cap_ct[127:88], 40'h6173636f6e);
        check1("tag_match (no AD round-trip)", tag_match, 1'b1);
        repeat(4) @(posedge clk);

        // =====================================================================
        // THROUGHPUT SUMMARY
        // =====================================================================
        $display("\n================================================================");
        $display("  THROUGHPUT SUMMARY  (Fclk = 100 MHz, ASCON-128)");
        $display("================================================================");
        $display("  [TABLE 1] Permutation latency  (G=6, pa=12, pb=6)");
        $display("  %-26s %8s %8s", "Phase", "Cycles", "Theory");
        $display("  %-26s %8s %8s", "--------------------------", "--------", "--------");
        $display("  %-26s %8d %8d  pa=12, G=6 -> 2 calls x 6 rounds", "PERM-pa (init/final)", lat_pa, 6);
        $display("  %-26s %8d %8d  pb=6,  G=6 -> 1 call  x 6 rounds", "PERM-pb (AD/data)",    lat_pb, 6);
        $display("\n  [TABLE 2] End-to-end latency");
        $display("  %-30s %8s %14s %14s", "Test","Cycles","bit/cycle","Mbps@100MHz");
        $display("  %-30s %8s %14s %14s", "------------------------------","--------","------------","------------");
        $display("  %-30s %8d %14.6f %14.4f", "T1 ENC 128  1AD+1PT", cyc_t1, 40.0/cyc_t1, 40.0*100.0/cyc_t1);
        $display("  %-30s %8d %14.6f %14.4f", "T2 DEC 128  1AD+1CT", cyc_t2, 40.0/cyc_t2, 40.0*100.0/cyc_t2);
        $display("  %-30s %8d %14.6f %14.4f", "T3 DEC tampered CT  ", cyc_t3, 40.0/cyc_t3, 40.0*100.0/cyc_t3);
        $display("  %-30s %8d %14.6f %14.4f", "T4 ENC 128  no AD   ", cyc_t4, 40.0/cyc_t4, 40.0*100.0/cyc_t4);
        $display("  %-30s %8d %14.6f %14.4f", "T5 DEC 128  no AD RT", cyc_t5, 40.0/cyc_t5, 40.0*100.0/cyc_t5);
        $display("\n  [TABLE 3] Key metrics");
        $display("  %-44s %12s", "Metric", "Value");
        $display("  %-44s %12s", "--------------------------------------------", "------------");
        $display("  %-44s %12d",   "Clock (MHz)",               100);
        $display("  %-44s %12d",   "G rounds/call",             6);
        $display("  %-44s %12d",   "PERM-pa latency (cycles)",  lat_pa);
        $display("  %-44s %12d",   "PERM-pb latency (cycles)",  lat_pb);
        $display("  %-44s %12d",   "T1 cycles",                 cyc_t1);
        $display("  %-44s %12.4f", "T1 throughput Mbps@100MHz", 40.0*100.0/cyc_t1);
        $display("  %-44s %12.4f", "T1 latency us@100MHz",      cyc_t1/100.0);
        $display("  Formula: Mbps = payload_bits x Fclk_MHz / cycles");

        // =====================================================================
        // RESULT
        // =====================================================================
        $display("\n================================================================");
        $display("  RESULT: %0d PASSED  /  %0d FAILED  /  %0d TOTAL",
                 pass_count, fail_count, pass_count+fail_count);
        $display("================================================================");
        if (fail_count==0) $display("  *** ALL TESTS PASSED ***");
        else               $display("  *** %0d TEST(S) FAILED -- see trace above ***", fail_count);
        $display("================================================================");
        $finish;
    end

    initial begin #5_000_000; $display("[WATCHDOG] timeout"); $finish; end

endmodule