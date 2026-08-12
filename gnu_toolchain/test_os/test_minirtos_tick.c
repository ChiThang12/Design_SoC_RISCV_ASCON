/* test_minirtos_tick.c - Phase 2 pre-FreeRTOS context-switch smoke
 *
 * Goal:
 *   Prove the CPU can run two independent task contexts and switch between
 *   them from a CLINT machine-timer interrupt.
 *
 * This is intentionally smaller than FreeRTOS. It validates the hardware
 * contract FreeRTOS needs most: precise timer trap, full register frame,
 * per-task stack, restore, and mret into the next task.
 */
#include <stdint.h>
#include "uart.h"
#include "clint.h"
#include "irq.h"

typedef struct {
    uint32_t ra;
    uint32_t sp;
    uint32_t gp;
    uint32_t tp;
    uint32_t t0;
    uint32_t t1;
    uint32_t t2;
    uint32_t s0;
    uint32_t s1;
    uint32_t a0;
    uint32_t a1;
    uint32_t a2;
    uint32_t a3;
    uint32_t a4;
    uint32_t a5;
    uint32_t a6;
    uint32_t a7;
    uint32_t s2;
    uint32_t s3;
    uint32_t s4;
    uint32_t s5;
    uint32_t s6;
    uint32_t s7;
    uint32_t s8;
    uint32_t s9;
    uint32_t s10;
    uint32_t s11;
    uint32_t t3;
    uint32_t t4;
    uint32_t t5;
    uint32_t t6;
    uint32_t mepc;
    uint32_t mstatus;
} minirtos_ctx_t;

static minirtos_ctx_t task_ctx[2];
static minirtos_ctx_t *volatile current_ctx = &task_ctx[0];

static uint32_t task0_stack[128];
static uint32_t task1_stack[128];

static volatile uint32_t current_task = 0u;
static volatile uint32_t tick_count = 0u;
static volatile uint32_t switch_count = 0u;
static volatile uint32_t task0_count = 0u;
static volatile uint32_t task1_count = 0u;
static volatile uint32_t pass_reported = 0u;
static volatile uint32_t fail_code = 0u;

#define MINIRTOS_PASS_TICKS     4u
#define MINIRTOS_PASS_SWITCHES  4u
#define MINIRTOS_UART_DIV       16u

static void task0_entry(void);
static void task1_entry(void);
void minirtos_trap_entry(void);
void minirtos_start_first_raw(uint32_t sp_value, void (*entry)(void));

static void schedule_next_tick(void)
{
    /*
     * Keep producer->store-data spacing explicit. This mini-RTOS smoke is
     * intentionally sensitive to RAW hazards because FreeRTOS tick code will
     * hit the same pattern.
     */
    __asm__ volatile (
        "li t0, 0x40004004\n"
        "li t1, -1\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "fence w,w\n"

        "li t0, 0x4000bff8\n"
        "lw t1, 0(t0)\n"
        "addi t1, t1, 200\n"
        "nop\n"
        "nop\n"
        "li t0, 0x40004000\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "fence w,w\n"

        "li t0, 0x40004004\n"
        "li t1, 0\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "fence w,w\n"
        ::: "t0", "t1", "memory"
    );
}

static void stop_timer_for_pass(void)
{
    /*
     * Keep PASS reporting non-preemptible. A pending second tick can otherwise
     * interrupt the UART print and make the regression line look corrupted.
     */
    __asm__ volatile (
        "csrci mstatus, 8\n"
        "li t0, 128\n"
        "csrc mie, t0\n"
        "nop\n"
        "nop\n"

        "li t0, 0x40004004\n"
        "li t1, -1\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "nop\n"
        "nop\n"
        "sw t1, 0(t0)\n"
        "fence w,w\n"
        ::: "t0", "t1", "memory"
    );
}

minirtos_ctx_t *minirtos_tick_from_trap(void)
{
    uint32_t cause = irq_mcause();

    if (cause != 0x80000007u) {
        fail_code = cause;
        irq_disable_timer();
        irq_disable_global();
        return current_ctx;
    }

    tick_count++;
    schedule_next_tick();

    current_task ^= 1u;
    switch_count++;
    current_ctx = &task_ctx[current_task];
    return current_ctx;
}

__attribute__((naked)) void minirtos_trap_entry(void)
{
    __asm__ volatile (
        /* Save t0/t1/t2 on the interrupted task stack before using them. */
        "addi sp, sp, -12\n"
        "sw t0, 0(sp)\n"
        "sw t1, 4(sp)\n"
        "sw t2, 8(sp)\n"

        "la t0, current_ctx\n"
        "lw t0, 0(t0)\n"

        "sw ra, 0(t0)\n"
        "addi t1, sp, 12\n"
        "sw t1, 4(t0)\n"
        "sw gp, 8(t0)\n"
        "sw tp, 12(t0)\n"
        "lw t1, 0(sp)\n"
        "nop\n"
        "nop\n"
        "sw t1, 16(t0)\n"
        "lw t1, 4(sp)\n"
        "nop\n"
        "nop\n"
        "sw t1, 20(t0)\n"
        "lw t1, 8(sp)\n"
        "nop\n"
        "nop\n"
        "sw t1, 24(t0)\n"
        "sw s0, 28(t0)\n"
        "sw s1, 32(t0)\n"
        "sw a0, 36(t0)\n"
        "sw a1, 40(t0)\n"
        "sw a2, 44(t0)\n"
        "sw a3, 48(t0)\n"
        "sw a4, 52(t0)\n"
        "sw a5, 56(t0)\n"
        "sw a6, 60(t0)\n"
        "sw a7, 64(t0)\n"
        "sw s2, 68(t0)\n"
        "sw s3, 72(t0)\n"
        "sw s4, 76(t0)\n"
        "sw s5, 80(t0)\n"
        "sw s6, 84(t0)\n"
        "sw s7, 88(t0)\n"
        "sw s8, 92(t0)\n"
        "sw s9, 96(t0)\n"
        "sw s10, 100(t0)\n"
        "sw s11, 104(t0)\n"
        "sw t3, 108(t0)\n"
        "sw t4, 112(t0)\n"
        "sw t5, 116(t0)\n"
        "sw t6, 120(t0)\n"
        "csrr t1, mepc\n"
        /* CSR read results are not available to the immediately following
         * integer instruction on this pipeline. Keep the saved PC precise. */
        "nop\n"
        "nop\n"
        "sw t1, 124(t0)\n"
        "csrr t1, mstatus\n"
        "nop\n"
        "nop\n"
        "ori t1, t1, 0x88\n"
        "sw t1, 128(t0)\n"

        "addi sp, sp, 12\n"
        "call minirtos_tick_from_trap\n"

        "fence w,w\n"

        "j minirtos_restore_context\n"
    );
}

__attribute__((naked)) void minirtos_start_first_raw(uint32_t sp_value, void (*entry)(void))
{
    (void)sp_value;
    (void)entry;
    __asm__ volatile (
        "li t0, 0x1888\n"
        "csrw mstatus, t0\n"
        "csrw mepc, a1\n"
        "mv sp, a0\n"
        "mret\n"
    );
}

__attribute__((naked)) void minirtos_restore_context(void)
{
    __asm__ volatile (
        /* a0 points to the context to restore. Keep it in t0 until the end. */
        "mv t0, a0\n"
        "lw t1, 128(t0)\n"
        "nop\n"
        "nop\n"
        "ori t1, t1, 0x88\n"
        "csrw mstatus, t1\n"
        "lw t1, 124(t0)\n"
        "nop\n"
        "nop\n"
        "csrw mepc, t1\n"

        "lw ra, 0(t0)\n"
        "lw gp, 8(t0)\n"
        "lw tp, 12(t0)\n"
        "lw s0, 28(t0)\n"
        "lw s1, 32(t0)\n"
        "lw a1, 40(t0)\n"
        "lw a2, 44(t0)\n"
        "lw a3, 48(t0)\n"
        "lw a4, 52(t0)\n"
        "lw a5, 56(t0)\n"
        "lw a6, 60(t0)\n"
        "lw a7, 64(t0)\n"
        "lw s2, 68(t0)\n"
        "lw s3, 72(t0)\n"
        "lw s4, 76(t0)\n"
        "lw s5, 80(t0)\n"
        "lw s6, 84(t0)\n"
        "lw s7, 88(t0)\n"
        "lw s8, 92(t0)\n"
        "lw s9, 96(t0)\n"
        "lw s10, 100(t0)\n"
        "lw s11, 104(t0)\n"
        "lw t3, 108(t0)\n"
        "lw t4, 112(t0)\n"
        "lw t5, 116(t0)\n"
        "lw t6, 120(t0)\n"

        "lw t1, 128(t0)\n"
        "nop\n"
        "nop\n"
        "ori t1, t1, 0x88\n"
        "csrw mstatus, t1\n"
        "lw t1, 124(t0)\n"
        "nop\n"
        "nop\n"
        "csrw mepc, t1\n"
        "lw t1, 20(t0)\n"
        "lw t2, 24(t0)\n"
        "lw sp, 4(t0)\n"
        "lw a0, 36(t0)\n"
        "lw t0, 16(t0)\n"
        "mret\n"
    );
}

__attribute__((naked, noinline)) static uint32_t stack_top(uint32_t *stack, uint32_t words)
{
    (void)stack;
    (void)words;
    __asm__ volatile (
        "slli a1, a1, 2\n"
        "add a0, a0, a1\n"
        "andi a0, a0, -8\n"
        "ret\n"
    );
}

#define UART_PUTC_SAFE_IMM(ch_)                                      \
    __asm__ volatile (                                               \
        "1:\n"                                                       \
        "li t0, 0x50000008\n"                                        \
        "lw t1, 0(t0)\n"                                             \
        "andi t1, t1, 2\n"                                           \
        "bnez t1, 1b\n"                                              \
        "li t0, 0x50000000\n"                                        \
        "li t1, %0\n"                                                \
        "nop\n"                                                      \
        "nop\n"                                                      \
        "nop\n"                                                      \
        "sw t1, 0(t0)\n"                                             \
        "fence w,w\n"                                                \
        :: "i" (ch_) : "t0", "t1", "memory"                         \
    )

static void init_context(minirtos_ctx_t *ctx, void (*entry)(void), uint32_t *stack, uint32_t words)
{
    uint32_t i;
    uint32_t *raw = (uint32_t *)ctx;
    uint32_t gp_value;
    uint32_t tp_value;
    uint32_t sp_value;

    for (i = 0u; i < (sizeof(*ctx) / sizeof(uint32_t)); i++) {
        raw[i] = 0u;
    }

    __asm__ volatile (
        "slli %0, %2, 2\n"
        "add %0, %1, %0\n"
        "andi %0, %0, -8\n"
        : "=&r" (sp_value)
        : "r" (stack), "r" (words)
    );
    ctx->sp = sp_value;
    __asm__ volatile ("mv %0, gp" : "=r" (gp_value));
    __asm__ volatile ("mv %0, tp" : "=r" (tp_value));
    ctx->gp = gp_value;
    ctx->tp = tp_value;
    ctx->mepc = (uint32_t)entry;
    ctx->mstatus = 0x00001888u; /* MPP=M, MPIE=1, MIE=1 for this core's mret path. */
}

static void uart_puts_imm_pass(void)
{
    UART_PUTC_SAFE_IMM('[');
    UART_PUTC_SAFE_IMM('P');
    UART_PUTC_SAFE_IMM('A');
    UART_PUTC_SAFE_IMM('S');
    UART_PUTC_SAFE_IMM('S');
    UART_PUTC_SAFE_IMM(']');
    UART_PUTC_SAFE_IMM(' ');
    UART_PUTC_SAFE_IMM('m');
    UART_PUTC_SAFE_IMM('i');
    UART_PUTC_SAFE_IMM('n');
    UART_PUTC_SAFE_IMM('i');
    UART_PUTC_SAFE_IMM('r');
    UART_PUTC_SAFE_IMM('t');
    UART_PUTC_SAFE_IMM('o');
    UART_PUTC_SAFE_IMM('s');
    UART_PUTC_SAFE_IMM('_');
    UART_PUTC_SAFE_IMM('t');
    UART_PUTC_SAFE_IMM('i');
    UART_PUTC_SAFE_IMM('c');
    UART_PUTC_SAFE_IMM('k');
    UART_PUTC_SAFE_IMM('\r');
    UART_PUTC_SAFE_IMM('\n');
}

static void maybe_pass(void)
{
    if (!pass_reported &&
        tick_count >= MINIRTOS_PASS_TICKS &&
        switch_count >= MINIRTOS_PASS_SWITCHES &&
        task0_count >= 2u &&
        task1_count >= 2u &&
        fail_code == 0u) {
        pass_reported = 1u;
        stop_timer_for_pass();
        uart_puts_imm_pass();
        while (1) {
            __asm__ volatile ("nop");
        }
    }
}

static void task0_entry(void)
{
    while (1) {
        task0_count++;
        maybe_pass();
        __asm__ volatile ("nop");
    }
}

static void task1_entry(void)
{
    while (1) {
        task1_count++;
        maybe_pass();
        __asm__ volatile ("nop");
    }
}

int main(void)
{
    uart_init(MINIRTOS_UART_DIV, 0u, 0u);
    uart_puts("[RTOS] minirtos boot\r\n");

    init_context(&task_ctx[0], task0_entry, task0_stack, 128u);
    init_context(&task_ctx[1], task1_entry, task1_stack, 128u);

    current_task = 0u;
    current_ctx = &task_ctx[0];

    irq_set_mtvec(minirtos_trap_entry);
    irq_enable_timer();
    schedule_next_tick();

    __asm__ volatile ("fence w,w" ::: "memory");
    minirtos_start_first_raw(stack_top(task0_stack, 128u), task0_entry);

    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
