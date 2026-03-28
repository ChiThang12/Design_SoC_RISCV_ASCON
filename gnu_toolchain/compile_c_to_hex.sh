#!/usr/bin/env bash
# compile_c_to_hex.sh  --  RISC-V C/ASM to HEX  (v2.7)
#
# THAY ĐỔI v2.7 (so với v2.6):
# ============================================================================
#
# FIX-STACK v2.7 (CRITICAL — Root Cause DECERR trên TB có DMEM 4KB):
#   v2.6/v2.5 sinh crt0 với `addi sp, sp, -16` sau `la sp, __stack_top`.
#   Hậu quả:
#     sp vào main() = 0x10001FF0
#     main() push frame: addi sp, sp, -32 → sp = 0x10001FD0
#     sw ra, 28(sp) → store tại 0x10001FEC
#   Trên TB 5M×12S với DMEM chỉ map đến 0x10000FFF (4KB):
#     0x10001FEC > 0x10000FFF → DECERR → ra bị corrupt → PC = 0xffffff00
#     → ICache fetch 0xffffff00 → DECERR → watchdog timeout.
#   (Trên soc_top.v với DMEM 8KB = 0x10001FFF thì vẫn OK, nên bug ẩn.)
#
#   FIX: Xóa `addi sp, sp, -16` khỏi cả hai block crt0 (bare + full).
#     _start KHÔNG return → không cần frame của riêng nó.
#     Sau fix:
#       sp vào main() = 0x10002000
#       main() push: sp - 32 = 0x10001FE0
#       sw ra, 28(sp) = 0x10001FFC ← trong DMEM cả 4KB lẫn 8KB. OK.
#
# Không thay đổi nào khác so với v2.6.
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

INPUT_FILE=""
OUTPUT_HEX="program.hex"
VERBOSE=0
NO_PADDING=0
NO_CRT0=0
OPTIMIZE=""
MEM_SIZE=2048
KEEP_TEMP=0

# FIX-B + FIX-E: Stack top đúng = cuối DMEM_STACK = 0x10002000
STACK_TOP=0x10002000

usage() {
    cat << EOF
${GREEN}RISC-V C to HEX Compiler  --  SoC v3.0 (v2.5)${NC}
Usage: $0 -i <input.c|input.s> [OPTIONS]

${YELLOW}Required:${NC}
  -i <file>        Input C source or Assembly file

${YELLOW}Optional:${NC}
  -o <file>        Output hex file (default: program.hex)
  -O <level>       Optimization: 0, 1, 2, 3, s (default: 0)
                   QUAN TRỌNG: luôn dùng -O 0 cho firmware MMIO
  -n               No padding with NOPs
  -c               No .bss clear in startup (bare-metal, _start only)
  -m <size>        Memory size in words (default: 2048 = 8KB IMEM)
  -k               Keep temporary files
  -v               Verbose mode
  -h               Show this help

${YELLOW}Address Map (SoC v3.0):${NC}
  ROM  S0  IMEM     0x0000_0000   8KB
  RAM  S1  DMEM     0x1000_0000   8KB
    DMEM_DATA        0x1000_0000   2KB  (data + bss)
    GUARD ZONE       0x1000_0800   2KB  (unmapped)
    DMEM_STACK       0x1000_1000   4KB  (stack)
  S2   ASCON        0x2000_0000   4KB
  S3   SoC Ctrl     0x3000_0000   4KB
  S4   CLINT        0x4000_0000  64KB
  Stack top         0x1000_2000  (top of DMEM_STACK)
EOF
    exit 1
}

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

if [ -z "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file not specified${NC}"; usage
fi
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: File '$INPUT_FILE' not found${NC}"; exit 1
fi
if ! command -v riscv64-unknown-elf-gcc &> /dev/null; then
    echo -e "${RED}Error: RISC-V toolchain not found${NC}"
    echo "Install: sudo apt install gcc-riscv64-unknown-elf"
    exit 1
fi

EXT="${INPUT_FILE##*.}"
BASE_NAME=$(basename "$INPUT_FILE" .$EXT)
ELF_FILE="${BASE_NAME}.elf"
BIN_FILE="${BASE_NAME}.bin"
DUMP_FILE="${BASE_NAME}.dump"
ASM_FILE="${BASE_NAME}.s"
MAP_FILE="${BASE_NAME}.map"

# FIX-D: trap EXIT để cleanup luôn chạy dù exit code là gì
TEMP_FILES=(linker_minimal.ld startup_generated.s "$ELF_FILE" "$BIN_FILE" "${BASE_NAME}.o")
[ "$EXT" = "c" ] && TEMP_FILES+=("$ASM_FILE")

cleanup() {
    if [ "$KEEP_TEMP" -eq 0 ]; then
        for f in "${TEMP_FILES[@]}"; do rm -f "$f"; done
    fi
}
trap cleanup EXIT

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   RISC-V C/ASM to HEX  v2.7           ║${NC}"
echo -e "${GREEN}║   SoC v3.0  --  5Mx12S crossbar       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Input:${NC}       $INPUT_FILE"
echo -e "${BLUE}Output:${NC}      $OUTPUT_HEX"
echo -e "${BLUE}Optimize:${NC}    ${OPTIMIZE:--O0}"
if [ "${OPTIMIZE}" = "-Os" ] || [ "${OPTIMIZE}" = "-O2" ] || [ "${OPTIMIZE}" = "-O3" ]; then
    echo -e "${RED}[WARN] ${OPTIMIZE} có thể làm GCC fold địa chỉ MMIO!${NC}"
fi
echo -e "${BLUE}Mem Size:${NC}    $MEM_SIZE words ($((MEM_SIZE * 4)) bytes IMEM)"
echo ""

# ============================================================================
# Step 1: Linker script
# FIX-A: Tách RAM thành DMEM_DATA + DMEM_STACK với guard zone 4KB.
#        Thêm ASSERT để bắt lỗi layout lúc link thay vì lúc sim.
# ============================================================================
echo -e "${YELLOW}[1/6] Creating linker script...${NC}"

cat > linker_minimal.ld << 'LINKER_EOF'
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
    DMEM_STACK (rwx) : ORIGIN = 0x10001000, LENGTH = 4K
}

SECTIONS {
    . = 0x00000000;

    .text : {
        *(.text.start)
        *(.text*)
        . = ALIGN(4);
        *(.rodata*)
        *(.srodata*)
        *(.sdata2*)
        . = ALIGN(4);
    } > ROM

    __data_load = LOADADDR(.data);

    .data : {
        __data_start = .;
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
ASSERT(__stack_top == 0x10002000,
    "ERROR: __stack_top != 0x10002000 — kiem tra DMEM_STACK LENGTH (phai = 4K).")
ASSERT(__bss_end <= __stack_bottom,
    "ERROR: BSS/data tran vao vung stack!")
LINKER_EOF

echo -e "${GREEN}✓ Linker script: linker_minimal.ld${NC}"
echo -e "${GREEN}  DMEM_DATA  : 0x10000000 – 0x100007FF (2KB, data+bss)${NC}"
echo -e "${GREEN}  GUARD ZONE : 0x10000800 – 0x10000FFF (2KB, unmapped)${NC}"
echo -e "${GREEN}  DMEM_STACK : 0x10001000 – 0x10001FFF (4KB, stack)${NC}"
echo -e "${GREEN}  __stack_top: 0x10002000 (first push=0x10001FFC, in DMEM)${NC}"

# ============================================================================
# Step 2: Startup code
# FIX-B: Dùng `la sp, __stack_top` thay vì `li sp, 0x10001F00`.
#        Linker resolve __stack_top = 0x10002000 đúng từ .stack section.
# FIX-STACK v2.7: XÓA `addi sp, sp, -16`.
#   _start KHÔNG return → không cần caller frame riêng.
#   addi -16 làm sp vào main() = 0x10001FF0.
#   main() push thêm -32 → sp = 0x10001FD0.
#   Trên TB có DMEM chỉ 4KB (0x10000000..0x10000FFF):
#     sw ra, 28(sp) = 0x10001FEC → DECERR → PC corrupt → 0xffffff00.
#   Sau fix: sp vào main() = 0x10002000, push -32 → sp = 0x10001FE0,
#   sw ra, 28(sp) = 0x10001FFC → trong DMEM mọi topology. OK.
# ============================================================================
echo -e "${YELLOW}[2/6] Creating startup code...${NC}"

if [ $NO_CRT0 -eq 1 ]; then
    # Bare-metal: không clear .bss, không copy .data
    cat > startup_generated.s << 'STARTUP_EOF'
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

    call main

_halt:
    j _halt

.end
STARTUP_EOF
    echo -e "${GREEN}✓ Bare-metal startup (no .bss clear, no .data copy)${NC}"
    echo -e "${GREEN}  sp = __stack_top = 0x10002000 (FIX-STACK v2.7: no -16 offset)${NC}"

else
    # Full crt0: copy .data từ ROM sang RAM, clear .bss
    cat > startup_generated.s << 'STARTUP_EOF'
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

    # Copy .data từ ROM (LMA) sang DMEM_DATA (VMA)
    la   t0, __data_load
    la   t1, __data_start
    la   t2, __data_end
    beq  t1, t2, _copy_done
_copy_data:
    bge  t1, t2, _copy_done
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    _copy_data
_copy_done:

    # Clear .bss (chỉ trong DMEM_DATA, __bss_end <= 0x10000800)
    # FIX-A: Guard zone đảm bảo vòng lặp này không thể chạm vào stack.
    la   t0, __bss_start
    la   t1, __bss_end
_clear_bss:
    bge  t0, t1, _bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    _clear_bss

_bss_done:
    call main

_halt:
    j _halt

.end
STARTUP_EOF
    echo -e "${GREEN}✓ Full crt0 startup (.data copy + .bss clear + _halt)${NC}"
    echo -e "${GREEN}  sp = __stack_top = 0x10002000 (FIX-STACK v2.7: no -16 offset)${NC}"
    echo -e "${GREEN}  .bss clear range: __bss_start .. __bss_end (max 0x10000800)${NC}"
fi

# ============================================================================
# Step 3: Compile
# ============================================================================
echo -e "${YELLOW}[3/6] Compiling...${NC}"

COMMON_FLAGS=(
    -march=rv32im
    -mabi=ilp32
    -mno-relax
    -misa-spec=20191213
    -fno-pic
    -fno-common
    -ffreestanding
    -nostdlib
    -nostartfiles
    -T linker_minimal.ld
    -Wl,-Map,"$MAP_FILE"
    ${OPTIMIZE:--O0}
    -fno-tree-dce
    -fno-tree-dse
    -fno-tree-fre
    -fno-ipa-pure-const
)

if [ "$EXT" = "c" ]; then
    COMPILE_FLAGS=(
        "${COMMON_FLAGS[@]}"
        -o "$ELF_FILE"
        "$INPUT_FILE"
        startup_generated.s
    )
    [ $VERBOSE -eq 1 ] && echo -e "${CYAN}Command: riscv64-unknown-elf-gcc ${COMPILE_FLAGS[*]}${NC}"
    riscv64-unknown-elf-gcc "${COMPILE_FLAGS[@]}"

    riscv64-unknown-elf-gcc \
        -S -march=rv32im -mabi=ilp32 -mno-relax -misa-spec=20191213 \
        ${OPTIMIZE:--O0} -ffreestanding \
        -fverbose-asm -o "$ASM_FILE" "$INPUT_FILE" 2>/dev/null || true

elif [ "$EXT" = "s" ] || [ "$EXT" = "S" ]; then
    if [ $NO_CRT0 -eq 1 ]; then
        riscv64-unknown-elf-gcc \
            "${COMMON_FLAGS[@]}" \
            -o "$ELF_FILE" \
            "$INPUT_FILE"
    else
        riscv64-unknown-elf-gcc \
            "${COMMON_FLAGS[@]}" \
            -o "$ELF_FILE" \
            "$INPUT_FILE" startup_generated.s
    fi
else
    echo -e "${RED}Error: Unsupported file type: $EXT${NC}"; exit 1
fi

echo -e "${GREEN}✓ ELF created: $ELF_FILE${NC}"

# ── Sanity checks ────────────────────────────────────────────────────────────

# .data VMA phải nằm trong DMEM_DATA (0x10000xxx)
DATA_VMA=$(riscv64-unknown-elf-objdump -h "$ELF_FILE" 2>/dev/null \
    | awk '/.data/ {print $4; exit}')
if [ -n "$DATA_VMA" ] && [ "$DATA_VMA" != "00000000" ]; then
    if [[ ! "$DATA_VMA" == 10000* ]]; then
        echo -e "${RED}[WARN] .data VMA = 0x${DATA_VMA} -- không ở DMEM_DATA!${NC}"
    else
        echo -e "${GREEN}  ✓ .data VMA = 0x${DATA_VMA} (DMEM_DATA — OK)${NC}"
    fi
fi

# FIX-C: Check ngưỡng đúng = 0x10000800 (end of DMEM_DATA), không phải STACK_TOP
BSS_END_HEX=$(riscv64-unknown-elf-nm "$ELF_FILE" 2>/dev/null \
    | awk '/__bss_end/ {print $1; exit}')
if [ -n "$BSS_END_HEX" ]; then
    BSS_END_DEC=$((16#$BSS_END_HEX))
    DMEM_DATA_END=$((16#10000800))   # FIX-C: ngưỡng đúng
    DMEM_END_DEC=$((16#10002000))
    GAP_BYTES=$(( DMEM_DATA_END - BSS_END_DEC ))
    if [ "$BSS_END_DEC" -gt "$DMEM_DATA_END" ]; then
        echo -e "${RED}[!!!] __bss_end = 0x${BSS_END_HEX} TRAN QUA DMEM_DATA (max 0x10000800)!${NC}"
        echo -e "${RED}      Tang DMEM_DATA LENGTH hoac giam bien global.${NC}"
        exit 1
    elif [ "$BSS_END_DEC" -gt "$DMEM_END_DEC" ]; then
        echo -e "${RED}[!!!] __bss_end = 0x${BSS_END_HEX} NGOAI DMEM!${NC}"
        exit 1
    else
        echo -e "${GREEN}  ✓ __bss_end = 0x${BSS_END_HEX} (DMEM_DATA — OK, con ${GAP_BYTES} byte den guard)${NC}"
    fi
fi

# __stack_top phải là 0x10002000
STACK_TOP_HEX=$(riscv64-unknown-elf-nm "$ELF_FILE" 2>/dev/null \
    | awk '/__stack_top/ {print $1; exit}')
if [ -n "$STACK_TOP_HEX" ]; then
    if [ "$STACK_TOP_HEX" = "10002000" ]; then
        echo -e "${GREEN}  ✓ __stack_top = 0x${STACK_TOP_HEX} (first push=0x10001FFC, in DMEM — OK)${NC}"
    else
        echo -e "${RED}[!!!] __stack_top = 0x${STACK_TOP_HEX} != 0x10002000!${NC}"
        exit 1
    fi
fi

# _halt loop
HALT_ADDR=$(riscv64-unknown-elf-nm "$ELF_FILE" 2>/dev/null \
    | awk '/_halt/ {print $1; exit}')
if [ -n "$HALT_ADDR" ]; then
    echo -e "${GREEN}  ✓ _halt ở 0x${HALT_ADDR} (halt loop — OK)${NC}"
else
    echo -e "${RED}  [!!!] _halt KHÔNG tìm thấy trong ELF!${NC}"
fi

# ============================================================================
# Step 4: Disassembly
# ============================================================================
echo -e "${YELLOW}[4/6] Disassembling...${NC}"
riscv64-unknown-elf-objdump -d -M numeric,no-aliases "$ELF_FILE" > "$DUMP_FILE"
echo -e "${GREEN}✓ Disassembly: $DUMP_FILE${NC}"

# ============================================================================
# Step 5: Extract binary
# ============================================================================
echo -e "${YELLOW}[5/6] Extracting binary...${NC}"

riscv64-unknown-elf-objcopy \
    --remove-section=.bss       \
    --remove-section=.sbss      \
    --remove-section=.comment   \
    --remove-section=".note*"   \
    --remove-section=".debug*"  \
    -O binary "$ELF_FILE" "$BIN_FILE"

BIN_SIZE=$(stat -c%s "$BIN_FILE" 2>/dev/null || stat -f%z "$BIN_FILE")
echo -e "${GREEN}✓ Binary: $BIN_FILE  ($BIN_SIZE bytes = $((BIN_SIZE/4)) words)${NC}"

if [ $((BIN_SIZE / 4)) -gt $MEM_SIZE ]; then
    echo -e "${RED}[!!!] Binary ($((BIN_SIZE/4)) words) > IMEM ($MEM_SIZE words)!${NC}"
    echo -e "${RED}      Dùng -O s hoặc tăng -m${NC}"
    exit 1
fi

# ============================================================================
# Step 6: Convert to HEX + padding
# ============================================================================
echo -e "${YELLOW}[6/6] Converting to HEX...${NC}"

python3 - << PYTHON_EOF
import sys

with open("$BIN_FILE", "rb") as f:
    data = f.read()

lines = []
for i in range(0, len(data), 4):
    chunk = data[i:i+4]
    chunk = chunk + b'\x00' * (4 - len(chunk))
    word = int.from_bytes(chunk, byteorder='little')
    lines.append(f"{word:08x}")

actual   = len(lines)
mem_size = $MEM_SIZE
no_pad   = $NO_PADDING

if not no_pad and actual < mem_size:
    lines.extend(["00000013"] * (mem_size - actual))
    print(f"  Padding: {actual} -> {mem_size} words (NOPs)", file=sys.stderr)
else:
    print(f"  No padding needed ({actual} words)", file=sys.stderr)

with open("$OUTPUT_HEX", "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"  Instructions/data : {actual} words  ({actual*4} bytes)", file=sys.stderr)
print(f"  Total HEX lines   : {len(lines)}", file=sys.stderr)
PYTHON_EOF

# ============================================================================
# Statistics
# ============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             Statistics                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"

ACTUAL_LINES=$(wc -l < "$OUTPUT_HEX")
MEM_USED_PCT=$(awk "BEGIN {printf \"%.1f\", $ACTUAL_LINES/$MEM_SIZE*100}")

echo -e "${BLUE}Binary size:${NC}     $BIN_SIZE bytes"
echo -e "${BLUE}HEX lines:${NC}       $ACTUAL_LINES"
echo -e "${BLUE}IMEM usage:${NC}      ${MEM_USED_PCT}%  ($ACTUAL_LINES / $MEM_SIZE words)"
echo -e "${BLUE}Stack top:${NC}       0x10002000  (sp vào main=0x10002000, FIX-STACK v2.7: no -16)"
echo -e "${BLUE}BSS max:${NC}         0x10000800  (DMEM_DATA end)"

# ============================================================================
# Verbose
# ============================================================================
if [ $VERBOSE -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}═══ Key Symbols ═══${NC}"
    riscv64-unknown-elf-nm "$ELF_FILE" \
        | grep -E "_start|_halt|main|__bss|__data|__stack" \
        | sort -k1 || true

    echo ""
    echo -e "${YELLOW}═══ Section Layout ═══${NC}"
    riscv64-unknown-elf-objdump -h "$ELF_FILE" \
        | grep -E "Idx|Name|\.text|\.data|\.bss|\.rodata|\.stack" || true

    echo ""
    echo -e "${YELLOW}═══ First 20 Instructions ═══${NC}"
    head -60 "$DUMP_FILE" | grep -E "^\s*[0-9a-f]+:" | head -20 || true

    echo ""
    echo -e "${YELLOW}═══ First 16 HEX Words ═══${NC}"
    head -16 "$OUTPUT_HEX" | nl -w3 -s": "
fi

# ============================================================================
# Cleanup — FIX-D: trap EXIT xử lý, nhưng hỏi user nếu interactive
# ============================================================================
if [ $KEEP_TEMP -eq 1 ]; then
    echo ""
    echo -e "${BLUE}Keeping temporary files (-k):${NC}"
    echo -e "  linker_minimal.ld  startup_generated.s  $ELF_FILE  $DUMP_FILE  $MAP_FILE"
    [ "$EXT" = "c" ] && echo -e "  $ASM_FILE"
    # Tắt trap cleanup khi -k
    trap - EXIT
else
    echo ""
    if [ -t 0 ]; then
        read -p "Delete temporary files? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            # User chọn giữ lại → tắt trap
            trap - EXIT
            echo -e "${BLUE}Kept: linker_minimal.ld startup_generated.s $ELF_FILE $DUMP_FILE $MAP_FILE${NC}"
        fi
    else
        echo -e "${BLUE}Non-interactive: auto-deleting temporary files${NC}"
        # trap EXIT sẽ chạy cleanup
    fi
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    ✓  Compilation Successful!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo -e "${BLUE}Ready:${NC}       $OUTPUT_HEX"
echo -e "${BLUE}Disassembly:${NC} $DUMP_FILE"
echo -e "${BLUE}Map file:${NC}    $MAP_FILE"
[ -f "$ASM_FILE" ] && echo -e "${BLUE}Assembly:${NC}    $ASM_FILE"