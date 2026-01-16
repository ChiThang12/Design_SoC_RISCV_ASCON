// ============================================================================
// riscv_soc_top.v - RISC-V SoC với AXI4-Lite Interconnect
// ============================================================================
// Mô tả:
//   - Tích hợp RISC-V Core, IMEM, DMEM qua AXI4-Lite Interconnect
//   - Memory Map:
//     * IMEM: 0x00000000 - 0x0FFFFFFF (256MB, read-only)
//     * DMEM: 0x10000000 - 0x1FFFFFFF (256MB, read-write)
// ============================================================================

`include "riscv_core_axi.v"
`include "memory/inst_mem_axi_slave.v"
`include "memory/data_mem_axi_slave.v"
`include "axi4_lite_interconnect.v"

module riscv_soc_top (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Debug Outputs
    // ========================================================================
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instr,
    output wire [31:0] debug_alu_result,
    output wire [31:0] debug_mem_data,
    output wire        debug_branch_taken,
    output wire [31:0] debug_branch_target,
    output wire        debug_stall,
    output wire [1:0]  debug_forward_a,
    output wire [1:0]  debug_forward_b
);

    // ========================================================================
    // Internal AXI Buses
    // ========================================================================
    // Master -> Interconnect
    wire [31:0] m_axi_awaddr;
    wire [2:0]  m_axi_awprot;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_araddr;
    wire [2:0]  m_axi_arprot;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;
    
    // Interconnect -> IMEM Slave
    wire [31:0] s0_axi_awaddr;
    wire [2:0]  s0_axi_awprot;
    wire        s0_axi_awvalid;
    wire        s0_axi_awready;
    wire [31:0] s0_axi_wdata;
    wire [3:0]  s0_axi_wstrb;
    wire        s0_axi_wvalid;
    wire        s0_axi_wready;
    wire [1:0]  s0_axi_bresp;
    wire        s0_axi_bvalid;
    wire        s0_axi_bready;
    wire [31:0] s0_axi_araddr;
    wire [2:0]  s0_axi_arprot;
    wire        s0_axi_arvalid;
    wire        s0_axi_arready;
    wire [31:0] s0_axi_rdata;
    wire [1:0]  s0_axi_rresp;
    wire        s0_axi_rvalid;
    wire        s0_axi_rready;
    
    // Interconnect -> DMEM Slave
    wire [31:0] s1_axi_awaddr;
    wire [2:0]  s1_axi_awprot;
    wire        s1_axi_awvalid;
    wire        s1_axi_awready;
    wire [31:0] s1_axi_wdata;
    wire [3:0]  s1_axi_wstrb;
    wire        s1_axi_wvalid;
    wire        s1_axi_wready;
    wire [1:0]  s1_axi_bresp;
    wire        s1_axi_bvalid;
    wire        s1_axi_bready;
    wire [31:0] s1_axi_araddr;
    wire [2:0]  s1_axi_arprot;
    wire        s1_axi_arvalid;
    wire        s1_axi_arready;
    wire [31:0] s1_axi_rdata;
    wire [1:0]  s1_axi_rresp;
    wire        s1_axi_rvalid;
    wire        s1_axi_rready;
    
    // ========================================================================
    // RISC-V Core với AXI Master Interface
    // ========================================================================
    riscv_core_axi cpu (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI Master Interface
        .M_AXI_AWADDR(m_axi_awaddr),
        .M_AXI_AWPROT(m_axi_awprot),
        .M_AXI_AWVALID(m_axi_awvalid),
        .M_AXI_AWREADY(m_axi_awready),
        
        .M_AXI_WDATA(m_axi_wdata),
        .M_AXI_WSTRB(m_axi_wstrb),
        .M_AXI_WVALID(m_axi_wvalid),
        .M_AXI_WREADY(m_axi_wready),
        
        .M_AXI_BRESP(m_axi_bresp),
        .M_AXI_BVALID(m_axi_bvalid),
        .M_AXI_BREADY(m_axi_bready),
        
        .M_AXI_ARADDR(m_axi_araddr),
        .M_AXI_ARPROT(m_axi_arprot),
        .M_AXI_ARVALID(m_axi_arvalid),
        .M_AXI_ARREADY(m_axi_arready),
        
        .M_AXI_RDATA(m_axi_rdata),
        .M_AXI_RRESP(m_axi_rresp),
        .M_AXI_RVALID(m_axi_rvalid),
        .M_AXI_RREADY(m_axi_rready),
        
        // Debug Outputs
        .debug_pc(debug_pc),
        .debug_instr(debug_instr),
        .debug_alu_result(debug_alu_result),
        .debug_mem_data(debug_mem_data),
        .debug_branch_taken(debug_branch_taken),
        .debug_branch_target(debug_branch_target),
        .debug_stall(debug_stall),
        .debug_forward_a(debug_forward_a),
        .debug_forward_b(debug_forward_b)
    );
    
    // ========================================================================
    // AXI4-Lite Interconnect (1 Master -> 2 Slaves)
    // ========================================================================
    axi4_lite_interconnect interconnect (
        .clk(clk),
        .rst_n(rst_n),
        
        // Master Port (from CPU)
        .M_AXI_AWADDR(m_axi_awaddr),
        .M_AXI_AWPROT(m_axi_awprot),
        .M_AXI_AWVALID(m_axi_awvalid),
        .M_AXI_AWREADY(m_axi_awready),
        .M_AXI_WDATA(m_axi_wdata),
        .M_AXI_WSTRB(m_axi_wstrb),
        .M_AXI_WVALID(m_axi_wvalid),
        .M_AXI_WREADY(m_axi_wready),
        .M_AXI_BRESP(m_axi_bresp),
        .M_AXI_BVALID(m_axi_bvalid),
        .M_AXI_BREADY(m_axi_bready),
        .M_AXI_ARADDR(m_axi_araddr),
        .M_AXI_ARPROT(m_axi_arprot),
        .M_AXI_ARVALID(m_axi_arvalid),
        .M_AXI_ARREADY(m_axi_arready),
        .M_AXI_RDATA(m_axi_rdata),
        .M_AXI_RRESP(m_axi_rresp),
        .M_AXI_RVALID(m_axi_rvalid),
        .M_AXI_RREADY(m_axi_rready),
        
        // Slave 0 Port (to IMEM)
        .S0_AXI_AWADDR(s0_axi_awaddr),
        .S0_AXI_AWPROT(s0_axi_awprot),
        .S0_AXI_AWVALID(s0_axi_awvalid),
        .S0_AXI_AWREADY(s0_axi_awready),
        .S0_AXI_WDATA(s0_axi_wdata),
        .S0_AXI_WSTRB(s0_axi_wstrb),
        .S0_AXI_WVALID(s0_axi_wvalid),
        .S0_AXI_WREADY(s0_axi_wready),
        .S0_AXI_BRESP(s0_axi_bresp),
        .S0_AXI_BVALID(s0_axi_bvalid),
        .S0_AXI_BREADY(s0_axi_bready),
        .S0_AXI_ARADDR(s0_axi_araddr),
        .S0_AXI_ARPROT(s0_axi_arprot),
        .S0_AXI_ARVALID(s0_axi_arvalid),
        .S0_AXI_ARREADY(s0_axi_arready),
        .S0_AXI_RDATA(s0_axi_rdata),
        .S0_AXI_RRESP(s0_axi_rresp),
        .S0_AXI_RVALID(s0_axi_rvalid),
        .S0_AXI_RREADY(s0_axi_rready),
        
        // Slave 1 Port (to DMEM)
        .S1_AXI_AWADDR(s1_axi_awaddr),
        .S1_AXI_AWPROT(s1_axi_awprot),
        .S1_AXI_AWVALID(s1_axi_awvalid),
        .S1_AXI_AWREADY(s1_axi_awready),
        .S1_AXI_WDATA(s1_axi_wdata),
        .S1_AXI_WSTRB(s1_axi_wstrb),
        .S1_AXI_WVALID(s1_axi_wvalid),
        .S1_AXI_WREADY(s1_axi_wready),
        .S1_AXI_BRESP(s1_axi_bresp),
        .S1_AXI_BVALID(s1_axi_bvalid),
        .S1_AXI_BREADY(s1_axi_bready),
        .S1_AXI_ARADDR(s1_axi_araddr),
        .S1_AXI_ARPROT(s1_axi_arprot),
        .S1_AXI_ARVALID(s1_axi_arvalid),
        .S1_AXI_ARREADY(s1_axi_arready),
        .S1_AXI_RDATA(s1_axi_rdata),
        .S1_AXI_RRESP(s1_axi_rresp),
        .S1_AXI_RVALID(s1_axi_rvalid),
        .S1_AXI_RREADY(s1_axi_rready)
    );
    
    // ========================================================================
    // Instruction Memory (AXI Slave 0)
    // ========================================================================
    inst_mem_axi_slave imem_slave (
        .clk(clk),
        .rst_n(rst_n),
        
        .S_AXI_AWADDR(s0_axi_awaddr),
        .S_AXI_AWPROT(s0_axi_awprot),
        .S_AXI_AWVALID(s0_axi_awvalid),
        .S_AXI_AWREADY(s0_axi_awready),
        
        .S_AXI_WDATA(s0_axi_wdata),
        .S_AXI_WSTRB(s0_axi_wstrb),
        .S_AXI_WVALID(s0_axi_wvalid),
        .S_AXI_WREADY(s0_axi_wready),
        
        .S_AXI_BRESP(s0_axi_bresp),
        .S_AXI_BVALID(s0_axi_bvalid),
        .S_AXI_BREADY(s0_axi_bready),
        
        .S_AXI_ARADDR(s0_axi_araddr),
        .S_AXI_ARPROT(s0_axi_arprot),
        .S_AXI_ARVALID(s0_axi_arvalid),
        .S_AXI_ARREADY(s0_axi_arready),
        
        .S_AXI_RDATA(s0_axi_rdata),
        .S_AXI_RRESP(s0_axi_rresp),
        .S_AXI_RVALID(s0_axi_rvalid),
        .S_AXI_RREADY(s0_axi_rready)
    );
    
    // ========================================================================
    // Data Memory (AXI Slave 1)
    // ========================================================================
    data_mem_axi_slave dmem_slave (
        .clk(clk),
        .rst_n(rst_n),
        
        .S_AXI_AWADDR(s1_axi_awaddr),
        .S_AXI_AWPROT(s1_axi_awprot),
        .S_AXI_AWVALID(s1_axi_awvalid),
        .S_AXI_AWREADY(s1_axi_awready),
        
        .S_AXI_WDATA(s1_axi_wdata),
        .S_AXI_WSTRB(s1_axi_wstrb),
        .S_AXI_WVALID(s1_axi_wvalid),
        .S_AXI_WREADY(s1_axi_wready),
        
        .S_AXI_BRESP(s1_axi_bresp),
        .S_AXI_BVALID(s1_axi_bvalid),
        .S_AXI_BREADY(s1_axi_bready),
        
        .S_AXI_ARADDR(s1_axi_araddr),
        .S_AXI_ARPROT(s1_axi_arprot),
        .S_AXI_ARVALID(s1_axi_arvalid),
        .S_AXI_ARREADY(s1_axi_arready),
        
        .S_AXI_RDATA(s1_axi_rdata),
        .S_AXI_RRESP(s1_axi_rresp),
        .S_AXI_RVALID(s1_axi_rvalid),
        .S_AXI_RREADY(s1_axi_rready)
    );

endmodule