// ============================================================================
// Module: dma_arbiter
// ============================================================================
// Description:
//   Arbiter for DMA channels with priority-based scheduling
//
// Features:
//   - 4-channel fixed priority arbitration
//   - Configurable channel priorities (0=low, 3=high)
//   - Fair scheduling for same-priority channels (round-robin)
//   - One-hot grant encoding for fast selection
//
// Author: ChiThang
// ============================================================================

`include "dma/dma_defines.vh"

module dma_arbiter #(
    parameter NUM_CHANNELS = `NUM_DMA_CHANNELS
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Channel Request Interface
    // ========================================================================
    input wire [NUM_CHANNELS-1:0] channel_request,   // Request from each channel
    input wire [1:0]              channel_priority_0, // Priority for channel 0
    input wire [1:0]              channel_priority_1,
    input wire [1:0]              channel_priority_2,
    input wire [1:0]              channel_priority_3,
    
    // ========================================================================
    // Grant Interface
    // ========================================================================
    output reg [NUM_CHANNELS-1:0] channel_grant,     // One-hot grant signal
    output reg [1:0]              active_channel,    // Active channel ID
    output wire                   grant_valid,       // Grant is valid
    
    // ========================================================================
    // Engine Interface
    // ========================================================================
    input wire engine_busy,       // Engine is currently processing
    input wire engine_done        // Engine completed transfer
);

    // ========================================================================
    // Priority Encoding
    // ========================================================================
    wire [1:0] priority [0:NUM_CHANNELS-1];
    
    assign priority[0] = channel_priority_0;
    assign priority[1] = channel_priority_1;
    assign priority[2] = channel_priority_2;
    assign priority[3] = channel_priority_3;
    
    // ========================================================================
    // Round-Robin State (for same-priority channels)
    // ========================================================================
    reg [1:0] rr_pointer;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_pointer <= 2'd0;
        end else if (grant_valid && engine_done) begin
            // Move to next channel after grant
            rr_pointer <= rr_pointer + 1;
        end
    end
    
    // ========================================================================
    // Priority-based Arbitration Logic
    // ========================================================================
    reg [1:0] highest_priority;
    reg [NUM_CHANNELS-1:0] priority_mask [0:3]; // Mask for each priority level
    
    integer i;
    always @(*) begin
        // Clear masks
        for (i = 0; i < 4; i = i + 1) begin
            priority_mask[i] = 4'b0000;
        end
        
        // Build priority masks
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
            if (channel_request[i]) begin
                priority_mask[priority[i]][i] = 1'b1;
            end
        end
        
        // Find highest priority with pending requests
        if (|priority_mask[3])
            highest_priority = 2'd3;
        else if (|priority_mask[2])
            highest_priority = 2'd2;
        else if (|priority_mask[1])
            highest_priority = 2'd1;
        else
            highest_priority = 2'd0;
    end
    
    // ========================================================================
    // Channel Selection (within same priority - round-robin)
    // ========================================================================
    reg [1:0] selected_channel;
    reg       selection_valid;
    
    always @(*) begin
        selected_channel = 2'd0;
        selection_valid  = 1'b0;
        
        // Select from highest priority group using round-robin
        case (highest_priority)
            2'd3: begin
                if (priority_mask[3] != 4'b0000) begin
                    selection_valid = 1'b1;
                    // Round-robin among priority 3 channels
                    if (priority_mask[3][rr_pointer])
                        selected_channel = rr_pointer;
                    else if (priority_mask[3][(rr_pointer + 1) % 4])
                        selected_channel = (rr_pointer + 1) % 4;
                    else if (priority_mask[3][(rr_pointer + 2) % 4])
                        selected_channel = (rr_pointer + 2) % 4;
                    else
                        selected_channel = (rr_pointer + 3) % 4;
                end
            end
            
            2'd2: begin
                if (priority_mask[2] != 4'b0000) begin
                    selection_valid = 1'b1;
                    if (priority_mask[2][rr_pointer])
                        selected_channel = rr_pointer;
                    else if (priority_mask[2][(rr_pointer + 1) % 4])
                        selected_channel = (rr_pointer + 1) % 4;
                    else if (priority_mask[2][(rr_pointer + 2) % 4])
                        selected_channel = (rr_pointer + 2) % 4;
                    else
                        selected_channel = (rr_pointer + 3) % 4;
                end
            end
            
            2'd1: begin
                if (priority_mask[1] != 4'b0000) begin
                    selection_valid = 1'b1;
                    if (priority_mask[1][rr_pointer])
                        selected_channel = rr_pointer;
                    else if (priority_mask[1][(rr_pointer + 1) % 4])
                        selected_channel = (rr_pointer + 1) % 4;
                    else if (priority_mask[1][(rr_pointer + 2) % 4])
                        selected_channel = (rr_pointer + 2) % 4;
                    else
                        selected_channel = (rr_pointer + 3) % 4;
                end
            end
            
            2'd0: begin
                if (priority_mask[0] != 4'b0000) begin
                    selection_valid = 1'b1;
                    if (priority_mask[0][rr_pointer])
                        selected_channel = rr_pointer;
                    else if (priority_mask[0][(rr_pointer + 1) % 4])
                        selected_channel = (rr_pointer + 1) % 4;
                    else if (priority_mask[0][(rr_pointer + 2) % 4])
                        selected_channel = (rr_pointer + 2) % 4;
                    else
                        selected_channel = (rr_pointer + 3) % 4;
                end
            end
        endcase
    end
    
    // ========================================================================
    // Grant Generation
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            channel_grant  <= 4'b0000;
            active_channel <= 2'd0;
        end else begin
            if (!engine_busy && selection_valid) begin
                // Grant to selected channel
                channel_grant <= (4'b0001 << selected_channel);
                active_channel <= selected_channel;
            end else if (engine_done) begin
                // Clear grant after completion
                channel_grant <= 4'b0000;
            end
        end
    end
    
    assign grant_valid = |channel_grant;

endmodule