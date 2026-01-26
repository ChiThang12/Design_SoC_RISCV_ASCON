// ============================================================================
// Module: icache_controller
// ============================================================================
// Description:
//   Main cache controller with state machine
//   - Handles lookup, miss detection, refill coordination
//   - Interfaces with tag array, data array, and AXI interface
//
// Author: ChiThang
// ============================================================================

`include "cache/icache_defines.vh"

module icache_controller (
    input wire clk,
    input wire rst_n,
    
    // CPU Interface
    input wire [31:0] cpu_addr,
    input wire        cpu_req,
    output reg [31:0] cpu_rdata,
    output reg        cpu_ready,
    input wire        flush,
    
    // Tag Array Interface
    output wire [5:0]  tag_lookup_index,
    output wire [21:0] tag_lookup_tag,
    input wire         tag_hit,
    output reg         tag_update_valid,
    output reg [5:0]   tag_update_index,
    output reg [21:0]  tag_update_tag,
    output reg         tag_flush_all,
    
    // Data Array Interface
    output wire [5:0]  data_read_index,
    output wire [1:0]  data_read_offset,
    input wire [31:0]  data_read_data,
    output reg         data_write_enable,
    output reg [5:0]   data_write_index,
    output reg [1:0]   data_write_offset,
    output reg [31:0]  data_write_data,
    
    // AXI Refill Interface
    output reg [31:0]  refill_addr,
    output reg         refill_start,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,
    
    // Statistics
    output reg [31:0]  stat_hits,
    output reg [31:0]  stat_misses
);

    // ========================================================================
    // Address Decomposition
    // ========================================================================
    wire [21:0] addr_tag;
    wire [5:0]  addr_index;
    wire [1:0]  addr_offset;
    
    assign addr_tag    = cpu_addr[31:10];
    assign addr_index  = cpu_addr[9:4];
    assign addr_offset = cpu_addr[3:2];
    
    // ========================================================================
    // Tag Array Lookup (Continuous)
    // ========================================================================
    assign tag_lookup_index = addr_index;
    assign tag_lookup_tag   = addr_tag;
    
    // ========================================================================
    // Data Array Read (Continuous)
    // ========================================================================
    assign data_read_index  = addr_index;
    assign data_read_offset = addr_offset;
    
    // ========================================================================
    // State Machine
    // ========================================================================
    reg [2:0] state, next_state;
    
    // Refill tracking
    reg [5:0]  refill_index;
    reg [21:0] refill_tag;
    reg [1:0]  requested_offset;  // Which word CPU originally requested
    reg [31:0] requested_data;    // Save the requested word
    reg        requested_data_ready;
    
    // ========================================================================
    // State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= `ICACHE_STATE_IDLE;
        end else if (flush) begin
            state <= `ICACHE_STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // ========================================================================
    // State Machine - Combinational (Next State Logic)
    // ========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            `ICACHE_STATE_IDLE: begin
                if (cpu_req) begin
                    next_state = `ICACHE_STATE_COMPARE;
                end
            end
            
            `ICACHE_STATE_COMPARE: begin
                if (!cpu_req) begin
                    next_state = `ICACHE_STATE_IDLE;
                end else if (tag_hit) begin
                    // Hit - back to IDLE
                    next_state = `ICACHE_STATE_IDLE;
                end else begin
                    // Miss - start refill
                    next_state = `ICACHE_STATE_MISS_REQ;
                end
            end
            
            `ICACHE_STATE_MISS_REQ: begin
                // Wait for refill to start
                if (refill_busy) begin
                    next_state = `ICACHE_STATE_REFILL;
                end
            end
            
            `ICACHE_STATE_REFILL: begin
                if (refill_done) begin
                    next_state = `ICACHE_STATE_IDLE;
                end
            end
            
            default: next_state = `ICACHE_STATE_IDLE;
        endcase
    end
    
    // ========================================================================
    // State Machine - Output Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_ready           <= 1'b0;
            cpu_rdata           <= 32'h0;
            refill_addr         <= 32'h0;
            refill_start        <= 1'b0;
            refill_index        <= 6'h0;
            refill_tag          <= 22'h0;
            requested_offset    <= 2'b00;
            requested_data      <= 32'h0;
            requested_data_ready <= 1'b0;
            tag_update_valid    <= 1'b0;
            tag_update_index    <= 6'h0;
            tag_update_tag      <= 22'h0;
            tag_flush_all       <= 1'b0;
            data_write_enable   <= 1'b0;
            data_write_index    <= 6'h0;
            data_write_offset   <= 2'b00;
            data_write_data     <= 32'h0;
            stat_hits           <= 32'h0;
            stat_misses         <= 32'h0;
            
        end else begin
            // Default: clear one-shot signals
            cpu_ready         <= 1'b0;
            refill_start      <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;
            
            // Handle flush
            if (flush) begin
                tag_flush_all <= 1'b1;
            end
            
            case (state)
                `ICACHE_STATE_IDLE: begin
                    requested_data_ready <= 1'b0;
                end
                
                `ICACHE_STATE_COMPARE: begin
                    if (tag_hit) begin
                        // ✅ CACHE HIT
                        cpu_rdata <= data_read_data;
                        cpu_ready <= 1'b1;
                        stat_hits <= stat_hits + 1;
                    end else if (cpu_req) begin
                        // ❌ CACHE MISS - Prepare refill
                        refill_addr      <= {cpu_addr[31:4], 4'b0000};  // Align to line
                        refill_index     <= addr_index;
                        refill_tag       <= addr_tag;
                        requested_offset <= addr_offset;
                        stat_misses      <= stat_misses + 1;
                    end
                end
                
                `ICACHE_STATE_MISS_REQ: begin
                    // Start AXI refill
                    refill_start <= 1'b1;
                end
                
                `ICACHE_STATE_REFILL: begin
                    // Write incoming data to cache
                    if (refill_data_valid) begin
                        data_write_enable <= 1'b1;
                        data_write_index  <= refill_index;
                        data_write_offset <= refill_word;
                        data_write_data   <= refill_data;
                        
                        // Check if this is the word CPU requested
                        if (refill_word == requested_offset && !requested_data_ready) begin
                            requested_data       <= refill_data;
                            requested_data_ready <= 1'b1;
                        end
                    end
                    
                    // Refill complete
                    if (refill_done) begin
                        // Mark line as valid
                        tag_update_valid <= 1'b1;
                        tag_update_index <= refill_index;
                        tag_update_tag   <= refill_tag;
                        
                        // Return data to CPU
                        cpu_rdata <= requested_data;
                        cpu_ready <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule