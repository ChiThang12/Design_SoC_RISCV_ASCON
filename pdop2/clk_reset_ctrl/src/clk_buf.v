// ============================================================================
// Module  : clk_buf
// Project : RISC-V SoC
//
// Clock buffer tích hợp ICG (Integrated Clock Gating).
// Khi enable=0: clock out bị gate → domain tắt, tiết kiệm điện.
// Khi enable=1: clock out = clk_in.
//
// WHY ICG vs simple AND gate:
//   AND gate thông thường tạo glitch nếu enable thay đổi trong khi clk=1.
//   ICG dùng latch để "latch" enable khi clk=0 → chuyển đổi sạch.
//
// SYNTHESIS NOTE:
//   Tool tổng hợp sẽ map module này thành cell ICG của foundry
//   (vd: TSMC CLKGATETST_X8, Sky130 sky130_fd_sc_hd__dlclkp_1).
//   `ifdef SIMULATION giữ behavioral model chạy được trong simulation.
//
// FPGA NOTE:
//   Trên FPGA không có ICG cell → dùng enable register thay thế.
//   Pragma KEEP_HIERARCHY ngăn Vivado/Quartus optimize module đi.
// ============================================================================

module clk_buf (
    input  wire clk_in,    // clock đầu vào từ PLL hoặc pad
    input  wire enable,    // 1=clock chạy, 0=gate
    input  wire test_en,   // scan test: bypass gate (DFT)
    output wire clk_out    // clock ra đến domain
);

`ifdef SYNTHESIS

    // Trong synthesis: tool sẽ infer ICG cell từ foundry library
    // (tương đương CLKGATETST_X8 của TSMC 28nm)
    // Latch enable khi clock thấp → không glitch
    // WHY (* dont_touch *): không để tool rename/optimize đi
    (* dont_touch = "true" *)
    wire en_latch;

    // Level-sensitive latch: transparent khi clk_in = 0
    // Đây là pattern chuẩn tool nhận ra và map vào ICG cell
    latch_en u_latch (
        .clk   (clk_in),
        .d     (enable | test_en),
        .q     (en_latch)
    );

    assign clk_out = clk_in & en_latch;

`else

    // Behavioral model cho simulation
    // WHY: không cần latch trong sim, AND gate đủ chính xác
    assign clk_out = clk_in & (enable | test_en);

`endif

endmodule

// ============================================================================
// Latch primitive (chỉ dùng trong synthesis path)
// Tool sẽ map thành ICG latch của foundry
// ============================================================================
`ifdef SYNTHESIS
module latch_en (
    input  wire clk,   // enable khi clk=0 (active-low transparent)
    input  wire d,
    output reg  q
);
    always @(*) begin
        if (!clk) q <= d;   // latch transparent khi clock thấp
    end
endmodule
`endif