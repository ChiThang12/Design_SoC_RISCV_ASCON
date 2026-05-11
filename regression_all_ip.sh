#!/usr/bin/env bash
# =============================================================================
# regression_all_ip.sh — Chứng minh từng IP hoạt động qua firmware test suite
#
# Usage:
#   bash regression_all_ip.sh              # chạy tất cả 8 test
#   bash regression_all_ip.sh test_uart   # chỉ chạy 1 test cụ thể
#
# Pass criteria: tìm thấy [PASS] hoặc ALL_PASS trong log, không có [FAIL]/TIMEOUT
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FW="$SCRIPT_DIR/gnu_toolchain"
LOG_DIR="$SCRIPT_DIR/logs"
TB="$SCRIPT_DIR/run_soc_ascon.v"

# Danh sách test theo thứ tự (integration phải chạy cuối)
ALL_TESTS=(test_uart test_gpio test_timer test_clint test_plic test_ascon test_dma_uart test_integration)

declare -A IP_NAME=(
    ["test_uart"]="UART"
    ["test_gpio"]="GPIO (edge IRQ)"
    ["test_timer"]="Timer0/1 + WDT"
    ["test_clint"]="CLINT (mtime/mtimecmp/msip)"
    ["test_plic"]="PLIC (interrupt routing)"
    ["test_ascon"]="ASCON DMA 16-block"
    ["test_dma_uart"]="GP-DMA mem-to-mem"
    ["test_integration"]="Integration (all 6 IPs)"
)

# Nếu có argument → chạy chỉ test đó
if [[ $# -ge 1 ]]; then
    ALL_TESTS=("$1")
fi

mkdir -p "$LOG_DIR"

# =============================================================================
# Step 1: Build firmware hex files
# =============================================================================
echo "=============================================="
echo " Step 1: Build Firmware Test Hex Files"
echo "=============================================="

cd "$FW"
BUILD_FAIL=0
for t in "${ALL_TESTS[@]}"; do
    src="tests/${t}.c"
    hex="tests/${t}.hex"
    if [[ ! -f "$src" ]]; then
        echo "  [SKIP] $src không tồn tại"
        continue
    fi
    printf "  Building %-30s ... " "$src"
    if ./compile_c_to_hex.sh -i "$src" -o "$hex" -O 0 -c > /dev/null 2>&1; then
        echo "OK"
    else
        echo "FAIL"
        BUILD_FAIL=$((BUILD_FAIL + 1))
    fi
done
cd "$SCRIPT_DIR"

if [[ $BUILD_FAIL -gt 0 ]]; then
    echo ""
    echo "[ERROR] $BUILD_FAIL firmware build(s) failed — abort"
    exit 1
fi

echo ""

# =============================================================================
# Step 2: Compile SoC testbench + run simulation for each test
# =============================================================================
echo "=============================================="
echo " Step 2: Run IP Verification Tests"
echo "=============================================="
echo ""

PASS=0
FAIL=0
FAIL_LIST=()

for t in "${ALL_TESTS[@]}"; do
    hex="$FW/tests/${t}.hex"
    logfile="$LOG_DIR/${t}.log"
    ip="${IP_NAME[$t]}"

    if [[ ! -f "$hex" ]]; then
        echo "  [SKIP] $hex không tồn tại"
        continue
    fi

    printf "  %-35s ... " "$ip"

    # Compile TB (chỉ một lần cho toàn bộ regression)
    # TIMEOUT=600000: 200k mặc định không đủ cho UART tests (115200 baud @100MHz = 868cy/bit)
    # test_uart: "Hello UART\r\n" + "[PASS] uart\r\n" ≈ 226k cycles UART time alone
    VVP="$LOG_DIR/run_soc_ascon.vvp"
    if [[ ! -f "$VVP" ]]; then
        iverilog -g2005 -DTIMEOUT=600000 -o "$VVP" "$TB" > "$logfile" 2>&1
        if [[ $? -ne 0 ]]; then
            echo "COMPILE_ERR"
            FAIL=$((FAIL + 1))
            FAIL_LIST+=("$t (TB compile error)")
            continue
        fi
    fi

    # Chạy simulation với +IMEM_HEX override (boot_rom.v dùng $value$plusargs)
    vvp "$VVP" "+IMEM_HEX=${hex}" >> "$logfile" 2>&1

    # Phân tích kết quả
    has_pass=0
    has_fail=0
    grep -q "\[PASS\]\|ALL_PASS"      "$logfile" 2>/dev/null && has_pass=1
    grep -q "\[FAIL\]\|\$fatal\|TIMEOUT\|Error\|fatal" "$logfile" 2>/dev/null && has_fail=1

    if [[ $has_pass -eq 1 && $has_fail -eq 0 ]]; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL  (xem $logfile)"
        FAIL=$((FAIL + 1))
        FAIL_LIST+=("$t")
    fi
done

# =============================================================================
# Step 3: Summary
# =============================================================================
echo ""
echo "=============================================="
echo " IP Verification Summary"
echo "=============================================="
printf "  PASS: %d\n" "$PASS"
printf "  FAIL: %d\n" "$FAIL"
printf "  TOTAL: %d\n" "$((PASS + FAIL))"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "  ✅  TẤT CA IP HOAT DONG DUNG"
    echo "      (logs: $LOG_DIR/)"
    exit 0
else
    echo "  ❌  CON IP LOI:"
    for f in "${FAIL_LIST[@]}"; do
        echo "      - $f"
    done
    echo ""
    echo "  Xem log chi tiet: $LOG_DIR/<test_name>.log"
    exit 1
fi
