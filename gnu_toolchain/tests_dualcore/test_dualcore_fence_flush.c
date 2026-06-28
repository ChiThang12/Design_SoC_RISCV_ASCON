/* Repeated shared-line writes + fence flushes to exercise writeback visibility. */
#include "dualcore_common.h"

#define SIG0_VALUE     0xFEC10001u
#define SIG1_VALUE     0x0BADF00Du
#define WIN_BASE       0x10000100u
#define WIN_WORD0      (WIN_BASE + 0x00u)
#define WIN_WORD1      (WIN_BASE + 0x04u)
#define WIN_WORD2      (WIN_BASE + 0x08u)
#define WIN_WORD3      (WIN_BASE + 0x0Cu)

int main(void)
{
    uint32_t step;

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);

    for (step = 0; step < 32u; step++) {
        uint32_t v0 = 0xA5000000u | step;
        uint32_t v1 = 0x5A000000u | (step << 1);
        uint32_t v2 = 0x3C000000u | (step << 2);
        uint32_t v3 = 0xC3000000u | (step << 3);

        DMEM32(WIN_WORD0) = v0;
        DMEM32(WIN_WORD1) = v1;
        DMEM32(WIN_WORD2) = v2;
        DMEM32(WIN_WORD3) = v3;

        __asm__ volatile ("fence w,w" ::: "memory");

        if (DMEM32(WIN_WORD0) != v0) dualcore_fail_stop();
        if (DMEM32(WIN_WORD1) != v1) dualcore_fail_stop();
        if (DMEM32(WIN_WORD2) != v2) dualcore_fail_stop();
        if (DMEM32(WIN_WORD3) != v3) dualcore_fail_stop();

        DMEM32(AUX0_ADDR) = v0 ^ v1;
        DMEM32(AUX1_ADDR) = v2 ^ v3;
        DMEM32(SHARED_COUNT_ADDR) = step + 1u;
        DMEM32(HEARTBEAT_ADDR) = step + 1u;
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }

    while (1) {
        uint32_t beat = DMEM32(HEARTBEAT_ADDR) + 1u;
        DMEM32(HEARTBEAT_ADDR) = beat;
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        if ((beat & 7u) == 0u) {
            __asm__ volatile ("fence w,w" ::: "memory");
        }
    }

    return 0;
}
