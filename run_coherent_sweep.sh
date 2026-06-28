#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if (($#)); then
  SIZES=("$@")
else
  SIZES=(256 512 1024)
fi

COH_CTRL="${COH_CTRL:-3}"
SWEEP_SRC="$ROOT/gnu_toolchain/tests/test_ascon_dma_coherent_nofence_sweep.c"

echo "payload_bytes,fair_cycles,done_cycles,throughput_fair_mbps,m2_aw,throughput_done_mbps,snoop_read,snoop_inv,m2_ar,peak_wr_fifo,dma_start,last_m2_b"

for size in "${SIZES[@]}"; do
  src="/tmp/test_ascon_dma_coherent_nofence_${size}b_coh${COH_CTRL}.c"
  hex="gnu_toolchain/tests/test_ascon_dma_coherent_nofence_${size}b_coh${COH_CTRL}.hex"
  vvp_out="/tmp/run_soc_coherent_nofence_${size}b_coh${COH_CTRL}_sweep.vvp"
  log="/tmp/run_soc_coherent_nofence_${size}b_coh${COH_CTRL}_sweep.log"

  printf '#define PAYLOAD_BYTES %su\n#define DMA_COH_CTRL_VALUE %su\n#include "%s"\n' "$size" "$COH_CTRL" "$SWEEP_SRC" > "$src"
  (cd gnu_toolchain && ./compile_c_to_hex.sh -i "$src" -o "tests/test_ascon_dma_coherent_nofence_${size}b_coh${COH_CTRL}.hex" -k -O 0 -c >/dev/null 2>&1)
  iverilog -g2012 -I. \
    -DIMEM_INIT_FILE=\"${hex}\" \
    -DPAYLOAD_BYTES=${size} \
    -DCOH_CTRL_VALUE=${COH_CTRL} \
    -o "${vvp_out}" run_soc_coherent_nofence_sweep.v
  vvp "${vvp_out}" | tee "${log}" >/dev/null
  rg '^CSV,' "${log}" | sed 's/^CSV,//'
done
