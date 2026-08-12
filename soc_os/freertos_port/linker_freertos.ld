OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    ROM        (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    DMEM_DATA  (rwx) : ORIGIN = 0x10000000, LENGTH = 4K
    DMEM_STACK (rwx) : ORIGIN = 0x10001000, LENGTH = 0xFF0
}

SECTIONS {
    . = ORIGIN(ROM);

    .text : {
        *(.text.start)
        *(.text*)
        . = ALIGN(4);
    } > ROM

    __data_load = LOADADDR(.data);

    .data : {
        __data_start = .;
        *(.rodata*)
        *(.srodata*)
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        __data_end = .;
    } > DMEM_DATA AT > ROM

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM_DATA

    .stack (NOLOAD) : {
        __stack_bottom = .;
        . = . + LENGTH(DMEM_STACK);
        __stack_top = .;
    } > DMEM_STACK

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.riscv.attributes)
        *(.debug*)
    }
}

ASSERT(__bss_end <= 0x10001000, "FreeRTOS .bss/data exceeds DMEM_DATA")
ASSERT(__stack_top == 0x10001FF0, "Unexpected FreeRTOS stack top")
