/* gpio.h — GPIO Driver (S6 @ 0x5001_0000)
 *
 * Register map (từ gpio_regfile.v):
 *   0x00  DIR      direction: 1=output, 0=input per bit
 *   0x04  DOUT     data output
 *   0x08  DIN      data input (RO)
 *   0x0C  IRQ_EN   interrupt enable per bit
 *   0x10  IRQ_STAT interrupt status (W1C)
 *   0x14  IRQ_MODE 0=level, 1=edge per bit
 *   0x18  IRQ_POL  0=falling/low, 1=rising/high per bit
 */
#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>
#include "memory_map.h"

/* ── Register accessors ──────────────────────────────────────────────────── */
#define GPIO_DIR      MMIO_REG(GPIO_BASE, 0x00)
#define GPIO_DOUT     MMIO_REG(GPIO_BASE, 0x04)
#define GPIO_DIN      MMIO_REG(GPIO_BASE, 0x08)
#define GPIO_IRQ_EN   MMIO_REG(GPIO_BASE, 0x0C)
#define GPIO_IRQ_STAT MMIO_REG(GPIO_BASE, 0x10)
#define GPIO_IRQ_MODE MMIO_REG(GPIO_BASE, 0x14)
#define GPIO_IRQ_POL  MMIO_REG(GPIO_BASE, 0x18)

/* ── Direction ───────────────────────────────────────────────────────────── */

/* out_mask: bit=1 → output, bit=0 → input */
static inline void gpio_set_dir(uint32_t out_mask)
{
    GPIO_DIR = out_mask;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── Output write ────────────────────────────────────────────────────────── */

/* Ghi val vào các bit có mask=1, không đụng các bit còn lại */
static inline void gpio_write(uint32_t val, uint32_t mask)
{
    uint32_t cur = GPIO_DOUT;
    GPIO_DOUT = (cur & ~mask) | (val & mask);
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void gpio_set(uint32_t mask)
{
    GPIO_DOUT |= mask;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void gpio_clear(uint32_t mask)
{
    GPIO_DOUT &= ~mask;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── Input read ──────────────────────────────────────────────────────────── */
static inline uint32_t gpio_read(void)
{
    return GPIO_DIN;
}

/* ── IRQ config ──────────────────────────────────────────────────────────── */
/*
 * gpio_irq_enable:
 *   pin_mask  — bitmask các pin cần bật IRQ
 *   edge      — 0=level trigger, 1=edge trigger (IRQ_MODE)
 *   polarity  — 0=falling/low, 1=rising/high (IRQ_POL)
 */
/* NOTE: edge/polarity dùng uint32_t thay vì uint8_t để tránh GCC sinh sb/lbu.
 * DCache store buffer có bug forwarding sub-word (BUG-C9): sb → lbu trả sai data.
 * uint32_t → sw/lw → bypass bug. Xóa workaround này sau khi fix BUG-C9 trong RTL. */
static inline void gpio_irq_enable(uint32_t pin_mask, uint32_t edge, uint32_t polarity)
{
    if (edge)
        GPIO_IRQ_MODE |= pin_mask;
    else
        GPIO_IRQ_MODE &= ~pin_mask;

    if (polarity)
        GPIO_IRQ_POL |= pin_mask;
    else
        GPIO_IRQ_POL &= ~pin_mask;

    GPIO_IRQ_EN |= pin_mask;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* W1C: ghi 1 vào bit tương ứng để xóa */
static inline void gpio_irq_clear(uint32_t pin_mask)
{
    GPIO_IRQ_STAT = pin_mask;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline uint32_t gpio_irq_status(void)
{
    return GPIO_IRQ_STAT;
}

#endif /* GPIO_H */
