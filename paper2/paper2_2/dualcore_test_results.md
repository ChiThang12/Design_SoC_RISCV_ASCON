# Dual-Core Test Results

Unified SoC TB:
- `tb_soc/tb_soc_dualcore_suite.v`

Firmware suite:
- `gnu_toolchain/tests_dualcore/test_dualcore_basic.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_cache_sweep.c`
- `gnu_toolchain/tests_dualcore/test_dualcore_fence_flush.c`

Directed coherency-protocol TB:
- `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`

Run date:
- 2026-06-28

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

- `tb_dcache_dualcore_protocol`
  - PASS
  - `16 PASS / 0 FAIL`
  - Verified protocol sequence:
    - `CPU0` refill gets a line and moves to `E`
    - `CPU0` writes the line and moves to `M`
    - upstream `snoop-read` returns the latest modified line from `CPU0`
    - upstream `invalidate` forces dirty writeback to shared memory
    - `CPU1` refills afterward and observes the latest `CPU0` data

Command entrypoints:
- `bash run_dualcore_suite.sh`
- Chi tiet bash command: `paper2/paper2_2/dualcore_test_commands.md`

Current limitation:
- These tests prove dual-core execution, shared-memory activity, DCache traffic, and fence-driven writeback visibility.
- The directed protocol TB proves the responder side of `CPU0 write -> CPU1 observe` at DCache/snoop-bus level.
- The SoC top still does not have an automatic CPU-miss-initiated cache-to-cache snoop path, so full end-to-end CPU-CPU ownership transfer inside `soc_top` remains a next step.
- DMA multicore snoop correctness also remains a next step.

Completion guide:
- Short-term stable validation path:
  - Run standalone DCache regressions
  - Run `tb_dcache_dualcore_protocol.v`
  - Run `bash run_dualcore_suite.sh`
- To claim a stronger dual-core result in the paper, the next missing proof is:
  - `CPU miss` automatically triggering snoop toward peer DCache owner at top level
  - returned latest line or forced writeback/invalidate without using a directed external snoop stimulus
- After that, the next missing proof is DMA multicore coherency:
  - coherent DMA read sourcing the latest peer-cache line
  - coherent DMA write invalidating or downgrading both peer caches in a deterministic order
