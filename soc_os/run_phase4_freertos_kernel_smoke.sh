#!/usr/bin/env bash
# Phase 4 real FreeRTOS-Kernel smoke runner.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_NAME="test_freertos_kernel_smoke"
BUILD_DIR="/tmp/${TEST_NAME}_build"
ELF_PATH="$BUILD_DIR/${TEST_NAME}.elf"
BIN_PATH="$BUILD_DIR/${TEST_NAME}.bin"
DUMP_PATH="$BUILD_DIR/${TEST_NAME}.dump"
MAP_PATH="$BUILD_DIR/${TEST_NAME}.map"
HEX_PATH="$ROOT_DIR/gnu_toolchain/test_os/${TEST_NAME}.hex"
VVP_PATH="/tmp/${TEST_NAME}_phase4.vvp"
LOG_PATH="$ROOT_DIR/log/${TEST_NAME}.log"
UART_DIV=16
MEM_SIZE_WORDS=2048

KERNEL_DIR="$ROOT_DIR/soc_os/FreeRTOS-Kernel"
PORT_DIR="$ROOT_DIR/soc_os/freertos_port"

echo "=============================================="
echo " Phase 4 real FreeRTOS-Kernel smoke"
echo "=============================================="

mkdir -p "$BUILD_DIR" "$ROOT_DIR/log" "$ROOT_DIR/gnu_toolchain/test_os"

cat > "$BUILD_DIR/startup_freertos.S" <<'STARTUP_EOF'
.section .text.start
.globl _start

_start:
    la   sp, __stack_top
    csrr t0, mhartid
    slli t0, t0, 11
    sub  sp, sp, t0
    nop
    nop

    la   t0, trap_handler
    csrw mtvec, t0

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

.weak trap_handler
trap_handler:
    j trap_handler
STARTUP_EOF

COMMON_FLAGS=(
    -march=rv32im_zicsr
    -mabi=ilp32
    -mno-relax
    -misa-spec=20191213
    -fno-pic
    -fno-common
    -ffreestanding
    -nostdlib
    -nostartfiles
    -fomit-frame-pointer
    -fno-strict-volatile-bitfields
    -fno-schedule-insns
    -fno-schedule-insns2
    -fno-reorder-functions
    -ffunction-sections
    -fdata-sections
    -Os
    -I "$ROOT_DIR/gnu_toolchain/include"
    -I "$PORT_DIR"
    -I "$KERNEL_DIR/include"
)

SOURCES=(
    "$ROOT_DIR/gnu_toolchain/test_os/${TEST_NAME}.c"
    "$PORT_DIR/string_shims.c"
    "$PORT_DIR/port.c"
    "$PORT_DIR/portASM.S"
    "$KERNEL_DIR/tasks.c"
    "$KERNEL_DIR/list.c"
    "$KERNEL_DIR/queue.c"
    "$BUILD_DIR/startup_freertos.S"
)

echo "=============================================="
echo " Step 1: Build firmware"
echo "=============================================="
riscv64-unknown-elf-gcc \
    "${COMMON_FLAGS[@]}" \
    -T "$PORT_DIR/linker_freertos.ld" \
    -Wl,-Map,"$MAP_PATH" \
    -Wl,--gc-sections \
    -o "$ELF_PATH" \
    "${SOURCES[@]}"

riscv64-unknown-elf-objdump -d -M numeric,no-aliases "$ELF_PATH" > "$DUMP_PATH"
riscv64-unknown-elf-objcopy \
    --remove-section=.bss \
    --remove-section=.sbss \
    --remove-section=.comment \
    --remove-section=".note*" \
    --remove-section=".debug*" \
    -O binary "$ELF_PATH" "$BIN_PATH"

python3 - <<PYTHON_EOF
import sys
from pathlib import Path

data = Path("$BIN_PATH").read_bytes()
lines = []
for i in range(0, len(data), 4):
    chunk = data[i:i + 4] + b"\\x00" * (4 - len(data[i:i + 4]))
    lines.append(f"{int.from_bytes(chunk, 'little'):08x}")

actual = len(lines)
mem_size = $MEM_SIZE_WORDS
if actual > mem_size:
    print(f"ERROR: firmware uses {actual} words > IMEM {mem_size} words", file=sys.stderr)
    sys.exit(1)
lines.extend(["00000013"] * (mem_size - actual))
Path("$HEX_PATH").write_text("\\n".join(lines) + "\\n")
print(f"  Instructions/data : {actual} words ({actual * 4} bytes)")
print(f"  Total HEX lines   : {len(lines)}")
PYTHON_EOF

echo "  Built: $HEX_PATH"
echo "  ELF:   $ELF_PATH"
echo "  MAP:   $MAP_PATH"

echo ""
echo "=============================================="
echo " Step 2: Compile simulation"
echo "=============================================="
iverilog -g2005 \
    -DLOG_LEVEL=0 \
    -DBAUD_DIV="$UART_DIV" \
    -DIMEM_INIT_FILE="\"${HEX_PATH}\"" \
    ${EXTRA_IVERILOG_DEFINES:-} \
    -o "$VVP_PATH" run_soc_ascon.v
echo "  VVP: $VVP_PATH"

echo ""
echo "=============================================="
echo " Step 3: Run simulation"
echo "=============================================="
timeout 180s vvp "$VVP_PATH" > "$LOG_PATH" 2>&1 || true

if grep -q '\*\*\* PASS.*freertos_kernel_smoke' "$LOG_PATH"; then
    echo "  RESULT: PASS"
    grep '\*\*\* PASS.*freertos_kernel_smoke' "$LOG_PATH" | tail -n 1
    exit 0
fi

echo "  RESULT: FAIL/TIMEOUT"
grep -E 'CLINT] TIMER_IRQ|TEST-RESULT|Final PC|timer_irq|Message:|DECERR|WATCHDOG|STOP:|FreeRTOS|freertos_kernel_smoke|FAIL' "$LOG_PATH" | tail -n 120 || true
exit 1
