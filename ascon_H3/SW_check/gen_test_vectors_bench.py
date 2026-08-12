#!/usr/bin/env python3
"""gen_test_vectors_bench.py — Golden reference vectors for test_ascon_bench.c

Uses same key/nonce/AD/PT constants as the firmware tests.
Calls ascon.ascon_encrypt() (Ascon-AEAD128) to produce expected CT+TAG.

Output format matches the UART output from the firmware so they can be
compared line-by-line after a SoC simulation run.
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))
import ascon as ascon_lib

# ── Test vectors (must match firmware #defines) ──────────────────────────────
KEY   = bytes([0x00,0x01,0x02,0x03, 0x04,0x05,0x06,0x07,
               0x08,0x09,0x0A,0x0B, 0x0C,0x0D,0x0E,0x0F])
NONCE = bytes([0x10,0x11,0x12,0x13, 0x14,0x15,0x16,0x17,
               0x18,0x19,0x1A,0x1B, 0x1C,0x1D,0x1E,0x1F])

# AD = "FRMH" + frame_id=1 (big-endian 32-bit words)
AD = bytes([0x46,0x52,0x4D,0x48, 0x00,0x00,0x00,0x01])

# Single-block PT (8 bytes): TV_PT_W0 | TV_PT_W1 (big-endian)
PT_1BLOCK = bytes([0xA0,0x00,0x00,0x00, 0xB0,0x00,0x00,0x00])

# 16-block PT (128 bytes): block[i] = {0xA0000000|i, 0xB0000000|i}
PT_16BLOCK = b"".join(
    bytes([(0xA0000000 | i) >> 24, (0xA0000000 | i) >> 16 & 0xFF,
           (0xA0000000 | i) >>  8 & 0xFF, (0xA0000000 | i) & 0xFF,
           (0xB0000000 | i) >> 24, (0xB0000000 | i) >> 16 & 0xFF,
           (0xB0000000 | i) >>  8 & 0xFF, (0xB0000000 | i) & 0xFF])
    for i in range(16)
)

VARIANT = "Ascon-AEAD128"


def fmt_ct(data):
    """Format ciphertext bytes as space-separated 32-bit hex words."""
    words = [int.from_bytes(data[i:i+4], 'big') for i in range(0, len(data), 4)]
    return " ".join(f"{w:08X}" for w in words)


def run_case(label, pt, ad_bytes):
    ct_full = ascon_lib.ascon_encrypt(KEY, NONCE, ad_bytes, pt, VARIANT)
    ct   = ct_full[:-16]
    tag  = ct_full[-16:]
    print(f"[{label}]")
    print(f"  pt_bytes={len(pt)} ad_bytes={len(ad_bytes)}")
    if ct:
        print(f"  ct={fmt_ct(ct)}")
    print(f"  tag={fmt_ct(tag)}")
    print()
    return ct, tag


def main():
    print("=" * 60)
    print(" ASCON Golden Reference — gen_test_vectors_bench.py")
    print(f" Variant : {VARIANT}")
    print(f" Key     : {KEY.hex()}")
    print(f" Nonce   : {NONCE.hex()}")
    print(f" AD      : {AD.hex()}")
    print("=" * 60)
    print()

    ct_cpu_noad, tag_cpu_noad = run_case("CPU8-NOAD",  PT_1BLOCK,  b"")
    ct_cpu_ad,   tag_cpu_ad   = run_case("CPU8-AD",    PT_1BLOCK,  AD)
    ct_dma_noad, tag_dma_noad = run_case("DMA-NOAD",   PT_16BLOCK, b"")
    ct_dma_ad,   tag_dma_ad   = run_case("DMA-AD",     PT_16BLOCK, AD)

    # Cross-mode check: 1-block no-AD must be identical between CPU and DMA
    # (use only first 8B of DMA CT for comparison)
    dma_ct_1blk = ct_dma_noad[:8]
    match = (ct_cpu_noad == dma_ct_1blk and tag_cpu_noad == tag_dma_noad)
    # NOTE: CPU-direct (1 block) and DMA (1 block) should match in output CT and TAG
    # when running the same payload. Here we only check against DMA 16-block tag.
    print("[CROSS-CHECK CPU-NOAD vs DMA-1BLK]")
    print("  (run DMA with 1 block to get comparable output)")
    ct_dma_1blk, tag_dma_1blk = run_case("DMA-1BLK-NOAD", PT_1BLOCK, b"")
    match = (ct_cpu_noad == ct_dma_1blk and tag_cpu_noad == tag_dma_1blk)
    print(f"  CPU-NOAD CT  = {fmt_ct(ct_cpu_noad)}")
    print(f"  DMA-1BLK CT  = {fmt_ct(ct_dma_1blk)}")
    print(f"  CPU-NOAD TAG = {fmt_ct(tag_cpu_noad)}")
    print(f"  DMA-1BLK TAG = {fmt_ct(tag_dma_1blk)}")
    print(f"  MATCH: {'YES' if match else 'NO (expected YES)'}")


if __name__ == "__main__":
    main()
