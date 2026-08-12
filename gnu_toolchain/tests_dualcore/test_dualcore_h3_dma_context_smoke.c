/* H3 DMA context smoke test.
 *
 * Goal:
 * - Start ASCON DMA from context 1.
 * - Switch CONTEXT_SEL back to context 0 while DMA is in flight.
 * - Let the testbench verify dma_context_id_active latched context 1.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"
#include "dmem_layout.h"

#define SIG0_VALUE 0x3C00E101u
#define SIG1_VALUE 0x3C00E102u

#define ASCON_OFS_ATU_BASE       0x150u
#define ASCON_OFS_ATU_WINDOW     0x154u
#define ASCON_OFS_DMA_COH_CTRL   0x158u

#define DMA_COH_CTRL_VALUE 3u
#define DMA_TIMEOUT_LIMIT  0x001FFFFFu

#define CTX0_KEY0   0x00112233u
#define CTX0_KEY1   0x44556677u
#define CTX0_KEY2   0x8899AABBu
#define CTX0_KEY3   0xCCDDEEFFu
#define CTX0_NONCE0 0x10213243u
#define CTX0_NONCE1 0x54657687u
#define CTX0_NONCE2 0x98A9BACBu
#define CTX0_NONCE3 0xDCEDFE0Fu

#define CTX1_KEY0   0x00010203u
#define CTX1_KEY1   0x04050607u
#define CTX1_KEY2   0x08090A0Bu
#define CTX1_KEY3   0x0C0D0E0Fu
#define CTX1_NONCE0 0x10111213u
#define CTX1_NONCE1 0x14151617u
#define CTX1_NONCE2 0x18191A1Bu
#define CTX1_NONCE3 0x1C1D1E1Fu

static inline void ascon_write_raw(uint32_t offset, uint32_t val)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    *p = val;
}

static inline uint32_t ascon_read_raw(uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    return *p;
}

static void fail_with_marker(uint32_t a0, uint32_t a1)
{
    DMEM32(AUX0_ADDR) = a0;
    DMEM32(AUX1_ADDR) = a1;
    __asm__ volatile ("fence w,w" ::: "memory");
    dualcore_fail_stop();
}

static void configure_ctx0(void)
{
    ascon_select_context(0u);
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(CTX0_KEY0, CTX0_KEY1, CTX0_KEY2, CTX0_KEY3);
    ascon_set_nonce(CTX0_NONCE0, CTX0_NONCE1, CTX0_NONCE2, CTX0_NONCE3);
    ascon_clear_ad();
    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
}

static void configure_ctx1_dma(void)
{
    ascon_select_context(1u);
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(CTX1_KEY0, CTX1_KEY1, CTX1_KEY2, CTX1_KEY3);
    ascon_set_nonce(CTX1_NONCE0, CTX1_NONCE1, CTX1_NONCE2, CTX1_NONCE3);
    ascon_clear_ad();
    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_BASE, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_WINDOW, 0u);
    ASCON_WRITE(ASCON_OFS_DMA_COH_CTRL, DMA_COH_CTRL_VALUE);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);
    ascon_dma_config(PT_MULTI_BASE, CT_MULTI_BASE, DMEM_MULTI_PT_LEN);
}

static void seed_dma_buffers(void)
{
    volatile uint32_t *pt = (volatile uint32_t *)PT_MULTI_BASE;
    volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

    for (uint32_t i = 0; i < (DMEM_MULTI_PT_LEN / 4u); i++) {
        pt[i] = 0x51000000u + i;
    }
    for (uint32_t i = 0; i < (DMEM_MULTI_CT_LEN / 4u); i++) {
        ct[i] = 0xA5A50000u + i;
    }
    __asm__ volatile ("fence w,w" ::: "memory");
}

static uint32_t wait_dma_done(void)
{
    uint32_t status;
    uint32_t timeout = DMA_TIMEOUT_LIMIT;

    do {
        status = ascon_read_raw(ASCON_OFS_STATUS);
        if (--timeout == 0u) {
            fail_with_marker(0x3C0E3001u, status);
        }
    } while ((status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) == 0u);

    return status;
}

int main(void)
{
    uint32_t hart = dualcore_hartid();

    if (hart != 0u) {
        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
            __asm__ volatile ("nop");
        }
    }

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
    ascon_soft_reset();

    seed_dma_buffers();
    configure_ctx1_dma();

    DMEM32(SHARED_COUNT_ADDR) = 1u;
    DMEM32(HEARTBEAT_ADDR) = 1u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_write_raw(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

    configure_ctx0();

    DMEM32(SHARED_COUNT_ADDR) = 2u;
    DMEM32(HEARTBEAT_ADDR) = 2u;
    __asm__ volatile ("fence w,w" ::: "memory");

    uint32_t status = wait_dma_done();
    if ((status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) != 0u) {
        fail_with_marker(0x3C0E3002u, status);
    }

    DMEM32(AUX0_ADDR) = 0x3C0D3000u;
    DMEM32(AUX1_ADDR) = status;
    DMEM32(SHARED_COUNT_ADDR) = 3u;
    DMEM32(HEARTBEAT_ADDR) = 3u;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }
}
