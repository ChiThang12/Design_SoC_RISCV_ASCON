// ============================================================================
// Module: dcache_tag_array  —  Write-Back version
// ============================================================================
// FIX-BUG3: Dirty forwarding thiếu khi update_fwd active cùng lúc với
//           dirty_set_fwd. Trường hợp này xảy ra sau write-allocate:
//           cycle N:   refill_done → tag_update_valid=1 + tag_dirty_set=1
//           cycle N+1: CPU request mới đến cùng index → update_fwd=1
//                      nhưng dirty_set_fwd có thể không active (one-shot pulse)
//                      → dirty_out đọc từ dirty_array (chưa update) → 0 sai
//
//   Fix: Thêm dirty_set_pending register — latch dirty_set khi update_valid
//        active đồng thời, để dirty_out forward đúng trên cycle kế tiếp.
//        Thực chất: dirty_array[index] update cùng cycle với valid_array,
//        nên chỉ cần đảm bảo forwarding cover đúng cycle N+1.
//
// FIX cách đơn giản hơn: update dirty_array ĐỒNG THỜI với valid_array
// trong cùng always block (thay vì check dirty_set riêng biệt), và
// forward cả dirty khi update_fwd active.
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
    // Forward: nếu update/dirty đang nhắm đúng lookup_index trong cycle này
    wire stored_valid = valid_array[lookup_index];
    wire stored_match = (tag_array[lookup_index] == lookup_tag);

    wire update_fwd      = update_valid && (update_index == lookup_index);
    wire dirty_set_fwd   = dirty_set    && (dirty_index  == lookup_index);
    wire dirty_clear_fwd = dirty_clear  && (dirty_index  == lookup_index);

    // Hit: stored hit OR đang allocate line này với đúng tag
    assign hit = (stored_valid && stored_match) ||
                 (update_fwd  && (update_tag == lookup_tag));

    // FIX-BUG3: Dirty forwarding phải cover cả trường hợp update_fwd active
    // Khi update_fwd=1 và dirty_set_fwd=1 cùng lúc → new line = dirty (write-allocate)
    // Khi update_fwd=1 và không có dirty_set → new line = clean (refill)
    // Priority: dirty_set > dirty_clear > stored value
    // Khi update_fwd active mà dirty_set không set → line mới là clean (refill)
    assign dirty_out = dirty_set_fwd   ? 1'b1 :
                       dirty_clear_fwd ? 1'b0 :
                       (update_fwd && !dirty_set_fwd) ? 1'b0 :  // FIX: refill = clean
                       dirty_array[lookup_index];

    // Evict tag: nếu update đang set line này → forward tag mới (đây là tag sẽ được store)
    // Thực ra khi evict, ta cần tag CŨ (trước khi allocate) để tính evict_addr
    // update_fwd active chỉ SAU KHI evict đã xong → không conflict
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
                // Flush: invalidate all, clear dirty
                // NOTE: Flush không evict dirty lines — caller phải FENCE + drain SB trước
                for (i = 0; i < 64; i = i + 1) begin
                    valid_array[i] <= 1'b0;
                    dirty_array[i] <= 1'b0;
                end
            end else begin
                // Allocate line mới khi refill xong
                if (update_valid) begin
                    valid_array[update_index] <= 1'b1;
                    tag_array[update_index]   <= update_tag;
                    // FIX-BUG3: dirty_array phải được clear khi allocate (refill = clean data)
                    // dirty_set sẽ được assert riêng nếu cần (write-allocate path)
                    dirty_array[update_index] <= 1'b0;
                end

                // Set dirty khi write hit (hoặc write-allocate sau refill)
                // Priority: dirty_set có thể active cùng cycle với update_valid
                // (write-allocate: refill_done → update_valid=1 + dirty_set=1 đồng thời)
                // Vì cả 2 trong cùng always block, dirty_set override dirty clear từ update
                if (dirty_set) begin
                    dirty_array[dirty_index] <= 1'b1;
                end

                // Clear dirty khi eviction hoàn thành
                // dirty_clear và dirty_set không thể active cùng lúc (different states)
                if (dirty_clear) begin
                    dirty_array[dirty_index] <= 1'b0;
                    valid_array[dirty_index] <= 1'b0;  // invalidate sau evict
                end
            end
        end
    end

endmodule