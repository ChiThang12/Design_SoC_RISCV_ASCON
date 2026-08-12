`timescale 1ns/1ps

// ============================================================================
// timer_channel.v — Single 32-bit Timer Channel
//
// Instantiated ×2 in timer_top for Timer0 and Timer1.
// Supports:
//   - Up-counting (count_dir=1) or down-counting (count_dir=0)
//   - Auto-reload: reload from load_val on timeout if auto_reload=1
//   - One-shot: stop on timeout if auto_reload=0
//   - IRQ output: pulses 1 cycle on timeout when irq_en=1
// ============================================================================

module timer_channel (
    input  wire        clk,
    input  wire        rst_n,

    // Control (from timer_regfile)
    input  wire        en,            // enable counting
    input  wire        auto_reload,   // 1=reload on timeout, 0=one-shot
    input  wire        irq_en,        // enable IRQ output
    input  wire        count_dir,     // 1=up, 0=down

    // Load value (also reload value)
    input  wire [31:0] load_val,

    // Status outputs (to timer_regfile)
    output reg  [31:0] count,         // current count value (read-only)
    output reg         timeout_flag,  // set on timeout, cleared by W1C write
    input  wire        timeout_clr,   // W1C clear pulse from regfile

    // IRQ
    output wire        irq
);

    // Timeout condition
    wire timeout_up   = (count_dir == 1'b1) && (count == 32'hFFFF_FFFF);
    wire timeout_down = (count_dir == 1'b0) && (count == 32'h0000_0000);
    wire timeout      = en && (timeout_up || timeout_down);

    // IRQ is a 1-cycle pulse on timeout (not the sticky flag)
    assign irq = timeout && irq_en;

    // [FIX-TIMER-LOAD] Detect rising edge of `en` to (re)load count from load_val.
    // Without this, count stays at its reset value (0) and the down-count timeout
    // (count==0) fires immediately on enable, never producing a useful delay.
    reg en_r;
    wire en_rise = en && !en_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count        <= 32'h0;
            timeout_flag <= 1'b0;
            en_r         <= 1'b0;
        end else begin
            en_r <= en;

            // Clear sticky flag on W1C write
            if (timeout_clr)
                timeout_flag <= 1'b0;

            if (en_rise) begin
                // Load initial count from load_val on enable
                count <= load_val;
            end else if (!en) begin
                // Disabled: hold count (do not reset — allows inspection)
            end else if (timeout) begin
                // Timeout this cycle
                timeout_flag <= 1'b1;
                if (auto_reload)
                    count <= load_val;
                // one-shot: count stays at boundary, en expected to be cleared by SW
            end else begin
                count <= count_dir ? count + 32'd1 : count - 32'd1;
            end
        end
    end

endmodule
