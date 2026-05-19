/* test_uart.c — UART Driver Test
 * Standalone: ./compile_c_to_hex.sh -i tests/test_uart.c -o tests/test_uart.hex -O 0
 * Protocol  : [PASS] uart / [FAIL] uart err=<code>
 */
#include <stdint.h>
#include "uart.h"

/* ── Test logic ───────────────────────────────────────────────────────────── */
static int run_uart_test(void)
{
    uint32_t timeout;
    uint32_t irq_s;

    /* 1. Init UART 115200 baud, IRQ off */
    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    /* 2. Basic TX — TB monitors uart_tx wire */
    uart_puts("Hello UART\r\n");

    /* 3. TX IRQ test
     *    TX IRQ fires when TX FIFO becomes empty.
     *    Enable IRQ → write one byte → wait for TX_EMPTY → check IRQ flag. */
    uart_irq_clear();        /* clear stale flags */
    uart_tx_irq_enable();

    uart_putc('A');          /* load one byte into FIFO */

    /* Poll for TX FIFO drain + IRQ assertion */
    timeout = 0x3FFFFu;
    do {
        irq_s = uart_irq_status();
        if (--timeout == 0u) return -1;
    } while (!(irq_s & UART_IRQ_TX));

    uart_irq_clear();        /* W1C — clear TX IRQ */

    /* Verify flag cleared */
    if (uart_irq_status() & UART_IRQ_TX) return -2;

    /* Flush TB line buffer: byte 'A' ở trên không có '\n' nên TB parser
     * sẽ ghép 'A' với line kế tiếp ("[PASS] uart") → fail match. */
    uart_puts("\r\n");

    return 0;
}

/* ── Standalone main ─────────────────────────────────────────────────────── */
#ifndef INTEGRATION_BUILD
int main(void)
{
    int r = run_uart_test();
    if (r == 0) {
        uart_puts("[PASS] uart\r\n");
    } else {
        uart_puts("[FAIL] uart err=0x");
        uart_puthex32((uint32_t)r);
        uart_puts("\r\n");
    }
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
