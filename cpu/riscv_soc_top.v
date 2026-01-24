// ============================================================================
// Module: riscv_soc_top (WITH DEBUG PORTS)
// ============================================================================
`include "riscv_cpu_core.v"
`include "interface/imem_access_unit.v"
`include "interface/dmem_access_unit.v"
`include "memory/inst_mem_axi_slave.v"
`include "memory/data_mem_axi_slave.v"
// ============================================================================
// riscv_soc_top.v - RISC-V SoC with AXI4-Lite Interconnect
// ============================================================================
// Description:
//   Top-level SoC integrating:
//   - RISC-V CPU Core (5-stage pipeline)
//   - Instruction Memory (via AXI4-Lite)
//   - Data Memory (via AXI4-Lite)
//   - AXI4-Lite Interconnect
//
// Author: ChiThang
// ============================================================================

module riscv_soc_top (
    input wire clk,
    input wire rst_n
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    
    // CPU → IMEM Access Unit
    wire [31:0] cpu_imem_addr;
    wire        cpu_imem_valid;
    wire [31:0] cpu_imem_rdata;
    wire        cpu_imem_ready;
    
    // CPU → DMEM Access Unit
    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    wire [3:0]  cpu_dmem_wstrb;
    wire        cpu_dmem_valid;
    wire        cpu_dmem_we;
    wire [31:0] cpu_dmem_rdata;
    wire        cpu_dmem_ready;
    
    // ========================================================================
    // AXI4-Lite Master Signals (IMEM Access Unit → Interconnect)
    // ========================================================================
    wire [31:0] imem_m_axi_awaddr;
    wire [2:0]  imem_m_axi_awprot;
    wire        imem_m_axi_awvalid;
    wire        imem_m_axi_awready;
    
    wire [31:0] imem_m_axi_wdata;
    wire [3:0]  imem_m_axi_wstrb;
    wire        imem_m_axi_wvalid;
    wire        imem_m_axi_wready;
    
    wire [1:0]  imem_m_axi_bresp;
    wire        imem_m_axi_bvalid;
    wire        imem_m_axi_bready;
    
    wire [31:0] imem_m_axi_araddr;
    wire [2:0]  imem_m_axi_arprot;
    wire        imem_m_axi_arvalid;
    wire        imem_m_axi_arready;
    
    wire [31:0] imem_m_axi_rdata;
    wire [1:0]  imem_m_axi_rresp;
    wire        imem_m_axi_rvalid;
    wire        imem_m_axi_rready;
    
    // ========================================================================
    // AXI4-Lite Master Signals (DMEM Access Unit → Interconnect)
    // ========================================================================
    wire [31:0] dmem_m_axi_awaddr;
    wire [2:0]  dmem_m_axi_awprot;
    wire        dmem_m_axi_awvalid;
    wire        dmem_m_axi_awready;
    
    wire [31:0] dmem_m_axi_wdata;
    wire [3:0]  dmem_m_axi_wstrb;
    wire        dmem_m_axi_wvalid;
    wire        dmem_m_axi_wready;
    
    wire [1:0]  dmem_m_axi_bresp;
    wire        dmem_m_axi_bvalid;
    wire        dmem_m_axi_bready;
    
    wire [31:0] dmem_m_axi_araddr;
    wire [2:0]  dmem_m_axi_arprot;
    wire        dmem_m_axi_arvalid;
    wire        dmem_m_axi_arready;
    
    wire [31:0] dmem_m_axi_rdata;
    wire [1:0]  dmem_m_axi_rresp;
    wire        dmem_m_axi_rvalid;
    wire        dmem_m_axi_rready;
    
    // ========================================================================
    // AXI4-Lite Slave Signals (Interconnect → IMEM Slave)
    // ========================================================================
    wire [31:0] imem_s_axi_awaddr;
    wire [2:0]  imem_s_axi_awprot;
    wire        imem_s_axi_awvalid;
    wire        imem_s_axi_awready;
    
    wire [31:0] imem_s_axi_wdata;
    wire [3:0]  imem_s_axi_wstrb;
    wire        imem_s_axi_wvalid;
    wire        imem_s_axi_wready;
    
    wire [1:0]  imem_s_axi_bresp;
    wire        imem_s_axi_bvalid;
    wire        imem_s_axi_bready;
    
    wire [31:0] imem_s_axi_araddr;
    wire [2:0]  imem_s_axi_arprot;
    wire        imem_s_axi_arvalid;
    wire        imem_s_axi_arready;
    
    wire [31:0] imem_s_axi_rdata;
    wire [1:0]  imem_s_axi_rresp;
    wire        imem_s_axi_rvalid;
    wire        imem_s_axi_rready;
    
    // ========================================================================
    // AXI4-Lite Slave Signals (Interconnect → DMEM Slave)
    // ========================================================================
    wire [31:0] dmem_s_axi_awaddr;
    wire [2:0]  dmem_s_axi_awprot;
    wire        dmem_s_axi_awvalid;
    wire        dmem_s_axi_awready;
    
    wire [31:0] dmem_s_axi_wdata;
    wire [3:0]  dmem_s_axi_wstrb;
    wire        dmem_s_axi_wvalid;
    wire        dmem_s_axi_wready;
    
    wire [1:0]  dmem_s_axi_bresp;
    wire        dmem_s_axi_bvalid;
    wire        dmem_s_axi_bready;
    
    wire [31:0] dmem_s_axi_araddr;
    wire [2:0]  dmem_s_axi_arprot;
    wire        dmem_s_axi_arvalid;
    wire        dmem_s_axi_arready;
    
    wire [31:0] dmem_s_axi_rdata;
    wire [1:0]  dmem_s_axi_rresp;
    wire        dmem_s_axi_rvalid;
    wire        dmem_s_axi_rready;
    
    // ========================================================================
    // Reset Synchronizer
    // ========================================================================
    wire rst = ~rst_n;
    
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
    // 2. Instruction Memory Access Unit (AXI4-Lite Master)
    // ------------------------------------------------------------------------
    imem_access_unit imem_access (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU Interface
        .if_addr(cpu_imem_addr),
        .if_req(cpu_imem_valid),
        .if_data(cpu_imem_rdata),
        .if_ready(cpu_imem_ready),
        .if_error(),  // Not used
        
        // AXI4-Lite Master Interface
        .M_AXI_AWADDR(imem_m_axi_awaddr),
        .M_AXI_AWPROT(imem_m_axi_awprot),
        .M_AXI_AWVALID(imem_m_axi_awvalid),
        .M_AXI_AWREADY(imem_m_axi_awready),
        
        .M_AXI_WDATA(imem_m_axi_wdata),
        .M_AXI_WSTRB(imem_m_axi_wstrb),
        .M_AXI_WVALID(imem_m_axi_wvalid),
        .M_AXI_WREADY(imem_m_axi_wready),
        
        .M_AXI_BRESP(imem_m_axi_bresp),
        .M_AXI_BVALID(imem_m_axi_bvalid),
        .M_AXI_BREADY(imem_m_axi_bready),
        
        .M_AXI_ARADDR(imem_m_axi_araddr),
        .M_AXI_ARPROT(imem_m_axi_arprot),
        .M_AXI_ARVALID(imem_m_axi_arvalid),
        .M_AXI_ARREADY(imem_m_axi_arready),
        
        .M_AXI_RDATA(imem_m_axi_rdata),
        .M_AXI_RRESP(imem_m_axi_rresp),
        .M_AXI_RVALID(imem_m_axi_rvalid),
        .M_AXI_RREADY(imem_m_axi_rready)
    );
    
    // ------------------------------------------------------------------------
    // 3. Data Memory Access Unit (AXI4-Lite Master)
    // ------------------------------------------------------------------------
    dmem_access_unit dmem_access (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU Interface
        .mem_addr(cpu_dmem_addr),
        .mem_wdata(cpu_dmem_wdata),
        .mem_wstrb(cpu_dmem_wstrb),
        .mem_req(cpu_dmem_valid),
        .mem_wr(cpu_dmem_we),
        .mem_rdata(cpu_dmem_rdata),
        .mem_ready(cpu_dmem_ready),
        .mem_error(),  // Not used
        
        // AXI4-Lite Master Interface
        .M_AXI_AWADDR(dmem_m_axi_awaddr),
        .M_AXI_AWPROT(dmem_m_axi_awprot),
        .M_AXI_AWVALID(dmem_m_axi_awvalid),
        .M_AXI_AWREADY(dmem_m_axi_awready),
        
        .M_AXI_WDATA(dmem_m_axi_wdata),
        .M_AXI_WSTRB(dmem_m_axi_wstrb),
        .M_AXI_WVALID(dmem_m_axi_wvalid),
        .M_AXI_WREADY(dmem_m_axi_wready),
        
        .M_AXI_BRESP(dmem_m_axi_bresp),
        .M_AXI_BVALID(dmem_m_axi_bvalid),
        .M_AXI_BREADY(dmem_m_axi_bready),
        
        .M_AXI_ARADDR(dmem_m_axi_araddr),
        .M_AXI_ARPROT(dmem_m_axi_arprot),
        .M_AXI_ARVALID(dmem_m_axi_arvalid),
        .M_AXI_ARREADY(dmem_m_axi_arready),
        
        .M_AXI_RDATA(dmem_m_axi_rdata),
        .M_AXI_RRESP(dmem_m_axi_rresp),
        .M_AXI_RVALID(dmem_m_axi_rvalid),
        .M_AXI_RREADY(dmem_m_axi_rready)
    );
    
    // ------------------------------------------------------------------------
    // 4. AXI4-Lite Interconnect (Simple Direct Connection)
    // ------------------------------------------------------------------------
    // IMEM Path: IMEM Access Unit → IMEM Slave
    assign imem_s_axi_awaddr  = imem_m_axi_awaddr;
    assign imem_s_axi_awprot  = imem_m_axi_awprot;
    assign imem_s_axi_awvalid = imem_m_axi_awvalid;
    assign imem_m_axi_awready = imem_s_axi_awready;
    
    assign imem_s_axi_wdata   = imem_m_axi_wdata;
    assign imem_s_axi_wstrb   = imem_m_axi_wstrb;
    assign imem_s_axi_wvalid  = imem_m_axi_wvalid;
    assign imem_m_axi_wready  = imem_s_axi_wready;
    
    assign imem_m_axi_bresp   = imem_s_axi_bresp;
    assign imem_m_axi_bvalid  = imem_s_axi_bvalid;
    assign imem_s_axi_bready  = imem_m_axi_bready;
    
    assign imem_s_axi_araddr  = imem_m_axi_araddr;
    assign imem_s_axi_arprot  = imem_m_axi_arprot;
    assign imem_s_axi_arvalid = imem_m_axi_arvalid;
    assign imem_m_axi_arready = imem_s_axi_arready;
    
    assign imem_m_axi_rdata   = imem_s_axi_rdata;
    assign imem_m_axi_rresp   = imem_s_axi_rresp;
    assign imem_m_axi_rvalid  = imem_s_axi_rvalid;
    assign imem_s_axi_rready  = imem_m_axi_rready;
    
    // DMEM Path: DMEM Access Unit → DMEM Slave
    assign dmem_s_axi_awaddr  = dmem_m_axi_awaddr;
    assign dmem_s_axi_awprot  = dmem_m_axi_awprot;
    assign dmem_s_axi_awvalid = dmem_m_axi_awvalid;
    assign dmem_m_axi_awready = dmem_s_axi_awready;
    
    assign dmem_s_axi_wdata   = dmem_m_axi_wdata;
    assign dmem_s_axi_wstrb   = dmem_m_axi_wstrb;
    assign dmem_s_axi_wvalid  = dmem_m_axi_wvalid;
    assign dmem_m_axi_wready  = dmem_s_axi_wready;
    
    assign dmem_m_axi_bresp   = dmem_s_axi_bresp;
    assign dmem_m_axi_bvalid  = dmem_s_axi_bvalid;
    assign dmem_s_axi_bready  = dmem_m_axi_bready;
    
    assign dmem_s_axi_araddr  = dmem_m_axi_araddr;
    assign dmem_s_axi_arprot  = dmem_m_axi_arprot;
    assign dmem_s_axi_arvalid = dmem_m_axi_arvalid;
    assign dmem_m_axi_arready = dmem_s_axi_arready;
    
    assign dmem_m_axi_rdata   = dmem_s_axi_rdata;
    assign dmem_m_axi_rresp   = dmem_s_axi_rresp;
    assign dmem_m_axi_rvalid  = dmem_s_axi_rvalid;
    assign dmem_s_axi_rready  = dmem_m_axi_rready;
    
    // ------------------------------------------------------------------------
    // 5. Instruction Memory (AXI4-Lite Slave)
    // ------------------------------------------------------------------------
    inst_mem_axi_slave imem_slave (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4-Lite Slave Interface
        .S_AXI_AWADDR(imem_s_axi_awaddr),
        .S_AXI_AWPROT(imem_s_axi_awprot),
        .S_AXI_AWVALID(imem_s_axi_awvalid),
        .S_AXI_AWREADY(imem_s_axi_awready),
        
        .S_AXI_WDATA(imem_s_axi_wdata),
        .S_AXI_WSTRB(imem_s_axi_wstrb),
        .S_AXI_WVALID(imem_s_axi_wvalid),
        .S_AXI_WREADY(imem_s_axi_wready),
        
        .S_AXI_BRESP(imem_s_axi_bresp),
        .S_AXI_BVALID(imem_s_axi_bvalid),
        .S_AXI_BREADY(imem_s_axi_bready),
        
        .S_AXI_ARADDR(imem_s_axi_araddr),
        .S_AXI_ARPROT(imem_s_axi_arprot),
        .S_AXI_ARVALID(imem_s_axi_arvalid),
        .S_AXI_ARREADY(imem_s_axi_arready),
        
        .S_AXI_RDATA(imem_s_axi_rdata),
        .S_AXI_RRESP(imem_s_axi_rresp),
        .S_AXI_RVALID(imem_s_axi_rvalid),
        .S_AXI_RREADY(imem_s_axi_rready)
    );
    
    // ------------------------------------------------------------------------
    // 6. Data Memory (AXI4-Lite Slave)
    // ------------------------------------------------------------------------
    data_mem_axi_slave dmem_slave (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4-Lite Slave Interface
        .S_AXI_AWADDR(dmem_s_axi_awaddr),
        .S_AXI_AWPROT(dmem_s_axi_awprot),
        .S_AXI_AWVALID(dmem_s_axi_awvalid),
        .S_AXI_AWREADY(dmem_s_axi_awready),
        
        .S_AXI_WDATA(dmem_s_axi_wdata),
        .S_AXI_WSTRB(dmem_s_axi_wstrb),
        .S_AXI_WVALID(dmem_s_axi_wvalid),
        .S_AXI_WREADY(dmem_s_axi_wready),
        
        .S_AXI_BRESP(dmem_s_axi_bresp),
        .S_AXI_BVALID(dmem_s_axi_bvalid),
        .S_AXI_BREADY(dmem_s_axi_bready),
        
        .S_AXI_ARADDR(dmem_s_axi_araddr),
        .S_AXI_ARPROT(dmem_s_axi_arprot),
        .S_AXI_ARVALID(dmem_s_axi_arvalid),
        .S_AXI_ARREADY(dmem_s_axi_arready),
        
        .S_AXI_RDATA(dmem_s_axi_rdata),
        .S_AXI_RRESP(dmem_s_axi_rresp),
        .S_AXI_RVALID(dmem_s_axi_rvalid),
        .S_AXI_RREADY(dmem_s_axi_rready)
    );

endmodule