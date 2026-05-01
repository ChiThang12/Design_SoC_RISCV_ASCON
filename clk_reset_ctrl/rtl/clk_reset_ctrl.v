// ============================================================================
// Module  : clk_reset_ctrl
// Project : RISC-V SoC
//
// Bộ điều khiển Clock và Reset trung tâm — thay thế dòng nguy hiểm:
//   wire fabric_rst_n = ext_rst_n;   // CŨ: metastability hazard!
//
// [THÊM MỚI so với v1]
//   Input ndmreset từ jtag_debug_top (riscv_dm):
//     ndmreset = 1 → reset CPU + tất cả peripheral, NGOẠI TRỪ fabric (crossbar)
//                    và bản thân JTAG DM (để debugger vẫn connected).
//     WHY không reset fabric: JTAG DM dùng crossbar (M4 SBA) để đọc/ghi
//     DMEM/IMEM trong khi CPU đang bị reset. Nếu reset crossbar, path đó bị
//     cắt và debugger mất kết nối.
//     WHY không reset JTAG DM: DM là người phát ndmreset, nếu reset chính nó
//     sẽ tự giải phóng ndmreset và CPU chưa kịp reset đầy đủ.
//
//   Tín hiệu ndmreset đến từ tck domain (JTAG TAP) nhưng đã được đồng bộ
//   bên trong jtag_dtm (2-FF synchronizer tck→clk). Ở đây clk_reset_ctrl
//   vẫn qua thêm reset_sync để chắc chắn — defense in depth.
//
// [THÊM MỚI v3] AON mini-domain:
//   clk_aon = clk_in (không bao giờ gate) — cấp cho wake-up logic của
//   UART RX detector, GPIO edge detector, Timer compare, PLIC.
//   aon_rst_n chỉ bị POR + ext_rst, KHÔNG bị soft_rst hoặc ndmreset:
//     WHY: wake logic phải giữ state xuyên suốt soft_rst và JTAG session.
//   periph_wake_req (async từ AON) → ungate clk_periph ngay lập tức.
//   wake_ack = periph_clk_dyn_en_r → AON logic biết clock đã ổn, clear wake_pend.
//
// Hierarchy:
//   clk_reset_ctrl
//   ├── por_stretcher            — kéo dài POR ≥10µs sau khi VDD ổn định
//   ├── reset_sync u_sync_fabric — đồng bộ reset vào domain CORE/FABRIC
//   ├── reset_sync u_sync_cpu    — đồng bộ reset vào domain CPU
//   ├── reset_sync u_sync_periph — đồng bộ reset vào domain PERIPH
//   ├── reset_sync u_sync_ndm   — đồng bộ ndmreset trước khi combine
//   ├── reset_sync u_sync_aon   — đồng bộ AON reset (por+ext only) [MỚI]
//   ├── soft_rst_sync            — tái đồng bộ soft_rst_pulse, kéo dài 8 cycle
//   ├── clk_buf u_clk_core       — ICG gate cho domain CORE
//   └── clk_buf u_clk_periph     — ICG gate cho domain PERIPH
//   (clk_aon = clk_in trực tiếp, không qua ICG)
//
// Reset logic (tất cả active-low):
//   combined_rst_n       = por_n_stretched AND ext_rst_n AND soft_rst_n
//   combined_cpu_rst_n   = combined_rst_n AND ndm_rst_n AND boot_done
//   aon_combined_rst_n   = por_n_stretched AND ext_rst_n  (không soft, không ndm)
//   fabric_rst_n         = sync(combined_rst_n)     — KHÔNG bị ndmreset
//   cpu_rst_n            = sync(combined_cpu_rst_n)
//   periph_rst_n         = sync(combined_cpu_rst_n)
//   aon_rst_n            = sync(aon_combined_rst_n) — KHÔNG bị soft/ndm
//
// Kết nối trong soc_top.v:
//   clk_reset_ctrl u_clkrst (
//       .clk_in          (clk),
//       .por_n           (por_n),
//       .ext_rst_n       (ext_rst_n),
//       .soft_rst_pulse  (soft_rst_pulse),
//       .ndmreset        (jtag_ndmreset),
//       .boot_done       (boot_done),
//       .test_en         (1'b0),
//       .core_clk_en     (1'b1),
//       .periph_clk_en   (1'b1),
//       .periph_wake_req (periph_wake_req),   // ← MỚI: async từ AON
//       .clk_core        (clk_core),
//       .clk_periph      (clk_periph),
//       .clk_aon         (clk_aon),           // ← MỚI: always-on
//       .aon_rst_n       (aon_rst_n),         // ← MỚI: AON reset
//       .wake_ack        (wake_ack),           // ← MỚI: periph clock stable
//       .fabric_rst_n    (fabric_rst_n),
//       .cpu_rst_n       (cpu_rst_n),
//       .periph_rst_n    (periph_rst_n)
//   );
//   wire cpu_rst = ~cpu_rst_n;   // CPU core dùng active-high rst
// ============================================================================
`include "clk_reset_ctrl/rtl/reset_sync.v"
`include "clk_reset_ctrl/rtl/por_stretcher.v"
`include "clk_reset_ctrl/rtl/soft_rst_sync.v"
`include "clk_reset_ctrl/rtl/clk_buf.v"


// PROVIDES: clk_core, clk_periph (ICG-gated); clk_aon (always-on);
//           fabric_rst_n, cpu_rst_n, periph_rst_n, aon_rst_n (synced resets);
//           wake_ack (periph clock stable signal for AON clear)
// REQUIRES: clk_in (main osc), por_n, ext_rst_n, ndmreset, boot_done,
//           periph_wake_req (async from AON domain), gating policy inputs
module clk_reset_ctrl #(
    parameter POR_CYCLES       = 1000,  // 10µs @ 100MHz
    parameter SOFT_RST_STRETCH = 8,     // 8 cycle pulse stretch
    parameter CORE_IDLE_HOLD_CYCLES   = 32,
    parameter PERIPH_IDLE_HOLD_CYCLES = 64
) (
    // =========================================================================
    // Clock inputs
    // =========================================================================
    input  wire clk_in,         // clock chính từ pad (hoặc PLL output)

    // =========================================================================
    // Reset inputs
    // =========================================================================
    input  wire por_n,          // Power-On Reset từ pad (active-low, có thể bounce)
    input  wire ext_rst_n,      // External reset từ GPIO (active-low, không sync)
    input  wire soft_rst_pulse, // Soft reset 1-cycle pulse từ soc_ctrl_slave

    // =========================================================================
    // Boot done — CPU held in reset until boot_ctrl finishes loading IMEM
    //
    // WHY: IMEM is a blank SRAM loaded by boot_ctrl at startup. If CPU were
    // released before loading completes, it would fetch NOPs or garbage.
    // boot_done=0 keeps cpu_rst_n=0; after PROG_WORDS written, boot_done=1.
    // =========================================================================
    input  wire boot_done,      // from boot_ctrl (active-high, sticky)

    // =========================================================================
    // JTAG Non-Debug Module Reset  [THÊM MỚI]
    //
    // ndmreset = 1 (active-high, theo RISC-V debug spec §3.3):
    //   → Reset CPU core và tất cả peripheral
    //   → KHÔNG reset crossbar (fabric) — giữ đường SBA của DM
    //   → KHÔNG reset JTAG DM — DM vẫn phải điều khiển được reset
    //
    // WHY active-high khác với các reset input khác (active-low):
    //   RISC-V Debug Spec định nghĩa ndmreset là active-high để phân biệt
    //   rõ với các reset hệ thống thông thường. Chúng ta convert thành
    //   active-low (ndm_rst_n = ~ndmreset_sync) trước khi AND vào combined.
    //
    // WHY cần thêm reset_sync cho ndmreset:
    //   Dù jtag_dtm đã sync tck→clk, thêm 1 tầng FF nữa là "defense in depth"
    //   an toàn hơn khi clk_reset_ctrl là module boundary cuối cùng trước
    //   khi reset đến từng domain.
    // =========================================================================
    input  wire ndmreset,       // JTAG DM → reset CPU+periph (active-high, đã sync)

    // =========================================================================
    // DFT / Test
    // =========================================================================
    input  wire test_en,        // Scan test enable — bypass ICG khi scan

    // =========================================================================
    // Clock enable cho từng power domain
    // =========================================================================
    input  wire core_clk_en,    // static allow/mask cho CORE gating policy
    input  wire periph_clk_en,  // static allow/mask cho PERIPH gating policy

    // =========================================================================
    // Dynamic clock-gating policy inputs (đã tổng hợp ở soc_top)
    // =========================================================================
    input  wire cpu_wfi,
    input  wire ascon_busy,
    input  wire core_bus_active,
    input  wire core_wake_event,
    input  wire periph_bus_active,
    input  wire periph_busy,
    input  wire periph_wake_event,
    input  wire periph_gate_allow,

    // =========================================================================
    // AON wake request [MỚI]
    //
    // periph_wake_req = 1 (async từ AON domain):
    //   → override gate condition → periph_clk_dyn_en_r set ngay lập tức
    //   → sau FF sampling: periph clock bật, wake_ack assert
    //   WHY async OK: periph_clk_dyn_en_r là FF → giải quyết metastability
    //   trước khi tín hiệu đến ICG latch.
    // =========================================================================
    input  wire periph_wake_req,  // async wake từ AON (GPIO/UART RX/Timer)

    // =========================================================================
    // Clock outputs (gated + always-on)
    // =========================================================================
    output wire clk_core,         // clock đến CPU, Cache, ASCON, Crossbar (ICG)
    output wire clk_periph,       // clock đến UART, SPI, GPIO, Timer, PLIC (ICG)
    output wire clk_aon,          // always-on clock = clk_in, không bao giờ gate

    // =========================================================================
    // Reset outputs (active-low, đã đồng bộ)
    // =========================================================================
    output wire fabric_rst_n,     // reset cho toàn bộ fabric — KHÔNG bị ndmreset
    output wire cpu_rst_n,        // reset riêng cho CPU core — BỊ ndmreset
    output wire periph_rst_n,     // reset cho domain PERIPH — BỊ ndmreset
    output wire aon_rst_n,        // reset cho AON domain — chỉ POR+ext, KHÔNG soft/ndm
    output wire wake_ack          // periph clock đang chạy → AON có thể clear wake_pend
);

    // =========================================================================
    // Stage 1: POR stretcher
    // =========================================================================
    wire por_n_stretched;

    por_stretcher #(
        .POR_CYCLES (POR_CYCLES)
    ) u_por (
        .clk        (clk_in),
        .por_n_raw  (por_n),
        .por_n_out  (por_n_stretched)
    );

    // =========================================================================
    // Stage 2a: Soft reset
    // =========================================================================
    wire soft_rst_n_w;

    soft_rst_sync #(
        .STRETCH_CYCLES (SOFT_RST_STRETCH)
    ) u_soft (
        .clk            (clk_in),
        .por_rst_n      (por_n_stretched),
        .soft_rst_pulse (soft_rst_pulse),
        .soft_rst_n     (soft_rst_n_w)
    );

    // =========================================================================
    // Stage 2b: Kết hợp reset cho FABRIC (không có ndmreset)
    //
    // WHY fabric KHÔNG có ndmreset:
    //   Crossbar cần hoạt động liên tục để JTAG DM (M4) có thể truy cập
    //   DMEM/IMEM qua System Bus Access trong khi CPU đang bị ndmreset.
    //   Nếu fabric bị reset, M4 AXI path bị cắt → debugger mất khả năng
    //   load chương trình hoặc đọc memory sau khi reset CPU.
    // =========================================================================
    wire combined_rst_n = por_n_stretched & ext_rst_n & soft_rst_n_w;

    // =========================================================================
    // Stage 2c: Đồng bộ ndmreset vào clk domain (defense in depth)
    //
    // ndmreset là active-high → convert sang active-low trước khi dùng
    // Dùng reset_sync với rst_async_n = ~ndmreset:
    //   ndmreset=0 (bình thường) → rst_async_n=1 → rst_sync_n=1 → không reset
    //   ndmreset=1 (reset)       → rst_async_n=0 → rst_sync_n=0 → reset assert
    // =========================================================================
    wire ndm_rst_n_sync;    // đã đồng bộ, active-low

    reset_sync u_sync_ndm (
        .clk         (clk_in),
        .rst_async_n (~ndmreset),      // active-high → flip thành active-low
        .rst_sync_n  (ndm_rst_n_sync)
    );

    // combined_cpu_rst_n: thêm ndmreset + boot_done vào chain reset CPU/periph
    // WHY AND: active-low → bất kỳ nguồn nào pull xuống 0 → reset assert
    // boot_done=0 giữ CPU reset cho đến khi boot_ctrl nạp xong IMEM
    wire combined_cpu_rst_n = combined_rst_n & ndm_rst_n_sync & boot_done;

    // =========================================================================
    // Stage 2d: AON reset — chỉ POR + ext_rst, KHÔNG soft_rst, KHÔNG ndmreset
    //
    // WHY tách riêng: wake-up logic trong peripheral (UART RX detector, GPIO
    // edge detector, Timer compare) phải giữ trạng thái xuyên qua soft_rst
    // và JTAG ndmreset. Nếu AON reset bị kéo xuống khi soft_rst → wake_pend
    // bị xóa → CPU không thể tỉnh dậy khi reset xong.
    // ext_rst_n được include vì đây là hard reset vật lý (nút reset trên board).
    // =========================================================================
    wire aon_combined_rst_n = por_n_stretched & ext_rst_n;

    reset_sync u_sync_aon (
        .clk        (clk_in),
        .rst_async_n(aon_combined_rst_n),
        .rst_sync_n (aon_rst_n)
    );

    // clk_aon: không qua ICG — luôn = clk_in bất kể mọi gate condition
    assign clk_aon = clk_in;

    // =========================================================================
    // Stage 3: 2FF synchronizer cho mỗi reset domain
    // =========================================================================

    // Fabric reset: chỉ từ combined_rst_n — KHÔNG có ndmreset
    reset_sync u_sync_fabric (
        .clk        (clk_in),
        .rst_async_n(combined_rst_n),
        .rst_sync_n (fabric_rst_n)
    );

    // CPU reset: combined + ndmreset + boot_done
    // WHY riêng biệt: debug module cần reset CPU mà không reset crossbar.
    // Khi ndmreset=1, cpu_rst_n=0 nhưng fabric_rst_n vẫn=1.
    reset_sync u_sync_cpu (
        .clk        (clk_in),
        .rst_async_n(combined_cpu_rst_n),
        .rst_sync_n (cpu_rst_n)
    );

    // Peripheral reset: cũng bị ndmreset
    // WHY: UART, SPI, GPIO cần reset khi CPU reset để tránh stale state
    // (ví dụ UART đang TX giữa chừng, GPIO output bị giữ sai level).
    // PLIC cũng reset để xóa pending interrupts từ session debug trước.
    reset_sync u_sync_periph (
        .clk        (clk_in),
        .rst_async_n(combined_cpu_rst_n),
        .rst_sync_n (periph_rst_n)
    );

    // =========================================================================
    // Stage 4: Clock gating (ICG)
    // =========================================================================
    reg [31:0] core_idle_hold_r;
    reg [31:0] periph_idle_hold_r;
    reg        core_clk_dyn_en_r;
    reg        periph_clk_dyn_en_r;

    wire core_clk_req =
        core_clk_en &&
        (core_wake_event || ascon_busy || core_bus_active || !cpu_wfi);

    // periph_wake_req (async từ AON) nằm trong điều kiện OR → FF sampling tại
    // posedge clk_in giải quyết metastability trước khi kết quả đến ICG latch
    wire periph_clk_req =
        periph_clk_en &&
        (periph_wake_req || periph_wake_event || periph_bus_active ||
         periph_busy || !periph_gate_allow);

    always @(posedge clk_in or negedge combined_rst_n) begin
        if (!combined_rst_n) begin
            core_idle_hold_r    <= 32'd0;
            periph_idle_hold_r  <= 32'd0;
            core_clk_dyn_en_r   <= 1'b1;
            periph_clk_dyn_en_r <= 1'b1;
        end else begin
            if (!core_clk_en) begin
                core_idle_hold_r  <= 32'd0;
                core_clk_dyn_en_r <= 1'b0;
            end else if (core_clk_req) begin
                core_idle_hold_r  <= (CORE_IDLE_HOLD_CYCLES > 0) ? (CORE_IDLE_HOLD_CYCLES - 1) : 0;
                core_clk_dyn_en_r <= 1'b1;
            end else if (core_idle_hold_r != 32'd0) begin
                core_idle_hold_r  <= core_idle_hold_r - 32'd1;
                core_clk_dyn_en_r <= 1'b1;
            end else begin
                core_clk_dyn_en_r <= 1'b0;
            end

            if (!periph_clk_en) begin
                periph_idle_hold_r  <= 32'd0;
                periph_clk_dyn_en_r <= 1'b0;
            end else if (periph_clk_req) begin
                periph_idle_hold_r  <= (PERIPH_IDLE_HOLD_CYCLES > 0) ? (PERIPH_IDLE_HOLD_CYCLES - 1) : 0;
                periph_clk_dyn_en_r <= 1'b1;
            end else if (periph_idle_hold_r != 32'd0) begin
                periph_idle_hold_r  <= periph_idle_hold_r - 32'd1;
                periph_clk_dyn_en_r <= 1'b1;
            end else begin
                periph_clk_dyn_en_r <= 1'b0;
            end
        end
    end

    clk_buf u_clk_core (
        .clk_in  (clk_in),
        .enable  (core_clk_dyn_en_r),
        .test_en (test_en),
        .clk_out (clk_core)
    );

    clk_buf u_clk_periph (
        .clk_in  (clk_in),
        .enable  (periph_clk_dyn_en_r),
        .test_en (test_en),
        .clk_out (clk_periph)
    );

    // wake_ack: assert khi periph clock đang chạy ổn định
    // AON logic dùng wake_ack để clear wake_pend SR-latch sau khi biết
    // clk_periph đã bật và peripheral sẵn sàng xử lý interrupt.
    assign wake_ack = periph_clk_dyn_en_r;

endmodule
