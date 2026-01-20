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
NO_CRT0=0           # NEW: Disable C runtime startup
OPTIMIZE=""         # NEW: Optimization level
MEM_SIZE=1024       # NEW: Memory size in words
KEEP_TEMP=0         # NEW: Keep temporary files

usage() {
    cat << EOF
${GREEN}RISC-V C to HEX Compiler${NC}
Usage: $0 -i <input.c|input.s> [OPTIONS]

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

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   RISC-V C/ASM to HEX Compiler        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Input:${NC}       $INPUT_FILE"
echo -e "${BLUE}Output:${NC}      $OUTPUT_HEX"
echo -e "${BLUE}Type:${NC}        $([ "$EXT" = "c" ] && echo "C source" || echo "Assembly")"
echo -e "${BLUE}CRT0:${NC}        $([ $NO_CRT0 -eq 1 ] && echo "Disabled (bare-metal)" || echo "Enabled")"
echo -e "${BLUE}Optimize:${NC}    ${OPTIMIZE:-None}"
echo -e "${BLUE}Mem Size:${NC}    $MEM_SIZE words ($((MEM_SIZE * 4)) bytes)"
echo ""

# ============================================================================
# Step 1: Create minimal linker script (NO .bss clearing!)
# ============================================================================
echo -e "${YELLOW}[1/6] Creating linker script...${NC}"

cat > linker_minimal.ld << 'LINKER_EOF'
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x00001000, LENGTH = 4K
}

SECTIONS {
    . = 0x00000000;
    
    .text : {
        *(.text.start)
        *(.text*)
        *(.rodata*)
    } > ROM
    
    .data : {
        *(.data*)
    } > RAM AT > ROM
    
    /* CRITICAL: Small .bss to reduce zero-fill time */
    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        . = . + 64;  /* Only 64 bytes = 16 words to clear */
        __bss_end = .;
    } > RAM
    
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.riscv.attributes)
    }
}
LINKER_EOF

echo -e "${GREEN}✓ Linker script: linker_minimal.ld${NC}"

# ============================================================================
# Step 2: Create startup file based on mode
# ============================================================================
echo -e "${YELLOW}[2/6] Creating startup code...${NC}"

if [ $NO_CRT0 -eq 1 ]; then
    # Bare-metal: NO crt0, direct execution
    cat > startup_generated.s << 'STARTUP_EOF'
.section .text.start
.globl _start

_start:
    # Minimal setup: Just set stack pointer
    la sp, __stack_top
    
    # Jump directly to main
    call main
    
    # Halt loop
_halt:
    j _halt

.section .data
__stack_top:
    .word 0x2000  # Stack at 8KB

.end
STARTUP_EOF
    echo -e "${GREEN}✓ Bare-metal startup (no .bss clearing)${NC}"
else
    # Standard crt0: Clear .bss section
    cat > startup_generated.s << 'STARTUP_EOF'
.section .text.start
.globl _start

_start:
    # Setup stack
    la sp, __stack_top
    
    # Clear .bss section (OPTIMIZED: only 64 bytes)
    la t0, __bss_start
    la t1, __bss_end
_clear_bss:
    bge t0, t1, _bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j _clear_bss
    
_bss_done:
    # Call main
    call main
    
    # Halt after main returns
_halt:
    j _halt

.section .data
__stack_top:
    .word 0x2000

.end
STARTUP_EOF
    echo -e "${GREEN}✓ Standard startup (64-byte .bss)${NC}"
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
        -T linker_minimal.ld
        $OPTIMIZE
        -o "$ELF_FILE"
        "$INPUT_FILE"
        startup_generated.s
    )
    
    if [ $VERBOSE -eq 1 ]; then
        echo "Command: riscv64-unknown-elf-gcc ${COMPILE_FLAGS[*]}"
    fi
    
    riscv64-unknown-elf-gcc "${COMPILE_FLAGS[@]}"
    
    # Generate assembly listing
    riscv64-unknown-elf-gcc -S -march=rv32im -mabi=ilp32 $OPTIMIZE \
        -fverbose-asm -o "$ASM_FILE" "$INPUT_FILE" 2>/dev/null || true
    
elif [ "$EXT" = "s" ] || [ "$EXT" = "S" ]; then
    # Assembly compilation
    if [ $NO_CRT0 -eq 1 ]; then
        # Direct assembly, no startup
        riscv64-unknown-elf-as -march=rv32im -o "${BASE_NAME}.o" "$INPUT_FILE"
        riscv64-unknown-elf-ld -T linker_minimal.ld -o "$ELF_FILE" "${BASE_NAME}.o"
    else
        # Assembly with startup
        riscv64-unknown-elf-gcc \
            -march=rv32im -mabi=ilp32 \
            -nostdlib -nostartfiles \
            -T linker_minimal.ld \
            -o "$ELF_FILE" \
            "$INPUT_FILE" startup_generated.s
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
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Statistics                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"

FILE_SIZE=$(stat -c%s "$BIN_FILE" 2>/dev/null || stat -f%z "$BIN_FILE")
FINAL_LINES=$(wc -l < "$OUTPUT_HEX")

echo -e "${BLUE}Binary size:${NC}      $FILE_SIZE bytes"
echo -e "${BLUE}Instructions:${NC}    $ACTUAL_LINES (actual)"
echo -e "${BLUE}HEX lines:${NC}       $FINAL_LINES (in output)"
echo -e "${BLUE}Memory usage:${NC}    $(awk "BEGIN {printf \"%.1f\", $ACTUAL_LINES/$MEM_SIZE*100}")%"

# Show disassembly preview
if [ $VERBOSE -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}═══ First 15 Instructions ═══${NC}"
    head -40 "$DUMP_FILE" | grep -E "^\s*[0-9a-f]+:" | head -15
    
    echo ""
    echo -e "${YELLOW}═══ First 10 HEX Words ═══${NC}"
    head -10 "$OUTPUT_HEX" | nl -w2 -s": "
    
    if [ -f "$ASM_FILE" ]; then
        echo ""
        echo -e "${YELLOW}═══ Generated Assembly ═══${NC}"
        echo "See: $ASM_FILE"
    fi
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
              linker_minimal.ld startup_generated.s
        echo -e "${GREEN}✓ Cleaned up${NC}"
    fi
else
    echo -e "${BLUE}Keeping temporary files (-k flag)${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    ✓ Compilation Successful!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo -e "${BLUE}Ready to use:${NC} $OUTPUT_HEX"
echo -e "${BLUE}Disassembly:${NC}  $DUMP_FILE"
[ -f "$ASM_FILE" ] && echo -e "${BLUE}Assembly:${NC}     $ASM_FILE"