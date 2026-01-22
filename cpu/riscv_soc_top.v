// ============================================================================
// Module: riscv_soc_top (WITH DEBUG PORTS)
// ============================================================================
`include "datapath.v"
`include "interface/imem_access_unit.v"
`include "interface/dmem_access_unit.v"
`include "memory/inst_mem_axi_slave.v"
`include "memory/data_mem_axi_slave.v"

module riscv_soc_top (
    input wire clk,
    input wire rst_n,
    
    // Debug outputs
    output wire [31:0] pc_current,
    output wire [31:0] instruction_current,
    
    // Debug: AXI IMEM signals
    output wire        S_AXI_IMEM_ARVALID,
    output wire        S_AXI_IMEM_ARREADY,
    output wire [31:0] S_AXI_IMEM_ARADDR,
    output wire        S_AXI_IMEM_RVALID,
    output wire        S_AXI_IMEM_RREADY,
    output wire [31:0] S_AXI_IMEM_RDATA,
    
    // Debug: AXI DMEM signals
    output wire        S_AXI_DMEM_AWVALID,
    output wire        S_AXI_DMEM_AWREADY,
    output wire [31:0] S_AXI_DMEM_AWADDR,
    output wire        S_AXI_DMEM_WVALID,
    output wire        S_AXI_DMEM_WREADY,
    output wire [31:0] S_AXI_DMEM_WDATA,
    output wire        S_AXI_DMEM_ARVALID,
    output wire        S_AXI_DMEM_ARREADY,
    output wire [31:0] S_AXI_DMEM_ARADDR,
    output wire        S_AXI_DMEM_RVALID,
    output wire        S_AXI_DMEM_RREADY,
    output wire [31:0] S_AXI_DMEM_RDATA
);

    // ========================================================================
    // Internal Signals - Datapath <-> IMEM Access Unit
    // ========================================================================
    wire [31:0] imem_addr;
    wire        imem_valid;
    wire [31:0] imem_rdata;
    wire        imem_ready;
    
    // ========================================================================
    // Internal Signals - Datapath <-> DMEM Access Unit
    // ========================================================================
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_valid;
    wire        dmem_we;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;
    
    // ========================================================================
    // AXI Signals - IMEM Master
    // ========================================================================
    wire [31:0] M0_AXI_AWADDR;
    wire [2:0]  M0_AXI_AWPROT;
    wire        M0_AXI_AWVALID;
    wire        M0_AXI_AWREADY;
    
    wire [31:0] M0_AXI_WDATA;
    wire [3:0]  M0_AXI_WSTRB;
    wire        M0_AXI_WVALID;
    wire        M0_AXI_WREADY;
    
    wire [1:0]  M0_AXI_BRESP;
    wire        M0_AXI_BVALID;
    wire        M0_AXI_BREADY;
    
    wire [31:0] M0_AXI_ARADDR;
    wire [2:0]  M0_AXI_ARPROT;
    wire        M0_AXI_ARVALID;
    wire        M0_AXI_ARREADY;
    
    wire [31:0] M0_AXI_RDATA;
    wire [1:0]  M0_AXI_RRESP;
    wire        M0_AXI_RVALID;
    wire        M0_AXI_RREADY;
    
    // ========================================================================
    // AXI Signals - DMEM Master
    // ========================================================================
    wire [31:0] M1_AXI_AWADDR;
    wire [2:0]  M1_AXI_AWPROT;
    wire        M1_AXI_AWVALID;
    wire        M1_AXI_AWREADY;
    
    wire [31:0] M1_AXI_WDATA;
    wire [3:0]  M1_AXI_WSTRB;
    wire        M1_AXI_WVALID;
    wire        M1_AXI_WREADY;
    
    wire [1:0]  M1_AXI_BRESP;
    wire        M1_AXI_BVALID;
    wire        M1_AXI_BREADY;
    
    wire [31:0] M1_AXI_ARADDR;
    wire [2:0]  M1_AXI_ARPROT;
    wire        M1_AXI_ARVALID;
    wire        M1_AXI_ARREADY;
    
    wire [31:0] M1_AXI_RDATA;
    wire [1:0]  M1_AXI_RRESP;
    wire        M1_AXI_RVALID;
    wire        M1_AXI_RREADY;
    
    // ========================================================================
    // AXI Signals - IMEM Slave
    // ========================================================================
    wire [31:0] S0_AXI_AWADDR;
    wire [2:0]  S0_AXI_AWPROT;
    wire        S0_AXI_AWVALID;
    wire        S0_AXI_AWREADY;
    
    wire [31:0] S0_AXI_WDATA;
    wire [3:0]  S0_AXI_WSTRB;
    wire        S0_AXI_WVALID;
    wire        S0_AXI_WREADY;
    
    wire [1:0]  S0_AXI_BRESP;
    wire        S0_AXI_BVALID;
    wire        S0_AXI_BREADY;
    
    wire [31:0] S0_AXI_ARADDR;
    wire [2:0]  S0_AXI_ARPROT;
    wire        S0_AXI_ARVALID;
    wire        S0_AXI_ARREADY;
    
    wire [31:0] S0_AXI_RDATA;
    wire [1:0]  S0_AXI_RRESP;
    wire        S0_AXI_RVALID;
    wire        S0_AXI_RREADY;
    
    // ========================================================================
    // AXI Signals - DMEM Slave
    // ========================================================================
    wire [31:0] S1_AXI_AWADDR;
    wire [2:0]  S1_AXI_AWPROT;
    wire        S1_AXI_AWVALID;
    wire        S1_AXI_AWREADY;
    
    wire [31:0] S1_AXI_WDATA;
    wire [3:0]  S1_AXI_WSTRB;
    wire        S1_AXI_WVALID;
    wire        S1_AXI_WREADY;
    
    wire [1:0]  S1_AXI_BRESP;
    wire        S1_AXI_BVALID;
    wire        S1_AXI_BREADY;
    
    wire [31:0] S1_AXI_ARADDR;
    wire [2:0]  S1_AXI_ARPROT;
    wire        S1_AXI_ARVALID;
    wire        S1_AXI_ARREADY;
    
    wire [31:0] S1_AXI_RDATA;
    wire [1:0]  S1_AXI_RRESP;
    wire        S1_AXI_RVALID;
    wire        S1_AXI_RREADY;
    
    // ========================================================================
    // Export AXI signals for debugging
    // ========================================================================
    assign S_AXI_IMEM_ARVALID = S0_AXI_ARVALID;
    assign S_AXI_IMEM_ARREADY = S0_AXI_ARREADY;
    assign S_AXI_IMEM_ARADDR  = S0_AXI_ARADDR;
    assign S_AXI_IMEM_RVALID  = S0_AXI_RVALID;
    assign S_AXI_IMEM_RREADY  = S0_AXI_RREADY;
    assign S_AXI_IMEM_RDATA   = S0_AXI_RDATA;
    
    assign S_AXI_DMEM_AWVALID = S1_AXI_AWVALID;
    assign S_AXI_DMEM_AWREADY = S1_AXI_AWREADY;
    assign S_AXI_DMEM_AWADDR  = S1_AXI_AWADDR;
    assign S_AXI_DMEM_WVALID  = S1_AXI_WVALID;
    assign S_AXI_DMEM_WREADY  = S1_AXI_WREADY;
    assign S_AXI_DMEM_WDATA   = S1_AXI_WDATA;
    assign S_AXI_DMEM_ARVALID = S1_AXI_ARVALID;
    assign S_AXI_DMEM_ARREADY = S1_AXI_ARREADY;
    assign S_AXI_DMEM_ARADDR  = S1_AXI_ARADDR;
    assign S_AXI_DMEM_RVALID  = S1_AXI_RVALID;
    assign S_AXI_DMEM_RREADY  = S1_AXI_RREADY;
    assign S_AXI_DMEM_RDATA   = S1_AXI_RDATA;
    
    // ========================================================================
    // Datapath Instance
    // ========================================================================
    datapath u_datapath (
        .clock(clk),
        .reset(~rst_n),
        
        // IMEM Interface
        .imem_addr(imem_addr),
        .imem_valid(imem_valid),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        
        // DMEM Interface
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_valid(dmem_valid),
        .dmem_we(dmem_we),
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready),
        
        // Debug outputs
        .pc_current(pc_current),
        .instruction_current(instruction_current),
        .alu_result_debug(),
        .mem_out_debug(),
        .branch_taken_debug(),
        .branch_target_debug(),
        .stall_debug(),
        .forward_a_debug(),
        .forward_b_debug()
    );
    
    // ========================================================================
    // IMEM Access Unit Instance
    // ========================================================================
    imem_access_unit u_imem_access (
        .clk(clk),
        .rst_n(rst_n),
        
        // IF Interface
        .if_addr(imem_addr),
        .if_req(imem_valid),
        .if_data(imem_rdata),
        .if_ready(imem_ready),
        .if_error(),
        
        // AXI Master Interface
        .M_AXI_AWADDR(M0_AXI_AWADDR),
        .M_AXI_AWPROT(M0_AXI_AWPROT),
        .M_AXI_AWVALID(M0_AXI_AWVALID),
        .M_AXI_AWREADY(M0_AXI_AWREADY),
        
        .M_AXI_WDATA(M0_AXI_WDATA),
        .M_AXI_WSTRB(M0_AXI_WSTRB),
        .M_AXI_WVALID(M0_AXI_WVALID),
        .M_AXI_WREADY(M0_AXI_WREADY),
        
        .M_AXI_BRESP(M0_AXI_BRESP),
        .M_AXI_BVALID(M0_AXI_BVALID),
        .M_AXI_BREADY(M0_AXI_BREADY),
        
        .M_AXI_ARADDR(M0_AXI_ARADDR),
        .M_AXI_ARPROT(M0_AXI_ARPROT),
        .M_AXI_ARVALID(M0_AXI_ARVALID),
        .M_AXI_ARREADY(M0_AXI_ARREADY),
        
        .M_AXI_RDATA(M0_AXI_RDATA),
        .M_AXI_RRESP(M0_AXI_RRESP),
        .M_AXI_RVALID(M0_AXI_RVALID),
        .M_AXI_RREADY(M0_AXI_RREADY)
    );
    
    // ========================================================================
    // DMEM Access Unit Instance
    // ========================================================================
    dmem_access_unit u_dmem_access (
        .clk(clk),
        .rst_n(rst_n),
        
        // MEM Interface
        .mem_addr(dmem_addr),
        .mem_wdata(dmem_wdata),
        .mem_wstrb(dmem_wstrb),
        .mem_req(dmem_valid),
        .mem_wr(dmem_we),
        .mem_rdata(dmem_rdata),
        .mem_ready(dmem_ready),
        .mem_error(),
        
        // AXI Master Interface
        .M_AXI_AWADDR(M1_AXI_AWADDR),
        .M_AXI_AWPROT(M1_AXI_AWPROT),
        .M_AXI_AWVALID(M1_AXI_AWVALID),
        .M_AXI_AWREADY(M1_AXI_AWREADY),
        
        .M_AXI_WDATA(M1_AXI_WDATA),
        .M_AXI_WSTRB(M1_AXI_WSTRB),
        .M_AXI_WVALID(M1_AXI_WVALID),
        .M_AXI_WREADY(M1_AXI_WREADY),
        
        .M_AXI_BRESP(M1_AXI_BRESP),
        .M_AXI_BVALID(M1_AXI_BVALID),
        .M_AXI_BREADY(M1_AXI_BREADY),
        
        .M_AXI_ARADDR(M1_AXI_ARADDR),
        .M_AXI_ARPROT(M1_AXI_ARPROT),
        .M_AXI_ARVALID(M1_AXI_ARVALID),
        .M_AXI_ARREADY(M1_AXI_ARREADY),
        
        .M_AXI_RDATA(M1_AXI_RDATA),
        .M_AXI_RRESP(M1_AXI_RRESP),
        .M_AXI_RVALID(M1_AXI_RVALID),
        .M_AXI_RREADY(M1_AXI_RREADY)
    );
    
    // ========================================================================
    // Direct connections - IMEM Master to IMEM Slave
    // ========================================================================
    assign S0_AXI_AWADDR  = M0_AXI_AWADDR;
    assign S0_AXI_AWPROT  = M0_AXI_AWPROT;
    assign S0_AXI_AWVALID = M0_AXI_AWVALID;
    assign M0_AXI_AWREADY = S0_AXI_AWREADY;
    
    assign S0_AXI_WDATA   = M0_AXI_WDATA;
    assign S0_AXI_WSTRB   = M0_AXI_WSTRB;
    assign S0_AXI_WVALID  = M0_AXI_WVALID;
    assign M0_AXI_WREADY  = S0_AXI_WREADY;
    
    assign M0_AXI_BRESP   = S0_AXI_BRESP;
    assign M0_AXI_BVALID  = S0_AXI_BVALID;
    assign S0_AXI_BREADY  = M0_AXI_BREADY;
    
    assign S0_AXI_ARADDR  = M0_AXI_ARADDR;
    assign S0_AXI_ARPROT  = M0_AXI_ARPROT;
    assign S0_AXI_ARVALID = M0_AXI_ARVALID;
    assign M0_AXI_ARREADY = S0_AXI_ARREADY;
    
    assign M0_AXI_RDATA   = S0_AXI_RDATA;
    assign M0_AXI_RRESP   = S0_AXI_RRESP;
    assign M0_AXI_RVALID  = S0_AXI_RVALID;
    assign S0_AXI_RREADY  = M0_AXI_RREADY;
    
    // ========================================================================
    // Direct connections - DMEM Master to DMEM Slave
    // ========================================================================
    assign S1_AXI_AWADDR  = M1_AXI_AWADDR;
    assign S1_AXI_AWPROT  = M1_AXI_AWPROT;
    assign S1_AXI_AWVALID = M1_AXI_AWVALID;
    assign M1_AXI_AWREADY = S1_AXI_AWREADY;
    
    assign S1_AXI_WDATA   = M1_AXI_WDATA;
    assign S1_AXI_WSTRB   = M1_AXI_WSTRB;
    assign S1_AXI_WVALID  = M1_AXI_WVALID;
    assign M1_AXI_WREADY  = S1_AXI_WREADY;
    
    assign M1_AXI_BRESP   = S1_AXI_BRESP;
    assign M1_AXI_BVALID  = S1_AXI_BVALID;
    assign S1_AXI_BREADY  = M1_AXI_BREADY;
    
    assign S1_AXI_ARADDR  = M1_AXI_ARADDR;
    assign S1_AXI_ARPROT  = M1_AXI_ARPROT;
    assign S1_AXI_ARVALID = M1_AXI_ARVALID;
    assign M1_AXI_ARREADY = S1_AXI_ARREADY;
    
    assign M1_AXI_RDATA   = S1_AXI_RDATA;
    assign M1_AXI_RRESP   = S1_AXI_RRESP;
    assign M1_AXI_RVALID  = S1_AXI_RVALID;
    assign S1_AXI_RREADY  = M1_AXI_RREADY;
    
    // ========================================================================
    // IMEM Slave Instance
    // ========================================================================
    inst_mem_axi_slave u_imem (
        .clk(clk),
        .rst_n(rst_n),
        
        .S_AXI_AWADDR(S0_AXI_AWADDR),
        .S_AXI_AWPROT(S0_AXI_AWPROT),
        .S_AXI_AWVALID(S0_AXI_AWVALID),
        .S_AXI_AWREADY(S0_AXI_AWREADY),
        
        .S_AXI_WDATA(S0_AXI_WDATA),
        .S_AXI_WSTRB(S0_AXI_WSTRB),
        .S_AXI_WVALID(S0_AXI_WVALID),
        .S_AXI_WREADY(S0_AXI_WREADY),
        
        .S_AXI_BRESP(S0_AXI_BRESP),
        .S_AXI_BVALID(S0_AXI_BVALID),
        .S_AXI_BREADY(S0_AXI_BREADY),
        
        .S_AXI_ARADDR(S0_AXI_ARADDR),
        .S_AXI_ARPROT(S0_AXI_ARPROT),
        .S_AXI_ARVALID(S0_AXI_ARVALID),
        .S_AXI_ARREADY(S0_AXI_ARREADY),
        
        .S_AXI_RDATA(S0_AXI_RDATA),
        .S_AXI_RRESP(S0_AXI_RRESP),
        .S_AXI_RVALID(S0_AXI_RVALID),
        .S_AXI_RREADY(S0_AXI_RREADY)
    );
    
    // ========================================================================
    // DMEM Slave Instance
    // ========================================================================
    data_mem_axi_slave u_dmem (
        .clk(clk),
        .rst_n(rst_n),
        
        .S_AXI_AWADDR(S1_AXI_AWADDR),
        .S_AXI_AWPROT(S1_AXI_AWPROT),
        .S_AXI_AWVALID(S1_AXI_AWVALID),
        .S_AXI_AWREADY(S1_AXI_AWREADY),
        
        .S_AXI_WDATA(S1_AXI_WDATA),
        .S_AXI_WSTRB(S1_AXI_WSTRB),
        .S_AXI_WVALID(S1_AXI_WVALID),
        .S_AXI_WREADY(S1_AXI_WREADY),
        
        .S_AXI_BRESP(S1_AXI_BRESP),
        .S_AXI_BVALID(S1_AXI_BVALID),
        .S_AXI_BREADY(S1_AXI_BREADY),
        
        .S_AXI_ARADDR(S1_AXI_ARADDR),
        .S_AXI_ARPROT(S1_AXI_ARPROT),
        .S_AXI_ARVALID(S1_AXI_ARVALID),
        .S_AXI_ARREADY(S1_AXI_ARREADY),
        
        .S_AXI_RDATA(S1_AXI_RDATA),
        .S_AXI_RRESP(S1_AXI_RRESP),
        .S_AXI_RVALID(S1_AXI_RVALID),
        .S_AXI_RREADY(S1_AXI_RREADY)
    );

endmodule