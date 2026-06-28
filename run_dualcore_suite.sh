#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GNU="$ROOT/gnu_toolchain"
TB="$ROOT/tb_soc/tb_soc_dualcore_suite.v"
TMPDIR="${TMPDIR:-/tmp}"

tests=(
  "test_dualcore_basic 32'hD00D_CAFE 32'h1357_9BDF 16 8"
  "test_dualcore_cache_sweep 32'hCACE_0001 32'h2468_ACE0 20 24"
  "test_dualcore_fence_flush 32'hFEC1_0001 32'h0BAD_F00D 20 20"
)

for item in "${tests[@]}"; do
  read -r name sig0 sig1 heartbeat dc_req <<<"$item"
  src="tests_dualcore/${name}.c"
  hex="tests_dualcore/${name}.hex"
  out="${TMPDIR}/${name}.out"

  echo "== Building ${name} =="
  (
    cd "$GNU"
    ./compile_c_to_hex.sh -i "$src" -o "$hex" -c >/dev/null
  )

  echo "== Running ${name} =="
  (
    cd "$ROOT"
    iverilog -g2005 -I. \
      -DTEST_HEX="\"gnu_toolchain/${hex}\"" \
      -DSCENARIO_NAME="\"${name}\"" \
      -DEXPECT_SIG0="${sig0}" \
      -DEXPECT_SIG1="${sig1}" \
      -DHEARTBEAT_MIN="${heartbeat}" \
      -DDC_REQ_MIN="${dc_req}" \
      -o "$out" "$TB" >/dev/null
    vvp "$out"
  )
  echo
done
