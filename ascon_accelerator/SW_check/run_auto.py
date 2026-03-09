#!/usr/bin/env python3
"""
ASCON Test Utility - Tool để test và debug Ascon implementation
Có thể so sánh kết quả giữa software và hardware
"""

import sys
import json
import argparse
from typing import Optional, List, Tuple
from pathlib import Path
import ascon  # Import module ascon của bạn

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
    
    args = parser.parse_args()
    
    tester = AsconTester(debug=args.debug)
    
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
        vectors = []
        for i in range(args.generate):
            vectors.append(tester.generate_test_vector(args.type, i+1))
        
        print(json.dumps(vectors, indent=2))
    
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