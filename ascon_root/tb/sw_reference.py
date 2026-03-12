#!/usr/bin/env python3
"""
sw_reference.py  –  Software reference output cho Ascon-128 AEAD
Sử dụng ĐÚNG cùng inputs với testbench Verilog (ascon_top_tb.v)

Usage:
    python sw_reference.py               # in kết quả default
    python sw_reference.py --compare     # in format dễ so sánh với HW log
    python sw_reference.py --no-ad       # tính CT cho trường hợp không có AD (Test 4)
"""

import sys
import argparse

# Import module ascon (phải cùng thư mục)
try:
    import ascon
except ImportError:
    print("[ERROR] Không tìm thấy ascon.py – đặt file này cùng thư mục với ascon.py")
    sys.exit(1)

# ============================================================
#  INPUTS – khớp với localparam trong ascon_top_tb.v
# ============================================================

KEY   = bytes(range(16))       # 000102030405060708090A0B0C0D0E0F
NONCE = bytes(range(16, 32))   # 101112131415161718191A1B1C1D1E1F
AD    = b"ASCON"               # 4153434F4E  (5 bytes)
PT    = b"ascon"               # 6173636F6E  (5 bytes)


def bytes_to_hex128(b: bytes) -> str:
    """Pad bytes to 16 bytes, return 32-char hex (big-endian, upper)."""
    padded = b.ljust(16, b'\x00')[:16]
    return padded.hex().upper()


def run_encrypt(key, nonce, ad, pt, label="WITH AD"):
    print(f"\n{'='*54}")
    print(f"  ENCRYPT  ({label})")
    print(f"{'='*54}")
    print(f"  Key        : {key.hex().upper()}")
    print(f"  Nonce      : {nonce.hex().upper()}")
    print(f"  AD         : '{ad.decode(errors='replace')}' = {ad.hex().upper()} ({len(ad)} bytes)")
    print(f"  Plaintext  : '{pt.decode(errors='replace')}' = {pt.hex().upper()} ({len(pt)} bytes)")

    ct_full = ascon.ascon_encrypt(key, nonce, ad, pt)
    ct_only = ct_full[:-16]
    tag     = ct_full[-16:]

    ct_hex128  = bytes_to_hex128(ct_only)
    tag_hex128 = bytes_to_hex128(tag)
    pt_hex128  = bytes_to_hex128(pt)

    print(f"\n  --- SW Reference Output ---")
    print(f"  Ciphertext : {ct_only.hex().upper()} ({len(ct_only)} bytes)")
    print(f"  Tag        : {tag.hex().upper()} (16 bytes)")
    print()
    print(f"  --- 128-bit format (to compare with Verilog $display) ---")
    print(f"  CT  (128b) : {ct_hex128}  // only [{len(pt)*8-1}:0] valid")
    print(f"  TAG (128b) : {tag_hex128}")
    print(f"  PT  (128b) : {pt_hex128}  // only [{len(pt)*8-1}:0] valid")

    return ct_only, tag


def run_decrypt(key, nonce, ad, ct_only, tag, pt_ref, label="WITH AD"):
    print(f"\n{'='*54}")
    print(f"  DECRYPT  ({label})")
    print(f"{'='*54}")

    ct_full = ct_only + tag
    result = ascon.ascon_decrypt(key, nonce, ad, ct_full)

    if result is None:
        print("  [FAIL] Tag verification FAILED!")
    else:
        match = (result == pt_ref)
        print(f"  Decrypted  : {result.hex().upper()} ({len(result)} bytes)")
        print(f"  Expected   : {pt_ref.hex().upper()} ({len(pt_ref)} bytes)")
        print(f"  Tag match  : {'OK ✓' if match else 'MISMATCH ✗'}")


def run_tamper_test(key, nonce, ad, ct_only, tag):
    print(f"\n{'='*54}")
    print(f"  TAMPER TEST (expect FAIL)")
    print(f"{'='*54}")

    # Flip last bit of ciphertext (same as TB: ct ^ 128'h1)
    ct_tampered = bytes(ct_only[:-1]) + bytes([ct_only[-1] ^ 0x01])
    ct_full = ct_tampered + tag
    result = ascon.ascon_decrypt(key, nonce, ad, ct_full)

    if result is None:
        print("  [PASS] Tag mismatch correctly detected (result = None)")
    else:
        print("  [FAIL] Should have failed but got:", result.hex().upper())


def print_verilog_params():
    """In ra các localparam để copy vào Verilog TB."""
    print(f"\n{'='*54}")
    print(f"  VERILOG localparam VALUES")
    print(f"{'='*54}")
    print(f'  localparam [127:0] TEST_KEY   = 128\'h{KEY.hex().upper()};')
    print(f'  localparam [127:0] TEST_NONCE = 128\'h{NONCE.hex().upper()};')
    print(f'  localparam [127:0] TEST_AD    = 128\'h{bytes_to_hex128(AD)};  // "{AD.decode()}"')
    print(f'  localparam [127:0] TEST_PT    = 128\'h{bytes_to_hex128(PT)};  // "{PT.decode()}"')
    print(f'  localparam [6:0]   PT_LEN     = 7\'d{len(PT)};')
    print(f'  localparam [6:0]   AD_LEN     = 7\'d{len(AD)};')

    ct_full = ascon.ascon_encrypt(KEY, NONCE, AD, PT)
    ct_only = ct_full[:-16]
    tag     = ct_full[-16:]
    print(f'  localparam [127:0] REF_CT     = 128\'h{bytes_to_hex128(ct_only)};  // {len(ct_only)} bytes valid')
    print(f'  localparam [127:0] REF_TAG    = 128\'h{bytes_to_hex128(tag)};')


def main():
    parser = argparse.ArgumentParser(description="Ascon SW reference – matched to Verilog TB inputs")
    parser.add_argument("--compare", action="store_true",
                        help="In format dễ so sánh với HW simulation log")
    parser.add_argument("--no-ad", action="store_true",
                        help="Thêm test không có AD (ad_valid=0, Test 4)")
    parser.add_argument("--params", action="store_true",
                        help="In Verilog localparam để copy vào TB")
    args = parser.parse_args()

    print("\n" + "="*54)
    print("  Ascon-128 SW Reference  (run_auto.py SW defaults)")
    print("="*54)

    # Test 1: Encrypt
    ct_only, tag = run_encrypt(KEY, NONCE, AD, PT, label="Test 1 – WITH AD")

    # Test 2: Decrypt
    run_decrypt(KEY, NONCE, AD, ct_only, tag, PT, label="Test 2 – WITH AD")

    # Test 3: Tamper
    run_tamper_test(KEY, NONCE, AD, ct_only, tag)

    # Test 4: No AD
    if args.no_ad:
        ct_no_ad, tag_no_ad = run_encrypt(KEY, NONCE, b"", PT, label="Test 4 – NO AD")

    if args.params:
        print_verilog_params()

    print(f"\n{'='*54}")
    print("  QUICK COMPARISON TABLE")
    print(f"{'='*54}")
    print("  Signal          SW value (hex, 128-bit)")
    print("  --------------  --------------------------------")
    print(f"  TEST_PT         {bytes_to_hex128(PT)}")
    print(f"  REF_CT          {bytes_to_hex128(ct_only)}")
    print(f"  REF_TAG         {bytes_to_hex128(tag)}")
    print()
    print("  Compare with Verilog $display output:")
    print("    HW Ciphertext  : xxxx...  ← should match REF_CT above")
    print("    HW Tag         : xxxx...  ← should match REF_TAG above")
    print()
    print("  Run SW with same params:")
    print("    python run_auto.py --aead \\")
    print("      --key   000102030405060708090A0B0C0D0E0F \\")
    print("      --nonce 101112131415161718191A1B1C1D1E1F \\")
    print("      --ad ASCON --plaintext ascon")
    print()


if __name__ == "__main__":
    main()