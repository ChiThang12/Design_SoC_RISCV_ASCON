// ============================================================================
// Module: dcache_top
// ============================================================================
// Description:
//   Data cache with write-through policy and AXI4 Full interface
//   Simpler than icache - optimized for RISC-V load/store operations
//
// Author: ChiThang
// Version: 1.0 - Write-through, direct-mapped
// ============================================================================

`include "interface/dcache/dcache_defines.vh"
`include "interface/dcache/dcache_tag_array.v"
`include "interface/dcache/dcache_data_array.v"
`include "interface/dcache/dcache_axi_interface.v"
`include "interface/dcache/dcache_controller.v"

module dcache_top #(
    parameter CACHE_SIZE = `DCACHE_SIZE,      // 8KB
    parameter LINE_SIZE  = `DCACHE_LINE_SIZE, // 16 bytes (4 words)
    parameter ADDR_WIDTH = `DCACHE_ADDR_WIDTH,
    parameter DATA_WIDTH = `DCACHE_DATA_WIDTH
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // CPU Interface
    // ========================================================================
    input wire [ADDR_WIDTH-1:0]  cpu_addr,
    input wire [DATA_WIDTH-1:0]  cpu_wdata,
    input wire [3:0]             cpu_wstrb,    // Byte enable
    input wire                   cpu_req,
    input wire                   cpu_we,       // Write enable
    output wire [DATA_WIDTH-1:0] cpu_rdata,
    output wire                  cpu_ready,
    
    // Fence/Flush
    input wire                   fence,
    
    // ========================================================================
    // Memory Interface (AXI4 Full)
    // ========================================================================
    // AR Channel (Address Read)
    output wire [ADDR_WIDTH-1:0] mem_araddr,
    output wire [7:0]            mem_arlen,
    output wire [2:0]            mem_arsize,
    output wire [1:0]            mem_arburst,
    output wire [2:0]            mem_arprot,
    output wire                  mem_arvalid,
    input wire                   mem_arready,
    
    // R Channel (Read Data)
    input wire [DATA_WIDTH-1:0]  mem_rdata,
    input wire [1:0]             mem_rresp,
    input wire                   mem_rlast,
    input wire                   mem_rvalid,
    output wire                  mem_rready,
    
    // AW Channel (Address Write)
    output wire [ADDR_WIDTH-1:0] mem_awaddr,
    output wire [7:0]            mem_awlen,
    output wire [2:0]            mem_awsize,
    output wire [1:0]            mem_awburst,
    output wire [2:0]            mem_awprot,
    output wire                  mem_awvalid,
    input wire                   mem_awready,
    
    // W Channel (Write Data)
    output wire [DATA_WIDTH-1:0] mem_wdata,
    output wire [3:0]            mem_wstrb,
    output wire                  mem_wlast,
    output wire                  mem_wvalid,
    input wire                   mem_wready,
    
    // B Channel (Write Response)
    input wire [1:0]             mem_bresp,
    input wire                   mem_bvalid,
    output wire                  mem_bready,
    
    // ========================================================================
    // Statistics (optional debug)
    // ========================================================================
    output wire [31:0] stat_hits,
    output wire [31:0] stat_misses,
    output wire [31:0] stat_writes
);

    // ========================================================================
    // Internal Signals
    // ========================================================================
    
    // Tag Array
    wire [5:0]  tag_lookup_index;
    wire [21:0] tag_lookup_tag;
    wire        tag_hit;
    wire        tag_update_valid;
    wire [5:0]  tag_update_index;
    wire [21:0] tag_update_tag;
    wire        tag_flush_all;
    
    // Data Array
    wire [5:0]  data_read_index;
    wire [1:0]  data_read_offset;
    wire [31:0] data_read_data;
    wire        data_write_enable;
    wire [5:0]  data_write_index;
    wire [1:0]  data_write_offset;
    wire [31:0] data_write_data;
    wire [3:0]  data_write_strb;
    
    // AXI Refill (Read)
    wire [31:0] refill_addr;
    wire        refill_start;
    wire        refill_busy;
    wire        refill_done;
    wire [31:0] refill_data;
    wire [1:0]  refill_word;
    wire        refill_data_valid;
    
    // AXI Write-through
    wire [31:0] wt_addr;
    wire [31:0] wt_data;
    wire [3:0]  wt_strb;
    wire        wt_start;
    wire        wt_busy;
    wire        wt_done;
    
    // ========================================================================
    // Sub-Module Instances
    // ========================================================================
    
    // Tag Array
    dcache_tag_array tag_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .lookup_index(tag_lookup_index),
        .lookup_tag(tag_lookup_tag),
        .hit(tag_hit),
        
        .update_valid(tag_update_valid),
        .update_index(tag_update_index),
        .update_tag(tag_update_tag),
        
        .flush_all(tag_flush_all)
    );
    
    // Data Array
    dcache_data_array data_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .read_index(data_read_index),
        .read_offset(data_read_offset),
        .read_data(data_read_data),
        
        .write_enable(data_write_enable),
        .write_index(data_write_index),
        .write_offset(data_write_offset),
        .write_data(data_write_data),
        .write_strb(data_write_strb)
    );
    
    // AXI4 Interface (Read + Write)
    dcache_axi_interface axi_interface_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        // Read refill
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        
        // Write-through
        .wt_addr(wt_addr),
        .wt_data(wt_data),
        .wt_strb(wt_strb),
        .wt_start(wt_start),
        .wt_busy(wt_busy),
        .wt_done(wt_done),
        
        // AXI4 Full interface
        .M_AXI_ARADDR(mem_araddr),
        .M_AXI_ARLEN(mem_arlen),
        .M_AXI_ARSIZE(mem_arsize),
        .M_AXI_ARBURST(mem_arburst),
        .M_AXI_ARPROT(mem_arprot),
        .M_AXI_ARVALID(mem_arvalid),
        .M_AXI_ARREADY(mem_arready),
        
        .M_AXI_RDATA(mem_rdata),
        .M_AXI_RRESP(mem_rresp),
        .M_AXI_RLAST(mem_rlast),
        .M_AXI_RVALID(mem_rvalid),
        .M_AXI_RREADY(mem_rready),
        
        .M_AXI_AWADDR(mem_awaddr),
        .M_AXI_AWLEN(mem_awlen),
        .M_AXI_AWSIZE(mem_awsize),
        .M_AXI_AWBURST(mem_awburst),
        .M_AXI_AWPROT(mem_awprot),
        .M_AXI_AWVALID(mem_awvalid),
        .M_AXI_AWREADY(mem_awready),
        
        .M_AXI_WDATA(mem_wdata),
        .M_AXI_WSTRB(mem_wstrb),
        .M_AXI_WLAST(mem_wlast),
        .M_AXI_WVALID(mem_wvalid),
        .M_AXI_WREADY(mem_wready),
        
        .M_AXI_BRESP(mem_bresp),
        .M_AXI_BVALID(mem_bvalid),
        .M_AXI_BREADY(mem_bready)
    );
    
    // Controller
    dcache_controller controller_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .fence(fence),
        
        .tag_lookup_index(tag_lookup_index),
        .tag_lookup_tag(tag_lookup_tag),
        .tag_hit(tag_hit),
        .tag_update_valid(tag_update_valid),
        .tag_update_index(tag_update_index),
        .tag_update_tag(tag_update_tag),
        .tag_flush_all(tag_flush_all),
        
        .data_read_index(data_read_index),
        .data_read_offset(data_read_offset),
        .data_read_data(data_read_data),
        .data_write_enable(data_write_enable),
        .data_write_index(data_write_index),
        .data_write_offset(data_write_offset),
        .data_write_data(data_write_data),
        .data_write_strb(data_write_strb),
        
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        
        .wt_addr(wt_addr),
        .wt_data(wt_data),
        .wt_strb(wt_strb),
        .wt_start(wt_start),
        .wt_busy(wt_busy),
        .wt_done(wt_done),
        
        .stat_hits(stat_hits),
        .stat_misses(stat_misses),
        .stat_writes(stat_writes)
    );

endmodule