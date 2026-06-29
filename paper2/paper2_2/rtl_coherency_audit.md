# Audit RTL coherency cho paper2_2

Phạm vi:
- Dựa trên các source root hiện tại được include bởi `soc_top.v`
- Tập trung vào các file RTL đầu tiên cần thay đổi cho kế hoạch dual-core + snoop coherency

Ghi chú trạng thái hiện tại:
- Repo hiện đã có một protocol TB tại `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`
- TB đó chứng minh automatic `CPU1 read miss -> peer snoop -> dirty owner writeback/invalidate -> CPU1 refill latest data`
- TB này cũng chứng minh DMA-style coherent read và invalidate qua shared snoop path
- Repo cũng có `ascon/dma/tb/tb_ascon_dma.v` pass `66 PASS / 0 FAIL`
- Snoop interconnect đã được cập nhật và verify lại:
  - `dcache_snoop_arb_3to1` hiện xoay grant công bằng hơn
  - `dma_snoop_arb` không còn khóa theo ưu tiên read-over-write cố định
  - `dcache_snoop_bus_2way` hiện capture responder data phòng thủ hơn và cảnh báo khi có conflicting dual-hit payload
- `soc_top.v` hiện nối các CPU-miss-driven snoop initiator từ cả hai DCache instance qua snoop arbiter 3 nguồn
- `test_dualcore_peer_snoop` hiện chứng minh `CPU0 dirty write -> CPU1 read same line` ở mức firmware/top-level
- Full ASCON DMA engine end-to-end coherency hiện đã đóng ở mức SoC dual-core
- Proof firmware/TB mức SoC ổn định:
  - `gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.c`
  - `tb_soc/tb_soc_dualcore_suite.v` GPIO/AUX-based completion check
  - verify PASS hiện tại:
    - `heartbeat=4`
    - `shared_count=1`
    - `aux0=0xac03d003`
    - `gpio=0xac03d003`
    - `core0_dc_req_count=12437`
    - `core1_dc_req_count=12527`
    - `dcache0 writes=4191 hits=12398`
    - `dcache1 writes=4183 hits=12522`
- Các sửa lỗi closure chính:
  - per-hart private stack generation trong `gnu_toolchain/compile_c_to_hex.sh`
  - non-cacheable write-strobe latch trong `cache_interface/dcache/dcache_axi_interface.v`
  - ASCON DMA start/mode/data-valid sequencing trong `ascon/ascon_top.v` và `ascon/dma/rtl/dma_ctrl_fsm.v`
  - debug-only ASCON/AXI trace gating để giữ normal regression sạch
  - H3/H1 hiện là phạm vi audit tiếp theo, không chỉ là ý tưởng tương lai

## 1) Tích hợp top-level trước

### `soc_top.v`
- Lý do đi trước: đây là nơi CPU, ICache, DCache, DMA và crossbar hiện tại được nối với nhau.
- Trạng thái:
  - `CPU Core 1`, `ICache 1` và `DCache 1` đã được tích hợp.
  - Shared snoop/coherency interconnect đã có.
  - Các CPU miss-snoop port được route qua arbiter.
  - `CPU1` có `mhartid = 1` và shared IRQ/debug request wiring.
- Việc cần làm tiếp:
  - Thêm visibility debug/perf theo từng core nếu paper cần.
  - Thêm benchmark/performance counter cho các bảng cuối của paper.

### `interconnect/axi4_crossbar_5m12s.v`
- Lý do quan trọng: fabric hiện tại có 5 master; dual-core cần ít nhất thêm một master path.
- Thay đổi có thể cần:
  - Thêm master port mới cho traffic của `Core 1`
  - Kiểm tra lại address decode / arbitration priorities
  - Giữ DMA và cache master không starvation lẫn nhau dưới contention

### `interconnect/axi4_master_mux_5m.v`
- Lý do quan trọng: nếu crossbar hoặc sub-fabric vẫn mux master nội bộ, mux đó phải mở rộng theo core mới.
- Thay đổi có thể cần:
  - Mở rộng master select logic
  - Verify ID/response routing vẫn trả về đúng requester

## 2) DCache coherency là block rủi ro nhất

### `cache_interface/dcache/dcache_tag_array.v`
- Lý do đi sớm: đây là nơi cache line state đang được lưu hiện nay.
- Thay đổi có thể cần:
  - Thay model `valid/dirty` hiện tại bằng MESI-style state encoding, hoặc thêm state field 2-bit riêng
  - Chỉnh hit logic và eviction bookkeeping
  - Thêm state update theo từng line cho snoop invalidate / downgrade

### `cache_interface/dcache/dcache_controller.v`
- Lý do critical: FSM này đang sở hữu refill, eviction, fence và xử lý snoop sideband.
- Trạng thái:
  - Explicit snoop handling for read/invalidate/response exists.
  - Peer miss-snoop state exists for cacheable read misses.
  - Dirty owner writeback/invalidate ordering is covered by protocol TB.
- Việc cần làm tiếp:
  - Direct cache-to-cache data forwarding chưa được implement; safe path hiện tại là writeback/invalidate rồi refill.
  - Tiếp tục stress-test các race case giữa CPU request, flush và snoop traffic.

### `cache_interface/dcache/dcache_top.v`
- Lý do đây là integration point: nó nối tag array, data array, controller, AXI interface và sideband snoop ports.
- Trạng thái:
  - Các signal MESI/snoop đã được luồng hóa qua top.
  - Per-cache snoop responder and miss-snoop initiator ports are exposed.
  - CPU-facing API remains stable.

### `cache_interface/dcache/dcache_axi_interface.v`
- Lý do có thể cần sửa tiếp: timing refill/evict đã có behavior nhạy ở mức chu kỳ.
- Thay đổi có thể cần:
  - Đảm bảo eviction/refill do snoop kích hoạt không race với CPU traffic bình thường
  - Giữ AXI bursts align với cache-line state transitions
  - Rà lại các giả định chỉ còn đúng trong hệ thống single-core

### `cache_interface/dcache/dcache_data_array.v`
- Lý do ưu tiên thấp hơn: data storage có thể không cần sửa lớn, nhưng coherency có thể cần hỗ trợ đọc full line.
- Thay đổi có thể cần:
  - Có thể rất ít
  - Có thể cần helper readout bổ sung nếu snoop response phải trả về full cache line

### `cache_interface/dcache/tb/tb_dcache_snoop.v`
- Lý do hữu ích sớm: đây là testbench trực tiếp cho snoop path.
- Thay đổi có thể cần:
  - Mở rộng test cho read-hit, invalidate-hit và dirty-line response
  - Thêm check cho MESI state transitions nếu tag encoding thay đổi

## 3) DMA sideband coherency

### `ascon/dma/rtl/ascon_dma.v`
- Lý do quan trọng: version này đã expose `coh_ctrl` và sideband snoop interface.
- Thay đổi có thể cần:
  - Functional path hiện đã được verify bằng standalone DMA TB và full SoC ASCON DMA proof
  - Tiếp tục thêm số đo stress/contention nếu paper cần dữ liệu fairness hoặc throughput

### `ascon/dma/rtl/dma_read_engine.v`
- Lý do quan trọng: đây là nơi coherent read thử snoop trước khi fallback sang AXI.
- Trạng thái:
  - Coherent read path is verified by protocol TB, standalone DMA TB, and full SoC ASCON DMA proof.
  - Full SoC proof confirms DMA sees latest CPU-produced dirty input.

### `ascon/dma/rtl/dma_write_engine.v`
- Lý do quan trọng: coherent write phải invalidate hoặc downgrade cache khác trước memory writeback.
- Trạng thái:
  - Coherent write/invalidate primitive is verified by protocol TB and standalone DMA TB.
  - Full SoC ASCON DMA proof confirms output/tag visibility under cache-hit pressure.

### `ascon/dma/rtl/dma_snoop_arb.v`
- Lý do quan trọng: arbiter này có thể là nơi serialize request ordering.
- Trạng thái:
  - Read-vs-write snoop arbitration has been updated to a fairer alternation policy.
  - Standalone DMA TB vẫn pass sau cập nhật.
- Việc cần làm tiếp:
  - Thêm số đo tập trung vào contention ở mức SoC nếu paper cần số liệu fairness.

### `ascon/ascon_top.v`
- Lý do quan trọng: đây là integration point cho ASCON core, DMA và slave register bank.
- Trạng thái:
  - DMA mode/start sequencing is verified by full ASCON DMA SoC proof.
  - Register map stayed stable for firmware.
  - Sideband coherency vẫn được expose ra fabric mức SoC.

### `ascon/interface/rtl/ascon_axi_slave.v`
- Lý do quan trọng: đây là nơi CPU cấu hình behavior ASCON/DMA.
- Trạng thái:
  - Register fields match current firmware assumptions.
  - Debug traces are gated so normal regression output stays readable.

## 4) Thay đổi phía CPU có thể nhỏ hơn

### `cpu/riscv_cpu_core_v2.v`
- Lý do nằm trong danh sách: core hiện tại đã phát `dcache_req`, `dcache_we` và `fence_type`.
- Trạng thái:
  - Core has `HART_ID` parameter.
  - CSR `mhartid` trả về hart ID đã cấu hình.
- Việc cần làm tiếp:
  - Chỉ thêm debug/perf hook nếu paper cần visibility theo từng core.

### `cpu/core/LSU.v`
- Lý do liên quan: LSU là nơi load/store, fence và bypass behavior gặp DCache handshake.
- Thay đổi có thể cần:
  - Rà behavior fence theo coherent DCache rules
  - Đảm bảo non-cacheable hoặc MMIO path không phá snoop timing

## 5) Đường SoC DMA hiện tại / legacy

### `dma/dma_ctrl.v`
- Lý do vẫn liên quan: đây là SoC DMA controller hiện đang nối trong `soc_top.v`.
- Thay đổi có thể cần:
  - Nếu H3/H1 vẫn dùng DMA path này, thêm coherency interface mới ở đây
  - Nếu không, giữ ổn định và tập trung vào ASCON coherent DMA trước

### `dma/rtl/dma_axi_master.v`, `dma/rtl/dma_channel.v`, `dma/rtl/dma_arbiter.v`, `dma/rtl/dma_reg_slave.v`
- Lý do có thể liên quan: đây là các submodule phía sau SoC DMA controller.
- Thay đổi có thể cần:
  - Hầu như giữ nguyên, trừ khi SoC DMA cũng phải tham gia snoop fabric mới

## 6) Thứ tự sửa đề xuất đầu tiên

1. `soc_top.v`
2. `cache_interface/dcache/dcache_tag_array.v`
3. `cache_interface/dcache/dcache_controller.v`
4. `cache_interface/dcache/dcache_top.v`
5. `ascon/dma/rtl/ascon_dma.v`
6. `ascon/dma/rtl/dma_read_engine.v`
7. `ascon/dma/rtl/dma_write_engine.v`
8. `interconnect/axi4_crossbar_5m12s.v`
9. `interconnect/axi4_master_mux_5m.v`
10. `tb_dcache_snoop.v` và các cache/DMA testbench liên quan

## 7) Next audit scope: H3 and H1

### H3 - Multi-Context ASCON
- Start from `ascon/ascon_top.v`
- Thêm `context_id` plumbing trong `ascon/interface/rtl/ascon_axi_slave.v` hoặc entry point AXI slave hiện tại
- Luồng hóa context selection vào `ascon/dma/rtl/ascon_dma.v` và `ascon/dma/rtl/dma_ctrl_fsm.v`
- Thêm dual-core firmware test where `CPU0` and `CPU1` own different contexts

### H1 - Compute-in-Cache
- Start from `cache_interface/dcache/dcache_tag_array.v`
- Thêm metadata bit nhỏ theo từng line such as `crypto_pending`
- Extend `cache_interface/dcache/dcache_controller.v` with queue/batching logic
- Chỉ đụng `cache_interface/dcache/dcache_top.v` khi micro-architecture đủ ổn định cho proof-of-concept

## 7) Ghi chú thực tế

- Repo có nhiều snapshot và bản trùng dưới `pd2/` và `cpu/pd/`
- Không bắt đầu ở đó trừ khi build flow chứng minh các bản copy đó là bản đang active
- Các root file được nhắc ở trên là điểm bắt đầu an toàn nhất cho phần multicore của paper2_2
