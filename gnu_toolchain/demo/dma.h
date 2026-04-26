/* ============================================================================
 * dma.h — SoC DMA Controller Driver Library
 * Version : 1.0
 *
 * Phần cứng: dma_ctrl.v (dma_reg_slave + 4×dma_channel + dma_arbiter +
 *            dma_axi_master), slave S11 trong AXI crossbar.
 *
 * Base address: 0x6001_0000  (DMA_BASE_HI = "0x60010")
 *
 * ── Register Map (từ dma_reg_slave.v) ───────────────────────────────────
 *
 *  Channel registers (offset per channel = 0x010):
 *    CHn_SRC  = base + 0x000 + n*0x10   [31:0] RW  địa chỉ nguồn
 *    CHn_DST  = base + 0x004 + n*0x10   [31:0] RW  địa chỉ đích
 *    CHn_LEN  = base + 0x008 + n*0x10   [31:0] RW  số byte cần copy
 *    CHn_CTRL = base + 0x00C + n*0x10   [3:0]  RW  [0]=EN [1]=START(SC) [3:2]=MODE
 *
 *  Global registers:
 *    STATUS     = base + 0x080   [11:0] RO   [3:0]=done [7:4]=error [11:8]=busy
 *    IRQ_EN     = base + 0x084   [3:0]  RW   bật IRQ per channel
 *    IRQ_STATUS = base + 0x088   [3:0]  RW1C ghi 1 để clear
 *
 * ── CHn_CTRL bit layout ──────────────────────────────────────────────────
 *   [0]   EN    : enable channel (phải =1 trước khi START)
 *   [1]   START : self-clearing pulse, hardware clear sau 1 cycle
 *   [3:2] MODE  : 2'b00 = mem-to-mem (chỉ mode được hỗ trợ hiện tại)
 *                 2'b01/10 = periph modes (chưa implement, báo error)
 *
 * ── STATUS bit layout ────────────────────────────────────────────────────
 *   [3:0]   DONE  : sticky, clear bằng ghi 1 vào STATUS[3:0]
 *   [7:4]   ERROR : sticky, clear bằng ghi 1 vào STATUS[7:4]
 *   [11:8]  BUSY  : real-time, phản ánh trạng thái hiện tại channel
 *
 * ── IRQ ──────────────────────────────────────────────────────────────────
 *   irq_out = |(IRQ_EN & IRQ_STATUS) → PLIC[7]
 *   IRQ_STATUS set khi ch_done hoặc ch_error (bất kỳ channel nào)
 *   Clear bằng RW1C vào IRQ_STATUS
 *
 * ── Đặc điểm hardware ────────────────────────────────────────────────────
 *   - 4 channel độc lập (CH0..CH3), mỗi channel có line buffer 16×32-bit
 *   - Chỉ hỗ trợ mem-to-mem (MODE=0), DMA burst 16-beat × 4-byte = 64 byte/burst
 *   - Arbiter round-robin cho read bus và write bus (2 channel có thể hoạt động
 *     song song nếu 1 đọc và 1 ghi cùng lúc)
 *   - Transfer length phải là bội số của 4 byte (word-aligned)
 *   - Địa chỉ src/dst phải word-aligned (địa chỉ thấp nhất 2 bit = 00)
 * ============================================================================ */

#ifndef _DMA_H_
#define _DMA_H_

#include <stdint.h>

/* ── Base Address ────────────────────────────────────────────────────────── */
/* Base: 0x6001_0000 → LUI load upper = 0x60010 (lui rx, 0x60010 → rx = 0x60010_000)
 * Các register offset đều < 0x1000 nên dùng được trực tiếp làm immediate.  */
#define DMA_BASE_HI  "0x60010"

/* ── Channel stride ──────────────────────────────────────────────────────── */
#define DMA_CH_STRIDE   0x010   /* byte offset giữa 2 channel liên tiếp */
#define DMA_NUM_CH      4

/* ── Register Offsets (tương đối với base 0x6001_0000) ──────────────────── */
/* Channel n: offset = DMA_CH_BASE(n) + DMA_OFS_CH_xxx */
#define DMA_CH_BASE(n)      ((n) * DMA_CH_STRIDE)   /* 0x000, 0x010, 0x020, 0x030 */

#define DMA_OFS_CH_SRC      0x000
#define DMA_OFS_CH_DST      0x004
#define DMA_OFS_CH_LEN      0x008
#define DMA_OFS_CH_CTRL     0x00C

/* Địa chỉ tuyệt đối (offset từ base) cho từng channel */
#define DMA_OFS_CH0_SRC     0x000
#define DMA_OFS_CH0_DST     0x004
#define DMA_OFS_CH0_LEN     0x008
#define DMA_OFS_CH0_CTRL    0x00C

#define DMA_OFS_CH1_SRC     0x010
#define DMA_OFS_CH1_DST     0x014
#define DMA_OFS_CH1_LEN     0x018
#define DMA_OFS_CH1_CTRL    0x01C

#define DMA_OFS_CH2_SRC     0x020
#define DMA_OFS_CH2_DST     0x024
#define DMA_OFS_CH2_LEN     0x028
#define DMA_OFS_CH2_CTRL    0x02C

#define DMA_OFS_CH3_SRC     0x030
#define DMA_OFS_CH3_DST     0x034
#define DMA_OFS_CH3_LEN     0x038
#define DMA_OFS_CH3_CTRL    0x03C

/* Global registers */
#define DMA_OFS_STATUS      0x080
#define DMA_OFS_IRQ_EN      0x084
#define DMA_OFS_IRQ_STATUS  0x088

/* ── CHn_CTRL Bits ───────────────────────────────────────────────────────── */
#define DMA_CTRL_EN         (1u << 0)   /* Enable channel */
#define DMA_CTRL_START      (1u << 1)   /* Start (self-clearing 1-cycle pulse) */
#define DMA_CTRL_MODE_MEM   (0u << 2)   /* MODE=00: mem-to-mem (duy nhất hỗ trợ) */
/* (1u<<2) = periph-to-mem: chưa implement, sẽ báo error */
/* (2u<<2) = mem-to-periph: chưa implement, sẽ báo error */

/* Combo thường dùng: enable + start + mem-to-mem */
#define DMA_CTRL_START_MEM  (DMA_CTRL_EN | DMA_CTRL_START | DMA_CTRL_MODE_MEM)

/* ── STATUS Bits (offset 0x080) ──────────────────────────────────────────── */
/* [3:0]  DONE : sticky, 1 bit per channel */
#define DMA_ST_DONE(ch)     (1u << (ch))
#define DMA_ST_DONE_ANY     (0xFu << 0)

/* [7:4]  ERROR: sticky, 1 bit per channel */
#define DMA_ST_ERROR(ch)    (1u << ((ch) + 4))
#define DMA_ST_ERROR_ANY    (0xFu << 4)

/* [11:8] BUSY : real-time */
#define DMA_ST_BUSY(ch)     (1u << ((ch) + 8))
#define DMA_ST_BUSY_ANY     (0xFu << 8)

/* ── IRQ_STATUS / IRQ_EN Bits (offset 0x084, 0x088) ─────────────────────── */
/* 1 bit per channel [3:0], cùng layout */
#define DMA_IRQ_CH(ch)      (1u << (ch))
#define DMA_IRQ_ALL         (0xFu)

/* ── Inline Assembly Macros ──────────────────────────────────────────────── */
/*
 * Sử dụng "i" constraint → offset được mã hóa trực tiếp vào lệnh lw/sw,
 * không phát sinh lệnh ADD thêm, không bị compiler reorder.
 * fence w,w sau mỗi write đảm bảo thứ tự ghi đến MMIO hardware.
 *
 * QUAN TRỌNG: Constraint "i" yêu cầu offset phải là hằng số tại compile-time.
 * Không truyền biến runtime vào tham số offset của các macro này.
 * Với offset động, dùng DMA_WRITE_DYN / DMA_READ_DYN bên dưới.
 */
#define DMA_WRITE(offset, val)  do {                            \
    __asm__ volatile (                                          \
        "lui  t0, " DMA_BASE_HI "\n"                           \
        "sw   %0, %1(t0)\n"                                    \
        "fence w, w\n"                                         \
        :: "r" ((uint32_t)(val)), "i" (offset)                 \
        : "t0", "memory"                                       \
    );                                                          \
} while(0)

#define DMA_READ(offset, val)   do {                            \
    __asm__ volatile (                                          \
        "lui  t0, " DMA_BASE_HI "\n"                           \
        "lw   %0, %1(t0)\n"                                    \
        : "=r" (val)                                            \
        : "i" (offset)                                          \
        : "t0", "memory"                                        \
    );                                                          \
} while(0)

/*
 * DMA_WRITE_DYN / DMA_READ_DYN: dùng khi offset là biến runtime
 * (ví dụ: DMA_CH_BASE(ch) với ch là biến).
 * Dùng "add" để tính địa chỉ, sau đó lw/sw offset 0.
 */
#define DMA_WRITE_DYN(base_reg, dyn_offset, val)  do {         \
    volatile uint32_t *_p = (volatile uint32_t *)              \
        (0x60010000u + (uint32_t)(dyn_offset));                 \
    *_p = (uint32_t)(val);                                      \
    __asm__ volatile ("fence w, w" ::: "memory");               \
} while(0)

#define DMA_READ_DYN(dyn_offset, val)  do {                     \
    volatile uint32_t *_p = (volatile uint32_t *)              \
        (0x60010000u + (uint32_t)(dyn_offset));                 \
    (val) = *_p;                                                \
} while(0)

/* ============================================================================
 * HELPER FUNCTIONS
 * ============================================================================ */

/* ── Đọc STATUS toàn cục ─────────────────────────────────────────────────── */
static inline uint32_t dma_read_status(void) {
    uint32_t v;
    DMA_READ(DMA_OFS_STATUS, v);
    return v;
}

/* ── Clear sticky DONE bit của channel ch (RW1C vào STATUS[3:0]) ─────────── */
static inline void dma_clear_done(uint8_t ch) {
    /* Ghi 1 vào đúng bit DONE[ch], giữ nguyên bit còn lại = 0
     * (ghi 0 vào ERROR bits → không clear error).              */
    DMA_WRITE_DYN(0, DMA_OFS_STATUS, DMA_ST_DONE(ch));
}

/* ── Clear sticky ERROR bit của channel ch ──────────────────────────────── */
static inline void dma_clear_error(uint8_t ch) {
    DMA_WRITE_DYN(0, DMA_OFS_STATUS, DMA_ST_ERROR(ch));
}

/* ── Clear tất cả DONE + ERROR của tất cả channel ───────────────────────── */
static inline void dma_clear_all_status(void) {
    DMA_WRITE(DMA_OFS_STATUS, (DMA_ST_DONE_ANY | DMA_ST_ERROR_ANY));
}

/* ── Đọc IRQ_STATUS ──────────────────────────────────────────────────────── */
static inline uint32_t dma_read_irq_status(void) {
    uint32_t v;
    DMA_READ(DMA_OFS_IRQ_STATUS, v);
    return v;
}

/* ── Clear IRQ_STATUS của channel ch (RW1C) ─────────────────────────────── */
static inline void dma_clear_irq(uint8_t ch) {
    DMA_WRITE_DYN(0, DMA_OFS_IRQ_STATUS, DMA_IRQ_CH(ch));
}

/* ── Clear tất cả IRQ ────────────────────────────────────────────────────── */
static inline void dma_clear_all_irq(void) {
    DMA_WRITE(DMA_OFS_IRQ_STATUS, DMA_IRQ_ALL);
}

/* ── Cấu hình IRQ_EN ─────────────────────────────────────────────────────── */
static inline void dma_irq_enable(uint8_t ch_mask) {
    DMA_WRITE(DMA_OFS_IRQ_EN, (ch_mask & DMA_IRQ_ALL));
}

static inline void dma_irq_disable_all(void) {
    DMA_WRITE(DMA_OFS_IRQ_EN, 0u);
}

/* ============================================================================
 * CHANNEL API (compile-time channel index — dùng constant literal cho ch)
 *
 * Hai dạng API:
 *  1. dma_ch_setup_N() — compile-time channel number (dùng "i" constraint,
 *     offset được mã hóa trực tiếp vào lệnh → hiệu quả nhất).
 *     Dùng khi channel number biết tại compile-time (đa số trường hợp).
 *
 *  2. dma_ch_setup() — runtime channel number (dùng DMA_WRITE_DYN,
 *     offset tính bằng pointer arithmetic).
 *     Dùng khi channel number là biến (vd: trong vòng lặp, hàm callback).
 * ============================================================================ */

/* ── API compile-time: CH0 ───────────────────────────────────────────────── */
static inline void dma_ch0_setup(uint32_t src, uint32_t dst, uint32_t len) {
    DMA_WRITE(DMA_OFS_CH0_SRC,  src);
    DMA_WRITE(DMA_OFS_CH0_DST,  dst);
    DMA_WRITE(DMA_OFS_CH0_LEN,  len);
}
static inline void dma_ch0_start(void) {
    DMA_WRITE(DMA_OFS_CH0_CTRL, DMA_CTRL_START_MEM);
}

/* ── API compile-time: CH1 ───────────────────────────────────────────────── */
static inline void dma_ch1_setup(uint32_t src, uint32_t dst, uint32_t len) {
    DMA_WRITE(DMA_OFS_CH1_SRC,  src);
    DMA_WRITE(DMA_OFS_CH1_DST,  dst);
    DMA_WRITE(DMA_OFS_CH1_LEN,  len);
}
static inline void dma_ch1_start(void) {
    DMA_WRITE(DMA_OFS_CH1_CTRL, DMA_CTRL_START_MEM);
}

/* ── API compile-time: CH2 ───────────────────────────────────────────────── */
static inline void dma_ch2_setup(uint32_t src, uint32_t dst, uint32_t len) {
    DMA_WRITE(DMA_OFS_CH2_SRC,  src);
    DMA_WRITE(DMA_OFS_CH2_DST,  dst);
    DMA_WRITE(DMA_OFS_CH2_LEN,  len);
}
static inline void dma_ch2_start(void) {
    DMA_WRITE(DMA_OFS_CH2_CTRL, DMA_CTRL_START_MEM);
}

/* ── API compile-time: CH3 ───────────────────────────────────────────────── */
static inline void dma_ch3_setup(uint32_t src, uint32_t dst, uint32_t len) {
    DMA_WRITE(DMA_OFS_CH3_SRC,  src);
    DMA_WRITE(DMA_OFS_CH3_DST,  dst);
    DMA_WRITE(DMA_OFS_CH3_LEN,  len);
}
static inline void dma_ch3_start(void) {
    DMA_WRITE(DMA_OFS_CH3_CTRL, DMA_CTRL_START_MEM);
}

/* ── API runtime: channel index là biến ─────────────────────────────────── */
/*
 * Dùng khi cần:
 *   for (int ch = 0; ch < 4; ch++) dma_ch_setup(ch, src[ch], dst[ch], len);
 *
 * Lưu ý: ch phải trong khoảng [0..3], không kiểm tra bounds ở đây.
 */
static inline void dma_ch_setup(uint8_t ch, uint32_t src, uint32_t dst, uint32_t len) {
    uint32_t base = DMA_CH_BASE(ch);
    DMA_WRITE_DYN(0, base + DMA_OFS_CH_SRC, src);
    DMA_WRITE_DYN(0, base + DMA_OFS_CH_DST, dst);
    DMA_WRITE_DYN(0, base + DMA_OFS_CH_LEN, len);
}

static inline void dma_ch_start(uint8_t ch) {
    DMA_WRITE_DYN(0, DMA_CH_BASE(ch) + DMA_OFS_CH_CTRL, DMA_CTRL_START_MEM);
}

/* ── Disable channel (clear EN bit) ─────────────────────────────────────── */
static inline void dma_ch_disable(uint8_t ch) {
    DMA_WRITE_DYN(0, DMA_CH_BASE(ch) + DMA_OFS_CH_CTRL, 0u);
}

/* ── Poll: chờ channel ch hoàn tất (DONE hoặc ERROR) ────────────────────── */
/*
 * Trả về phần STATUS liên quan đến channel ch:
 *   Bit 0: DONE  (status bit của ch)
 *   Bit 4: ERROR (status bit của ch, đã shift)
 *
 * Dùng DMA_ST_DONE(0) / DMA_ST_ERROR(0) trên giá trị trả về để kiểm tra:
 *   uint32_t result = dma_wait(ch);
 *   if (result & DMA_ST_ERROR(ch)) { ... }
 *   if (result & DMA_ST_DONE(ch))  { ... }
 */
static inline uint32_t dma_wait(uint8_t ch) {
    uint32_t st;
    do {
        DMA_READ(DMA_OFS_STATUS, st);
    } while (!(st & (DMA_ST_DONE(ch) | DMA_ST_ERROR(ch))));
    return st;
}

/* ── Poll: chờ tất cả channel trong mask hoàn tất ───────────────────────── */
/*
 * ch_mask: bitmask của các channel cần chờ (ví dụ: 0x3 = CH0+CH1).
 * Trả về STATUS khi tất cả channel trong mask đều DONE hoặc có ít nhất 1 ERROR.
 * Caller nên check DMA_ST_ERROR_ANY để xem có lỗi không.
 */
static inline uint32_t dma_wait_all(uint8_t ch_mask) {
    uint32_t st;
    uint32_t done_mask  = (uint32_t)(ch_mask & 0xFu);
    uint32_t error_mask = (uint32_t)(ch_mask & 0xFu) << 4;
    do {
        DMA_READ(DMA_OFS_STATUS, st);
        /* Dừng khi tất cả channel trong mask DONE, hoặc bất kỳ 1 channel ERROR */
        if (st & error_mask) break;
    } while ((st & done_mask) != done_mask);
    return st;
}

/* ── Poll: kiểm tra channel có đang bận không (non-blocking) ────────────── */
static inline uint32_t dma_is_busy(uint8_t ch) {
    uint32_t st;
    DMA_READ(DMA_OFS_STATUS, st);
    return (st & DMA_ST_BUSY(ch)) ? 1u : 0u;
}

/* ============================================================================
 * CONVENIENCE: Setup + Start + Wait trong 1 lần gọi
 *
 * Phù hợp khi chỉ cần 1 channel và không quan tâm đến overlap.
 * Tự động clear status trước khi start (tránh đọc nhầm sticky bit cũ).
 *
 * Trả về 0 nếu thành công, -1 nếu có lỗi.
 * ============================================================================ */
static inline int dma_memcpy(uint8_t ch, uint32_t src, uint32_t dst, uint32_t len) {
    uint32_t st;

    /* 1. Clear sticky status cũ của channel này */
    DMA_WRITE_DYN(0, DMA_OFS_STATUS,
        DMA_ST_DONE(ch) | DMA_ST_ERROR(ch));

    /* 2. Cấu hình channel */
    dma_ch_setup(ch, src, dst, len);

    /* 3. Khởi động */
    dma_ch_start(ch);

    /* 4. Chờ hoàn tất */
    st = dma_wait(ch);

    /* 5. Clear status sau khi done */
    DMA_WRITE_DYN(0, DMA_OFS_STATUS,
        DMA_ST_DONE(ch) | DMA_ST_ERROR(ch));

    return (st & DMA_ST_ERROR(ch)) ? -1 : 0;
}

/* ============================================================================
 * ISR HELPER: dùng trong interrupt handler của PLIC[7]
 *
 * Ví dụ ISR:
 *   void dma_irq_handler(void) {
 *       uint32_t pending = dma_isr_get_pending();
 *       for (int ch = 0; ch < 4; ch++) {
 *           if (pending & DMA_IRQ_CH(ch)) {
 *               // xử lý channel ch
 *               dma_isr_clear(ch);
 *           }
 *       }
 *   }
 * ============================================================================ */

/* Trả về IRQ_STATUS hiện tại (các channel đang pending IRQ) */
static inline uint32_t dma_isr_get_pending(void) {
    return dma_read_irq_status();
}

/* Clear IRQ của channel ch sau khi xử lý xong */
static inline void dma_isr_clear(uint8_t ch) {
    dma_clear_irq(ch);
    dma_clear_done(ch);   /* Clear sticky DONE cùng lúc */
}

/* ============================================================================
 * USAGE EXAMPLES
 * ============================================================================
 *
 * ── Ví dụ 1: Copy đơn giản bằng CH0 (blocking) ──────────────────────────
 *
 *   int ret = dma_memcpy(0, 0x20001000, 0x20002000, 256);
 *   if (ret < 0) { // xử lý lỗi }
 *
 * ── Ví dụ 2: 2 channel chạy song song rồi chờ cả hai ──────────────────
 *
 *   // Clear status cũ
 *   dma_clear_all_status();
 *
 *   // Setup & start cả 2
 *   dma_ch0_setup(0x20001000, 0x20003000, 512);
 *   dma_ch1_setup(0x20005000, 0x20007000, 256);
 *   dma_ch0_start();
 *   dma_ch1_start();
 *
 *   // Chờ cả CH0 và CH1
 *   uint32_t st = dma_wait_all(0x3);   // mask = CH0|CH1
 *   if (st & DMA_ST_ERROR_ANY) { // có lỗi ở channel nào đó }
 *
 * ── Ví dụ 3: Dùng IRQ (non-blocking) ────────────────────────────────────
 *
 *   dma_clear_all_irq();
 *   dma_irq_enable(DMA_IRQ_CH(0));     // chỉ bật IRQ CH0
 *
 *   dma_ch0_setup(src, dst, len);
 *   dma_ch0_start();
 *   // ... CPU làm việc khác ...
 *
 *   // Trong ISR:
 *   void dma_irq_handler(void) {
 *       uint32_t pend = dma_isr_get_pending();
 *       if (pend & DMA_IRQ_CH(0)) {
 *           dma_isr_clear(0);
 *           // callback / signal semaphore
 *       }
 *   }
 *
 * ── Ví dụ 4: Vòng lặp nhiều channel với runtime index ──────────────────
 *
 *   uint32_t srcs[4] = { 0x1000, 0x2000, 0x3000, 0x4000 };
 *   uint32_t dsts[4] = { 0x5000, 0x6000, 0x7000, 0x8000 };
 *   for (int ch = 0; ch < 4; ch++) {
 *       dma_ch_setup(ch, srcs[ch], dsts[ch], 128);
 *       dma_ch_start(ch);
 *   }
 *   uint32_t st = dma_wait_all(0xF);   // chờ tất cả 4 channel
 *
 * ============================================================================ */

#endif /* _DMA_H_ */