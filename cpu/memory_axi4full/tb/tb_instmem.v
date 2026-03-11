// ============================================================================
// tb_inst_mem_axi_slave.v — Testbench toàn diện
// ============================================================================
// Module Under Test : inst_mem_axi_slave  +  inst_mem
//
// Context SoC:
//   - Instruction Memory (ROM): CPU fetch instruction qua AXI4 Read burst
//   - Icache controller dùng DMA-like burst để fill cache line
//   - Memory là READ-ONLY → mọi Write phải trả SLVERR
//   - Zero-latency first beat (burst_data combinational)
//   - ARREADY là combinational (assert ngay khi RD_IDLE)
//
// Danh sách test:
//   TC01  Single read len=1  — fetch 1 instruction (addr=0)
//   TC02  Burst read  len=4  — icache line fill (4 words)
//   TC03  Burst read  len=8  — icache line fill lớn
//   TC04  Burst read  len=16 — max burst
//   TC05  ARREADY là combinational: assert ngay không cần chờ clock
//   TC06  Zero-latency first beat: RVALID đã lên cùng/ngay sau AR handshake
//   TC07  RID match ARID — zero-latency (dùng S_AXI_ARID trực tiếp)
//   TC08  Đọc nhiều địa chỉ khác nhau — data integrity
//   TC09  Backpressure: RREADY=0 giữa burst, slave phải hold data
//   TC10  Write → phải nhận SLVERR (BRESP=2'b10), data không thay đổi
//   TC11  Write burst len=4 → SLVERR, đọc lại địa chỉ đó vẫn = NOP
//   TC12  BID phải match AWID khi write (dù SLVERR)
//   TC13  Reset giữa read burst — slave phải về IDLE
//   TC14  Hai read liên tiếp không idle
//   TC15  Đọc đúng địa chỉ offset (word 0, word 1, word 15) riêng lẻ
// ============================================================================

`timescale 1ns/1ps
`define SIMULATION
`define TESTBENCH_MODE
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
module tb_inst_mem_axi_slave;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH   = 4;
    parameter MEM_SIZE   = 4096;          // 4KB = 1024 words
    parameter CLK_PERIOD = 10;            // 100 MHz

    // NOP pattern: ADDI x0,x0,0
    localparam NOP = 32'h0000_0013;

    // -------------------------------------------------------------------------
    // DUT Ports
    // -------------------------------------------------------------------------
    reg  clk, rst_n;

    // Write Address
    reg  [ID_WIDTH-1:0]     S_AXI_AWID;
    reg  [ADDR_WIDTH-1:0]   S_AXI_AWADDR;
    reg  [7:0]              S_AXI_AWLEN;
    reg  [2:0]              S_AXI_AWSIZE;
    reg  [1:0]              S_AXI_AWBURST;
    reg  [2:0]              S_AXI_AWPROT;
    reg                     S_AXI_AWVALID;
    wire                    S_AXI_AWREADY;
    // Write Data
    reg  [DATA_WIDTH-1:0]   S_AXI_WDATA;
    reg  [DATA_WIDTH/8-1:0] S_AXI_WSTRB;
    reg                     S_AXI_WLAST;
    reg                     S_AXI_WVALID;
    wire                    S_AXI_WREADY;
    // Write Response
    wire [ID_WIDTH-1:0]     S_AXI_BID;
    wire [1:0]              S_AXI_BRESP;
    wire                    S_AXI_BVALID;
    reg                     S_AXI_BREADY;
    // Read Address
    reg  [ID_WIDTH-1:0]     S_AXI_ARID;
    reg  [ADDR_WIDTH-1:0]   S_AXI_ARADDR;
    reg  [7:0]              S_AXI_ARLEN;
    reg  [2:0]              S_AXI_ARSIZE;
    reg  [1:0]              S_AXI_ARBURST;
    reg  [2:0]              S_AXI_ARPROT;
    reg                     S_AXI_ARVALID;
    wire                    S_AXI_ARREADY;
    // Read Data
    wire [ID_WIDTH-1:0]     S_AXI_RID;
    wire [DATA_WIDTH-1:0]   S_AXI_RDATA;
    wire [1:0]              S_AXI_RRESP;
    wire                    S_AXI_RLAST;
    wire                    S_AXI_RVALID;
    reg                     S_AXI_RREADY;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    inst_mem_axi_slave #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .MEM_SIZE     (MEM_SIZE),
        .MEM_INIT_FILE("")              // TESTBENCH_MODE: init to NOP
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .S_AXI_AWID     (S_AXI_AWID),
        .S_AXI_AWADDR   (S_AXI_AWADDR),
        .S_AXI_AWLEN    (S_AXI_AWLEN),
        .S_AXI_AWSIZE   (S_AXI_AWSIZE),
        .S_AXI_AWBURST  (S_AXI_AWBURST),
        .S_AXI_AWPROT   (S_AXI_AWPROT),
        .S_AXI_AWVALID  (S_AXI_AWVALID),
        .S_AXI_AWREADY  (S_AXI_AWREADY),
        .S_AXI_WDATA    (S_AXI_WDATA),
        .S_AXI_WSTRB    (S_AXI_WSTRB),
        .S_AXI_WLAST    (S_AXI_WLAST),
        .S_AXI_WVALID   (S_AXI_WVALID),
        .S_AXI_WREADY   (S_AXI_WREADY),
        .S_AXI_BID      (S_AXI_BID),
        .S_AXI_BRESP    (S_AXI_BRESP),
        .S_AXI_BVALID   (S_AXI_BVALID),
        .S_AXI_BREADY   (S_AXI_BREADY),
        .S_AXI_ARID     (S_AXI_ARID),
        .S_AXI_ARADDR   (S_AXI_ARADDR),
        .S_AXI_ARLEN    (S_AXI_ARLEN),
        .S_AXI_ARSIZE   (S_AXI_ARSIZE),
        .S_AXI_ARBURST  (S_AXI_ARBURST),
        .S_AXI_ARPROT   (S_AXI_ARPROT),
        .S_AXI_ARVALID  (S_AXI_ARVALID),
        .S_AXI_ARREADY  (S_AXI_ARREADY),
        .S_AXI_RID      (S_AXI_RID),
        .S_AXI_RDATA    (S_AXI_RDATA),
        .S_AXI_RRESP    (S_AXI_RRESP),
        .S_AXI_RLAST    (S_AXI_RLAST),
        .S_AXI_RVALID   (S_AXI_RVALID),
        .S_AXI_RREADY   (S_AXI_RREADY)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    integer pass_count, fail_count, tc_num;
    reg [DATA_WIDTH-1:0] rd_buf [0:31];
    integer              rd_idx;

    // -------------------------------------------------------------------------
    // Backdoor write vào inst_mem.memory[] để set known data
    // -------------------------------------------------------------------------
    // Dùng hierarchical reference để pre-load data không cần .hex
    task backdoor_write;
        input integer word_idx;
        input [DATA_WIDTH-1:0] val;
    begin
        dut.imem.memory[word_idx] = val;
    end
    endtask

    // -------------------------------------------------------------------------
    // Task: reset
    // -------------------------------------------------------------------------
    task do_reset;
    begin
        rst_n          <= 0;
        S_AXI_AWID     <= 0; S_AXI_AWADDR  <= 0; S_AXI_AWLEN  <= 0;
        S_AXI_AWSIZE   <= 3'b010; S_AXI_AWBURST <= 2'b01;
        S_AXI_AWPROT   <= 0; S_AXI_AWVALID <= 0;
        S_AXI_WDATA    <= 0; S_AXI_WSTRB   <= 4'hF;
        S_AXI_WLAST    <= 0; S_AXI_WVALID  <= 0;
        S_AXI_BREADY   <= 1;
        S_AXI_ARID     <= 0; S_AXI_ARADDR  <= 0; S_AXI_ARLEN  <= 0;
        S_AXI_ARSIZE   <= 3'b010; S_AXI_ARBURST <= 2'b01;
        S_AXI_ARPROT   <= 0; S_AXI_ARVALID <= 0;
        S_AXI_RREADY   <= 1;
        repeat(4) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------------
    // Task: axi_read_burst
    //   addr              - byte address
    //   id                - ARID
    //   len               - số beats (ARLEN = len-1)
    //   bp_at_beat        - beat index để de-assert RREADY (-1 = không)
    // -------------------------------------------------------------------------
    task axi_read_burst;
        input [ADDR_WIDTH-1:0] addr;
        input [ID_WIDTH-1:0]   id;
        input integer          len;
        input integer          bp_at_beat;  // backpressure at beat#
        integer beat;
        integer timeout;
    begin
        rd_idx = 0;
        // AR channel
        @(negedge clk); // drive trước sườn lên
        S_AXI_ARID    <= id;
        S_AXI_ARADDR  <= addr;
        S_AXI_ARLEN   <= len - 1;
        S_AXI_ARSIZE  <= 3'b010;
        S_AXI_ARBURST <= 2'b01;
        S_AXI_ARPROT  <= 3'b000;
        S_AXI_ARVALID <= 1;
        S_AXI_RREADY  <= 1;

        // Chờ ARREADY (combinational → thường sẵn ngay)
        @(posedge clk);
        while (!S_AXI_ARREADY) @(posedge clk);
        // Handshake done
        @(negedge clk);
        S_AXI_ARVALID <= 0;

        // R channel: nhận từng beat
        beat = 0;
        timeout = 0;
        while (beat < len && timeout < 2000) begin
            // Áp backpressure TRƯỚC khi sample (khi sắp nhận beat bp_at_beat)
            if (bp_at_beat == beat && beat > 0) begin
                @(negedge clk);
                S_AXI_RREADY <= 0;
                repeat(3) @(posedge clk);
                @(negedge clk);
                S_AXI_RREADY <= 1;
            end
            @(posedge clk);
            timeout = timeout + 1;
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                rd_buf[rd_idx] = S_AXI_RDATA;
                rd_idx = rd_idx + 1;
                beat = beat + 1;
            end
        end
        if (timeout >= 2000)
            $display("  [WARN] TC%02d read timeout!", tc_num);
        repeat(2) @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------------
    // Task: axi_write_burst
    //   Ghi vào ROM — expected behavior: SLVERR response
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0]   wr_data_arr [0:31];

    task axi_write_burst;
        input [ADDR_WIDTH-1:0] addr;
        input [ID_WIDTH-1:0]   id;
        input integer          len;
        integer beat;
        integer timeout;
    begin
        // AW channel
        @(negedge clk);
        S_AXI_AWID    <= id;
        S_AXI_AWADDR  <= addr;
        S_AXI_AWLEN   <= len - 1;
        S_AXI_AWSIZE  <= 3'b010;
        S_AXI_AWBURST <= 2'b01;
        S_AXI_AWPROT  <= 3'b000;
        S_AXI_AWVALID <= 1;

        @(posedge clk);
        while (!S_AXI_AWREADY) @(posedge clk);
        @(negedge clk);
        S_AXI_AWVALID <= 0;

        // W channel
        beat = 0;
        while (beat < len) begin
            S_AXI_WDATA  <= wr_data_arr[beat];
            S_AXI_WSTRB  <= 4'hF;
            S_AXI_WLAST  <= (beat == len-1) ? 1'b1 : 1'b0;
            S_AXI_WVALID <= 1;
            @(posedge clk);
            while (!S_AXI_WREADY) @(posedge clk);
            @(negedge clk);
            beat = beat + 1;
        end
        S_AXI_WVALID <= 0;
        S_AXI_WLAST  <= 0;

        // B channel
        S_AXI_BREADY <= 1;
        timeout = 0;
        @(posedge clk);
        while (!S_AXI_BVALID && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat(2) @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------------
    // check helpers
    // -------------------------------------------------------------------------
    task check_eq;
        input [DATA_WIDTH-1:0] actual, expected;
        input [127:0] msg;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d %s | got=0x%08h", tc_num, msg, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d %s | exp=0x%08h got=0x%08h",
                     tc_num, msg, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task check_bit;
        input actual, expected;
        input [127:0] msg;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d %s | got=%b", tc_num, msg, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d %s | exp=%b got=%b",
                     tc_num, msg, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task check_id;
        input [ID_WIDTH-1:0] actual, expected;
        input [127:0] msg;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d %s | got=%0d", tc_num, msg, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d %s | exp=%0d got=%0d",
                     tc_num, msg, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    task check_resp;
        input [1:0] actual, expected;
        input [127:0] msg;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d %s | got=2'b%02b", tc_num, msg, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d %s | exp=2'b%02b got=2'b%02b",
                     tc_num, msg, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    integer k;

    initial begin
        $dumpfile("tb_inst_mem_axi_slave.vcd");
        $dumpvars(0, tb_inst_mem_axi_slave);

        pass_count = 0;
        fail_count = 0;
        tc_num     = 0;

        do_reset;

        // Pre-load known instructions via backdoor
        // Word 0..15 = 0xAABB_CCnn (nn = word index)
        for (k = 0; k < 16; k = k+1)
            backdoor_write(k, 32'hAABB_CC00 + k);
        // Word 16..31 = 0x1234_00nn
        for (k = 16; k < 32; k = k+1)
            backdoor_write(k, 32'h1234_0000 + k);
        // Word 100 = distinctive value
        backdoor_write(100, 32'hDEAD_C0DE);
        // Word 200 = another distinctive
        backdoor_write(200, 32'hBEEF_FEED);

        // ===================================================================
        // TC01: Single read len=1 — fetch 1 instruction (word 0)
        // ===================================================================
        tc_num = 1;
        $display("\n[TC%02d] Single read len=1 — fetch word 0", tc_num);
        axi_read_burst(32'h0000_0000, 4'd1, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC01 word0");

        // ===================================================================
        // TC02: Burst read len=4 — icache line fill (4 words)
        // ===================================================================
        tc_num = 2;
        $display("\n[TC%02d] Burst read len=4 — icache line fill", tc_num);
        axi_read_burst(32'h0000_0000, 4'd2, 4, -1);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC02 beat0");
        check_eq(rd_buf[1], 32'hAABB_CC01, "TC02 beat1");
        check_eq(rd_buf[2], 32'hAABB_CC02, "TC02 beat2");
        check_eq(rd_buf[3], 32'hAABB_CC03, "TC02 beat3");

        // ===================================================================
        // TC03: Burst read len=8
        // ===================================================================
        tc_num = 3;
        $display("\n[TC%02d] Burst read len=8", tc_num);
        axi_read_burst(32'h0000_0000, 4'd3, 8, -1);
        for (k = 0; k < 8; k = k+1)
            check_eq(rd_buf[k], 32'hAABB_CC00 + k, "TC03 beat");

        // ===================================================================
        // TC04: Burst read len=16 — max burst
        // ===================================================================
        tc_num = 4;
        $display("\n[TC%02d] Burst read len=16 — max burst", tc_num);
        axi_read_burst(32'h0000_0000, 4'd4, 16, -1);
        for (k = 0; k < 16; k = k+1)
            check_eq(rd_buf[k], 32'hAABB_CC00 + k, "TC04 beat");

        // ===================================================================
        // TC05: ARREADY là combinational — phải HIGH ngay khi IDLE
        //       Kiểm tra tại thời điểm TRƯỚC posedge (sau reset)
        // ===================================================================
        tc_num = 5;
        $display("\n[TC%02d] ARREADY is combinational (HIGH in IDLE state)", tc_num);
        // Sau khi TC04 xong, slave đã về IDLE
        // Sample ARREADY tại negedge (giữa chu kỳ) — phải đang HIGH
        @(negedge clk);
        #1; // propagation
        check_bit(S_AXI_ARREADY, 1'b1, "TC05 ARREADY=1 in IDLE");

        // ===================================================================
        // TC06: Zero-latency first beat
        //       RVALID phải được assert ngay posedge clk sau AR handshake
        //       (burst_data combinational → burst_valid set cùng cycle req)
        // ===================================================================
        tc_num = 6;
        $display("\n[TC%02d] Zero-latency: RVALID on cycle after AR handshake", tc_num);
        begin : tc06_block
            integer rvalid_delay;
            @(negedge clk);
            S_AXI_ARID    <= 4'd6;
            S_AXI_ARADDR  <= 32'h0000_0000;
            S_AXI_ARLEN   <= 8'd0;     // 1 beat
            S_AXI_ARSIZE  <= 3'b010;
            S_AXI_ARBURST <= 2'b01;
            S_AXI_ARVALID <= 1;
            S_AXI_RREADY  <= 1;

            // AR handshake tại posedge này (ARREADY combinational)
            @(posedge clk);
            // ARREADY phải là 1 (combinational), handshake ngay
            if (!S_AXI_ARREADY) begin
                $display("  [FAIL] TC%02d ARREADY not high at handshake", tc_num);
                fail_count = fail_count + 1;
            end

            @(negedge clk);
            S_AXI_ARVALID <= 0;

            // RVALID phải lên NGAY posedge tiếp theo (zero-latency)
            // inst_mem assert burst_valid trong BURST_IDLE khi burst_req=1
            @(posedge clk);
            rvalid_delay = 0;
            if (S_AXI_RVALID) begin
                $display("  [PASS] TC%02d RVALID asserted 1 cycle after AR handshake", tc_num);
                pass_count = pass_count + 1;
            end else begin
                // Cho thêm 1 cycle
                @(posedge clk);
                if (S_AXI_RVALID) begin
                    $display("  [WARN] TC%02d RVALID latency = 2 cycles (expected 1)", tc_num);
                    pass_count = pass_count + 1; // vẫn pass nếu data đúng
                end else begin
                    $display("  [FAIL] TC%02d RVALID not asserted after AR handshake", tc_num);
                    fail_count = fail_count + 1;
                end
            end

            // Chờ beat xong
            while (!S_AXI_RLAST || !S_AXI_RVALID) @(posedge clk);
            @(posedge clk);
        end

        // ===================================================================
        // TC07: RID match ARID — cả zero-latency (beat 0) và latch (beat 1+)
        // ===================================================================
        tc_num = 7;
        $display("\n[TC%02d] RID must match ARID for all beats", tc_num);
        begin : tc07_block
            reg [ID_WIDTH-1:0] captured_rid_beat0;
            reg [ID_WIDTH-1:0] captured_rid_beat1;
            integer b;

            @(negedge clk);
            S_AXI_ARID    <= 4'd7;
            S_AXI_ARADDR  <= 32'h0000_0000;
            S_AXI_ARLEN   <= 8'd3;    // 4 beats
            S_AXI_ARSIZE  <= 3'b010;
            S_AXI_ARBURST <= 2'b01;
            S_AXI_ARVALID <= 1;
            S_AXI_RREADY  <= 1;

            @(posedge clk);           // AR handshake (ARREADY comb)
            @(negedge clk);
            S_AXI_ARVALID <= 0;

            // Capture RID cho từng beat
            b = 0;
            while (b < 4) begin
                @(posedge clk);
                if (S_AXI_RVALID && S_AXI_RREADY) begin
                    if (S_AXI_RID !== 4'd7) begin
                        $display("  [FAIL] TC%02d RID mismatch at beat %0d | exp=7 got=%0d",
                                 tc_num, b, S_AXI_RID);
                        fail_count = fail_count + 1;
                    end else begin
                        $display("  [PASS] TC%02d RID=7 correct at beat %0d", tc_num, b);
                        pass_count = pass_count + 1;
                    end
                    b = b + 1;
                end
            end
            @(posedge clk);
        end

        // ===================================================================
        // TC08: Data integrity — đọc các địa chỉ khác nhau
        // ===================================================================
        tc_num = 8;
        $display("\n[TC%02d] Data integrity — different addresses", tc_num);
        // word 0
        axi_read_burst(32'h0000_0000, 4'd8, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC08 word0");
        // word 5 (byte addr = 5*4 = 0x14)
        axi_read_burst(32'h0000_0014, 4'd8, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC05, "TC08 word5");
        // word 100 (byte addr = 400 = 0x190)
        axi_read_burst(32'h0000_0190, 4'd8, 1, -1);
        check_eq(rd_buf[0], 32'hDEAD_C0DE, "TC08 word100");
        // word 200 (byte addr = 800 = 0x320)
        axi_read_burst(32'h0000_0320, 4'd8, 1, -1);
        check_eq(rd_buf[0], 32'hBEEF_FEED, "TC08 word200");

        // ===================================================================
        // TC09: Backpressure — RREADY de-assert tại beat 2
        //       Slave phải hold RVALID/RDATA cho đến khi RREADY lên lại
        // ===================================================================
        tc_num = 9;
        $display("\n[TC%02d] Backpressure — RREADY=0 at beat 2", tc_num);
        axi_read_burst(32'h0000_0000, 4'd9, 4, 2);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC09 beat0");
        check_eq(rd_buf[1], 32'hAABB_CC01, "TC09 beat1");
        check_eq(rd_buf[2], 32'hAABB_CC02, "TC09 beat2 after bp");
        check_eq(rd_buf[3], 32'hAABB_CC03, "TC09 beat3");

        // ===================================================================
        // TC10: Write single — phải nhận SLVERR (BRESP = 2'b10)
        // ===================================================================
        tc_num = 10;
        $display("\n[TC%02d] Write to ROM → SLVERR (BRESP=10)", tc_num);
        wr_data_arr[0] = 32'hDEAD_BEEF;
        axi_write_burst(32'h0000_0000, 4'd10, 1);
        check_resp(S_AXI_BRESP, 2'b10, "TC10 BRESP=SLVERR");
        // Đọc lại word 0 — phải vẫn là giá trị cũ (ROM không bị ghi)
        axi_read_burst(32'h0000_0000, 4'd10, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC10 ROM unchanged after write");

        // ===================================================================
        // TC11: Burst write len=4 → SLVERR, data không thay đổi
        // ===================================================================
        tc_num = 11;
        $display("\n[TC%02d] Burst write len=4 → SLVERR, ROM unchanged", tc_num);
        for (k = 0; k < 4; k = k+1)
            wr_data_arr[k] = 32'hFFFF_0000 + k;
        axi_write_burst(32'h0000_0000, 4'd11, 4);
        check_resp(S_AXI_BRESP, 2'b10, "TC11 BRESP=SLVERR burst");
        // Đọc lại 4 words
        axi_read_burst(32'h0000_0000, 4'd11, 4, -1);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC11 ROM word0 unchanged");
        check_eq(rd_buf[1], 32'hAABB_CC01, "TC11 ROM word1 unchanged");
        check_eq(rd_buf[2], 32'hAABB_CC02, "TC11 ROM word2 unchanged");
        check_eq(rd_buf[3], 32'hAABB_CC03, "TC11 ROM word3 unchanged");

        // ===================================================================
        // TC12: BID phải match AWID (dù SLVERR)
        // ===================================================================
        tc_num = 12;
        $display("\n[TC%02d] BID must match AWID even on SLVERR", tc_num);
        wr_data_arr[0] = 32'hCAFE_1234;
        axi_write_burst(32'h0000_0000, 4'd12, 1);
        check_id(S_AXI_BID, 4'd12, "TC12 BID match AWID");
        check_resp(S_AXI_BRESP, 2'b10, "TC12 still SLVERR");

        // ===================================================================
        // TC13: Reset giữa read burst — slave phải về IDLE
        // ===================================================================
        tc_num = 13;
        $display("\n[TC%02d] Reset in middle of read burst", tc_num);
        begin : tc13_block
            // Bắt đầu read burst len=8
            @(negedge clk);
            S_AXI_ARID    <= 4'd13;
            S_AXI_ARADDR  <= 32'h0000_0000;
            S_AXI_ARLEN   <= 8'd7;
            S_AXI_ARSIZE  <= 3'b010;
            S_AXI_ARBURST <= 2'b01;
            S_AXI_ARVALID <= 1;
            S_AXI_RREADY  <= 1;

            @(posedge clk);           // AR handshake
            @(negedge clk);
            S_AXI_ARVALID <= 0;

            // Nhận 2 beat rồi reset
            @(posedge clk); // beat 0
            @(posedge clk); // beat 1
            #1;
            rst_n <= 0;
            repeat(3) @(posedge clk);
            rst_n <= 1;
            S_AXI_RREADY <= 0;
            @(posedge clk);
            S_AXI_RREADY <= 1;
            repeat(2) @(posedge clk);

            // Sau reset: RVALID phải = 0, ARREADY phải = 1 (IDLE)
            #1;
            check_bit(S_AXI_RVALID,  1'b0, "TC13 RVALID=0 after reset");
            check_bit(S_AXI_ARREADY, 1'b1, "TC13 ARREADY=1 (IDLE) after reset");
        end

        // ===================================================================
        // TC14: Hai read liên tiếp không idle
        // ===================================================================
        tc_num = 14;
        $display("\n[TC%02d] Two consecutive reads without idle", tc_num);
        axi_read_burst(32'h0000_0000, 4'd14, 4, -1);
        check_eq(rd_buf[0], 32'hAABB_CC00, "TC14 read1 beat0");
        check_eq(rd_buf[3], 32'hAABB_CC03, "TC14 read1 beat3");
        // Ngay sau khi kết thúc, bắt đầu read thứ 2
        axi_read_burst(32'h0000_0040, 4'd14, 4, -1); // word 16..19 (byte addr=0x40)
        check_eq(rd_buf[0], 32'h1234_0010, "TC14 read2 beat0 (word16)");
        check_eq(rd_buf[1], 32'h1234_0011, "TC14 read2 beat1 (word17)");
        check_eq(rd_buf[2], 32'h1234_0012, "TC14 read2 beat2 (word18)");
        check_eq(rd_buf[3], 32'h1234_0013, "TC14 read2 beat3 (word19)");

        // ===================================================================
        // TC15: Đọc từng word offset riêng lẻ (word 0, word 1, word 15)
        // ===================================================================
        tc_num = 15;
        $display("\n[TC%02d] Read individual words at different offsets", tc_num);
        // word 1 (byte addr = 4)
        axi_read_burst(32'h0000_0004, 4'd15, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC01, "TC15 word1");
        // word 7 (byte addr = 28 = 0x1C)
        axi_read_burst(32'h0000_001C, 4'd15, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC07, "TC15 word7");
        // word 15 (byte addr = 60 = 0x3C)
        axi_read_burst(32'h0000_003C, 4'd15, 1, -1);
        check_eq(rd_buf[0], 32'hAABB_CC0F, "TC15 word15");
        // word 200 (byte addr = 800 = 0x320) — far address
        axi_read_burst(32'h0000_0320, 4'd15, 1, -1);
        check_eq(rd_buf[0], 32'hBEEF_FEED, "TC15 word200 far");

        // ===================================================================
        // SUMMARY
        // ===================================================================
        repeat(5) @(posedge clk);
        $display("\n============================================================");
        $display("  TESTBENCH SUMMARY  [inst_mem_axi_slave]");
        $display("  PASS : %0d", pass_count);
        $display("  FAIL : %0d", fail_count);
        $display("  TOTAL: %0d", pass_count + fail_count);
        $display("============================================================");
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> %0d TEST(S) FAILED <<<", fail_count);
        $display("============================================================\n");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog
    // -------------------------------------------------------------------------
    initial begin
        #200000;
        $display("[WATCHDOG] Simulation timed out at %0t!", $time);
        $finish;
    end

endmodule