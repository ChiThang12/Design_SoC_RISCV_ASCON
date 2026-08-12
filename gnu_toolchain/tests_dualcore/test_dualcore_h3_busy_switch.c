/* H3 negative test: switch CONTEXT_SEL while core is busy.
 *
 * Goal:
 * - Build a clean reference output for context 0.
 * - Start context 0 again.
 * - While core 0 is busy, CPU1 switches CONTEXT_SEL and writes context 1.
 * - Verify the in-flight context 0 result still matches the clean reference.
 * - Run context 1 afterwards and verify context 0 is still preserved.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"

#define SIG0_VALUE 0x3C00C101u
#define SIG1_VALUE 0x3C00C102u

#define CTX0_MODE   ASCON_MODE_128_ENC
#define CTX1_MODE   ASCON_MODE_128_ENC

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

#define CTX1_KEY0   0x89ABCDEFu
#define CTX1_KEY1   0x01234567u
#define CTX1_KEY2   0x76543210u
#define CTX1_KEY3   0xFEDCBA98u
#define CTX1_NONCE0 0x0A0B0C0Du
#define CTX1_NONCE1 0x0E0F1011u
#define CTX1_NONCE2 0x12131415u
#define CTX1_NONCE3 0x16171819u
#define CTX1_P0     0xCAFEBABEu
#define CTX1_P1     0xDEADBEEFu

#define H3_BUSY_CTX0_CT0_ADDR   0x100003E0u
#define H3_BUSY_CTX0_CT1_ADDR   0x100003E4u
#define H3_BUSY_CTX0_TAG0_ADDR  0x100003E8u
#define H3_BUSY_CTX0_TAG1_ADDR  0x100003ECu
#define H3_BUSY_CTX0_TAG2_ADDR  0x100003F0u
#define H3_BUSY_CTX0_TAG3_ADDR  0x100003F4u

static inline uint32_t ascon_read_raw(uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    return *p;
}

static void spin_delay(uint32_t cycles)
{
    while (cycles-- != 0u) {
        __asm__ volatile ("nop");
    }
}

static void configure_ctx0(void)
{
    ascon_select_context(0u);
    ascon_set_mode(CTX0_MODE);
    ascon_set_key(CTX0_KEY0, CTX0_KEY1, CTX0_KEY2, CTX0_KEY3);
    ascon_set_nonce(CTX0_NONCE0, CTX0_NONCE1, CTX0_NONCE2, CTX0_NONCE3);
    ascon_clear_ad();
    ascon_set_ptext(CTX0_P0, CTX0_P1, 8u);
}

static void configure_ctx1(void)
{
    ascon_select_context(1u);
    ascon_set_mode(CTX1_MODE);
    ascon_set_key(CTX1_KEY0, CTX1_KEY1, CTX1_KEY2, CTX1_KEY3);
    ascon_set_nonce(CTX1_NONCE0, CTX1_NONCE1, CTX1_NONCE2, CTX1_NONCE3);
    ascon_clear_ad();
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

static void run_and_check(uint32_t fail_code)
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

    if (hart != 0u) {
        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
            __asm__ volatile ("nop");
        }
    }

    uint32_t ref_ct0, ref_ct1, ref_tag0, ref_tag1, ref_tag2, ref_tag3;
    uint32_t run_ct0, run_ct1, run_tag0, run_tag1, run_tag2, run_tag3;
    uint32_t status;

    dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
    ascon_soft_reset();
    spin_delay(64u);

    configure_ctx0();
    configure_ctx0();
    run_and_check(0x3C0E1000u);
    read_outputs(&ref_ct0, &ref_ct1, &ref_tag0, &ref_tag1, &ref_tag2, &ref_tag3);

    DMEM32(H3_BUSY_CTX0_CT0_ADDR) = ref_ct0;
    DMEM32(H3_BUSY_CTX0_CT1_ADDR) = ref_ct1;
    DMEM32(H3_BUSY_CTX0_TAG0_ADDR) = ref_tag0;
    DMEM32(H3_BUSY_CTX0_TAG1_ADDR) = ref_tag1;
    DMEM32(H3_BUSY_CTX0_TAG2_ADDR) = ref_tag2;
    DMEM32(H3_BUSY_CTX0_TAG3_ADDR) = ref_tag3;

    configure_ctx0();

    DMEM32(SHARED_COUNT_ADDR) = 1u;
    DMEM32(HEARTBEAT_ADDR) = 1u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_core_start();
    ascon_select_context(1u);
    configure_ctx1();
    ascon_select_context(0u);
    ascon_select_context(1u);
    DMEM32(AUX1_ADDR) = 0x3C0B1001u;
    DMEM32(SHARED_COUNT_ADDR) = 2u;
    DMEM32(HEARTBEAT_ADDR) = 2u;
    __asm__ volatile ("fence w,w" ::: "memory");

    ascon_wait_core_done();
    status = ascon_read_raw(ASCON_OFS_STATUS);
    if ((status & ASCON_ST_CORE_ERR) != 0u) {
        fail_with_marker(0x3C0E1001u, status);
    }

    ascon_select_context(0u);
    read_outputs(&run_ct0, &run_ct1, &run_tag0, &run_tag1, &run_tag2, &run_tag3);
    if ((run_ct0 != ref_ct0) || (run_ct1 != ref_ct1) ||
        (run_tag0 != ref_tag0) || (run_tag1 != ref_tag1) ||
        (run_tag2 != ref_tag2) || (run_tag3 != ref_tag3)) {
        fail_with_marker(0x3C0C1000u, run_tag0);
    }

    DMEM32(AUX0_ADDR) = 0x3C0C1000u;
    DMEM32(SHARED_COUNT_ADDR) = 3u;
    DMEM32(HEARTBEAT_ADDR) = 4u;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }
}
