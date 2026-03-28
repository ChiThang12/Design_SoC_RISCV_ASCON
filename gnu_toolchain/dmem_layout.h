#ifndef DMEM_LAYOUT_H
#define DMEM_LAYOUT_H

#include <stdint.h>
#include <stddef.h>

/* ============================================================================
 * DMEM Layout — Data Memory (S1, base 0x1000_0000, 8KB)
 *
 * Offset map:
 *   0x0000  PTEXT_0    plaintext word 0  — CPU ghi, DMA đọc
 *   0x0004  PTEXT_1    plaintext word 1
 *   0x0008  _pad0[2]
 *   0x0010  CTEXT_0    ciphertext word 0 — DMA ghi sau DONE
 *   0x0014  CTEXT_1    ciphertext word 1
 *   0x0018  TAG_0      auth tag[127:96]
 *   0x001C  TAG_1      auth tag[95:64]
 *   0x0020  TAG_2      auth tag[63:32]
 *   0x0024  TAG_3      auth tag[31:0]
 *   0x0028  _pad1[2]
 *   0x0030  KEY_0      key snapshot (debug only)
 *   0x0034  KEY_1
 *   0x0038  KEY_2
 *   0x003C  KEY_3
 *   0x0040  NONCE_0    nonce snapshot (debug only)
 *   0x0044  NONCE_1
 *   0x0048  NONCE_2
 *   0x004C  NONCE_3
 *   0x0050  DATALEN    số byte plaintext
 *   0x0054  STATUS     ASCON STATUS snapshot
 *   0x0058  RETCODE    0=OK, -1=error, -2=timeout, -3=reset_failed (v11)
 * ============================================================================ */

typedef struct {
    volatile uint32_t PTEXT_0;     /* 0x0000 */
    volatile uint32_t PTEXT_1;     /* 0x0004 */
    volatile uint32_t _pad0[2];    /* 0x0008 */
    volatile uint32_t CTEXT_0;     /* 0x0010 - DMA output */
    volatile uint32_t CTEXT_1;     /* 0x0014 - DMA output */
    volatile uint32_t TAG_0;       /* 0x0018 - DMA output */
    volatile uint32_t TAG_1;       /* 0x001C - DMA output */
    volatile uint32_t TAG_2;       /* 0x0020 - DMA output */
    volatile uint32_t TAG_3;       /* 0x0024 - DMA output */
    volatile uint32_t _pad1[2];    /* 0x0028 */
    volatile uint32_t KEY_0;       /* 0x0030 - key snapshot */
    volatile uint32_t KEY_1;       /* 0x0034 */
    volatile uint32_t KEY_2;       /* 0x0038 */
    volatile uint32_t KEY_3;       /* 0x003C */
    volatile uint32_t NONCE_0;     /* 0x0040 - nonce snapshot */
    volatile uint32_t NONCE_1;     /* 0x0044 */
    volatile uint32_t NONCE_2;     /* 0x0048 */
    volatile uint32_t NONCE_3;     /* 0x004C */
    volatile uint32_t DATALEN;     /* 0x0050 */
    volatile uint32_t STATUS;      /* 0x0054 */
    volatile uint32_t RETCODE;     /* 0x0058 */
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

#define DMEM  ((DmemLayout_t *) 0x10000000UL)

/*
 * DMA Address + Length Constants
 * ============================================================================
 *
 * DMEM_DMA_SRC_ADDR  = địa chỉ PTEXT_0 (DMA đọc plaintext từ đây).
 *
 * DMEM_DMA_OUTPUT_ADDR = địa chỉ CTEXT_0 (DMA ghi ctext + tag vào đây).
 *
 * ── BUG-C FIX (v11): Tách DMA_LEN ──────────────────────────────────────
 *
 * DMEM_DMA_INPUT_LEN = 8
 *   Số byte DMA đọc từ SRC (plaintext). Dùng cho ASCON->DMA_LEN nếu
 *   RTL của bạn định nghĩa DMA_LEN = input transfer size.
 *
 * DMEM_DMA_OUTPUT_LEN = 24 = ctext(8) + tag(16)
 *   Số byte DMA ghi vào DST. Dùng cho ASCON->DMA_LEN nếu RTL định
 *   nghĩa DMA_LEN = output transfer size.
 *
 * Mặc định trong main.c v11: dùng DMEM_DMA_INPUT_LEN = 8.
 */
#define DMEM_DMA_SRC_ADDR    0x10000000UL   /* PTEXT_0 offset 0x0000 */
#define DMEM_DMA_OUTPUT_ADDR 0x10000010UL   /* CTEXT_0 offset 0x0010 */
#define DMEM_DMA_INPUT_LEN   8u             /* = PTEXT_LEN — BUG-C FIX */
#define DMEM_DMA_OUTPUT_LEN  24u            /* ctext(8) + tag(16) */

/*
 * Sanity: vùng DMA output (0x10000010 .. 0x10000027) không overlap RETCODE.
 * 0x10000010 + 24 = 0x10000028 <= 0x10000058. OK.
 */
_Static_assert(
    (0x10000010UL + 24u) <= (0x10000000UL + 0x0058UL),
    "DMA output region overlap RETCODE!"
);

#endif /* DMEM_LAYOUT_H */