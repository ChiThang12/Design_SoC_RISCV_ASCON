// ============================================================================
// Testbench : tb_ascon_ip_top.v   Version 1.3
//
// Root-cause fix vs v1.2:
//   - axi_write task: Verilog-2001 tasks không cho phép khởi tạo local reg
//     trong vòng lặp có @(posedge clk). Rewrite dùng state-machine đơn giản:
//     drive AW+W cùng lúc, sau đó wait từng kênh bằng vòng lặp riêng.
//   - Thêm timeout từng bước trong axi_write/axi_read để phát hiện deadlock
// ============================================================================

`timescale 1ns/1ps
`include "ascon_accelerator/ascon_top.v"

module tb_ascon_ip_top;

    localparam CLK_PERIOD   = 10;
    localparam S_ADDR_WIDTH = 32;
    localparam S_DATA_WIDTH = 32;
    localparam S_ID_WIDTH   = 4;
    localparam M_ADDR_WIDTH = 32;
    localparam M_DATA_WIDTH = 64;
    localparam M_ID_WIDTH   = 4;

    localparam BASE         = 32'h2000_0000;
    localparam ADDR_CTRL    = BASE + 32'h000;
    localparam ADDR_STATUS  = BASE + 32'h004;
    localparam ADDR_MODE    = BASE + 32'h008;
    localparam ADDR_IRQ_EN  = BASE + 32'h00C;
    localparam ADDR_KEY_0   = BASE + 32'h010;
    localparam ADDR_KEY_1   = BASE + 32'h014;
    localparam ADDR_KEY_2   = BASE + 32'h018;
    localparam ADDR_KEY_3   = BASE + 32'h01C;
    localparam ADDR_NON_0   = BASE + 32'h020;
    localparam ADDR_NON_1   = BASE + 32'h024;
    localparam ADDR_NON_2   = BASE + 32'h028;
    localparam ADDR_NON_3   = BASE + 32'h02C;
    localparam ADDR_PTX_0   = BASE + 32'h030;
    localparam ADDR_PTX_1   = BASE + 32'h034;
    localparam ADDR_CTX_0   = BASE + 32'h040;
    localparam ADDR_CTX_1   = BASE + 32'h044;
    localparam ADDR_TAG_0   = BASE + 32'h048;
    localparam ADDR_TAG_1   = BASE + 32'h04C;
    localparam ADDR_TAG_2   = BASE + 32'h050;
    localparam ADDR_TAG_3   = BASE + 32'h054;
    localparam ADDR_DMA_SRC = BASE + 32'h100;
    localparam ADDR_DMA_DST = BASE + 32'h104;
    localparam ADDR_DMA_LEN = BASE + 32'h108;

    localparam CTRL_START    = 32'h1;
    localparam CTRL_SOFT_RST = 32'h2;
    localparam CTRL_DMA_EN   = 32'h4;
    localparam CTRL_DMA_START= 32'h5;

    localparam STATUS_BUSY      = 0;
    localparam STATUS_DONE      = 1;
    localparam STATUS_DMA_BUSY  = 2;
    localparam STATUS_DMA_DONE  = 3;
    localparam STATUS_ERROR     = 4;
    localparam STATUS_DMA_ERROR = 5;

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    reg clk   = 0;
    reg rst_n = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // AXI4-Lite Slave signals
    // =========================================================================
    reg  [S_ID_WIDTH-1:0]     s_awid    = 0;
    reg  [S_ADDR_WIDTH-1:0]   s_awaddr  = 0;
    reg  [2:0]                s_awprot  = 0;
    reg                       s_awvalid = 0;
    wire                      s_awready;

    reg  [S_DATA_WIDTH-1:0]   s_wdata  = 0;
    reg  [S_DATA_WIDTH/8-1:0] s_wstrb  = 4'hF;
    reg                       s_wvalid = 0;
    wire                      s_wready;

    wire [S_ID_WIDTH-1:0]     s_bid;
    wire [1:0]                s_bresp;
    wire                      s_bvalid;
    reg                       s_bready = 1;

    reg  [S_ID_WIDTH-1:0]     s_arid    = 0;
    reg  [S_ADDR_WIDTH-1:0]   s_araddr  = 0;
    reg  [2:0]                s_arprot  = 0;
    reg                       s_arvalid = 0;
    wire                      s_arready;

    wire [S_ID_WIDTH-1:0]     s_rid;
    wire [S_DATA_WIDTH-1:0]   s_rdata;
    wire [1:0]                s_rresp;
    wire                      s_rlast;
    wire                      s_rvalid;
    reg                       s_rready = 1;

    // =========================================================================
    // AXI4-Full Master signals
    // =========================================================================
    wire [M_ID_WIDTH-1:0]     m_awid;
    wire [M_ADDR_WIDTH-1:0]   m_awaddr;
    wire [7:0]                m_awlen;
    wire [2:0]                m_awsize;
    wire [1:0]                m_awburst;
    wire [3:0]                m_awcache;
    wire [2:0]                m_awprot_w;
    wire                      m_awvalid;
    reg                       m_awready = 0;

    wire [M_DATA_WIDTH-1:0]   m_wdata;
    wire [M_DATA_WIDTH/8-1:0] m_wstrb;
    wire                      m_wlast;
    wire                      m_wvalid;
    reg                       m_wready  = 0;

    reg  [M_ID_WIDTH-1:0]     m_bid    = 0;
    reg  [1:0]                m_bresp  = 0;
    reg                       m_bvalid = 0;
    wire                      m_bready;

    wire [M_ID_WIDTH-1:0]     m_arid;
    wire [M_ADDR_WIDTH-1:0]   m_araddr;
    wire [7:0]                m_arlen;
    wire [2:0]                m_arsize;
    wire [1:0]                m_arburst;
    wire [3:0]                m_arcache;
    wire [2:0]                m_arprot_w;
    wire                      m_arvalid;
    reg                       m_arready = 0;

    reg  [M_ID_WIDTH-1:0]     m_rid    = 0;
    reg  [M_DATA_WIDTH-1:0]   m_rdata  = 0;
    reg  [1:0]                m_rresp  = 0;
    reg                       m_rlast  = 0;
    reg                       m_rvalid = 0;
    wire                      m_rready;

    wire irq;

    // =========================================================================
    // DUT
    // =========================================================================
    ascon_ip_top #(
        .S_ADDR_WIDTH (S_ADDR_WIDTH),
        .S_DATA_WIDTH (S_DATA_WIDTH),
        .S_ID_WIDTH   (S_ID_WIDTH),
        .M_ADDR_WIDTH (M_ADDR_WIDTH),
        .M_DATA_WIDTH (M_DATA_WIDTH),
        .M_ID_WIDTH   (M_ID_WIDTH)
    ) dut (
        .clk              (clk),       .rst_n            (rst_n),
        .S_AXI_AWID       (s_awid),    .S_AXI_AWADDR     (s_awaddr),
        .S_AXI_AWPROT     (s_awprot),  .S_AXI_AWVALID    (s_awvalid),
        .S_AXI_AWREADY    (s_awready),
        .S_AXI_WDATA      (s_wdata),   .S_AXI_WSTRB      (s_wstrb),
        .S_AXI_WVALID     (s_wvalid),  .S_AXI_WREADY     (s_wready),
        .S_AXI_BID        (s_bid),     .S_AXI_BRESP      (s_bresp),
        .S_AXI_BVALID     (s_bvalid),  .S_AXI_BREADY     (s_bready),
        .S_AXI_ARID       (s_arid),    .S_AXI_ARADDR     (s_araddr),
        .S_AXI_ARPROT     (s_arprot),  .S_AXI_ARVALID    (s_arvalid),
        .S_AXI_ARREADY    (s_arready),
        .S_AXI_RID        (s_rid),     .S_AXI_RDATA      (s_rdata),
        .S_AXI_RRESP      (s_rresp),   .S_AXI_RLAST      (s_rlast),
        .S_AXI_RVALID     (s_rvalid),  .S_AXI_RREADY     (s_rready),
        .M_AXI_AWID       (m_awid),    .M_AXI_AWADDR     (m_awaddr),
        .M_AXI_AWLEN      (m_awlen),   .M_AXI_AWSIZE     (m_awsize),
        .M_AXI_AWBURST    (m_awburst), .M_AXI_AWCACHE    (m_awcache),
        .M_AXI_AWPROT     (m_awprot_w),.M_AXI_AWVALID    (m_awvalid),
        .M_AXI_AWREADY    (m_awready),
        .M_AXI_WDATA      (m_wdata),   .M_AXI_WSTRB      (m_wstrb),
        .M_AXI_WLAST      (m_wlast),   .M_AXI_WVALID     (m_wvalid),
        .M_AXI_WREADY     (m_wready),
        .M_AXI_BID        (m_bid),     .M_AXI_BRESP      (m_bresp),
        .M_AXI_BVALID     (m_bvalid),  .M_AXI_BREADY     (m_bready),
        .M_AXI_ARID       (m_arid),    .M_AXI_ARADDR     (m_araddr),
        .M_AXI_ARLEN      (m_arlen),   .M_AXI_ARSIZE     (m_arsize),
        .M_AXI_ARBURST    (m_arburst), .M_AXI_ARCACHE    (m_arcache),
        .M_AXI_ARPROT     (m_arprot_w),.M_AXI_ARVALID    (m_arvalid),
        .M_AXI_ARREADY    (m_arready),
        .M_AXI_RID        (m_rid),     .M_AXI_RDATA      (m_rdata),
        .M_AXI_RRESP      (m_rresp),   .M_AXI_RLAST      (m_rlast),
        .M_AXI_RVALID     (m_rvalid),  .M_AXI_RREADY     (m_rready),
        .irq              (irq)
    );

    // =========================================================================
    // DDR memory model  (1 KB)
    // =========================================================================
    reg [7:0] ddr_mem [0:1023];
    integer mi;
    initial for (mi = 0; mi < 1024; mi = mi+1) ddr_mem[mi] = 8'h00;

    `define DDR_IDX(a) ((a) & 10'h3FF)

    reg tc9_err = 0;

    // M_AXI Read responder
    reg [M_ADDR_WIDTH-1:0] rd_addr;
    reg [7:0]              rd_beats;
    reg [M_ID_WIDTH-1:0]   rd_id;
    reg                    mem_rd_st = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_arready <= 0; m_rvalid <= 0; m_rlast <= 0;
            m_rdata   <= 0; m_rid    <= 0; mem_rd_st <= 0;
        end else if (mem_rd_st == 0) begin
            m_arready <= 1;
            if (m_arvalid && m_arready) begin
                rd_addr   <= m_araddr; rd_beats <= m_arlen;
                rd_id     <= m_arid;   m_arready <= 0;
                mem_rd_st <= 1;
            end
        end else begin
            m_rvalid <= 1;
            m_rid    <= rd_id;
            m_rresp  <= tc9_err ? 2'b10 : 2'b00;
            m_rdata  <= { ddr_mem[`DDR_IDX(rd_addr+0)], ddr_mem[`DDR_IDX(rd_addr+1)],
                          ddr_mem[`DDR_IDX(rd_addr+2)], ddr_mem[`DDR_IDX(rd_addr+3)],
                          ddr_mem[`DDR_IDX(rd_addr+4)], ddr_mem[`DDR_IDX(rd_addr+5)],
                          ddr_mem[`DDR_IDX(rd_addr+6)], ddr_mem[`DDR_IDX(rd_addr+7)] };
            m_rlast  <= (rd_beats == 0);
            if (m_rvalid && m_rready) begin
                if (rd_beats == 0) begin
                    m_rvalid <= 0; m_rlast <= 0; mem_rd_st <= 0;
                end else begin
                    rd_addr  <= rd_addr + (M_DATA_WIDTH/8);
                    rd_beats <= rd_beats - 1;
                end
            end
        end
    end

    // M_AXI Write responder
    reg [M_ADDR_WIDTH-1:0] wr_addr;
    reg [7:0]              wr_beats;
    reg [M_ID_WIDTH-1:0]   wr_id;
    reg [1:0]              mem_wr_st = 0;
    integer bi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready <= 0; m_wready <= 0; m_bvalid <= 0;
            m_bid <= 0; m_bresp <= 0; mem_wr_st <= 0;
        end else case (mem_wr_st)
            2'd0: begin
                m_awready <= 1;
                if (m_awvalid && m_awready) begin
                    wr_addr   <= m_awaddr; wr_beats <= m_awlen;
                    wr_id     <= m_awid;   m_awready <= 0;
                    m_wready  <= 1;        mem_wr_st <= 1;
                end
            end
            2'd1: begin
                if (m_wvalid && m_wready) begin
                    for (bi=0; bi < M_DATA_WIDTH/8; bi=bi+1)
                        if (m_wstrb[bi]) ddr_mem[`DDR_IDX(wr_addr+bi)] <= m_wdata[bi*8 +: 8];
                    if (m_wlast) begin
                        m_wready <= 0; m_bvalid <= 1;
                        m_bid    <= wr_id; m_bresp <= 0; mem_wr_st <= 2;
                    end else begin
                        wr_addr  <= wr_addr + (M_DATA_WIDTH/8);
                        wr_beats <= wr_beats - 1;
                    end
                end
            end
            2'd2: begin
                if (m_bvalid && m_bready) begin
                    m_bvalid <= 0; mem_wr_st <= 0;
                end
            end
            default: mem_wr_st <= 0;
        endcase
    end

    // =========================================================================
    // Shared task state vars (module-level — Verilog-2001 safe)
    // =========================================================================
    reg [31:0] rdata_buf  = 0;
    integer    pass_count = 0;
    integer    fail_count = 0;

    // =========================================================================
    // AXI4-Lite Write task
    // -  Drive AW+W đồng thời trên cùng posedge đầu tiên
    // -  Dùng hai vòng lặp riêng để deassert từng kênh khi ready
    // -  KHÔNG dùng local reg  (Verilog-2001 task local reg + @clk = unreliable)
    // =========================================================================
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        integer tw;
        begin
            // --- Phase 1: present AW + W trên cùng clock edge ---
            @(posedge clk); #1;
            s_awid    = 4'h1;  s_awaddr  = addr;
            s_awvalid = 1'b1;
            s_wdata   = data;  s_wstrb   = strb;
            s_wvalid  = 1'b1;

            // --- Phase 2: wait AW accepted (deassert sau khi accepted) ---
            tw = 0;
            @(posedge clk);
            while (!(s_awready && s_awvalid)) begin
                @(posedge clk);
                tw = tw + 1;
                if (tw > 200) begin
                    $display("  [ERR] axi_write AW timeout! awready=%b awvalid=%b addr=%08h",
                             s_awready, s_awvalid, addr);
                    tw = 0; // reset to avoid infinite loop — slave bug
                    s_awvalid = 0;
                end
            end
            #1; s_awvalid = 1'b0;

            // --- Phase 3: wait W accepted (deassert sau khi accepted) ---
            // W có thể đã được accepted cùng cycle với AW — kiểm tra ngay
            tw = 0;
            if (!(s_wready && s_wvalid)) begin
                @(posedge clk);
                while (!(s_wready && s_wvalid)) begin
                    @(posedge clk);
                    tw = tw + 1;
                    if (tw > 200) begin
                        $display("  [ERR] axi_write W timeout! wready=%b wvalid=%b addr=%08h",
                                 s_wready, s_wvalid, addr);
                        tw = 0;
                        s_wvalid = 0;
                    end
                end
            end
            #1; s_wvalid = 1'b0;

            // --- Phase 4: wait B response ---
            tw = 0;
            while (!s_bvalid) begin
                @(posedge clk);
                tw = tw + 1;
                if (tw > 200) begin
                    $display("  [ERR] axi_write B timeout! bvalid=%b addr=%08h",
                             s_bvalid, addr);
                    tw = 0;
                    disable axi_write;
                end
            end
            @(posedge clk);
        end
    endtask

    task axi_wr;
        input [31:0] addr;
        input [31:0] data;
        begin axi_write(addr, data, 4'hF); end
    endtask

    // =========================================================================
    // AXI4-Lite Read task
    // =========================================================================
    task axi_read;
        input [31:0] addr;
        integer tr;
        begin
            @(posedge clk); #1;
            s_arid    = 4'h2;
            s_araddr  = addr;
            s_arvalid = 1'b1;

            // wait AR accepted
            tr = 0;
            @(posedge clk);
            while (!(s_arready && s_arvalid)) begin
                @(posedge clk);
                tr = tr + 1;
                if (tr > 200) begin
                    $display("  [ERR] axi_read AR timeout! addr=%08h", addr);
                    tr = 0;
                    s_arvalid = 0;
                end
            end
            #1; s_arvalid = 1'b0;

            // wait R response
            tr = 0;
            while (!s_rvalid) begin
                @(posedge clk);
                tr = tr + 1;
                if (tr > 200) begin
                    $display("  [ERR] axi_read R timeout! addr=%08h", addr);
                    tr = 0;
                    disable axi_read;
                end
            end
            rdata_buf = s_rdata;
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // wait_done  (poll STATUS với delay giữa các lần)
    // =========================================================================
    task wait_done;
        input [31:0] mask;
        input integer max_polls;
        integer p;
        begin
            p = 0;
            begin : wdone
                forever begin
                    repeat(5) @(posedge clk);
                    axi_read(ADDR_STATUS);
                    if (rdata_buf & mask) disable wdone;
                    p = p + 1;
                    if (p >= max_polls) begin
                        $display("  [TIMEOUT] wait_done: STATUS=0x%08h  core_busy=%b  core_done=%b",
                                 rdata_buf, dut.core_busy_w, dut.core_done_w);
                        disable wdone;
                    end
                end
            end
        end
    endtask

    // =========================================================================
    // check / check_bit
    // =========================================================================
    task check;
        input [127:0] unused;
        input [31:0]  got;
        input [31:0]  exp;
        input [639:0] lbl;
        begin
            if (got === exp) begin
                $display("  [PASS] %s  got=0x%08h", lbl, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s  got=0x%08h  exp=0x%08h  (@%0t)",
                         lbl, got, exp, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_bit;
        input [31:0]  val;
        input integer bpos;
        input integer expv;
        input [639:0] lbl;
        begin
            if (((val >> bpos) & 1) === expv[0:0]) begin
                $display("  [PASS] %s  bit[%0d]=%0d", lbl, bpos, expv);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s  bit[%0d] got=%0d exp=%0d  (@%0t)",
                         lbl, bpos, (val>>bpos)&1, expv, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // wait_irq
    // =========================================================================
    task wait_irq;
        input integer tmax;
        integer ci;
        begin
            ci = 0;
            begin : wIRQ
                forever begin
                    @(posedge clk);
                    if (irq) disable wIRQ;
                    ci = ci + 1;
                    if (ci >= tmax) begin
                        $display("  [TIMEOUT] wait_irq: no irq after %0d cycles", tmax);
                        disable wIRQ;
                    end
                end
            end
        end
    endtask

    // =========================================================================
    // DDR helpers
    // =========================================================================
    task seed_ddr;
        input [31:0] base;
        input [63:0] d64;
        integer k;
        begin
            for (k=0; k<8; k=k+1)
                ddr_mem[(base+k) & 10'h3FF] = d64[63 - k*8 -: 8];
        end
    endtask

    function [63:0] read_ddr64;
        input [31:0] base;
        integer k;
        reg [63:0] v;
        begin
            v = 0;
            for (k=0; k<8; k=k+1)
                v[63 - k*8 -: 8] = ddr_mem[(base+k) & 10'h3FF];
            read_ddr64 = v;
        end
    endfunction

    // =========================================================================
    // VCD
    // =========================================================================
    initial begin
        $dumpfile("tb_ascon_ip_top.vcd");
        $dumpvars(0, tb_ascon_ip_top);
    end

    // =========================================================================
    // Realtime monitor
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && dut.u_core.start)
            $display("  [MON @%0t] core.start  busy=%b  done=%b",
                     $time, dut.core_busy_w, dut.core_done_w);
    end
    always @(posedge dut.core_done_w)
        $display("  [MON @%0t] core.DONE asserted!", $time);
    always @(posedge dut.core_busy_w)
        $display("  [MON @%0t] core.BUSY asserted!", $time);
    always @(negedge dut.core_busy_w)
        $display("  [MON @%0t] core.BUSY deasserted  done=%b", $time, dut.core_done_w);

    // =========================================================================
    // Module-level temporaries
    // =========================================================================
    reg [31:0] golden_ctx_0 = 0, golden_ctx_1 = 0;
    reg [31:0] golden_tag_0 = 0, golden_tag_1 = 0;
    reg [31:0] golden_tag_2 = 0, golden_tag_3 = 0;
    reg [63:0] ddr_result;
    integer    b2b_i;

    // =========================================================================
    // Main test
    // =========================================================================
    initial begin
        $display("================================================================");
        $display("   ASCON IP Top Testbench v1.3");
        $display("================================================================");

        rst_n = 0;
        repeat(5) @(posedge clk);
        @(negedge clk); rst_n = 1;
        repeat(3) @(posedge clk);

        // =====================================================================
        // TC1
        // =====================================================================
        $display("\n[TC1] Reset and idle state");
        check(0, s_awready, 1, "TC1 -- AWREADY=1");
        check(0, s_wready,  1, "TC1 -- WREADY=1");
        check(0, s_bvalid,  0, "TC1 -- BVALID=0");
        check(0, s_arready, 1, "TC1 -- ARREADY=1");
        check(0, s_rvalid,  0, "TC1 -- RVALID=0");
        check(0, irq,       0, "TC1 -- irq=0");
        check(0, m_awvalid, 0, "TC1 -- M_AWVALID=0");
        check(0, m_arvalid, 0, "TC1 -- M_ARVALID=0");
        axi_read(ADDR_STATUS);
        check(0, rdata_buf, 0, "TC1 -- STATUS=0");
        axi_read(ADDR_DMA_LEN);
        check(0, rdata_buf, 32'd8, "TC1 -- DMA_LEN=8");

        // =====================================================================
        // TC2: CPU-Direct encrypt
        // =====================================================================
        $display("\n[TC2] CPU-Direct mode: encrypt");

        $display("  [DBG] awready=%b wready=%b", s_awready, s_wready);

        axi_wr(ADDR_KEY_0, 32'h00010203); $display("  [DBG] KEY_0 written");
        axi_wr(ADDR_KEY_1, 32'h04050607); $display("  [DBG] KEY_1 written");
        axi_wr(ADDR_KEY_2, 32'h08090A0B); $display("  [DBG] KEY_2 written");
        axi_wr(ADDR_KEY_3, 32'h0C0D0E0F); $display("  [DBG] KEY_3 written");

        axi_wr(ADDR_NON_0, 32'h0F0E0D0C);
        axi_wr(ADDR_NON_1, 32'h0B0A0908);
        axi_wr(ADDR_NON_2, 32'h07060504);
        axi_wr(ADDR_NON_3, 32'h03020100);
        $display("  [DBG] NONCE written");

        axi_wr(ADDR_PTX_0, 32'hDEADBEEF);
        axi_wr(ADDR_PTX_1, 32'hCAFEBABE);
        $display("  [DBG] PTEXT written");

        axi_wr(ADDR_MODE, 32'h0);

        axi_read(ADDR_STATUS);
        $display("  [DBG] STATUS before START = 0x%08h  awready=%b wready=%b",
                 rdata_buf, s_awready, s_wready);

        $display("  [DBG] Firing CTRL.START...");
        axi_wr(ADDR_CTRL, CTRL_START);
        $display("  [DBG] CTRL.START done. core_start_mux=%b core_busy=%b core_done=%b",
                 dut.core_start_mux, dut.core_busy_w, dut.core_done_w);

        repeat(2)  @(posedge clk);
        $display("  [DBG] +2cy: core_start_mux=%b core_busy=%b core_done=%b",
                 dut.core_start_mux, dut.core_busy_w, dut.core_done_w);

        repeat(10) @(posedge clk);
        $display("  [DBG] +10cy: core_busy=%b core_done=%b",
                 dut.core_busy_w, dut.core_done_w);
        axi_read(ADDR_STATUS);
        $display("  [DBG] +10cy: STATUS=0x%08h", rdata_buf);

        repeat(50) @(posedge clk);
        $display("  [DBG] +50cy: core_busy=%b core_done=%b",
                 dut.core_busy_w, dut.core_done_w);

        repeat(200) @(posedge clk);
        $display("  [DBG] +200cy: core_busy=%b core_done=%b",
                 dut.core_busy_w, dut.core_done_w);
        axi_read(ADDR_STATUS);
        $display("  [DBG] +200cy: STATUS=0x%08h", rdata_buf);

        wait_done(32'h2, 500);

        axi_read(ADDR_STATUS);
        $display("  [DBG] Final STATUS = 0x%08h", rdata_buf);
        check_bit(rdata_buf, STATUS_DONE, 1, "TC2 -- STATUS.DONE=1");
        check_bit(rdata_buf, STATUS_BUSY, 0, "TC2 -- STATUS.BUSY=0");

        axi_read(ADDR_CTX_0); golden_ctx_0 = rdata_buf;
        axi_read(ADDR_CTX_1); golden_ctx_1 = rdata_buf;
        axi_read(ADDR_TAG_0); golden_tag_0 = rdata_buf;
        axi_read(ADDR_TAG_1); golden_tag_1 = rdata_buf;
        axi_read(ADDR_TAG_2); golden_tag_2 = rdata_buf;
        axi_read(ADDR_TAG_3); golden_tag_3 = rdata_buf;

        $display("  [INFO] CTEXT: %08h_%08h", golden_ctx_0, golden_ctx_1);
        $display("  [INFO] TAG  : %08h_%08h_%08h_%08h",
                 golden_tag_0, golden_tag_1, golden_tag_2, golden_tag_3);

        if (golden_ctx_0 !== 0 || golden_ctx_1 !== 0) begin
            $display("  [PASS] TC2 -- CTEXT non-zero"); pass_count = pass_count+1;
        end else begin
            $display("  [FAIL] TC2 -- CTEXT is zero");  fail_count = fail_count+1;
        end
        if (golden_tag_0 !== 0 || golden_tag_1 !== 0 ||
            golden_tag_2 !== 0 || golden_tag_3 !== 0) begin
            $display("  [PASS] TC2 -- TAG non-zero"); pass_count = pass_count+1;
        end else begin
            $display("  [FAIL] TC2 -- TAG is zero");  fail_count = fail_count+1;
        end

        // =====================================================================
        // TC3
        // =====================================================================
        $display("\n[TC3] irq on DONE");
        axi_wr(ADDR_CTRL,   CTRL_SOFT_RST);
        repeat(3) @(posedge clk);
        axi_wr(ADDR_IRQ_EN, 32'h1);
        axi_wr(ADDR_CTRL,   CTRL_START);
        wait_irq(2000);
        check(0, irq, 1, "TC3 -- irq=1 after DONE");
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DONE, 1, "TC3 -- STATUS.DONE=1");
        axi_wr(ADDR_IRQ_EN, 32'h0);
        repeat(3) @(posedge clk);
        check(0, irq, 0, "TC3 -- irq=0 after clear");

        // =====================================================================
        // TC4
        // =====================================================================
        $display("\n[TC4] SOFT_RST");
        axi_wr(ADDR_IRQ_EN, 32'h1);
        repeat(2) @(posedge clk);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DONE, 1, "TC4 -- DONE=1 before RST");
        check(0, irq, 1, "TC4 -- irq=1 before RST");
        axi_wr(ADDR_CTRL, CTRL_SOFT_RST);
        repeat(3) @(posedge clk);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DONE, 0, "TC4 -- DONE=0 after RST");
        check_bit(rdata_buf, STATUS_BUSY, 0, "TC4 -- BUSY=0 after RST");
        check(0, irq, 0, "TC4 -- irq=0 after RST");
        axi_wr(ADDR_IRQ_EN, 32'h0);

        // =====================================================================
        // TC5
        // =====================================================================
        $display("\n[TC5] START blocked while busy");
        axi_wr(ADDR_CTRL, CTRL_START);
        @(posedge clk); @(posedge clk);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_BUSY, 1, "TC5 -- BUSY=1 after START");
        axi_wr(ADDR_CTRL, CTRL_START);   // second start — should be ignored
        wait_done(32'h2, 500);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DONE, 1, "TC5 -- DONE=1 after 2nd START ignored");
        axi_read(ADDR_CTX_0);
        check(0, rdata_buf, golden_ctx_0, "TC5 -- CTEXT_0 not corrupted");
        axi_read(ADDR_CTX_1);
        check(0, rdata_buf, golden_ctx_1, "TC5 -- CTEXT_1 not corrupted");

        // =====================================================================
        // TC6
        // =====================================================================
        $display("\n[TC6] DMA mode: full pipeline");
        axi_wr(ADDR_CTRL, CTRL_SOFT_RST);
        repeat(3) @(posedge clk);
        seed_ddr(32'h100, {32'hDEADBEEF, 32'hCAFEBABE});
        axi_wr(ADDR_DMA_SRC, 32'h100);
        axi_wr(ADDR_DMA_DST, 32'h200);
        axi_wr(ADDR_DMA_LEN, 32'd8);
        axi_wr(ADDR_IRQ_EN,  32'h2);
        axi_wr(ADDR_CTRL,    CTRL_DMA_START);
        wait_done(32'h8, 1000);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DMA_DONE,  1, "TC6 -- DMA_DONE=1");
        check_bit(rdata_buf, STATUS_DMA_BUSY,  0, "TC6 -- DMA_BUSY=0");
        check_bit(rdata_buf, STATUS_DMA_ERROR, 0, "TC6 -- DMA_ERROR=0");
        axi_read(ADDR_CTX_0);
        check(0, rdata_buf, golden_ctx_0, "TC6 -- CTEXT_0 after DMA");
        axi_read(ADDR_CTX_1);
        check(0, rdata_buf, golden_ctx_1, "TC6 -- CTEXT_1 after DMA");
        axi_read(ADDR_TAG_0);
        check(0, rdata_buf, golden_tag_0, "TC6 -- TAG_0 after DMA");
        axi_read(ADDR_TAG_3);
        check(0, rdata_buf, golden_tag_3, "TC6 -- TAG_3 after DMA");
        ddr_result = read_ddr64(32'h200);
        $display("  [INFO] DDR[0x200]=%016h", ddr_result);
        if (ddr_result !== 0) begin
            $display("  [PASS] TC6 -- DDR dst non-zero"); pass_count=pass_count+1;
        end else begin
            $display("  [FAIL] TC6 -- DDR dst zero");    fail_count=fail_count+1;
        end

        // =====================================================================
        // TC7
        // =====================================================================
        $display("\n[TC7] DMA IRQ");
        check(0, irq, 1, "TC7 -- irq=1 on DMA_DONE");
        axi_wr(ADDR_IRQ_EN, 32'h0);
        repeat(3) @(posedge clk);
        check(0, irq, 0, "TC7 -- irq=0 after clear");

        // =====================================================================
        // TC8
        // =====================================================================
        $display("\n[TC8] DMA SOFT_RST");
        axi_wr(ADDR_CTRL, CTRL_SOFT_RST);
        repeat(5) @(posedge clk);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DONE,     0, "TC8 -- DONE=0 after RST");
        check_bit(rdata_buf, STATUS_DMA_DONE, 0, "TC8 -- DMA_DONE=0 after RST");
        check_bit(rdata_buf, STATUS_DMA_BUSY, 0, "TC8 -- DMA_BUSY=0 after RST");
        check(0, irq, 0, "TC8 -- irq=0 after RST");

        // =====================================================================
        // TC9: DMA error
        // =====================================================================
        $display("\n[TC9] DMA error injection");
        axi_wr(ADDR_IRQ_EN,  32'h4);
        tc9_err = 0;
        axi_wr(ADDR_DMA_SRC, 32'h100);
        axi_wr(ADDR_DMA_DST, 32'h300);
        axi_wr(ADDR_DMA_LEN, 32'd8);
        axi_wr(ADDR_CTRL,    CTRL_DMA_START);
        begin : wAR
            integer tc;
            tc = 0;
            forever begin
                @(posedge clk);
                if (m_arvalid) disable wAR;
                tc = tc + 1;
                if (tc > 500) disable wAR;
            end
        end
        tc9_err = 1;
        repeat(4) @(posedge clk);
        tc9_err = 0;
        wait_done(32'h20, 1000);
        axi_read(ADDR_STATUS);
        check_bit(rdata_buf, STATUS_DMA_ERROR, 1, "TC9 -- DMA_ERROR=1");
        check(0, irq, 1, "TC9 -- irq=1 on error");
        axi_wr(ADDR_IRQ_EN, 32'h0);
        axi_wr(ADDR_CTRL,   CTRL_SOFT_RST);
        repeat(3) @(posedge clk);

        // =====================================================================
        // TC10
        // =====================================================================
        $display("\n[TC10] CTEXT/TAG preserved");
        axi_wr(ADDR_CTRL, CTRL_START);
        wait_done(32'h2, 500);
        axi_read(ADDR_CTX_0); check(0, rdata_buf, golden_ctx_0, "TC10 -- CTEXT_0");
        axi_read(ADDR_CTX_1); check(0, rdata_buf, golden_ctx_1, "TC10 -- CTEXT_1");
        axi_read(ADDR_TAG_0); check(0, rdata_buf, golden_tag_0, "TC10 -- TAG_0");
        axi_read(ADDR_TAG_1); check(0, rdata_buf, golden_tag_1, "TC10 -- TAG_1");
        axi_read(ADDR_TAG_2); check(0, rdata_buf, golden_tag_2, "TC10 -- TAG_2");
        axi_read(ADDR_TAG_3); check(0, rdata_buf, golden_tag_3, "TC10 -- TAG_3");

        // =====================================================================
        // TC11
        // =====================================================================
        $display("\n[TC11] Back-to-back encrypts");
        for (b2b_i=0; b2b_i<3; b2b_i=b2b_i+1) begin
            axi_wr(ADDR_CTRL, CTRL_SOFT_RST);
            repeat(2) @(posedge clk);
            axi_wr(ADDR_CTRL, CTRL_START);
            wait_done(32'h2, 500);
            axi_read(ADDR_CTX_0);
            if      (b2b_i==0) check(0, rdata_buf, golden_ctx_0, "TC11 -- B2B[0] CTX0");
            else if (b2b_i==1) check(0, rdata_buf, golden_ctx_0, "TC11 -- B2B[1] CTX0");
            else               check(0, rdata_buf, golden_ctx_0, "TC11 -- B2B[2] CTX0");
            axi_read(ADDR_CTX_1);
            if      (b2b_i==0) check(0, rdata_buf, golden_ctx_1, "TC11 -- B2B[0] CTX1");
            else if (b2b_i==1) check(0, rdata_buf, golden_ctx_1, "TC11 -- B2B[1] CTX1");
            else               check(0, rdata_buf, golden_ctx_1, "TC11 -- B2B[2] CTX1");
        end

        // =====================================================================
        // TC12
        // =====================================================================
        $display("\n[TC12] Register readback");
        axi_wr(ADDR_MODE,   32'h3);
        axi_wr(ADDR_IRQ_EN, 32'h7);
        axi_read(ADDR_MODE);   check(0, rdata_buf, 32'h3, "TC12 -- MODE=0x3");
        axi_read(ADDR_IRQ_EN); check(0, rdata_buf, 32'h7, "TC12 -- IRQ_EN=0x7");
        axi_wr(ADDR_MODE,   32'h0);
        axi_wr(ADDR_IRQ_EN, 32'h0);
        axi_read(ADDR_MODE);   check(0, rdata_buf, 32'h0, "TC12 -- MODE=0 cleared");
        axi_read(ADDR_IRQ_EN); check(0, rdata_buf, 32'h0, "TC12 -- IRQ_EN=0 cleared");

        // =====================================================================
        // Summary
        // =====================================================================
        repeat(5) @(posedge clk);
        $display("\n================================================================");
        $display("   TEST RESULTS SUMMARY");
        $display("================================================================");
        $display("   PASS : %0d", pass_count);
        $display("   FAIL : %0d", fail_count);
        if (fail_count == 0)
            $display("   *** ALL TESTS PASSED ***");
        else
            $display("   *** %0d TEST(S) FAILED ***", fail_count);
        $display("================================================================");
        $finish;
    end

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin
        #20_000_000;
        $display("[WATCHDOG] Timeout!  core_busy=%b  core_done=%b  awready=%b  wready=%b",
                 dut.core_busy_w, dut.core_done_w, s_awready, s_wready);
        $finish;
    end

endmodule