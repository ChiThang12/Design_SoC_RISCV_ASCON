/* test_clint.c — CLINT (mtime + mtimecmp + msip) Test
 * Standalone: ./compile_c_to_hex.sh -i tests/test_clint.c -o tests/test_clint.hex -O 0 -c
 *
 * Tests:
 *   A. mtime monotonically increasing
 *   B. mtimecmp timer: delay 100 µs → ISR sets flag → clint_clear_timer()
 *   C. msip software interrupt: set msip → ISR sets flag → clear
 *
 * CLINT irqs bypass PLIC — go directly to CPU via mie.MTIE / mie.MSIE
 */
#include <stdint.h>
#include "uart.h"
#include "clint.h"
#include "irq.h"

static volatile uint32_t clint_timer_flag = 0u;
static volatile uint32_t clint_sw_flag    = 0u;

__attribute__((interrupt("machine"))) static void clint_isr(void)
{
    uint32_t cause = irq_mcause();

    if (cause == 0x80000007u) {         /* M-mode timer interrupt */
        clint_clear_timer();            /* prevent re-fire before mret */
        clint_timer_flag = 1u;
    } else if (cause == 0x80000003u) {  /* M-mode software interrupt */
        clint_sw_irq_clear();
        clint_sw_flag = 1u;
    }
}

static int run_clint_test(void)
{
    uint64_t t0, t1;
    uint32_t timeout;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    /* ── A. mtime monotonically increasing ───────────────────────────────── */
    t0 = clint_mtime();
    /* Small NOP gap to let mtime advance (mtime_tick @ 1 MHz → 1 tick/µs) */
    {
        uint32_t i;
        for (i = 0u; i < 200u; i++) __asm__ volatile ("nop");
    }
    t1 = clint_mtime();
    if (t1 <= t0) return -1;

    /* ── B. mtimecmp timer interrupt ──────────────────────────────────────── */
    clint_timer_flag = 0u;
    irq_set_mtvec(clint_isr);
    irq_enable_timer();
    irq_enable_global();

    clint_set_timer_delay_us(100u);     /* fire after 100 µs (100 ticks @ 1 MHz) */

    timeout = 0x7FFFFu;
    while (!clint_timer_flag) {
        if (--timeout == 0u) {
            irq_disable_global();
            irq_disable_timer();
            return -2;
        }
    }
    irq_disable_timer();

    /* ── C. Software interrupt (msip) ────────────────────────────────────── */
    clint_sw_flag = 0u;
    irq_enable_software();              /* mie.MSIE — MIE already on */

    clint_sw_irq_set();

    timeout = 0x3FFFFu;
    while (!clint_sw_flag) {
        if (--timeout == 0u) {
            irq_disable_global();
            irq_disable_software();
            return -3;
        }
    }
    irq_disable_software();
    irq_disable_global();

    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    int r = run_clint_test();
    if (r == 0) {
        uart_puts("[PASS] clint\r\n");
    } else {
        uart_puts("[FAIL] clint err=0x");
        uart_puthex32((uint32_t)r);
        uart_puts("\r\n");
    }
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
