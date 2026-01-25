// ============================================================================
// Module: dma_engine
// ============================================================================
// Description:
//   DMA transfer engine with AXI4 master interface
//
// Features:
//   - AXI4 burst read and write operations
//   - Internal FIFO for read data buffering
//   - Configurable burst size (1, 4, 8, 16 beats)
//   - Support for incremental and fixed addressing
//   - Error detection and reporting
//
// Author: ChiThang
// ============================================================================

`include "dma/dma_defines.vh"

module dma_engine #(
    parameter DATA_WIDTH = `DMA_DATA_WIDTH,
    parameter ADDR_WIDTH = `DMA_ADDR_WIDTH,
    parameter FIFO_DEPTH = `DMA_FIFO_DEPTH
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Control Interface (from arbiter/channel)
    // ========================================================================
    input wire        start,              // Start transfer
    input wire [31:0] src_addr,           // Source address
    input wire [31:0] dst_addr,           // Destination address
    input wire [31:0] transfer_size,      // Total bytes to transfer
    input wire [2:0]  burst_size,         // Burst size encoding
    input wire [1:0]  data_width,         // Data width encoding
    input wire        src_incr,           // Source address increment enable
    input wire        dst_incr,           // Destination address increment enable
    
    output reg        busy,               // Engine is busy
    output reg        done,               // Transfer complete
    output reg        error,              // Transfer error
    
    // ========================================================================
    // AXI4 Master Interface
    // ========================================================================
    // Write Address Channel
    output reg [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output reg [7:0]            M_AXI_AWLEN,
    output reg [2:0]            M_AXI_AWSIZE,
    output reg [1:0]            M_AXI_AWBURST,
    output reg                  M_AXI_AWVALID,
    input wire                  M_AXI_AWREADY,
    
    // Write Data Channel
    output reg [DATA_WIDTH-1:0]     M_AXI_WDATA,
    output reg [DATA_WIDTH/8-1:0]   M_AXI_WSTRB,
    output reg                      M_AXI_WLAST,
    output reg                      M_AXI_WVALID,
    input wire                      M_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]  M_AXI_BRESP,
    input wire        M_AXI_BVALID,
    output reg        M_AXI_BREADY,
    
    // Read Address Channel
    output reg [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output reg [7:0]            M_AXI_ARLEN,
    output reg [2:0]            M_AXI_ARSIZE,
    output reg [1:0]            M_AXI_ARBURST,
    output reg                  M_AXI_ARVALID,
    input wire                  M_AXI_ARREADY,
    
    // Read Data Channel
    input wire [DATA_WIDTH-1:0] M_AXI_RDATA,
    input wire [1:0]            M_AXI_RRESP,
    input wire                  M_AXI_RLAST,
    input wire                  M_AXI_RVALID,
    output reg                  M_AXI_RREADY
);

    // ========================================================================
    // Internal State Machine
    // ========================================================================
    reg [2:0] state;
    
    // ========================================================================
    // Transfer Tracking
    // ========================================================================
    reg [31:0] current_src_addr;
    reg [31:0] current_dst_addr;
    reg [31:0] bytes_remaining;
    reg [7:0]  current_burst_len;
    reg [7:0]  beat_counter;
    
    // ========================================================================
    // Internal FIFO for Read Data
    // ========================================================================
    reg [DATA_WIDTH-1:0] read_fifo [0:FIFO_DEPTH-1];
    reg [3:0] fifo_wr_ptr;
    reg [3:0] fifo_rd_ptr;
    reg [4:0] fifo_count;
    
    wire fifo_full;
    wire fifo_empty;
    
    assign fifo_full  = (fifo_count == FIFO_DEPTH);
    assign fifo_empty = (fifo_count == 0);
    
    // ========================================================================
    // Burst Size Decoding
    // ========================================================================
    reg [7:0] max_burst_beats;
    
    always @(*) begin
        case (burst_size)
            `DMA_BURST_1:  max_burst_beats = 8'd1;
            `DMA_BURST_4:  max_burst_beats = 8'd4;
            `DMA_BURST_8:  max_burst_beats = 8'd8;
            `DMA_BURST_16: max_burst_beats = 8'd16;
            default:       max_burst_beats = 8'd1;
        endcase
    end
    
    // ========================================================================
    // Transfer Size Decoding
    // ========================================================================
    reg [2:0] axi_size;
    reg [3:0] bytes_per_beat;
    
    always @(*) begin
        case (data_width)
            `DMA_WIDTH_8BIT: begin
                axi_size = `AXI_SIZE_1BYTE;
                bytes_per_beat = 4'd1;
            end
            `DMA_WIDTH_16BIT: begin
                axi_size = `AXI_SIZE_2BYTE;
                bytes_per_beat = 4'd2;
            end
            `DMA_WIDTH_32BIT: begin
                axi_size = `AXI_SIZE_4BYTE;
                bytes_per_beat = 4'd4;
            end
            default: begin
                axi_size = `AXI_SIZE_4BYTE;
                bytes_per_beat = 4'd4;
            end
        endcase
    end
    
    // ========================================================================
    // Main State Machine
    // ========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= `DMA_STATE_IDLE;
            busy              <= 1'b0;
            done              <= 1'b0;
            error             <= 1'b0;
            current_src_addr  <= 32'h0;
            current_dst_addr  <= 32'h0;
            bytes_remaining   <= 32'h0;
            current_burst_len <= 8'h0;
            beat_counter      <= 8'h0;
            
            M_AXI_AWADDR      <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWLEN       <= 8'h0;
            M_AXI_AWSIZE      <= 3'b0;
            M_AXI_AWBURST     <= 2'b0;
            M_AXI_AWVALID     <= 1'b0;
            
            M_AXI_WDATA       <= {DATA_WIDTH{1'b0}};
            M_AXI_WSTRB       <= {DATA_WIDTH/8{1'b0}};
            M_AXI_WLAST       <= 1'b0;
            M_AXI_WVALID      <= 1'b0;
            
            M_AXI_BREADY      <= 1'b0;
            
            M_AXI_ARADDR      <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARLEN       <= 8'h0;
            M_AXI_ARSIZE      <= 3'b0;
            M_AXI_ARBURST     <= 2'b0;
            M_AXI_ARVALID     <= 1'b0;
            
            M_AXI_RREADY      <= 1'b0;
            
            fifo_wr_ptr       <= 4'h0;
            fifo_rd_ptr       <= 4'h0;
            fifo_count        <= 5'h0;
            
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                read_fifo[i] <= {DATA_WIDTH{1'b0}};
            end
            
        end else begin
            case (state)
                // ============================================================
                // IDLE: Wait for start command
                // ============================================================
                `DMA_STATE_IDLE: begin
                    if (start) begin
                        current_src_addr <= src_addr;
                        current_dst_addr <= dst_addr;
                        bytes_remaining  <= transfer_size;
                        busy             <= 1'b1;
                        done             <= 1'b0;
                        error            <= 1'b0;
                        fifo_wr_ptr      <= 4'h0;
                        fifo_rd_ptr      <= 4'h0;
                        fifo_count       <= 5'h0;
                        state            <= `DMA_STATE_READ_ADDR;
                    end
                end
                
                // ============================================================
                // READ_ADDR: Issue read address
                // ============================================================
                `DMA_STATE_READ_ADDR: begin
                    // Calculate burst length (min of max_burst and remaining)
                    if (bytes_remaining >= (max_burst_beats * bytes_per_beat)) begin
                        current_burst_len <= max_burst_beats - 1; // AXI len = beats - 1
                    end else begin
                        current_burst_len <= (bytes_remaining / bytes_per_beat) - 1;
                    end
                    
                    M_AXI_ARADDR  <= current_src_addr;
                    M_AXI_ARLEN   <= current_burst_len;
                    M_AXI_ARSIZE  <= axi_size;
                    M_AXI_ARBURST <= src_incr ? `AXI_BURST_INCR : `AXI_BURST_FIXED;
                    M_AXI_ARVALID <= 1'b1;
                    
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;
                        beat_counter  <= 8'h0;
                        state         <= `DMA_STATE_READ_DATA;
                    end
                end
                
                // ============================================================
                // READ_DATA: Receive read data into FIFO
                // ============================================================
                `DMA_STATE_READ_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        // Write to FIFO
                        read_fifo[fifo_wr_ptr] <= M_AXI_RDATA;
                        fifo_wr_ptr <= fifo_wr_ptr + 1;
                        fifo_count  <= fifo_count + 1;
                        beat_counter <= beat_counter + 1;
                        
                        // Check for errors
                        if (M_AXI_RRESP != `AXI_RESP_OKAY) begin
                            error <= 1'b1;
                            state <= `DMA_STATE_DONE;
                        end
                        
                        // Last beat
                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY <= 1'b0;
                            state        <= `DMA_STATE_WRITE_ADDR;
                        end
                    end
                end
                
                // ============================================================
                // WRITE_ADDR: Issue write address
                // ============================================================
                `DMA_STATE_WRITE_ADDR: begin
                    M_AXI_AWADDR  <= current_dst_addr;
                    M_AXI_AWLEN   <= current_burst_len;
                    M_AXI_AWSIZE  <= axi_size;
                    M_AXI_AWBURST <= dst_incr ? `AXI_BURST_INCR : `AXI_BURST_FIXED;
                    M_AXI_AWVALID <= 1'b1;
                    
                    if (M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        beat_counter  <= 8'h0;
                        state         <= `DMA_STATE_WRITE_DATA;
                    end
                end
                
                // ============================================================
                // WRITE_DATA: Send write data from FIFO
                // ============================================================
                `DMA_STATE_WRITE_DATA: begin
                    if (!fifo_empty) begin
                        M_AXI_WDATA  <= read_fifo[fifo_rd_ptr];
                        M_AXI_WSTRB  <= {DATA_WIDTH/8{1'b1}}; // Full strobe
                        M_AXI_WVALID <= 1'b1;
                        M_AXI_WLAST  <= (beat_counter == current_burst_len);
                        
                        if (M_AXI_WREADY) begin
                            fifo_rd_ptr  <= fifo_rd_ptr + 1;
                            fifo_count   <= fifo_count - 1;
                            beat_counter <= beat_counter + 1;
                            
                            if (beat_counter == current_burst_len) begin
                                M_AXI_WVALID <= 1'b0;
                                M_AXI_BREADY <= 1'b1;
                                state        <= `DMA_STATE_WRITE_RESP;
                            end
                        end
                    end
                end
                
                // ============================================================
                // WRITE_RESP: Wait for write response
                // ============================================================
                `DMA_STATE_WRITE_RESP: begin
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY <= 1'b0;
                        
                        // Check response
                        if (M_AXI_BRESP != `AXI_RESP_OKAY) begin
                            error <= 1'b1;
                            state <= `DMA_STATE_DONE;
                        end else begin
                            // Update addresses and counters
                            if (src_incr) begin
                                current_src_addr <= current_src_addr + ((current_burst_len + 1) * bytes_per_beat);
                            end
                            
                            if (dst_incr) begin
                                current_dst_addr <= current_dst_addr + ((current_burst_len + 1) * bytes_per_beat);
                            end
                            
                            bytes_remaining <= bytes_remaining - ((current_burst_len + 1) * bytes_per_beat);
                            
                            // Check if transfer complete
                            if (bytes_remaining <= ((current_burst_len + 1) * bytes_per_beat)) begin
                                state <= `DMA_STATE_DONE;
                            end else begin
                                state <= `DMA_STATE_READ_ADDR;
                            end
                        end
                    end
                end
                
                // ============================================================
                // DONE: Transfer complete
                // ============================================================
                `DMA_STATE_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= `DMA_STATE_IDLE;
                end
                
                default: state <= `DMA_STATE_IDLE;
            endcase
        end
    end

endmodule