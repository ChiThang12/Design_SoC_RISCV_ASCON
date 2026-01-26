// ============================================================================
// Module: icache_axi_interface
// ============================================================================
// Description:
//   AXI4 master interface for cache line refill with BURST support
//   - Single burst read 4 words (one cache line)
//   - Uses ARLEN=3 for 4-beat INCR burst
//
// Author: ChiThang
// Version: AXI4 Full
// ============================================================================

`include "icache_defines.vh"

module icache_axi_interface (
    input wire clk,
    input wire rst_n,
    
    // Control Interface
    input wire [31:0] refill_addr,      // Line-aligned address to fetch
    input wire        refill_start,     // Start refill operation
    output reg        refill_busy,      // Refill in progress
    output reg        refill_done,      // Refill complete (1-cycle pulse)
    
    // Data Output
    output reg [31:0] refill_data,      // Current word being filled
    output reg [1:0]  refill_word,      // Word counter (0-3)
    output reg        refill_data_valid, // Data valid
    
    // AXI4 Master Read Channel
    output reg [31:0] M_AXI_ARADDR,
    output wire [7:0] M_AXI_ARLEN,      // Burst length - 1 (3 = 4 beats)
    output wire [2:0] M_AXI_ARSIZE,     // 2^2 = 4 bytes per beat
    output wire [1:0] M_AXI_ARBURST,    // INCR = 01
    output wire [2:0] M_AXI_ARPROT,
    output reg        M_AXI_ARVALID,
    input wire        M_AXI_ARREADY,
    
    input wire [31:0] M_AXI_RDATA,
    input wire [1:0]  M_AXI_RRESP,
    input wire        M_AXI_RLAST,      // Last beat indicator
    input wire        M_AXI_RVALID,
    output reg        M_AXI_RREADY
);

    // ========================================================================
    // AXI4 Protocol Constants
    // ========================================================================
    assign M_AXI_ARLEN   = 8'd3;        // 4 beats (ARLEN = n-1)
    assign M_AXI_ARSIZE  = 3'b010;      // 4 bytes (2^2 = 4)
    assign M_AXI_ARBURST = 2'b01;       // INCR (incrementing burst)
    assign M_AXI_ARPROT  = 3'b000;      // Unprivileged, secure, data access
    
    // ========================================================================
    // Refill State Machine
    // ========================================================================
    localparam [1:0]
        REFILL_IDLE = 2'b00,
        REFILL_AR   = 2'b01,
        REFILL_R    = 2'b10;
    
    reg [1:0] state;
    reg [1:0] word_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= REFILL_IDLE;
            refill_busy      <= 1'b0;
            refill_done      <= 1'b0;
            refill_data_valid <= 1'b0;
            refill_data      <= 32'h0;
            refill_word      <= 2'b00;
            word_counter     <= 2'b00;
            M_AXI_ARADDR     <= 32'h0;
            M_AXI_ARVALID    <= 1'b0;
            M_AXI_RREADY     <= 1'b0;
            
        end else begin
            // Default: clear one-shot signals
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            
            case (state)
                REFILL_IDLE: begin
                    if (refill_start) begin
                        // Start burst refill
                        M_AXI_ARADDR  <= refill_addr;
                        M_AXI_ARVALID <= 1'b1;
                        refill_busy   <= 1'b1;
                        word_counter  <= 2'b00;
                        state         <= REFILL_AR;
                    end
                end
                
                REFILL_AR: begin
                    // Wait for address handshake
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;
                        state         <= REFILL_R;
                    end
                end
                
                REFILL_R: begin
                    // Receive burst data
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        refill_data       <= M_AXI_RDATA;
                        refill_word       <= word_counter;
                        refill_data_valid <= 1'b1;
                        word_counter      <= word_counter + 1;
                        
                        // Check for last beat (using RLAST)
                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY  <= 1'b0;
                            refill_busy   <= 1'b0;
                            refill_done   <= 1'b1;
                            state         <= REFILL_IDLE;
                        end
                    end
                end
                
                default: state <= REFILL_IDLE;
            endcase
        end
    end

endmodule