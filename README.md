# 🚀 Logic Synthesis Flow with Cadence Genus

Tài liệu này hướng dẫn cách tổ chức thư mục và thực thi quy trình tổng hợp mạch logic (Synthesis) cho dự án **SoC_RISCV_ASCON** sử dụng công cụ Cadence Genus.

## 📂 Tổ chức thư mục (Directory Structure)

Hệ thống thư mục được thiết kế để tối ưu hóa việc quản lý dữ liệu đầu vào và kết quả đầu ra trong luồng thiết kế ASIC.

| Thư mục | Mô tả nội dung |
| :--- | :--- |
| `rtl/` | Chứa mã nguồn thiết kế (`.v`, `.sv`). |
| `libraries/` | Chứa file thư viện công nghệ (`.lib`, `.db`) và macro vật lý (`.lef`). |
| `scripts/` | Chứa các script điều khiển Genus (`.tcl`) và ràng buộc thời gian (`.sdc`). |
| `reports/` | Lưu trữ báo cáo kết quả: timing, area, power và QoS. |
| `outputs/` | Lưu trữ Gate-level Netlist (`.v`) và SDC sau tổng hợp cho bước P&R. |
| `log_genus/` | Lưu trữ tệp log (`genus.log`) và history (`genus.cmd`) để debug. |

---

## 🛠 Quy trình thực hiện (Workflow)

Quá trình Synthesis được thực hiện tuần tự qua các bước sau:

1. **Library Setup**: Thiết lập đường dẫn và nạp thư viện từ thư mục `libraries/`.
2. **Read HDL**: Nạp mã nguồn RTL từ thư mục `rtl/`.
3. **Constraints**: Áp dụng các thông số ràng buộc (Clock 100MHz, Delay, Uncertainty) từ thư mục `scripts/`.
4. **Synthesis & Optimization**: Thực thi các công đoạn `syn_generic`, `syn_map` và `syn_opt`.
5. **Reporting & Export**: Xuất dữ liệu phân tích ra `reports/` và Netlist ra `outputs/`.

---

## 📊 Tóm tắt kết quả (QoS Summary)

Dựa trên báo cáo tổng hợp cho module `inst_mem`:

* **Timing**: Clean (Không vi phạm).
  * **Slack**: `+492.9 ps` (Target 100MHz).
    * **TNS**: `0.0`.
    * **Diện tích (Area)**: `271,311.464` đơn vị (Đã map RAM Macro).
    * **Thành phần**: 61 Sequential và 173 Combinational instances.

    ---

## 💻 Hướng dẫn thực thi (Quick Start)

Chạy lệnh tổng hợp từ thư mục gốc của project:

```bash
genus -files ./scripts/syn.tcl -log ./log_genus/synthesis.log



