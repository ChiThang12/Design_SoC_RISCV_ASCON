#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}      RISC-V C -> HEX -> MO PHONG        ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo

# Step 1: Compile C -> HEX
echo -e "${YELLOW}[1/2] Dang bien dich example.c -> program.hex...${NC}"
./compile_c_to_hex.sh -i example.c -o program.hex -c -O2

echo -e "${GREEN}[OK] Bien dich thanh cong!${NC}"
echo

# Step 2: Run simulation
echo -e "${YELLOW}[2/2] Dang chay mo phong voi vvp...${NC}"
if ! command -v vvp &> /dev/null; then
    echo -e "${RED}[LOI] Khong tim thay vvp! Can cai Icarus Verilog.${NC}"
    exit 1
fi

vvp run_program.vvp

echo
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}           HOAN TAT!                     ${NC}"
echo -e "${BLUE}=========================================${NC}"

