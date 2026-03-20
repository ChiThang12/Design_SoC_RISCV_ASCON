// ============================================================================
// Module  : clk_reset_ctrl
// Project : RISC-V SoC
//
// Bộ điều khiển Clock và Reset trung tâm — thay thế dòng nguy hiểm:
//   wire fabric_rst_n = ext_rst_n;   // CŨ: metastability hazard!
//
// Hierarchy:
//   clk_reset_ctrl
//   ├── por_stretcher       — kéo dài POR ≥10µs sau khi VDD ổn định
//   ├── reset_sync u_sync_fabric  — đồng bộ reset vào domain CORE/FABRIC
//   ├── reset_sync u_sync_cpu     — đồng bộ reset vào domain CPU (cùng clk)
//   ├── reset_sync u_sync_periph  — đồng bộ reset vào domain PERIPH
//   ├── soft_rst_sync       — tái đồng bộ soft_rst_pulse, kéo dài 8 cycle
//   ├── clk_buf u_clk_core  — ICG gate cho domain CORE
//   └── clk_buf u_clk_periph— ICG gate cho domain PERIPH
//
// Reset logic (tất cả active-low):
//   combined_rst_n = por_n_stretched AND ext_rst_sync_n AND soft_rst_n
//   fabric_rst_n   = combined_rst_n  (2FF sync → CORE domain)
//   cpu_rst_n      = combined_rst_n  (2FF sync → CPU domain, cùng clk)
//   periph_rst_n   = combined_rst_n  (2FF sync → PERIPH domain)
//
// Kết nối trong soc_top.v:
//   // XÓA: wire fabric_rst_n = ext_rst_n;
//   // THÊM:
//   clk_reset_ctrl u_clkrst (
//       .clk_in          (clk),
//       .por_n           (por_n),
//       .ext_rst_n       (ext_rst_n),
//       .soft_rst_pulse  (soft_rst_pulse),
//       .test_en         (1'b0),
//       .core_clk_en     (1'b1),
//       .periph_clk_en   (1'b1),
//       .clk_core        (clk_core),    // dùng thay cho clk nếu muốn gate
//       .clk_periph      (clk_periph),
//       .fabric_rst_n    (fabric_rst_n),
//       .cpu_rst_n       (cpu_rst_n),
//       .periph_rst_n    (periph_rst_n)
//   );
//   // cpu_rst = ~cpu_rst_n  (CPU core dùng active-high rst)
// ============================================================================
`include "clk_reset_ctrl/rtl/reset_sync.v"
`include "clk_reset_ctrl/rtl/por_stretcher.v"
`include "clk_reset_ctrl/rtl/soft_rst_sync.v"
`include "clk_reset_ctrl/rtl/clk_buf.v"


module clk_reset_ctrl #(
    parameter POR_CYCLES     = 1000,  // 10µs @ 100MHz
    parameter SOFT_RST_STRETCH = 8    // 8 cycle pulse stretch
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
    output wire fabric_rst_n,   // reset cho toàn bộ fabric (crossbar, cache, ASCON)
    output wire cpu_rst_n,      // reset riêng cho CPU core
    output wire periph_rst_n    // reset cho domain PERIPH
);

    // =========================================================================
    // Stage 1: POR stretcher
    // Kéo dài POR pad ≥ POR_CYCLES chu kỳ để VDD ổn định
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
    // Stage 2: Kết hợp tất cả nguồn reset
    // Combined = POR AND ext_rst AND soft_rst
    // Tất cả active-low: AND hợp lệ (bất kỳ nguồn nào = 0 → reset)
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

    // WHY AND: active-low → nếu bất kỳ nguồn nào pull xuống 0 → reset assert
    wire combined_rst_n = por_n_stretched & ext_rst_n & soft_rst_n_w;

    // =========================================================================
    // Stage 3: 2FF synchronizer cho mỗi reset domain
    // Mỗi domain có reset_sync riêng để tránh cross-domain coupling
    // =========================================================================

    // Fabric reset (crossbar, cache, ASCON, CLINT, SOC CTRL)
    reset_sync u_sync_fabric (
        .clk        (clk_in),
        .rst_async_n(combined_rst_n),
        .rst_sync_n (fabric_rst_n)
    );

    // CPU reset (riêng biệt để có thể reset CPU mà không reset fabric)
    // WHY riêng: debug module (JTAG) cần reset CPU nhưng giữ crossbar chạy
    reset_sync u_sync_cpu (
        .clk        (clk_in),
        .rst_async_n(combined_rst_n),
        .rst_sync_n (cpu_rst_n)
    );

    // Peripheral reset (UART, SPI, GPIO, Timer, PLIC)
    reset_sync u_sync_periph (
        .clk        (clk_in),
        .rst_async_n(combined_rst_n),
        .rst_sync_n (periph_rst_n)
    );

    // =========================================================================
    // Stage 4: Clock gating (ICG) cho từng domain
    // =========================================================================

    // CORE domain: CPU + ICache + DCache + ASCON + Crossbar
    clk_buf u_clk_core (
        .clk_in  (clk_in),
        .enable  (core_clk_en),
        .test_en (test_en),
        .clk_out (clk_core)
    );

    // PERIPH domain: UART, SPI, GPIO, Timer/WDT, PLIC
    clk_buf u_clk_periph (
        .clk_in  (clk_in),
        .enable  (periph_clk_en),
        .test_en (test_en),
        .clk_out (clk_periph)
    );

endmodule