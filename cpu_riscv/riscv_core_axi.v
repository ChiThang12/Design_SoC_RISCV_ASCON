// ============================================================================
// riscv_core_axi.v - RISC-V CPU Core with AXI4-Lite Interface
// ============================================================================
// Description:
//   - Wrapper integrating datapath.v with your existing AXI modules
//   - Uses mem_access_unit.v for IF/MEM arbitration and AXI conversion
//   - Compatible with your axi_interconnect, memory slaves, etc.
// ============================================================================

`include "datapath.v"
`include "interface/mem_access_unit.v"
//`include "interface/axi4_lite_master_if.v"
//`include "address_decoder.v"

module riscv_core_axi (
    input wire clk,
    input wire rst_n,         // Active low reset
    
    // ========================================================================
    // AXI4-Lite Master Interface
    // ========================================================================
    // Write Address Channel
    output wire [31:0] M_AXI_AWADDR,
    output wire [2:0]  M_AXI_AWPROT,
    output wire        M_AXI_AWVALID,
    input wire         M_AXI_AWREADY,
    
    // Write Data Channel
    output wire [31:0] M_AXI_WDATA,
    output wire [3:0]  M_AXI_WSTRB,
    output wire        M_AXI_WVALID,
    input wire         M_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]   M_AXI_BRESP,
    input wire         M_AXI_BVALID,
    output wire        M_AXI_BREADY,
    
    // Read Address Channel
    output wire [31:0] M_AXI_ARADDR,
    output wire [2:0]  M_AXI_ARPROT,
    output wire        M_AXI_ARVALID,
    input wire         M_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  M_AXI_RDATA,
    input wire [1:0]   M_AXI_RRESP,
    input wire         M_AXI_RVALID,
    output wire        M_AXI_RREADY,
    
    // ========================================================================
    // Debug Outputs (Optional)
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
    // Reset Conversion
    // ========================================================================
    wire reset = ~rst_n;
    
    // ========================================================================
    // CPU <-> Memory Access Unit Interface
    // ========================================================================
    wire [31:0] if_addr;
    wire        if_req;
    wire [31:0] if_data;
    wire        if_ready;
    wire        if_error;
    
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_req;
    wire        mem_wr;
    wire [31:0] mem_rdata;
    wire        mem_ready;
    wire        mem_error;
    
    // ========================================================================
    // RISC-V CPU Core Instance (datapath.v)
    // ========================================================================
    datapath cpu_core (
        .clk(clk),
        .reset(reset),
        
        // Instruction Memory Interface
        .imem_addr(if_addr),
        .imem_req(if_req),
        .imem_data(if_data),
        .imem_ready(if_ready),
        
        // Data Memory Interface
        .dmem_addr(mem_addr),
        .dmem_wdata(mem_wdata),
        .dmem_wstrb(mem_wstrb),
        .dmem_req(mem_req),
        .dmem_wr(mem_wr),
        .dmem_rdata(mem_rdata),
        .dmem_ready(mem_ready),
        
        // Debug Outputs
        .pc_current(debug_pc),
        .instruction_current(debug_instr),
        .alu_result_debug(debug_alu_result),
        .mem_out_debug(debug_mem_data),
        .branch_taken_debug(debug_branch_taken),
        .branch_target_debug(debug_branch_target),
        .stall_debug(debug_stall),
        .forward_a_debug(debug_forward_a),
        .forward_b_debug(debug_forward_b)
    );
    
    // ========================================================================
    // Memory Access Unit - Converts simple interface to AXI
    // Uses your existing mem_access_unit.v
    // ========================================================================
    mem_access_unit mau (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU Side - Instruction Fetch
        .if_addr(if_addr),
        .if_req(if_req),
        .if_data(if_data),
        .if_ready(if_ready),
        .if_error(if_error),
        
        // CPU Side - Data Memory
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_req(mem_req),
        .mem_wr(mem_wr),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .mem_error(mem_error),
        
        // AXI Master Interface
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWPROT(M_AXI_AWPROT),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );

endmodule