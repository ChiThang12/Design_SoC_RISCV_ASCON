/* Multi-line cache sweep test for both cores running the same binary. */
#include "dualcore_common.h"

#define SIG0_VALUE    0xCACE0001u
#define SIG1_VALUE    0x2468ACE0u
#define BUF_BASE      0x10000040u
#define BUF_WORDS     32u
#define OUT_SUM_ADDR  AUX0_ADDR
#define OUT_LAST_ADDR AUX1_ADDR

int main(void)
{
    uint32_t round;

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);

    for (round = 0; round < 24u; round++) {
        uint32_t i;
        uint32_t sum = 0u;

        for (i = 0; i < BUF_WORDS; i++) {
            uint32_t value = (round << 16) ^ (i * 0x01010101u) ^ 0x55AA00FFu;
            DMEM32(BUF_BASE + (i << 2)) = value;
            sum ^= value;
        }

        for (i = 0; i < BUF_WORDS; i++) {
            uint32_t value = DMEM32(BUF_BASE + (i << 2));
            sum ^= value;
        }

        DMEM32(OUT_SUM_ADDR) = sum;
        DMEM32(OUT_LAST_ADDR) = round;
        DMEM32(SHARED_COUNT_ADDR) = round + 1u;
        DMEM32(HEARTBEAT_ADDR) = round + 1u;

        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        __asm__ volatile ("fence w,w" ::: "memory");
    }

    while (1) {
        uint32_t beat = DMEM32(HEARTBEAT_ADDR) + 1u;
        DMEM32(HEARTBEAT_ADDR) = beat;
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        if ((beat & 15u) == 0u) {
            __asm__ volatile ("fence w,w" ::: "memory");
        }
    }

    return 0;
}
