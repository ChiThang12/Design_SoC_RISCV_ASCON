/* CPU0 dirty write -> CPU1 read miss -> automatic peer snoop invalidate/writeback. */
#include "dualcore_common.h"

#define SIG0_VALUE      0x5A110001u
#define SIG1_VALUE      0xC001D00Du
#define FLAG_ADDR       0x10000200u
#define DATA_ADDR       0x10000220u
#define READY_MAGIC     0xACCE5501u
#define DATA_MAGIC      0xFACEB00Cu

int main(void)
{
    uint32_t hart = dualcore_hartid();

    if (hart == 0u) {
        dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);

        DMEM32(DATA_ADDR) = DATA_MAGIC;
        DMEM32(FLAG_ADDR) = READY_MAGIC;
        DMEM32(AUX1_ADDR) = 0x11110000u | hart;

        while (1) {
            uint32_t beat = DMEM32(HEARTBEAT_ADDR);
            DMEM32(HEARTBEAT_ADDR) = beat + 1u;
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }
    } else {
        while (DMEM32(RESULT_ADDR) != RESULT_RUNNING) {
            __asm__ volatile ("nop");
        }
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

        while (1) {
            __asm__ volatile ("fence iorw, iorw" ::: "memory");
            if (DMEM32(FLAG_ADDR) == READY_MAGIC) {
                break;
            }
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }

        if (DMEM32(DATA_ADDR) != DATA_MAGIC) {
            dualcore_fail_stop();
        }

        DMEM32(AUX0_ADDR) = DMEM32(DATA_ADDR);
        DMEM32(AUX1_ADDR) = 0x22220000u | hart;
        DMEM32(SHARED_COUNT_ADDR) = 1u;
        DMEM32(HEARTBEAT_ADDR) = 2u;
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

        while (1) {
            uint32_t beat = DMEM32(HEARTBEAT_ADDR);
            DMEM32(HEARTBEAT_ADDR) = beat + 1u;
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }
    }

    return 0;
}
