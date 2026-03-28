#ifndef ASCON_REGS_H
#define ASCON_REGS_H

#include <stdint.h>

/* ============================================================================
 * ascon_regs.h — ASCON-128 Accelerator Register Map
 *
 * Base: S2  0x2000_0000  (4KB)
 *
 * Register layout (deduced từ firmware + debug log):
 *
 *  Offset   Name        Access   Description
 *  ------   ----        ------   -----------
 *  0x000    CTRL        W        Control: SOFT_RST=0x02, DMA_START=0x05
 *  0x004    MODE        W        Mode: ENCRYPT=0x01
 *  0x008    IRQ_EN      W        Interrupt enable (0=off)
 *  0x00C    _pad0       —        reserved
 *  0x010    KEY_0       W        Key[127:96]
 *  0x014    KEY_1       W        Key[95:64]
 *  0x018    KEY_2       W        Key[63:32]
 *  0x01C    KEY_3       W        Key[31:0]
 *  0x020    NONCE_0     W        Nonce[127:96]
 *  0x024    NONCE_1     W        Nonce[95:64]
 *  0x028    NONCE_2     W        Nonce[63:32]
 *  0x02C    NONCE_3     W        Nonce[31:0]
 *  0x030    DATA_LEN    W        Plaintext length (bytes), mask 0xFF
 *  0x034    _pad1       —        reserved
 *  0x038    _pad2       —        reserved
 *  0x03C    STATUS      R        bit0=CORE_BUSY, bit1=DMA_DONE, bit2=ERROR
 *  0x040    TAG_0       R        Auth tag[127:96]  (valid after DMA_DONE)
 *  0x044    TAG_1       R        Auth tag[95:64]
 *  0x048    TAG_2       R        Auth tag[63:32]
 *  0x04C    TAG_3       R        Auth tag[31:0]
 *  0x100    DMA_SRC     W        DMA source address (DMEM plaintext)
 *  0x104    DMA_DST     W        DMA destination address (DMEM ciphertext)
 *  0x108    DMA_LEN     W        DMA transfer length (bytes, input semantics)
 *
 * Root cause fix (v14):
 *   Các phiên bản trước định nghĩa ASCON_BASE = 0x10002000 (= __stack_top).
 *   Hậu quả:
 *     - Tất cả ASCON write đi vào vùng trên stack → DECERR hoặc corrupt stack
 *     - ascon_read_status() đọc 0x10002000+0x3C = 0x1000203C → DECERR loop
 *     - S2 ASCON AW/AR = 0/0 trong TB summary
 *   Fix: ASCON_BASE = 0x20000000 (đúng theo SoC address map, S2)
 * ============================================================================ */

/* --------------------------------------------------------------------------
 * ASCON register struct
 * -------------------------------------------------------------------------- */
typedef struct {
    /* 0x000 - 0x00C: Control */
    volatile uint32_t CTRL;         /* 0x000 */
    volatile uint32_t MODE;         /* 0x004 */
    volatile uint32_t IRQ_EN;       /* 0x008 */
    volatile uint32_t _pad0;        /* 0x00C */

    /* 0x010 - 0x01C: Key (128-bit) */
    volatile uint32_t KEY_0;        /* 0x010 */
    volatile uint32_t KEY_1;        /* 0x014 */
    volatile uint32_t KEY_2;        /* 0x018 */
    volatile uint32_t KEY_3;        /* 0x01C */

    /* 0x020 - 0x02C: Nonce (128-bit) */
    volatile uint32_t NONCE_0;      /* 0x020 */
    volatile uint32_t NONCE_1;      /* 0x024 */
    volatile uint32_t NONCE_2;      /* 0x028 */
    volatile uint32_t NONCE_3;      /* 0x02C */

    /* 0x030 - 0x03C: Config + Status */
    volatile uint32_t DATA_LEN;     /* 0x030 */
    volatile uint32_t _pad1;        /* 0x034 */
    volatile uint32_t _pad2;        /* 0x038 */
    volatile uint32_t STATUS;       /* 0x03C  R — poll target */

    /* 0x040 - 0x04C: Auth tag output */
    volatile uint32_t TAG_0;        /* 0x040 */
    volatile uint32_t TAG_1;        /* 0x044 */
    volatile uint32_t TAG_2;        /* 0x048 */
    volatile uint32_t TAG_3;        /* 0x04C */

    /* 0x050 - 0x0FC: padding to DMA block */
    volatile uint32_t _pad3[44];    /* 0x050 - 0x0FC */

    /* 0x100 - 0x108: DMA */
    volatile uint32_t DMA_SRC;      /* 0x100  offset=256 decimal, confirmed by asm */
    volatile uint32_t DMA_DST;      /* 0x104 */
    volatile uint32_t DMA_LEN;      /* 0x108 */
} AsconRegs_t;

/* Static assert offsets */
#include <stddef.h>
_Static_assert(offsetof(AsconRegs_t, CTRL)     == 0x000, "CTRL");
_Static_assert(offsetof(AsconRegs_t, MODE)     == 0x004, "MODE");
_Static_assert(offsetof(AsconRegs_t, IRQ_EN)   == 0x008, "IRQ_EN");
_Static_assert(offsetof(AsconRegs_t, KEY_0)    == 0x010, "KEY_0");
_Static_assert(offsetof(AsconRegs_t, KEY_3)    == 0x01C, "KEY_3");
_Static_assert(offsetof(AsconRegs_t, NONCE_0)  == 0x020, "NONCE_0");
_Static_assert(offsetof(AsconRegs_t, NONCE_3)  == 0x02C, "NONCE_3");
_Static_assert(offsetof(AsconRegs_t, DATA_LEN) == 0x030, "DATA_LEN");
_Static_assert(offsetof(AsconRegs_t, STATUS)   == 0x03C, "STATUS");
_Static_assert(offsetof(AsconRegs_t, TAG_0)    == 0x040, "TAG_0");
_Static_assert(offsetof(AsconRegs_t, TAG_3)    == 0x04C, "TAG_3");
_Static_assert(offsetof(AsconRegs_t, DMA_SRC)  == 0x100, "DMA_SRC");
_Static_assert(offsetof(AsconRegs_t, DMA_DST)  == 0x104, "DMA_DST");
_Static_assert(offsetof(AsconRegs_t, DMA_LEN)  == 0x108, "DMA_LEN");

/* --------------------------------------------------------------------------
 * Base address pointer  ← ĐÂY LÀ FIX CHÍNH (0x10002000 → 0x20000000)
 * -------------------------------------------------------------------------- */
#define ASCON_BASE  0x20000000UL
#define ASCON       ((AsconRegs_t *)(ASCON_BASE))

/* --------------------------------------------------------------------------
 * CTRL register values
 * -------------------------------------------------------------------------- */
#define CTRL_SOFT_RST   0x02u   /* BUG-E: KHÔNG phải 0x08 */
#define CTRL_DMA_START  0x05u   /* DMA_EN | START */

/* --------------------------------------------------------------------------
 * MODE register values
 * -------------------------------------------------------------------------- */
#define MODE_ENCRYPT    0x01u

/* --------------------------------------------------------------------------
 * DATA_LEN mask
 * -------------------------------------------------------------------------- */
#define DATA_LEN_MASK   0xFFu

/* --------------------------------------------------------------------------
 * STATUS register bit fields
 * -------------------------------------------------------------------------- */
#define STATUS_CORE_BUSY    (1u << 0)   /* bit0: core đang chạy / reset chưa xong */
#define STATUS_DMA_DONE     (1u << 1)   /* bit1: DMA hoàn thành, TAG valid */
#define STATUS_ERROR        (1u << 2)   /* bit2: lỗi bất kỳ */
#define STATUS_ANY_ERROR    (STATUS_ERROR)

/* --------------------------------------------------------------------------
 * ascon_read_status — đọc STATUS register tại offset 0x03C
 *
 * Với ASCON_BASE = 0x20000000:
 *   STATUS address = 0x20000000 + 0x03C = 0x2000003C  → S2 ASCON AR ✓
 * -------------------------------------------------------------------------- */
__attribute__((optimize("O0")))
static inline uint32_t ascon_read_status(void)
{
    uint32_t s = ASCON->STATUS;
    __asm__ volatile ("" ::: "memory");
    return s;
}

#endif /* ASCON_REGS_H */