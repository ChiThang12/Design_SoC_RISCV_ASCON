// ============================================================================
// tb_axi_width_converter_64to32.v  (Verilog-2001 compatible — fixed)
//
// Các thay đổi so với bản gốc:
//   1. Bỏ `string` → dùng reg [255:0] / reg [8*64-1:0]
//   2. Thay  @(posedge clk iff COND)  →  wait-loop tương đương
//   3. Bỏ khai báo biến bên trong begin...end block → khai báo ở đầu module
//   4. Bỏ cú pháp SystemVerilog fork-join trong named block có local var
//   5. Sửa task fail_tc: tham số là reg [255:0] thay vì string
// ============================================================================
`timescale 1ns/1ps
`include "axi_width_converter_64to32.v"

module tb_axi_width_converter_64to32;

// ============================================================================
// Parameters
// ============================================================================
localparam ADDR_WIDTH   = 32;
localparam ID_WIDTH     = 4;
localparam M_DATA_WIDTH = 64;
localparam S_DATA_WIDTH = 32;
localparam M_STRB_WIDTH = 8;
localparam S_STRB_WIDTH = 4;
localparam CLK_PERIOD   = 10;

// ============================================================================
// Clock & Reset
// ============================================================================
reg clk, rst_n;
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT ports — Master side (64-bit)
// ============================================================================
reg  [ID_WIDTH-1:0]     M_AXI_AWID;
reg  [ADDR_WIDTH-1:0]   M_AXI_AWADDR;
reg  [7:0]              M_AXI_AWLEN;
reg  [2:0]              M_AXI_AWSIZE;
reg  [1:0]              M_AXI_AWBURST;
reg  [3:0]              M_AXI_AWCACHE;
reg  [2:0]              M_AXI_AWPROT;
reg                     M_AXI_AWVALID;
wire                    M_AXI_AWREADY;

reg  [M_DATA_WIDTH-1:0] M_AXI_WDATA;
reg  [M_STRB_WIDTH-1:0] M_AXI_WSTRB;
reg                     M_AXI_WLAST;
reg                     M_AXI_WVALID;
wire                    M_AXI_WREADY;

wire [ID_WIDTH-1:0]     M_AXI_BID;
wire [1:0]              M_AXI_BRESP;
wire                    M_AXI_BVALID;
reg                     M_AXI_BREADY;

reg  [ID_WIDTH-1:0]     M_AXI_ARID;
reg  [ADDR_WIDTH-1:0]   M_AXI_ARADDR;
reg  [7:0]              M_AXI_ARLEN;
reg  [2:0]              M_AXI_ARSIZE;
reg  [1:0]              M_AXI_ARBURST;
reg  [3:0]              M_AXI_ARCACHE;
reg  [2:0]              M_AXI_ARPROT;
reg                     M_AXI_ARVALID;
wire                    M_AXI_ARREADY;

wire [ID_WIDTH-1:0]     M_AXI_RID;
wire [M_DATA_WIDTH-1:0] M_AXI_RDATA;
wire [1:0]              M_AXI_RRESP;
wire                    M_AXI_RLAST;
wire                    M_AXI_RVALID;
reg                     M_AXI_RREADY;

// ============================================================================
// DUT ports — Slave side (32-bit)
// ============================================================================
wire [ID_WIDTH-1:0]     S_AXI_AWID;
wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR;
wire [7:0]              S_AXI_AWLEN;
wire [2:0]              S_AXI_AWSIZE;
wire [1:0]              S_AXI_AWBURST;
wire [2:0]              S_AXI_AWPROT;
wire                    S_AXI_AWVALID;
reg                     S_AXI_AWREADY;

wire [S_DATA_WIDTH-1:0] S_AXI_WDATA;
wire [S_STRB_WIDTH-1:0] S_AXI_WSTRB;
wire                    S_AXI_WLAST;
wire                    S_AXI_WVALID;
reg                     S_AXI_WREADY;

reg  [ID_WIDTH-1:0]     S_AXI_BID;
reg  [1:0]              S_AXI_BRESP;
reg                     S_AXI_BVALID;
wire                    S_AXI_BREADY;

wire [ID_WIDTH-1:0]     S_AXI_ARID;
wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR;
wire [7:0]              S_AXI_ARLEN;
wire [2:0]              S_AXI_ARSIZE;
wire [1:0]              S_AXI_ARBURST;
wire [2:0]              S_AXI_ARPROT;
wire                    S_AXI_ARVALID;
reg                     S_AXI_ARREADY;

reg  [ID_WIDTH-1:0]     S_AXI_RID;
reg  [S_DATA_WIDTH-1:0] S_AXI_RDATA;
reg  [1:0]              S_AXI_RRESP;
reg                     S_AXI_RLAST;
reg                     S_AXI_RVALID;
wire                    S_AXI_RREADY;

// ============================================================================
// DUT instantiation
// ============================================================================
axi_width_converter_64to32 #(
    .ADDR_WIDTH   (ADDR_WIDTH),
    .ID_WIDTH     (ID_WIDTH),
    .M_DATA_WIDTH (M_DATA_WIDTH),
    .S_DATA_WIDTH (S_DATA_WIDTH)
) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .M_AXI_AWID       (M_AXI_AWID),
    .M_AXI_AWADDR     (M_AXI_AWADDR),
    .M_AXI_AWLEN      (M_AXI_AWLEN),
    .M_AXI_AWSIZE     (M_AXI_AWSIZE),
    .M_AXI_AWBURST    (M_AXI_AWBURST),
    .M_AXI_AWCACHE    (M_AXI_AWCACHE),
    .M_AXI_AWPROT     (M_AXI_AWPROT),
    .M_AXI_AWVALID    (M_AXI_AWVALID),
    .M_AXI_AWREADY    (M_AXI_AWREADY),
    .M_AXI_WDATA      (M_AXI_WDATA),
    .M_AXI_WSTRB      (M_AXI_WSTRB),
    .M_AXI_WLAST      (M_AXI_WLAST),
    .M_AXI_WVALID     (M_AXI_WVALID),
    .M_AXI_WREADY     (M_AXI_WREADY),
    .M_AXI_BID        (M_AXI_BID),
    .M_AXI_BRESP      (M_AXI_BRESP),
    .M_AXI_BVALID     (M_AXI_BVALID),
    .M_AXI_BREADY     (M_AXI_BREADY),
    .M_AXI_ARID       (M_AXI_ARID),
    .M_AXI_ARADDR     (M_AXI_ARADDR),
    .M_AXI_ARLEN      (M_AXI_ARLEN),
    .M_AXI_ARSIZE     (M_AXI_ARSIZE),
    .M_AXI_ARBURST    (M_AXI_ARBURST),
    .M_AXI_ARCACHE    (M_AXI_ARCACHE),
    .M_AXI_ARPROT     (M_AXI_ARPROT),
    .M_AXI_ARVALID    (M_AXI_ARVALID),
    .M_AXI_ARREADY    (M_AXI_ARREADY),
    .M_AXI_RID        (M_AXI_RID),
    .M_AXI_RDATA      (M_AXI_RDATA),
    .M_AXI_RRESP      (M_AXI_RRESP),
    .M_AXI_RLAST      (M_AXI_RLAST),
    .M_AXI_RVALID     (M_AXI_RVALID),
    .M_AXI_RREADY     (M_AXI_RREADY),
    .S_AXI_AWID       (S_AXI_AWID),
    .S_AXI_AWADDR     (S_AXI_AWADDR),
    .S_AXI_AWLEN      (S_AXI_AWLEN),
    .S_AXI_AWSIZE     (S_AXI_AWSIZE),
    .S_AXI_AWBURST    (S_AXI_AWBURST),
    .S_AXI_AWPROT     (S_AXI_AWPROT),
    .S_AXI_AWVALID    (S_AXI_AWVALID),
    .S_AXI_AWREADY    (S_AXI_AWREADY),
    .S_AXI_WDATA      (S_AXI_WDATA),
    .S_AXI_WSTRB      (S_AXI_WSTRB),
    .S_AXI_WLAST      (S_AXI_WLAST),
    .S_AXI_WVALID     (S_AXI_WVALID),
    .S_AXI_WREADY     (S_AXI_WREADY),
    .S_AXI_BID        (S_AXI_BID),
    .S_AXI_BRESP      (S_AXI_BRESP),
    .S_AXI_BVALID     (S_AXI_BVALID),
    .S_AXI_BREADY     (S_AXI_BREADY),
    .S_AXI_ARID       (S_AXI_ARID),
    .S_AXI_ARADDR     (S_AXI_ARADDR),
    .S_AXI_ARLEN      (S_AXI_ARLEN),
    .S_AXI_ARSIZE     (S_AXI_ARSIZE),
    .S_AXI_ARBURST    (S_AXI_ARBURST),
    .S_AXI_ARPROT     (S_AXI_ARPROT),
    .S_AXI_ARVALID    (S_AXI_ARVALID),
    .S_AXI_ARREADY    (S_AXI_ARREADY),
    .S_AXI_RID        (S_AXI_RID),
    .S_AXI_RDATA      (S_AXI_RDATA),
    .S_AXI_RRESP      (S_AXI_RRESP),
    .S_AXI_RLAST      (S_AXI_RLAST),
    .S_AXI_RVALID     (S_AXI_RVALID),
    .S_AXI_RREADY     (S_AXI_RREADY)
);

// ============================================================================
// Score tracking — dùng reg thay vì string
// ============================================================================
integer pass_count, fail_count, tc_num;
reg [8*64-1:0] tc_name;   // thay "string" bằng reg đủ rộng

task pass_tc;
    begin
        $display("[PASS] TC%-2d: %s", tc_num, tc_name);
        pass_count = pass_count + 1;
    end
endtask

task fail_tc;
    input [8*64-1:0] reason;   // thay "string" parameter
    begin
        $display("[FAIL] TC%-2d: %s -- %s", tc_num, tc_name, reason);
        fail_count = fail_count + 1;
    end
endtask

// ============================================================================
// Clock helpers
// ============================================================================
task clk_cycle;
    begin
        @(posedge clk); #1;
    end
endtask

task clk_n;
    input integer n;
    integer ci;
    begin
        for (ci = 0; ci < n; ci = ci+1)
            clk_cycle;
    end
endtask

// ============================================================================
// Reset
// ============================================================================
task do_reset;
    begin
        rst_n = 0;
        M_AXI_AWID=0; M_AXI_AWADDR=0; M_AXI_AWLEN=0;
        M_AXI_AWSIZE=3'b011; M_AXI_AWBURST=2'b01;
        M_AXI_AWCACHE=0; M_AXI_AWPROT=0; M_AXI_AWVALID=0;
        M_AXI_WDATA=0; M_AXI_WSTRB=0; M_AXI_WLAST=0;
        M_AXI_WVALID=0; M_AXI_BREADY=1;
        M_AXI_ARID=0; M_AXI_ARADDR=0; M_AXI_ARLEN=0;
        M_AXI_ARSIZE=3'b011; M_AXI_ARBURST=2'b01;
        M_AXI_ARCACHE=0; M_AXI_ARPROT=0; M_AXI_ARVALID=0;
        M_AXI_RREADY=1;
        S_AXI_AWREADY=1; S_AXI_WREADY=1;
        S_AXI_BID=0; S_AXI_BRESP=0; S_AXI_BVALID=0;
        S_AXI_ARREADY=1;
        S_AXI_RID=0; S_AXI_RDATA=0; S_AXI_RRESP=0;
        S_AXI_RLAST=0; S_AXI_RVALID=0;
        clk_n(5);
        rst_n = 1;
        clk_n(2);
    end
endtask

// ============================================================================
// master_aw: gửi AW, chờ AWREADY bằng polling loop
// ============================================================================
task master_aw;
    input [ID_WIDTH-1:0]   id;
    input [ADDR_WIDTH-1:0] addr;
    input [7:0]            len;
    begin
        M_AXI_AWID    = id;
        M_AXI_AWADDR  = addr;
        M_AXI_AWLEN   = len;
        M_AXI_AWSIZE  = 3'b011;
        M_AXI_AWBURST = 2'b01;
        M_AXI_AWVALID = 1;
        // Thay @(posedge clk iff M_AXI_AWREADY) → polling loop
        begin : aw_wait
            reg done;
            done = 0;
            while (!done) begin
                @(posedge clk);
                if (M_AXI_AWREADY) done = 1;
            end
        end
        #1;
        M_AXI_AWVALID = 0;
    end
endtask

// ============================================================================
// master_wdata: gửi W beat, chờ WREADY
// ============================================================================
task master_wdata;
    input [M_DATA_WIDTH-1:0] data;
    input [M_STRB_WIDTH-1:0] strb;
    input                    last;
    begin
        M_AXI_WDATA  = data;
        M_AXI_WSTRB  = strb;
        M_AXI_WLAST  = last;
        M_AXI_WVALID = 1;
        begin : w_wait
            reg done;
            done = 0;
            while (!done) begin
                @(posedge clk);
                if (M_AXI_WREADY) done = 1;
            end
        end
        #1;
        M_AXI_WVALID = 0;
        M_AXI_WLAST  = 0;
    end
endtask

// ============================================================================
// slave_bresp
// ============================================================================
task slave_bresp;
    input [ID_WIDTH-1:0] id;
    input [1:0]          resp;
    begin
        S_AXI_BID    = id;
        S_AXI_BRESP  = resp;
        S_AXI_BVALID = 1;
        begin : b_wait
            reg done;
            done = 0;
            while (!done) begin
                @(posedge clk);
                if (S_AXI_BREADY) done = 1;
            end
        end
        #1;
        S_AXI_BVALID = 0;
    end
endtask

// ============================================================================
// Capture arrays cho slave W beats
// ============================================================================
reg [S_DATA_WIDTH-1:0] s_wdata_captured [0:31];
reg [S_STRB_WIDTH-1:0] s_wstrb_captured [0:31];
reg                    s_wlast_captured [0:31];
integer s_beat_cnt;

task collect_slave_wbeats;
    input integer num_beats;
    integer sw_i;
    begin
        s_beat_cnt = 0;
        sw_i = 0;
        while (sw_i < num_beats) begin
            @(posedge clk);
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                s_wdata_captured[s_beat_cnt] = S_AXI_WDATA;
                s_wstrb_captured[s_beat_cnt] = S_AXI_WSTRB;
                s_wlast_captured[s_beat_cnt] = S_AXI_WLAST;
                s_beat_cnt = s_beat_cnt + 1;
                sw_i = sw_i + 1;
            end
        end
        #1;
    end
endtask

// ============================================================================
// slave_rdata
// ============================================================================
task slave_rdata;
    input [ID_WIDTH-1:0]     id;
    input [S_DATA_WIDTH-1:0] data;
    input [1:0]              resp;
    input                    last;
    begin
        S_AXI_RID    = id;
        S_AXI_RDATA  = data;
        S_AXI_RRESP  = resp;
        S_AXI_RLAST  = last;
        S_AXI_RVALID = 1;
        begin : sr_wait
            reg done;
            done = 0;
            while (!done) begin
                @(posedge clk);
                if (S_AXI_RREADY) done = 1;
            end
        end
        #1;
        S_AXI_RVALID = 0;
        S_AXI_RLAST  = 0;
    end
endtask

// ============================================================================
// Capture arrays cho master R beats
// ============================================================================
reg [M_DATA_WIDTH-1:0] m_rdata_captured [0:15];
reg [1:0]              m_rresp_captured [0:15];
reg                    m_rlast_captured [0:15];
integer m_rbeat_cnt;

task collect_master_rbeats;
    input integer num_beats;
    integer mr_i;
    begin
        m_rbeat_cnt = 0;
        mr_i = 0;
        while (mr_i < num_beats) begin
            @(posedge clk);
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                m_rdata_captured[m_rbeat_cnt] = M_AXI_RDATA;
                m_rresp_captured[m_rbeat_cnt] = M_AXI_RRESP;
                m_rlast_captured[m_rbeat_cnt] = M_AXI_RLAST;
                m_rbeat_cnt = m_rbeat_cnt + 1;
                mr_i = mr_i + 1;
            end
        end
        #1;
    end
endtask

// ============================================================================
// Biến dùng chung trong main (khai báo ở module scope)
// ============================================================================
integer i, errors;
reg [M_DATA_WIDTH-1:0] exp_rdata;

// Biến cho TC3
reg [31:0] tc3_hi, tc3_lo;

// Biến cho TC11
integer tc11_k;
reg [7:0] tc11_test_mlens  [0:4];
reg [7:0] tc11_exp_slens   [0:4];
integer   tc11_len_errors;
integer   tc11_mb, tc11_nb;

// Biến cho TC14
integer   tc14_txn;
reg [63:0] tc14_patterns [0:2];

// ============================================================================
// MAIN TEST
// ============================================================================
initial begin
    $dumpfile("tb_axi_width_converter_64to32.vcd");
    $dumpvars(0, tb_axi_width_converter_64to32);

    pass_count = 0;
    fail_count = 0;
    tc_num     = 0;

    do_reset;

    // ====================================================================
    // TC1: Write single beat AWLEN=0 → 2 slave beats
    // ====================================================================
    tc_num  = 1;
    tc_name = "Write single beat AWLEN=0";
    errors  = 0;

    fork
        begin : tc1_master
            master_aw(4'hA, 32'h1000_0000, 8'd0);
            master_wdata(64'hDEAD_BEEF_CAFE_F00D, 8'hFF, 1'b1);
            M_AXI_BREADY = 1;
        end
        begin : tc1_slave
            collect_slave_wbeats(2);
            slave_bresp(4'hA, 2'b00);
        end
    join

    if (S_AXI_AWLEN  !== 8'h01)   errors = errors + 1;
    if (S_AXI_AWSIZE !== 3'b010)  errors = errors + 1;
    if (s_wdata_captured[0] !== 32'hCAFE_F00D) errors = errors + 1;
    if (s_wdata_captured[1] !== 32'hDEAD_BEEF) errors = errors + 1;
    if (s_wstrb_captured[0] !== 4'hF)          errors = errors + 1;
    if (s_wstrb_captured[1] !== 4'hF)          errors = errors + 1;
    if (s_wlast_captured[0] !== 1'b0)          errors = errors + 1;
    if (s_wlast_captured[1] !== 1'b1)          errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Write data or AW check failed");

    // ====================================================================
    // TC2: Write burst AWLEN=3 → 8 slave beats
    // ====================================================================
    tc_num  = 2;
    tc_name = "Write burst AWLEN=3";
    errors  = 0;

    fork
        begin : tc2_master
            master_aw(4'h1, 32'h2000_0000, 8'd3);
            master_wdata(64'hAAAA_BBBB_CCCC_DDDD, 8'hFF, 1'b0);
            master_wdata(64'h1111_2222_3333_4444, 8'hFF, 1'b0);
            master_wdata(64'h5555_6666_7777_8888, 8'hFF, 1'b0);
            master_wdata(64'h9999_AAAA_BBBB_CCCC, 8'hFF, 1'b1);
        end
        begin : tc2_slave
            collect_slave_wbeats(8);
            slave_bresp(4'h1, 2'b00);
        end
    join

    if (S_AXI_AWLEN !== 8'h07)             errors = errors + 1;
    if (s_wdata_captured[0] !== 32'hCCCC_DDDD) errors = errors + 1;
    if (s_wdata_captured[1] !== 32'hAAAA_BBBB) errors = errors + 1;
    if (s_wdata_captured[2] !== 32'h3333_4444) errors = errors + 1;
    if (s_wdata_captured[3] !== 32'h1111_2222) errors = errors + 1;
    if (s_wdata_captured[4] !== 32'h7777_8888) errors = errors + 1;
    if (s_wdata_captured[5] !== 32'h5555_6666) errors = errors + 1;
    if (s_wdata_captured[6] !== 32'hBBBB_CCCC) errors = errors + 1;
    if (s_wdata_captured[7] !== 32'h9999_AAAA) errors = errors + 1;
    if (s_wlast_captured[7] !== 1'b1)          errors = errors + 1;
    if (s_wlast_captured[6] !== 1'b0)          errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Burst write data mismatch");

    // ====================================================================
    // TC3: Write burst AWLEN=7 → 16 slave beats
    // ====================================================================
    tc_num  = 3;
    tc_name = "Write burst AWLEN=7 (16 slave beats)";
    errors  = 0;

    fork
        begin : tc3_master
            master_aw(4'h2, 32'h3000_0000, 8'd7);
            for (i = 0; i < 8; i = i+1) begin
                tc3_lo = 32'hE000_0000 | (32'd2 * i);
                tc3_hi = 32'hF000_0000 | (32'd2 * i + 32'd1);
                master_wdata({tc3_hi, tc3_lo}, 8'hFF, (i==7) ? 1'b1 : 1'b0);
            end
        end
        begin : tc3_slave
            collect_slave_wbeats(16);
            slave_bresp(4'h2, 2'b00);
        end
    join

    if (S_AXI_AWLEN !== 8'h0F)              errors = errors + 1;
    if (s_wdata_captured[0]  !== 32'hE000_0000) errors = errors + 1;
    if (s_wdata_captured[1]  !== 32'hF000_0001) errors = errors + 1;
    if (s_wlast_captured[14] !== 1'b0)          errors = errors + 1;
    if (s_wlast_captured[15] !== 1'b1)          errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Long burst check failed");

    // ====================================================================
    // TC4: Write với slave WREADY stall
    // ====================================================================
    tc_num  = 4;
    tc_name = "Write slave WREADY back-pressure";
    errors  = 0;
    S_AXI_WREADY = 0;

    fork
        begin : tc4_master
            master_aw(4'h3, 32'h4000_0000, 8'd1);
            master_wdata(64'hDEAD_1234_BEEF_5678, 8'hFF, 1'b0);
            master_wdata(64'hABCD_EF01_2345_6789, 8'hFF, 1'b1);
        end
        begin : tc4_slave
            clk_n(8);
            S_AXI_WREADY = 1;
            collect_slave_wbeats(4);
            slave_bresp(4'h3, 2'b00);
        end
    join

    if (s_wdata_captured[0] !== 32'hBEEF_5678) errors = errors + 1;
    if (s_wdata_captured[1] !== 32'hDEAD_1234) errors = errors + 1;
    if (s_wdata_captured[2] !== 32'h2345_6789) errors = errors + 1;
    if (s_wdata_captured[3] !== 32'hABCD_EF01) errors = errors + 1;
    if (s_wlast_captured[3] !== 1'b1)          errors = errors + 1;

    clk_n(2);
    S_AXI_WREADY = 1;
    if (errors == 0) pass_tc; else fail_tc("Back-pressure write mismatch");

    // ====================================================================
    // TC5: Read single beat ARLEN=0 → 1×64-bit master
    // ====================================================================
    tc_num  = 5;
    tc_name = "Read single beat ARLEN=0";
    errors  = 0;
    M_AXI_RREADY = 1;
    S_AXI_ARREADY = 1;

    fork
        begin : tc5_master
            M_AXI_ARID    = 4'hB;
            M_AXI_ARADDR  = 32'h5000_0000;
            M_AXI_ARLEN   = 8'd0;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc5_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
        end
        begin : tc5_slave
            begin : tc5_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            if (S_AXI_ARLEN  !== 8'h01)  errors = errors + 1;
            if (S_AXI_ARSIZE !== 3'b010) errors = errors + 1;
            slave_rdata(4'hB, 32'hCAFE_1234, 2'b00, 1'b0);
            slave_rdata(4'hB, 32'hDEAD_BEEF, 2'b00, 1'b1);
        end
        begin : tc5_collect
            collect_master_rbeats(1);
        end
    join
    exp_rdata = {32'hDEAD_BEEF, 32'hCAFE_1234};
    if (m_rdata_captured[0] !== exp_rdata) errors = errors + 1;
    if (m_rlast_captured[0] !== 1'b1)      errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Read data assembly failed");

    // ====================================================================
    // TC6: Read burst ARLEN=3 → 4×64-bit master
    // ====================================================================
    tc_num  = 6;
    tc_name = "Read burst ARLEN=3";
    errors  = 0;
    M_AXI_RREADY = 1;

    fork
        begin : tc6_master
            M_AXI_ARID    = 4'h4;
            M_AXI_ARADDR  = 32'h6000_0000;
            M_AXI_ARLEN   = 8'd3;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc6_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
        end
        begin : tc6_slave
            begin : tc6_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            if (S_AXI_ARLEN !== 8'h07) errors = errors + 1;
            slave_rdata(4'h4, 32'hAAAA_0001, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'hBBBB_0002, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'hCCCC_0003, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'hDDDD_0004, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'hEEEE_0005, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'hFFFF_0006, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'h1111_0007, 2'b00, 1'b0);
            slave_rdata(4'h4, 32'h2222_0008, 2'b00, 1'b1);
        end
        begin : tc6_collect
            collect_master_rbeats(4);
        end
    join
    if (m_rdata_captured[0] !== {32'hBBBB_0002, 32'hAAAA_0001}) errors = errors + 1;
    if (m_rdata_captured[1] !== {32'hDDDD_0004, 32'hCCCC_0003}) errors = errors + 1;
    if (m_rdata_captured[2] !== {32'hFFFF_0006, 32'hEEEE_0005}) errors = errors + 1;
    if (m_rdata_captured[3] !== {32'h2222_0008, 32'h1111_0007}) errors = errors + 1;
    if (m_rlast_captured[0] !== 1'b0) errors = errors + 1;
    if (m_rlast_captured[1] !== 1'b0) errors = errors + 1;
    if (m_rlast_captured[2] !== 1'b0) errors = errors + 1;
    if (m_rlast_captured[3] !== 1'b1) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Read burst data mismatch");

    // ====================================================================
    // TC7: Read với slave RVALID stall
    // ====================================================================
    tc_num  = 7;
    tc_name = "Read slave RVALID stall";
    errors  = 0;
    M_AXI_RREADY = 1;

    fork
        begin : tc7_master
            M_AXI_ARID    = 4'h5;
            M_AXI_ARADDR  = 32'h7000_0000;
            M_AXI_ARLEN   = 8'd0;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc7_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
        end
        begin : tc7_slave
            begin : tc7_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            clk_n(10);
            slave_rdata(4'h5, 32'h1234_5678, 2'b00, 1'b0);
            clk_n(5);
            slave_rdata(4'h5, 32'hABCD_EF01, 2'b00, 1'b1);
        end
        begin : tc7_collect
            collect_master_rbeats(1);
        end
    join
    if (m_rdata_captured[0] !== {32'hABCD_EF01, 32'h1234_5678}) errors = errors + 1;
    if (m_rlast_captured[0] !== 1'b1) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Stalled slave read failed");

    // ====================================================================
    // TC8: Read với master RREADY stall
    // ====================================================================
    tc_num  = 8;
    tc_name = "Read master RREADY back-pressure";
    errors  = 0;
    M_AXI_RREADY = 0;

    fork
        begin : tc8_master
            M_AXI_ARID    = 4'h6;
            M_AXI_ARADDR  = 32'h8000_0000;
            M_AXI_ARLEN   = 8'd1;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc8_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
            clk_n(20);
            M_AXI_RREADY = 1;
        end
        begin : tc8_slave
            begin : tc8_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            slave_rdata(4'h6, 32'hAAAA_1111, 2'b00, 1'b0);
            slave_rdata(4'h6, 32'hBBBB_2222, 2'b00, 1'b0);
            slave_rdata(4'h6, 32'hCCCC_3333, 2'b00, 1'b0);
            slave_rdata(4'h6, 32'hDDDD_4444, 2'b00, 1'b1);
        end
        begin : tc8_collect
            collect_master_rbeats(2);
        end
    join
    if (m_rdata_captured[0] !== {32'hBBBB_2222, 32'hAAAA_1111}) errors = errors + 1;
    if (m_rdata_captured[1] !== {32'hDDDD_4444, 32'hCCCC_3333}) errors = errors + 1;
    if (m_rlast_captured[1] !== 1'b1) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Master back-pressure read failed");

    // ====================================================================
    // TC9: Simultaneous Write + Read
    // ====================================================================
    tc_num  = 9;
    tc_name = "Simultaneous Write + Read";
    errors  = 0;
    M_AXI_RREADY = 1;

    fork
        begin : tc9_write
            master_aw(4'h7, 32'h9000_0000, 8'd0);
            master_wdata(64'h1111_2222_3333_4444, 8'hFF, 1'b1);
        end
        begin : tc9_read
            M_AXI_ARID    = 4'h8;
            M_AXI_ARADDR  = 32'hA000_0000;
            M_AXI_ARLEN   = 8'd0;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc9_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
        end
        begin : tc9_slave_wr
            collect_slave_wbeats(2);
            slave_bresp(4'h7, 2'b00);
        end
        begin : tc9_slave_rd
            begin : tc9_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            slave_rdata(4'h8, 32'hFEED_FACE, 2'b00, 1'b0);
            slave_rdata(4'h8, 32'hC0DE_BABE, 2'b00, 1'b1);
        end
        begin : tc9_collect
            collect_master_rbeats(1);
        end
    join
    if (s_wdata_captured[0] !== 32'h3333_4444) errors = errors + 1;
    if (s_wdata_captured[1] !== 32'h1111_2222) errors = errors + 1;
    if (m_rdata_captured[0] !== {32'hC0DE_BABE, 32'hFEED_FACE}) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Simultaneous RW failed");

    // ====================================================================
    // TC10: Write partial WSTRB
    // ====================================================================
    tc_num  = 10;
    tc_name = "Write partial WSTRB (byte lanes)";
    errors  = 0;

    fork
        begin : tc10_master
            master_aw(4'hC, 32'hB000_0000, 8'd0);
            master_wdata(64'hDEAD_BEEF_CAFE_F00D, 8'b1010_0101, 1'b1);
        end
        begin : tc10_slave
            collect_slave_wbeats(2);
            slave_bresp(4'hC, 2'b00);
        end
    join

    if (s_wstrb_captured[0] !== 4'b0101)       errors = errors + 1;
    if (s_wstrb_captured[1] !== 4'b1010)       errors = errors + 1;
    if (s_wdata_captured[0] !== 32'hCAFE_F00D) errors = errors + 1;
    if (s_wdata_captured[1] !== 32'hDEAD_BEEF) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("WSTRB partial lanes failed");

    // ====================================================================
    // TC11: AWLEN doubling formula
    // ====================================================================
    tc_num  = 11;
    tc_name = "AWLEN doubling formula";
    errors  = 0;

    tc11_test_mlens[0] = 8'd0;   tc11_exp_slens[0] = 8'd1;
    tc11_test_mlens[1] = 8'd1;   tc11_exp_slens[1] = 8'd3;
    tc11_test_mlens[2] = 8'd7;   tc11_exp_slens[2] = 8'd15;
    tc11_test_mlens[3] = 8'd15;  tc11_exp_slens[3] = 8'd31;
    tc11_test_mlens[4] = 8'd127; tc11_exp_slens[4] = 8'd255;
    tc11_len_errors = 0;

    for (tc11_k = 0; tc11_k < 5; tc11_k = tc11_k + 1) begin
        M_AXI_AWID    = 4'd0;
        M_AXI_AWADDR  = 32'hC000_0000;
        M_AXI_AWLEN   = tc11_test_mlens[tc11_k];
        M_AXI_AWSIZE  = 3'b011;
        M_AXI_AWBURST = 2'b01;
        M_AXI_AWVALID = 1;
        S_AXI_AWREADY = 1;
        @(posedge clk); #1;
        if (S_AXI_AWLEN !== tc11_exp_slens[tc11_k]) begin
            $display("  TC11: M_AWLEN=%0d exp S_AWLEN=%0d got %0d",
                      tc11_test_mlens[tc11_k], tc11_exp_slens[tc11_k], S_AXI_AWLEN);
            tc11_len_errors = tc11_len_errors + 1;
        end
        M_AXI_AWVALID = 0;
        // Drain: gửi master beats và collect slave beats song song
        fork
            begin : tc11_mw
                for (tc11_mb = 0; tc11_mb <= tc11_test_mlens[tc11_k]; tc11_mb = tc11_mb + 1)
                    master_wdata(64'h0, 8'hFF,
                                 (tc11_mb == tc11_test_mlens[tc11_k]) ? 1'b1 : 1'b0);
            end
            begin : tc11_sw
                tc11_nb = (tc11_test_mlens[tc11_k] + 1) * 2;
                collect_slave_wbeats(tc11_nb);
                slave_bresp(4'd0, 2'b00);
            end
        join
        clk_n(2);
    end
    errors = tc11_len_errors;

    if (errors == 0) pass_tc; else fail_tc("AWLEN doubling formula mismatch");

    // ====================================================================
    // TC12: BRESP pass-through SLVERR
    // ====================================================================
    tc_num  = 12;
    tc_name = "BRESP pass-through SLVERR";
    errors  = 0;

    fork
        begin : tc12_master
            master_aw(4'hD, 32'hD000_0000, 8'd0);
            master_wdata(64'hFFFF_FFFF_FFFF_FFFF, 8'hFF, 1'b1);
            M_AXI_BREADY = 1;
        end
        begin : tc12_slave
            collect_slave_wbeats(2);
            slave_bresp(4'hD, 2'b10);
        end
        begin : tc12_check
            // Chờ M_AXI_BVALID trong fork (cùng lúc slave_bresp đang active)
            begin : tc12_bwait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_BVALID) done = 1; end
            end
            #1;
            if (M_AXI_BRESP !== 2'b10) errors = errors + 1;
            if (M_AXI_BID   !== 4'hD)  errors = errors + 1;
        end
    join

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("BRESP SLVERR pass-through failed");

    // ====================================================================
    // TC13: RRESP worst-case OR merge
    // ====================================================================
    tc_num  = 13;
    tc_name = "RRESP worst-case OR (beat1=SLVERR)";
    errors  = 0;
    M_AXI_RREADY = 1;

    fork
        begin : tc13_master
            M_AXI_ARID    = 4'hE;
            M_AXI_ARADDR  = 32'hE000_0000;
            M_AXI_ARLEN   = 8'd0;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc13_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
        end
        begin : tc13_slave
            begin : tc13_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            slave_rdata(4'hE, 32'h1234_5678, 2'b00, 1'b0);
            slave_rdata(4'hE, 32'hABCD_EF01, 2'b10, 1'b1);
        end
        begin : tc13_collect
            collect_master_rbeats(1);
        end
    join
    if (m_rresp_captured[0] !== 2'b10) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("RRESP OR merge failed");

    // ====================================================================
    // TC14: Multiple consecutive write transactions
    // ====================================================================
    tc_num  = 14;
    tc_name = "Multiple consecutive write transactions";
    errors  = 0;

    tc14_patterns[0] = 64'h0011_2233_4455_6677;
    tc14_patterns[1] = 64'h8899_AABB_CCDD_EEFF;
    tc14_patterns[2] = 64'hFEDC_BA98_7654_3210;

    for (tc14_txn = 0; tc14_txn < 3; tc14_txn = tc14_txn + 1) begin
        fork
            begin : tc14_m
                master_aw(tc14_txn, 32'hF000_0000 + tc14_txn*4, 8'd0);
                master_wdata(tc14_patterns[tc14_txn], 8'hFF, 1'b1);
            end
            begin : tc14_s
                collect_slave_wbeats(2);
                slave_bresp(tc14_txn, 2'b00);
            end
        join
        if (s_wdata_captured[0] !== tc14_patterns[tc14_txn][31:0])  errors = errors + 1;
        if (s_wdata_captured[1] !== tc14_patterns[tc14_txn][63:32]) errors = errors + 1;
        clk_n(1);
    end

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("Pipeline write transactions failed");

    // ====================================================================
    // TC15: RLAST correctness across burst
    // ====================================================================
    tc_num  = 15;
    tc_name = "RLAST correctness across burst";
    errors  = 0;
    M_AXI_RREADY = 1;

    fork
        begin : tc15_master
            M_AXI_ARID    = 4'hF;
            M_AXI_ARADDR  = 32'h0F00_0000;
            M_AXI_ARLEN   = 8'd1;
            M_AXI_ARSIZE  = 3'b011;
            M_AXI_ARBURST = 2'b01;
            M_AXI_ARVALID = 1;
            begin : tc15_ar_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (M_AXI_ARREADY) done = 1; end
            end
            #1; M_AXI_ARVALID = 0;
        end
        begin : tc15_slave
            begin : tc15_arv_wait
                reg done; done = 0;
                while (!done) begin @(posedge clk); if (S_AXI_ARVALID) done = 1; end
            end
            #1;
            slave_rdata(4'hF, 32'hAAAA_AAAA, 2'b00, 1'b0);
            slave_rdata(4'hF, 32'hBBBB_BBBB, 2'b00, 1'b0);
            slave_rdata(4'hF, 32'hCCCC_CCCC, 2'b00, 1'b0);
            slave_rdata(4'hF, 32'hDDDD_DDDD, 2'b00, 1'b1);
        end
        begin : tc15_collect
            collect_master_rbeats(2);
        end
    join
    if (m_rlast_captured[0] !== 1'b0) errors = errors + 1;
    if (m_rlast_captured[1] !== 1'b1) errors = errors + 1;
    if (m_rdata_captured[0] !== {32'hBBBB_BBBB, 32'hAAAA_AAAA}) errors = errors + 1;
    if (m_rdata_captured[1] !== {32'hDDDD_DDDD, 32'hCCCC_CCCC}) errors = errors + 1;

    clk_n(2);
    if (errors == 0) pass_tc; else fail_tc("RLAST timing incorrect");

    // ====================================================================
    // Summary
    // ====================================================================
    clk_n(5);
    $display("");
    $display("============================================================");
    $display("  TESTBENCH SUMMARY: axi_width_converter_64to32");
    $display("============================================================");
    $display("  Total TCs : %0d", tc_num);
    $display("  PASS      : %0d", pass_count);
    $display("  FAIL      : %0d", fail_count);
    $display("============================================================");
    if (fail_count == 0)
        $display("  ALL TESTS PASSED");
    else
        $display("  SOME TESTS FAILED -- check above");
    $display("============================================================");

    $finish;
end

// ============================================================================
// Watchdog
// ============================================================================
parameter WD_LIMIT = 500;
initial begin
    #(WD_LIMIT * CLK_PERIOD * 200);
    $display("[WATCHDOG] Simulation timed out!");
    $finish;
end

// ============================================================================
// Signal monitor
// ============================================================================
always @(posedge clk) begin
    if (S_AXI_AWVALID && S_AXI_AWREADY)
        $display("  [AW->S] addr=%h len=%0d size=%0d",
                  S_AXI_AWADDR, S_AXI_AWLEN, S_AXI_AWSIZE);
    if (S_AXI_WVALID && S_AXI_WREADY)
        $display("  [W->S]  data=%h strb=%b last=%0b",
                  S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WLAST);
    if (M_AXI_BVALID && M_AXI_BREADY)
        $display("  [B->M]  id=%h resp=%0b", M_AXI_BID, M_AXI_BRESP);
    if (S_AXI_ARVALID && S_AXI_ARREADY)
        $display("  [AR->S] addr=%h len=%0d size=%0d",
                  S_AXI_ARADDR, S_AXI_ARLEN, S_AXI_ARSIZE);
    if (M_AXI_RVALID && M_AXI_RREADY)
        $display("  [R->M]  data=%h resp=%0b last=%0b",
                  M_AXI_RDATA, M_AXI_RRESP, M_AXI_RLAST);
end

endmodule
// ============================================================================
// END: tb_axi_width_converter_64to32.v
// ============================================================================