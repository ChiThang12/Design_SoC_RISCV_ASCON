OUTPUT_ARCH("riscv")
ENTRY(_start)

/* ── MEMORY MAP ─────────────────────────────────────────────────────────────
 * ROM        : 0x00000000 – 0x00001FFF  (8 KB) — code + rodata
 * DMEM_DATA  : 0x10000000 – 0x100007FF  (2 KB) — .data + .bss
 * GUARD GAP  : 0x10000800 – 0x10000FFF  (2 KB) — unmapped (linker-enforced)
 * DMEM_STACK : 0x10001000 – 0x10001FFF  (4 KB) — stack (grows down)
 *
 * FIX-STACK (v2.6): DMEM_STACK ORIGIN đổi từ 0x10001800 → 0x10001000,
 * LENGTH đổi từ 2K → 4K.
 *
 * BUG cũ (v2.5): ORIGIN=0x10001800, LENGTH=2K → __stack_top = 0x10002000.
 * soc_top.v S1_MASK=0xFFFF_E000 → DMEM decode max = 0x10001FFF.
 * Push đầu tiên: sp-4 = 0x1000200C → DECERR → PC corrupt → 0xffffff00.
 *
 * FIX: ORIGIN=0x10001000, LENGTH=4K → __stack_top = 0x10002000 (SAME),
 * nhưng first push sp-4 = 0x10001FFC ← trong DMEM. Đúng.
 * Stack thực tế 4KB (0x10001000..0x10001FFF), đủ cho firmware này.
 * ─────────────────────────────────────────────────────────────────────────── */
MEMORY {
    ROM        (rx)  : ORIGIN = 0x00000000, LENGTH = 8K
    DMEM_DATA  (rwx) : ORIGIN = 0x10000000, LENGTH = 2K
    DMEM_STACK (rwx) : ORIGIN = 0x10001000, LENGTH = 0xFF0
}
SECTIONS {
    . = 0x00000000;

    /* 1. Lệnh (Instructions) ở lại ROM */
    .text : {
        *(.text.start)
        *(.text*)
        . = ALIGN(4);
    } > ROM

    __data_load = LOADADDR(.data);

    /* 2. Di chuyển Rodata xuống Data để được copy vào DMEM */
    .data : {
        __data_start = .;
        *(.rodata*)      /* DI CHUYỂN XUỐNG ĐÂY */
        *(.srodata*)     /* DI CHUYỂN XUỐNG ĐÂY */
        *(.sdata2*)      /* DI CHUYỂN XUỐNG ĐÂY */
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

    /* Stack section — chỉ để khai báo __stack_top, không có content */
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
/* ── ASSERT (FIX-STACK v2.6) ─────────────────────────────────────────────── */
ASSERT(__bss_end <= 0x10000800,
    "ERROR: .bss tran qua 2KB DMEM_DATA! Tang DMEM_DATA hoac giam bien global.")
ASSERT(__stack_bottom >= 0x10001000,
    "ERROR: __stack_bottom sai — DMEM_STACK phai bat dau tu 0x10001000.")
ASSERT(__stack_top == 0x10001FF0,
    "ERROR: __stack_top != 0x10001FF0 — kiem tra DMEM_STACK LENGTH.")
ASSERT(__bss_end <= __stack_bottom,
    "ERROR: BSS/data tran vao vung stack!")
