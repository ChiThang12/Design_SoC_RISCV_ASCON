import os
import re

def flatten_verilog(top_file, output_file, search_dirs):
    processed_files = set()
    out_lines = []
    
    # Add timescale at the top
    out_lines.append("`timescale 1ns/1ps\n")

    def process_file(filepath):
        filepath = os.path.abspath(filepath)
        if filepath in processed_files:
            return
        processed_files.add(filepath)

        if not os.path.exists(filepath):
            print(f"WARNING: File not found: {filepath}")
            return

        out_lines.append(f"\n// {'='*78}\n")
        out_lines.append(f"// FILE: {os.path.basename(filepath)}\n")
        out_lines.append(f"// {'='*78}\n\n")

        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        for line in lines:
            m = re.match(r'^\s*`include\s+"([^"]+)"', line)
            if m:
                inc_file = m.group(1)
                # Try to find the included file
                found = False
                for d in search_dirs:
                    full_path = os.path.join(d, inc_file)
                    if os.path.exists(full_path):
                        process_file(full_path)
                        found = True
                        break
                if not found:
                    print(f"WARNING: Could not resolve include: {inc_file} from {filepath}")
                    out_lines.append("// " + line) # Keep it commented
            elif re.match(r'^\s*`timescale', line):
                out_lines.append("// " + line)
            else:
                out_lines.append(line)

    process_file(top_file)

    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(out_lines)
    
    print(f"Flattening complete! Wrote to {output_file}")
    print(f"Processed {len(processed_files)} files.")

if __name__ == '__main__':
    workspace = "/home/chithang/Project/Design_SoC_RISCV_ASCON"
    search_dirs = [workspace] # Usually relative to workspace
    top = os.path.join(workspace, "soc_hs.v")
    out = os.path.join(workspace, "pd2", "soc_full.v")
    flatten_verilog(top, out, search_dirs)
