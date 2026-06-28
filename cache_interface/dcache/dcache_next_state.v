module dcache_next_state (
    // ---------------------------------------------------------------------
    // Current state and global blockers
    // ---------------------------------------------------------------------
    input  wire [3:0] state,
    input  wire       flush_busy,
    input  wire       snoop_busy,
    input  wire       tag_line_invalidate,

    // ---------------------------------------------------------------------
    // CPU request qualifiers
    // ---------------------------------------------------------------------
    input  wire       cpu_req,
    input  wire       fence_any,
    input  wire       nc_just_completed,
    input  wire       do_deferred_write,
    input  wire       addr_is_nc,
    input  wire       cpu_we,
    input  wire       idle_hit,

    // ---------------------------------------------------------------------
    // Lookup / transaction results
    // ---------------------------------------------------------------------
    input  wire       tag_lookup_stable,
    input  wire       tag_hit,
    input  wire       tag_dirty_out,
    input  wire       miss_snoop_enable,
    input  wire       miss_snoop_accepted,
    input  wire       miss_snoop_resp_valid,
    input  wire       local_miss_dirty,
    input  wire       evict_done,
    input  wire       cur_we,
    input  wire       refill_data_valid,
    input  wire [1:0] refill_word,
    input  wire [1:0] requested_offset,
    input  wire       refill_done,
    input  wire       requested_data_ready,

    // ---------------------------------------------------------------------
    // Next-state result
    // ---------------------------------------------------------------------
    output reg  [3:0] next_state
);

    localparam [3:0]
        DCACHE_STATE_IDLE         = 4'b0000,
        DCACHE_STATE_LOOKUP       = 4'b0001,
        DCACHE_STATE_REFILL       = 4'b0010,
        DCACHE_STATE_EVICT        = 4'b0011,
        DCACHE_STATE_WAIT         = 4'b0100,
        DCACHE_STATE_REFILL_DRAIN = 4'b0101,
        DCACHE_STATE_NC_READ      = 4'b0110,
        DCACHE_STATE_NC_WRITE     = 4'b0111,
        DCACHE_STATE_PEER_SNOOP   = 4'b1000;

    always @(*) begin
        next_state = state;
        case (state)
            DCACHE_STATE_IDLE: begin
                if (!flush_busy && !snoop_busy && !tag_line_invalidate &&
                    cpu_req && !fence_any && !nc_just_completed && !do_deferred_write) begin
                    if (addr_is_nc)
                        next_state = cpu_we ? DCACHE_STATE_NC_WRITE
                                            : DCACHE_STATE_NC_READ;
                    else if (idle_hit)
                        next_state = DCACHE_STATE_IDLE;
                    else
                        next_state = DCACHE_STATE_LOOKUP;
                end
            end

            DCACHE_STATE_LOOKUP: begin
                if (tag_lookup_stable) begin
                    if (tag_hit)
                        next_state = DCACHE_STATE_IDLE;
                    else if (miss_snoop_enable && !cur_we)
                        next_state = DCACHE_STATE_PEER_SNOOP;
                    else if (tag_dirty_out)
                        next_state = DCACHE_STATE_EVICT;
                    else
                        next_state = DCACHE_STATE_REFILL;
                end
            end

            DCACHE_STATE_PEER_SNOOP: begin
                if (miss_snoop_resp_valid) begin
                    if (local_miss_dirty)
                        next_state = DCACHE_STATE_EVICT;
                    else
                        next_state = DCACHE_STATE_REFILL;
                end
            end

            DCACHE_STATE_EVICT: begin
                if (evict_done)
                    next_state = DCACHE_STATE_WAIT;
            end

            DCACHE_STATE_WAIT: begin
                next_state = DCACHE_STATE_REFILL;
            end

            DCACHE_STATE_REFILL: begin
                if (!cur_we && refill_data_valid && (refill_word == requested_offset)) begin
                    if (refill_done)
                        next_state = DCACHE_STATE_IDLE;
                    else
                        next_state = DCACHE_STATE_REFILL_DRAIN;
                end else if (cur_we && refill_done) begin
                    next_state = DCACHE_STATE_IDLE;
                end else if (!cur_we && refill_done && requested_data_ready) begin
                    next_state = DCACHE_STATE_IDLE;
                end
            end

            DCACHE_STATE_REFILL_DRAIN: begin
                if (refill_done)
                    next_state = DCACHE_STATE_IDLE;
            end

            DCACHE_STATE_NC_READ: begin
                if (refill_done)
                    next_state = DCACHE_STATE_IDLE;
            end

            DCACHE_STATE_NC_WRITE: begin
                if (evict_done)
                    next_state = DCACHE_STATE_IDLE;
            end

            default: next_state = DCACHE_STATE_IDLE;
        endcase
    end
endmodule
