# RTL coherency audit for paper2_2

Scope:
- Based on the current root sources that are included by `soc_top.v`
- Focused on the first RTL files that should change for the dual-core + snoop coherency plan

Current status note:
- The repo now has a protocol TB at `cache_interface/dcache/tb/tb_dcache_dualcore_protocol.v`
- That TB proves automatic `CPU1 read miss -> peer snoop -> dirty owner writeback/invalidate -> CPU1 refill latest data`
- The same TB also proves DMA-style coherent read and invalidate through the shared snoop path
- The repo also has `ascon/dma/tb/tb_ascon_dma.v` passing `66 PASS / 0 FAIL`
- The snoop interconnect was refreshed and re-verified:
  - `dcache_snoop_arb_3to1` now rotates grants more fairly
  - `dma_snoop_arb` no longer locks into fixed read-over-write preference
  - `dcache_snoop_bus_2way` now captures responder data more defensively and warns on conflicting dual-hit payloads
- `soc_top.v` now wires CPU-miss-driven snoop initiators from both DCache instances through a 3-source snoop arbiter
- `test_dualcore_peer_snoop` now proves `CPU0 dirty write -> CPU1 read same line` at firmware/top-level level
- Remaining gap: full ASCON DMA engine end-to-end coherency is not complete yet
- There is now an experimental SoC-level firmware/TB attempt:
  - `gnu_toolchain/tests_dualcore/test_dualcore_ascon_dma_coherent.c`
  - `tb_soc/tb_soc_dualcore_suite.v` optional GPIO-based completion check
  - current verification still times out, so this is not a closed proof yet

## 1) Top-level integration first

### `soc_top.v`
- Why it comes first: this is where the current CPU, ICache, DCache, DMA, and crossbar are wired together.
- Status:
  - `CPU Core 1`, `ICache 1`, and `DCache 1` are integrated.
  - The shared snoop/coherency interconnect is present.
  - CPU miss-snoop ports are routed through the arbiter.
  - `CPU1` has `mhartid = 1` and shared IRQ/debug request wiring.
- Follow-up:
  - Add stronger per-core debug/perf visibility if the paper needs it.
  - Add full ASCON DMA engine end-to-end coherency proof.

### `interconnect/axi4_crossbar_5m12s.v`
- Why it matters: the current fabric is 5 masters; dual-core needs at least one more master path.
- Likely changes:
  - Add a new master port for `Core 1` traffic
  - Re-check address decode / arbitration priorities
  - Keep DMA and cache masters from starving each other under contention

### `interconnect/axi4_master_mux_5m.v`
- Why it matters: if the crossbar or a sub-fabric still muxes masters internally, that mux must grow with the new core.
- Likely changes:
  - Extend master select logic
  - Verify ID/response routing still returns to the right requester

## 2) DCache coherency is the riskiest block

### `cache_interface/dcache/dcache_tag_array.v`
- Why it comes early: this is where cache line state lives today.
- Likely changes:
  - Replace the current `valid/dirty` model with MESI-style state encoding, or add a separate 2-bit state field
  - Adjust hit logic and eviction bookkeeping
  - Add per-line state updates for snoop invalidate / downgrade

### `cache_interface/dcache/dcache_controller.v`
- Why it is critical: this FSM already owns refill, eviction, fence, and snoop sideband handling.
- Status:
  - Explicit snoop handling for read/invalidate/response exists.
  - Peer miss-snoop state exists for cacheable read misses.
  - Dirty owner writeback/invalidate ordering is covered by protocol TB.
- Follow-up:
  - Direct cache-to-cache data forwarding is not implemented; current safe path is writeback/invalidate followed by refill.
  - Keep stress-testing race cases between CPU request, flush, and snoop traffic.

### `cache_interface/dcache/dcache_top.v`
- Why it is the integration point: it connects tag array, data array, controller, AXI interface, and sideband snoop ports.
- Status:
  - MESI/snoop signals are threaded through the top.
  - Per-cache snoop responder and miss-snoop initiator ports are exposed.
  - CPU-facing API remains stable.

### `cache_interface/dcache/dcache_axi_interface.v`
- Why it is likely to need follow-up edits: refill/evict timing already has delicate cycle-level behavior.
- Likely changes:
  - Ensure snoop-triggered eviction/refill does not race normal CPU traffic
  - Keep AXI bursts aligned with cache-line state transitions
  - Review any assumptions that still only make sense in a single-core system

### `cache_interface/dcache/dcache_data_array.v`
- Why it is lower priority: data storage itself may not need major changes, but coherency may need line readout support.
- Likely changes:
  - Probably minimal
  - May need extra readout helpers if snoop responses must return a full cache line

### `cache_interface/dcache/tb/tb_dcache_snoop.v`
- Why it is useful early: this is the direct testbench for the snoop path.
- Likely changes:
  - Extend tests for read-hit, invalidate-hit, and dirty-line response
  - Add checks for MESI state transitions if the tag encoding changes

## 3) DMA sideband coherency

### `ascon/dma/rtl/ascon_dma.v`
- Why it is important: this version already exposes `coh_ctrl` and a sideband snoop interface.
- Likely changes:
  - Rewire the snoop request/response path to the new snoop bus
  - Make DMA read/write engines use the shared coherency controller instead of a single DCache peer
  - Keep the DMA mode selection (`coh_ctrl`) aligned with the paper scenarios

### `ascon/dma/rtl/dma_read_engine.v`
- Why it matters: this is where coherent reads already try to snoop before falling back to AXI.
- Likely changes:
  - Broadcast snoop requests through the new bus
  - Accept data from whichever cache owns the newest line
  - Keep the fast path for hits and the fallback path for misses

### `ascon/dma/rtl/dma_write_engine.v`
- Why it matters: coherent writes must invalidate or downgrade other caches before memory writeback.
- Likely changes:
  - Add or refine invalidate sequencing
  - Make sure line-by-line invalidation is safe in multicore mode
  - Preserve the existing coherent/non-coherent mode switch

### `ascon/dma/rtl/dma_snoop_arb.v`
- Why it matters: this arbiter likely becomes the place where request ordering is serialized.
- Status:
  - Read-vs-write snoop arbitration has been updated to a fairer alternation policy.
  - Standalone DMA TB still passes after the update.
- Follow-up:
  - Add contention-focused measurement at SoC level if the paper needs fairness numbers.

### `ascon/ascon_top.v`
- Why it matters: it is the integration point for ASCON core, DMA, and the slave register bank.
- Likely changes:
  - Thread coherent DMA signals through the top
  - Keep the register map stable for firmware
  - Pass sideband coherency signals out to the SoC-level fabric

### `ascon/interface/rtl/ascon_axi_slave.v`
- Why it matters: this is where the CPU configures ASCON/DMA behavior.
- Likely changes:
  - Expose or forward `coh_ctrl`
  - Verify register fields still match the firmware assumptions

## 4) CPU-side changes are probably smaller

### `cpu/riscv_cpu_core_v2.v`
- Why it is on the list: the current core already emits `dcache_req`, `dcache_we`, and `fence_type`.
- Status:
  - Core has `HART_ID` parameter.
  - `mhartid` CSR returns the configured hart ID.
- Follow-up:
  - Add more debug/perf hooks only if the paper needs per-core visibility.

### `cpu/core/LSU.v`
- Why it is relevant: LSU is the place where loads/stores, fences, and bypass behavior meet the DCache handshake.
- Likely changes:
  - Review fence behavior against coherent DCache rules
  - Ensure non-cacheable or MMIO paths do not break snoop timing

## 5) Current SoC DMA / legacy path

### `dma/dma_ctrl.v`
- Why it is still relevant: this is the current SoC DMA controller wired in `soc_top.v`.
- Likely changes:
  - If the dual-core paper still uses this DMA path, add the new coherency interface here too
  - Otherwise, keep it stable and focus on the ASCON coherent DMA first

### `dma/rtl/dma_axi_master.v`, `dma/rtl/dma_channel.v`, `dma/rtl/dma_arbiter.v`, `dma/rtl/dma_reg_slave.v`
- Why they may matter: these are the submodules behind the SoC DMA controller.
- Likely changes:
  - Mostly unchanged unless the SoC DMA must also participate in the new snoop fabric

## 6) Suggested first edit order

1. `soc_top.v`
2. `cache_interface/dcache/dcache_tag_array.v`
3. `cache_interface/dcache/dcache_controller.v`
4. `cache_interface/dcache/dcache_top.v`
5. `ascon/dma/rtl/ascon_dma.v`
6. `ascon/dma/rtl/dma_read_engine.v`
7. `ascon/dma/rtl/dma_write_engine.v`
8. `interconnect/axi4_crossbar_5m12s.v`
9. `interconnect/axi4_master_mux_5m.v`
10. `tb_dcache_snoop.v` and the related cache/DMA testbenches

## 7) Practical note

- The repo has multiple snapshots and duplicates under `pd2/` and `cpu/pd/`
- Do not start there unless the build flow proves those copies are the active ones
- The root files referenced above are the safest first pass for the paper2_2 multicore work
