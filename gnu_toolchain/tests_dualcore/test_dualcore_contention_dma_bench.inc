/* Dual-core contention benchmark:
 * keep the ASCON DMA path identical to the known-good 128B coherent test,
 * and inject a separate CPU1 producer-buffer read sweep during the DMA window.
 *
 * Variant selection:
 * - BENCH_FORWARD_HIT=1: CPU0 leaves producer lines dirty, CPU1 should be
 *   served through peer snoop + direct cache-to-cache forwarding.
 * - BENCH_FORWARD_HIT=0: CPU0 fences after producer writes, so CPU1 should
 *   fall back to memory refills for the first sweep.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"
#include "dmem_layout.h"

#ifndef BENCH_FORWARD_HIT
#error "BENCH_FORWARD_HIT must be defined before including benchmark body"
#endif

#ifndef SIG0_VALUE
#error "SIG0_VALUE must be defined before including benchmark body"
#endif

#ifndef SIG1_VALUE
#error "SIG1_VALUE must be defined before including benchmark body"
#endif

#ifndef AUX0_PASS_VALUE
#error "AUX0_PASS_VALUE must be defined before including benchmark body"
#endif

#ifndef AUX1_PASS_VALUE
#error "AUX1_PASS_VALUE must be defined before including benchmark body"
#endif

#define ASCON_OFS_ATU_BASE      0x150u
#define ASCON_OFS_ATU_WINDOW    0x154u
#define ASCON_OFS_DMA_COH_CTRL  0x158u

#define DMA_COH_CTRL_VALUE 3u
#define DMA_TIMEOUT_LIMIT  0x001FFFFFu
#define CPU0_DMA_START_GAP 2048u
#define CPU1_BOOT_DELAY    512u
#define CPU1_START_GAP     768u
#define CPU1_PHASE_TIMEOUT 0x0007FFFFu

#define TV_KEY_0    0x00010203u
#define TV_KEY_1    0x04050607u
#define TV_KEY_2    0x08090A0Bu
#define TV_KEY_3    0x0C0D0E0Fu
#define TV_NONCE_0  0x10111213u
#define TV_NONCE_1  0x14151617u
#define TV_NONCE_2  0x18191A1Bu
#define TV_NONCE_3  0x1C1D1E1Fu

#define PRODUCER_BASE       0x10000340u
#define EVICT_BASE          0x10000740u
#define PRODUCER_LINE_COUNT 12u
#define WORDS_PER_LINE      4u
#define PRODUCER_WORD_COUNT (PRODUCER_LINE_COUNT * WORDS_PER_LINE)

static inline void bench_fence_flush_invalidate(void)
{
    __asm__ volatile ("fence rw,rw" ::: "memory");
}

static void fail_with_capture(uint32_t a0, uint32_t a1)
{
    DMEM32(AUX0_ADDR) = a0;
    DMEM32(AUX1_ADDR) = a1;
    __asm__ volatile ("fence w,w" ::: "memory");
    dualcore_fail_stop();
}

static void spin_delay(uint32_t cycles)
{
    for (uint32_t i = 0; i < cycles; i++) {
        __asm__ volatile ("nop");
    }
}

static inline uint32_t producer_word(uint32_t idx)
{
    uint32_t mix = (idx << 12) ^ (idx << 5) ^ (idx << 1);
    return 0xC2C00000u ^ (BENCH_FORWARD_HIT ? 0x01000000u : 0x02000000u) ^
           (mix + 0x55AAu);
}

static void prepare_producer_region(void)
{
    volatile uint32_t *buf = (volatile uint32_t *)PRODUCER_BASE;

    for (uint32_t i = 0; i < PRODUCER_WORD_COUNT; i++) {
        buf[i] = producer_word(i);
    }
    __asm__ volatile ("" ::: "memory");
}

static void evict_producer_region_to_memory(void)
{
    volatile uint32_t *buf = (volatile uint32_t *)EVICT_BASE;

    for (uint32_t i = 0; i < PRODUCER_WORD_COUNT; i++) {
        buf[i] = 0xE7100000u ^ (i * 0x01010101u);
    }
    __asm__ volatile ("" ::: "memory");
}

static void prepare_dma_plaintext_without_fence(void)
{
    volatile uint32_t *pt = (volatile uint32_t *)PT_MULTI_BASE;

    for (uint32_t i = 0u; i < (DMEM_MULTI_PT_LEN / 4u); i++) {
        pt[i] = (i & 1u) ? 0x33334444u : 0x11112222u;
    }

    for (uint32_t i = 0u; i < DMEM_MULTI_BLOCK_COUNT; i++) {
        pt[i * 2u]      = 0xA5000000u | i;
        pt[i * 2u + 1u] = 0x5A000000u | i;
    }

    __asm__ volatile ("" ::: "memory");
}

static void prepare_dma_output_stale_region(void)
{
    volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

    for (uint32_t i = 0u; i < (DMEM_MULTI_CT_LEN / 4u); i++) {
        ct[i] = 0xDEAD0000u ^ (i * 0x01010101u);
    }
    __asm__ volatile ("" ::: "memory");
}

static void configure_ascon_dma_bench(void)
{
    ascon_soft_reset();
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(TV_KEY_0, TV_KEY_1, TV_KEY_2, TV_KEY_3);
    ascon_set_nonce(TV_NONCE_0, TV_NONCE_1, TV_NONCE_2, TV_NONCE_3);
    ascon_clear_ad();

    /* Match the known-good 128B DMA setup exactly. */
    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_BASE, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_WINDOW, 0u);
    ASCON_WRITE(ASCON_OFS_DMA_COH_CTRL, DMA_COH_CTRL_VALUE);
    ascon_dma_config(PT_MULTI_BASE, CT_MULTI_BASE, DMEM_MULTI_PT_LEN);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);
}

static uint32_t start_dma_and_wait(void)
{
    uint32_t status;
    uint32_t timeout = DMA_TIMEOUT_LIMIT;

    ascon_dma_start();
    do {
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            fail_with_capture(0xFFFF1001u, status);
        }
    } while ((status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) == 0u);

    return status;
}

static void wait_for_cpu0_ready(void)
{
    uint32_t timeout = CPU1_PHASE_TIMEOUT;

    while (DMEM32(RESULT_ADDR) != RESULT_RUNNING) {
        if (--timeout == 0u) {
            fail_with_capture(0xFFFF2001u, DMEM32(RESULT_ADDR));
        }
        __asm__ volatile ("nop");
    }

    timeout = CPU1_PHASE_TIMEOUT;
    while (DMEM32(HEARTBEAT_ADDR) < 1u) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        if (--timeout == 0u) {
            fail_with_capture(0xFFFF2002u, DMEM32(HEARTBEAT_ADDR));
        }
        __asm__ volatile ("nop");
    }
}

static void consume_and_check_region(void)
{
    volatile uint32_t *buf = (volatile uint32_t *)PRODUCER_BASE;

    for (uint32_t i = 0; i < PRODUCER_WORD_COUNT; i++) {
        uint32_t got = buf[i];
        uint32_t exp = producer_word(i);
        if (got != exp) {
            fail_with_capture(exp, got);
        }
    }
}

int main(void)
{
    uint32_t hart = dualcore_hartid();

    if (hart == 0u) {
        uint32_t status;
        volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

        dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
        configure_ascon_dma_bench();
        prepare_producer_region();
#if BENCH_FORWARD_HIT
        __asm__ volatile ("" ::: "memory");
#else
        evict_producer_region_to_memory();
#endif
        prepare_dma_plaintext_without_fence();
        prepare_dma_output_stale_region();

        DMEM32(HEARTBEAT_ADDR) = 1u;
        __asm__ volatile ("fence w,w" ::: "memory");
        spin_delay(CPU0_DMA_START_GAP);

        status = start_dma_and_wait();
        if ((status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) != 0u) {
            fail_with_capture(0xFFFF1002u, status);
        }
        if ((ct[0] == 0u) && (ct[1] == 0u)) {
            fail_with_capture(0xFFFF1003u, ct[0]);
        }

        DMEM32(SHARED_COUNT_ADDR) = PRODUCER_LINE_COUNT;
        DMEM32(HEARTBEAT_ADDR) = 2u;
        DMEM32(AUX0_ADDR) = AUX0_PASS_VALUE;
        __asm__ volatile ("fence w,w" ::: "memory");

        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }
    }

    spin_delay(CPU1_BOOT_DELAY);
    wait_for_cpu0_ready();
    spin_delay(CPU1_START_GAP);
    consume_and_check_region();

    DMEM32(HEARTBEAT_ADDR) = 3u;
    DMEM32(AUX1_ADDR) = AUX1_PASS_VALUE;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }

    return 0;
}
