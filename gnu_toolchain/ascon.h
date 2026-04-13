/* ============================================================================
 * ascon.h — ASCON Crypto Accelerator Library (CPU-Direct & DMA Mode)
 * Version : 2.5
 *
 * Sử dụng Inline Assembly để truy cập phần cứng an toàn tuyệt đối,
 * tránh mọi can thiệp của compiler optimization (không bị reorder, duplicate).
 *
 * Base Address giả định: 0x2000_0000
 * (Chỉnh sửa ASCON_BASE_HI nếu SoC của bạn map IP vào vùng nhớ khác)
 *
 * ── Fix v2.5: FIX-CTRL-DMA-START ────────────────────────────────────────────
 * CTRL register (offset 0x020) — hợp đồng chính xác theo RTL
 * (ascon_axi_slave.v line 372, line 383):
 *
 *   bit[0] CORE_START : 1-cycle pulse khởi động CORE
 *   bit[1] SOFT_RST   : soft reset toàn IP (CORE + DMA)
 *   bit[2] DMA_EN     : enable + khởi động DMA transfer
 *
 * Muốn DMA chạy → phải set CẢ bit[0] (START) lẫn bit[2] (DMA_EN):
 *   CTRL = 0x5 (bit0 | bit2)
 *
 * Trước đây ASCON_CTRL_DMA_START = (1u << 2) = 0x4 → thiếu bit0 →
 * DMA nhận lệnh nhưng CORE không được kích → CORE_DONE không bao giờ set.
 *
 * ── Fix v2.4 (giữ nguyên): FIX-MODE-OVERLAP ────────────────────────────────
 * ADDR_MODE (offset 0x000):
 *   bit[0] = variant  : 0 = ASCON-128,  1 = ASCON-128a
 *   bit[1] = direction: 0 = Encrypt,    1 = Decrypt
 *
 *   ASCON_MODE_128_ENC  (0x0)  ASCON-128  Encrypt
 *   ASCON_MODE_128A_ENC (0x1)  ASCON-128a Encrypt
 *   ASCON_MODE_128_DEC  (0x2)  ASCON-128  Decrypt
 *   ASCON_MODE_128A_DEC (0x3)  ASCON-128a Decrypt
 * ============================================================================ */

#ifndef _ASCON_H_
#define _ASCON_H_

#include <stdint.h>

/* Base address High-part (ví dụ: 0x20000000 -> 0x20000) */
#define ASCON_BASE_HI "0x20000"

/* ── Register Offsets (từ ascon_axi_slave.v) ───────────────────────────── */
#define ASCON_OFS_MODE      0x000
#define ASCON_OFS_STATUS    0x004
#define ASCON_OFS_IRQ_EN    0x00C
#define ASCON_OFS_KEY_0     0x010
#define ASCON_OFS_KEY_1     0x014
#define ASCON_OFS_KEY_2     0x018
#define ASCON_OFS_KEY_3     0x01C
#define ASCON_OFS_CTRL      0x020
#define ASCON_OFS_NONCE_0   0x024
#define ASCON_OFS_NONCE_1   0x028
#define ASCON_OFS_NONCE_2   0x02C
#define ASCON_OFS_NONCE_3   0x030
#define ASCON_OFS_PTEXT_0   0x034
#define ASCON_OFS_PTEXT_1   0x038
#define ASCON_OFS_DATA_LEN  0x03C
#define ASCON_OFS_CTEXT_0   0x040
#define ASCON_OFS_CTEXT_1   0x044
#define ASCON_OFS_TAG_0     0x048
#define ASCON_OFS_TAG_1     0x04C
#define ASCON_OFS_TAG_2     0x050
#define ASCON_OFS_TAG_3     0x054
#define ASCON_OFS_DMA_SRC   0x100
#define ASCON_OFS_DMA_DST   0x104
#define ASCON_OFS_DMA_LEN   0x108

/* ── Mode Register Bits (Thanh ghi 0x000) ──────────────────────────────── */
/*
 *  bit[0] VARIANT  : 0 = ASCON-128, 1 = ASCON-128a
 *  bit[1] DIRECTION: 0 = Encrypt,   1 = Decrypt
 *
 *  FIX-MODE-OVERLAP v2.4: tách variant và direction thành 2 bit riêng.
 */
#define ASCON_MODE_VARIANT_128      (0u << 0)   /* ASCON-128  */
#define ASCON_MODE_VARIANT_128A     (1u << 0)   /* ASCON-128a */
#define ASCON_MODE_DIR_ENC          (0u << 1)   /* Encrypt    */
#define ASCON_MODE_DIR_DEC          (1u << 1)   /* Decrypt    */

/* 4 tổ hợp hợp lệ (dùng trực tiếp với ascon_set_mode) */
#define ASCON_MODE_128_ENC   (ASCON_MODE_VARIANT_128  | ASCON_MODE_DIR_ENC)  /* 0x0 */
#define ASCON_MODE_128A_ENC  (ASCON_MODE_VARIANT_128A | ASCON_MODE_DIR_ENC)  /* 0x1 */
#define ASCON_MODE_128_DEC   (ASCON_MODE_VARIANT_128  | ASCON_MODE_DIR_DEC)  /* 0x2 */
#define ASCON_MODE_128A_DEC  (ASCON_MODE_VARIANT_128A | ASCON_MODE_DIR_DEC)  /* 0x3 */

/* ── Status Bits (Thanh ghi 0x004) ─────────────────────────────────────── */
#define ASCON_ST_CORE_BUSY  (1u << 0)
#define ASCON_ST_CORE_DONE  (1u << 1)
#define ASCON_ST_DMA_BUSY   (1u << 2)
#define ASCON_ST_DMA_DONE   (1u << 3)
#define ASCON_ST_CORE_ERR   (1u << 4)
#define ASCON_ST_DMA_ERR    (1u << 5)

/* ── CTRL Bits (Thanh ghi 0x020) ────────────────────────────────────────── */
/*
 * Hợp đồng CTRL theo RTL (ascon_axi_slave.v line 372, line 383):
 *
 *   bit[0]  CORE_START : 1-cycle pulse khởi động CORE processing
 *   bit[1]  SOFT_RST   : soft reset toàn IP (CORE + DMA)
 *   bit[2]  DMA_EN     : enable + khởi động DMA transfer
 *
 * !! QUAN TRỌNG !!
 * Để DMA hoạt động đúng, phải ghi CTRL = DMA_EN | CORE_START = 0x5.
 * Chỉ ghi DMA_EN (0x4) mà thiếu CORE_START (bit0) → DMA kéo dữ liệu
 * nhưng CORE không được kích → CORE_DONE không bao giờ được set.
 */
#define ASCON_CTRL_CORE_START   (1u << 0)   /* Bit 0: kích CORE (1 cycle) */
#define ASCON_CTRL_SOFT_RST     (1u << 1)   /* Bit 1: soft reset toàn IP  */
#define ASCON_CTRL_DMA_EN       (1u << 2)   /* Bit 2: enable DMA transfer */

/*
 * ASCON_CTRL_DMA_START: giá trị đúng để khởi động DMA + CORE đồng thời.
 *   = CORE_START | DMA_EN = 0x1 | 0x4 = 0x5
 *
 * FIX v2.5: Trước đây định nghĩa sai là (1u << 2) = 0x4, thiếu bit0
 * → CORE không chạy → CORE_DONE timeout. Nay sửa thành 0x5.
 */
#define ASCON_CTRL_DMA_START    (ASCON_CTRL_CORE_START | ASCON_CTRL_DMA_EN)  /* 0x5 */

/* ── Inline Assembly Macros cho Đọc/Ghi ─────────────────────────────────── */
/* Ràng buộc "i" (immediate) giúp lệnh sw/lw mã hóa trực tiếp offset vào
 * lệnh máy, tránh compiler sinh thêm lệnh ADD và bị reorder.              */

#define ASCON_WRITE(offset, val) do { \
    __asm__ volatile ( \
        "lui  t0, " ASCON_BASE_HI "\n" \
        "sw   %0, %1(t0)\n" \
        "fence w, w\n" \
        :: "r" ((uint32_t)(val)), "i" (offset) \
        : "t0", "memory" \
    ); \
} while(0)

#define ASCON_READ(offset, val) do { \
    __asm__ volatile ( \
        "lui  t0, " ASCON_BASE_HI "\n" \
        "lw   %0, %1(t0)\n" \
        : "=r" (val) \
        : "i" (offset) \
        : "t0", "memory" \
    ); \
} while(0)


/* =========================================================================
 * CÁC HÀM TIỆN ÍCH (HELPER FUNCTIONS)
 * ========================================================================= */

/* 1. Reset mềm toàn bộ IP (CORE + DMA) */
static inline void ascon_soft_reset(void) {
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_SOFT_RST);
}

/* 2. Cấu hình Mode
 *    Dùng các macro: ASCON_MODE_128_ENC / ASCON_MODE_128A_ENC /
 *                   ASCON_MODE_128_DEC / ASCON_MODE_128A_DEC
 *
 *    Ví dụ:
 *      ascon_set_mode(ASCON_MODE_128_ENC);    // ASCON-128  Encrypt
 *      ascon_set_mode(ASCON_MODE_128A_DEC);   // ASCON-128a Decrypt
 */
static inline void ascon_set_mode(uint32_t mode_val) {
    ASCON_WRITE(ASCON_OFS_MODE, mode_val);
}

/* 3. Nạp Key (128-bit, 4 × 32-bit word, big-endian: k0 = word cao nhất) */
static inline void ascon_set_key(uint32_t k0, uint32_t k1, uint32_t k2, uint32_t k3) {
    ASCON_WRITE(ASCON_OFS_KEY_0, k0);
    ASCON_WRITE(ASCON_OFS_KEY_1, k1);
    ASCON_WRITE(ASCON_OFS_KEY_2, k2);
    ASCON_WRITE(ASCON_OFS_KEY_3, k3);
}

/* 4. Nạp Nonce (128-bit) */
static inline void ascon_set_nonce(uint32_t n0, uint32_t n1, uint32_t n2, uint32_t n3) {
    ASCON_WRITE(ASCON_OFS_NONCE_0, n0);
    ASCON_WRITE(ASCON_OFS_NONCE_1, n1);
    ASCON_WRITE(ASCON_OFS_NONCE_2, n2);
    ASCON_WRITE(ASCON_OFS_NONCE_3, n3);
}

/* -------------------------------------------------------------------------
 * CPU-DIRECT MODE (nạp tay qua thanh ghi, tối đa 64-bit plaintext)
 * ------------------------------------------------------------------------- */

/* Nạp plaintext (tối đa 64-bit = 2 word) và độ dài thực tính bằng byte */
static inline void ascon_set_ptext(uint32_t p0, uint32_t p1, uint32_t byte_len) {
    ASCON_WRITE(ASCON_OFS_PTEXT_0,  p0);
    ASCON_WRITE(ASCON_OFS_PTEXT_1,  p1);
    ASCON_WRITE(ASCON_OFS_DATA_LEN, byte_len);
}

/* Khởi động CORE (1-cycle pulse, hardware tự clear busy→done) */
static inline void ascon_core_start(void) {
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_CORE_START);
}

/* Busy-wait đến khi CORE_DONE = 1 */
static inline void ascon_wait_core_done(void) {
    uint32_t status;
    do {
        ASCON_READ(ASCON_OFS_STATUS, status);
    } while (!(status & ASCON_ST_CORE_DONE));
}

/* -------------------------------------------------------------------------
 * DMA MODE (DMA tự kéo dữ liệu từ bộ nhớ, CORE chạy song song)
 * ------------------------------------------------------------------------- */

/* Cấu hình địa chỉ nguồn, đích và số byte trước khi start */
static inline void ascon_dma_config(uint32_t src_addr, uint32_t dst_addr, uint32_t byte_len) {
    ASCON_WRITE(ASCON_OFS_DMA_SRC, src_addr);
    ASCON_WRITE(ASCON_OFS_DMA_DST, dst_addr);
    ASCON_WRITE(ASCON_OFS_DMA_LEN, byte_len);
}

/* Bật DMA_EN + CORE_START đồng thời trong cùng 1 write (= 0x5)
 *
 * !! Không dùng ASCON_CTRL_DMA_EN (0x4) đơn độc !!
 * Phải có CORE_START (bit0) để CORE được kích sau khi DMA nạp xong. */
static inline void ascon_dma_start(void) {
    ASCON_WRITE(ASCON_OFS_CTRL, ASCON_CTRL_DMA_START);  /* 0x5 = bit0|bit2 */
}

/* Busy-wait đến khi DMA_DONE hoặc DMA_ERR.
 * Trả về giá trị status để caller kiểm tra lỗi:
 *   if (ascon_wait_dma_done() & ASCON_ST_DMA_ERR) { ... }  */
static inline uint32_t ascon_wait_dma_done(void) {
    uint32_t status;
    do {
        ASCON_READ(ASCON_OFS_STATUS, status);
    } while (!(status & (ASCON_ST_DMA_DONE | ASCON_ST_DMA_ERR)));
    return status;
}

/* -------------------------------------------------------------------------
 * ĐỌC KẾT QUẢ CTEXT & TAG
 * ------------------------------------------------------------------------- */

/* Đọc ciphertext (64-bit, 2 word) — chỉ có nghĩa khi CORE_DONE=1 */
static inline void ascon_get_ctext(uint32_t *c0, uint32_t *c1) {
    ASCON_READ(ASCON_OFS_CTEXT_0, *c0);
    ASCON_READ(ASCON_OFS_CTEXT_1, *c1);
}

/* Đọc authentication tag (128-bit, 4 word) */
static inline void ascon_get_tag(uint32_t *t0, uint32_t *t1, uint32_t *t2, uint32_t *t3) {
    ASCON_READ(ASCON_OFS_TAG_0, *t0);
    ASCON_READ(ASCON_OFS_TAG_1, *t1);
    ASCON_READ(ASCON_OFS_TAG_2, *t2);
    ASCON_READ(ASCON_OFS_TAG_3, *t3);
}

/* -------------------------------------------------------------------------
 * USAGE EXAMPLE — DMA Mode, ASCON-128 Encrypt
 * -------------------------------------------------------------------------
 *   // 1. Ghi plaintext vào DMEM trước
 *   DMEM->PTEXT_0 = 0xAABBCCDD;
 *
 *   // 2. Reset + cấu hình
 *   ascon_soft_reset();
 *   ascon_set_mode(ASCON_MODE_128_ENC);
 *   ascon_set_key  (0xDEADBEEF, 0xCAFEBABE, 0x01234567, 0x89ABCDEF);
 *   ascon_set_nonce(0x11111111, 0x22222222, 0x33333333, 0x44444444);
 *
 *   // 3. Cấu hình DMA + fence + start (CTRL = 0x5)
 *   ascon_dma_config(DMEM_DMA_SRC_ADDR, DMEM_DMA_OUTPUT_ADDR, DMEM_DMA_INPUT_LEN);
 *   __asm__ volatile ("fence rw, rw" ::: "memory");
 *   ascon_dma_start();   // ghi CTRL = 0x5 (DMA_EN | CORE_START)
 *
 *   // 4. Poll
 *   uint32_t st = ascon_wait_dma_done();
 *   if (!(st & ASCON_ST_DMA_ERR)) ascon_wait_core_done();
 * ------------------------------------------------------------------------- */

#endif /* _ASCON_H_ */