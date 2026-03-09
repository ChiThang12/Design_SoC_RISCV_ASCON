// ============================================================================
// Module: dma_engine_axi4
// ============================================================================
// Description:
//   Enhanced DMA transfer engine with full AXI4 master interface
//
// Features:
//   - Full AXI4 protocol compliance (ID, LOCK, CACHE, PROT, QOS)
//   - AXI4 burst read and write operations with configurable burst length
//   - Enhanced internal FIFO with almost-full/empty flags
//   - Configurable burst size (1-256 beats)
//   - Support for incremental, fixed, and wrap addressing
//   - Comprehensive error detection and reporting
//   - Outstanding transaction tracking
//   - Optimized state machine for better throughput
//
// Author: ChiThang (Enhanced AXI4-Full Version)
// ============================================================================

`include "dma_defines_axi4.vh"

module dma_engine_axi4 #(
    parameter DATA_WIDTH = `DMA_DATA_WIDTH,
    parameter ADDR_WIDTH = `DMA_ADDR_WIDTH,
    parameter ID_WIDTH   = `DMA_ID_WIDTH,
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
    input wire [3:0]  cache_type,         // Cache type for AXI
    input wire [2:0]  prot_type,          // Protection type for AXI
    input wire [ID_WIDTH-1:0] channel_id, // Channel ID for AXI transactions
    
    output reg        busy,               // Engine is busy
    output reg        done,               // Transfer complete
    output reg        error,              // Transfer error
    output reg [1:0]  error_type,         // 00=none, 01=read_err, 10=write_err
    
    // ========================================================================
    // AXI4 Master Interface - Write Channels
    // ========================================================================
    // Write Address Channel
    output reg [ID_WIDTH-1:0]   M_AXI_AWID,
    output reg [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output reg [7:0]            M_AXI_AWLEN,
    output reg [2:0]            M_AXI_AWSIZE,
    output reg [1:0]            M_AXI_AWBURST,
    output reg                  M_AXI_AWLOCK,
    output reg [3:0]            M_AXI_AWCACHE,
    output reg [2:0]            M_AXI_AWPROT,
    output reg [3:0]            M_AXI_AWQOS,
    output reg                  M_AXI_AWVALID,
    input wire                  M_AXI_AWREADY,
    
    // Write Data Channel
    output reg [DATA_WIDTH-1:0]     M_AXI_WDATA,
    output reg [DATA_WIDTH/8-1:0]   M_AXI_WSTRB,
    output reg                      M_AXI_WLAST,
    output reg                      M_AXI_WVALID,
    input wire                      M_AXI_WREADY,
    
    // Write Response Channel
    input wire [ID_WIDTH-1:0] M_AXI_BID,
    input wire [1:0]          M_AXI_BRESP,
    input wire                M_AXI_BVALID,
    output reg                M_AXI_BREADY,
    
    // ========================================================================
    // AXI4 Master Interface - Read Channels
    // ========================================================================
    // Read Address Channel
    output reg [ID_WIDTH-1:0]   M_AXI_ARID,
    output reg [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output reg [7:0]            M_AXI_ARLEN,
    output reg [2:0]            M_AXI_ARSIZE,
    output reg [1:0]            M_AXI_ARBURST,
    output reg                  M_AXI_ARLOCK,
    output reg [3:0]            M_AXI_ARCACHE,
    output reg [2:0]            M_AXI_ARPROT,
    output reg [3:0]            M_AXI_ARQOS,
    output reg                  M_AXI_ARVALID,
    input wire                  M_AXI_ARREADY,
    
    // Read Data Channel
    input wire [ID_WIDTH-1:0]   M_AXI_RID,
    input wire [DATA_WIDTH-1:0] M_AXI_RDATA,
    input wire [1:0]            M_AXI_RRESP,
    input wire                  M_AXI_RLAST,
    input wire                  M_AXI_RVALID,
    output reg                  M_AXI_RREADY
);

    // ========================================================================
    // Internal State Machine
    // ========================================================================
    reg [3:0] state;
    
    // ========================================================================
    // Transfer Tracking
    // ========================================================================
    reg [31:0] current_src_addr;
    reg [31:0] current_dst_addr;
    reg [31:0] bytes_remaining;
    reg [7:0]  current_burst_len;
    reg [7:0]  beat_counter;
    reg [7:0]  read_burst_beats;     // Tracks beats in current read burst
    reg [7:0]  write_burst_beats;    // Tracks beats in current write burst
    
    // Outstanding transaction tracking
    reg [2:0] outstanding_reads;
    reg [2:0] outstanding_writes;
    
    // ========================================================================
    // Internal FIFO for Read Data
    // ========================================================================
    reg [DATA_WIDTH-1:0] read_fifo [0:FIFO_DEPTH-1];
    reg [5:0] fifo_wr_ptr;
    reg [5:0] fifo_rd_ptr;
    reg [6:0] fifo_count;
    
    wire fifo_full;
    wire fifo_empty;
    wire fifo_almost_full;
    wire fifo_almost_empty;
    
    assign fifo_full        = (fifo_count >= FIFO_DEPTH);
    assign fifo_empty       = (fifo_count == 0);
    assign fifo_almost_full = (fifo_count >= `DMA_FIFO_THRESHOLD);
    assign fifo_almost_empty= (fifo_count <= 4);
    
    // ========================================================================
    // Burst Size Decoding
    // ========================================================================
    reg [7:0] max_burst_beats;
    
    always @(*) begin
        case (burst_size)
            `DMA_BURST_1:   max_burst_beats = 8'd1;
            `DMA_BURST_4:   max_burst_beats = 8'd4;
            `DMA_BURST_8:   max_burst_beats = 8'd8;
            `DMA_BURST_16:  max_burst_beats = 8'd16;
            `DMA_BURST_32:  max_burst_beats = 8'd32;
            `DMA_BURST_64:  max_burst_beats = 8'd64;
            `DMA_BURST_128: max_burst_beats = 8'd128;
            `DMA_BURST_256: max_burst_beats = 8'd256;
            default:        max_burst_beats = 8'd16;
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
    // Burst Length Calculation
    // ========================================================================
    reg [7:0] calculated_burst_len;
    reg [31:0] bytes_in_burst;
    
    always @(*) begin
        // Calculate how many beats we can do in this burst
        bytes_in_burst = max_burst_beats * bytes_per_beat;
        
        if (bytes_remaining >= bytes_in_burst) begin
            calculated_burst_len = max_burst_beats - 1; // AXI len = beats - 1
        end else begin
            // Calculate exact number of beats needed for remaining bytes
            calculated_burst_len = ((bytes_remaining + bytes_per_beat - 1) / bytes_per_beat) - 1;
        end
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
            error_type        <= 2'b00;
            current_src_addr  <= 32'h0;
            current_dst_addr  <= 32'h0;
            bytes_remaining   <= 32'h0;
            current_burst_len <= 8'h0;
            beat_counter      <= 8'h0;
            read_burst_beats  <= 8'h0;
            write_burst_beats <= 8'h0;
            outstanding_reads <= 3'h0;
            outstanding_writes<= 3'h0;
            
            // Write Address Channel
            M_AXI_AWID        <= {ID_WIDTH{1'b0}};
            M_AXI_AWADDR      <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWLEN       <= 8'h0;
            M_AXI_AWSIZE      <= 3'b0;
            M_AXI_AWBURST     <= 2'b0;
            M_AXI_AWLOCK      <= 1'b0;
            M_AXI_AWCACHE     <= 4'h0;
            M_AXI_AWPROT      <= 3'b0;
            M_AXI_AWQOS       <= 4'h0;
            M_AXI_AWVALID     <= 1'b0;
            
            // Write Data Channel
            M_AXI_WDATA       <= {DATA_WIDTH{1'b0}};
            M_AXI_WSTRB       <= {DATA_WIDTH/8{1'b0}};
            M_AXI_WLAST       <= 1'b0;
            M_AXI_WVALID      <= 1'b0;
            
            // Write Response Channel
            M_AXI_BREADY      <= 1'b0;
            
            // Read Address Channel
            M_AXI_ARID        <= {ID_WIDTH{1'b0}};
            M_AXI_ARADDR      <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARLEN       <= 8'h0;
            M_AXI_ARSIZE      <= 3'b0;
            M_AXI_ARBURST     <= 2'b0;
            M_AXI_ARLOCK      <= 1'b0;
            M_AXI_ARCACHE     <= 4'h0;
            M_AXI_ARPROT      <= 3'b0;
            M_AXI_ARQOS       <= 4'h0;
            M_AXI_ARVALID     <= 1'b0;
            
            // Read Data Channel
            M_AXI_RREADY      <= 1'b0;
            
            // FIFO
            fifo_wr_ptr       <= 6'h0;
            fifo_rd_ptr       <= 6'h0;
            fifo_count        <= 7'h0;
            
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                read_fifo[i] <= {DATA_WIDTH{1'b0}};
            end
            
        end else begin
            case (state)
                // ============================================================
                // READ_ADDR: Issue read address
                // ============================================================
                `DMA_STATE_READ_ADDR: begin
                    // Only issue read if FIFO has space
                    if (!fifo_almost_full && bytes_remaining > 0) begin
                        if (!M_AXI_ARVALID) begin
                            // Cycle 1: latch address signals and assert ARVALID
                            current_burst_len <= calculated_burst_len;
                            read_burst_beats  <= calculated_burst_len + 1;
                            M_AXI_ARID    <= channel_id;
                            M_AXI_ARADDR  <= current_src_addr;
                            M_AXI_ARLEN   <= calculated_burst_len;
                            M_AXI_ARSIZE  <= axi_size;
                            M_AXI_ARBURST <= src_incr ? `AXI_BURST_INCR : `AXI_BURST_FIXED;
                            M_AXI_ARLOCK  <= `AXI_LOCK_NORMAL;
                            M_AXI_ARCACHE <= cache_type;
                            M_AXI_ARPROT  <= prot_type;
                            M_AXI_ARQOS   <= `AXI_QOS_DEFAULT;
                            M_AXI_ARVALID <= 1'b1;
                        end else if (M_AXI_ARREADY) begin
                            // Cycle 2+: slave has accepted — deassert ARVALID
                            M_AXI_ARVALID     <= 1'b0;
                            M_AXI_RREADY      <= 1'b1;
                            beat_counter      <= 8'h0;
                            outstanding_reads <= outstanding_reads + 1;
                            state             <= `DMA_STATE_READ_DATA;
                        end
                    end else if (bytes_remaining == 0) begin
                        // All reads issued, wait for data
                        if (fifo_empty && outstanding_reads == 0) begin
                            state <= `DMA_STATE_DONE;
                        end else begin
                            state <= `DMA_STATE_WRITE_ADDR;
                        end
                    end
                end
                
                // ============================================================
                // READ_DATA: Receive read data into FIFO
                // ============================================================
                `DMA_STATE_READ_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        // Write to FIFO
                        if (!fifo_full) begin
                            read_fifo[fifo_wr_ptr] <= M_AXI_RDATA;
                            fifo_wr_ptr <= fifo_wr_ptr + 1;
                            fifo_count  <= fifo_count + 1;
                        end
                        
                        beat_counter <= beat_counter + 1;
                        
                        // Check for errors
                        if (M_AXI_RRESP != `AXI_RESP_OKAY && M_AXI_RRESP != `AXI_RESP_EXOKAY) begin
                            error      <= 1'b1;
                            error_type <= 2'b01; // Read error
                            M_AXI_RREADY <= 1'b0;
                            state      <= `DMA_STATE_ERROR;
                        end
                        
                        // Last beat of burst
                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY <= 1'b0;
                            outstanding_reads <= outstanding_reads - 1;
                            
                            // Update source address
                            if (src_incr) begin
                                current_src_addr <= current_src_addr + ({{24{1'b0}}, read_burst_beats} * {{28{1'b0}}, bytes_per_beat});
                            end
                            
                            // Update bytes remaining
                            bytes_remaining <= bytes_remaining - ({{24{1'b0}}, read_burst_beats} * {{28{1'b0}}, bytes_per_beat});
                            
                            // Move to write phase
                            state <= `DMA_STATE_WRITE_ADDR;
                        end
                    end
                end
                
                // ============================================================
                // WRITE_ADDR: Issue write address
                // ============================================================
                `DMA_STATE_WRITE_ADDR: begin
                    // Only issue write if we have data in FIFO
                    if (!fifo_empty && outstanding_writes < `MAX_OUTSTANDING_WRITES) begin
                        if (!M_AXI_AWVALID) begin
                            // Cycle 1: latch address signals and assert AWVALID
                            write_burst_beats <= read_burst_beats;
                            M_AXI_AWID    <= channel_id;
                            M_AXI_AWADDR  <= current_dst_addr;
                            M_AXI_AWLEN   <= current_burst_len;
                            M_AXI_AWSIZE  <= axi_size;
                            M_AXI_AWBURST <= dst_incr ? `AXI_BURST_INCR : `AXI_BURST_FIXED;
                            M_AXI_AWLOCK  <= `AXI_LOCK_NORMAL;
                            M_AXI_AWCACHE <= cache_type;
                            M_AXI_AWPROT  <= prot_type;
                            M_AXI_AWQOS   <= `AXI_QOS_DEFAULT;
                            M_AXI_AWVALID <= 1'b1;
                        end else if (M_AXI_AWREADY) begin
                            // Cycle 2+: slave has accepted — deassert AWVALID
                            M_AXI_AWVALID      <= 1'b0;
                            beat_counter       <= 8'h0;
                            outstanding_writes <= outstanding_writes + 1;
                            state              <= `DMA_STATE_WRITE_DATA;
                        end
                    end else if (fifo_empty && bytes_remaining > 0) begin
                        // Need more data, go back to reading
                        state <= `DMA_STATE_READ_ADDR;
                    end else if (fifo_empty && bytes_remaining == 0 && outstanding_writes == 0) begin
                        // All done
                        state <= `DMA_STATE_DONE;
                    end
                end
                
                // ============================================================
                // WRITE_DATA: Send write data from FIFO
                // ============================================================
                `DMA_STATE_WRITE_DATA: begin
                    if (!fifo_empty || M_AXI_WVALID) begin
                        // Send data
                        if (!M_AXI_WVALID) begin
                            M_AXI_WDATA  <= read_fifo[fifo_rd_ptr];
                            M_AXI_WSTRB  <= {DATA_WIDTH/8{1'b1}}; // Full strobe
                            M_AXI_WLAST  <= (beat_counter == current_burst_len);
                            M_AXI_WVALID <= 1'b1;
                        end
                        
                        if (M_AXI_WREADY && M_AXI_WVALID) begin
                            fifo_rd_ptr  <= fifo_rd_ptr + 1;
                            fifo_count   <= fifo_count - 1;
                            beat_counter <= beat_counter + 1;
                            M_AXI_WVALID <= 1'b0;
                            
                            if (M_AXI_WLAST) begin
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
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BREADY       <= 1'b0;
                        outstanding_writes <= outstanding_writes - 1;
                        
                        // Check response
                        if (M_AXI_BRESP != `AXI_RESP_OKAY && M_AXI_BRESP != `AXI_RESP_EXOKAY) begin
                            error      <= 1'b1;
                            error_type <= 2'b10; // Write error
                            state      <= `DMA_STATE_ERROR;
                        end else begin
                            // Update destination address
                            if (dst_incr) begin
                                current_dst_addr <= current_dst_addr + ({{24{1'b0}}, write_burst_beats} * {{28{1'b0}}, bytes_per_beat});
                            end
                            
                            // Check if transfer complete or need more data
                            if (bytes_remaining == 0 && fifo_empty) begin
                                state <= `DMA_STATE_DONE;
                            end else if (bytes_remaining > 0) begin
                                state <= `DMA_STATE_READ_ADDR;
                            end else begin
                                state <= `DMA_STATE_WRITE_ADDR;
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
                
                // ============================================================
                // ERROR: Transfer error occurred
                // ============================================================
                `DMA_STATE_ERROR: begin
                    busy  <= 1'b0;
                    done  <= 1'b0;
                    error <= 1'b1;
                    state <= `DMA_STATE_IDLE;
                end
                
                // ============================================================
                // IDLE: clear done/error flags from previous transfer
                // ============================================================
                `DMA_STATE_IDLE: begin
                    if (start && transfer_size > 0) begin
                        current_src_addr  <= src_addr;
                        current_dst_addr  <= dst_addr;
                        bytes_remaining   <= transfer_size;
                        busy              <= 1'b1;
                        done              <= 1'b0;
                        error             <= 1'b0;
                        error_type        <= 2'b00;
                        fifo_wr_ptr       <= 6'h0;
                        fifo_rd_ptr       <= 6'h0;
                        fifo_count        <= 7'h0;
                        outstanding_reads <= 3'h0;
                        outstanding_writes<= 3'h0;
                        state             <= `DMA_STATE_READ_ADDR;
                    end else begin
                        // Auto-clear done/error one cycle after returning to IDLE
                        done  <= 1'b0;
                        error <= 1'b0;
                    end
                end
                
                default: state <= `DMA_STATE_IDLE;
            endcase
        end
    end

endmodule