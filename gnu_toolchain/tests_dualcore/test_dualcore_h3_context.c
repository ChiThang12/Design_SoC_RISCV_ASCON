/* H3 multi-context ASCON proof.
 *
 * Goal:
 * - Keep two ASCON context banks independent through CONTEXT_SEL.
 * - Show that CPU0 can run context 0, CPU1 can run context 1, and switching
 *   back to context 0 preserves its outputs.
 * - Publish simple pass markers in AUX0/AUX1; SoC cycle counts are captured by
 *   the dual-core testbench.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"
#include "dmem_layout.h"

#define SIG0_VALUE 0x3C000001u
#define SIG1_VALUE 0x3C000002u

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

#define H3_CTX0_CT0_ADDR   0x10000380u
#define H3_CTX0_CT1_ADDR   0x10000384u
#define H3_CTX0_TAG0_ADDR  0x10000388u
#define H3_CTX0_TAG1_ADDR  0x1000038Cu
#define H3_CTX0_TAG2_ADDR  0x10000390u
#define H3_CTX0_TAG3_ADDR  0x10000394u
#define CPU1_BOOT_DELAY    4096u

static inline void ascon_write_raw(uint32_t offset, uint32_t val)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    *p = val;
}

static inline uint32_t ascon_read_raw(uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(0x20000000u + offset);
    return *p;
}

static void configure_context(uint32_t context_id,
                              uint32_t mode,
                              uint32_t k0, uint32_t k1, uint32_t k2, uint32_t k3,
                              uint32_t n0, uint32_t n1, uint32_t n2, uint32_t n3,
                              uint32_t p0, uint32_t p1)
{
    ascon_select_context(context_id);
    ascon_set_mode(mode);
    ascon_set_key(k0, k1, k2, k3);
    ascon_set_nonce(n0, n1, n2, n3);
    ascon_set_ptext(p0, p1, 8u);
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

int main(void)
{
    uint32_t hart = dualcore_hartid();
    uint32_t ct0_0, ct0_1, tag0_0, tag0_1, tag0_2, tag0_3;

    if (hart == 0u) {
        uint32_t ct0_chk0, ct0_chk1, tag0_chk0, tag0_chk1, tag0_chk2, tag0_chk3;
        uint32_t status;

        dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
        ascon_soft_reset();

        configure_context(0u, CTX0_MODE,
                          CTX0_KEY0, CTX0_KEY1, CTX0_KEY2, CTX0_KEY3,
                          CTX0_NONCE0, CTX0_NONCE1, CTX0_NONCE2, CTX0_NONCE3,
                          CTX0_P0, CTX0_P1);

        ascon_core_start();
        ascon_wait_core_done();
        status = ascon_read_raw(ASCON_OFS_STATUS);
        if ((status & ASCON_ST_CORE_ERR) != 0u) {
            fail_with_marker(0x3C0E0000u, status);
        }

        read_outputs(&ct0_0, &ct0_1, &tag0_0, &tag0_1, &tag0_2, &tag0_3);
        DMEM32(H3_CTX0_CT0_ADDR) = ct0_0;
        DMEM32(H3_CTX0_CT1_ADDR) = ct0_1;
        DMEM32(H3_CTX0_TAG0_ADDR) = tag0_0;
        DMEM32(H3_CTX0_TAG1_ADDR) = tag0_1;
        DMEM32(H3_CTX0_TAG2_ADDR) = tag0_2;
        DMEM32(H3_CTX0_TAG3_ADDR) = tag0_3;
        DMEM32(AUX0_ADDR) = 0x3C0A0000u;

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
    uint32_t ctx0_chk0, ctx0_chk1, ctx0_tag0, ctx0_tag1, ctx0_tag2, ctx0_tag3;
    uint32_t status;

    ascon_soft_reset();
    ascon_select_context(1u);
    configure_context(1u, CTX1_MODE,
                      CTX1_KEY0, CTX1_KEY1, CTX1_KEY2, CTX1_KEY3,
                      CTX1_NONCE0, CTX1_NONCE1, CTX1_NONCE2, CTX1_NONCE3,
                      CTX1_P0, CTX1_P1);

    ascon_core_start();
    ascon_wait_core_done();
    status = ascon_read_raw(ASCON_OFS_STATUS);
    if ((status & ASCON_ST_CORE_ERR) != 0u) {
        fail_with_marker(0x3C0E0001u, status);
    }

    read_outputs(&ct1_0, &ct1_1, &tag1_0, &tag1_1, &tag1_2, &tag1_3);
    if ((ct1_0 == DMEM32(H3_CTX0_CT0_ADDR)) &&
        (ct1_1 == DMEM32(H3_CTX0_CT1_ADDR)) &&
        (tag1_0 == DMEM32(H3_CTX0_TAG0_ADDR)) &&
        (tag1_1 == DMEM32(H3_CTX0_TAG1_ADDR)) &&
        (tag1_2 == DMEM32(H3_CTX0_TAG2_ADDR)) &&
        (tag1_3 == DMEM32(H3_CTX0_TAG3_ADDR))) {
        fail_with_marker(0x3C0B0000u, tag1_0);
    }

    ascon_select_context(0u);
    read_outputs(&ctx0_chk0, &ctx0_chk1, &ctx0_tag0, &ctx0_tag1, &ctx0_tag2, &ctx0_tag3);
    if ((ctx0_chk0 != DMEM32(H3_CTX0_CT0_ADDR)) ||
        (ctx0_chk1 != DMEM32(H3_CTX0_CT1_ADDR)) ||
        (ctx0_tag0 != DMEM32(H3_CTX0_TAG0_ADDR)) ||
        (ctx0_tag1 != DMEM32(H3_CTX0_TAG1_ADDR)) ||
        (ctx0_tag2 != DMEM32(H3_CTX0_TAG2_ADDR)) ||
        (ctx0_tag3 != DMEM32(H3_CTX0_TAG3_ADDR))) {
        fail_with_marker(ctx0_chk0, ctx0_tag0);
    }

    DMEM32(AUX1_ADDR) = 0x3C0B0001u;
    DMEM32(SHARED_COUNT_ADDR) = 2u;
    DMEM32(HEARTBEAT_ADDR) = 4u;
    __asm__ volatile ("fence w,w" ::: "memory");

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }

    return 0;
}
