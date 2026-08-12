#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GNU="$ROOT/gnu_toolchain"
TB_DUAL="$ROOT/tb_soc/tb_soc_dualcore_suite.v"
OUT_DIR="${OUT_DIR:-/tmp/h_firmware_benchmarks}"
mkdir -p "$OUT_DIR"

overall_status=0

run_cmd_to_log() {
  local log="$1"
  shift
  (
    cd "$ROOT"
    "$@"
  ) | tee "$log"
}

mark_fail() {
  overall_status=1
}

run_dualcore_case() {
  local name="$1"
  local sig0="$2"
  local sig1="$3"
  local heartbeat="$4"
  local dc_req="$5"
  local aux0_en="$6"
  local aux0="$7"
  local aux1_en="$8"
  local aux1="$9"
  local timeout="${10}"
  local extra_define="${11:-}"
  local out="${OUT_DIR}/${name}.out"
  local log="${OUT_DIR}/${name}.log"

  echo "== [H3] Building ${name} =="
  (
    cd "$GNU"
    ./compile_c_to_hex.sh -i "tests_dualcore/${name}.c" -o "tests_dualcore/${name}.hex" -O 0 >/dev/null
  ) || { echo "[FAIL] build ${name}"; mark_fail; return; }

  echo "== [H3] Running ${name} =="
  (
    cd "$ROOT"
    iverilog -g2005 -I. \
      ${extra_define:+$extra_define} \
      -DTEST_HEX="\"gnu_toolchain/tests_dualcore/${name}.hex\"" \
      -DSCENARIO_NAME="\"${name}\"" \
      -DEXPECT_SIG0="${sig0}" \
      -DEXPECT_SIG1="${sig1}" \
      -DHEARTBEAT_MIN="${heartbeat}" \
      -DDC_REQ_MIN="${dc_req}" \
      -DAUX0_CHECK_ENABLE="${aux0_en}" \
      -DEXPECT_AUX0="${aux0}" \
      -DAUX1_CHECK_ENABLE="${aux1_en}" \
      -DEXPECT_AUX1="${aux1}" \
      -DTIMEOUT_CYCLES="${timeout}" \
      -o "$out" "$TB_DUAL" >/dev/null &&
    vvp "$out"
  ) | tee "$log"

  if ! rg -q "^\[PASS\] ${name}$" "$log"; then
    echo "[FAIL] ${name} did not reach PASS"
    mark_fail
  fi
}

run_baseline_payload() {
  local out="${OUT_DIR}/run_soc_fence_128b.out"
  local log="${OUT_DIR}/run_soc_fence_128b.log"

  echo "== [BASELINE] Running software-fenced payload firmware =="
  (
    cd "$ROOT"
    iverilog -g2012 -I. -o "$out" run_soc_fence_128b.v >/dev/null &&
    vvp "$out"
  ) | tee "$log"

  if ! rg -q "^\[PASS\] SoC software-fenced DMA 128B test passed$" "$log"; then
    echo "[FAIL] baseline payload firmware did not reach PASS"
    mark_fail
  fi
}

run_streaming_headline() {
  local size="${1:-128}"
  local coh="$2"
  local wrapper_log="${OUT_DIR}/run_output_cachehit_${size}b_coh${coh}.wrapper.log"
  local log="/tmp/run_output_cachehit_${size}b_coh${coh}.log"

  echo "== [STREAMING] Running output cache-hit firmware, COH_CTRL=${coh} =="
  (
    cd "$ROOT"
    COH_CTRL="$coh" bash run_output_cachehit.sh "$size"
  ) | tee "$wrapper_log"

  if [[ ! -f "$log" ]]; then
    echo "[FAIL] missing streaming log for COH_CTRL=${coh}"
    mark_fail
    return
  fi

  if ! rg -q "^\[PASS\] SoC coherent no-fence sweep payload=${size}B passed$" "$log"; then
    echo "[FAIL] streaming headline firmware COH_CTRL=${coh} did not reach PASS"
    mark_fail
  fi
}

print_summary() {
  local ctx_log="${OUT_DIR}/test_dualcore_h3_context.log"
  local bench_log="${OUT_DIR}/test_dualcore_h3_benchmark.log"
  local base_log="${OUT_DIR}/run_soc_fence_128b.log"
  local stream1_log="/tmp/run_output_cachehit_128b_coh1.log"
  local stream3_log="/tmp/run_output_cachehit_128b_coh3.log"

  echo
  echo "================ H FIRMWARE SUMMARY ================"
  echo "[H3] test_dualcore_h3_context"
  rg -n "^\[PASS\]|^  cycles=|^  heartbeat=|peer_snp_hits|c2c_fwds|^\[FAIL\]" "$ctx_log" || true
  echo
  echo "[H3] test_dualcore_h3_benchmark"
  rg -n "^\[PASS\]|^  cycles=|h3_core_ops|h3_context_switches|avg_mmio_interval_cycles|rtl_select_latency_cycles|^\[FAIL\]" "$bench_log" || true
  echo
  echo "[BASELINE] run_soc_fence_128b"
  rg -n "^\[PASS\]|dma_start/done/error|fair write-complete cyc|M2 AR/AW|^\[FAIL\]" "$base_log" || true
  echo
  echo "[STREAMING] output cache-hit, COH_CTRL=1"
  rg -n "^\[PASS\]|^CSV,|^\[FAIL\]|unexpected coherence control|firmware reported failure" "$stream1_log" || true
  echo
  echo "[STREAMING] output cache-hit, COH_CTRL=3"
  rg -n "^\[PASS\]|^CSV,|^\[FAIL\]|unexpected coherence control|firmware reported failure" "$stream3_log" || true
  echo "===================================================="
}

run_dualcore_case \
  "test_dualcore_h3_context" \
  "32'h3C000001" \
  "32'h3C000002" \
  "4" \
  "0" \
  "1" \
  "32'h3C0A0000" \
  "1" \
  "32'h3C0B0001" \
  "500000" \
  ""

run_dualcore_case \
  "test_dualcore_h3_benchmark" \
  "32'h3C00B001" \
  "32'h3C00B002" \
  "6" \
  "0" \
  "1" \
  "32'h3C0BEE00" \
  "1" \
  "32'h3C0BEE01" \
  "500000" \
  "-DH3_BENCH_TRACE"

run_baseline_payload
run_streaming_headline 128 1
run_streaming_headline 128 3
print_summary

exit "$overall_status"
