/* soc_ctrl.h — SoC Control Driver (S3 @ 0x3000_0000)
 *
 * Register map (từ soc_ctrl_slave.v):
 *   0x000  SYS_ID       RO  = 0xA5C0_0001
 *   0x004  SYS_CTRL     WO  [0]=soft_rst (1-cycle pulse)
 *   0x008  IRQ_STATUS   RW1C [5:0]: [0]=ASCON [1]=UART [2]=GPIO [3]=SPI [4]=TIMER [5]=WDT
 *   0x00C  IRQ_MASK     RW  [5:0]
 *   0x010  ICACHE_HITS  RO
 *   0x014  ICACHE_MISS  RO
 *   0x018  DCACHE_HITS  RO
 *   0x01C  DCACHE_MISS  RO
 *   0x020  DCACHE_WR    RO
 *   0x024  CYCLE_CNT    RO  free-running counter
 *   0x028  HART_ID      RO  = 0x0
 */
#ifndef SOC_CTRL_H
#define SOC_CTRL_H

#include <stdint.h>
#include "memory_map.h"

/* ── IRQ_STATUS / IRQ_MASK bit positions ─────────────────────────────────── */
#define SOC_IRQ_ASCON   (1u << 0)
#define SOC_IRQ_UART    (1u << 1)
#define SOC_IRQ_GPIO    (1u << 2)
#define SOC_IRQ_SPI     (1u << 3)
#define SOC_IRQ_TIMER   (1u << 4)
#define SOC_IRQ_WDT     (1u << 5)

/* ── Expected SYS_ID value ───────────────────────────────────────────────── */
#define SOC_SYSID_EXPECTED  0xA5C00001u

/* ── Register accessors ──────────────────────────────────────────────────── */
#define SOC_SYS_ID      MMIO_REG(SOC_CTRL_BASE, 0x000)
#define SOC_SYS_CTRL    MMIO_REG(SOC_CTRL_BASE, 0x004)
#define SOC_IRQ_STATUS  MMIO_REG(SOC_CTRL_BASE, 0x008)
#define SOC_IRQ_MASK    MMIO_REG(SOC_CTRL_BASE, 0x00C)
#define SOC_ICACHE_HITS MMIO_REG(SOC_CTRL_BASE, 0x010)
#define SOC_ICACHE_MISS MMIO_REG(SOC_CTRL_BASE, 0x014)
#define SOC_DCACHE_HITS MMIO_REG(SOC_CTRL_BASE, 0x018)
#define SOC_DCACHE_MISS MMIO_REG(SOC_CTRL_BASE, 0x01C)
#define SOC_DCACHE_WR   MMIO_REG(SOC_CTRL_BASE, 0x020)
#define SOC_CYCLE_CNT   MMIO_REG(SOC_CTRL_BASE, 0x024)
#define SOC_HART_ID     MMIO_REG(SOC_CTRL_BASE, 0x028)

/* ── API ─────────────────────────────────────────────────────────────────── */

/* Trả về SYS_ID. Nên verify == SOC_SYSID_EXPECTED khi boot. */
static inline uint32_t soc_ctrl_sysid(void)
{
    return SOC_SYS_ID;
}

/* Phát 1-cycle soft reset pulse */
static inline void soc_ctrl_soft_reset(void)
{
    SOC_SYS_CTRL = 1u;
    __asm__ volatile ("fence w,w" ::: "memory");
    /* RTL tự clear sau 1 cycle — không cần ghi 0 */
}

/* Đọc free-running cycle counter */
static inline uint32_t soc_ctrl_cycle_cnt(void)
{
    return SOC_CYCLE_CNT;
}

/*
 * Đọc 4 cache counter cùng lúc.
 * Truyền NULL cho các pointer không cần.
 */
static inline void soc_ctrl_cache_stats(uint32_t *ih, uint32_t *im,
                                         uint32_t *dh, uint32_t *dm)
{
    if (ih) *ih = SOC_ICACHE_HITS;
    if (im) *im = SOC_ICACHE_MISS;
    if (dh) *dh = SOC_DCACHE_HITS;
    if (dm) *dm = SOC_DCACHE_MISS;
}

/* IRQ_STATUS — RW1C */
static inline uint32_t soc_ctrl_irq_status(void)
{
    return SOC_IRQ_STATUS;
}

static inline void soc_ctrl_irq_clear(uint32_t mask)
{
    SOC_IRQ_STATUS = mask;  /* W1C */
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* IRQ_MASK */
static inline void soc_ctrl_irq_mask_set(uint32_t mask)
{
    SOC_IRQ_MASK = mask;
    __asm__ volatile ("fence w,w" ::: "memory");
}

#endif /* SOC_CTRL_H */
