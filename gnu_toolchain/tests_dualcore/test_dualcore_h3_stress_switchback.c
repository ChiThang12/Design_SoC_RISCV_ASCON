/* H3 stress test: repeated switch-back across two context banks.
 *
 * Goal:
 * - Configure both contexts once.
 * - Alternate context 0 and context 1 across multiple rounds.
 * - Save the first output of each context as a reference.
 * - Verify every later run matches its own reference after repeated switches.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"

#define SIG0_VALUE 0x3C00D101u
#define SIG1_VALUE 0x3C00D102u

#define CTX0_KEY0   0x00010203u
#define CTX0_KEY1   0x04050607u
#define CTX0_KEY2   0x08090A0Bu
#define CTX0_KEY3   0x0C0D0E0Fu
#define CTX0_NONCE0 0x10111213u
#define CTX0_NONCE1 0x14151617u
#define CTX0_NONCE2 0x18191A1Bu
#define CTX0_NONCE3 0x1C1D1E1Fu
#define CTX0_P0     0x11223344u
#define CTX0_P1     0x55667788u

#define CTX1_KEY0   0x0F0E0D0Cu
#define CTX1_KEY1   0x0B0A0908u
#define CTX1_KEY2   0x07060504u
#define CTX1_KEY3   0x03020100u
#define CTX1_NONCE0 0x21222324u
#define CTX1_NONCE1 0x25262728u
#define CTX1_NONCE2 0x292A2B2Cu
#define CTX1_NONCE3 0x2D2E2F30u
#define CTX1_P0     0xA1B2C3D4u
#define CTX1_P1     0xE5F60718u

#define H3_STRESS_CTX0_CT0_ADDR  0x10000400u
#define H3_STRESS_CTX0_CT1_ADDR  0x10000404u
#define H3_STRESS_CTX0_TAG0_ADDR 0x10000408u
#define H3_STRESS_CTX0_TAG1_ADDR 0x1000040Cu
#define H3_STRESS_CTX0_TAG2_ADDR 0x10000410u
#define H3_STRESS_CTX0_TAG3_ADDR 0x10000414u

#define H3_STRESS_CTX1_CT0_ADDR  0x10000418u
#define H3_STRESS_CTX1_CT1_ADDR  0x1000041Cu
#define H3_STRESS_CTX1_TAG0_ADDR 0x10000420u
#define H3_STRESS_CTX1_TAG1_ADDR 0x10000424u
#define H3_STRESS_CTX1_TAG2_ADDR 0x10000428u
#define H3_STRESS_CTX1_TAG3_ADDR 0x1000042Cu

static inline uint32_t ascon_read_raw(uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    return *p;
}

static void configure_ctx0(void)
{
    ascon_select_context(0u);
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(CTX0_KEY0, CTX0_KEY1, CTX0_KEY2, CTX0_KEY3);
    ascon_set_nonce(CTX0_NONCE0, CTX0_NONCE1, CTX0_NONCE2, CTX0_NONCE3);
    ascon_set_ptext(CTX0_P0, CTX0_P1, 8u);
}

static void configure_ctx1(void)
{
    ascon_select_context(1u);
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(CTX1_KEY0, CTX1_KEY1, CTX1_KEY2, CTX1_KEY3);
    ascon_set_nonce(CTX1_NONCE0, CTX1_NONCE1, CTX1_NONCE2, CTX1_NONCE3);
    ascon_set_ptext(CTX1_P0, CTX1_P1, 8u);
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

static void run_selected_context(uint32_t fail_code)
{
    uint32_t status;

    ascon_core_start();
    ascon_wait_core_done();
    status = ascon_read_raw(ASCON_OFS_STATUS);
    if ((status & ASCON_ST_CORE_ERR) != 0u) {
        fail_with_marker(fail_code, status);
    }
}

static void check_equal(uint32_t base_addr, uint32_t fail_code)
{
    uint32_t ct0, ct1, tag0, tag1, tag2, tag3;

    read_outputs(&ct0, &ct1, &tag0, &tag1, &tag2, &tag3);
    if ((ct0 != DMEM32(base_addr + 0x00u)) ||
        (ct1 != DMEM32(base_addr + 0x04u)) ||
        (tag0 != DMEM32(base_addr + 0x08u)) ||
        (tag1 != DMEM32(base_addr + 0x0Cu)) ||
        (tag2 != DMEM32(base_addr + 0x10u)) ||
        (tag3 != DMEM32(base_addr + 0x14u))) {
        fail_with_marker(fail_code, tag0);
    }
}

static void save_outputs(uint32_t base_addr)
{
    uint32_t ct0, ct1, tag0, tag1, tag2, tag3;

    read_outputs(&ct0, &ct1, &tag0, &tag1, &tag2, &tag3);
    DMEM32(base_addr + 0x00u) = ct0;
    DMEM32(base_addr + 0x04u) = ct1;
    DMEM32(base_addr + 0x08u) = tag0;
    DMEM32(base_addr + 0x0Cu) = tag1;
    DMEM32(base_addr + 0x10u) = tag2;
    DMEM32(base_addr + 0x14u) = tag3;
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

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
    ascon_soft_reset();

    configure_ctx0();
    configure_ctx1();

    ascon_select_context(0u);
    configure_ctx0();
    run_selected_context(0x3C0E2000u);
    save_outputs(H3_STRESS_CTX0_CT0_ADDR);

    ascon_select_context(1u);
    configure_ctx1();
    run_selected_context(0x3C0E2001u);
    save_outputs(H3_STRESS_CTX1_CT0_ADDR);

    if ((DMEM32(H3_STRESS_CTX1_CT0_ADDR) == DMEM32(H3_STRESS_CTX0_CT0_ADDR)) &&
        (DMEM32(H3_STRESS_CTX1_CT1_ADDR) == DMEM32(H3_STRESS_CTX0_CT1_ADDR)) &&
        (DMEM32(H3_STRESS_CTX1_TAG0_ADDR) == DMEM32(H3_STRESS_CTX0_TAG0_ADDR)) &&
        (DMEM32(H3_STRESS_CTX1_TAG1_ADDR) == DMEM32(H3_STRESS_CTX0_TAG1_ADDR)) &&
        (DMEM32(H3_STRESS_CTX1_TAG2_ADDR) == DMEM32(H3_STRESS_CTX0_TAG2_ADDR)) &&
        (DMEM32(H3_STRESS_CTX1_TAG3_ADDR) == DMEM32(H3_STRESS_CTX0_TAG3_ADDR))) {
        fail_with_marker(0x3C0B2000u, DMEM32(H3_STRESS_CTX1_TAG0_ADDR));
    }

    DMEM32(SHARED_COUNT_ADDR) = 2u;
    DMEM32(HEARTBEAT_ADDR) = 2u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_select_context(0u);
    configure_ctx0();
    run_selected_context(0x3C0E2002u);
    check_equal(H3_STRESS_CTX0_CT0_ADDR, 0x3C0C2000u);
    DMEM32(SHARED_COUNT_ADDR) = 3u;
    DMEM32(HEARTBEAT_ADDR) = 3u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_select_context(1u);
    configure_ctx1();
    run_selected_context(0x3C0E2003u);
    check_equal(H3_STRESS_CTX1_CT0_ADDR, 0x3C0C2001u);
    DMEM32(SHARED_COUNT_ADDR) = 4u;
    DMEM32(HEARTBEAT_ADDR) = 4u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_select_context(0u);
    configure_ctx0();
    run_selected_context(0x3C0E2004u);
    check_equal(H3_STRESS_CTX0_CT0_ADDR, 0x3C0C2002u);
    DMEM32(SHARED_COUNT_ADDR) = 5u;
    DMEM32(HEARTBEAT_ADDR) = 5u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_select_context(1u);
    configure_ctx1();
    run_selected_context(0x3C0E2005u);
    check_equal(H3_STRESS_CTX1_CT0_ADDR, 0x3C0C2003u);
    DMEM32(AUX0_ADDR) = 0x3C0D2000u;
    DMEM32(AUX1_ADDR) = 0x3C0D2001u;
    DMEM32(SHARED_COUNT_ADDR) = 6u;
    DMEM32(HEARTBEAT_ADDR) = 8u;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }
}
