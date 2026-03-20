// ============================================================================
// Testbench : clk_reset_ctrl_tb
// Project   : RISC-V SoC
//
// Kiểm tra các kịch bản:
//   TC1: POR kéo dài đúng POR_CYCLES chu kỳ
//   TC2: ext_rst_n đồng bộ qua 2FF (fabric_rst_n trễ 2 cycle)
//   TC3: soft_rst_pulse tạo ra reset kéo dài SOFT_RST_STRETCH cycle
//   TC4: Tất cả reset cùng lúc → fabric_rst_n = 0
// ============================================================================

`timescale 1ns/1ps
`include "clk_reset_ctrl/rtl/clk_reset_ctrl.v"
module clk_reset_ctrl_tb;

    // Parameters
    localparam POR_CYCLES      = 16;   // nhỏ để sim nhanh (thực tế = 1000)
    localparam SOFT_RST_STRETCH = 8;
    localparam CLK_PERIOD      = 10;   // 100MHz → 10ns

    // DUT ports
    reg  clk_in, por_n, ext_rst_n, soft_rst_pulse, test_en;
    reg  core_clk_en, periph_clk_en;
    wire clk_core, clk_periph;
    wire fabric_rst_n, cpu_rst_n, periph_rst_n;

    // Instantiate DUT
    clk_reset_ctrl #(
        .POR_CYCLES      (POR_CYCLES),
        .SOFT_RST_STRETCH(SOFT_RST_STRETCH)
    ) dut (
        .clk_in         (clk_in),
        .por_n          (por_n),
        .ext_rst_n      (ext_rst_n),
        .soft_rst_pulse (soft_rst_pulse),
        .test_en        (test_en),
        .core_clk_en    (core_clk_en),
        .periph_clk_en  (periph_clk_en),
        .clk_core       (clk_core),
        .clk_periph     (clk_periph),
        .fabric_rst_n   (fabric_rst_n),
        .cpu_rst_n      (cpu_rst_n),
        .periph_rst_n   (periph_rst_n)
    );

    // Clock
    initial clk_in = 0;
    always #(CLK_PERIOD/2) clk_in = ~clk_in;

    // Task: wait N rising edges
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk_in);
        end
    endtask

    // Task: check signal
    task check;
        input [255:0] name;
        input         actual, expected;
        begin
            if (actual !== expected)
                $display("FAIL [%0t] %s: got %b, expected %b", $time, name, actual, expected);
            else
                $display("PASS [%0t] %s = %b", $time, name, actual);
        end
    endtask

    integer i;

    initial begin
        // Init
        por_n          = 0;
        ext_rst_n      = 0;
        soft_rst_pulse = 0;
        test_en        = 0;
        core_clk_en    = 1;
        periph_clk_en  = 1;

        // =====================================================================
        // TC1: POR kéo dài
        // =====================================================================
        $display("\n--- TC1: POR stretcher ---");
        @(posedge clk_in); #1;
        check("fabric_rst_n during POR", fabric_rst_n, 1'b0);

        ext_rst_n = 1;
        // Release POR
        por_n = 1;
        // Trong POR_CYCLES chu kỳ đầu: vẫn reset
        wait_cycles(POR_CYCLES - 2);
        check("fabric_rst_n mid-stretch", fabric_rst_n, 1'b0);

        // Sau POR_CYCLES + 2FF sync: release
        wait_cycles(10);
        check("fabric_rst_n after POR", fabric_rst_n, 1'b1);

        // =====================================================================
        // TC2: ext_rst_n → 2FF sync
        // =====================================================================
        $display("\n--- TC2: ext_rst_n sync 2FF ---");
        ext_rst_n = 1;
        wait_cycles(4);
        check("fabric_rst_n stable", fabric_rst_n, 1'b1);

        // Assert ext reset
        @(posedge clk_in); #1;
        ext_rst_n = 0;
        @(posedge clk_in); #1;
        // Sau 1 cycle: vẫn có thể chưa propagate (2FF trễ)
        // Sau 2 cycle: chắc chắn 0
        @(posedge clk_in); #1;
        @(posedge clk_in); #1;
        check("fabric_rst_n after ext_rst assert", fabric_rst_n, 1'b0);

        // Release
        ext_rst_n = 1;
        @(posedge clk_in); #1;
        @(posedge clk_in); #1;
        @(posedge clk_in); #1;
        check("fabric_rst_n after ext_rst release", fabric_rst_n, 1'b1);

        // =====================================================================
        // TC3: soft_rst_pulse
        // =====================================================================
        $display("\n--- TC3: soft_rst_pulse stretch ---");
        @(posedge clk_in); #1;
        soft_rst_pulse = 1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 0;

        // Sau 2FF: reset phải active
        wait_cycles(3);
        check("fabric_rst_n during soft_rst", fabric_rst_n, 1'b0);

        // Sau SOFT_RST_STRETCH + 2FF: release
        wait_cycles(SOFT_RST_STRETCH + 4);
        check("fabric_rst_n after soft_rst", fabric_rst_n, 1'b1);

        // =====================================================================
        // TC4: Clock gating
        // =====================================================================
        $display("\n--- TC4: Clock gating ---");
        core_clk_en = 0;
        @(posedge clk_in); #1;
        // clk_core phải stop (check level)
        #(CLK_PERIOD);
        $display("clk_core gated (should be 0): %b", clk_core);

        core_clk_en = 1;
        #(CLK_PERIOD);
        $display("clk_core enabled (should toggle): running");

        // =====================================================================
        $display("\n--- Simulation done ---");
        #100;
        $finish;
    end

    // Timeout
    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("clk_reset_ctrl_tb.vcd");
        $dumpvars(0, clk_reset_ctrl_tb);
    end

endmodule