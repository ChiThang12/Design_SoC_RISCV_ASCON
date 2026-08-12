#!/usr/bin/env bash
# =============================================================================
# run_layer_test.sh — Chạy debug test theo từng layer
#
# Usage:
#   ./workflow/run_layer_test.sh 1        # Layer 1: CPU pipeline standalone
#   ./workflow/run_layer_test.sh 2        # Layer 2: CRT0 copy pattern
#   ./workflow/run_layer_test.sh 3        # Layer 3: DCache + DMEM
#   ./workflow/run_layer_test.sh 4        # Layer 4: ICache + IMEM
#   ./workflow/run_layer_test.sh 5        # Layer 5: Full SoC + CRT0
#   ./workflow/run_layer_test.sh 6a       # Layer 6a: UART simple
#   ./workflow/run_layer_test.sh 6b       # Layer 6b: UART IRQ
#   ./workflow/run_layer_test.sh 6c       # Layer 6c: ASCON DMA
#   ./workflow/run_layer_test.sh all      # Chạy tất cả từ L1 → dừng khi fail
#
# Output:
#   log/layer<N>_<name>.log    — log chi tiết
#   Báo cáo ngắn gọn ra stdout (PASS/FAIL + snippet)
#
# Pass criteria:
#   Mỗi layer có criteria riêng (xem plan_debug.md)
#   Script tìm keyword [Lx-PASS] hoặc *** PASS trong log
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

LOG_DIR="$ROOT/log"
mkdir -p "$LOG_DIR"

LAYER="${1:-}"

# ── Color helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
sep()   { echo "─────────────────────────────────────────────────────"; }

# ── Kết quả toàn bộ ────────────────────────────────────────────────────────
OVERALL_PASS=1

# =============================================================================
# Hàm chạy simulation và check kết quả
# run_sim <log_name> <verilog_file> [extra_flags]
# =============================================================================
run_sim() {
    local log_name="$1"
    local vfile="$2"
    shift 2
    local extra_flags="${*:-}"
    local log="$LOG_DIR/${log_name}.log"

    info "Compiling: $vfile"
    if ! iverilog -g2005 $extra_flags -o "/tmp/${log_name}.vvp" "$vfile" 2>&1 | tee -a "$log"; then
        fail "Compile FAILED: $vfile"
        echo "  → Xem chi tiết: $log"
        return 1
    fi

    info "Running simulation → $log"
    vvp "/tmp/${log_name}.vvp" >> "$log" 2>&1
    return 0
}

# =============================================================================
# Check pass/fail từ log
# check_log <log_name> <pass_pattern> <fail_pattern>
# =============================================================================
check_log() {
    local log_name="$1"
    local pass_pat="$2"
    local fail_pat="$3"
    local log="$LOG_DIR/${log_name}.log"

    if grep -q "$pass_pat" "$log" 2>/dev/null; then
        return 0   # PASS
    elif grep -q "$fail_pat" "$log" 2>/dev/null; then
        return 2   # FAIL (explicit)
    else
        return 1   # TIMEOUT / no result
    fi
}

# =============================================================================
# In snippet từ log (5 dòng cuối có nội dung)
# =============================================================================
show_snippet() {
    local log_name="$1"
    local log="$LOG_DIR/${log_name}.log"
    echo "  Last output:"
    grep -v "^$" "$log" 2>/dev/null | tail -8 | sed 's/^/    /'
}

# =============================================================================
# LAYER 1 — CPU Pipeline Standalone
# =============================================================================
run_layer1() {
    sep
    info "LAYER 1 — CPU Pipeline Standalone"
    sep

    local all_ok=0

    # ── Step 1A: Existing general CPU TB ────────────────────────────────────
    info "Step 1A: General CPU TB (tb_riscv_cpu_core_v2.v)"
    local log_a="layer1a_cpu_general"
    > "$LOG_DIR/${log_a}.log"

    if [[ ! -f "cpu/tb/tb_riscv_cpu_core_v2.v" ]]; then
        warn "  tb_riscv_cpu_core_v2.v không tồn tại — bỏ qua step 1A"
    else
        run_sim "$log_a" "cpu/tb/tb_riscv_cpu_core_v2.v"
        check_log "$log_a" "ALL TESTS PASSED\|\*\*\* ALL" "FAILED\|\*\*\* [0-9]* FAILED"
        local rc_a=$?
        if [[ $rc_a -eq 0 ]]; then
            pass "  Step 1A: General CPU TB — ALL PASSED"
        else
            fail "  Step 1A: General CPU TB — CÓ FAIL"
            show_snippet "$log_a"
            warn ">>> BUG tại TB general — báo user trước khi phân tích."
            all_ok=1
        fi
    fi

    # ── Step 1B: Focused hazard TB (tb_layer1_pipeline.v) ───────────────────
    info "Step 1B: Focused Hazard TB (tb_layer1_pipeline.v)"
    local log_b="layer1b_hazard"
    > "$LOG_DIR/${log_b}.log"

    if [[ ! -f "cpu/tb/tb_layer1_pipeline.v" ]]; then
        fail "  tb_layer1_pipeline.v không tồn tại"
        return 1
    fi

    run_sim "$log_b" "cpu/tb/tb_layer1_pipeline.v"
    check_log "$log_b" "L1-PASS\|ALL PIPELINE HAZARD TESTS PASSED" "L1-FAIL\|FAILED\|WATCHDOG"
    local rc_b=$?
    case $rc_b in
        0) pass "  Step 1B: Focused Hazard TB — L1-PASS" ;;
        2) fail "  Step 1B: Focused Hazard TB — L1-FAIL"
           show_snippet "$log_b"
           warn ">>> BUG DETECTED: Pipeline hazard (load-use / CRT0 pattern)"
           warn ">>> Báo user. Log: $LOG_DIR/${log_b}.log"
           all_ok=1 ;;
        1) warn "  Step 1B: Không tìm thấy PASS/FAIL keyword"
           show_snippet "$log_b"
           all_ok=1 ;;
    esac

    sep
    if [[ $all_ok -eq 0 ]]; then
        pass "LAYER 1 — PASS (cả 2 TB đều pass)"
    else
        fail "LAYER 1 — FAIL"
        info "Xem log chi tiết:"
        info "  $LOG_DIR/${log_a}.log"
        info "  $LOG_DIR/${log_b}.log"
    fi
    return $all_ok
}

# =============================================================================
# LAYER 2 — CRT0 Copy Pattern
# =============================================================================
run_layer2() {
    sep
    info "LAYER 2 — CRT0 _copy_data Pattern"
    info "Testbench: cpu/tb/tb_cpu_crt0_pattern.v"
    sep

    if [[ ! -f "cpu/tb/tb_cpu_crt0_pattern.v" ]]; then
        warn "Testbench CHƯA TỒN TẠI: cpu/tb/tb_cpu_crt0_pattern.v"
        warn "Cần tạo testbench này trước. Xem plan_debug.md Layer 2."
        echo ""
        warn ">>> Báo user: Layer 2 TB chưa có — cần tạo mới."
        return 1
    fi

    local log="layer2_crt0"
    > "$LOG_DIR/${log}.log"

    run_sim "$log" "cpu/tb/tb_cpu_crt0_pattern.v" || return 1

    check_log "$log" "L2-PASS\|DMEM.*correct\|copy.*correct" "FAIL\|MISMATCH\|ERROR"
    local rc=$?
    case $rc in
        0) pass "L2 CRT0 Copy — DMEM copy đúng"
           return 0 ;;
        2) fail "L2 CRT0 Copy — DMEM copy SAI"
           show_snippet "$log"
           warn ">>> BUG: CRT0 load-use hazard không xử lý đúng."
           warn ">>> Báo user trước khi phân tích."
           return 1 ;;
        1) warn "L2 CRT0 — Không tìm thấy PASS/FAIL keyword"
           show_snippet "$log"
           return 1 ;;
    esac
}

# =============================================================================
# LAYER 3 — CPU + DCache + DMEM via AXI
# =============================================================================
run_layer3() {
    sep
    info "LAYER 3 — CPU + DCache + DMEM via AXI"
    info "Testbench: cpu/tb/tb_riscv_soc_top.v"
    sep

    if [[ ! -f "cpu/tb/tb_riscv_soc_top.v" ]]; then
        warn "Testbench không tồn tại: cpu/tb/tb_riscv_soc_top.v"
        return 1
    fi

    local log="layer3_dcache"
    > "$LOG_DIR/${log}.log"

    run_sim "$log" "cpu/tb/tb_riscv_soc_top.v" || return 1

    check_log "$log" "\[PASS\]\|L3-PASS" "FAIL\|ERROR"
    local rc=$?
    case $rc in
        0) pass "L3 DCache — OK"
           return 0 ;;
        *) fail "L3 DCache — FAIL hoặc timeout"
           show_snippet "$log"
           warn ">>> BUG DETECTED tại Layer 3 — báo user."
           return 1 ;;
    esac
}

# =============================================================================
# LAYER 4 — ICache + IMEM via AXI (Minimal firmware)
# =============================================================================
run_layer4() {
    sep
    info "LAYER 4 — ICache + IMEM via AXI (Minimal firmware)"
    info "Test: DMEM[0x10000000] = 0xDEADBEEF sau boot"
    sep

    # Check xem có hex minimal không
    if [[ ! -f "gnu_toolchain/tests/test_minimal.hex" ]]; then
        warn "test_minimal.hex chưa tồn tại."
        warn "Cần build: cd gnu_toolchain && ./compile_c_to_hex.sh -i tests/test_minimal.c -o tests/test_minimal.hex -c"
        warn ">>> Báo user: cần tạo test_minimal.c trước."
        return 1
    fi

    local log="layer4_icache"
    > "$LOG_DIR/${log}.log"

    cp "gnu_toolchain/tests/test_minimal.hex" "memory/program.hex"
    run_sim "$log" "run_soc_ascon.v" || return 1

    check_log "$log" "DEADBEEF\|L4-PASS\|\[PASS\]" "FAIL\|ERROR\|TIMEOUT"
    local rc=$?
    case $rc in
        0) pass "L4 ICache — Minimal firmware boot OK"
           return 0 ;;
        *) fail "L4 ICache — FAIL"
           show_snippet "$log"
           warn ">>> BUG DETECTED tại Layer 4 — báo user."
           return 1 ;;
    esac
}

# =============================================================================
# LAYER 5 — Full SoC + CRT0 Verify
# =============================================================================
run_layer5() {
    sep
    info "LAYER 5 — Full SoC + CRT0 .data copy verify"
    info "Test: magic[] = 'HELLO' copied đúng → STATUS=0x48"
    sep

    if [[ ! -f "gnu_toolchain/tests/test_crt0_verify.hex" ]]; then
        warn "test_crt0_verify.hex chưa tồn tại."
        warn "Cần tạo tests/test_crt0_verify.c trước."
        warn ">>> Báo user: cần tạo test_crt0_verify.c."
        return 1
    fi

    local log="layer5_crt0_soc"
    > "$LOG_DIR/${log}.log"

    cp "gnu_toolchain/tests/test_crt0_verify.hex" "memory/program.hex"
    run_sim "$log" "run_soc_ascon.v" || return 1

    check_log "$log" "L5-PASS\|STATUS=0x48\|\[PASS\]" "FAIL\|ERROR\|TIMEOUT"
    local rc=$?
    case $rc in
        0) pass "L5 Full SoC CRT0 — .data copy đúng"
           return 0 ;;
        *) fail "L5 Full SoC CRT0 — .data copy SAI hoặc timeout"
           show_snippet "$log"
           warn ">>> BUG DETECTED tại Layer 5 — CRT0 load-use hazard còn."
           warn ">>> Báo user trước khi phân tích."
           return 1 ;;
    esac
}

# =============================================================================
# LAYER 6a — UART Simple
# =============================================================================
run_layer6a() {
    sep
    info "LAYER 6a — UART Simple (uart_puts)"
    sep

    local log="layer6a_uart_simple"
    > "$LOG_DIR/${log}.log"

    cp "gnu_toolchain/tests/test_uart_simple.hex" "memory/program.hex"
    run_sim "$log" "run_soc_ascon.v" || return 1

    check_log "$log" "\*\*\* PASS\|\[PASS\]" "\*\*\* FAIL\|\[FAIL\]"
    local rc=$?
    case $rc in
        0) pass "L6a UART Simple — PASS"
           return 0 ;;
        2) fail "L6a UART Simple — FAIL (explicit)"
           show_snippet "$log"
           warn ">>> BUG tại UART simple — báo user."
           return 1 ;;
        1) warn "L6a UART Simple — TIMEOUT (không thấy PASS/FAIL)"
           show_snippet "$log"
           return 1 ;;
    esac
}

# =============================================================================
# LAYER 6b — UART IRQ
# =============================================================================
run_layer6b() {
    sep
    info "LAYER 6b — UART IRQ (W1C clear)"
    info "Known bug: TX IRQ W1C clear fail → retcode=-2"
    sep

    local log="layer6b_uart_irq"
    > "$LOG_DIR/${log}.log"

    cp "gnu_toolchain/tests/test_uart.hex" "memory/program.hex"
    run_sim "$log" "run_soc_ascon.v" || return 1

    check_log "$log" "\*\*\* PASS\|\[PASS\]" "\*\*\* FAIL\|\[FAIL\]\|err=0xFFFFFFFE"
    local rc=$?
    case $rc in
        0) pass "L6b UART IRQ — PASS"
           return 0 ;;
        2) fail "L6b UART IRQ — FAIL"
           # Check nếu là bug đã biết
           if grep -q "err=0xFFFFFFFE\|FFFFFFFF\|FE" "$LOG_DIR/${log}.log" 2>/dev/null; then
               warn ">>> KNOWN BUG-002: W1C clear fail (retcode=-2)"
               warn ">>> Báo user: UART IRQ W1C bug vẫn còn."
           else
               warn ">>> BUG MỚI tại L6b — báo user để xem xét."
           fi
           show_snippet "$log"
           return 1 ;;
        1) warn "L6b UART IRQ — TIMEOUT"
           show_snippet "$log"
           return 1 ;;
    esac
}

# =============================================================================
# LAYER 6c — ASCON DMA
# =============================================================================
run_layer6c() {
    sep
    info "LAYER 6c — ASCON DMA 16-block"
    info "Depends on: L1/L2 pass (CRT0 copy đúng)"
    sep

    local log="layer6c_ascon"
    > "$LOG_DIR/${log}.log"

    cp "gnu_toolchain/tests/test_ascon.hex" "memory/program.hex"
    run_sim "$log" "run_soc_ascon.v" || return 1

    check_log "$log" "\*\*\* PASS\|\[PASS\]" "\*\*\* FAIL\|\[FAIL\]\|TIMEOUT\|WATCHDOG"
    local rc=$?
    case $rc in
        0) pass "L6c ASCON — PASS"
           return 0 ;;
        2) fail "L6c ASCON — FAIL"
           show_snippet "$log"
           warn ">>> BUG tại ASCON — báo user."
           return 1 ;;
        1) warn "L6c ASCON — TIMEOUT / không có kết quả rõ ràng"
           show_snippet "$log"
           warn ">>> Có thể: CRT0 bug chưa fix (L1/L2 chưa pass)"
           warn ">>> Báo user."
           return 1 ;;
    esac
}

# =============================================================================
# MAIN — Dispatch
# =============================================================================

if [[ -z "$LAYER" ]]; then
    echo "Usage: $0 <layer>"
    echo "  Layers: 1, 2, 3, 4, 5, 6a, 6b, 6c, all"
    echo "  Xem plan_debug.md để biết từng layer test gì."
    exit 1
fi

case "$LAYER" in
    1)   run_layer1;  OVERALL_PASS=$? ;;
    2)   run_layer2;  OVERALL_PASS=$? ;;
    3)   run_layer3;  OVERALL_PASS=$? ;;
    4)   run_layer4;  OVERALL_PASS=$? ;;
    5)   run_layer5;  OVERALL_PASS=$? ;;
    6a)  run_layer6a; OVERALL_PASS=$? ;;
    6b)  run_layer6b; OVERALL_PASS=$? ;;
    6c)  run_layer6c; OVERALL_PASS=$? ;;
    all)
        info "Chạy tất cả layers từ L1 → L6c (dừng khi fail)"
        for L in 1 2 3 4 5 6a 6b 6c; do
            run_layer$L
            if [[ $? -ne 0 ]]; then
                sep
                fail "Dừng tại Layer $L — fix bug trước khi tiếp tục."
                OVERALL_PASS=1
                break
            fi
        done
        ;;
    *)
        echo "[ERROR] Layer không hợp lệ: $LAYER"
        echo "Chọn: 1 2 3 4 5 6a 6b 6c all"
        exit 1
        ;;
esac

sep
if [[ $OVERALL_PASS -eq 0 ]]; then
    pass "Layer $LAYER — DONE ✓"
    info "Tiếp theo: xem plan_debug.md để chọn layer tiếp theo"
else
    fail "Layer $LAYER — CÓ VẤN ĐỀ"
    info "Xem log chi tiết trong: $LOG_DIR/"
    info "Tham khảo: plan_debug.md và task_debug.md"
fi

exit $OVERALL_PASS
