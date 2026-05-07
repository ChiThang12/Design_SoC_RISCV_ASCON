/* test_uart_simple.c — Minimal UART test, no string literals, no .data copy.
 * Build with -c flag (bare-metal, no startup): avoids .rodata issues.
 * Just writes individual chars via uart_putc (pure MMIO, no pointers to .rodata).
 */
#include <stdint.h>
#include "uart.h"

int main(void)
{
    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    /* "UART OK\r\n" — individual char constants, not string literals */
    uart_putc('U');
    uart_putc('A');
    uart_putc('R');
    uart_putc('T');
    uart_putc(' ');
    uart_putc('O');
    uart_putc('K');
    uart_putc('\r');
    uart_putc('\n');

    /* "[PASS] uart_simple\r\n" */
    uart_putc('[');
    uart_putc('P');
    uart_putc('A');
    uart_putc('S');
    uart_putc('S');
    uart_putc(']');
    uart_putc(' ');
    uart_putc('u');
    uart_putc('a');
    uart_putc('r');
    uart_putc('t');
    uart_putc('_');
    uart_putc('s');
    uart_putc('i');
    uart_putc('m');
    uart_putc('p');
    uart_putc('l');
    uart_putc('e');
    uart_putc('\r');
    uart_putc('\n');

    while (1) {}
    return 0;
}
