/* test_plic.c — PLIC Interrupt Controller Test (via ASCON core-done IRQ)
 * Standalone: ./compile_c_to_hex.sh -i tests/test_plic.c -o tests/test_plic.hex -O 0 -c
 *
 * Flow:
 *   1. Enable PLIC src=8 (ASCON), threshold=0, priority=1
 *   2. Enable ASCON core-done IRQ (IRQ_EN[0]=1)
 *   3. Configure ASCON CPU-direct: mode + key + nonce + ptext + start CORE
 *   4. ISR: plic_claim() → verify src==8 → plic_complete() → set flag
 *   5. Verify flag set within timeout
 */
#include <stdint.h>
#include "uart.h"
#include "plic.h"
#include "irq.h"
#include "ascon.h"

static volatile uint32_t plic_irq_flag = 0u;
static volatile uint32_t plic_claimed_src = 0u;

__attribute__((interrupt("machine"))) static void plic_isr(void)
{
    uint32_t cause = irq_mcause();
    if ((cause & 0xFFu) == 11u) {       /* M-mode external interrupt */
        uint32_t src = plic_claim();
        plic_claimed_src = src;
        plic_complete(src);
        plic_irq_flag = 1u;
    }
}

static int run_plic_test(void)
{
    uint32_t timeout;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    /* 1. PLIC: enable ASCON source */
    plic_set_threshold(0u);
    plic_set_priority(PLIC_SRC_ASCON, 1u);
    plic_enable(PLIC_SRC_ASCON);

    /* 2. CPU IRQ: set mtvec, enable external + global */
    irq_set_mtvec(plic_isr);
    irq_enable_external();
    irq_enable_global();

    /* 3. ASCON CPU-direct: configure and start CORE */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);  /* soft reset */
    ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);

    ASCON_WRITE(ASCON_OFS_KEY_0,   0xDEADBEEFu);
    ASCON_WRITE(ASCON_OFS_KEY_1,   0xCAFEBABEu);
    ASCON_WRITE(ASCON_OFS_KEY_2,   0x01234567u);
    ASCON_WRITE(ASCON_OFS_KEY_3,   0x89ABCDEFu);

    ASCON_WRITE(ASCON_OFS_NONCE_0, 0x11111111u);
    ASCON_WRITE(ASCON_OFS_NONCE_1, 0x22222222u);
    ASCON_WRITE(ASCON_OFS_NONCE_2, 0x33333333u);
    ASCON_WRITE(ASCON_OFS_NONCE_3, 0x44444444u);

    ASCON_WRITE(ASCON_OFS_PTEXT_0, 0xAABBCCDDu);
    ASCON_WRITE(ASCON_OFS_PTEXT_1, 0x00000000u);
    ASCON_WRITE(ASCON_OFS_DATA_LEN, 4u);

    /* 4. Enable ASCON core-done IRQ before starting CORE */
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0x01u);  /* bit[0] = core_done IRQ */
    __asm__ volatile ("fence rw,rw" ::: "memory");

    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_CORE_START);

    /* 5. Wait for ISR flag */
    timeout = 0x7FFFFu;
    while (!plic_irq_flag) {
        if (--timeout == 0u) {
            irq_disable_global();
            return -1;
        }
    }
    irq_disable_global();

    /* 6. Verify claimed source was ASCON (src=8) */
    if (plic_claimed_src != PLIC_SRC_ASCON) return -2;

    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    int r = run_plic_test();
    if (r == 0) {
        uart_puts("[PASS] plic\r\n");
    } else {
        uart_puts("[FAIL] plic err=0x");
        uart_puthex32((uint32_t)r);
        uart_puts("\r\n");
    }
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
