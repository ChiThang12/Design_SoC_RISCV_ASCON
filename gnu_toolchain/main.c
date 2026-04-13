/* ============================================================================
 * main.c — ASCON DMA Firmware: IMEM → DMEM → ASCON DMA → DMEM
 * Version : 7.0
 *
 * FIX v7.0 — FIX-CTRL-DMA-START
 * ─────────────────────────────────────────────────────────────────────────────
 * [ROOT CAUSE v6]
 *   ASCON_CTRL_DMA_START được định nghĩa là (1u << 2) = 0x4 (chỉ DMA_EN).
 *   Theo RTL (ascon_axi_slave.v line 372, line 383):
 *     bit[0] = CORE_START  (1-cycle pulse kích CORE)
 *     bit[1] = SOFT_RST
 *     bit[2] = DMA_EN      (enable + start DMA)
 *   → Thiếu bit[0]: DMA kéo dữ liệu xong nhưng CORE không được kích
 *     → CORE_DONE không bao giờ set → timeout ở bước poll CORE_DONE.
 *
 * [FIX]
 *   Trong ascon.h v2.5:
 *     ASCON_CTRL_DMA_START = ASCON_CTRL_CORE_START | ASCON_CTRL_DMA_EN
 *                          = (1u << 0) | (1u << 2) = 0x5
 *   → Một lần ghi CTRL = 0x5 đồng thời kích cả DMA lẫn CORE.
 *
 * [FLOW GHI THANH GHI — CỐ ĐỊNH, KHÔNG ĐỔI THỨ TỰ]
 *   1. PTEXT_0  → DMEM (CPU store)
 *   2. CTRL     = SOFT_RST  (0x2)
 *   3. MODE     = 128_ENC   (0x0)
 *   4. KEY[0..3]
 *   5. NONCE[0..3]
 *   6. DMA_SRC, DMA_DST, DMA_LEN
 *   7. fence rw, rw
 *   8. CTRL     = DMA_START (0x5)   ← bit0|bit2, không phải 0x4
 *   9. Poll DMA_DONE | DMA_ERR
 *  10. Poll CORE_DONE | CORE_ERR
 *  11. Lưu STATUS + RETCODE về DMEM
 *
 * COMPILE:
 *   ./compile_c_to_hex.sh -i main.c -o program.hex -k -O 1 -c
 * ============================================================================ */

#include <stdint.h>
#include "ascon.h"
#include "dmem_layout.h"

/* ── Key / Nonce ─────────────────────────────────────────────────────────── */
#define MY_KEY_0    0xDEADBEEFu
#define MY_KEY_1    0xCAFEBABEu
#define MY_KEY_2    0x01234567u
#define MY_KEY_3    0x89ABCDEFu

#define MY_NONCE_0  0x11111111u
#define MY_NONCE_1  0x22222222u
#define MY_NONCE_2  0x33333333u
#define MY_NONCE_3  0x44444444u

#define MY_PTEXT    0xDEADBEEFu

#define TIMEOUT_LIMIT   0x000FFFFFu

/* ─────────────────────────────────────────────────────────────────────────
 * NOP_BARRIER: drain LSU pipeline, ngăn SoC gộp AXI burst
 * ───────────────────────────────────────────────────────────────────────── */
#define NOP_BARRIER() __asm__ volatile ( \
    "nop\nnop\nnop\nnop\n"              \
    "nop\nnop\nnop\nnop\n"              \
    ::: "memory"                         \
)

/* ─────────────────────────────────────────────────────────────────────────
 * SW_SINGLE: 1 store = 1 AXI beat, với NOP_BARRIER tránh burst
 * ───────────────────────────────────────────────────────────────────────── */
#define SW_SINGLE(addr, val) do {                       \
    __asm__ volatile (                                  \
        "sw   %1, 0(%0)\n"                              \
        "fence w, w\n"                                  \
        :                                               \
        : "r" ((volatile uint32_t *)(uintptr_t)(addr)), \
          "r" ((uint32_t)(val))                         \
        : "memory"                                      \
    );                                                  \
    NOP_BARRIER();                                      \
} while (0)

/* =========================================================================
 * main
 * ========================================================================= */
int main(void)
{
    uint32_t status  = 0u;
    uint32_t retcode = 0u;
    uint32_t timeout;

    /* ── 1. CPU store plaintext → DMEM[PTEXT_0] ────────────────────────── */
    SW_SINGLE(DMEM_BASE + offsetof(DmemLayout_t, PTEXT_0), MY_PTEXT);

    /* ── 2. ASCON soft reset ─────────────────────────────────────────────
     * ASCON_CTRL_SOFT_RST = bit[1] = 0x2
     * ────────────────────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);
    NOP_BARRIER();
    NOP_BARRIER();

    /* ── 3. Set MODE: ASCON-128 Encrypt (0x0) ─────────────────────────── */
    ASCON_WRITE(ASCON_OFS_MODE, ASCON_MODE_128_ENC);
    NOP_BARRIER();

    /* ── 4. Set KEY (4 word) ─────────────────────────────────────────────
     * ASCON_OFS_KEY_0 = 0x010
     * ASCON_OFS_KEY_1 = 0x014
     * ASCON_OFS_KEY_2 = 0x018
     * ASCON_OFS_KEY_3 = 0x01C
     * ────────────────────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_KEY_0, MY_KEY_0);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_KEY_1, MY_KEY_1);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_KEY_2, MY_KEY_2);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_KEY_3, MY_KEY_3);
    NOP_BARRIER();

    /* ── 5. Set NONCE (4 word) ───────────────────────────────────────────
     * ASCON_OFS_NONCE_0 = 0x024
     * ASCON_OFS_NONCE_1 = 0x028
     * ASCON_OFS_NONCE_2 = 0x02C
     * ASCON_OFS_NONCE_3 = 0x030
     * ────────────────────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_NONCE_0, MY_NONCE_0);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_NONCE_1, MY_NONCE_1);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_NONCE_2, MY_NONCE_2);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_NONCE_3, MY_NONCE_3);
    NOP_BARRIER();

    /* ── 6. Set DMA_SRC, DMA_DST, DMA_LEN ──────────────────────────────
     * ASCON_OFS_DMA_SRC = 0x100  →  src  = DMEM PTEXT_0 (0x100001C0)
     * ASCON_OFS_DMA_DST = 0x104  →  dst  = DMEM CTEXT_0 (0x100001D0)
     * ASCON_OFS_DMA_LEN = 0x108  →  len  = 4 bytes (ASCON_BLOCK_SIZE)
     * ────────────────────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_DMA_SRC, DMEM_DMA_SRC_ADDR);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_DMA_DST, DMEM_DMA_OUTPUT_ADDR);
    NOP_BARRIER();
    ASCON_WRITE(ASCON_OFS_DMA_LEN, DMEM_DMA_INPUT_LEN);
    NOP_BARRIER();

    /* ── 7. Full barrier trước khi start ─────────────────────────────── */
    __asm__ volatile ("fence rw, rw" ::: "memory");

    /* ── 8. DMA START: CTRL = ASCON_CTRL_DMA_START = 0x5 ────────────────
     *
     * FIX v7.0: ghi 0x5 (bit0 | bit2), không phải 0x4 (bit2 đơn độc).
     *
     *   bit[2] DMA_EN     = 1  → kích DMA kéo 4B từ DMA_SRC → CORE
     *   bit[0] CORE_START = 1  → kích CORE xử lý ngay khi DMA nạp xong
     *
     * Nếu chỉ ghi 0x4 (thiếu bit0): DMA chạy bình thường, nhưng CORE
     * không nhận lệnh START → CORE_DONE không bao giờ set → timeout.
     * ────────────────────────────────────────────────────────────────────── */
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);   /* 0x5 = bit0|bit2 */
    NOP_BARRIER();

    /* ── 9. Poll DMA_DONE với timeout ───────────────────────────────────
     * ASCON_ST_DMA_DONE = bit[3], ASCON_ST_DMA_ERR = bit[5]
     * ────────────────────────────────────────────────────────────────────── */
    timeout = TIMEOUT_LIMIT;
    do {
        NOP_BARRIER();
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            retcode = (uint32_t)(-2);
            goto done;
        }
    } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR)));

    if (status & ASCON_ST_DMA_ERR) {
        retcode = (uint32_t)(-1);
        goto done;
    }

    /* ── 10. Poll CORE_DONE (tag generation) ────────────────────────────
     * ASCON_ST_CORE_DONE = bit[1], ASCON_ST_CORE_ERR = bit[4]
     *
     * CORE đã được kích bởi CTRL bit[0] ở bước 8.
     * Chờ CORE hoàn thành sinh tag sau khi DMA hoàn thành.
     * ────────────────────────────────────────────────────────────────────── */
    timeout = TIMEOUT_LIMIT;
    do {
        NOP_BARRIER();
        ASCON_READ(ASCON_OFS_STATUS, status);
        if (--timeout == 0u) {
            retcode = (uint32_t)(-2);
            goto done;
        }
    } while (!(status & ASCON_ST_CORE_DONE));

    if (status & ASCON_ST_CORE_ERR) {
        retcode = (uint32_t)(-1);
        goto done;
    }

    retcode = 0u;

done:
    /* ── 11. Lưu STATUS + RETCODE về DMEM ───────────────────────────── */
    SW_SINGLE(DMEM_BASE + offsetof(DmemLayout_t, STATUS),  status);
    SW_SINGLE(DMEM_BASE + offsetof(DmemLayout_t, RETCODE), retcode);

    /* ── 12. Halt ────────────────────────────────────────────────────── */
    while (1) __asm__ volatile ("nop");
    return 0;
}