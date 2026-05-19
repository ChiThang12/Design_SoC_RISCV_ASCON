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

    call main

_halt:
    j _halt

.weak trap_handler
trap_handler:
    j trap_handler

.end
