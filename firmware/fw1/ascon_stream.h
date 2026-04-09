#ifndef ASCON_STREAM_H
#define ASCON_STREAM_H

/* ============================================================================
 * ascon_stream.h — Interrupt-driven streaming context
 *
 * Mô hình:
 *   - CPU ghi plaintext vào DMEM, kick DMA, rồi làm việc khác.
 *   - ASCON DMA xong → IRQ → ISR lấy kết quả, kick block tiếp nếu còn.
 *   - CPU kiểm tra g_stream.done trong main loop khi cần.
 *
 * Thiết kế để dễ upgrade:
 *   - Thay ascon_stream_feed_cpu() bằng soc_dma_feed() khi có SoC DMA.
 *   - ISR không thay đổi.
 * ============================================================================ */

#include <stdint.h>
#include "ascon_regs.h"
#include "dmem_layout.h"

/* ── Cấu hình ─────────────────────────────────────────────────────────────── */

#define ASCON_BLOCK_SIZE    4u      /* bytes mỗi block plaintext */
#define ASCON_OUTPUT_SIZE   24u     /* bytes output: 8 ctext + 16 tag */
#define STREAM_MAX_BLOCKS   16u     /* tối đa 16 blocks mỗi session */

/*
 * IRQ_EN value:
 *   Bit 1 (0x02) = enable interrupt khi DMA_DONE.
 *
 * FIXED: IRQ_EN offset conflict
 *   ascon_regs.h  → IRQ_EN @ 0x008 (wrong)
 *   ascon_axi_slave.v → ADDR_IRQ_EN = 12'h00C (correct)
 *   Fix: Use raw pointer to 0x00C instead of ASCON->IRQ_EN
 */
#define IRQ_EN_DMA_DONE     0x02u

/* ── Output buffer ────────────────────────────────────────────────────────── */

typedef struct {
    uint32_t ctext[2];   /* ciphertext word 0..1 */
    uint32_t tag[4];     /* auth tag word 0..3    */
} AsconBlockOut_t;

/* ── Stream context (global, shared CPU ↔ ISR) ───────────────────────────── */

typedef struct {
    /* Input (CPU thiết lập trước khi start) */
    const uint8_t  *ptext;          /* con trỏ plaintext buffer */
    uint32_t        n_blocks;       /* tổng số block */
    uint32_t        key[4];         /* 128-bit key   */
    uint32_t        nonce[4];       /* 128-bit nonce */

    /* Output (ISR ghi sau mỗi block) */
    AsconBlockOut_t out[STREAM_MAX_BLOCKS];

    /* State (CPU đọc, ISR ghi — volatile) */
    volatile uint32_t cur_block;    /* block đang xử lý (0-based) */
    volatile uint32_t done;         /* 1 = tất cả blocks xong     */
    volatile uint32_t error;        /* STATUS khi lỗi, 0 nếu OK   */
} AsconStream_t;

/* Singleton — định nghĩa trong main.c */
extern AsconStream_t g_stream;

/* ── Internal: ghi plaintext block vào DMEM (CPU-write path) ─────────────── */

/*
 * Hiện tại: CPU copy từ g_stream.ptext[block] → DMEM.
 * Tương lai: Thay bằng SoC DMA transfer, hàm này là điểm thay thế duy nhất.
 */
__attribute__((optimize("O0"), noinline))
static void ascon_feed_block_cpu(uint32_t block_idx)
{
    const uint8_t *src = g_stream.ptext + block_idx * ASCON_BLOCK_SIZE;

    /* Copy đúng 4 bytes (1 word = ASCON_BLOCK_SIZE) vào DMEM PTEXT_0 */
    uint32_t w0;
    __builtin_memcpy(&w0, src, 4);

    DMEM->PTEXT_0 = w0;

    /*
     * Full fence: đảm bảo DCache writeback về SRAM trước khi
     * ASCON DMA (M2) đọc. fence w,w không đủ (chỉ ordering, không flush).
     */
    __asm__ volatile ("fence" ::: "memory");
}

/* ── Internal: reset + config ASCON cho 1 block ─────────────────────────── */

__attribute__((optimize("O0"), noinline))
static int ascon_config_block(void)
{
    /* Config */
    ASCON_WRITE(ASCON->MODE,    MODE_ENCRYPT);
    ASCON_WRITE(ASCON->IRQ_EN,  IRQ_EN_DMA_DONE);  /* FIXED: Struct updated to match RTL */
    ASCON_WRITE(ASCON->KEY_0,   g_stream.key[0]);
    ASCON_WRITE(ASCON->KEY_1,   g_stream.key[1]);
    ASCON_WRITE(ASCON->KEY_2,   g_stream.key[2]);
    ASCON_WRITE(ASCON->KEY_3,   g_stream.key[3]);
    ASCON_WRITE(ASCON->NONCE_0, g_stream.nonce[0]);
    ASCON_WRITE(ASCON->NONCE_1, g_stream.nonce[1]);
    ASCON_WRITE(ASCON->NONCE_2, g_stream.nonce[2]);
    ASCON_WRITE(ASCON->NONCE_3, g_stream.nonce[3]);
    ASCON_WRITE(ASCON->DATA_LEN, (uint32_t)(ASCON_BLOCK_SIZE & DATA_LEN_MASK));

    return 0;
}

/* ── Internal: kick DMA cho block hiện tại ───────────────────────────────── */

__attribute__((optimize("O0"), noinline))
static void ascon_kick_dma(void)
{
    ASCON_WRITE(ASCON->DMA_SRC, DMEM_DMA_SRC_ADDR);     /* PTEXT_0 */
    ASCON_WRITE(ASCON->DMA_DST, DMEM_DMA_OUTPUT_ADDR);  /* CTEXT_0 */
    ASCON_WRITE(ASCON->DMA_LEN, DMEM_DMA_INPUT_LEN);    /* 8 bytes */

    /* Triple fence + full fence trước START */
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile ("fence w,w" ::: "memory");
    __asm__ volatile (
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        "nop\nnop\nnop\nnop\nnop\nnop\nnop\nnop\n"
        ::: "memory"
    );
    __asm__ volatile ("fence" ::: "memory");

    ASCON_WRITE(ASCON->CTRL, CTRL_DMA_START);
}

/* ── Public API ───────────────────────────────────────────────────────────── */

/*
 * ascon_stream_start() — CPU gọi để kick block đầu tiên.
 * Trả về 0 nếu OK, -3 nếu reset timeout.
 */
__attribute__((optimize("O0"), noinline))
static int ascon_stream_start(void)
{
    g_stream.cur_block = 0u;
    g_stream.done      = 0u;
    g_stream.error     = 0u;

    ascon_feed_block_cpu(0u);

    int r = ascon_config_block();
    if (r != 0) {
        g_stream.error = (uint32_t)(uint32_t)(-3);
        g_stream.done  = 1u;
        return r;
    }

    ascon_kick_dma();
    return 0;
}

/*
 * ascon_isr() — gọi từ trap handler khi MEIP (PLIC source 8).
 *
 * Làm:
 *   1. PLIC claim → xác nhận source = ASCON (8).
 *   2. Đọc STATUS, kiểm tra lỗi.
 *   3. Copy ctext + tag từ DMEM/ASCON regs vào g_stream.out[].
 *   4. ASCON SOFT_RST (clear key/nonce).
 *   5. PLIC complete.
 *   6. Nếu còn block: feed + config + kick block tiếp.
 *      Nếu hết: set g_stream.done = 1.
 */
__attribute__((optimize("O0"), noinline))
void ascon_isr(void);

#endif /* ASCON_STREAM_H */