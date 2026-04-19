#ifndef DMEM_LAYOUT_H
#define DMEM_LAYOUT_H

#include <stdint.h>
#include <stddef.h>

/* ============================================================================
 * DMEM Layout — Data Memory (S1, 8KB tổng)
 *
 * Phân vùng SRAM:
 *   0x10000000 – 0x100001B3  g_stream (AsconStream_t, 436 B = 0x1B4)
 *                             ← linker đặt .bss tại đây
 *   0x100001B4 – 0x100001BF  alignment gap (12 B)
 *   0x100001C0 – 0x1000021B  DmemLayout_t (92 B = 0x5C)  ← DMEM base
 *   0x1000021C – 0x100007FF  free (1508 B)
 *   0x10000800 – 0x10000FFF  guard zone (linker-enforced)
 *   0x10001000 – 0x10001FFF  stack (4KB, grows down)
 *
 * QUAN TRỌNG:
 *   DmemLayout_t KHÔNG đặt tại 0x10000000 vì g_stream (.bss) được linker
 *   đặt từ 0x10000000 và chiếm 0x1B4 byte. Dời lên 0x100001C0 tránh overlap.
 *
 *   ASCON hardware registers (MODE, KEY, CTRL, TAG...) vẫn ở S2=0x20000000.
 *   DmemLayout_t chỉ là vùng SRAM trung gian CPU↔DMA — không liên quan
 *   đến RTL register map của ascon_axi_slave.v.
 *
 * Offset map (tính từ DMEM_BASE = 0x100001C0):
 *   +0x0000  PTEXT_0    plaintext word 0  — CPU ghi, DMA đọc
 *   +0x0004  PTEXT_1    (reserved, ASCON_BLOCK_SIZE=4 chỉ dùng PTEXT_0)
 *   +0x0008  _pad0[2]
 *   +0x0010  CTEXT_0    ciphertext word 0 — DMA ghi sau DONE
 *   +0x0014  CTEXT_1    ciphertext word 1
 *   +0x0018  TAG_0      auth tag[127:96]
 *   +0x001C  TAG_1      auth tag[95:64]
 *   +0x0020  TAG_2      auth tag[63:32]
 *   +0x0024  TAG_3      auth tag[31:0]
 *   +0x0028  _pad1[2]
 *   +0x0030  KEY_0      key snapshot (debug only)
 *   +0x0034  KEY_1
 *   +0x0038  KEY_2
 *   +0x003C  KEY_3
 *   +0x0040  NONCE_0    nonce snapshot (debug only)
 *   +0x0044  NONCE_1
 *   +0x0048  NONCE_2
 *   +0x004C  NONCE_3
 *   +0x0050  DATALEN    số byte plaintext
 *   +0x0054  STATUS     ASCON STATUS snapshot
 *   +0x0058  RETCODE    0=OK, -1=error, -2=timeout, -3=reset_failed
 * ============================================================================ */

typedef struct {
    volatile uint32_t PTEXT_0;     /* +0x0000 */
    volatile uint32_t PTEXT_1;     /* +0x0004 — reserved khi BLOCK_SIZE=4 */
    volatile uint32_t _pad0[2];    /* +0x0008 */
    volatile uint32_t CTEXT_0;     /* +0x0010 - DMA output */
    volatile uint32_t CTEXT_1;     /* +0x0014 - DMA output */
    volatile uint32_t TAG_0;       /* +0x0018 - DMA output */
    volatile uint32_t TAG_1;       /* +0x001C - DMA output */
    volatile uint32_t TAG_2;       /* +0x0020 - DMA output */
    volatile uint32_t TAG_3;       /* +0x0024 - DMA output */
    volatile uint32_t _pad1[2];    /* +0x0028 */
    volatile uint32_t KEY_0;       /* +0x0030 - key snapshot */
    volatile uint32_t KEY_1;       /* +0x0034 */
    volatile uint32_t KEY_2;       /* +0x0038 */
    volatile uint32_t KEY_3;       /* +0x003C */
    volatile uint32_t NONCE_0;     /* +0x0040 - nonce snapshot */
    volatile uint32_t NONCE_1;     /* +0x0044 */
    volatile uint32_t NONCE_2;     /* +0x0048 */
    volatile uint32_t NONCE_3;     /* +0x004C */
    volatile uint32_t DATALEN;     /* +0x0050 */
    volatile uint32_t STATUS;      /* +0x0054 */
    volatile uint32_t RETCODE;     /* +0x0058 */
} DmemLayout_t;

_Static_assert(offsetof(DmemLayout_t, PTEXT_0) == 0x0000, "PTEXT_0");
_Static_assert(offsetof(DmemLayout_t, PTEXT_1) == 0x0004, "PTEXT_1");
_Static_assert(offsetof(DmemLayout_t, CTEXT_0) == 0x0010, "CTEXT_0");
_Static_assert(offsetof(DmemLayout_t, TAG_0)   == 0x0018, "TAG_0");
_Static_assert(offsetof(DmemLayout_t, KEY_0)   == 0x0030, "KEY_0");
_Static_assert(offsetof(DmemLayout_t, NONCE_0) == 0x0040, "NONCE_0");
_Static_assert(offsetof(DmemLayout_t, DATALEN) == 0x0050, "DATALEN");
_Static_assert(offsetof(DmemLayout_t, STATUS)  == 0x0054, "STATUS");
_Static_assert(offsetof(DmemLayout_t, RETCODE) == 0x0058, "RETCODE");

/* ── Base pointer ──────────────────────────────────────────────────────────
 * 0x100001C0: ngay sau g_stream (0x10000000..0x100001B3) + 12B gap.
 * Align 32-byte đảm bảo DMA burst alignment.
 * Không đụng đến RTL register map (S2=0x20000000).
 * ──────────────────────────────────────────────────────────────────────── */
#define DMEM_BASE            0x100001C0UL
#define DMEM  ((DmemLayout_t *)(DMEM_BASE))

/* ── DMA Address + Length Constants ────────────────────────────────────────
 *
 * DMEM_DMA_SRC_ADDR  = PTEXT_0 = DMEM_BASE + 0x0000
 * DMEM_DMA_OUTPUT_ADDR = CTEXT_0 = DMEM_BASE + 0x0010
 *
 * DMEM_DMA_INPUT_LEN = 4 = ASCON_BLOCK_SIZE
 *   CPU ghi 1 word (4B) vào PTEXT_0, DMA đọc 4B từ đây.
 *
 * DMEM_DMA_OUTPUT_LEN = 24 = ctext(8) + tag(16)
 *   DMA ghi 24B vào DST kể từ CTEXT_0.
 * ──────────────────────────────────────────────────────────────────────── */
#define DMEM_DMA_SRC_ADDR    (DMEM_BASE + 0x0000UL)  /* PTEXT_0: 0x100001C0 */
#define DMEM_DMA_OUTPUT_ADDR (DMEM_BASE + 0x0010UL)  /* CTEXT_0: 0x100001D0 */
#define DMEM_DMA_INPUT_LEN   8u                       /* = ASCON_BLOCK_SIZE  */
#define DMEM_DMA_OUTPUT_LEN  24u                      /* ctext(8) + tag(16)  */

/* Sanity: DMA output region không overlap RETCODE.
 * CTEXT_0 + 24 = 0x100001D0 + 0x18 = 0x100001E8 <= RETCODE @ 0x10000218. OK */
_Static_assert(
    (DMEM_BASE + 0x0010UL + 24u) <= (DMEM_BASE + 0x0058UL),
    "DMA output region overlap RETCODE!"
);

/* Sanity: DmemLayout_t nằm sau g_stream (0x100001B4) */
_Static_assert(
    DMEM_BASE >= 0x100001B4UL,
    "DMEM_BASE overlap g_stream! Tang DMEM_BASE."
);

/* Sanity: DmemLayout_t kết thúc trước guard zone (0x10000800) */
_Static_assert(
    (DMEM_BASE + 0x005CUL) <= 0x10000800UL,
    "DmemLayout_t vuot DMEM_DATA region!"
);

#endif /* DMEM_LAYOUT_H */