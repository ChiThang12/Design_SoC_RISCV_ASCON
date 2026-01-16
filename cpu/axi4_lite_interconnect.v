// ============================================================================
// axi4_lite_interconnect.v - Simple AXI4-Lite 1-to-2 Interconnect
// ============================================================================
// Mô tả:
//   - 1 Master (RISC-V Core) kết nối với 2 Slaves (IMEM + DMEM)
//   - Address decoding dựa trên MSB của địa chỉ
//   - Hỗ trợ cả READ và WRITE channels
// ============================================================================

module axi4_lite_interconnect (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Master Interface (từ RISC-V Core)
    // ========================================================================
    // Write Address Channel
    input wire [31:0]  M_AXI_AWADDR,
    input wire [2:0]   M_AXI_AWPROT,
    input wire         M_AXI_AWVALID,
    output wire        M_AXI_AWREADY,
    
    // Write Data Channel
    input wire [31:0]  M_AXI_WDATA,
    input wire [3:0]   M_AXI_WSTRB,
    input wire         M_AXI_WVALID,
    output wire        M_AXI_WREADY,
    
    // Write Response Channel
    output wire [1:0]  M_AXI_BRESP,
    output wire        M_AXI_BVALID,
    input wire         M_AXI_BREADY,
    
    // Read Address Channel
    input wire [31:0]  M_AXI_ARADDR,
    input wire [2:0]   M_AXI_ARPROT,
    input wire         M_AXI_ARVALID,
    output wire        M_AXI_ARREADY,
    
    // Read Data Channel
    output wire [31:0] M_AXI_RDATA,
    output wire [1:0]  M_AXI_RRESP,
    output wire        M_AXI_RVALID,
    input wire         M_AXI_RREADY,
    
    // ========================================================================
    // Slave 0 Interface (Instruction Memory)
    // ========================================================================
    // Write Address Channel
    output wire [31:0] S0_AXI_AWADDR,
    output wire [2:0]  S0_AXI_AWPROT,
    output wire        S0_AXI_AWVALID,
    input wire         S0_AXI_AWREADY,
    
    // Write Data Channel
    output wire [31:0] S0_AXI_WDATA,
    output wire [3:0]  S0_AXI_WSTRB,
    output wire        S0_AXI_WVALID,
    input wire         S0_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]   S0_AXI_BRESP,
    input wire         S0_AXI_BVALID,
    output wire        S0_AXI_BREADY,
    
    // Read Address Channel
    output wire [31:0] S0_AXI_ARADDR,
    output wire [2:0]  S0_AXI_ARPROT,
    output wire        S0_AXI_ARVALID,
    input wire         S0_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  S0_AXI_RDATA,
    input wire [1:0]   S0_AXI_RRESP,
    input wire         S0_AXI_RVALID,
    output wire        S0_AXI_RREADY,
    
    // ========================================================================
    // Slave 1 Interface (Data Memory)
    // ========================================================================
    // Write Address Channel
    output wire [31:0] S1_AXI_AWADDR,
    output wire [2:0]  S1_AXI_AWPROT,
    output wire        S1_AXI_AWVALID,
    input wire         S1_AXI_AWREADY,
    
    // Write Data Channel
    output wire [31:0] S1_AXI_WDATA,
    output wire [3:0]  S1_AXI_WSTRB,
    output wire        S1_AXI_WVALID,
    input wire         S1_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]   S1_AXI_BRESP,
    input wire         S1_AXI_BVALID,
    output wire        S1_AXI_BREADY,
    
    // Read Address Channel
    output wire [31:0] S1_AXI_ARADDR,
    output wire [2:0]  S1_AXI_ARPROT,
    output wire        S1_AXI_ARVALID,
    input wire         S1_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  S1_AXI_RDATA,
    input wire [1:0]   S1_AXI_RRESP,
    input wire         S1_AXI_RVALID,
    output wire        S1_AXI_RREADY
);

    // ========================================================================
    // Address Decoding Parameters
    // ========================================================================
    // IMEM: 0x00000000 - 0x0FFFFFFF (256MB)
    // DMEM: 0x10000000 - 0x1FFFFFFF (256MB)
    localparam [31:0] IMEM_BASE = 32'h00000000;
    localparam [31:0] IMEM_MASK = 32'hF0000000;
    localparam [31:0] DMEM_BASE = 32'h10000000;
    localparam [31:0] DMEM_MASK = 32'hF0000000;
    
    // ========================================================================
    // Address Decode Functions
    // ========================================================================
    function addr_decode_wr;
        input [31:0] addr;
        begin
            if ((addr & IMEM_MASK) == (IMEM_BASE & IMEM_MASK))
                addr_decode_wr = 1'b0;  // IMEM
            else if ((addr & DMEM_MASK) == (DMEM_BASE & DMEM_MASK))
                addr_decode_wr = 1'b1;  // DMEM
            else
                addr_decode_wr = 1'b1;  // Default to DMEM
        end
    endfunction
    
    function addr_decode_rd;
        input [31:0] addr;
        begin
            if ((addr & IMEM_MASK) == (IMEM_BASE & IMEM_MASK))
                addr_decode_rd = 1'b0;  // IMEM
            else if ((addr & DMEM_MASK) == (DMEM_BASE & DMEM_MASK))
                addr_decode_rd = 1'b1;  // DMEM
            else
                addr_decode_rd = 1'b1;  // Default to DMEM
        end
    endfunction
    
    // ========================================================================
    // Write Channel Routing
    // ========================================================================
    reg wr_slave_sel;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_slave_sel <= 1'b0;
        end else if (M_AXI_AWVALID && M_AXI_AWREADY) begin
            wr_slave_sel <= addr_decode_wr(M_AXI_AWADDR);
        end
    end
    
    // Write Address Channel
    assign S0_AXI_AWADDR  = M_AXI_AWADDR;
    assign S0_AXI_AWPROT  = M_AXI_AWPROT;
    assign S0_AXI_AWVALID = M_AXI_AWVALID && !addr_decode_wr(M_AXI_AWADDR);
    
    assign S1_AXI_AWADDR  = M_AXI_AWADDR;
    assign S1_AXI_AWPROT  = M_AXI_AWPROT;
    assign S1_AXI_AWVALID = M_AXI_AWVALID && addr_decode_wr(M_AXI_AWADDR);
    
    assign M_AXI_AWREADY = addr_decode_wr(M_AXI_AWADDR) ? S1_AXI_AWREADY : S0_AXI_AWREADY;
    
    // Write Data Channel
    assign S0_AXI_WDATA  = M_AXI_WDATA;
    assign S0_AXI_WSTRB  = M_AXI_WSTRB;
    assign S0_AXI_WVALID = M_AXI_WVALID && !wr_slave_sel;
    
    assign S1_AXI_WDATA  = M_AXI_WDATA;
    assign S1_AXI_WSTRB  = M_AXI_WSTRB;
    assign S1_AXI_WVALID = M_AXI_WVALID && wr_slave_sel;
    
    assign M_AXI_WREADY = wr_slave_sel ? S1_AXI_WREADY : S0_AXI_WREADY;
    
    // Write Response Channel
    assign M_AXI_BRESP  = wr_slave_sel ? S1_AXI_BRESP  : S0_AXI_BRESP;
    assign M_AXI_BVALID = wr_slave_sel ? S1_AXI_BVALID : S0_AXI_BVALID;
    
    assign S0_AXI_BREADY = M_AXI_BREADY && !wr_slave_sel;
    assign S1_AXI_BREADY = M_AXI_BREADY && wr_slave_sel;
    
    // ========================================================================
    // Read Channel Routing
    // ========================================================================
    reg rd_slave_sel;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_slave_sel <= 1'b0;
        end else if (M_AXI_ARVALID && M_AXI_ARREADY) begin
            rd_slave_sel <= addr_decode_rd(M_AXI_ARADDR);
        end
    end
    
    // Read Address Channel
    assign S0_AXI_ARADDR  = M_AXI_ARADDR;
    assign S0_AXI_ARPROT  = M_AXI_ARPROT;
    assign S0_AXI_ARVALID = M_AXI_ARVALID && !addr_decode_rd(M_AXI_ARADDR);
    
    assign S1_AXI_ARADDR  = M_AXI_ARADDR;
    assign S1_AXI_ARPROT  = M_AXI_ARPROT;
    assign S1_AXI_ARVALID = M_AXI_ARVALID && addr_decode_rd(M_AXI_ARADDR);
    
    assign M_AXI_ARREADY = addr_decode_rd(M_AXI_ARADDR) ? S1_AXI_ARREADY : S0_AXI_ARREADY;
    
    // Read Data Channel
    assign M_AXI_RDATA  = rd_slave_sel ? S1_AXI_RDATA  : S0_AXI_RDATA;
    assign M_AXI_RRESP  = rd_slave_sel ? S1_AXI_RRESP  : S0_AXI_RRESP;
    assign M_AXI_RVALID = rd_slave_sel ? S1_AXI_RVALID : S0_AXI_RVALID;
    
    assign S0_AXI_RREADY = M_AXI_RREADY && !rd_slave_sel;
    assign S1_AXI_RREADY = M_AXI_RREADY && rd_slave_sel;
    
    // ========================================================================
    // Debug Monitor
    // ========================================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (M_AXI_AWVALID && M_AXI_AWREADY) begin
            $display("[INTERCONNECT] Write addr=0x%08h -> Slave %0d, time=%0t",
                     M_AXI_AWADDR, addr_decode_wr(M_AXI_AWADDR), $time);
        end
        if (M_AXI_ARVALID && M_AXI_ARREADY) begin
            $display("[INTERCONNECT] Read addr=0x%08h -> Slave %0d, time=%0t",
                     M_AXI_ARADDR, addr_decode_rd(M_AXI_ARADDR), $time);
        end
    end
    // synthesis translate_on

endmodule