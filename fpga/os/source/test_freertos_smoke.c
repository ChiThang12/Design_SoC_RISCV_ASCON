/* test_freertos_smoke.c - Phase 3 minimal FreeRTOS-port smoke
 *
 * This is not the upstream FreeRTOS kernel yet. It is a small, self-contained
 * compatibility smoke that exercises the exact machine-mode contract required
 * by a FreeRTOS RISC-V port: task stacks, full context save/restore, CLINT tick,
 * and mret into the selected task.
 */
#include <stdint.h>
#include "uart.h"
#include "irq.h"

typedef void (*TaskFunction_t)(void *);
typedef uint32_t StackType_t;
typedef int BaseType_t;

typedef struct {
    uint32_t ra, sp, gp, tp;
    uint32_t t0, t1, t2;
    uint32_t s0, s1;
    uint32_t a0, a1, a2, a3, a4, a5, a6, a7;
    uint32_t s2, s3, s4, s5, s6, s7, s8, s9, s10, s11;
    uint32_t t3, t4, t5, t6;
    uint32_t mepc;
    uint32_t mstatus;
} freertos_port_ctx_t;

#define configTICK_RATE_HZ      5000u
#define portTICK_US             (1000000u / configTICK_RATE_HZ)
#define portMAX_TASKS           2u
#define portSTACK_WORDS         128u
#define pdPASS                  1
#define pdFAIL                  0

static freertos_port_ctx_t task_ctx[portMAX_TASKS];
static freertos_port_ctx_t *volatile pxCurrentTCB = &task_ctx[0];
static StackType_t task0_stack[portSTACK_WORDS];
static StackType_t task1_stack[portSTACK_WORDS];

static volatile uint32_t uxCurrentTask;
static volatile uint32_t xTickCount;
static volatile uint32_t uxSwitchCount;
static volatile uint32_t task0_count;
static volatile uint32_t task1_count;
static volatile uint32_t pass_reported;
static volatile uint32_t fail_code;

void freertos_trap_entry(void);
void freertos_start_first_task(uint32_t sp_value, void (*entry)(void));
void freertos_restore_context(void);

static void prvTaskA(void *arg);
static void prvTaskB(void *arg);

static void vPortSetupTimerInterrupt(void)
{
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

static void vPortStopTimerForPass(void)
{
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

static void vPortPutPassLine(void)
{
    uart_puts("[PASS] freertos_smoke\r\n");
}

static void prvMaybePass(void)
{
    if (!pass_reported &&
        xTickCount >= 4u &&
        uxSwitchCount >= 4u &&
        task0_count >= 2u &&
        task1_count >= 2u &&
        fail_code == 0u) {
        pass_reported = 1u;
        vPortStopTimerForPass();
        vPortPutPassLine();
        while (1) {
            __asm__ volatile ("nop");
        }
    }
}

freertos_port_ctx_t *xPortSysTickHandler(void)
{
    uint32_t cause = irq_mcause();

    if (cause != 0x80000007u) {
        fail_code = cause;
        irq_disable_timer();
        irq_disable_global();
        return pxCurrentTCB;
    }

    xTickCount++;
    vPortSetupTimerInterrupt();

    uxCurrentTask ^= 1u;
    uxSwitchCount++;
    pxCurrentTCB = &task_ctx[uxCurrentTask];
    return pxCurrentTCB;
}

__attribute__((naked)) void freertos_trap_entry(void)
{
    __asm__ volatile (
        "addi sp, sp, -12\n"
        "sw t0, 0(sp)\n"
        "sw t1, 4(sp)\n"
        "sw t2, 8(sp)\n"

        "la t0, pxCurrentTCB\n"
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
        "nop\n"
        "nop\n"
        "sw t1, 124(t0)\n"
        "csrr t1, mstatus\n"
        "nop\n"
        "nop\n"
        "ori t1, t1, 0x88\n"
        "sw t1, 128(t0)\n"

        "addi sp, sp, 12\n"
        "call xPortSysTickHandler\n"
        "fence w,w\n"
        "j freertos_restore_context\n"
    );
}

__attribute__((naked)) void freertos_start_first_task(uint32_t sp_value, void (*entry)(void))
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

__attribute__((naked)) void freertos_restore_context(void)
{
    __asm__ volatile (
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

static uint32_t prvStackTop(StackType_t *stack, uint32_t words)
{
    uint32_t sp;
    __asm__ volatile (
        "slli %0, %2, 2\n"
        "add %0, %1, %0\n"
        "andi %0, %0, -8\n"
        : "=&r" (sp)
        : "r" (stack), "r" (words)
    );
    return sp;
}

static void prvInitContext(freertos_port_ctx_t *ctx,
                           TaskFunction_t entry,
                           void *arg,
                           StackType_t *stack,
                           uint32_t words)
{
    uint32_t i;
    uint32_t *raw = (uint32_t *)ctx;
    uint32_t gp_value;
    uint32_t tp_value;

    for (i = 0u; i < (sizeof(*ctx) / sizeof(uint32_t)); i++) {
        raw[i] = 0u;
    }

    __asm__ volatile ("mv %0, gp" : "=r" (gp_value));
    __asm__ volatile ("mv %0, tp" : "=r" (tp_value));
    ctx->sp = prvStackTop(stack, words);
    ctx->gp = gp_value;
    ctx->tp = tp_value;
    ctx->a0 = (uint32_t)arg;
    ctx->mepc = (uint32_t)entry;
    ctx->mstatus = 0x00001888u;
}

BaseType_t xTaskCreate(TaskFunction_t task,
                       const char *name,
                       uint32_t stack_words,
                       void *arg,
                       uint32_t priority,
                       void *handle)
{
    static uint32_t created;
    StackType_t *stack;

    (void)name;
    (void)stack_words;
    (void)priority;
    (void)handle;

    if (created >= portMAX_TASKS) {
        return pdFAIL;
    }

    stack = (created == 0u) ? task0_stack : task1_stack;
    prvInitContext(&task_ctx[created], task, arg, stack, portSTACK_WORDS);
    created++;
    return pdPASS;
}

void vTaskStartScheduler(void)
{
    uxCurrentTask = 0u;
    pxCurrentTCB = &task_ctx[0];
    irq_set_mtvec(freertos_trap_entry);
    irq_enable_timer();
    vPortSetupTimerInterrupt();
    __asm__ volatile ("fence w,w" ::: "memory");
    freertos_start_first_task(task_ctx[0].sp, (void (*)(void))task_ctx[0].mepc);
}

static void prvTaskA(void *arg)
{
    (void)arg;
    while (1) {
        task0_count++;
        prvMaybePass();
        __asm__ volatile ("nop");
    }
}

static void prvTaskB(void *arg)
{
    (void)arg;
    while (1) {
        task1_count++;
        prvMaybePass();
        __asm__ volatile ("nop");
    }
}

int main(void)
{
    uart_init(16u, 0u, 0u);
    uart_puts("[RTOS] FreeRTOS smoke boot\r\n");

    if (xTaskCreate(prvTaskA, "A", portSTACK_WORDS, 0, 1u, 0) != pdPASS ||
        xTaskCreate(prvTaskB, "B", portSTACK_WORDS, 0, 1u, 0) != pdPASS) {
        uart_puts("[FAIL] freertos_smoke create\r\n");
        while (1) {
            __asm__ volatile ("nop");
        }
    }

    vTaskStartScheduler();
    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
