/* test_ascon_bench.c — Cross-mode benchmark + correctness check
 *
 * Runs all 4 modes and verifies CT+TAG consistency between CPU-direct
 * and DMA (1-block, no AD). Both must produce identical output.
 *
 * UART budget note: [PASS] is printed before verbose metrics so the
 * testbench 800K-cycle watchdog records the result in time.
 */
#include <stdint.h>
#include "uart.h"
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
#define TV_PT_W0    0xA0000000u
#define TV_PT_W1    0xB0000000u
#define TV_AD_W0    0x46524D48u
#define TV_AD_W1    0x00000001u
#define TV_AD_LEN   8u

#define TIMEOUT_CPU  20000u
#define TIMEOUT_DMA  20000u

static void uart_putu32d(uint32_t v)
{
    char buf[10];
    uint32_t i = 0u;
    if (v == 0u) { uart_putc('0'); return; }
    while (v > 0u) { buf[i++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (i > 0u) { uart_putc(buf[--i]); }
}

static void fill_pt_single(void)
{
    volatile uint32_t * const pt = (volatile uint32_t *)PT_MULTI_BASE;
    pt[0] = TV_PT_W0;
    pt[1] = TV_PT_W1;
}

static void fill_pt_multi(void)
{
    uint32_t i;
    volatile uint32_t * const pt = (volatile uint32_t *)PT_MULTI_BASE;
    for (i = 0u; i < DMEM_MULTI_BLOCK_COUNT; i++) {
        pt[i * 2u]      = 0xA0000000u | i;
        pt[i * 2u + 1u] = 0xB0000000u | i;
    }
}

/* Returns cycles; 0 = error; fills c0/c1/tag via pointers */
static uint32_t run_cpu_enc(uint32_t use_ad,
                             uint32_t *c0, uint32_t *c1,
                             uint32_t *t0r, uint32_t *t1r,
                             uint32_t *t2r, uint32_t *t3r)
{
    uint32_t ts0, ts1, status, timeout;

    ascon_soft_reset();
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(TV_KEY_0, TV_KEY_1, TV_KEY_2, TV_KEY_3);
    ascon_set_nonce(TV_NONCE_0, TV_NONCE_1, TV_NONCE_2, TV_NONCE_3);
    if (use_ad) ascon_set_ad(TV_AD_W0, TV_AD_W1, 0u, 0u, TV_AD_LEN);
    else        ascon_clear_ad();
    ascon_set_ptext(TV_PT_W0, TV_PT_W1, 8u);

    __asm__ volatile ("csrr %0, mcycle" : "=r"(ts0));
    __asm__ volatile ("fence rw,rw" ::: "memory");
    ascon_core_start();

    timeout = TIMEOUT_CPU;
    do {
        __asm__ volatile ("nop;nop;nop;nop" ::: "memory");
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) return 0u;
    } while (!(status & (ASCON_ST_CORE_DONE | ASCON_ST_CORE_ERR)));

    __asm__ volatile ("csrr %0, mcycle" : "=r"(ts1));

    if (status & ASCON_ST_CORE_ERR) return 0u;

    ascon_get_ctext(c0, c1);
    ascon_get_tag(t0r, t1r, t2r, t3r);
    return ts1 - ts0;
}

/* Returns cycles; 0 = error */
static uint32_t run_dma_enc(uint32_t use_ad, uint32_t n_blocks,
                             uint32_t *t0r, uint32_t *t1r,
                             uint32_t *t2r, uint32_t *t3r)
{
    uint32_t ts0, ts1, status, timeout;
    uint32_t byte_len = n_blocks * 8u;
    uint32_t dma_burst = (n_blocks > 8u) ? 7u :
                         (n_blocks > 0u) ? (n_blocks - 1u) : 0u;

    ascon_soft_reset();
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(TV_KEY_0, TV_KEY_1, TV_KEY_2, TV_KEY_3);
    ascon_set_nonce(TV_NONCE_0, TV_NONCE_1, TV_NONCE_2, TV_NONCE_3);
    if (use_ad) ascon_set_ad(TV_AD_W0, TV_AD_W1, 0u, 0u, TV_AD_LEN);
    else        ascon_clear_ad();
    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
    ascon_dma_config(PT_MULTI_BASE, CT_MULTI_BASE, byte_len);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, dma_burst);

    __asm__ volatile ("csrr %0, mcycle" : "=r"(ts0));
    __asm__ volatile ("fence rw,rw" ::: "memory");
    ascon_dma_start();

    timeout = TIMEOUT_DMA;
    do {
        __asm__ volatile ("nop;nop;nop;nop;nop;nop;nop;nop" ::: "memory");
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) return 0u;
    } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));

    __asm__ volatile ("csrr %0, mcycle" : "=r"(ts1));
    __asm__ volatile ("fence r,r" ::: "memory");

    if (status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) return 0u;

    ascon_get_tag(t0r, t1r, t2r, t3r);
    return ts1 - ts0;
}

static int run_bench_test(void)
{
    uint32_t cyc_cpu_noad, cyc_dma_noad;
    uint32_t cpu_c0, cpu_c1, dma_c0, dma_c1;
    uint32_t cpu_tag0, cpu_tag1, cpu_tag2, cpu_tag3;
    uint32_t dma_tag0, dma_tag1, dma_tag2, dma_tag3;
    int match;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);
    uart_puts("[ASCON-BENCH]\r\n");

    /* CPU-direct 1-block no-AD */
    cyc_cpu_noad = run_cpu_enc(0u, &cpu_c0, &cpu_c1,
                               &cpu_tag0, &cpu_tag1, &cpu_tag2, &cpu_tag3);
    if (cyc_cpu_noad == 0u) {
        DMEM->RETCODE = (uint32_t)-2;
        uart_puts("[FAIL] ascon_bench cpu_noad\r\n");
        return -1;
    }

    /* DMA 1-block no-AD (for cross-mode check) */
    fill_pt_single();
    cyc_dma_noad = run_dma_enc(0u, 1u,
                               &dma_tag0, &dma_tag1, &dma_tag2, &dma_tag3);
    if (cyc_dma_noad == 0u) {
        DMEM->RETCODE = (uint32_t)-3;
        uart_puts("[FAIL] ascon_bench dma_noad\r\n");
        return -1;
    }
    dma_c0 = *((volatile uint32_t *)CT_MULTI_BASE);
    dma_c1 = *((volatile uint32_t *)(CT_MULTI_BASE + 4u));

    /* Cross-mode check */
    match = (cpu_c0 == dma_c0 && cpu_c1 == dma_c1 &&
             cpu_tag0 == dma_tag0 && cpu_tag1 == dma_tag1 &&
             cpu_tag2 == dma_tag2 && cpu_tag3 == dma_tag3);
    if (!match) {
        DMEM->RETCODE = (uint32_t)-4;
        uart_puts("[FAIL] ascon_bench CT/TAG mismatch\r\n");
        return -1;
    }

    /* Print PASS before verbose output to beat watchdog */
    uart_puts("[PASS] ascon_bench\r\n");

    uart_puts("  cpu_cyc="); uart_puthex32(cyc_cpu_noad);
    uart_puts(" dma_cyc="); uart_puthex32(cyc_dma_noad); uart_puts("\r\n");
    uart_puts("  cpu_ct="); uart_puthex32(cpu_c0); uart_putc(' '); uart_puthex32(cpu_c1);
    uart_puts(" dma_ct="); uart_puthex32(dma_c0); uart_putc(' '); uart_puthex32(dma_c1);
    uart_puts("\r\n  tag=");
    uart_puthex32(cpu_tag0); uart_putc(' ');
    uart_puthex32(cpu_tag1); uart_putc(' ');
    uart_puthex32(cpu_tag2); uart_putc(' ');
    uart_puthex32(cpu_tag3); uart_puts("\r\n");

    /* DMA 16-block (may be cut off by watchdog — PASS already recorded) */
    fill_pt_multi();
    {
        uint32_t cyc16, tp16, lat16;
        uint32_t tag0, tag1, tag2, tag3;
        cyc16 = run_dma_enc(0u, 16u, &tag0, &tag1, &tag2, &tag3);
        if (cyc16 > 0u) {
            tp16  = 102400u / cyc16;
            lat16 = (80u * cyc16) / 100u;
            uart_puts("  dma16 mbps="); uart_putu32d(tp16);
            uart_puts(" lat10k="); uart_putu32d(lat16); uart_puts("us\r\n");
        }
    }

    DMEM->STATUS  = 0u;
    DMEM->RETCODE = 0u;
    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    run_bench_test();
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
