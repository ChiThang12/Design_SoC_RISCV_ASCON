/* test_ascon_dma_coherent_nofence_128b.c
 * Software-fenced no-coherent ASCON DMA 128B benchmark/control test.
 * The plaintext buffer is written through the CPU DCache and DMA is started
 * without a hardware fence/flush. The testbench verifies the snoop hit path. */
#include <stdint.h>
#include "ascon.h"
#include "dmem_layout.h"

#define TV_KEY_0    0x00010203u
#define TV_KEY_1    0x04050607u
#define TV_KEY_2    0x08090A0Bu
#define TV_KEY_3    0x0C0D0E0Fu
#define TV_NONCE_0  0x10111213u
#define TV_NONCE_1  0x14151617u
#define TV_NONCE_2  0x18191A1Bu
#define TV_NONCE_3  0x1C1D1E1Fu

#define ASCON_OFS_ATU_BASE      0x150u
#define ASCON_OFS_ATU_WINDOW    0x154u
#define ASCON_OFS_DMA_COH_CTRL  0x158u
#define ASCON_OFS_RESULT_MAILBOX 0x138u

#define RET_RUNNING 0xCAFE0001u
#define RET_PASS    0xCAFE0000u
#define RET_TIMEOUT 0xFFFF0001u
#define RET_DMAERR  0xFFFF0002u
#define RET_BADOUT  0xFFFF0003u

#define PT_WORD0    0xA5000000u
#define PT_WORD1    0x5A000000u
#define STALE_WORD0 0x11112222u
#define STALE_WORD1 0x33334444u

#define TIMEOUT_LIMIT 0x001FFFFFu

#ifndef DMA_COH_CTRL_VALUE
#define DMA_COH_CTRL_VALUE 0u
#endif

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

static void dirty_plaintext_without_fence(void)
{
    volatile uint32_t *pt = (volatile uint32_t *)PT_MULTI_BASE;
    uint32_t i;

    for (i = 0u; i < (DMEM_MULTI_PT_LEN / 4u); i++)
        pt[i] = (i & 1u) ? STALE_WORD1 : STALE_WORD0;

    for (i = 0u; i < DMEM_MULTI_BLOCK_COUNT; i++) {
        pt[i * 2u]      = PT_WORD0 | i;
        pt[i * 2u + 1u] = PT_WORD1 | i;
    }

    __asm__ volatile ("" ::: "memory");
}

int main(void)
{
    uint32_t status;
    uint32_t timeout;
    volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

    DMEM->RETCODE = RET_RUNNING;
    DMEM->STATUS  = 0u;
    ascon_write_raw(ASCON_OFS_RESULT_MAILBOX, RET_RUNNING);

    ascon_soft_reset();
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(TV_KEY_0, TV_KEY_1, TV_KEY_2, TV_KEY_3);
    ascon_set_nonce(TV_NONCE_0, TV_NONCE_1, TV_NONCE_2, TV_NONCE_3);
    ascon_clear_ad();

    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_BASE, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_WINDOW, 0u);
    ASCON_WRITE(ASCON_OFS_DMA_COH_CTRL, DMA_COH_CTRL_VALUE);
    ascon_dma_config(PT_MULTI_BASE, CT_MULTI_BASE, DMEM_MULTI_PT_LEN);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);

    dirty_plaintext_without_fence();

    /* Baseline/control: use ASCON_WRITE so the software fence flushes dirty plaintext before DMA. */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

    timeout = TIMEOUT_LIMIT;
    do {
        status = ascon_read_raw(ASCON_OFS_STATUS);
        if (--timeout == 0u) {
            DMEM->STATUS = status;
            DMEM->RETCODE = RET_TIMEOUT;
            ascon_write_raw(ASCON_OFS_RESULT_MAILBOX, RET_TIMEOUT);
            while (1) __asm__ volatile ("nop");
        }
    } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));

    DMEM->STATUS = status;
    if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) {
        DMEM->RETCODE = RET_DMAERR;
        ascon_write_raw(ASCON_OFS_RESULT_MAILBOX, RET_DMAERR);
        while (1) __asm__ volatile ("nop");
    }

    if ((ct[0] == 0u) && (ct[1] == 0u)) {
        DMEM->RETCODE = RET_BADOUT;
        ascon_write_raw(ASCON_OFS_RESULT_MAILBOX, RET_BADOUT);
        while (1) __asm__ volatile ("nop");
    }

    DMEM->RETCODE = RET_PASS;
    ascon_write_raw(ASCON_OFS_RESULT_MAILBOX, RET_PASS);
    while (1) __asm__ volatile ("nop");
    return 0;
}
