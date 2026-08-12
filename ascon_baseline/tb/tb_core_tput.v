`timescale 1ns/1ps
// ============================================================================
// tb_core_tput.v  — CPU-direct ASCON CORE throughput benchmark
//
// Compatible với ascon_CONTROLLER.v v9 (5-bit state encoding):
//   S_DATA_LOAD=9, S_DATA_PERM=10, S_DOM_SEP=8, S_PRE_FIN=13 ...
//
// Đo throughput thực tế khi feed data trực tiếp vào CORE (không qua DMA/AXI).
// Dùng data_ready handshake để gửi block liên tục.
//
// Fclk = 100 MHz.  Throughput = payload_bits × 100 / total_cycles  (Mbps)
// ============================================================================
`include "ascon_baseline/rtl/ascon_CORE.v"

module tb_core_tput;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    reg         clk, rst_n, start;
    reg  [1:0]  mode;
    reg         enc_dec;
    reg  [127:0] key_in, nonce_in, ad_in, data_in, tag_received;
    reg          ad_valid, ad_last;
    reg          data_valid, data_last;
    reg  [6:0]   data_len;

    wire [127:0] data_out;
    wire         data_out_valid;
    wire         data_ready, ad_ready;
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
        .data_in(data_in), .data_valid(data_valid), .data_last(data_last),
        .data_len(data_len),
        .tag_received(tag_received),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .data_ready(data_ready), .ad_ready(ad_ready),
        .tag_out(tag_out), .tag_valid(tag_valid),
        .tag_match(tag_match), .done(done), .busy(busy)
    );

    initial clk = 0;
    always #5 clk = ~clk;   // 10 ns period = 100 MHz

    // FSM probe — 5-bit (current CONTROLLER v9 encoding)
    wire [4:0] hw_fsm = dut.u_ctrl.state;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task do_reset;
        begin
            rst_n = 0; repeat(4) @(posedge clk);
            rst_n = 1; repeat(2) @(posedge clk);
        end
    endtask

    // Pulse start, wait until data_ready (FSM reached DATA_LOAD after INIT+DOM_SEP)
    task pulse_start_wait_data;
        integer t;
        begin
            @(posedge clk); #1;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;
            t = 0;
            while (!data_ready && t < 2000) begin
                @(posedge clk); #1; t = t + 1;
            end
            if (t >= 2000)
                $display("  [ERROR] pulse_start_wait_data: data_ready never asserted");
        end
    endtask

    // -------------------------------------------------------------------------
    // Benchmark state
    // -------------------------------------------------------------------------
    integer cyc0, cyc1, cyc_total;

    // -------------------------------------------------------------------------
    // run_tput: feed N blocks of blk_bytes each, measure cycles
    //   Uses data_ready handshake: wait for data_ready=1, present block, advance clock.
    //   Timing: cyc0 = cycle when first block consumed, cyc1 = cycle of done.
    // -------------------------------------------------------------------------
    task run_tput;
        input integer n_blocks;
        input integer blk_bytes;
        integer i, t;
        real payload_bits, tput_mbps, tput_gbps;
        begin
            // Present block 0 before start
            data_in    = 128'h0123456789ABCDEF_FEDCBA9876543210;
            data_len   = blk_bytes[6:0];
            data_valid = 1'b1;
            data_last  = (n_blocks == 1) ? 1'b1 : 1'b0;

            // Initialization: INIT_LOAD → INIT_PERM → POST_INIT → DOM_SEP → DATA_LOAD
            pulse_start_wait_data;

            // data_ready=1 now (FSM is in DATA_LOAD, about to consume block 0)
            cyc0 = $time / 10;

            for (i = 0; i < n_blocks; i = i + 1) begin
                // Update data_in for current block
                data_in   = {64'h0123456789000000 + i[63:0], 64'hFEDCBA9876543210};
                data_len  = blk_bytes[6:0];
                data_last = (i == n_blocks - 1) ? 1'b1 : 1'b0;
                data_valid = 1'b1;

                // Wait until FSM is in DATA_LOAD (data_ready=1)
                t = 0;
                while (!data_ready && t < 200) begin
                    @(posedge clk); #1; t = t + 1;
                end
                if (t >= 200) $display("  [ERROR] data_ready stuck low at block %0d", i);

                // Advance one clock: FSM consumes this block
                @(posedge clk); #1;
            end

            // Wait for done
            data_valid = 1'b0;
            data_last  = 1'b0;
            t = 0;
            while (!done && t < 100000) begin @(posedge clk); #1; t = t + 1; end
            if (t >= 100000) $display("  [ERROR] done never asserted");

            cyc1 = $time / 10;
            cyc_total = cyc1 - cyc0;

            payload_bits = n_blocks * blk_bytes * 8.0;
            tput_mbps    = payload_bits * 100.0 / cyc_total;
            tput_gbps    = tput_mbps / 1000.0;

            $display("  N=%4d  bytes/blk=%2d  total_bytes=%5d  cycles=%5d  %7.2f Mbps  %.3f Gbps",
                n_blocks, blk_bytes, n_blocks*blk_bytes, cyc_total, tput_mbps, tput_gbps);
        end
    endtask

    // -------------------------------------------------------------------------
    // MAIN
    // -------------------------------------------------------------------------
    localparam [127:0] KEY   = 128'h000102030405060708090A0B0C0D0E0F;
    localparam [127:0] NONCE = 128'h101112131415161718191A1B1C1D1E1F;

    initial begin
        rst_n=0; start=0; mode=2'b00; enc_dec=0;
        key_in=KEY; nonce_in=NONCE;
        ad_in=0; ad_valid=0; ad_last=0;
        data_in=0; data_valid=0; data_last=0; data_len=7'd16;
        tag_received=128'b0;
        cyc0=0; cyc1=0; cyc_total=0;

        repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        $display("====================================================================");
        $display("  ASCON CORE CPU-Direct Throughput Benchmark");
        $display("  G_COMB_RND_128=6  G_SBOX_PIPELINE=0  Fclk=100MHz");
        $display("  is_128a=1 (hardwired) → rate=16B, x0+x1 XOR per block");
        $display("====================================================================");

        // ------------------------------------------------------------------
        // BENCHMARK 1: 16-byte blocks (full NIST rate) — maximum throughput
        // ------------------------------------------------------------------
        $display("\n[BENCH 1] 16-byte blocks  (full 128-bit rate, NIST Ascon-AEAD128)");
        $display("  N=1 (single block, includes INIT overhead):");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(1, 16);

        $display("  N=8:");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(8, 16);

        $display("  N=64:");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(64, 16);

        $display("  N=128 (steady-state ~2KB):");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(128, 16);

        $display("  N=256 (steady-state ~4KB):");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(256, 16);

        // ------------------------------------------------------------------
        // BENCHMARK 2: 8-byte blocks (DMA-equivalent, only upper 64-bit PT)
        // ------------------------------------------------------------------
        $display("\n[BENCH 2] 8-byte blocks  (DMA-equivalent, upper 64-bit only)");
        $display("  N=128 (1024 bytes, same as v1 testbench T6):");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(128, 8);

        $display("  N=256 (2048 bytes, steady-state):");
        do_reset; mode=2'b00; enc_dec=0; ad_valid=0; ad_last=1;
        run_tput(256, 8);

        // ------------------------------------------------------------------
        // SUMMARY
        // ------------------------------------------------------------------
        $display("\n====================================================================");
        $display("  THROUGHPUT FORMULA:");
        $display("    steady-state bps/Hz = (bytes_per_block * 8) / cycles_per_block");
        $display("    G_SBOX_PIPELINE=0 → 1 perm/cycle → ~3 cycles/block");
        $display("    16B block: 128 bits / 3 cyc = 42.67 bit/cyc = 4267 Mbps @100MHz");
        $display("    8B  block:  64 bits / 3 cyc = 21.33 bit/cyc = 2133 Mbps @100MHz");
        $display("====================================================================");

        $finish;
    end

    // Watchdog
    initial begin #20_000_000; $display("[WATCHDOG] timeout"); $finish; end

endmodule
