# RISC-V ASCON SoC - Physical Design (PD) Environment

Thư mục `pd2/` chứa toàn bộ mã nguồn RTL đã được làm phẳng (flatten/bundle) và chuẩn bị sẵn sàng cho quá trình Physical Design (Tổng hợp - Synthesis, Place & Route).

## 🏆 Top Module

Top module dành cho quá trình chạy Physical Design có thể chọn một trong hai tùy thuộc vào mục đích của bạn:

1. **`soc_hs`** (Nằm trong file `soc_hs.v`):
   - **Mô tả:** Là Hardware Wrapper cấp cao nhất. Chứa vòng ring của IO Pads (IOBUF, OBUFT) dùng để giao tiếp với các chân vật lý (pins) bên ngoài chip.
   - **Nên dùng khi:** Chạy tổng hợp cho toàn bộ Chip (Full-chip Synthesis) để kiểm tra timing qua IO pads hoặc nạp FPGA/Tape-out.

2. **`soc_top`** (Nằm trong file `soc_top.v`):
   - **Mô tả:** Là module chứa core logic bên trong (CPU, ASCON, Memory, AXI Bus, DMA, UART, Timer, PLIC, v.v.) nhưng KHÔNG chứa các IO Pads vật lý.
   - **Nên dùng khi:** Chỉ muốn chạy tổng hợp phần lõi (Core-level Synthesis) để đánh giá diện tích, công suất, và timing nội bộ.

---

## 📂 Cấu trúc Files cho Physical Design

Để tránh các lỗi rắc rối liên quan đến đường dẫn include (`` `include ``) khi đưa vào các tool PD như Design Compiler (Synopsys), Genus/Innovus (Cadence), hay Yosys, mã nguồn đã được gom lại theo 2 cách tùy chọn:

### Lựa chọn 1: Sử dụng Single Source (Khuyên dùng)
- **File:** `soc_full.v`
- **Mô tả:** Đây là file duy nhất dung lượng ~1.1MB, chứa toàn bộ tất cả các sub-modules bên trong hệ thống (Hơn 100 modules). Toàn bộ các câu lệnh `` `include `` đã được loại bỏ. `` `timescale `` được đưa lên đầu file.
- **Cách dùng:** Chỉ cần load duy nhất file `soc_full.v` vào tool PD của bạn.

### Lựa chọn 2: Sử dụng Filelist
- **Thư mục:** `rtl/` (Chứa các file `.v` lẻ rời rạc đã được comment out các dòng `` `include ``).
- **File:** `filelist.f` (Danh sách đường dẫn trỏ tới các file trong `rtl/`).
- **Cách dùng:** Dùng lệnh đọc filelist trong tool PD (Ví dụ: `read_verilog -f filelist.f`).

---

## ⚠️ Lưu ý về mặt Kiến trúc
- Thư mục này giữ nguyên 100% cấu trúc của thiết kế gốc. Tất cả các module (kể cả PLIC, CLINT, GPIO, v.v.) đều được giữ lại và tổng hợp bình thường.
- Không chứa các file Testbench (`tb_*.v`, `run_soc*.v`) để tránh tool PD nhận diện nhầm top module hoặc tổng hợp sai logic không tổng hợp được (non-synthesizable).
