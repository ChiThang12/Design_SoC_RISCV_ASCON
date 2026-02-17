// ============================================================================
// riscv_soc_top_cached.v - RISC-V SoC with ICache + DCache
// ============================================================================
// Description:
//   RISC-V SoC with instruction and data caches
//   - ICache: 4KB, read-only, direct-mapped
//   - DCache: 8KB, write-through, direct-mapped
//   - Both use AXI4 Full for memory access
//   - LSU: High-performance (Store Buffer 8 entry, Load Queue 2 entry)
//
// CHANGES v2:
//   CHG-1: CPU interface đổi từ dmem_* → dcache_* (khớp với LSU mới)
//   CHG-2: Thêm wire current_* để kết nối dcache_top (port mới của controller)
//   CHG-3: Tie off current_* nếu không dùng debug (floating wire fix)
//   CHG-4: Reset polarity comment rõ ràng
//
// Author: ChiThang
// Version: 2.1
// ============================================================================

`include "cpu/riscv_cpu_core_v2.v"
`include "cpu/interface/icache/icache_top.v"
`include "cpu/interface/dcache/dcache_top.v"
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/memory_axi4full/data_mem_axi_slave.v"

module riscv_soc_top_cached (
    input wire clk,
    input wire rst_n,           // Active-low reset (toàn bộ SoC)

    // Debug outputs
    output wire [31:0] icache_hits,
    output wire [31:0] icache_misses,
    output wire [31:0] dcache_hits,
    output wire [31:0] dcache_misses,
    output wire [31:0] dcache_writes
);

    // ========================================================================
    // Reset — CPU dùng active-high, Cache/Memory dùng active-low
    // CHG-4: Comment rõ polarity để tránh nhầm khi thêm module mới
    // ========================================================================
    wire rst = ~rst_n;          // Active-high rst cho CPU core

    // ========================================================================
    // CPU ↔ ICache Interface
    // ========================================================================
    wire [31:0] cpu_imem_addr;
    wire        cpu_imem_valid;
    wire [31:0] cpu_imem_rdata;
    wire        cpu_imem_ready;

    // ========================================================================
    // CPU ↔ DCache Interface (CHG-1: đổi tên từ dmem_* → dcache_*)
    // CPU output: dcache_req, dcache_we, dcache_addr, dcache_wdata, dcache_wstrb
    // CPU input : dcache_rdata, dcache_ready
    // ========================================================================
    wire [31:0] cpu_dcache_addr;
    wire [31:0] cpu_dcache_wdata;
    wire [3:0]  cpu_dcache_wstrb;
    wire        cpu_dcache_req;
    wire        cpu_dcache_we;
    wire [31:0] cpu_dcache_rdata;
    wire        cpu_dcache_ready;

    // ========================================================================
    // CHG-2: DCache current_* debug signals
    // Expose trạng thái dCache đang xử lý — có thể nối vào debug unit
    // hoặc tie off nếu không dùng
    // ========================================================================
    wire [31:0] dcache_current_addr;
    wire [31:0] dcache_current_data;
    wire        dcache_current_valid;

    // ========================================================================
    // ICache ↔ Instruction Memory (AXI4 Full)
    // ========================================================================
    wire [31:0] icache_araddr;
    wire [7:0]  icache_arlen;
    wire [2:0]  icache_arsize;
    wire [1:0]  icache_arburst;
    wire [2:0]  icache_arprot;
    wire        icache_arvalid;
    wire        icache_arready;

    wire [31:0] icache_rdata;
    wire [1:0]  icache_rresp;
    wire        icache_rlast;
    wire        icache_rvalid;
    wire        icache_rready;

    // ICache write channels — read-only cache, tie off slave side
    wire [31:0] icache_awaddr;
    wire [7:0]  icache_awlen;
    wire [2:0]  icache_awsize;
    wire [1:0]  icache_awburst;
    wire [2:0]  icache_awprot;
    wire        icache_awvalid;
    wire        icache_awready;
    wire [31:0] icache_wdata;
    wire [3:0]  icache_wstrb;
    wire        icache_wlast;
    wire        icache_wvalid;
    wire        icache_wready;
    wire [1:0]  icache_bresp;
    wire        icache_bvalid;
    wire        icache_bready;

    // ========================================================================
    // DCache ↔ Data Memory (AXI4 Full)
    // ========================================================================
    wire [31:0] dcache_araddr;
    wire [7:0]  dcache_arlen;
    wire [2:0]  dcache_arsize;
    wire [1:0]  dcache_arburst;
    wire [2:0]  dcache_arprot;
    wire        dcache_arvalid;
    wire        dcache_arready;

    wire [31:0] dcache_rdata;
    wire [1:0]  dcache_rresp;
    wire        dcache_rlast;
    wire        dcache_rvalid;
    wire        dcache_rready;

    wire [31:0] dcache_awaddr;
    wire [7:0]  dcache_awlen;
    wire [2:0]  dcache_awsize;
    wire [1:0]  dcache_awburst;
    wire [2:0]  dcache_awprot;
    wire        dcache_awvalid;
    wire        dcache_awready;

    wire [31:0] dcache_wdata_axi;
    wire [3:0]  dcache_wstrb_axi;
    wire        dcache_wlast;
    wire        dcache_wvalid;
    wire        dcache_wready;

    wire [1:0]  dcache_bresp;
    wire        dcache_bvalid;
    wire        dcache_bready;

    // ========================================================================
    // 1. RISC-V CPU Core
    // CHG-1: Port names đổi thành dcache_* để khớp với LSU mới
    // ========================================================================
    riscv_cpu_core cpu (
        .clk          (clk),
        .rst          (rst),

        // Instruction Memory Interface
        .imem_addr    (cpu_imem_addr),
        .imem_valid   (cpu_imem_valid),
        .imem_rdata   (cpu_imem_rdata),
        .imem_ready   (cpu_imem_ready),

        // Data Cache Interface (CHG-1)
        .dcache_addr  (cpu_dcache_addr),
        .dcache_wdata (cpu_dcache_wdata),
        .dcache_wstrb (cpu_dcache_wstrb),
        .dcache_req   (cpu_dcache_req),
        .dcache_we    (cpu_dcache_we),
        .dcache_rdata (cpu_dcache_rdata),
        .dcache_ready (cpu_dcache_ready)
    );

    // ========================================================================
    // 2. Instruction Cache
    // ========================================================================
    icache_top icache (
        .clk          (clk),
        .rst_n        (rst_n),          // Active-low

        // CPU Interface
        .cpu_addr     (cpu_imem_addr),
        .cpu_req      (cpu_imem_valid),
        .cpu_rdata    (cpu_imem_rdata),
        .cpu_ready    (cpu_imem_ready),
        .flush        (1'b0),

        // AXI4 Read Interface
        .mem_araddr   (icache_araddr),
        .mem_arlen    (icache_arlen),
        .mem_arsize   (icache_arsize),
        .mem_arburst  (icache_arburst),
        .mem_arprot   (icache_arprot),
        .mem_arvalid  (icache_arvalid),
        .mem_arready  (icache_arready),

        .mem_rdata    (icache_rdata),
        .mem_rresp    (icache_rresp),
        .mem_rlast    (icache_rlast),
        .mem_rvalid   (icache_rvalid),
        .mem_rready   (icache_rready),

        // Write channels — read-only cache
        .mem_awaddr   (icache_awaddr),
        .mem_awlen    (icache_awlen),
        .mem_awsize   (icache_awsize),
        .mem_awburst  (icache_awburst),
        .mem_awprot   (icache_awprot),
        .mem_awvalid  (icache_awvalid),
        .mem_awready  (icache_awready),

        .mem_wdata    (icache_wdata),
        .mem_wstrb    (icache_wstrb),
        .mem_wlast    (icache_wlast),
        .mem_wvalid   (icache_wvalid),
        .mem_wready   (icache_wready),

        .mem_bresp    (icache_bresp),
        .mem_bvalid   (icache_bvalid),
        .mem_bready   (icache_bready),

        // Statistics
        .stat_hits    (icache_hits),
        .stat_misses  (icache_misses)
    );

    // ========================================================================
    // 3. Data Cache
    // CHG-2: Thêm current_* ports — wire đã khai báo ở trên
    // CHG-3: current_* được khai báo nhưng không drive ra ngoài module
    //        (tie off internally) — synthesis sẽ optimize away nếu không dùng
    // ========================================================================
    dcache_top dcache (
        .clk              (clk),
        .rst_n            (rst_n),      // Active-low

        // CPU (LSU) Interface
        .cpu_addr         (cpu_dcache_addr),
        .cpu_wdata        (cpu_dcache_wdata),
        .cpu_wstrb        (cpu_dcache_wstrb),
        .cpu_req          (cpu_dcache_req),
        .cpu_we           (cpu_dcache_we),
        .cpu_rdata        (cpu_dcache_rdata),
        .cpu_ready        (cpu_dcache_ready),
        .fence            (1'b0),       // TODO: kết nối vào FENCE instruction decoder

        // CHG-2: current_* debug ports
        .current_addr     (dcache_current_addr),
        .current_data     (dcache_current_data),
        .current_valid    (dcache_current_valid),

        // AXI4 Read Interface
        .mem_araddr       (dcache_araddr),
        .mem_arlen        (dcache_arlen),
        .mem_arsize       (dcache_arsize),
        .mem_arburst      (dcache_arburst),
        .mem_arprot       (dcache_arprot),
        .mem_arvalid      (dcache_arvalid),
        .mem_arready      (dcache_arready),

        .mem_rdata        (dcache_rdata),
        .mem_rresp        (dcache_rresp),
        .mem_rlast        (dcache_rlast),
        .mem_rvalid       (dcache_rvalid),
        .mem_rready       (dcache_rready),

        // AXI4 Write Interface
        .mem_awaddr       (dcache_awaddr),
        .mem_awlen        (dcache_awlen),
        .mem_awsize       (dcache_awsize),
        .mem_awburst      (dcache_awburst),
        .mem_awprot       (dcache_awprot),
        .mem_awvalid      (dcache_awvalid),
        .mem_awready      (dcache_awready),

        .mem_wdata        (dcache_wdata_axi),
        .mem_wstrb        (dcache_wstrb_axi),
        .mem_wlast        (dcache_wlast),
        .mem_wvalid       (dcache_wvalid),
        .mem_wready       (dcache_wready),

        .mem_bresp        (dcache_bresp),
        .mem_bvalid       (dcache_bvalid),
        .mem_bready       (dcache_bready),

        // Statistics
        .stat_hits        (dcache_hits),
        .stat_misses      (dcache_misses),
        .stat_writes      (dcache_writes)
    );

    // ========================================================================
    // 4. Instruction Memory (AXI4 Slave)
    // ========================================================================
    inst_mem_axi_slave imem (
        .clk              (clk),
        .rst_n            (rst_n),

        .S_AXI_ARADDR     (icache_araddr),
        .S_AXI_ARLEN      (icache_arlen),
        .S_AXI_ARSIZE     (icache_arsize),
        .S_AXI_ARBURST    (icache_arburst),
        .S_AXI_ARPROT     (icache_arprot),
        .S_AXI_ARVALID    (icache_arvalid),
        .S_AXI_ARREADY    (icache_arready),

        .S_AXI_RDATA      (icache_rdata),
        .S_AXI_RRESP      (icache_rresp),
        .S_AXI_RLAST      (icache_rlast),
        .S_AXI_RVALID     (icache_rvalid),
        .S_AXI_RREADY     (icache_rready),

        .S_AXI_AWADDR     (icache_awaddr),
        .S_AXI_AWLEN      (icache_awlen),
        .S_AXI_AWSIZE     (icache_awsize),
        .S_AXI_AWBURST    (icache_awburst),
        .S_AXI_AWPROT     (icache_awprot),
        .S_AXI_AWVALID    (icache_awvalid),
        .S_AXI_AWREADY    (icache_awready),

        .S_AXI_WDATA      (icache_wdata),
        .S_AXI_WSTRB      (icache_wstrb),
        .S_AXI_WLAST      (icache_wlast),
        .S_AXI_WVALID     (icache_wvalid),
        .S_AXI_WREADY     (icache_wready),

        .S_AXI_BRESP      (icache_bresp),
        .S_AXI_BVALID     (icache_bvalid),
        .S_AXI_BREADY     (icache_bready)
    );

    // ========================================================================
    // 5. Data Memory (AXI4 Slave)
    // ========================================================================
    data_mem_axi4_slave dmem (
        .clk              (clk),
        .rst_n            (rst_n),

        .S_AXI_ARADDR     (dcache_araddr),
        .S_AXI_ARLEN      (dcache_arlen),
        .S_AXI_ARSIZE     (dcache_arsize),
        .S_AXI_ARBURST    (dcache_arburst),
        .S_AXI_ARPROT     (dcache_arprot),
        .S_AXI_ARVALID    (dcache_arvalid),
        .S_AXI_ARREADY    (dcache_arready),

        .S_AXI_RDATA      (dcache_rdata),
        .S_AXI_RRESP      (dcache_rresp),
        .S_AXI_RLAST      (dcache_rlast),
        .S_AXI_RVALID     (dcache_rvalid),
        .S_AXI_RREADY     (dcache_rready),

        .S_AXI_AWADDR     (dcache_awaddr),
        .S_AXI_AWLEN      (dcache_awlen),
        .S_AXI_AWSIZE     (dcache_awsize),
        .S_AXI_AWBURST    (dcache_awburst),
        .S_AXI_AWPROT     (dcache_awprot),
        .S_AXI_AWVALID    (dcache_awvalid),
        .S_AXI_AWREADY    (dcache_awready),

        .S_AXI_WDATA      (dcache_wdata_axi),
        .S_AXI_WSTRB      (dcache_wstrb_axi),
        .S_AXI_WLAST      (dcache_wlast),
        .S_AXI_WVALID     (dcache_wvalid),
        .S_AXI_WREADY     (dcache_wready),

        .S_AXI_BRESP      (dcache_bresp),
        .S_AXI_BVALID     (dcache_bvalid),
        .S_AXI_BREADY     (dcache_bready)
    );

endmodule