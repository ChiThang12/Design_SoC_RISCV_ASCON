OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    /* SoC Memory Map - CRITICAL! */
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K   /* IMEM: Instruction memory */
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K   /* DMEM: Data memory */
}

SECTIONS {
    /* ===== CODE SECTION (in ROM) ===== */
    . = 0x00000000;
    
    .text : {
        *(.text.start)      /* Startup code first */
        *(.text*)           /* Program code */
        *(.rodata*)         /* Read-only data */
        . = ALIGN(4);
    } > ROM
    
    _etext = .;
    
    /* ===== DATA SECTION (in RAM, loaded from ROM) ===== */
    .data : AT(_etext) {
        . = ALIGN(4);
        _sdata = .;
        __data_start = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
        __data_end = .;
    } > RAM
    
    /* ===== BSS SECTION (in RAM, zero-initialized) ===== */
    .bss : {
        . = ALIGN(4);
        _sbss = .;
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        . = . + 256;  /* Reserve 256 bytes for .bss */
        _ebss = .;
        __bss_end = .;
    } > RAM
    
    /* ===== STACK (at top of 64KB RAM) ===== */
    . = 0x10010000;  /* 64KB from RAM base */
    __stack_top = .;
    
    /* ===== DISCARD UNNECESSARY SECTIONS ===== */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.riscv.attributes)
        *(.eh_frame*)
    }
}

/* Provide symbols for C runtime */
PROVIDE(__global_pointer$ = _sdata + 0x800);
PROVIDE(_end = .);
PROVIDE(end = .);
