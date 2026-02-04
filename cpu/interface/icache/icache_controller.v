// ============================================================================
// Module: icache_controller (COMPLETELY FIXED - V2)
// ============================================================================
// Description:
//   Main cache controller with state machine
//   CRITICAL FIX: cpu_ready và cpu_rdata phải là COMBINATIONAL cho cache HIT
//   để có response ngay trong cùng clock cycle
//
// Author: ChiThang (Fixed by Claude - V2)
// ============================================================================

`include "icache_defines.vh"

module icache_controller (
    input wire clk,
    input wire rst_n,
    
    // CPU Interface
    input wire [31:0] cpu_addr,
    input wire        cpu_req,
    output wire [31:0] cpu_rdata,      
    output wire        cpu_ready,    
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
    reg [1:0]  requested_offset;
    reg [31:0] requested_data;
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
                    // Hit - go back to IDLE
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
    // ✅ CRITICAL FIX: COMBINATIONAL OUTPUT for CPU Interface
    // ========================================================================
    // Cache HIT must respond in the SAME cycle (combinational logic)
    // Cache MISS completion can use registered data
    
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;
    
    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;
        
        case (state)
            `ICACHE_STATE_COMPARE: begin
                // ✅ CACHE HIT: Immediate combinational response
                if (tag_hit && cpu_req) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = data_read_data;
                end
            end
            
            `ICACHE_STATE_REFILL: begin
                // CACHE MISS: Response when refill completes
                if (refill_done) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = requested_data;
                end
            end
            
            default: begin
                cpu_ready_int = 1'b0;
                cpu_rdata_int = 32'h0;
            end
        endcase
    end
    
    // Direct assignment to output (COMBINATIONAL)
    assign cpu_ready = cpu_ready_int;
    assign cpu_rdata = cpu_rdata_int;
    
    // ========================================================================
    // State Machine - Sequential Output Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
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
            // ================================================================
            // Default: clear one-shot signals
            // ================================================================
            refill_start      <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;
            
            // ================================================================
            // Handle flush
            // ================================================================
            if (flush) begin
                tag_flush_all <= 1'b1;
            end
            
            // ================================================================
            // State Machine Output
            // ================================================================
            case (state)
                `ICACHE_STATE_IDLE: begin
                    requested_data_ready <= 1'b0;
                end
                
                `ICACHE_STATE_COMPARE: begin
                    if (tag_hit && cpu_req) begin
                        // ✅ CACHE HIT - Update statistics only
                        stat_hits <= stat_hits + 1;
                        // cpu_rdata and cpu_ready are handled by combinational logic above
                    end
                    
                    if (!tag_hit && cpu_req) begin
                        // ❌ CACHE MISS - Prepare refill
                        refill_addr      <= {cpu_addr[31:4], 4'b0000};
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
                        
                        // cpu_rdata and cpu_ready are handled by combinational logic above
                    end
                end
            endcase
        end
    end

endmodule