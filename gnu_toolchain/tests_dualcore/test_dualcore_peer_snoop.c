/* CPU0 dirty write -> CPU1 read miss -> automatic peer snoop invalidate/writeback. */
#include "dualcore_common.h"

#define SIG0_VALUE      0x5A110001u
#define SIG1_VALUE      0xC001D00Du
#define DATA_ADDR       0x10000220u
#define DATA_MAGIC      0xFACEB00Cu

int main(void)
{
    uint32_t hart = dualcore_hartid();

    if (hart == 0u) {
        dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);

        DMEM32(DATA_ADDR) = DATA_MAGIC;

        while (1) {
            __asm__ volatile ("nop");
        }
    } else {
        for (uint32_t boot_delay = 0; boot_delay < 4096u; boot_delay++) {
            __asm__ volatile ("nop");
        }

        while (DMEM32(RESULT_ADDR) != RESULT_RUNNING) {
            __asm__ volatile ("nop");
        }
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

        for (uint32_t delay = 0; delay < 4096u; delay++) {
            __asm__ volatile ("nop");
        }

        if (DMEM32(DATA_ADDR) != DATA_MAGIC) {
            dualcore_fail_stop();
        }

        DMEM32(AUX0_ADDR) = DMEM32(DATA_ADDR);
        DMEM32(AUX1_ADDR) = 0x22220000u | hart;
        DMEM32(SHARED_COUNT_ADDR) = 1u;
        DMEM32(HEARTBEAT_ADDR) = 2u;
        __asm__ volatile ("fence w,w" ::: "memory");
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }
    }

    return 0;
}
