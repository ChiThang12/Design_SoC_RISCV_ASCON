/* test_freertos_kernel_smoke.c - real FreeRTOS-Kernel bring-up smoke */
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "uart.h"
#include "irq.h"
#include "gpio.h"

#define KERNEL_SMOKE_STACK_WORDS 128u
#define KERNEL_SMOKE_UART_DIV    16u
#define TELEMETRY_EARLY_LIMIT    4u
#define TELEMETRY_SPACING_MASK   0x1Fu
#define HEARTBEAT_GPIO_BIT       0u
#define HEARTBEAT_GPIO_MASK      (1u << HEARTBEAT_GPIO_BIT)

static StaticTask_t task_a_tcb;
static StaticTask_t task_b_tcb;
static StaticTask_t idle_tcb;

static StackType_t task_a_stack[ KERNEL_SMOKE_STACK_WORDS ];
static StackType_t task_b_stack[ KERNEL_SMOKE_STACK_WORDS ];
static StackType_t idle_stack[ configMINIMAL_STACK_SIZE ];

static volatile uint32_t task_a_count;
static volatile uint32_t task_b_count;
static volatile uint32_t telemetry_beat;
static volatile uint32_t pass_reported;

static void uart_putu32( uint32_t value )
{
    char buf[ 11 ];
    uint32_t i = 0u;

    if( value == 0u )
    {
        uart_putc( '0' );
        return;
    }

    while( ( value != 0u ) && ( i < sizeof( buf ) ) )
    {
        buf[ i ] = (char)( '0' + ( value % 10u ) );
        value /= 10u;
        i++;
    }

    while( i > 0u )
    {
        i--;
        uart_putc( buf[ i ] );
    }
}

static uint32_t telemetry_should_emit( uint32_t count )
{
    return ( count <= TELEMETRY_EARLY_LIMIT ) || ( ( count & TELEMETRY_SPACING_MASK ) == 0u );
}

static void telemetry_emit( char task_name )
{
    telemetry_beat++;
    uart_puts( "[TEL] task=" );
    uart_putc( task_name );
    uart_puts( " tick=" );
    uart_putu32( (uint32_t)xTaskGetTickCount() );
    uart_puts( " a=" );
    uart_putu32( task_a_count );
    uart_puts( " b=" );
    uart_putu32( task_b_count );
    uart_puts( " beat=" );
    uart_putu32( telemetry_beat );
    uart_puts( "\r\n" );
}

static void heartbeat_init( void )
{
    gpio_set_dir( HEARTBEAT_GPIO_MASK );
    gpio_clear( HEARTBEAT_GPIO_MASK );
}

static void heartbeat_update( void )
{
    if( ( xTaskGetTickCount() & 1u ) != 0u )
    {
        gpio_set( HEARTBEAT_GPIO_MASK );
    }
    else
    {
        gpio_clear( HEARTBEAT_GPIO_MASK );
    }
}

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
        heartbeat_update();
        if( telemetry_should_emit( task_a_count ) != 0u )
        {
            telemetry_emit( 'A' );
        }
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
        if( telemetry_should_emit( task_b_count ) != 0u )
        {
            telemetry_emit( 'B' );
        }
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
    heartbeat_init();
    uart_puts( "[RTOS] FreeRTOS kernel smoke boot\r\n" );
    uart_puts( "[TEL] dashboard=armed\r\n" );

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

    uart_puts( "[TEL] scheduler=starting\r\n" );
    vTaskStartScheduler();

    uart_puts( "[FAIL] freertos_kernel_smoke scheduler\r\n" );
    while( 1 )
    {
        __asm__ volatile ( "nop" );
    }
}
