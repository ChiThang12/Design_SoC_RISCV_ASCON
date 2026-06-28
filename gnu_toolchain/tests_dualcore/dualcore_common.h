#ifndef TESTS_DUALCORE_COMMON_H
#define TESTS_DUALCORE_COMMON_H

#include <stdint.h>

#define DMEM32(addr) (*(volatile uint32_t *)(addr))

#define SHARED_SIG0_ADDR   0x10000000u
#define SHARED_SIG1_ADDR   0x10000004u
#define SHARED_COUNT_ADDR  0x10000008u
#define HEARTBEAT_ADDR     0x1000000Cu
#define RESULT_ADDR        0x10000010u
#define AUX0_ADDR          0x10000014u
#define AUX1_ADDR          0x10000018u

#define RESULT_RUNNING     0xCAFE0001u
#define RESULT_FAIL        0xDEAD0001u

static inline void dualcore_fail_stop(void)
{
    DMEM32(RESULT_ADDR) = RESULT_FAIL;
    __asm__ volatile ("fence w,w" ::: "memory");
    while (1) {
        __asm__ volatile ("nop");
    }
}

static inline void dualcore_publish_start(uint32_t sig0, uint32_t sig1)
{
    DMEM32(SHARED_SIG0_ADDR) = sig0;
    DMEM32(SHARED_SIG1_ADDR) = sig1;
    DMEM32(SHARED_COUNT_ADDR) = 0u;
    DMEM32(HEARTBEAT_ADDR) = 0u;
    DMEM32(RESULT_ADDR) = RESULT_RUNNING;
    DMEM32(AUX0_ADDR) = 0u;
    DMEM32(AUX1_ADDR) = 0u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void dualcore_check_signatures(uint32_t sig0, uint32_t sig1)
{
    if (DMEM32(SHARED_SIG0_ADDR) != sig0) {
        dualcore_fail_stop();
    }
    if (DMEM32(SHARED_SIG1_ADDR) != sig1) {
        dualcore_fail_stop();
    }
}

static inline uint32_t dualcore_hartid(void)
{
    uint32_t hart;
    __asm__ volatile ("csrr %0, mhartid" : "=r"(hart));
    return hart;
}

#endif
