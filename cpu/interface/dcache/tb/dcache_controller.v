// ============================================================================
// Module: dcache_controller
// ============================================================================
// Description:
//   Main data cache controller with read/write support
//   - Write-through policy (all writes go to memory)
//   - Read miss triggers cache line refill
//   - Write hit: update cache + write-through
//   - Write miss: write-through only (no refill)
//
// Author: ChiThang
// ============================================================================

`include "cpu/interface/dcache/tb/dcache_defines.vh"

module dcache_controller (
    input wire clk,
    input wire rst_n,
    
    // CPU Interface
    input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    input wire [3:0]  cpu_wstrb,
    input wire        cpu_req,
    input wire        cpu_we,           // 1=write, 0=read
    output wire [31:0] cpu_rdata,      
    output wire        cpu_ready,    
    input wire        fence,
    
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
    output reg [3:0]   data_write_strb,
    
    // AXI Refill Interface (for read misses)
    output reg [31:0]  refill_addr,
    output reg         refill_start,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,
    
    // AXI Write-Through Interface (for writes)
    output reg [31:0]  wt_addr,
    output reg [31:0]  wt_data,
    output reg [3:0]   wt_strb,
    output reg         wt_start,
    input wire         wt_busy,
    input wire         wt_done,
    
    // Statistics
    output reg [31:0]  stat_hits,
    output reg [31:0]  stat_misses,
    output reg [31:0]  stat_writes
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
            state <= `DCACHE_STATE_IDLE;
        end else if (fence) begin
            state <= `DCACHE_STATE_IDLE;
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
            `DCACHE_STATE_IDLE: begin
                if (cpu_req) begin
                    next_state = `DCACHE_STATE_LOOKUP;
                end
            end
            
            `DCACHE_STATE_LOOKUP: begin
                if (!cpu_req) begin
                    next_state = `DCACHE_STATE_IDLE;
                end else if (cpu_we) begin
                    // Write operation: always write-through
                    next_state = `DCACHE_STATE_WRITE_THRU;
                end else begin
                    // Read operation
                    if (tag_hit) begin
                        // Read hit - done immediately
                        next_state = `DCACHE_STATE_IDLE;
                    end else begin
                        // Read miss - start refill
                        next_state = `DCACHE_STATE_REFILL;
                    end
                end
            end
            
            `DCACHE_STATE_REFILL: begin
                if (refill_done) begin
                    next_state = `DCACHE_STATE_IDLE;
                end
            end
            
            `DCACHE_STATE_WRITE_THRU: begin
                if (wt_done) begin
                    next_state = `DCACHE_STATE_IDLE;
                end
            end
            
            default: next_state = `DCACHE_STATE_IDLE;
        endcase
    end
    
    // ========================================================================
    // COMBINATIONAL OUTPUT for CPU Interface
    // ========================================================================
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;
    
    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;
        
        case (state)
            `DCACHE_STATE_LOOKUP: begin
                if (cpu_req && !cpu_we && tag_hit) begin
                    // Read hit: immediate response
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = data_read_data;
                end
            end
            
            `DCACHE_STATE_REFILL: begin
                // Read miss: response when refill completes
                if (refill_done) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = requested_data;
                end
            end
            
            `DCACHE_STATE_WRITE_THRU: begin
                // Write: response when write-through completes
                if (wt_done) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = 32'h0;  // Writes don't return data
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
            // Refill control
            refill_addr         <= 32'h0;
            refill_start        <= 1'b0;
            refill_index        <= 6'h0;
            refill_tag          <= 22'h0;
            requested_offset    <= 2'b00;
            requested_data      <= 32'h0;
            requested_data_ready <= 1'b0;
            
            // Write-through control
            wt_addr             <= 32'h0;
            wt_data             <= 32'h0;
            wt_strb             <= 4'h0;
            wt_start            <= 1'b0;
            
            // Tag array control
            tag_update_valid    <= 1'b0;
            tag_update_index    <= 6'h0;
            tag_update_tag      <= 22'h0;
            tag_flush_all       <= 1'b0;
            
            // Data array control
            data_write_enable   <= 1'b0;
            data_write_index    <= 6'h0;
            data_write_offset   <= 2'b00;
            data_write_data     <= 32'h0;
            data_write_strb     <= 4'h0;
            
            // Statistics
            stat_hits           <= 32'h0;
            stat_misses         <= 32'h0;
            stat_writes         <= 32'h0;
            
        end else begin
            // ================================================================
            // Default: clear one-shot signals
            // ================================================================
            refill_start      <= 1'b0;
            wt_start          <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;
            
            // ================================================================
            // Handle fence
            // ================================================================
            if (fence) begin
                tag_flush_all <= 1'b1;
            end
            
            // ================================================================
            // State Machine Output
            // ================================================================
            case (state)
                `DCACHE_STATE_IDLE: begin
                    requested_data_ready <= 1'b0;
                end
                
                `DCACHE_STATE_LOOKUP: begin
                    if (cpu_req && !cpu_we) begin
                        // READ OPERATION
                        if (tag_hit) begin
                            // Read hit
                            stat_hits <= stat_hits + 1;
                        end else begin
                            // Read miss - prepare refill
                            refill_addr      <= {cpu_addr[31:4], 4'b0000};
                            refill_index     <= addr_index;
                            refill_tag       <= addr_tag;
                            requested_offset <= addr_offset;
                            stat_misses      <= stat_misses + 1;
                            refill_start     <= 1'b1;
                        end
                    end else if (cpu_req && cpu_we) begin
                        // WRITE OPERATION
                        stat_writes <= stat_writes + 1;
                        
                        // Prepare write-through
                        wt_addr  <= cpu_addr;
                        wt_data  <= cpu_wdata;
                        wt_strb  <= cpu_wstrb;
                        wt_start <= 1'b1;
                        
                        // If write hit, also update cache
                        if (tag_hit) begin
                            data_write_enable <= 1'b1;
                            data_write_index  <= addr_index;
                            data_write_offset <= addr_offset;
                            data_write_data   <= cpu_wdata;
                            data_write_strb   <= cpu_wstrb;
                        end
                        // If write miss, only write-through (no cache update)
                    end
                end
                
                `DCACHE_STATE_REFILL: begin
                    // Write incoming data to cache
                    if (refill_data_valid) begin
                        data_write_enable <= 1'b1;
                        data_write_index  <= refill_index;
                        data_write_offset <= refill_word;
                        data_write_data   <= refill_data;
                        data_write_strb   <= 4'b1111;  // Full word write
                        
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
                    end
                end
                
                `DCACHE_STATE_WRITE_THRU: begin
                    // Wait for write-through to complete
                    // wt_done is handled in combinational logic
                end
            endcase
        end
    end

endmodule