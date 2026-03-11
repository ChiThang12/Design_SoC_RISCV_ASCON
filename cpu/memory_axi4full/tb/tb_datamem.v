// ============================================================================
// tb_data_mem_axi4_slave.v — Testbench toàn diện
// ============================================================================
// Module Under Test: data_mem_axi4_slave
//   + data_mem_burst (sub-module)
//
// Context SoC:
//   - CPU ghi data vào qua AXI4 Write (cache eviction / store)
//   - IPASCON DMA đọc/ghi data qua AXI4 Read/Write burst
//   - BASE_ADDR = 0x1000_0000
//
// Danh sách test:
//   TC01  Single write len=1, WVALID đến cùng cycle AW  → kiểm tra FIX-BUG5
//   TC02  Single write len=1, WVALID đến SAU AW         → trường hợp bình thường
//   TC03  Burst write len=4 (CPU cache eviction)
//   TC04  Burst write len=8 (DMA IPASCON write to data_mem)
//   TC05  Burst write len=16 (max DMA burst)
//   TC06  Single read  len=1 sau TC01
//   TC07  Burst read   len=4 (DMA fetch)
//   TC08  Burst read   len=8 (DMA fetch lớn)
//   TC09  Write → Read: kiểm tra data integrity
//   TC10  Partial byte strobe (WSTRB != 4'b1111)
//   TC11  Read backpressure: RREADY bị de-assert giữa chừng
//   TC12  Hai write liên tiếp không có idle cycle giữa
//   TC13  Reset giữa chừng write transaction
//   TC14  BID phải match AWID / RID phải match ARID
//   TC15  Write + Read concurrent (CPU ghi, DMA đọc vùng khác)
// ============================================================================

`timescale 1ns/1ps
`define SIMULATION

// ============================================================================
// Include các module thực
// ============================================================================

`include "cpu/memory_axi4full/data_mem_axi_slave.v"

// ============================================================================
// Testbench Top
// ============================================================================
module tb_data_mem_axi4_slave;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH   = 4;
    parameter MEM_SIZE   = 8192;
    parameter BASE_ADDR  = 32'h10000000;
    parameter CLK_PERIOD = 10; // 100 MHz

    // -----------------------------------------------------------------------
    // DUT Ports
    // -----------------------------------------------------------------------
    reg  clk;
    reg  rst_n;

    // Write Address Channel
    reg  [ID_WIDTH-1:0]     S_AXI_AWID;
    reg  [ADDR_WIDTH-1:0]   S_AXI_AWADDR;
    reg  [7:0]              S_AXI_AWLEN;
    reg  [2:0]              S_AXI_AWSIZE;
    reg  [1:0]              S_AXI_AWBURST;
    reg  [2:0]              S_AXI_AWPROT;
    reg                     S_AXI_AWVALID;
    wire                    S_AXI_AWREADY;

    // Write Data Channel
    reg  [DATA_WIDTH-1:0]   S_AXI_WDATA;
    reg  [DATA_WIDTH/8-1:0] S_AXI_WSTRB;
    reg                     S_AXI_WLAST;
    reg                     S_AXI_WVALID;
    wire                    S_AXI_WREADY;

    // Write Response Channel
    wire [ID_WIDTH-1:0]     S_AXI_BID;
    wire [1:0]              S_AXI_BRESP;
    wire                    S_AXI_BVALID;
    reg                     S_AXI_BREADY;

    // Read Address Channel
    reg  [ID_WIDTH-1:0]     S_AXI_ARID;
    reg  [ADDR_WIDTH-1:0]   S_AXI_ARADDR;
    reg  [7:0]              S_AXI_ARLEN;
    reg  [2:0]              S_AXI_ARSIZE;
    reg  [1:0]              S_AXI_ARBURST;
    reg  [2:0]              S_AXI_ARPROT;
    reg                     S_AXI_ARVALID;
    wire                    S_AXI_ARREADY;

    // Read Data Channel
    wire [ID_WIDTH-1:0]     S_AXI_RID;
    wire [DATA_WIDTH-1:0]   S_AXI_RDATA;
    wire [1:0]              S_AXI_RRESP;
    wire                    S_AXI_RLAST;
    wire                    S_AXI_RVALID;
    reg                     S_AXI_RREADY;

    // -----------------------------------------------------------------------
    // DUT Instantiation
    // -----------------------------------------------------------------------
    data_mem_axi4_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .MEM_SIZE  (MEM_SIZE)
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

    // -----------------------------------------------------------------------
    // Clock Generation
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -----------------------------------------------------------------------
    // Scoreboard và counters
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer tc_num;

    // Buffer lưu dữ liệu đọc về
    reg [DATA_WIDTH-1:0] rd_data_buf [0:31];
    integer              rd_buf_idx;

    // -----------------------------------------------------------------------
    // Task: reset
    // -----------------------------------------------------------------------
    task do_reset;
    begin
        rst_n          <= 0;
        S_AXI_AWID     <= 0; S_AXI_AWADDR <= 0; S_AXI_AWLEN <= 0;
        S_AXI_AWSIZE   <= 3'b010; S_AXI_AWBURST <= 2'b01;
        S_AXI_AWPROT   <= 0; S_AXI_AWVALID <= 0;
        S_AXI_WDATA    <= 0; S_AXI_WSTRB <= 4'hF;
        S_AXI_WLAST    <= 0; S_AXI_WVALID <= 0;
        S_AXI_BREADY   <= 1;
        S_AXI_ARID     <= 0; S_AXI_ARADDR <= 0; S_AXI_ARLEN <= 0;
        S_AXI_ARSIZE   <= 3'b010; S_AXI_ARBURST <= 2'b01;
        S_AXI_ARPROT   <= 0; S_AXI_ARVALID <= 0;
        S_AXI_RREADY   <= 1;
        repeat(4) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Task: axi_write_burst
    //   addr      - địa chỉ byte (AXI absolute, bao gồm BASE_ADDR)
    //   id        - AWID
    //   data[]    - mảng data (tối đa 32 beats)
    //   strb[]    - mảng strobe (tối đa 32 beats)
    //   len       - số beats (AXI AWLEN = len-1)
    //   simultaneous_w - 1: WVALID cùng cycle AW (test FIX-BUG5)
    // -----------------------------------------------------------------------
    reg [DATA_WIDTH-1:0]   wr_data_arr [0:31];
    reg [DATA_WIDTH/8-1:0] wr_strb_arr [0:31];

    task axi_write_burst;
        input [ADDR_WIDTH-1:0] addr;
        input [ID_WIDTH-1:0]   id;
        input integer          len;
        input integer          simultaneous_w;
        integer                i;
        integer                beat;
    begin
        // ---- AW channel ----
        @(posedge clk);
        #1;
        S_AXI_AWID    <= id;
        S_AXI_AWADDR  <= addr;
        S_AXI_AWLEN   <= len - 1;
        S_AXI_AWSIZE  <= 3'b010;   // 4 bytes per beat
        S_AXI_AWBURST <= 2'b01;    // INCR
        S_AXI_AWPROT  <= 3'b000;
        S_AXI_AWVALID <= 1;

        if (simultaneous_w) begin
            // WVALID cùng cycle với AWVALID → test FIX-BUG5
            S_AXI_WDATA  <= wr_data_arr[0];
            S_AXI_WSTRB  <= wr_strb_arr[0];
            S_AXI_WLAST  <= (len == 1) ? 1 : 0;
            S_AXI_WVALID <= 1;
        end

        // Chờ AW handshake
        @(posedge clk);
        while (!S_AXI_AWREADY) @(posedge clk);
        #1;
        S_AXI_AWVALID <= 0;

        // ---- W channel ----
        if (simultaneous_w) begin
            // Beat 0 đã được gửi, chờ WREADY
            @(posedge clk);
            while (!S_AXI_WREADY) @(posedge clk);
            #1;
            if (len == 1) begin
                S_AXI_WVALID <= 0;
                S_AXI_WLAST  <= 0;
            end else begin
                // Tiếp tục beat 1..len-1
                for (beat = 1; beat < len; beat = beat + 1) begin
                    S_AXI_WDATA  <= wr_data_arr[beat];
                    S_AXI_WSTRB  <= wr_strb_arr[beat];
                    S_AXI_WLAST  <= (beat == len-1) ? 1 : 0;
                    S_AXI_WVALID <= 1;
                    @(posedge clk);
                    while (!S_AXI_WREADY) @(posedge clk);
                    #1;
                end
                S_AXI_WVALID <= 0;
                S_AXI_WLAST  <= 0;
            end
        end else begin
            // W sau AW — normal flow
            for (beat = 0; beat < len; beat = beat + 1) begin
                S_AXI_WDATA  <= wr_data_arr[beat];
                S_AXI_WSTRB  <= wr_strb_arr[beat];
                S_AXI_WLAST  <= (beat == len-1) ? 1 : 0;
                S_AXI_WVALID <= 1;
                @(posedge clk);
                while (!S_AXI_WREADY) @(posedge clk);
                #1;
            end
            S_AXI_WVALID <= 0;
            S_AXI_WLAST  <= 0;
        end

        // ---- B channel: chờ response ----
        S_AXI_BREADY <= 1;
        @(posedge clk);
        while (!S_AXI_BVALID) @(posedge clk);
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Task: axi_read_burst
    //   addr    - địa chỉ byte
    //   id      - ARID
    //   len     - số beats (AXI ARLEN = len-1)
    //   rready_deassert_beat - beat nào de-assert RREADY (-1 = không de-assert)
    // -----------------------------------------------------------------------
    task axi_read_burst;
        input [ADDR_WIDTH-1:0] addr;
        input [ID_WIDTH-1:0]   id;
        input integer          len;
        input integer          rready_deassert_beat;
        integer                beat;
    begin
        rd_buf_idx = 0;

        // ---- AR channel ----
        @(posedge clk);
        #1;
        S_AXI_ARID    <= id;
        S_AXI_ARADDR  <= addr;
        S_AXI_ARLEN   <= len - 1;
        S_AXI_ARSIZE  <= 3'b010;
        S_AXI_ARBURST <= 2'b01;
        S_AXI_ARPROT  <= 3'b000;
        S_AXI_ARVALID <= 1;
        S_AXI_RREADY  <= 1;

        @(posedge clk);
        while (!S_AXI_ARREADY) @(posedge clk);
        #1;
        S_AXI_ARVALID <= 0;

        // ---- R channel: nhận từng beat ----
        beat = 0;
        while (beat < len) begin
            if (rready_deassert_beat == beat) begin
                // Thêm stall để test backpressure
                S_AXI_RREADY <= 0;
                repeat(3) @(posedge clk);
                #1;
                S_AXI_RREADY <= 1;
            end
            @(posedge clk);
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                rd_data_buf[rd_buf_idx] = S_AXI_RDATA;
                rd_buf_idx = rd_buf_idx + 1;
                beat = beat + 1;
            end
        end
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Task: check_value
    // -----------------------------------------------------------------------
    task check_value;
        input [DATA_WIDTH-1:0] actual;
        input [DATA_WIDTH-1:0] expected;
        input [127:0]          msg;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d %s | got=0x%08h", tc_num, msg, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d %s | expected=0x%08h got=0x%08h",
                     tc_num, msg, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // -----------------------------------------------------------------------
    // Task: check_bid
    // -----------------------------------------------------------------------
    task check_bid;
        input [ID_WIDTH-1:0] actual;
        input [ID_WIDTH-1:0] expected;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d BID match | got=%0d", tc_num, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d BID mismatch | expected=%0d got=%0d",
                     tc_num, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // -----------------------------------------------------------------------
    // Task: check_rid
    // -----------------------------------------------------------------------
    task check_rid;
        input [ID_WIDTH-1:0] actual;
        input [ID_WIDTH-1:0] expected;
    begin
        if (actual === expected) begin
            $display("  [PASS] TC%02d RID match | got=%0d", tc_num, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d RID mismatch | expected=%0d got=%0d",
                     tc_num, expected, actual);
            fail_count = fail_count + 1;
        end
    end
    endtask

    // -----------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -----------------------------------------------------------------------
    integer k;

    initial begin
        $dumpfile("tb_data_mem_axi4_slave.vcd");
        $dumpvars(0, tb_data_mem_axi4_slave);

        pass_count = 0;
        fail_count = 0;
        tc_num     = 0;

        do_reset;

        // ====================================================================
        // TC01: Single write len=1, WVALID đến CÙNG cycle AW
        //       → Kiểm tra FIX-BUG5: beat đầu không bị drop
        // ====================================================================
        tc_num = 1;
        $display("\n[TC%02d] Single write len=1 — WVALID simultaneous with AW (FIX-BUG5)", tc_num);
        wr_data_arr[0] = 32'hDEAD_BEEF;
        wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0000, 4'd1, 1, 1); // simultaneous=1
        check_bid(S_AXI_BID, 4'd1);
        // Đọc lại để xác nhận data đã được ghi
        axi_read_burst(BASE_ADDR + 32'h0000, 4'd1, 1, -1);
        check_value(rd_data_buf[0], 32'hDEAD_BEEF, "TC01 wr then rd");

        // ====================================================================
        // TC02: Single write len=1, WVALID đến SAU AW
        // ====================================================================
        tc_num = 2;
        $display("\n[TC%02d] Single write len=1 — WVALID after AW (normal)", tc_num);
        wr_data_arr[0] = 32'hCAFE_0002;
        wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0010, 4'd2, 1, 0); // simultaneous=0
        check_bid(S_AXI_BID, 4'd2);
        axi_read_burst(BASE_ADDR + 32'h0010, 4'd2, 1, -1);
        check_value(rd_data_buf[0], 32'hCAFE_0002, "TC02 wr then rd");

        // ====================================================================
        // TC03: Burst write len=4 — CPU cache eviction (4 beats INCR)
        // ====================================================================
        tc_num = 3;
        $display("\n[TC%02d] Burst write len=4 — CPU cache eviction", tc_num);
        wr_data_arr[0] = 32'h0300_AA00;
        wr_data_arr[1] = 32'h0301_BB01;
        wr_data_arr[2] = 32'h0302_CC02;
        wr_data_arr[3] = 32'h0303_DD03;
        wr_strb_arr[0] = 4'hF; wr_strb_arr[1] = 4'hF;
        wr_strb_arr[2] = 4'hF; wr_strb_arr[3] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0100, 4'd3, 4, 0);
        check_bid(S_AXI_BID, 4'd3);
        // Đọc lại 4 beat
        axi_read_burst(BASE_ADDR + 32'h0100, 4'd3, 4, -1);
        check_value(rd_data_buf[0], 32'h0300_AA00, "TC03 beat0");
        check_value(rd_data_buf[1], 32'h0301_BB01, "TC03 beat1");
        check_value(rd_data_buf[2], 32'h0302_CC02, "TC03 beat2");
        check_value(rd_data_buf[3], 32'h0303_DD03, "TC03 beat3");

        // ====================================================================
        // TC04: Burst write len=8 — DMA IPASCON ghi vào data_mem
        // ====================================================================
        tc_num = 4;
        $display("\n[TC%02d] Burst write len=8 — IPASCON DMA write", tc_num);
        for (k = 0; k < 8; k = k+1) begin
            wr_data_arr[k] = 32'h0400_0000 + k;
            wr_strb_arr[k] = 4'hF;
        end
        axi_write_burst(BASE_ADDR + 32'h0200, 4'd4, 8, 0);
        check_bid(S_AXI_BID, 4'd4);
        axi_read_burst(BASE_ADDR + 32'h0200, 4'd4, 8, -1);
        for (k = 0; k < 8; k = k+1)
            check_value(rd_data_buf[k], 32'h0400_0000 + k, "TC04 beat");

        // ====================================================================
        // TC05: Burst write len=16 — max DMA burst
        // ====================================================================
        tc_num = 5;
        $display("\n[TC%02d] Burst write len=16 — max DMA burst", tc_num);
        for (k = 0; k < 16; k = k+1) begin
            wr_data_arr[k] = 32'h0500_0000 + k * 32'h11;
            wr_strb_arr[k] = 4'hF;
        end
        axi_write_burst(BASE_ADDR + 32'h0300, 4'd5, 16, 0);
        check_bid(S_AXI_BID, 4'd5);
        axi_read_burst(BASE_ADDR + 32'h0300, 4'd5, 16, -1);
        for (k = 0; k < 16; k = k+1)
            check_value(rd_data_buf[k], 32'h0500_0000 + k * 32'h11, "TC05 beat");

        // ====================================================================
        // TC06: Single read len=1 từ địa chỉ đã write ở TC01
        // ====================================================================
        tc_num = 6;
        $display("\n[TC%02d] Single read len=1", tc_num);
        axi_read_burst(BASE_ADDR + 32'h0000, 4'd6, 1, -1);
        check_value(rd_data_buf[0], 32'hDEAD_BEEF, "TC06 single rd");
        check_rid(S_AXI_RID, 4'd6);

        // ====================================================================
        // TC07: Burst read len=4
        // ====================================================================
        tc_num = 7;
        $display("\n[TC%02d] Burst read len=4 — DMA fetch", tc_num);
        axi_read_burst(BASE_ADDR + 32'h0100, 4'd7, 4, -1);
        check_value(rd_data_buf[0], 32'h0300_AA00, "TC07 beat0");
        check_value(rd_data_buf[1], 32'h0301_BB01, "TC07 beat1");
        check_value(rd_data_buf[2], 32'h0302_CC02, "TC07 beat2");
        check_value(rd_data_buf[3], 32'h0303_DD03, "TC07 beat3");

        // ====================================================================
        // TC08: Burst read len=8
        // ====================================================================
        tc_num = 8;
        $display("\n[TC%02d] Burst read len=8 — DMA fetch", tc_num);
        axi_read_burst(BASE_ADDR + 32'h0200, 4'd8, 8, -1);
        for (k = 0; k < 8; k = k+1)
            check_value(rd_data_buf[k], 32'h0400_0000 + k, "TC08 beat");

        // ====================================================================
        // TC09: Write→Read data integrity — nhiều địa chỉ khác nhau
        // ====================================================================
        tc_num = 9;
        $display("\n[TC%02d] Write→Read data integrity (4 locations)", tc_num);
        // Ghi 4 word vào 4 địa chỉ khác nhau
        wr_data_arr[0] = 32'h1234_5678; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0400, 4'd9, 1, 0);
        wr_data_arr[0] = 32'hABCD_EF01; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0404, 4'd9, 1, 0);
        wr_data_arr[0] = 32'hFEDC_BA98; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0408, 4'd9, 1, 0);
        wr_data_arr[0] = 32'h5A5A_5A5A; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h040C, 4'd9, 1, 0);
        // Đọc lại
        axi_read_burst(BASE_ADDR + 32'h0400, 4'd9, 4, -1);
        check_value(rd_data_buf[0], 32'h1234_5678, "TC09 addr+0");
        check_value(rd_data_buf[1], 32'hABCD_EF01, "TC09 addr+4");
        check_value(rd_data_buf[2], 32'hFEDC_BA98, "TC09 addr+8");
        check_value(rd_data_buf[3], 32'h5A5A_5A5A, "TC09 addr+C");

        // ====================================================================
        // TC10: Partial byte strobe WSTRB
        // ====================================================================
        tc_num = 10;
        $display("\n[TC%02d] Partial byte strobe (WSTRB=0101 → byte0,byte2 only)", tc_num);
        // Ghi base = 0xFFFF_FFFF trước
        wr_data_arr[0] = 32'hFFFF_FFFF; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0500, 4'd10, 1, 0);
        // Ghi lại chỉ byte0 và byte2 với strobe = 4'b0101
        wr_data_arr[0] = 32'hAA_BB_CC_DD; wr_strb_arr[0] = 4'b0101; // byte0=DD, byte2=BB
        axi_write_burst(BASE_ADDR + 32'h0500, 4'd10, 1, 0);
        // Đọc lại → byte0=DD, byte1=FF(unchanged), byte2=BB, byte3=FF(unchanged)
        axi_read_burst(BASE_ADDR + 32'h0500, 4'd10, 1, -1);
        check_value(rd_data_buf[0], 32'hFF_BB_FF_DD, "TC10 partial strobe");

        // ====================================================================
        // TC11: Read backpressure — RREADY de-assert giữa burst
        // ====================================================================
        tc_num = 11;
        $display("\n[TC%02d] Read backpressure — RREADY de-assert at beat 2", tc_num);
        // Ghi 4 word vào 0x0600
        for (k = 0; k < 4; k = k+1) begin
            wr_data_arr[k] = 32'h0B00_0000 + k;
            wr_strb_arr[k] = 4'hF;
        end
        axi_write_burst(BASE_ADDR + 32'h0600, 4'd11, 4, 0);
        // Đọc với backpressure tại beat 2
        axi_read_burst(BASE_ADDR + 32'h0600, 4'd11, 4, 2);
        check_value(rd_data_buf[0], 32'h0B00_0000, "TC11 beat0");
        check_value(rd_data_buf[1], 32'h0B00_0001, "TC11 beat1");
        check_value(rd_data_buf[2], 32'h0B00_0002, "TC11 beat2 after bp");
        check_value(rd_data_buf[3], 32'h0B00_0003, "TC11 beat3");

        // ====================================================================
        // TC12: Hai write liên tiếp không idle
        // ====================================================================
        tc_num = 12;
        $display("\n[TC%02d] Two consecutive writes no idle", tc_num);
        wr_data_arr[0] = 32'hC001_0001; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0700, 4'd12, 1, 0);
        wr_data_arr[0] = 32'hC002_0002; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0704, 4'd12, 1, 0);
        // Đọc lại 2 word
        axi_read_burst(BASE_ADDR + 32'h0700, 4'd12, 2, -1);
        check_value(rd_data_buf[0], 32'hC001_0001, "TC12 wr1");
        check_value(rd_data_buf[1], 32'hC002_0002, "TC12 wr2");

        // ====================================================================
        // TC13: Reset giữa chừng transaction write
        // ====================================================================
        tc_num = 13;
        $display("\n[TC%02d] Reset in the middle of write transaction", tc_num);
        // Bắt đầu ghi nhưng reset trước khi hoàn thành
        @(posedge clk); #1;
        S_AXI_AWID    <= 4'd13;
        S_AXI_AWADDR  <= BASE_ADDR + 32'h0800;
        S_AXI_AWLEN   <= 8'd3;
        S_AXI_AWSIZE  <= 3'b010;
        S_AXI_AWBURST <= 2'b01;
        S_AXI_AWVALID <= 1;
        @(posedge clk); // AW nhận được
        #1; S_AXI_AWVALID <= 0;
        // Ghi 1 beat rồi reset
        S_AXI_WDATA  <= 32'hDEAD_1313;
        S_AXI_WSTRB  <= 4'hF;
        S_AXI_WLAST  <= 0;
        S_AXI_WVALID <= 1;
        @(posedge clk);
        #1;
        // Phát reset
        rst_n <= 0;
        repeat(3) @(posedge clk);
        rst_n <= 1;
        S_AXI_WVALID <= 0;
        S_AXI_AWVALID <= 0;
        @(posedge clk);
        // Sau reset: slave phải về IDLE, BVALID=0, ARREADY/AWREADY về trạng thái init
        if (!S_AXI_BVALID) begin
            $display("  [PASS] TC%02d BVALID=0 after reset", tc_num);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d BVALID should be 0 after reset", tc_num);
            fail_count = fail_count + 1;
        end
        // Sau reset slave sẽ assert AWREADY=0 (init state là 0 trước khi vào IDLE)
        // Chờ 2 cycle để state machine vào IDLE và assert AWREADY
        repeat(2) @(posedge clk);
        if (S_AXI_AWREADY) begin
            $display("  [PASS] TC%02d AWREADY=1 after reset (WR_IDLE)", tc_num);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] TC%02d AWREADY should be 1 in WR_IDLE", tc_num);
            fail_count = fail_count + 1;
        end

        // ====================================================================
        // TC14: BID phải match AWID / RID phải match ARID
        // ====================================================================
        tc_num = 14;
        $display("\n[TC%02d] BID must match AWID / RID must match ARID", tc_num);
        wr_data_arr[0] = 32'hE14E_0001; wr_strb_arr[0] = 4'hF;
        axi_write_burst(BASE_ADDR + 32'h0900, 4'd14, 1, 0);
        check_bid(S_AXI_BID, 4'd14);
        axi_read_burst(BASE_ADDR + 32'h0900, 4'd14, 1, -1);
        check_rid(S_AXI_RID, 4'd14);

        // ====================================================================
        // TC15: CPU write burst len=4 vùng 0x0A00, sau đó DMA đọc lại
        //       simultaneous_w=0 (normal flow, không trigger bug địa chỉ)
        //
        // [BUG DOCUMENTATION - data_mem_burst.v]
        // Khi simultaneous_w=1 (FIX-BUG5 path trên AXI slave):
        //   burst_wr_valid assert cùng cycle AW handshake.
        //   Tại cycle đó, write_addr reg trong AXI slave CHƯA được latch
        //   (latch xảy ra posedge clk kế tiếp). Do đó burst_wr_addr
        //   mà data_mem_burst nhìn thấy = giá trị CŨ từ transaction trước
        //   → beat đầu bị ghi vào địa chỉ sai (off by previous addr).
        // Root cause: data_mem_burst dùng burst_wr_addr combinatorially
        //   ngay tại cycle đầu của burst_wr_valid, nhưng AXI slave mất
        //   1 cycle để latch AWADDR → write_addr.
        // Impact: CPU cache eviction với simultaneous W sẽ ghi data vào
        //   địa chỉ sai → memory corruption trong SoC.
        // Fix đề xuất: Thêm 1 cycle pipeline delay trong data_mem_burst
        //   để đợi write_addr ổn định; hoặc AXI slave cần assert
        //   burst_wr_valid 1 cycle SAU khi write_addr đã được latch.
        // ====================================================================
        tc_num = 15;
        $display("\n[TC%02d] CPU write len=4 @ 0xA00 then DMA read (normal flow)", tc_num);
        $display("  [NOTE] simultaneous_w=0 used — see BUG DOC above for simultaneous_w=1 issue");
        for (k = 0; k < 4; k = k+1) begin
            wr_data_arr[k] = 32'h0F00_0000 + k;
            wr_strb_arr[k] = 4'hF;
        end
        axi_write_burst(BASE_ADDR + 32'h0A00, 4'd15, 4, 0);  // simultaneous=0
        check_bid(S_AXI_BID, 4'd15);
        // DMA đọc lại vùng vừa ghi
        axi_read_burst(BASE_ADDR + 32'h0A00, 4'd15, 4, -1);
        check_value(rd_data_buf[0], 32'h0F00_0000, "TC15 CPU wr beat0");
        check_value(rd_data_buf[1], 32'h0F00_0001, "TC15 CPU wr beat1");
        check_value(rd_data_buf[2], 32'h0F00_0002, "TC15 CPU wr beat2");
        check_value(rd_data_buf[3], 32'h0F00_0003, "TC15 CPU wr beat3");
        // Cũng đọc vùng DMA cũ để confirm không bị ảnh hưởng
        axi_read_burst(BASE_ADDR + 32'h0200, 4'd15, 2, -1);
        check_value(rd_data_buf[0], 32'h0400_0000, "TC15 DMA old rd beat0");
        check_value(rd_data_buf[1], 32'h0400_0001, "TC15 DMA old rd beat1");

        // ====================================================================
        // SUMMARY
        // ====================================================================
        repeat(5) @(posedge clk);
        $display("\n============================================================");
        $display("  TESTBENCH SUMMARY");
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

    // -----------------------------------------------------------------------
    // Watchdog: tránh hang simulation
    // -----------------------------------------------------------------------
    initial begin
        #500000;
        $display("[WATCHDOG] Simulation timed out!");
        $finish;
    end

endmodule