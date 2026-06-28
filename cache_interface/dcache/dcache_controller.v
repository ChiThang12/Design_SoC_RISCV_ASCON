// ============================================================================
// Module: dcache_controller  —  Write-Back + Write-Allocate
//
// Refactor note:
//   This controller now delegates distinct concerns into submodules:
//   - dcache_next_state   : combinational next-state decode
//   - dcache_cpu_response : combinational CPU ready/rdata response
//   - dcache_flush_ctrl   : dirty-line scan + fence flush/invalidate flow
//   - dcache_snoop_ctrl   : sideband snoop request/response flow
//
// The top-level controller keeps the main sequential datapath orchestration so
// behavior stays aligned with the existing tests while the file becomes easier
// to reason about and extend.
// ============================================================================

`include "cache_interface/dcache/dcache_next_state.v"
`include "cache_interface/dcache/dcache_cpu_response.v"
`include "cache_interface/dcache/dcache_flush_ctrl.v"
`include "cache_interface/dcache/dcache_snoop_ctrl.v"

module dcache_controller (
    // ---------------------------------------------------------------------
    // Clock / Reset
    // ---------------------------------------------------------------------
    input wire clk,
    input wire rst_n,

    // ---------------------------------------------------------------------
    // CPU request / response interface
    // ---------------------------------------------------------------------
    input wire [31:0]  cpu_addr,
    input wire [31:0]  cpu_wdata,
    input wire [3:0]   cpu_wstrb,
    input wire         cpu_req,
    input wire         cpu_we,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,
    input wire [1:0]   fence_type,
    input wire         miss_snoop_enable,

    output wire [31:0] current_addr,
    output wire [31:0] current_data,
    output wire        current_valid,

    // ---------------------------------------------------------------------
    // Tag-array interface
    // ---------------------------------------------------------------------
    output wire [5:0]  tag_lookup_index,
    output wire [21:0] tag_lookup_tag,
    input wire         tag_hit,
    input wire         tag_dirty_out,
    input wire [21:0]  tag_evict_tag_out,
    input wire [1:0]   tag_state_out,
    output reg         tag_update_valid,
    output reg [5:0]   tag_update_index,
    output reg [21:0]  tag_update_tag,
    output wire        tag_flush_all,
    output wire        tag_invalidate_all,
    output wire        tag_dirty_set,
    output wire        tag_dirty_clear,
    output wire [5:0]  tag_dirty_index,
    output wire        tag_line_shared,
    output wire [5:0]  tag_line_shared_index,
    output wire        tag_line_invalidate,
    output wire [5:0]  tag_line_invalidate_index,

    // ---------------------------------------------------------------------
    // Data-array interface
    // ---------------------------------------------------------------------
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

    // ---------------------------------------------------------------------
    // AXI refill / eviction orchestration
    // ---------------------------------------------------------------------
    output reg [31:0]  refill_addr,
    output reg         refill_start,
    output reg         refill_nc,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,

    output wire [31:0] evict_addr,
    output wire [31:0] evict_data_0,
    output wire [31:0] evict_data_1,
    output wire [31:0] evict_data_2,
    output wire [31:0] evict_data_3,
    output wire        evict_start,
    output wire        evict_nc,
    output wire [3:0]  evict_wstrb_nc,
    input wire         evict_busy,
    input wire         evict_done,

    // ---------------------------------------------------------------------
    // Sideband snoop interface
    // ---------------------------------------------------------------------
    input wire [31:0]  dc_snoop_addr,
    input wire [1:0]   dc_snoop_cmd,
    input wire         dc_snoop_req_valid,
    output wire        dc_snoop_req_ready,
    output wire        dc_snoop_resp_valid,
    output wire        dc_snoop_resp_hit,
    output wire [127:0] dc_snoop_resp_data,

    output reg [31:0]  miss_snoop_addr,
    output reg [1:0]   miss_snoop_cmd,
    output reg         miss_snoop_req_valid,
    input wire         miss_snoop_req_ready,
    input wire         miss_snoop_resp_valid,
    input wire         miss_snoop_resp_hit,
    input wire [127:0] miss_snoop_resp_data,

    // ---------------------------------------------------------------------
    // Statistics
    // ---------------------------------------------------------------------
    output reg [31:0]  stat_hits,
    output reg [31:0]  stat_misses,
    output reg [31:0]  stat_writes
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

    wire fence_flush = fence_type[0];
    wire fence_inval = fence_type[1];
    wire fence_any   = |fence_type;
    wire addr_is_nc  = (cpu_addr[31:29] != 3'b000);

    reg [31:0] cur_addr;
    reg [31:0] cur_wdata;
    reg [3:0]  cur_wstrb;
    reg        cur_we;

    reg [3:0] state;
    wire [3:0] next_state;

    reg        nc_just_completed;
    reg        tag_lookup_stable;
    reg [5:0]  prev_lookup_index;
    reg [21:0] prev_lookup_tag;
    reg        prev_was_idle_hit_check;

    reg [5:0]  refill_index_r;
    reg [21:0] refill_tag_r;
    reg [1:0]  requested_offset;
    reg [31:0] requested_data;
    reg        requested_data_ready;
    reg [5:0]  main_evict_index_r;
    reg        local_miss_dirty_r;
    reg        pending_write;
    reg        do_deferred_write;
    reg [1:0]  deferred_offset;
    reg [31:0] deferred_wdata;
    reg [3:0]  deferred_wstrb;
    reg [5:0]  deferred_index;
    reg        miss_snoop_accepted_r;

    reg        main_evict_start;
    reg [31:0] main_evict_addr_r;
    reg [31:0] main_evict_data_0_r;
    reg [31:0] main_evict_data_1_r;
    reg [31:0] main_evict_data_2_r;
    reg [31:0] main_evict_data_3_r;
    reg        main_evict_nc_r;
    reg [3:0]  main_evict_wstrb_nc_r;

    reg        main_dirty_set;
    reg        main_dirty_clear;
    reg [5:0]  main_dirty_index_r;

    wire       snoop_busy;
    wire       snoop_lookup_active;
    wire [5:0] snoop_index;
    wire [21:0] snoop_tag;
    wire       snoop_evict_start;
    wire [31:0] snoop_evict_addr;
    wire [31:0] snoop_evict_data_0;
    wire [31:0] snoop_evict_data_1;
    wire [31:0] snoop_evict_data_2;
    wire [31:0] snoop_evict_data_3;

    wire       flush_busy;
    wire [2:0] flush_state;
    wire [5:0] flush_index;
    wire       flush_evict_start;
    wire [31:0] flush_evict_addr;
    wire [31:0] flush_evict_data_0;
    wire [31:0] flush_evict_data_1;
    wire [31:0] flush_evict_data_2;
    wire [31:0] flush_evict_data_3;
    wire       flush_dirty_clear;
    wire [5:0] flush_dirty_index;

    wire        idle_hit_check = (state == DCACHE_STATE_IDLE) &&
                                 cpu_req && !fence_any && !flush_busy &&
                                 !snoop_busy && !tag_line_invalidate;

    wire [31:0] lookup_addr   = idle_hit_check ? cpu_addr : cur_addr;
    wire [21:0] lookup_tag_w  = lookup_addr[31:10];
    wire [5:0]  lookup_index  = lookup_addr[9:4];
    wire [1:0]  lookup_offset = lookup_addr[3:2];

    wire [21:0] cur_tag    = cur_addr[31:10];
    wire [5:0]  cur_index  = cur_addr[9:4];
    wire [1:0]  cur_offset = cur_addr[3:2];

    wire idle_tag_hit_valid = prev_was_idle_hit_check &&
                              (lookup_index == prev_lookup_index) &&
                              (lookup_tag_w == prev_lookup_tag) &&
                              !flush_busy;
    wire idle_hit = tag_hit && idle_tag_hit_valid;

    wire snoop_cpu_ok = (state == DCACHE_STATE_IDLE) ||
                         (state == DCACHE_STATE_PEER_SNOOP) ||
                         !cpu_req || (cpu_req && addr_is_nc);
    wire snoop_safe_to_accept = ((state == DCACHE_STATE_IDLE) ||
                                 (state == DCACHE_STATE_PEER_SNOOP)) && !flush_busy && !fence_any &&
                                snoop_cpu_ok && !do_deferred_write && !nc_just_completed &&
                                !tag_line_invalidate;
    wire cpu_req_without_snoop = cpu_req && !dc_snoop_req_valid;

    assign current_addr  = cur_addr;
    assign current_data  = cur_wdata;
    assign current_valid = (state != DCACHE_STATE_IDLE);

    assign tag_lookup_index = flush_busy ? flush_index :
                              snoop_lookup_active ? snoop_index : lookup_index;
    assign tag_lookup_tag   = flush_busy ? 22'h0 :
                              snoop_lookup_active ? snoop_tag : lookup_tag_w;

    assign data_read_index     = flush_busy ? flush_index : lookup_index;
    assign data_read_offset    = lookup_offset;
    assign data_read_all_index = flush_busy ? flush_index :
                                 snoop_lookup_active ? snoop_index : cur_index;

    assign tag_dirty_set   = main_dirty_set;
    assign tag_dirty_clear = flush_dirty_clear | main_dirty_clear;
    assign tag_dirty_index = flush_dirty_clear ? flush_dirty_index : main_dirty_index_r;

    assign evict_start    = flush_evict_start | main_evict_start | snoop_evict_start;
    assign evict_addr     = flush_evict_start ? flush_evict_addr :
                            snoop_evict_start ? snoop_evict_addr :
                            main_evict_addr_r;
    assign evict_data_0   = flush_evict_start ? flush_evict_data_0 :
                            snoop_evict_start ? snoop_evict_data_0 :
                            main_evict_data_0_r;
    assign evict_data_1   = flush_evict_start ? flush_evict_data_1 :
                            snoop_evict_start ? snoop_evict_data_1 :
                            main_evict_data_1_r;
    assign evict_data_2   = flush_evict_start ? flush_evict_data_2 :
                            snoop_evict_start ? snoop_evict_data_2 :
                            main_evict_data_2_r;
    assign evict_data_3   = flush_evict_start ? flush_evict_data_3 :
                            snoop_evict_start ? snoop_evict_data_3 :
                            main_evict_data_3_r;
    assign evict_nc       = main_evict_start ? main_evict_nc_r : 1'b0;
    assign evict_wstrb_nc = main_evict_start ? main_evict_wstrb_nc_r : 4'h0;

    dcache_next_state u_next_state (
        .state(state),
        .flush_busy(flush_busy),
        .snoop_busy(snoop_busy),
        .tag_line_invalidate(tag_line_invalidate),
        .cpu_req(cpu_req_without_snoop),
        .fence_any(fence_any),
        .nc_just_completed(nc_just_completed),
        .do_deferred_write(do_deferred_write),
        .addr_is_nc(addr_is_nc),
        .cpu_we(cpu_we),
        .idle_hit(idle_hit),
        .tag_lookup_stable(tag_lookup_stable),
        .tag_hit(tag_hit),
        .tag_dirty_out(tag_dirty_out),
        .miss_snoop_enable(miss_snoop_enable),
        .miss_snoop_accepted(miss_snoop_accepted_r),
        .miss_snoop_resp_valid(miss_snoop_resp_valid),
        .local_miss_dirty(local_miss_dirty_r),
        .evict_done(evict_done),
        .cur_we(cur_we),
        .refill_data_valid(refill_data_valid),
        .refill_word(refill_word),
        .requested_offset(requested_offset),
        .refill_done(refill_done),
        .requested_data_ready(requested_data_ready),
        .next_state(next_state)
    );

    dcache_cpu_response u_cpu_response (
        .state(state),
        .flush_busy(flush_busy),
        .snoop_busy(snoop_busy),
        .tag_line_invalidate(tag_line_invalidate),
        .cpu_req(cpu_req),
        .idle_hit(idle_hit),
        .fence_any(fence_any),
        .do_deferred_write(do_deferred_write),
        .cpu_we(cur_we),
        .tag_lookup_stable(tag_lookup_stable),
        .tag_hit(tag_hit),
        .data_read_data(data_read_data),
        .refill_data_valid(refill_data_valid),
        .refill_word(refill_word),
        .requested_offset(requested_offset),
        .refill_data(refill_data),
        .refill_done(refill_done),
        .requested_data_ready(requested_data_ready),
        .requested_data(requested_data),
        .evict_done(evict_done),
        .cpu_ready(cpu_ready),
        .cpu_rdata(cpu_rdata)
    );

    dcache_flush_ctrl u_flush_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .fence_flush(fence_flush),
        .fence_inval(fence_inval),
        .fence_any(fence_any),
        .dirty_track_set(main_dirty_set),
        .dirty_track_clear(tag_dirty_clear),
        .dirty_track_index(tag_dirty_index),
        .tag_line_invalidate(tag_line_invalidate),
        .tag_line_invalidate_index(tag_line_invalidate_index),
        .tag_evict_tag_out(tag_evict_tag_out),
        .data_read_word_0(data_read_word_0),
        .data_read_word_1(data_read_word_1),
        .data_read_word_2(data_read_word_2),
        .data_read_word_3(data_read_word_3),
        .evict_done(evict_done),
        .flush_busy(flush_busy),
        .flush_state(flush_state),
        .flush_index(flush_index),
        .flush_evict_start(flush_evict_start),
        .flush_evict_addr(flush_evict_addr),
        .flush_evict_data_0(flush_evict_data_0),
        .flush_evict_data_1(flush_evict_data_1),
        .flush_evict_data_2(flush_evict_data_2),
        .flush_evict_data_3(flush_evict_data_3),
        .flush_dirty_clear(flush_dirty_clear),
        .flush_dirty_index(flush_dirty_index),
        .tag_flush_all(tag_flush_all),
        .tag_invalidate_all(tag_invalidate_all)
    );

    dcache_snoop_ctrl u_snoop_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .snoop_req_addr(dc_snoop_addr),
        .snoop_req_cmd(dc_snoop_cmd),
        .snoop_req_valid(dc_snoop_req_valid),
        .snoop_safe_to_accept(snoop_safe_to_accept),
        .tag_hit(tag_hit),
        .tag_dirty_out(tag_dirty_out),
        .tag_state_out(tag_state_out),
        .data_read_word_0(data_read_word_0),
        .data_read_word_1(data_read_word_1),
        .data_read_word_2(data_read_word_2),
        .data_read_word_3(data_read_word_3),
        .evict_done(evict_done),
        .snoop_req_ready(dc_snoop_req_ready),
        .snoop_resp_valid(dc_snoop_resp_valid),
        .snoop_resp_hit(dc_snoop_resp_hit),
        .snoop_resp_data(dc_snoop_resp_data),
        .snoop_busy(snoop_busy),
        .snoop_lookup_active(snoop_lookup_active),
        .snoop_index(snoop_index),
        .snoop_tag(snoop_tag),
        .tag_line_shared(tag_line_shared),
        .tag_line_shared_index(tag_line_shared_index),
        .tag_line_invalidate(tag_line_invalidate),
        .tag_line_invalidate_index(tag_line_invalidate_index),
        .snoop_evict_start(snoop_evict_start),
        .snoop_evict_addr(snoop_evict_addr),
        .snoop_evict_data_0(snoop_evict_data_0),
        .snoop_evict_data_1(snoop_evict_data_1),
        .snoop_evict_data_2(snoop_evict_data_2),
        .snoop_evict_data_3(snoop_evict_data_3)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            nc_just_completed <= 1'b0;
        else
            nc_just_completed <= (state == DCACHE_STATE_NC_WRITE && evict_done) ||
                                 (state == DCACHE_STATE_NC_READ  && refill_done);
    end

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= DCACHE_STATE_IDLE;
        else
            state <= next_state;
    end

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
            main_evict_index_r   <= 6'h0;
            local_miss_dirty_r   <= 1'b0;
            pending_write        <= 1'b0;
            do_deferred_write    <= 1'b0;
            deferred_offset      <= 2'b00;
            deferred_wdata       <= 32'h0;
            deferred_wstrb       <= 4'h0;
            deferred_index       <= 6'h0;
            miss_snoop_addr      <= 32'h0;
            miss_snoop_cmd       <= 2'b00;
            miss_snoop_req_valid <= 1'b0;
            miss_snoop_accepted_r<= 1'b0;
            main_evict_start     <= 1'b0;
            main_evict_addr_r    <= 32'h0;
            main_evict_data_0_r  <= 32'h0;
            main_evict_data_1_r  <= 32'h0;
            main_evict_data_2_r  <= 32'h0;
            main_evict_data_3_r  <= 32'h0;
            main_evict_nc_r      <= 1'b0;
            main_evict_wstrb_nc_r<= 4'h0;
            tag_update_valid     <= 1'b0;
            tag_update_index     <= 6'h0;
            tag_update_tag       <= 22'h0;
            main_dirty_set       <= 1'b0;
            main_dirty_clear     <= 1'b0;
            main_dirty_index_r   <= 6'h0;
            data_write_enable    <= 1'b0;
            data_write_index     <= 6'h0;
            data_write_offset    <= 2'b00;
            data_write_data      <= 32'h0;
            data_write_strb      <= 4'h0;
            stat_hits            <= 32'h0;
            stat_misses          <= 32'h0;
            stat_writes          <= 32'h0;
        end else begin
            refill_start         <= 1'b0;
            refill_nc            <= 1'b0;
            miss_snoop_req_valid <= 1'b0;
            main_evict_start     <= 1'b0;
            main_evict_nc_r      <= 1'b0;
            main_evict_wstrb_nc_r<= 4'h0;
            tag_update_valid     <= 1'b0;
            main_dirty_set       <= 1'b0;
            main_dirty_clear     <= 1'b0;
            data_write_enable    <= 1'b0;
            do_deferred_write    <= 1'b0;

            if (!flush_busy) begin
                case (state)
                    DCACHE_STATE_IDLE: begin
                        requested_data_ready <= 1'b0;
                        pending_write        <= 1'b0;
                        miss_snoop_accepted_r<= 1'b0;

                        if (do_deferred_write) begin
                            data_write_enable <= 1'b1;
                            data_write_index  <= deferred_index;
                            data_write_offset <= deferred_offset;
                            data_write_data   <= deferred_wdata;
                            data_write_strb   <= deferred_wstrb;
                            do_deferred_write <= 1'b0;
                        end

                        if (!snoop_busy && !tag_line_invalidate &&
                            cpu_req_without_snoop && !fence_any && !nc_just_completed && !do_deferred_write) begin
                            cur_addr  <= cpu_addr;
                            cur_wdata <= cpu_wdata;
                            cur_wstrb <= cpu_wstrb;
                            cur_we    <= cpu_we;

                            if (addr_is_nc) begin
                                if (cpu_we) begin
                                    main_evict_addr_r     <= cpu_addr;
                                    main_evict_data_0_r   <= cpu_wdata;
                                    main_evict_data_1_r   <= 32'h0;
                                    main_evict_data_2_r   <= 32'h0;
                                    main_evict_data_3_r   <= 32'h0;
                                    main_evict_nc_r       <= 1'b1;
                                    main_evict_wstrb_nc_r <= cpu_wstrb;
                                    main_evict_start      <= 1'b1;
                                    stat_writes           <= stat_writes + 1;
                                end else begin
                                    refill_addr  <= cpu_addr;
                                    refill_nc    <= 1'b1;
                                    refill_start <= 1'b1;
                                end
                            end else if (idle_hit) begin
                                if (cpu_we) begin
                                    stat_writes           <= stat_writes + 1;
                                    stat_hits             <= stat_hits + 1;
                                    data_write_enable     <= 1'b1;
                                    data_write_index      <= lookup_index;
                                    data_write_offset     <= lookup_offset;
                                    data_write_data       <= cpu_wdata;
                                    data_write_strb       <= cpu_wstrb;
                                    main_dirty_set        <= 1'b1;
                                    main_dirty_index_r    <= lookup_index;
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
                                    stat_writes           <= stat_writes + 1;
                                    stat_hits             <= stat_hits + 1;
                                    data_write_enable     <= 1'b1;
                                    data_write_index      <= cur_index;
                                    data_write_offset     <= cur_offset;
                                    data_write_data       <= cur_wdata;
                                    data_write_strb       <= cur_wstrb;
                                    main_dirty_set        <= 1'b1;
                                    main_dirty_index_r    <= cur_index;
                                end else begin
                                    stat_hits <= stat_hits + 1;
                                end
                            end else begin
                                stat_misses <= stat_misses + 1;
                                if (cur_we)
                                    stat_writes <= stat_writes + 1;

                                refill_index_r   <= cur_index;
                                refill_tag_r     <= cur_tag;
                                requested_offset <= cur_offset;
                                pending_write    <= cur_we;
                                local_miss_dirty_r <= tag_dirty_out;
                                miss_snoop_addr    <= {cur_addr[31:4], 4'b0000};
                                miss_snoop_cmd     <= 2'b10;

                                if ((!miss_snoop_enable || cur_we) && tag_dirty_out) begin
                                    main_evict_addr_r     <= {tag_evict_tag_out, cur_index, 4'b0000};
                                    main_evict_data_0_r   <= data_read_word_0;
                                    main_evict_data_1_r   <= data_read_word_1;
                                    main_evict_data_2_r   <= data_read_word_2;
                                    main_evict_data_3_r   <= data_read_word_3;
                                    main_evict_index_r    <= cur_index;
                                    main_evict_start      <= 1'b1;
                                end else if (!miss_snoop_enable || cur_we) begin
                                    refill_addr  <= {cur_addr[31:4], 4'b0000};
                                    refill_start <= 1'b1;
                                end
                            end
                        end
                    end

                    DCACHE_STATE_PEER_SNOOP: begin
                        if (miss_snoop_resp_valid) begin
                            if (local_miss_dirty_r) begin
                                main_evict_addr_r     <= {tag_evict_tag_out, cur_index, 4'b0000};
                                main_evict_data_0_r   <= data_read_word_0;
                                main_evict_data_1_r   <= data_read_word_1;
                                main_evict_data_2_r   <= data_read_word_2;
                                main_evict_data_3_r   <= data_read_word_3;
                                main_evict_index_r    <= cur_index;
                                main_evict_start      <= 1'b1;
                            end else begin
                                refill_addr  <= {cur_addr[31:4], 4'b0000};
                                refill_start <= 1'b1;
                            end
                        end else if (!miss_snoop_accepted_r) begin
                            miss_snoop_req_valid <= 1'b1;
                            if (miss_snoop_req_ready)
                                miss_snoop_accepted_r <= 1'b1;
                        end
                    end

                    DCACHE_STATE_EVICT: begin
                        if (evict_done) begin
                            main_dirty_clear      <= 1'b1;
                            main_dirty_index_r    <= main_evict_index_r;
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

                            if ((refill_word == requested_offset) && !requested_data_ready) begin
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
                                main_dirty_set         <= 1'b1;
                                main_dirty_index_r     <= refill_index_r;
                                pending_write          <= 1'b0;
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

                    default: begin
                    end
                endcase
            end
        end
    end

`ifdef DEBUG_DCACHE
    always @(posedge clk) begin
        if (flush_busy && cpu_req && cpu_we && (cpu_addr[31:29] != 3'b000))
            $display("[%0t][NC-WR-BLOCKED-FLUSH] addr=%08h data=%08h",
                     $time, cpu_addr, cpu_wdata);
        if (!flush_busy && !fence_any && nc_just_completed && cpu_req && cpu_we &&
            (cpu_addr[31:29] != 3'b000))
            $display("[%0t][NC-WR-BLOCKED-GUARD] addr=%08h data=%08h",
                     $time, cpu_addr, cpu_wdata);
        if (state == DCACHE_STATE_NC_WRITE && next_state == DCACHE_STATE_IDLE)
            $display("[%0t][NC-WRITE-DONE] addr=%08h evict_done=%b flush_busy=%b",
                     $time, cur_addr, evict_done, flush_busy);
    end
`endif

endmodule
