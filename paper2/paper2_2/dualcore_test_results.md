# Dual-Core Test Results

Unified SoC TB:
- `tb_soc/tb_soc_dualcore_suite.v`

Firmware suite:
- `gnu_toolchain/tests_dualcore/test_dualcore_basic.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_cache_sweep.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_fence_flush.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_peer_snoop.c`

Directed coherency-protocol TB:
- `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`

Run date:
- 2026-06-28
- Last verification refresh:
  - 2026-06-28 after snoop-arbiter / snoop-bus robustness update

Results:
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
  - Verified top-level firmware sequence:
    - `CPU0` publishes start, then writes `DATA_ADDR=0x10000220` and keeps the line dirty
    - `CPU1` reads the same address
    - `CPU1` read miss triggers automatic peer snoop
    - `CPU0` dirty line is written back/invalidated
    - `CPU1` observes `0xfaceb00c` and publishes it through `aux0`

- `tb_dcache_dualcore_protocol`
  - PASS
  - `22 PASS / 0 FAIL`
  - Verified protocol sequence:
    - `CPU0` refill gets a line and moves to `E`
    - `CPU0` writes the line and moves to `M`
    - directed upstream `snoop-read` returns the latest modified line from `CPU0`
    - `CPU1` read miss automatically issues a peer snoop
    - `CPU0` dirty owner writes back and invalidates before `CPU1` refill
    - `CPU1` refills afterward and observes the latest `CPU0` data
    - `CPU1` can then write the line and become the modified owner
    - DMA-style coherent read returns the latest modified line from `CPU1`
    - DMA-style coherent invalidate forces dirty writeback and invalidates `CPU1`

- `tb_ascon_dma`
  - PASS
  - `66 PASS / 0 FAIL`
  - Verified DMA-side coherency building blocks:
    - coherent read snoop hit path works through `coh_ctrl=2'b11`
    - coherent write path issues invalidate snoops before AXI writeback
    - DMA read/write snoop arbitration remains functional after arbiter update
    - AXI backpressure and error-path handling remain intact

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

Command entrypoints:
- `bash run_dualcore_suite.sh`
- Chi tiet bash command: `paper2/paper2_2/dualcore_test_commands.md`
- Additional DMA-focused TB:
  - `ascon/dma/tb/tb_ascon_dma.v`

Current limitation:
- These tests prove dual-core execution, shared-memory activity, DCache traffic, and fence-driven writeback visibility.
- The DCache protocol TB proves automatic CPU read-miss peer snoop at DCache/snoop-bus level.
- `soc_top.v` now wires CPU miss snoop requests from both DCache instances through a 3-source snoop arbiter.
- The snoop arbiters were refreshed and re-verified:
  - top-level `dcache_snoop_arb_3to1` now uses fairer round-robin style grant rotation
  - DMA `dma_snoop_arb` no longer relies on fixed read-over-write priority
  - `dcache_snoop_bus_2way` now captures responses more defensively and warns on conflicting dual-hit data
- `test_dualcore_peer_snoop` now proves the CPU-CPU dirty-owner transfer path at firmware/top-level level.
- The current CPU miss path uses peer invalidate/writeback followed by normal refill; it is not direct cache-to-cache data forwarding.
- DMA-side snoop engines and standalone ASCON DMA coherency primitives are now regression-covered, but full SoC-level ASCON DMA multicore end-to-end proof remains a next step.

Completion guide:
- Short-term stable validation path:
  - Run standalone DCache regressions
  - Run `tb_dcache_dualcore_protocol.v`
  - Run `ascon/dma/tb/tb_ascon_dma.v`
  - Run `bash run_dualcore_suite.sh`
- Strong CPU-CPU dual-core result now has both protocol-level and firmware/top-level proof.
- Strong DMA-side primitive result now has both protocol-level DCache proof and standalone ASCON-DMA proof.
- The next missing proof is still SoC-level DMA multicore coherency:
  - full ASCON DMA read sourcing the latest peer-cache line
  - full ASCON DMA write invalidating or downgrading both peer caches in a deterministic order

Latest WIP attempt for 2.3:
- Added experimental firmware:
  - `gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.c`
- Added optional non-cacheable completion hook in TB:
  - `GPIO_CHECK_ENABLE`
  - `EXPECT_GPIO`
- Current verification status:
  - build PASS for the new firmware image
  - SoC-level run still TIMEOUT
  - observed timeout snapshot:
    - `sig0=0xa5c02301`
    - `sig1=0xd24a6003`
    - `result=0xcafe0001`
    - `gpio=zzzzzzzz`
    - `core0_dc_req_count=30655`
    - `core1_dc_req_count=30690`
    - `dcache0 writes=10252 hits=30627`
    - `dcache1 writes=10237 hits=30685`
  - interpretation:
    - both cores generate heavy DCache traffic
    - the current RTL/firmware combination still lacks a stable SoC-level completion proof for full ASCON DMA multicore coherency
