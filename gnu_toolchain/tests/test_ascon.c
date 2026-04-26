/* test_ascon.c — ASCON 16-block DMA Encrypt Test
 * Refactored from gnu_toolchain/main.c (v10.0)
 * Standalone: ./compile_c_to_hex.sh -i tests/test_ascon.c -o tests/test_ascon.hex -O 1 -c
 *
 * Pipeline: CPU writes 16 blocks of plaintext → DMEM
 *           DMA reads DMEM → feeds ASCON CORE → writes ciphertext+tag back
 *           CPU polls STATUS (DMA_DONE | DMA_ERR | CORE_ERR)
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

#define TIMEOUT_LIMIT  0x003FFFFFu

static int run_ascon_test(void)
{
    uint32_t status  = 0u;
    uint32_t retcode = 0u;
    uint32_t timeout;
    uint32_t i;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    /* 1. Write 16 plaintext blocks → DMEM */
    volatile uint32_t * const pt = (volatile uint32_t *)PT_MULTI_BASE;
    for (i = 0u; i < (uint32_t)DMEM_MULTI_BLOCK_COUNT; i++) {
        pt[i * 2u]      = 0xA0000000u | i;
        pt[i * 2u + 1u] = 0xB0000000u | i;
    }

    /* 2. Soft reset */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);

    /* 3. Mode: ASCON-128 Encrypt */
    ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);

    /* 4. Key */
    ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
    ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
    ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
    ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);

    /* 5. Nonce */
    ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
    ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
    ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
    ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);

    /* 6. DMA config */
    ASCON_WRITE(ASCON_OFS_DMA_SRC,   PT_MULTI_BASE);
    ASCON_WRITE(ASCON_OFS_DMA_DST,   CT_MULTI_BASE);
    ASCON_WRITE(ASCON_OFS_DMA_LEN,   DMEM_MULTI_PT_LEN);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 7u);
    ASCON_WRITE(ASCON_OFS_DATA_LEN,  8u);

    /* Enable DMA_DONE IRQ for observability (TB can monitor) */
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0x02u);

    /* 7. Full barrier before DMA starts reading DMEM */
    __asm__ volatile ("fence rw,rw" ::: "memory");

    /* 8. Start DMA + CORE: CTRL = DMA_EN | CORE_START = 0x5 */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

    /* 9. Poll STATUS at reduced frequency (green IC: ~1 poll per 32 cycles) */
    timeout = TIMEOUT_LIMIT;
    do {
        __asm__ volatile ("nop; nop; nop; nop; nop; nop; nop; nop" ::: "memory");
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

    __asm__ volatile ("fence r,r" ::: "memory");
    retcode = 0u;

done:
    /* 10. Save to DMEM for post-simulation inspection */
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
