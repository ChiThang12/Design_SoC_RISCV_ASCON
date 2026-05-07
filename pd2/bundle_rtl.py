import os
import re
import sys

def bundle_rtl(rtl_dir, output_file):
    out_content = []
    
    # Optional: add a generic timescale at the top
    out_content.append("`timescale 1ns/1ps\n")
    
    # Track files to avoid duplicates if any
    processed = set()
    
    for filename in sorted(os.listdir(rtl_dir)):
        if not filename.endswith('.v'):
            continue
        # Skip testbenches just in case they snuck in
        if filename.startswith('tb_') or filename.startswith('run_soc'):
            continue
            
        filepath = os.path.join(rtl_dir, filename)
        if filepath in processed:
            continue
        processed.add(filepath)
        
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        out_content.append(f"\n// {'='*78}\n")
        out_content.append(f"// FILE: {filename}\n")
        out_content.append(f"// {'='*78}\n\n")
        
        for line in lines:
            # Comment out `include statements
            if re.match(r'^\s*`include', line):
                out_content.append("// " + line)
            # Optional: comment out `timescale as well, since we put one at the top
            elif re.match(r'^\s*`timescale', line):
                out_content.append("// " + line)
            else:
                out_content.append(line)
                
    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(out_content)

    print(f"Successfully bundled {len(processed)} files into {output_file}")

if __name__ == '__main__':
    bundle_rtl('pd2/rtl', 'pd2/soc_full.v')
