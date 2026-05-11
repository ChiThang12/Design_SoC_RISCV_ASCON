// // ============================================================================
// // icache_controller — 8 words/line, index 5 bit, offset 3 bit
// // ============================================================================
// module icache_controller (
//     input wire clk,
//     input wire rst_n,

//     input wire [31:0]  cpu_addr,
//     input wire         cpu_req,
//     output wire [31:0] cpu_rdata,
//     output wire        cpu_ready,
//     input wire         flush,

//     output wire [4:0]  tag_lookup_index,   // 5 bit
//     output wire [21:0] tag_lookup_tag,
//     input wire         tag_hit,
//     output reg         tag_update_valid,
//     output reg [4:0]   tag_update_index,   // 5 bit
//     output reg [21:0]  tag_update_tag,
//     output reg         tag_flush_all,

//     output wire [4:0]  data_read_index,    // 5 bit
//     output wire [2:0]  data_read_offset,   // 3 bit
//     input wire [31:0]  data_read_data,
//     output reg         data_write_enable,
//     output reg [4:0]   data_write_index,   // 5 bit
//     output reg [2:0]   data_write_offset,  // 3 bit
//     output reg [31:0]  data_write_data,

//     output wire [31:0] refill_addr,
//     output wire        refill_start,
//     input wire         refill_busy,
//     input wire         refill_done,
//     input wire [31:0]  refill_data,
//     input wire [2:0]   refill_word,        // 3 bit
//     input wire         refill_data_valid,

//     output reg [31:0]  stat_hits,
//     output reg [31:0]  stat_misses
// );

//     // =========================================================================
//     // Address decomposition — LINE_SIZE=32 bytes
//     // [31:10] tag=22bit  [9:5] index=5bit  [4:2] offset=3bit  [1:0]=00
//     // =========================================================================
//     wire [21:0] cpu_tag    = cpu_addr[31:10];
//     wire [4:0]  cpu_index  = cpu_addr[9:5];
//     wire [2:0]  cpu_offset = cpu_addr[4:2];
//     wire [31:0] cpu_line_addr = {cpu_addr[31:5], 5'b00000};  // align 32 bytes

//     // =========================================================================
//     // Shadow valid/tag — 32 lines
//     // =========================================================================
//     reg        ctrl_valid [0:31];
//     reg [21:0] ctrl_tag   [0:31];

//     wire ctrl_hit = ctrl_valid[cpu_index] && (ctrl_tag[cpu_index] == cpu_tag);

//     assign tag_lookup_index = cpu_index;
//     assign tag_lookup_tag   = cpu_tag;
//     assign data_read_index  = cpu_index;
//     assign data_read_offset = cpu_offset;

//     // =========================================================================
//     // Prefetch engine
//     // =========================================================================
//     reg [31:0] pf_ptr;      // line-aligned, bước 32 bytes
//     reg [4:0]  pf_index;
//     reg [21:0] pf_tag;
//     reg        pf_active;

//     wire [4:0]  pf_ptr_index = pf_ptr[9:5];
//     wire [21:0] pf_ptr_tag   = pf_ptr[31:10];

//     wire pf_ptr_cached = ctrl_valid[pf_ptr_index] &&
//                          (ctrl_tag[pf_ptr_index] == pf_ptr_tag);

//     wire cpu_miss = cpu_req && !ctrl_hit;

//     wire loading_cpu_line = pf_active &&
//                             (pf_index == cpu_index) &&
//                             (pf_tag   == cpu_tag);

//     assign refill_addr  = cpu_miss ? cpu_line_addr : pf_ptr;
//     assign refill_start = !refill_busy && !pf_active &&
//                           (cpu_miss || !pf_ptr_cached);

//     // =========================================================================
//     // CPU stall capture
//     // =========================================================================
//     reg [31:0] stall_data;
//     reg        stall_data_rdy;

//     // =========================================================================
//     // CPU output
//     // =========================================================================
//     reg        cpu_ready_int;
//     reg [31:0] cpu_rdata_int;

//     always @(*) begin
//         cpu_ready_int = 1'b0;
//         cpu_rdata_int = 32'h0;
//         if (cpu_req) begin
//             if (ctrl_hit) begin
//                 cpu_ready_int = 1'b1;
//                 cpu_rdata_int = data_read_data;
//             end else if (loading_cpu_line && stall_data_rdy && refill_done) begin
//                 cpu_ready_int = 1'b1;
//                 cpu_rdata_int = stall_data;
//             end
//         end
//     end

//     assign cpu_ready = cpu_ready_int;
//     assign cpu_rdata = cpu_rdata_int;

//     // =========================================================================
//     // Sequential
//     // =========================================================================
//     integer i;

//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             pf_ptr            <= 32'h0;
//             pf_index          <= 5'h0;
//             pf_tag            <= 22'h0;
//             pf_active         <= 1'b0;
//             stall_data        <= 32'h0;
//             stall_data_rdy    <= 1'b0;
//             tag_update_valid  <= 1'b0;
//             tag_update_index  <= 5'h0;
//             tag_update_tag    <= 22'h0;
//             tag_flush_all     <= 1'b0;
//             data_write_enable <= 1'b0;
//             data_write_index  <= 5'h0;
//             data_write_offset <= 3'h0;
//             data_write_data   <= 32'h0;
//             stat_hits         <= 32'h0;
//             stat_misses       <= 32'h0;
//             for (i = 0; i < 32; i = i + 1) begin
//                 ctrl_valid[i] <= 1'b0;
//                 ctrl_tag[i]   <= 22'h0;
//             end

//         end else begin
//             tag_update_valid  <= 1'b0;
//             tag_flush_all     <= 1'b0;
//             data_write_enable <= 1'b0;

//             if (flush) begin
//                 tag_flush_all  <= 1'b1;
//                 pf_active      <= 1'b0;
//                 pf_ptr         <= cpu_line_addr;
//                 stall_data_rdy <= 1'b0;
//                 for (i = 0; i < 32; i = i + 1)
//                     ctrl_valid[i] <= 1'b0;

//             end else begin

//                 // Phase 1: khởi động load
//                 if (!refill_busy && !pf_active) begin
//                     if (cpu_miss) begin
//                         pf_index       <= cpu_index;
//                         pf_tag         <= cpu_tag;
//                         pf_active      <= 1'b1;
//                         stall_data_rdy <= 1'b0;
//                         stat_misses    <= stat_misses + 1;
//                         pf_ptr         <= cpu_line_addr + 32'd32; // bước 32 bytes
//                     end else if (pf_ptr_cached) begin
//                         pf_ptr <= pf_ptr + 32'd32;
//                     end else begin
//                         pf_index  <= pf_ptr_index;
//                         pf_tag    <= pf_ptr_tag;
//                         pf_active <= 1'b1;
//                         pf_ptr    <= pf_ptr + 32'd32;
//                     end
//                 end

//                 // Phase 2: nhận data
//                 if (refill_data_valid) begin
//                     data_write_enable <= 1'b1;
//                     data_write_index  <= pf_index;
//                     data_write_offset <= refill_word;
//                     data_write_data   <= refill_data;

//                     if (loading_cpu_line && !stall_data_rdy &&
//                         refill_word == cpu_offset) begin
//                         stall_data     <= refill_data;
//                         stall_data_rdy <= 1'b1;
//                     end
//                 end

//                 // Phase 3: xong 1 line
//                 if (refill_done) begin
//                     tag_update_valid     <= 1'b1;
//                     tag_update_index     <= pf_index;
//                     tag_update_tag       <= pf_tag;
//                     ctrl_valid[pf_index] <= 1'b1;
//                     ctrl_tag[pf_index]   <= pf_tag;
//                     pf_active            <= 1'b0;
//                     stall_data_rdy       <= 1'b0;
//                 end

//                 if (cpu_req && ctrl_hit)
//                     stat_hits <= stat_hits + 1;
//             end
//         end
//     end
// endmodule

// ============================================================================
// icache_controller — 8 words/line, index 5 bit, offset 3 bit
// ============================================================================
module icache_controller (
    input wire clk,
    input wire rst_n,

    input wire [31:0]  cpu_addr,
    input wire         cpu_req,
    output wire [31:0] cpu_rdata,
    output wire        cpu_ready,
    input wire         flush,

    output wire [4:0]  tag_lookup_index,   // 5 bit
    output wire [21:0] tag_lookup_tag,
    input wire         tag_hit,
    output reg         tag_update_valid,
    output reg [4:0]   tag_update_index,   // 5 bit
    output reg [21:0]  tag_update_tag,
    output reg         tag_flush_all,

    output wire [4:0]  data_read_index,    // 5 bit
    output wire [2:0]  data_read_offset,   // 3 bit
    input wire [31:0]  data_read_data,
    output reg         data_write_enable,
    output reg [4:0]   data_write_index,   // 5 bit
    output reg [2:0]   data_write_offset,  // 3 bit
    output reg [31:0]  data_write_data,

    output wire [31:0] refill_addr,
    output wire        refill_start,
    input wire         refill_busy,
    input wire         refill_done,
    input wire [31:0]  refill_data,
    input wire [2:0]   refill_word,        // 3 bit
    input wire         refill_data_valid,

    output reg [31:0]  stat_hits,
    output reg [31:0]  stat_misses
);

    // =========================================================================
    // IMEM address limit — pf_ptr wraps here to prevent DECERR on AXI crossbar
    // Default: 8 KB (matches inst_mem.v MEM_DEPTH=1024 words)
    // =========================================================================
    parameter IMEM_LIMIT = 32'h00002000;

    // =========================================================================
    // Address decomposition — LINE_SIZE=32 bytes
    // [31:10] tag=22bit  [9:5] index=5bit  [4:2] offset=3bit  [1:0]=00
    // =========================================================================
    wire [21:0] cpu_tag    = cpu_addr[31:10];
    wire [4:0]  cpu_index  = cpu_addr[9:5];
    wire [2:0]  cpu_offset = cpu_addr[4:2];
    wire [31:0] cpu_line_addr = {cpu_addr[31:5], 5'b00000};  // align 32 bytes

    // Wrapped next pf_ptr values — prevent prefetcher from crossing IMEM boundary
    wire [31:0] pf_ptr_next    = (pf_ptr + 32'd32 >= IMEM_LIMIT) ? 32'h0 : pf_ptr + 32'd32;
    wire [31:0] cpu_line_next  = (cpu_line_addr + 32'd32 >= IMEM_LIMIT) ? 32'h0 : cpu_line_addr + 32'd32;

    // =========================================================================
    // Shadow valid/tag — 32 lines
    // =========================================================================
    reg        ctrl_valid [0:31];
    reg [21:0] ctrl_tag   [0:31];

    // FIX: ctrl_hit_committed = line đang được commit ngay cycle này
    // Khi refill_done=1, ctrl_valid[pf_index] chưa kịp update (registered lag),
    // nhưng ta biết line đó đã xong → tính là hit ngay để tránh cpu_miss=1 sai.
    wire line_just_done = refill_done &&
                          (pf_index == cpu_index) &&
                          (pf_tag   == cpu_tag);

    // FIX-ALIAS: Prefetcher đang ghi một line KHÁC vào cùng set với CPU.
    // Trong cửa sổ này, ctrl_tag chưa update nhưng data_array đang bị overwrite
    // word-by-word với dữ liệu sai (NOP từ vùng ngoài chương trình).
    // → Buộc cpu_miss=1 để CPU đợi prefetch xong rồi mới demand-fill đúng line.
    wire prefetch_aliasing = pf_active &&
                             (pf_index == cpu_index) &&
                             (pf_tag   != cpu_tag);

    wire ctrl_hit = ((ctrl_valid[cpu_index] || line_just_done) &&
                     (ctrl_tag[cpu_index] == cpu_tag || line_just_done)) &&
                    !prefetch_aliasing;

    assign tag_lookup_index = cpu_index;
    assign tag_lookup_tag   = cpu_tag;
    assign data_read_index  = cpu_index;
    assign data_read_offset = cpu_offset;

    // =========================================================================
    // Prefetch engine
    // =========================================================================
    reg [31:0] pf_ptr;      // line-aligned, bước 32 bytes
    reg [4:0]  pf_index;
    reg [21:0] pf_tag;
    reg        pf_active;

    wire [4:0]  pf_ptr_index = pf_ptr[9:5];
    wire [21:0] pf_ptr_tag   = pf_ptr[31:10];

    // FIX: pf_ptr_cached tính cả line vừa được commit
    wire pf_line_just_done = refill_done &&
                             (pf_index == pf_ptr_index) &&
                             (pf_tag   == pf_ptr_tag);
    wire pf_ptr_cached = (ctrl_valid[pf_ptr_index] || pf_line_just_done) &&
                         (ctrl_tag[pf_ptr_index] == pf_ptr_tag || pf_line_just_done);

    wire cpu_miss = cpu_req && !ctrl_hit;

    wire loading_cpu_line = pf_active &&
                            (pf_index == cpu_index) &&
                            (pf_tag   == cpu_tag);

    assign refill_addr  = cpu_miss ? cpu_line_addr : pf_ptr;
    // FIX-NOALIAS-GATE: prefetch không được bắn AR khi sẽ alias một valid line
    // tag khác (phải đồng bộ với Phase 1 always block, nếu không AXI burst vẫn
    // chạy và overwrite data_array[pf_index_cũ]).
    wire pf_would_alias_w = ctrl_valid[pf_ptr_index] &&
                            (ctrl_tag[pf_ptr_index] != pf_ptr_tag);
    wire pf_would_thrash_w = cpu_req && (pf_ptr_index == cpu_index);
    // FIX: bypass pf_active stale khi refill_done=1
    assign refill_start = !refill_busy &&
                          (!pf_active || refill_done) &&
                          (cpu_miss ||
                           (!pf_ptr_cached && !pf_would_alias_w && !pf_would_thrash_w));

    // =========================================================================
    // CPU stall capture
    // =========================================================================
    reg [31:0] stall_data;
    reg        stall_data_rdy;

    // =========================================================================
    // CPU output
    // =========================================================================
    reg        cpu_ready_int;
    reg [31:0] cpu_rdata_int;

    always @(*) begin
        cpu_ready_int = 1'b0;
        cpu_rdata_int = 32'h0;
        if (cpu_req) begin
            if (ctrl_hit) begin
                cpu_ready_int = 1'b1;
                // [FIX-ICACHE-REFILL-READ] On refill completion (line_just_done=1),
                // data array write is non-blocking and hasn't committed yet this cycle.
                // Prefer stall_data (captured directly from AXI) for offsets 0..6,
                // or live refill_data for offset 7 (stall_data_rdy not yet set).
                if (line_just_done && stall_data_rdy)
                    cpu_rdata_int = stall_data;
                else if (line_just_done && refill_data_valid && (refill_word == cpu_offset))
                    cpu_rdata_int = refill_data;
                else
                    cpu_rdata_int = data_read_data;
            end else if (loading_cpu_line && stall_data_rdy && refill_done) begin
                cpu_ready_int = 1'b1;
                cpu_rdata_int = stall_data;
            end
        end
    end

    assign cpu_ready = cpu_ready_int;
    assign cpu_rdata = cpu_rdata_int;

`ifdef DEBUG_STALL
    reg [31:0] icache_dbg_stuck;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) icache_dbg_stuck <= 32'h0;
        else if (cpu_req && !cpu_ready_int) icache_dbg_stuck <= icache_dbg_stuck + 1'b1;
        else icache_dbg_stuck <= 32'h0;
    end
    always @(posedge clk) begin
        if (rst_n && cpu_req && !cpu_ready_int && (icache_dbg_stuck > 32'd30)) begin
            $display("[ICACHE t=%0t stuck=%0d] cpu_addr=%h cpu_idx=%h cpu_tag=%h ctrl_hit=%b ctrl_valid=%b ctrl_tag_match=%b pf_active=%b pf_ptr=%h pf_index=%h pf_tag=%h loading_cpu=%b refill_busy=%b refill_done=%b refill_start=%b line_just_done=%b stall_rdy=%b",
                     $time, icache_dbg_stuck, cpu_addr, cpu_index, cpu_tag,
                     ctrl_hit, ctrl_valid[cpu_index], (ctrl_tag[cpu_index]==cpu_tag),
                     pf_active, pf_ptr, pf_index, pf_tag,
                     loading_cpu_line, refill_busy, refill_done, refill_start,
                     line_just_done, stall_data_rdy);
        end
    end
`endif

    // =========================================================================
    // Sequential
    // =========================================================================
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf_ptr            <= 32'h0;
            pf_index          <= 5'h0;
            pf_tag            <= 22'h0;
            pf_active         <= 1'b0;
            stall_data        <= 32'h0;
            stall_data_rdy    <= 1'b0;
            tag_update_valid  <= 1'b0;
            tag_update_index  <= 5'h0;
            tag_update_tag    <= 22'h0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;
            data_write_index  <= 5'h0;
            data_write_offset <= 3'h0;
            data_write_data   <= 32'h0;
            stat_hits         <= 32'h0;
            stat_misses       <= 32'h0;
            for (i = 0; i < 32; i = i + 1) begin
                ctrl_valid[i] <= 1'b0;
                ctrl_tag[i]   <= 22'h0;
            end

        end else begin
            tag_update_valid  <= 1'b0;
            tag_flush_all     <= 1'b0;
            data_write_enable <= 1'b0;

            if (flush) begin
                tag_flush_all  <= 1'b1;
                pf_active      <= 1'b0;
                pf_ptr         <= cpu_line_addr;
                stall_data_rdy <= 1'b0;
                for (i = 0; i < 32; i = i + 1)
                    ctrl_valid[i] <= 1'b0;

            end else begin

                // Phase 1: khởi động load
                // FIX: điều kiện khớp với assign refill_start
                if (!refill_busy && (!pf_active || refill_done)) begin
                    if (cpu_miss) begin
                        pf_index       <= cpu_index;
                        pf_tag         <= cpu_tag;
                        pf_active      <= 1'b1;
                        stall_data_rdy <= 1'b0;
                        stat_misses    <= stat_misses + 1;
                        pf_ptr         <= cpu_line_next; // FIX-WRAP: wrap at IMEM_LIMIT
                    end else if (pf_ptr_cached) begin
                        pf_ptr <= pf_ptr_next;
                    end else if (cpu_req && pf_ptr_index == cpu_index) begin
                        // FIX-THRASH: prefetch line này sẽ evict set đang dùng bởi CPU
                        // → chỉ advance pf_ptr, không fetch → tránh thrashing vô hạn
                        pf_ptr <= pf_ptr_next;
                    end else if (ctrl_valid[pf_ptr_index] &&
                                 (ctrl_tag[pf_ptr_index] != pf_ptr_tag)) begin
                        // FIX-NOALIAS: line tại set này đã valid với tag khác — KHÔNG
                        // evict bằng prefetch speculative (sẽ phá data_array của CPU
                        // và buộc CPU re-refill loop vô hạn). Chỉ advance pf_ptr.
                        pf_ptr <= pf_ptr_next;
                    end else begin
                        pf_index  <= pf_ptr_index;
                        pf_tag    <= pf_ptr_tag;
                        pf_active <= 1'b1;
                        pf_ptr    <= pf_ptr_next;
                    end
                end

                // Phase 2: nhận data
                if (refill_data_valid) begin
                    data_write_enable <= 1'b1;
                    data_write_index  <= pf_index;
                    data_write_offset <= refill_word;
                    data_write_data   <= refill_data;

                    // FIX-ICACHE-STALLCAP: capture cho CPU khi burst đang load
                    // line CPU cần — kiểm tra index+tag trực tiếp, không phụ thuộc
                    // pf_active (Phase 3 có thể clear pf_active cùng cycle do NBA).
                    if ((pf_index == cpu_index) && (pf_tag == cpu_tag) &&
                        cpu_req && !stall_data_rdy &&
                        (refill_word == cpu_offset)) begin
                        stall_data     <= refill_data;
                        stall_data_rdy <= 1'b1;
                    end
                end

                // Phase 3: xong 1 line
                if (refill_done) begin
                    tag_update_valid     <= 1'b1;
                    tag_update_index     <= pf_index;
                    tag_update_tag       <= pf_tag;
                    ctrl_valid[pf_index] <= 1'b1;
                    ctrl_tag[pf_index]   <= pf_tag;
                    // FIX-ICACHE-PFACT: chỉ clear pf_active nếu Phase 1 KHÔNG vừa
                    // launch refill mới cùng cycle (tránh overwrite pf_active<=1).
                    if (!refill_start)
                        pf_active <= 1'b0;
                    // FIX-ICACHE-STALLCLR: chỉ clear stall_data_rdy khi line vừa
                    // refill đúng là của CPU (CPU consume cùng cycle qua cpu_ready_int).
                    if ((pf_index == cpu_index) && (pf_tag == cpu_tag))
                        stall_data_rdy <= 1'b0;
                end

                if (cpu_req && ctrl_hit)
                    stat_hits <= stat_hits + 1;
            end
        end
    end
endmodule
