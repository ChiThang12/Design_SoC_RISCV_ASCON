`timescale 1ns/1ps

// ============================================================================
// File     : tb_ascon_dma.v
// Project  : RISC-V SoC — ASCON Crypto Accelerator IP
// Version  : 3.0 (root cause fixed)
//
// Root cause analysis:
// ─────────────────────────────────────────────────────────────────────────
// dma_write_engine WR_DATA state có logic:
//   if (!M_AXI_WVALID) begin  // nhánh A: drive beat
//       M_AXI_WDATA  <= ...;
//       M_AXI_WVALID <= 1;
//       M_AXI_WLAST  <= (beat_cnt==2);
//   end
//   if (M_AXI_WVALID && M_AXI_WREADY) begin  // nhánh B: handshake
//       M_AXI_WVALID <= 0;
//       ...
//   end
//
// Nếu TB slave assert WREADY=1 TRƯỚC khi WVALID đến:
//   Cycle N: WVALID=0, WREADY=1 → nhánh A execute (WVALID set)
//             cùng lúc: WVALID=0 nên nhánh B KHÔNG execute
//             → Nhưng do nonblocking, WVALID thực sự =0 khi eval nhánh B
//             → Beat được drive đúng, handshake cycle sau
//
// Thực ra bug nằm ở chỗ khác:
// Cycle N:   word_half=1, !WVALID → nhánh A: WDATA={hi,lo}, WVALID=1, WLAST=?
//             word_half <= 0 (nhánh A line 179)
// Cycle N+1: word_half=0, WVALID=1, WREADY=1 → vào nhánh !word_half
//             → fifo_dout lại bị latch làm wdata_hi → POP lần nữa → duplicate
//
// Fix: TB slave dùng WREADY chỉ =1 sau khi detect WVALID (1-cycle pulse),
//      không pre-assert. Điều này tránh race condition trong RTL write engine.
//
// Thêm: FIX FIFO read latency trong write engine:
//   WR_ADDR: pop high word → word_half=0, WR_DATA chờ dout valid
//   WR_DATA word_half=0: dout valid (high word) → latch, pop low word
//   WR_DATA word_half=1: dout valid (low word) → compose WDATA, drive
//   Handshake xong: nếu chưa last → pop high word tiếp → word_half=0
//
// Kết quả expected (3 beats, beat_cnt=0,1,2):
//   Beat0: {ctext_0, ctext_1}  → WLAST=0
//   Beat1: {tag_0, tag_1}      → WLAST=0
//   Beat2: {tag_2, tag_3}      → WLAST=1
// ============================================================================

`timescale 1ns/1ps
`define SIMULATION
`include "ascon_accelerator/dma/rtl/ascon_dma.v"
module tb_ascon_dma;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter ADDR_WIDTH     = 32;
    parameter AXI_DATA_WIDTH = 64;
    parameter AXI_ID_WIDTH   = 4;
    parameter RD_FIFO_DEPTH  = 4;
    parameter WR_FIFO_DEPTH  = 8;
    parameter CLK_PERIOD     = 10;
    parameter CORE_LATENCY   = 8;
    parameter MEM_SIZE       = 256;  // 256 × 64-bit, indexed bằng addr[10:3]

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    reg clk, rst_n;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Control
    // =========================================================================
    reg  [ADDR_WIDTH-1:0]  src_addr, dst_addr;
    reg  [31:0]            byte_len;
    reg  [7:0]             burst_len;
    reg                    dma_start, dma_soft_rst;

    wire                   dma_busy, dma_done, dma_error;
    wire                   status_rd_done, status_wr_done;
    wire                   status_rd_error, status_wr_error, status_fifo_overflow;
    wire [ADDR_WIDTH-1:0]  dma_err_addr;

    // =========================================================================
    // CORE mock signals
    // =========================================================================
    wire [31:0] core_ptext_0, core_ptext_1;
    wire        core_data_valid, core_start;
    reg         core_data_ready, core_busy, core_done;
    reg  [31:0] core_ctext_0, core_ctext_1;
    reg  [31:0] core_tag_0, core_tag_1, core_tag_2, core_tag_3;

    // =========================================================================
    // AXI4 Master signals
    // =========================================================================
    wire [AXI_ID_WIDTH-1:0]     M_AXI_AWID;
    wire [ADDR_WIDTH-1:0]       M_AXI_AWADDR;
    wire [7:0]                  M_AXI_AWLEN;
    wire [2:0]                  M_AXI_AWSIZE;
    wire [1:0]                  M_AXI_AWBURST;
    wire [3:0]                  M_AXI_AWCACHE;
    wire [2:0]                  M_AXI_AWPROT;
    wire                        M_AXI_AWVALID;
    reg                         M_AXI_AWREADY;

    wire [AXI_DATA_WIDTH-1:0]   M_AXI_WDATA;
    wire [AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB;
    wire                        M_AXI_WLAST, M_AXI_WVALID;
    reg                         M_AXI_WREADY;

    reg  [AXI_ID_WIDTH-1:0]     M_AXI_BID;
    reg  [1:0]                  M_AXI_BRESP;
    reg                         M_AXI_BVALID;
    wire                        M_AXI_BREADY;

    wire [AXI_ID_WIDTH-1:0]     M_AXI_ARID;
    wire [ADDR_WIDTH-1:0]       M_AXI_ARADDR;
    wire [7:0]                  M_AXI_ARLEN;
    wire [2:0]                  M_AXI_ARSIZE;
    wire [1:0]                  M_AXI_ARBURST;
    wire [3:0]                  M_AXI_ARCACHE;
    wire [2:0]                  M_AXI_ARPROT;
    wire                        M_AXI_ARVALID;
    reg                         M_AXI_ARREADY;

    reg  [AXI_ID_WIDTH-1:0]     M_AXI_RID;
    reg  [AXI_DATA_WIDTH-1:0]   M_AXI_RDATA;
    reg  [1:0]                  M_AXI_RRESP;
    reg                         M_AXI_RLAST, M_AXI_RVALID;
    wire                        M_AXI_RREADY;

    // =========================================================================
    // DUT
    // =========================================================================
    ascon_dma #(
        .ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH), .RD_FIFO_DEPTH(RD_FIFO_DEPTH),
        .WR_FIFO_DEPTH(WR_FIFO_DEPTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .src_addr(src_addr), .dst_addr(dst_addr),
        .byte_len(byte_len), .burst_len(burst_len),
        .dma_start(dma_start), .dma_soft_rst(dma_soft_rst),
        .dma_busy(dma_busy), .dma_done(dma_done), .dma_error(dma_error),
        .status_rd_done(status_rd_done), .status_wr_done(status_wr_done),
        .status_rd_error(status_rd_error), .status_wr_error(status_wr_error),
        .status_fifo_overflow(status_fifo_overflow),
        .dma_err_addr(dma_err_addr),
        .core_ptext_0(core_ptext_0), .core_ptext_1(core_ptext_1),
        .core_data_valid(core_data_valid), .core_data_ready(core_data_ready),
        .core_start(core_start), .core_busy(core_busy), .core_done(core_done),
        .core_ctext_0(core_ctext_0), .core_ctext_1(core_ctext_1),
        .core_tag_0(core_tag_0), .core_tag_1(core_tag_1),
        .core_tag_2(core_tag_2), .core_tag_3(core_tag_3),
        .M_AXI_AWID(M_AXI_AWID), .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN), .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST), .M_AXI_AWCACHE(M_AXI_AWCACHE),
        .M_AXI_AWPROT(M_AXI_AWPROT), .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA), .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST), .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BID(M_AXI_BID), .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID), .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARID(M_AXI_ARID), .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN), .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST), .M_AXI_ARCACHE(M_AXI_ARCACHE),
        .M_AXI_ARPROT(M_AXI_ARPROT), .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RID(M_AXI_RID), .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP), .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID), .M_AXI_RREADY(M_AXI_RREADY)
    );

    // =========================================================================
    // Memory model — 256 × 64-bit
    //   Địa chỉ word = addr[10:3], đảm bảo không out of bounds
    // =========================================================================
    reg [63:0] mem [0:MEM_SIZE-1];

    function [7:0] addr2idx;
        input [ADDR_WIDTH-1:0] a;
        begin addr2idx = a[10:3]; end
    endfunction

    // =========================================================================
    // AXI READ SLAVE — FSM
    //   RS_IDLE : đợi ARVALID, sau delay → ARREADY, chuyển RS_DATA
    //   RS_DATA : giữ RVALID=1 đến khi RREADY, xử lý multi-beat nếu ARLEN>0
    // =========================================================================
    localparam RS_IDLE=1'b0, RS_DATA=1'b1;
    reg        rd_state;
    reg [3:0]  rd_dly_cnt;
    reg [3:0]  axi_rd_delay;
    reg        force_rd_error;
    reg [ADDR_WIDTH-1:0] rd_addr_lat;
    reg [7:0]  rd_beats_rem;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RS_IDLE;
            M_AXI_ARREADY <= 0; M_AXI_RVALID <= 0;
            M_AXI_RDATA <= 0; M_AXI_RRESP <= 0;
            M_AXI_RLAST <= 0; M_AXI_RID <= 0;
            rd_dly_cnt <= 0; rd_beats_rem <= 0;
        end else begin
            M_AXI_ARREADY <= 0;
            case (rd_state)
                RS_IDLE: begin
                    M_AXI_RVALID <= 0;
                    if (M_AXI_ARVALID) begin
                        if (rd_dly_cnt < axi_rd_delay) begin
                            rd_dly_cnt <= rd_dly_cnt + 1;
                        end else begin
                            M_AXI_ARREADY <= 1;
                            rd_addr_lat   <= M_AXI_ARADDR;
                            rd_beats_rem  <= M_AXI_ARLEN;
                            rd_dly_cnt    <= 0;
                            rd_state      <= RS_DATA;
                        end
                    end
                end
                RS_DATA: begin
                    // Present data — giữ cho đến khi accept
                    M_AXI_RVALID <= 1;
                    M_AXI_RID    <= M_AXI_ARID;
                    M_AXI_RRESP  <= force_rd_error ? 2'b10 : 2'b00;
                    M_AXI_RDATA  <= mem[addr2idx(rd_addr_lat)];
                    M_AXI_RLAST  <= (rd_beats_rem == 0);
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        if (rd_beats_rem == 0) begin
                            M_AXI_RVALID <= 0;
                            M_AXI_RLAST  <= 0;
                            rd_state     <= RS_IDLE;
                        end else begin
                            rd_addr_lat  <= rd_addr_lat + 8;
                            rd_beats_rem <= rd_beats_rem - 1;
                            M_AXI_RDATA  <= mem[addr2idx(rd_addr_lat + 8)];
                            M_AXI_RLAST  <= (rd_beats_rem == 1);
                        end
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // AXI WRITE SLAVE — FSM
    //
    // FIX KQUAN TRỌNG:
    //   dma_write_engine có logic nonblocking trong WR_DATA:
    //     if (!WVALID)  → set WDATA, WVALID=1, WLAST, word_half=0  [nhánh A]
    //     if (WVALID && WREADY) → clear WVALID, advance beat  [nhánh B]
    //   Nếu WREADY=1 từ trước (pre-asserted), cycle mà WVALID vừa set:
    //     nonblocking: WVALID_old=0 → nhánh A chạy (WVALID<=1)
    //                  WVALID_old=0 → nhánh B KHÔNG chạy (0 && 1 = 0)
    //   Nhưng vấn đề là word_half bị clear về 0 trong nhánh A (line 179),
    //   cycle tiếp theo word_half=0, WVALID=1, WREADY=1 → nhánh B chạy OK.
    //   Vậy RTL đúng nếu WREADY được giữ =1 liên tục.
    //
    //   Thực sự bug là slave của TB: sau WLAST, slave clear WREADY ngay,
    //   nhưng chưa gửi BVALID. DMA engine chuyển WR_RESP, assert BREADY,
    //   nhưng BVALID=0 → kẹt mãi.
    //   Slave cần chắc chắn: khi WLAST accept, BÁO BVALID trong cycle tiếp.
    //
    //   States: WS_IDLE → WS_ADDR → WS_DATA → WS_RESP
    //   WS_RESP: giữ BVALID=1 cho đến khi BREADY (từ DMA engine).
    // =========================================================================
    localparam WS_IDLE=2'd0, WS_ADDR=2'd1, WS_DATA=2'd2, WS_RESP=2'd3;
    reg [1:0]  wr_state;
    reg [3:0]  wr_dly_cnt;
    reg [3:0]  axi_wr_delay;
    reg        force_wr_error;
    reg [ADDR_WIDTH-1:0] wr_addr_lat;
    reg [2:0]  wr_beat_idx;   // 0..2

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WS_IDLE;
            M_AXI_AWREADY <= 0; M_AXI_WREADY <= 0;
            M_AXI_BVALID  <= 0; M_AXI_BRESP  <= 0; M_AXI_BID <= 0;
            wr_dly_cnt <= 0; wr_beat_idx <= 0;
        end else begin
            M_AXI_AWREADY <= 0;   // default: 1-cycle pulse only

            case (wr_state)

                // ── Đợi AWVALID, apply delay ──────────────────────────────────
                WS_IDLE: begin
                    M_AXI_WREADY <= 0;
                    M_AXI_BVALID <= 0;
                    if (M_AXI_AWVALID) begin
                        if (wr_dly_cnt < axi_wr_delay) begin
                            wr_dly_cnt <= wr_dly_cnt + 1;
                        end else begin
                            // Accept AW
                            M_AXI_AWREADY <= 1;
                            wr_addr_lat   <= M_AXI_AWADDR;
                            wr_beat_idx   <= 0;
                            wr_dly_cnt    <= 0;
                            wr_state      <= WS_ADDR;
                        end
                    end
                end

                // ── 1-cycle gap sau AWREADY ───────────────────────────────────
                // Đợi DMA engine chuyển sang WR_DATA trước khi assert WREADY.
                // Điều này tránh WREADY=1 trước khi WVALID đến.
                WS_ADDR: begin
                    M_AXI_AWREADY <= 0;
                    // Không assert WREADY vội — đợi WVALID trước
                    wr_state <= WS_DATA;
                end

                // ── Accept write data beats ───────────────────────────────────
                // QUAN TRỌNG: WREADY chỉ assert khi thấy WVALID=1
                // Tránh pre-asserted WREADY gây conflict với RTL logic
                WS_DATA: begin
                    // Assert WREADY chỉ khi có data để accept
                    M_AXI_WREADY <= M_AXI_WVALID;  // mirror WVALID với 1-cycle

                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        // Ghi vào memory
                        mem[addr2idx(wr_addr_lat) + {{5{1'b0}}, wr_beat_idx}] <= M_AXI_WDATA;
                        $display("[MEM-WR @%0t] beat%0d addr=%08h[%0d] data=%016h last=%b",
                                 $time, wr_beat_idx,
                                 wr_addr_lat, addr2idx(wr_addr_lat)+wr_beat_idx,
                                 M_AXI_WDATA, M_AXI_WLAST);

                        if (M_AXI_WLAST) begin
                            M_AXI_WREADY <= 0;
                            wr_state     <= WS_RESP;
                        end else begin
                            wr_beat_idx <= wr_beat_idx + 1;
                        end
                    end
                end

                // ── Gửi BRESP, đợi DMA accept ────────────────────────────────
                WS_RESP: begin
                    M_AXI_BVALID <= 1;
                    M_AXI_BRESP  <= force_wr_error ? 2'b10 : 2'b00;
                    M_AXI_BID    <= M_AXI_AWID;
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BVALID <= 0;
                        wr_state     <= WS_IDLE;
                    end
                end

            endcase
        end
    end

    // =========================================================================
    // ASCON CORE Mock
    //   core_start → sau CORE_LATENCY cycles → core_done, ctext=~ptext
    // =========================================================================
    reg [7:0]  core_lat_cnt;
    reg        core_running;
    reg [31:0] saved_p0, saved_p1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_busy <= 0; core_done <= 0; core_data_ready <= 1;
            core_lat_cnt <= 0; core_running <= 0;
            core_ctext_0 <= 0; core_ctext_1 <= 0;
            core_tag_0 <= 0; core_tag_1 <= 0; core_tag_2 <= 0; core_tag_3 <= 0;
        end else begin
            core_done <= 0;
            if (core_start && !core_running) begin
                core_running <= 1; core_busy <= 1; core_lat_cnt <= 0;
                saved_p0 <= core_ptext_0; saved_p1 <= core_ptext_1;
                $display("[CORE @%0t] START ptext={%08h,%08h}",
                         $time, core_ptext_0, core_ptext_1);
            end
            if (core_running) begin
                core_lat_cnt <= core_lat_cnt + 1;
                if (core_lat_cnt == CORE_LATENCY - 1) begin
                    core_running <= 0; core_busy <= 0; core_done <= 1;
                    core_ctext_0 <= ~saved_p0;  core_ctext_1 <= ~saved_p1;
                    core_tag_0   <= 32'hDEADBEEF; core_tag_1 <= 32'hCAFEBABE;
                    core_tag_2   <= 32'h01234567; core_tag_3 <= 32'h89ABCDEF;
                    $display("[CORE @%0t] DONE ctext={%08h,%08h} tag={%08h,%08h,%08h,%08h}",
                        $time, ~saved_p0, ~saved_p1,
                        32'hDEADBEEF, 32'hCAFEBABE, 32'h01234567, 32'h89ABCDEF);
                end
            end
        end
    end

    // =========================================================================
    // Scoreboard
    // =========================================================================
    integer pass_count, fail_count;
    reg     done_seen, error_seen;

    always @(posedge clk) begin
        if (dma_done)  done_seen  <= 1;
        if (dma_error) error_seen <= 1;
    end

    task check;
        input [255:0] name;
        input         cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  [PASS] %s -- %s", name, msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s -- %s  (@%0t)", name, msg, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_cycles;
        input integer n; integer i;
        begin for (i=0; i<n; i=i+1) @(posedge clk); end
    endtask

    task pulse_dma_start;
        begin
            @(posedge clk); #1 dma_start = 1;
            @(posedge clk); #1 dma_start = 0;
        end
    endtask

    task pulse_soft_rst;
        begin
            @(posedge clk); #1 dma_soft_rst = 1;
            @(posedge clk); #1 dma_soft_rst = 0;
        end
    endtask

    task wait_dma_done;
        input integer timeout_cyc;
        integer i;
        begin
            i = 0;
            while (!done_seen && i < timeout_cyc) begin
                @(posedge clk); i = i + 1;
            end
            if (i >= timeout_cyc)
                $display("[WARN] wait_dma_done: TIMEOUT after %0d cycles!", timeout_cyc);
        end
    endtask

    task apply_reset;
        integer i;
        begin
            rst_n = 0; dma_start = 0; dma_soft_rst = 0;
            src_addr = 0; dst_addr = 0; byte_len = 8; burst_len = 0;
            force_rd_error = 0; force_wr_error = 0;
            axi_rd_delay = 0; axi_wr_delay = 0;
            done_seen = 0; error_seen = 0;
            for (i=0; i<MEM_SIZE; i=i+1) mem[i] = 64'h0;
            repeat(6) @(posedge clk);
            #1 rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask

    // =========================================================================
    // MAIN TEST
    // =========================================================================
    initial begin
        $dumpfile("tb_ascon_dma.vcd");
        $dumpvars(0, tb_ascon_dma);
        pass_count = 0; fail_count = 0;

        $display("================================================================");
        $display("   ASCON DMA Testbench v3.0 -- RISC-V SoC");
        $display("================================================================");

        // ─── TC1: Reset & Idle ────────────────────────────────────────────────
        $display("\n[TC1] Reset and Idle state check");
        apply_reset;
        check("TC1", dma_busy      === 1'b0, "dma_busy=0 after reset");
        check("TC1", dma_done      === 1'b0, "dma_done=0 after reset");
        check("TC1", dma_error     === 1'b0, "dma_error=0 after reset");
        check("TC1", M_AXI_ARVALID === 1'b0, "AXI AR silent after reset");
        check("TC1", M_AXI_AWVALID === 1'b0, "AXI AW silent after reset");
        check("TC1", M_AXI_WVALID  === 1'b0, "AXI W  silent after reset");

        // ─── TC2: Normal full pipeline ────────────────────────────────────────
        // src: addr=0x000 → idx=0
        // dst: addr=0x100 → idx=32 (0x100>>3 = 0x20 = 32)
        // Plaintext: 0x00010203_04050607
        // Expected ctext: ~ptext = 0xFFFEFDFC_FBFAF9F8
        // Beat0 = {ctext_0, ctext_1} = {FFFEFDFC, FBFAF9F8} → 0xFFFEFDFCFBFAF9F8
        // Beat1 = {tag_0,   tag_1}   = {DEADBEEF, CAFEBABE} → 0xDEADBEEFCAFEBABE
        // Beat2 = {tag_2,   tag_3}   = {01234567, 89ABCDEF} → 0x0123456789ABCDEF
        $display("\n[TC2] Normal pipeline: src=0x000 dst=0x100");
        apply_reset;
        mem[8'h00] = 64'h00010203_04050607;
        src_addr = 32'h0000_0000; dst_addr = 32'h0000_0100;
        byte_len = 8; burst_len = 0;

        pulse_dma_start;
        @(posedge clk);
        check("TC2", dma_busy === 1'b1, "dma_busy=1 after start");

        wait_dma_done(300);
        wait_cycles(3);
        check("TC2", done_seen      === 1'b1, "dma_done pulse seen");
        check("TC2", error_seen     === 1'b0, "no dma_error");
        check("TC2", status_rd_done === 1'b1, "status_rd_done=1");
        check("TC2", status_wr_done === 1'b1, "status_wr_done=1");
        check("TC2", dma_busy       === 1'b0, "dma_busy=0 after done");

        begin : TC2_mem
            reg [63:0] b0, b1, b2;
            b0 = 64'hFFFEFDFC_FBFAF9F8;
            b1 = 64'hDEADBEEF_CAFEBABE;
            b2 = 64'h01234567_89ABCDEF;
            check("TC2", mem[8'h20] === b0, "Beat0: {ctext_0,ctext_1} correct");
            check("TC2", mem[8'h21] === b1, "Beat1: {tag_0,tag_1} correct");
            check("TC2", mem[8'h22] === b2, "Beat2: {tag_2,tag_3} correct");
        end

        // ─── TC3: AXI Read Error ─────────────────────────────────────────────
        $display("\n[TC3] AXI Read Error: RRESP=SLVERR (2'b10)");
        apply_reset;
        src_addr = 32'h0000_0008; dst_addr = 32'h0000_0108;
        force_rd_error = 1;
        pulse_dma_start;
        wait_dma_done(150);
        wait_cycles(2);
        check("TC3", done_seen       === 1'b1, "dma_done seen on error path");
        check("TC3", error_seen      === 1'b1, "dma_error seen");
        check("TC3", status_rd_error === 1'b1, "status_rd_error=1");
        check("TC3", status_wr_done  === 1'b0, "write NOT started after rd error");

        // ─── TC4: AXI Write Error ────────────────────────────────────────────
        $display("\n[TC4] AXI Write Error: BRESP=SLVERR (2'b10)");
        apply_reset;
        mem[8'h02] = 64'hAABBCCDD_EEFF0011;
        src_addr = 32'h0000_0010; dst_addr = 32'h0000_0110;
        force_wr_error = 1;
        pulse_dma_start;
        wait_dma_done(300);
        wait_cycles(2);
        check("TC4", done_seen       === 1'b1, "dma_done seen on wr error");
        check("TC4", error_seen      === 1'b1, "dma_error seen");
        check("TC4", status_wr_error === 1'b1, "status_wr_error=1");
        check("TC4", dma_err_addr    === 32'h0000_0110, "dma_err_addr=dst_addr");

        // ─── TC5: Soft Reset while BUSY ──────────────────────────────────────
        $display("\n[TC5] Soft Reset while DMA in-flight");
        apply_reset;
        mem[8'h03] = 64'h1122334455667788;
        src_addr = 32'h0000_0018; dst_addr = 32'h0000_0118;
        axi_rd_delay = 8;  // giữ DMA kẹt ở RD_ADDR
        pulse_dma_start;
        wait_cycles(3);
        check("TC5", dma_busy === 1'b1, "dma_busy=1 before soft reset");
        pulse_soft_rst;
        wait_cycles(3);
        check("TC5", dma_busy  === 1'b0, "dma_busy=0 after soft reset");
        check("TC5", dma_error === 1'b0, "no residual error after soft reset");

        // Restart
        axi_rd_delay = 0; done_seen = 0; error_seen = 0;
        wait_cycles(2);
        pulse_dma_start;
        wait_dma_done(300);
        wait_cycles(2);
        check("TC5", done_seen  === 1'b1, "Clean restart after soft reset OK");
        check("TC5", error_seen === 1'b0, "No error on restart");

        // ─── TC6: Back-to-back ────────────────────────────────────────────────
        $display("\n[TC6] Back-to-back transactions (2x)");
        apply_reset;
        mem[8'h04] = 64'hDEADBEEF_CAFEBABE;
        src_addr = 32'h0000_0020; dst_addr = 32'h0000_0120;
        pulse_dma_start;
        wait_dma_done(300); wait_cycles(2);
        check("TC6", done_seen  === 1'b1, "Txn-1 done");
        check("TC6", error_seen === 1'b0, "Txn-1 no error");

        done_seen = 0; error_seen = 0;
        mem[8'h05] = 64'h01234567_89ABCDEF;
        src_addr = 32'h0000_0028; dst_addr = 32'h0000_0128;
        wait_cycles(2);
        pulse_dma_start;
        wait_dma_done(300); wait_cycles(2);
        check("TC6", done_seen  === 1'b1, "Txn-2 done");
        check("TC6", error_seen === 1'b0, "Txn-2 no error");

        // ─── TC7: AXI Backpressure ────────────────────────────────────────────
        $display("\n[TC7] AXI backpressure: ARREADY delay=5, AWREADY delay=4");
        apply_reset;
        mem[8'h06] = 64'hFEDCBA98_76543210;
        src_addr = 32'h0000_0030; dst_addr = 32'h0000_0130;
        axi_rd_delay = 5; axi_wr_delay = 4;
        pulse_dma_start;
        wait_dma_done(500); wait_cycles(2);
        check("TC7", done_seen  === 1'b1, "dma_done despite backpressure");
        check("TC7", error_seen === 1'b0, "no errors with backpressure");

        // ─── TC8: AXI AR protocol ─────────────────────────────────────────────
        $display("\n[TC8] AXI AR channel: ARSIZE/ARBURST/ARLEN/ARCACHE/ARPROT");
        apply_reset;
        mem[8'h07] = 64'h12345678_9ABCDEF0;
        src_addr = 32'h0000_0038; dst_addr = 32'h0000_0138;
        burst_len = 8'h00; axi_rd_delay = 3;
        pulse_dma_start;
        begin : tc8_ar
            integer t; t = 0;
            while (!M_AXI_ARVALID && t < 50) begin @(posedge clk); t=t+1; end
        end
        check("TC8", M_AXI_ARVALID === 1'b1,         "ARVALID asserted");
        check("TC8", M_AXI_ARADDR  === 32'h0000_0038, "ARADDR = src_addr");
        check("TC8", M_AXI_ARLEN   === 8'h00,          "ARLEN=0 (1 beat)");
        check("TC8", M_AXI_ARSIZE  === 3'b011,          "ARSIZE=3 (8B/beat)");
        check("TC8", M_AXI_ARBURST === 2'b01,           "ARBURST=INCR");
        check("TC8", M_AXI_ARCACHE === 4'b0010,         "ARCACHE=0010");
        check("TC8", M_AXI_ARPROT  === 3'b000,          "ARPROT=000");
        wait_dma_done(300); wait_cycles(2);
        check("TC8", done_seen === 1'b1, "TC8 pipeline complete");

        // ─── TC9: AXI AW protocol ─────────────────────────────────────────────
        $display("\n[TC9] AXI AW channel: AWLEN/AWSIZE/AWBURST/AWCACHE/WSTRB");
        apply_reset;
        mem[8'h08] = 64'h0A0B0C0D_0E0F1011;
        src_addr = 32'h0000_0040; dst_addr = 32'h0000_0140;
        axi_wr_delay = 2;
        pulse_dma_start;
        begin : tc9_aw
            integer t; t = 0;
            while (!M_AXI_AWVALID && t < 300) begin @(posedge clk); t=t+1; end
        end
        if (M_AXI_AWVALID) begin
            check("TC9", M_AXI_AWLEN   === 8'h02,          "AWLEN=2 (3 beats)");
            check("TC9", M_AXI_AWSIZE  === 3'b011,          "AWSIZE=3 (8B/beat)");
            check("TC9", M_AXI_AWBURST === 2'b01,           "AWBURST=INCR");
            check("TC9", M_AXI_AWADDR  === 32'h0000_0140,   "AWADDR=dst_addr");
            check("TC9", M_AXI_AWCACHE === 4'b0010,         "AWCACHE=0010");
            check("TC9", M_AXI_WSTRB   === 8'hFF,           "WSTRB=0xFF");
        end else begin
            check("TC9", 1'b0, "AWVALID never asserted");
        end
        wait_dma_done(300); wait_cycles(2);
        check("TC9", done_seen  === 1'b1, "TC9 pipeline complete");
        check("TC9", error_seen === 1'b0, "TC9 no errors");

        // ─── TC10: busy/done handshake ────────────────────────────────────────
        $display("\n[TC10] dma_busy/dma_done timing handshake");
        apply_reset;
        mem[8'h09] = 64'hAAAAAAAA_55555555;
        src_addr = 32'h0000_0048; dst_addr = 32'h0000_0148;
        pulse_dma_start;
        @(posedge clk);
        check("TC10", dma_busy === 1'b1, "dma_busy=1 immediately after start");
        wait_dma_done(300);
        check("TC10", done_seen === 1'b1, "dma_done pulse captured");
        wait_cycles(2);
        check("TC10", dma_busy === 1'b0, "dma_busy=0 after done");
        check("TC10", dma_done === 1'b0, "dma_done cleared (1-cycle pulse)");

        // ─── Summary ──────────────────────────────────────────────────────────
        $display("\n================================================================");
        $display("   TEST RESULTS SUMMARY");
        $display("================================================================");
        $display("   PASS : %0d", pass_count);
        $display("   FAIL : %0d", fail_count);
        if (fail_count == 0)
            $display("   *** ALL TESTS PASSED *** ");
        else
            $display("   *** %0d TEST(S) FAILED ***", fail_count);
        $display("================================================================");
        #50; $finish;
    end

    // =========================================================================
    // Watchdog
    // =========================================================================
    initial begin #1_500_000; $display("[WATCHDOG] Timeout."); $finish; end

    // =========================================================================
    // Transaction monitor
    // =========================================================================
    always @(posedge clk) begin
        if (dma_start)
            $display("[MON @%0t] DMA START src=%08h dst=%08h", $time, src_addr, dst_addr);
        if (dma_done)
            $display("[MON @%0t] DMA DONE  err=%b rd_done=%b wr_done=%b",
                     $time, dma_error, status_rd_done, status_wr_done);
        if (dma_error && dma_busy)
            $display("[MON @%0t] DMA ERROR err_addr=%08h rd=%b wr=%b",
                     $time, dma_err_addr, status_rd_error, status_wr_error);
        if (M_AXI_ARVALID && M_AXI_ARREADY)
            $display("[AXI @%0t] AR  addr=%08h len=%0d size=%0d",
                     $time, M_AXI_ARADDR, M_AXI_ARLEN, M_AXI_ARSIZE);
        if (M_AXI_RVALID && M_AXI_RREADY)
            $display("[AXI @%0t] R   data=%016h last=%b resp=%0d",
                     $time, M_AXI_RDATA, M_AXI_RLAST, M_AXI_RRESP);
        if (M_AXI_AWVALID && M_AXI_AWREADY)
            $display("[AXI @%0t] AW  addr=%08h len=%0d size=%0d",
                     $time, M_AXI_AWADDR, M_AXI_AWLEN, M_AXI_AWSIZE);
        if (M_AXI_WVALID && M_AXI_WREADY)
            $display("[AXI @%0t] W   data=%016h last=%b strb=%02h",
                     $time, M_AXI_WDATA, M_AXI_WLAST, M_AXI_WSTRB);
        if (M_AXI_BVALID && M_AXI_BREADY)
            $display("[AXI @%0t] B   resp=%0d (bid=%0d)", $time, M_AXI_BRESP, M_AXI_BID);
    end

endmodule