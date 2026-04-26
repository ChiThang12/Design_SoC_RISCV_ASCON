#ifndef PLIC_DRV_H
#define PLIC_DRV_H

/* ============================================================================
 * plic_drv.h — PLIC Driver (S9 @ 0x5004_0000)
 *
 * Register map (từ SoC doc):
 *   0x000–0x03C  priority[0:11]   — per-source priority (1 = lowest, 7 = highest)
 *   0x080        pending           — pending bitmask
 *   0x100        enable            — enable bitmask cho hart 0
 *   0x204        claim/complete    — claim highest IRQ / complete sau xử lý
 *
 * ASCON IRQ = source 8 (từ RTL plic_top.v, soc_top.v)
 * ============================================================================ */

#include <stdint.h>

#define PLIC_BASE           0x50040000UL

/* Register pointers */
#define PLIC_PRIORITY(n)    (*((volatile uint32_t *)(PLIC_BASE + 0x000UL + (n)*4UL)))
#define PLIC_PENDING        (*((volatile uint32_t *)(PLIC_BASE + 0x080UL)))
#define PLIC_ENABLE         (*((volatile uint32_t *)(PLIC_BASE + 0x100UL)))
#define PLIC_THRESHOLD      (*((volatile uint32_t *)(PLIC_BASE + 0x200UL)))
#define PLIC_CLAIM          (*((volatile uint32_t *)(PLIC_BASE + 0x204UL)))
#define PLIC_COMPLETE       (*((volatile uint32_t *)(PLIC_BASE + 0x204UL))) /* same addr */

/* ASCON source ID */
#define PLIC_SRC_ASCON      8u

/* ── PLIC init: bật ASCON IRQ source ─────────────────────────────────────── */
static inline void plic_init_ascon(void)
{
    /* Priority = 1 (bất kỳ giá trị > 0 đều kích hoạt) */
    PLIC_PRIORITY(PLIC_SRC_ASCON) = 1u;

    /* Enable source 8 cho hart 0 */
    PLIC_ENABLE = (1u << PLIC_SRC_ASCON);

    /* Threshold = 0: accept tất cả priority > 0 */
    PLIC_THRESHOLD = 0u;

    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── Claim: lấy source ID của IRQ đang pending ───────────────────────────── */
static inline uint32_t plic_claim(void)
{
    return PLIC_CLAIM;
}

/* ── Complete: báo PLIC đã xử lý xong source_id ─────────────────────────── */
static inline void plic_complete(uint32_t source_id)
{
    PLIC_COMPLETE = source_id;
    __asm__ volatile ("fence w,w" ::: "memory");
}

/* ── Enable/disable M-mode external interrupt ────────────────────────────── */
static inline void mie_enable_external(void)
{
    /* mie.MEIE = bit 11 */
    __asm__ volatile (
        "li   t0, 0x800\n"
        "csrs mie, t0\n"
        ::: "t0", "memory"
    );
}

static inline void mstatus_enable_irq(void)
{
    /* mstatus.MIE = bit 3 */
    __asm__ volatile (
        "li   t0, 0x8\n"
        "csrs mstatus, t0\n"
        ::: "t0", "memory"
    );
}

static inline void mstatus_disable_irq(void)
{
    __asm__ volatile (
        "li   t0, 0x8\n"
        "csrc mstatus, t0\n"
        ::: "t0", "memory"
    );
}

#endif /* PLIC_DRV_H */