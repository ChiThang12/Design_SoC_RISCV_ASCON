#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#define configCPU_CLOCK_HZ                  100000000UL
#define configMTIME_CLOCK_HZ                1000000UL
#define configTICK_RATE_HZ                  5000UL

#define configUSE_PREEMPTION                1
#define configUSE_TIME_SLICING              1
#define configUSE_IDLE_HOOK                 0
#define configUSE_TICK_HOOK                 0
#define configMAX_PRIORITIES                4
#define configMINIMAL_STACK_SIZE            128
#define configTOTAL_HEAP_SIZE               0
#define configMAX_TASK_NAME_LEN             8
#define configUSE_16_BIT_TICKS              0
#define configIDLE_SHOULD_YIELD             1
#define configSUPPORT_STATIC_ALLOCATION     1
#define configSUPPORT_DYNAMIC_ALLOCATION    0

#define configUSE_MUTEXES                   0
#define configUSE_RECURSIVE_MUTEXES         0
#define configUSE_COUNTING_SEMAPHORES       0
#define configUSE_TIMERS                    0
#define configUSE_MALLOC_FAILED_HOOK        0

#define INCLUDE_vTaskDelay                  1
#define INCLUDE_vTaskDelete                 0
#define INCLUDE_vTaskSuspend                0
#define INCLUDE_xTaskGetSchedulerState      0

#define portCLINT_BASE                      0x40000000UL
#define portUART_BASE                       0x50000000UL

#endif
