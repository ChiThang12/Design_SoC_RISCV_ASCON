// ============================================================================
// inst_mem_axi_slave.v - Instruction Memory AXI4-Lite Slave Wrapper
// ============================================================================
// Mô tả:
//   - Wrapper cho inst_mem module với AXI4-Lite slave interface
//   - Chỉ hỗ trợ READ (instruction memory là read-only)
//   - Write request sẽ trả về SLVERR
// ============================================================================
<<<<<<< HEAD
`include "memory/inst_mem.v"
=======
`include "inst_mem.v"
>>>>>>> 5c36a3d (add CPU in SoC)
module inst_mem_axi_slave (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4-Lite Slave Interface
    // ========================================================================
    
    // Write Address Channel (không support, nhưng vẫn phải có)
    input wire [31:0] S_AXI_AWADDR,
    input wire [2:0]  S_AXI_AWPROT,
    input wire        S_AXI_AWVALID,
    output reg        S_AXI_AWREADY,
    
    // Write Data Channel
    input wire [31:0] S_AXI_WDATA,
    input wire [3:0]  S_AXI_WSTRB,
    input wire        S_AXI_WVALID,
    output reg        S_AXI_WREADY,
    
    // Write Response Channel
    output reg [1:0]  S_AXI_BRESP,
    output reg        S_AXI_BVALID,
    input wire        S_AXI_BREADY,
    
    // Read Address Channel
    input wire [31:0] S_AXI_ARADDR,
    input wire [2:0]  S_AXI_ARPROT,
    input wire        S_AXI_ARVALID,
    output reg        S_AXI_ARREADY,
    
    // Read Data Channel
    output reg [31:0] S_AXI_RDATA,
    output reg [1:0]  S_AXI_RRESP,
    output reg        S_AXI_RVALID,
    input wire        S_AXI_RREADY
);

    // ========================================================================
    // AXI Response Codes
    // ========================================================================
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;  // Slave error (write to ROM)
    
    // ========================================================================
    // State Machine for Read Channel
    // ========================================================================
    localparam [1:0]
        RD_IDLE  = 2'b00,
        RD_WAIT  = 2'b01,
        RD_RESP  = 2'b10;
    
    reg [1:0] rd_state, rd_next;
    
    // ========================================================================
    // State Machine for Write Channel (Always reject)
    // ========================================================================
    localparam [1:0]
        WR_IDLE  = 2'b00,
        WR_ADDR  = 2'b01,
        WR_DATA  = 2'b10,
        WR_RESP  = 2'b11;
    
    reg [1:0] wr_state, wr_next;
    
    // ========================================================================
    // Internal Memory Signals
    // ========================================================================
    reg [31:0] mem_addr_latched;
    wire [31:0] mem_read_data;
    
    // ========================================================================
    // Instruction Memory Instance (original ROM)
    // ========================================================================
    inst_mem imem (
        .PC(mem_addr_latched),
        .reset(~rst_n),              // Convert active-low to active-high
        .Instruction_Code(mem_read_data)
    );
    
    // ========================================================================
    // Read State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
        end else begin
            rd_state <= rd_next;
        end
    end
    
    // ========================================================================
    // Read State Machine - Combinational
    // ========================================================================
    always @(*) begin
        rd_next = rd_state;
        
        case (rd_state)
            RD_IDLE: begin
                if (S_AXI_ARVALID) begin
                    rd_next = RD_WAIT;
                end
            end
            
            RD_WAIT: begin
                // 1 cycle delay để đọc từ memory
                rd_next = RD_RESP;
            end
            
            RD_RESP: begin
                if (S_AXI_RREADY) begin
                    rd_next = RD_IDLE;
                end
            end
            
            default: rd_next = RD_IDLE;
        endcase
    end
    
    // ========================================================================
    // Read Address Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY <= 1'b0;
            mem_addr_latched <= 32'h0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID) begin
                        S_AXI_ARREADY <= 1'b1;
                        mem_addr_latched <= S_AXI_ARADDR;
                    end else begin
                        S_AXI_ARREADY <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_ARREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Read Data Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_RDATA  <= 32'h0;
            S_AXI_RRESP  <= RESP_OKAY;
            S_AXI_RVALID <= 1'b0;
        end else begin
            case (rd_state)
                RD_WAIT: begin
                    // Latch data từ memory
                    S_AXI_RDATA  <= mem_read_data;
                    S_AXI_RRESP  <= RESP_OKAY;
                    S_AXI_RVALID <= 1'b1;
                end
                
                RD_RESP: begin
                    if (S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_RVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
        end else begin
            wr_state <= wr_next;
        end
    end
    
    // ========================================================================
    // Write State Machine - Combinational
    // ========================================================================
    always @(*) begin
        wr_next = wr_state;
        
        case (wr_state)
            WR_IDLE: begin
                if (S_AXI_AWVALID) begin
                    wr_next = WR_ADDR;
                end
            end
            
            WR_ADDR: begin
                // Accept address
                wr_next = WR_DATA;
            end
            
            WR_DATA: begin
                if (S_AXI_WVALID) begin
                    wr_next = WR_RESP;
                end
            end
            
            WR_RESP: begin
                if (S_AXI_BREADY) begin
                    wr_next = WR_IDLE;
                end
            end
            
            default: wr_next = WR_IDLE;
        endcase
    end
    
    // ========================================================================
    // Write Address Channel (Accept but reject later)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (S_AXI_AWVALID) begin
                        S_AXI_AWREADY <= 1'b1;
                    end else begin
                        S_AXI_AWREADY <= 1'b0;
                    end
                end
                
                WR_ADDR: begin
                    S_AXI_AWREADY <= 1'b0;
                end
                
                default: begin
                    S_AXI_AWREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write Data Channel (Accept but ignore)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_WREADY <= 1'b0;
        end else begin
            case (wr_state)
                WR_DATA: begin
                    if (S_AXI_WVALID) begin
                        S_AXI_WREADY <= 1'b1;
                    end else begin
                        S_AXI_WREADY <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_WREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write Response Channel (Always return SLVERR)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BRESP  <= RESP_SLVERR;
            S_AXI_BVALID <= 1'b0;
        end else begin
            case (wr_state)
                WR_DATA: begin
                    if (S_AXI_WVALID) begin
                        S_AXI_BRESP  <= RESP_SLVERR;  // ROM không thể ghi
                        S_AXI_BVALID <= 1'b1;
                    end
                end
                
                WR_RESP: begin
                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_BVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Debug/Warning for write attempts
    // ========================================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (wr_state == WR_RESP && S_AXI_BREADY) begin
            $display("[IMEM WARNING] Write attempt to ROM at addr=0x%08h, time=%0t", 
                     S_AXI_AWADDR, $time);
        end
    end
    // synthesis translate_on

endmodule