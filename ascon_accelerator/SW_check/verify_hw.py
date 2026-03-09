#!/usr/bin/env python3
"""
verify_hw.py - Sinh test vectors từ SW reference để Verilog TB verify HW

Output file: ascon_hw_vectors.tv
Format mỗi dòng:
  MODE OP KEY NONCE PT_LEN PT_HEX AD_LEN AD_HEX CT_HEX TAG_HEX

Trong đó:
  MODE : 0 = Ascon-AEAD128
  OP   : 0 = encrypt, 1 = decrypt
  KEY  : 32 hex chars (128-bit)
  NONCE: 32 hex chars (128-bit)
  PT_LEN: decimal, số bytes của plaintext
  PT_HEX: hex string (PT_LEN*2 chars), "00" nếu PT_LEN=0
  AD_LEN: decimal, số bytes của associated data
  AD_HEX: hex string, "00" nếu AD_LEN=0
  CT_HEX: hex string = ciphertext only (không gồm tag), "00" nếu rỗng
  TAG_HEX: 32 hex chars (128-bit tag)

Dòng bắt đầu bằng '#' là comment, TB có thể bỏ qua.

Cách dùng:
  python verify_hw.py                   # sinh 10 random AEAD test case
  python verify_hw.py --mode aead --count 20
  python verify_hw.py --mode permutation --rounds 12
  python verify_hw.py --mode all        # AEAD + permutation
  python verify_hw.py --fixed           # dùng input cố định (dễ debug RTL)
"""

import argparse
import random
import sys
import os

# ── Import ascon từ cùng thư mục ──────────────────────────────────────────────
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import ascon
except ImportError:
    print("[ERROR] Không tìm thấy ascon.py. Đặt verify_hw.py cùng thư mục với ascon.py")
    sys.exit(1)

# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def hex_or_zero(b: bytes) -> str:
    """Trả về hex string, hoặc '00' nếu rỗng (để TB không gặp field trống)."""
    return b.hex().upper() if b else "00"

def rand_bytes(n: int) -> bytes:
    return bytes([random.randint(0, 255) for _ in range(n)])

# ══════════════════════════════════════════════════════════════════════════════
#  SINH VECTORS AEAD
# ══════════════════════════════════════════════════════════════════════════════

def gen_aead_vectors(count: int, fixed: bool = False) -> list[dict]:
    """
    Trả về list các dict chứa đủ thông tin cho 1 test case AEAD.
    fixed=True: dùng key/nonce/pt/ad cố định, chỉ thay đổi độ dài.
    """
    vectors = []

    if fixed:
        # Dùng pattern 0x00..FF dễ nhìn trên waveform
        key   = bytes(range(16))                        # 00 01 02 ... 0F
        nonce = bytes(range(0x10, 0x20))                # 10 11 12 ... 1F
        pt_pool = bytes(range(32))                      # 00 01 ... 1F
        ad_pool = bytes([0xAA, 0xBB, 0xCC, 0xDD,
                         0xEE, 0xFF, 0x11, 0x22,
                         0x33, 0x44, 0x55, 0x66,
                         0x77, 0x88, 0x99, 0x00])

        # Tạo các combination pt_len x ad_len nhỏ để phủ edge-case
        combos = [
            (0, 0), (0, 4), (0, 16),
            (1, 0), (1, 8),
            (8, 0), (8, 8), (8, 16),
            (16, 0), (16, 16),
            (20, 12), (32, 0), (32, 32),
        ]
        # Giới hạn theo count
        combos = combos[:count]
        for idx, (pt_len, ad_len) in enumerate(combos):
            pt = pt_pool[:pt_len]
            ad = ad_pool[:ad_len]
            ct_full = ascon.ascon_encrypt(key, nonce, ad, pt, "Ascon-AEAD128")
            ct_only = ct_full[:-16]
            tag     = ct_full[-16:]
            vectors.append({
                "count"  : idx + 1,
                "mode"   : 0,
                "op"     : 0,
                "key"    : key,
                "nonce"  : nonce,
                "pt_len" : pt_len,
                "pt"     : pt,
                "ad_len" : ad_len,
                "ad"     : ad,
                "ct"     : ct_only,
                "tag"    : tag,
            })
    else:
        for idx in range(count):
            key    = rand_bytes(16)
            nonce  = rand_bytes(16)
            pt_len = random.randint(0, 32)
            ad_len = random.randint(0, 16)
            pt     = rand_bytes(pt_len)
            ad     = rand_bytes(ad_len)

            ct_full = ascon.ascon_encrypt(key, nonce, ad, pt, "Ascon-AEAD128")
            ct_only = ct_full[:-16]
            tag     = ct_full[-16:]

            # Thêm 1 decrypt test ngay sau encrypt để TB tự verify round-trip
            vectors.append({
                "count"  : idx * 2 + 1,
                "mode"   : 0,
                "op"     : 0,      # encrypt
                "key"    : key,
                "nonce"  : nonce,
                "pt_len" : pt_len,
                "pt"     : pt,
                "ad_len" : ad_len,
                "ad"     : ad,
                "ct"     : ct_only,
                "tag"    : tag,
            })
            vectors.append({
                "count"  : idx * 2 + 2,
                "mode"   : 0,
                "op"     : 1,      # decrypt (dùng ct+tag từ encrypt ở trên)
                "key"    : key,
                "nonce"  : nonce,
                "pt_len" : pt_len,
                "pt"     : pt,     # expected plaintext (TB so sánh output HW)
                "ad_len" : ad_len,
                "ad"     : ad,
                "ct"     : ct_only,
                "tag"    : tag,
            })

    return vectors


# ══════════════════════════════════════════════════════════════════════════════
#  SINH VECTORS PERMUTATION
# ══════════════════════════════════════════════════════════════════════════════

def gen_permutation_vectors(rounds_list: list[int] = [12, 8, 6],
                            fixed: bool = False) -> list[dict]:
    """
    Sinh test vector cho permutation-only test.
    Format khác AEAD: chỉ có X0..X4 in và X0..X4 out.
    """
    import copy

    vectors = []
    idx = 1

    state_patterns = [
        [0x0000000000000000] * 5,                                    # all zero
        [0x1111111111111111,0x2222222222222222,0x3333333333333333,
         0x4444444444444444,0x5555555555555555],                      # pattern
        [0x0123456789ABCDEF,0xFEDCBA9876543210,0x0011223344556677,
         0x8899AABBCCDDEEFF,0x1122334455667788],                      # reference
        [0x0F0F0F0F0F0F0F0F,0xF0F0F0F0F0F0F0F0,0xA5A5A5A5A5A5A5A5,
         0x5A5A5A5A5A5A5A5A,0xFFFFFFFFFFFFFFFF],                     # từ hdsd.txt
    ]

    if not fixed:
        # Thêm vài state random
        for _ in range(3):
            state_patterns.append([random.randint(0, 0xFFFFFFFFFFFFFFFF) for _ in range(5)])

    for rounds in rounds_list:
        for state_in in state_patterns:
            state = list(state_in)          # copy vì ascon_permutation mutate in-place
            ascon.ascon_permutation(state, rounds)
            vectors.append({
                "count"    : idx,
                "rounds"   : rounds,
                "x_in"     : list(state_in),
                "x_out"    : list(state),
            })
            idx += 1

    return vectors


# ══════════════════════════════════════════════════════════════════════════════
#  GHI FILE .tv
# ══════════════════════════════════════════════════════════════════════════════

def write_aead_tv(vectors: list[dict], filepath: str):
    """
    Ghi file test vector AEAD cho Verilog TB.

    Format:
      # comment
      COUNT MODE OP KEY NONCE PT_LEN PT_HEX AD_LEN AD_HEX CT_HEX TAG_HEX

    TB đọc bằng $fscanf với format string tương ứng.
    """
    with open(filepath, "w") as f:
        f.write("# ============================================================\n")
        f.write("# ASCON-AEAD128 Test Vectors - generated by verify_hw.py\n")
        f.write("# SW reference: ascon.py (NIST SP 800-232)\n")
        f.write("#\n")
        f.write("# COLUMNS:\n")
        f.write("#   COUNT  : test case index (decimal)\n")
        f.write("#   MODE   : 0=Ascon-AEAD128\n")
        f.write("#   OP     : 0=encrypt  1=decrypt\n")
        f.write("#   KEY    : 128-bit key (32 hex chars)\n")
        f.write("#   NONCE  : 128-bit nonce (32 hex chars)\n")
        f.write("#   PT_LEN : plaintext length in bytes (decimal)\n")
        f.write("#   PT_HEX : plaintext hex (PT_LEN*2 chars, '00' if empty)\n")
        f.write("#   AD_LEN : associated data length in bytes (decimal)\n")
        f.write("#   AD_HEX : associated data hex ('00' if empty)\n")
        f.write("#   CT_HEX : ciphertext hex without tag ('00' if empty)\n")
        f.write("#   TAG_HEX: 128-bit authentication tag (32 hex chars)\n")
        f.write("# ============================================================\n")
        f.write("#\n")

        for v in vectors:
            f.write(
                f"{v['count']} "
                f"{v['mode']} "
                f"{v['op']} "
                f"{v['key'].hex().upper()} "
                f"{v['nonce'].hex().upper()} "
                f"{v['pt_len']} "
                f"{hex_or_zero(v['pt'])} "
                f"{v['ad_len']} "
                f"{hex_or_zero(v['ad'])} "
                f"{hex_or_zero(v['ct'])} "
                f"{v['tag'].hex().upper()}\n"
            )

    print(f"[OK] Đã ghi {len(vectors)} AEAD vectors → {filepath}")


def write_permutation_tv(vectors: list[dict], filepath: str):
    """
    Ghi file test vector permutation cho Verilog TB.

    Format:
      COUNT ROUNDS X0_IN X1_IN X2_IN X3_IN X4_IN X0_OUT X1_OUT X2_OUT X3_OUT X4_OUT
    """
    with open(filepath, "w") as f:
        f.write("# ============================================================\n")
        f.write("# ASCON Permutation Test Vectors - generated by verify_hw.py\n")
        f.write("#\n")
        f.write("# COLUMNS:\n")
        f.write("#   COUNT  : test case index (decimal)\n")
        f.write("#   ROUNDS : number of permutation rounds (6, 8, or 12)\n")
        f.write("#   X0_IN .. X4_IN  : input state (5 x 16 hex chars = 64-bit each)\n")
        f.write("#   X0_OUT .. X4_OUT: expected output state\n")
        f.write("# ============================================================\n")
        f.write("#\n")

        for v in vectors:
            xi = " ".join(f"{x:016X}" for x in v["x_in"])
            xo = " ".join(f"{x:016X}" for x in v["x_out"])
            f.write(f"{v['count']} {v['rounds']} {xi} {xo}\n")

    print(f"[OK] Đã ghi {len(vectors)} permutation vectors → {filepath}")


# ══════════════════════════════════════════════════════════════════════════════
#  IN SUMMARY ra màn hình
# ══════════════════════════════════════════════════════════════════════════════

def print_summary_aead(vectors: list[dict]):
    print("\n── AEAD Test Vector Summary ─────────────────────────────────────")
    print(f"  Total vectors : {len(vectors)}")
    enc = sum(1 for v in vectors if v['op'] == 0)
    dec = sum(1 for v in vectors if v['op'] == 1)
    print(f"  Encrypt       : {enc}")
    print(f"  Decrypt       : {dec}")
    # In 2 vector đầu để người dùng check nhanh
    for v in vectors[:2]:
        op_str = "ENC" if v['op'] == 0 else "DEC"
        print(f"\n  [{v['count']}] {op_str}")
        print(f"    KEY   : {v['key'].hex().upper()}")
        print(f"    NONCE : {v['nonce'].hex().upper()}")
        print(f"    PT    : {hex_or_zero(v['pt'])} (len={v['pt_len']})")
        print(f"    AD    : {hex_or_zero(v['ad'])} (len={v['ad_len']})")
        print(f"    CT    : {hex_or_zero(v['ct'])}")
        print(f"    TAG   : {v['tag'].hex().upper()}")
    if len(vectors) > 2:
        print(f"\n  ... và {len(vectors)-2} vectors nữa trong file.")
    print("─────────────────────────────────────────────────────────────────\n")


# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="Sinh test vectors ASCON cho Verilog Testbench",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python verify_hw.py                          # 10 AEAD random vectors
  python verify_hw.py --count 20               # 20 AEAD random vectors
  python verify_hw.py --fixed                  # AEAD vectors cố định (dễ debug)
  python verify_hw.py --mode permutation       # Permutation vectors (rounds 6,8,12)
  python verify_hw.py --mode permutation --rounds 12
  python verify_hw.py --mode all --count 10    # Cả AEAD + permutation
  python verify_hw.py --out my_vectors.tv      # Đổi tên file output
        """
    )
    parser.add_argument("--mode", choices=["aead", "permutation", "all"],
                        default="aead", help="Loại test vector cần sinh (default: aead)")
    parser.add_argument("--count", type=int, default=10,
                        help="Số lượng test case AEAD (default: 10)")
    parser.add_argument("--rounds", type=int, default=None,
                        help="Số rounds cho permutation test (default: sinh cả 6,8,12)")
    parser.add_argument("--fixed", action="store_true",
                        help="Dùng input cố định thay vì random (tốt để debug RTL lần đầu)")
    parser.add_argument("--out", type=str, default=None,
                        help="Tên file output (default: ascon_aead_vectors.tv hoặc ascon_perm_vectors.tv)")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed để kết quả tái tạo được (default: 42)")

    args = parser.parse_args()
    random.seed(args.seed)

    if args.mode in ("aead", "all"):
        vectors = gen_aead_vectors(args.count, fixed=args.fixed)
        out_path = args.out if args.out else "ascon_aead_vectors.tv"
        write_aead_tv(vectors, out_path)
        print_summary_aead(vectors)

    if args.mode in ("permutation", "all"):
        rounds_list = [args.rounds] if args.rounds else [6, 8, 12]
        perm_vectors = gen_permutation_vectors(rounds_list, fixed=args.fixed)
        perm_out = ("ascon_perm_vectors.tv" if args.out is None
                    else args.out.replace(".tv", "_perm.tv"))
        write_permutation_tv(perm_vectors, perm_out)


if __name__ == "__main__":
    main()