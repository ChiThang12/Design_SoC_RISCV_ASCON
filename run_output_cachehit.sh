#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SIZE="${1:-128}"
COH_CTRL="${COH_CTRL:-1}"
SRC="$ROOT/gnu_toolchain/tests/test_ascon_dma_output_cachehit.c"
WRAP="/tmp/test_ascon_dma_output_cachehit_${SIZE}b_coh${COH_CTRL}.c"
HEX="gnu_toolchain/tests/test_ascon_dma_output_cachehit_${SIZE}b_coh${COH_CTRL}.hex"
VVP="/tmp/run_output_cachehit_${SIZE}b_coh${COH_CTRL}.vvp"
LOG="/tmp/run_output_cachehit_${SIZE}b_coh${COH_CTRL}.log"

printf '#define PAYLOAD_BYTES %su\n#define DMA_COH_CTRL_VALUE %su\n#include "%s"\n' "$SIZE" "$COH_CTRL" "$SRC" > "$WRAP"

(cd gnu_toolchain && ./compile_c_to_hex.sh -i "$WRAP" -o "tests/test_ascon_dma_output_cachehit_${SIZE}b_coh${COH_CTRL}.hex" -k -O 0 -c >/dev/null 2>&1)

iverilog -g2012 -I. \
  -DIMEM_INIT_FILE=\"${HEX}\" \
  -DPAYLOAD_BYTES="${SIZE}" \
  -DCOH_CTRL_VALUE="${COH_CTRL}" \
  -o "$VVP" run_soc_coherent_nofence_sweep.v

vvp "$VVP" | tee "$LOG" >/dev/null
rg '^CSV,' "$LOG" | sed 's/^CSV,//'
