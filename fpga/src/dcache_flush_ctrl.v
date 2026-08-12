module dcache_flush_ctrl (
    // ---------------------------------------------------------------------
    // Clock / Reset
    // ---------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // ---------------------------------------------------------------------
    // Fence request classification
    // ---------------------------------------------------------------------
    input  wire        fence_flush,
    input  wire        fence_inval,
    input  wire        fence_any,

    // ---------------------------------------------------------------------
    // Dirty-line tracking updates from the parent controller
    // ---------------------------------------------------------------------
    input  wire        dirty_track_set,
    input  wire        dirty_track_clear,
    input  wire [5:0]  dirty_track_index,
    input  wire        tag_line_invalidate,
    input  wire [5:0]  tag_line_invalidate_index,

    // ---------------------------------------------------------------------
    // Tag / data lookup results used during flush eviction
    // ---------------------------------------------------------------------
    input  wire [21:0] tag_evict_tag_out,
    input  wire [31:0] data_read_word_0,
    input  wire [31:0] data_read_word_1,
    input  wire [31:0] data_read_word_2,
    input  wire [31:0] data_read_word_3,

    // ---------------------------------------------------------------------
    // Eviction completion handshake
    // ---------------------------------------------------------------------
    input  wire        evict_done,

    // ---------------------------------------------------------------------
    // Flush status and generated actions
    // ---------------------------------------------------------------------
    output reg         flush_busy,
    output reg  [2:0]  flush_state,
    output reg  [5:0]  flush_index,
    output reg         flush_evict_start,
    output reg  [31:0] flush_evict_addr,
    output reg  [31:0] flush_evict_data_0,
    output reg  [31:0] flush_evict_data_1,
    output reg  [31:0] flush_evict_data_2,
    output reg  [31:0] flush_evict_data_3,
    output reg         flush_dirty_clear,
    output reg  [5:0]  flush_dirty_index,
    output reg         tag_flush_all,
    output reg         tag_invalidate_all
);

    localparam [2:0]
        FLUSH_IDLE     = 3'd0,
        FLUSH_SETTLE   = 3'd1,
        FLUSH_SCAN     = 3'd2,
        FLUSH_EVICT    = 3'd3,
        FLUSH_DONE     = 3'd4,
        FLUSH_TAG_WAIT = 3'd5;

    reg [63:0] dirty_bitmap;
    reg        flush_need_inval;
    reg [5:0]  evict_index_r;
    reg [5:0]  flush_next_dirty_index;
    reg        flush_has_dirty;
    integer    pe_i;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dirty_bitmap <= 64'h0;
        end else begin
            if (tag_flush_all || tag_invalidate_all) begin
                dirty_bitmap <= 64'h0;
            end else begin
                if (dirty_track_set)
                    dirty_bitmap[dirty_track_index] <= 1'b1;
                if (dirty_track_clear)
                    dirty_bitmap[dirty_track_index] <= 1'b0;
                if (tag_line_invalidate)
                    dirty_bitmap[tag_line_invalidate_index] <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flush_state        <= FLUSH_IDLE;
            flush_index        <= 6'h0;
            flush_busy         <= 1'b0;
            flush_need_inval   <= 1'b0;
            evict_index_r      <= 6'h0;
            flush_evict_start  <= 1'b0;
            flush_evict_addr   <= 32'h0;
            flush_evict_data_0 <= 32'h0;
            flush_evict_data_1 <= 32'h0;
            flush_evict_data_2 <= 32'h0;
            flush_evict_data_3 <= 32'h0;
            flush_dirty_clear  <= 1'b0;
            flush_dirty_index  <= 6'h0;
            tag_flush_all      <= 1'b0;
            tag_invalidate_all <= 1'b0;
        end else begin
            flush_evict_start  <= 1'b0;
            flush_dirty_clear  <= 1'b0;
            tag_flush_all      <= 1'b0;
            tag_invalidate_all <= 1'b0;

            case (flush_state)
                FLUSH_IDLE: begin
                    if (fence_any) begin
                        flush_need_inval <= fence_inval;
                        flush_busy       <= 1'b1;
                        if (!fence_flush)
                            flush_state <= FLUSH_DONE;
                        else
                            flush_state <= FLUSH_SCAN;
                    end
                end

                FLUSH_SCAN: begin
                    if (!flush_has_dirty) begin
                        flush_state <= FLUSH_DONE;
                    end else begin
                        flush_index <= flush_next_dirty_index;
                        flush_state <= FLUSH_SETTLE;
                    end
                end

                FLUSH_SETTLE: begin
                    evict_index_r      <= flush_index;
                    flush_evict_data_0 <= data_read_word_0;
                    flush_evict_data_1 <= data_read_word_1;
                    flush_evict_data_2 <= data_read_word_2;
                    flush_evict_data_3 <= data_read_word_3;
                    flush_state        <= FLUSH_TAG_WAIT;
                end

                FLUSH_TAG_WAIT: begin
                    flush_evict_addr  <= {tag_evict_tag_out, flush_index, 4'b0000};
                    flush_evict_start <= 1'b1;
                    flush_state       <= FLUSH_EVICT;
                end

                FLUSH_EVICT: begin
                    if (evict_done) begin
                        flush_dirty_clear <= 1'b1;
                        flush_dirty_index <= evict_index_r;
                        flush_state       <= FLUSH_SCAN;
                    end
                end

                FLUSH_DONE: begin
                    flush_busy <= 1'b0;
                    if (flush_need_inval)
                        tag_invalidate_all <= 1'b1;
                    else if (fence_flush)
                        tag_flush_all <= 1'b1;
                    flush_state <= FLUSH_IDLE;
                end

                default: begin
                    flush_state <= FLUSH_IDLE;
                end
            endcase
        end
    end
endmodule
