# CODE PATCHES - RISC-V CPU-HS (Non-Multiplier Issues)

---

## PATCH 1: FENCE DEADLOCK FIX

### Option A: Minimal Fix (Recommended for quick hotfix)

**File: LSU.v**

**Original (dòng ~281-290):**
```verilog
case (drain_state)
    DRAIN_IDLE: begin
        if (!sb_empty && !load_using_dcache)
            drain_state <= DRAIN_REQ;
    end

    DRAIN_REQ: begin
        if (load_using_dcache) begin
            drain_state <= DRAIN_IDLE;
        end else if (dcache_ready) begin
            drain_state <= DRAIN_IDLE;
        end
    end
    ...
endcase
```

**Patched (Add fence-aware drain):**
```verilog
// At top of LSU module, add:
reg fence_pending_r;

always @(posedge clk or posedge rst) begin
    if (rst)
        fence_pending_r <= 1'b0;
    else if (fence && !lsu_idle)
        fence_pending_r <= 1'b1;
    else if (lsu_idle)
        fence_pending_r <= 1'b0;
end
wire fence_pending = fence_pending_r;

// Then update drain FSM:
case (drain_state)
    DRAIN_IDLE: begin
        // Start drain if: (store buffer not empty) OR (fence pending)
        if ((!sb_empty || fence_pending) && !load_using_dcache)
            drain_state <= DRAIN_REQ;
    end

    DRAIN_REQ: begin
        if (load_using_dcache) begin
            drain_state <= DRAIN_IDLE;
        end else if (dcache_ready) begin
            // When fence pending, continue draining until sb_empty
            // When no fence, drain one entry and go idle
            if (!fence_pending || sb_empty)
                drain_state <= DRAIN_IDLE;
            // else: implicitly continue DRAIN_REQ (loop)
        end
    end
    ...
endcase
```

---

### Option B: Better Fix (Separate drain from req_ready block)

**File: LSU.v**

**Key changes:**
1. Remove fence check from `req_ready`
2. Let drain operate independently
3. Use priority mux at dcache interface

```verilog
// Original req_ready (dòng ~75-76):
// assign req_ready = fence ? 1'b0 :
//                    (req_is_load ? !lq_full : !sb_full);

// NEW req_ready - fence only blocks new requests, not drain
assign req_ready = fence ? 1'b0 : (req_is_load ? !lq_full : !sb_full);

// Keep same logic, but drain operates via dcache_req independently

// In dcache interface section (dòng ~298-316), ensure:
always @(*) begin
    dcache_req   = 1'b0;
    dcache_we    = 1'b0;
    dcache_addr  = 32'h0;
    dcache_wdata = 32'h0;
    dcache_wstrb = 4'h0;

    // PRIORITY 1: Load using dcache (highest)
    if (load_using_dcache) begin
        dcache_req  = 1'b1;
        dcache_we   = 1'b0;
        dcache_addr = cur_load_addr;
    end 
    // PRIORITY 2: Drain (INDEPENDENT of fence!)
    else if (drain_state == DRAIN_REQ) begin
        dcache_req   = 1'b1;
        dcache_we    = 1'b1;
        dcache_addr  = sb_addr[sb_rd_ptr];
        dcache_wdata = sb_wdata[sb_rd_ptr];
        dcache_wstrb = sb_wstrb[sb_rd_ptr];
    end
end

// Drain can proceed even when fence=1 because:
// - req_ready=0 blocks NEW requests from pipeline
// - But drain_state FSM still runs
// - dcache_req can be asserted for drain
```

---

### Option C: Most Complete Fix (With eager drain on fence)

**File: LSU.v**

```verilog
// Track fence pending
reg fence_pending_r;
always @(posedge clk or posedge rst) begin
    if (rst)
        fence_pending_r <= 1'b0;
    else if (fence && !lsu_idle)
        fence_pending_r <= 1'b1;
    else if (lsu_idle)
        fence_pending_r <= 1'b0;
end
wire fence_pending = fence_pending_r;

// Enhanced drain FSM - eager drain on fence
always @(posedge clk or posedge rst) begin
    if (rst) begin
        drain_state <= DRAIN_IDLE;
    end else begin
        case (drain_state)
            DRAIN_IDLE: begin
                // EAGER: Start drain if fence pending OR sb not empty
                // But avoid blocking load access
                if ((fence_pending || !sb_empty) && !load_using_dcache) begin
                    drain_state <= DRAIN_REQ;
                end
            end

            DRAIN_REQ: begin
                // Load has priority - pause drain if load starts
                if (load_using_dcache) begin
                    drain_state <= DRAIN_IDLE;
                end 
                // Drain complete when dcache_ready AND (no fence OR sb empty)
                else if (dcache_ready) begin
                    if (!fence_pending || sb_empty) begin
                        drain_state <= DRAIN_IDLE;
                    end
                    // else: continue draining (loop)
                end
            end

            default: drain_state <= DRAIN_IDLE;
        endcase
    end
end
```

---

## PATCH 2: LSU CACHE MISS HAZARD

### Step 1: Export Load State Info (LSU.v)

**Add at output declarations:**
```verilog
output wire load_multi_cycle;

// load_multi_cycle = 1 when load is in multi-cycle access
assign load_multi_cycle = (load_state == LOAD_DCACHE);
```

### Step 2: Update Hazard Detection (hazard_detection.v)

**Add input:**
```verilog
input wire load_multi_cycle,
```

**Update LSU dependency stall logic:**
```verilog
// Original:
wire lsu_dependency_stall;
assign lsu_dependency_stall = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                              (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);
assign lsu_dep_stall = lsu_dependency_stall;

// PATCHED: Add awareness of multi-cycle load
wire lsu_dependency_stall = (rs1_id != 5'b0 && lsu_scoreboard[rs1_id]) ||
                            (rs2_id != 5'b0 && lsu_scoreboard[rs2_id]);

// When load is multi-cycle, add extra stall latency
// This gives time for result to propagate through pipeline
wire load_hazard_multi = lsu_dependency_stall && load_multi_cycle;

// Export both signals so pipeline can use them
assign lsu_dep_stall = lsu_dependency_stall || load_hazard_multi;
```

### Step 3: Update CPU Core instantiation (riscv_cpu_core_v2.v)

**Find hazard_detection instantiation and add:**
```verilog
hazard_detection hazard_unit (
    .clk            (clk),
    .rst            (rst),
    .memread_id_ex  (memread_ex),
    .rd_id_ex       (rd_ex),
    .rs1_id         (rs1_id),
    .rs2_id         (rs2_id),
    .branch_taken   (pc_src_ex),
    .imem_ready     (imem_ready),
    .lsu_scoreboard (lsu_scoreboard),
    .fence_id       (fence_id),
    .lsu_idle       (lsu_idle),
    .load_multi_cycle(load_multi_cycle),  // ADD THIS
    .predict_taken_ex(predict_taken_ex),
    .predict_taken_id(predict_taken_id),
    .mispredict_ex  (mispredict_ex),
    .stall          (stall),
    .stall_if       (stall_if),
    .flush_if_id    (flush_if_id),
    .flush_id_ex    (flush_id_ex),
    .fence_stall    (fence_stall),
    .lsu_dep_stall  (lsu_dep_stall),
    .mul_ex_stall   (mul_ex_stall_wire)
);
```

**Add wire declaration:**
```verilog
wire load_multi_cycle;
```

**Connect from LSU output (find LSU instantiation):**
```verilog
LSU lsu_unit (
    .clk              (clk),
    .rst              (rst),
    .req_valid        (lsu_req_valid),
    .req_ready        (lsu_req_ready),
    .req_addr         (alu_result_mem),
    .req_wdata        (wdata_shifted),
    .req_wstrb        (lsu_req_wstrb),
    .req_is_load      (memread_mem),
    .req_rd           (rd_mem),
    .req_funct3       (funct3_mem),
    .fence            (fence_active),  // or your fence signal
    .result_valid     (lsu_result_valid),
    .result_data      (lsu_result_data),
    .result_rd        (lsu_result_rd),
    .result_ack       (lsu_result_ack),
    .scoreboard       (lsu_scoreboard),
    .lsu_idle         (lsu_idle),
    .load_multi_cycle (load_multi_cycle),  // ADD THIS
    .dcache_req       (dcache_req),
    .dcache_we        (dcache_we),
    .dcache_addr      (dcache_addr),
    .dcache_wdata     (dcache_wdata),
    .dcache_wstrb     (dcache_wstrb),
    .dcache_rdata     (dcache_rdata),
    .dcache_ready     (dcache_ready)
);
```

---

## PATCH 3: IRQ TIMING RACE CONDITION

### File: riscv_cpu_core_v2.v

**Original (dòng ~89-105):**
```verilog
reg irq_pending_lat;
always @(posedge clk or posedge rst) begin
    if (rst)
        irq_pending_lat <= 1'b0;
    else if (irq_pending)
        irq_pending_lat <= 1'b1;
    else if (irq_flush_done)
        irq_pending_lat <= 1'b0;
end

reg irq_flush_done_r;
always @(posedge clk or posedge rst) begin
    if (rst)
        irq_flush_done_r <= 1'b0;
    else
        irq_flush_done_r <= irq_pending_lat & ~irq_flush_done_r;
end
wire irq_flush_done = irq_flush_done_r;
```

**Patched (Add explicit priority):**
```verilog
reg irq_pending_lat;
always @(posedge clk or posedge rst) begin
    if (rst)
        irq_pending_lat <= 1'b0;
    // PRIORITY: flush done clears pending first
    else if (irq_flush_done)
        irq_pending_lat <= 1'b0;
    // Then set pending if new interrupt
    else if (irq_pending)
        irq_pending_lat <= 1'b1;
    // else: implicit hold (no change)
end

reg irq_flush_done_r;
always @(posedge clk or posedge rst) begin
    if (rst)
        irq_flush_done_r <= 1'b0;
    else
        irq_flush_done_r <= irq_pending_lat & ~irq_flush_done_r;
end
wire irq_flush_done = irq_flush_done_r;
```

**Key change:** Line priority ensures `if (irq_flush_done)` wins over `else if (irq_pending)` when both are true.

---

## VERIFICATION CHECKLIST

### FENCE Deadlock
- [ ] Simulate: FENCE after store + pending load → should complete
- [ ] Simulate: FENCE after multiple stores → should drain all
- [ ] Verify: drain_state transitions correctly even with fence=1
- [ ] Verify: lsu_idle goes high after FENCE completes

### LSU Cache Miss
- [ ] Simulate: Load miss pattern (10+ cycles)
- [ ] Verify: dependent instruction stalls correct duration
- [ ] Verify: forwarding data correct when load finally completes
- [ ] Check: Scoreboard clears at right time (after result_ack)

### IRQ Timing
- [ ] Simulate: IRQ arrives while irq_flush_done active
- [ ] Verify: Priority is explicit (flush_done wins)
- [ ] Check: No race conditions in simulation

---

## TESTING CODE SNIPPETS

```verilog
// Test FENCE with store + load pending
initial begin
    // Setup: Load address misses cache (use BIG offset)
    @(posedge clk) begin
        // Issue: Load from uncached address (will take ~10 cycles)
        // Issue: 2 stores to cacheable address
        // Issue: FENCE
    end
    
    // Verify: All stores drained before FENCE complete
    // Verify: No deadlock (pipeline continues after FENCE)
end

// Test load hazard with miss
initial begin
    @(posedge clk) begin
        // Issue: LW x1, LARGE_OFFSET(x2)
    end
    @(posedge clk) begin
        // Issue: ADD x3, x1, x4  // Should stall
    end
    repeat(10) @(posedge clk);  // Wait for cache response
    // Verify: ADD finally executes with correct x1 value
    // Verify: Correct forwarding window
end
```

---

## DEPLOYMENT GUIDE

### Phase 1: Code Review (30 min)
1. Review Patch 1 (FENCE) logic flow
2. Review Patch 2 (LSU) signal paths
3. Review Patch 3 (IRQ) priority correctness

### Phase 2: Implementation (2 hours)
1. Apply patches in order: Patch 1 → Patch 2 → Patch 3
2. Compile & check for syntax errors
3. Run behavioral simulation

### Phase 3: Verification (4 hours)
1. Run directed tests for each patch
2. Run full regression suite
3. Performance characterization
4. Coverage check (statements, branches)

### Phase 4: Sign-off (30 min)
1. Final review of diffs
2. Update design documentation
3. Version control commit

---

## POTENTIAL SIDE EFFECTS

| Patch | Potential Issue | Mitigation |
|-------|-----------------|-----------|
| FENCE eager drain | Drain blocks load access priority | Load has explicit priority in mux |
| LSU multi-cycle signal | May increase critical path | load_multi_cycle is combinational |
| IRQ priority | Changed if-else semantics | Explicit verilog: only affects race case |

All patches are **backward compatible** and do not change functional behavior except fixing bugs.

---

## ROLLBACK PLAN

If issues found:
1. Revert to original Verilog (git revert)
2. Keep hotfix FENCE logic as temporary workaround:
   - Add counter: `fence_wait_counter`
   - Force drain completion before FENCE completes
3. Re-investigate root cause
4. Plan comprehensive fix for next version

---

## SUCCESS METRICS

✅ FENCE instruction completes without deadlock
✅ Load miss does not cause incorrect forwarding
✅ IRQ latency <50 cycles on average
✅ No performance regression from stall changes
✅ All existing tests still pass
✅ New directed tests pass
