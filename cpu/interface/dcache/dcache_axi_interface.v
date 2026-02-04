// ============================================================================
// Module: dcache_axi_interface
// ============================================================================
// Description:
//   AXI4 master interface for data cache with read refill and write-through
//   - Burst read for cache line refill (4 words)
//   - Single write for write-through operations
//
// Author: ChiThang
// Version: AXI4 Full with Write Support
// ============================================================================

`include "interface/dcache/dcache_defines.vh"

module dcache_axi_interface (
    input wire clk,
    input wire rst_n,
    
    // Read Refill Interface
    input wire [31:0] refill_addr,      // Line-aligned address to fetch
    input wire        refill_start,     // Start refill operation
    output reg        refill_busy,      // Refill in progress
    output reg        refill_done,      // Refill complete (1-cycle pulse)
    output reg [31:0] refill_data,      // Current word being filled
    output reg [1:0]  refill_word,      // Word counter (0-3)
    output reg        refill_data_valid, // Data valid
    
    // Write-Through Interface
    input wire [31:0] wt_addr,          // Write address
    input wire [31:0] wt_data,          // Write data
    input wire [3:0]  wt_strb,          // Write byte enable
    input wire        wt_start,         // Start write operation
    output reg        wt_busy,          // Write in progress
    output reg        wt_done,          // Write complete (1-cycle pulse)
    
    // AXI4 Master Read Channel
    output reg [31:0] M_AXI_ARADDR,
    output wire [7:0] M_AXI_ARLEN,
    output wire [2:0] M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    output wire [2:0] M_AXI_ARPROT,
    output reg        M_AXI_ARVALID,
    input wire        M_AXI_ARREADY,
    
    input wire [31:0] M_AXI_RDATA,
    input wire [1:0]  M_AXI_RRESP,
    input wire        M_AXI_RLAST,
    input wire        M_AXI_RVALID,
    output reg        M_AXI_RREADY,
    
    // AXI4 Master Write Channel
    output reg [31:0] M_AXI_AWADDR,
    output wire [7:0] M_AXI_AWLEN,
    output wire [2:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    output wire [2:0] M_AXI_AWPROT,
    output reg        M_AXI_AWVALID,
    input wire        M_AXI_AWREADY,
    
    output reg [31:0] M_AXI_WDATA,
    output reg [3:0]  M_AXI_WSTRB,
    output wire       M_AXI_WLAST,
    output reg        M_AXI_WVALID,
    input wire        M_AXI_WREADY,
    
    input wire [1:0]  M_AXI_BRESP,
    input wire        M_AXI_BVALID,
    output reg        M_AXI_BREADY
);

    // ========================================================================
    // AXI4 Protocol Constants
    // ========================================================================
    // Read burst: 4 words (cache line refill)
    assign M_AXI_ARLEN   = 8'd3;        // 4 beats (ARLEN = n-1)
    assign M_AXI_ARSIZE  = 3'b010;      // 4 bytes (2^2 = 4)
    assign M_AXI_ARBURST = 2'b01;       // INCR
    assign M_AXI_ARPROT  = 3'b000;
    
    // Write: single word (write-through)
    assign M_AXI_AWLEN   = 8'd0;        // 1 beat
    assign M_AXI_AWSIZE  = 3'b010;      // 4 bytes
    assign M_AXI_AWBURST = 2'b01;       // INCR
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_WLAST   = 1'b1;        // Always last for single write
    
    // ========================================================================
    // Read Refill State Machine
    // ========================================================================
    localparam [1:0]
        RD_IDLE = 2'b00,
        RD_AR   = 2'b01,
        RD_R    = 2'b10,
        RD_DONE = 2'b11;
    
    reg [1:0] rd_state;
    reg [1:0] rd_word_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state          <= RD_IDLE;
            refill_busy       <= 1'b0;
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            refill_data       <= 32'h0;
            refill_word       <= 2'b00;
            rd_word_counter   <= 2'b00;
            M_AXI_ARADDR      <= 32'h0;
            M_AXI_ARVALID     <= 1'b0;
            M_AXI_RREADY      <= 1'b0;
            
        end else begin
            // Default: clear one-shot signals
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            
            case (rd_state)
                RD_IDLE: begin
                    refill_busy      <= 1'b0;
                    M_AXI_ARVALID    <= 1'b0;
                    M_AXI_RREADY     <= 1'b0;
                    rd_word_counter  <= 2'b00;
                    
                    if (refill_start) begin
                        M_AXI_ARADDR  <= refill_addr;
                        M_AXI_ARVALID <= 1'b1;
                        refill_busy   <= 1'b1;
                        rd_state      <= RD_AR;
                    end
                end
                
                RD_AR: begin
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;
                        rd_state      <= RD_R;
                    end
                end
                
                RD_R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        // Capture data
                        refill_data       <= M_AXI_RDATA;
                        refill_word       <= rd_word_counter;
                        refill_data_valid <= 1'b1;
                        
                        if (M_AXI_RLAST) begin
                            // Last word - finish
                            M_AXI_RREADY <= 1'b0;
                            rd_state     <= RD_DONE;
                        end else begin
                            // Continue burst
                            rd_word_counter <= rd_word_counter + 1'b1;
                        end
                    end
                end
                
                RD_DONE: begin
                    refill_done <= 1'b1;
                    rd_state    <= RD_IDLE;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write-Through State Machine
    // ========================================================================
    localparam [1:0]
        WR_IDLE = 2'b00,
        WR_AW   = 2'b01,
        WR_W    = 2'b10,
        WR_B    = 2'b11;
    
    reg [1:0] wr_state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            wt_busy        <= 1'b0;
            wt_done        <= 1'b0;
            M_AXI_AWADDR   <= 32'h0;
            M_AXI_AWVALID  <= 1'b0;
            M_AXI_WDATA    <= 32'h0;
            M_AXI_WSTRB    <= 4'h0;
            M_AXI_WVALID   <= 1'b0;
            M_AXI_BREADY   <= 1'b0;
            
        end else begin
            // Default: clear one-shot signals
            wt_done <= 1'b0;
            
            case (wr_state)
                WR_IDLE: begin
                    wt_busy       <= 1'b0;
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    
                    if (wt_start) begin
                        // Latch write data
                        M_AXI_AWADDR  <= wt_addr;
                        M_AXI_WDATA   <= wt_data;
                        M_AXI_WSTRB   <= wt_strb;
                        M_AXI_AWVALID <= 1'b1;
                        M_AXI_WVALID  <= 1'b1;  // Can issue AW and W simultaneously
                        wt_busy       <= 1'b1;
                        wr_state      <= WR_AW;
                    end
                end
                
                WR_AW: begin
                    // Wait for both AW and W handshakes
                    if (M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                    end
                    
                    if (M_AXI_WREADY) begin
                        M_AXI_WVALID <= 1'b0;
                    end
                    
                    if ((!M_AXI_AWVALID || M_AXI_AWREADY) && 
                        (!M_AXI_WVALID || M_AXI_WREADY)) begin
                        // Both channels done
                        M_AXI_BREADY <= 1'b1;
                        wr_state     <= WR_B;
                    end
                end
                
                WR_B: begin
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY <= 1'b0;
                        wt_done      <= 1'b1;
                        wr_state     <= WR_IDLE;
                    end
                end
            endcase
        end
    end

endmodule