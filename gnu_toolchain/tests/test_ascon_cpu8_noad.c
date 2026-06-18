/* test_ascon_cpu8_noad.c — CPU-direct 8B encrypt, no AD
 * Latency baseline: 1 AEAD session, no Associated Data. */
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

#define TIMEOUT_LIMIT 20000u

static void uart_putu32d(uint32_t v)
{
    char buf[10];
    uint32_t i = 0u;
    if (v == 0u) { uart_putc('0'); return; }
    while (v > 0u) { buf[i++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (i > 0u) { uart_putc(buf[--i]); }
}

static int run_cpu8_noad_test(void)
{
    uint32_t t0, t1, cycles, throughput;
    uint32_t status;
    uint32_t c0, c1, tag0, tag1, tag2, tag3;
    uint32_t timeout;

    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);
    uart_puts("[ASCON-CPU8-NOAD]\r\n");

    ascon_soft_reset();
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(TV_KEY_0, TV_KEY_1, TV_KEY_2, TV_KEY_3);
    ascon_set_nonce(TV_NONCE_0, TV_NONCE_1, TV_NONCE_2, TV_NONCE_3);
    ascon_clear_ad();
    ascon_set_ptext(TV_PT_W0, TV_PT_W1, 8u);

    __asm__ volatile ("csrr %0, mcycle" : "=r"(t0));
    __asm__ volatile ("fence rw,rw" ::: "memory");
    ascon_core_start();

    timeout = TIMEOUT_LIMIT;
    do {
        __asm__ volatile ("nop;nop;nop;nop" ::: "memory");
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            DMEM->RETCODE = (uint32_t)-2;
            uart_puts("[FAIL] ascon_cpu8_noad timeout\r\n");
            return -1;
        }
    } while (!(status & (ASCON_ST_CORE_DONE | ASCON_ST_CORE_ERR)));

    __asm__ volatile ("csrr %0, mcycle" : "=r"(t1));

    if (status & ASCON_ST_CORE_ERR) {
        DMEM->RETCODE = (uint32_t)-3;
        uart_puts("[FAIL] ascon_cpu8_noad CORE_ERR\r\n");
        return -1;
    }

    ascon_get_ctext(&c0, &c1);
    ascon_get_tag(&tag0, &tag1, &tag2, &tag3);
    cycles = t1 - t0;
    throughput = 6400u / (cycles ? cycles : 1u);

    /* Print PASS first so testbench records it before UART budget runs out */
    uart_puts("[PASS] ascon_cpu8_noad\r\n");
    uart_puts("  cyc="); uart_puthex32(cycles);
    uart_puts(" mbps="); uart_putu32d(throughput);
    uart_puts(" ct="); uart_puthex32(c0); uart_putc(' '); uart_puthex32(c1);
    uart_puts("\r\n  tag=");
    uart_puthex32(tag0); uart_putc(' ');
    uart_puthex32(tag1); uart_putc(' ');
    uart_puthex32(tag2); uart_putc(' ');
    uart_puthex32(tag3); uart_puts("\r\n");

    DMEM->STATUS  = status;
    DMEM->RETCODE = 0u;
    return 0;
}

#ifndef INTEGRATION_BUILD
int main(void)
{
    run_cpu8_noad_test();
    while (1) __asm__ volatile ("nop");
    return 0;
}
#endif
