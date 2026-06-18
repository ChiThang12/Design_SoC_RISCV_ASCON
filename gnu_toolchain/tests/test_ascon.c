/* test_ascon.c - ASCON DMA AEAD coverage test
 *
 * Covers:
 *   1. DMA encrypt with empty AD.
 *   2. DMA encrypt with AD.
 *   3. CPU-direct decrypt of the last DMA block with matching tag.
 *   4. CPU-direct decrypt with a bad tag and expect TAG_MISMATCH.
 */
#include <stdint.h>
#include "uart.h"
#include "ascon.h"
#include "dmem_layout.h"

#define MY_KEY_0    0xDEADBEEFu
#define MY_KEY_1    0xCAFEBABEu
#define MY_KEY_2    0x01234567u
#define MY_KEY_3    0x89ABCDEFu

#define MY_NONCE_0  0x11111111u
#define MY_NONCE_1  0x22222222u
#define MY_NONCE_2  0x33333333u
#define MY_NONCE_3  0x44444444u

#define TIMEOUT_LIMIT   0x003FFFFFu

#define ERR_TIMEOUT        ((uint32_t)-2)
#define ERR_DMA_CORE       ((uint32_t)-3)
#define ERR_TAG_MISSING    ((uint32_t)-4)
#define ERR_TAG_UNEXPECTED ((uint32_t)-5)
#define ERR_PTEXT_MISMATCH ((uint32_t)-6)
#define ERR_TAG_NO_CHANGE  ((uint32_t)-7)

static void fill_plaintext(void)
{
    uint32_t i;
    volatile uint32_t * const pt = (volatile uint32_t *)PT_MULTI_BASE;

    for (i = 0u; i < (uint32_t)DMEM_MULTI_BLOCK_COUNT; i++) {
        pt[i * 2u]      = 0xA0000000u | i;
        pt[i * 2u + 1u] = 0xB0000000u | i;
    }
}

static void configure_key_nonce(uint32_t mode)
{
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);
    ASCON_WRITE(ASCON_OFS_MODE, mode);

    ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
    ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
    ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
    ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);

    ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
    ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
    ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
    ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);

    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0x02u);
}

static void set_test_ad(void)
{
    ascon_set_ad(0x4153434Fu, 0x4E2D4144u, 0x2D544553u, 0x54000000u, 13u);
}

static uint32_t run_dma(uint32_t src, uint32_t dst, uint32_t len)
{
    uint32_t status;
    uint32_t timeout = TIMEOUT_LIMIT;

    ASCON_WRITE(ASCON_OFS_DMA_SRC,   src);
    ASCON_WRITE(ASCON_OFS_DMA_DST,   dst);
    ASCON_WRITE(ASCON_OFS_DMA_LEN,   len);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);

    __asm__ volatile ("fence rw,rw" ::: "memory");
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

    do {
        __asm__ volatile ("nop; nop; nop; nop; nop; nop; nop; nop" ::: "memory");
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            return ERR_TIMEOUT;
        }
    } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)));

    ASCON_READ(ASCON_OFS_STATUS, status);
    return status;
}

static int status_has_hw_error(uint32_t status)
{
    return ((status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) != 0u);
}

static uint32_t run_encrypt(uint32_t use_ad)
{
    uint32_t status;

    configure_key_nonce(ASCON_MODE_128_ENC);
    if (use_ad) {
        set_test_ad();
    } else {
        ascon_clear_ad();
    }

    status = run_dma(PT_MULTI_BASE, CT_MULTI_BASE, DMEM_MULTI_PT_LEN);
    if (status == ERR_TIMEOUT) return status;
    if (status_has_hw_error(status)) return ERR_DMA_CORE;
    if ((status & ASCON_ST_TAG_MISMATCH) != 0u) return ERR_TAG_UNEXPECTED;

    return status;
}

static uint32_t run_core_decrypt(uint32_t c0, uint32_t c1,
                                 uint32_t tag0, uint32_t tag1,
                                 uint32_t tag2, uint32_t tag3)
{
    uint32_t status;
    uint32_t timeout = TIMEOUT_LIMIT;

    configure_key_nonce(ASCON_MODE_128_DEC);
    set_test_ad();
    ascon_set_tag_in(tag0, tag1, tag2, tag3);
    ascon_set_ptext(c0, c1, 8u);

    __asm__ volatile ("fence rw,rw" ::: "memory");
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_CORE_START);

    do {
        __asm__ volatile ("nop; nop; nop; nop" ::: "memory");
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            return ERR_TIMEOUT;
        }
    } while (!(status & (ASCON_ST_CORE_DONE | ASCON_ST_CORE_ERR)));

    ASCON_READ(ASCON_OFS_STATUS, status);
    if (status_has_hw_error(status)) return ERR_DMA_CORE;

    return status;
}

static int run_ascon_test(void)
{
    uint32_t status;
    uint32_t retcode = 0u;
    uint32_t noad_tag0;
    uint32_t noad_tag1;
    uint32_t noad_tag2;
    uint32_t noad_tag3;
    uint32_t tag0;
    uint32_t tag1;
    uint32_t tag2;
    uint32_t tag3;
    uint32_t c0;
    uint32_t c1;
    uint32_t p0;
    uint32_t p1;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    fill_plaintext();

    status = run_encrypt(0u);
    if (status >= 0x80000000u) {
        retcode = status;
        goto done;
    }
    ASCON_READ(ASCON_OFS_TAG_0, noad_tag0);
    ASCON_READ(ASCON_OFS_TAG_1, noad_tag1);
    ASCON_READ(ASCON_OFS_TAG_2, noad_tag2);
    ASCON_READ(ASCON_OFS_TAG_3, noad_tag3);

    status = run_encrypt(1u);
    if (status >= 0x80000000u) {
        retcode = status;
        goto done;
    }

    ASCON_READ(ASCON_OFS_TAG_0, tag0);
    ASCON_READ(ASCON_OFS_TAG_1, tag1);
    ASCON_READ(ASCON_OFS_TAG_2, tag2);
    ASCON_READ(ASCON_OFS_TAG_3, tag3);
    ASCON_READ(ASCON_OFS_CTEXT_0, c0);
    ASCON_READ(ASCON_OFS_CTEXT_1, c1);

    if ((tag0 == noad_tag0) && (tag1 == noad_tag1) &&
        (tag2 == noad_tag2) && (tag3 == noad_tag3)) {
        retcode = ERR_TAG_NO_CHANGE;
        goto done;
    }

    status = run_core_decrypt(c0, c1, tag0, tag1, tag2, tag3);
    if (status >= 0x80000000u) {
        retcode = status;
        goto done;
    }
    if ((status & ASCON_ST_TAG_MISMATCH) != 0u) {
        retcode = ERR_TAG_UNEXPECTED;
        goto done;
    }
    ASCON_READ(ASCON_OFS_CTEXT_0, p0);
    ASCON_READ(ASCON_OFS_CTEXT_1, p1);
    if ((p0 != 0xA000000Fu) || (p1 != 0xB000000Fu)) {
        retcode = ERR_PTEXT_MISMATCH;
        goto done;
    }

    status = run_core_decrypt(c0, c1, tag0 ^ 0x00000001u, tag1, tag2, tag3);
    if (status >= 0x80000000u) {
        retcode = status;
        goto done;
    }
    if ((status & ASCON_ST_TAG_MISMATCH) == 0u) {
        retcode = ERR_TAG_MISSING;
        goto done;
    }

done:
    DMEM->STATUS  = status;
    DMEM->RETCODE = retcode;

    if (retcode != 0u) return -1;
    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    int r = run_ascon_test();
    if (r == 0) {
        uart_puts("[PASS] ascon\r\n");
    } else {
        uint32_t rc = DMEM->RETCODE;
        uart_puts("[FAIL] ascon err=0x");
        uart_puthex32(rc);
        uart_puts("\r\n");
    }
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
