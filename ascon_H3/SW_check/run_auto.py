#!/usr/bin/env python3
"""
ASCON Test Utility - Tool để test và debug Ascon implementation
Có thể so sánh kết quả giữa software và hardware
"""

import sys
import os
import json
import argparse
from typing import Optional, List, Tuple
from pathlib import Path
from datetime import datetime
import ascon  # Import module ascon của bạn

# ---------------------------------------------------------------------------
# Co-sim fixed inputs — KEY/NONCE never change; thêm test case mới vào list
# ---------------------------------------------------------------------------
COSIM_KEY   = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
COSIM_NONCE = bytes.fromhex("101112131415161718191a1b1c1d1e1f")

# (hw_mode, plaintext, associated_data, label)
#   hw_mode 0 = CPU-Direct  (PT max 8 bytes, AD max 16 bytes)
#   hw_mode 1 = DMA         (PT/AD must be multiple of 8 bytes)
COSIM_TESTS = [
    (0, b"ascon",                              b"",                              "TC1-CPU-NoAD"),
    (0, b"ascon",                              b"ASCON",                         "TC2-CPU-AD"),
    (1, bytes.fromhex("0102030405060708"),     b"",                              "TC3-DMA-NoAD"),
    (1, bytes.fromhex("0102030405060708"),     bytes.fromhex("aabbccddeeff0011"),"TC4-DMA-AD"),
]

class AsconTester:
    def __init__(self, debug: bool = False):
        self.debug = debug
        self.test_vectors = []
        
    def print_banner(self, title: str):
        print("\n" + "="*60)
        print(f"  {title}")
        print("="*60)
    
    def bytes_to_hex_spaced(self, data: bytes, group: int = 8) -> str:
        """Convert bytes to hex with spacing for readability"""
        hex_str = data.hex().upper()
        if group > 0:
            return ' '.join([hex_str[i:i+group] for i in range(0, len(hex_str), group)])
        return hex_str
    
    def int_to_hex_state(self, state: List[int]) -> List[str]:
        """Convert state integers to hex strings"""
        return [f"{x:016X}" for x in state]
    
    def print_state(self, state: List[int], label: str = "State"):
        """Print Ascon state in readable format"""
        hex_state = self.int_to_hex_state(state)
        print(f"\n{label}:")
        print(f"  x0: {hex_state[0]}")
        print(f"  x1: {hex_state[1]}")
        print(f"  x2: {hex_state[2]}")
        print(f"  x3: {hex_state[3]}")
        print(f"  x4: {hex_state[4]}")
    
    def test_permutation(self, rounds: int = 12, input_state: Optional[List[int]] = None):
        """Test permutation layer only"""
        self.print_banner(f"TEST PERMUTATION (Rounds: {rounds})")
        
        if input_state is None:
            # Default test state
            input_state = [
                0x0123456789ABCDEF,  # x0
                0xFEDCBA9876543210,  # x1
                0x0011223344556677,  # x2
                0x8899AABBCCDDEEFF,  # x3
                0x1122334455667788,  # x4
            ]
        
        print("Input State:")
        self.print_state(input_state, "Input")
        
        # Make a copy for permutation
        state = input_state.copy()
        
        print(f"\nRunning permutation ({rounds} rounds)...")
        ascon.ascon_permutation(state, rounds)
        
        print("\nOutput State:")
        self.print_state(state, "Output")
        
        return input_state, state
    
    def test_hash(self, 
                  message: bytes = b"ascon",
                  variant: str = "Ascon-Hash256",
                  hashlength: int = 32,
                  customization: bytes = b""):
        """Test hash function"""
        self.print_banner(f"TEST HASH ({variant})")
        
        print(f"Message: {message}")
        print(f"Message (hex): {self.bytes_to_hex_spaced(message)}")
        print(f"Length: {len(message)} bytes")
        
        if customization:
            print(f"Customization: {customization}")
            print(f"Customization (hex): {self.bytes_to_hex_spaced(customization)}")
        
        print(f"\nComputing hash...")
        hash_result = ascon.ascon_hash(message, variant, hashlength, customization)
        
        print(f"\nHash Result ({len(hash_result)} bytes):")
        print(f"Hex: {self.bytes_to_hex_spaced(hash_result)}")
        
        return hash_result
    
    def test_mac(self,
                 key: bytes = bytes(range(16)),
                 message: bytes = b"ascon",
                 variant: str = "Ascon-Mac",
                 taglength: int = 16):
        """Test MAC function"""
        self.print_banner(f"TEST MAC ({variant})")
        
        print(f"Key ({len(key)} bytes): {self.bytes_to_hex_spaced(key)}")
        print(f"Message: {message}")
        print(f"Message (hex): {self.bytes_to_hex_spaced(message)}")
        
        print(f"\nComputing MAC...")
        mac_result = ascon.ascon_mac(key, message, variant, taglength)
        
        print(f"\nMAC Result ({len(mac_result)} bytes):")
        print(f"Hex: {self.bytes_to_hex_spaced(mac_result)}")
        
        return mac_result
    
    def test_aead_encrypt(self,
                          key: bytes = bytes(range(16)),
                          nonce: bytes = bytes(range(16, 32)),
                          associateddata: bytes = b"ASCON",
                          plaintext: bytes = b"ascon",
                          variant: str = "Ascon-AEAD128"):
        """Test AEAD encryption"""
        self.print_banner(f"TEST AEAD ENCRYPT ({variant})")
        
        print(f"Key ({len(key)} bytes): {self.bytes_to_hex_spaced(key)}")
        print(f"Nonce ({len(nonce)} bytes): {self.bytes_to_hex_spaced(nonce)}")
        print(f"Associated Data: {associateddata}")
        print(f"Associated Data (hex): {self.bytes_to_hex_spaced(associateddata)}")
        print(f"Plaintext: {plaintext}")
        print(f"Plaintext (hex): {self.bytes_to_hex_spaced(plaintext)}")
        
        print(f"\nEncrypting...")
        ciphertext = ascon.ascon_encrypt(key, nonce, associateddata, plaintext, variant)
        
        print(f"\nCiphertext ({len(ciphertext)} bytes):")
        ct_only = ciphertext[:-16]
        tag = ciphertext[-16:]
        print(f"Ciphertext only: {self.bytes_to_hex_spaced(ct_only)}")
        print(f"Tag ({len(tag)} bytes): {self.bytes_to_hex_spaced(tag)}")
        print(f"Full output: {self.bytes_to_hex_spaced(ciphertext)}")
        
        return ciphertext
    
    def test_aead_decrypt(self,
                          key: bytes = bytes(range(16)),
                          nonce: bytes = bytes(range(16, 32)),
                          associateddata: bytes = b"ASCON",
                          ciphertext: Optional[bytes] = None,
                          variant: str = "Ascon-AEAD128"):
        """Test AEAD decryption"""
        self.print_banner(f"TEST AEAD DECRYPT ({variant})")
        
        if ciphertext is None:
            # Auto-encrypt first
            plaintext = b"ascon"
            ciphertext = ascon.ascon_encrypt(key, nonce, associateddata, plaintext, variant)
        
        print(f"Key ({len(key)} bytes): {self.bytes_to_hex_spaced(key)}")
        print(f"Nonce ({len(nonce)} bytes): {self.bytes_to_hex_spaced(nonce)}")
        print(f"Associated Data: {associateddata}")
        print(f"Associated Data (hex): {self.bytes_to_hex_spaced(associateddata)}")
        print(f"Ciphertext ({len(ciphertext)} bytes): {self.bytes_to_hex_spaced(ciphertext)}")
        
        print(f"\nDecrypting...")
        plaintext = ascon.ascon_decrypt(key, nonce, associateddata, ciphertext, variant)
        
        if plaintext is None:
            print("\n✗ DECRYPTION FAILED - Tag verification failed!")
            return None
        else:
            print(f"\n✓ Decryption successful!")
            print(f"Plaintext: {plaintext}")
            print(f"Plaintext (hex): {self.bytes_to_hex_spaced(plaintext)}")
            return plaintext
    
    def compare_with_hardware(self, 
                             sw_result: bytes, 
                             hw_result_hex: str,
                             label: str = "Comparison"):
        """Compare software result with hardware result"""
        self.print_banner(label)
        
        sw_hex = sw_result.hex().upper()
        hw_hex = hw_result_hex.upper().replace(" ", "")
        
        print(f"Software result ({len(sw_result)} bytes):")
        print(f"  {self.bytes_to_hex_spaced(sw_result)}")
        print(f"\nHardware result ({len(hw_hex)//2} bytes):")
        print(f"  {self.bytes_to_hex_spaced(bytes.fromhex(hw_hex))}")
        
        if sw_hex == hw_hex:
            print("\n✓ RESULTS MATCH!")
            return True
        else:
            print("\n✗ RESULTS DIFFER!")
            print(f"\nDifferences:")
            for i in range(0, len(sw_hex), 2):
                sw_byte = sw_hex[i:i+2]
                hw_byte = hw_hex[i:i+2] if i < len(hw_hex) else "??"
                if sw_byte != hw_byte:
                    print(f"  Byte {i//2}: SW={sw_byte}, HW={hw_byte}")
            return False
    
    def generate_test_vector(self,
                            test_type: str = "aead",
                            count: int = 1) -> dict:
        """Generate a test vector in hardware-friendly format"""
        import random
        
        if test_type == "aead":
            key = bytes([random.randint(0, 255) for _ in range(16)])
            nonce = bytes([random.randint(0, 255) for _ in range(16)])
            pt_len = random.randint(0, 32)
            ad_len = random.randint(0, 32)
            plaintext = bytes([random.randint(0, 255) for _ in range(pt_len)])
            ad = bytes([random.randint(0, 255) for _ in range(ad_len)])
            
            ciphertext = ascon.ascon_encrypt(key, nonce, ad, plaintext)
            
            return {
                "Count": count,
                "Key": key.hex().upper(),
                "Nonce": nonce.hex().upper(),
                "PT": plaintext.hex().upper(),
                "PT_len": pt_len,
                "AD": ad.hex().upper(),
                "AD_len": ad_len,
                "CT": ciphertext.hex().upper(),
                "CT_only": ciphertext[:-16].hex().upper(),
                "Tag": ciphertext[-16:].hex().upper()
            }
        
        elif test_type == "hash":
            msg_len = random.randint(0, 1024)
            message = bytes([random.randint(0, 255) for _ in range(msg_len)])
            hash_result = ascon.ascon_hash(message, "Ascon-Hash256", 32)
            
            return {
                "Count": count,
                "Msg": message.hex().upper(),
                "Msg_len": msg_len,
                "Hash": hash_result.hex().upper()
            }
        
        return {}
    
    def export_hex_test_vectors(self, count: int, filename: str):
        """Export test vectors in a simple hex format for Verilog parsing
        Format per line:
        MODE KEY NONCE AD_LEN AD_HEX PT_LEN PT_HEX CT_HEX TAG_HEX
        MODE: 0 (CPU-Direct), 1 (DMA)
        All hex strings are padded/formatted to be easily read by $fscanf
        """
        import random
        
        with open(filename, 'w') as f:
            f.write("// Format: MODE KEY NONCE AD_LEN AD_HEX PT_LEN PT_HEX CT_HEX TAG_HEX\n")
            f.write("// MODE: 0 = CPU-Direct, 1 = DMA\n")
            
            for i in range(count):
                # Randomly choose CPU-Direct (mode 0) or DMA (mode 1)
                # CPU-Direct has strict length limits in this testbench: PT max 8, AD max 16
                mode = random.choice([0, 1])
                
                key = bytes([random.randint(0, 255) for _ in range(16)])
                nonce = bytes([random.randint(0, 255) for _ in range(16)])
                
                if mode == 0:
                    pt_len = random.randint(0, 1) * 8
                    ad_len = random.randint(0, 2) * 8
                else:
                    pt_len = random.randint(0, 16) * 8
                    ad_len = random.randint(0, 16) * 8
                    
                plaintext = bytes([random.randint(0, 255) for _ in range(pt_len)])
                ad = bytes([random.randint(0, 255) for _ in range(ad_len)])
                
                ciphertext = ascon.ascon_encrypt(key, nonce, ad, plaintext)
                ct_only = ciphertext[:-16]
                tag = ciphertext[-16:]
                
                # To make it extremely easy for Verilog $fscanf("%h"):
                # Always output at least '00' if length is 0 to avoid parsing errors
                ad_hex = ad.hex().upper() if ad_len > 0 else "00"
                pt_hex = plaintext.hex().upper() if pt_len > 0 else "00"
                ct_hex = ct_only.hex().upper() if pt_len > 0 else "00"
                
                line = f"{mode} {key.hex().upper()} {nonce.hex().upper()} {ad_len:04X} {ad_hex} {pt_len:04X} {pt_hex} {ct_hex} {tag.hex().upper()}\n"
                f.write(line)
                
        print(f"Exported {count} test vectors to {filename} in Verilog-friendly hex format.")
    
    def run_cosim_tests(self, out_dir="."):
        """Generate sw_ascon_output.log + test_vectors.hex for co-simulation."""
        os.makedirs(out_dir, exist_ok=True)
        log_path = os.path.join(out_dir, "sw_ascon_output.log")
        vec_path = os.path.join(out_dir, "test_vectors.hex")

        log_lines = [
            "=" * 64,
            "  ASCON SW REFERENCE OUTPUT",
            f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 64,
            f"KEY   : {COSIM_KEY.hex().upper()}",
            f"NONCE : {COSIM_NONCE.hex().upper()}",
            "",
        ]
        vec_lines = [
            "// Format: HW_MODE KEY NONCE AD_LEN AD PT_LEN PT CT TAG",
            "// HW_MODE: 0=CPU-Direct  1=DMA | Variant: Ascon-AEAD128",
        ]

        all_pass = True
        for hw_mode, pt, ad, label in COSIM_TESTS:
            ct_full = ascon.ascon_encrypt(COSIM_KEY, COSIM_NONCE, ad, pt, "Ascon-AEAD128")
            ct_only = ct_full[:-16]
            tag     = ct_full[-16:]
            pt_back = ascon.ascon_decrypt(COSIM_KEY, COSIM_NONCE, ad, ct_full, "Ascon-AEAD128")
            dec_ok  = (pt_back == pt)
            if not dec_ok:
                all_pass = False

            log_lines += [
                f"[{label}]",
                f"  HW Mode : {'CPU-Direct' if hw_mode == 0 else 'DMA'}",
                f"  PT      : {pt.hex().upper()}  ({len(pt)} bytes)",
                f"  AD      : {ad.hex().upper() if ad else '(empty)'}  ({len(ad)} bytes)",
                f"  CT      : {ct_only.hex().upper()}",
                f"  TAG     : {tag.hex().upper()}",
                f"  DECRYPT : {'PASS' if dec_ok else 'FAIL'}",
                "",
            ]

            ad_hex = ad.hex().upper() if ad else "00"
            pt_hex = pt.hex().upper() if pt else "00"
            ct_hex = ct_only.hex().upper() if ct_only else "00"
            vec_lines.append(
                f"{hw_mode} {COSIM_KEY.hex().upper()} {COSIM_NONCE.hex().upper()} "
                f"{len(ad):04X} {ad_hex} {len(pt):04X} {pt_hex} {ct_hex} {tag.hex().upper()}"
            )

        log_lines += [
            "=" * 64,
            f"  SW STATUS : {'ALL PASS' if all_pass else 'SOME FAIL'}",
            f"  Vectors   : {vec_path}",
            "=" * 64,
        ]

        body = '\n'.join(log_lines) + '\n'
        with open(log_path, 'w') as f:
            f.write(body)
        with open(vec_path, 'w') as f:
            f.write('\n'.join(vec_lines) + '\n')

        print(body)
        print(f"SW log     → {log_path}")
        print(f"TB vectors → {vec_path}")

    def interactive_mode(self):
        """Interactive testing mode"""
        print("\n" + "="*60)
        print("  ASCON INTERACTIVE TEST MODE")
        print("="*60)
        
        while True:
            print("\nSelect test type:")
            print("  1. Permutation test")
            print("  2. Hash test")
            print("  3. MAC test")
            print("  4. AEAD encryption")
            print("  5. AEAD decryption")
            print("  6. Compare with hardware")
            print("  7. Generate test vector")
            print("  0. Exit")
            
            choice = input("\nEnter choice (0-7): ").strip()
            
            if choice == "0":
                print("Exiting...")
                break
            
            elif choice == "1":
                rounds = input("Rounds (default 12): ").strip()
                rounds = int(rounds) if rounds else 12
                
                custom_state = input("Custom state (5 hex values, space separated) [Enter for default]: ").strip()
                if custom_state:
                    values = custom_state.split()
                    state = [int(x, 16) for x in values[:5]]
                    self.test_permutation(rounds, state)
                else:
                    self.test_permutation(rounds)
            
            elif choice == "2":
                msg = input("Message (default 'ascon'): ").strip()
                message = msg.encode() if msg else b"ascon"
                
                print("Variants: 1=Hash256, 2=XOF128, 3=CXOF128")
                v_choice = input("Variant (default 1): ").strip()
                variants = ["Ascon-Hash256", "Ascon-XOF128", "Ascon-CXOF128"]
                variant = variants[int(v_choice)-1] if v_choice and v_choice in "123" else "Ascon-Hash256"
                
                if variant == "Ascon-CXOF128":
                    custom = input("Customization string [Enter for none]: ").strip()
                    customization = custom.encode() if custom else b""
                    self.test_hash(message, variant, 32, customization)
                else:
                    self.test_hash(message, variant)
            
            elif choice == "3":
                key_input = input("Key (16 hex bytes) [Enter for default]: ").strip()
                key = bytes.fromhex(key_input) if key_input else bytes(range(16))
                
                msg = input("Message (default 'ascon'): ").strip()
                message = msg.encode() if msg else b"ascon"
                
                print("Variants: 1=Mac, 2=Prf, 3=PrfShort")
                v_choice = input("Variant (default 1): ").strip()
                variants = ["Ascon-Mac", "Ascon-Prf", "Ascon-PrfShort"]
                variant = variants[int(v_choice)-1] if v_choice and v_choice in "123" else "Ascon-Mac"
                
                self.test_mac(key, message, variant)
            
            elif choice == "4":
                key_input = input("Key (16 hex bytes) [Enter for default]: ").strip()
                key = bytes.fromhex(key_input) if key_input else bytes(range(16))
                
                nonce_input = input("Nonce (16 hex bytes) [Enter for default]: ").strip()
                nonce = bytes.fromhex(nonce_input) if nonce_input else bytes(range(16, 32))
                
                ad = input("Associated Data [Enter for 'ASCON']: ").strip()
                associateddata = ad.encode() if ad else b"ASCON"
                
                pt = input("Plaintext [Enter for 'ascon']: ").strip()
                plaintext = pt.encode() if pt else b"ascon"
                
                ciphertext = self.test_aead_encrypt(key, nonce, associateddata, plaintext)
                
                # Ask if want to save
                save = input("\nSave to file? (y/n): ").strip().lower()
                if save == 'y':
                    filename = input("Filename: ").strip()
                    with open(filename, 'w') as f:
                        f.write(f"Key: {key.hex().upper()}\n")
                        f.write(f"Nonce: {nonce.hex().upper()}\n")
                        f.write(f"AD: {associateddata.hex().upper()}\n")
                        f.write(f"Plaintext: {plaintext.hex().upper()}\n")
                        f.write(f"Ciphertext: {ciphertext.hex().upper()}\n")
                    print(f"Saved to {filename}")
            
            elif choice == "5":
                key_input = input("Key (16 hex bytes) [Enter for default]: ").strip()
                key = bytes.fromhex(key_input) if key_input else bytes(range(16))
                
                nonce_input = input("Nonce (16 hex bytes) [Enter for default]: ").strip()
                nonce = bytes.fromhex(nonce_input) if nonce_input else bytes(range(16, 32))
                
                ad = input("Associated Data [Enter for 'ASCON']: ").strip()
                associateddata = ad.encode() if ad else b"ASCON"
                
                ct_input = input("Ciphertext (hex) [Enter to auto-generate]: ").strip()
                if ct_input:
                    ciphertext = bytes.fromhex(ct_input)
                    self.test_aead_decrypt(key, nonce, associateddata, ciphertext)
                else:
                    self.test_aead_decrypt(key, nonce, associateddata)
            
            elif choice == "6":
                sw_input = input("Software result (hex): ").strip()
                hw_input = input("Hardware result (hex): ").strip()
                label = input("Comparison label [Enter for default]: ").strip()
                
                sw_bytes = bytes.fromhex(sw_input)
                self.compare_with_hardware(sw_bytes, hw_input, label or "Software vs Hardware")
            
            elif choice == "7":
                print("Test vector types: 1=AEAD, 2=Hash")
                t_choice = input("Type (default 1): ").strip()
                t_type = "aead" if t_choice != "2" else "hash"
                
                count = input("Count number (default 1): ").strip()
                count = int(count) if count else 1
                
                vector = self.generate_test_vector(t_type, count)
                
                print("\nGenerated Test Vector:")
                for key, value in vector.items():
                    print(f"  {key}: {value}")
                
                save = input("\nSave to JSON? (y/n): ").strip().lower()
                if save == 'y':
                    filename = input("Filename: ").strip()
                    with open(filename, 'w') as f:
                        json.dump([vector], f, indent=2)
                    print(f"Saved to {filename}")
            
            else:
                print("Invalid choice!")

def main():
    parser = argparse.ArgumentParser(
        description="ASCON Test Utility - Test và so sánh Ascon implementation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --permutation                   # Test permutation
  %(prog)s --permutation --rounds 6        # Test 6 rounds permutation
  %(prog)s --hash                          # Test hash
  %(prog)s --aead                          # Test AEAD encryption
  %(prog)s --decrypt                       # Test AEAD decryption
  %(prog)s --mac                           # Test MAC
  %(prog)s --compare SW_HEX HW_HEX         # Compare results
  %(prog)s --interactive                   # Interactive mode
  %(prog)s --generate 5 > test_vectors.json # Generate 5 test vectors
        """
    )
    
    parser.add_argument("--permutation", action="store_true", help="Test permutation")
    parser.add_argument("--rounds", type=int, default=12, help="Number of permutation rounds")
    parser.add_argument("--state", type=str, help="Initial state as hex (5 values space separated)")
    
    parser.add_argument("--hash", action="store_true", help="Test hash function")
    parser.add_argument("--message", type=str, default="ascon", help="Message to hash")
    parser.add_argument("--hash-variant", choices=["Hash256", "XOF128", "CXOF128"], 
                       default="Hash256", help="Hash variant")
    parser.add_argument("--customization", type=str, default="", help="Customization string (CXOF only)")
    
    parser.add_argument("--mac", action="store_true", help="Test MAC function")
    parser.add_argument("--key", type=str, help="Key as hex string")
    parser.add_argument("--mac-variant", choices=["Mac", "Prf", "PrfShort"], 
                       default="Mac", help="MAC variant")
    
    parser.add_argument("--aead", action="store_true", help="Test AEAD encryption")
    parser.add_argument("--decrypt", action="store_true", help="Test AEAD decryption")
    parser.add_argument("--nonce", type=str, help="Nonce as hex string")
    parser.add_argument("--ad", type=str, default="ASCON", help="Associated data")
    parser.add_argument("--plaintext", type=str, default="ascon", help="Plaintext")
    parser.add_argument("--ciphertext", type=str, help="Ciphertext as hex (for decryption)")
    
    parser.add_argument("--compare", nargs=2, metavar=("SW_HEX", "HW_HEX"), 
                       help="Compare software and hardware results")
    
    parser.add_argument("--generate", type=int, metavar="N", 
                       help="Generate N test vectors")
    parser.add_argument("--type", choices=["aead", "hash"], default="aead",
                       help="Type of test vectors to generate")
    
    parser.add_argument("--interactive", "-i", action="store_true",
                       help="Interactive mode")
    parser.add_argument("--debug", action="store_true",
                       help="Enable debug output")
    parser.add_argument("--export-hex", type=str, metavar="FILE",
                       help="Generate AEAD test vectors and save as Verilog-friendly hex file")
    parser.add_argument("--cosim", action="store_true",
                       help="Run co-sim suite: fixed inputs → sw_ascon_output.log + test_vectors.hex")
    parser.add_argument("--out-dir", type=str, default=".",
                       help="Output directory for --cosim (default: current dir)")
    
    args = parser.parse_args()
    
    tester = AsconTester(debug=args.debug)
    
    if args.cosim:
        tester.run_cosim_tests(args.out_dir)
        return

    if args.interactive:
        tester.interactive_mode()
        return
    
    if args.permutation:
        state = None
        if args.state:
            values = args.state.split()
            state = [int(x, 16) for x in values[:5]]
        tester.test_permutation(args.rounds, state)
    
    elif args.hash:
        customization = args.customization.encode() if args.customization else b""
        variant = f"Ascon-{args.hash_variant}"
        tester.test_hash(args.message.encode(), variant, 32, customization)
    
    elif args.mac:
        key = bytes.fromhex(args.key) if args.key else bytes(range(16))
        variant = f"Ascon-{args.mac_variant}"
        tester.test_mac(key, args.message.encode(), variant)
    
    elif args.aead:
        key = bytes.fromhex(args.key) if args.key else bytes(range(16))
        nonce = bytes.fromhex(args.nonce) if args.nonce else bytes(range(16, 32))
        tester.test_aead_encrypt(key, nonce, args.ad.encode(), args.plaintext.encode())
    
    elif args.decrypt:
        key = bytes.fromhex(args.key) if args.key else bytes(range(16))
        nonce = bytes.fromhex(args.nonce) if args.nonce else bytes(range(16, 32))
        ciphertext = bytes.fromhex(args.ciphertext) if args.ciphertext else None
        tester.test_aead_decrypt(key, nonce, args.ad.encode(), ciphertext)
    
    elif args.compare:
        sw_result = bytes.fromhex(args.compare[0])
        tester.compare_with_hardware(sw_result, args.compare[1])
    
    elif args.generate:
        if args.export_hex:
            tester.export_hex_test_vectors(args.generate, args.export_hex)
        else:
            vectors = []
            for i in range(args.generate):
                vectors.append(tester.generate_test_vector(args.type, i+1))
            
            print(json.dumps(vectors, indent=2))
    
    elif args.export_hex:
        # Default 10 vectors if --generate not specified
        tester.export_hex_test_vectors(10, args.export_hex)
        
    else:
        # Run all basic tests if no arguments
        print("Running basic test suite...")
        tester.test_permutation(12)
        tester.test_hash()
        tester.test_mac()
        tester.test_aead_encrypt()
        tester.test_aead_decrypt()

if __name__ == "__main__":
    main()