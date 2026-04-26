/* plic.h — PLIC Driver (S9 @ 0x5004_0000)
 *
 * Register map:
 *   0x000 + n*4   priority[n]     per-source priority (0=disable, 1-7=active)
 *   0x080         pending         pending bitmask (RO)
 *   0x100         enable          enable bitmask hart 0
 *   0x200         threshold       priority threshold hart 0
 *   0x204         claim/complete  RO=claim, WO=complete
 */
#ifndef PLIC_H
#define PLIC_H

#include <stdint.h>
#include "memory_map.h"

/* ── Source IDs ──────────────────────────────────────────────────────────── */
#define PLIC_SRC_UART_TX    1u
#define PLIC_SRC_UART_RX    2u
#define PLIC_SRC_GPIO       4u
#define PLIC_SRC_TIMER0     5u
#define PLIC_SRC_TIMER1     6u
#define PLIC_SRC_WDT        7u
#define PLIC_SRC_ASCON      8u
#define PLIC_SRC_DMA        9u

/* ── Register accessors ──────────────────────────────────────────────────── */
#define PLIC_PRIORITY(n)    MMIO_REG(PLIC_BASE, 0x000UL + (uint32_t)(n) * 4UL)
#define PLIC_PENDING        MMIO_REG(PLIC_BASE, 0x080UL)
#define PLIC_ENABLE         MMIO_REG(PLIC_BASE, 0x100UL)
#define PLIC_THRESHOLD      MMIO_REG(PLIC_BASE, 0x200UL)
#define PLIC_CLAIM_COMPLETE MMIO_REG(PLIC_BASE, 0x204UL)

/* ── API ─────────────────────────────────────────────────────────────────── */
static inline void plic_set_priority(uint32_t src, uint32_t prio)
{
    PLIC_PRIORITY(src) = prio;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void plic_enable(uint32_t src)
{
    PLIC_ENABLE |= (1u << src);
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void plic_disable(uint32_t src)
{
    PLIC_ENABLE &= ~(1u << src);
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline void plic_set_threshold(uint32_t thr)
{
    PLIC_THRESHOLD = thr;
    __asm__ volatile ("fence w,w" ::: "memory");
}

static inline uint32_t plic_claim(void)
{
    return PLIC_CLAIM_COMPLETE;
}

static inline void plic_complete(uint32_t src)
{
    PLIC_CLAIM_COMPLETE = src;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* Shortcut: init một source với priority=1, threshold=0 */
static inline void plic_init_source(uint32_t src)
{
    plic_set_threshold(0u);
    plic_set_priority(src, 1u);
    plic_enable(src);
}

#endif /* PLIC_H */
