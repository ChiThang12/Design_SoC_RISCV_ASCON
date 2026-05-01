# Behavior Contract

## HARD RULES — không bao giờ vi phạm
1. **Code first** — không preamble ("I will now...", "Here is...", "Tôi sẽ...")
2. **No refactor ngoài scope** — chỉ sửa đúng phần được yêu cầu, không "dọn dẹp" xung quanh
3. **No TODO placeholder** — implement đầy đủ, hoặc nói rõ lý do không làm được
4. **No style change** — không đổi indent, naming, format ngoài phần cần sửa
5. **No proactive suggestion** — chỉ làm đúng yêu cầu, không thêm "by the way..."
6. **Assumption rõ ràng** — khi task không rõ, làm theo cách hiểu hợp lý nhất và ghi inline:
   `// Assumption: <điều đang giả định>`

## Output Format
- Default: **diff + 2 dòng** (thay đổi gì + tại sao)
- Max **150 dòng**/response
- Bullet points cho list; **bảng so sánh** khi có ≥2 options
- Ngôn ngữ: **Tiếng Việt** giải thích, **English** cho code/signal/port name

## Scope Confirmation
| Tình huống | Hành động |
|-----------|-----------|
| Sửa 1 file | Làm ngay, không hỏi |
| Sửa nhiều file | Báo scope trước: "Sẽ sửa X và Y — tiếp tục?" |

## Bug Warning — chỉ cảnh báo khi
- Deadlock (AXI channel stuck, FSM không thoát được)
- Data corruption (write sai address, width mismatch làm mất data)
- AXI protocol violation (valid gated by ready, missing WLAST...)
- Bỏ qua: style issue, minor inefficiency, warnings không ảnh hưởng function

## RTK Enforcement
- **LUÔN** dùng: `rtk ls`, `rtk read`, `rtk grep`, `rtk git ...`
- Nếu sắp dùng `cat`/`grep`/`ls`/`find` trực tiếp → dùng rtk thay thế
- Nhắc user nếu họ paste lệnh non-rtk trong yêu cầu

## RTL ↔ Firmware Sync — Critical (nguồn bug #1)
Mỗi khi sửa các mục sau trong RTL → **PHẢI** note define tương ứng trong firmware:

| Thay đổi RTL | File firmware cần check |
|-------------|------------------------|
| Register offset trong `ascon_axi_slave.v` | `gnu_toolchain/include/ascon.h` |
| STATUS bit layout | `ASCON_ST_*` defines trong `ascon.h` |
| CTRL bit semantic | `ASCON_CTRL_*` defines |
| Base address | `include/memory_map.h` |
| IRQ source routing | `include/plic.h` (PLIC_SRC_*) |
