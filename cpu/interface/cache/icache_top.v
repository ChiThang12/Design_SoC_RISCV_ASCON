// ============================================================================
// Module: icache_top
// ============================================================================
// Description:
//   Top-level instruction cache integration with AXI4 Full interface
//   Connects all sub-modules together
//
// Author: ChiThang
// Version: AXI4 Full Support
// ============================================================================

`include "cache/icache_defines.vh"
`include "cache/icache_tag_array.v"
`include "cache/icache_data_array.v"
`include "cache/icache_axi_interface.v"
`include "cache/icache_controller.v"

module icache_top #(
    parameter CACHE_SIZE = `ICACHE_SIZE,
    parameter LINE_SIZE  = `ICACHE_LINE_SIZE,
    parameter ADDR_WIDTH = `ICACHE_ADDR_WIDTH,
    parameter DATA_WIDTH = `ICACHE_DATA_WIDTH
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // CPU Interface
    // ========================================================================
    input wire [ADDR_WIDTH-1:0] cpu_addr,
    input wire                  cpu_req,
    output wire [DATA_WIDTH-1:0] cpu_rdata,
    output wire                  cpu_ready,
    
    // Branch/Jump flush
    input wire                  flush,
    
    // ========================================================================
    // Memory Interface (AXI4 Full - Read Only)
    // ========================================================================
    // AR Channel (Address Read)
    output wire [ADDR_WIDTH-1:0] mem_araddr,
    output wire [7:0]            mem_arlen,     // Burst length
    output wire [2:0]            mem_arsize,    // Transfer size
    output wire [1:0]            mem_arburst,   // Burst type
    output wire [2:0]            mem_arprot,
    output wire                  mem_arvalid,
    input wire                   mem_arready,
    
    // R Channel (Read Data)
    input wire [DATA_WIDTH-1:0]  mem_rdata,
    input wire [1:0]             mem_rresp,
    input wire                   mem_rlast,     // Last transfer in burst
    input wire                   mem_rvalid,
    output wire                  mem_rready,
    
    // ========================================================================
    // Unused Write Channels (tied off for read-only cache)
    // ========================================================================
    // AW Channel
    output wire [ADDR_WIDTH-1:0] mem_awaddr,
    output wire [7:0]            mem_awlen,
    output wire [2:0]            mem_awsize,
    output wire [1:0]            mem_awburst,
    output wire [2:0]            mem_awprot,
    output wire                  mem_awvalid,
    input wire                   mem_awready,
    
    // W Channel
    output wire [DATA_WIDTH-1:0] mem_wdata,
    output wire [3:0]            mem_wstrb,
    output wire                  mem_wlast,
    output wire                  mem_wvalid,
    input wire                   mem_wready,
    
    // B Channel
    input wire [1:0]             mem_bresp,
    input wire                   mem_bvalid,
    output wire                  mem_bready,
    
    // ========================================================================
    // Statistics (optional debug)
    // ========================================================================
    output wire [31:0] stat_hits,
    output wire [31:0] stat_misses
);

    // ========================================================================
    // Tie off unused write channels (read-only cache)
    // ========================================================================
    assign mem_awaddr  = 32'h0;
    assign mem_awlen   = 8'h0;
    assign mem_awsize  = 3'b000;
    assign mem_awburst = 2'b00;
    assign mem_awprot  = 3'b000;
    assign mem_awvalid = 1'b0;
    assign mem_wdata   = 32'h0;
    assign mem_wstrb   = 4'h0;
    assign mem_wlast   = 1'b0;
    assign mem_wvalid  = 1'b0;
    assign mem_bready  = 1'b0;
    
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
    
    // AXI Refill
    wire [31:0] refill_addr;
    wire        refill_start;
    wire        refill_busy;
    wire        refill_done;
    wire [31:0] refill_data;
    wire [1:0]  refill_word;
    wire        refill_data_valid;
    
    // ========================================================================
    // Sub-Module Instances
    // ========================================================================
    
    // Tag Array
    icache_tag_array tag_array_inst (
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
    icache_data_array data_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .read_index(data_read_index),
        .read_offset(data_read_offset),
        .read_data(data_read_data),
        
        .write_enable(data_write_enable),
        .write_index(data_write_index),
        .write_offset(data_write_offset),
        .write_data(data_write_data)
    );
    
    // AXI4 Interface
    icache_axi_interface axi_interface_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        
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
        .M_AXI_RREADY(mem_rready)
    );
    
    // Controller
    icache_controller controller_inst (
        .clk(clk),
        .rst_n(rst_n),
        
        .cpu_addr(cpu_addr),
        .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .flush(flush),
        
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
        
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        
        .stat_hits(stat_hits),
        .stat_misses(stat_misses)
    );

endmodule