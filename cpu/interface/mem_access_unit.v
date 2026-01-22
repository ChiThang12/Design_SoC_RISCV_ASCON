// ============================================================================
// Module: mem_access_unit
// ----------------------------------------------------------------------------
// Description:
//   Memory Access Unit (MAU) đóng vai trò trung gian giữa CPU core và
//   AXI4-Lite bus. Module này cho phép hai nguồn truy cập bộ nhớ độc lập:
//
//     - Instruction Fetch (IF)
//     - Data Memory Access (MEM)
//
//   chia sẻ chung một AXI4-Lite master interface.
//
//   MAU che giấu hoàn toàn giao thức AXI khỏi CPU, cung cấp giao diện
//   memory-like đơn giản cho IF và MEM.
//
//   Đặc điểm chính:
//   - Hỗ trợ AXI4-Lite single-beat read / write
//   - Arbitration giữa IF và MEM (ưu tiên MEM)
//   - Request được latch và giữ cho đến khi AXI transaction hoàn tất
//   - IF và MEM chỉ cần phát request 1-cycle, không cần giữ tín hiệu
//   - Phù hợp cho softcore CPU (RISC-V, MIPS, custom CPU)
//
// ----------------------------------------------------------------------------
// Operation:
//   1. IF hoặc MEM phát request trong 1 cycle (if_req / mem_req)
//   2. Request được latch vào internal registers và đánh dấu pending
//   3. FSM arbitration chọn nguồn truy cập:
//        - Ưu tiên MEM nếu đồng thời có IF và MEM
//   4. Request được chuyển thành giao diện CPU-side cho AXI master
//   5. AXI master thực hiện transaction (read / write)
//   6. Khi AXI transaction hoàn tất:
//        - *_ready được assert 1 cycle
//        - Dữ liệu đọc được trả về (nếu là read)
//        - *_error phản ánh lỗi AXI (SLVERR / DECERR)
//
// ----------------------------------------------------------------------------
// Arbitration Policy:
//   - MEM có độ ưu tiên cao hơn IF
//   - Chỉ xử lý một transaction tại một thời điểm
//   - Không pipeline, không out-of-order
//
// ----------------------------------------------------------------------------
// Timing Model:
//   - IF / MEM request: 1-cycle pulse
//   - AXI latency: variable (do slave quyết định)
//   - *_ready: pulse 1 cycle khi transaction hoàn tất
//
// Author: ChiThang
// ============================================================================
//
// Clock & Reset
// ----------------------------------------------------------------------------
// clk              : Clock hệ thống
// rst_n            : Reset active-low
//
// ----------------------------------------------------------------------------
// Instruction Fetch Interface
// ----------------------------------------------------------------------------
// if_addr          : Địa chỉ đọc instruction (byte address)
// if_req           : Yêu cầu đọc instruction (1-cycle pulse)
// if_data          : Instruction data trả về
// if_ready         : Báo IF transaction hoàn tất (1-cycle pulse)
// if_error         : Báo lỗi AXI khi đọc instruction
//
// ----------------------------------------------------------------------------
// Data Memory Interface
// ----------------------------------------------------------------------------
// mem_addr         : Địa chỉ đọc/ghi data (byte address)
// mem_wdata        : Dữ liệu ghi
// mem_wstrb        : Byte strobe (write enable từng byte)
// mem_req          : Yêu cầu truy cập data (1-cycle pulse)
// mem_wr           : 1 = write, 0 = read
// mem_rdata        : Dữ liệu đọc trả về
// mem_ready        : Báo MEM transaction hoàn tất (1-cycle pulse)
// mem_error        : Báo lỗi AXI khi truy cập data
//
// ----------------------------------------------------------------------------
// AXI4-Lite Master Interface
// ----------------------------------------------------------------------------
// M_AXI_*          : Chuẩn AXI4-Lite master signals
//   - Write Address Channel (AW)
//   - Write Data Channel (W)
//   - Write Response Channel (B)
//   - Read Address Channel (AR)
//   - Read Data Channel (R)
// ============================================================================


`include "axi4_lite_master_if.v"
module mem_access_unit (
    input wire clk,
    input wire rst_n,
    
    // Instruction Fetch Interface
    input wire [31:0] if_addr,
    input wire        if_req,
    output reg [31:0] if_data,
    output reg        if_ready,
    output reg        if_error,
    
    // Data Memory Interface
    input wire [31:0] mem_addr,
    input wire [31:0] mem_wdata,
    input wire [3:0]  mem_wstrb,
    input wire        mem_req,
    input wire        mem_wr,
    output reg [31:0] mem_rdata,
    output reg        mem_ready,
    output reg        mem_error,
    
    // AXI4-Lite Master Interface
    output wire [31:0] M_AXI_AWADDR,
    output wire [2:0]  M_AXI_AWPROT,
    output wire        M_AXI_AWVALID,
    input wire         M_AXI_AWREADY,
    
    output wire [31:0] M_AXI_WDATA,
    output wire [3:0]  M_AXI_WSTRB,
    output wire        M_AXI_WVALID,
    input wire         M_AXI_WREADY,
    
    input wire [1:0]   M_AXI_BRESP,
    input wire         M_AXI_BVALID,
    output wire        M_AXI_BREADY,
    
    output wire [31:0] M_AXI_ARADDR,
    output wire [2:0]  M_AXI_ARPROT,
    output wire        M_AXI_ARVALID,
    input wire         M_AXI_ARREADY,
    
    input wire [31:0]  M_AXI_RDATA,
    input wire [1:0]   M_AXI_RRESP,
    input wire         M_AXI_RVALID,
    output wire        M_AXI_RREADY
);

    // ========================================================================
    // Arbitration State Machine
    // ========================================================================
    localparam [1:0] 
        ARB_IDLE    = 2'b00,
        ARB_MEM     = 2'b01,
        ARB_IF      = 2'b10;
    
    reg [1:0] arb_state, arb_next;
    
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
    
    reg [31:0] mem_addr_reg;
    reg [31:0] mem_wdata_reg;
    reg [3:0]  mem_wstrb_reg;
    reg        mem_wr_reg;
    reg        mem_req_pending;
    
    // ========================================================================
    // Latch IF Request
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_addr_reg <= 32'h0;
            if_req_pending <= 1'b0;
        end else begin
            // Set pending when new request arrives
            if (if_req && !if_req_pending) begin
                if_addr_reg <= if_addr;
                if_req_pending <= 1'b1;
            end 
            // Clear pending only when this request completes
            else if (if_req_pending && arb_state == ARB_IF && axi_cpu_ready) begin
                if_req_pending <= 1'b0;
            end
        end
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
            // Set pending when new request arrives
            if (mem_req && !mem_req_pending) begin
                mem_addr_reg <= mem_addr;
                mem_wdata_reg <= mem_wdata;
                mem_wstrb_reg <= mem_wstrb;
                mem_wr_reg <= mem_wr;
                mem_req_pending <= 1'b1;
            end 
            // Clear pending only when this request completes
            else if (mem_req_pending && arb_state == ARB_MEM && axi_cpu_ready) begin
                mem_req_pending <= 1'b0;
            end
        end
    end
    
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
                if (mem_req_pending) begin
                    arb_next = ARB_MEM;
                end else if (if_req_pending) begin
                    arb_next = ARB_IF;
                end
            end
            
            ARB_MEM: begin
                if (axi_cpu_ready) begin
                    // Check if there's pending IF request
                    if (if_req_pending) begin
                        arb_next = ARB_IF;
                    end else begin
                        arb_next = ARB_IDLE;
                    end
                end
            end
            
            ARB_IF: begin
                if (axi_cpu_ready) begin
                    // Check if there's new MEM request (higher priority)
                    if (mem_req_pending) begin
                        arb_next = ARB_MEM;
                    end else begin
                        arb_next = ARB_IDLE;
                    end
                end
            end
            
            default: arb_next = ARB_IDLE;
        endcase
    end
    
    // ========================================================================
    // AXI Request Generation
    // ========================================================================
    always @(*) begin
        // Default values
        axi_cpu_addr  = 32'h0;
        axi_cpu_wdata = 32'h0;
        axi_cpu_wstrb = 4'h0;
        axi_cpu_req   = 1'b0;
        axi_cpu_wr    = 1'b0;
        
        case (arb_state)
            ARB_IDLE: begin
                // Prepare next request
                if (mem_req_pending) begin
                    axi_cpu_addr  = mem_addr_reg;
                    axi_cpu_wdata = mem_wdata_reg;
                    axi_cpu_wstrb = mem_wstrb_reg;
                    axi_cpu_req   = 1'b1;
                    axi_cpu_wr    = mem_wr_reg;
                end else if (if_req_pending) begin
                    axi_cpu_addr  = if_addr_reg;
                    axi_cpu_wdata = 32'h0;
                    axi_cpu_wstrb = 4'hF;
                    axi_cpu_req   = 1'b1;
                    axi_cpu_wr    = 1'b0;
                end
            end
            
            ARB_MEM: begin
                axi_cpu_addr  = mem_addr_reg;
                axi_cpu_wdata = mem_wdata_reg;
                axi_cpu_wstrb = mem_wstrb_reg;
                axi_cpu_req   = 1'b0;  // Already latched into AXI master
                axi_cpu_wr    = mem_wr_reg;
            end
            
            ARB_IF: begin
                axi_cpu_addr  = if_addr_reg;
                axi_cpu_wdata = 32'h0;
                axi_cpu_wstrb = 4'hF;
                axi_cpu_req   = 1'b0;  // Already latched into AXI master
                axi_cpu_wr    = 1'b0;
            end
        endcase
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
            if_ready <= (arb_state == ARB_IF) && axi_cpu_ready;
            if_error <= (arb_state == ARB_IF) && axi_cpu_error;
            
            if ((arb_state == ARB_IF) && axi_cpu_ready && !axi_cpu_error) begin
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
            
            if ((arb_state == ARB_MEM) && axi_cpu_ready && !axi_cpu_error) begin
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
        
        .cpu_addr(axi_cpu_addr),
        .cpu_wdata(axi_cpu_wdata),
        .cpu_wstrb(axi_cpu_wstrb),
        .cpu_req(axi_cpu_req),
        .cpu_wr(axi_cpu_wr),
        .cpu_rdata(axi_cpu_rdata),
        .cpu_ready(axi_cpu_ready),
        .cpu_error(axi_cpu_error),
        
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