// ============================================================================
// Module: dma_channel
// ============================================================================
// Description:
//   Single DMA channel with configuration registers and state tracking
//
// Features:
//   - Configurable source/destination addresses
//   - Transfer length configuration
//   - Address increment control
//   - Burst size and data width configuration
//   - Status reporting (busy, done, error)
//
// Author: ChiThang
// ============================================================================

`include "dma/dma_defines.vh"

module dma_channel (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Configuration Interface (from AXI4-Lite slave)
    // ========================================================================
    input wire [31:0] cfg_src_addr,
    input wire [31:0] cfg_dst_addr,
    input wire [31:0] cfg_length,
    input wire [31:0] cfg_ctrl,
    input wire        cfg_ctrl_write,
    
    input wire        cfg_status_write,
    input wire [31:0] cfg_status_wdata,
    
    output reg [31:0] status_reg,
    output reg [31:0] curr_src_addr,
    output reg [31:0] curr_dst_addr,
    output reg [31:0] remaining_bytes,
    
    // ========================================================================
    // Channel Request Interface (to arbiter)
    // ========================================================================
    output wire       channel_request,
    output wire [1:0] channel_priority,
    
    // ========================================================================
    // DMA Engine Interface
    // ========================================================================
    input wire        engine_grant,       // Arbiter grants this channel
    input wire        engine_done,        // Engine completed transfer
    input wire        engine_error,       // Engine encountered error
    
    output reg [31:0] engine_src_addr,
    output reg [31:0] engine_dst_addr,
    output reg [31:0] engine_transfer_size,
    output reg [2:0]  engine_burst_size,
    output reg [1:0]  engine_data_width,
    output reg        engine_src_incr,
    output reg        engine_dst_incr,
    
    // ========================================================================
    // Interrupt Output
    // ========================================================================
    output wire       irq_done,
    output wire       irq_error
);

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [31:0] src_addr_reg;
    reg [31:0] dst_addr_reg;
    reg [31:0] length_reg;
    reg [31:0] ctrl_reg;
    
    // ========================================================================
    // Control Register Decoding
    // ========================================================================
    wire       ctrl_start;
    wire       ctrl_enable;
    wire [2:0] ctrl_burst_size;
    wire [1:0] ctrl_data_width;
    wire       ctrl_src_incr;
    wire       ctrl_dst_incr;
    wire [1:0] ctrl_priority;
    
    assign ctrl_start      = ctrl_reg[`DMA_CTRL_START_BIT];
    assign ctrl_enable     = ctrl_reg[`DMA_CTRL_ENABLE_BIT];
    assign ctrl_burst_size = ctrl_reg[`DMA_CTRL_BURST_MSB:`DMA_CTRL_BURST_LSB];
    assign ctrl_data_width = ctrl_reg[`DMA_CTRL_WIDTH_MSB:`DMA_CTRL_WIDTH_LSB];
    assign ctrl_src_incr   = ctrl_reg[`DMA_CTRL_SRC_INCR_BIT];
    assign ctrl_dst_incr   = ctrl_reg[`DMA_CTRL_DST_INCR_BIT];
    assign ctrl_priority   = ctrl_reg[`DMA_CTRL_PRIORITY_MSB:`DMA_CTRL_PRIORITY_LSB];
    
    // ========================================================================
    // Status Register Decoding
    // ========================================================================
    wire status_busy;
    wire status_done;
    wire status_error;
    
    assign status_busy  = status_reg[`DMA_STATUS_BUSY_BIT];
    assign status_done  = status_reg[`DMA_STATUS_DONE_BIT];
    assign status_error = status_reg[`DMA_STATUS_ERROR_BIT];
    
    // ========================================================================
    // Channel State Machine
    // ========================================================================
    localparam [1:0]
        CH_IDLE     = 2'b00,
        CH_READY    = 2'b01,
        CH_ACTIVE   = 2'b10,
        CH_COMPLETE = 2'b11;
    
    reg [1:0] channel_state;
    
    // ========================================================================
    // Configuration Register Updates
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_addr_reg <= 32'h0;
            dst_addr_reg <= 32'h0;
            length_reg   <= 32'h0;
            ctrl_reg     <= 32'h0;
        end else begin
            // Source address
            if (cfg_ctrl_write && (channel_state == CH_IDLE)) begin
                src_addr_reg <= cfg_src_addr;
            end
            
            // Destination address
            if (cfg_ctrl_write && (channel_state == CH_IDLE)) begin
                dst_addr_reg <= cfg_dst_addr;
            end
            
            // Transfer length
            if (cfg_ctrl_write && (channel_state == CH_IDLE)) begin
                length_reg <= cfg_length;
            end
            
            // Control register
            if (cfg_ctrl_write) begin
                ctrl_reg <= cfg_ctrl;
            end else if (channel_state == CH_COMPLETE) begin
                // Auto-clear START bit when done
                ctrl_reg[`DMA_CTRL_START_BIT] <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // Status Register Updates
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_reg <= 32'h0;
        end else begin
            // Software write (W1C for DONE and ERROR bits)
            if (cfg_status_write) begin
                status_reg[`DMA_STATUS_DONE_BIT]  <= status_reg[`DMA_STATUS_DONE_BIT]  & ~cfg_status_wdata[`DMA_STATUS_DONE_BIT];
                status_reg[`DMA_STATUS_ERROR_BIT] <= status_reg[`DMA_STATUS_ERROR_BIT] & ~cfg_status_wdata[`DMA_STATUS_ERROR_BIT];
            end
            
            // Hardware updates
            case (channel_state)
                CH_IDLE: begin
                    status_reg[`DMA_STATUS_BUSY_BIT] <= 1'b0;
                end
                
                CH_READY, CH_ACTIVE: begin
                    status_reg[`DMA_STATUS_BUSY_BIT] <= 1'b1;
                end
                
                CH_COMPLETE: begin
                    status_reg[`DMA_STATUS_BUSY_BIT] <= 1'b0;
                    if (engine_error) begin
                        status_reg[`DMA_STATUS_ERROR_BIT] <= 1'b1;
                    end else begin
                        status_reg[`DMA_STATUS_DONE_BIT] <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // ========================================================================
    // Channel State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_state    <= CH_IDLE;
            curr_src_addr    <= 32'h0;
            curr_dst_addr    <= 32'h0;
            remaining_bytes  <= 32'h0;
            engine_src_addr  <= 32'h0;
            engine_dst_addr  <= 32'h0;
            engine_transfer_size <= 32'h0;
            engine_burst_size    <= 3'b0;
            engine_data_width    <= 2'b0;
            engine_src_incr      <= 1'b0;
            engine_dst_incr      <= 1'b0;
        end else begin
            case (channel_state)
                CH_IDLE: begin
                    // Wait for START command
                    if (ctrl_enable && ctrl_start && !status_busy) begin
                        // Initialize transfer
                        curr_src_addr   <= src_addr_reg;
                        curr_dst_addr   <= dst_addr_reg;
                        remaining_bytes <= length_reg;
                        channel_state   <= CH_READY;
                    end
                end
                
                CH_READY: begin
                    // Wait for arbiter grant
                    if (engine_grant) begin
                        // Prepare engine parameters
                        engine_src_addr      <= curr_src_addr;
                        engine_dst_addr      <= curr_dst_addr;
                        engine_transfer_size <= remaining_bytes;
                        engine_burst_size    <= ctrl_burst_size;
                        engine_data_width    <= ctrl_data_width;
                        engine_src_incr      <= ctrl_src_incr;
                        engine_dst_incr      <= ctrl_dst_incr;
                        channel_state        <= CH_ACTIVE;
                    end
                end
                
                CH_ACTIVE: begin
                    // Wait for engine completion
                    if (engine_done || engine_error) begin
                        channel_state <= CH_COMPLETE;
                    end
                    // Note: Engine will update curr_src/dst and remaining via external interface
                end
                
                CH_COMPLETE: begin
                    // Return to IDLE
                    channel_state <= CH_IDLE;
                end
                
                default: channel_state <= CH_IDLE;
            endcase
        end
    end
    
    // ========================================================================
    // Output Assignments
    // ========================================================================
    assign channel_request  = (channel_state == CH_READY);
    assign channel_priority = ctrl_priority;
    
    assign irq_done  = status_done;
    assign irq_error = status_error;

endmodule