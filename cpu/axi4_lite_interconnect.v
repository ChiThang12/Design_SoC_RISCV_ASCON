// ============================================================================
// axi4_lite_interconnect.v - 1-to-2 AXI4-Lite Interconnect (FIXED)
// ============================================================================
// Description:
//   - Routes AXI transactions from 1 master to 2 slaves based on address
//   - Memory Map:
//     * Slave 0 (IMEM): 0x00000000 - 0x0FFFFFFF (256MB) - READ ONLY
//     * Slave 1 (DMEM): 0x10000000 - 0x1FFFFFFF (256MB) - READ/WRITE
// ============================================================================

module axi4_lite_interconnect (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Master Interface (from RISC-V Core)
    // ========================================================================
    // Write Address Channel
    input wire [31:0]  M_AXI_AWADDR,
    input wire [2:0]   M_AXI_AWPROT,
    input wire         M_AXI_AWVALID,
    output reg         M_AXI_AWREADY,
    
    // Write Data Channel
    input wire [31:0]  M_AXI_WDATA,
    input wire [3:0]   M_AXI_WSTRB,
    input wire         M_AXI_WVALID,
    output reg         M_AXI_WREADY,
    
    // Write Response Channel
    output reg [1:0]   M_AXI_BRESP,
    output reg         M_AXI_BVALID,
    input wire         M_AXI_BREADY,
    
    // Read Address Channel
    input wire [31:0]  M_AXI_ARADDR,
    input wire [2:0]   M_AXI_ARPROT,
    input wire         M_AXI_ARVALID,
    output reg         M_AXI_ARREADY,
    
    // Read Data Channel
    output reg [31:0]  M_AXI_RDATA,
    output reg [1:0]   M_AXI_RRESP,
    output reg         M_AXI_RVALID,
    input wire         M_AXI_RREADY,
    
    // ========================================================================
    // Slave 0 Interface (Instruction Memory)
    // ========================================================================
    // Write Address Channel
    output reg [31:0]  S0_AXI_AWADDR,
    output reg [2:0]   S0_AXI_AWPROT,
    output reg         S0_AXI_AWVALID,
    input wire         S0_AXI_AWREADY,
    
    // Write Data Channel
    output reg [31:0]  S0_AXI_WDATA,
    output reg [3:0]   S0_AXI_WSTRB,
    output reg         S0_AXI_WVALID,
    input wire         S0_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]   S0_AXI_BRESP,
    input wire         S0_AXI_BVALID,
    output reg         S0_AXI_BREADY,
    
    // Read Address Channel
    output reg [31:0]  S0_AXI_ARADDR,
    output reg [2:0]   S0_AXI_ARPROT,
    output reg         S0_AXI_ARVALID,
    input wire         S0_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  S0_AXI_RDATA,
    input wire [1:0]   S0_AXI_RRESP,
    input wire         S0_AXI_RVALID,
    output reg         S0_AXI_RREADY,
    
    // ========================================================================
    // Slave 1 Interface (Data Memory)
    // ========================================================================
    // Write Address Channel
    output reg [31:0]  S1_AXI_AWADDR,
    output reg [2:0]   S1_AXI_AWPROT,
    output reg         S1_AXI_AWVALID,
    input wire         S1_AXI_AWREADY,
    
    // Write Data Channel
    output reg [31:0]  S1_AXI_WDATA,
    output reg [3:0]   S1_AXI_WSTRB,
    output reg         S1_AXI_WVALID,
    input wire         S1_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]   S1_AXI_BRESP,
    input wire         S1_AXI_BVALID,
    output reg         S1_AXI_BREADY,
    
    // Read Address Channel
    output reg [31:0]  S1_AXI_ARADDR,
    output reg [2:0]   S1_AXI_ARPROT,
    output reg         S1_AXI_ARVALID,
    input wire         S1_AXI_ARREADY,
    
    // Read Data Channel
    input wire [31:0]  S1_AXI_RDATA,
    input wire [1:0]   S1_AXI_RRESP,
    input wire         S1_AXI_RVALID,
    output reg         S1_AXI_RREADY
);

    // ========================================================================
    // Address Decoding Parameters - FIXED!
    // ========================================================================
    // Memory Map:
    //   IMEM: 0x00000000 - 0x0FFFFFFF (bit [31:28] = 4'h0)
    //   DMEM: 0x10000000 - 0x1FFFFFFF (bit [31:28] = 4'h1)
    
    // ========================================================================
    // AXI Response Codes
    // ========================================================================
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;  // Decode error
    
    // ========================================================================
    // Slave Selection
    // ========================================================================
    reg [1:0] wr_slave_sel;  // 00: IMEM, 01: DMEM, 11: Invalid
    reg [1:0] rd_slave_sel;  // 00: IMEM, 01: DMEM, 11: Invalid
    
    // Write address decode
    always @(*) begin
        if (M_AXI_AWADDR[31:28] == 4'h0) begin
            wr_slave_sel = 2'b00;  // IMEM
        end else if (M_AXI_AWADDR[31:28] == 4'h1) begin
            wr_slave_sel = 2'b01;  // DMEM
        end else begin
            wr_slave_sel = 2'b11;  // Invalid - DECERR
        end
    end
    
    // Read address decode
    always @(*) begin
        if (M_AXI_ARADDR[31:28] == 4'h0) begin
            rd_slave_sel = 2'b00;  // IMEM
        end else if (M_AXI_ARADDR[31:28] == 4'h1) begin
            rd_slave_sel = 2'b01;  // DMEM
        end else begin
            rd_slave_sel = 2'b11;  // Invalid - DECERR
        end
    end
    
    // ========================================================================
    // Write Address Channel Routing
    // ========================================================================
    always @(*) begin
        // Default values
        S0_AXI_AWADDR  = 32'h0;
        S0_AXI_AWPROT  = 3'h0;
        S0_AXI_AWVALID = 1'b0;
        S1_AXI_AWADDR  = 32'h0;
        S1_AXI_AWPROT  = 3'h0;
        S1_AXI_AWVALID = 1'b0;
        
        case (wr_slave_sel)
            2'b00: begin  // IMEM
                S0_AXI_AWADDR  = M_AXI_AWADDR;
                S0_AXI_AWPROT  = M_AXI_AWPROT;
                S0_AXI_AWVALID = M_AXI_AWVALID;
                M_AXI_AWREADY  = S0_AXI_AWREADY;
            end
            
            2'b01: begin  // DMEM
                S1_AXI_AWADDR  = M_AXI_AWADDR;
                S1_AXI_AWPROT  = M_AXI_AWPROT;
                S1_AXI_AWVALID = M_AXI_AWVALID;
                M_AXI_AWREADY  = S1_AXI_AWREADY;
            end
            
            default: begin  // Invalid address
                M_AXI_AWREADY  = 1'b1;  // Accept but will return DECERR
            end
        endcase
    end
    
    // ========================================================================
    // Write Data Channel Routing
    // ========================================================================
    always @(*) begin
        // Default values
        S0_AXI_WDATA  = 32'h0;
        S0_AXI_WSTRB  = 4'h0;
        S0_AXI_WVALID = 1'b0;
        S1_AXI_WDATA  = 32'h0;
        S1_AXI_WSTRB  = 4'h0;
        S1_AXI_WVALID = 1'b0;
        
        case (wr_slave_sel)
            2'b00: begin  // IMEM
                S0_AXI_WDATA  = M_AXI_WDATA;
                S0_AXI_WSTRB  = M_AXI_WSTRB;
                S0_AXI_WVALID = M_AXI_WVALID;
                M_AXI_WREADY  = S0_AXI_WREADY;
            end
            
            2'b01: begin  // DMEM
                S1_AXI_WDATA  = M_AXI_WDATA;
                S1_AXI_WSTRB  = M_AXI_WSTRB;
                S1_AXI_WVALID = M_AXI_WVALID;
                M_AXI_WREADY  = S1_AXI_WREADY;
            end
            
            default: begin  // Invalid address
                M_AXI_WREADY  = 1'b1;  // Accept but will return DECERR
            end
        endcase
    end
    
    // ========================================================================
    // Write Response Channel Routing
    // ========================================================================
    always @(*) begin
        // Default values
        S0_AXI_BREADY = 1'b0;
        S1_AXI_BREADY = 1'b0;
        
        case (wr_slave_sel)
            2'b00: begin  // IMEM
                M_AXI_BRESP  = S0_AXI_BRESP;
                M_AXI_BVALID = S0_AXI_BVALID;
                S0_AXI_BREADY = M_AXI_BREADY;
            end
            
            2'b01: begin  // DMEM
                M_AXI_BRESP  = S1_AXI_BRESP;
                M_AXI_BVALID = S1_AXI_BVALID;
                S1_AXI_BREADY = M_AXI_BREADY;
            end
            
            default: begin  // Invalid address - return DECERR
                M_AXI_BRESP  = RESP_DECERR;
                M_AXI_BVALID = M_AXI_WVALID;  // Return error immediately
            end
        endcase
    end
    
    // ========================================================================
    // Read Address Channel Routing
    // ========================================================================
    always @(*) begin
        // Default values
        S0_AXI_ARADDR  = 32'h0;
        S0_AXI_ARPROT  = 3'h0;
        S0_AXI_ARVALID = 1'b0;
        S1_AXI_ARADDR  = 32'h0;
        S1_AXI_ARPROT  = 3'h0;
        S1_AXI_ARVALID = 1'b0;
        
        case (rd_slave_sel)
            2'b00: begin  // IMEM
                S0_AXI_ARADDR  = M_AXI_ARADDR;
                S0_AXI_ARPROT  = M_AXI_ARPROT;
                S0_AXI_ARVALID = M_AXI_ARVALID;
                M_AXI_ARREADY  = S0_AXI_ARREADY;
            end
            
            2'b01: begin  // DMEM
                S1_AXI_ARADDR  = M_AXI_ARADDR;
                S1_AXI_ARPROT  = M_AXI_ARPROT;
                S1_AXI_ARVALID = M_AXI_ARVALID;
                M_AXI_ARREADY  = S1_AXI_ARREADY;
            end
            
            default: begin  // Invalid address
                M_AXI_ARREADY  = 1'b1;  // Accept but will return DECERR
            end
        endcase
    end
    
    // ========================================================================
    // Read Data Channel Routing
    // ========================================================================
    always @(*) begin
        // Default values
        S0_AXI_RREADY = 1'b0;
        S1_AXI_RREADY = 1'b0;
        
        case (rd_slave_sel)
            2'b00: begin  // IMEM
                M_AXI_RDATA  = S0_AXI_RDATA;
                M_AXI_RRESP  = S0_AXI_RRESP;
                M_AXI_RVALID = S0_AXI_RVALID;
                S0_AXI_RREADY = M_AXI_RREADY;
            end
            
            2'b01: begin  // DMEM
                M_AXI_RDATA  = S1_AXI_RDATA;
                M_AXI_RRESP  = S1_AXI_RRESP;
                M_AXI_RVALID = S1_AXI_RVALID;
                S1_AXI_RREADY = M_AXI_RREADY;
            end
            
            default: begin  // Invalid address - return DECERR
                M_AXI_RDATA  = 32'hDEADBEEF;  // Error pattern
                M_AXI_RRESP  = RESP_DECERR;
                M_AXI_RVALID = M_AXI_ARVALID;  // Return error immediately
            end
        endcase
    end
    
    // ========================================================================
    // Debug Messages
    // ========================================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n) begin
            // Write transactions
            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                case (wr_slave_sel)
                    2'b00: $display("[INTERCONNECT] Write addr=0x%08h -> Slave 0 (IMEM), time=%0t", M_AXI_AWADDR, $time);
                    2'b01: $display("[INTERCONNECT] Write addr=0x%08h -> Slave 1 (DMEM), time=%0t", M_AXI_AWADDR, $time);
                    default: $display("[INTERCONNECT] Write addr=0x%08h -> INVALID (DECERR), time=%0t", M_AXI_AWADDR, $time);
                endcase
            end
            
            // Read transactions
            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                case (rd_slave_sel)
                    2'b00: $display("[INTERCONNECT] Read addr=0x%08h -> Slave 0 (IMEM), time=%0t", M_AXI_ARADDR, $time);
                    2'b01: $display("[INTERCONNECT] Read addr=0x%08h -> Slave 1 (DMEM), time=%0t", M_AXI_ARADDR, $time);
                    default: $display("[INTERCONNECT] Read addr=0x%08h -> INVALID (DECERR), time=%0t", M_AXI_ARADDR, $time);
                endcase
            end
        end
    end
    // synthesis translate_on

endmodule