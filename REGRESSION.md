# Regression Test Suite - Huong Dan & Known Bugs

> Đây là tài liệu cho các session AI tiếp theo. Đọc trước khi bắt đầu debug.

## 1. Cách chạy regression

### Chay full tests
```bash
bash regression_full.sh
```

### Chay 1 test
```bash
bash regression_full.sh test_uart
```

### Build hex + chay khi sua firmware
```bash
bash regression_full.sh -b              # build tất cả + chạy
bash regression_full.sh -b test_ascon   # build + chạy 1 test
```

### Output
- `log/<test_name>.log` — log riêng từng test
- Summary table cuối console: PASS/TIMEOUT/FAIL + UART output snippet
- `memory/program.hex` tu dong restore tu `memory/program.hex.bak` sau khi chay serial legacy.
- Nen dung mode parallel/define de moi test lay hex rieng, khong tranh nhau `memory/program.hex`.

### Cách script hoạt động
1. Build firmware C thanh `gnu_toolchain/tests/<test>.hex` neu co `-b`.
2. Parallel mode compile moi VVP voi `-DIMEM_INIT_FILE="<abs test hex>"`.
3. Testbench `run_soc_ascon.v` truyen `IMEM_INIT_FILE` xuong `soc_hs/soc_top`.
4. `uart_boot_ctrl` nap image vao IMEM qua boot sideband, roi `boot_done` moi tha reset CPU.
5. Serial legacy van copy tam `<test>.hex` vao `memory/program.hex`, nhung IMEM van duoc nap qua `uart_boot_ctrl`, khong phai direct init ben trong IMEM SRAM.
6. Parse log: tim `*** PASS` / `*** FAIL` markers tu TB test result block.

### Firmware load override tu testbench

Khuyen dung mot trong hai cach sau:

```bash
iverilog -g2005 -DIMEM_INIT_FILE='"gnu_toolchain/tests/test_plic.hex"' -o /tmp/run_soc_ascon.vvp run_soc_ascon.v
vvp /tmp/run_soc_ascon.vvp
```

Hoac compile mot lan va override runtime:

```bash
iverilog -g2005 -o /tmp/run_soc_ascon.vvp run_soc_ascon.v
vvp /tmp/run_soc_ascon.vvp +IMEM_HEX=gnu_toolchain/tests/test_plic.hex
```

Contract hien tai: IMEM SRAM production khong tu `$readmemh("program.hex")`; firmware duoc dua tu testbench/boot controller vao IMEM truoc khi CPU fetch.

## 2. Tests và mục đích

| Test | IP/Subsystem | Pass criteria |
|------|--------------|---------------|
| `test_uart_simple` | UART literal putc (`uart_putc('U')`) | In ra `UART OK\r\n[PASS] uart_simple\r\n` |
| `test_uart` | UART driver + TX IRQ poll | `[PASS] uart\r\n` |
| `test_gpio` | GPIO edge IRQ qua PLIC | `[PASS] gpio\r\n` (TB toggle gpio_in[8] sau 5000cy) |
| `test_timer` | Timer0/1 countdown + WDT | `[PASS] timer\r\n` |
| `test_clint` | CLINT mtime/mtimecmp/msip | `[PASS] clint\r\n` |
| `test_plic` | PLIC interrupt routing | `[PASS] plic\r\n` |
| `test_ascon` | ASCON DMA 16-block AEAD | `[PASS] ascon\r\n` |
| `test_dma_uart` | GP-DMA mem→mem→UART | `[PASS] dma_uart\r\n` |
| `test_integration` | Tất cả 6 IPs sequential | `ALL_PASS 6/6\r\n` |

## 3. Lịch sử fix (timestamp: 2026-05-11)

### Bug đã fix (commit pending)

**Bug 1: ICache prefetch alias overwrite**
- File: [cache_interface/icache/icache_controller.v](cache_interface/icache/icache_controller.v)
- Triệu chứng: test_uart_simple chỉ in 6/28 chars, sau đó stuck. Prefetcher iterate qua hết IMEM_LIMIT=8KB, ghi đè data_array của valid cache lines với NOPs từ vùng ngoài program.
- Tags: `FIX-NOALIAS`, `FIX-NOALIAS-GATE`, `FIX-ICACHE-STALLCAP`, `FIX-ICACHE-PFACT`, `FIX-ICACHE-STALLCLR`

**Bug 2: ICache combinational ARVALID active trong reset**
- File: [cache_interface/icache/icache_axi_interface.v](cache_interface/icache/icache_axi_interface.v#L52)
- Triệu chứng: ICache dùng `cpu_rst_n` (held trong boot), inst_mem dùng `fabric_rst_n` (active từ cycle 2022). ICache's `M_AXI_ARVALID = (state==IDLE) && refill_start` là combinational → ARVALID=1 ngay cả khi reset → inst_mem bắt đầu burst stuck.
- Tag: `FIX-ICACHE-RESET-ARVALID`
- Fix: `assign M_AXI_ARVALID = (state == IDLE) && refill_start && rst_n;`

**Bug 3: DECERR slave always-1 arready leak vào OR-tree**
- File: [interconnect/axi4_decerr_slave.v](interconnect/axi4_decerr_slave.v)
- Triệu chứng: `M{N}_AXI_ARREADY = OR(all slave arready)`. DECERR slave registered `s_arready=1` luôn trong RS_IDLE → leak vào OR → master tưởng AR đã accept dù target slave thật chưa accept → AR mất luôn.
- Bằng chứng: instrumented `inst_mem_axi_slave.v` log AR receive: 32 ARs từ M0, 0 ARs từ M1 (M1's AR không bao giờ tới IMEM).
- Tags: `FIX-DECERR-ARREADY`, `FIX-DECERR-AWREADY`
- Fix: gate combinational `assign s_arready = (rs_state == RS_IDLE) && s_arvalid;`

### Cách 2 bugs tương tác (vì sao chỉ fix 1 không đủ)
1. ICache combinational ARVALID active trong boot → inst_mem (đã active) thấy AR → bắt đầu burst stuck.
2. Sau cpu_rst_n release, ICache cần ARREADY=1 để escape stuck → DECERR's always-1 arready leak vào OR-tree là hack vô tình hoạt động cho M0.
3. Nhưng cùng leak làm M1 thấy false-ARREADY cho S0 → M1 drop arvalid → AR mất.

**Fix cả 2 đồng thời**: ICache không tạo stuck burst → không cần hack → DECERR có thể fix sạch → M1→S0 hoạt động bình thường.

## 4. Bug còn lại — DCache reading IMEM consistency

**Trạng thái**: ❌ Chưa fix (cần session debug riêng)

**Triệu chứng**: 8/9 tests vẫn TIMEOUT sau khi fix crossbar bug. test_uart_simple PASS vì không đọc IMEM qua DCache.

**Bằng chứng cụ thể trong test_uart** ([log/test_uart.log](log/test_uart.log) sau fix):
```
[4192] [M1-AR] addr=0x00000010  len=3  -> IMEM         ← M1 fetch IMEM line OK
[4194] [LD]    addr=0x00000014  data=0x01828293       ← Read 0x14 = đúng (rodata word)
[4205] [LD]    addr=0x10001ebc  data=0x00000014       ← Stack load OK
[4214] [LD]    addr=0x00000014  data=0x00000000       ← Same addr, value=0 (SAI!)
[4218] [ST]    addr=0x10001ebc  data=0x00000015       ← CPU stuck loop
```

**Cùng địa chỉ 0x14, hai lần read trả khác nhau**. Lần 1 đúng, lần 2 = 0.

**Hypotheses cần verify**:
1. **DCache write-back caching IMEM region nhầm**. IMEM addresses (0x0-0x1FFF) đáng lẽ nên uncached hoặc invalidate khi không dùng. DCache cache line đầu có data đúng, sau bị evict/overwrite.
2. **DCache prefetcher giống ICache** — có thể có alias overwrite. Cần check `cache_interface/dcache/dcache_controller.v` có prefetch engine không.
3. **ICache prefetcher đè memory[0x14]** — ICache vẫn prefetch IMEM lines, nếu BRAM shared port có race với DCache read.

**Hot files để debug**:
- [cache_interface/dcache/dcache_controller.v](cache_interface/dcache/dcache_controller.v) — DCache logic (write-back, dirty bitmap)
- [cpu/core/LSU.v](cpu/core/LSU.v) — load/store unit, store-to-load forwarding
- [memory/inst_mem.v](memory/inst_mem.v) — BRAM dual port (write từ boot_we, read từ AXI)

**Có thể cần làm**:
1. Thêm `$display` debug vào `dcache_controller.v` log mỗi line allocate/evict/hit.
2. Trace 2 lần load 0x14 — xem lần 2 là cache hit hay miss + AR phát ra đâu.
3. Check linker script `gnu_toolchain/linker_minimal.ld` — rodata có nằm trong vùng cacheable không.

**Tests bị ảnh hưởng**: test_uart, test_gpio, test_timer, test_clint, test_plic, test_ascon, test_dma_uart, test_integration (tất cả test có rodata hoặc deep call stack).

## 5. Files quan trọng (cho future sessions)

### Production RTL
- `cache_interface/icache/` — ICache (đã fix)
- `cache_interface/dcache/` — DCache (cần debug)
- `interconnect/axi4_crossbar_5m12s.v` — AXI crossbar (5 masters × 12 slaves)
- `interconnect/axi4_master_mux_5m.v` — per-slave mux với fixed priority M0>M1>M2>M3>M4
- `interconnect/axi4_decerr_slave.v` — DECERR slave (đã fix)
- `memory/inst_mem_axi_slave.v` — IMEM AXI wrapper
- `memory/inst_mem.v` — IMEM BRAM (dual port: boot_we write + AXI read)
- `run_soc_ascon.v` — top-level TB

### Firmware
- `gnu_toolchain/tests/*.c` — test source
- `gnu_toolchain/tests/*.hex` — built hex files
- `gnu_toolchain/compile_c_to_hex.sh` — build script (dùng `-c` cho bare-metal)
- `gnu_toolchain/build_all.sh` — build tất cả tests

### Tooling
- `workflow/urun_verilog.sh` — wrapper iverilog+vvp với `-l <logname>` option
- `regression_full.sh` — script này
- `.claude/rules/` — coding conventions cho session AI

## 6. Quick debug commands

```bash
# Xem activity post-boot trong 1 test
awk '/^\[/ && !/M0-AR/ {n=substr($1,2,length($1)-2)+0; if(n>4072) print}' log/test_uart.log | head -30

# So sánh M1-AR vs M0-AR counts
echo "M0:" $(grep -c "M0-AR" log/test_uart.log)
echo "M1:" $(grep -c "M1-AR" log/test_uart.log)
echo "M1->IMEM:" $(grep -c "M1-AR.*IMEM" log/test_uart.log)

# Tìm ERR-RAW (scoreboard mismatch — có thể false-positive cho write-back DCache)
grep "ERR-RAW" log/test_uart.log | head -10

# Inspect specific cycle range
awk -v lo=4000 -v hi=4500 '/^\[/{n=substr($1,2,length($1)-2)+0; if(n>=lo && n<=hi) print}' log/test_uart.log

# LOG_LEVEL tăng lên 3 để có per-beat trace (chỉnh trong run_soc_ascon.v)
# `define LOG_LEVEL 3
```
