.section .text.start
.globl _start

_start:
    # Set stack pointer to top of RAM (0x10010000)
    lui sp, 0x10010
    
    # Jump directly to main
    call main
    
    # Infinite loop after main returns
_halt:
    # Put return value in loop for debugging
    mv   a0, a0
    j    _halt

.end
