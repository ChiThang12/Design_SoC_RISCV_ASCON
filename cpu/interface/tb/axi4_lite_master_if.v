// ============================================================================
// Module: axi4_lite_master_if (COMPLETE FIX v2)
// ============================================================================
// CRITICAL FIXES:
// 1. Clear cpu_ready properly after transaction
// 2. Prevent request from being latched multiple times
// 3. Proper handshake completion
// ============================================================================

module axi4_lite_master_if (
    input wire clk,
    input wire rst_n,
    
    // CPU Request Interface
    input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    input wire [3:0]  cpu_wstrb,
    input wire        cpu_req,
    input wire        cpu_wr,
    output reg [31:0] cpu_rdata,
    output reg        cpu_ready,
    output reg        cpu_error,
    
    // AXI4-Lite Master Interface
    output reg [31:0] M_AXI_AWADDR,
    output wire [2:0] M_AXI_AWPROT,
    output reg        M_AXI_AWVALID,
    input wire        M_AXI_AWREADY,
    
    output reg [31:0] M_AXI_WDATA,
    output reg [3:0]  M_AXI_WSTRB,
    output reg        M_AXI_WVALID,
    input wire        M_AXI_WREADY,
    
    input wire [1:0]  M_AXI_BRESP,
    input wire        M_AXI_BVALID,
    output reg        M_AXI_BREADY,
    
    output reg [31:0] M_AXI_ARADDR,
    output wire [2:0] M_AXI_ARPROT,
    output reg        M_AXI_ARVALID,
    input wire        M_AXI_ARREADY,
    
    input wire [31:0] M_AXI_RDATA,
    input wire [1:0]  M_AXI_RRESP,
    input wire        M_AXI_RVALID,
    output reg        M_AXI_RREADY
);

    localparam [2:0] PROT_DEFAULT = 3'b000;
    localparam [1:0] RESP_OKAY   = 2'b00;
    
    localparam [2:0] 
        IDLE        = 3'b000,
        WRITE_ADDR  = 3'b001,
        WRITE_DATA  = 3'b010,
        WRITE_RESP  = 3'b011,
        READ_ADDR   = 3'b100,
        READ_DATA   = 3'b101,
        DONE        = 3'b110;
    
    reg [2:0] state, next_state;
    
    reg [31:0] addr_reg;
    reg [31:0] wdata_reg;
    reg [3:0]  wstrb_reg;
    reg        wr_reg;
    reg        req_pending;
    
    assign M_AXI_AWPROT = PROT_DEFAULT;
    assign M_AXI_ARPROT = PROT_DEFAULT;
    
    // State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // Next State Logic
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
            
            WRITE_ADDR: begin
                if (M_AXI_AWREADY && M_AXI_WREADY)
                    next_state = WRITE_RESP;
                else if (M_AXI_AWREADY)
                    next_state = WRITE_DATA;
            end
            
            WRITE_DATA: begin
                if (M_AXI_WREADY)
                    next_state = WRITE_RESP;
            end
            
            WRITE_RESP: begin
                if (M_AXI_BVALID && M_AXI_BREADY)
                    next_state = DONE;
            end
            
            READ_ADDR: begin
                if (M_AXI_ARREADY)
                    next_state = READ_DATA;
            end
            
            READ_DATA: begin
                if (M_AXI_RVALID && M_AXI_RREADY)
                    next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg    <= 32'h0;
            wdata_reg   <= 32'h0;
            wstrb_reg   <= 4'h0;
            wr_reg      <= 1'b0;
            req_pending <= 1'b0;
        end else begin
            // ✅ Latch NGAY khi ở IDLE và có request
            if ((state == IDLE) && cpu_req && !req_pending) begin
                addr_reg    <= cpu_addr;
                wdata_reg   <= cpu_wdata;
                wstrb_reg   <= cpu_wstrb;
                wr_reg      <= cpu_wr;
                req_pending <= 1'b1;
            end 
            // Clear khi về IDLE
            else if (state == DONE) begin
                req_pending <= 1'b0;
            end
        end
    end
    
    // AXI Write Address Channel
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
                    end
                end
                
                WRITE_ADDR, WRITE_DATA: begin
                    if (M_AXI_AWREADY)
                        M_AXI_AWVALID <= 1'b0;
                end
                
                default: begin
                    M_AXI_AWVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // AXI Write Data Channel
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
                    end
                end
                
                WRITE_ADDR, WRITE_DATA: begin
                    if (M_AXI_WREADY)
                        M_AXI_WVALID <= 1'b0;
                end
                
                default: begin
                    M_AXI_WVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // AXI Write Response Channel
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
    
    // AXI Read Address Channel
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
                    end
                end
                
                READ_ADDR: begin
                    if (M_AXI_ARREADY)
                        M_AXI_ARVALID <= 1'b0;
                end
                
                default: begin
                    M_AXI_ARVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // AXI Read Data Channel
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
    
    // CRITICAL FIX: CPU Ready Signal
    // Assert for ONE cycle when DONE, then clear
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_ready <= 1'b0;
        end else begin
            cpu_ready <= (state == DONE);
        end
    end
    
    // CPU Read Data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_rdata <= 32'h0;
        end else if (state == READ_DATA && M_AXI_RVALID) begin
            cpu_rdata <= M_AXI_RDATA;
        end
    end
    
    // CPU Error Detection
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_error <= 1'b0;
        end else begin
            if (state == WRITE_RESP && M_AXI_BVALID && M_AXI_BRESP != RESP_OKAY)
                cpu_error <= 1'b1;
            else if (state == READ_DATA && M_AXI_RVALID && M_AXI_RRESP != RESP_OKAY)
                cpu_error <= 1'b1;
            else if (state == IDLE)
                cpu_error <= 1'b0;
        end
    end

endmodule