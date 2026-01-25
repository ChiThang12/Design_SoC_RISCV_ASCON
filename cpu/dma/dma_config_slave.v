// ============================================================================
// Module: dma_config_slave
// ============================================================================
// Description:
//   AXI4-Lite slave interface for DMA configuration
//
// Register Map:
//   Channel 0: 0x00 - 0x1F
//   Channel 1: 0x20 - 0x3F
//   Channel 2: 0x40 - 0x5F
//   Channel 3: 0x60 - 0x7F
//
// Author: ChiThang
// ============================================================================

`include "dma/dma_defines.vh"

module dma_config_slave #(
    parameter NUM_CHANNELS = `NUM_DMA_CHANNELS,
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4-Lite Slave Interface
    // ========================================================================
    input wire [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0]            S_AXI_AWPROT,
    input wire                  S_AXI_AWVALID,
    output reg                  S_AXI_AWREADY,
    
    input wire [31:0]           S_AXI_WDATA,
    input wire [3:0]            S_AXI_WSTRB,
    input wire                  S_AXI_WVALID,
    output reg                  S_AXI_WREADY,
    
    output reg [1:0]            S_AXI_BRESP,
    output reg                  S_AXI_BVALID,
    input wire                  S_AXI_BREADY,
    
    input wire [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0]            S_AXI_ARPROT,
    input wire                  S_AXI_ARVALID,
    output reg                  S_AXI_ARREADY,
    
    output reg [31:0]           S_AXI_RDATA,
    output reg [1:0]            S_AXI_RRESP,
    output reg                  S_AXI_RVALID,
    input wire                  S_AXI_RREADY,
    
    // ========================================================================
    // Channel Configuration Interface
    // ========================================================================
    // Channel 0
    output reg [31:0] ch0_src_addr,
    output reg [31:0] ch0_dst_addr,
    output reg [31:0] ch0_length,
    output reg [31:0] ch0_ctrl,
    output reg        ch0_ctrl_write,
    output reg        ch0_status_write,
    output reg [31:0] ch0_status_wdata,
    input wire [31:0] ch0_status,
    input wire [31:0] ch0_curr_src,
    input wire [31:0] ch0_curr_dst,
    input wire [31:0] ch0_remaining,
    
    // Channel 1
    output reg [31:0] ch1_src_addr,
    output reg [31:0] ch1_dst_addr,
    output reg [31:0] ch1_length,
    output reg [31:0] ch1_ctrl,
    output reg        ch1_ctrl_write,
    output reg        ch1_status_write,
    output reg [31:0] ch1_status_wdata,
    input wire [31:0] ch1_status,
    input wire [31:0] ch1_curr_src,
    input wire [31:0] ch1_curr_dst,
    input wire [31:0] ch1_remaining,
    
    // Channel 2
    output reg [31:0] ch2_src_addr,
    output reg [31:0] ch2_dst_addr,
    output reg [31:0] ch2_length,
    output reg [31:0] ch2_ctrl,
    output reg        ch2_ctrl_write,
    output reg        ch2_status_write,
    output reg [31:0] ch2_status_wdata,
    input wire [31:0] ch2_status,
    input wire [31:0] ch2_curr_src,
    input wire [31:0] ch2_curr_dst,
    input wire [31:0] ch2_remaining,
    
    // Channel 3
    output reg [31:0] ch3_src_addr,
    output reg [31:0] ch3_dst_addr,
    output reg [31:0] ch3_length,
    output reg [31:0] ch3_ctrl,
    output reg        ch3_ctrl_write,
    output reg        ch3_status_write,
    output reg [31:0] ch3_status_wdata,
    input wire [31:0] ch3_status,
    input wire [31:0] ch3_curr_src,
    input wire [31:0] ch3_curr_dst,
    input wire [31:0] ch3_remaining
);

    // ========================================================================
    // Write Transaction State
    // ========================================================================
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [31:0]           write_data;
    reg [3:0]            write_strb;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY <= 1'b1;
            S_AXI_WREADY  <= 1'b1;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BRESP   <= 2'b00;
            write_addr    <= {ADDR_WIDTH{1'b0}};
            write_data    <= 32'h0;
            write_strb    <= 4'h0;
            
            ch0_src_addr <= 32'h0;
            ch0_dst_addr <= 32'h0;
            ch0_length   <= 32'h0;
            ch0_ctrl     <= 32'h0;
            ch0_ctrl_write <= 1'b0;
            ch0_status_write <= 1'b0;
            ch0_status_wdata <= 32'h0;
            
            ch1_src_addr <= 32'h0;
            ch1_dst_addr <= 32'h0;
            ch1_length   <= 32'h0;
            ch1_ctrl     <= 32'h0;
            ch1_ctrl_write <= 1'b0;
            ch1_status_write <= 1'b0;
            ch1_status_wdata <= 32'h0;
            
            ch2_src_addr <= 32'h0;
            ch2_dst_addr <= 32'h0;
            ch2_length   <= 32'h0;
            ch2_ctrl     <= 32'h0;
            ch2_ctrl_write <= 1'b0;
            ch2_status_write <= 1'b0;
            ch2_status_wdata <= 32'h0;
            
            ch3_src_addr <= 32'h0;
            ch3_dst_addr <= 32'h0;
            ch3_length   <= 32'h0;
            ch3_ctrl     <= 32'h0;
            ch3_ctrl_write <= 1'b0;
            ch3_status_write <= 1'b0;
            ch3_status_wdata <= 32'h0;
            
        end else begin
            // Clear one-shot signals
            ch0_ctrl_write   <= 1'b0;
            ch0_status_write <= 1'b0;
            ch1_ctrl_write   <= 1'b0;
            ch1_status_write <= 1'b0;
            ch2_ctrl_write   <= 1'b0;
            ch2_status_write <= 1'b0;
            ch3_ctrl_write   <= 1'b0;
            ch3_status_write <= 1'b0;
            
            // Write address phase
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                write_addr    <= S_AXI_AWADDR;
                S_AXI_AWREADY <= 1'b0;
            end
            
            // Write data phase
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                write_data   <= S_AXI_WDATA;
                write_strb   <= S_AXI_WSTRB;
                S_AXI_WREADY <= 1'b0;
            end
            
            // Process write
            if (!S_AXI_AWREADY && !S_AXI_WREADY && !S_AXI_BVALID) begin
                S_AXI_BVALID <= 1'b1;
                S_AXI_BRESP  <= `AXI_RESP_OKAY;
                
                // Decode channel and register
                case (write_addr[6:5]) // Channel select (bits [6:5])
                    2'b00: begin // Channel 0
                        case (write_addr[4:2]) // Register select
                            `DMA_REG_SRC_ADDR: ch0_src_addr <= write_data;
                            `DMA_REG_DST_ADDR: ch0_dst_addr <= write_data;
                            `DMA_REG_LENGTH:   ch0_length   <= write_data;
                            `DMA_REG_CTRL: begin
                                ch0_ctrl       <= write_data;
                                ch0_ctrl_write <= 1'b1;
                            end
                            `DMA_REG_STATUS: begin
                                ch0_status_wdata <= write_data;
                                ch0_status_write <= 1'b1;
                            end
                        endcase
                    end
                    
                    2'b01: begin // Channel 1
                        case (write_addr[4:2])
                            `DMA_REG_SRC_ADDR: ch1_src_addr <= write_data;
                            `DMA_REG_DST_ADDR: ch1_dst_addr <= write_data;
                            `DMA_REG_LENGTH:   ch1_length   <= write_data;
                            `DMA_REG_CTRL: begin
                                ch1_ctrl       <= write_data;
                                ch1_ctrl_write <= 1'b1;
                            end
                            `DMA_REG_STATUS: begin
                                ch1_status_wdata <= write_data;
                                ch1_status_write <= 1'b1;
                            end
                        endcase
                    end
                    
                    2'b10: begin // Channel 2
                        case (write_addr[4:2])
                            `DMA_REG_SRC_ADDR: ch2_src_addr <= write_data;
                            `DMA_REG_DST_ADDR: ch2_dst_addr <= write_data;
                            `DMA_REG_LENGTH:   ch2_length   <= write_data;
                            `DMA_REG_CTRL: begin
                                ch2_ctrl       <= write_data;
                                ch2_ctrl_write <= 1'b1;
                            end
                            `DMA_REG_STATUS: begin
                                ch2_status_wdata <= write_data;
                                ch2_status_write <= 1'b1;
                            end
                        endcase
                    end
                    
                    2'b11: begin // Channel 3
                        case (write_addr[4:2])
                            `DMA_REG_SRC_ADDR: ch3_src_addr <= write_data;
                            `DMA_REG_DST_ADDR: ch3_dst_addr <= write_data;
                            `DMA_REG_LENGTH:   ch3_length   <= write_data;
                            `DMA_REG_CTRL: begin
                                ch3_ctrl       <= write_data;
                                ch3_ctrl_write <= 1'b1;
                            end
                            `DMA_REG_STATUS: begin
                                ch3_status_wdata <= write_data;
                                ch3_status_write <= 1'b1;
                            end
                        endcase
                    end
                endcase
            end
            
            // Write response
            if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID  <= 1'b0;
                S_AXI_AWREADY <= 1'b1;
                S_AXI_WREADY  <= 1'b1;
            end
        end
    end
    
    // ========================================================================
    // Read Transaction
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY <= 1'b1;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RDATA   <= 32'h0;
            S_AXI_RRESP   <= 2'b00;
        end else begin
            // Read address phase
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                S_AXI_ARREADY <= 1'b0;
                S_AXI_RVALID  <= 1'b1;
                S_AXI_RRESP   <= `AXI_RESP_OKAY;
                
                // Decode and read
                case (S_AXI_ARADDR[6:5]) // Channel select
                    2'b00: begin // Channel 0
                        case (S_AXI_ARADDR[4:2])
                            `DMA_REG_SRC_ADDR:   S_AXI_RDATA <= ch0_src_addr;
                            `DMA_REG_DST_ADDR:   S_AXI_RDATA <= ch0_dst_addr;
                            `DMA_REG_LENGTH:     S_AXI_RDATA <= ch0_length;
                            `DMA_REG_CTRL:       S_AXI_RDATA <= ch0_ctrl;
                            `DMA_REG_STATUS:     S_AXI_RDATA <= ch0_status;
                            `DMA_REG_CURR_SRC:   S_AXI_RDATA <= ch0_curr_src;
                            `DMA_REG_CURR_DST:   S_AXI_RDATA <= ch0_curr_dst;
                            `DMA_REG_REMAINING:  S_AXI_RDATA <= ch0_remaining;
                            default:             S_AXI_RDATA <= 32'h0;
                        endcase
                    end
                    
                    2'b01: begin // Channel 1
                        case (S_AXI_ARADDR[4:2])
                            `DMA_REG_SRC_ADDR:   S_AXI_RDATA <= ch1_src_addr;
                            `DMA_REG_DST_ADDR:   S_AXI_RDATA <= ch1_dst_addr;
                            `DMA_REG_LENGTH:     S_AXI_RDATA <= ch1_length;
                            `DMA_REG_CTRL:       S_AXI_RDATA <= ch1_ctrl;
                            `DMA_REG_STATUS:     S_AXI_RDATA <= ch1_status;
                            `DMA_REG_CURR_SRC:   S_AXI_RDATA <= ch1_curr_src;
                            `DMA_REG_CURR_DST:   S_AXI_RDATA <= ch1_curr_dst;
                            `DMA_REG_REMAINING:  S_AXI_RDATA <= ch1_remaining;
                            default:             S_AXI_RDATA <= 32'h0;
                        endcase
                    end
                    
                    2'b10: begin // Channel 2
                        case (S_AXI_ARADDR[4:2])
                            `DMA_REG_SRC_ADDR:   S_AXI_RDATA <= ch2_src_addr;
                            `DMA_REG_DST_ADDR:   S_AXI_RDATA <= ch2_dst_addr;
                            `DMA_REG_LENGTH:     S_AXI_RDATA <= ch2_length;
                            `DMA_REG_CTRL:       S_AXI_RDATA <= ch2_ctrl;
                            `DMA_REG_STATUS:     S_AXI_RDATA <= ch2_status;
                            `DMA_REG_CURR_SRC:   S_AXI_RDATA <= ch2_curr_src;
                            `DMA_REG_CURR_DST:   S_AXI_RDATA <= ch2_curr_dst;
                            `DMA_REG_REMAINING:  S_AXI_RDATA <= ch2_remaining;
                            default:             S_AXI_RDATA <= 32'h0;
                        endcase
                    end
                    
                    2'b11: begin // Channel 3
                        case (S_AXI_ARADDR[4:2])
                            `DMA_REG_SRC_ADDR:   S_AXI_RDATA <= ch3_src_addr;
                            `DMA_REG_DST_ADDR:   S_AXI_RDATA <= ch3_dst_addr;
                            `DMA_REG_LENGTH:     S_AXI_RDATA <= ch3_length;
                            `DMA_REG_CTRL:       S_AXI_RDATA <= ch3_ctrl;
                            `DMA_REG_STATUS:     S_AXI_RDATA <= ch3_status;
                            `DMA_REG_CURR_SRC:   S_AXI_RDATA <= ch3_curr_src;
                            `DMA_REG_CURR_DST:   S_AXI_RDATA <= ch3_curr_dst;
                            `DMA_REG_REMAINING:  S_AXI_RDATA <= ch3_remaining;
                            default:             S_AXI_RDATA <= 32'h0;
                        endcase
                    end
                endcase
            end
            
            // Read response
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID  <= 1'b0;
                S_AXI_ARREADY <= 1'b1;
            end
        end
    end

endmodule