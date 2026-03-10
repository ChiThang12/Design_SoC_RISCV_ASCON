// ============================================================================
// Module: dcache_controller  —  Write-Back + Write-Allocate + Optimized
// ============================================================================
//
// OPTIMIZATION:
// [OPT-1] 1-CYCLE HIT LATENCY
//   IDLE: check tag với cpu_addr trực tiếp → cpu_ready=1 ngay tại IDLE cycle
//   Chỉ vào LOOKUP khi MISS (cần evict/refill)
//
// [OPT-2] CRITICAL-WORD-FIRST trong REFILL
//   Khi beat chứa word CPU cần về → trả cpu_ready=1 ngay
//   FSM vào REFILL_DRAIN: drain nốt các beat còn lại
//   CPU resume execute trong khi cache fill nốt phần còn lại
//
// FIX-BUG2 (axi_interface): refill_done bây giờ assert CÙNG CYCLE với beat cuối
//   Controller phải update CWF logic: không cần check refill_done riêng nữa
//   → nếu (refill_data_valid & refill_word==requested_offset & refill_done)
//     đều true cùng lúc → về IDLE thẳng (không qua REFILL_DRAIN)
//
// FIX-BUG3 (tag_array): Write-allocate dirty_set phải được assert
//   CÙNG CYCLE với tag_update_valid khi pending_write=1
//   → dirty_set + dirty_index set khi refill_done & pending_write
//
// FIX-BUG-LOOKUP (controller): LOOKUP state dùng tag_hit sai cycle
//   Tag array là synchronous read: kết quả lookup_index/lookup_tag
//   chỉ có sau 1 clock edge. Khi IDLE miss → state chuyển sang LOOKUP,
//   nhưng tag array vẫn đang dùng cpu_addr (idle_hit_check=0 → cur_addr).
//   Vấn đề: tại cycle đầu tiên của LOOKUP, tag_hit vẫn là kết quả
//   từ cycle IDLE (dùng cpu_addr cũ hoặc cur_addr chưa stable).
//   FIX: LOOKUP state bỏ qua tag_hit ở cycle đầu tiên (tag_lookup_stable),
//        chờ 1 cycle để tag array trả kết quả đúng với cur_addr.
//
// STATE MACHINE:
//   IDLE         → IDLE           (hit: 1 cycle)
//   IDLE         → LOOKUP         (miss: latch cur_addr, chờ tag array)
//   LOOKUP       → EVICT          (dirty victim, tag stable)
//   LOOKUP       → REFILL         (clean victim, tag stable)
//   EVICT        → WAIT
//   WAIT         → REFILL
//   REFILL       → IDLE           (CWF hoặc write miss done)
//   REFILL       → REFILL_DRAIN   (CWF: critical word arrived, burst chưa xong)
//   REFILL_DRAIN → IDLE           (burst hoàn tất)
// ============================================================================

`include "cpu/interface/dcache/dcache_defines.vh"

module dcache_controller (
    input wire clk,
    input wire rst_n,

    // CPU Interface
    input wire [31:0]  cpu_addr,
    input wire [31:0]  cpu_wdata,
    input wire [3:0]   cpu_wstrb,
    input wire         cpu_req,
    input wire         cpu_we,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,
    input wire         fence,

    // Debug
    output wire [31:0] current_addr,
    output wire [31:0] current_data,
    output wire        current_valid,

    // Tag Array Interface
    output wire [5:0]  tag_lookup_index,
    output wire [21:0] tag_lookup_tag,
    input wire         tag_hit,
    input wire         tag_dirty_out,
    input wire [21:0]  tag_evict_tag_out,
    output reg         tag_update_valid,
    output reg [5:0]   tag_update_index,
    output reg [21:0]  tag_update_tag,
    output reg         tag_flush_all,
    output reg         tag_dirty_set,
    output reg         tag_dirty_clear,
    output reg [5:0]   tag_dirty_index,

    // Data Array Interface
    output wire [5:0]  data_read_index,
    output wire [1:0]  data_read_offset,
    input wire [31:0]  data_read_data,
    output reg         data_write_enable,
    output reg [5:0]   data_write_index,
    output reg [1:0]   data_write_offset,
    output reg [31:0]  data_write_data,
    output reg [3:0]   data_write_strb,

    // Read-All Interface (eviction)
    output wire [5:0]  data_read_all_index,
    input wire [31:0]  data_read_word_0,
    input wire [31:0]  data_read_word_1,
    input wire [31:0]  data_read_word_2,
    input wire [31:0]  data_read_word_3,

    // AXI Refill Interface
    output reg [31:0]  refill_addr,
    output reg         refill_start,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,

    // AXI Eviction Interface
    output reg [31:0]  evict_addr,
    output reg [31:0]  evict_data_0,
    output reg [31:0]  evict_data_1,
    output reg [31:0]  evict_data_2,
    output reg [31:0]  evict_data_3,
    output reg         evict_start,
    input wire         evict_busy,
    input wire         evict_done,

    // Statistics
    output reg [31:0]  stat_hits,
    output reg [31:0]  stat_misses,
    output reg [31:0]  stat_writes
);

    // =========================================================================
    // Registered request (dùng khi MISS — cần lưu qua nhiều cycles)
    // =========================================================================
    reg [31:0] cur_addr;
    reg [31:0] cur_wdata;
    reg [3:0]  cur_wstrb;
    reg        cur_we;

    assign current_addr  = cur_addr;
    assign current_data  = cur_wdata;
    assign current_valid = (state != `DCACHE_STATE_IDLE);

    // =========================================================================
    // OPT-1: Dual-mode address decomposition
    // IDLE: dùng cpu_addr trực tiếp để check tag (1-cycle hit)
    // Các state khác: dùng cur_addr (registered, stable)
    // =========================================================================
    reg [2:0] state, next_state;

    wire idle_hit_check = (state == `DCACHE_STATE_IDLE) && cpu_req && !fence;

    wire [31:0] lookup_addr   = idle_hit_check ? cpu_addr  : cur_addr;
    wire [21:0] lookup_tag_w  = lookup_addr[31:10];
    wire [5:0]  lookup_index  = lookup_addr[9:4];
    wire [1:0]  lookup_offset = lookup_addr[3:2];

    wire [21:0] cur_tag    = cur_addr[31:10];
    wire [5:0]  cur_index  = cur_addr[9:4];
    wire [1:0]  cur_offset = cur_addr[3:2];

    assign tag_lookup_index    = lookup_index;
    assign tag_lookup_tag      = lookup_tag_w;
    assign data_read_index     = lookup_index;
    assign data_read_offset    = lookup_offset;
    assign data_read_all_index = cur_index;  // eviction dùng cur_addr

    // =========================================================================
    // FIX-BUG-LOOKUP: Tag lookup stability tracking
    // Tag array là synchronous: kết quả (tag_hit, tag_dirty_out, tag_evict_tag_out)
    // chỉ valid SAU 1 clock edge kể từ khi lookup_index/lookup_tag được drive.
    //
    // Khi IDLE → LOOKUP transition xảy ra:
    //   - Cycle IDLE cuối: idle_hit_check = 1 → tag array nhận cpu_addr
    //   - Cycle LOOKUP đầu: idle_hit_check = 0 → tag array nhận cur_addr
    //     Nhưng TAG_HIT lúc này vẫn là kết quả từ cpu_addr (IDLE cycle) → SAI
    //   - Cycle LOOKUP thứ 2: tag_hit mới đúng với cur_addr
    //
    // tag_lookup_stable = 1 khi tag array đã có đủ 1 cycle để compute với cur_addr.
    // LOOKUP state chỉ ra quyết định evict/refill khi tag_lookup_stable = 1.
    // =========================================================================
    reg tag_lookup_stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tag_lookup_stable <= 1'b0;
        else if (state == `DCACHE_STATE_IDLE)
            // Reset khi về IDLE, sẵn sàng cho miss tiếp theo
            tag_lookup_stable <= 1'b0;
        else if (state == `DCACHE_STATE_LOOKUP)
            // Sau 1 cycle trong LOOKUP, tag array đã stable
            tag_lookup_stable <= 1'b1;
        else
            tag_lookup_stable <= 1'b0;
    end

    // =========================================================================
    // State Machine
    // =========================================================================
    reg [5:0]  refill_index_r;
    reg [21:0] refill_tag_r;
    reg [1:0]  requested_offset;
    reg [31:0] requested_data;
    reg        requested_data_ready;
    reg [5:0]  evict_index_r;
    reg        pending_write;

    // ─── Sequential: state ───────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     state <= `DCACHE_STATE_IDLE;
        else if (fence) state <= `DCACHE_STATE_IDLE;
        else            state <= next_state;
    end

    // ─── Combinational: next-state ───────────────────────────────────────────
    always @(*) begin
        next_state = state;
        case (state)

            `DCACHE_STATE_IDLE: begin
                if (cpu_req && !fence) begin
                    if (tag_hit)
                        next_state = `DCACHE_STATE_IDLE;
                    else
                        next_state = `DCACHE_STATE_LOOKUP;
                end
            end

            // FIX-BUG-LOOKUP: Chỉ ra quyết định khi tag_lookup_stable = 1
            // (tag array đã có 1 full cycle với cur_addr làm input)
            `DCACHE_STATE_LOOKUP: begin
                if (tag_lookup_stable) begin
                    if (tag_hit)
                        next_state = `DCACHE_STATE_IDLE;
                    else begin
                        if (tag_dirty_out)
                            next_state = `DCACHE_STATE_EVICT;
                        else
                            next_state = `DCACHE_STATE_REFILL;
                    end
                end
                // Nếu !tag_lookup_stable: giữ nguyên LOOKUP, chờ thêm 1 cycle
            end

            `DCACHE_STATE_EVICT: begin
                if (evict_done) next_state = `DCACHE_STATE_WAIT;
            end

            `DCACHE_STATE_WAIT: begin
                next_state = `DCACHE_STATE_REFILL;
            end

            // FIX-BUG2: refill_done assert cùng cycle với beat cuối
            // → check (refill_data_valid & refill_done & word==requested) cùng lúc possible
            `DCACHE_STATE_REFILL: begin
                if (!cur_we && refill_data_valid && (refill_word == requested_offset)) begin
                    // CWF: critical word arrived
                    if (refill_done)
                        next_state = `DCACHE_STATE_IDLE;         // last beat = critical word
                    else
                        next_state = `DCACHE_STATE_REFILL_DRAIN; // drain nốt
                end else if (cur_we && refill_done) begin
                    // Write miss: refill xong, write sẽ được apply
                    next_state = `DCACHE_STATE_IDLE;
                end else if (!cur_we && refill_done && requested_data_ready) begin
                    // Read miss fallback: critical word đã capture trước
                    next_state = `DCACHE_STATE_IDLE;
                end
            end

            `DCACHE_STATE_REFILL_DRAIN: begin
                if (refill_done) next_state = `DCACHE_STATE_IDLE;
            end

            default: next_state = `DCACHE_STATE_IDLE;
        endcase
    end

    // ─── Combinational: CPU output ───────────────────────────────────────────
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;

    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;

        case (state)

            // OPT-1: HIT tại IDLE — 1 cycle latency
            `DCACHE_STATE_IDLE: begin
                if (cpu_req && tag_hit && !fence) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = cpu_we ? 32'h0 : data_read_data;
                end
            end

            // FIX-BUG-LOOKUP: Chỉ serve hit khi tag_lookup_stable = 1
            `DCACHE_STATE_LOOKUP: begin
                if (tag_lookup_stable && tag_hit) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = cur_we ? 32'h0 : data_read_data;
                end
            end

            // OPT-2: REFILL — Critical-Word-First
            `DCACHE_STATE_REFILL: begin
                if (!cur_we && refill_data_valid && (refill_word == requested_offset)) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = refill_data;  // directly from AXI bus
                end else if (cur_we && refill_done) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = 32'h0;
                end else if (!cur_we && refill_done && requested_data_ready) begin
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = requested_data;
                end
            end

            `DCACHE_STATE_REFILL_DRAIN: ;  // CPU không nhận thêm ready

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
            cur_addr             <= 32'h0;
            cur_wdata            <= 32'h0;
            cur_wstrb            <= 4'h0;
            cur_we               <= 1'b0;
            refill_addr          <= 32'h0;
            refill_start         <= 1'b0;
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
            evict_start          <= 1'b0;
            evict_index_r        <= 6'h0;
            pending_write        <= 1'b0;
            tag_update_valid     <= 1'b0;
            tag_update_index     <= 6'h0;
            tag_update_tag       <= 22'h0;
            tag_flush_all        <= 1'b0;
            tag_dirty_set        <= 1'b0;
            tag_dirty_clear      <= 1'b0;
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
            refill_start      <= 1'b0;
            evict_start       <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            tag_dirty_set     <= 1'b0;
            tag_dirty_clear   <= 1'b0;
            data_write_enable <= 1'b0;

            if (fence) tag_flush_all <= 1'b1;

            case (state)
                // =============================================================
                // IDLE: OPT-1 — serve hit ngay nếu có
                // =============================================================
                `DCACHE_STATE_IDLE: begin
                    requested_data_ready <= 1'b0;
                    pending_write        <= 1'b0;

                    if (cpu_req && !fence) begin
                        if (tag_hit) begin
                            // HIT tại IDLE
                            if (cpu_we) begin
                                stat_writes <= stat_writes + 1;
                                stat_hits   <= stat_hits + 1;
                                data_write_enable <= 1'b1;
                                data_write_index  <= lookup_index;
                                data_write_offset <= lookup_offset;
                                data_write_data   <= cpu_wdata;
                                data_write_strb   <= cpu_wstrb;
                                tag_dirty_set     <= 1'b1;
                                tag_dirty_index   <= lookup_index;
                            end else begin
                                stat_hits <= stat_hits + 1;
                            end
                        end else begin
                            // MISS: latch và vào LOOKUP
                            cur_addr  <= cpu_addr;
                            cur_wdata <= cpu_wdata;
                            cur_wstrb <= cpu_wstrb;
                            cur_we    <= cpu_we;
                        end
                    end
                end

                // =============================================================
                // LOOKUP: chỉ vào khi MISS từ IDLE (cur_addr đã latch)
                // FIX-BUG-LOOKUP: Chỉ act khi tag_lookup_stable = 1
                //   Cycle 1 trong LOOKUP: tag array đang compute với cur_addr
                //                         → chờ, không làm gì
                //   Cycle 2 trong LOOKUP: tag_lookup_stable = 1, tag_hit valid
                //                         → ra quyết định evict hoặc refill
                // =============================================================
                `DCACHE_STATE_LOOKUP: begin
                    if (tag_lookup_stable) begin
                        if (tag_hit) begin
                            // Forwarding hit — handle safe
                            if (cur_we) begin
                                stat_writes <= stat_writes + 1;
                                stat_hits   <= stat_hits + 1;
                                data_write_enable <= 1'b1;
                                data_write_index  <= cur_index;
                                data_write_offset <= cur_offset;
                                data_write_data   <= cur_wdata;
                                data_write_strb   <= cur_wstrb;
                                tag_dirty_set     <= 1'b1;
                                tag_dirty_index   <= cur_index;
                            end else begin
                                stat_hits <= stat_hits + 1;
                            end
                        end else begin
                            // MISS — kick eviction hoặc refill
                            stat_misses <= stat_misses + 1;
                            if (cur_we) stat_writes <= stat_writes + 1;

                            refill_index_r   <= cur_index;
                            refill_tag_r     <= cur_tag;
                            requested_offset <= cur_offset;
                            pending_write    <= cur_we;

                            if (tag_dirty_out) begin
                                evict_addr    <= {tag_evict_tag_out, cur_index, 4'b0000};
                                evict_data_0  <= data_read_word_0;
                                evict_data_1  <= data_read_word_1;
                                evict_data_2  <= data_read_word_2;
                                evict_data_3  <= data_read_word_3;
                                evict_index_r <= cur_index;
                                evict_start   <= 1'b1;
                            end else begin
                                refill_addr  <= {cur_addr[31:4], 4'b0000};
                                refill_start <= 1'b1;
                                // NOTE: refill_addr được set ở đây (nonblocking).
                                // axi_interface có RD_LATCH để đọc đúng cycle sau.
                            end
                        end
                    end
                    // Nếu !tag_lookup_stable: không làm gì, chờ cycle tiếp
                end

                // =============================================================
                // EVICT: chờ AXI burst write
                // =============================================================
                `DCACHE_STATE_EVICT: begin
                    if (evict_done) begin
                        tag_dirty_clear <= 1'b1;
                        tag_dirty_index <= evict_index_r;
                    end
                end

                // =============================================================
                // WAIT: kick refill sau khi evict xong
                // =============================================================
                `DCACHE_STATE_WAIT: begin
                    refill_addr  <= {cur_addr[31:4], 4'b0000};
                    refill_start <= 1'b1;
                    // axi_interface RD_LATCH sẽ đọc refill_addr cycle tiếp
                end

                // =============================================================
                // REFILL: nhận burst, OPT-2 Critical-Word-First
                // FIX-BUG2: refill_done có thể assert cùng cycle refill_data_valid
                //           (khi critical word = beat cuối) — handle đúng
                // FIX-BUG3: Write-allocate — tag_dirty_set phải được assert
                //           CÙNG CYCLE với tag_update_valid khi pending_write=1
                // =============================================================
                `DCACHE_STATE_REFILL: begin
                    if (refill_data_valid) begin
                        // Ghi từng word vào cache khi nhận từ AXI
                        data_write_enable <= 1'b1;
                        data_write_index  <= refill_index_r;
                        data_write_offset <= refill_word;
                        data_write_data   <= refill_data;
                        data_write_strb   <= 4'b1111;

                        // Capture word CPU cần (cho fallback path)
                        if (refill_word == requested_offset && !requested_data_ready) begin
                            requested_data       <= refill_data;
                            requested_data_ready <= 1'b1;
                        end
                    end

                    if (refill_done) begin
                        // Burst xong: update tag
                        tag_update_valid <= 1'b1;
                        tag_update_index <= refill_index_r;
                        tag_update_tag   <= refill_tag_r;

                        if (pending_write) begin
                            // Write-allocate: apply store vào cache
                            data_write_enable <= 1'b1;
                            data_write_index  <= refill_index_r;
                            data_write_offset <= requested_offset;
                            data_write_data   <= cur_wdata;
                            data_write_strb   <= cur_wstrb;
                            // FIX-BUG3: dirty_set CÙNG CYCLE với tag_update_valid
                            tag_dirty_set     <= 1'b1;
                            tag_dirty_index   <= refill_index_r;
                            pending_write     <= 1'b0;
                        end
                    end
                end

                // =============================================================
                // REFILL_DRAIN: CPU đã resume, drain nốt burst
                // =============================================================
                `DCACHE_STATE_REFILL_DRAIN: begin
                    if (refill_data_valid) begin
                        data_write_enable <= 1'b1;
                        data_write_index  <= refill_index_r;
                        data_write_offset <= refill_word;
                        data_write_data   <= refill_data;
                        data_write_strb   <= 4'b1111;
                    end

                    if (refill_done) begin
                        // Tất cả words đã nhận → update tag
                        tag_update_valid <= 1'b1;
                        tag_update_index <= refill_index_r;
                        tag_update_tag   <= refill_tag_r;
                        // CWF chỉ cho read miss (cur_we=0), không có pending_write
                    end
                end

                default: ;
            endcase
        end
    end

endmodule