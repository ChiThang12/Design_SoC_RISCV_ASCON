Tạo session summary theo protocol `/handoff` trong `.claude/rules/session.md`.

Chạy `rtk git diff` và `rtk git status` để lấy danh sách files thay đổi.

Append vào `.claude/handoff.md` (tạo mới nếu chưa có):

```markdown
## [ngày giờ hiện tại] Session Summary

### Đã làm
- [list các task đã hoàn thành trong session này]

### Files thay đổi
- `[file]`: [lý do thay đổi 1 dòng]

### Còn làm
- [list các task chưa xong hoặc bước tiếp theo]

### Design decisions
- [các quyết định non-obvious: tại sao chọn approach X thay vì Y]

### Known bugs chưa fix
- [nếu phát hiện bug nhưng chưa sửa trong session này]
```
