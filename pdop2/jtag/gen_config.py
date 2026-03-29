import os
import json
import re

def clean_and_config():
    design_name = "jtag_debug_top"
    src_dir = "src"
    verilog_files = []

    print(f"--- Bắt đầu xử lý dự án: {design_name} ---")

    # 1. Quét và xử lý từng file Verilog
    for root, dirs, files in os.walk(src_dir):
        for file in files:
            if file.endswith(".v"):
                file_path = os.path.join(root, file)
                
                # Đọc nội dung file
                with open(file_path, 'r', encoding='utf-8') as f:
                    lines = f.readlines()

                # Xóa các dòng bắt đầu bằng `include
                new_lines = []
                removed_count = 0
                for line in lines:
                    # Regex tìm dòng có `include (kể cả có khoảng trắng phía trước)
                    if re.match(r'^\s*`include\s+"', line):
                        removed_count += 1
                        continue
                    new_lines.append(line)

                # Lưu lại file nếu có thay đổi
                if removed_count > 0:
                    with open(file_path, 'w', encoding='utf-8') as f:
                        f.writelines(new_lines)
                    print(f"[Clean] Đã xóa {removed_count} dòng include tại: {file}")

                # Thêm vào danh sách file cho OpenLane
                rel_path = os.path.relpath(file_path, os.getcwd())
                verilog_files.append(f"dir::{rel_path}")

    # 2. Sắp xếp danh sách file (Đảm bảo file Top nằm cuối cùng)
    # File top thường chứa nhiều module con nên cần được đọc sau cùng để tránh lỗi định nghĩa
    verilog_files.sort(key=lambda x: design_name in x)

    # 3. Tạo cấu hình JSON
    config = {
        "DESIGN_NAME": design_name,
        "VERILOG_FILES": verilog_files,
        "CLOCK_PORT": "clk",
        "CLOCK_PERIOD": 10.0,
        "FP_SIZING": "absolute",
        "DIE_AREA": [0, 0, 450, 450],
        "PL_TARGET_DENSITY_PCT": 45,
        "FP_CORE_UTIL": 40,
        "SYNTH_STRATEGY": "DELAY 1",
        "PL_TIME_DRIVEN": True,
        "RUN_POST_CTS_RESIZER_TIMING": True,
        "RUN_ANTENNA_REPAIR": True,
        "RT_MAX_LAYER": "met5",
        "RUN_MAGIC_STREAMOUT": True,
        "RUN_KLAYOUT_STREAMOUT": True
    }

    with open("config.json", "w") as f:
        json.dump(config, f, indent=2)
    
    print(f"--- Hoàn tất! Đã tạo config.json với {len(verilog_files)} files ---")

if __name__ == "__main__":
    clean_and_config()