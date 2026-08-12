/* Baseline no-CRF proof using real MMIO reloads.
 *
 * Goal:
 * - Run session 0 on CPU0 and publish its outputs.
 * - Run session 1 on CPU1 after a full register reload.
 * - Reload session 0 again and re-run it, proving the baseline needs
 *   software reload instead of H3 context-bank preservation.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"
#include "dmem_layout.h"

#define SIG0_VALUE 0x3C100001u
#define SIG1_VALUE 0x3C100002u

#define S0_MODE   ASCON_MODE_128_ENC
#define S1_MODE   ASCON_MODE_128_ENC

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

#define BASE_S0_CT0_ADDR   0x10000380u
#define BASE_S0_CT1_ADDR   0x10000384u
#define BASE_S0_TAG0_ADDR  0x10000388u
#define BASE_S0_TAG1_ADDR  0x1000038Cu
#define BASE_S0_TAG2_ADDR  0x10000390u
#define BASE_S0_TAG3_ADDR  0x10000394u
#define CPU1_BOOT_DELAY    4096u

static inline uint32_t ascon_read_raw(uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    return *p;
}

static void configure_s0(void)
{
    ascon_set_mode(S0_MODE);
    ascon_set_key(S0_KEY0, S0_KEY1, S0_KEY2, S0_KEY3);
    ascon_set_nonce(S0_NONCE0, S0_NONCE1, S0_NONCE2, S0_NONCE3);
    ascon_set_ptext(S0_P0, S0_P1, 8u);
}

static void configure_s1(void)
{
    ascon_set_mode(S1_MODE);
    ascon_set_key(S1_KEY0, S1_KEY1, S1_KEY2, S1_KEY3);
    ascon_set_nonce(S1_NONCE0, S1_NONCE1, S1_NONCE2, S1_NONCE3);
    ascon_set_ptext(S1_P0, S1_P1, 8u);
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

static void spin_delay(uint32_t cycles)
{
    for (uint32_t i = 0; i < cycles; i++) {
        __asm__ volatile ("nop");
    }
}

static void run_loaded_session(uint32_t fail_code)
{
    uint32_t status;

    ascon_core_start();
    ascon_wait_core_done();
    status = ascon_read_raw(ASCON_OFS_STATUS);
    if ((status & ASCON_ST_CORE_ERR) != 0u) {
        fail_with_marker(fail_code, status);
    }
}

int main(void)
{
    uint32_t hart = dualcore_hartid();

    if (hart == 0u) {
        uint32_t ct0_0, ct0_1, tag0_0, tag0_1, tag0_2, tag0_3;

        dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
    ascon_soft_reset();
        configure_s0();
        run_loaded_session(0x3C1E0000u);

        read_outputs(&ct0_0, &ct0_1, &tag0_0, &tag0_1, &tag0_2, &tag0_3);
        DMEM32(BASE_S0_CT0_ADDR) = ct0_0;
        DMEM32(BASE_S0_CT1_ADDR) = ct0_1;
        DMEM32(BASE_S0_TAG0_ADDR) = tag0_0;
        DMEM32(BASE_S0_TAG1_ADDR) = tag0_1;
        DMEM32(BASE_S0_TAG2_ADDR) = tag0_2;
        DMEM32(BASE_S0_TAG3_ADDR) = tag0_3;
        DMEM32(AUX0_ADDR) = 0x3C1A0000u;

        DMEM32(SHARED_COUNT_ADDR) = 1u;
        DMEM32(HEARTBEAT_ADDR) = 1u;
        __asm__ volatile ("fence w,w" ::: "memory");

        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }
    }

    spin_delay(CPU1_BOOT_DELAY);

    while (DMEM32(RESULT_ADDR) != RESULT_RUNNING) {
        __asm__ volatile ("nop");
    }
    while (DMEM32(SHARED_COUNT_ADDR) != 1u) {
        __asm__ volatile ("nop");
    }
    dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

    uint32_t ct1_0, ct1_1, tag1_0, tag1_1, tag1_2, tag1_3;
    uint32_t s0_chk0, s0_chk1, s0_tag0, s0_tag1, s0_tag2, s0_tag3;

    ascon_soft_reset();

    configure_s1();
    run_loaded_session(0x3C1E0001u);

    read_outputs(&ct1_0, &ct1_1, &tag1_0, &tag1_1, &tag1_2, &tag1_3);
    if ((ct1_0 == DMEM32(BASE_S0_CT0_ADDR)) &&
        (ct1_1 == DMEM32(BASE_S0_CT1_ADDR)) &&
        (tag1_0 == DMEM32(BASE_S0_TAG0_ADDR)) &&
        (tag1_1 == DMEM32(BASE_S0_TAG1_ADDR)) &&
        (tag1_2 == DMEM32(BASE_S0_TAG2_ADDR)) &&
        (tag1_3 == DMEM32(BASE_S0_TAG3_ADDR))) {
        fail_with_marker(0x3C1B0000u, tag1_0);
    }

    ascon_soft_reset();
    configure_s0();
    run_loaded_session(0x3C1E0002u);

    read_outputs(&s0_chk0, &s0_chk1, &s0_tag0, &s0_tag1, &s0_tag2, &s0_tag3);
    if ((s0_chk0 != DMEM32(BASE_S0_CT0_ADDR)) ||
        (s0_chk1 != DMEM32(BASE_S0_CT1_ADDR)) ||
        (s0_tag0 != DMEM32(BASE_S0_TAG0_ADDR)) ||
        (s0_tag1 != DMEM32(BASE_S0_TAG1_ADDR)) ||
        (s0_tag2 != DMEM32(BASE_S0_TAG2_ADDR)) ||
        (s0_tag3 != DMEM32(BASE_S0_TAG3_ADDR))) {
        fail_with_marker(s0_chk0, s0_tag0);
    }

    DMEM32(AUX1_ADDR) = 0x3C1B0001u;
    DMEM32(SHARED_COUNT_ADDR) = 2u;
    DMEM32(HEARTBEAT_ADDR) = 4u;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }

    return 0;
}
