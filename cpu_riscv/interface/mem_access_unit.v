// ============================================================================
// mem_access_unit.v - Memory Access Unit with AXI4-Lite Master
// ============================================================================
// Mô tả:
//   - Arbitration giữa Instruction Fetch (IF) và Data Memory (MEM) access
//   - Ưu tiên: MEM > IF (data critical hơn)
//   - Giao tiếp với AXI4-Lite bus thông qua master interface
// ============================================================================
`include "interface/axi4_lite_master_if.v"

module mem_access_unit (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Instruction Fetch Interface (từ IFU)
    // ========================================================================
    input wire [31:0] if_addr,        // Địa chỉ instruction
    input wire        if_req,         // Request valid
    output reg [31:0] if_data,        // Instruction data
    output reg        if_ready,       // Data ready
    output reg        if_error,       // Bus error
    
    // ========================================================================
    // Data Memory Interface (từ MEM stage)
    // ========================================================================
    input wire [31:0] mem_addr,       // Địa chỉ data
    input wire [31:0] mem_wdata,      // Dữ liệu ghi
    input wire [3:0]  mem_wstrb,      // Write strobes (byte enables)
    input wire        mem_req,        // Request valid
    input wire        mem_wr,         // 1=Write, 0=Read
    output reg [31:0] mem_rdata,      // Dữ liệu đọc
    output reg        mem_ready,      // Transaction done
    output reg        mem_error,      // Bus error
    
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
    output wire        M_AXI_RREADY
);

    // ========================================================================
    // Arbitration State Machine
    // ========================================================================
    localparam [1:0] 
        ARB_IDLE    = 2'b00,   // Chờ request
        ARB_MEM     = 2'b01,   // Đang xử lý MEM request
        ARB_IF      = 2'b10;   // Đang xử lý IF request
    
    reg [1:0] arb_state, arb_next;
    
    // ========================================================================
    // AXI Master Interface Signals
    // ========================================================================
    wire [31:0] axi_cpu_addr;
    wire [31:0] axi_cpu_wdata;
    wire [3:0]  axi_cpu_wstrb;
    wire        axi_cpu_req;
    wire        axi_cpu_wr;
    wire [31:0] axi_cpu_rdata;
    wire        axi_cpu_ready;
    wire        axi_cpu_error;
    
    // ========================================================================
    // Multiplexer Signals
    // ========================================================================
    reg [31:0] mux_addr;
    reg [31:0] mux_wdata;
    reg [3:0]  mux_wstrb;
    reg        mux_req;
    reg        mux_wr;
    
    // ========================================================================
    // Arbitration State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
        end else begin
            arb_state <= arb_next;
        end
    end
    
    // ========================================================================
    // Arbitration State Machine - Combinational
    // ========================================================================
    always @(*) begin
        arb_next = arb_state;
        
        case (arb_state)
            ARB_IDLE: begin
                // Priority: MEM > IF
                if (mem_req) begin
                    arb_next = ARB_MEM;
                end else if (if_req) begin
                    arb_next = ARB_IF;
                end
            end
            
            ARB_MEM: begin
                // Chờ MEM transaction hoàn thành
                if (axi_cpu_ready) begin
                    arb_next = ARB_IDLE;
                end
            end
            
            ARB_IF: begin
                // Chờ IF transaction hoàn thành
                if (axi_cpu_ready) begin
                    arb_next = ARB_IDLE;
                end
            end
            
            default: arb_next = ARB_IDLE;
        endcase
    end
    
    // ========================================================================
    // Request Multiplexer
    // ========================================================================
    always @(*) begin
        // Default values
        mux_addr  = 32'h0;
        mux_wdata = 32'h0;
        mux_wstrb = 4'h0;
        mux_req   = 1'b0;
        mux_wr    = 1'b0;
        
        case (arb_state)
            ARB_IDLE: begin
                // MUX cho request tiếp theo
                if (mem_req) begin
                    mux_addr  = mem_addr;
                    mux_wdata = mem_wdata;
                    mux_wstrb = mem_wstrb;
                    mux_req   = 1'b1;
                    mux_wr    = mem_wr;
                end else if (if_req) begin
                    mux_addr  = if_addr;
                    mux_wdata = 32'h0;
                    mux_wstrb = 4'hF;      // IF luôn đọc word
                    mux_req   = 1'b1;
                    mux_wr    = 1'b0;      // IF luôn là read
                end
            end
            
            ARB_MEM: begin
                mux_addr  = mem_addr;
                mux_wdata = mem_wdata;
                mux_wstrb = mem_wstrb;
                mux_req   = 1'b0;  // Request đã được latch vào AXI master
                mux_wr    = mem_wr;
            end
            
            ARB_IF: begin
                mux_addr  = if_addr;
                mux_wdata = 32'h0;
                mux_wstrb = 4'hF;
                mux_req   = 1'b0;  // Request đã được latch vào AXI master
                mux_wr    = 1'b0;
            end
        endcase
    end
    
    // ========================================================================
    // AXI Master Interface Connections
    // ========================================================================
    assign axi_cpu_addr  = mux_addr;
    assign axi_cpu_wdata = mux_wdata;
    assign axi_cpu_wstrb = mux_wstrb;
    assign axi_cpu_req   = mux_req;
    assign axi_cpu_wr    = mux_wr;
    
    // ========================================================================
    // IF Response Generation
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_data  <= 32'h0;
            if_ready <= 1'b0;
            if_error <= 1'b0;
        end else begin
            if_ready <= (arb_state == ARB_IF) && axi_cpu_ready;
            if_error <= (arb_state == ARB_IF) && axi_cpu_error;
            
            if ((arb_state == ARB_IF) && axi_cpu_ready) begin
                if_data <= axi_cpu_rdata;
            end
        end
    end
    
    // ========================================================================
    // MEM Response Generation
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rdata <= 32'h0;
            mem_ready <= 1'b0;
            mem_error <= 1'b0;
        end else begin
            mem_ready <= (arb_state == ARB_MEM) && axi_cpu_ready;
            mem_error <= (arb_state == ARB_MEM) && axi_cpu_error;
            
            if ((arb_state == ARB_MEM) && axi_cpu_ready) begin
                mem_rdata <= axi_cpu_rdata;
            end
        end
    end
    
    // ========================================================================
    // AXI4-Lite Master Interface Instance
    // ========================================================================
    axi4_lite_master_if axi_master (
        .clk(clk),
        .rst_n(rst_n),
        
        // CPU Interface
        .cpu_addr(axi_cpu_addr),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_wstrb(axi_cpu_wstrb),
        .cpu_req(axi_cpu_req),
        .cpu_wr(axi_cpu_wr),
        .cpu_rdata(axi_cpu_rdata),
        .cpu_ready(axi_cpu_ready),
        .cpu_error(axi_cpu_error),
        
        // AXI4-Lite Master Interface
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