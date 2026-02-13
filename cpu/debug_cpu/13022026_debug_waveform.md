## Nhóm 2 — CPU Pipeline (cpu_imem_*)

**Nguyên lý hoạt động:**

IFU (Instruction Fetch Unit) là stage đầu tiên của pipeline. Mỗi cycle, CPU đưa ra `cpu_imem_addr` = giá trị PC hiện tại và assert `cpu_imem_valid=1` để báo "tôi cần lệnh tại địa chỉ này". ICache nhận request, nếu có data thì trả `cpu_imem_rdata` kèm `cpu_imem_ready=1` trong cùng cycle — đây là handshake kiểu valid/ready.

**Cách đọc waveform để chứng minh đúng:**

Khi cả `cpu_imem_valid=1` và `cpu_imem_ready=1` cùng lúc tại posedge clk → handshake thành công, instruction được nhận. Cycle tiếp theo `cpu_imem_addr` tăng thêm 4 (PC+4 bình thường). Khi có cache miss, `cpu_imem_ready=0` kéo dài nhiều cycle → pipeline stall, `cpu_imem_addr` giữ nguyên không tăng. Sau khi ICache refill xong, `cpu_imem_ready` lên 1 trở lại, pipeline tiếp tục.

```
         ____      ____      ____      ____
clk  ___|    |____|    |____|    |____|    |
     
addr    [0x00]    [0x04]    [0x08]    [0x0C]   ← PC tăng đều = pipeline chạy tốt
valid        ________________________________
ready        _______________                    ← ready=0 = stall do miss
                            ________________
```

**Điểm chứng minh với giảng viên:** Chỉ ra đoạn `valid=1, ready=0` kéo dài → đó là lúc ICache đang miss và fetch từ AXI. Sau khi `ready` lên 1, PC tiếp tục tăng bình thường → stall được xử lý đúng, pipeline không mất lệnh.

---

## Nhóm 3 — ICache Miss & AXI4 Read Channel

**Nguyên lý hoạt động:**

Khi CPU fetch một PC mà ICache chưa có (cold miss hoặc conflict miss), ICache FSM chuyển sang trạng thái MISS và phát một AXI4 AR (Address Read) transaction lên memory. ICache dùng burst mode với `arlen=3` tức 4 beats — tương ứng 4 words = 1 cache line 16 bytes. `arburst=2'b01` (INCR) nghĩa là địa chỉ tự động tăng mỗi beat.

Memory slave nhận AR, assert `arready=1` để handshake, rồi trả lần lượt 4 data beats qua R channel. Mỗi beat có `rvalid=1`, beat cuối có `rlast=1`. ICache nhận đủ 4 words, ghi vào cache line, set valid bit và tag, rồi trả instruction đầu tiên cho CPU.

**Cách đọc waveform để chứng minh đúng:**

```
arvalid _______|‾‾‾‾‾‾‾‾‾|___________________
arready ______________|‾‾‾|___________________   ← AR handshake 1 cycle
araddr              [0x10]                        ← địa chỉ aligned theo cache line
arlen               [  3 ]                        ← 4 beats

rvalid  ___________________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|___
rready  _____________________________|‾‾‾‾‾‾‾‾‾|
rdata               [D0] [D1] [D2] [D3]           ← 4 words tuần tự
rlast               [ 0]  [0]  [0]  [1]           ← chỉ beat cuối = 1
rresp               [ 0]  [0]  [0]  [0]           ← OKAY = không lỗi
```

**Điểm chứng minh với giảng viên:** Đếm đúng 4 beats giữa `arvalid` và `rlast`. Sau `rlast=1`, các fetch tiếp theo trong cùng cache line (3 địa chỉ kế tiếp) phải là HIT — tức không có AR transaction mới. Điều này chứng minh cache line được lưu đúng. Miss tiếp theo chỉ xảy ra khi CPU bước sang cache line mới (mỗi 4 lệnh).

---

## Nhóm 4 — CPU Data Memory Interface (cpu_dmem_*)

**Nguyên lý hoạt động:**

Khi pipeline thực thi lệnh LOAD (LW/LH/LB) hoặc STORE (SW/SH/SB), stage MEM của CPU assert `cpu_dmem_valid=1` cùng với `cpu_dmem_addr` = địa chỉ tính từ ALU. Với STORE thêm `cpu_dmem_we=1`, `cpu_dmem_wdata` = data cần ghi, `cpu_dmem_wstrb` = byte enable (SW=4'b1111, SH=4'b0011, SB=4'b0001).

DCache xử lý request: nếu HIT thì `cpu_dmem_ready=1` ngay cycle kế, nếu MISS thì kéo `ready=0` cho đến khi refill xong. Toàn bộ thời gian `ready=0` là pipeline stall — stage IF/ID/EX bị giữ nguyên.

**Cách đọc waveform để chứng minh đúng:**

```
Trường hợp STORE (SW):
dmem_addr   [0x2000]__________
dmem_valid  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
dmem_we     ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾   ← =1 là STORE
dmem_wdata  [0xDEAD0123]______
dmem_wstrb  [0xF]_____________   ← 1111 = full word
dmem_ready  ________|‾‾‾‾‾‾‾‾   ← stall 2 cycle rồi grant

Trường hợp LOAD (LW):
dmem_we     _________________   ← =0 là LOAD
dmem_ready  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾   ← HIT → ready ngay
dmem_rdata  [0x00000005]_____   ← data trả về
```

**Điểm chứng minh với giảng viên:** Chỉ ra `wstrb` khác nhau giữa SW/SH/SB — đây là byte-enable đúng theo RISC-V spec. Khi LOAD HIT, `ready=1` ngay cycle sau valid → không stall, IPC tốt. Khi LOAD MISS, đếm số cycle stall = thời gian AXI refill.

---

## Nhóm 5 — DCache Write-Through (AXI Write Channel)

**Nguyên lý hoạt động:**

DCache là write-through, nghĩa là mỗi STORE vừa ghi vào cache line vừa phải ghi ngay lên memory. Sau khi nhận STORE từ CPU, DCache phát AXI Write transaction gồm 3 channel tuần tự: AW (address) → W (data) → B (response).

DCache gửi `awvalid=1` và `wvalid=1` đồng thời (vì single-beat write, data đã có sẵn). Memory slave handshake AW trước (`awready=1`), sau đó handshake W (`wready=1`), rồi trả B channel với `bvalid=1, bresp=OKAY`. DCache nhận B xong mới báo `cpu_dmem_ready=1` cho CPU — đây là cơ chế đảm bảo write consistency.

**Cách đọc waveform để chứng minh đúng:**

```
         T0    T1    T2    T3    T4
awvalid  ‾‾‾‾‾‾‾‾‾‾‾|__________________
awready  ______|‾‾‾‾‾|__________________   ← AW handshake tại T1
awaddr         [0x2000]

wvalid   ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|____________
wready   _______________|‾‾‾|____________   ← W handshake tại T2
wdata                   [0xDEAD0123]
wstrb                   [0xF]
wlast                   [ 1 ]              ← single beat, last=1 ngay

bvalid   ___________________|‾‾‾‾|______
bready   ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾   ← B handshake T3
bresp                       [ 0 ]          ← OKAY
```

**Điểm chứng minh với giảng viên:** Chuỗi AW→W→B phải xảy ra đúng thứ tự và đúng 1 lần cho mỗi STORE. `wlast=1` luôn đúng vì write-through là single beat (không phải burst). `bresp=0` xác nhận memory ghi thành công. Đây là bằng chứng write-through hoạt động đúng AXI4 spec.

---

## Nhóm 6 — DCache Read Miss & Refill (AXI Read Channel)

**Nguyên lý hoạt động:**

Tương tự ICache nhưng dùng cho data. Khi LOAD miss, DCache phát AR burst lên data memory để kéo cả cache line về. Điểm khác biệt quan trọng: trong khi đang refill, `cpu_dmem_ready=0` → CPU stall. Sau khi `rlast=1` và data được ghi vào cache line, DCache mới trả `cpu_dmem_ready=1` kèm `cpu_dmem_rdata` = word cần thiết (lấy đúng offset trong cache line).

Các LOAD tiếp theo cùng cache line sẽ là HIT, `cpu_dmem_ready=1` ngay lập tức mà không cần AXI transaction.

**Cách đọc waveform để chứng minh đúng:**

```
cpu_dmem_valid  ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
cpu_dmem_ready  ___________________________|‾‾‾  ← stall dài = miss + refill
cpu_dmem_rdata                             [X]   ← data đúng sau refill

dcache_arvalid  ____|‾‾‾‾‾‾‾|________________
dcache_arready  _________|‾‾‾|________________   ← AR handshake
dcache_arlen           [  3 ]                    ← 4 beats = 1 cache line

dcache_rvalid   _____________|‾‾‾‾‾‾‾‾‾‾‾‾|___
dcache_rdata             [D0] [D1] [D2] [D3]
dcache_rlast             [ 0]  [0]  [0]  [1]    ← last = beat thứ 4
```

**Điểm chứng minh với giảng viên:** Đo khoảng thời gian từ lúc `cpu_dmem_valid=1` đến `cpu_dmem_ready=1` — đó là miss penalty. Sau `rlast`, nếu có LOAD thứ 2 đến cùng cache line thì `ready=1` ngay lập tức không có AR mới — chứng minh cache line đã được lưu đúng và hit logic hoạt động.

---

## Nhóm 7 — Cache Performance Counters

**Nguyên lý hoạt động:**

Bốn counter được increment trong hardware mỗi khi có sự kiện tương ứng. `icache_hits` tăng mỗi khi CPU fetch một PC mà tag match và valid bit = 1. `icache_misses` tăng mỗi khi tag không match hoặc valid=0 → trigger AXI burst. Tương tự cho `dcache_hits`, `dcache_misses`. `dcache_writes` tăng mỗi khi có STORE hoàn thành qua write-through.

**Cách đọc waveform để chứng minh đúng:**

Các counter là monotonically increasing — chỉ tăng không bao giờ giảm. Tỉ lệ cần thỏa mãn:

```
ICache: sau khi warm up, hits/misses ~ 3:1 (vì mỗi miss fetch 4 words → 3 hit tiếp theo)

DCache: dcache_hits + dcache_misses = tổng số LOAD
        dcache_writes = tổng số STORE hoàn thành

Công thức hit rate:
  icache_hit_rate = icache_hits / (icache_hits + icache_misses) × 100%
```

**Điểm chứng minh với giảng viên:** Show counter tăng đều theo thời gian (không bị treo). Chỉ ra `icache_hits` tăng nhanh hơn `icache_misses` khoảng 3 lần sau khi cache warm — đây là bằng chứng spatial locality đang được khai thác đúng. `dcache_writes` bằng đúng số STORE instruction đã thực thi — chứng minh write-through không bỏ sót write nào.