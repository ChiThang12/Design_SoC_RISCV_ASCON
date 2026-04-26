// ============================================================================
// wdt_core.v — Watchdog Timer Core
//
// Down-counter watchdog. Software must periodically write 0xDEAD_FEED to
// WDT_FEED register to kick (reload) the counter. If the counter reaches 0:
//   - wdt_irq is asserted (sticky, cleared by W1C write to WDT_STATUS)
//   - After WDT_RST_DELAY cycles, wdt_rst_req is asserted (active-high)
//     → This can be fed back to soc_top as an additional reset source.
//
// Magic feed value: 0xDEAD_FEED (any other value is ignored).
// ============================================================================

module wdt_core (
    input  wire        clk,
    input  wire        rst_n,

    // Control (from timer_regfile)
    input  wire        en,            // enable watchdog
    input  wire        irq_en,        // enable IRQ on expiry

    // Load value
    input  wire [31:0] load_val,

    // Feed pulse (from regfile: write 0xDEAD_FEED → feed_pulse=1 for 1 cycle)
    input  wire        feed_pulse,

    // Status outputs
    output reg  [31:0] count,
    output reg         expired_flag,  // sticky, W1C
    input  wire        expired_clr,   // W1C clear pulse from regfile

    // Outputs
    output wire        wdt_irq,
    output reg         wdt_rst_req    // active-high reset request (holds for 4 cycles)
);

    localparam WDT_RST_CYCLES = 4;

    reg [2:0] rst_cnt;    // counts down after expiry to generate reset pulse

    wire expired = en && (count == 32'h0);

    assign wdt_irq = expired_flag && irq_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count        <= 32'hFFFF_FFFF;
            expired_flag <= 1'b0;
            wdt_rst_req  <= 1'b0;
            rst_cnt      <= 3'd0;
        end else begin
            // W1C clear
            if (expired_clr)
                expired_flag <= 1'b0;

            // Feed watchdog
            if (feed_pulse && en) begin
                count <= load_val;
            end else if (en && !expired) begin
                count <= count - 32'd1;
            end

            // Expiry handling
            if (expired && !expired_flag) begin
                expired_flag <= 1'b1;
                rst_cnt      <= WDT_RST_CYCLES[2:0];
            end

            // Reset pulse generation
            if (rst_cnt != 3'd0) begin
                wdt_rst_req <= 1'b1;
                rst_cnt     <= rst_cnt - 3'd1;
            end else begin
                wdt_rst_req <= 1'b0;
            end
        end
    end

endmodule
