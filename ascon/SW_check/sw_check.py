# =========================
# ASCON Reference Model
# =========================

MASK64 = 0xFFFFFFFFFFFFFFFF

# -------- Rotate Right --------
def rotr(x, n):
    return ((x >> n) | (x << (64 - n))) & MASK64


# -------- Print State --------
def print_state(tag, x):
    print(f"{tag}:")
    for i in range(5):
        print(f"  x{i} = {x[i]:016x}")
    print()


# -------- Add Round Constant --------
RC = [
    0xF0, 0xE1, 0xD2, 0xC3, 0xB4, 0xA5,
    0x96, 0x87, 0x78, 0x69, 0x5A, 0x4B
]

def add_constant(x, r):
    x[2] ^= RC[r]
    x[2] &= MASK64
    return x


# -------- Substitution Layer (S-box) --------
def sbox_layer(x):
    x0, x1, x2, x3, x4 = x

    x0 ^= x4
    x4 ^= x3
    x2 ^= x1

    t0 = (~x0) & x1
    t1 = (~x1) & x2
    t2 = (~x2) & x3
    t3 = (~x3) & x4
    t4 = (~x4) & x0

    x0 ^= t1
    x1 ^= t2
    x2 ^= t3
    x3 ^= t4
    x4 ^= t0

    x1 ^= x0
    x0 ^= x4
    x3 ^= x2
    x2 = ~x2

    return [
        x0 & MASK64,
        x1 & MASK64,
        x2 & MASK64,
        x3 & MASK64,
        x4 & MASK64
    ]


# -------- Linear Diffusion --------
def linear_diffusion(x):
    x[0] ^= rotr(x[0], 19) ^ rotr(x[0], 28)
    x[1] ^= rotr(x[1], 61) ^ rotr(x[1], 39)
    x[2] ^= rotr(x[2], 1)  ^ rotr(x[2], 6)
    x[3] ^= rotr(x[3], 10) ^ rotr(x[3], 17)
    x[4] ^= rotr(x[4], 7)  ^ rotr(x[4], 41)

    return [v & MASK64 for v in x]


# -------- One ASCON Round --------
def ascon_round(x, r, verbose=True):
    if verbose:
        print(f"==== ROUND {r} ====")
        print_state("Input", x)

    x = add_constant(x, r)
    if verbose:
        print_state("After AddConstant", x)

    x = sbox_layer(x)
    if verbose:
        print_state("After S-box", x)

    x = linear_diffusion(x)
    if verbose:
        print_state("After LinearDiff", x)

    return x


# -------- ASCON Permutation --------
def ascon_permutation(x, rounds=12, verbose=True):
    for r in range(12 - rounds, 12):
        x = ascon_round(x, r, verbose)
    return x


# -------- Testbench --------
def main():
    # Example test vector (easy for RTL debug)
    state = [
        0x0000000000000000,
        0x1111111111111111,
        0x2222222222222222,
        0x3333333333333333,
        0x4444444444444444
    ]

    print("===== ASCON PERMUTATION TEST =====")
    print_state("Initial State", state)

    out = ascon_permutation(state, rounds=12, verbose=True)

    print("===== FINAL OUTPUT =====")
    print_state("Final State", out)


if __name__ == "__main__":
    main()
