# Ascon Core – Module Documentation

## Tổng quan kiến trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                          ascon_CORE (Top)                        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    ASCON CONTROLLER (FSM)                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│        │ control signals                                         │
│   ┌────▼──────┐   ┌──────────────────┐   ┌──────────────────┐  │
│   │   INIT    │──▶│  STATE REGISTER  │──▶│  TAG GENERATOR   │  │
│   │           │   │    (320-bit)     │   └────────┬─────────┘  │
│   ├───────────┤   │                  │            │             │
│   │ DATAPATH  │──▶│                  │   ┌────────▼─────────┐  │
│   │(XOR/PAD)  │   │                  │   │  TAG COMPARATOR  │  │
│   └───────────┘   └────────┬─────────┘   └──────────────────┘  │
│                             │ ▲                                  │
│                   ┌─────────▼─┴──────────┐                     │
│                   │     PERMUTATION       │  ← bạn đã có        │
│                   │  (Const+Sub+Diffuse)  │                     │
│                   └──────────────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Danh sách file

| File | Module | Mô tả |
|------|--------|-------|
| `ascon_CORE.v` | `ascon_CORE` | Top-level wrapper, nối tất cả sub-module |
| `ascon_CONTROLLER.v` | `ascon_CONTROLLER` | FSM điều phối toàn bộ luồng AEAD |
| `ascon_INITIALIZATION.v` | `ascon_INITIALIZATION` | Load Key/Nonce, tạo state ban đầu |
| `ascon_DATAPATH.v` | `ascon_DATAPATH` | XOR plaintext/ciphertext, padding |
| `ascon_STATE_REGISTER.v` | `ascon_STATE_REGISTER` | Lưu 320-bit state, mux 3 nguồn |
| `ascon_TAG_GENERATOR.v` | `ascon_TAG_GENERATOR` | Tạo authentication tag 128-bit |
| `ascon_TAG_COMPARATOR.v` | `ascon_TAG_COMPARATOR` | So sánh tag (constant-time) |
| `ascon_PERMUTATION.v` | `ascon_PERMUTATION` | **Bạn đã có** – không thay đổi |
| `tb_ascon_CORE.v` | `tb_ascon_CORE` | Testbench 4 test case |

---

## Mô tả từng module

### 1. `ascon_INITIALIZATION`

**Interface:**
```verilog
input  load_key, load_nonce   // pulse để latch key/nonce
input  [1:0] mode             // 00=Ascon-128, 01=Ascon-128a, 10=Hash
input  init_start             // pulse tạo init state
input  [127:0] key_in, nonce_in
output [319:0] init_state_out
output init_valid
```

**Chức năng:**  
Ghép IV (64-bit, chọn theo `mode`) + Key (128-bit) + Nonce (128-bit) thành state 320-bit ban đầu:
```
state = IV || Key[127:64] || Key[63:0] || Nonce[127:64] || Nonce[63:0]
```

| Mode | IV |
|------|----|
| Ascon-128  | `0x80400c0600000000` |
| Ascon-128a | `0x80800c0800000000` |
| Ascon-Hash | `0x00400c0000000100` |

---

### 2. `ascon_DATAPATH`

**Interface:**
```verilog
input  [1:0] mode             // rate: 64b (128) hoặc 128b (128a)
input  enc_dec                // 0=encrypt, 1=decrypt
input  pad_enable             // áp dụng padding cho block cuối
input  [1:0] block_sel        // 00=AD, 01=PT/CT, 10=Final
input  [127:0] data_in
input  [6:0]  data_len        // bytes hợp lệ trong block cuối
input  [319:0] state_in
output [319:0] state_xored    // state sau XOR
output [127:0] data_out       // CT hoặc PT output
output data_out_valid
```

**Chức năng:**
- **Encrypt:** `C = x0 XOR P; x0 = C`
- **Decrypt:** `P = x0 XOR C; x0 = C` (ciphertext thay vào state)
- **Padding:** thêm byte `0x80` tại vị trí `data_len`, zero-fill phần còn lại
- Rate: Ascon-128 = 64-bit, Ascon-128a = 128-bit

---

### 3. `ascon_STATE_REGISTER`

**Interface:**
```verilog
input [1:0] src_sel  // 00=INIT, 01=DATAPATH, 10=PERMUTATION
input load           // enable latch
input [319:0] init_state, dp_state, perm_state
output reg [319:0] state_out
```

**Chức năng:**  
Thanh ghi 320-bit đơn giản với 3-to-1 mux, load theo cạnh dương clock.

---

### 4. `ascon_TAG_GENERATOR`

**Interface:**
```verilog
input  gen_tag          // pulse
input  [319:0] state_in // state sau permutation finalization
input  [127:0] key_in
output [127:0] tag_out
output tag_valid
```

**Chức năng (Ascon-128):**
```
tag = (x3 XOR key_high) || (x4 XOR key_low)
    = state[127:64] XOR key[127:64] || state[63:0] XOR key[63:0]
```

---

### 5. `ascon_TAG_COMPARATOR`

**Interface:**
```verilog
input  compare
input  [127:0] tag_computed, tag_received
output tag_match    // 1 = authentic
output tag_done
```

**Chức năng:**  
So sánh constant-time: `diff = tag_computed XOR tag_received; match = (diff == 0)`  
Tránh timing side-channel attack.

---

### 6. `ascon_CONTROLLER` (FSM)

**Luồng trạng thái:**

```
IDLE
 └─start──► LOAD_KEY ──► LOAD_NONCE ──► INIT ──► INIT_PERM ──► INIT_PERM_W
                                                                      │
                                              ┌───────────────────────┘
                                              ▼
                                         ABSORB_AD ──► AD_PERM_W
                                              │              │
                                          (no AD)     ◄──────┘
                                              ▼
                                         DOM_SEP ──► PROC_DATA ──► DATA_PERM_W
                                                         │               │
                                                     (last)        ◄─────┘
                                                         ▼
                                                    FINALIZE ──► FIN_PERM_W
                                                                      │
                                                                  GEN_TAG
                                                                      │
                                                            (dec) CMP_TAG
                                                                      │
                                                                    DONE
```

**Rounds:**

| Phase | Rounds |
|-------|--------|
| Initialization permutation | 12 |
| AD / Data permutation (Ascon-128) | 6 |
| AD / Data permutation (Ascon-128a) | 8 |
| Finalization permutation | 12 |

---

### 7. `ascon_CORE` (Top-level)

Nối tất cả module với nhau. Bổ sung thêm 3 phép biến đổi đặc biệt:

| Thao tác | Vị trí trong luồng | Công thức |
|----------|-------------------|-----------|
| Post-init key XOR | Sau INIT_PERM | `x3 ^= key_high; x4 ^= key_low` |
| Domain separation | Sau AD absorption | `x4[0] ^= 1` |
| Pre-finalization key XOR | Trước FIN_PERM | `x1 ^= key_high; x2 ^= key_low` |

---

## Testbench – 4 Test Case

| # | Mô tả | Kỳ vọng |
|---|-------|---------|
| 1 | Mã hóa Ascon-128, có AD, 8 bytes plaintext | Done=1, CT + Tag được tạo |
| 2 | Giải mã với CT/Tag từ Test 1 | PT khớp, tag_match=1 |
| 3 | Giải mã với ciphertext bị tamper (flip 1 bit) | tag_match=0 |
| 4 | Mã hóa không có Associated Data (ad_valid=0) | Done=1, CT + Tag được tạo |

### Cách chạy simulation (Icarus Verilog)

```bash
# Biên dịch (thay ascon_PERMUTATION.v bằng file thực của bạn)
iverilog -o sim_ascon \
  ascon_PERMUTATION.v \
  ascon_INITIALIZATION.v \
  ascon_DATAPATH.v \
  ascon_STATE_REGISTER.v \
  ascon_TAG_GENERATOR.v \
  ascon_TAG_COMPARATOR.v \
  ascon_CONTROLLER.v \
  ascon_CORE.v \
  tb_ascon_CORE.v

# Chạy simulation
vvp sim_ascon

# Xem waveform
gtkwave tb_ascon_CORE.vcd
```

### Cách chạy với ModelSim/QuestaSim

```tcl
vlog ascon_PERMUTATION.v ascon_INITIALIZATION.v ascon_DATAPATH.v \
     ascon_STATE_REGISTER.v ascon_TAG_GENERATOR.v \
     ascon_TAG_COMPARATOR.v ascon_CONTROLLER.v \
     ascon_CORE.v tb_ascon_CORE.v

vsim tb_ascon_CORE
run -all
```

---

## Lưu ý tích hợp

1. **File `ascon_PERMUTATION.v` của bạn không cần chỉnh sửa** – CORE gọi đúng interface đã cho.
2. **State width:** Toàn bộ pipeline dùng 320-bit (`[319:0]`), layout `x0=bit[319:256]` … `x4=bit[63:0]`.
3. **Timing:** Mỗi permutation chiếm `rounds` chu kỳ clock (theo module của bạn). Controller chờ `perm_done` trước khi chuyển trạng thái.
4. **Key XOR post-init và pre-fin** được thực hiện bằng logic tổ hợp trong `ascon_CORE`, không cần thêm state trong controller.
5. **Để pass KAT (Known Answer Tests) chính thức**, bạn cần thay test vector trong testbench bằng vector từ: https://ascon.iaik.tugraz.at/
