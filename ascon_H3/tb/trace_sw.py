#!/usr/bin/env python3
"""
SW Trace — in từng bước giống hệt HW debug log để so sánh trực tiếp.
Chạy: python trace_sw.py
"""
import sys
sys.path.insert(0, '/home/claude')
import ascon

# ============================================================
# Test vectors (giống testbench)
# ============================================================
KEY   = bytes.fromhex("000102030405060708090A0B0C0D0E0F")
NONCE = bytes.fromhex("101112131415161718191A1B1C1D1E1F")
AD    = b"ASCON"
PT    = b"ascon"

def fmt(S):
    return "  ".join(f"x{i}={v:016x}" for i,v in enumerate(S))

def fmt_x0(S):
    return f"{S[0]:016x}"

def bswap64(x):
    b = x.to_bytes(8, 'big')
    return int.from_bytes(b[::-1], 'big')

def bytes_to_int_le(b):
    return int.from_bytes(b, 'little')

def int_to_bytes_le(v, n):
    return v.to_bytes(n, 'little')

SEP = "=" * 62

# ============================================================
def trace_encrypt():
    print(SEP)
    print("SW TRACE — Encryption (NIST Ascon-AEAD128)")
    print(SEP)
    print(f"  key  : {KEY.hex()}")
    print(f"  nonce: {NONCE.hex()}")
    print(f"  AD   : {AD}  ({AD.hex()})")
    print(f"  PT   : {PT}  ({PT.hex()})")
    print()

    k, a, b, rate = 128, 12, 8, 16
    version = 1
    taglen  = 128

    S = [0]*5

    # ---- INITIALIZATION ----
    print("── INITIALIZATION ──────────────────────────────────")

    # Build IV (SW: bytes, then load as LE integers)
    iv_bytes = bytes([version, 0, (b<<4)|a]) + taglen.to_bytes(2,'little') + bytes([rate, 0, 0])
    print(f"  iv_bytes    : {iv_bytes.hex()}")

    # Initial state: iv || key || nonce, each 8-byte chunk as LE int
    state_bytes = iv_bytes + KEY + NONCE
    S = [bytes_to_int_le(state_bytes[8*i:8*(i+1)]) for i in range(5)]
    print(f"  after load  : {fmt(S)}")
    # Map to HW-style: x0 = S[0]..x4 = S[4]
    print(f"  [HW expects] state_load src=00  next[319:256]={S[0]:016x}")
    print()

    # Permutation p^12
    print(f"  [HW expects] perm_start rounds=12  state[319:256]={S[0]:016x}")
    ascon.ascon_permutation(S, 12)
    print(f"  after perm12: {fmt(S)}")
    print()

    # Post-init key XOR
    # SW: zero_key = bytes_to_state(zero_bytes(40-16) + key)
    #   = state loaded from [0x00]*24 + KEY
    zero_key_bytes = bytes(24) + KEY
    zero_key = [bytes_to_int_le(zero_key_bytes[8*i:8*(i+1)]) for i in range(5)]
    print(f"  zero_key    : {' '.join(f'{v:016x}' for v in zero_key)}")
    for i in range(5):
        S[i] ^= zero_key[i]
    print(f"  after key XOR (post-init): {fmt(S)}")
    print(f"  [HW expects] state_load post_init=1  next[319:256]={S[0]:016x}")
    print()

    # ---- ASSOCIATED DATA ----
    print("── ASSOCIATED DATA ──────────────────────────────────")
    if len(AD) > 0:
        pad_len = rate - (len(AD) % rate)
        a_padding = b'\x01' + bytes(pad_len - 1)
        a_padded  = AD + a_padding
        print(f"  a_padded    : {a_padded.hex()}")

        for blk_start in range(0, len(a_padded), rate):
            blk = a_padded[blk_start:blk_start+rate]
            w0 = bytes_to_int_le(blk[0:8])
            w1 = bytes_to_int_le(blk[8:16])
            print(f"  XOR w0={w0:016x}  w1={w1:016x}  into x0/x1")
            S[0] ^= w0
            S[1] ^= w1
            print(f"  before perm8: x0={S[0]:016x}")
            print(f"  [HW expects] state_load src=01  next[319:256]={S[0]:016x}")
            print(f"  [HW expects] perm_start rounds=8  state[319:256]={S[0]:016x}")
            ascon.ascon_permutation(S, b)
            print(f"  after perm8 : {fmt(S)}")
            print(f"  [HW expects] state_load src=10  next[319:256]={S[0]:016x}")

    # Domain separation
    S[4] ^= (1 << 63)
    print(f"\n  domain sep  : x4 MSB flipped → x4={S[4]:016x}")
    print(f"  [HW expects] state_load dom_sep=1  next[319:256]={S[0]:016x}")
    print()

    # ---- PLAINTEXT ────────────────────────────────────────
    print("── PROCESS PLAINTEXT ────────────────────────────────")
    p_lastlen = len(PT) % rate
    p_padding = b'\x01' + bytes(rate - p_lastlen - 1)
    p_padded  = PT + p_padding
    print(f"  p_padded    : {p_padded.hex()}")

    # Last block only (len=5 < rate=16, so only 1 block total)
    blk = p_padded[0:rate]
    w0  = bytes_to_int_le(blk[0:8])
    w1  = bytes_to_int_le(blk[8:16])
    print(f"  XOR w0={w0:016x}  w1={w1:016x}")
    print(f"  state x0 before XOR: {S[0]:016x}")
    S[0] ^= w0
    S[1] ^= w1
    ct_w0 = S[0]
    ct_w1 = S[1]
    ct_bytes = int_to_bytes_le(ct_w0, 8)[:p_lastlen] + int_to_bytes_le(ct_w1, 8)[:max(0,p_lastlen-8)]
    print(f"  CT (LE ints): w0={ct_w0:016x}  w1={ct_w1:016x}")
    print(f"  CT bytes    : {ct_bytes.hex()}  (first {p_lastlen} bytes)")
    print(f"  [HW expects] state_load src=01  next[319:256]={S[0]:016x}")
    print()

    # ---- FINALIZATION ───────────────────────────────────────
    print("── FINALIZATION ─────────────────────────────────────")
    # SW: S[rate//8] ^= key[0:8] as LE, S[rate//8+1] ^= key[8:16] as LE
    #     rate//8 = 2 → S[2], S[3]
    k0 = bytes_to_int_le(KEY[0:8])
    k1 = bytes_to_int_le(KEY[8:16])
    print(f"  key_w0 (LE) : {k0:016x}")
    print(f"  key_w1 (LE) : {k1:016x}")
    S[2] ^= k0
    S[3] ^= k1
    print(f"  after pre-fin key XOR: {fmt(S)}")
    print(f"  [HW expects] state_load pre_fin=1  next[319:256]={S[0]:016x}")
    print()

    print(f"  [HW expects] perm_start rounds=12  state[319:256]={S[0]:016x}")
    ascon.ascon_permutation(S, 12)
    print(f"  after perm12: {fmt(S)}")
    print(f"  [HW expects] state_load src=10  next[319:256]={S[0]:016x}")
    print()

    # Tag
    S[3] ^= bytes_to_int_le(KEY[-16:-8])
    S[4] ^= bytes_to_int_le(KEY[-8:])
    tag = int_to_bytes_le(S[3], 8) + int_to_bytes_le(S[4], 8)
    print(f"  tag         : {tag.hex()}")
    print()

    print(SEP)
    print("SUMMARY")
    print(SEP)
    print(f"  CT (first {p_lastlen} bytes) : {ct_bytes.hex()}")
    print(f"  TAG                  : {tag.hex()}")
    ref_ct  = "4844624e51"
    ref_tag = "31f57794cc7d93d4d92dd5cbadb48e0b"
    print(f"  Expected CT          : {ref_ct}")
    print(f"  Expected TAG         : {ref_tag}")
    ct_match  = ct_bytes.hex() == ref_ct
    tag_match = tag.hex() == ref_tag
    print(f"  CT  {'✓ MATCH' if ct_match  else '✗ MISMATCH'}")
    print(f"  TAG {'✓ MATCH' if tag_match else '✗ MISMATCH'}")
    print()

    # Also cross-check with ascon library
    print("── Cross-check with ascon library ───────────────────")
    ct_lib = ascon.ascon_encrypt(KEY, NONCE, AD, PT)
    print(f"  library CT  : {ct_lib[:-16].hex()}")
    print(f"  library TAG : {ct_lib[-16:].hex()}")


# ============================================================
def trace_hw_init_vs_sw():
    """
    So sánh cụ thể cách HW build initial state vs SW.
    HW dùng bswap; SW dùng LE load trực tiếp.
    In ra để thấy có khớp không.
    """
    print()
    print(SEP)
    print("HW vs SW — Initial State Construction")
    print(SEP)

    # SW way
    version, a, b, rate, taglen = 1, 12, 8, 16, 128
    iv_bytes = bytes([version, 0, (b<<4)|a]) + taglen.to_bytes(2,'little') + bytes([rate, 0, 0])
    state_bytes = iv_bytes + KEY + NONCE
    SW_S = [int.from_bytes(state_bytes[8*i:8*(i+1)], 'little') for i in range(5)]
    print("SW initial state (LE load):")
    for i,v in enumerate(SW_S): print(f"  x{i} = {v:016x}")

    # HW way: INITIALIZATION bswaps key/nonce, IV is a constant
    IV_HW = 0x00001000808c0001
    def bswap(x):
        b = x.to_bytes(8,'big')
        return int.from_bytes(b[::-1],'big')

    k_hi = int.from_bytes(KEY[0:8], 'big')
    k_lo = int.from_bytes(KEY[8:16],'big')
    n_hi = int.from_bytes(NONCE[0:8],'big')
    n_lo = int.from_bytes(NONCE[8:16],'big')

    HW_S = [IV_HW, bswap(k_hi), bswap(k_lo), bswap(n_hi), bswap(n_lo)]
    print("\nHW initial state (bswap):")
    for i,v in enumerate(HW_S): print(f"  x{i} = {v:016x}")

    print("\nMatch?", ["✗ MISMATCH","✓ MATCH"][SW_S == HW_S])
    for i in range(5):
        if SW_S[i] != HW_S[i]:
            print(f"  x{i}: SW={SW_S[i]:016x}  HW={HW_S[i]:016x}")

    print()
    print(SEP)
    print("HW vs SW — Post-Init Key XOR")
    print(SEP)
    # SW: zero_key = state from [0]*24 + KEY
    zero_key_bytes = bytes(24) + KEY
    SW_zero_key = [int.from_bytes(zero_key_bytes[8*i:8*(i+1)],'little') for i in range(5)]
    print("SW zero_key:")
    for i,v in enumerate(SW_zero_key): print(f"  zk{i} = {v:016x}")

    # HW: XOR bswap(key_hi) into x3, bswap(key_lo) into x4
    hw_k_hi_bswap = bswap(k_hi)
    hw_k_lo_bswap = bswap(k_lo)
    HW_zero_key = [0, 0, 0, hw_k_hi_bswap, hw_k_lo_bswap]
    print("HW key XOR (post-init into x3/x4):")
    for i,v in enumerate(HW_zero_key): print(f"  hk{i} = {v:016x}")

    print("\nMatch?", ["✗ MISMATCH","✓ MATCH"][SW_zero_key == HW_zero_key])
    for i in range(5):
        if SW_zero_key[i] != HW_zero_key[i]:
            print(f"  idx{i}: SW={SW_zero_key[i]:016x}  HW={HW_zero_key[i]:016x}")


if __name__ == "__main__":
    trace_hw_init_vs_sw()
    print()
    trace_encrypt()