// ============================================================================
// Module  : ascon_irq_ctrl
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_axi_slave
//
// Description:
//   Interrupt controller for the ASCON accelerator IP.
//
//   Combines sticky status flags with IRQ_EN mask bits to produce a single
//   level-triggered interrupt output.
//
//   irq = (status_done      & irq_en[0])   -- crypto core finished
//       | (status_dma_done  & irq_en[1])   -- DMA transfer finished
//       | (status_error     & irq_en[2])   -- crypto error
//       | (status_dma_error & irq_en[2])   -- DMA AXI error
//
//   The interrupt is level-triggered and held high until the source flag is
//   cleared by a SOFT_RST write (handled in ascon_reg_bank).
//
//   Connect irq to a PLIC or GIC input on the SoC.
// ============================================================================

module ascon_irq_ctrl (
    // ── Sticky status flags (from ascon_reg_bank) ─────────────────────────────
    input  wire   status_done,
    input  wire   status_dma_done,
    input  wire   status_error,
    input  wire   status_dma_error,

    // ── IRQ enable mask (from ascon_reg_bank, register IRQ_EN 0x00C) ──────────
    input  wire   irq_en_done,      // IRQ_EN[0]
    input  wire   irq_en_dma_done,  // IRQ_EN[1]
    input  wire   irq_en_error,     // IRQ_EN[2]

    // ── Interrupt output ──────────────────────────────────────────────────────
    output wire   irq
);

    assign irq = (status_done      & irq_en_done)    |
                 (status_dma_done  & irq_en_dma_done) |
                 (status_error     & irq_en_error)    |
                 (status_dma_error & irq_en_error);

endmodule