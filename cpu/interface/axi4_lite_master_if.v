// ============================================================================
// Module: axi4_lite_master_if
// ----------------------------------------------------------------------------
// Description:
//   AXI4-Lite Master Interface đóng vai trò cầu nối giữa CPU core
//   (giao diện memory đơn giản) và bus AXI4-Lite chuẩn.
//
//   Module này che giấu hoàn toàn giao thức AXI khỏi CPU, cho phép CPU
//   chỉ cần phát các tín hiệu:
//     - cpu_addr
//     - cpu_req
//     - cpu_wr
//     - cpu_wdata / cpu_wstrb
//
//   và nhận lại:
//     - cpu_rdata
//     - cpu_ready
//     - cpu_error
//
//   - Hỗ trợ AXI4-Lite single-beat read / write
//   - Điều khiển handshake AW/W/B và AR/R bằng FSM
//   - Chỉ xử lý 1 transaction tại một thời điểm (non-pipelined)
//   - Phù hợp cho softcore CPU (RISC-V, MIPS, custom CPU)
//
// Operation:
//   - Khi cpu_req được assert, module latch request vào internal registers
//   - FSM bắt đầu AXI transaction tương ứng:
//       * Write  : AW -> W -> B
//       * Read   : AR -> R
//   - Module giữ VALID cho đến khi READY từ slave được assert
//   - Khi transaction hoàn tất:
//       * cpu_ready được pulse 1 cycle
//       * cpu_rdata hợp lệ (đối với read)
//       * cpu_error phản ánh BRESP / RRESP
//
// Author: ChiThang
// ============================================================================
//
// Clock & Reset
// clk              : Clock hệ thống
// rst_n            : Reset active-low
//
// ---------------------------------------------------------------------------
// CPU Request Interface (Memory-like Interface)
// ---------------------------------------------------------------------------
// cpu_addr         : Địa chỉ truy cập (byte address)
// cpu_wdata        : Dữ liệu ghi từ CPU
// cpu_wstrb        : Byte enable (AXI WSTRB)
// cpu_req          : Yêu cầu truy cập bộ nhớ
// cpu_wr           : 1 = write, 0 = read
//
// cpu_rdata        : Dữ liệu đọc trả về cho CPU
// cpu_ready        : Pulse báo transaction hoàn tất
// cpu_error        : Báo lỗi AXI (SLVERR / DECERR)
//
// ---------------------------------------------------------------------------
// AXI4-Lite Master Interface
// ---------------------------------------------------------------------------
//
// Write Address Channel (AW)
// M_AXI_AWADDR     : Địa chỉ ghi
// M_AXI_AWPROT     : Protection attributes (fixed = 3'b000)
// M_AXI_AWVALID    : Master báo địa chỉ hợp lệ
// M_AXI_AWREADY    : Slave sẵn sàng nhận địa chỉ
//
// Write Data Channel (W)
// M_AXI_WDATA      : Dữ liệu ghi
// M_AXI_WSTRB      : Byte strobe
// M_AXI_WVALID     : Master báo dữ liệu hợp lệ
// M_AXI_WREADY     : Slave sẵn sàng nhận dữ liệu
//
// Write Response Channel (B)
// M_AXI_BRESP      : Phản hồi ghi (OKAY / SLVERR / DECERR)
// M_AXI_BVALID     : Slave báo response hợp lệ
// M_AXI_BREADY     : Master sẵn sàng nhận response
//
// Read Address Channel (AR)
// M_AXI_ARADDR     : Địa chỉ đọc
// M_AXI_ARPROT     : Protection attributes (fixed = 3'b000)
// M_AXI_ARVALID    : Master báo địa chỉ hợp lệ
// M_AXI_ARREADY    : Slave sẵn sàng nhận địa chỉ
//
// Read Data Channel (R)
// M_AXI_RDATA      : Dữ liệu đọc từ slave
// M_AXI_RRESP      : Phản hồi đọc (OKAY / SLVERR / DECERR)
// M_AXI_RVALID     : Slave báo dữ liệu hợp lệ
// M_AXI_RREADY     : Master sẵn sàng nhận dữ liệu
// ============================================================================


module axi4_lite_master_if (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // CPU Request Interface (Simple Memory-like Interface)
    // ========================================================================
    input wire [31:0] cpu_addr,        // Địa chỉ truy cập
    input wire [31:0] cpu_wdata,       // Dữ liệu ghi
    input wire [3:0]  cpu_wstrb,       // Byte enables (1111=word, 0011=half, 0001=byte)
    input wire        cpu_req,         // Request valid
    input wire        cpu_wr,          // 1=Write, 0=Read
    output reg [31:0] cpu_rdata,       // Dữ liệu đọc về
    output reg        cpu_ready,       // Transaction hoàn thành (1 cycle pulse)
    output reg        cpu_error,       // Lỗi bus (SLVERR/DECERR)
    
    // ========================================================================
    // AXI4-Lite Master Interface
    // ========================================================================
    
    // Write Address Channel (AW)
    output reg [31:0] M_AXI_AWADDR,
    output wire [2:0] M_AXI_AWPROT,    // Protection type (thường để 3'b000)
    output reg        M_AXI_AWVALID,
    input wire        M_AXI_AWREADY,
    
    // Write Data Channel (W)
    output reg [31:0] M_AXI_WDATA,
    output reg [3:0]  M_AXI_WSTRB,
    output reg        M_AXI_WVALID,
    input wire        M_AXI_WREADY,
    
    // Write Response Channel (B)
    input wire [1:0]  M_AXI_BRESP,     // 00=OKAY, 01=EXOKAY, 10=SLVERR, 11=DECERR
    input wire        M_AXI_BVALID,
    output reg        M_AXI_BREADY,
    
    // Read Address Channel (AR)
    output reg [31:0] M_AXI_ARADDR,
    output wire [2:0] M_AXI_ARPROT,    // Protection type (thường để 3'b000)
    output reg        M_AXI_ARVALID,
    input wire        M_AXI_ARREADY,
    
    // Read Data Channel (R)
    input wire [31:0] M_AXI_RDATA,
    input wire [1:0]  M_AXI_RRESP,     // 00=OKAY, 01=EXOKAY, 10=SLVERR, 11=DECERR
    input wire        M_AXI_RVALID,
    output reg        M_AXI_RREADY
);

    // ========================================================================
    // AXI Protocol Constants
    // ========================================================================
    localparam [2:0] PROT_DEFAULT = 3'b000;  // Unprivileged, secure, data access
    
    localparam [1:0] RESP_OKAY   = 2'b00,
                     RESP_EXOKAY = 2'b01,
                     RESP_SLVERR = 2'b10,
                     RESP_DECERR = 2'b11;
    
    // ========================================================================
    // State Machine Definition
    // ========================================================================
    localparam [2:0] 
        IDLE        = 3'b000,   // Chờ request
        WRITE_ADDR  = 3'b001,   // Gửi write address
        WRITE_DATA  = 3'b010,   // Gửi write data
        WRITE_RESP  = 3'b011,   // Nhận write response
        READ_ADDR   = 3'b100,   // Gửi read address
        READ_DATA   = 3'b101;   // Nhận read data
    
    reg [2:0] state, next_state;
    
    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [31:0] addr_reg;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;
    reg        wr_reg;
    reg        req_pending;     // Cờ báo có request đang chờ
    
    // ========================================================================
    // Fixed AXI Signals
    // ========================================================================
    assign M_AXI_AWPROT = PROT_DEFAULT;
    assign M_AXI_ARPROT = PROT_DEFAULT;
    
    // ========================================================================
    // State Machine - Sequential Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // ========================================================================
    // State Machine - Next State Logic
    // ========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (req_pending) begin
                    if (wr_reg)
                        next_state = WRITE_ADDR;
                    else
                        next_state = READ_ADDR;
                end
            end
            
            // ================================================================
            // WRITE TRANSACTION
            // ================================================================
            WRITE_ADDR: begin
                if (M_AXI_AWREADY && M_AXI_WREADY)
                    next_state = WRITE_RESP;
                else if (M_AXI_AWREADY)
                    next_state = WRITE_DATA;
                // Giữ nguyên state nếu chưa ready
            end
            
            WRITE_DATA: begin
                if (M_AXI_WREADY)
                    next_state = WRITE_RESP;
            end
            
            WRITE_RESP: begin
                if (M_AXI_BVALID)
                    next_state = IDLE;
            end
            
            // ================================================================
            // READ TRANSACTION
            // ================================================================
            READ_ADDR: begin
                if (M_AXI_ARREADY)
                    next_state = READ_DATA;
            end
            
            READ_DATA: begin
                if (M_AXI_RVALID)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // ========================================================================
    // Latch CPU Request
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg    <= 32'h0;
            wdata_reg   <= 32'h0;
            wstrb_reg   <= 4'h0;
            wr_reg      <= 1'b0;
            req_pending <= 1'b0;
        end else begin
            // Reset req_pending khi transaction hoàn thành
            if ((state == WRITE_RESP && M_AXI_BVALID) || 
                (state == READ_DATA && M_AXI_RVALID)) begin
                req_pending <= 1'b0;
            end
            // Latch request mới nếu đang IDLE và có request
            else if (state == IDLE && cpu_req && !req_pending) begin
                addr_reg    <= cpu_addr;
                wdata_reg   <= cpu_wdata;
                wstrb_reg   <= cpu_wstrb;
                wr_reg      <= cpu_wr;
                req_pending <= 1'b1;
            end
        end
    end
    
    // ========================================================================
    // AXI Write Address Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_AWADDR  <= 32'h0;
            M_AXI_AWVALID <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (req_pending && wr_reg) begin
                        M_AXI_AWADDR  <= addr_reg;
                        M_AXI_AWVALID <= 1'b1;
                    end else begin
                        M_AXI_AWVALID <= 1'b0;
                    end
                end
                
                WRITE_ADDR, WRITE_DATA: begin
                    if (M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                    end
                end
                
                default: begin
                    M_AXI_AWVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // AXI Write Data Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_WDATA  <= 32'h0;
            M_AXI_WSTRB  <= 4'h0;
            M_AXI_WVALID <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (req_pending && wr_reg) begin
                        M_AXI_WDATA  <= wdata_reg;
                        M_AXI_WSTRB  <= wstrb_reg;
                        M_AXI_WVALID <= 1'b1;
                    end else begin
                        M_AXI_WVALID <= 1'b0;
                    end
                end
                
                WRITE_ADDR, WRITE_DATA: begin
                    if (M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0;
                    end
                end
                
                default: begin
                    M_AXI_WVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // AXI Write Response Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_BREADY <= 1'b0;
        end else begin
            case (state)
                WRITE_RESP: begin
                    M_AXI_BREADY <= 1'b1;
                end
                default: begin
                    M_AXI_BREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // AXI Read Address Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_ARADDR  <= 32'h0;
            M_AXI_ARVALID <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (req_pending && !wr_reg) begin
                        M_AXI_ARADDR  <= addr_reg;
                        M_AXI_ARVALID <= 1'b1;
                    end else begin
                        M_AXI_ARVALID <= 1'b0;
                    end
                end
                
                READ_ADDR: begin
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                    end
                end
                
                default: begin
                    M_AXI_ARVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // AXI Read Data Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_RREADY <= 1'b0;
        end else begin
            case (state)
                READ_DATA: begin
                    M_AXI_RREADY <= 1'b1;
                end
                default: begin
                    M_AXI_RREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // CPU Response - Ready Signal
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_ready <= 1'b0;
        end else begin
            // Pulse high khi hoàn thành transaction
            cpu_ready <= (state == WRITE_RESP && M_AXI_BVALID) ||
                         (state == READ_DATA && M_AXI_RVALID);
        end
    end
    
    // ========================================================================
    // CPU Response - Read Data
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_rdata <= 32'h0;
        end else if (state == READ_DATA && M_AXI_RVALID) begin
            cpu_rdata <= M_AXI_RDATA;
        end
    end
    
    // ========================================================================
    // CPU Response - Error Detection
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_error <= 1'b0;
        end else begin
            cpu_error <= (state == WRITE_RESP && M_AXI_BVALID && M_AXI_BRESP != RESP_OKAY) ||
                         (state == READ_DATA && M_AXI_RVALID && M_AXI_RRESP != RESP_OKAY);
        end
    end

endmodule