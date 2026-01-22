// ============================================================================
// Module: imem_access_unit
// ----------------------------------------------------------------------------
// Description:
//   Instruction Memory Access Unit - Chuyên trách truy cập instruction memory
//   thông qua AXI4-Lite bus. Module này che giấu giao thức AXI khỏi CPU core,
//   cung cấp giao diện đơn giản cho Instruction Fetch stage.
//
//   Đặc điểm:
//   - Chỉ hỗ trợ READ operations (instruction fetch)
//   - AXI4-Lite single-beat read
//   - IF chỉ cần phát request 1-cycle pulse
//   - Request được latch và giữ cho đến khi AXI transaction hoàn tất
//
// Author: ChiThang
// ============================================================================

`include "interface/axi4_lite_master_if.v"

module imem_access_unit (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Instruction Fetch Interface (từ datapath)
    // ========================================================================
    input wire [31:0] if_addr,      // imem_addr
    input wire        if_req,       // imem_valid (1-cycle pulse)
    output reg [31:0] if_data,      // imem_rdata
    output reg        if_ready,     // imem_ready (1-cycle pulse)
    output reg        if_error,     // Error flag (optional)
    
    // ========================================================================
    // AXI4-Lite Master Interface
    // ========================================================================
    // Write Address Channel (không sử dụng cho IMEM)
    output wire [31:0] M_AXI_AWADDR,
    output wire [2:0]  M_AXI_AWPROT,
    output wire        M_AXI_AWVALID,
    input wire         M_AXI_AWREADY,
    
    // Write Data Channel (không sử dụng cho IMEM)
    output wire [31:0] M_AXI_WDATA,
    output wire [3:0]  M_AXI_WSTRB,
    output wire        M_AXI_WVALID,
    input wire         M_AXI_WREADY,
    
    // Write Response Channel (không sử dụng cho IMEM)
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
    reg [31:0] if_addr_reg;
    reg        if_req_pending;
    
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
                if (if_req_pending) begin
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
    // Latch IF Request
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_addr_reg <= 32'h0;
            if_req_pending <= 1'b0;
        end else begin
            // Latch request khi nhận được if_req
            if (if_req && !if_req_pending) begin
                if_addr_reg <= if_addr;
                if_req_pending <= 1'b1;
            end 
            // Clear pending khi transaction hoàn tất
            else if (if_req_pending && axi_cpu_ready) begin
                if_req_pending <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // AXI Request Generation - CRITICAL FIX
    // ========================================================================
    // axi4_lite_master_if latch request khi state == IDLE && cpu_req
    // Vì vậy chúng ta CHỈ assert cpu_req trong state REQUESTING (1 cycle)
    always @(*) begin
        axi_cpu_addr  = if_addr_reg;
        axi_cpu_wdata = 32'h0;
        axi_cpu_wstrb = 4'hF;
        axi_cpu_wr    = 1'b0;  // Luôn là READ cho IMEM
        
        // CHỈ assert request trong state REQUESTING
        // Điều này đảm bảo axi4_lite_master_if nhận được pulse 1-cycle
        axi_cpu_req   = (state == ST_REQUESTING);
    end
    
    // ========================================================================
    // IF Response Generation
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_data  <= 32'h0;
            if_ready <= 1'b0;
            if_error <= 1'b0;
        end else begin
            // Assert ready khi transaction hoàn tất
            if_ready <= axi_cpu_ready && if_req_pending;
            if_error <= axi_cpu_error && if_req_pending;
            
            // Latch data khi đọc thành công
            if (axi_cpu_ready && !axi_cpu_error && if_req_pending) begin
                if_data <= axi_cpu_rdata;
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