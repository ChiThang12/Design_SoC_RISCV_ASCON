#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

SIZES=(128 256 512 1024)

echo "## Software-fenced baseline sweep, COH_CTRL=0"
bash run_fence_sweep.sh "${SIZES[@]}"

echo
echo "## Regular no-fence coherent sweep, COH_CTRL=3"
COH_CTRL=3 bash run_coherent_sweep.sh "${SIZES[@]}"

echo
echo "## Regular no-fence coherent sweep, COH_CTRL=1"
COH_CTRL=1 bash run_coherent_sweep.sh "${SIZES[@]}"

echo
echo "## Output-cache-hit control, COH_CTRL=1"
COH_CTRL=1 bash run_output_cachehit.sh 128

echo
echo "## Output-cache-hit control, COH_CTRL=3"
COH_CTRL=3 bash run_output_cachehit.sh 128
