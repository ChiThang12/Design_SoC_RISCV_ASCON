// ============================================================================
// Module: riscv_soc_top_cached
// ============================================================================
// Description:
//   RISC-V SoC with instruction and data caches
//   - ICache: 4KB, read-only, direct-mapped
//   - DCache: 8KB, write-through, direct-mapped
//   - Both use AXI4 Full for memory access
//
// Author: ChiThang
// Version: 2.0 - With Cache Integration
// ============================================================================

`include "cpu/riscv_cpu_core_v1.v"
`include "cpu/interface/icache/icache_top.v"
`include "cpu/interface/dcache/dcache_top.v"
`include "cpu/memory_axi4full/inst_mem_axi_slave.v"
`include "cpu/memory_axi4full/data_mem_axi_slave.v"

module riscv_soc_top_cached (
    input wire clk,
    input wire rst_n,
    
    // Debug outputs (optional)
    output wire [31:0] icache_hits,
    output wire [31:0] icache_misses,
    output wire [31:0] dcache_hits,
    output wire [31:0] dcache_misses,
    output wire [31:0] dcache_writes
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    
    wire rst = ~rst_n;
    
    // ------------------------------------------------------------------------
    // CPU ↔ ICache Interface
    // ------------------------------------------------------------------------
    wire [31:0] cpu_imem_addr;
    wire        cpu_imem_valid;
    wire [31:0] cpu_imem_rdata;
    wire        cpu_imem_ready;
    
    // ------------------------------------------------------------------------
    // CPU ↔ DCache Interface
    // ------------------------------------------------------------------------
    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    wire [3:0]  cpu_dmem_wstrb;
    wire        cpu_dmem_valid;
    wire        cpu_dmem_we;
    wire [31:0] cpu_dmem_rdata;
    wire        cpu_dmem_ready;
    
    // ------------------------------------------------------------------------
    // ICache ↔ Memory (AXI4 Full Interface)
    // ------------------------------------------------------------------------
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
    
    // Unused write channels for ICache (read-only)
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
    
    // ------------------------------------------------------------------------
    // DCache ↔ Memory (AXI4 Full Interface)
    // ------------------------------------------------------------------------
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
    
    wire [31:0] dcache_wdata;
    wire [3:0]  dcache_wstrb;
    wire        dcache_wlast;
    wire        dcache_wvalid;
    wire        dcache_wready;
    
    wire [1:0]  dcache_bresp;
    wire        dcache_bvalid;
    wire        dcache_bready;
    
    // ========================================================================
    // MODULE INSTANCES
    // ========================================================================
    
    // ------------------------------------------------------------------------
    // 1. RISC-V CPU Core
    // ------------------------------------------------------------------------
    riscv_cpu_core cpu (
        .clk(clk),
        .rst(rst),
        
        // Instruction Memory Interface
        .imem_addr(cpu_imem_addr),
        .imem_valid(cpu_imem_valid),
        .imem_rdata(cpu_imem_rdata),
        .imem_ready(cpu_imem_ready),
        
        // Data Memory Interface
        .dmem_addr(cpu_dmem_addr),
        .dmem_wdata(cpu_dmem_wdata),
        .dmem_wstrb(cpu_dmem_wstrb),
        .dmem_valid(cpu_dmem_valid),
        .dmem_we(cpu_dmem_we),
        .dmem_rdata(cpu_dmem_rdata),
        .dmem_ready(cpu_dmem_ready)
    );
    
    // ------------------------------------------------------------------------
    // 2. Instruction Cache
    // ------------------------------------------------------------------------
    icache_top icache (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU Interface
        .cpu_addr(cpu_imem_addr),
        .cpu_req(cpu_imem_valid),
        .cpu_rdata(cpu_imem_rdata),
        .cpu_ready(cpu_imem_ready),
        .flush(1'b0),  // Can connect to branch mispredict signal
        
        // AXI4 Memory Interface
        .mem_araddr(icache_araddr),
        .mem_arlen(icache_arlen),
        .mem_arsize(icache_arsize),
        .mem_arburst(icache_arburst),
        .mem_arprot(icache_arprot),
        .mem_arvalid(icache_arvalid),
        .mem_arready(icache_arready),
        
        .mem_rdata(icache_rdata),
        .mem_rresp(icache_rresp),
        .mem_rlast(icache_rlast),
        .mem_rvalid(icache_rvalid),
        .mem_rready(icache_rready),
        
        // Unused write channels
        .mem_awaddr(icache_awaddr),
        .mem_awlen(icache_awlen),
        .mem_awsize(icache_awsize),
        .mem_awburst(icache_awburst),
        .mem_awprot(icache_awprot),
        .mem_awvalid(icache_awvalid),
        .mem_awready(icache_awready),
        
        .mem_wdata(icache_wdata),
        .mem_wstrb(icache_wstrb),
        .mem_wlast(icache_wlast),
        .mem_wvalid(icache_wvalid),
        .mem_wready(icache_wready),
        
        .mem_bresp(icache_bresp),
        .mem_bvalid(icache_bvalid),
        .mem_bready(icache_bready),
        
        // Statistics
        .stat_hits(icache_hits),
        .stat_misses(icache_misses)
    );
    
    // ------------------------------------------------------------------------
    // 3. Data Cache
    // ------------------------------------------------------------------------
    dcache_top dcache (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU Interface
        .cpu_addr(cpu_dmem_addr),
        .cpu_wdata(cpu_dmem_wdata),
        .cpu_wstrb(cpu_dmem_wstrb),
        .cpu_req(cpu_dmem_valid),
        .cpu_we(cpu_dmem_we),
        .cpu_rdata(cpu_dmem_rdata),
        .cpu_ready(cpu_dmem_ready),
        .fence(1'b0),  // Can connect to FENCE instruction
        
        // AXI4 Memory Interface
        .mem_araddr(dcache_araddr),
        .mem_arlen(dcache_arlen),
        .mem_arsize(dcache_arsize),
        .mem_arburst(dcache_arburst),
        .mem_arprot(dcache_arprot),
        .mem_arvalid(dcache_arvalid),
        .mem_arready(dcache_arready),
        
        .mem_rdata(dcache_rdata),
        .mem_rresp(dcache_rresp),
        .mem_rlast(dcache_rlast),
        .mem_rvalid(dcache_rvalid),
        .mem_rready(dcache_rready),
        
        .mem_awaddr(dcache_awaddr),
        .mem_awlen(dcache_awlen),
        .mem_awsize(dcache_awsize),
        .mem_awburst(dcache_awburst),
        .mem_awprot(dcache_awprot),
        .mem_awvalid(dcache_awvalid),
        .mem_awready(dcache_awready),
        
        .mem_wdata(dcache_wdata),
        .mem_wstrb(dcache_wstrb),
        .mem_wlast(dcache_wlast),
        .mem_wvalid(dcache_wvalid),
        .mem_wready(dcache_wready),
        
        .mem_bresp(dcache_bresp),
        .mem_bvalid(dcache_bvalid),
        .mem_bready(dcache_bready),
        
        // Statistics
        .stat_hits(dcache_hits),
        .stat_misses(dcache_misses),
        .stat_writes(dcache_writes)
    );
    
    // ------------------------------------------------------------------------
    // 4. Instruction Memory (AXI4 Slave)
    // ------------------------------------------------------------------------
    // Note: Need to modify inst_mem_axi_slave to support AXI4 Full
    // For now, this is a placeholder showing the connection pattern
    inst_mem_axi_slave imem (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4 Full Slave Interface
        .S_AXI_ARADDR(icache_araddr),
        .S_AXI_ARLEN(icache_arlen),
        .S_AXI_ARSIZE(icache_arsize),
        .S_AXI_ARBURST(icache_arburst),
        .S_AXI_ARPROT(icache_arprot),
        .S_AXI_ARVALID(icache_arvalid),
        .S_AXI_ARREADY(icache_arready),
        
        .S_AXI_RDATA(icache_rdata),
        .S_AXI_RRESP(icache_rresp),
        .S_AXI_RLAST(icache_rlast),
        .S_AXI_RVALID(icache_rvalid),
        .S_AXI_RREADY(icache_rready),
        
        // Tie off unused write channels
        .S_AXI_AWADDR(icache_awaddr),
        .S_AXI_AWLEN(icache_awlen),
        .S_AXI_AWSIZE(icache_awsize),
        .S_AXI_AWBURST(icache_awburst),
        .S_AXI_AWPROT(icache_awprot),
        .S_AXI_AWVALID(icache_awvalid),
        .S_AXI_AWREADY(icache_awready),
        
        .S_AXI_WDATA(icache_wdata),
        .S_AXI_WSTRB(icache_wstrb),
        .S_AXI_WLAST(icache_wlast),
        .S_AXI_WVALID(icache_wvalid),
        .S_AXI_WREADY(icache_wready),
        
        .S_AXI_BRESP(icache_bresp),
        .S_AXI_BVALID(icache_bvalid),
        .S_AXI_BREADY(icache_bready)
    );
    
    // ------------------------------------------------------------------------
    // 5. Data Memory (AXI4 Slave)
    // ------------------------------------------------------------------------
    data_mem_axi4_slave dmem (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4 Full Slave Interface
        .S_AXI_ARADDR(dcache_araddr),
        .S_AXI_ARLEN(dcache_arlen),
        .S_AXI_ARSIZE(dcache_arsize),
        .S_AXI_ARBURST(dcache_arburst),
        .S_AXI_ARPROT(dcache_arprot),
        .S_AXI_ARVALID(dcache_arvalid),
        .S_AXI_ARREADY(dcache_arready),
        
        .S_AXI_RDATA(dcache_rdata),
        .S_AXI_RRESP(dcache_rresp),
        .S_AXI_RLAST(dcache_rlast),
        .S_AXI_RVALID(dcache_rvalid),
        .S_AXI_RREADY(dcache_rready),
        
        .S_AXI_AWADDR(dcache_awaddr),
        .S_AXI_AWLEN(dcache_awlen),
        .S_AXI_AWSIZE(dcache_awsize),
        .S_AXI_AWBURST(dcache_awburst),
        .S_AXI_AWPROT(dcache_awprot),
        .S_AXI_AWVALID(dcache_awvalid),
        .S_AXI_AWREADY(dcache_awready),
        
        .S_AXI_WDATA(dcache_wdata),
        .S_AXI_WSTRB(dcache_wstrb),
        .S_AXI_WLAST(dcache_wlast),
        .S_AXI_WVALID(dcache_wvalid),
        .S_AXI_WREADY(dcache_wready),
        
        .S_AXI_BRESP(dcache_bresp),
        .S_AXI_BVALID(dcache_bvalid),
        .S_AXI_BREADY(dcache_bready)
    );

endmodule