/* clint.h — CLINT Driver (S4 @ 0x4000_0000)
 *
 * Register map (từ clint.v):
 *   0x0000  msip         [RW]  Machine software interrupt pending (bit[0])
 *   0x4000  mtimecmp_lo  [RW]  Timer compare — 32-bit thấp
 *   0x4004  mtimecmp_hi  [RW]  Timer compare — 32-bit cao
 *   0xBFF8  mtime_lo     [RO]  Current mtime — 32-bit thấp
 *   0xBFFC  mtime_hi     [RO]  Current mtime — 32-bit cao
 *
 * Lưu ý: offset > 12-bit → KHÔNG dùng inline asm "i" constraint.
 * Dùng C pointer (volatile uint32_t *) cho tất cả access.
 *
 * mtime tick = 1 MHz (prescaler trong soc_top) → 1 tick = 1 µs
 * timer_irq fires khi mtime >= mtimecmp
 */
#ifndef CLINT_H
#define CLINT_H

#include <stdint.h>
#include "memory_map.h"

/* ── Register pointers (C pointer, không dùng MMIO_REG macro vì offset > 12-bit) */
#define CLINT_MSIP         ((volatile uint32_t *)(CLINT_BASE + 0x0000UL))
#define CLINT_MTIMECMP_LO  ((volatile uint32_t *)(CLINT_BASE + 0x4000UL))
#define CLINT_MTIMECMP_HI  ((volatile uint32_t *)(CLINT_BASE + 0x4004UL))
#define CLINT_MTIME_LO     ((volatile uint32_t *)(CLINT_BASE + 0xBFF8UL))
#define CLINT_MTIME_HI     ((volatile uint32_t *)(CLINT_BASE + 0xBFFCUL))

/* ── mtime read ──────────────────────────────────────────────────────────── */
/*
 * Đọc lo trước để giảm khả năng race:
 * Nếu hi thay đổi giữa 2 lần đọc, đọc lại lần nữa.
 */
static inline uint64_t clint_mtime(void)
{
    uint32_t lo, hi, hi2;
    do {
        hi  = *CLINT_MTIME_HI;
        lo  = *CLINT_MTIME_LO;
        hi2 = *CLINT_MTIME_HI;
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | (uint64_t)lo;
}

/* ── mtimecmp write ──────────────────────────────────────────────────────── */
/*
 * Ghi hi = 0xFFFFFFFF trước để tránh spurious interrupt trong lúc update.
 * Sau đó ghi lo, rồi ghi hi chính thức — per RISC-V spec.
 */
static inline void clint_set_mtimecmp(uint64_t cmp)
{
    *CLINT_MTIMECMP_HI = 0xFFFFFFFFu;   /* block spurious */
    __asm__ volatile ("fence w,w" ::: "memory");
    *CLINT_MTIMECMP_LO = (uint32_t)(cmp & 0xFFFFFFFFu);
    __asm__ volatile ("fence w,w" ::: "memory");
    *CLINT_MTIMECMP_HI = (uint32_t)(cmp >> 32);
    __asm__ volatile ("fence w,w" ::: "memory");
}

/*
 * Set timer để fire sau us microseconds (mtime đơn vị µs @ 1 MHz tick).
 */
static inline void clint_set_timer_delay_us(uint32_t us)
{
    uint64_t now = clint_mtime();
    clint_set_mtimecmp(now + (uint64_t)us);
}

/* Vô hiệu hóa timer interrupt bằng cách đặt mtimecmp = max */
static inline void clint_clear_timer(void)
{
    clint_set_mtimecmp(0xFFFFFFFFFFFFFFFFULL);
}

/* ── Software interrupt ──────────────────────────────────────────────────── */
static inline void clint_sw_irq_set(void)
{
    *CLINT_MSIP = 1u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void clint_sw_irq_clear(void)
{
    *CLINT_MSIP = 0u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline uint32_t clint_sw_irq_pending(void)
{
    return *CLINT_MSIP & 1u;
}

#endif /* CLINT_H */
