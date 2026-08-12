/* test_freertos_kernel_smoke.c - real FreeRTOS-Kernel bring-up smoke */
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "uart.h"
#include "irq.h"

#define KERNEL_SMOKE_STACK_WORDS 128u
#define KERNEL_SMOKE_UART_DIV    16u

static StaticTask_t task_a_tcb;
static StaticTask_t task_b_tcb;
static StaticTask_t idle_tcb;

static StackType_t task_a_stack[ KERNEL_SMOKE_STACK_WORDS ];
static StackType_t task_b_stack[ KERNEL_SMOKE_STACK_WORDS ];
static StackType_t idle_stack[ configMINIMAL_STACK_SIZE ];

static volatile uint32_t task_a_count;
static volatile uint32_t task_b_count;
static volatile uint32_t pass_reported;

static void stop_timer_for_pass( void )
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

static void maybe_pass( void )
{
    if( ( pass_reported == 0u ) &&
        ( task_a_count >= 2u ) &&
        ( task_b_count >= 2u ) )
    {
        pass_reported = 1u;
        stop_timer_for_pass();
        uart_puts( "[PASS] freertos_kernel_smoke\r\n" );
        while( 1 )
        {
            __asm__ volatile ( "nop" );
        }
    }
}

static void task_a( void * arg )
{
    ( void ) arg;

    while( 1 )
    {
        task_a_count++;
        maybe_pass();
        taskYIELD();
        __asm__ volatile ( "nop" );
    }
}

static void task_b( void * arg )
{
    ( void ) arg;

    while( 1 )
    {
        task_b_count++;
        maybe_pass();
        taskYIELD();
        __asm__ volatile ( "nop" );
    }
}

void vApplicationGetIdleTaskMemory( StaticTask_t ** ppxIdleTaskTCBBuffer,
                                    StackType_t ** ppxIdleTaskStackBuffer,
                                    configSTACK_DEPTH_TYPE * puxIdleTaskStackSize )
{
    *ppxIdleTaskTCBBuffer = &idle_tcb;
    *ppxIdleTaskStackBuffer = idle_stack;
    *puxIdleTaskStackSize = configMINIMAL_STACK_SIZE;
}

void vApplicationStackOverflowHook( TaskHandle_t task, char * name )
{
    ( void ) task;
    ( void ) name;
    irq_disable_global();
    uart_puts( "[FAIL] freertos_kernel_smoke stack\r\n" );
    while( 1 )
    {
        __asm__ volatile ( "nop" );
    }
}

int main( void )
{
    uart_init( KERNEL_SMOKE_UART_DIV, 0u, 0u );
    uart_puts( "[RTOS] FreeRTOS kernel smoke boot\r\n" );

    if( xTaskCreateStatic( task_a,
                           "A",
                           KERNEL_SMOKE_STACK_WORDS,
                           0,
                           tskIDLE_PRIORITY + 1u,
                           task_a_stack,
                           &task_a_tcb ) == 0 )
    {
        uart_puts( "[FAIL] freertos_kernel_smoke createA\r\n" );
        while( 1 ) {}
    }

    if( xTaskCreateStatic( task_b,
                           "B",
                           KERNEL_SMOKE_STACK_WORDS,
                           0,
                           tskIDLE_PRIORITY + 1u,
                           task_b_stack,
                           &task_b_tcb ) == 0 )
    {
        uart_puts( "[FAIL] freertos_kernel_smoke createB\r\n" );
        while( 1 ) {}
    }

    vTaskStartScheduler();

    uart_puts( "[FAIL] freertos_kernel_smoke scheduler\r\n" );
    while( 1 )
    {
        __asm__ volatile ( "nop" );
    }
}
