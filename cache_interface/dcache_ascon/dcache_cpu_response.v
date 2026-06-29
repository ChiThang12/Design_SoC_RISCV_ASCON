module dcache_cpu_response (
    // ---------------------------------------------------------------------
    // Current state and global blockers
    // ---------------------------------------------------------------------
    input  wire [3:0]  state,
    input  wire        flush_busy,
    input  wire        snoop_busy,
    input  wire        tag_line_invalidate,

    // ---------------------------------------------------------------------
    // CPU-side request context
    // ---------------------------------------------------------------------
    input  wire        cpu_req,
    input  wire        idle_hit,
    input  wire        fence_any,
    input  wire        do_deferred_write,
    input  wire        cpu_we,

    // ---------------------------------------------------------------------
    // Lookup and refill/evict results
    // ---------------------------------------------------------------------
    input  wire        tag_lookup_stable,
    input  wire        tag_hit,
    input  wire [31:0] data_read_data,
    input  wire        refill_data_valid,
    input  wire [1:0]  refill_word,
    input  wire [1:0]  requested_offset,
    input  wire [31:0] refill_data,
    input  wire        refill_done,
    input  wire        requested_data_ready,
    input  wire [31:0] requested_data,
    input  wire        evict_done,
    input  wire        c2c_fill_done,

    // ---------------------------------------------------------------------
    // CPU response
    // ---------------------------------------------------------------------
    output reg         cpu_ready,
    output reg [31:0]  cpu_rdata
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
        DCACHE_STATE_PEER_SNOOP   = 4'b1000,
        DCACHE_STATE_C2C_FILL     = 4'b1001;

    always @(*) begin
        cpu_ready = 1'b0;
        cpu_rdata = 32'h0;

        if (!flush_busy) begin
            case (state)
                DCACHE_STATE_IDLE: begin
                    if (!snoop_busy && !tag_line_invalidate &&
                        cpu_req && idle_hit && !fence_any && !do_deferred_write) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = cpu_we ? 32'h0 : data_read_data;
                    end
                end

                DCACHE_STATE_LOOKUP: begin
                    if (tag_lookup_stable && tag_hit) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = cpu_we ? 32'h0 : data_read_data;
                    end
                end

                DCACHE_STATE_REFILL: begin
                    if (!cpu_we && refill_data_valid && (refill_word == requested_offset)) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = refill_data;
                    end else if (cpu_we && refill_done) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = 32'h0;
                    end else if (!cpu_we && refill_done && requested_data_ready) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = requested_data;
                    end
                end

                DCACHE_STATE_NC_READ: begin
                    if (refill_done) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = refill_data;
                    end
                end

                DCACHE_STATE_NC_WRITE: begin
                    if (evict_done) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = 32'h0;
                    end
                end

                DCACHE_STATE_C2C_FILL: begin
                    if (c2c_fill_done) begin
                        cpu_ready = 1'b1;
                        cpu_rdata = requested_data;
                    end
                end

                default: begin
                    cpu_ready = 1'b0;
                    cpu_rdata = 32'h0;
                end
            endcase
        end
    end
endmodule
