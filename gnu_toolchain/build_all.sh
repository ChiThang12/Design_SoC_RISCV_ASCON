#!/usr/bin/env bash
# build_all.sh — Compile tất cả test programs trong gnu_toolchain/tests/
# Cách dùng: cd gnu_toolchain && ./build_all.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_DIR="tests"
COMPILE_SCRIPT="./compile_c_to_hex.sh"
PASS=0
FAIL=0
SKIP=0

if [ ! -x "$COMPILE_SCRIPT" ]; then
    echo -e "${RED}ERROR: $COMPILE_SCRIPT not found or not executable${NC}"
    exit 1
fi

echo -e "${YELLOW}=== Building all tests ===${NC}"
echo ""

# Danh sách test files theo thứ tự ưu tiên (integration build last)
STANDALONE_TESTS=(
    test_uart.c
    test_gpio.c
    test_timer.c
    test_clint.c
    test_plic.c
    test_ascon.c
)

# Build từng standalone test
for test_file in "${STANDALONE_TESTS[@]}"; do
    src="$TESTS_DIR/$test_file"
    base="${test_file%.c}"
    hex="$TESTS_DIR/${base}.hex"

    if [ ! -f "$src" ]; then
        echo -e "  ${YELLOW}SKIP${NC} $base (file not found)"
        SKIP=$((SKIP + 1))
        continue
    fi

    printf "  Building %-30s ... " "$base"

    # Use -O0 for GPIO/CLINT/PLIC tests, -O1 for ASCON (timing sensitive)
    OPT="-O 0"
    if [ "$base" = "test_ascon" ]; then
        OPT="-O 1"
    fi

    if "$COMPILE_SCRIPT" -i "$src" -o "$hex" $OPT -c > /tmp/build_${base}.log 2>&1; then
        echo -e "${GREEN}OK${NC}  → $hex"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Error log:"
        sed 's/^/      /' /tmp/build_${base}.log | head -20
        FAIL=$((FAIL + 1))
    fi
done

# Build integration test (unity build — includes all others)
echo ""
printf "  Building %-30s ... " "test_integration"
INT_SRC="$TESTS_DIR/test_integration.c"
INT_HEX="$TESTS_DIR/test_integration.hex"

if [ -f "$INT_SRC" ]; then
    if "$COMPILE_SCRIPT" -i "$INT_SRC" -o "$INT_HEX" -O 0 -c > /tmp/build_test_integration.log 2>&1; then
        echo -e "${GREEN}OK${NC}  → $INT_HEX"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC}"
        echo "    Error log:"
        sed 's/^/      /' /tmp/build_test_integration.log | head -20
        FAIL=$((FAIL + 1))
    fi
else
    echo -e "${YELLOW}SKIP${NC} (file not found)"
    SKIP=$((SKIP + 1))
fi

# Summary
echo ""
echo -e "${YELLOW}=== Build Summary ===${NC}"
echo -e "  ${GREEN}PASS${NC}: $PASS"
[ $FAIL  -gt 0 ] && echo -e "  ${RED}FAIL${NC}: $FAIL"
[ $SKIP  -gt 0 ] && echo -e "  ${YELLOW}SKIP${NC}: $SKIP"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All builds successful.${NC}"
    echo ""
    echo "To run a test in simulation:"
    echo "  cp $TESTS_DIR/<test>.hex program.hex"
    echo "  iverilog -g2005 -I.. -o sim.vvp ../tb_soc_full.v && vvp sim.vvp"
    exit 0
else
    echo -e "${RED}${FAIL} build(s) failed.${NC}"
    exit 1
fi
