#!/usr/bin/env bash
# =============================================================================
# regression_full.sh — Full IP regression test suite
#
# Chạy 9 firmware tests qua workflow chuẩn (copy hex → urun_verilog.sh → log).
# Báo cáo PASS/FAIL với UART output snippet cho mỗi test.
#
# Usage:
#   bash regression_full.sh                  # chạy tất cả 9 test
#   bash regression_full.sh test_uart        # chỉ chạy 1 test
#   bash regression_full.sh -b               # rebuild firmware hex trước
#   bash regression_full.sh -b test_ascon    # rebuild rồi chạy 1 test
#
# Output:
#   log/<test>.log              — log từng test (compatible với urun_verilog.sh -l)
#   memory/program.hex          — bị thay tạm thời, restore sau khi xong
#   memory/program.hex.bak      — backup tự động (nếu chưa có)
#
# Pass criteria:
#   grep "*** PASS" trong log → PASS
#   grep "*** FAIL" trong log → FAIL
#   Cả hai không có            → TIMEOUT (CPU stuck hoặc test chưa hoàn tất)
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Danh sách 9 tests (test_uart_simple chạy đầu = sanity check) ──
ALL_TESTS=(
    test_uart_simple
    test_uart
    test_gpio
    test_timer
    test_clint
    test_plic
    test_ascon
    test_dma_uart
    test_integration
)

declare -A IP_NAME=(
    ["test_uart_simple"]="UART (simple putc)"
    ["test_uart"]="UART (full driver + IRQ)"
    ["test_gpio"]="GPIO (edge IRQ via PLIC)"
    ["test_timer"]="Timer0/1 + WDT"
    ["test_clint"]="CLINT (mtime/mtimecmp/msip)"
    ["test_plic"]="PLIC (interrupt routing)"
    ["test_ascon"]="ASCON DMA 16-block AEAD"
    ["test_dma_uart"]="GP-DMA mem-to-mem"
    ["test_integration"]="Integration (all 6 IPs)"
)

# ── Parse args ──
DO_BUILD=0
TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--build) DO_BUILD=1; shift ;;
        -h|--help)
            sed -n '2,25p' "$0"; exit 0 ;;
        *) TARGET="$1"; shift ;;
    esac
done

if [[ -n "$TARGET" ]]; then
    ALL_TESTS=("$TARGET")
fi

# ── Backup program.hex nếu chưa có ──
if [[ ! -f memory/program.hex.bak && -f memory/program.hex ]]; then
    cp memory/program.hex memory/program.hex.bak
    echo "[INFO] Backed up memory/program.hex → memory/program.hex.bak"
fi

# ── Build hex nếu yêu cầu ──
if [[ $DO_BUILD -eq 1 ]]; then
    echo "=============================================="
    echo " Step 1: Build firmware hex files"
    echo "=============================================="
    pushd gnu_toolchain > /dev/null
    BUILD_FAIL=0
    for t in "${ALL_TESTS[@]}"; do
        src="tests/${t}.c"
        hex="tests/${t}.hex"
        if [[ ! -f "$src" ]]; then
            echo "  [SKIP] $src không tồn tại"; continue
        fi
        printf "  Building %-30s ... " "$t"
        if ./compile_c_to_hex.sh -i "$src" -o "$hex" -O 0 > /dev/null 2>&1; then
            echo "OK"
        else
            echo "FAIL"
            BUILD_FAIL=$((BUILD_FAIL + 1))
        fi
    done
    popd > /dev/null
    if [[ $BUILD_FAIL -gt 0 ]]; then
        echo "[ERROR] $BUILD_FAIL build(s) failed — abort"
        exit 1
    fi
    echo ""
fi

# ── Run sims ──
echo "=============================================="
echo " Run regression — ${#ALL_TESTS[@]} test(s)"
echo "=============================================="
mkdir -p log

for t in "${ALL_TESTS[@]}"; do
    hex="gnu_toolchain/tests/${t}.hex"
    if [[ ! -f "$hex" ]]; then
        echo "  [SKIP] $hex không tồn tại (chạy '$0 -b' để build trước)"
        continue
    fi
    ip="${IP_NAME[$t]:-$t}"
    printf "  %-40s ... " "$ip"
    cp "$hex" memory/program.hex
    if ./workflow/urun_verilog.sh -l "$t" run_soc_ascon.v > /dev/null 2>&1; then
        echo "DONE"
    else
        echo "SIM_ERR"
    fi
done

# ── Restore program.hex ──
if [[ -f memory/program.hex.bak ]]; then
    cp memory/program.hex.bak memory/program.hex
    echo ""
    echo "[INFO] Restored memory/program.hex from backup"
fi

# ── Summary table ──
echo ""
echo "=============================================="
echo " Summary"
echo "=============================================="
printf "  %-22s %-9s %-10s %s\n" "TEST" "RESULT" "UART#" "MESSAGE"
printf "  %-22s %-9s %-10s %s\n" "----" "------" "-----" "-------"

PASS=0; FAIL=0; TIMEOUT=0
FAIL_LIST=()
for t in "${ALL_TESTS[@]}"; do
    log="log/${t}.log"
    if [[ ! -f "$log" ]]; then
        printf "  %-22s %-9s\n" "$t" "MISSING"
        continue
    fi
    pass_cnt=$(/bin/grep '\*\*\* PASS' "$log" 2>/dev/null | wc -l | tr -d ' ')
    fail_cnt=$(/bin/grep '\*\*\* FAIL' "$log" 2>/dev/null | wc -l | tr -d ' ')
    uart_cnt=$(/bin/grep '\[UART-TX\]' "$log" 2>/dev/null | wc -l | tr -d ' ')
    msg=$(/bin/grep "Message:" "$log" | head -1 | sed 's/.*Message: //' | cut -c1-40)
    if [[ "${pass_cnt:-0}" -gt 0 ]]; then
        result="PASS"
        PASS=$((PASS + 1))
    elif [[ "${fail_cnt:-0}" -gt 0 ]]; then
        result="FAIL"
        FAIL=$((FAIL + 1))
        FAIL_LIST+=("$t")
    else
        result="TIMEOUT"
        TIMEOUT=$((TIMEOUT + 1))
        FAIL_LIST+=("$t")
    fi
    printf "  %-22s %-9s uart=%-5s %s\n" "$t" "$result" "${uart_cnt:-0}" "$msg"
done

echo ""
printf "  Total: %d  |  PASS: %d  |  FAIL: %d  |  TIMEOUT: %d\n" \
    "${#ALL_TESTS[@]}" "$PASS" "$FAIL" "$TIMEOUT"

if [[ ${#FAIL_LIST[@]} -gt 0 ]]; then
    echo ""
    echo "  Tests cần debug:"
    for f in "${FAIL_LIST[@]}"; do
        echo "    - $f  (xem log/${f}.log)"
    done
fi

[[ $PASS -eq ${#ALL_TESTS[@]} ]] && exit 0 || exit 1
