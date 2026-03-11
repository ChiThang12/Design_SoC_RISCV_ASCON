// ============================================================================
// cpu_core.v (riscv_soc_top_cached) — v3.3
//
// Fix so voi v3.2:
//   [UPDATE] Doi axi4_crossbar (2M) -> axi4_crossbar_3m4s (3M)
//            M2 (DMA) duoc tie-off trong module nay vi day la CPU-only top.
//            Khi tich hop vao riscv_ascon_soc_top_v2, M2 se duoc noi DMA that.
//
// Giu nguyen cac fix tu v3.2:
//   [BUG 1] S2/S3 stub bvalid=0 mai mai -> deadlock DCache: da fix bang FSM
//   [BUG 2] s2_rvalid combinational pass-through: da fix bang 1-cycle reg
//   [BUG 3] S1 RID/BID lay wire hien tai: da fix bang latch tai handshake
// ============================================================================

`include "cpu/riscv_cpu_core_v2.v"
`include "cpu/interface/icache/icache_top.v"
`include "cpu/interface/dcache/dcache_top.v"
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/memory_axi4full/data_mem_axi_slave.v"
`include "cpu/interconnect/axi4_crossbar_3m5s.v"

module riscv_soc_top_cached (
    input wire clk,
    input wire rst_n,

    output wire [31:0] icache_hits,
    output wire [31:0] icache_misses,
    output wire [31:0] dcache_hits,
    output wire [31:0] dcache_misses,
    output wire [31:0] dcache_writes
);

    localparam ID_WIDTH = 4;

    wire rst = ~rst_n;

    // ========================================================================
    // CPU <-> ICache / DCache
    // ========================================================================
    wire [31:0] cpu_imem_addr,  cpu_imem_rdata;
    wire        cpu_imem_valid, cpu_imem_ready;

    wire [31:0] cpu_dcache_addr,  cpu_dcache_wdata, cpu_dcache_rdata;
    wire [3:0]  cpu_dcache_wstrb;
    wire        cpu_dcache_req,   cpu_dcache_we,    cpu_dcache_ready;

    wire [31:0] dcache_current_addr, dcache_current_data;
    wire        dcache_current_valid;

    // ========================================================================
    // M0 (ICache) <-> Crossbar
    // ========================================================================
    wire [ID_WIDTH-1:0] m0_arid,  m0_rid,  m0_awid,  m0_bid;
    wire [31:0] m0_araddr, m0_rdata, m0_awaddr, m0_wdata;
    wire [7:0]  m0_arlen,  m0_awlen;
    wire [2:0]  m0_arsize, m0_awsize, m0_arprot, m0_awprot;
    wire [1:0]  m0_arburst,m0_awburst,m0_rresp,  m0_bresp;
    wire [3:0]  m0_wstrb;
    wire        m0_arvalid,m0_arready,m0_rvalid, m0_rready, m0_rlast;
    wire        m0_awvalid,m0_awready,m0_wvalid, m0_wready, m0_wlast;
    wire        m0_bvalid, m0_bready;

    // ========================================================================
    // M1 (DCache) <-> Crossbar
    // ========================================================================
    wire [ID_WIDTH-1:0] m1_arid,  m1_rid,  m1_awid,  m1_bid;
    wire [31:0] m1_araddr, m1_rdata, m1_awaddr, m1_wdata;
    wire [7:0]  m1_arlen,  m1_awlen;
    wire [2:0]  m1_arsize, m1_awsize, m1_arprot, m1_awprot;
    wire [1:0]  m1_arburst,m1_awburst,m1_rresp,  m1_bresp;
    wire [3:0]  m1_wstrb;
    wire        m1_arvalid,m1_arready,m1_rvalid, m1_rready, m1_rlast;
    wire        m1_awvalid,m1_awready,m1_wvalid, m1_wready, m1_wlast;
    wire        m1_bvalid, m1_bready;

    // ========================================================================
    // M2 (DMA) — tie-off trong module nay; crossbar xu ly DECERR tu dong
    // Khi tich hop vao riscv_ascon_soc_top_v2, M2 se duoc noi DMA that
    // ========================================================================
    wire [ID_WIDTH-1:0] m2_rid,  m2_bid;
    wire [31:0] m2_rdata;
    wire [1:0]  m2_rresp, m2_bresp;
    wire        m2_arready, m2_rvalid, m2_rlast;
    wire        m2_awready, m2_wready;
    wire        m2_bvalid;

    // ========================================================================
    // S0 (IMEM) <-> Crossbar
    // ========================================================================
    wire [ID_WIDTH-1:0] s0_arid,  s0_rid,  s0_awid,  s0_bid;
    wire [31:0] s0_araddr, s0_rdata, s0_awaddr, s0_wdata;
    wire [7:0]  s0_arlen,  s0_awlen;
    wire [2:0]  s0_arsize, s0_awsize, s0_arprot, s0_awprot;
    wire [1:0]  s0_arburst,s0_awburst,s0_rresp,  s0_bresp;
    wire [3:0]  s0_wstrb;
    wire        s0_arvalid,s0_arready,s0_rvalid, s0_rready, s0_rlast;
    wire        s0_awvalid,s0_awready,s0_wvalid, s0_wready, s0_wlast;
    wire        s0_bvalid, s0_bready;

    // ========================================================================
    // S1 (DMEM) <-> Crossbar
    // ========================================================================
    wire [ID_WIDTH-1:0] s1_arid,  s1_rid,  s1_awid,  s1_bid;
    wire [31:0] s1_araddr, s1_rdata, s1_awaddr, s1_wdata;
    wire [7:0]  s1_arlen,  s1_awlen;
    wire [2:0]  s1_arsize, s1_awsize, s1_arprot, s1_awprot;
    wire [1:0]  s1_arburst,s1_awburst,s1_rresp,  s1_bresp;
    wire [3:0]  s1_wstrb;
    wire        s1_arvalid,s1_arready,s1_rvalid, s1_rready, s1_rlast;
    wire        s1_awvalid,s1_awready,s1_wvalid, s1_wready, s1_wlast;
    wire        s1_bvalid, s1_bready;

    // ========================================================================
    // S2 (ASCON placeholder) <-> Crossbar
    // ========================================================================
    wire [ID_WIDTH-1:0] s2_arid,  s2_rid,  s2_awid,  s2_bid;
    wire [31:0] s2_araddr, s2_rdata, s2_awaddr, s2_wdata;
    wire [7:0]  s2_arlen,  s2_awlen;
    wire [2:0]  s2_arsize, s2_awsize, s2_arprot, s2_awprot;
    wire [1:0]  s2_arburst,s2_awburst,s2_rresp,  s2_bresp;
    wire [3:0]  s2_wstrb;
    wire        s2_arvalid,s2_arready,s2_rvalid, s2_rready, s2_rlast;
    wire        s2_awvalid,s2_awready,s2_wvalid, s2_wready, s2_wlast;
    wire        s2_bvalid, s2_bready;

    // ========================================================================
    // S3 (SoC Ctrl placeholder) <-> Crossbar
    // ========================================================================
    wire [ID_WIDTH-1:0] s3_arid,  s3_rid,  s3_awid,  s3_bid;
    wire [31:0] s3_araddr, s3_rdata, s3_awaddr, s3_wdata;
    wire [7:0]  s3_arlen,  s3_awlen;
    wire [2:0]  s3_arsize, s3_awsize, s3_arprot, s3_awprot;
    wire [1:0]  s3_arburst,s3_awburst,s3_rresp,  s3_bresp;
    wire [3:0]  s3_wstrb;
    wire        s3_arvalid,s3_arready,s3_rvalid, s3_rready, s3_rlast;
    wire        s3_awvalid,s3_awready,s3_wvalid, s3_wready, s3_wlast;
    wire        s3_bvalid, s3_bready;

    // ========================================================================
    // S2 Stub — ASCON placeholder
    // [BUG 1 FIX] Write FSM: tao B response dung AXI4 spec (khong deadlock)
    // [BUG 2 FIX] 1-cycle register cho RVALID (khong combinational pass)
    // ========================================================================
    assign s2_arready = 1'b1;
    assign s2_rid     = s2_arid;
    assign s2_rdata   = 32'hDEAD_BEEF;
    assign s2_rresp   = 2'b10;   // SLVERR
    assign s2_rlast   = 1'b1;

    reg s2_rvalid_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s2_rvalid_r <= 1'b0;
        else        s2_rvalid_r <= s2_arvalid & s2_arready;
    end
    assign s2_rvalid = s2_rvalid_r;

    localparam S2_WR_IDLE = 2'b00, S2_WR_DATA = 2'b01, S2_WR_RESP = 2'b10;
    reg [1:0]          s2_wr_state;
    reg [ID_WIDTH-1:0] s2_bid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_wr_state <= S2_WR_IDLE;
            s2_bid_r    <= {ID_WIDTH{1'b0}};
        end else begin
            case (s2_wr_state)
                S2_WR_IDLE: if (s2_awvalid)                    begin s2_bid_r <= s2_awid; s2_wr_state <= S2_WR_DATA; end
                S2_WR_DATA: if (s2_wvalid && s2_wlast)         s2_wr_state <= S2_WR_RESP;
                S2_WR_RESP: if (s2_bready)                     s2_wr_state <= S2_WR_IDLE;
                default:    s2_wr_state <= S2_WR_IDLE;
            endcase
        end
    end

    assign s2_awready = (s2_wr_state == S2_WR_IDLE);
    assign s2_wready  = (s2_wr_state == S2_WR_DATA);
    assign s2_bid     = s2_bid_r;
    assign s2_bresp   = 2'b10;
    assign s2_bvalid  = (s2_wr_state == S2_WR_RESP);

    // ========================================================================
    // S3 Stub — SoC Ctrl placeholder
    // [BUG 1 FIX] Write FSM tuong tu S2
    // ========================================================================
    assign s3_arready = 1'b1;
    assign s3_rid     = s3_arid;
    assign s3_rdata   = 32'hDEAD_BEEF;
    assign s3_rresp   = 2'b10;
    assign s3_rlast   = 1'b1;

    reg s3_rvalid_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s3_rvalid_r <= 1'b0;
        else        s3_rvalid_r <= s3_arvalid & s3_arready;
    end
    assign s3_rvalid = s3_rvalid_r;

    localparam S3_WR_IDLE = 2'b00, S3_WR_DATA = 2'b01, S3_WR_RESP = 2'b10;
    reg [1:0]          s3_wr_state;
    reg [ID_WIDTH-1:0] s3_bid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_wr_state <= S3_WR_IDLE;
            s3_bid_r    <= {ID_WIDTH{1'b0}};
        end else begin
            case (s3_wr_state)
                S3_WR_IDLE: if (s3_awvalid)              begin s3_bid_r <= s3_awid; s3_wr_state <= S3_WR_DATA; end
                S3_WR_DATA: if (s3_wvalid && s3_wlast)   s3_wr_state <= S3_WR_RESP;
                S3_WR_RESP: if (s3_bready)               s3_wr_state <= S3_WR_IDLE;
                default:    s3_wr_state <= S3_WR_IDLE;
            endcase
        end
    end

    assign s3_awready = (s3_wr_state == S3_WR_IDLE);
    assign s3_wready  = (s3_wr_state == S3_WR_DATA);
    assign s3_bid     = s3_bid_r;
    assign s3_bresp   = 2'b10;
    assign s3_bvalid  = (s3_wr_state == S3_WR_RESP);

    // ========================================================================
    // S1 RID/BID — [BUG 3 FIX] latch tai thoi diem handshake
    // ========================================================================
    reg [ID_WIDTH-1:0] s1_rid_r, s1_bid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_rid_r <= {ID_WIDTH{1'b0}};
            s1_bid_r <= {ID_WIDTH{1'b0}};
        end else begin
            if (s1_arvalid && s1_arready) s1_rid_r <= s1_arid;
            if (s1_awvalid && s1_awready) s1_bid_r <= s1_awid;
        end
    end

    assign s1_rid = s1_rid_r;
    assign s1_bid = s1_bid_r;

    // ========================================================================
    // 1. RISC-V CPU Core
    // ========================================================================
    riscv_cpu_core cpu (
        .clk          (clk),
        .rst          (rst),
        .imem_addr    (cpu_imem_addr),
        .imem_valid   (cpu_imem_valid),
        .imem_rdata   (cpu_imem_rdata),
        .imem_ready   (cpu_imem_ready),
        .dcache_addr  (cpu_dcache_addr),
        .dcache_wdata (cpu_dcache_wdata),
        .dcache_wstrb (cpu_dcache_wstrb),
        .dcache_req   (cpu_dcache_req),
        .dcache_we    (cpu_dcache_we),
        .dcache_rdata (cpu_dcache_rdata),
        .dcache_ready (cpu_dcache_ready)
    );

    // ========================================================================
    // 2. Instruction Cache — Master 0
    // ========================================================================
    icache_top #(.ID_WIDTH(ID_WIDTH)) icache (
        .clk         (clk),        .rst_n       (rst_n),
        .cpu_addr    (cpu_imem_addr),
        .cpu_req     (cpu_imem_valid),
        .cpu_rdata   (cpu_imem_rdata),
        .cpu_ready   (cpu_imem_ready),
        .flush       (1'b0),
        .mem_arid    (m0_arid),    .mem_araddr  (m0_araddr),
        .mem_arlen   (m0_arlen),   .mem_arsize  (m0_arsize),
        .mem_arburst (m0_arburst), .mem_arprot  (m0_arprot),
        .mem_arvalid (m0_arvalid), .mem_arready (m0_arready),
        .mem_rid     (m0_rid),     .mem_rdata   (m0_rdata),
        .mem_rresp   (m0_rresp),   .mem_rlast   (m0_rlast),
        .mem_rvalid  (m0_rvalid),  .mem_rready  (m0_rready),
        .mem_awid    (m0_awid),    .mem_awaddr  (m0_awaddr),
        .mem_awlen   (m0_awlen),   .mem_awsize  (m0_awsize),
        .mem_awburst (m0_awburst), .mem_awprot  (m0_awprot),
        .mem_awvalid (m0_awvalid), .mem_awready (m0_awready),
        .mem_wdata   (m0_wdata),   .mem_wstrb   (m0_wstrb),
        .mem_wlast   (m0_wlast),   .mem_wvalid  (m0_wvalid),
        .mem_wready  (m0_wready),
        .mem_bid     (m0_bid),     .mem_bresp   (m0_bresp),
        .mem_bvalid  (m0_bvalid),  .mem_bready  (m0_bready),
        .stat_hits   (icache_hits),
        .stat_misses (icache_misses)
    );

    // ========================================================================
    // 3. Data Cache — Master 1
    // ========================================================================
    dcache_top #(.ID_WIDTH(ID_WIDTH)) dcache (
        .clk           (clk),        .rst_n         (rst_n),
        .cpu_addr      (cpu_dcache_addr),
        .cpu_wdata     (cpu_dcache_wdata),
        .cpu_wstrb     (cpu_dcache_wstrb),
        .cpu_req       (cpu_dcache_req),
        .cpu_we        (cpu_dcache_we),
        .cpu_rdata     (cpu_dcache_rdata),
        .cpu_ready     (cpu_dcache_ready),
        .fence         (1'b0),
        .current_addr  (dcache_current_addr),
        .current_data  (dcache_current_data),
        .current_valid (dcache_current_valid),
        .mem_arid      (m1_arid),    .mem_araddr    (m1_araddr),
        .mem_arlen     (m1_arlen),   .mem_arsize    (m1_arsize),
        .mem_arburst   (m1_arburst), .mem_arprot    (m1_arprot),
        .mem_arvalid   (m1_arvalid), .mem_arready   (m1_arready),
        .mem_rid       (m1_rid),     .mem_rdata     (m1_rdata),
        .mem_rresp     (m1_rresp),   .mem_rlast     (m1_rlast),
        .mem_rvalid    (m1_rvalid),  .mem_rready    (m1_rready),
        .mem_awid      (m1_awid),    .mem_awaddr    (m1_awaddr),
        .mem_awlen     (m1_awlen),   .mem_awsize    (m1_awsize),
        .mem_awburst   (m1_awburst), .mem_awprot    (m1_awprot),
        .mem_awvalid   (m1_awvalid), .mem_awready   (m1_awready),
        .mem_wdata     (m1_wdata),   .mem_wstrb     (m1_wstrb),
        .mem_wlast     (m1_wlast),   .mem_wvalid    (m1_wvalid),
        .mem_wready    (m1_wready),
        .mem_bid       (m1_bid),     .mem_bresp     (m1_bresp),
        .mem_bvalid    (m1_bvalid),  .mem_bready    (m1_bready),
        .stat_hits     (dcache_hits),
        .stat_misses   (dcache_misses),
        .stat_writes   (dcache_writes)
    );

    // ========================================================================
    // 4. AXI4 Crossbar 3M×4S
    // M2 tie-off: arvalid/awvalid=0 -> crossbar khong gui request nao
    // ========================================================================
    axi4_crossbar_3m5s #(.ID_WIDTH(ID_WIDTH)) xbar (
        .clk            (clk),        .rst_n          (rst_n),
        // M0 — ICache
        .M0_AXI_ARID    (m0_arid),    .M0_AXI_ARADDR  (m0_araddr),
        .M0_AXI_ARLEN   (m0_arlen),   .M0_AXI_ARSIZE  (m0_arsize),
        .M0_AXI_ARBURST (m0_arburst), .M0_AXI_ARPROT  (m0_arprot),
        .M0_AXI_ARVALID (m0_arvalid), .M0_AXI_ARREADY (m0_arready),
        .M0_AXI_RID     (m0_rid),     .M0_AXI_RDATA   (m0_rdata),
        .M0_AXI_RRESP   (m0_rresp),   .M0_AXI_RLAST   (m0_rlast),
        .M0_AXI_RVALID  (m0_rvalid),  .M0_AXI_RREADY  (m0_rready),
        .M0_AXI_AWID    (m0_awid),    .M0_AXI_AWADDR  (m0_awaddr),
        .M0_AXI_AWLEN   (m0_awlen),   .M0_AXI_AWSIZE  (m0_awsize),
        .M0_AXI_AWBURST (m0_awburst), .M0_AXI_AWPROT  (m0_awprot),
        .M0_AXI_AWVALID (m0_awvalid), .M0_AXI_AWREADY (m0_awready),
        .M0_AXI_WDATA   (m0_wdata),   .M0_AXI_WSTRB   (m0_wstrb),
        .M0_AXI_WLAST   (m0_wlast),   .M0_AXI_WVALID  (m0_wvalid),
        .M0_AXI_WREADY  (m0_wready),
        .M0_AXI_BID     (m0_bid),     .M0_AXI_BRESP   (m0_bresp),
        .M0_AXI_BVALID  (m0_bvalid),  .M0_AXI_BREADY  (m0_bready),
        // M1 — DCache
        .M1_AXI_ARID    (m1_arid),    .M1_AXI_ARADDR  (m1_araddr),
        .M1_AXI_ARLEN   (m1_arlen),   .M1_AXI_ARSIZE  (m1_arsize),
        .M1_AXI_ARBURST (m1_arburst), .M1_AXI_ARPROT  (m1_arprot),
        .M1_AXI_ARVALID (m1_arvalid), .M1_AXI_ARREADY (m1_arready),
        .M1_AXI_RID     (m1_rid),     .M1_AXI_RDATA   (m1_rdata),
        .M1_AXI_RRESP   (m1_rresp),   .M1_AXI_RLAST   (m1_rlast),
        .M1_AXI_RVALID  (m1_rvalid),  .M1_AXI_RREADY  (m1_rready),
        .M1_AXI_AWID    (m1_awid),    .M1_AXI_AWADDR  (m1_awaddr),
        .M1_AXI_AWLEN   (m1_awlen),   .M1_AXI_AWSIZE  (m1_awsize),
        .M1_AXI_AWBURST (m1_awburst), .M1_AXI_AWPROT  (m1_awprot),
        .M1_AXI_AWVALID (m1_awvalid), .M1_AXI_AWREADY (m1_awready),
        .M1_AXI_WDATA   (m1_wdata),   .M1_AXI_WSTRB   (m1_wstrb),
        .M1_AXI_WLAST   (m1_wlast),   .M1_AXI_WVALID  (m1_wvalid),
        .M1_AXI_WREADY  (m1_wready),
        .M1_AXI_BID     (m1_bid),     .M1_AXI_BRESP   (m1_bresp),
        .M1_AXI_BVALID  (m1_bvalid),  .M1_AXI_BREADY  (m1_bready),
        // M2 — DMA tie-off (khong co DMA trong module nay)
        .M2_AXI_ARID    ({ID_WIDTH{1'b0}}), .M2_AXI_ARADDR  (32'h0),
        .M2_AXI_ARLEN   (8'h0),             .M2_AXI_ARSIZE  (3'h0),
        .M2_AXI_ARBURST (2'h0),             .M2_AXI_ARPROT  (3'h0),
        .M2_AXI_ARVALID (1'b0),             .M2_AXI_ARREADY (m2_arready),
        .M2_AXI_RID     (m2_rid),           .M2_AXI_RDATA   (m2_rdata),
        .M2_AXI_RRESP   (m2_rresp),         .M2_AXI_RLAST   (m2_rlast),
        .M2_AXI_RVALID  (m2_rvalid),        .M2_AXI_RREADY  (1'b1),
        .M2_AXI_AWID    ({ID_WIDTH{1'b0}}), .M2_AXI_AWADDR  (32'h0),
        .M2_AXI_AWLEN   (8'h0),             .M2_AXI_AWSIZE  (3'h0),
        .M2_AXI_AWBURST (2'h0),             .M2_AXI_AWPROT  (3'h0),
        .M2_AXI_AWVALID (1'b0),             .M2_AXI_AWREADY (m2_awready),
        .M2_AXI_WDATA   (32'h0),            .M2_AXI_WSTRB   (4'h0),
        .M2_AXI_WLAST   (1'b0),             .M2_AXI_WVALID  (1'b0),
        .M2_AXI_WREADY  (m2_wready),
        .M2_AXI_BID     (m2_bid),           .M2_AXI_BRESP   (m2_bresp),
        .M2_AXI_BVALID  (m2_bvalid),        .M2_AXI_BREADY  (1'b1),
        // S0 — IMEM
        .S0_AXI_ARID    (s0_arid),    .S0_AXI_ARADDR  (s0_araddr),
        .S0_AXI_ARLEN   (s0_arlen),   .S0_AXI_ARSIZE  (s0_arsize),
        .S0_AXI_ARBURST (s0_arburst), .S0_AXI_ARPROT  (s0_arprot),
        .S0_AXI_ARVALID (s0_arvalid), .S0_AXI_ARREADY (s0_arready),
        .S0_AXI_RID     (s0_rid),     .S0_AXI_RDATA   (s0_rdata),
        .S0_AXI_RRESP   (s0_rresp),   .S0_AXI_RLAST   (s0_rlast),
        .S0_AXI_RVALID  (s0_rvalid),  .S0_AXI_RREADY  (s0_rready),
        .S0_AXI_AWID    (s0_awid),    .S0_AXI_AWADDR  (s0_awaddr),
        .S0_AXI_AWLEN   (s0_awlen),   .S0_AXI_AWSIZE  (s0_awsize),
        .S0_AXI_AWBURST (s0_awburst), .S0_AXI_AWPROT  (s0_awprot),
        .S0_AXI_AWVALID (s0_awvalid), .S0_AXI_AWREADY (s0_awready),
        .S0_AXI_WDATA   (s0_wdata),   .S0_AXI_WSTRB   (s0_wstrb),
        .S0_AXI_WLAST   (s0_wlast),   .S0_AXI_WVALID  (s0_wvalid),
        .S0_AXI_WREADY  (s0_wready),
        .S0_AXI_BID     (s0_bid),     .S0_AXI_BRESP   (s0_bresp),
        .S0_AXI_BVALID  (s0_bvalid),  .S0_AXI_BREADY  (s0_bready),
        // S1 — DMEM
        .S1_AXI_ARID    (s1_arid),    .S1_AXI_ARADDR  (s1_araddr),
        .S1_AXI_ARLEN   (s1_arlen),   .S1_AXI_ARSIZE  (s1_arsize),
        .S1_AXI_ARBURST (s1_arburst), .S1_AXI_ARPROT  (s1_arprot),
        .S1_AXI_ARVALID (s1_arvalid), .S1_AXI_ARREADY (s1_arready),
        .S1_AXI_RID     (s1_rid),     .S1_AXI_RDATA   (s1_rdata),
        .S1_AXI_RRESP   (s1_rresp),   .S1_AXI_RLAST   (s1_rlast),
        .S1_AXI_RVALID  (s1_rvalid),  .S1_AXI_RREADY  (s1_rready),
        .S1_AXI_AWID    (s1_awid),    .S1_AXI_AWADDR  (s1_awaddr),
        .S1_AXI_AWLEN   (s1_awlen),   .S1_AXI_AWSIZE  (s1_awsize),
        .S1_AXI_AWBURST (s1_awburst), .S1_AXI_AWPROT  (s1_awprot),
        .S1_AXI_AWVALID (s1_awvalid), .S1_AXI_AWREADY (s1_awready),
        .S1_AXI_WDATA   (s1_wdata),   .S1_AXI_WSTRB   (s1_wstrb),
        .S1_AXI_WLAST   (s1_wlast),   .S1_AXI_WVALID  (s1_wvalid),
        .S1_AXI_WREADY  (s1_wready),
        .S1_AXI_BID     (s1_bid),     .S1_AXI_BRESP   (s1_bresp),
        .S1_AXI_BVALID  (s1_bvalid),  .S1_AXI_BREADY  (s1_bready),
        // S2 — ASCON stub
        .S2_AXI_ARID    (s2_arid),    .S2_AXI_ARADDR  (s2_araddr),
        .S2_AXI_ARLEN   (s2_arlen),   .S2_AXI_ARSIZE  (s2_arsize),
        .S2_AXI_ARBURST (s2_arburst), .S2_AXI_ARPROT  (s2_arprot),
        .S2_AXI_ARVALID (s2_arvalid), .S2_AXI_ARREADY (s2_arready),
        .S2_AXI_RID     (s2_rid),     .S2_AXI_RDATA   (s2_rdata),
        .S2_AXI_RRESP   (s2_rresp),   .S2_AXI_RLAST   (s2_rlast),
        .S2_AXI_RVALID  (s2_rvalid),  .S2_AXI_RREADY  (s2_rready),
        .S2_AXI_AWID    (s2_awid),    .S2_AXI_AWADDR  (s2_awaddr),
        .S2_AXI_AWLEN   (s2_awlen),   .S2_AXI_AWSIZE  (s2_awsize),
        .S2_AXI_AWBURST (s2_awburst), .S2_AXI_AWPROT  (s2_awprot),
        .S2_AXI_AWVALID (s2_awvalid), .S2_AXI_AWREADY (s2_awready),
        .S2_AXI_WDATA   (s2_wdata),   .S2_AXI_WSTRB   (s2_wstrb),
        .S2_AXI_WLAST   (s2_wlast),   .S2_AXI_WVALID  (s2_wvalid),
        .S2_AXI_WREADY  (s2_wready),
        .S2_AXI_BID     (s2_bid),     .S2_AXI_BRESP   (s2_bresp),
        .S2_AXI_BVALID  (s2_bvalid),  .S2_AXI_BREADY  (s2_bready),
        // S3 — SoC Ctrl stub
        .S3_AXI_ARID    (s3_arid),    .S3_AXI_ARADDR  (s3_araddr),
        .S3_AXI_ARLEN   (s3_arlen),   .S3_AXI_ARSIZE  (s3_arsize),
        .S3_AXI_ARBURST (s3_arburst), .S3_AXI_ARPROT  (s3_arprot),
        .S3_AXI_ARVALID (s3_arvalid), .S3_AXI_ARREADY (s3_arready),
        .S3_AXI_RID     (s3_rid),     .S3_AXI_RDATA   (s3_rdata),
        .S3_AXI_RRESP   (s3_rresp),   .S3_AXI_RLAST   (s3_rlast),
        .S3_AXI_RVALID  (s3_rvalid),  .S3_AXI_RREADY  (s3_rready),
        .S3_AXI_AWID    (s3_awid),    .S3_AXI_AWADDR  (s3_awaddr),
        .S3_AXI_AWLEN   (s3_awlen),   .S3_AXI_AWSIZE  (s3_awsize),
        .S3_AXI_AWBURST (s3_awburst), .S3_AXI_AWPROT  (s3_awprot),
        .S3_AXI_AWVALID (s3_awvalid), .S3_AXI_AWREADY (s3_awready),
        .S3_AXI_WDATA   (s3_wdata),   .S3_AXI_WSTRB   (s3_wstrb),
        .S3_AXI_WLAST   (s3_wlast),   .S3_AXI_WVALID  (s3_wvalid),
        .S3_AXI_WREADY  (s3_wready),
        .S3_AXI_BID     (s3_bid),     .S3_AXI_BRESP   (s3_bresp),
        .S3_AXI_BVALID  (s3_bvalid),  .S3_AXI_BREADY  (s3_bready)
    );

    // ========================================================================
    // 5. Instruction Memory — Slave 0
    // ========================================================================
    inst_mem_axi_slave #(.ID_WIDTH(ID_WIDTH)) imem (
        .clk           (clk),          .rst_n         (rst_n),
        .S_AXI_ARID    (s0_arid),
        .S_AXI_ARADDR  (s0_araddr),    .S_AXI_ARLEN   (s0_arlen),
        .S_AXI_ARSIZE  (s0_arsize),    .S_AXI_ARBURST (s0_arburst),
        .S_AXI_ARPROT  (s0_arprot),    .S_AXI_ARVALID (s0_arvalid),
        .S_AXI_ARREADY (s0_arready),
        .S_AXI_RID     (s0_rid),
        .S_AXI_RDATA   (s0_rdata),     .S_AXI_RRESP   (s0_rresp),
        .S_AXI_RLAST   (s0_rlast),     .S_AXI_RVALID  (s0_rvalid),
        .S_AXI_RREADY  (s0_rready),
        .S_AXI_AWID    (s0_awid),
        .S_AXI_AWADDR  (s0_awaddr),    .S_AXI_AWLEN   (s0_awlen),
        .S_AXI_AWSIZE  (s0_awsize),    .S_AXI_AWBURST (s0_awburst),
        .S_AXI_AWPROT  (s0_awprot),    .S_AXI_AWVALID (s0_awvalid),
        .S_AXI_AWREADY (s0_awready),
        .S_AXI_WDATA   (s0_wdata),     .S_AXI_WSTRB   (s0_wstrb),
        .S_AXI_WLAST   (s0_wlast),     .S_AXI_WVALID  (s0_wvalid),
        .S_AXI_WREADY  (s0_wready),
        .S_AXI_BID     (s0_bid),
        .S_AXI_BRESP   (s0_bresp),     .S_AXI_BVALID  (s0_bvalid),
        .S_AXI_BREADY  (s0_bready)
    );

    // ========================================================================
    // 6. Data Memory — Slave 1
    // data_mem chua co ID port -> dung s1_rid_r / s1_bid_r da latch o tren
    // ========================================================================
    data_mem_axi4_slave dmem (
        .clk           (clk),          .rst_n         (rst_n),
        .S_AXI_ARADDR  (s1_araddr),    .S_AXI_ARLEN   (s1_arlen),
        .S_AXI_ARSIZE  (s1_arsize),    .S_AXI_ARBURST (s1_arburst),
        .S_AXI_ARPROT  (s1_arprot),    .S_AXI_ARVALID (s1_arvalid),
        .S_AXI_ARREADY (s1_arready),
        .S_AXI_RDATA   (s1_rdata),     .S_AXI_RRESP   (s1_rresp),
        .S_AXI_RLAST   (s1_rlast),     .S_AXI_RVALID  (s1_rvalid),
        .S_AXI_RREADY  (s1_rready),
        .S_AXI_AWADDR  (s1_awaddr),    .S_AXI_AWLEN   (s1_awlen),
        .S_AXI_AWSIZE  (s1_awsize),    .S_AXI_AWBURST (s1_awburst),
        .S_AXI_AWPROT  (s1_awprot),    .S_AXI_AWVALID (s1_awvalid),
        .S_AXI_AWREADY (s1_awready),
        .S_AXI_WDATA   (s1_wdata),     .S_AXI_WSTRB   (s1_wstrb),
        .S_AXI_WLAST   (s1_wlast),     .S_AXI_WVALID  (s1_wvalid),
        .S_AXI_WREADY  (s1_wready),
        .S_AXI_BRESP   (s1_bresp),     .S_AXI_BVALID  (s1_bvalid),
        .S_AXI_BREADY  (s1_bready)
    );

endmodule