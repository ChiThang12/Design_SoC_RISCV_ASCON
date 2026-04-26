/* timer.h — Timer0/1 + WDT Driver (S8 @ 0x5003_0000)
 *
 * Register map (từ timer_regfile.v):
 *   0x00  T0_CTRL   [0]=en [1]=auto_reload [2]=irq_en [3]=count_dir
 *   0x04  T0_LOAD   reload value
 *   0x08  T0_COUNT  current count (RO)
 *   0x0C  T0_STATUS [0]=timeout_flag (W1C)
 *   0x10  T1_CTRL   (layout giống T0)
 *   0x14  T1_LOAD
 *   0x18  T1_COUNT  (RO)
 *   0x1C  T1_STATUS [0]=timeout_flag (W1C)
 *   0x20  WDT_CTRL  [0]=en [1]=irq_en
 *   0x24  WDT_LOAD  timeout period
 *   0x28  WDT_FEED  write WDT_FEED_MAGIC to kick
 *   0x2C  WDT_STATUS [0]=expired_flag (W1C)
 */
#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>
#include "memory_map.h"

/* ── CTRL bit fields ─────────────────────────────────────────────────────── */
#define TIMER_CTRL_EN           (1u << 0)
#define TIMER_CTRL_AUTO_RELOAD  (1u << 1)
#define TIMER_CTRL_IRQ_EN       (1u << 2)
#define TIMER_CTRL_COUNT_DIR    (1u << 3)  /* 1=count up, 0=count down */

/* WDT_CTRL bits */
#define WDT_CTRL_EN             (1u << 0)
#define WDT_CTRL_IRQ_EN         (1u << 1)

/* Magic value cho WDT_FEED — phải khớp RTL: 32'hDEAD_FEED */
#define WDT_FEED_MAGIC          0xDEADFEEDu

/* ── Register accessors — Timer 0 ────────────────────────────────────────── */
#define T0_CTRL     MMIO_REG(TIMER_BASE, 0x00)
#define T0_LOAD     MMIO_REG(TIMER_BASE, 0x04)
#define T0_COUNT    MMIO_REG(TIMER_BASE, 0x08)
#define T0_STATUS   MMIO_REG(TIMER_BASE, 0x0C)

/* ── Register accessors — Timer 1 ────────────────────────────────────────── */
#define T1_CTRL     MMIO_REG(TIMER_BASE, 0x10)
#define T1_LOAD     MMIO_REG(TIMER_BASE, 0x14)
#define T1_COUNT    MMIO_REG(TIMER_BASE, 0x18)
#define T1_STATUS   MMIO_REG(TIMER_BASE, 0x1C)

/* ── Register accessors — WDT ────────────────────────────────────────────── */
#define WDT_CTRL    MMIO_REG(TIMER_BASE, 0x20)
#define WDT_LOAD    MMIO_REG(TIMER_BASE, 0x24)
#define WDT_FEED    MMIO_REG(TIMER_BASE, 0x28)
#define WDT_STATUS  MMIO_REG(TIMER_BASE, 0x2C)

/* ── Timer 0 API ─────────────────────────────────────────────────────────── */

static inline void timer0_oneshot(uint32_t load_val)
{
    T0_CTRL = 0u;                       /* disable trước khi config */
    T0_LOAD = load_val;
    __asm__ volatile ("fence w,w" ::: "memory");
    T0_CTRL = TIMER_CTRL_EN;            /* start, no auto-reload */
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void timer0_autoreload(uint32_t load_val, uint8_t irq_en)
{
    T0_CTRL = 0u;
    T0_LOAD = load_val;
    __asm__ volatile ("fence w,w" ::: "memory");
    T0_CTRL = TIMER_CTRL_EN | TIMER_CTRL_AUTO_RELOAD
            | (irq_en ? TIMER_CTRL_IRQ_EN : 0u);
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* Poll đến khi timeout hoặc đạt limit cycle. Return 0=OK, -1=timeout limit */
static inline int timer0_wait_timeout(uint32_t limit)
{
    while (limit--) {
        if (T0_STATUS & 1u) return 0;
    }
    return -1;
}

static inline void timer0_clear(void)
{
    T0_STATUS = 1u;   /* W1C */
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void timer0_stop(void)
{
    T0_CTRL = 0u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── Timer 1 API ─────────────────────────────────────────────────────────── */

static inline void timer1_oneshot(uint32_t load_val)
{
    T1_CTRL = 0u;
    T1_LOAD = load_val;
    __asm__ volatile ("fence w,w" ::: "memory");
    T1_CTRL = TIMER_CTRL_EN;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void timer1_autoreload(uint32_t load_val, uint8_t irq_en)
{
    T1_CTRL = 0u;
    T1_LOAD = load_val;
    __asm__ volatile ("fence w,w" ::: "memory");
    T1_CTRL = TIMER_CTRL_EN | TIMER_CTRL_AUTO_RELOAD
            | (irq_en ? TIMER_CTRL_IRQ_EN : 0u);
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline int timer1_wait_timeout(uint32_t limit)
{
    while (limit--) {
        if (T1_STATUS & 1u) return 0;
    }
    return -1;
}

static inline void timer1_clear(void)
{
    T1_STATUS = 1u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void timer1_stop(void)
{
    T1_CTRL = 0u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── WDT API ─────────────────────────────────────────────────────────────── */

static inline void wdt_enable(uint32_t period)
{
    WDT_CTRL = 0u;      /* disable trước khi load */
    WDT_LOAD = period;
    __asm__ volatile ("fence w,w" ::: "memory");
    WDT_CTRL = WDT_CTRL_EN;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* Kick watchdog — phải ghi đúng magic value */
static inline void wdt_feed(void)
{
    WDT_FEED = WDT_FEED_MAGIC;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void wdt_disable(void)
{
    WDT_CTRL = 0u;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline uint32_t wdt_expired(void)
{
    return WDT_STATUS & 1u;
}

static inline void wdt_clear(void)
{
    WDT_STATUS = 1u;    /* W1C */
    __asm__ volatile ("fence w,w" ::: "memory");
}

#endif /* TIMER_H */
