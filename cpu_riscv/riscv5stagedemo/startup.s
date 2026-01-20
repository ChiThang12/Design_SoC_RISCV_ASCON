.section .text.init
.global _start

_start:
    # Initialize stack pointer
    li sp, 0x1400           # Stack at end of data memory (0x1000 + 0x400)
    
    # Clear .bss section
    li a0, 0x1000           # __bss_start (approximate)
    li a1, 0x1400           # __bss_end
    
clear_bss:
    bge a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j clear_bss
    
bss_done:
    # Call main function
    call main
    
    # Halt after main returns
_halt:
    j _halt

.global _exit
_exit:
    j _halt
