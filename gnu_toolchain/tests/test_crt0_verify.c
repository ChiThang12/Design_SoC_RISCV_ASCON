/* test_crt0_verify.c — C1: Boot + CRT0 .data section init verify.
 *
 * Build WITHOUT -c flag (full CRT0 — copies .data from ROM to DMEM).
 * NON-const static → linker places in .data (LMA=ROM, VMA=DMEM).
 * CRT0 copies .data at startup; volatile pointer forces runtime load.
 * If CRT0 copied correctly: vm[0]=='H' (0x48), vm[4]=='O' (0x4F).
 */
#include <stdint.h>
#include "uart.h"
#include "dmem_layout.h"

/* NON-const → .data section, CRT0 must copy ROM→DMEM */
static char magic[] = "HELLO";

int main(void)
{
    /* Volatile pointer forces runtime load from DMEM (prevents compile-time folding) */
    volatile char *vm = (volatile char *)magic;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    DMEM->STATUS  = (uint32_t)(unsigned char)vm[0];  /* expect 0x48 'H' */
    DMEM->RETCODE = (uint32_t)(unsigned char)vm[4];  /* expect 0x4F 'O' */

    if (vm[0] == 'H' && vm[4] == 'O') {
        /* [PASS] prefix — testbench parse_uart_line outputs "*** PASS" to log */
        uart_putc('['); uart_putc('P'); uart_putc('A'); uart_putc('S');
        uart_putc('S'); uart_putc(']'); uart_putc(' ');
        uart_putc('c'); uart_putc('r'); uart_putc('t'); uart_putc('0');
        uart_putc('\r'); uart_putc('\n');
    } else {
        uart_putc('['); uart_putc('F'); uart_putc('A'); uart_putc('I');
        uart_putc('L'); uart_putc(']'); uart_putc(' ');
        uart_putc('c'); uart_putc('r'); uart_putc('t'); uart_putc('0');
        uart_putc('\r'); uart_putc('\n');
    }

    /* Step 1: wait until TX FIFO empty (bit 0 = TX_EMPTY).
     * At this point last char is dequeued into the shift register. */
    {
        volatile uint32_t st;
        do {
            st = *((volatile uint32_t *)0x50000008u);
        } while (!(st & 1u));
    }
    /* Step 2: extra ~1000 cycles for shift register to finish the last byte
     * (1 char = 10 bits × 86.8 cycles/bit ≈ 868 cycles at 115200/100MHz). */
    {
        volatile uint32_t i;
        for (i = 0u; i < 250u; i++)
            __asm__ volatile ("nop");
    }

    while (1) {}
    return 0;
}
