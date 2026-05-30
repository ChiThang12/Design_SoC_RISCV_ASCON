`timescale 1ns/1ps

// ============================================================================
// Module  : plic_top
// Project : RISC-V SoC
//
// RISC-V Platform-Level Interrupt Controller (PLIC) v1.0
// 1 context (hart 0, M-mode). 32 sources (source 0 reserved).
// Address: S9 = 0x5004_0000, size 4KB (remapped layout — xem plic_regfile.v)
//
// Hierarchy:
//   plic_top
//   ├── plic_regfile          — AXI4-Full slave + register bank
//   ├── plic_gateway ×31      — per-source gateway (edge-latch + claim/complete)
//   └── plic_priority_encoder — tìm source ưu tiên cao nhất
//
// Source Assignment (từ SoC_Register_Map_Full.docx section 10):
//   Source 0  : reserved (always 0)
//   Source 1  : UART TX IRQ  (uart_top)
//   Source 2  : UART RX IRQ  (uart_top)
//   Source 3  : SPI IRQ      (spi_top)
//   Source 4  : GPIO IRQ     (gpio_top)
//   Source 5  : TIMER0 IRQ   (timer_wdt_top)
//   Source 6  : TIMER1 IRQ   (timer_wdt_top)
//   Source 7  : WDT WARN IRQ (timer_wdt_top)
//   Source 8  : ASCON IRQ    (ascon_ip_top / soc_ctrl_slave.irq_out)
//   Source 9..31: reserved (tie irq_src[9:31] = 0 in soc_top)
//
// Kết nối trong soc_top.v:
//   plic_top u_plic (
//       .clk        (clk),
//       .rst_n      (fabric_rst_n),
//       .s_axi_*    (s9_*),
//       .irq_src    ({23'd0, soc_ctrl_irq_out, wdt_irq, timer1_irq,
//                     timer0_irq, gpio_irq, spi_irq,
//                     uart_rx_irq, uart_tx_irq, 1'b0}),
//       .meip       (external_irq)   // → CPU
//   );
//
// Remapping 4KB:
//   priority[N]  : 0x000 + 4×N  (N=0..11 trong 4KB, đủ cho 12 sources)
//   pending[0]   : 0x080         (remapped từ spec 0x001000)
//   enable[0]    : 0x100         (remapped từ spec 0x002000)
//   threshold    : 0x200         (remapped từ spec 0x200000)
//   claim/complete: 0x204        (remapped từ spec 0x200004)
// ============================================================================

`include "plic/rtl/plic_regfile.v"
`include "plic/rtl/plic_gateway.v"
`include "plic/rtl/plic_priority_encoder.v"

module plic_top #(
    parameter NUM_SRC    = 32,
    parameter PRIO_W     = 3,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // =========================================================================
    // AXI4-Full Slave Interface (từ crossbar S9)
    // =========================================================================
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // =========================================================================
    // Interrupt Sources (NUM_SRC bits, source 0 = bit 0 always 0)
    // =========================================================================
    input  wire [NUM_SRC-1:0]     irq_src,   // irq_src[0] ignored (reserved)

    // =========================================================================
    // Output → CPU external interrupt
    // =========================================================================
    output wire                   meip       // Machine External Interrupt Pending
);

    localparam ID_W = $clog2(NUM_SRC);

    // =========================================================================
    // Internal wires
    // =========================================================================
    wire [PRIO_W*NUM_SRC-1:0] priority_flat;
    wire [NUM_SRC-1:0]         enable;
    wire [PRIO_W-1:0]          threshold;
    wire                       claim_pulse;
    wire                       complete_pulse;
    wire [ID_W-1:0]            complete_id;
    wire [ID_W-1:0]            claim_id;
    wire [PRIO_W-1:0]          claim_prio;
    wire [NUM_SRC-1:0]         pending;

    // =========================================================================
    // plic_regfile — AXI4-Full slave + config registers
    // =========================================================================
    plic_regfile #(
        .NUM_SRC    (NUM_SRC),
        .PRIO_W     (PRIO_W),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_regfile (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awid     (s_axi_awid),    .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),   .s_axi_awsize  (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst), .s_axi_awprot  (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid), .s_axi_awready (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),   .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),   .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bid      (s_axi_bid),     .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),  .s_axi_bready  (s_axi_bready),
        .s_axi_arid     (s_axi_arid),    .s_axi_araddr  (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),   .s_axi_arsize  (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst), .s_axi_arprot  (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid), .s_axi_arready (s_axi_arready),
        .s_axi_rid      (s_axi_rid),     .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),   .s_axi_rlast   (s_axi_rlast),
        .s_axi_rvalid   (s_axi_rvalid),  .s_axi_rready  (s_axi_rready),
        .priority_flat  (priority_flat),
        .enable         (enable),
        .threshold      (threshold),
        .claim_pulse    (claim_pulse),
        .complete_pulse (complete_pulse),
        .complete_id    (complete_id),
        .claim_id_in    (claim_id),
        .pending_in     (pending)
    );

    // =========================================================================
    // plic_gateway ×NUM_SRC — per-source gateway
    // Source 0: tie-off (reserved per PLIC spec)
    // =========================================================================
    assign pending[0] = 1'b0;

    genvar gi;
    generate
        for (gi = 1; gi < NUM_SRC; gi = gi + 1) begin : gen_gw
            plic_gateway u_gw (
                .clk      (clk),
                .rst_n    (rst_n),
                .irq_in   (irq_src[gi]),
                // claim pulse fires only for this source
                .claim    (claim_pulse    && (claim_id    == gi[ID_W-1:0])),
                .complete (complete_pulse && (complete_id == gi[ID_W-1:0])),
                .pending  (pending[gi])
            );
        end
    endgenerate

    // =========================================================================
    // plic_priority_encoder — find highest-priority pending+enabled source
    // =========================================================================
    plic_priority_encoder #(
        .NUM_SRC (NUM_SRC),
        .PRIO_W  (PRIO_W)
    ) u_enc (
        .pending        (pending),
        .enabled        (enable),
        .threshold      (threshold),
        .priority_flat  (priority_flat),
        .claim_id       (claim_id),
        .claim_prio     (claim_prio),
        .irq_pending    (meip)
    );

`ifdef DEBUG_WDATA
    reg prev_pending8;
    reg prev_meip;
    reg prev_irq8;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_pending8 <= 1'b0;
            prev_meip     <= 1'b0;
            prev_irq8     <= 1'b0;
        end else begin
            if (pending[8] !== prev_pending8 || meip !== prev_meip)
                $display("[%6d] [PLIC-MON] irq_src8=%b pending8=%b enable8=%b prio8=%0d thr=%0d meip=%b claim_id=%0d",
                         $time, irq_src[8], pending[8], enable[8],
                         priority_flat[PRIO_W*8 +: PRIO_W], threshold, meip, claim_id);
            // Track irq_src[8] at clock edge
            if (irq_src[8] !== prev_irq8)
                $display("[%6d] [PLIC-IRQ8] irq_src8 changed: %b→%b  pending8=%b in_service(gw8)=? enable8=%b",
                         $time, prev_irq8, irq_src[8], pending[8], enable[8]);
            prev_pending8 <= pending[8];
            prev_meip     <= meip;
            prev_irq8     <= irq_src[8];
        end
    end
`endif

endmodule