/* ============================================================================
 * linker.ld - RISC-V Linker Script
 * ============================================================================
 * Mô tả: Định nghĩa memory layout cho RISC-V processor
 * Instruction Memory: 0x00000000 - 0x00000FFF (4KB)
 * Data Memory:        0x00001000 - 0x000013FF (1KB)
 * ============================================================================
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    /* Instruction Memory (ROM) - 4KB */
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    
    /* Data Memory (RAM) - 1KB */
    DMEM (rw)  : ORIGIN = 0x00001000, LENGTH = 1K
}

SECTIONS
{
    /* Code section - goes to instruction memory */
    .text : {
        *(.text.init)      /* Startup code first */
        *(.text)           /* Main code */
        *(.text.*)         /* Other code sections */
        *(.rodata)         /* Read-only data */
        *(.rodata.*)
    } > IMEM
    
    /* Data section - goes to data memory */
    .data : {
        __data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        __data_end = .;
    } > DMEM AT > IMEM
    
    /* BSS section - uninitialized data */
    .bss : {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        __bss_end = .;
    } > DMEM
    
    /* Stack pointer (grows downward from end of RAM) */
    __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
    
    /* Discard unwanted sections */
    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}
