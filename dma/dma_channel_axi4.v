// ============================================================================
// Module: dma_channel_axi4
// ============================================================================
// Description:
//   Enhanced DMA channel with full AXI4 configuration support
//
// Features:
//   - Configurable source/destination addresses with alignment check
//   - Transfer length configuration with validation
//   - Address increment control
//   - Burst size and data width configuration
//   - Cache and protection type configuration
//   - Enhanced status reporting (busy, done, error types)
//   - Channel priority and QoS support
//
// Author: ChiThang (Enhanced AXI4-Full Version)
// ============================================================================

`include "dma_defines_axi4.vh"

module dma_channel_axi4 #(
    parameter CHANNEL_ID = 0,
    parameter ID_WIDTH = `DMA_ID_WIDTH
)(
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
    input wire [1:0]  engine_error_type,  // Error type from engine
    
    output reg [31:0] engine_src_addr,
    output reg [31:0] engine_dst_addr,
    output reg [31:0] engine_transfer_size,
    output reg [2:0]  engine_burst_size,
    output reg [1:0]  engine_data_width,
    output reg        engine_src_incr,
    output reg        engine_dst_incr,
    output reg [3:0]  engine_cache_type,
    output reg [2:0]  engine_prot_type,
    output reg [ID_WIDTH-1:0] engine_channel_id,
    
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
    wire [3:0] ctrl_cache_type;
    wire [2:0] ctrl_prot_type;
    
    assign ctrl_start      = ctrl_reg[`DMA_CTRL_START_BIT];
    assign ctrl_enable     = ctrl_reg[`DMA_CTRL_ENABLE_BIT];
    assign ctrl_burst_size = ctrl_reg[`DMA_CTRL_BURST_MSB:`DMA_CTRL_BURST_LSB];
    assign ctrl_data_width = ctrl_reg[`DMA_CTRL_WIDTH_MSB:`DMA_CTRL_WIDTH_LSB];
    assign ctrl_src_incr   = ctrl_reg[`DMA_CTRL_SRC_INCR_BIT];
    assign ctrl_dst_incr   = ctrl_reg[`DMA_CTRL_DST_INCR_BIT];
    assign ctrl_priority   = ctrl_reg[`DMA_CTRL_PRIORITY_MSB:`DMA_CTRL_PRIORITY_LSB];
    assign ctrl_cache_type = ctrl_reg[`DMA_CTRL_CACHE_MSB:`DMA_CTRL_CACHE_LSB];
    assign ctrl_prot_type  = ctrl_reg[`DMA_CTRL_PROT_MSB:`DMA_CTRL_PROT_LSB];
    
    // ========================================================================
    // Status Register Decoding
    // ========================================================================
    wire status_busy;
    wire status_done;
    wire status_error;
    wire status_read_err;
    wire status_write_err;
    
    assign status_busy      = status_reg[`DMA_STATUS_BUSY_BIT];
    assign status_done      = status_reg[`DMA_STATUS_DONE_BIT];
    assign status_error     = status_reg[`DMA_STATUS_ERROR_BIT];
    assign status_read_err  = status_reg[`DMA_STATUS_READ_ERR];
    assign status_write_err = status_reg[`DMA_STATUS_WRITE_ERR];
    
    // ========================================================================
    // Channel State Machine
    // ========================================================================
    localparam [2:0]
        CH_IDLE       = 3'b000,
        CH_VALIDATE   = 3'b001,
        CH_READY      = 3'b010,
        CH_ACTIVE     = 3'b011,
        CH_WAIT_DONE  = 3'b100,
        CH_COMPLETE   = 3'b101,
        CH_ERROR      = 3'b110;
    
    reg [2:0] channel_state;
    
    // ========================================================================
    // Address Alignment Check
    // ========================================================================
    reg addr_aligned;
    reg [1:0] alignment_bytes;
    
    always @(*) begin
        case (ctrl_data_width)
            `DMA_WIDTH_8BIT:  alignment_bytes = 2'd0; // No alignment required
            `DMA_WIDTH_16BIT: alignment_bytes = 2'd1; // 2-byte alignment
            `DMA_WIDTH_32BIT: alignment_bytes = 2'd2; // 4-byte alignment
            default:          alignment_bytes = 2'd0;
        endcase
        
        // Check if addresses are properly aligned
        addr_aligned = ((src_addr_reg & ((1 << alignment_bytes) - 1)) == 0) &&
                       ((dst_addr_reg & ((1 << alignment_bytes) - 1)) == 0);
    end
    
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
            // Update configuration only when channel is idle
            if (cfg_ctrl_write && (channel_state == CH_IDLE)) begin
                src_addr_reg <= cfg_src_addr;
                dst_addr_reg <= cfg_dst_addr;
                length_reg   <= cfg_length;
                ctrl_reg     <= cfg_ctrl;
            end else if (cfg_ctrl_write && (channel_state != CH_IDLE)) begin
                // Only allow control register updates when not idle
                ctrl_reg <= cfg_ctrl;
            end
            
            // Auto-clear START bit when transfer completes
            if (channel_state == CH_COMPLETE || channel_state == CH_ERROR) begin
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
            // Software write (W1C for interrupt-related bits)
            if (cfg_status_write) begin
                status_reg[`DMA_STATUS_DONE_BIT]   <= status_reg[`DMA_STATUS_DONE_BIT]   & ~cfg_status_wdata[`DMA_STATUS_DONE_BIT];
                status_reg[`DMA_STATUS_ERROR_BIT]  <= status_reg[`DMA_STATUS_ERROR_BIT]  & ~cfg_status_wdata[`DMA_STATUS_ERROR_BIT];
                status_reg[`DMA_STATUS_READ_ERR]   <= status_reg[`DMA_STATUS_READ_ERR]   & ~cfg_status_wdata[`DMA_STATUS_READ_ERR];
                status_reg[`DMA_STATUS_WRITE_ERR]  <= status_reg[`DMA_STATUS_WRITE_ERR]  & ~cfg_status_wdata[`DMA_STATUS_WRITE_ERR];
            end
            
            // Hardware updates based on state
            case (channel_state)
                CH_IDLE: begin
                    status_reg[`DMA_STATUS_BUSY_BIT] <= 1'b0;
                end
                
                CH_VALIDATE, CH_READY, CH_ACTIVE, CH_WAIT_DONE: begin
                    status_reg[`DMA_STATUS_BUSY_BIT] <= 1'b1;
                end
                
                CH_COMPLETE: begin
                    status_reg[`DMA_STATUS_BUSY_BIT] <= 1'b0;
                    status_reg[`DMA_STATUS_DONE_BIT] <= 1'b1;
                end
                
                CH_ERROR: begin
                    status_reg[`DMA_STATUS_BUSY_BIT]  <= 1'b0;
                    status_reg[`DMA_STATUS_ERROR_BIT] <= 1'b1;
                    
                    // Set specific error type
                    case (engine_error_type)
                        2'b01: status_reg[`DMA_STATUS_READ_ERR]  <= 1'b1;
                        2'b10: status_reg[`DMA_STATUS_WRITE_ERR] <= 1'b1;
                        default: begin
                            status_reg[`DMA_STATUS_READ_ERR]  <= 1'b0;
                            status_reg[`DMA_STATUS_WRITE_ERR] <= 1'b0;
                        end
                    endcase
                end
            endcase
        end
    end
    
    // ========================================================================
    // Channel State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_state         <= CH_IDLE;
            curr_src_addr         <= 32'h0;
            curr_dst_addr         <= 32'h0;
            remaining_bytes       <= 32'h0;
            engine_src_addr       <= 32'h0;
            engine_dst_addr       <= 32'h0;
            engine_transfer_size  <= 32'h0;
            engine_burst_size     <= 3'b0;
            engine_data_width     <= 2'b0;
            engine_src_incr       <= 1'b0;
            engine_dst_incr       <= 1'b0;
            engine_cache_type     <= 4'h0;
            engine_prot_type      <= 3'b0;
            engine_channel_id     <= {ID_WIDTH{1'b0}};
        end else begin
            case (channel_state)
                // ============================================================
                // IDLE: Wait for START command
                // ============================================================
                CH_IDLE: begin
                    if (ctrl_enable && ctrl_start && !status_busy) begin
                        // Initialize transfer parameters
                        curr_src_addr   <= src_addr_reg;
                        curr_dst_addr   <= dst_addr_reg;
                        remaining_bytes <= length_reg;
                        channel_state   <= CH_VALIDATE;
                    end
                end
                
                // ============================================================
                // VALIDATE: Check configuration validity
                // ============================================================
                CH_VALIDATE: begin
                    // Check address alignment and length validity
                    if (!addr_aligned || length_reg == 0) begin
                        channel_state <= CH_ERROR;
                    end else begin
                        channel_state <= CH_READY;
                    end
                end
                
                // ============================================================
                // READY: Wait for arbiter grant
                // ============================================================
                CH_READY: begin
                    if (engine_grant) begin
                        // Prepare engine parameters
                        engine_src_addr       <= curr_src_addr;
                        engine_dst_addr       <= curr_dst_addr;
                        engine_transfer_size  <= remaining_bytes;
                        engine_burst_size     <= ctrl_burst_size;
                        engine_data_width     <= ctrl_data_width;
                        engine_src_incr       <= ctrl_src_incr;
                        engine_dst_incr       <= ctrl_dst_incr;
                        engine_cache_type     <= (ctrl_cache_type != 4'h0) ? ctrl_cache_type : `AXI_CACHE_NORMAL_NOCACHE;
                        engine_prot_type      <= (ctrl_prot_type != 3'h0) ? ctrl_prot_type : `AXI_PROT_PRIV_NONSEC_DATA;
                        engine_channel_id     <= CHANNEL_ID[ID_WIDTH-1:0];
                        channel_state         <= CH_ACTIVE;
                    end
                end
                
                // ============================================================
                // ACTIVE: Engine is processing transfer
                // ============================================================
                CH_ACTIVE: begin
                    channel_state <= CH_WAIT_DONE;
                end
                
                // ============================================================
                // WAIT_DONE: Wait for engine completion
                // ============================================================
                CH_WAIT_DONE: begin
                    if (engine_done) begin
                        remaining_bytes <= 32'h0;
                        channel_state   <= CH_COMPLETE;
                    end else if (engine_error) begin
                        channel_state <= CH_ERROR;
                    end
                end
                
                // ============================================================
                // COMPLETE: Transfer successful
                // ============================================================
                CH_COMPLETE: begin
                    channel_state <= CH_IDLE;
                end
                
                // ============================================================
                // ERROR: Transfer failed
                // ============================================================
                CH_ERROR: begin
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
