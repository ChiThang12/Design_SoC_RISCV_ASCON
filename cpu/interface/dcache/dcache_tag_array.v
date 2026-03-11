// ============================================================================
// Module: dcache_tag_array  —  Write-Back version
// ============================================================================
// FIX-BUG3: Dirty forwarding thiếu khi update_fwd active cùng lúc với
//           dirty_set_fwd. Trường hợp này xảy ra sau write-allocate.
//   Fix: update dirty_array ĐỒNG THỜI với valid_array trong cùng always
//        block, và forward cả dirty khi update_fwd active.
//
// FIX-BUG-FALSE-HIT: stored hit không được masked khi update_fwd=1.
//   Scenario: index=N có tag=A (old). update_fwd=1, update_tag=B (new).
//   Request với lookup_tag=A:
//     stored_match = (tag[N]=A == lookup_tag=A) = TRUE → false hit!
//   Nhưng data_array[N] đã chứa data của B (refill xong).
//   → CPU nhận data của B với tag của A → SAI.
//
//   Root cause: khi update_fwd=1, tag cũ đang bị thay thế bởi tag mới.
//   Tag cũ không còn valid → phải bỏ qua stored hit, chỉ dùng forward.
//
//   FIX: Dùng MUX thay vì OR:
//     hit = update_fwd ? (update_tag == lookup_tag)
//                      : (stored_valid && stored_match);
// ============================================================================

`include "cpu/interface/dcache/dcache_defines.vh"

module dcache_tag_array (
    input wire clk,
    input wire rst_n,

    // Lookup Interface
    input wire [5:0]   lookup_index,
    input wire [21:0]  lookup_tag,
    output wire        hit,
    output wire        dirty_out,       // dirty bit của line lookup
    output wire [21:0] evict_tag_out,   // tag hiện tại để tính evict addr

    // Update Interface (allocate line mới khi refill xong)
    input wire         update_valid,
    input wire [5:0]   update_index,
    input wire [21:0]  update_tag,

    // Dirty Control Interface
    input wire         dirty_set,       // set dirty=1 (write hit / write-allocate)
    input wire         dirty_clear,     // clear dirty=0 (eviction done)
    input wire [5:0]   dirty_index,     // which line for dirty ops

    // Flush Interface
    input wire         flush_all
);

    // ========================================================================
    // Storage Arrays
    // ========================================================================
    reg        valid_array [0:63];
    reg [21:0] tag_array   [0:63];
    reg        dirty_array [0:63];

    // ========================================================================
    // Lookup Logic — Write-First Forwarding
    // ========================================================================
    wire stored_valid = valid_array[lookup_index];
    wire stored_match = (tag_array[lookup_index] == lookup_tag);

    wire update_fwd      = update_valid && (update_index == lookup_index);
    wire dirty_set_fwd   = dirty_set    && (dirty_index  == lookup_index);
    wire dirty_clear_fwd = dirty_clear  && (dirty_index  == lookup_index);

    // FIX-BUG-FALSE-HIT: Khi update_fwd=1, line đang được cấp phát lại
    // với tag mới. Tag cũ không còn valid → dùng MUX, không dùng OR.
    // update_fwd=1: chỉ hit nếu tag MỚI (update_tag) khớp lookup_tag.
    // update_fwd=0: hit theo stored value bình thường.
    assign hit = update_fwd ? (update_tag == lookup_tag)
                            : (stored_valid && stored_match);

    // FIX-BUG3: Dirty forwarding phải cover cả trường hợp update_fwd active
    assign dirty_out = dirty_set_fwd   ? 1'b1 :
                       dirty_clear_fwd ? 1'b0 :
                       (update_fwd && !dirty_set_fwd) ? 1'b0 :
                       dirty_array[lookup_index];

    // Evict tag: khi update_fwd active → forward tag mới
    assign evict_tag_out = update_fwd ? update_tag : tag_array[lookup_index];

    // ========================================================================
    // Update Logic (Sequential)
    // ========================================================================
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 64; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= 22'h0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            if (flush_all) begin
                for (i = 0; i < 64; i = i + 1) begin
                    valid_array[i] <= 1'b0;
                    dirty_array[i] <= 1'b0;
                end
            end else begin
                // Allocate line mới khi refill xong
                if (update_valid) begin
                    valid_array[update_index] <= 1'b1;
                    tag_array[update_index]   <= update_tag;
                    dirty_array[update_index] <= 1'b0;
                end

                // Set dirty khi write hit hoặc write-allocate
                // Priority: dirty_set override clear từ update (same always block)
                if (dirty_set) begin
                    dirty_array[dirty_index] <= 1'b1;
                end

                // Clear dirty khi eviction hoàn thành
                if (dirty_clear) begin
                    dirty_array[dirty_index] <= 1'b0;
                    valid_array[dirty_index] <= 1'b0;
                end
            end
        end
    end

endmodule