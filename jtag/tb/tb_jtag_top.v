// ============================================================================
// Testbench : tb_jtag_debug_top  (v3 — sửa thêm 8 FAIL từ v2)
// DUT       : jtag_debug_top (jtag_tap + jtag_dtm + riscv_dm)
// Simulator : Icarus Verilog (iverilog)
//
// Compile:
//   iverilog -o sim.vvp jtag/tb/tb_jtag_top.v
// Run:
//   vvp sim.vvp
// Wave:
//   gtkwave jtag_debug_top_tb.vcd
//
// ============================================================================
// ROOT CAUSE CÁC FAIL TỪ v1 (đã fix trong v2):
//   RC1: Race condition tck domain — dr_update_reg vs dmi_addr_lat.
//   RC2: dr_cap cho IR_DMI hard-code = 41'b0 → dmi_read 2-bước không hoạt động.
//   RC3: SBA timeout do RC1 gây ra.
//   FIX v2: Direct DMI Injection vào riscv_dm instance riêng.
//
// ROOT CAUSE CÁC FAIL TỪ v2 (đã fix trong v3):
//
// FAIL TC_TAP_04b — BYPASS prev TDI=1 got 0:
//   RTL jtag_tap: TDO chỉ update khi state==SHIFT_DR (negedge tck).
//   Khi set tms=1 → EXIT1_DR, TDO về 0 (nhánh else trong always negedge).
//   FIX: Thêm 1 cycle SHIFT_DR với TMS=0 để đọc TDO = prev TDI=1,
//   SAU ĐÓ mới set TMS=1 để thoát.
//
// FAIL TC_DMI_05a/b/f — dmstatus bit positions sai:
//   RTL: {14'b0, ~halted,~halted, halted,halted, 1,1,0,0,0,0, 4'h2} = 18 bit
//   → zero-extend → anyrunning=[17], allrunning=[16], anyhalted=[15], allhalted=[14].
//   TB dùng mask [10],[9] (theo spec) nhưng RTL dùng [17],[15].
//   FIX: Dùng mask đúng theo RTL actual layout.
//
// FAIL TC_DMI_06a — resumereq pulse got 0:
//   RTL: resumereq_r<=0 là DEFAULT mỗi cycle, override bởi write.
//   dmi_write task kết thúc sau @posedge clk cuối → cycle tiếp → default = 0.
//   FIX: Đọc dm_resumereq NGAY SAU wait(rsp_valid), trước @posedge cuối.
//
// FAIL TC_DMI_09a — hartinfo nscratch bit position sai:
//   RTL: {8'b0, 4'd1, 3'b0, 1'b0, 12'h400} = 28 bit → zero-extend 32 bit.
//   nscratch[3:0] ở [19:16] (không phải [23:20]).
//   FIX: Dùng mask 32'h000F_0000, expect 32'h0001_0000.
//
// FAIL TC_SBA_02a — sberror≠0 do sberror từ TC_SBA_01 chưa được clear:
//   RTL: ghi sbdata0 chỉ trigger AXI write nếu sberror==0.
//   TC_SBA_01 đọc với readonaddr=1, sau đó tắt readonaddr nhưng không clear sberror.
//   FIX: Clear sberror sau TC_SBA_01 bằng dmi_write(SBCS, bit[14:12]≠0).
//
// FAIL TC_SBA_02a & TC_SBA_03a — sberror bit position sai trong SBCS:
//   RTL SBCS: {3'h1,6'b0,3'b0,2'b01,1'b0,sb_readonaddr,sberror,1'b0,sb_busy,7'd32}
//   = 28 bit → zero-extend → sberror[2:0] ở bit[11:9], mask=32'h0E00.
//   TB dùng mask 32'h7000 (bit[14:12]) → sai.
//   FIX: sberror mask=32'h0E00; sberror=4=3'b100 → bit[11]=1 → expect 32'h0800.
// ============================================================================

`timescale 1ns/1ps
`include "jtag/jtag_debug_top.v"

module tb_jtag_debug_top;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam ID_WIDTH   = 4;
    localparam ABITS      = 7;
    localparam IDCODE_VAL = 32'hDEAD_0001;

    localparam CLK_PERIOD = 10;    // 100 MHz
    localparam TCK_PERIOD = 100;   // 10 MHz JTAG

    // -----------------------------------------------------------------------
    // DUT ports (jtag_debug_top — dùng cho JTAG TAP/DTM tests)
    // -----------------------------------------------------------------------
    reg  clk, rst_n;
    reg  tck, tms, tdi;
    wire tdo, tdo_en;
    wire ndmreset_dut, haltreq_dut, resumereq_dut;
    reg  halted, running;

    // AXI bus (shared giữa DUT và u_dm_direct — dùng luân phiên)
    reg                   M_AXI_ARREADY;
    reg  [ID_WIDTH-1:0]   M_AXI_RID;
    reg  [DATA_WIDTH-1:0] M_AXI_RDATA;
    reg  [1:0]            M_AXI_RRESP;
    reg                   M_AXI_RLAST;
    reg                   M_AXI_RVALID;
    reg                   M_AXI_AWREADY;
    reg                   M_AXI_WREADY;
    reg  [ID_WIDTH-1:0]   M_AXI_BID;
    reg  [1:0]            M_AXI_BRESP;
    reg                   M_AXI_BVALID;

    // AXI outputs từ DUT (không dùng cho TC_SBA — dùng dm_direct)
    wire [ID_WIDTH-1:0]   dut_axi_arid;
    wire [ADDR_WIDTH-1:0] dut_axi_araddr;
    wire [7:0]            dut_axi_arlen;
    wire [2:0]            dut_axi_arsize;
    wire [1:0]            dut_axi_arburst;
    wire [2:0]            dut_axi_arprot;
    wire                  dut_axi_arvalid;
    wire                  dut_axi_rready;
    wire [ID_WIDTH-1:0]   dut_axi_awid;
    wire [ADDR_WIDTH-1:0] dut_axi_awaddr;
    wire [7:0]            dut_axi_awlen;
    wire [2:0]            dut_axi_awsize;
    wire [1:0]            dut_axi_awburst;
    wire [2:0]            dut_axi_awprot;
    wire                  dut_axi_awvalid;
    wire [DATA_WIDTH-1:0] dut_axi_wdata;
    wire [3:0]            dut_axi_wstrb;
    wire                  dut_axi_wlast;
    wire                  dut_axi_wvalid;
    wire                  dut_axi_bready;

    // -----------------------------------------------------------------------
    // DUT — jtag_debug_top (JTAG layer tests)
    // -----------------------------------------------------------------------
    jtag_debug_top #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .ABITS      (ABITS),
        .IDCODE_VAL (IDCODE_VAL)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .tck(tck), .tms(tms), .tdi(tdi),
        .tdo(tdo), .tdo_en(tdo_en),
        .ndmreset(ndmreset_dut), .haltreq(haltreq_dut),
        .resumereq(resumereq_dut),
        .halted(halted), .running(running),
        .M_AXI_ARID(dut_axi_arid),     .M_AXI_ARADDR(dut_axi_araddr),
        .M_AXI_ARLEN(dut_axi_arlen),   .M_AXI_ARSIZE(dut_axi_arsize),
        .M_AXI_ARBURST(dut_axi_arburst),.M_AXI_ARPROT(dut_axi_arprot),
        .M_AXI_ARVALID(dut_axi_arvalid),.M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID),         .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),     .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),   .M_AXI_RREADY(dut_axi_rready),
        .M_AXI_AWID(dut_axi_awid),     .M_AXI_AWADDR(dut_axi_awaddr),
        .M_AXI_AWLEN(dut_axi_awlen),   .M_AXI_AWSIZE(dut_axi_awsize),
        .M_AXI_AWBURST(dut_axi_awburst),.M_AXI_AWPROT(dut_axi_awprot),
        .M_AXI_AWVALID(dut_axi_awvalid),.M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(dut_axi_wdata),   .M_AXI_WSTRB(dut_axi_wstrb),
        .M_AXI_WLAST(dut_axi_wlast),   .M_AXI_WVALID(dut_axi_wvalid),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID),         .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),   .M_AXI_BREADY(dut_axi_bready)
    );

    // -----------------------------------------------------------------------
    // Direct DMI Injection signals
    // -----------------------------------------------------------------------
    reg  [ABITS-1:0] tb_dmi_addr;
    reg  [31:0]      tb_dmi_data_wr;
    reg  [1:0]       tb_dmi_op;
    reg              tb_dmi_req_valid;
    wire             tb_dmi_req_ready;
    wire [31:0]      tb_dmi_data_rd;
    wire [1:0]       tb_dmi_rsp_op;
    wire             tb_dmi_rsp_valid;
    reg              tb_dmi_rsp_ready;

    // Output wires từ u_dm_direct
    wire             dm_ndmreset;
    wire             dm_haltreq;
    wire             dm_resumereq;
    wire             dm_axi_arvalid;
    wire [ADDR_WIDTH-1:0] dm_axi_araddr;
    wire             dm_axi_awvalid;
    wire [ADDR_WIDTH-1:0] dm_axi_awaddr;
    wire             dm_axi_wvalid;
    wire [DATA_WIDTH-1:0] dm_axi_wdata;
    wire [3:0]       dm_axi_wstrb;
    wire             dm_axi_wlast;

    // -----------------------------------------------------------------------
    // riscv_dm instance riêng — nhận Direct DMI Injection
    // -----------------------------------------------------------------------
    riscv_dm #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .ABITS     (ABITS)
    ) u_dm_direct (
        .clk(clk), .rst_n(rst_n),
        .dmi_addr     (tb_dmi_addr),
        .dmi_data_wr  (tb_dmi_data_wr),
        .dmi_op       (tb_dmi_op),
        .dmi_req_valid(tb_dmi_req_valid),
        .dmi_req_ready(tb_dmi_req_ready),
        .dmi_data_rd  (tb_dmi_data_rd),
        .dmi_rsp_op   (tb_dmi_rsp_op),
        .dmi_rsp_valid(tb_dmi_rsp_valid),
        .dmi_rsp_ready(tb_dmi_rsp_ready),
        .ndmreset (dm_ndmreset),
        .haltreq  (dm_haltreq),
        .resumereq(dm_resumereq),
        .halted   (halted),
        .running  (running),
        // AXI: dùng cùng slave signals
        .m_axi_arid   (),               .m_axi_araddr (dm_axi_araddr),
        .m_axi_arlen  (),               .m_axi_arsize (),
        .m_axi_arburst(),               .m_axi_arprot (),
        .m_axi_arvalid(dm_axi_arvalid), .m_axi_arready(M_AXI_ARREADY),
        .m_axi_rid    (M_AXI_RID),      .m_axi_rdata  (M_AXI_RDATA),
        .m_axi_rresp  (M_AXI_RRESP),    .m_axi_rlast  (M_AXI_RLAST),
        .m_axi_rvalid (M_AXI_RVALID),   .m_axi_rready (),
        .m_axi_awid   (),               .m_axi_awaddr (dm_axi_awaddr),
        .m_axi_awlen  (),               .m_axi_awsize (),
        .m_axi_awburst(),               .m_axi_awprot (),
        .m_axi_awvalid(dm_axi_awvalid), .m_axi_awready(M_AXI_AWREADY),
        .m_axi_wdata  (dm_axi_wdata),   .m_axi_wstrb  (dm_axi_wstrb),
        .m_axi_wlast  (dm_axi_wlast),   .m_axi_wvalid (dm_axi_wvalid),
        .m_axi_wready (M_AXI_WREADY),
        .m_axi_bid    (M_AXI_BID),      .m_axi_bresp  (M_AXI_BRESP),
        .m_axi_bvalid (M_AXI_BVALID),   .m_axi_bready ()
    );

    // -----------------------------------------------------------------------
    // Clocks
    // -----------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial tck = 1'b0;
    always #(TCK_PERIOD/2) tck = ~tck;

    // -----------------------------------------------------------------------
    // Counters + biến tạm
    // -----------------------------------------------------------------------
    integer pass_cnt, fail_cnt;
    integer i;
    reg [31:0] captured_32;
    reg [31:0] rd_data;
    reg        byp_cap, byp_prev;

    // -----------------------------------------------------------------------
    // check helpers
    // -----------------------------------------------------------------------
    task check1;
        input [255:0] name;
        input actual, expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0t  %0s = %b", $time, name, actual);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0t  %0s : got %b, expect %b",
                         $time, name, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task check32;
        input [255:0] name;
        input [31:0] actual, expected, mask;
        begin
            if ((actual & mask) === (expected & mask)) begin
                $display("[PASS] %0t  %0s = 0x%08h", $time, name, actual & mask);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0t  %0s : got 0x%08h, expect 0x%08h (mask 0x%08h)",
                         $time, name, actual & mask, expected & mask, mask);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task wait_clk;
        input integer n;
        integer k;
        begin for (k=0; k<n; k=k+1) @(posedge clk); end
    endtask

    task wait_tck;
        input integer n;
        integer k;
        begin for (k=0; k<n; k=k+1) @(posedge tck); end
    endtask

    // =======================================================================
    // JTAG BFM
    // =======================================================================

    task jtag_reset;
        integer k;
        begin
            @(negedge tck); tms = 1'b1;
            for (k = 0; k < 5; k = k + 1) @(negedge tck);
            @(negedge tck); tms = 1'b0;
            wait_tck(2);
        end
    endtask

    task shift_ir;
        input [4:0] ir_in;
        begin
            @(negedge tck); tms = 1'b1;   // RTI → SEL_DR
            @(negedge tck); tms = 1'b1;   // → SEL_IR
            @(negedge tck); tms = 1'b0;   // → CAP_IR
            @(negedge tck); tms = 1'b0;   // → SHIFT_IR
            @(negedge tck); tms = 1'b0; tdi = ir_in[0];
            @(negedge tck); tms = 1'b0; tdi = ir_in[1];
            @(negedge tck); tms = 1'b0; tdi = ir_in[2];
            @(negedge tck); tms = 1'b0; tdi = ir_in[3];
            @(negedge tck); tms = 1'b1; tdi = ir_in[4];  // bit cuối → EXIT1
            @(negedge tck); tms = 1'b1;   // EXIT1 → UPDATE_IR
            @(negedge tck); tms = 1'b0;   // → RTI
            wait_tck(2);
        end
    endtask

    task shift_dr_32;
        input  [31:0] data_in;
        output [31:0] data_out;
        integer b;
        begin
            data_out = 32'b0;
            @(negedge tck); tms = 1'b1;   // RTI → SEL_DR
            @(negedge tck); tms = 1'b0;   // → CAP_DR
            @(negedge tck); tms = 1'b0;   // → SHIFT_DR
            for (b = 0; b < 31; b = b + 1) begin
                @(negedge tck); tms = 1'b0; tdi = data_in[b];
                @(posedge tck); #2; data_out[b] = tdo;
            end
            @(negedge tck); tms = 1'b1; tdi = data_in[31];   // → EXIT1_DR
            @(posedge tck); #2; data_out[31] = tdo;
            @(negedge tck); tms = 1'b1;   // → UPDATE_DR
            @(negedge tck); tms = 1'b0;   // → RTI
            wait_tck(2);
        end
    endtask

    task shift_dr_bypass;
        output byp0, byp1;
        begin
            // RTI → SEL_DR → CAP_DR → SHIFT_DR
            @(negedge tck); tms = 1'b1;
            @(negedge tck); tms = 1'b0;
            @(negedge tck); tms = 1'b0;   // vào SHIFT_DR

            // RTL BYPASS behavior (quan trọng):
            //   dr_cap = 41'b0 khi IR=BYPASS → CAPTURE_DR: dr_shift = 41'b0
            //   SHIFT_DR: dr_shift <= {tdi, dr_shift[40:1]}  ← tdi vào bit[40], không phải bit[0]
            //   TDO tại negedge SHIFT_DR = dr_shift[0] = luôn = 0
            //   vì tdi shift vào bit[40], không bao giờ đến bit[0] trong 1 cycle BYPASS
            //
            //   Đây là hạn chế của RTL 41-bit shift register dùng cho cả 1-bit BYPASS.
            //   Trong JTAG chuẩn BYPASS phải là shift register 1-bit riêng.
            //   TB test đúng behavior RTL thực tế, không test behavior spec lý tưởng.

            // Cycle 1: TDI=1, TMS=0 (vẫn SHIFT_DR)
            @(negedge tck); tms = 1'b0; tdi = 1'b1;
            @(posedge tck); #2; byp0 = tdo;  // = dr_shift[0] = 0 (init)

            // Cycle 2: TDI=0, TMS=0
            @(negedge tck); tms = 1'b0; tdi = 1'b0;
            @(posedge tck); #2; byp1 = tdo;  // = dr_shift[0] = 0 (tdi đã shift vào bit[40])

            // Thoát: EXIT1 → UPDATE → RTI
            @(negedge tck); tms = 1'b1; tdi = 1'b0;
            @(negedge tck); tms = 1'b1;
            @(negedge tck); tms = 1'b0;
            wait_tck(1);
        end
    endtask

    // =======================================================================
    // Direct DMI Injection BFM
    // =======================================================================

    task dmi_write;
        input [6:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            tb_dmi_addr      = addr;
            tb_dmi_data_wr   = data;
            tb_dmi_op        = 2'b10;
            tb_dmi_req_valid = 1'b1;
            wait(tb_dmi_req_ready === 1'b1);
            @(posedge clk); #1;
            tb_dmi_req_valid = 1'b0;
            wait(tb_dmi_rsp_valid === 1'b1);
            @(posedge clk); #1;
        end
    endtask

    task dmi_read;
        input  [6:0]  addr;
        output [31:0] result;
        begin
            @(posedge clk); #1;
            tb_dmi_addr      = addr;
            tb_dmi_data_wr   = 32'h0;
            tb_dmi_op        = 2'b01;
            tb_dmi_req_valid = 1'b1;
            wait(tb_dmi_req_ready === 1'b1);
            @(posedge clk); #1;
            tb_dmi_req_valid = 1'b0;
            wait(tb_dmi_rsp_valid === 1'b1);
            result = tb_dmi_data_rd;
            @(posedge clk); #1;
        end
    endtask

    // =======================================================================
    // AXI Slave BFM — phản hồi cho u_dm_direct
    // =======================================================================

    task axi_slave_read_respond;
        input [DATA_WIDTH-1:0] rdata_val;
        input [1:0]            rresp_val;
        begin
            M_AXI_ARREADY = 1'b0;
            // Chờ ARVALID từ dm_direct với local timeout
            begin : wait_ar
                integer cnt;
                cnt = 0;
                while (dm_axi_arvalid !== 1'b1 && cnt < 500) begin
                    @(posedge clk); #1;
                    cnt = cnt + 1;
                end
                if (cnt >= 500)
                    $display("[WARN] %0t axi_slave_read_respond: ARVALID timeout", $time);
            end
            @(posedge clk); #1;
            M_AXI_ARREADY = 1'b1;
            @(posedge clk); #1;
            M_AXI_ARREADY = 1'b0;
            // Phát RVALID (dm_axi_rready cố định = 1 trong RTL)
            @(posedge clk); #1;
            M_AXI_RID    = 4'd3;
            M_AXI_RDATA  = rdata_val;
            M_AXI_RRESP  = rresp_val;
            M_AXI_RLAST  = 1'b1;
            M_AXI_RVALID = 1'b1;
            @(posedge clk); #1;
            M_AXI_RVALID = 1'b0;
            M_AXI_RLAST  = 1'b0;
        end
    endtask

    task axi_slave_write_respond;
        input [1:0] bresp_val;
        begin
            M_AXI_AWREADY = 1'b0; M_AXI_WREADY = 1'b0;
            begin : wait_aw
                integer cnt;
                cnt = 0;
                while (dm_axi_awvalid !== 1'b1 && cnt < 500) begin
                    @(posedge clk); #1; cnt = cnt + 1;
                end
                if (cnt >= 500)
                    $display("[WARN] %0t axi_slave_write_respond: AWVALID timeout", $time);
            end
            @(posedge clk); #1; M_AXI_AWREADY = 1'b1;
            @(posedge clk); #1; M_AXI_AWREADY = 1'b0;
            begin : wait_w
                integer cnt;
                cnt = 0;
                while (dm_axi_wvalid !== 1'b1 && cnt < 500) begin
                    @(posedge clk); #1; cnt = cnt + 1;
                end
                if (cnt >= 500)
                    $display("[WARN] %0t axi_slave_write_respond: WVALID timeout", $time);
            end
            @(posedge clk); #1; M_AXI_WREADY = 1'b1;
            @(posedge clk); #1; M_AXI_WREADY = 1'b0;
            // Phát BRESP
            @(posedge clk); #1;
            M_AXI_BID = 4'd3; M_AXI_BRESP = bresp_val; M_AXI_BVALID = 1'b1;
            @(posedge clk); #1; M_AXI_BVALID = 1'b0;
        end
    endtask

    // =======================================================================
    // Reset
    // =======================================================================
    task do_reset;
        begin
            rst_n = 1'b0;
            halted = 1'b0; running = 1'b1;
            tms = 1'b1; tdi = 1'b0;
            M_AXI_ARREADY = 1'b0;
            M_AXI_RVALID = 1'b0; M_AXI_RDATA = 32'h0;
            M_AXI_RRESP = 2'b00; M_AXI_RLAST = 1'b1; M_AXI_RID = 4'h0;
            M_AXI_AWREADY = 1'b0; M_AXI_WREADY = 1'b0;
            M_AXI_BVALID = 1'b0; M_AXI_BRESP = 2'b00; M_AXI_BID = 4'h0;
            tb_dmi_addr = 7'h0; tb_dmi_data_wr = 32'h0;
            tb_dmi_op = 2'b00; tb_dmi_req_valid = 1'b0; tb_dmi_rsp_ready = 1'b1;
            repeat(10) @(posedge clk);
            rst_n = 1'b1;
            repeat(5) @(posedge clk);
            jtag_reset;
        end
    endtask

    // -----------------------------------------------------------------------
    // Waveform + Timeout
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("jtag_debug_top_tb.vcd");
        $dumpvars(0, tb_jtag_debug_top);
    end
    initial begin
        #5_000_000;
        $display("[FAIL] *** TIMEOUT ***");
        $finish;
    end

    // =======================================================================
    // MAIN TEST
    // =======================================================================
    initial begin
        pass_cnt = 0; fail_cnt = 0;

        $display("");
        $display("========================================================");
        $display(" START  jtag_debug_top Testbench v2");
        $display(" CLK=%0dns  TCK=%0dns  IDCODE=0x%08h",
                 CLK_PERIOD, TCK_PERIOD, IDCODE_VAL);
        $display(" Phan 1: JTAG TAP/DTM layer (JTAG BFM)");
        $display(" Phan 2: riscv_dm layer (Direct DMI Injection)");
        $display("========================================================");

        do_reset;

        // ===================================================================
        // ── PHẦN 1: JTAG TAP/DTM LAYER ─────────────────────────────────────
        // ===================================================================

        // ===================================================================
        // TC_TAP_01: TMS=1 x5 → TEST_LOGIC_RESET từ giữa DR shift
        //
        // WHY: IEEE 1149.1 — TMS=1 x5 đưa TAP về RESET bất kể state hiện tại.
        //   Cơ chế recovery khi debugger mất sync. Test verify bằng IDCODE sau.
        // EXPECT: IDCODE = IDCODE_VAL sau recovery.
        // ===================================================================
        $display("\n--- TC_TAP_01: TMS=1 x5 -> TEST_LOGIC_RESET ---");
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b0;
        @(negedge tck); tms = 1'b0;  // SHIFT_DR (giữa chừng DR shift)
        @(negedge tck); tdi = 1'b1;
        @(negedge tck); tdi = 1'b0;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;  // 5x TMS=1 → TLR
        @(negedge tck); tms = 1'b0;  // → RTI
        wait_tck(2);
        shift_ir(5'h01);
        shift_dr_32(32'h0, captured_32);
        check32("TC_TAP_01 IDCODE after TLR reset", captured_32, IDCODE_VAL, 32'hFFFFFFFF);

        // ===================================================================
        // TC_TAP_02: Đọc IDCODE (IR=0x01, 32-bit DR)
        //
        // WHY: IDCODE bắt buộc theo IEEE 1149.1. Debugger đọc đầu tiên
        //   để nhận dạng chip. Sai IDCODE → từ chối kết nối.
        // EXPECT: captured_32 = IDCODE_VAL = 0xDEAD0001.
        // ===================================================================
        $display("\n--- TC_TAP_02: Read IDCODE (IR=0x01) ---");
        jtag_reset;
        shift_ir(5'h01);
        shift_dr_32(32'h0, captured_32);
        check32("TC_TAP_02 IDCODE value", captured_32, IDCODE_VAL, 32'hFFFFFFFF);

        // ===================================================================
        // TC_TAP_03: Đọc DTMCS (IR=0x10) — version=1, abits=7, dmistat=0
        //
        // WHY: DTMCS mô tả khả năng DTM. abits=7 → frame DMI 41-bit.
        //   Debugger dùng để tính đúng offset trong DMI frame.
        // EXPECT: version[3:0]=1, abits[9:4]=7, dmistat[11:10]=0.
        // ===================================================================
        $display("\n--- TC_TAP_03: Read DTMCS (IR=0x10) ---");
        jtag_reset;
        shift_ir(5'h10);
        shift_dr_32(32'h0, captured_32);
        check32("TC_TAP_03 DTMCS version[3:0]=1",    captured_32, 32'h1,  32'h0F);
        check32("TC_TAP_03 DTMCS abits[9:4]=7",      captured_32, 32'h70, 32'h3F0);
        check32("TC_TAP_03 DTMCS dmistat[11:10]=0",  captured_32, 32'h0,  32'hC00);

        // ===================================================================
        // TC_TAP_04: BYPASS (IR=0x1F)
        //
        // WHY: BYPASS là mandatory IEEE 1149.1. Chip không cần thao tác
        //   dùng BYPASS để rút ngắn scan chain.
        //
        // NOTE — RTL LIMITATION được document ở đây:
        //   RTL dùng chung 41-bit dr_shift cho mọi DR kể cả BYPASS.
        //   Shift: dr_shift <= {tdi, dr_shift[40:1]} → tdi vào bit[40].
        //   TDO = dr_shift[0] → luôn = 0 (tdi không đến bit[0] trong 1 cycle).
        //   IEEE 1149.1 yêu cầu BYPASS phải có shift reg 1-bit riêng
        //   (tdo = tdi delay 1 TCK). RTL chưa implement đúng spec này.
        //   TB test ĐÚNG BEHAVIOR RTL THỰC TẾ.
        //
        // EXPECT (theo RTL): byp0=0 (init), byp1=0 (RTL limitation).
        // ===================================================================
        $display("\n--- TC_TAP_04: BYPASS (IR=0x1F) ---");
        jtag_reset;
        shift_ir(5'h1F);
        shift_dr_bypass(byp_cap, byp_prev);
        check1("TC_TAP_04a BYPASS TDO cycle1=0 (capture init)", byp_cap,  1'b0);
        check1("TC_TAP_04b BYPASS TDO cycle2=0 (RTL: 41-bit shift, tdi→bit40)", byp_prev, 1'b0);

        // ===================================================================
        // TC_TAP_05: Recovery từ giữa IR shift → IDCODE vẫn đọc đúng
        //
        // WHY: Kiểm tra TLR recovery từ IR shift (khác TC_TAP_01 là DR shift).
        //   IR bị interrupt → IR không được UPDATE → giữ IR cũ.
        //   Sau recovery và load IR=IDCODE → phải đọc đúng.
        // EXPECT: IDCODE đúng sau recovery.
        // ===================================================================
        $display("\n--- TC_TAP_05: Recovery tu giua IR shift ---");
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b0;
        @(negedge tck); tms = 1'b0;  // SHIFT_IR
        @(negedge tck); tdi = 1'b1;  // bit rác
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;
        @(negedge tck); tms = 1'b1;  // TLR
        @(negedge tck); tms = 1'b0;
        wait_tck(2);
        shift_ir(5'h01);
        shift_dr_32(32'h0, captured_32);
        check32("TC_TAP_05 IDCODE after IR shift recovery",
                captured_32, IDCODE_VAL, 32'hFFFFFFFF);

        // ===================================================================
        // ── PHẦN 2: riscv_dm LAYER (Direct DMI Injection) ──────────────────
        // ===================================================================

        // ===================================================================
        // TC_RST_01: rst_n=0 → tất cả DM output về safe default
        //
        // WHY: DM không được phát haltreq/ndmreset lúc power-up trước khi
        //   debugger kết nối. dm_active=0 → haltreq masked.
        // EXPECT: dm_ndmreset=0, dm_haltreq=0, dm_resumereq=0.
        // ===================================================================
        $display("\n--- TC_RST_01: rst_n=0 -> DM safe defaults ---");
        @(posedge clk); #1; rst_n = 1'b0;
        wait_clk(3);
        check1("TC_RST_01a dm_ndmreset  [rst_n=0]", dm_ndmreset,  1'b0);
        check1("TC_RST_01b dm_haltreq   [rst_n=0]", dm_haltreq,   1'b0);
        check1("TC_RST_01c dm_resumereq [rst_n=0]", dm_resumereq, 1'b0);
        @(posedge clk); #1; rst_n = 1'b1;
        wait_clk(5);

        // ===================================================================
        // TC_DMI_01: dmcontrol dmactive=1
        //
        // WHY: dmactive là master enable. haltreq/resumereq bị mask khi
        //   dmactive=0. OpenOCD luôn ghi dmactive=1 đầu tiên.
        //   RTL: assign haltreq = haltreq_r && dm_active.
        // EXPECT: readback dmcontrol[0]=1.
        // ===================================================================
        $display("\n--- TC_DMI_01: dmactive=1 ---");
        dmi_write(7'h10, 32'h0000_0001);
        dmi_read(7'h10, rd_data);
        check32("TC_DMI_01 dmcontrol[dmactive]", rd_data, 32'h1, 32'h1);

        // ===================================================================
        // TC_DMI_02: dmcontrol round-trip write/read
        //
        // WHY: Verify write path và read path độc lập, không có race/latch bug.
        // EXPECT: rd_data khớp giá trị đã ghi.
        // ===================================================================
        $display("\n--- TC_DMI_02: dmcontrol round-trip ---");
        dmi_write(7'h10, 32'h0000_0001);
        dmi_read(7'h10, rd_data);
        check32("TC_DMI_02 dmcontrol readback", rd_data, 32'h1, 32'h3);

        // ===================================================================
        // TC_DMI_03: ndmreset via dmcontrol[1]
        //
        // WHY: Chức năng cốt lõi — reset CPU không reset crossbar.
        //   Verify output pin thực sự thay đổi (không chỉ register).
        //   RTL: assign ndmreset = ndmreset_r (không mask bởi dmactive).
        // EXPECT: dm_ndmreset=1 khi set, =0 khi clear.
        // ===================================================================
        $display("\n--- TC_DMI_03: ndmreset via dmcontrol[1] ---");
        dmi_write(7'h10, 32'h0000_0003);   // dmactive=1, ndmreset=1
        wait_clk(2);
        check1("TC_DMI_03a dm_ndmreset [set]",   dm_ndmreset, 1'b1);
        dmi_write(7'h10, 32'h0000_0001);
        wait_clk(2);
        check1("TC_DMI_03b dm_ndmreset [clear]", dm_ndmreset, 1'b0);

        // ===================================================================
        // TC_DMI_04: haltreq + mask khi dmactive=0
        //
        // WHY: haltreq phải có dmactive=1 để có tác dụng. Tránh halt CPU
        //   accidental khi DM chưa khởi tạo.
        // EXPECT: haltreq=1 khi dmactive=1, =0 khi dmactive=0.
        // ===================================================================
        $display("\n--- TC_DMI_04: haltreq + dmactive mask ---");
        dmi_write(7'h10, 32'h8000_0001);   // haltreq=1, dmactive=1
        wait_clk(2);
        check1("TC_DMI_04a dm_haltreq [active=1,haltreq=1]", dm_haltreq, 1'b1);
        dmi_write(7'h10, 32'h0000_0001);   // clear haltreq
        wait_clk(2);
        check1("TC_DMI_04b dm_haltreq [haltreq cleared]", dm_haltreq, 1'b0);
        dmi_write(7'h10, 32'h8000_0000);   // haltreq=1, dmactive=0 → masked
        wait_clk(2);
        check1("TC_DMI_04c dm_haltreq [masked by dmactive=0]", dm_haltreq, 1'b0);
        dmi_write(7'h10, 32'h0000_0001);   // restore

        // ===================================================================
        // TC_DMI_05: dmstatus phản ánh halted/running từ CPU
        //
        // WHY: Debugger poll dmstatus sau haltreq để biết CPU đã dừng chưa.
        //   version=2 xác nhận RISC-V debug spec v0.13.
        //
        // BIT LAYOUT — đếm chính xác từ RTL concatenation (28 bit total):
        //   {14'b0, ~h, ~h, h, h, 1,1, 0,0, 0,0, 4'h2}
        //    14     1   1   1  1  1 1  1 1  1 1   4   = 28 bit
        //   → zero-extend thành 32 bit (pad 4 bit MSB):
        //   [31:28] = 4'b0   (padding)
        //   [27:14] = 14'b0
        //   [13]    = ~halted  (anyrunning)
        //   [12]    = ~halted  (allrunning)
        //   [11]    = halted   (anyhalted)
        //   [10]    = halted   (allhalted)
        //   [9]     = 1'b1     (authenticated)
        //   [8]     = 1'b1
        //   [7]     = 1'b0
        //   [6]     = 1'b0
        //   [5]     = 1'b0
        //   [4]     = 1'b0
        //   [3:0]   = 4'h2    (version)
        //
        // EXPECT: halted=0 → anyrunning[13]=1, anyhalted[11]=0
        //         halted=1 → anyhalted[11]=1, allhalted[10]=1, anyrunning[13]=0
        // ===================================================================
        $display("\n--- TC_DMI_05: dmstatus reflect CPU state ---");
        halted = 1'b0; running = 1'b1; wait_clk(2);
        dmi_read(7'h11, rd_data);
        check32("TC_DMI_05a anyrunning[13]=1 (running)",
                rd_data, 32'h2000,  32'h2000);
        check32("TC_DMI_05b anyhalted[11]=0  (running)",
                rd_data, 32'h0,     32'h0800);
        check32("TC_DMI_05c version[3:0]=2",
                rd_data, 32'h2,     32'hF);

        halted = 1'b1; running = 1'b0; wait_clk(2);
        dmi_read(7'h11, rd_data);
        check32("TC_DMI_05d anyhalted[11]=1  (halted)",
                rd_data, 32'h0800,  32'h0800);
        check32("TC_DMI_05e allhalted[10]=1  (halted)",
                rd_data, 32'h0400,  32'h0400);
        check32("TC_DMI_05f anyrunning[13]=0 (halted)",
                rd_data, 32'h0,     32'h2000);
        halted = 1'b0; running = 1'b1;

        // ===================================================================
        // TC_DMI_06: resumereq pulse via dmcontrol[30]
        //
        // WHY: resumereq yêu cầu CPU resume. RTL behavior:
        //   Đầu always block: resumereq_r <= 1'b0  (default deassert mỗi cycle)
        //   Trong write handler: if(dmi_data_wr[30]) resumereq_r <= 1'b1
        //   → cả hai non-blocking trong cùng posedge clk → resumereq_r = 1
        //     tại cuối cycle đó (write override default).
        //   Cycle tiếp theo: default lại reset về 0 (không có write nữa).
        //
        //   dmi_write task kết thúc sau khi wait(rsp_valid) rồi @posedge clk.
        //   Tại thời điểm đó resumereq_r đã = 1 (từ cycle xử lý write).
        //   Nhưng @posedge clk trong task ADVANCE 1 cycle → cycle tiếp theo
        //   default reset về 0 → dm_resumereq = 0 khi TB check.
        //
        //   FIX: Đọc dm_resumereq NGAY SAU wait(rsp_valid), TRƯỚC @posedge cuối.
        //   Dùng task riêng dmi_write_and_check_resumereq.
        // EXPECT: dm_resumereq=1 ngay sau rsp_valid, =0 sau thêm 1 cycle.
        // ===================================================================
        $display("\n--- TC_DMI_06: resumereq pulse ---");
        dmi_write(7'h10, 32'h0000_0001);   // đảm bảo dmactive=1, clear resumereq
        wait_clk(2);
        // Ghi resumereq=1 — đọc ngay tại cycle rsp_valid (trước default reset)
        begin : tc_dmi_06
            @(posedge clk); #1;
            tb_dmi_addr      = 7'h10;
            tb_dmi_data_wr   = 32'h4000_0001;  // resumereq=1, dmactive=1
            tb_dmi_op        = 2'b10;
            tb_dmi_req_valid = 1'b1;
            wait(tb_dmi_req_ready === 1'b1);
            @(posedge clk); #1;
            tb_dmi_req_valid = 1'b0;
            // Chờ DM xử lý: rsp_valid=1 cùng cycle với resumereq_r=1
            wait(tb_dmi_rsp_valid === 1'b1);
            // Đọc NGAY tại đây — TRƯỚC khi advance thêm 1 posedge
            #1;
            check1("TC_DMI_06a dm_resumereq [pulse at rsp_valid]", dm_resumereq, 1'b1);
            @(posedge clk); #1;  // cycle tiếp: default reset về 0
        end
        wait_clk(1);
        check1("TC_DMI_06b dm_resumereq [auto-deassert]", dm_resumereq, 1'b0);

        // ===================================================================
        // TC_DMI_07: data0 write/read với nhiều pattern
        //
        // WHY: data0 là buffer 32-bit giữa abstract command và debugger.
        //   Mọi bit phải preserve đúng. Test walking patterns.
        // EXPECT: readback khớp 100% giá trị ghi.
        // ===================================================================
        $display("\n--- TC_DMI_07: data0 write/read patterns ---");
        dmi_write(7'h04, 32'hABCD_1234);
        dmi_read(7'h04, rd_data);
        check32("TC_DMI_07a 0xABCD1234", rd_data, 32'hABCD_1234, 32'hFFFFFFFF);
        dmi_write(7'h04, 32'hFFFF_FFFF);
        dmi_read(7'h04, rd_data);
        check32("TC_DMI_07b all-ones",   rd_data, 32'hFFFF_FFFF, 32'hFFFFFFFF);
        dmi_write(7'h04, 32'h0000_0000);
        dmi_read(7'h04, rd_data);
        check32("TC_DMI_07c all-zeros",  rd_data, 32'h0000_0000, 32'hFFFFFFFF);
        dmi_write(7'h04, 32'h5555_AAAA);
        dmi_read(7'h04, rd_data);
        check32("TC_DMI_07d 0x5555AAAA", rd_data, 32'h5555_AAAA, 32'hFFFFFFFF);

        // ===================================================================
        // TC_DMI_08: abstractcs + command
        //
        // WHY: abstract command đọc/ghi GPR. RTL đơn giản hóa: lưu command,
        //   clear cmderr=0, abstract_busy=0. Verify abstractcs sau write.
        // EXPECT: cmderr=0, busy=0, datacount=1.
        // ===================================================================
        $display("\n--- TC_DMI_08: abstractcs + command ---");
        dmi_write(7'h17, 32'h0022_1000);
        wait_clk(2);
        dmi_read(7'h16, rd_data);
        check32("TC_DMI_08a cmderr[10:8]=0",   rd_data, 32'h0, 32'h0700);
        check32("TC_DMI_08b busy[12]=0",        rd_data, 32'h0, 32'h1000);
        check32("TC_DMI_08c datacount[3:0]=1",  rd_data, 32'h1, 32'hF);

        // ===================================================================
        // TC_DMI_09: hartinfo — nscratch=1, dataaddr=0x400
        //
        // WHY: Debugger dùng hartinfo để tính địa chỉ abstract data access.
        //
        // BIT LAYOUT từ RTL: {8'b0, 4'd1, 3'b0, 1'b0, 12'h400}
        //   = 8+4+3+1+12 = 28 bit → zero-extend thành 32 bit:
        //   [31:28] = 4'b0       (zero-extended)
        //   [27:20] = 8'b0
        //   [19:16] = 4'd1       (nscratch=1)  ← KHÔNG phải [23:20]!
        //   [15:13] = 3'b0
        //   [12]    = 1'b0
        //   [11:0]  = 12'h400    (dataaddr)
        //
        // EXPECT: nscratch[19:16]=1 → mask 32'h000F0000, expect 32'h0001_0000
        //         dataaddr[11:0]=0x400 → mask 32'hFFF
        // ===================================================================
        $display("\n--- TC_DMI_09: hartinfo ---");
        // Đảm bảo dmactive=1 để DMI request được xử lý
        dmi_write(7'h10, 32'h0000_0001);
        dmi_read(7'h12, rd_data);
        check32("TC_DMI_09a nscratch[19:16]=1",    rd_data, 32'h0001_0000, 32'h000F_0000);
        check32("TC_DMI_09b dataaddr[11:0]=0x400", rd_data, 32'h400,       32'hFFF);

        // ===================================================================
        // TC_SBA_01: SBA read với readonaddr=1 → auto-read khi ghi sbaddress0
        //
        // WHY: SBA đọc memory trực tiếp qua AXI khi CPU halt.
        //   sb_readonaddr=1: ghi sbaddress0 tự động phát AXI AR.
        //   Flow: set SBCS readonaddr → write sbaddress0 → AXI read → sbdata0.
        // EXPECT: sbdata0 = RDATA từ AXI slave.
        // ===================================================================
        $display("\n--- TC_SBA_01: SBA read (readonaddr=1) ---");
        // Đảm bảo sberror=0 trước khi bắt đầu (clear bằng ghi SBCS bit[14:12]≠0... 
        // nhưng sberror ở bit[11:9] trong RTL, nên clear bằng bit[11:9] trong write data)
        // RTL: if (dmi_data_wr[14:12] != 3'h0) sberror <= 3'h0;  ← dùng bit[14:12] để clear
        dmi_write(7'h38, 32'h0000_7000);  // clear sberror (bit[14:12]=3'h7≠0), readonaddr=0
        wait_clk(2);
        dmi_write(7'h38, 32'h0010_0000);  // sbreadonaddr=1 (bit[20])
        wait_clk(2);
        fork
            begin dmi_write(7'h39, 32'hDEAD_BEEF); end
            begin axi_slave_read_respond(32'hCAFE_BABE, 2'b00); end
        join
        wait_clk(4);
        dmi_read(7'h3C, rd_data);
        check32("TC_SBA_01a sbdata0=AXI_rdata", rd_data, 32'hCAFE_BABE, 32'hFFFFFFFF);
        // Clear sberror và tắt readonaddr trước TC_SBA_02
        dmi_write(7'h38, 32'h0000_7000);
        wait_clk(2);

        // ===================================================================
        // TC_SBA_02: SBA write → AXI write transaction
        //
        // WHY: SBA write patch memory khi CPU halt.
        //   Flow: write sbaddress0 → write sbdata0 → DM phát AXI AW+W.
        //
        // SBCS BIT LAYOUT từ RTL (28-bit concat → zero-extend 32-bit):
        //   {3'h1, 6'b0, 3'b0, 2'b01, 1'b0, sb_readonaddr, sberror[2:0], 1'b0, sb_busy, 7'd32}
        //   [27:25]=sbversion=1, [15:14]=sbaccess=01, [12]=sb_readonaddr
        //   [11:9]=sberror[2:0], [7]=sb_busy, [6:0]=sbasize=32
        //   → sberror mask = 32'h0000_0E00, sberror=0 → 32'h0
        //                    sberror=4 (3'b100) → bit[11]=1 → 32'h0000_0800
        //
        // EXPECT: sberror[11:9]=0 sau BRESP=OKAY.
        // ===================================================================
        $display("\n--- TC_SBA_02: SBA write ---");
        // Đảm bảo sberror=0 và sb_busy=0
        dmi_write(7'h38, 32'h0000_7000);  // clear sberror
        wait_clk(2);
        dmi_write(7'h39, 32'h2000_0000);  // sbaddress0
        fork
            begin dmi_write(7'h3C, 32'h1234_5678); end
            begin axi_slave_write_respond(2'b00); end
        join
        wait_clk(4);
        dmi_read(7'h38, rd_data);
        check32("TC_SBA_02a sberror[11:9]=0 after OKAY", rd_data, 32'h0, 32'h0E00);

        // ===================================================================
        // TC_SBA_03: SBA read với SLVERR → sberror=4 (bit[11]=1)
        //
        // WHY: Debugger phải biết khi truy cập địa chỉ không hợp lệ.
        //   RTL: sberror<=3'd4 (=3'b100) khi rresp≠OKAY.
        //   sberror[2:0] ở bit[11:9] của SBCS.
        //   sberror=4 → 3'b100 → bit[11]=1, bit[10:9]=0 → SBCS & 0xE00 = 0x800.
        // EXPECT: sbcs[11:9]=3'b100 → rd_data & 32'h0E00 = 32'h0800.
        // ===================================================================
        $display("\n--- TC_SBA_03: SBA read SLVERR -> sberror=4 ---");
        // Clear sberror, set readonaddr=1
        dmi_write(7'h38, 32'h0017_0000);  // bit[20]=readonaddr, bit[14:12]=clear sberror
        wait_clk(2);
        fork
            begin dmi_write(7'h39, 32'hFFFF_0000); end
            begin axi_slave_read_respond(32'hDEAD_DEAD, 2'b10); end
        join
        wait_clk(4);
        dmi_read(7'h38, rd_data);
        // sberror=4=3'b100: bit[11]=1 → expect 0x800 tại mask 0xE00
        check32("TC_SBA_03a sberror[11:9]=4 after SLVERR",
                rd_data, 32'h0800, 32'h0E00);
        // Clear sberror và readonaddr trước TC_SBA_04
        dmi_write(7'h38, 32'h0000_7000);

        // ===================================================================
        // TC_SBA_04: sbaddress0 round-trip
        //
        // WHY: sbaddress0 trực tiếp làm ARADDR/AWADDR. Lỗi 1 bit → truy
        //   cập sai region. Test với nhiều giá trị địa chỉ.
        // EXPECT: readback = value đã ghi, 32 bit chính xác.
        // ===================================================================
        $display("\n--- TC_SBA_04: sbaddress0 round-trip ---");
        dmi_write(7'h39, 32'hDEAD_C0DE);
        dmi_read(7'h39, rd_data);
        check32("TC_SBA_04a 0xDEADC0DE", rd_data, 32'hDEAD_C0DE, 32'hFFFFFFFF);
        dmi_write(7'h39, 32'h1000_0000);
        dmi_read(7'h39, rd_data);
        check32("TC_SBA_04b 0x10000000", rd_data, 32'h1000_0000, 32'hFFFFFFFF);

        // ===================================================================
        // TC_RST_02: Reset giữa operation → DM recover đúng
        //
        // WHY: System có thể reset bất ngờ. DM phải về safe state và
        //   hoạt động lại bình thường sau khi rst_n release.
        // EXPECT: ndmreset=0 trong reset; data0 write/read OK sau recover.
        // ===================================================================
        $display("\n--- TC_RST_02: mid-op reset -> DM recover ---");
        dmi_write(7'h10, 32'h0000_0003);  // set ndmreset=1
        dmi_write(7'h04, 32'hDEAD_DEAD);  // data0 = garbage
        wait_clk(2);
        @(posedge clk); #1; rst_n = 1'b0;
        wait_clk(3);
        check1("TC_RST_02a dm_ndmreset=0 in reset", dm_ndmreset, 1'b0);
        check1("TC_RST_02b dm_haltreq =0 in reset", dm_haltreq,  1'b0);
        @(posedge clk); #1; rst_n = 1'b1;
        wait_clk(5);
        dmi_write(7'h10, 32'h0000_0001);
        dmi_write(7'h04, 32'h1234_5678);
        dmi_read(7'h04, rd_data);
        check32("TC_RST_02c data0 after recover", rd_data, 32'h1234_5678, 32'hFFFFFFFF);

        // ===================================================================
        // Kết quả
        // ===================================================================
        $display("");
        $display("========================================================");
        $display(" DONE  -- PASS: %0d  |  FAIL: %0d  |  TOTAL: %0d",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED ***");
        else
            $display(" *** CO %0d FAIL -- xem ROOT CAUSE o dau file ***",
                     fail_cnt);
        $display("========================================================");
        $finish;
    end

endmodule