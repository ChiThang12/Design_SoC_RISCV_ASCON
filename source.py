import os

OUTPUT_FILE = r"D:\PROJECT_RISCV_ASCON\Design_SoC_RISCV_ASCON\source_prj.txt"
ROOT_DIR = "."


def is_last_item(items, index):
    return index == len(items) - 1


def build_tree(root, prefix=""):
    lines = []

    # Lấy danh sách thư mục + file .v
    try:
        entries = sorted(os.listdir(root))
    except PermissionError:
        return []

    dirs = [d for d in entries if os.path.isdir(os.path.join(root, d))]
    files = [f for f in entries if f.endswith(".v")]

    items = dirs + files

    for i, item in enumerate(items):
        path = os.path.join(root, item)
        connector = "└── " if is_last_item(items, i) else "├── "

        lines.append(prefix + connector + item)

        if os.path.isdir(path):
            extension = "    " if is_last_item(items, i) else "│   "
            lines.extend(build_tree(path, prefix + extension))

    return lines


def main():
    tree_lines = [ROOT_DIR]
    tree_lines += build_tree(ROOT_DIR)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(tree_lines))

    print(f"Tree structure written to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()