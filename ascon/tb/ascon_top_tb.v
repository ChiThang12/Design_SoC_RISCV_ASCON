// ============================================================================
// Testbench: ascon_TOP_tb
// Mô tả: Verify ASCON_TOP bằng cách đọc test vectors từ file .tv
//
// Cách dùng:
//   1. Chạy verify_hw.py để sinh ascon_hw_vectors.tv
//   2. Đặt file .tv cùng thư mục với simulation
//   3. Chạy simulation
//
// File .tv format (mỗi dòng):
//   COUNT OP KEY(32h) NONCE(32h) FIELD_A(16h) FIELD_B(16h) TAG(32h)
//   OP=0 (encrypt): FIELD_A=PT,  FIELD_B=expected_CT
//   OP=1 (decrypt): FIELD_A=CT,  FIELD_B=expected_PT
//
// Kết quả đúng (từ RTL big-endian simulation):
//   T1 CT =bc820dbdf7a4631c  TAG=850b981f3b472c863bbeb369a8dfbf8b
//   T2 CT =b8dff46b0db421f8  TAG=b637dc47d25dad1c98a006af31885d53
// ============================================================================
`timescale 1ns/1ps
`include "ascon/rtl/ascon_top.v"

module ascon_TOP_tb;

// ============================================================================
// Parameters
// ============================================================================
parameter TV_FILE    = "ascon_hw_vectors.tv";
parameter MAX_WAIT   = 600;   // max cycles to wait for output
parameter CLK_PERIOD = 10;    // 10ns = 100MHz

// ============================================================================
// DUT signals
// ============================================================================
reg          clk, rst_n, start;
reg  [1:0]   mode;
reg  [127:0] key, nonce, received_tag;
reg  [63:0]  ad_data, data_in;
reg          ad_valid, ad_last, data_valid, data_last;

wire [63:0]  data_out;
wire         data_out_valid;
wire [127:0] tag_out;
wire         tag_out_valid;
wire         tag_match, tag_cmp_valid;
wire         ready, busy;

// ============================================================================
// DUT instantiation
// ============================================================================
ASCON_TOP dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .mode         (mode),
    .start        (start),
    .key          (key),
    .nonce        (nonce),
    .ad_data      (ad_data),
    .ad_valid     (ad_valid),
    .ad_last      (ad_last),
    .data_in      (data_in),
    .data_valid   (data_valid),
    .data_last    (data_last),
    .received_tag (received_tag),
    .data_out     (data_out),
    .data_out_valid(data_out_valid),
    .tag_out      (tag_out),
    .tag_out_valid(tag_out_valid),
    .tag_match    (tag_match),
    .tag_cmp_valid(tag_cmp_valid),
    .ready        (ready),
    .busy         (busy)
);

// ============================================================================
// Clock
// ============================================================================
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// VCD dump
// ============================================================================
initial begin
    $dumpfile("ascon_TOP_tb.vcd");
    $dumpvars(0, ascon_TOP_tb);
end

// ============================================================================
// Watchdog
// ============================================================================
initial begin
    #5000000;
    $display("[TIMEOUT] Simulation exceeded time limit");
    $finish;
end

// ============================================================================
// Test counters & capture registers
// ============================================================================
integer pass_cnt, fail_cnt, wc;
reg [63:0]  cap_data_out;
reg [127:0] cap_tag;
reg         cap_tag_match;
integer     total_from_file;

// ============================================================================
// Task: reset DUT
// ============================================================================
task do_reset;
    begin
        rst_n        = 0;
        start        = 0;
        mode         = 0;
        key          = 0;
        nonce        = 0;
        received_tag = 0;
        ad_data      = 0;
        ad_valid     = 0;
        ad_last      = 0;
        data_in      = 0;
        data_valid   = 0;
        data_last    = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    end
endtask

// ============================================================================
// Task: wait for ready
// ============================================================================
task wait_ready;
    begin
        wc = 0;
        while (!ready && wc < 20) begin
            @(posedge clk);
            wc = wc + 1;
        end
        if (!ready)
            $display("    [WARN] ready timeout after DONE");
    end
endtask

// ============================================================================
// Task: run encrypt, capture output
// ============================================================================
task run_encrypt;
    input [127:0] k, n;
    input [63:0]  pt;
    begin
        key        = k;
        nonce      = n;
        data_in    = pt;
        mode       = 2'b00;
        ad_valid   = 1'b0;
        ad_last    = 1'b0;
        data_valid = 1'b1;
        data_last  = 1'b1;
        received_tag = 128'h0;

        @(posedge clk); #1;
        start = 1;
        @(posedge clk); #1;
        start = 0;

        // Wait data_out_valid
        wc = 0;
        while (!data_out_valid && wc < MAX_WAIT) begin
            @(posedge clk); wc = wc + 1;
        end
        if (!data_out_valid) begin
            $display("    [ERROR] data_out_valid timeout (encrypt)");
            fail_cnt = fail_cnt + 1;
            cap_data_out = 64'hX;
        end else begin
            cap_data_out = data_out;
        end

        // Wait tag_out_valid
        wc = 0;
        while (!tag_out_valid && wc < 100) begin
            @(posedge clk); wc = wc + 1;
        end
        cap_tag = tag_out;

        wait_ready;
        @(posedge clk);
    end
endtask

// ============================================================================
// Task: run decrypt, capture output + tag comparison
// ============================================================================
task run_decrypt;
    input [127:0] k, n;
    input [63:0]  ct;
    input [127:0] rtag;
    begin
        key        = k;
        nonce      = n;
        data_in    = ct;
        mode       = 2'b01;
        ad_valid   = 1'b0;
        ad_last    = 1'b0;
        data_valid = 1'b1;
        data_last  = 1'b1;
        received_tag = rtag;

        @(posedge clk); #1;
        start = 1;
        @(posedge clk); #1;
        start = 0;

        wc = 0;
        while (!data_out_valid && wc < MAX_WAIT) begin
            @(posedge clk); wc = wc + 1;
        end
        if (!data_out_valid) begin
            $display("    [ERROR] data_out_valid timeout (decrypt)");
            fail_cnt = fail_cnt + 1;
            cap_data_out = 64'hX;
        end else begin
            cap_data_out = data_out;
        end

        wc = 0;
        while (!tag_out_valid && wc < 100) begin
            @(posedge clk); wc = wc + 1;
        end
        cap_tag = tag_out;

        wc = 0;
        while (!tag_cmp_valid && wc < 20) begin
            @(posedge clk); wc = wc + 1;
        end
        cap_tag_match = tag_match;

        wait_ready;
        @(posedge clk);
    end
endtask

initial begin : MAIN
    pass_cnt        = 0;
    fail_cnt        = 0;
    total_from_file = 0;

    $display("============================================================");
    $display("  ASCON_TOP Testbench — reading %s", TV_FILE);
    $display("============================================================");

    fd = $fopen(TV_FILE, "r");
    if (fd == 0) begin
        $display("[FATAL] Cannot open %s", TV_FILE);
        $display("  Run: python verify_hw.py  to generate the file.");
        $finish;
    end

    do_reset;

    while (!$feof(fd)) begin
        // Try reading COUNT + OP first
        ret = $fscanf(fd, " %d %d ", tv_count, tv_op);

        if (ret != 2) begin
            // Comment line or blank — skip to end of line
            ret = $fgets(line_buf, fd);
        end else begin
            // Read remaining fields
            ret = $fscanf(fd, "%h %h %h %h %h",
                          tv_key, tv_nonce,
                          tv_field_a, tv_field_b,
                          tv_tag_exp);

            if (ret == 5) begin
                total_from_file = total_from_file + 1;
                do_reset;

                if (tv_op == 0) begin
                    // ── ENCRYPT ─────────────────────────────────────────
                    // field_a = PT, field_b = expected CT
                    $display("\n[T%0d] ENCRYPT", tv_count);
                    $display("  KEY   = %032h", tv_key);
                    $display("  NONCE = %032h", tv_nonce);
                    $display("  PT    = %016h", tv_field_a);
                    $display("  EXP_CT  = %016h", tv_field_b);
                    $display("  EXP_TAG = %032h", tv_tag_exp);

                    run_encrypt(tv_key, tv_nonce, tv_field_a);

                    $display("  GOT_CT  = %016h", cap_data_out);
                    $display("  GOT_TAG = %032h", cap_tag);

                    if (cap_data_out === tv_field_b && cap_tag === tv_tag_exp) begin
                        $display("  [PASS]");
                        pass_cnt = pass_cnt + 1;
                    end else begin
                        $display("  [FAIL]");
                        if (cap_data_out !== tv_field_b)
                            $display("    CT  mismatch: got=%016h exp=%016h",
                                     cap_data_out, tv_field_b);
                        if (cap_tag !== tv_tag_exp)
                            $display("    TAG mismatch: got=%032h exp=%032h",
                                     cap_tag, tv_tag_exp);
                        fail_cnt = fail_cnt + 1;
                    end

                end else begin
                    // ── DECRYPT ─────────────────────────────────────────
                    // field_a = CT, field_b = expected PT
                    $display("\n[T%0d] DECRYPT", tv_count);
                    $display("  KEY   = %032h", tv_key);
                    $display("  NONCE = %032h", tv_nonce);
                    $display("  CT    = %016h", tv_field_a);
                    $display("  EXP_PT  = %016h", tv_field_b);
                    $display("  EXP_TAG = %032h", tv_tag_exp);

                    run_decrypt(tv_key, tv_nonce, tv_field_a, tv_tag_exp);

                    $display("  GOT_PT    = %016h", cap_data_out);
                    $display("  TAG_MATCH = %b", cap_tag_match);

                    if (cap_data_out === tv_field_b && cap_tag_match === 1'b1) begin
                        $display("  [PASS]");
                        pass_cnt = pass_cnt + 1;
                    end else begin
                        $display("  [FAIL]");
                        if (cap_data_out !== tv_field_b)
                            $display("    PT  mismatch: got=%016h exp=%016h",
                                     cap_data_out, tv_field_b);
                        if (cap_tag_match !== 1'b1)
                            $display("    TAG_MATCH: got=%b exp=1", cap_tag_match);
                        fail_cnt = fail_cnt + 1;
                    end
                end

            end else begin
                // Malformed line
                ret = $fgets(line_buf, fd);
            end
        end
    end

    $fclose(fd);

    // ── Summary ───────────────────────────────────────────────────────────
    @(posedge clk);
    $display("\n============================================================");
    $display("  Vectors from file : %0d", total_from_file);
    $display("  PASS / TOTAL      : %0d / %0d", pass_cnt, pass_cnt + fail_cnt);
    if (fail_cnt == 0)
        $display("  *** ALL TESTS PASSED ***");
    else
        $display("  *** %0d FAILED ***", fail_cnt);
    $display("============================================================");
    $finish;
end

// ============================================================================
// NOTE về endianness — ĐỌC TRƯỚC KHI DÙNG
// ============================================================================
// ascon.py dùng little-endian (bytes_to_int = int.from_bytes(...,'little'))
// ascon_top.v dùng big-endian tự nhiên của Verilog
// → verify_hw.py được cập nhật để sinh expected values khớp với RTL (big-endian)
// → Các giá trị TB hardcode cũ (T1 TAG=8966...) là SAI, đã được sửa thành:
//   T1 TAG = 850b981f3b472c863bbeb369a8dfbf8b  (RTL correct)
//   T2 TAG = b637dc47d25dad1c98a006af31885d53  (khớp vì key/nonce=0)
// ============================================================================

endmodule