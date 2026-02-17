// ============================================================================
// Module: dcache_controller
// ============================================================================
// Description:
//   Main data cache controller with read/write support
//   - Write-through policy (all writes go to memory)
//   - Read miss triggers cache line refill
//   - Write hit: update cache + write-through
//   - Write miss: write-through only (no refill)
//
// FIXES so với version cũ:
//   FIX-1: Latch cpu_addr/cpu_wdata/cpu_wstrb/cpu_we ngay tại IDLE khi
//          cpu_req assert. Toàn bộ FSM dùng registered copy (cur_*) thay
//          vì live cpu_* signals → tránh data/addr thay đổi giữa chừng.
//   FIX-2: Tag lookup và data array read dùng cur_addr (registered) thay
//          vì cpu_addr trực tiếp → index/tag luôn đúng xuyên suốt FSM.
//   FIX-3: Thêm output port current_addr và current_data để expose trạng
//          thái đang xử lý ra ngoài cho debug và kết nối upstream.
//   FIX-4: Sửa DCACHE_NUM_LINES comment (512 vs 64 mismatch trong defines).
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
    input wire        cpu_we,           // 1=write, 0=read
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,
    input wire        fence,

    // ========================================================================
    // FIX-3: Expose current request đang được xử lý ra ngoài
    // Cho phép upstream (LSU, debug unit) biết controller đang xử lý gì
    // ========================================================================
    output wire [31:0] current_addr,    // Địa chỉ của request đang xử lý
    output wire [31:0] current_data,    // Data của request đang xử lý (store)
    output wire        current_valid,   // 1 khi FSM đang xử lý request (không ở IDLE)

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

    // AXI Refill Interface (for read misses)
    output reg [31:0]  refill_addr,
    output reg         refill_start,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [1:0]   refill_word,
    input wire         refill_data_valid,

    // AXI Write-Through Interface (for writes)
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

    // ========================================================================
    // FIX-1: Registered request - latch khi IDLE nhận cpu_req
    // Dùng cur_* xuyên suốt FSM thay vì live cpu_* signals
    // ========================================================================
    reg [31:0] cur_addr;    // Địa chỉ đã được latch
    reg [31:0] cur_wdata;   // Write data đã được latch
    reg [3:0]  cur_wstrb;   // Write strobe đã được latch
    reg        cur_we;      // Write enable đã được latch

    // FIX-3: Expose ra ngoài
    assign current_addr  = cur_addr;
    assign current_data  = cur_wdata;
    assign current_valid = (state != `DCACHE_STATE_IDLE);

    // ========================================================================
    // FIX-2: Address Decomposition từ cur_addr (registered, không phải live)
    // ========================================================================
    wire [21:0] cur_tag;
    wire [5:0]  cur_index;
    wire [1:0]  cur_offset;

    assign cur_tag    = cur_addr[31:10];
    assign cur_index  = cur_addr[9:4];
    assign cur_offset = cur_addr[3:2];

    // ========================================================================
    // Tag Array Lookup - dùng cur_addr để index/tag ổn định khi FSM chạy
    // ========================================================================
    assign tag_lookup_index = cur_index;
    assign tag_lookup_tag   = cur_tag;

    // ========================================================================
    // Data Array Read - tương tự dùng cur_addr
    // ========================================================================
    assign data_read_index  = cur_index;
    assign data_read_offset = cur_offset;

    // ========================================================================
    // State Machine
    // ========================================================================
    reg [2:0] state, next_state;

    // Refill tracking
    reg [5:0]  refill_index_r;
    reg [21:0] refill_tag_r;
    reg [1:0]  requested_offset;
    reg [31:0] requested_data;
    reg        requested_data_ready;

    // ========================================================================
    // State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= `DCACHE_STATE_IDLE;
        end else if (fence) begin
            state <= `DCACHE_STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ========================================================================
    // State Machine - Combinational (Next State Logic)
    // ========================================================================
    always @(*) begin
        next_state = state;

        case (state)
            `DCACHE_STATE_IDLE: begin
                if (cpu_req) begin
                    next_state = `DCACHE_STATE_LOOKUP;
                end
            end

            `DCACHE_STATE_LOOKUP: begin
                if (!cpu_req && !cur_we) begin
                    // Request dropped trước khi xử lý xong
                    next_state = `DCACHE_STATE_IDLE;
                end else if (cur_we) begin
                    // Write: luôn write-through
                    next_state = `DCACHE_STATE_WRITE_THRU;
                end else begin
                    // Read
                    if (tag_hit) begin
                        next_state = `DCACHE_STATE_IDLE;  // Hit: done ngay
                    end else begin
                        next_state = `DCACHE_STATE_REFILL; // Miss: refill
                    end
                end
            end

            `DCACHE_STATE_REFILL: begin
                if (refill_done) begin
                    next_state = `DCACHE_STATE_IDLE;
                end
            end

            `DCACHE_STATE_WRITE_THRU: begin
                if (wt_done) begin
                    next_state = `DCACHE_STATE_IDLE;
                end
            end

            default: next_state = `DCACHE_STATE_IDLE;
        endcase
    end

    // ========================================================================
    // CPU Output - Combinational
    // ========================================================================
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;

    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;

        case (state)
            `DCACHE_STATE_LOOKUP: begin
                if (!cur_we && tag_hit) begin
                    // Read hit: trả data ngay từ data array
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = data_read_data;
                end
            end

            `DCACHE_STATE_REFILL: begin
                if (refill_done) begin
                    // Read miss complete: trả data đã được capture
                    cpu_ready_int = 1'b1;
                    cpu_rdata_int = requested_data;
                end
            end

            `DCACHE_STATE_WRITE_THRU: begin
                if (wt_done) begin
                    // Write complete
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

    // ========================================================================
    // State Machine - Sequential Output Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // FIX-1: Reset registered request
            cur_addr              <= 32'h0;
            cur_wdata             <= 32'h0;
            cur_wstrb             <= 4'h0;
            cur_we                <= 1'b0;

            // Refill control
            refill_addr           <= 32'h0;
            refill_start          <= 1'b0;
            refill_index_r        <= 6'h0;
            refill_tag_r          <= 22'h0;
            requested_offset      <= 2'b00;
            requested_data        <= 32'h0;
            requested_data_ready  <= 1'b0;

            // Write-through control
            wt_addr               <= 32'h0;
            wt_data               <= 32'h0;
            wt_strb               <= 4'h0;
            wt_start              <= 1'b0;

            // Tag array control
            tag_update_valid      <= 1'b0;
            tag_update_index      <= 6'h0;
            tag_update_tag        <= 22'h0;
            tag_flush_all         <= 1'b0;

            // Data array control
            data_write_enable     <= 1'b0;
            data_write_index      <= 6'h0;
            data_write_offset     <= 2'b00;
            data_write_data       <= 32'h0;
            data_write_strb       <= 4'h0;

            // Statistics
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

            // Fence: invalidate all
            if (fence) begin
                tag_flush_all <= 1'b1;
            end

            case (state)
                // ============================================================
                // IDLE: Chờ request mới
                // FIX-1: Latch cpu_* vào cur_* ngay khi nhận request
                // ============================================================
                `DCACHE_STATE_IDLE: begin
                    requested_data_ready <= 1'b0;

                    if (cpu_req) begin
                        // Latch request để các state sau dùng → tránh live signal thay đổi
                        cur_addr  <= cpu_addr;
                        cur_wdata <= cpu_wdata;
                        cur_wstrb <= cpu_wstrb;
                        cur_we    <= cpu_we;
                    end
                end

                // ============================================================
                // LOOKUP: Tag check xong, quyết định hit/miss/write
                // Dùng cur_* (đã latch) thay vì cpu_* trực tiếp
                // ============================================================
                `DCACHE_STATE_LOOKUP: begin
                    if (cur_we) begin
                        // WRITE: chuẩn bị write-through
                        stat_writes <= stat_writes + 1;

                        wt_addr  <= cur_addr;   // FIX-1: dùng cur_addr
                        wt_data  <= cur_wdata;  // FIX-1: dùng cur_wdata
                        wt_strb  <= cur_wstrb;
                        wt_start <= 1'b1;

                        // Write hit: cập nhật cache luôn
                        if (tag_hit) begin
                            data_write_enable <= 1'b1;
                            data_write_index  <= cur_index;
                            data_write_offset <= cur_offset;
                            data_write_data   <= cur_wdata;
                            data_write_strb   <= cur_wstrb;
                        end
                        // Write miss: chỉ write-through, không refill cache

                    end else begin
                        // READ
                        if (tag_hit) begin
                            stat_hits <= stat_hits + 1;
                            // cpu_rdata được trả combinationally từ data array
                        end else begin
                            // Read miss: bắt đầu refill
                            stat_misses      <= stat_misses + 1;

                            refill_addr      <= {cur_addr[31:4], 4'b0000}; // FIX-1: line-aligned từ cur_addr
                            refill_index_r   <= cur_index;
                            refill_tag_r     <= cur_tag;
                            requested_offset <= cur_offset;
                            refill_start     <= 1'b1;
                        end
                    end
                end

                // ============================================================
                // REFILL: Đợi AXI burst trả đủ cache line
                // ============================================================
                `DCACHE_STATE_REFILL: begin
                    if (refill_data_valid) begin
                        // Ghi từng word vào data array
                        data_write_enable <= 1'b1;
                        data_write_index  <= refill_index_r;
                        data_write_offset <= refill_word;
                        data_write_data   <= refill_data;
                        data_write_strb   <= 4'b1111;

                        // Capture word mà CPU yêu cầu
                        if (refill_word == requested_offset && !requested_data_ready) begin
                            requested_data       <= refill_data;
                            requested_data_ready <= 1'b1;
                        end
                    end

                    if (refill_done) begin
                        // Đánh dấu line valid trong tag array
                        tag_update_valid <= 1'b1;
                        tag_update_index <= refill_index_r;
                        tag_update_tag   <= refill_tag_r;
                    end
                end

                // ============================================================
                // WRITE_THRU: Chờ AXI write response
                // wt_done được handle ở combinational output
                // ============================================================
                `DCACHE_STATE_WRITE_THRU: begin
                    // Không cần làm gì thêm, wt_busy/wt_done từ AXI interface
                end

                default: ; // No action
            endcase
        end
    end

endmodule