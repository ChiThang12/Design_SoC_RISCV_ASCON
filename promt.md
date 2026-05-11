Tóm tắt Session — Debug ICache Bug trong test_uart_simple
Vấn đề
Simulation test_uart_simple.hex chỉ truyền được 6/28 ký tự qua UART (U,A,R,T,' ',O). Char #7 ('K') output = 0x00. Root cause: stack pointer (sp) corrupt từ 0x10001ff0 → 0x10002000 vì prologue addi x2,x2,-16 tại PC=0x98 không commit vào register file.

Đã làm
1. Truy vết bug
Trace pc_id/ex, regwrite_wb, rd_wb, stall_any trong run_soc_ascon.v
Phát hiện EX=0x98 có rd=00 (sai) cho putc #7, đúng phải là rd=02 (x2)
IF stage trả về instr_if=0x00000013 (NOP) thay vì 0xff010113 (prologue) tại cycle line_just_done=1
2. Phân tích ICache timing
icache_axi_interface.v: tất cả output đều registered → 1-cycle delay
icache_data_array.v: khởi tạo NOP, write NBA → ghi delay 2 cycle sau beat AXI
icache_controller.v Phase 2 dùng stall_data capture, nhưng Phase 3 (line 458) clear stall_data_rdy cùng cycle → CPU lấy được NOP từ data_array stale
3. Đã thử fix (chưa work)
FIX-ICACHE-REFILL-READ: ưu tiên stall_data khi line_just_done && stall_data_rdy — thất bại vì stall_data_rdy=0
4. Root cause mới phát hiện (qua $display)
Thêm $display vào Phase 2 (icache_controller.v:443-447):


[IC-P2] rw=6 co=6 lcl=0 sdr=0 rd=00e15703 pf_act=0 pf_idx=2 cpu_idx=4
pf_act=0, pf_idx=2 ≠ cpu_idx=4 → đang là beat của một PREFETCH (idx=2), không phải miss của CPU (idx=4)
loading_cpu_line=0 → Phase 2 không bao giờ capture được word cho cpu_offset=6
CPU bị block đợi prefetch hoàn tất trước khi miss request của 0x98 được serve, do refill_busy=1 chặn Phase 1
Files đã thay đổi
File	Thay đổi
run_soc_ascon.v	Thêm signal taps + debug $display block (line 138-161, 1603-1640)
cache_interface/icache/icache_controller.v	(1) FIX-ICACHE-REFILL-READ line 349-358 (chưa work) (2) $display [IC-P2] line 444-447
Còn lại
Fix prefetch priority: CPU miss phải có priority cao hơn prefetch — khi cpu_miss=1, phải hủy/preempt prefetch đang chạy hoặc đảm bảo prefetch không block CPU miss
Verify 28 chars UART output đầy đủ
Cleanup debug code
Plan file
/home/chithang/.claude/plans/simulation-test-uart-simple-hex-tr-c-fix-delightful-rain.md — fix LSU + JALR (đã apply một phần)

Lệnh chạy

./workflow/urun_verilog.sh run_soc_ascon.v
rtk read log/run_soc_ascon.log
grep "\[IC-P2\]" log/run_soc_ascon.log | grep "co=6"