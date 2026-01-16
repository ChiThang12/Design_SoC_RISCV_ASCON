#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INPUT_FILE=""
OUTPUT_HEX="program.hex"
VERBOSE=0
NO_PADDING=0  # NEW: Option to disable padding

usage() {
    echo "Usage: $0 -i <input.c> [-o <output.hex>] [-n] [-v]"
    echo ""
    echo "Options:"
    echo "  -i <input.c>     Input C source file (required)"
    echo "  -o <output.hex>  Output hex file (default: program.hex)"
    echo "  -n               No padding (only actual instructions)"
    echo "  -v               Verbose mode"
    exit 1
}

while getopts "i:o:nvh" opt; do
    case $opt in
        i) INPUT_FILE="$OPTARG" ;;
        o) OUTPUT_HEX="$OPTARG" ;;
        n) NO_PADDING=1 ;;
        v) VERBOSE=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file not specified${NC}"
    usage
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file '$INPUT_FILE' not found${NC}"
    exit 1
fi

if ! command -v riscv64-unknown-elf-gcc &> /dev/null; then
    echo -e "${RED}Error: RISC-V toolchain not found${NC}"
    exit 1
fi

echo -e "${GREEN}=== RISC-V C to HEX Compiler ===${NC}"
echo "Input:  $INPUT_FILE"
echo "Output: $OUTPUT_HEX"
echo ""

BASE_NAME=$(basename "$INPUT_FILE" .c)
ELF_FILE="${BASE_NAME}.elf"
BIN_FILE="${BASE_NAME}.bin"
DUMP_FILE="${BASE_NAME}.dump"

# Step 1: Compile
echo -e "${YELLOW}[1/5] Compiling C to ELF...${NC}"
riscv64-unknown-elf-gcc \
    -march=rv32im \
    -mabi=ilp32 \
    -nostdlib \
    -nostartfiles \
    -T linker.ld \
    -o "$ELF_FILE" \
    "$INPUT_FILE" \
    startup.s

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Compilation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ELF file created: $ELF_FILE${NC}"

# Step 2: Disassembly
echo -e "${YELLOW}[2/5] Generating disassembly...${NC}"
riscv64-unknown-elf-objdump -d "$ELF_FILE" > "$DUMP_FILE"
echo -e "${GREEN}✓ Disassembly saved: $DUMP_FILE${NC}"

# Step 3: Extract binary
echo -e "${YELLOW}[3/5] Extracting binary...${NC}"
riscv64-unknown-elf-objcopy -O binary "$ELF_FILE" "$BIN_FILE"
echo -e "${GREEN}✓ Binary file created: $BIN_FILE${NC}"

# Step 4: Convert to HEX
echo -e "${YELLOW}[4/5] Converting to HEX format...${NC}"

python3 << PYTHON_EOF > "$OUTPUT_HEX"
with open("$BIN_FILE", "rb") as f:
    data = f.read()
    for i in range(0, len(data), 4):
        if i + 4 <= len(data):
            word = data[i:i+4]
            hex_str = ''.join(f'{b:02x}' for b in reversed(word))
            print(hex_str)
        elif i < len(data):
            remaining = data[i:]
            padded = remaining + b'\x00' * (4 - len(remaining))
            hex_str = ''.join(f'{b:02x}' for b in reversed(padded))
            print(hex_str)
PYTHON_EOF

# Pad to 1024 lines (optional)
if [ $NO_PADDING -eq 0 ]; then
    LINES=$(wc -l < "$OUTPUT_HEX")
    if [ $LINES -lt 1024 ]; then
        echo "Padding to 1024 instructions..."
        for i in $(seq $((LINES + 1)) 1024); do
            echo "00000013" >> "$OUTPUT_HEX"
        done
    fi
fi

echo -e "${GREEN}✓ HEX file created: $OUTPUT_HEX${NC}"

# Step 5: Statistics
echo -e "${YELLOW}[5/5] Statistics:${NC}"
FILE_SIZE=$(stat -c%s "$BIN_FILE" 2>/dev/null || stat -f%z "$BIN_FILE")
INSTR_COUNT=$((FILE_SIZE / 4))
HEX_LINES=$(wc -l < "$OUTPUT_HEX")
echo "  Binary size:     $FILE_SIZE bytes"
echo "  Instructions:    $INSTR_COUNT (actual)"
echo "  HEX lines:       $HEX_LINES"

if [ $VERBOSE -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}First 10 instructions from disassembly:${NC}"
    head -30 "$DUMP_FILE" | grep ":" | head -10
    echo ""
    echo -e "${YELLOW}First 10 lines of HEX file:${NC}"
    head -10 "$OUTPUT_HEX"
fi

read -p "Delete temporary files? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$ELF_FILE" "$BIN_FILE"
    echo -e "${GREEN}Temporary files deleted${NC}"
fi

echo ""
echo -e "${GREEN}=== Compilation successful! ===${NC}"
echo "Ready to use: $OUTPUT_HEX"