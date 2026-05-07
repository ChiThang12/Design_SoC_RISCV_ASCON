import os
import re

def remove_includes(directory):
    count = 0
    for filename in os.listdir(directory):
        if not filename.endswith('.v'):
            continue
            
        filepath = os.path.join(directory, filename)
        
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        modified = False
        out_lines = []
        for line in lines:
            if re.match(r'^\s*`include', line):
                out_lines.append("// " + line)
                modified = True
            else:
                out_lines.append(line)
                
        if modified:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.writelines(out_lines)
            count += 1
            print(f"Commented out includes in: {filename}")
            
    print(f"Total files modified: {count}")

if __name__ == '__main__':
    remove_includes('pd2/rtl')
