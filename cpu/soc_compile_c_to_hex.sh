#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default options
INPUT_FILE=""
OUTPUT_HEX="program.hex"
VERBOSE=0
NO_PADDING=0
NO_CRT0=0
OPTIMIZE=""
MEM_SIZE=1024
KEEP_TEMP=0

usage() {
    cat << EOF
${GREEN}RISC-V C to HEX Compiler for SoC${NC}
${YELLOW}Memory Map:${NC}
  ROM (IMEM): 0x00000000 - 0x0FFFFFFF (256MB, read-only)
  RAM (DMEM): 0x10000000 - 0x1FFFFFFF (256MB, read-write)

${YELLOW}Usage:${NC} $0 -i <input.c|input.s> [OPTIONS]

${YELLOW}Required:${NC}
  -i <file>        Input C source or Assembly file

${YELLOW}Optional:${NC}
  -o <file>        Output hex file (default: program.hex)
  -O <level>       Optimization: 0, 1, 2, 3, s (default: none)
  -n               No padding with NOPs
  -c               No C runtime (no crt0, direct _start)
  -m <size>        Memory size in words (default: 1024)
  -k               Keep temporary files
  -v               Verbose mode
  -h               Show this help

${YELLOW}Examples:${NC}
  $0 -i main.c                        # Compile C with crt0
  $0 -i main.c -c -O2                 # No crt0, optimized
  $0 -i test.s -o test.hex -n         # Assembly without padding
  $0 -i main.c -O2 -m 512 -v          # Optimized, 512-word memory
EOF
    exit 1
}

# Parse arguments
while getopts "i:o:O:m:nckvh" opt; do
    case $opt in
        i) INPUT_FILE="$OPTARG" ;;
        o) OUTPUT_HEX="$OPTARG" ;;
        O) OPTIMIZE="-O$OPTARG" ;;
        m) MEM_SIZE="$OPTARG" ;;
        n) NO_PADDING=1 ;;
        c) NO_CRT0=1 ;;
        k) KEEP_TEMP=1 ;;
        v) VERBOSE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate input
if [ -z "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file not specified${NC}"
    usage
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file '$INPUT_FILE' not found${NC}"
    exit 1
fi

# Check toolchain
if ! command -v riscv64-unknown-elf-gcc &> /dev/null; then
    echo -e "${RED}Error: RISC-V toolchain not found${NC}"
    echo "Install: sudo apt install gcc-riscv64-unknown-elf"
    exit 1
fi

# File extension detection
EXT="${INPUT_FILE##*.}"
BASE_NAME=$(basename "$INPUT_FILE" .$EXT)
ELF_FILE="${BASE_NAME}.elf"
BIN_FILE="${BASE_NAME}.bin"
DUMP_FILE="${BASE_NAME}.dump"
ASM_FILE="${BASE_NAME}.s"

echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   RISC-V SoC C/ASM to HEX Compiler   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Input:${NC}       $INPUT_FILE"
echo -e "${BLUE}Output:${NC}      $OUTPUT_HEX"
echo -e "${BLUE}Type:${NC}        $([ "$EXT" = "c" ] && echo "C source" || echo "Assembly")"
echo -e "${BLUE}CRT0:${NC}        $([ $NO_CRT0 -eq 1 ] && echo "Disabled (bare-metal)" || echo "Enabled")"
echo -e "${BLUE}Optimize:${NC}    ${OPTIMIZE:-None}"
echo -e "${BLUE}Mem Size:${NC}    $MEM_SIZE words ($((MEM_SIZE * 4)) bytes)"
echo ""

# ============================================================================
# Step 1: Create SoC-compatible linker script
# ============================================================================
echo -e "${YELLOW}[1/6] Creating SoC linker script...${NC}"

cat > linker_soc.ld << 'LINKER_EOF'
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
LINKER_EOF

echo -e "${GREEN}✓ Linker script: linker_soc.ld${NC}"
if [ $VERBOSE -eq 1 ]; then
    echo -e "${BLUE}  ROM: 0x00000000 - 0x0000FFFF (64KB)${NC}"
    echo -e "${BLUE}  RAM: 0x10000000 - 0x1000FFFF (64KB)${NC}"
    echo -e "${BLUE}  Stack: 0x10010000 (top of RAM)${NC}"
fi

# ============================================================================
# Step 2: Create startup code
# ============================================================================
echo -e "${YELLOW}[2/6] Creating startup code...${NC}"

if [ $NO_CRT0 -eq 1 ]; then
    # Bare-metal: NO crt0, minimal setup
    cat > startup_soc.s << 'STARTUP_EOF'
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
STARTUP_EOF
    echo -e "${GREEN}✓ Bare-metal startup (no .bss clearing)${NC}"
else
    # Standard crt0: Initialize .bss and .data
    cat > startup_soc.s << 'STARTUP_EOF'
.section .text.start
.globl _start

_start:
    # ========================================
    # 1. Setup stack pointer (0x10010000)
    # ========================================
    lui  sp, 0x10010
    
    # ========================================
    # 2. Clear .bss section (zero-initialize)
    # ========================================
    la   t0, __bss_start
    la   t1, __bss_end
_clear_bss:
    bge  t0, t1, _bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    _clear_bss
    
_bss_done:
    # ========================================
    # 3. Copy .data section from ROM to RAM
    # (Optional - usually handled by linker)
    # ========================================
    # Skip data copy for now - linker handles it
    
    # ========================================
    # 4. Call main function
    # ========================================
    call main
    
    # ========================================
    # 5. Infinite loop after main returns
    # Return value is in a0 (x10)
    # ========================================
_halt:
    # Keep return value visible for debugging
    mv   a0, a0
    j    _halt

.end
STARTUP_EOF
    echo -e "${GREEN}✓ Standard startup with .bss init${NC}"
fi

# ============================================================================
# Step 3: Compile based on input type
# ============================================================================
echo -e "${YELLOW}[3/6] Compiling...${NC}"

if [ "$EXT" = "c" ]; then
    # C compilation
    COMPILE_FLAGS=(
        -march=rv32im
        -mabi=ilp32
        -nostdlib
        -nostartfiles
        -T linker_soc.ld
        $OPTIMIZE
        -fno-builtin
        -fno-stack-protector
        -o "$ELF_FILE"
        "$INPUT_FILE"
        startup_soc.s
    )
    
    if [ $VERBOSE -eq 1 ]; then
        echo "Command: riscv64-unknown-elf-gcc ${COMPILE_FLAGS[*]}"
    fi
    
    riscv64-unknown-elf-gcc "${COMPILE_FLAGS[@]}"
    
    # Generate assembly listing for reference
    riscv64-unknown-elf-gcc -S -march=rv32im -mabi=ilp32 $OPTIMIZE \
        -fverbose-asm -o "$ASM_FILE" "$INPUT_FILE" 2>/dev/null || true
    
elif [ "$EXT" = "s" ] || [ "$EXT" = "S" ]; then
    # Assembly compilation
    if [ $NO_CRT0 -eq 1 ]; then
        # Direct assembly, no startup
        riscv64-unknown-elf-as -march=rv32im -o "${BASE_NAME}.o" "$INPUT_FILE"
        riscv64-unknown-elf-ld -T linker_soc.ld -o "$ELF_FILE" "${BASE_NAME}.o"
    else
        # Assembly with startup
        riscv64-unknown-elf-gcc \
            -march=rv32im -mabi=ilp32 \
            -nostdlib -nostartfiles \
            -T linker_soc.ld \
            -o "$ELF_FILE" \
            "$INPUT_FILE" startup_soc.s
    fi
else
    echo -e "${RED}Error: Unsupported file type: $EXT${NC}"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Compilation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ELF created: $ELF_FILE${NC}"

# ============================================================================
# Step 4: Generate disassembly
# ============================================================================
echo -e "${YELLOW}[4/6] Disassembling...${NC}"
riscv64-unknown-elf-objdump -d -M numeric,no-aliases "$ELF_FILE" > "$DUMP_FILE"
echo -e "${GREEN}✓ Disassembly: $DUMP_FILE${NC}"

# Show memory layout
if [ $VERBOSE -eq 1 ]; then
    echo ""
    echo -e "${BLUE}Memory Layout:${NC}"
    riscv64-unknown-elf-size "$ELF_FILE"
fi

# ============================================================================
# Step 5: Extract binary
# ============================================================================
echo -e "${YELLOW}[5/6] Extracting binary...${NC}"
riscv64-unknown-elf-objcopy -O binary "$ELF_FILE" "$BIN_FILE"
echo -e "${GREEN}✓ Binary: $BIN_FILE${NC}"

# ============================================================================
# Step 6: Convert to HEX with optional padding
# ============================================================================
echo -e "${YELLOW}[6/6] Converting to HEX...${NC}"

python3 << PYTHON_EOF > "$OUTPUT_HEX"
with open("$BIN_FILE", "rb") as f:
    data = f.read()
    
    # Convert to little-endian hex words
    for i in range(0, len(data), 4):
        if i + 4 <= len(data):
            word = data[i:i+4]
            hex_str = ''.join(f'{b:02x}' for b in reversed(word))
            print(hex_str)
        elif i < len(data):
            # Partial word: pad with zeros
            remaining = data[i:]
            padded = remaining + b'\x00' * (4 - len(remaining))
            hex_str = ''.join(f'{b:02x}' for b in reversed(padded))
            print(hex_str)
PYTHON_EOF

# Padding logic
ACTUAL_LINES=$(wc -l < "$OUTPUT_HEX")

if [ $NO_PADDING -eq 0 ]; then
    if [ $ACTUAL_LINES -lt $MEM_SIZE ]; then
        echo "  Padding $ACTUAL_LINES → $MEM_SIZE words (NOPs)..."
        for i in $(seq $((ACTUAL_LINES + 1)) $MEM_SIZE); do
            echo "00000013" >> "$OUTPUT_HEX"  # NOP = addi x0, x0, 0
        done
        echo -e "${GREEN}✓ Padded with $((MEM_SIZE - ACTUAL_LINES)) NOPs${NC}"
    fi
else
    echo -e "${BLUE}  No padding (actual: $ACTUAL_LINES words)${NC}"
fi

# ============================================================================
# Statistics
# ============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Statistics                    ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"

FILE_SIZE=$(stat -c%s "$BIN_FILE" 2>/dev/null || stat -f%z "$BIN_FILE")
FINAL_LINES=$(wc -l < "$OUTPUT_HEX")

echo -e "${BLUE}Binary size:${NC}      $FILE_SIZE bytes"
echo -e "${BLUE}Instructions:${NC}    $ACTUAL_LINES (actual)"
echo -e "${BLUE}HEX lines:${NC}       $FINAL_LINES (in output)"
echo -e "${BLUE}Memory usage:${NC}    $(awk "BEGIN {printf \"%.1f\", $ACTUAL_LINES/$MEM_SIZE*100}")%"

# Show disassembly preview
if [ $VERBOSE -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}╔══ First 20 Instructions ══╗${NC}"
    head -50 "$DUMP_FILE" | grep -E "^\s*[0-9a-f]+:" | head -20
    
    echo ""
    echo -e "${YELLOW}╔══ First 10 HEX Words ══╗${NC}"
    head -10 "$OUTPUT_HEX" | nl -w2 -s": 0x"
    
    if [ -f "$ASM_FILE" ]; then
        echo ""
        echo -e "${YELLOW}╔══ Generated Assembly ══╗${NC}"
        echo "See: $ASM_FILE"
    fi
    
    # Check for critical addresses
    echo ""
    echo -e "${YELLOW}╔══ Symbol Table ══╗${NC}"
    riscv64-unknown-elf-nm "$ELF_FILE" | grep -E "(main|_start|__stack_top|__bss)" || true
fi

# ============================================================================
# Verification
# ============================================================================
echo ""
echo -e "${YELLOW}╔══ Verification ══╗${NC}"

# Check if main exists
if riscv64-unknown-elf-nm "$ELF_FILE" | grep -q " main"; then
    MAIN_ADDR=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep " main" | awk '{print $1}')
    echo -e "${GREEN}✓${NC} main() found at 0x$MAIN_ADDR"
else
    echo -e "${RED}✗${NC} main() not found!"
fi

# Check stack pointer
if riscv64-unknown-elf-nm "$ELF_FILE" | grep -q "__stack_top"; then
    STACK_ADDR=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep "__stack_top" | awk '{print $1}')
    echo -e "${GREEN}✓${NC} Stack at 0x$STACK_ADDR"
    
    # Verify stack is in RAM range
    if [[ "0x$STACK_ADDR" -ge "0x10000000" ]]; then
        echo -e "${GREEN}✓${NC} Stack in correct RAM range (0x10000000+)"
    else
        echo -e "${RED}✗${NC} Stack NOT in RAM range!"
    fi
else
    echo -e "${YELLOW}⚠${NC} Stack address not found"
fi

# Check .bss section
if riscv64-unknown-elf-nm "$ELF_FILE" | grep -q "__bss_start"; then
    BSS_START=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep "__bss_start" | awk '{print $1}')
    BSS_END=$(riscv64-unknown-elf-nm "$ELF_FILE" | grep "__bss_end" | awk '{print $1}')
    echo -e "${GREEN}✓${NC} .bss section: 0x$BSS_START - 0x$BSS_END"
fi

# ============================================================================
# Cleanup
# ============================================================================
if [ $KEEP_TEMP -eq 0 ]; then
    echo ""
    read -p "Delete temporary files? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$ELF_FILE" "$BIN_FILE" "${BASE_NAME}.o" \
              linker_soc.ld startup_soc.s
        echo -e "${GREEN}✓ Cleaned up${NC}"
    fi
else
    echo -e "${BLUE}Keeping temporary files (-k flag)${NC}"
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    ✓ Compilation Successful!          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
echo -e "${BLUE}Ready for SoC:${NC} $OUTPUT_HEX"
echo -e "${BLUE}Disassembly:${NC}   $DUMP_FILE"
[ -f "$ASM_FILE" ] && echo -e "${BLUE}Assembly:${NC}      $ASM_FILE"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Copy $OUTPUT_HEX to memory/program.hex"
echo "  2. Run simulation: vvp run_riscv_soc_top.vvp"
echo ""