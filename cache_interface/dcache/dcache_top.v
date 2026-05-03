// ============================================================================
// Module: dcache_top  —  Write-Back + Write-Allocate version
// Thêm AXI4 ID signals để kết nối vào axi4_crossbar (M1)
// ============================================================================
`include "cache_interface/dcache/dcache_tag_array.v"
`include "cache_interface/dcache/dcache_data_array.v"
`include "cache_interface/dcache/dcache_axi_interface.v"
`include "cache_interface/dcache/dcache_controller.v"


module dcache_top #(
    parameter CACHE_SIZE = 8192,
    parameter LINE_SIZE  = 16,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // CPU Interface
    // ========================================================================
    input  wire [ADDR_WIDTH-1:0] cpu_addr,
    input  wire [DATA_WIDTH-1:0] cpu_wdata,
    input  wire [3:0]            cpu_wstrb,
    input  wire                  cpu_req,
    input  wire                  cpu_we,
    output wire [DATA_WIDTH-1:0] cpu_rdata,
    output wire                  cpu_ready,
    // fence_type[0]=flush-dirty  fence_type[1]=invalidate-read
    input  wire [1:0]            fence_type,

    // Debug
    output wire [ADDR_WIDTH-1:0] current_addr,
    output wire [DATA_WIDTH-1:0] current_data,
    output wire                  current_valid,

    // ========================================================================
    // AXI4 Read Address Channel
    // ========================================================================
    output wire [ID_WIDTH-1:0]   mem_arid,
    output wire [ADDR_WIDTH-1:0] mem_araddr,
    output wire [7:0]            mem_arlen,
    output wire [2:0]            mem_arsize,
    output wire [1:0]            mem_arburst,
    output wire [2:0]            mem_arprot,
    output wire                  mem_arvalid,
    input  wire                  mem_arready,

    // AXI4 Read Data Channel
    input  wire [ID_WIDTH-1:0]   mem_rid,
    input  wire [DATA_WIDTH-1:0] mem_rdata,
    input  wire [1:0]            mem_rresp,
    input  wire                  mem_rlast,
    input  wire                  mem_rvalid,
    output wire                  mem_rready,

    // ========================================================================
    // AXI4 Write Address Channel
    // ========================================================================
    output wire [ID_WIDTH-1:0]   mem_awid,
    output wire [ADDR_WIDTH-1:0] mem_awaddr,
    output wire [7:0]            mem_awlen,
    output wire [2:0]            mem_awsize,
    output wire [1:0]            mem_awburst,
    output wire [2:0]            mem_awprot,
    output wire                  mem_awvalid,
    input  wire                  mem_awready,

    // AXI4 Write Data Channel
    output wire [DATA_WIDTH-1:0] mem_wdata,
    output wire [3:0]            mem_wstrb,
    output wire                  mem_wlast,
    output wire                  mem_wvalid,
    input  wire                  mem_wready,

    // AXI4 Write Response Channel
    input  wire [ID_WIDTH-1:0]   mem_bid,
    input  wire [1:0]            mem_bresp,
    input  wire                  mem_bvalid,
    output wire                  mem_bready,

    // ========================================================================
    // Statistics
    // ========================================================================
    output wire [31:0] stat_hits,
    output wire [31:0] stat_misses,
    output wire [31:0] stat_writes
);

    // ========================================================================
    // Internal Signals — Tag Array
    // ========================================================================
    wire [5:0]  tag_lookup_index;
    wire [21:0] tag_lookup_tag;
    wire        tag_hit;
    wire        tag_dirty_out;
    wire [21:0] tag_evict_tag_out;
    wire        tag_update_valid;
    wire [5:0]  tag_update_index;
    wire [21:0] tag_update_tag;
    wire        tag_flush_all;      // flush dirty lines (write-back) — fence w,w hoặc fence iorw
    wire        tag_invalidate_all; // xóa valid bits (invalidate)    — fence iorw hoặc fence.i
    wire        tag_dirty_set;
    wire        tag_dirty_clear;
    wire [5:0]  tag_dirty_index;

    // ========================================================================
    // Internal Signals — Data Array
    // ========================================================================
    wire [5:0]  data_read_index;
    wire [1:0]  data_read_offset;
    wire [31:0] data_read_data;
    wire [5:0]  data_read_all_index;
    wire [31:0] data_read_word_0;
    wire [31:0] data_read_word_1;
    wire [31:0] data_read_word_2;
    wire [31:0] data_read_word_3;
    wire        data_write_enable;
    wire [5:0]  data_write_index;
    wire [1:0]  data_write_offset;
    wire [31:0] data_write_data;
    wire [3:0]  data_write_strb;

    // ========================================================================
    // Internal Signals — AXI Refill / Eviction
    // ========================================================================
    wire [31:0] refill_addr;
    wire        refill_start;
    wire        refill_nc;       // [NC-BYPASS]
    wire        refill_busy;
    wire        refill_done;
    wire [31:0] refill_data;
    wire [1:0]  refill_word;
    wire        refill_data_valid;

    wire [31:0] evict_addr;
    wire [31:0] evict_data_0;
    wire [31:0] evict_data_1;
    wire [31:0] evict_data_2;
    wire [31:0] evict_data_3;
    wire        evict_start;
    wire        evict_nc;        // [NC-BYPASS]
    wire [3:0]  evict_wstrb_nc;  // [NC-BYPASS]
    wire        evict_busy;
    wire        evict_done;

    // ========================================================================
    // Sub-Modules
    // ========================================================================

    dcache_tag_array tag_array_inst (
        .clk            (clk),
        .rst_n          (rst_n),
        .lookup_index   (tag_lookup_index),
        .lookup_tag     (tag_lookup_tag),
        .hit            (tag_hit),
        .dirty_out      (tag_dirty_out),
        .evict_tag_out  (tag_evict_tag_out),
        .update_valid   (tag_update_valid),
        .update_index   (tag_update_index),
        .update_tag     (tag_update_tag),
        .dirty_set      (tag_dirty_set),
        .dirty_clear    (tag_dirty_clear),
        .dirty_index    (tag_dirty_index),
        .flush_all      (tag_flush_all),
        .invalidate_all (tag_invalidate_all)
    );

    dcache_data_array data_array_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .read_index      (data_read_index),
        .read_offset     (data_read_offset),
        .read_data       (data_read_data),
        .read_all_index  (data_read_all_index),
        .read_word_0     (data_read_word_0),
        .read_word_1     (data_read_word_1),
        .read_word_2     (data_read_word_2),
        .read_word_3     (data_read_word_3),
        .write_enable    (data_write_enable),
        .write_index     (data_write_index),
        .write_offset    (data_write_offset),
        .write_data      (data_write_data),
        .write_strb      (data_write_strb)
    );

    dcache_axi_interface #(.ID_WIDTH(ID_WIDTH)) axi_interface_inst (
        .clk               (clk),
        .rst_n             (rst_n),

        .refill_addr       (refill_addr),
        .refill_start      (refill_start),
        .refill_nc         (refill_nc),
        .refill_busy       (refill_busy),
        .refill_done       (refill_done),
        .refill_data       (refill_data),
        .refill_word       (refill_word),
        .refill_data_valid (refill_data_valid),

        .evict_addr        (evict_addr),
        .evict_data_0      (evict_data_0),
        .evict_data_1      (evict_data_1),
        .evict_data_2      (evict_data_2),
        .evict_data_3      (evict_data_3),
        .evict_start       (evict_start),
        .evict_nc          (evict_nc),
        .evict_wstrb_nc    (evict_wstrb_nc),
        .evict_busy        (evict_busy),
        .evict_done        (evict_done),

        .M_AXI_ARID        (mem_arid),
        .M_AXI_ARADDR      (mem_araddr),
        .M_AXI_ARLEN       (mem_arlen),
        .M_AXI_ARSIZE      (mem_arsize),
        .M_AXI_ARBURST     (mem_arburst),
        .M_AXI_ARPROT      (mem_arprot),
        .M_AXI_ARVALID     (mem_arvalid),
        .M_AXI_ARREADY     (mem_arready),
        .M_AXI_RID         (mem_rid),
        .M_AXI_RDATA       (mem_rdata),
        .M_AXI_RRESP       (mem_rresp),
        .M_AXI_RLAST       (mem_rlast),
        .M_AXI_RVALID      (mem_rvalid),
        .M_AXI_RREADY      (mem_rready),

        .M_AXI_AWID        (mem_awid),
        .M_AXI_AWADDR      (mem_awaddr),
        .M_AXI_AWLEN       (mem_awlen),
        .M_AXI_AWSIZE      (mem_awsize),
        .M_AXI_AWBURST     (mem_awburst),
        .M_AXI_AWPROT      (mem_awprot),
        .M_AXI_AWVALID     (mem_awvalid),
        .M_AXI_AWREADY     (mem_awready),
        .M_AXI_WDATA       (mem_wdata),
        .M_AXI_WSTRB       (mem_wstrb),
        .M_AXI_WLAST       (mem_wlast),
        .M_AXI_WVALID      (mem_wvalid),
        .M_AXI_WREADY      (mem_wready),
        .M_AXI_BID         (mem_bid),
        .M_AXI_BRESP       (mem_bresp),
        .M_AXI_BVALID      (mem_bvalid),
        .M_AXI_BREADY      (mem_bready)
    );

    dcache_controller controller_inst (
        .clk                (clk),
        .rst_n              (rst_n),

        .cpu_addr           (cpu_addr),
        .cpu_wdata          (cpu_wdata),
        .cpu_wstrb          (cpu_wstrb),
        .cpu_req            (cpu_req),
        .cpu_we             (cpu_we),
        .cpu_rdata          (cpu_rdata),
        .cpu_ready          (cpu_ready),
        .fence_type         (fence_type),

        .current_addr       (current_addr),
        .current_data       (current_data),
        .current_valid      (current_valid),

        .tag_lookup_index   (tag_lookup_index),
        .tag_lookup_tag     (tag_lookup_tag),
        .tag_hit            (tag_hit),
        .tag_dirty_out      (tag_dirty_out),
        .tag_evict_tag_out  (tag_evict_tag_out),
        .tag_update_valid   (tag_update_valid),
        .tag_update_index   (tag_update_index),
        .tag_update_tag     (tag_update_tag),
        .tag_flush_all      (tag_flush_all),
        .tag_invalidate_all (tag_invalidate_all),
        .tag_dirty_set      (tag_dirty_set),
        .tag_dirty_clear    (tag_dirty_clear),
        .tag_dirty_index    (tag_dirty_index),

        .data_read_index    (data_read_index),
        .data_read_offset   (data_read_offset),
        .data_read_data     (data_read_data),
        .data_write_enable  (data_write_enable),
        .data_write_index   (data_write_index),
        .data_write_offset  (data_write_offset),
        .data_write_data    (data_write_data),
        .data_write_strb    (data_write_strb),

        .data_read_all_index(data_read_all_index),
        .data_read_word_0   (data_read_word_0),
        .data_read_word_1   (data_read_word_1),
        .data_read_word_2   (data_read_word_2),
        .data_read_word_3   (data_read_word_3),

        .refill_addr        (refill_addr),
        .refill_start       (refill_start),
        .refill_nc          (refill_nc),
        .refill_busy        (refill_busy),
        .refill_done        (refill_done),
        .refill_data        (refill_data),
        .refill_word        (refill_word),
        .refill_data_valid  (refill_data_valid),

        .evict_addr         (evict_addr),
        .evict_data_0       (evict_data_0),
        .evict_data_1       (evict_data_1),
        .evict_data_2       (evict_data_2),
        .evict_data_3       (evict_data_3),
        .evict_start        (evict_start),
        .evict_nc           (evict_nc),
        .evict_wstrb_nc     (evict_wstrb_nc),
        .evict_busy         (evict_busy),
        .evict_done         (evict_done),

        .stat_hits          (stat_hits),
        .stat_misses        (stat_misses),
        .stat_writes        (stat_writes)
    );

endmodule
