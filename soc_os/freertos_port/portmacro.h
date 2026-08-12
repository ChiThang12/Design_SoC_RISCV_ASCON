#ifndef PORTMACRO_H
#define PORTMACRO_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define portCHAR          char
#define portFLOAT         float
#define portDOUBLE        double
#define portLONG          long
#define portSHORT         short
#define portSTACK_TYPE    uint32_t
#define portBASE_TYPE     long

typedef portSTACK_TYPE StackType_t;
typedef long BaseType_t;
typedef unsigned long UBaseType_t;

#if ( configTICK_TYPE_WIDTH_IN_BITS == TICK_TYPE_WIDTH_16_BITS )
    typedef uint16_t TickType_t;
    #define portMAX_DELAY    ( TickType_t ) 0xffffU
#elif ( configTICK_TYPE_WIDTH_IN_BITS == TICK_TYPE_WIDTH_32_BITS )
    typedef uint32_t TickType_t;
    #define portMAX_DELAY    ( TickType_t ) 0xffffffffUL
#else
    #error Unsupported TickType_t width for H3 RV32 port
#endif

#define portSTACK_GROWTH           ( -1 )
#define portTICK_PERIOD_MS         ( ( TickType_t ) 1000 / configTICK_RATE_HZ )
#define portBYTE_ALIGNMENT         8
#define portPOINTER_SIZE_TYPE      uint32_t
#define portCRITICAL_NESTING_IN_TCB 0
#define portNOP()                  __asm__ volatile ( "nop" )
#define portINLINE                 inline
#define portFORCE_INLINE           inline __attribute__( ( always_inline ) )
#define portDONT_DISCARD           __attribute__( ( used ) )
#define portARCH_NAME              "H3_RV32IM_MMODE"

void vPortYield( void );
void vPortEnterCritical( void );
void vPortExitCritical( void );
void vPortDisableInterrupts( void );
void vPortEnableInterrupts( void );

#define portDISABLE_INTERRUPTS()   vPortDisableInterrupts()
#define portENABLE_INTERRUPTS()    vPortEnableInterrupts()
#define portENTER_CRITICAL()       vPortEnterCritical()
#define portEXIT_CRITICAL()        vPortExitCritical()
#define portYIELD()                vPortYield()
#define portYIELD_WITHIN_API()     vPortYield()
#define portYIELD_FROM_ISR( x )    do { if( ( x ) != 0 ) { vPortYield(); } } while( 0 )
#define portEND_SWITCHING_ISR( x ) portYIELD_FROM_ISR( x )
#define portTASK_FUNCTION_PROTO( vFunction, pvParameters ) void vFunction( void * pvParameters )
#define portTASK_FUNCTION( vFunction, pvParameters ) void vFunction( void * pvParameters )

#define portSET_INTERRUPT_MASK_FROM_ISR()    ( 0UL )
#define portCLEAR_INTERRUPT_MASK_FROM_ISR( uxSavedStatusValue ) \
    do { ( void ) ( uxSavedStatusValue ); } while( 0 )

#ifdef __cplusplus
}
#endif

#endif
