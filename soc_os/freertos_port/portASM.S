    .section .text
    .align 2

    .extern pxCurrentTCB
    .extern xTaskIncrementTick
    .extern vTaskSwitchContext
    .extern vPortSetupTimerInterrupt

    .globl freertos_trap_entry
    .globl freertos_restore_context
    .globl freertos_restore_first_context

/* Context frame, 33 words:
 *  0 ra,  1 sp,  2 gp,  3 tp,  4 t0,  5 t1,  6 t2,
 *  7 s0,  8 s1,  9 a0, 10 a1, 11 a2, 12 a3, 13 a4,
 * 14 a5, 15 a6, 16 a7, 17 s2, 18 s3, 19 s4, 20 s5,
 * 21 s6, 22 s7, 23 s8, 24 s9, 25 s10, 26 s11,
 * 27 t3, 28 t4, 29 t5, 30 t6, 31 mepc, 32 mstatus.
 */

freertos_trap_entry:
    addi sp, sp, -12
    sw t0, 0(sp)
    sw t1, 4(sp)
    sw t2, 8(sp)

    csrr t1, mcause
    nop
    nop
    li t2, 0x80000007
    beq t1, t2, 1f
    li t2, 0x0000000b
    beq t1, t2, 1f
    li t2, 0x80000003
    beq t1, t2, 1f
    addi sp, sp, 12
0:
    j 0b

1:
    addi sp, sp, -132
    sw ra, 0(sp)
    addi t0, sp, 144
    sw t0, 4(sp)
    sw gp, 8(sp)
    sw tp, 12(sp)
    lw t0, 132(sp)
    nop
    nop
    sw t0, 16(sp)
    lw t0, 136(sp)
    nop
    nop
    sw t0, 20(sp)
    lw t0, 140(sp)
    nop
    nop
    sw t0, 24(sp)
    sw s0, 28(sp)
    sw s1, 32(sp)
    sw a0, 36(sp)
    sw a1, 40(sp)
    sw a2, 44(sp)
    sw a3, 48(sp)
    sw a4, 52(sp)
    sw a5, 56(sp)
    sw a6, 60(sp)
    sw a7, 64(sp)
    sw s2, 68(sp)
    sw s3, 72(sp)
    sw s4, 76(sp)
    sw s5, 80(sp)
    sw s6, 84(sp)
    sw s7, 88(sp)
    sw s8, 92(sp)
    sw s9, 96(sp)
    sw s10, 100(sp)
    sw s11, 104(sp)
    sw t3, 108(sp)
    sw t4, 112(sp)
    sw t5, 116(sp)
    sw t6, 120(sp)
    csrr t0, mepc
    nop
    nop
    csrr t1, mcause
    nop
    nop
    li t2, 0x0000000b
    bne t1, t2, 4f
    addi t0, t0, 4
4:
    sw t0, 124(sp)
    csrr t0, mstatus
    nop
    nop
    ori t0, t0, 0x88
    sw t0, 128(sp)

    lui t0, %hi(pxCurrentTCB)
    nop
    nop
    addi t0, t0, %lo(pxCurrentTCB)
    nop
    nop
    lw t1, 0(t0)
    nop
    nop
    sw sp, 0(t1)

    csrr t0, mcause
    nop
    nop
    li t1, 0x80000007
    bne t0, t1, 2f

    call vPortSetupTimerInterrupt
    call xTaskIncrementTick
    beqz a0, 3f
2:
    call vTaskSwitchContext
3:
    j freertos_restore_context

freertos_restore_first_context:
freertos_restore_context:
    lui t0, %hi(pxCurrentTCB)
    nop
    nop
    addi t0, t0, %lo(pxCurrentTCB)
    nop
    nop
    lw t1, 0(t0)
    nop
    nop
    nop
    nop
    lw t0, 0(t1)
    nop
    nop
    nop
    nop

    lw t1, 128(t0)
    nop
    nop
    li t2, -9
    and t1, t1, t2
    ori t1, t1, 0x80
    csrw mstatus, t1
    lw t1, 124(t0)
    nop
    nop
    csrw mepc, t1

    lw ra, 0(t0)
    nop
    nop
    lw gp, 8(t0)
    nop
    nop
    lw tp, 12(t0)
    nop
    nop
    lw s0, 28(t0)
    nop
    nop
    lw s1, 32(t0)
    nop
    nop
    lw a1, 40(t0)
    nop
    nop
    lw a2, 44(t0)
    nop
    nop
    lw a3, 48(t0)
    nop
    nop
    lw a4, 52(t0)
    nop
    nop
    lw a5, 56(t0)
    nop
    nop
    lw a6, 60(t0)
    nop
    nop
    lw a7, 64(t0)
    nop
    nop
    lw s2, 68(t0)
    nop
    nop
    lw s3, 72(t0)
    nop
    nop
    lw s4, 76(t0)
    nop
    nop
    lw s5, 80(t0)
    nop
    nop
    lw s6, 84(t0)
    nop
    nop
    lw s7, 88(t0)
    nop
    nop
    lw s8, 92(t0)
    nop
    nop
    lw s9, 96(t0)
    nop
    nop
    lw s10, 100(t0)
    nop
    nop
    lw s11, 104(t0)
    nop
    nop
    lw t3, 108(t0)
    nop
    nop
    lw t4, 112(t0)
    nop
    nop
    lw t5, 116(t0)
    nop
    nop
    lw t6, 120(t0)
    nop
    nop
    lw t1, 20(t0)
    nop
    nop
    lw t2, 24(t0)
    nop
    nop
    lw sp, 4(t0)
    nop
    nop
    lw a0, 36(t0)
    nop
    nop
    lw t0, 16(t0)
    nop
    nop
    mret
