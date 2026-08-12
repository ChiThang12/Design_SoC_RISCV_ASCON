#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GNU="$ROOT/gnu_toolchain"
TB="$ROOT/tb_soc/tb_soc_dualcore_suite.v"
TMPDIR="${TMPDIR:-/tmp}"

tests=(
  "test_dualcore_basic 32'hD00D_CAFE 32'h1357_9BDF 16 8 0 32'h0000_0000 0 32'h0000_0000 0 32'h0000_0000 400000"
  "test_dualcore_cache_sweep 32'hCACE_0001 32'h2468_ACE0 20 24 0 32'h0000_0000 0 32'h0000_0000 0 32'h0000_0000 400000"
  "test_dualcore_fence_flush 32'hFEC1_0001 32'h0BAD_F00D 20 20 0 32'h0000_0000 0 32'h0000_0000 0 32'h0000_0000 400000"
  "test_dualcore_peer_snoop 32'h5A11_0001 32'hC001_D00D 2 4 1 32'hFACE_B00C 1 32'h2222_0001 0 32'h0000_0000 400000"
)

for item in "${tests[@]}"; do
  read -r name sig0 sig1 heartbeat dc_req aux0_check aux0 aux1_check aux1 gpio_check expect_gpio timeout <<<"$item"
  src="tests_dualcore/${name}.c"
  hex="tests_dualcore/${name}.hex"
  out="${TMPDIR}/${name}.out"
  timeout="${timeout:-400000}"

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
      -DAUX0_CHECK_ENABLE="${aux0_check}" \
      -DEXPECT_AUX0="${aux0}" \
      -DAUX1_CHECK_ENABLE="${aux1_check}" \
      -DEXPECT_AUX1="${aux1}" \
      -DGPIO_CHECK_ENABLE="${gpio_check}" \
      -DEXPECT_GPIO="${expect_gpio}" \
      -DTIMEOUT_CYCLES="${timeout}" \
      -o "$out" "$TB" >/dev/null
    vvp "$out"
  )
  echo
done
