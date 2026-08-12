/* test_store_raw.c - focused producer -> store-data RAW regression.
 *
 * FreeRTOS tick/setup code frequently executes:
 *   li/addi producer -> sw to MMIO/DMEM
 *
 * This test intentionally uses no NOPs between the producer and store. The CPU
 * must forward/freeze the rs2 store-data path correctly without firmware gaps.
 */
#include <stdint.h>
#include "uart.h"

#define UART_PUTC_SAFE_IMM(ch_)                                      \
    __asm__ volatile (                                               \
        "1:\n"                                                       \
        "li t0, 0x50000008\n"                                        \
        "lw t1, 0(t0)\n"                                             \
        "andi t1, t1, 2\n"                                           \
        "bnez t1, 1b\n"                                              \
        "li t0, 0x50000000\n"                                        \
        "li t1, %0\n"                                                \
        "nop\n"                                                      \
        "nop\n"                                                      \
        "nop\n"                                                      \
        "sw t1, 0(t0)\n"                                             \
        "fence w,w\n"                                                \
        :: "i" (ch_) : "t0", "t1", "memory"                         \
    )

static void uart_pass(void)
{
    UART_PUTC_SAFE_IMM('['); UART_PUTC_SAFE_IMM('P'); UART_PUTC_SAFE_IMM('A');
    UART_PUTC_SAFE_IMM('S'); UART_PUTC_SAFE_IMM('S'); UART_PUTC_SAFE_IMM(']');
    UART_PUTC_SAFE_IMM(' '); UART_PUTC_SAFE_IMM('s'); UART_PUTC_SAFE_IMM('t');
    UART_PUTC_SAFE_IMM('o'); UART_PUTC_SAFE_IMM('r'); UART_PUTC_SAFE_IMM('e');
    UART_PUTC_SAFE_IMM('_'); UART_PUTC_SAFE_IMM('r'); UART_PUTC_SAFE_IMM('a');
    UART_PUTC_SAFE_IMM('w'); UART_PUTC_SAFE_IMM('\r'); UART_PUTC_SAFE_IMM('\n');
}

static void uart_fail(void)
{
    UART_PUTC_SAFE_IMM('['); UART_PUTC_SAFE_IMM('F'); UART_PUTC_SAFE_IMM('A');
    UART_PUTC_SAFE_IMM('I'); UART_PUTC_SAFE_IMM('L'); UART_PUTC_SAFE_IMM(']');
    UART_PUTC_SAFE_IMM(' '); UART_PUTC_SAFE_IMM('s'); UART_PUTC_SAFE_IMM('t');
    UART_PUTC_SAFE_IMM('o'); UART_PUTC_SAFE_IMM('r'); UART_PUTC_SAFE_IMM('e');
    UART_PUTC_SAFE_IMM('_'); UART_PUTC_SAFE_IMM('r'); UART_PUTC_SAFE_IMM('a');
    UART_PUTC_SAFE_IMM('w'); UART_PUTC_SAFE_IMM('\r'); UART_PUTC_SAFE_IMM('\n');
}

static uint32_t raw_li_sw_lw(void)
{
    uint32_t got;
    __asm__ volatile (
        "li t0, 0x10000080\n"
        "li t1, 0x11223344\n"
        "sw t1, 0(t0)\n"
        "lw %0, 0(t0)\n"
        : "=r" (got)
        :
        : "t0", "t1", "memory"
    );
    return got;
}

static uint32_t raw_addi_sw_lw(void)
{
    uint32_t got;
    __asm__ volatile (
        "li t0, 0x10000084\n"
        "li t1, 0x11223000\n"
        "addi t1, t1, 0x344\n"
        "sw t1, 0(t0)\n"
        "lw %0, 0(t0)\n"
        : "=r" (got)
        :
        : "t0", "t1", "memory"
    );
    return got;
}

static uint32_t raw_clint_mtimecmp_rw(void)
{
    uint32_t got_lo;
    uint32_t got_hi;

    __asm__ volatile (
        "li t0, 0x40004004\n"
        "li t1, -1\n"
        "sw t1, 0(t0)\n"

        "li t0, 0x40004000\n"
        "li t1, 0x01020000\n"
        "addi t1, t1, 0x304\n"
        "sw t1, 0(t0)\n"

        "li t0, 0x40004004\n"
        "li t1, 0x55667000\n"
        "addi t1, t1, 0x788\n"
        "sw t1, 0(t0)\n"

        "li t0, 0x40004000\n"
        "lw %0, 0(t0)\n"
        "li t0, 0x40004004\n"
        "lw %1, 0(t0)\n"
        : "=r" (got_lo), "=r" (got_hi)
        :
        : "t0", "t1", "memory"
    );

    return (got_lo == 0x01020304u && got_hi == 0x55667788u) ? 0u : 1u;
}

static uint32_t raw_lw_sw_lw(void)
{
    uint32_t got;
    __asm__ volatile (
        "li t0, 0x10000090\n"
        "li t1, 0x5a5a5000\n"
        "addi t1, t1, 0x5a5\n"
        "sw t1, 0(t0)\n"
        "lw t2, 0(t0)\n"
        "sw t2, 4(t0)\n"
        "lw %0, 4(t0)\n"
        : "=r" (got)
        :
        : "t0", "t1", "t2", "memory"
    );
    return got;
}

static uint32_t raw_lbu_sw_lw(void)
{
    uint32_t got;
    __asm__ volatile (
        "li t0, 0x10000098\n"
        "li t1, 0x000000a5\n"
        "sw t1, 0(t0)\n"
        "lbu t2, 0(t0)\n"
        "sw t2, 4(t0)\n"
        "lw %0, 4(t0)\n"
        : "=r" (got)
        :
        : "t0", "t1", "t2", "memory"
    );
    return got;
}

int main(void)
{
    uart_init(UART_DIV_115200_100MHZ, 0u, 0u);

    if (raw_li_sw_lw() != 0x11223344u) {
        uart_fail();
    } else if (raw_addi_sw_lw() != 0x11223344u) {
        uart_fail();
    } else if (raw_clint_mtimecmp_rw() != 0u) {
        uart_fail();
    } else if (raw_lw_sw_lw() != 0x5a5a55a5u) {
        uart_fail();
    } else if (raw_lbu_sw_lw() != 0x000000a5u) {
        uart_fail();
    } else {
        uart_pass();
    }

    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
