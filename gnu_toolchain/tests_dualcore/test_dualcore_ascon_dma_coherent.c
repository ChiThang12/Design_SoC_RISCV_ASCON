/* Dual-core end-to-end ASCON DMA coherency proof.
 *
 * Coverage:
 * - CPU0 leaves the plaintext source line dirty in DCache with no fence.
 * - ASCON DMA coherent read must snoop CPU0 and consume the latest plaintext.
 * - CPU0 and CPU1 both keep different output cache lines dirty/stale before DMA.
 * - ASCON DMA coherent write must invalidate both cached output lines so each
 *   hart refetches fresh ciphertext/tag data after completion.
 */
#include <stdint.h>
#include "dualcore_common.h"
#include "ascon.h"
#include "dmem_layout.h"
#include "gpio.h"

#define SIG0_VALUE 0xA5C02301u
#define SIG1_VALUE 0xD24A6003u

#define TV_KEY_0    0x00010203u
#define TV_KEY_1    0x04050607u
#define TV_KEY_2    0x08090A0Bu
#define TV_KEY_3    0x0C0D0E0Fu
#define TV_NONCE_0  0x10111213u
#define TV_NONCE_1  0x14151617u
#define TV_NONCE_2  0x18191A1Bu
#define TV_NONCE_3  0x1C1D1E1Fu

#define ASCON_OFS_ATU_BASE       0x150u
#define ASCON_OFS_ATU_WINDOW     0x154u
#define ASCON_OFS_DMA_COH_CTRL   0x158u

#define DMA_COH_CTRL_VALUE 3u
#define DMA_TIMEOUT_LIMIT  0x0000FFFFu

#define PT_WORD0       0x12345678u
#define PT_WORD1       0x9ABCDEF0u
#define PT_STALE0      0x11112222u
#define PT_STALE1      0x33334444u

#define OUT0_STALE0    0xC001CAFEu
#define OUT0_STALE1    0xD00DFEEDu
#define OUT0_STALE2    0x0BADB002u
#define OUT0_STALE3    0x0BADC0DEu
#define OUT1_STALE4    0x13579BDFu
#define OUT1_STALE5    0x2468ACE0u

#define EXPECT_CT0     0xDAD6AAB5u
#define EXPECT_CT1     0x9AF53D3Du
#define EXPECT_TAG0    0xF46F7363u
#define EXPECT_TAG1    0xEAF31505u
#define EXPECT_TAG2    0x9AFD1BFBu
#define EXPECT_TAG3    0xE221CC7Fu

#define CPU1_BOOT_DELAY    4096u
#define CPU0_DMA_DELAY     32768u
#define CPU1_DMA_WAIT      98304u
#define CPU0_FINISH_DELAY  131072u

#define GPIO_PASS_VALUE 0xAC03D003u

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

static void fail_with_capture(uint32_t a0, uint32_t a1)
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

static void configure_ascon_dma(void)
{
    ascon_soft_reset();
    ascon_set_mode(ASCON_MODE_128_ENC);
    ascon_set_key(TV_KEY_0, TV_KEY_1, TV_KEY_2, TV_KEY_3);
    ascon_set_nonce(TV_NONCE_0, TV_NONCE_1, TV_NONCE_2, TV_NONCE_3);
    ascon_clear_ad();

    ASCON_WRITE(ASCON_OFS_DATA_LEN, 8u);
    ASCON_WRITE(ASCON_OFS_IRQ_EN, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_BASE, 0u);
    ASCON_WRITE(ASCON_OFS_ATU_WINDOW, 0u);
    ASCON_WRITE(ASCON_OFS_DMA_COH_CTRL, DMA_COH_CTRL_VALUE);
    ascon_dma_config(PT_MULTI_BASE, CT_MULTI_BASE, 8u);
    ASCON_WRITE(ASCON_OFS_DMA_BURST, 0u);
}

static void seed_source_memory_stale(void)
{
    volatile uint32_t *pt = (volatile uint32_t *)PT_MULTI_BASE;

    pt[0] = PT_STALE0;
    pt[1] = PT_STALE1;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static void dirty_output_line0_without_fence(void)
{
    volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

    ct[0] = OUT0_STALE0;
    ct[1] = OUT0_STALE1;
    ct[2] = OUT0_STALE2;
    ct[3] = OUT0_STALE3;
    __asm__ volatile ("" ::: "memory");
}

static void dirty_output_line1_without_fence(void)
{
    volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

    ct[4] = OUT1_STALE4;
    ct[5] = OUT1_STALE5;
    __asm__ volatile ("" ::: "memory");
}

static void dirty_source_latest_without_fence(void)
{
    volatile uint32_t *pt = (volatile uint32_t *)PT_MULTI_BASE;

    pt[0] = PT_WORD0;
    pt[1] = PT_WORD1;
    __asm__ volatile ("" ::: "memory");
}

static uint32_t start_dma_and_wait(void)
{
    uint32_t status;
    uint32_t timeout = DMA_TIMEOUT_LIMIT;

    ascon_write_raw(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);

    do {
        status = ascon_read_raw(ASCON_OFS_STATUS);
        if (--timeout == 0u) {
            fail_with_capture(0xFFFF0001u, status);
        }
    } while ((status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) == 0u);

    return status;
}

int main(void)
{
    uint32_t hart = dualcore_hartid();
    volatile uint32_t *pt = (volatile uint32_t *)PT_MULTI_BASE;
    volatile uint32_t *ct = (volatile uint32_t *)CT_MULTI_BASE;

    if (hart == 0u) {
        uint32_t status;

        dualcore_publish_start(SIG0_VALUE, SIG1_VALUE);
        gpio_set_dir(0xFFFFFFFFu);
        gpio_write(0u, 0xFFFFFFFFu);
        seed_source_memory_stale();
        configure_ascon_dma();
        dirty_output_line0_without_fence();

        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        spin_delay(CPU0_DMA_DELAY);

        dirty_source_latest_without_fence();
        status = start_dma_and_wait();
        if ((status & (ASCON_ST_DMA_ERR | ASCON_ST_CORE_ERR)) != 0u) {
            fail_with_capture(0xFFFF0002u, status);
        }

        if ((pt[0] != PT_WORD0) || (pt[1] != PT_WORD1)) {
            fail_with_capture(pt[0], pt[1]);
        }

        if ((ct[0] != EXPECT_CT0) || (ct[1] != EXPECT_CT1) ||
            (ct[2] != EXPECT_TAG0) || (ct[3] != EXPECT_TAG1)) {
            fail_with_capture(ct[0], ct[1]);
        }

        spin_delay(CPU0_FINISH_DELAY);
        gpio_write(GPIO_PASS_VALUE, 0xFFFFFFFFu);

        while (1) {
            dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
        }
    }

    spin_delay(CPU1_BOOT_DELAY);
    dirty_output_line1_without_fence();
    spin_delay(CPU1_DMA_WAIT);
    dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);

    if ((ct[4] != EXPECT_TAG2) || (ct[5] != EXPECT_TAG3)) {
        fail_with_capture(ct[4], ct[5]);
    }

    if ((ct[4] == OUT1_STALE4) && (ct[5] == OUT1_STALE5)) {
        fail_with_capture(0xFFFF0003u, ct[5]);
    }

    while (1) {
        dualcore_check_signatures(SIG0_VALUE, SIG1_VALUE);
    }

    return 0;
}
