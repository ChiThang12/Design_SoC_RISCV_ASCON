#!/usr/bin/env bash
# Phase 1 pre-RTOS closure runner.
#
# Runs the interrupt/trap/cache blocker set that must stay green before
# starting the FreeRTOS port. Use LOOPS=N for repeated stability runs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOOPS="${LOOPS:-1}"
TESTS=(
    test_timer
    test_gpio
    test_clint
    test_plic
)

echo "=============================================="
echo " Phase 1 P0 pre-RTOS closure"
echo "=============================================="
echo "  LOOPS : ${LOOPS}"
echo "  TESTS : ${TESTS[*]}"
echo "  UART  : fast simulation baud"
echo ""

for ((i = 1; i <= LOOPS; i++)); do
    echo "----------------------------------------------"
    echo " Phase 1 run ${i}/${LOOPS}"
    echo "----------------------------------------------"
    EXTRA_CFLAGS="${EXTRA_CFLAGS:--DSOC_SIM_FAST_UART}" \
    EXTRA_IVERILOG_DEFINES="${EXTRA_IVERILOG_DEFINES:--DBAUD_DIV=1 -DLOG_LEVEL=0 -DFINISH_ON_PASS}" \
        bash regression_full.sh -b "${TESTS[@]}"
done

echo ""
echo "[OK] Phase 1 P0 regression completed: ${LOOPS}/${LOOPS} loop(s)"
