// ============================================================================
// Module: dcache_controller
// ============================================================================
// Description:
//   Main data cache controller with read/write support
//   - Write-through policy (all writes go to memory)
//   - Read miss triggers cache line refill
//   - Write hit:  update cache + write-through to DMEM
//   - Write miss: update cache (write-allocate) + write-through to DMEM
//
// BUG FIXES (so với version cũ):
//
//   FIX-A [CRITICAL] Write-miss không allocate cache line
//     Nguyên nhân RAW-ERR trong log:
//       store addr → write MISS → chỉ gửi AXI write-through, không update cache
//       load  addr → read  MISS → refill từ DMEM (đôi khi chưa kịp commit)
//                              → đọc data cũ = 0
//     Fix: Khi write MISS, ghi ngay word đó vào cache data array và
//          cập nhật tag array (write-allocate). Bước này xảy ra đồng thời
//          với AXI write-through → sau đó load cùng địa chỉ sẽ HIT cache,
//          không cần refill từ DMEM nữa.
//
//   FIX-B [CRITICAL] Race condition: write-through chưa commit, read-miss
//          refill đã bắt đầu
//     Nguyên nhân: FSM trả cpu_ready sau wt_done, CPU issue LOAD ngay.
//                  LOOKUP → read miss → REFILL khởi động NGAY KỲ ĐÓ.
//                  Nhưng với FIX-A, write-miss đã cập nhật cache →
//                  lần load sau sẽ HIT, không refill nữa → race biến mất.
//
//   FIX-C [HIGH] LOOKUP: hủy read request giữa chừng
//     Code cũ: if (!cpu_req && !cur_we) → về IDLE
//     Nếu cpu_req deassert 1 cycle (pipeline stall), request bị drop
//     → CPU nhận không bao giờ cpu_ready → treo.
//     Fix: Xóa điều kiện hủy mid-flight. Một khi đã latch vào LOOKUP,
//          FSM luôn xử lý đến khi complete.
//
//   FIX-D [MEDIUM] Write-hit: data_write_enable giữ 1 cycle thừa
//     data_write_enable = 1 được set ở LOOKUP, nhưng đồng thời
//     wt_start = 1 chuyển FSM sang WRITE_THRU.
//     Ở WRITE_THRU, default clearing của data_write_enable sẽ tắt nó
//     → chỉ 1 cycle → đúng cho data_array (sequential write)
//     → Không cần thay đổi, nhưng đã verify đây là intentional.
//
//   FIX-1..4 từ version trước (latch cpu_*, expose current_*, dùng cur_*)
//   giữ nguyên.
//
// Author: ChiThang
// ============================================================================

`include "cpu/interface/dcache/dcache_defines.vh"

module dcache_controller (
    input wire clk,
    input wire rst_n,

    // CPU Interface
    input wire [31:0] cpu_addr,
    input wire [31:0] cpu_wdata,
    input wire [3:0]  cpu_wstrb,
    input wire        cpu_req,
    input wire        cpu_we,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,
    input wire        fence,

    // Expose current request (debug / upstream visibility)
    output wire [31:0] current_addr,
    output wire [31:0] current_data,
    output wire        current_valid,

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

    // AXI Refill Interface (read misses)
    output reg [31:0]  refill_addr,
    output reg         refill_start,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,

    // AXI Write-Through Interface (writes)
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

    // =========================================================================
    // Registered request — latch khi IDLE nhận cpu_req
    // Dùng cur_* xuyên suốt FSM, tránh live signal thay đổi giữa chừng
    // =========================================================================
    reg [31:0] cur_addr;
    reg [31:0] cur_wdata;
    reg [3:0]  cur_wstrb;
    reg        cur_we;

    assign current_addr  = cur_addr;
    assign current_data  = cur_wdata;
    assign current_valid = (state != `DCACHE_STATE_IDLE);

    // =========================================================================
    // Address Decomposition từ cur_addr (registered)
    // =========================================================================
    wire [21:0] cur_tag;
    wire [5:0]  cur_index;
    wire [1:0]  cur_offset;

    assign cur_tag    = cur_addr[31:10];
    assign cur_index  = cur_addr[9:4];
    assign cur_offset = cur_addr[3:2];

    // Tag / Data array lookup dùng cur_addr
    assign tag_lookup_index = cur_index;
    assign tag_lookup_tag   = cur_tag;
    assign data_read_index  = cur_index;
    assign data_read_offset = cur_offset;

    // =========================================================================
    // State Machine
    // =========================================================================
    reg [2:0] state, next_state;

    // Refill tracking
    reg [5:0]  refill_index_r;
    reg [21:0] refill_tag_r;
    reg [1:0]  requested_offset;
    reg [31:0] requested_data;
    reg        requested_data_ready;

    // -------------------------------------------------------------------------
    // Sequential: state register
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= `DCACHE_STATE_IDLE;
        else if (fence)
            state <= `DCACHE_STATE_IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Combinational: next-state logic
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            `DCACHE_STATE_IDLE: begin
                if (cpu_req)
                    next_state = `DCACHE_STATE_LOOKUP;
            end

            `DCACHE_STATE_LOOKUP: begin
                if (cur_we) begin
                    // Write: luôn write-through, đồng thời update cache (FIX-A)
                    next_state = `DCACHE_STATE_WRITE_THRU;
                end else begin
                    // Read
                    if (tag_hit) begin
                        next_state = `DCACHE_STATE_IDLE;   // hit: done ngay
                    end else begin
                        next_state = `DCACHE_STATE_REFILL; // miss: refill
                    end
                end
                // FIX-C: Không có điều kiện hủy !cpu_req
                // Một khi đã vào LOOKUP, luôn xử lý đến complete.
            end

            `DCACHE_STATE_REFILL: begin
                if (refill_done)
                    next_state = `DCACHE_STATE_IDLE;
            end

            `DCACHE_STATE_WRITE_THRU: begin
                if (wt_done)
                    next_state = `DCACHE_STATE_IDLE;
            end

            default: next_state = `DCACHE_STATE_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Combinational: CPU output
    // -------------------------------------------------------------------------
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;

    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;

        case (state)
            `DCACHE_STATE_LOOKUP: begin
                if (!cur_we && tag_hit) begin
                    // Read hit: data từ data array (combinational)
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = data_read_data;
                end
            end

            `DCACHE_STATE_REFILL: begin
                if (refill_done) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = requested_data;
                end
            end

            `DCACHE_STATE_WRITE_THRU: begin
                if (wt_done) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = 32'h0;
                end
            end

            default: begin
                cpu_ready_int = 1'b0;
                cpu_rdata_int = 32'h0;
            end
        endcase
    end

    assign cpu_ready = cpu_ready_int;
    assign cpu_rdata = cpu_rdata_int;

    // =========================================================================
    // Sequential Output Logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_addr              <= 32'h0;
            cur_wdata             <= 32'h0;
            cur_wstrb             <= 4'h0;
            cur_we                <= 1'b0;

            refill_addr           <= 32'h0;
            refill_start          <= 1'b0;
            refill_index_r        <= 6'h0;
            refill_tag_r          <= 22'h0;
            requested_offset      <= 2'b00;
            requested_data        <= 32'h0;
            requested_data_ready  <= 1'b0;

            wt_addr               <= 32'h0;
            wt_data               <= 32'h0;
            wt_strb               <= 4'h0;
            wt_start              <= 1'b0;

            tag_update_valid      <= 1'b0;
            tag_update_index      <= 6'h0;
            tag_update_tag        <= 22'h0;
            tag_flush_all         <= 1'b0;

            data_write_enable     <= 1'b0;
            data_write_index      <= 6'h0;
            data_write_offset     <= 2'b00;
            data_write_data       <= 32'h0;
            data_write_strb       <= 4'h0;

            stat_hits             <= 32'h0;
            stat_misses           <= 32'h0;
            stat_writes           <= 32'h0;

        end else begin
            // Default: clear one-shot signals
            refill_start      <= 1'b0;
            wt_start          <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;

            if (fence) begin
                tag_flush_all <= 1'b1;
            end

            case (state)
                // =============================================================
                // IDLE: Latch request mới
                // =============================================================
                `DCACHE_STATE_IDLE: begin
                    requested_data_ready <= 1'b0;

                    if (cpu_req) begin
                        cur_addr  <= cpu_addr;
                        cur_wdata <= cpu_wdata;
                        cur_wstrb <= cpu_wstrb;
                        cur_we    <= cpu_we;
                    end
                end

                // =============================================================
                // LOOKUP: Tag check — quyết định hit/miss/write
                // =============================================================
                `DCACHE_STATE_LOOKUP: begin
                    if (cur_we) begin
                        // =====================================================
                        // WRITE PATH
                        // =====================================================
                        stat_writes <= stat_writes + 1;

                        // Bước 1: Gửi write-through xuống DMEM qua AXI
                        wt_addr  <= cur_addr;
                        wt_data  <= cur_wdata;
                        wt_strb  <= cur_wstrb;
                        wt_start <= 1'b1;

                        // Bước 2: Update cache data array (hit hoặc miss)
                        // ─────────────────────────────────────────────────────
                        // FIX-A: Trước đây chỉ update khi write HIT.
                        //        Nay update cả khi write MISS (write-allocate).
                        //
                        //   Write HIT:  line đã valid → chỉ cần merge byte-lane
                        //   Write MISS: line chưa có → ghi word này vào đúng
                        //               offset; các word khác trong line sẽ
                        //               là giá trị cũ (don't care vì chưa valid).
                        //               Sau đó đánh dấu tag valid.
                        //
                        //   Kết quả: load sau đó cùng địa chỉ → HIT → trả
                        //   đúng data; không cần refill từ DMEM → RAW-ERR biến mất.
                        // ─────────────────────────────────────────────────────
                        data_write_enable <= 1'b1;
                        data_write_index  <= cur_index;
                        data_write_offset <= cur_offset;
                        data_write_data   <= cur_wdata;
                        data_write_strb   <= cur_wstrb;

                        // FIX-A: Nếu write MISS → cập nhật tag array để line valid
                        if (!tag_hit) begin
                            tag_update_valid <= 1'b1;
                            tag_update_index <= cur_index;
                            tag_update_tag   <= cur_tag;
                        end

                        // Thống kê
                        if (tag_hit)
                            stat_hits   <= stat_hits + 1;
                        else
                            stat_misses <= stat_misses + 1;

                    end else begin
                        // =====================================================
                        // READ PATH
                        // =====================================================
                        if (tag_hit) begin
                            stat_hits <= stat_hits + 1;
                            // cpu_rdata trả combinationally từ data array
                            // → cpu_ready = 1 ngay cycle này (từ comb output)
                        end else begin
                            // Read miss: bắt đầu AXI burst refill
                            stat_misses      <= stat_misses + 1;
                            refill_addr      <= {cur_addr[31:4], 4'b0000};
                            refill_index_r   <= cur_index;
                            refill_tag_r     <= cur_tag;
                            requested_offset <= cur_offset;
                            refill_start     <= 1'b1;
                        end
                    end
                end

                // =============================================================
                // REFILL: Nhận từng word từ AXI burst, ghi vào data array
                // =============================================================
                `DCACHE_STATE_REFILL: begin
                    if (refill_data_valid) begin
                        data_write_enable <= 1'b1;
                        data_write_index  <= refill_index_r;
                        data_write_offset <= refill_word;
                        data_write_data   <= refill_data;
                        data_write_strb   <= 4'b1111;

                        // Capture word CPU yêu cầu
                        if (refill_word == requested_offset && !requested_data_ready) begin
                            requested_data       <= refill_data;
                            requested_data_ready <= 1'b1;
                        end
                    end

                    if (refill_done) begin
                        tag_update_valid <= 1'b1;
                        tag_update_index <= refill_index_r;
                        tag_update_tag   <= refill_tag_r;
                    end
                end

                // =============================================================
                // WRITE_THRU: Chờ AXI write response
                // cpu_ready được assert combinationally khi wt_done = 1
                // =============================================================
                `DCACHE_STATE_WRITE_THRU: begin
                    // Không cần làm gì thêm
                    // wt_done → next_state = IDLE → cpu_ready = 1 (comb)
                end

                default: ; // No action
            endcase
        end
    end

endmodule