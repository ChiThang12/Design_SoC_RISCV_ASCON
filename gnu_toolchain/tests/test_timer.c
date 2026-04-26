/* test_timer.c — Timer0/1 + WDT Test
 * Standalone: ./compile_c_to_hex.sh -i tests/test_timer.c -o tests/test_timer.hex -O 0 -c
 *
 * Tests:
 *   A. Timer0 one-shot  : LOAD=5000, poll timeout flag → clear
 *   B. Timer0 auto-reload × 3 via PLIC IRQ counter
 *   C. WDT feed loop    : LOAD=50000, kick × 10 → verify no expire
 *   D. WDT expire       : LOAD=200, no feed → poll expire flag → clear
 *      TB intercepts wdt_rst_req — sim continues after WDT fires
 */
#include <stdint.h>
#include "uart.h"
#include "timer.h"
#include "plic.h"
#include "irq.h"

static volatile uint32_t timer_irq_count = 0u;

__attribute__((interrupt("machine"))) static void timer_isr(void)
{
    uint32_t cause = irq_mcause();
    if ((cause & 0xFFu) == 11u) {       /* M-mode external interrupt */
        uint32_t src = plic_claim();
        if (src == PLIC_SRC_TIMER0) {
            timer0_clear();             /* W1C timeout flag */
            timer_irq_count++;
        }
        plic_complete(src);
    }
}

static int run_timer_test(void)
{
    uint32_t i, timeout;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    /* ── A. Timer0 one-shot ───────────────────────────────────────────────── */
    timer0_oneshot(5000u);
    if (timer0_wait_timeout(0x3FFFFu) != 0) return -1;
    timer0_clear();
    timer0_stop();

    /* ── B. Timer0 auto-reload × 3 via PLIC IRQ ──────────────────────────── */
    timer_irq_count = 0u;

    plic_set_threshold(0u);
    plic_set_priority(PLIC_SRC_TIMER0, 1u);
    plic_enable(PLIC_SRC_TIMER0);

    irq_set_mtvec(timer_isr);
    irq_enable_external();
    irq_enable_global();

    timer0_autoreload(1000u, 1u);       /* LOAD=1000, irq_en=1 */

    timeout = 0x7FFFFu;
    while (timer_irq_count < 3u) {
        if (--timeout == 0u) {
            irq_disable_global();
            return -2;
        }
    }

    irq_disable_global();
    timer0_stop();
    plic_disable(PLIC_SRC_TIMER0);

    /* ── C. WDT feed loop — must not expire ──────────────────────────────── */
    wdt_enable(50000u);
    for (i = 0u; i < 10u; i++) {
        uint32_t j;
        for (j = 0u; j < 200u; j++) __asm__ volatile ("nop");
        wdt_feed();
    }
    if (wdt_expired()) return -3;       /* expired despite feeding → FAIL */
    wdt_disable();

    /* ── D. WDT expire test ───────────────────────────────────────────────── */
    /* TB will intercept wdt_rst_req and NOT reset the DUT */
    wdt_clear();
    wdt_enable(200u);                   /* short timeout, no feed */

    timeout = 0xFFFFu;
    while (!wdt_expired()) {
        if (--timeout == 0u) return -4;
    }
    wdt_clear();
    wdt_disable();

    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    int r = run_timer_test();
    if (r == 0) {
        uart_puts("[PASS] timer\r\n");
    } else {
        uart_puts("[FAIL] timer err=0x");
        uart_puthex32((uint32_t)r);
        uart_puts("\r\n");
    }
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
