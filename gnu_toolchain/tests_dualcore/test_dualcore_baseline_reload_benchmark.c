/* Baseline no-CRF benchmark with real MMIO reloads.
 *
 * This benchmark measures the true software reload cost on the same SoC path
 * used by H3. Instead of CONTEXT_SEL, firmware rewrites MODE/KEY/NONCE/PTEXT/
 * DATA_LEN for every session switch.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"

#define SIG0_VALUE 0x3C10B001u
#define SIG1_VALUE 0x3C10B002u

#define S0_KEY0   0x00010203u
#define S0_KEY1   0x04050607u
#define S0_KEY2   0x08090A0Bu
#define S0_KEY3   0x0C0D0E0Fu
#define S0_NONCE0 0x10111213u
#define S0_NONCE1 0x14151617u
#define S0_NONCE2 0x18191A1Bu
#define S0_NONCE3 0x1C1D1E1Fu
#define S0_P0     0x11223344u
#define S0_P1     0x55667788u

#define S1_KEY0   0x0F0E0D0Cu
#define S1_KEY1   0x0B0A0908u
#define S1_KEY2   0x07060504u
#define S1_KEY3   0x03020100u
#define S1_NONCE0 0x21222324u
#define S1_NONCE1 0x25262728u
#define S1_NONCE2 0x292A2B2Cu
#define S1_NONCE3 0x2D2E2F30u
#define S1_P0     0xA1B2C3D4u
#define S1_P1     0xE5F60718u

#define BASE_STAGE_RELOAD_BEGIN  50u
#define BASE_STAGE_RELOAD_DONE   59u
#define BASE_STAGE_S0_RUN        60u
#define BASE_STAGE_S0_DONE       61u
#define BASE_STAGE_S1_RUN        70u
#define BASE_STAGE_S1_DONE       71u
#define BASE_STAGE_VERIFY_DONE   80u

#define BASE_BENCH_S0_CT0_ADDR   0x100003C0u
#define BASE_BENCH_S0_CT1_ADDR   0x100003C4u
#define BASE_BENCH_S0_TAG0_ADDR  0x100003C8u
#define BASE_BENCH_S0_TAG1_ADDR  0x100003CCu
#define BASE_BENCH_S0_TAG2_ADDR  0x100003D0u
#define BASE_BENCH_S0_TAG3_ADDR  0x100003D4u
#define BASE_BENCH_RELOAD_AVG_ADDR 0x100003D8u
#define BASE_BENCH_ACTIVE_AVG_ADDR 0x100003DCu

static inline uint32_t read_cycle32(void)
{
    uint32_t v;
    __asm__ volatile ("rdcycle %0" : "=r"(v));
    return v;
}

static inline uint32_t ascon_read_raw(uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    return *p;
}

static void configure_s0(void)
{
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(S0_KEY0, S0_KEY1, S0_KEY2, S0_KEY3);
    ascon_set_nonce(S0_NONCE0, S0_NONCE1, S0_NONCE2, S0_NONCE3);
    ascon_set_ptext(S0_P0, S0_P1, 8u);
}

static void configure_s1(void)
{
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(S1_KEY0, S1_KEY1, S1_KEY2, S1_KEY3);
    ascon_set_nonce(S1_NONCE0, S1_NONCE1, S1_NONCE2, S1_NONCE3);
    ascon_set_ptext(S1_P0, S1_P1, 8u);
}

static uint32_t reload_s0(void)
{
    uint32_t start = read_cycle32();
    ascon_soft_reset();
    configure_s0();
    return read_cycle32() - start;
}

static uint32_t reload_s1(void)
{
    uint32_t start = read_cycle32();
    ascon_soft_reset();
    configure_s1();
    return read_cycle32() - start;
}

static void read_outputs(uint32_t *ct0, uint32_t *ct1,
                         uint32_t *tag0, uint32_t *tag1,
                         uint32_t *tag2, uint32_t *tag3)
{
    ASCON_READ(ASCON_OFS_CTEXT_0, *ct0);
    ASCON_READ(ASCON_OFS_CTEXT_1, *ct1);
    ASCON_READ(ASCON_OFS_TAG_0, *tag0);
    ASCON_READ(ASCON_OFS_TAG_1, *tag1);
    ASCON_READ(ASCON_OFS_TAG_2, *tag2);
    ASCON_READ(ASCON_OFS_TAG_3, *tag3);
}

static void fail_with_marker(uint32_t a0, uint32_t a1)
{
    DMEM32(AUX0_ADDR) = a0;
    DMEM32(AUX1_ADDR) = a1;
    __asm__ volatile ("fence w,w" ::: "memory");
    dualcore_fail_stop();
}

static uint32_t run_loaded_session(uint32_t fail_code)
{
    uint32_t start;
    uint32_t status;

    start = read_cycle32();
    ascon_core_start();
    ascon_wait_core_done();
    status = ascon_read_raw(ASCON_OFS_STATUS);
    if ((status & ASCON_ST_CORE_ERR) != 0u) {
        fail_with_marker(fail_code, status);
    }
    return read_cycle32() - start;
}

int main(void)
{
    uint32_t hart = dualcore_hartid();

    if (hart != 0u) {
        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
            __asm__ volatile ("nop");
        }
    }

    uint32_t ct0_0, ct0_1, tag0_0, tag0_1, tag0_2, tag0_3;
    uint32_t ct1_0, ct1_1, tag1_0, tag1_1, tag1_2, tag1_3;
    uint32_t reload_cycles[6];
    uint32_t active0, active1, active0b;
    uint32_t reload_sum = 0u;
    uint32_t reload_avg;
    uint32_t active_avg;

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);

    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_RELOAD_BEGIN;
    __asm__ volatile ("fence w,w" ::: "memory");
    reload_cycles[0] = reload_s0();
    reload_cycles[1] = reload_s1();
    reload_cycles[2] = reload_s0();
    reload_cycles[3] = reload_s1();
    reload_cycles[4] = reload_s0();
    reload_cycles[5] = reload_s1();
    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_RELOAD_DONE;
    __asm__ volatile ("fence w,w" ::: "memory");

    for (uint32_t i = 0; i < 6u; i++) {
        reload_sum += reload_cycles[i];
    }
    reload_avg = reload_sum / 6u;
    DMEM32(BASE_BENCH_RELOAD_AVG_ADDR) = reload_avg;

    reload_s0();
    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_S0_RUN;
    __asm__ volatile ("fence w,w" ::: "memory");
    active0 = run_loaded_session(0x3C1E1000u);
    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_S0_DONE;
    __asm__ volatile ("fence w,w" ::: "memory");
    read_outputs(&ct0_0, &ct0_1, &tag0_0, &tag0_1, &tag0_2, &tag0_3);
    DMEM32(BASE_BENCH_S0_CT0_ADDR) = ct0_0;
    DMEM32(BASE_BENCH_S0_CT1_ADDR) = ct0_1;
    DMEM32(BASE_BENCH_S0_TAG0_ADDR) = tag0_0;
    DMEM32(BASE_BENCH_S0_TAG1_ADDR) = tag0_1;
    DMEM32(BASE_BENCH_S0_TAG2_ADDR) = tag0_2;
    DMEM32(BASE_BENCH_S0_TAG3_ADDR) = tag0_3;

    reload_s1();
    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_S1_RUN;
    __asm__ volatile ("fence w,w" ::: "memory");
    active1 = run_loaded_session(0x3C1E1001u);
    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_S1_DONE;
    __asm__ volatile ("fence w,w" ::: "memory");
    read_outputs(&ct1_0, &ct1_1, &tag1_0, &tag1_1, &tag1_2, &tag1_3);
    if ((ct1_0 == ct0_0) &&
        (ct1_1 == ct0_1) &&
        (tag1_0 == tag0_0) &&
        (tag1_1 == tag0_1) &&
        (tag1_2 == tag0_2) &&
        (tag1_3 == tag0_3)) {
        fail_with_marker(0x3C1B1000u, tag1_0);
    }

    reload_s0();
    active0b = run_loaded_session(0x3C1E1002u);
    read_outputs(&ct0_0, &ct0_1, &tag0_0, &tag0_1, &tag0_2, &tag0_3);
    if ((ct0_0 != DMEM32(BASE_BENCH_S0_CT0_ADDR)) ||
        (ct0_1 != DMEM32(BASE_BENCH_S0_CT1_ADDR)) ||
        (tag0_0 != DMEM32(BASE_BENCH_S0_TAG0_ADDR)) ||
        (tag0_1 != DMEM32(BASE_BENCH_S0_TAG1_ADDR)) ||
        (tag0_2 != DMEM32(BASE_BENCH_S0_TAG2_ADDR)) ||
        (tag0_3 != DMEM32(BASE_BENCH_S0_TAG3_ADDR))) {
        fail_with_marker(0x3C1C1000u, tag0_0);
    }

    active_avg = (active0 + active1 + active0b) / 3u;
    DMEM32(BASE_BENCH_ACTIVE_AVG_ADDR) = active_avg;

    DMEM32(SHARED_COUNT_ADDR) = BASE_STAGE_VERIFY_DONE;
    DMEM32(AUX0_ADDR) = reload_avg;
    DMEM32(AUX1_ADDR) = active_avg;
    DMEM32(SHARED_COUNT_ADDR) = 2u;
    DMEM32(HEARTBEAT_ADDR) = 6u;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }

    return 0;
}
