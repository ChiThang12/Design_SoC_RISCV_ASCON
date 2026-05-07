// ============================================================================
// Module: dcache_controller  —  Write-Back + Write-Allocate
// FIXED VERSION
// ============================================================================
// BUG FIXES:
//
// [FIX-1] evict_start multi-driver race
//   Root cause: flush FSM và sequential output block đều drive evict_start.
//   Output block default evict_start<=0 mỗi cycle → ghi đè pulse từ flush FSM
//   trong FLUSH_TAG_WAIT → evict không bao giờ start từ flush path.
//   Fix: tách thành flush_evict_start (flush FSM) và main_evict_start (main FSM).
//   evict_start = flush_evict_start | main_evict_start (combinational OR).
//
// [FIX-2] tag_dirty_clear multi-driver
//   Root cause: FLUSH_EVICT trong output block và DCACHE_STATE_EVICT trong
//   main FSM output block đều drive tag_dirty_clear → Verilog last-assign wins.
//   Fix: tách thành flush_dirty_clear và main_dirty_clear, OR lại.
//
// [FIX-3] TC15: fence_type=2'b10 (invalidate only) không trigger flush_busy
//   Root cause: FLUSH_IDLE chỉ check fence_flush (bit[0]). Invalidate-only
//   (bit[1]=1, bit[0]=0) không start flush FSM → flush_busy không lên → TB timeout.
//   Fix: FLUSH_IDLE start khi fence_any (|fence_type). Nếu không cần flush
//   (fence_inval only), skip thẳng đến FLUSH_DONE.
//
// [FIX-4] evict_nc flag không clear sau NC write
//   Root cause: evict_nc set khi NC write, nhưng flush evict path cũng dùng
//   evict_start → evict_nc có thể còn set stale từ lần trước.
//   Fix: evict_nc chỉ set khi main FSM NC path, clear ở default.
//
// [ORIGINAL FIXES PRESERVED]
//   [FIX-BUG-IDLE-HIT] idle_tag_hit_valid guard
//   [FIX-FLUSH-BITMAP] dirty_bitmap priority encoder
//   [FIX-FLUSH-TAG-WAIT] 1-cycle tag latency
//   [FIX-TC3] deferred pending write
// ============================================================================

`define FLUSH_IDLE     3'd0
`define FLUSH_SETTLE   3'd1
`define FLUSH_TAG_WAIT 3'd5
`define FLUSH_SCAN     3'd2
`define FLUSH_EVICT    3'd3
`define FLUSH_DONE     3'd4

module dcache_controller (
    input wire clk,
    input wire rst_n,

    input wire [31:0]  cpu_addr,
    input wire [31:0]  cpu_wdata,
    input wire [3:0]   cpu_wstrb,
    input wire         cpu_req,
    input wire         cpu_we,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,
    input wire [1:0]   fence_type,

    output wire [31:0] current_addr,
    output wire [31:0] current_data,
    output wire        current_valid,

    output wire [5:0]  tag_lookup_index,
    output wire [21:0] tag_lookup_tag,
    input wire         tag_hit,
    input wire         tag_dirty_out,
    input wire [21:0]  tag_evict_tag_out,
    output reg         tag_update_valid,
    output reg [5:0]   tag_update_index,
    output reg [21:0]  tag_update_tag,
    output reg         tag_flush_all,
    output reg         tag_invalidate_all,
    output wire        tag_dirty_set,
    output wire        tag_dirty_clear,
    output reg [5:0]   tag_dirty_index,

    output wire [5:0]  data_read_index,
    output wire [1:0]  data_read_offset,
    input wire [31:0]  data_read_data,
    output reg         data_write_enable,
    output reg [5:0]   data_write_index,
    output reg [1:0]   data_write_offset,
    output reg [31:0]  data_write_data,
    output reg [3:0]   data_write_strb,

    output wire [5:0]  data_read_all_index,
    input wire [31:0]  data_read_word_0,
    input wire [31:0]  data_read_word_1,
    input wire [31:0]  data_read_word_2,
    input wire [31:0]  data_read_word_3,

    output reg [31:0]  refill_addr,
    output reg         refill_start,
    output reg         refill_nc,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,

    output reg [31:0]  evict_addr,
    output reg [31:0]  evict_data_0,
    output reg [31:0]  evict_data_1,
    output reg [31:0]  evict_data_2,
    output reg [31:0]  evict_data_3,
    output wire        evict_start,     // [FIX-1] now wire (OR of two sources)
    output reg         evict_nc,
    output reg [3:0]   evict_wstrb_nc,
    input wire         evict_busy,
    input wire         evict_done,

    output reg [31:0]  stat_hits,
    output reg [31:0]  stat_misses,
    output reg [31:0]  stat_writes
);

    localparam [2:0]
        DCACHE_STATE_IDLE         = 3'b000,
        DCACHE_STATE_LOOKUP       = 3'b001,
        DCACHE_STATE_REFILL       = 3'b010,
        DCACHE_STATE_EVICT        = 3'b011,
        DCACHE_STATE_WAIT         = 3'b100,
        DCACHE_STATE_REFILL_DRAIN = 3'b101,
        DCACHE_STATE_NC_READ      = 3'b110,
        DCACHE_STATE_NC_WRITE     = 3'b111;

    wire fence_flush = fence_type[0];
    wire fence_inval = fence_type[1];
    wire fence_any   = |fence_type;

    // =========================================================================
    // [FIX-1] Separate evict_start sources — OR them together
    // =========================================================================
    reg flush_evict_start;  // from flush FSM
    reg main_evict_start;   // from main FSM sequential output
    assign evict_start = flush_evict_start | main_evict_start;

    // [FIX-NC-DOUBLE] 1-cycle guard: NC_WRITE/NC_READ return to IDLE while
    // cpu_req still holds old instruction (CPU pipeline stall release has
    // 1-cycle latency). This flag blocks re-issue for exactly 1 cycle.
    reg nc_just_completed;

    // =========================================================================
    // [FIX-2] Separate tag_dirty_clear / tag_dirty_set sources
    // =========================================================================
    reg flush_dirty_clear;
    reg main_dirty_clear;
    reg main_dirty_set;
    assign tag_dirty_clear = flush_dirty_clear | main_dirty_clear;
    assign tag_dirty_set   = main_dirty_set;

    // =========================================================================
    // [FIX-FLUSH-BITMAP] Shadow dirty bitmap
    // =========================================================================
    reg [63:0] dirty_bitmap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dirty_bitmap <= 64'h0;
        end else begin
            if (tag_flush_all || tag_invalidate_all) begin
                dirty_bitmap <= 64'h0;
            end else begin
                if (main_dirty_set)
                    dirty_bitmap[tag_dirty_index] <= 1'b1;
                if (tag_dirty_clear)
                    dirty_bitmap[tag_dirty_index] <= 1'b0;
            end
        end
    end

    // Priority encoder
    reg [5:0]  flush_next_dirty_index;
    reg        flush_has_dirty;

    integer pe_i;
    always @(*) begin
        flush_next_dirty_index = 6'd0;
        flush_has_dirty        = 1'b0;
        for (pe_i = 63; pe_i >= 0; pe_i = pe_i - 1) begin
            if (dirty_bitmap[pe_i]) begin
                flush_next_dirty_index = pe_i[5:0];
                flush_has_dirty        = 1'b1;
            end
        end
    end

    // =========================================================================
    // Flush FSM
    // =========================================================================
    reg [2:0] flush_state;
    reg [5:0] flush_index;
    reg       flush_need_inval;
    reg       flush_busy;

    reg [31:0] cur_addr;
    reg [31:0] cur_wdata;
    reg [3:0]  cur_wstrb;
    reg        cur_we;

    assign current_addr  = cur_addr;
    assign current_data  = cur_wdata;
    assign current_valid = (state != DCACHE_STATE_IDLE);

    reg [2:0] state, next_state;

    wire addr_is_nc = (cpu_addr[31:29] != 3'b000);

    wire        idle_hit_check = (state == DCACHE_STATE_IDLE)
                                 && cpu_req && !fence_any && !flush_busy;

    wire [31:0] lookup_addr   = idle_hit_check ? cpu_addr : cur_addr;
    wire [21:0] lookup_tag_w  = lookup_addr[31:10];
    wire [5:0]  lookup_index  = lookup_addr[9:4];
    wire [1:0]  lookup_offset = lookup_addr[3:2];

    wire [21:0] cur_tag    = cur_addr[31:10];
    wire [5:0]  cur_index  = cur_addr[9:4];
    wire [1:0]  cur_offset = cur_addr[3:2];

    assign tag_lookup_index = flush_busy ? flush_index : lookup_index;
    assign tag_lookup_tag   = flush_busy ? 22'h0       : lookup_tag_w;

    assign data_read_index     = flush_busy ? flush_index : lookup_index;
    assign data_read_offset    = lookup_offset;
    assign data_read_all_index = flush_busy ? flush_index : cur_index;

    // =========================================================================
    // [FIX-BUG-IDLE-HIT] Guard tag_hit trong IDLE
    // =========================================================================
    reg [5:0]  prev_lookup_index;
    reg [21:0] prev_lookup_tag;
    reg        prev_was_idle_hit_check;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_lookup_index       <= 6'h0;
            prev_lookup_tag         <= 22'h0;
            prev_was_idle_hit_check <= 1'b0;
        end else begin
            prev_lookup_index       <= tag_lookup_index;
            prev_lookup_tag         <= lookup_tag_w;
            prev_was_idle_hit_check <= idle_hit_check;
        end
    end

    wire idle_tag_hit_valid = prev_was_idle_hit_check
                              && (lookup_index == prev_lookup_index)
                              && (lookup_tag_w == prev_lookup_tag)
                              && !flush_busy;

    wire idle_hit = tag_hit && idle_tag_hit_valid;

    // =========================================================================
    // tag_lookup_stable cho LOOKUP state
    // =========================================================================
    reg tag_lookup_stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tag_lookup_stable <= 1'b0;
        else if (state == DCACHE_STATE_IDLE)
            tag_lookup_stable <= 1'b0;
        else if (state == DCACHE_STATE_LOOKUP)
            tag_lookup_stable <= 1'b1;
        else
            tag_lookup_stable <= 1'b0;
    end

    reg [5:0]  refill_index_r;
    reg [21:0] refill_tag_r;
    reg [1:0]  requested_offset;
    reg [31:0] requested_data;
    reg        requested_data_ready;
    reg [5:0]  evict_index_r;
    reg        pending_write;
    reg        do_deferred_write;
    reg [1:0]  deferred_offset;
    reg [31:0] deferred_wdata;
    reg [3:0]  deferred_wstrb;
    reg [5:0]  deferred_index;

    // =========================================================================
    // Main FSM — sequential state
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= DCACHE_STATE_IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // Main FSM — combinational next-state
    // =========================================================================
    always @(*) begin
        next_state = state;
        case (state)

            DCACHE_STATE_IDLE: begin
                if (!flush_busy && cpu_req && !fence_any && !nc_just_completed) begin
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
                    else if (tag_dirty_out)
                        next_state = DCACHE_STATE_EVICT;
                    else
                        next_state = DCACHE_STATE_REFILL;
                end
            end

            DCACHE_STATE_EVICT: begin
                if (evict_done) next_state = DCACHE_STATE_WAIT;
            end

            DCACHE_STATE_WAIT: begin
                next_state = DCACHE_STATE_REFILL;
            end

            DCACHE_STATE_REFILL: begin
                if (!cur_we && refill_data_valid && (refill_word == requested_offset)) begin
                    if (refill_done) next_state = DCACHE_STATE_IDLE;
                    else             next_state = DCACHE_STATE_REFILL_DRAIN;
                end else if (cur_we && refill_done) begin
                    next_state = DCACHE_STATE_IDLE;
                end else if (!cur_we && refill_done && requested_data_ready) begin
                    next_state = DCACHE_STATE_IDLE;
                end
            end

            DCACHE_STATE_REFILL_DRAIN: begin
                if (refill_done) next_state = DCACHE_STATE_IDLE;
            end

            DCACHE_STATE_NC_READ: begin
                if (refill_done) next_state = DCACHE_STATE_IDLE;
            end

            DCACHE_STATE_NC_WRITE: begin
                if (evict_done) next_state = DCACHE_STATE_IDLE;
            end

            default: next_state = DCACHE_STATE_IDLE;
        endcase
    end

    // =========================================================================
    // CPU output — combinational
    // =========================================================================
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;

    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;

        if (!flush_busy) begin
            case (state)
                DCACHE_STATE_IDLE: begin
                    if (cpu_req && idle_hit && !fence_any) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = cpu_we ? 32'h0 : data_read_data;
                    end
                end

                DCACHE_STATE_LOOKUP: begin
                    if (tag_lookup_stable && tag_hit) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = cur_we ? 32'h0 : data_read_data;
                    end
                end

                DCACHE_STATE_REFILL: begin
                    if (!cur_we && refill_data_valid && (refill_word == requested_offset)) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = refill_data;
                    end else if (cur_we && refill_done) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = 32'h0;
                    end else if (!cur_we && refill_done && requested_data_ready) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = requested_data;
                    end
                end

                DCACHE_STATE_REFILL_DRAIN: ;

                DCACHE_STATE_NC_READ: begin
                    if (refill_done) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = refill_data;
                    end
                end

                DCACHE_STATE_NC_WRITE: begin
                    if (evict_done) begin
                        cpu_ready_int = 1'b1;
                        cpu_rdata_int = 32'h0;
                    end
                end

                default: ;
            endcase
        end
    end

    assign cpu_ready = cpu_ready_int;
    assign cpu_rdata = cpu_rdata_int;

    // =========================================================================
    // Flush FSM — sequential
    // [FIX-3] Start on fence_any (not just fence_flush)
    //   If fence_inval only (no flush needed), skip to FLUSH_DONE directly.
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_state        <= `FLUSH_IDLE;
            flush_index        <= 6'h0;
            flush_need_inval   <= 1'b0;
            flush_busy         <= 1'b0;
            flush_evict_start  <= 1'b0;  // [FIX-1]
        end else begin
            flush_evict_start <= 1'b0;  // default: deassert each cycle

            case (flush_state)

                `FLUSH_IDLE: begin
                    // [FIX-3] trigger on any fence (flush or invalidate)
                    if (fence_any) begin
                        flush_need_inval <= fence_inval;
                        flush_busy       <= 1'b1;
                        // If invalidate-only (no dirty writeback needed), skip scan
                        if (!fence_flush)
                            flush_state <= `FLUSH_DONE;
                        else
                            flush_state <= `FLUSH_SCAN;
                    end
                end

                `FLUSH_SCAN: begin
                    if (!flush_has_dirty) begin
                        flush_state <= `FLUSH_DONE;
                    end else begin
                        flush_index <= flush_next_dirty_index;
                        flush_state <= `FLUSH_SETTLE;
                    end
                end

                `FLUSH_SETTLE: begin
                    evict_index_r <= flush_index;
                    // data_array is combinational: latch data NOW
                    evict_data_0 <= data_read_word_0;
                    evict_data_1 <= data_read_word_1;
                    evict_data_2 <= data_read_word_2;
                    evict_data_3 <= data_read_word_3;
                    flush_state  <= `FLUSH_TAG_WAIT;
                end

                // [FIX-FLUSH-TAG-WAIT] tag_array registered output now valid
                // [FIX-1] pulse flush_evict_start here (not main evict_start)
                `FLUSH_TAG_WAIT: begin
                    evict_addr        <= {tag_evict_tag_out, flush_index, 4'b0000};
                    flush_evict_start <= 1'b1;   // [FIX-1] dedicated signal
                    flush_state       <= `FLUSH_EVICT;
                end

                `FLUSH_EVICT: begin
                    // flush_evict_start already cleared by default above
                    if (evict_done) begin
                        dirty_bitmap[evict_index_r] <= 1'b0;
                        flush_state <= `FLUSH_SCAN;
                    end
                end

                `FLUSH_DONE: begin
                    flush_busy  <= 1'b0;
                    flush_state <= `FLUSH_IDLE;
                end

                default: flush_state <= `FLUSH_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Sequential Output Logic — Main FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_addr             <= 32'h0;
            cur_wdata            <= 32'h0;
            cur_wstrb            <= 4'h0;
            cur_we               <= 1'b0;
            refill_addr          <= 32'h0;
            refill_start         <= 1'b0;
            refill_nc            <= 1'b0;
            refill_index_r       <= 6'h0;
            refill_tag_r         <= 22'h0;
            requested_offset     <= 2'b00;
            requested_data       <= 32'h0;
            requested_data_ready <= 1'b0;
            evict_addr           <= 32'h0;
            evict_data_0         <= 32'h0;
            evict_data_1         <= 32'h0;
            evict_data_2         <= 32'h0;
            evict_data_3         <= 32'h0;
            main_evict_start     <= 1'b0;  // [FIX-1]
            nc_just_completed    <= 1'b0;  // [FIX-NC-DOUBLE]
            evict_index_r        <= 6'h0;
            evict_nc             <= 1'b0;
            evict_wstrb_nc       <= 4'h0;
            pending_write        <= 1'b0;
            do_deferred_write    <= 1'b0;
            deferred_offset      <= 2'b00;
            deferred_wdata       <= 32'h0;
            deferred_wstrb       <= 4'h0;
            deferred_index       <= 6'h0;
            tag_update_valid     <= 1'b0;
            tag_update_index     <= 6'h0;
            tag_update_tag       <= 22'h0;
            tag_flush_all        <= 1'b0;
            tag_invalidate_all   <= 1'b0;
            main_dirty_set       <= 1'b0;   // [FIX-2]
            main_dirty_clear     <= 1'b0;   // [FIX-2]
            flush_dirty_clear    <= 1'b0;   // [FIX-2]
            tag_dirty_index      <= 6'h0;
            data_write_enable    <= 1'b0;
            data_write_index     <= 6'h0;
            data_write_offset    <= 2'b00;
            data_write_data      <= 32'h0;
            data_write_strb      <= 4'h0;
            stat_hits            <= 32'h0;
            stat_misses          <= 32'h0;
            stat_writes          <= 32'h0;
        end else begin
            // Pulse defaults
            refill_start       <= 1'b0;
            refill_nc          <= 1'b0;
            main_evict_start   <= 1'b0;   // [FIX-1]
            evict_nc           <= 1'b0;
            nc_just_completed  <= 1'b0;   // [FIX-NC-DOUBLE]
            tag_update_valid   <= 1'b0;
            tag_flush_all      <= 1'b0;
            tag_invalidate_all <= 1'b0;
            main_dirty_set     <= 1'b0;   // [FIX-2]
            main_dirty_clear   <= 1'b0;   // [FIX-2]
            flush_dirty_clear  <= 1'b0;   // [FIX-2]
            data_write_enable  <= 1'b0;
            do_deferred_write  <= 1'b0;

            // ── Flush FSM outputs ─────────────────────────────────────────────
            case (flush_state)

                `FLUSH_EVICT: begin
                    // [FIX-2] Use flush_dirty_clear instead of tag_dirty_clear
                    if (evict_done) begin
                        flush_dirty_clear <= 1'b1;
                        tag_dirty_index   <= evict_index_r;
                    end
                end

                `FLUSH_DONE: begin
                    tag_flush_all <= flush_need_inval ? 1'b0 : fence_flush;
                    // [FIX-3] Always assert invalidate_all if needed
                    if (flush_need_inval)
                        tag_invalidate_all <= 1'b1;
                    else if (fence_flush)
                        tag_flush_all <= 1'b1;
                end

                default: ;
            endcase

            // ── Main FSM outputs ──────────────────────────────────────────────
            if (!flush_busy) begin
                case (state)

                    DCACHE_STATE_IDLE: begin
                        requested_data_ready <= 1'b0;
                        pending_write        <= 1'b0;

                        // [FIX-TC3] deferred pending write
                        if (do_deferred_write) begin
                            data_write_enable <= 1'b1;
                            data_write_index  <= deferred_index;
                            data_write_offset <= deferred_offset;
                            data_write_data   <= deferred_wdata;
                            data_write_strb   <= deferred_wstrb;
                            do_deferred_write <= 1'b0;
                        end

                        if (cpu_req && !fence_any && !nc_just_completed) begin  // [FIX-NC-DOUBLE]
                            cur_addr  <= cpu_addr;
                            cur_wdata <= cpu_wdata;
                            cur_wstrb <= cpu_wstrb;
                            cur_we    <= cpu_we;

                            if (addr_is_nc) begin
                                if (cpu_we) begin
                                    evict_addr       <= cpu_addr;
                                    evict_data_0     <= cpu_wdata;
                                    evict_data_1     <= 32'h0;
                                    evict_data_2     <= 32'h0;
                                    evict_data_3     <= 32'h0;
                                    evict_nc         <= 1'b1;
                                    evict_wstrb_nc   <= cpu_wstrb;
                                    main_evict_start <= 1'b1;  // [FIX-1]
                                    stat_writes      <= stat_writes + 1;
                                end else begin
                                    refill_addr  <= cpu_addr;
                                    refill_nc    <= 1'b1;
                                    refill_start <= 1'b1;
                                end
                            end else if (idle_hit) begin
                                if (cpu_we) begin
                                    stat_writes       <= stat_writes + 1;
                                    stat_hits         <= stat_hits + 1;
                                    data_write_enable <= 1'b1;
                                    data_write_index  <= lookup_index;
                                    data_write_offset <= lookup_offset;
                                    data_write_data   <= cpu_wdata;
                                    data_write_strb   <= cpu_wstrb;
                                    main_dirty_set    <= 1'b1;  // [FIX-2]
                                    tag_dirty_index   <= lookup_index;
                                end else begin
                                    stat_hits <= stat_hits + 1;
                                end
                            end
                        end
                    end

                    DCACHE_STATE_LOOKUP: begin
                        if (tag_lookup_stable) begin
                            if (tag_hit) begin
                                if (cur_we) begin
                                    stat_writes       <= stat_writes + 1;
                                    stat_hits         <= stat_hits + 1;
                                    data_write_enable <= 1'b1;
                                    data_write_index  <= cur_index;
                                    data_write_offset <= cur_offset;
                                    data_write_data   <= cur_wdata;
                                    data_write_strb   <= cur_wstrb;
                                    main_dirty_set    <= 1'b1;  // [FIX-2]
                                    tag_dirty_index   <= cur_index;
                                end else begin
                                    stat_hits <= stat_hits + 1;
                                end
                            end else begin
                                stat_misses <= stat_misses + 1;
                                if (cur_we) stat_writes <= stat_writes + 1;

                                refill_index_r   <= cur_index;
                                refill_tag_r     <= cur_tag;
                                requested_offset <= cur_offset;
                                pending_write    <= cur_we;

                                if (tag_dirty_out) begin
                                    evict_addr       <= {tag_evict_tag_out, cur_index, 4'b0000};
                                    evict_data_0     <= data_read_word_0;
                                    evict_data_1     <= data_read_word_1;
                                    evict_data_2     <= data_read_word_2;
                                    evict_data_3     <= data_read_word_3;
                                    evict_index_r    <= cur_index;
                                    main_evict_start <= 1'b1;  // [FIX-1]
                                end else begin
                                    refill_addr  <= {cur_addr[31:4], 4'b0000};
                                    refill_start <= 1'b1;
                                end
                            end
                        end
                    end

                    DCACHE_STATE_EVICT: begin
                        if (evict_done) begin
                            main_dirty_clear <= 1'b1;  // [FIX-2]
                            tag_dirty_index  <= evict_index_r;
                        end
                    end

                    DCACHE_STATE_WAIT: begin
                        refill_addr  <= {cur_addr[31:4], 4'b0000};
                        refill_start <= 1'b1;
                    end

                    DCACHE_STATE_REFILL: begin
                        if (refill_data_valid) begin
                            data_write_enable <= 1'b1;
                            data_write_index  <= refill_index_r;
                            data_write_offset <= refill_word;
                            data_write_data   <= refill_data;
                            data_write_strb   <= 4'b1111;

                            if (refill_word == requested_offset && !requested_data_ready) begin
                                requested_data       <= refill_data;
                                requested_data_ready <= 1'b1;
                            end
                        end

                        if (refill_done) begin
                            tag_update_valid <= 1'b1;
                            tag_update_index <= refill_index_r;
                            tag_update_tag   <= refill_tag_r;

                            if (pending_write) begin
                                if (refill_data_valid) begin
                                    do_deferred_write <= 1'b1;
                                    deferred_index    <= refill_index_r;
                                    deferred_offset   <= requested_offset;
                                    deferred_wdata    <= cur_wdata;
                                    deferred_wstrb    <= cur_wstrb;
                                end else begin
                                    data_write_enable <= 1'b1;
                                    data_write_index  <= refill_index_r;
                                    data_write_offset <= requested_offset;
                                    data_write_data   <= cur_wdata;
                                    data_write_strb   <= cur_wstrb;
                                end
                                main_dirty_set  <= 1'b1;  // [FIX-2]
                                tag_dirty_index <= refill_index_r;
                                pending_write   <= 1'b0;
                            end
                        end
                    end

                    DCACHE_STATE_REFILL_DRAIN: begin
                        if (refill_data_valid) begin
                            data_write_enable <= 1'b1;
                            data_write_index  <= refill_index_r;
                            data_write_offset <= refill_word;
                            data_write_data   <= refill_data;
                            data_write_strb   <= 4'b1111;
                        end

                        if (refill_done) begin
                            tag_update_valid <= 1'b1;
                            tag_update_index <= refill_index_r;
                            tag_update_tag   <= refill_tag_r;
                        end
                    end

                    DCACHE_STATE_NC_READ: begin
                        // [FIX-NC-DOUBLE] signal completion so IDLE skips 1 cycle
                        if (refill_done) nc_just_completed <= 1'b1;
                    end
                    DCACHE_STATE_NC_WRITE: begin
                        // [FIX-NC-DOUBLE] signal completion so IDLE skips 1 cycle
                        if (evict_done) nc_just_completed <= 1'b1;
                    end

                    default: ;
                endcase
            end
        end
    end

endmodule
