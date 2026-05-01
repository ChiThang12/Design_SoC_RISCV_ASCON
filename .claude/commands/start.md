Chạy session kickoff theo protocol `/start` trong `.claude/rules/session.md`.

Các bước:
1. Chạy `rtk git log -n 5` để xem commits gần nhất
2. Chạy `rtk git status` để xem uncommitted changes
3. Đọc `.claude/handoff.md` nếu tồn tại (xem session trước làm gì)
4. Đọc memory files nếu relevant

Sau đó báo ngắn gọn:
- Đang làm dở: [task]
- File chưa commit: [files]
- Đề xuất bắt đầu từ: [next step cụ thể]
