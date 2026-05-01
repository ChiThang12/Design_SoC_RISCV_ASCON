`timescale 1ns/1ps

// ============================================================================
// Testbench : tb_clk_reset_ctrl
// DUT       : clk_reset_ctrl
// Simulator : Icarus Verilog (iverilog)
//
// Compile (từ thư mục gốc project):
//   iverilog -o sim.vvp clk_reset_ctrl/tb/tb_clk_reset_ctrl.v
// Run:
//   vvp sim.vvp
// Wave:
//   gtkwave clk_reset_ctrl_tb.vcd
//
// ============================================================================
// PHÂN TÍCH 4 FAIL CỦA TB CŨ — ĐÃ SỬA:
//
// FAIL 1 — TC_RST_04: "glitch 1 cycle bị lọc"
//   TB CŨ SAI KỲ VỌNG: Kỳ vọng fabric_rst_n=1 sau glitch 1 cycle.
//   THỰC TẾ RTL: reset_sync dùng async negedge rst_async_n → khi rst_async_n
//   xuống 0 (dù chỉ 1ns), ff1 VÀ ff2 cùng về 0 NGAY LẬP TỨC qua async path.
//   2FF chỉ lọc glitch khi DEASSERT (release, synchronous path), không lọc
//   khi ASSERT (vì assert là asynchronous, không qua FF).
//   → SỬA: test lại đúng behavior: glitch 1 cycle VẪN kéo fabric_rst_n xuống 0,
//     nhưng recover nhanh hơn khi ext_rst_n trở về 1.
//
// FAIL 2 — TC_RST_07: "ndmreset=0 → cpu_rst_n chưa recover sau 4 cycle"
//   NGUYÊN NHÂN: ndmreset đi qua 2 tầng synchronizer:
//     Tầng 1: u_sync_ndm   (negedge ~ndmreset → ff instant, deassert qua 2FF)
//     Tầng 2: u_sync_cpu   (combined_cpu_rst_n → rst_sync_n qua 2FF)
//   Khi ndmreset=0 (deassert), ~ndmreset=1 → u_sync_ndm cần 2 cycle để
//   ndm_rst_n_sync=1, sau đó u_sync_cpu cần thêm 2 cycle → tổng tối thiểu 4
//   cycle, nhưng có thể cần 5 cycle do alignment với clk edge.
//   → SỬA: tăng wait_cycles(4) → wait_cycles(6) để chắc chắn.
//
// FAIL 3 — TC_SEQ_01: "ndmreset=1 + soft_rst → kỳ vọng fabric_rst_n=1"
//   TB CŨ SAI KỲ VỌNG: Kỳ vọng fabric_rst_n=1 khi soft_rst_pulse đang active.
//   THỰC TẾ RTL:
//     combined_rst_n = por_n_stretched & ext_rst_n & soft_rst_n_w
//     fabric_rst_n ← reset_sync(combined_rst_n)
//   Khi soft_rst_pulse active → soft_rst_n_w=0 → combined_rst_n=0
//   → fabric_rst_n=0.
//   Soft reset ảnh hưởng FABRIC vì nó nằm trong combined_rst_n chung.
//   Chỉ ndmreset mới không ảnh hưởng fabric (ndm_rst_n_sync chỉ AND vào
//   combined_CPU_rst_n).
//   → SỬA: kỳ vọng fabric_rst_n=0 khi soft_rst đang active (đúng RTL).
//     Thêm test case riêng chứng minh ndmreset-only không ảnh hưởng fabric.
//
// (FAIL 4 trùng với FAIL 3 — cùng TC_SEQ_01)
// ============================================================================

`timescale 1ns/1ps
`include "clk_reset_ctrl/clk_reset_ctrl.v"

module tb_clk_reset_ctrl;

    // -----------------------------------------------------------------------
    // Parameters — nhỏ để sim chạy nhanh, đủ để test đúng behavior
    // -----------------------------------------------------------------------
    localparam POR_CYCLES       = 16;   // thực tế = 1000 (10µs@100MHz)
    localparam SOFT_RST_STRETCH = 8;
    localparam CLK_PERIOD       = 10;   // 10ns → 100 MHz

    // -----------------------------------------------------------------------
    // Tín hiệu DUT
    // -----------------------------------------------------------------------
    reg  clk_in;
    reg  por_n;
    reg  ext_rst_n;
    reg  soft_rst_pulse;
    reg  ndmreset;
    reg  boot_done;
    reg  test_en;
    reg  core_clk_en;
    reg  periph_clk_en;
    reg  cpu_wfi;
    reg  ascon_busy;
    reg  core_bus_active;
    reg  core_wake_event;
    reg  periph_bus_active;
    reg  periph_busy;
    reg  periph_wake_event;
    reg  periph_gate_allow;
    reg  periph_wake_req;   // AON async wake request [MỚI]

    wire clk_core;
    wire clk_periph;
    wire clk_aon;           // always-on clock [MỚI]
    wire fabric_rst_n;
    wire cpu_rst_n;
    wire periph_rst_n;
    wire aon_rst_n;         // AON domain reset [MỚI]
    wire wake_ack;          // periph clock stable [MỚI]

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    clk_reset_ctrl #(
        .POR_CYCLES      (POR_CYCLES),
        .SOFT_RST_STRETCH(SOFT_RST_STRETCH)
    ) dut (
        .clk_in           (clk_in),
        .por_n            (por_n),
        .ext_rst_n        (ext_rst_n),
        .soft_rst_pulse   (soft_rst_pulse),
        .boot_done        (boot_done),
        .ndmreset         (ndmreset),
        .test_en          (test_en),
        .core_clk_en      (core_clk_en),
        .periph_clk_en    (periph_clk_en),
        .cpu_wfi          (cpu_wfi),
        .ascon_busy       (ascon_busy),
        .core_bus_active  (core_bus_active),
        .core_wake_event  (core_wake_event),
        .periph_bus_active(periph_bus_active),
        .periph_busy      (periph_busy),
        .periph_wake_event(periph_wake_event),
        .periph_gate_allow(periph_gate_allow),
        .periph_wake_req  (periph_wake_req),
        .clk_core         (clk_core),
        .clk_periph       (clk_periph),
        .clk_aon          (clk_aon),
        .fabric_rst_n     (fabric_rst_n),
        .cpu_rst_n        (cpu_rst_n),
        .periph_rst_n     (periph_rst_n),
        .aon_rst_n        (aon_rst_n),
        .wake_ack         (wake_ack)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial clk_in = 1'b0;
    always #(CLK_PERIOD/2) clk_in = ~clk_in;

    // -----------------------------------------------------------------------
    // Bộ đếm PASS / FAIL
    // -----------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

    // -----------------------------------------------------------------------
    // Biến tạm (khai báo ở module level — tương thích iverilog cũ)
    // -----------------------------------------------------------------------
    integer  transition_count;
    integer  c;
    reg      prev_val;
    reg      s0, s1;

    // -----------------------------------------------------------------------
    // Task: chờ N cạnh lên clock
    // -----------------------------------------------------------------------
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk_in);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: kiểm tra 1 tín hiệu 1-bit, in [PASS] / [FAIL]
    // -----------------------------------------------------------------------
    task check1;
        input [255:0] name;
        input         actual;
        input         expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0t  %0s = %b", $time, name, actual);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %0t  %0s : got %b, expect %b",
                         $time, name, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: đưa hệ thống về trạng thái "bình thường" (sau POR đầy đủ)
    //   Sau khi gọi task này: fabric/cpu/periph_rst_n = 1
    // -----------------------------------------------------------------------
    task full_release;
        begin
            // Assert tất cả reset, tắt ndmreset
            por_n          = 1'b0;
            ext_rst_n      = 1'b0;
            soft_rst_pulse = 1'b0;
            ndmreset       = 1'b0;
            boot_done      = 1'b1;
            test_en        = 1'b0;
            core_clk_en    = 1'b1;
            periph_clk_en  = 1'b1;
            cpu_wfi        = 1'b0;
            ascon_busy     = 1'b0;
            core_bus_active = 1'b0;
            core_wake_event = 1'b0;
            periph_bus_active = 1'b0;
            periph_busy    = 1'b0;
            periph_wake_event = 1'b0;
            periph_gate_allow = 1'b1;
            periph_wake_req   = 1'b0;
            wait_cycles(4);

            // Release POR và ext_rst đồng bộ với cạnh lên
            @(posedge clk_in); #1;
            por_n     = 1'b1;
            ext_rst_n = 1'b1;

            // Chờ POR_CYCLES (stretcher đếm) + 2FF fabric sync + margin
            // Tổng tối đa: POR_CYCLES + 2 + 2 (2FF ndm) + 2 margin = POR_CYCLES + 6
            wait_cycles(POR_CYCLES + 6);
        end
    endtask

    // -----------------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("clk_reset_ctrl_tb.vcd");
        $dumpvars(0, tb_clk_reset_ctrl);
    end

    // -----------------------------------------------------------------------
    // Timeout watchdog
    // -----------------------------------------------------------------------
    initial begin
        #500_000;
        $display("[FAIL] *** TIMEOUT ***");
        $finish;
    end

    // =======================================================================
    // MAIN TEST SEQUENCE
    // =======================================================================
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        $display("");
        $display("========================================================");
        $display(" START  clk_reset_ctrl Testbench");
        $display(" POR_CYCLES=%0d  SOFT_RST_STRETCH=%0d  CLK=%0dns",
                 POR_CYCLES, SOFT_RST_STRETCH, CLK_PERIOD);
        $display("========================================================");

        // ===================================================================
        // TC_RST_01: fabric_rst_n = 0 trong suốt giai đoạn POR
        //
        // WHY test: por_stretcher phải giữ reset tối thiểu POR_CYCLES chu
        //   kỳ sau khi por_n lên 1. Đảm bảo VDD ổn định trước khi release.
        // EXPECT: fabric/cpu/periph_rst_n = 0 từ đầu đến khi chưa đếm xong.
        // ===================================================================
        $display("\n--- TC_RST_01: fabric_rst_n = 0 trong suot POR ---");
        por_n          = 1'b0;
        ext_rst_n      = 1'b0;
        soft_rst_pulse = 1'b0;
        ndmreset       = 1'b0;
        boot_done      = 1'b1;
        test_en        = 1'b0;
        core_clk_en    = 1'b1;
        periph_clk_en  = 1'b1;
        cpu_wfi        = 1'b0;
        ascon_busy     = 1'b0;
        core_bus_active = 1'b0;
        core_wake_event = 1'b0;
        periph_bus_active = 1'b0;
        periph_busy    = 1'b0;
        periph_wake_event = 1'b0;
        periph_gate_allow = 1'b1;
        periph_wake_req   = 1'b0;

        wait_cycles(2);
        check1("TC_RST_01a fabric_rst_n [POR low]", fabric_rst_n, 1'b0);
        check1("TC_RST_01b cpu_rst_n    [POR low]", cpu_rst_n,    1'b0);
        check1("TC_RST_01c periph_rst_n [POR low]", periph_rst_n, 1'b0);

        // Release POR — stretcher bắt đầu đếm
        @(posedge clk_in); #1;
        por_n     = 1'b1;
        ext_rst_n = 1'b1;

        // Kiểm tra giữa quá trình đếm (cycle POR_CYCLES/2)
        wait_cycles(POR_CYCLES / 2);
        check1("TC_RST_01d fabric_rst_n [mid-stretch]", fabric_rst_n, 1'b0);

        // ===================================================================
        // TC_RST_02: fabric_rst_n = 1 sau POR_CYCLES + 2FF sync
        //
        // WHY test: sau khi stretcher đếm xong, reset_sync thêm 2 cycle.
        //   Kiểm tra đầu ra không release sớm (tiết kiệm margin → nguy hiểm).
        // EXPECT: fabric/cpu/periph_rst_n = 1 sau POR_CYCLES + 2 + margin.
        // ===================================================================
        $display("\n--- TC_RST_02: fabric_rst_n = 1 sau POR_CYCLES + 2FF ---");
        // Chờ phần còn lại + 2FF + margin
        wait_cycles(POR_CYCLES / 2 + 6);
        check1("TC_RST_02a fabric_rst_n [post-POR]", fabric_rst_n, 1'b1);
        check1("TC_RST_02b cpu_rst_n    [post-POR]", cpu_rst_n,    1'b1);
        check1("TC_RST_02c periph_rst_n [post-POR]", periph_rst_n, 1'b1);

        // ===================================================================
        // TC_RST_03: ext_rst_n assert → fabric_rst_n xuống sau ≤ 3 cycle
        //
        // WHY test: reset_sync cần tối đa 2 cạnh clk để propagate assert.
        //   (Khi assert: path là async negedge → ff1=0, ff2=0 NGAY LẬP TỨC
        //    không cần đợi 2 cycle — đây là ưu điểm của async assert).
        // EXPECT: fabric_rst_n = 0 sau ≤ 3 cycle.
        // ===================================================================
        $display("\n--- TC_RST_03: ext_rst_n assert → 2FF sync ---");
        wait_cycles(2);
        @(posedge clk_in); #1;
        ext_rst_n = 1'b0;   // assert bất đồng bộ

        // Assert là async → fabric_rst_n xuống gần như ngay lập tức
        wait_cycles(2);
        check1("TC_RST_03a fabric_rst_n [ext_rst asserted]", fabric_rst_n, 1'b0);
        check1("TC_RST_03b cpu_rst_n    [ext_rst asserted]", cpu_rst_n,    1'b0);
        check1("TC_RST_03c periph_rst_n [ext_rst asserted]", periph_rst_n, 1'b0);

        // Release ext_rst → deassert đi qua 2FF (sync) → cần 2 cycle
        @(posedge clk_in); #1;
        ext_rst_n = 1'b1;
        wait_cycles(4);   // 2FF + margin
        check1("TC_RST_03d fabric_rst_n [ext_rst released]", fabric_rst_n, 1'b1);

        // ===================================================================
        // TC_RST_04: ext_rst_n glitch 1 cycle → fabric_rst_n XUỐNG (async assert)
        //
        // WHY test — BEHAVIOR THỰC TẾ CỦA RTL:
        //   reset_sync có 2 path:
        //   - ASSERT:   async (negedge rst_async_n → ff1=0, ff2=0 tức thì)
        //   - DEASSERT: sync  (qua 2 cạnh clk dương → deassert sau 2 cycle)
        //
        //   Điều này có nghĩa: ngay cả glitch 1 cycle vẫn kéo fabric_rst_n=0
        //   NGAY LẬP TỨC vì rst_async_n = 0 kích negedge → async reset FF.
        //   Đây là trade-off thiết kế: đánh đổi để đảm bảo reset không bao
        //   giờ bị miss (safety critical). Glitch filter nếu cần thì phải
        //   làm ở tầng ngoài (debouncer pad) trước khi vào reset_sync.
        //
        //   Sau khi ext_rst_n về 1: fabric_rst_n recover sau 2FF = 2 cycle.
        //
        // EXPECT: fabric_rst_n = 0 khi glitch, = 1 sau 2FF recover.
        // ===================================================================
        $display("\n--- TC_RST_04: ext_rst_n glitch 1 cycle → fabric_rst_n XUONG (async) ---");
        wait_cycles(2);
        check1("TC_RST_04a fabric_rst_n [before glitch]", fabric_rst_n, 1'b1);

        // Tạo glitch 1 cycle
        @(posedge clk_in); #1;
        ext_rst_n = 1'b0;       // async assert → fabric_rst_n xuống NGAY
        @(posedge clk_in); #1;  // giữ 1 cycle
        ext_rst_n = 1'b1;       // release → deassert đi qua 2FF (cần 2 cycle)

        // fabric_rst_n vẫn = 0 ngay sau khi ext_rst_n về 1
        // (vì deassert phải qua 2FF — đây là behavior mong đợi đúng)
        #1;
        check1("TC_RST_04b fabric_rst_n [during glitch - async assert]", fabric_rst_n, 1'b0);

        // Sau 2FF sync deassert: fabric_rst_n = 1
        wait_cycles(4);
        check1("TC_RST_04c fabric_rst_n [after glitch - 2FF recover]", fabric_rst_n, 1'b1);

        // ===================================================================
        // TC_RST_05: soft_rst_pulse → tất cả 3 reset active STRETCH cycle
        //
        // WHY test: soft_rst_sync latch pulse 1-cycle và stretch thành
        //   STRETCH_CYCLES để đảm bảo pipeline 5-stage bị flush đầy đủ.
        //   Cả fabric, cpu, periph đều bị ảnh hưởng vì soft_rst_n_w nằm
        //   trong combined_rst_n chung.
        // EXPECT: fabric/cpu/periph = 0 trong STRETCH, = 1 sau đó.
        // ===================================================================
        $display("\n--- TC_RST_05: soft_rst_pulse stretch %0d cycle ---", SOFT_RST_STRETCH);
        // Cần ổn định trước khi test soft_rst
        wait_cycles(2);

        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b0;  // pulse chỉ 1 cycle

        // soft_rst_sync latch ngay → combined_rst_n=0 → reset_sync propagate
        // Chờ 3 cycle để qua 2FF sync fabric
        wait_cycles(3);
        check1("TC_RST_05a fabric_rst_n [soft_rst mid]", fabric_rst_n, 1'b0);
        check1("TC_RST_05b cpu_rst_n    [soft_rst mid]", cpu_rst_n,    1'b0);
        check1("TC_RST_05c periph_rst_n [soft_rst mid]", periph_rst_n, 1'b0);

        // Chờ stretch hết + 2FF + margin
        wait_cycles(SOFT_RST_STRETCH + 5);
        check1("TC_RST_05d fabric_rst_n [after soft_rst]", fabric_rst_n, 1'b1);
        check1("TC_RST_05e cpu_rst_n    [after soft_rst]", cpu_rst_n,    1'b1);
        check1("TC_RST_05f periph_rst_n [after soft_rst]", periph_rst_n, 1'b1);

        // ===================================================================
        // TC_RST_06: ndmreset=1 → cpu/periph reset, FABRIC KHÔNG ĐỔI
        //
        // WHY test: đây là test quan trọng nhất của ndmreset theo RISC-V
        //   Debug Spec §3.3. JTAG DM cần AXI crossbar (fabric) hoạt động
        //   để SBA path không bị cắt trong khi CPU đang bị reset.
        //   ndm_rst_n_sync chỉ AND vào combined_CPU_rst_n, KHÔNG vào
        //   combined_rst_n → fabric không bị ảnh hưởng.
        // EXPECT: cpu_rst_n=0, periph_rst_n=0, fabric_rst_n=1 (bất biến).
        // ===================================================================
        $display("\n--- TC_RST_06: ndmreset=1 → cpu/periph=0, fabric KHONG DOI ---");
        wait_cycles(2);
        check1("TC_RST_06_pre fabric_rst_n [stable]", fabric_rst_n, 1'b1);

        @(posedge clk_in); #1;
        ndmreset = 1'b1;  // active-high, RISC-V debug spec

        // ndmreset đi qua u_sync_ndm (async assert → tức thì),
        // sau đó combined_cpu_rst_n=0 đi qua u_sync_cpu (async → tức thì)
        wait_cycles(3);
        check1("TC_RST_06a fabric_rst_n [ndmreset=1]", fabric_rst_n, 1'b1); // KHÔNG đổi!
        check1("TC_RST_06b cpu_rst_n    [ndmreset=1]", cpu_rst_n,    1'b0);
        check1("TC_RST_06c periph_rst_n [ndmreset=1]", periph_rst_n, 1'b0);

        // ===================================================================
        // TC_RST_07: ndmreset=0 → cpu_rst_n recover sau 2 tầng sync
        //
        // WHY test: khi debugger thả ndmreset, CPU phải được release đúng.
        //   Path deassert: ndmreset=0 → ~ndmreset=1 → u_sync_ndm cần 2 cycle
        //   (sync deassert) → ndm_rst_n_sync=1 → combined_cpu_rst_n=1 →
        //   u_sync_cpu cần 2 cycle nữa → cpu_rst_n=1.
        //   Tổng: 2 + 2 = 4 cycle tối thiểu. Chờ 6 cycle để có margin.
        // EXPECT: cpu_rst_n = 1, periph_rst_n = 1 sau 6 cycle.
        // ===================================================================
        $display("\n--- TC_RST_07: ndmreset=0 → cpu_rst_n recover ---");
        @(posedge clk_in); #1;
        ndmreset = 1'b0;

        // 2 tầng sync × 2FF mỗi tầng = 4 cycle tối thiểu → chờ 6
        wait_cycles(6);
        check1("TC_RST_07a fabric_rst_n [ndmreset=0]", fabric_rst_n, 1'b1);
        check1("TC_RST_07b cpu_rst_n    [ndmreset=0]", cpu_rst_n,    1'b1);
        check1("TC_RST_07c periph_rst_n [ndmreset=0]", periph_rst_n, 1'b1);

        // ===================================================================
        // TC_RST_08: POR + ext_rst_n đồng thời → tất cả reset active
        //
        // WHY test: power-up scenario — pad POR và GPIO ext reset cùng low.
        //   Hệ thống phải xử lý đúng, không bị stuck hay undefined state.
        // EXPECT: fabric/cpu/periph_rst_n = 0.
        // ===================================================================
        $display("\n--- TC_RST_08: POR + ext_rst_n cung luc ---");
        @(posedge clk_in); #1;
        por_n     = 1'b0;
        ext_rst_n = 1'b0;
        wait_cycles(2);
        check1("TC_RST_08a fabric_rst_n [por+ext]", fabric_rst_n, 1'b0);
        check1("TC_RST_08b cpu_rst_n    [por+ext]", cpu_rst_n,    1'b0);
        check1("TC_RST_08c periph_rst_n [por+ext]", periph_rst_n, 1'b0);

        // Khôi phục trạng thái bình thường
        full_release;

        // ===================================================================
        // TC_RST_09: Deassert reset glitch-free (đồng bộ clk)
        //
        // WHY test: khi ext_rst_n về 1, fabric_rst_n phải deassert đúng
        //   1 lần qua 2FF (không bouncing). Reset_sync đảm bảo deassert
        //   chỉ xảy ra tại cạnh lên clock → glitch-free.
        // EXPECT: fabric_rst_n chuyển 0→1 đúng 1 lần, không bounce lại.
        // ===================================================================
        $display("\n--- TC_RST_09: Deassert reset glitch-free ---");
        @(posedge clk_in); #1;
        ext_rst_n = 1'b0;
        wait_cycles(3);
        check1("TC_RST_09a fabric_rst_n [ext assert]", fabric_rst_n, 1'b0);

        // Release → deassert qua 2FF → 1 lần chuyển 0→1
        @(posedge clk_in); #1;
        ext_rst_n = 1'b1;

        // Đếm số lần transition trong 5 cycle tiếp theo
        transition_count = 0;
        prev_val = fabric_rst_n;
        for (c = 0; c < 5; c = c + 1) begin
            @(posedge clk_in); #1;
            if (fabric_rst_n !== prev_val) begin
                transition_count = transition_count + 1;
                prev_val = fabric_rst_n;
            end
        end
        // Đúng 1 lần chuyển 0→1, không có bounce
        if (transition_count == 1 && fabric_rst_n == 1'b1) begin
            $display("[PASS] %0t  TC_RST_09b glitch-free deassert (1 transition)", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0t  TC_RST_09b transitions=%0d final=%b (expect 1 transition → 1)",
                     $time, transition_count, fabric_rst_n);
            fail_cnt = fail_cnt + 1;
        end

        // ===================================================================
        // TC_CLK_01: core_clk_en=0 → clk_core dừng (gated LOW)
        //
        // WHY test: ICG gate tắt clock khi domain idle → tiết kiệm
        //   dynamic power. Clock phải stable LOW, không có glitch.
        // EXPECT: clk_core = 0 liên tục khi enable=0.
        // ===================================================================
        $display("\n--- TC_CLK_01: core_clk_en=0 → clk_core gated ---");
        full_release;
        wait_cycles(2);
        @(negedge clk_in); #1;   // tắt khi clk thấp: clean transition
        core_clk_en = 1'b0;
        #(CLK_PERIOD * 2);
        check1("TC_CLK_01a clk_core gated", clk_core, 1'b0);

        // ===================================================================
        // TC_CLK_02: periph_clk_en=0 → clk_periph dừng
        //
        // WHY test: domain PERIPH (UART, SPI, GPIO) sleep độc lập với CORE.
        // EXPECT: clk_periph = 0.
        // ===================================================================
        $display("\n--- TC_CLK_02: periph_clk_en=0 → clk_periph gated ---");
        @(negedge clk_in); #1;
        periph_clk_en = 1'b0;
        #(CLK_PERIOD * 2);
        check1("TC_CLK_02a clk_periph gated", clk_periph, 1'b0);

        // ===================================================================
        // TC_CLK_03: test_en=1 → bypass ICG, clock chạy dù enable=0
        //
        // WHY test: DFT scan mode yêu cầu tất cả clock phải chạy để
        //   capture state đúng. test_en bypass gate: clk_out=clk_in & (en|test_en)
        //   = clk_in & 1 = clk_in. core_clk_en=0 và periph_clk_en=0 nhưng
        //   clock vẫn chạy nhờ test_en=1.
        // EXPECT: clk_core = clk_periph = clk_in khi test_en=1.
        // ===================================================================
        $display("\n--- TC_CLK_03: test_en=1 → bypass ICG ---");
        // core_clk_en và periph_clk_en vẫn = 0 từ TC_CLK_01/02
        test_en = 1'b1;
        #(CLK_PERIOD/2);   // đo ở giữa chu kỳ
        check1("TC_CLK_03a clk_core  [test_en=1]", clk_core,   clk_in);
        check1("TC_CLK_03b clk_periph[test_en=1]", clk_periph, clk_in);

        @(negedge clk_in); #1;
        test_en = 1'b0;

        // ===================================================================
        // TC_CLK_04: Re-enable core_clk_en → clk_core chạy lại sạch
        //
        // WHY test: sau khi gate rồi re-enable, clock phải chạy lại không
        //   có glitch. ICG latch enable khi clk=0 → chuyển đổi sạch.
        // EXPECT: clk_core toggle (s0 ≠ s1 sau half period).
        // ===================================================================
        $display("\n--- TC_CLK_04: re-enable core_clk_en → clk_core chay lai ---");
        @(negedge clk_in); #1;
        core_clk_en   = 1'b1;
        periph_clk_en = 1'b1;
        #(CLK_PERIOD/4);
        s0 = clk_core;
        #(CLK_PERIOD/2);
        s1 = clk_core;
        if (s0 !== s1) begin
            $display("[PASS] %0t  TC_CLK_04a clk_core toggling after re-enable", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0t  TC_CLK_04a clk_core NOT toggling (s0=%b s1=%b)",
                     $time, s0, s1);
            fail_cnt = fail_cnt + 1;
        end

        // ===================================================================
        // TC_SEQ_01: ndmreset=1 ONLY → fabric_rst_n giữ nguyên = 1
        //
        // WHY test: kiểm tra ISOLATED effect của ndmreset (không có soft_rst).
        //   Chứng minh rõ ràng: chỉ ndmreset không ảnh hưởng fabric.
        // EXPECT: fabric_rst_n=1, cpu_rst_n=0, periph_rst_n=0.
        // ===================================================================
        $display("\n--- TC_SEQ_01: ndmreset=1 only → fabric_rst_n KHONG DOI = 1 ---");
        full_release;
        wait_cycles(2);

        @(posedge clk_in); #1;
        ndmreset = 1'b1;
        wait_cycles(4);
        check1("TC_SEQ_01a fabric_rst_n [ndm only]", fabric_rst_n, 1'b1); // fabric an toàn
        check1("TC_SEQ_01b cpu_rst_n    [ndm only]", cpu_rst_n,    1'b0);
        check1("TC_SEQ_01c periph_rst_n [ndm only]", periph_rst_n, 1'b0);

        @(posedge clk_in); #1;
        ndmreset = 1'b0;
        wait_cycles(6);
        check1("TC_SEQ_01d cpu_rst_n    [ndm release]", cpu_rst_n,    1'b1);
        check1("TC_SEQ_01e periph_rst_n [ndm release]", periph_rst_n, 1'b1);

        // ===================================================================
        // TC_SEQ_02: soft_rst_pulse → fabric + cpu + periph cùng xuống
        //
        // WHY test — LƯU Ý QUAN TRỌNG VỀ KIẾN TRÚC:
        //   combined_rst_n = por_n_stretched & ext_rst_n & soft_rst_n_w
        //   fabric_rst_n ← reset_sync(combined_rst_n)
        //   → Soft reset ảnh hưởng CẢ FABRIC vì soft_rst_n_w trong combined.
        //   Đây là behavior đúng của RTL. Nếu muốn soft reset không ảnh
        //   hưởng fabric, phải tách soft_rst_n_w ra khỏi combined_rst_n
        //   (thay đổi RTL).
        //   Khác với ndmreset: ndm_rst_n_sync chỉ trong combined_CPU_rst_n.
        // EXPECT: cả 3 reset đều = 0 khi soft_rst active.
        // ===================================================================
        $display("\n--- TC_SEQ_02: soft_rst_pulse → ca 3 reset xuong (fabric bi anh huong) ---");
        full_release;
        wait_cycles(2);

        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b0;

        wait_cycles(3);
        // Cả 3 đều = 0 — đây là behavior ĐÚNG của RTL
        check1("TC_SEQ_02a fabric_rst_n [soft_rst]", fabric_rst_n, 1'b0);
        check1("TC_SEQ_02b cpu_rst_n    [soft_rst]", cpu_rst_n,    1'b0);
        check1("TC_SEQ_02c periph_rst_n [soft_rst]", periph_rst_n, 1'b0);

        wait_cycles(SOFT_RST_STRETCH + 5);
        check1("TC_SEQ_02d fabric_rst_n [after soft]", fabric_rst_n, 1'b1);
        check1("TC_SEQ_02e cpu_rst_n    [after soft]", cpu_rst_n,    1'b1);
        check1("TC_SEQ_02f periph_rst_n [after soft]", periph_rst_n, 1'b1);

        // ===================================================================
        // TC_SEQ_03: ndmreset=1 trong khi soft_rst đang active
        //            → cả 3 reset = 0 (ndm cộng với soft)
        //
        // WHY test: corner case debugger attach trong khi firmware crash.
        //   fabric_rst_n = 0 vì soft_rst_n_w=0 (qua combined_rst_n).
        //   cpu_rst_n = 0 vì cả combined_rst_n=0 và ndm_rst_n_sync=0.
        //   Sau khi cả 2 thả: cần 6 cycle để recover hoàn toàn.
        // EXPECT: cả 3 = 0 trong khi cả 2 active.
        // ===================================================================
        $display("\n--- TC_SEQ_03: ndmreset=1 trong khi soft_rst active ---");
        full_release;
        wait_cycles(2);

        // Bật ndmreset trước
        @(posedge clk_in); #1;
        ndmreset = 1'b1;
        wait_cycles(3);

        // Trigger soft_rst_pulse trong khi ndmreset đang giữ
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b0;

        wait_cycles(3);
        // fabric=0 vì soft_rst, cpu=0 vì cả soft+ndm, periph=0 tương tự
        check1("TC_SEQ_03a fabric_rst_n [ndm+soft active]", fabric_rst_n, 1'b0);
        check1("TC_SEQ_03b cpu_rst_n    [ndm+soft active]", cpu_rst_n,    1'b0);
        check1("TC_SEQ_03c periph_rst_n [ndm+soft active]", periph_rst_n, 1'b0);

        // Thả cả 2
        @(posedge clk_in); #1;
        ndmreset = 1'b0;

        // Chờ soft_rst stretch hết + 2 tầng sync recover
        wait_cycles(SOFT_RST_STRETCH + 8);
        check1("TC_SEQ_03d fabric_rst_n [all released]", fabric_rst_n, 1'b1);
        check1("TC_SEQ_03e cpu_rst_n    [all released]", cpu_rst_n,    1'b1);
        check1("TC_SEQ_03f periph_rst_n [all released]", periph_rst_n, 1'b1);

        // ===================================================================
        // TC_SEQ_04: soft_rst_pulse thứ 2 trong khi stretch chưa hết
        //
        // WHY test: RTL soft_rst_sync bỏ qua pulse mới khi rst_active=1
        //   (điều kiện: soft_rst_pulse && !rst_active).
        //   Pulse thứ 2 phải bị ignore, reset kéo dài từ pulse đầu.
        // EXPECT: fabric_rst_n = 0 liên tục, = 1 sau stretch đầu kết thúc.
        // ===================================================================
        $display("\n--- TC_SEQ_04: soft_rst pulse thu 2 khi stretch chua het ---");
        full_release;
        wait_cycles(2);

        // Pulse 1
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b0;

        wait_cycles(3);
        check1("TC_SEQ_04a fabric_rst_n [1st pulse mid]", fabric_rst_n, 1'b0);

        // Pulse 2 khi stretch đang active (cycle ~4/8)
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b0;

        wait_cycles(2);
        check1("TC_SEQ_04b fabric_rst_n [2nd pulse, still stretching]", fabric_rst_n, 1'b0);

        // Sau stretch đầu + margin: release (pulse 2 bị ignore)
        wait_cycles(SOFT_RST_STRETCH + 5);
        check1("TC_SEQ_04c fabric_rst_n [after 1st stretch]", fabric_rst_n, 1'b1);

        // ===================================================================
        // TC_AON_01: clk_aon luôn chạy kể cả khi core_clk_en=0, periph_clk_en=0
        //
        // WHY test: AON domain phải alive kể cả khi cả CORE và PERIPH bị gate.
        //   Nếu clk_aon bị gate, wake detector sẽ không chạy và SoC không
        //   thể tỉnh dậy từ sleep mode. clk_aon = clk_in (không qua ICG).
        // EXPECT: clk_aon toggling (s0 ≠ s1) bất kể enable state.
        // ===================================================================
        $display("\n--- TC_AON_01: clk_aon LUON chay du core_clk_en=0, periph_clk_en=0 ---");
        full_release;
        @(negedge clk_in); #1;
        core_clk_en   = 1'b0;
        periph_clk_en = 1'b0;
        #(CLK_PERIOD * 3);
        check1("TC_AON_01a clk_core gated", clk_core,   1'b0);
        check1("TC_AON_01b clk_periph gated", clk_periph, 1'b0);
        // clk_aon vẫn phải toggling
        s0 = clk_aon;
        #(CLK_PERIOD/2);
        s1 = clk_aon;
        if (s0 !== s1) begin
            $display("[PASS] %0t  TC_AON_01c clk_aon toggling when core+periph gated", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0t  TC_AON_01c clk_aon NOT toggling (s0=%b s1=%b)",
                     $time, s0, s1);
            fail_cnt = fail_cnt + 1;
        end
        // Khôi phục
        @(negedge clk_in); #1;
        core_clk_en   = 1'b1;
        periph_clk_en = 1'b1;

        // ===================================================================
        // TC_AON_02: aon_rst_n KHÔNG bị ảnh hưởng bởi soft_rst
        //
        // WHY test: wake-up state (wake_pend SR-latch) phải tồn tại qua
        //   soft_rst. Nếu aon_rst_n xuống khi soft_rst → CPU không thể
        //   biết nguyên nhân wake-up sau khi reset xong.
        //   aon_combined_rst_n = por_n_stretched & ext_rst_n (không có soft_rst_n_w).
        // EXPECT: aon_rst_n=1 trong khi fabric_rst_n=0 (soft_rst active).
        // ===================================================================
        $display("\n--- TC_AON_02: aon_rst_n KHONG bi soft_rst ---");
        full_release;
        wait_cycles(2);

        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b1;
        @(posedge clk_in); #1;
        soft_rst_pulse = 1'b0;

        wait_cycles(3);
        // fabric_rst_n phải = 0 (soft_rst ảnh hưởng combined_rst_n)
        check1("TC_AON_02a fabric_rst_n [soft_rst]", fabric_rst_n, 1'b0);
        // aon_rst_n phải = 1 (soft_rst KHÔNG trong aon_combined_rst_n)
        check1("TC_AON_02b aon_rst_n [soft_rst - KHONG bi anh huong]", aon_rst_n, 1'b1);

        wait_cycles(SOFT_RST_STRETCH + 5);
        check1("TC_AON_02c fabric_rst_n [after soft_rst]", fabric_rst_n, 1'b1);
        check1("TC_AON_02d aon_rst_n   [after soft_rst]", aon_rst_n,    1'b1);

        // ===================================================================
        // TC_AON_03: periph_wake_req=1 → clk_periph bật, wake_ack assert
        //
        // WHY test: đây là cơ chế wake-up chính của AON domain. Khi
        //   peripheral clock bị gate (idle), một signal từ AON (UART RX
        //   start bit, GPIO edge, Timer match) kéo periph_wake_req=1.
        //   Sau 1 FF cycle: periph_clk_dyn_en_r=1 → clk_periph bật.
        //   wake_ack = periph_clk_dyn_en_r → assert cùng lúc.
        // EXPECT: sau khi periph_wake_req=1, clock bật và wake_ack=1.
        // ===================================================================
        $display("\n--- TC_AON_03: periph_wake_req=1 → clk_periph bat, wake_ack=1 ---");
        full_release;
        // Để periph clock tự tắt: tắt tất cả busy/wake signals
        wait_cycles(2);
        @(negedge clk_in); #1;
        periph_gate_allow  = 1'b1;
        periph_busy        = 1'b0;
        periph_wake_event  = 1'b0;
        periph_bus_active  = 1'b0;
        periph_wake_req    = 1'b0;
        // Chờ PERIPH_IDLE_HOLD_CYCLES + margin để clock tắt
        // (testbench dùng default params, không override PERIPH_IDLE_HOLD_CYCLES
        //  nên dùng giá trị default=64. Dùng một giá trị nhỏ hơn để test nhanh hơn)
        // Thay vào đó dùng periph_clk_en=0 để force gate ngay
        @(negedge clk_in); #1;
        periph_clk_en = 1'b0;
        #(CLK_PERIOD * 2);
        check1("TC_AON_03a clk_periph gated before wake", clk_periph, 1'b0);
        check1("TC_AON_03b wake_ack before wake", wake_ack, 1'b0);

        // Re-enable periph_clk_en (cần để periph_clk_req có thể assert)
        // Sau đó assert periph_wake_req
        @(negedge clk_in); #1;
        periph_clk_en = 1'b1;

        @(posedge clk_in); #1;
        periph_wake_req = 1'b1;  // async wake từ AON

        // Sau 1-2 cycle FF sampling: periph_clk_dyn_en_r=1 → clock bật
        wait_cycles(3);
        check1("TC_AON_03c wake_ack after periph_wake_req", wake_ack, 1'b1);
        // Kiểm tra clk_periph đang chạy
        s0 = clk_periph;
        #(CLK_PERIOD/2);
        s1 = clk_periph;
        if (s0 !== s1) begin
            $display("[PASS] %0t  TC_AON_03d clk_periph toggling after wake_req", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0t  TC_AON_03d clk_periph NOT toggling after wake_req (s0=%b s1=%b)",
                     $time, s0, s1);
            fail_cnt = fail_cnt + 1;
        end

        // Clear wake_req → clock có thể gate lại sau HOLD cycle
        @(posedge clk_in); #1;
        periph_wake_req = 1'b0;

        // ===================================================================
        // Kết quả tổng hợp
        // ===================================================================
        $display("");
        $display("========================================================");
        $display(" DONE  -- PASS: %0d  |  FAIL: %0d  |  TOTAL: %0d",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL TESTS PASSED -- san sang tich hop vao soc_top.v ***");
        else
            $display(" *** CO %0d TEST THAT BAI -- xem phan tich o dau file ***",
                     fail_cnt);
        $display("========================================================");
        $finish;
    end

endmodule
