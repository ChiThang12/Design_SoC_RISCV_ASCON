#!/usr/bin/env bash
# ============================================
# lint_verilog.sh
# Usage:
#   ./lint_verilog.sh cpu.v
#   ./lint_verilog.sh -g2012 cpu.v
# ============================================

STD=""
SRC=""

if [[ "$1" == "-g2001" || "$1" == "-g2005" || "$1" == "-g2012" ]]; then
    STD="$1"
    SRC="$2"
else
    SRC="$1"
fi

if [[ -z "$SRC" ]]; then
    echo "[ERROR] Missing verilog file!"
    echo "Usage:"
    echo "  ./lint_verilog.sh cpu.v"
    echo "  ./lint_verilog.sh -g2012 cpu.v"
    exit 1
fi

echo "============================================"
echo "Linting   : $SRC"
if [[ -z "$STD" ]]; then
    echo "Standard : default"
else
    echo "Standard : $STD"
fi
echo "============================================"

iverilog $STD -Wall -tnull "$SRC" || exit 1

echo "--------------------------------------------"
echo "Lint finished with no fatal errors."
echo "============================================"
