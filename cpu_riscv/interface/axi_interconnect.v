// ============================================================================
// axi_interconnect.v - AXI4-Lite Interconnect (1 Master to 3 Slaves)
// ============================================================================
// Mô tả:
//   - Kết nối 1 AXI Master (CPU) với 3 AXI Slaves (IMEM, DMEM, ASCON)
//   - Sử dụng address_decoder để route transactions
//   - Multiplexing read/write responses về master
// ============================================================================

module axi_interconnect (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI Master Interface (từ CPU/mem_access_unit)
    // ========================================================================
    
    // Write Address Channel
    input wire [31:0] M_AXI_AWADDR,
    input wire [2:0]  M_AXI_AWPROT,
    input wire        M_AXI_AWVALID,
    output reg        M_AXI_AWREADY,
    
    // Write Data Channel
    input wire [31:0] M_AXI_WDATA,
    input wire [3:0]  M_AXI_WSTRB,
    input wire        M_AXI_WVALID,
    output reg        M_AXI_WREADY,
    
    // Write Response Channel
    output reg [1:0]  M_AXI_BRESP,
    output reg        M_AXI_BVALID,
    input wire        M_AXI_BREADY,
    
    // Read Address Channel
    input wire [31:0] M_AXI_ARADDR,
    input wire [2:0]  M_AXI_ARPROT,
    input wire        M_AXI_ARVALID,
    output reg        M_AXI_ARREADY,
    
    // Read Data Channel
    output reg [31:0] M_AXI_RDATA,
    output reg [1:0]  M_AXI_RRESP,
    output reg        M_AXI_RVALID,
    input wire        M_AXI_RREADY,
    
    // ========================================================================
    // AXI Slave 0: Instruction Memory (IMEM)
    // ========================================================================
    output wire [31:0] S0_AXI_AWADDR,
    output wire [2:0]  S0_AXI_AWPROT,
    output wire        S0_AXI_AWVALID,
    input wire         S0_AXI_AWREADY,
    
    output wire [31:0] S0_AXI_WDATA,
    output wire [3:0]  S0_AXI_WSTRB,
    output wire        S0_AXI_WVALID,
    input wire         S0_AXI_WREADY,
    
    input wire [1:0]   S0_AXI_BRESP,
    input wire         S0_AXI_BVALID,
    output wire        S0_AXI_BREADY,
    
    output wire [31:0] S0_AXI_ARADDR,
    output wire [2:0]  S0_AXI_ARPROT,
    output wire        S0_AXI_ARVALID,
    input wire         S0_AXI_ARREADY,
    
    input wire [31:0]  S0_AXI_RDATA,
    input wire [1:0]   S0_AXI_RRESP,
    input wire         S0_AXI_RVALID,
    output wire        S0_AXI_RREADY,
    
    // ========================================================================
    // AXI Slave 1: Data Memory (DMEM)
    // ========================================================================
    output wire [31:0] S1_AXI_AWADDR,
    output wire [2:0]  S1_AXI_AWPROT,
    output wire        S1_AXI_AWVALID,
    input wire         S1_AXI_AWREADY,
    
    output wire [31:0] S1_AXI_WDATA,
    output wire [3:0]  S1_AXI_WSTRB,
    output wire        S1_AXI_WVALID,
    input wire         S1_AXI_WREADY,
    
    input wire [1:0]   S1_AXI_BRESP,
    input wire         S1_AXI_BVALID,
    output wire        S1_AXI_BREADY,
    
    output wire [31:0] S1_AXI_ARADDR,
    output wire [2:0]  S1_AXI_ARPROT,
    output wire        S1_AXI_ARVALID,
    input wire         S1_AXI_ARREADY,
    
    input wire [31:0]  S1_AXI_RDATA,
    input wire [1:0]   S1_AXI_RRESP,
    input wire         S1_AXI_RVALID,
    output wire        S1_AXI_RREADY,
    
    // ========================================================================
    // AXI Slave 2: ASCON Accelerator
    // ========================================================================
    output wire [31:0] S2_AXI_AWADDR,
    output wire [2:0]  S2_AXI_AWPROT,
    output wire        S2_AXI_AWVALID,
    input wire         S2_AXI_AWREADY,
    
    output wire [31:0] S2_AXI_WDATA,
    output wire [3:0]  S2_AXI_WSTRB,
    output wire        S2_AXI_WVALID,
    input wire         S2_AXI_WREADY,
    
    input wire [1:0]   S2_AXI_BRESP,
    input wire         S2_AXI_BVALID,
    output wire        S2_AXI_BREADY,
    
    output wire [31:0] S2_AXI_ARADDR,
    output wire [2:0]  S2_AXI_ARPROT,
    output wire        S2_AXI_ARVALID,
    input wire         S2_AXI_ARREADY,
    
    input wire [31:0]  S2_AXI_RDATA,
    input wire [1:0]   S2_AXI_RRESP,
    input wire         S2_AXI_RVALID,
    output wire        S2_AXI_RREADY
);

    // ========================================================================
    // Address Decoder
    // ========================================================================
    wire sel_imem, sel_dmem, sel_ascon, sel_invalid;
    
    // Decode cho write address
    address_decoder wr_decoder (
        .addr(M_AXI_AWADDR),
        .sel_imem(sel_imem_wr),
        .sel_dmem(sel_dmem_wr),
        .sel_ascon(sel_ascon_wr),
        .sel_invalid(sel_invalid_wr)
    );
    
    // Decode cho read address
    address_decoder rd_decoder (
        .addr(M_AXI_ARADDR),
        .sel_imem(sel_imem_rd),
        .sel_dmem(sel_dmem_rd),
        .sel_ascon(sel_ascon_rd),
        .sel_invalid(sel_invalid_rd)
    );
    
    // ========================================================================
    // Write Address Decode signals
    // ========================================================================
    wire sel_imem_wr, sel_dmem_wr, sel_ascon_wr, sel_invalid_wr;
    
    // ========================================================================
    // Read Address Decode signals
    // ========================================================================
    wire sel_imem_rd, sel_dmem_rd, sel_ascon_rd, sel_invalid_rd;
    
    // ========================================================================
    // Latch selected slave for write transaction
    // ========================================================================
    reg [1:0] wr_slave_sel;  // 00=IMEM, 01=DMEM, 10=ASCON, 11=INVALID
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_slave_sel <= 2'b11;
        end else if (M_AXI_AWVALID && M_AXI_AWREADY) begin
            if (sel_imem_wr)
                wr_slave_sel <= 2'b00;
            else if (sel_dmem_wr)
                wr_slave_sel <= 2'b01;
            else if (sel_ascon_wr)
                wr_slave_sel <= 2'b10;
            else
                wr_slave_sel <= 2'b11;  // Invalid
        end
    end
    
    // ========================================================================
    // Latch selected slave for read transaction
    // ========================================================================
    reg [1:0] rd_slave_sel;  // 00=IMEM, 01=DMEM, 10=ASCON, 11=INVALID
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_slave_sel <= 2'b11;
        end else if (M_AXI_ARVALID && M_AXI_ARREADY) begin
            if (sel_imem_rd)
                rd_slave_sel <= 2'b00;
            else if (sel_dmem_rd)
                rd_slave_sel <= 2'b01;
            else if (sel_ascon_rd)
                rd_slave_sel <= 2'b10;
            else
                rd_slave_sel <= 2'b11;  // Invalid
        end
    end
    
    // ========================================================================
    // Write Address Channel - Route to selected slave
    // ========================================================================
    assign S0_AXI_AWADDR  = M_AXI_AWADDR;
    assign S0_AXI_AWPROT  = M_AXI_AWPROT;
    assign S0_AXI_AWVALID = M_AXI_AWVALID && sel_imem_wr;
    
    assign S1_AXI_AWADDR  = M_AXI_AWADDR;
    assign S1_AXI_AWPROT  = M_AXI_AWPROT;
    assign S1_AXI_AWVALID = M_AXI_AWVALID && sel_dmem_wr;
    
    assign S2_AXI_AWADDR  = M_AXI_AWADDR;
    assign S2_AXI_AWPROT  = M_AXI_AWPROT;
    assign S2_AXI_AWVALID = M_AXI_AWVALID && sel_ascon_wr;
    
    always @(*) begin
        if (sel_imem_wr)
            M_AXI_AWREADY = S0_AXI_AWREADY;
        else if (sel_dmem_wr)
            M_AXI_AWREADY = S1_AXI_AWREADY;
        else if (sel_ascon_wr)
            M_AXI_AWREADY = S2_AXI_AWREADY;
        else
            M_AXI_AWREADY = 1'b1;  // Invalid address, accept immediately
    end
    
    // ========================================================================
    // Write Data Channel - Route to selected slave
    // ========================================================================
    assign S0_AXI_WDATA  = M_AXI_WDATA;
    assign S0_AXI_WSTRB  = M_AXI_WSTRB;
    assign S0_AXI_WVALID = M_AXI_WVALID && (wr_slave_sel == 2'b00);
    
    assign S1_AXI_WDATA  = M_AXI_WDATA;
    assign S1_AXI_WSTRB  = M_AXI_WSTRB;
    assign S1_AXI_WVALID = M_AXI_WVALID && (wr_slave_sel == 2'b01);
    
    assign S2_AXI_WDATA  = M_AXI_WDATA;
    assign S2_AXI_WSTRB  = M_AXI_WSTRB;
    assign S2_AXI_WVALID = M_AXI_WVALID && (wr_slave_sel == 2'b10);
    
    always @(*) begin
        case (wr_slave_sel)
            2'b00:   M_AXI_WREADY = S0_AXI_WREADY;
            2'b01:   M_AXI_WREADY = S1_AXI_WREADY;
            2'b10:   M_AXI_WREADY = S2_AXI_WREADY;
            default: M_AXI_WREADY = 1'b1;  // Invalid
        endcase
    end
    
    // ========================================================================
    // Write Response Channel - Mux from selected slave
    // ========================================================================
    assign S0_AXI_BREADY = M_AXI_BREADY && (wr_slave_sel == 2'b00);
    assign S1_AXI_BREADY = M_AXI_BREADY && (wr_slave_sel == 2'b01);
    assign S2_AXI_BREADY = M_AXI_BREADY && (wr_slave_sel == 2'b10);
    
    always @(*) begin
        case (wr_slave_sel)
            2'b00: begin
                M_AXI_BRESP  = S0_AXI_BRESP;
                M_AXI_BVALID = S0_AXI_BVALID;
            end
            2'b01: begin
                M_AXI_BRESP  = S1_AXI_BRESP;
                M_AXI_BVALID = S1_AXI_BVALID;
            end
            2'b10: begin
                M_AXI_BRESP  = S2_AXI_BRESP;
                M_AXI_BVALID = S2_AXI_BVALID;
            end
            default: begin
                M_AXI_BRESP  = 2'b11;  // DECERR - invalid address
                M_AXI_BVALID = 1'b1;
            end
        endcase
    end
    
    // ========================================================================
    // Read Address Channel - Route to selected slave
    // ========================================================================
    assign S0_AXI_ARADDR  = M_AXI_ARADDR;
    assign S0_AXI_ARPROT  = M_AXI_ARPROT;
    assign S0_AXI_ARVALID = M_AXI_ARVALID && sel_imem_rd;
    
    assign S1_AXI_ARADDR  = M_AXI_ARADDR;
    assign S1_AXI_ARPROT  = M_AXI_ARPROT;
    assign S1_AXI_ARVALID = M_AXI_ARVALID && sel_dmem_rd;
    
    assign S2_AXI_ARADDR  = M_AXI_ARADDR;
    assign S2_AXI_ARPROT  = M_AXI_ARPROT;
    assign S2_AXI_ARVALID = M_AXI_ARVALID && sel_ascon_rd;
    
    always @(*) begin
        if (sel_imem_rd)
            M_AXI_ARREADY = S0_AXI_ARREADY;
        else if (sel_dmem_rd)
            M_AXI_ARREADY = S1_AXI_ARREADY;
        else if (sel_ascon_rd)
            M_AXI_ARREADY = S2_AXI_ARREADY;
        else
            M_AXI_ARREADY = 1'b1;  // Invalid address
    end
    
    // ========================================================================
    // Read Data Channel - Mux from selected slave
    // ========================================================================
    assign S0_AXI_RREADY = M_AXI_RREADY && (rd_slave_sel == 2'b00);
    assign S1_AXI_RREADY = M_AXI_RREADY && (rd_slave_sel == 2'b01);
    assign S2_AXI_RREADY = M_AXI_RREADY && (rd_slave_sel == 2'b10);
    
    always @(*) begin
        case (rd_slave_sel)
            2'b00: begin
                M_AXI_RDATA  = S0_AXI_RDATA;
                M_AXI_RRESP  = S0_AXI_RRESP;
                M_AXI_RVALID = S0_AXI_RVALID;
            end
            2'b01: begin
                M_AXI_RDATA  = S1_AXI_RDATA;
                M_AXI_RRESP  = S1_AXI_RRESP;
                M_AXI_RVALID = S1_AXI_RVALID;
            end
            2'b10: begin
                M_AXI_RDATA  = S2_AXI_RDATA;
                M_AXI_RRESP  = S2_AXI_RRESP;
                M_AXI_RVALID = S2_AXI_RVALID;
            end
            default: begin
                M_AXI_RDATA  = 32'hDEADBEEF;
                M_AXI_RRESP  = 2'b11;  // DECERR
                M_AXI_RVALID = 1'b1;
            end
        endcase
    end

endmodule