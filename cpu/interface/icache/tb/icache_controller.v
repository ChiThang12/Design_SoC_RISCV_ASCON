// ============================================================================
// Module: icache_controller (Non-Blocking 2-Line Architecture)
// ============================================================================
// ARCHITECTURE OVERVIEW:
//
//   NON-BLOCKING 2-LINE ICACHE:
//   ────────────────────────────────────────────────────────────────────────
//   Line 0: [Data][Tag][Valid]  ─┐
//   Line 1: [Data][Tag][Valid]  ─┴─→ Parallel Tag Compare
//
//   DUAL-LINE OPERATION:
//   - Active Line: Serves CPU (no stall)
//   - Fill Line: Refills in parallel from memory
//   - CPU only stalls when accessing line that is NOT valid yet
//
//   KEY FEATURES:
//   1. Parallel tag comparison on both lines
//   2. Hit on either line → immediate data return (no stall)
//   3. Refill in background while CPU continues on active line
//   4. Automatic prefetch when nearing end of current line
//   5. Smart line replacement (use the non-active line for refill)
//
//   EXPECTED BEHAVIOR:
//   - Sequential execution: ~0 stalls (if memory fast enough)
//   - CPI_effective ≈ 1.0 for sequential code
//   - Only stall on: branch to uncached line OR memory too slow
//
// ============================================================================

`include "cpu/interface/icache/icache_defines.vh"

module icache_controller (
    input wire clk,
    input wire rst_n,
    
    // CPU Interface
    input wire [31:0]  cpu_addr,
    input wire         cpu_req,
    output reg [31:0]  cpu_rdata,
    output reg         cpu_ready,
    input wire         flush,
    
    // Tag Array Interface (kept for compatibility, but internal arrays used)
    output wire [5:0]  tag_lookup_index,
    output wire [21:0] tag_lookup_tag,
    input wire         tag_hit,             // Not used (internal comparison)
    output reg         tag_update_valid,
    output reg [5:0]   tag_update_index,
    output reg [21:0]  tag_update_tag,
    output reg         tag_flush_all,
    
    // Data Array Interface (kept for compatibility, but internal arrays used)
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
    // 2-Line Cache Storage (Internal - Direct Mapped Per Line)
    // ========================================================================
    // Each line stores: 64 cache lines × 4 words × 32 bits
    // But we only have 2 physical lines that can hold any of the 64 addresses
    
    reg [127:0] line_data [0:1];     // 2 lines, each 128 bits (4 words)
    reg [21:0]  line_tag  [0:1];     // Tag for each line
    reg [5:0]   line_index [0:1];    // Index stored in each line
    reg         line_valid [0:1];    // Valid bit for each line
    
    // ========================================================================
    // Active/Fill Line Management
    // ========================================================================
    reg active_line_id;              // Which line (0 or 1) is currently serving CPU
    reg fill_line_id;                // Which line is being refilled
    reg fill_busy;                   // Refill in progress
    
    // ========================================================================
    // Address Decomposition
    // ========================================================================
    wire [21:0] cpu_tag;
    wire [5:0]  cpu_index;
    wire [1:0]  cpu_offset;
    wire [3:0]  cpu_byte_offset;
    
    assign cpu_tag         = cpu_addr[31:10];
    assign cpu_index       = cpu_addr[9:4];
    assign cpu_offset      = cpu_addr[3:2];
    assign cpu_byte_offset = cpu_addr[3:0];
    
    // ========================================================================
    // Parallel Tag Comparison (Both Lines)
    // ========================================================================
    wire hit_line0, hit_line1;
    wire cache_hit;
    wire hit_line_id;
    
    assign hit_line0  = line_valid[0] && 
                        (line_tag[0] == cpu_tag) && 
                        (line_index[0] == cpu_index);
    assign hit_line1  = line_valid[1] && 
                        (line_tag[1] == cpu_tag) && 
                        (line_index[1] == cpu_index);
    assign cache_hit  = hit_line0 | hit_line1;
    assign hit_line_id = hit_line1;  // 0 if hit line0, 1 if hit line1
    
    // ========================================================================
    // Data Mux (Select from Hit Line)
    // ========================================================================
    wire [127:0] hit_line_data;
    wire [31:0]  hit_word;
    
    assign hit_line_data = hit_line0 ? line_data[0] : line_data[1];
    
    // Extract word based on offset
    assign hit_word = (cpu_offset == 2'b00) ? hit_line_data[31:0]   :
                      (cpu_offset == 2'b01) ? hit_line_data[63:32]  :
                      (cpu_offset == 2'b10) ? hit_line_data[95:64]  :
                                               hit_line_data[127:96];
    
    // ========================================================================
    // Next-Line Prefetch Logic
    // ========================================================================
    wire [31:0] next_line_addr;
    wire [21:0] next_line_tag;
    wire [5:0]  next_line_index;
    wire        should_prefetch;
    wire        next_line_hit;
    
    // Calculate next line address (current line + 16 bytes)
    assign next_line_addr   = {cpu_addr[31:4], 4'b0000} + 32'd16;
    assign next_line_tag    = next_line_addr[31:10];
    assign next_line_index  = next_line_addr[9:4];
    
    // Check if next line already in cache
    assign next_line_hit = (line_valid[0] && line_tag[0] == next_line_tag && line_index[0] == next_line_index) ||
                           (line_valid[1] && line_tag[1] == next_line_tag && line_index[1] == next_line_index);
    
    // Prefetch trigger: near middle/end of line, next line not cached, not already filling
    // CRITICAL: Trigger at offset >= 1 (word 1, 2, or 3) to give enough time!
    assign should_prefetch = cache_hit &&                    // Current access is hit
                             cpu_req &&                      // CPU is requesting
                            //  (cpu_offset == 2'b00) &&        // Trigger early: word 1,2,3 (not just 2,3)
                             !next_line_hit &&               // Next line not in cache
                             !fill_busy &&                   // Not already filling
                             !refill_busy;                   // AXI not busy
    
    // ========================================================================
    // State Machine
    // ========================================================================
    localparam [2:0]
        S_IDLE     = 3'd0,
        S_SERVE    = 3'd1,  // Serving CPU from cache
        S_MISS_REQ = 3'd2,  // Initiate refill for miss
        S_WAIT     = 3'd3;  // Wait for refill when CPU needs uncached line
    
    reg [2:0] state, next_state;
    
    // Refill tracking
    reg [21:0] fill_tag;
    reg [5:0]  fill_index;
    reg [1:0]  fill_word_count;
    
    // ========================================================================
    // State Transition
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else if (flush)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    // ========================================================================
    // Next State Logic
    // ========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (cpu_req)
                    next_state = S_SERVE;
            end
            
            S_SERVE: begin
                if (!cpu_req) begin
                    next_state = S_IDLE;
                end else if (cache_hit) begin
                    // Hit: stay in SERVE
                    // Prefetch will start in parallel if needed
                    next_state = S_SERVE;
                end else begin
                    // Miss: need to refill
                    next_state = S_MISS_REQ;
                end
            end
            
            S_MISS_REQ: begin
                // Start refill, then wait
                next_state = S_WAIT;
            end
            
            S_WAIT: begin
                // Check if we can serve while waiting
                if (cache_hit) begin
                    // Hit on other line! Return to serve
                    next_state = S_SERVE;
                end else if (refill_done) begin
                    // Refill complete
                    next_state = S_SERVE;
                end
                // Otherwise stay in WAIT
            end
            
            default: next_state = S_IDLE;
        endcase
    end
    
    // ========================================================================
    // Output Logic
    // ========================================================================
    always @(*) begin
        cpu_ready = 1'b0;
        cpu_rdata = 32'h0;
        
        case (state)
            S_SERVE: begin
                if (cpu_req && cache_hit) begin
                    cpu_ready = 1'b1;
                    cpu_rdata = hit_word;
                end
            end
            
            S_WAIT: begin
                // Can still serve if hit on other line
                if (cpu_req && cache_hit) begin
                    cpu_ready = 1'b1;
                    cpu_rdata = hit_word;
                end
            end
            
            default: begin
                cpu_ready = 1'b0;
                cpu_rdata = 32'h0;
            end
        endcase
    end
    
    // ========================================================================
    // Sequential Logic - Refill & Prefetch
    // ========================================================================
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all lines
            for (i = 0; i < 2; i = i + 1) begin
                line_data[i]  <= 128'h0;
                line_tag[i]   <= 22'h0;
                line_index[i] <= 6'h0;
                line_valid[i] <= 1'b0;
            end
            
            active_line_id    <= 1'b0;
            fill_line_id      <= 1'b1;
            fill_busy         <= 1'b0;
            fill_tag          <= 22'h0;
            fill_index        <= 6'h0;
            fill_word_count   <= 2'b00;
            
            refill_addr       <= 32'h0;
            refill_start      <= 1'b0;
            
            tag_update_valid  <= 1'b0;
            tag_update_index  <= 6'h0;
            tag_update_tag    <= 22'h0;
            tag_flush_all     <= 1'b0;
            
            data_write_enable <= 1'b0;
            data_write_index  <= 6'h0;
            data_write_offset <= 2'b00;
            data_write_data   <= 32'h0;
            
            stat_hits         <= 32'h0;
            stat_misses       <= 32'h0;
            
        end else begin
            // Clear one-shot signals
            refill_start      <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;
            
            if (flush) begin
                // Invalidate all lines
                for (i = 0; i < 2; i = i + 1) begin
                    line_valid[i] <= 1'b0;
                end
                fill_busy <= 1'b0;
                tag_flush_all <= 1'b1;
                
            end else begin
                
                // ────────────────────────────────────────────────────────────
                // Handle Refill Data
                // ────────────────────────────────────────────────────────────
                if (refill_data_valid && fill_busy) begin
                    // Store word in fill line
                    case (refill_word)
                        2'b00: line_data[fill_line_id][31:0]    <= refill_data;
                        2'b01: line_data[fill_line_id][63:32]   <= refill_data;
                        2'b10: line_data[fill_line_id][95:64]   <= refill_data;
                        2'b11: line_data[fill_line_id][127:96]  <= refill_data;
                    endcase
                    
                    // Update external data array (for compatibility)
                    data_write_enable <= 1'b1;
                    data_write_index  <= fill_index;
                    data_write_offset <= refill_word;
                    data_write_data   <= refill_data;
                end
                
                if (refill_done && fill_busy) begin
                    // Mark line as valid
                    line_valid[fill_line_id] <= 1'b1;
                    line_tag[fill_line_id]   <= fill_tag;
                    line_index[fill_line_id] <= fill_index;
                    fill_busy <= 1'b0;  // Clear immediately to allow next prefetch
                    
                    // Update external tag array (for compatibility)
                    tag_update_valid <= 1'b1;
                    tag_update_index <= fill_index;
                    tag_update_tag   <= fill_tag;
                    
                    // Switch active line if CPU is waiting for this line
                    if (state == S_WAIT && !cache_hit) begin
                        active_line_id <= fill_line_id;
                        fill_line_id   <= ~fill_line_id;
                    end
                    // If CPU is already running on other line, just mark this ready
                    // Next prefetch can trigger on next cycle
                end
                
                // ────────────────────────────────────────────────────────────
                // State-Based Actions
                // ────────────────────────────────────────────────────────────
                case (state)
                    S_SERVE: begin
                        if (cpu_req) begin
                            if (cache_hit) begin
                                stat_hits <= stat_hits + 1;
                                
                                // Update active line
                                active_line_id <= hit_line_id;
                                
                                // Trigger prefetch if conditions met
                                if (should_prefetch) begin
                                    fill_line_id <= ~active_line_id;
                                    fill_tag     <= next_line_tag;
                                    fill_index   <= next_line_index;
                                    refill_addr  <= next_line_addr;
                                    refill_start <= 1'b1;
                                    fill_busy    <= 1'b1;
                                end
                                
                            end else begin
                                // Miss
                                stat_misses <= stat_misses + 1;
                            end
                        end
                    end
                    
                    S_MISS_REQ: begin
                        // Start refill for missed line
                        fill_line_id <= ~active_line_id;  // Use the other line
                        fill_tag     <= cpu_tag;
                        fill_index   <= cpu_index;
                        refill_addr  <= {cpu_addr[31:4], 4'b0000};
                        refill_start <= 1'b1;
                        fill_busy    <= 1'b1;
                    end
                    
                    S_WAIT: begin
                        // Just wait for refill or check for hits
                        // Refill handling done above
                    end
                    
                    default: ;
                endcase
            end
        end
    end
    
    // ========================================================================
    // External Interface Compatibility
    // ========================================================================
    assign tag_lookup_index = cpu_index;
    assign tag_lookup_tag   = cpu_tag;
    assign data_read_index  = cpu_index;
    assign data_read_offset = cpu_offset;

endmodule