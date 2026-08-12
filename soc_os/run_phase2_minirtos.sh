#!/usr/bin/env bash
# Phase 2 pre-FreeRTOS smoke runner.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TEST_NAME="test_minirtos_tick"
HEX_PATH="$ROOT_DIR/gnu_toolchain/test_os/${TEST_NAME}.hex"
VVP_PATH="/tmp/${TEST_NAME}_phase2.vvp"
LOG_PATH="$ROOT_DIR/log/${TEST_NAME}.log"
UART_DIV=16

echo "=============================================="
echo " Phase 2 mini-RTOS periodic tick smoke"
echo "=============================================="

mkdir -p "$ROOT_DIR/log"

echo "=============================================="
echo " Step 1: Build firmware"
echo "=============================================="
(
    cd "$ROOT_DIR/gnu_toolchain"
    ./compile_c_to_hex.sh -i "test_os/${TEST_NAME}.c" -o "test_os/${TEST_NAME}.hex" -O 0 >/dev/null
)
echo "  Built: $HEX_PATH"

echo ""
echo "=============================================="
echo " Step 2: Compile simulation"
echo "=============================================="
iverilog -g2005 \
    -DLOG_LEVEL=0 \
    -DBAUD_DIV="$UART_DIV" \
    -DIMEM_INIT_FILE="\"${HEX_PATH}\"" \
    -o "$VVP_PATH" run_soc_ascon.v
echo "  VVP: $VVP_PATH"

echo ""
echo "=============================================="
echo " Step 3: Run simulation"
echo "=============================================="
timeout 180s vvp "$VVP_PATH" > "$LOG_PATH" 2>&1 || true

if grep -q '\*\*\* PASS' "$LOG_PATH"; then
    echo "  RESULT: PASS"
    grep '\*\*\* PASS' "$LOG_PATH" | tail -n 1
    exit 0
fi

echo "  RESULT: FAIL/TIMEOUT"
grep -E 'CLINT] TIMER_IRQ|TEST-RESULT|Final PC|timer_irq|Message:|DECERR|WATCHDOG|STOP:' "$LOG_PATH" | tail -n 80 || true
exit 1
