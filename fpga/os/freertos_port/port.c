#include "FreeRTOS.h"
#include "task.h"
#include "irq.h"

extern void freertos_trap_entry( void );
extern void freertos_restore_first_context( void );

static volatile UBaseType_t uxCriticalNesting;

void vPortSetupTimerInterrupt( void )
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

StackType_t * pxPortInitialiseStack( StackType_t * pxTopOfStack,
                                     TaskFunction_t pxCode,
                                     void * pvParameters )
{
    uint32_t gpValue;
    uint32_t tpValue;
    StackType_t * pxFrame;
    uint32_t i;

    pxTopOfStack = ( StackType_t * ) ( ( ( uint32_t ) pxTopOfStack ) & ~0x7UL );
    pxFrame = pxTopOfStack - 33;

    for( i = 0; i < 33u; i++ )
    {
        pxFrame[ i ] = 0u;
    }

    __asm__ volatile ( "mv %0, gp" : "=r" ( gpValue ) );
    __asm__ volatile ( "mv %0, tp" : "=r" ( tpValue ) );

    pxFrame[ 1 ] = ( StackType_t ) pxTopOfStack;    /* sp */
    pxFrame[ 2 ] = gpValue;
    pxFrame[ 3 ] = tpValue;
    pxFrame[ 9 ] = ( StackType_t ) pvParameters;    /* a0 */
    pxFrame[ 31 ] = ( StackType_t ) pxCode;         /* mepc */
    pxFrame[ 32 ] = 0x00001888UL;                   /* MPP=M, MPIE=1, MIE=1 */

    return pxFrame;
}

BaseType_t xPortStartScheduler( void )
{
    uxCriticalNesting = 0;
    irq_set_mtvec( freertos_trap_entry );
    irq_enable_timer();
    vPortSetupTimerInterrupt();
    __asm__ volatile ( "fence w,w" ::: "memory" );
    freertos_restore_first_context();

    return pdFALSE;
}

void vPortEndScheduler( void )
{
    irq_disable_timer();
    irq_disable_global();
}

void vPortDisableInterrupts( void )
{
    irq_disable_global();
}

void vPortEnableInterrupts( void )
{
    irq_enable_global();
}

void vPortEnterCritical( void )
{
    irq_disable_global();
    uxCriticalNesting++;
}

void vPortExitCritical( void )
{
    if( uxCriticalNesting > 0u )
    {
        uxCriticalNesting--;
        if( uxCriticalNesting == 0u )
        {
            irq_enable_global();
        }
    }
}

void vPortYield( void )
{
    __asm__ volatile ( "ecall" ::: "memory" );
}
