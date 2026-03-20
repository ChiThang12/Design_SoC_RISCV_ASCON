// ============================================================================
// Module: dcache_data_array  —  Write-Back version
// ============================================================================
// Không thay đổi so với bản trước — logic đã đúng.
// read_all_index/read_word_{0..3}: đọc toàn bộ 4 words của 1 cache line
// trong cùng một cycle cho eviction burst.
// Write-first forwarding cho cả single-word và all-words read.
// ============================================================================

`include "cache_interface/dcache/dcache_defines.vh"

module dcache_data_array (
    input wire clk,
    input wire rst_n,

    // ── Single-word read (CPU load) ───────────────────────────────────────────
    input wire [5:0]   read_index,
    input wire [1:0]   read_offset,
    output wire [31:0] read_data,

    // ── All-words read (eviction) ─────────────────────────────────────────────
    input wire [5:0]   read_all_index,
    output wire [31:0] read_word_0,
    output wire [31:0] read_word_1,
    output wire [31:0] read_word_2,
    output wire [31:0] read_word_3,

    // ── Write (store hit, refill, write-allocate) ─────────────────────────────
    input wire         write_enable,
    input wire [5:0]   write_index,
    input wire [1:0]   write_offset,
    input wire [31:0]  write_data,
    input wire [3:0]   write_strb
);

    // ========================================================================
    // Storage: 64 lines × 4 words = 256 × 32-bit
    // Flat addr: {index[5:0], offset[1:0]}
    // ========================================================================
    reg [31:0] data_array [0:255];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 256; i = i + 1)
                data_array[i] <= 32'h0;
        end
    end

    // ========================================================================
    // Write Logic (Sequential, byte-enable)
    // ========================================================================
    wire [7:0] write_addr_flat = {write_index, write_offset};

    always @(posedge clk) begin
        if (write_enable) begin
            if (write_strb[0]) data_array[write_addr_flat][7:0]   <= write_data[7:0];
            if (write_strb[1]) data_array[write_addr_flat][15:8]  <= write_data[15:8];
            if (write_strb[2]) data_array[write_addr_flat][23:16] <= write_data[23:16];
            if (write_strb[3]) data_array[write_addr_flat][31:24] <= write_data[31:24];
        end
    end

    // ========================================================================
    // Single-word Read (Combinational, write-first forwarding)
    // ========================================================================
    wire [7:0]  read_addr_flat = {read_index, read_offset};
    wire        addr_collision = write_enable && (write_addr_flat == read_addr_flat);
    wire [31:0] raw_read       = data_array[read_addr_flat];

    assign read_data[7:0]   = (addr_collision && write_strb[0]) ? write_data[7:0]   : raw_read[7:0];
    assign read_data[15:8]  = (addr_collision && write_strb[1]) ? write_data[15:8]  : raw_read[15:8];
    assign read_data[23:16] = (addr_collision && write_strb[2]) ? write_data[23:16] : raw_read[23:16];
    assign read_data[31:24] = (addr_collision && write_strb[3]) ? write_data[31:24] : raw_read[31:24];

    // ========================================================================
    // All-words Read (Combinational — eviction)
    // Write-first forwarding cho từng word
    // ========================================================================
    wire [7:0] ra0 = {read_all_index, 2'd0};
    wire [7:0] ra1 = {read_all_index, 2'd1};
    wire [7:0] ra2 = {read_all_index, 2'd2};
    wire [7:0] ra3 = {read_all_index, 2'd3};

    wire col0 = write_enable && (write_addr_flat == ra0);
    wire col1 = write_enable && (write_addr_flat == ra1);
    wire col2 = write_enable && (write_addr_flat == ra2);
    wire col3 = write_enable && (write_addr_flat == ra3);

    assign read_word_0[7:0]   = (col0 && write_strb[0]) ? write_data[7:0]   : data_array[ra0][7:0];
    assign read_word_0[15:8]  = (col0 && write_strb[1]) ? write_data[15:8]  : data_array[ra0][15:8];
    assign read_word_0[23:16] = (col0 && write_strb[2]) ? write_data[23:16] : data_array[ra0][23:16];
    assign read_word_0[31:24] = (col0 && write_strb[3]) ? write_data[31:24] : data_array[ra0][31:24];

    assign read_word_1[7:0]   = (col1 && write_strb[0]) ? write_data[7:0]   : data_array[ra1][7:0];
    assign read_word_1[15:8]  = (col1 && write_strb[1]) ? write_data[15:8]  : data_array[ra1][15:8];
    assign read_word_1[23:16] = (col1 && write_strb[2]) ? write_data[23:16] : data_array[ra1][23:16];
    assign read_word_1[31:24] = (col1 && write_strb[3]) ? write_data[31:24] : data_array[ra1][31:24];

    assign read_word_2[7:0]   = (col2 && write_strb[0]) ? write_data[7:0]   : data_array[ra2][7:0];
    assign read_word_2[15:8]  = (col2 && write_strb[1]) ? write_data[15:8]  : data_array[ra2][15:8];
    assign read_word_2[23:16] = (col2 && write_strb[2]) ? write_data[23:16] : data_array[ra2][23:16];
    assign read_word_2[31:24] = (col2 && write_strb[3]) ? write_data[31:24] : data_array[ra2][31:24];

    assign read_word_3[7:0]   = (col3 && write_strb[0]) ? write_data[7:0]   : data_array[ra3][7:0];
    assign read_word_3[15:8]  = (col3 && write_strb[1]) ? write_data[15:8]  : data_array[ra3][15:8];
    assign read_word_3[23:16] = (col3 && write_strb[2]) ? write_data[23:16] : data_array[ra3][23:16];
    assign read_word_3[31:24] = (col3 && write_strb[3]) ? write_data[31:24] : data_array[ra3][31:24];

endmodule