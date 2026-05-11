.section .text.start
.globl _start

_start:
    # FIX-B: Dùng __stack_top symbol từ linker, không hardcode địa chỉ.
    # __stack_top = 0x10002000 (top of DMEM_STACK, resolve lúc link).
    # FIX-STACK v2.7: KHÔNG addi -16. _start không return nên không
    # cần frame riêng. main() tự push frame của nó từ 0x10002000 xuống.
    # First push của main(): sp-32 = 0x10001FE0, sw ra,28 = 0x10001FFC. OK.
    la   sp, __stack_top
    nop
    nop

    # Set trap vector early
    la   t0, trap_handler
    csrw mtvec, t0

    # Copy .data từ ROM (LMA) sang DMEM_DATA (VMA)
    la   t0, __data_load
    la   t1, __data_start
    la   t2, __data_end
    beq  t1, t2, _copy_done
_copy_data:
    bge  t1, t2, _copy_done
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    _copy_data
_copy_done:

    # Clear .bss (chỉ trong DMEM_DATA, __bss_end <= 0x10000800)
    # FIX-A: Guard zone đảm bảo vòng lặp này không thể chạm vào stack.
    la   t0, __bss_start
    la   t1, __bss_end
_clear_bss:
    bge  t0, t1, _bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    _clear_bss

_bss_done:
    call main

_halt:
    j _halt

.weak trap_handler
trap_handler:
    j trap_handler

.end
