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
// Hierarchy:
//   clk_reset_ctrl
//   ├── por_stretcher       — kéo dài POR ≥10µs sau khi VDD ổn định
//   ├── reset_sync u_sync_fabric  — đồng bộ reset vào domain CORE/FABRIC
//   ├── reset_sync u_sync_cpu     — đồng bộ reset vào domain CPU
//   ├── reset_sync u_sync_periph  — đồng bộ reset vào domain PERIPH
//   ├── reset_sync u_sync_ndm    — đồng bộ ndmreset trước khi combine
//   ├── soft_rst_sync       — tái đồng bộ soft_rst_pulse, kéo dài 8 cycle
//   ├── clk_buf u_clk_core  — ICG gate cho domain CORE
//   └── clk_buf u_clk_periph— ICG gate cho domain PERIPH
//
// Reset logic (tất cả active-low):
//   combined_rst_n       = por_n_stretched AND ext_rst_sync_n AND soft_rst_n
//   combined_cpu_rst_n   = combined_rst_n AND ndm_rst_n   ← CPU thêm ndmreset
//   fabric_rst_n         = combined_rst_n    (KHÔNG bị ảnh hưởng bởi ndmreset)
//   cpu_rst_n            = combined_cpu_rst_n
//   periph_rst_n         = combined_cpu_rst_n (peripheral cũng reset theo ndm)
//
// Kết nối trong soc_top.v:
//   clk_reset_ctrl u_clkrst (
//       .clk_in          (clk),
//       .por_n           (por_n),
//       .ext_rst_n       (ext_rst_n),
//       .soft_rst_pulse  (soft_rst_pulse),
//       .ndmreset        (jtag_ndmreset),   // ← MỚI, từ u_jtag.ndmreset
//       .test_en         (1'b0),
//       .core_clk_en     (1'b1),
//       .periph_clk_en   (1'b1),
//       .clk_core        (clk_core),
//       .clk_periph      (clk_periph),
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


module clk_reset_ctrl #(
    parameter POR_CYCLES       = 1000,  // 10µs @ 100MHz
    parameter SOFT_RST_STRETCH = 8      // 8 cycle pulse stretch
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
    input  wire core_clk_en,    // 1=CORE domain active, 0=gate clock
    input  wire periph_clk_en,  // 1=PERIPH domain active, 0=gate clock

    // =========================================================================
    // Clock outputs (gated)
    // =========================================================================
    output wire clk_core,       // clock đến CPU, Cache, ASCON, Crossbar
    output wire clk_periph,     // clock đến UART, SPI, GPIO, Timer, PLIC

    // =========================================================================
    // Reset outputs (active-low, đã đồng bộ)
    // =========================================================================
    output wire fabric_rst_n,   // reset cho toàn bộ fabric — KHÔNG bị ndmreset
    output wire cpu_rst_n,      // reset riêng cho CPU core — BỊ ndmreset
    output wire periph_rst_n    // reset cho domain PERIPH — BỊ ndmreset
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

    // combined_cpu_rst_n: thêm ndmreset vào chain reset của CPU và peripheral
    // WHY AND: active-low → bất kỳ nguồn nào pull xuống 0 → reset assert
    wire combined_cpu_rst_n = combined_rst_n & ndm_rst_n_sync;

    // =========================================================================
    // Stage 3: 2FF synchronizer cho mỗi reset domain
    // =========================================================================

    // Fabric reset: chỉ từ combined_rst_n — KHÔNG có ndmreset
    reset_sync u_sync_fabric (
        .clk        (clk_in),
        .rst_async_n(combined_rst_n),
        .rst_sync_n (fabric_rst_n)
    );

    // CPU reset: combined + ndmreset
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

    clk_buf u_clk_core (
        .clk_in  (clk_in),
        .enable  (core_clk_en),
        .test_en (test_en),
        .clk_out (clk_core)
    );

    clk_buf u_clk_periph (
        .clk_in  (clk_in),
        .enable  (periph_clk_en),
        .test_en (test_en),
        .clk_out (clk_periph)
    );

endmodule