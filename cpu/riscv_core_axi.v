// ============================================================================
// riscv_core_axi.v - RISC-V CPU Core với Dual AXI4-Lite Bus Interface
// ============================================================================
// Mô tả:
//   - CPU core RISC-V 32-bit pipeline
//   - Kết nối với memory qua 2 AXI4-Lite bus riêng biệt (Harvard Architecture)
//   - IMEM: Instruction Memory AXI Master (chỉ READ)
//   - DMEM: Data Memory AXI Master (READ + WRITE)
//   - Không cần arbitration - truy cập song song
// ============================================================================

`include "datapath.v"
`include "interface/imem_access_unit.v"
`include "interface/dmem_access_unit.v"

module riscv_core_axi (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4-Lite Master Interface 0 - INSTRUCTION MEMORY
    // ========================================================================
    
    // Write Address Channel (không sử dụng cho IMEM)
    output wire [31:0] M0_AXI_AWADDR,
    output wire [2:0]  M0_AXI_AWPROT,
    output wire        M0_AXI_AWVALID,
    input wire         M0_AXI_AWREADY,
    
    // Write Data Channel (không sử dụng cho IMEM)
    output wire [31:0] M0_AXI_WDATA,
    output wire [3:0]  M0_AXI_WSTRB,
    output wire        M0_AXI_WVALID,
    input wire         M0_AXI_WREADY,
    
    // Write Response Channel (không sử dụng cho IMEM)
    input wire [1:0]   M0_AXI_BRESP,
    input wire         M0_AXI_BVALID,
    output wire        M0_AXI_BREADY,
    
    // Read Address Channel
    output wire [31:0] M0_AXI_ARADDR,
    output wire [2:0]  M0_AXI_ARPROT,
    output wire        M0_AXI_ARVALID,
    input wire         M0_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  M0_AXI_RDATA,
    input wire [1:0]   M0_AXI_RRESP,
    input wire         M0_AXI_RVALID,
    output wire        M0_AXI_RREADY,
    
    // ========================================================================
    // AXI4-Lite Master Interface 1 - DATA MEMORY
    // ========================================================================
    
    // Write Address Channel
    output wire [31:0] M1_AXI_AWADDR,
    output wire [2:0]  M1_AXI_AWPROT,
    output wire        M1_AXI_AWVALID,
    input wire         M1_AXI_AWREADY,
    
    // Write Data Channel
    output wire [31:0] M1_AXI_WDATA,
    output wire [3:0]  M1_AXI_WSTRB,
    output wire        M1_AXI_WVALID,
    input wire         M1_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]   M1_AXI_BRESP,
    input wire         M1_AXI_BVALID,
    output wire        M1_AXI_BREADY,
    
    // Read Address Channel
    output wire [31:0] M1_AXI_ARADDR,
    output wire [2:0]  M1_AXI_ARPROT,
    output wire        M1_AXI_ARVALID,
    input wire         M1_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  M1_AXI_RDATA,
    input wire [1:0]   M1_AXI_RRESP,
    input wire         M1_AXI_RVALID,
    output wire        M1_AXI_RREADY,
    
    // ========================================================================
    // Debug/Monitor Signals (optional)
    // ========================================================================
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire [31:0] debug_alu_result,
    output wire        debug_stall,
    output wire        debug_branch_taken
);

    // ========================================================================
    // Reset Synchronization
    // ========================================================================
    wire reset = ~rst_n;
    
    // ========================================================================
    // Datapath <-> Memory Interface Signals
    // ========================================================================
    
    // Instruction Memory Interface
    wire [31:0] imem_addr;
    wire        imem_valid;
    wire [31:0] imem_rdata;
    wire        imem_ready;
    
    // Data Memory Interface
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_valid;
    wire        dmem_we;
    wire [31:0] dmem_rdata;
    wire        dmem_ready;
    
    // ========================================================================
    // Datapath Instance - CPU Core Pipeline
    // ========================================================================
    datapath cpu_datapath (
        .clock(clk),
        .reset(reset),
        
        // Instruction Memory Interface
        .imem_addr(imem_addr),
        .imem_valid(imem_valid),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        
        // Data Memory Interface
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_wstrb(dmem_wstrb),
        .dmem_valid(dmem_valid),
        .dmem_we(dmem_we),
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready),
        
        // Debug outputs
        .pc_current(debug_pc),
        .instruction_current(debug_instruction),
        .alu_result_debug(debug_alu_result),
        .mem_out_debug(),
        .branch_taken_debug(debug_branch_taken),
        .branch_target_debug(),
        .stall_debug(debug_stall),
        .forward_a_debug(),
        .forward_b_debug()
    );
    
    // ========================================================================
    // IMEM Access Unit - Instruction Fetch AXI Master
    // ========================================================================
    wire if_error;
    
    imem_access_unit imem_master (
        .clk(clk),
        .rst_n(rst_n),
        
        // Instruction Fetch Interface (từ datapath)
        .if_addr(imem_addr),
        .if_req(imem_valid),
        .if_data(imem_rdata),
        .if_ready(imem_ready),
        .if_error(if_error),
        
        // AXI4-Lite Master Interface 0 (IMEM)
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
    // DMEM Access Unit - Data Memory AXI Master
    // ========================================================================
    wire mem_error;
    
    dmem_access_unit dmem_master (
        .clk(clk),
        .rst_n(rst_n),
        
        // Data Memory Interface (từ datapath)
        .mem_addr(dmem_addr),
        .mem_wdata(dmem_wdata),
        .mem_wstrb(dmem_wstrb),
        .mem_req(dmem_valid),
        .mem_wr(dmem_we),
        .mem_rdata(dmem_rdata),
        .mem_ready(dmem_ready),
        .mem_error(mem_error),
        
        // AXI4-Lite Master Interface 1 (DMEM)
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
    // Error Handling (Optional - có thể mở rộng)
    // ========================================================================
    // Có thể thêm logic xử lý lỗi bus ở đây nếu cần
    // Ví dụ:
    // - Halt CPU khi có bus error
    // - Generate exception cho software handler
    // - Log error cho debug
    
    // Error detection
    wire bus_error = if_error | mem_error;
    
    // TODO: Implement error handling logic
    // - Exception generation
    // - Error logging
    // - CPU halt/recovery

endmodule