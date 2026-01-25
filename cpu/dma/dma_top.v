// ============================================================================
// Module: dma_top
// ============================================================================
// Description:
//   Top-level DMA controller integrating all sub-modules
//
// Hierarchy:
//   dma_top
//   ├── dma_config_slave    (AXI4-Lite configuration interface)
//   ├── dma_channel (x4)    (Channel state machines)
//   ├── dma_arbiter         (Channel arbitration)
//   └── dma_engine          (AXI4 master transfer engine)
//
// Author: ChiThang
// ============================================================================

`include "dma/dma_defines.vh"
`include "dma/dma_config_slave.v"
`include "dma/dma_channel.v"
`include "dma/dma_arbiter.v"
`include "dma/dma_engine.v"

module dma_top #(
    parameter NUM_CHANNELS = `NUM_DMA_CHANNELS,
    parameter ADDR_WIDTH = `DMA_ADDR_WIDTH,
    parameter DATA_WIDTH = `DMA_DATA_WIDTH
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4-Lite Slave Interface (Configuration)
    // ========================================================================
    input wire [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0]            S_AXI_AWPROT,
    input wire                  S_AXI_AWVALID,
    output wire                 S_AXI_AWREADY,
    
    input wire [31:0]           S_AXI_WDATA,
    input wire [3:0]            S_AXI_WSTRB,
    input wire                  S_AXI_WVALID,
    output wire                 S_AXI_WREADY,
    
    output wire [1:0]           S_AXI_BRESP,
    output wire                 S_AXI_BVALID,
    input wire                  S_AXI_BREADY,
    
    input wire [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0]            S_AXI_ARPROT,
    input wire                  S_AXI_ARVALID,
    output wire                 S_AXI_ARREADY,
    
    output wire [31:0]          S_AXI_RDATA,
    output wire [1:0]           S_AXI_RRESP,
    output wire                 S_AXI_RVALID,
    input wire                  S_AXI_RREADY,
    
    // ========================================================================
    // AXI4 Master Interface (Data Transfer)
    // ========================================================================
    // Write Address Channel
    output wire [ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [7:0]            M_AXI_AWLEN,
    output wire [2:0]            M_AXI_AWSIZE,
    output wire [1:0]            M_AXI_AWBURST,
    output wire                  M_AXI_AWVALID,
    input wire                   M_AXI_AWREADY,
    
    // Write Data Channel
    output wire [DATA_WIDTH-1:0]     M_AXI_WDATA,
    output wire [DATA_WIDTH/8-1:0]   M_AXI_WSTRB,
    output wire                      M_AXI_WLAST,
    output wire                      M_AXI_WVALID,
    input wire                       M_AXI_WREADY,
    
    // Write Response Channel
    input wire [1:0]             M_AXI_BRESP,
    input wire                   M_AXI_BVALID,
    output wire                  M_AXI_BREADY,
    
    // Read Address Channel
    output wire [ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [7:0]            M_AXI_ARLEN,
    output wire [2:0]            M_AXI_ARSIZE,
    output wire [1:0]            M_AXI_ARBURST,
    output wire                  M_AXI_ARVALID,
    input wire                   M_AXI_ARREADY,
    
    // Read Data Channel
    input wire [DATA_WIDTH-1:0]  M_AXI_RDATA,
    input wire [1:0]             M_AXI_RRESP,
    input wire                   M_AXI_RLAST,
    input wire                   M_AXI_RVALID,
    output wire                  M_AXI_RREADY,
    
    // ========================================================================
    // Interrupt Outputs
    // ========================================================================
    output wire [NUM_CHANNELS-1:0] irq_done,
    output wire [NUM_CHANNELS-1:0] irq_error
);

    // ========================================================================
    // Configuration Slave Interface Signals
    // ========================================================================
    wire [31:0] ch_src_addr  [0:NUM_CHANNELS-1];
    wire [31:0] ch_dst_addr  [0:NUM_CHANNELS-1];
    wire [31:0] ch_length    [0:NUM_CHANNELS-1];
    wire [31:0] ch_ctrl      [0:NUM_CHANNELS-1];
    wire        ch_ctrl_write[0:NUM_CHANNELS-1];
    wire        ch_status_write[0:NUM_CHANNELS-1];
    wire [31:0] ch_status_wdata[0:NUM_CHANNELS-1];
    wire [31:0] ch_status    [0:NUM_CHANNELS-1];
    wire [31:0] ch_curr_src  [0:NUM_CHANNELS-1];
    wire [31:0] ch_curr_dst  [0:NUM_CHANNELS-1];
    wire [31:0] ch_remaining [0:NUM_CHANNELS-1];
    
    // ========================================================================
    // Channel Request/Grant Signals
    // ========================================================================
    wire [NUM_CHANNELS-1:0] channel_request;
    wire [1:0]              channel_priority [0:NUM_CHANNELS-1];
    wire [NUM_CHANNELS-1:0] channel_grant;
    wire [1:0]              active_channel;
    wire                    grant_valid;
    
    // ========================================================================
    // Engine Interface Signals
    // ========================================================================
    wire [31:0] engine_src_addr  [0:NUM_CHANNELS-1];
    wire [31:0] engine_dst_addr  [0:NUM_CHANNELS-1];
    wire [31:0] engine_xfer_size [0:NUM_CHANNELS-1];
    wire [2:0]  engine_burst_size[0:NUM_CHANNELS-1];
    wire [1:0]  engine_data_width[0:NUM_CHANNELS-1];
    wire        engine_src_incr  [0:NUM_CHANNELS-1];
    wire        engine_dst_incr  [0:NUM_CHANNELS-1];
    
    wire        engine_start;
    wire [31:0] engine_src_mux;
    wire [31:0] engine_dst_mux;
    wire [31:0] engine_size_mux;
    wire [2:0]  engine_burst_mux;
    wire [1:0]  engine_width_mux;
    wire        engine_src_inc_mux;
    wire        engine_dst_inc_mux;
    
    wire        engine_busy;
    wire        engine_done;
    wire        engine_error;
    
    // ========================================================================
    // Configuration Slave Instance
    // ========================================================================
    dma_config_slave config_slave (
        .clk(clk),
        .rst_n(rst_n),
        
        // AXI4-Lite Slave
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWPROT(S_AXI_AWPROT),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARPROT(S_AXI_ARPROT),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        
        // Channel 0
        .ch0_src_addr(ch_src_addr[0]),
        .ch0_dst_addr(ch_dst_addr[0]),
        .ch0_length(ch_length[0]),
        .ch0_ctrl(ch_ctrl[0]),
        .ch0_ctrl_write(ch_ctrl_write[0]),
        .ch0_status_write(ch_status_write[0]),
        .ch0_status_wdata(ch_status_wdata[0]),
        .ch0_status(ch_status[0]),
        .ch0_curr_src(ch_curr_src[0]),
        .ch0_curr_dst(ch_curr_dst[0]),
        .ch0_remaining(ch_remaining[0]),
        
        // Channel 1
        .ch1_src_addr(ch_src_addr[1]),
        .ch1_dst_addr(ch_dst_addr[1]),
        .ch1_length(ch_length[1]),
        .ch1_ctrl(ch_ctrl[1]),
        .ch1_ctrl_write(ch_ctrl_write[1]),
        .ch1_status_write(ch_status_write[1]),
        .ch1_status_wdata(ch_status_wdata[1]),
        .ch1_status(ch_status[1]),
        .ch1_curr_src(ch_curr_src[1]),
        .ch1_curr_dst(ch_curr_dst[1]),
        .ch1_remaining(ch_remaining[1]),
        
        // Channel 2
        .ch2_src_addr(ch_src_addr[2]),
        .ch2_dst_addr(ch_dst_addr[2]),
        .ch2_length(ch_length[2]),
        .ch2_ctrl(ch_ctrl[2]),
        .ch2_ctrl_write(ch_ctrl_write[2]),
        .ch2_status_write(ch_status_write[2]),
        .ch2_status_wdata(ch_status_wdata[2]),
        .ch2_status(ch_status[2]),
        .ch2_curr_src(ch_curr_src[2]),
        .ch2_curr_dst(ch_curr_dst[2]),
        .ch2_remaining(ch_remaining[2]),
        
        // Channel 3
        .ch3_src_addr(ch_src_addr[3]),
        .ch3_dst_addr(ch_dst_addr[3]),
        .ch3_length(ch_length[3]),
        .ch3_ctrl(ch_ctrl[3]),
        .ch3_ctrl_write(ch_ctrl_write[3]),
        .ch3_status_write(ch_status_write[3]),
        .ch3_status_wdata(ch_status_wdata[3]),
        .ch3_status(ch_status[3]),
        .ch3_curr_src(ch_curr_src[3]),
        .ch3_curr_dst(ch_curr_dst[3]),
        .ch3_remaining(ch_remaining[3])
    );
    
    // ========================================================================
    // Channel Instances
    // ========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : gen_channels
            dma_channel channel_inst (
                .clk(clk),
                .rst_n(rst_n),
                
                // Configuration
                .cfg_src_addr(ch_src_addr[i]),
                .cfg_dst_addr(ch_dst_addr[i]),
                .cfg_length(ch_length[i]),
                .cfg_ctrl(ch_ctrl[i]),
                .cfg_ctrl_write(ch_ctrl_write[i]),
                .cfg_status_write(ch_status_write[i]),
                .cfg_status_wdata(ch_status_wdata[i]),
                
                .status_reg(ch_status[i]),
                .curr_src_addr(ch_curr_src[i]),
                .curr_dst_addr(ch_curr_dst[i]),
                .remaining_bytes(ch_remaining[i]),
                
                // Request/Grant
                .channel_request(channel_request[i]),
                .channel_priority(channel_priority[i]),
                .engine_grant(channel_grant[i]),
                
                // Engine Interface
                .engine_done(engine_done),
                .engine_error(engine_error),
                .engine_src_addr(engine_src_addr[i]),
                .engine_dst_addr(engine_dst_addr[i]),
                .engine_transfer_size(engine_xfer_size[i]),
                .engine_burst_size(engine_burst_size[i]),
                .engine_data_width(engine_data_width[i]),
                .engine_src_incr(engine_src_incr[i]),
                .engine_dst_incr(engine_dst_incr[i]),
                
                // Interrupts
                .irq_done(irq_done[i]),
                .irq_error(irq_error[i])
            );
        end
    endgenerate
    
    // ========================================================================
    // Arbiter Instance
    // ========================================================================
    dma_arbiter arbiter (
        .clk(clk),
        .rst_n(rst_n),
        
        .channel_request(channel_request),
        .channel_priority_0(channel_priority[0]),
        .channel_priority_1(channel_priority[1]),
        .channel_priority_2(channel_priority[2]),
        .channel_priority_3(channel_priority[3]),
        
        .channel_grant(channel_grant),
        .active_channel(active_channel),
        .grant_valid(grant_valid),
        
        .engine_busy(engine_busy),
        .engine_done(engine_done)
    );
    
    // ========================================================================
    // Engine Parameter Multiplexing
    // ========================================================================
    assign engine_start       = grant_valid;
    assign engine_src_mux     = engine_src_addr[active_channel];
    assign engine_dst_mux     = engine_dst_addr[active_channel];
    assign engine_size_mux    = engine_xfer_size[active_channel];
    assign engine_burst_mux   = engine_burst_size[active_channel];
    assign engine_width_mux   = engine_data_width[active_channel];
    assign engine_src_inc_mux = engine_src_incr[active_channel];
    assign engine_dst_inc_mux = engine_dst_incr[active_channel];
    
    // ========================================================================
    // Transfer Engine Instance
    // ========================================================================
    dma_engine engine (
        .clk(clk),
        .rst_n(rst_n),
        
        // Control
        .start(engine_start),
        .src_addr(engine_src_mux),
        .dst_addr(engine_dst_mux),
        .transfer_size(engine_size_mux),
        .burst_size(engine_burst_mux),
        .data_width(engine_width_mux),
        .src_incr(engine_src_inc_mux),
        .dst_incr(engine_dst_inc_mux),
        
        .busy(engine_busy),
        .done(engine_done),
        .error(engine_error),
        
        // AXI4 Master
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),
        .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),
        
        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),
        
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY),
        
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );

endmodule