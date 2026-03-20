// ============================================================================
// Module: dcache_tag_array — Direct-Mapped, 64 sets, 22-bit tag
// ============================================================================
//
// [FENCE-TYPE] Tách biệt flush và invalidate:
//
//   flush_all      = 1 : chỉ clear dirty bits, GIỮ NGUYÊN valid bits
//                        → cache lines vẫn readable (stack an toàn)
//                        → triggered bởi fence w,w (fence_type[0]=1)
//
//   invalidate_all = 1 : clear cả valid bits lẫn dirty bits
//                        → toàn bộ cache bị invalidate
//                        → triggered bởi fence iorw / fence.i (fence_type[1]=1)
//
// Cả hai có thể assert cùng lúc (fence iorw):
//   flush_all=1 + invalidate_all=1 → writeback dirty + invalidate all
//
// Lưu ý: flush_all chỉ clear dirty bit, KHÔNG writeback dữ liệu ra DMEM.
// Việc writeback được thực hiện bởi dcache_controller thông qua evict path
// trước khi assert flush_all. Trong thiết kế này (write-back, write-allocate),
// fence w,w yêu cầu writeback trước khi DMA đọc — controller phải xử lý
// eviction loop trước khi signal flush_all (TODO: cần fence FSM trong controller
// nếu muốn đúng hoàn toàn). Hiện tại flush_all chỉ clear dirty để tránh
// false eviction sau fence.
//
// ============================================================================

`include "cache_interface/dcache/dcache_defines.vh"

module dcache_tag_array #(
    parameter NUM_SETS  = 64,   // 6-bit index → 64 sets
    parameter TAG_WIDTH = 22    // addr[31:10]
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Lookup (combinational read — results valid next cycle)
    input  wire [5:0]            lookup_index,
    input  wire [TAG_WIDTH-1:0]  lookup_tag,
    output wire                  hit,
    output wire                  dirty_out,
    output wire [TAG_WIDTH-1:0]  evict_tag_out,

    // Update (fill new line after refill)
    input  wire                  update_valid,
    input  wire [5:0]            update_index,
    input  wire [TAG_WIDTH-1:0]  update_tag,

    // Dirty management
    input  wire                  dirty_set,
    input  wire                  dirty_clear,
    input  wire [5:0]            dirty_index,

    // [FENCE-TYPE] Flush vs Invalidate — tách biệt
    // flush_all=1      : clear dirty bits ONLY  (fence w,w)
    // invalidate_all=1 : clear valid + dirty     (fence iorw / fence.i)
    input  wire                  flush_all,
    input  wire                  invalidate_all
);

    // =========================================================================
    // Storage arrays
    // =========================================================================
    reg [TAG_WIDTH-1:0] tags  [0:NUM_SETS-1];
    reg                 valid [0:NUM_SETS-1];
    reg                 dirty [0:NUM_SETS-1];

    integer i;

    // =========================================================================
    // Synchronous write
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Power-on reset: invalidate everything
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tags[i]  <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            // ─── Priority (highest → lowest) ───────────────────────────────
            // 1. invalidate_all : clear valid + dirty tất cả sets (fence iorw)
            // 2. flush_all      : clear dirty ONLY (fence w,w) — valid an toàn
            // 3. update_valid   : install new tag sau refill
            // 4. dirty_set      : mark line dirty sau write
            // 5. dirty_clear    : clear dirty sau eviction
            // Các op này không conflict trong thực tế vì controller serializes
            // fence trước khi resume normal operation.
            // ─────────────────────────────────────────────────────────────────

            if (invalidate_all) begin
                // fence iorw / fence.i → invalidate toàn bộ
                for (i = 0; i < NUM_SETS; i = i + 1) begin
                    valid[i] <= 1'b0;
                    dirty[i] <= 1'b0;
                end
            end else if (flush_all) begin
                // fence w,w → chỉ clear dirty, GIỮ NGUYÊN valid
                // Stack frame vẫn readable, không cần refill lại
                for (i = 0; i < NUM_SETS; i = i + 1) begin
                    dirty[i] <= 1'b0;
                end
            end else begin
                // Normal operation
                if (update_valid) begin
                    tags [update_index] <= update_tag;
                    valid[update_index] <= 1'b1;
                    dirty[update_index] <= 1'b0; // new refill = clean
                end

                if (dirty_set) begin
                    dirty[dirty_index] <= 1'b1;
                end

                if (dirty_clear) begin
                    dirty[dirty_index] <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // Synchronous read (1-cycle latency — matches dcache_controller FIX-BUG-LOOKUP)
    // =========================================================================
    reg                 hit_r;
    reg                 dirty_r;
    reg [TAG_WIDTH-1:0] evict_tag_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_r       <= 1'b0;
            dirty_r     <= 1'b0;
            evict_tag_r <= {TAG_WIDTH{1'b0}};
        end else begin
            hit_r       <= valid[lookup_index] && (tags[lookup_index] == lookup_tag);
            dirty_r     <= dirty[lookup_index];
            evict_tag_r <= tags[lookup_index];
        end
    end

    assign hit          = hit_r;
    assign dirty_out    = dirty_r;
    assign evict_tag_out = evict_tag_r;

endmodule