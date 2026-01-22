// ============================================================================
// Module: dmem_access_unit
// ----------------------------------------------------------------------------
// Description:
//   Data Memory Access Unit - Chuyên trách truy cập data memory thông qua
//   AXI4-Lite bus. Module này che giấu giao thức AXI khỏi CPU core,
//   cung cấp giao diện đơn giản cho Memory stage.
//
//   Đặc điểm:
//   - Hỗ trợ cả READ và WRITE operations
//   - AXI4-Lite single-beat read/write
//   - MEM chỉ cần phát request 1-cycle pulse
//   - Request được latch và giữ cho đến khi AXI transaction hoàn tất
//   - Hỗ trợ byte-level write strobe
//
// Author: ChiThang
// ============================================================================

`include "interface/axi4_lite_master_if.v"

module dmem_access_unit (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Data Memory Interface (từ datapath)
    // ========================================================================
    input wire [31:0] mem_addr,     // dmem_addr
    input wire [31:0] mem_wdata,    // dmem_wdata
    input wire [3:0]  mem_wstrb,    // dmem_wstrb
    input wire        mem_req,      // dmem_valid (1-cycle pulse)
    input wire        mem_wr,       // dmem_we (1=write, 0=read)
    output reg [31:0] mem_rdata,    // dmem_rdata
    output reg        mem_ready,    // dmem_ready (1-cycle pulse)
    output reg        mem_error,    // Error flag (optional)
    
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
    // Internal State Machine
    // ========================================================================
    localparam [1:0]
        ST_IDLE       = 2'b00,
        ST_REQUESTING = 2'b01,
        ST_WAITING    = 2'b10;
    
    reg [1:0] state, next_state;

    // ========================================================================
    // AXI Master Interface Signals
    // ========================================================================
    reg [31:0] axi_cpu_addr;
    reg [31:0] axi_cpu_wdata;
    reg [3:0]  axi_cpu_wstrb;
    reg        axi_cpu_req;
    reg        axi_cpu_wr;
    wire [31:0] axi_cpu_rdata;
    wire        axi_cpu_ready;
    wire        axi_cpu_error;
    
    // ========================================================================
    // Latched Request Signals
    // ========================================================================
    reg [31:0] mem_addr_reg;
    reg [31:0] mem_wdata_reg;
    reg [3:0]  mem_wstrb_reg;
    reg        mem_wr_reg;
    reg        mem_req_pending;
    
    // ========================================================================
    // State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // ========================================================================
    // State Machine - Combinational
    // ========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            ST_IDLE: begin
                if (mem_req_pending) begin
                    next_state = ST_REQUESTING;
                end
            end
            
            ST_REQUESTING: begin
                // Chuyển sang WAITING sau khi đã gửi request
                next_state = ST_WAITING;
            end
            
            ST_WAITING: begin
                if (axi_cpu_ready) begin
                    next_state = ST_IDLE;
                end
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    // ========================================================================
    // Latch MEM Request
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_addr_reg <= 32'h0;
            mem_wdata_reg <= 32'h0;
            mem_wstrb_reg <= 4'h0;
            mem_wr_reg <= 1'b0;
            mem_req_pending <= 1'b0;
        end else begin
            // Latch request khi nhận được mem_req
            if (mem_req && !mem_req_pending) begin
                mem_addr_reg <= mem_addr;
                mem_wdata_reg <= mem_wdata;
                mem_wstrb_reg <= mem_wstrb;
                mem_wr_reg <= mem_wr;
                mem_req_pending <= 1'b1;
            end 
            // Clear pending khi transaction hoàn tất
            else if (mem_req_pending && axi_cpu_ready) begin
                mem_req_pending <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // AXI Request Generation - CRITICAL FIX
    // ========================================================================
    // axi4_lite_master_if latch request khi state == IDLE && cpu_req
    // Vì vậy chúng ta CHỈ assert cpu_req trong state REQUESTING (1 cycle)
    always @(*) begin
        axi_cpu_addr  = mem_addr_reg;
        axi_cpu_wdata = mem_wdata_reg;
        axi_cpu_wstrb = mem_wstrb_reg;
        axi_cpu_wr    = mem_wr_reg;
        
        // CHỈ assert request trong state REQUESTING
        // Điều này đảm bảo axi4_lite_master_if nhận được pulse 1-cycle
        axi_cpu_req   = (state == ST_REQUESTING);
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
            // Assert ready khi transaction hoàn tất
            mem_ready <= axi_cpu_ready && mem_req_pending;
            mem_error <= axi_cpu_error && mem_req_pending;
            
            // Latch data khi đọc thành công
            if (axi_cpu_ready && !axi_cpu_error && mem_req_pending && !mem_wr_reg) begin
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
        
        // CPU-side interface
        .cpu_addr(axi_cpu_addr),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_wstrb(axi_cpu_wstrb),
        .cpu_req(axi_cpu_req),
        .cpu_wr(axi_cpu_wr),
        .cpu_rdata(axi_cpu_rdata),
        .cpu_ready(axi_cpu_ready),
        .cpu_error(axi_cpu_error),
        
        // AXI4-Lite Master interface
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