#!/usr/bin/env python3
"""
SW reference cho ASCON image encryption — emulate HW DMA behavior:
  - 8-byte DMA block size (data_len=64 > rate=16 → apply_padding không insert 0x01 vào x1)
  - Chỉ x0 XOR với PT mỗi block; x1 không thay đổi trong XOR phase
  - Permutation pb=8 sau mỗi block trừ block cuối
  - Finalization giống Ascon-AEAD128 chuẩn (rate=16, pa=12)
  - Output: chỉ lấy x0 (upper 64-bit) của data_out per block
"""
import sys, os, time
sys.path.insert(0, os.path.dirname(__file__))
import ascon as L

KEY   = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
NONCE = bytes.fromhex("101112131415161718191a1b1c1d1e1f")
AD    = b""

# 8x8 grayscale gradient — 64 bytes
IMAGE = bytes([(r * 8 + c) * 4 % 256 for r in range(8) for c in range(8)])

BLOCK_SIZE = 8   # DMA block = 8 bytes


def ascon_hw_encrypt(key, nonce, ad, plaintext):
    """
    Emulate HW ASCON DMA encryption:
    - Init + AD: identical to Ascon-AEAD128 (k=128, rate=16, a=12, b=8)
    - Data: 8-byte blocks, x0 XOR only (x1 unchanged), pb=8 between blocks
    - Finalize: Ascon-AEAD128 standard (rate=16, pa=12)
    Returns (ciphertext_bytes, tag_bytes)
    """
    S = [0]*5
    L.ascon_initialize(S, 128, 16, 12, 8, 1, key, nonce)
    L.ascon_process_associated_data(S, 8, 16, ad)

    n_blocks = (len(plaintext) + BLOCK_SIZE - 1) // BLOCK_SIZE
    ct = b""
    for i in range(n_blocks):
        blk = plaintext[i*BLOCK_SIZE:(i+1)*BLOCK_SIZE]
        blk = blk + bytes(BLOCK_SIZE - len(blk))
        S[0] ^= L.bytes_to_int(blk)
        ct += L.int_to_bytes(S[0], 8)
        if i < n_blocks - 1:
            L.ascon_permutation(S, 8)

    tag = L.ascon_finalize(S, 16, 12, key)
    return ct, tag


# 1. Encrypt once → CT, TAG
ct, tag = ascon_hw_encrypt(KEY, NONCE, AD, IMAGE)

# 2. Benchmark: N lần, tính avg µs và MB/s
N = 5000
for _ in range(100): ascon_hw_encrypt(KEY, NONCE, AD, IMAGE)  # warmup
t0 = time.perf_counter()
for _ in range(N): ascon_hw_encrypt(KEY, NONCE, AD, IMAGE)
elapsed = time.perf_counter() - t0
avg_us  = elapsed / N * 1e6
tput_mb = len(IMAGE) / (elapsed / N) / 1e6

# 3. In kết quả
print(f"IMAGE  : {IMAGE.hex().upper()}")
print(f"CT     : {ct.hex().upper()}")
print(f"TAG    : {tag.hex().upper()}")
print(f"SW time: {avg_us:.3f} µs/op  ({tput_mb:.2f} MB/s = {tput_mb*8:.1f} Mbps)")

# 4. Ghi test vector
out = os.path.join(os.path.dirname(__file__), "..", "..", "pic_test_vectors.hex")
out = os.path.normpath(out)
with open(out, "w") as f:
    f.write("// HW ASCON DMA pic test vector\n")
    f.write("// Format: HW_MODE KEY NONCE AD_LEN AD PT_LEN PT CT TAG\n")
    f.write("// Image: 8x8 grayscale 64 bytes | HW: 8-byte DMA blocks, x0-only XOR\n")
    f.write(
        f"1 {KEY.hex().upper()} {NONCE.hex().upper()} "
        f"0000 00 "
        f"0040 {IMAGE.hex().upper()} "
        f"{ct.hex().upper()} {tag.hex().upper()}\n"
    )
print(f"Written: {out}")
