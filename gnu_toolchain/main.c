/* ============================================================================
 * main.c — ASCON DMA Firmware v8.0
 *
 * OPTIMIZATIONS vs v7.0:
 *   1. Removed all NOP_BARRIER() — ASCON_WRITE already has "fence w, w"
 *   2. Single "fence rw, rw" before DMA start drains store buffer for DMEM
 *   3. Single polling loop on DMA_DONE (fires after ALL write-backs:
 *      ciphertext blocks + 128-bit tag), so separate CORE_DONE poll is gone
 *   4. "fence r, r" after poll before DMEM reads (AXI→SRAM coherency)
 *
 * WRITE-BACK DATA PATH (DMA mode):
 *   CORE → WR FIFO (32-bit words) → dma_write_engine → AXI-64 → SRAM
 *   WR FIFO push order: ctext_0, ctext_1, tag_0, tag_1, tag_2, tag_3
 *   Write engine pops 2 × 32-bit per AXI beat (AWSIZE=3'b011 = 8 B):
 *     WDATA[31:0]  = 1st pop → lower byte address  (e.g., CTEXT_0)
 *     WDATA[63:32] = 2nd pop → higher byte address (e.g., CTEXT_1)
 *   DMEM layout after DMA_DONE (starting at CTEXT_0 = DMEM_BASE+0x10):
 *     +0x00 CTEXT_0   +0x04 CTEXT_1
 *     +0x08 TAG_0     +0x0C TAG_1
 *     +0x10 TAG_2     +0x14 TAG_3
 *
 * CTRL REGISTER (0x020) CONTRACT:
 *   bit[0] CORE_START  — gated by DMA_EN in slave: inactive when bit[2]=1
 *   bit[1] SOFT_RST
 *   bit[2] DMA_EN      — fires dma_start; CORE started internally by DMA FSM
 *   CTRL = 0x5 (DMA_EN | CORE_START) is the correct value; slave gates bit[0]
 *   when bit[2] is set, so only dma_start fires.
 *
 * COMPILE:  ./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
 * ============================================================================ */

#include <stdint.h>
#include "ascon.h"
#include "dmem_layout.h"

/* ── Test vectors ──────────────────────────────────────────────────────────── */
#define MY_KEY_0    0xDEADBEEFu
#define MY_KEY_1    0xCAFEBABEu
#define MY_KEY_2    0x01234567u
#define MY_KEY_3    0x89ABCDEFu

#define MY_NONCE_0  0x11111111u
#define MY_NONCE_1  0x22222222u
#define MY_NONCE_2  0x33333333u
#define MY_NONCE_3  0x44444444u

#define MY_PTEXT_0  0xDEADBEEFu
#define MY_PTEXT_1  0x01234567u

#define TIMEOUT_LIMIT  0x000FFFFFu

/* =========================================================================
 * main
 * ========================================================================= */
int main(void)
{
    uint32_t status  = 0u;
    uint32_t retcode = 0u;
    uint32_t timeout;

    /* 1. CPU store plaintext → DMEM ─────────────────────────────────────────
     * Plain volatile stores; the "fence rw, rw" at step 7 guarantees these
     * reach SRAM before the DMA read engine issues its first AXI read.      */
    DMEM->PTEXT_0 = MY_PTEXT_0;
    DMEM->PTEXT_1 = MY_PTEXT_1;

    /* 2. Soft reset ──────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);

    /* 3. Mode: ASCON-128 Encrypt ─────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);

    /* 4. Key (128-bit = 4 × 32-bit) ─────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
    ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
    ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
    ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);

    /* 5. Nonce (128-bit = 4 × 32-bit) ───────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
    ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
    ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
    ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);

    /* 6. DMA config ──────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_DMA_SRC,   DMEM_DMA_SRC_ADDR);     /* PTEXT_0 addr      */
    ASCON_WRITE(ASCON_OFS_DMA_DST,   DMEM_DMA_OUTPUT_ADDR);  /* CTEXT_0 addr      */
    ASCON_WRITE(ASCON_OFS_DMA_LEN,   DMEM_DMA_INPUT_LEN);    /* 8 bytes (2 words) */
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 0u);                     /* ARLEN=0: 1 beat   */
    ASCON_WRITE(ASCON_OFS_DATA_LEN,  DMEM_DMA_INPUT_LEN);

    /* 7. Full barrier — drain store buffer before DMA reads DMEM ───────────
     * Orders all preceding stores (steps 1..6) before any AXI transaction
     * issued by the DMA engine or ASCON slave after step 8.                */
    __asm__ volatile ("fence rw, rw" ::: "memory");

    /* 8. DMA + CORE start: CTRL = 0x5 (DMA_EN | CORE_START) ────────────────
     * Slave gates CORE_START when DMA_EN=1, so only dma_start fires here.
     * CORE is kicked internally by dma_ctrl_fsm when first block is ready.  */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

    /* 9. Poll DMA_DONE ───────────────────────────────────────────────────────
     * DMA_DONE fires after the last AXI B-channel response, meaning all
     * ciphertext words AND the 128-bit tag have been written to DMEM.
     * No separate CORE_DONE poll needed: DMA_DONE ⇒ CORE is already done.  */
    timeout = TIMEOUT_LIMIT;
    do {
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            retcode = (uint32_t)(-2);
            goto done;
        }
    } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));

    if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) {
        retcode = (uint32_t)(-1);
        goto done;
    }

    /* Ensure DMA AXI write-backs are visible to subsequent CPU DMEM loads.  */
    __asm__ volatile ("fence r, r" ::: "memory");

    retcode = 0u;

done:
    /* 10. Save STATUS + RETCODE to DMEM for post-simulation inspection ─────── */
    DMEM->STATUS  = status;
    DMEM->RETCODE = retcode;

    /* 11. Halt ───────────────────────────────────────────────────────────── */
    while (1) __asm__ volatile ("nop");
    return 0;
}
