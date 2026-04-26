/* irq.h — RISC-V M-mode interrupt helpers */
#ifndef IRQ_H
#define IRQ_H

#include <stdint.h>

/* ── mtvec ───────────────────────────────────────────────────────────────── */
static inline void irq_set_mtvec(void *handler)
{
    /* Direct mode: mtvec[1:0] = 00 */
    __asm__ volatile ("csrw mtvec, %0" :: "r" (handler) : "memory");
}

/* ── mstatus.MIE (bit 3) ─────────────────────────────────────────────────── */
static inline void irq_enable_global(void)
{
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
}

static inline void irq_disable_global(void)
{
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
}

/* ── mie bit fields ──────────────────────────────────────────────────────── */
static inline void irq_enable_software(void)   /* mie.MSIE bit 3 */
{
    __asm__ volatile ("li t0, 8\n csrs mie, t0" ::: "t0", "memory");
}

static inline void irq_enable_timer(void)      /* mie.MTIE bit 7 */
{
    __asm__ volatile ("li t0, 128\n csrs mie, t0" ::: "t0", "memory");
}

static inline void irq_enable_external(void)   /* mie.MEIE bit 11 */
{
    __asm__ volatile ("li t0, 0x800\n csrs mie, t0" ::: "t0", "memory");
}

static inline void irq_disable_software(void)
{
    __asm__ volatile ("li t0, 8\n csrc mie, t0" ::: "t0", "memory");
}

static inline void irq_disable_timer(void)
{
    __asm__ volatile ("li t0, 128\n csrc mie, t0" ::: "t0", "memory");
}

static inline void irq_disable_external(void)
{
    __asm__ volatile ("li t0, 0x800\n csrc mie, t0" ::: "t0", "memory");
}

/* ── CSR read helpers ────────────────────────────────────────────────────── */
static inline uint32_t irq_mcause(void)
{
    uint32_t v;
    __asm__ volatile ("csrr %0, mcause" : "=r" (v));
    return v;
}

static inline uint32_t irq_mepc(void)
{
    uint32_t v;
    __asm__ volatile ("csrr %0, mepc" : "=r" (v));
    return v;
}

/*
 * TRAP_HANDLER(name) — tạo M-mode interrupt handler chuẩn RISC-V.
 *
 * Dùng __attribute__((interrupt("machine"))) để GCC tự động:
 *   - Lưu/phục hồi toàn bộ caller-saved registers
 *   - Dùng mret thay vì ret
 *
 * Quy ước: định nghĩa name##_impl(void) trước khi gọi macro.
 *
 * Ví dụ:
 *   static void my_isr_impl(void) { ... }
 *   TRAP_HANDLER(my_isr)        // sinh my_isr() làm mtvec target
 *   irq_set_mtvec(my_isr);
 */
#define TRAP_HANDLER(name)                                              \
__attribute__((interrupt("machine"))) void name(void) {                \
    name##_impl();                                                      \
}

#endif /* IRQ_H */
