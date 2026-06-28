/* Minimal dual-core liveness test. */
#include "dualcore_common.h"

#define SIG0_VALUE 0xD00DCAFEu
#define SIG1_VALUE 0x13579BDFu

int main(void)
{
    uint32_t i;

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);

    for (i = 0; i < 64u; i++) {
        uint32_t count = DMEM32(SHARED_COUNT_ADDR);
        DMEM32(SHARED_COUNT_ADDR) = count + 1u;
        DMEM32(HEARTBEAT_ADDR) = count + 1u;

        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

        if ((i & 15u) == 15u) {
            __asm__ volatile ("fence w,w" ::: "memory");
        }
    }

    while (1) {
        uint32_t beat = DMEM32(HEARTBEAT_ADDR);
        DMEM32(HEARTBEAT_ADDR) = beat + 1u;
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

        if ((beat & 31u) == 31u) {
            __asm__ volatile ("fence w,w" ::: "memory");
        }
    }

    return 0;
}
