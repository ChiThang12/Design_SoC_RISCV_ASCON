`timescale 1ns/1ps

// ============================================================================
// gpio_iocell.v — GPIO IO Cell (Input synchronizer + interrupt detector)
//
// Per-pin responsibilities:
//   - 2-FF synchronizer on input path to avoid metastability
//   - Edge detector (rising / falling) for edge-triggered IRQ
//   - Level comparator for level-triggered IRQ
//   - OR-reduce all active IRQ bits → single gpio_irq output
// ============================================================================

module gpio_iocell #(
    parameter GPIO_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Raw IO signals (from pads, split to separate in/out/oe for simulation)
    input  wire [GPIO_WIDTH-1:0]   gpio_in_pad,   // sampled from pads
    input  wire [GPIO_WIDTH-1:0]   dir_reg,        // 1=output, 0=input
    input  wire [GPIO_WIDTH-1:0]   dout_reg,       // output data
    output wire [GPIO_WIDTH-1:0]   gpio_out_pad,   // drive to pads
    output wire [GPIO_WIDTH-1:0]   gpio_oe_pad,    // output enable

    // Synchronized input (for register read)
    output wire [GPIO_WIDTH-1:0]   din_sync,

    // IRQ configuration
    input  wire [GPIO_WIDTH-1:0]   irq_en,
    input  wire [GPIO_WIDTH-1:0]   irq_mode,   // 1=edge, 0=level
    input  wire [GPIO_WIDTH-1:0]   irq_pol,    // 1=rising/high, 0=falling/low

    // IRQ status (raw, before enable mask — captured in regfile as W1C)
    output wire [GPIO_WIDTH-1:0]   irq_raw,

    // Aggregated IRQ to PLIC
    output wire                    gpio_irq
);

    // ── Output drive ─────────────────────────────────────────────────────────
    assign gpio_out_pad = dout_reg;
    assign gpio_oe_pad  = dir_reg;   // 1=output enable

    // ── 2-FF synchronizer on input path ──────────────────────────────────────
    reg [GPIO_WIDTH-1:0] sync_ff1, sync_ff2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= {GPIO_WIDTH{1'b0}};
            sync_ff2 <= {GPIO_WIDTH{1'b0}};
        end else begin
            sync_ff1 <= gpio_in_pad;
            sync_ff2 <= sync_ff1;
        end
    end

    assign din_sync = sync_ff2;

    // ── Edge detector ────────────────────────────────────────────────────────
    reg [GPIO_WIDTH-1:0] sync_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sync_prev <= {GPIO_WIDTH{1'b0}};
        else
            sync_prev <= sync_ff2;
    end

    // Rising edge: 0→1 when irq_pol=1; Falling edge: 1→0 when irq_pol=0
    wire [GPIO_WIDTH-1:0] rising  = ~sync_prev &  sync_ff2;
    wire [GPIO_WIDTH-1:0] falling =  sync_prev & ~sync_ff2;
    wire [GPIO_WIDTH-1:0] edge_det = (irq_pol & rising) | (~irq_pol & falling);

    // Level: high when irq_pol=1; low when irq_pol=0
    wire [GPIO_WIDTH-1:0] level_det = irq_pol ? sync_ff2 : ~sync_ff2;

    // Raw IRQ per bit: edge or level depending on irq_mode
    assign irq_raw = irq_mode ? edge_det : level_det;

    // Aggregated: OR of all (irq_raw & irq_en)
    assign gpio_irq = |(irq_raw & irq_en);

endmodule
