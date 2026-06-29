# Kết quả Test Dual-Core

Ghi chú:
- File này là baseline ổn định để H1/H3 kế thừa.
- Đường dual-core coherency đã đóng functional closure; việc tiếp theo là H3 context plumbing, H1 compute-in-cache và các số đo paper-ready.

Unified SoC TB:
- `tb_soc/tb_soc_dualcore_suite.v`

Firmware suite:
- `gnu_toolchain/tests_dualcore/test_dualcore_basic.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_cache_sweep.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_fence_flush.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_peer_snoop.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.c`

Directed coherency-protocol TB:
- `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`

Ngày chạy:
- 2026-06-28
- Lần refresh verify gần nhất:
  - 2026-06-29 after full ASCON DMA dual-core SoC closure
  - 2026-06-29 after direct cache-to-cache forwarding enablement
  - 2026-06-29 after CPU/DMA contention benchmark capture for paper data

Kết quả:
- `test_dualcore_basic`
  - PASS
  - `heartbeat=16`
  - `shared_count=16`
  - `core0_dc_req_count=262`
  - `core1_dc_req_count=261`
  - `dcache0 writes=131 hits=255`
  - `dcache1 writes=131 hits=255`

- `test_dualcore_cache_sweep`
  - PASS
  - `heartbeat=20`
  - `shared_count=20`
  - `aux0=0x00000000`
  - `aux1=0x00000012`
  - `core0_dc_req_count=12575`
  - `core1_dc_req_count=12574`
  - `dcache0 writes=4716 hits=12559`
  - `dcache1 writes=4716 hits=12559`

- `test_dualcore_fence_flush`
  - PASS
  - `heartbeat=20`
  - `shared_count=20`
  - `aux0=0xff000036`
  - `aux1=0xff0000d8`
  - `core0_dc_req_count=899`
  - `core1_dc_req_count=899`
  - `dcache0 writes=347 hits=890`
  - `dcache1 writes=347 hits=890`

- `test_dualcore_peer_snoop`
  - PASS
  - `heartbeat=2`
  - `shared_count=1`
  - `aux0=0xfaceb00c`
  - `aux1=0x22220001`
  - `core0_dc_req_count=15`
  - `core1_dc_req_count=16406`
  - `dcache0 writes=13 hits=9`
  - `dcache1 writes=8204 hits=16398`
  - `dcache0 peer_snp_reqs=0 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=6`
  - `dcache1 peer_snp_reqs=3 peer_snp_hits=3 c2c_fwds=3 c2c_fill_cycles=12 mem_refills=4`
  - Chuỗi firmware top-level đã verify:
    - `CPU0` publish start, sau đó ghi `DATA_ADDR=0x10000220` và giữ line dirty
    - `CPU1` đọc cùng địa chỉ
    - `CPU1` read miss kích hoạt automatic peer snoop
    - `CPU0` dirty line được writeback/invalidate và cache line mới nhất được trả về trên snoop response
    - `CPU1` install line bằng direct cache-to-cache forwarding thay vì refill line yêu cầu từ memory
    - `CPU1` quan sát `0xfaceb00c` and publishes it through `aux0`

- `tb_dcache_dualcore_protocol`
  - PASS
  - `25 PASS / 0 FAIL`
  - Chuỗi protocol đã verify:
    - `CPU0` refill gets a line and moves to `E`
    - `CPU0` ghi line và chuyển sang `M`
    - directed upstream `snoop-read` trả về modified line mới nhất từ `CPU0`
    - `CPU1` read miss automatically issues a peer snoop
    - `CPU0` dirty owner writeback và invalidate, đồng thời trả về full line trên snoop response
    - `CPU1` fill line trực tiếp từ snoop response và tránh memory refill ở miss đó
    - `CPU1` sau đó có thể ghi line và trở thành modified owner
    - DMA-style coherent read trả về modified line mới nhất từ `CPU1`
    - DMA-style coherent invalidate forces dirty writeback and invalidates `CPU1`
  - Các protocol counter bổ sung hiện chứng minh:
    - `stat1_peer_snoop_reqs = 1`
    - `stat1_peer_snoop_hits = 1`
    - `stat1_c2c_forwards = 1`
    - `stat1_mem_refills = 0`

- `tb_ascon_dma`
  - PASS
  - `66 PASS / 0 FAIL`
  - Các building block DMA-side coherency đã verify:
    - coherent read snoop hit path works through `coh_ctrl=2'b11`
    - coherent write path issues invalidate snoops before AXI writeback
    - DMA read/write snoop arbitration remains functional after arbiter update
    - AXI backpressure and error-path handling remain intact

- `test_dualcore_ascon_dma_coherent`
  - PASS
  - `heartbeat=4`
  - `shared_count=1`
  - `aux0=0xac03d003`
  - `aux1=0x00000000`
  - `core0_dc_req_count=12437`
  - `core1_dc_req_count=12527`
  - `dcache0 writes=4191 hits=12398`
  - `dcache1 writes=4183 hits=12522`
  - `dcache0 peer_snp_reqs=1 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=11`
  - `dcache1 peer_snp_reqs=0 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=5`
  - Chuỗi full SoC đã verify:
    - `CPU0` ghi ASCON plaintext/source data và giữ source line cache-dirty
    - ASCON DMA coherent read path snoop plaintext mới nhất thay vì dùng stale memory
    - `CPU0` và `CPU1` đều touch vùng output/tag nên DMA output path phải xử lý cached line
    - ASCON DMA coherent write invalidates/writebacks affected output cache lines
    - `CPU0` validates ciphertext/tag words
    - `CPU1` validate các peer-visible tag word
    - `GPIO` và `AUX0` publish final pass marker `0xac03d003`

- `test_dualcore_contention_forward_dma`
  - PASS
  - `cycles=49957`
  - `heartbeat=3`
  - `shared_count=0`
  - `core0_dc_req_count=4597`
  - `core1_dc_req_count=4728`
  - `dcache0 writes=1624 hits=4518`
  - `dcache1 writes=1630 hits=4685`
  - `dcache0 peer_snp_reqs=5 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=59`
  - `dcache1 peer_snp_reqs=24 peer_snp_hits=10 c2c_fwds=10 c2c_fill_cycles=40 mem_refills=32`
  - Diễn giải:
    - Đây là baseline paper cho `direct cache-to-cache forwarding under concurrent ASCON DMA load`
    - `CPU1` nhận nhiều peer-snoop hit khi DMA đang hoạt động
    - `10` forwarded fill được quan sát ở consumer cache
    - mốc hoàn tất end-to-end là `49957` cycles

- `test_dualcore_contention_fallback_dma`
  - PASS
  - `cycles=81320`
  - `heartbeat=2`
  - `shared_count=12`
  - `core0_dc_req_count=7788`
  - `core1_dc_req_count=8101`
  - `dcache0 writes=2693 hits=7679`
  - `dcache1 writes=3143 hits=8093`
  - `dcache0 peer_snp_reqs=10 peer_snp_hits=0 c2c_fwds=0 c2c_fill_cycles=0 mem_refills=82`
  - `dcache1 peer_snp_reqs=2 peer_snp_hits=2 c2c_fwds=2 c2c_fill_cycles=8 mem_refills=6`
  - Diễn giải:
    - Đây là case fallback/reference, trong đó cache state phía producer bị làm nhiễu để consumer quan sát ít forwarded fill hơn
    - chỉ còn `2` forwarded fill ở consumer cache
    - mốc hoàn tất end-to-end tăng lên `81320` cycles

Tóm tắt contention benchmark cho số liệu paper-ready:

| Scenario | Cycles | Core1 Peer Snoop Hits | Core1 C2C Forwards | Core1 C2C Fill Cycles | Core0 Mem Refills | Core1 Mem Refills |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| forward-hit + DMA | 49957 | 10 | 10 | 40 | 59 | 32 |
| fallback-refill + DMA | 81320 | 2 | 2 | 8 | 82 | 6 |

- So sánh suy ra:
  - Case forwarding hoàn tất trong `49957 / 81320 = 0.614x` thời gian fallback
  - Tương đương, direct forwarding nhanh khoảng `1.63x` hơn case fallback trong benchmark này
  - Consumer-side `c2c_fwds` improves from `2` to `10` (`+5x`)
  - Consumer-side `peer_snp_hits` improves from `2` to `10` (`+5x`)

Standalone DCache regressions:
- `tb_dcache.v`
  - PASS
  - `59 PASS / 0 FAIL`
- `tb_dcache_snoop.v`
  - PASS
  - `14 PASS / 0 FAIL`
- `tb_dcache_mesi.v`
  - PASS
  - `14 PASS / 0 FAIL`

Entrypoint lệnh:
- `bash run_dualcore_suite.sh`
- Chi tiết bash command: `paper2/paper2_2/dualcore_test_commands.md`
- TB bổ sung tập trung vào DMA:
  - `ascon/dma/tb/tb_ascon_dma.v`

Trạng thái hiện tại:
- Các test này chứng minh dual-core execution, shared-memory activity, DCache traffic, and fence-driven writeback visibility.
- DCache protocol TB chứng minh automatic CPU read-miss peer snoop at DCache/snoop-bus level.
- `soc_top.v` now wires CPU miss snoop requests from both DCache instances through a 3-source snoop arbiter.
- Các snoop arbiter đã được cập nhật và verify lại:
  - top-level `dcache_snoop_arb_3to1` now uses fairer round-robin style grant rotation
  - DMA `dma_snoop_arb` no longer relies on fixed read-over-write priority
  - `dcache_snoop_bus_2way` now captures responses more defensively and warns on conflicting dual-hit data
- `test_dualcore_peer_snoop` hiện chứng minh đường CPU-CPU dirty-owner transfer ở mức firmware/top-level.
- Đường CPU miss hiện hỗ trợ direct cache-to-cache forwarding:
  - peer invalidate/writeback still preserves correctness for dirty owners
  - requester có thể fill line trực tiếp từ snoop response mà không cần memory refill khi peer hit
- Các counter mới hiện có in `tb_soc/tb_soc_dualcore_suite.v` / `soc_top.v` for paper data collection:
  - `peer_snp_reqs`
  - `peer_snp_hits`
  - `c2c_fwds`
  - `c2c_fill_cycles`
  - `mem_refills`
- DMA-side snoop engines, standalone ASCON DMA coherency primitives, and full SoC-level ASCON DMA multicore end-to-end flow are now regression-covered.
- Phần còn lại cho câu chuyện H1/H3 tách thành:
  - architecture: context plumbing for H3 and compute-in-cache metadata for H1
  - measurements: per-context H3 throughput, per-core miss-rate reporting, and baseline-vs-H3-vs-H1 comparison
- H3 và H1 là các mục architecture-phase tiếp theo từ `paper2/paper2_2/H1+H3.md`.

Hướng dẫn completion:
- Short-term stable validation path:
  - Chạy standalone DCache regressions
  - Chạy `tb_dcache_dualcore_protocol.v`
  - Chạy `ascon/dma/tb/tb_ascon_dma.v`
  - Chạy `bash run_dualcore_suite.sh`
- Strong CPU-CPU dual-core result now has both protocol-level and firmware/top-level proof.
- Strong DMA-side result now has protocol-level DCache proof, standalone ASCON-DMA proof, and full SoC-level ASCON DMA proof.
- Phần còn thiếu tiếp theo cho paper H1/H3 không phải functional closure, mà là thu thập số liệu:
  - snoop-count / cache-miss / throughput tables dùng các forwarding counter mới
  - H3 context-switch benchmark
  - H1 compute-in-cache latency/throughput benchmark

Closure ASCON DMA SoC mới nhất cho mục 2.3:
- Firmware:
  - `gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.c`
- Kiểm tra completion trong TB:
  - `GPIO_CHECK_ENABLE`
  - `EXPECT_GPIO`
  - `AUX0_CHECK_ENABLE`
  - `EXPECT_AUX0`
- Trạng thái verify hiện tại:
  - build PASS
  - SoC-level run PASS
  - snapshot PASS quan sát được:
    - `heartbeat=4`
    - `shared_count=1`
    - `aux0=0xac03d003`
    - `aux1=0x00000000`
    - `core0_dc_req_count=12437`
    - `core1_dc_req_count=12527`
    - `dcache0 writes=4191 hits=12398`
    - `dcache1 writes=4183 hits=12522`
  - diễn giải:
    - full ASCON DMA coherent read thấy input dirty do CPU tạo
    - full ASCON DMA coherent write visible sau output/cache-hit pressure từ cả hai core
    - GPIO vẫn dùng được cho PASS marker này, nên case này chưa cần UART fallback
