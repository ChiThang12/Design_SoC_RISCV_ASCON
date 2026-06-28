/* test_dualcore_basic.c
 *
 * Purpose:
 *   Minimal firmware for the current P0 dual-core bring-up. Both cores run
 *   the same image, continuously exercising their private DCache paths while
 *   sharing DMEM. The testbench proves dual-core activity by observing:
 *     1. shared DMEM signatures/heartbeat written by software
 *     2. per-core request counters and DCache stats inside soc_top
 *
 * Build:
 *   cd gnu_toolchain
 *   ./compile_c_to_hex.sh -i tests/test_dualcore_basic.c -o tests/test_dualcore_basic.hex -c
 */
#include <stdint.h>

#define DMEM32(addr) (*(volatile uint32_t *)(addr))

#define SHARED_SIG0_ADDR   0x10000000u
#define SHARED_SIG1_ADDR   0x10000004u
#define SHARED_COUNT_ADDR  0x10000008u
#define HEARTBEAT_ADDR     0x1000000Cu
#define RESULT_ADDR        0x10000010u

#define SIG0_VALUE         0xD00DCAFEu
#define SIG1_VALUE         0x13579BDFu
#define RESULT_RUNNING     0xCAFE0001u
#define RESULT_FAIL        0xDEAD0001u

static void fail_stop(void)
{
    DMEM32(RESULT_ADDR) = RESULT_FAIL;
    __asm__ volatile ("fence w,w" ::: "memory");
    while (1) {
        __asm__ volatile ("nop");
    }
}

int main(void)
{
    uint32_t i;

    DMEM32(SHARED_SIG0_ADDR) = SIG0_VALUE;
    DMEM32(SHARED_SIG1_ADDR) = SIG1_VALUE;
    DMEM32(RESULT_ADDR)      = RESULT_RUNNING;
    __asm__ volatile ("fence w,w" ::: "memory");

    for (i = 0; i < 64u; i++) {
        uint32_t count = DMEM32(SHARED_COUNT_ADDR);
        DMEM32(SHARED_COUNT_ADDR) = count + 1u;
        DMEM32(HEARTBEAT_ADDR)    = count + 1u;

        if (DMEM32(SHARED_SIG0_ADDR) != SIG0_VALUE) {
            fail_stop();
        }
        if (DMEM32(SHARED_SIG1_ADDR) != SIG1_VALUE) {
            fail_stop();
        }

        if ((i & 15u) == 15u) {
            __asm__ volatile ("fence w,w" ::: "memory");
        }
    }

    while (1) {
        uint32_t beat = DMEM32(HEARTBEAT_ADDR);
        DMEM32(HEARTBEAT_ADDR) = beat + 1u;

        if (DMEM32(SHARED_SIG0_ADDR) != SIG0_VALUE) {
            fail_stop();
        }
        if (DMEM32(SHARED_SIG1_ADDR) != SIG1_VALUE) {
            fail_stop();
        }

        if ((beat & 31u) == 31u) {
            __asm__ volatile ("fence w,w" ::: "memory");
        }
    }

    return 0;
}
