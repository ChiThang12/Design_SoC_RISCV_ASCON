/* test_integration.c — Full SoC Integration Test
 * Compile: ./compile_c_to_hex.sh -i tests/test_integration.c -o tests/test_integration.hex -O 0 -c
 *
 * Includes all test .c files as a unity build (INTEGRATION_BUILD suppresses
 * individual main() functions). Runs each test in order, outputs per-test
 * [PASS]/[FAIL], then a final summary line for TB detection.
 *
 * TB checks for "ALL_PASS 6/6" or "SOME_FAIL X/6".
 */

#define INTEGRATION_BUILD

#include "test_uart.c"
#include "test_gpio.c"
#include "test_timer.c"
#include "test_clint.c"
#include "test_plic.c"
#include "test_ascon.c"

/* uart_puts/puthex32 already available from test_uart.c's uart.h */

static void report(const char *name, int result, int *pass_count)
{
    if (result == 0) {
        uart_puts("[PASS] ");
        uart_puts(name);
        uart_puts("\r\n");
        (*pass_count)++;
    } else {
        uart_puts("[FAIL] ");
        uart_puts(name);
        uart_puts(" err=0x");
        uart_puthex32((uint32_t)result);
        uart_puts("\r\n");
    }
}

int main(void)
{
    int pass = 0;
    int total = 6;

    /* Re-init UART before first test output */
    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);
    uart_puts("=== Integration Test Start ===\r\n");

    report("uart",  run_uart_test(),  &pass);
    report("gpio",  run_gpio_test(),  &pass);
    report("timer", run_timer_test(), &pass);
    report("clint", run_clint_test(), &pass);
    report("plic",  run_plic_test(),  &pass);
    report("ascon", run_ascon_test(), &pass);

    /* Summary line — TB monitors for ALL_PASS / SOME_FAIL */
    if (pass == total) {
        uart_puts("ALL_PASS 6/6\r\n");
    } else {
        uart_puts("SOME_FAIL ");
        uart_puthex8((uint8_t)pass);
        uart_puts("/6\r\n");
    }

    while (1) __asm__ volatile ("nop");
    return 0;
}
