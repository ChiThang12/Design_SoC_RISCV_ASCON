// ============================================================================
// tb_inst_mem_v2.v - Testbench cho inst_mem (fixed TB + fixed DUT)
// ============================================================================
`timescale 1ns/1ps
`define TESTBENCH_MODE

`include "cpu/memory_axi4full/inst_mem.v"

module tb_inst_mem_v2;

parameter CLK_PERIOD = 10;
parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 32;
parameter MEM_SIZE   = 4096;

// ============================================================================
// Signals
// ============================================================================
reg  clk, rst_n;
reg  [ADDR_WIDTH-1:0] burst_addr;
reg  [7:0]            burst_len;
reg                   burst_req;
wire [DATA_WIDTH-1:0] burst_data;
wire                  burst_valid;
wire                  burst_last;
reg                   burst_ready;
reg  [ADDR_WIDTH-1:0] PC;
wire [DATA_WIDTH-1:0] Instruction_Code;

integer beat_num;
integer error_count;

// ============================================================================
// Clock
// ============================================================================
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT
// ============================================================================
inst_mem #(
    .MEM_SIZE(MEM_SIZE), .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH), .MEM_INIT_FILE("")
) dut (
    .clk(clk), .rst_n(rst_n),
    .PC(PC), .Instruction_Code(Instruction_Code),
    .burst_addr(burst_addr), .burst_len(burst_len),
    .burst_req(burst_req),   .burst_data(burst_data),
    .burst_valid(burst_valid),.burst_last(burst_last),
    .burst_ready(burst_ready)
);

// ============================================================================
// Task: do_burst - gửi request và collect beats
// len_axi = số beat - 1 (AXI convention: len=3 → 4 beats)
// ============================================================================
task do_burst;
    input [ADDR_WIDTH-1:0] addr;
    input [7:0]  len_axi;
    input [31:0] exp0, exp1, exp2, exp3;
    integer timeout;
    reg [31:0] exp_arr [0:3];
    begin
        exp_arr[0] = exp0; exp_arr[1] = exp1;
        exp_arr[2] = exp2; exp_arr[3] = exp3;

        $display("\n  [REQ] addr=0x%08h  len=%0d (%0d beats)",
                 addr, len_axi, len_axi+1);

        burst_addr  = addr;
        burst_len   = len_axi;
        burst_ready = 1'b1;
        beat_num    = 0;

        // Pulse request 1 cycle
        @(negedge clk);
        burst_req = 1'b1;
        @(negedge clk);
        burst_req = 1'b0;

        // Thu thập beats
        timeout = 0;
        while (beat_num <= len_axi) begin
            @(posedge clk); #1;
            if (burst_valid && burst_ready) begin
                // Kiểm tra data
                if (burst_data !== exp_arr[beat_num]) begin
                    $display("  [FAIL] beat[%0d] data: expect=0x%08h  got=0x%08h",
                             beat_num, exp_arr[beat_num], burst_data);
                    error_count = error_count + 1;
                end else
                    $display("  [PASS] beat[%0d] data=0x%08h", beat_num, burst_data);

                // Kiểm tra rlast
                if (beat_num == len_axi) begin
                    if (!burst_last) begin
                        $display("  [FAIL] beat[%0d]: rlast phải=1 nhưng=0", beat_num);
                        error_count = error_count + 1;
                    end else
                        $display("  [PASS] beat[%0d] rlast=1 đúng", beat_num);
                end else begin
                    if (burst_last) begin
                        $display("  [FAIL] beat[%0d]: rlast=1 quá sớm!", beat_num);
                        error_count = error_count + 1;
                    end
                end

                beat_num = beat_num + 1;

                // Thoát nếu last
                if (burst_last) begin
                    beat_num = len_axi + 1; // force exit
                end
            end
            timeout = timeout + 1;
            if (timeout > 30) begin
                $display("  [FAIL] TIMEOUT tại beat[%0d]!", beat_num);
                error_count = error_count + 1;
                beat_num = len_axi + 1;
            end
        end

        repeat(2) @(posedge clk);
    end
endtask

// ============================================================================
// MAIN
// ============================================================================
initial begin
    $dumpfile("tb_inst_mem_v2.vcd");
    $dumpvars(0, tb_inst_mem_v2);

    rst_n = 0; burst_req = 0; burst_ready = 1;
    burst_addr = 0; burst_len = 0; PC = 0;
    error_count = 0; beat_num = 0;

    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // Nạp data test vào memory
    dut.memory[0]  = 32'h00500093; // ADDI x1,x0,5
    dut.memory[1]  = 32'h00300113; // ADDI x2,x0,3
    dut.memory[2]  = 32'h002081b3; // ADD  x3,x1,x2
    dut.memory[3]  = 32'h40208233; // SUB  x4,x1,x2
    dut.memory[4]  = 32'h0020f2b3; // AND  x5,x1,x2
    dut.memory[5]  = 32'h0020e333; // OR   x6,x1,x2
    dut.memory[6]  = 32'h0020c3b3; // XOR  x7,x1,x2
    dut.memory[7]  = 32'h00209413; // SLLI x8,x1,2
    dut.memory[8]  = 32'h00102023; // SW   x1,0(x0)
    dut.memory[9]  = 32'h00202223; // SW   x2,4(x0)
    dut.memory[10] = 32'h00302423; // SW   x3,8(x0)
    dut.memory[11] = 32'h00002503; // LW   x10,0(x0)
    dut.memory[12] = 32'h00402583; // LW   x11,4(x0)
    dut.memory[13] = 32'h00802603; // LW   x12,8(x0)
    dut.memory[14] = 32'h0000006f; // JAL  x0,0
    dut.memory[15] = 32'h00000013; // NOP

    $display("=================================================");
    $display("  inst_mem Burst Read Testbench v2");
    $display("=================================================");

    // =========================================================
    // TEST 1: Miss tại 0x00 → 4 beats
    // =========================================================
    $display("\nTEST 1: addr=0x00 len=3 (4 beats)");
    $display("  Expect: ADDI ADDI ADD SUB");
    do_burst(32'h00000000, 8'd3,
        32'h00500093, 32'h00300113,
        32'h002081b3, 32'h40208233);

    // =========================================================
    // TEST 2: Miss tại 0x10 → beat0 phải là AND (không phải SUB)
    // =========================================================
    $display("\nTEST 2: addr=0x10 len=3 (bug gốc: beat0 trả SUB thay vì AND)");
    $display("  Expect: AND OR XOR SLLI");
    do_burst(32'h00000010, 8'd3,
        32'h0020f2b3, 32'h0020e333,
        32'h0020c3b3, 32'h00209413);

    // =========================================================
    // TEST 3: Miss tại 0x20
    // =========================================================
    $display("\nTEST 3: addr=0x20 len=3");
    $display("  Expect: SW SW SW LW");
    do_burst(32'h00000020, 8'd3,
        32'h00102023, 32'h00202223,
        32'h00302423, 32'h00002503);

    // =========================================================
    // TEST 4: Single beat len=0
    // =========================================================
    $display("\nTEST 4: addr=0x08 len=0 (single beat)");
    $display("  Expect: ADD, rlast=1 ngay");
    do_burst(32'h00000008, 8'd0,
        32'h002081b3, 32'h0, 32'h0, 32'h0);

    // =========================================================
    // TEST 5: burst_ready=0 giữa chừng (back-pressure)
    // =========================================================
    $display("\nTEST 5: addr=0x00, stall ready ở beat[1] trong 3 cycles");
    burst_addr  = 32'h00000000;
    burst_len   = 8'd3;
    burst_ready = 1'b1;
    beat_num    = 0;
    @(negedge clk); burst_req = 1'b1;
    @(negedge clk); burst_req = 1'b0;
    begin : test5
        integer t;
        integer stall_cnt;
        stall_cnt = 0;
        for (t = 0; t < 25; t = t + 1) begin
            // Set burst_ready trên negedge để tránh race với posedge DUT
            @(negedge clk);
            if (beat_num == 1 && stall_cnt < 3) begin
                burst_ready = 1'b0;   // stall beat[1] trong 3 cycles
                stall_cnt   = stall_cnt + 1;
            end else
                burst_ready = 1'b1;

            @(posedge clk); #1;
            if (burst_valid && burst_ready) begin
                $display("  beat[%0d]: data=0x%08h  last=%b",
                         beat_num, burst_data, burst_last);
                beat_num = beat_num + 1;
                if (burst_last) t = 25;
            end else if (burst_valid && !burst_ready) begin
                $display("  beat[%0d]: STALL cycle %0d  data_held=0x%08h",
                         beat_num, stall_cnt, burst_data);
            end
        end
    end
    if (beat_num == 4)
        $display("  [PASS] Back-pressure OK, nhan du 4 beats");
    else begin
        $display("  [FAIL] Chi nhan %0d beats", beat_num);
        error_count = error_count + 1;
    end

    // =========================================================
    // Kết quả
    // =========================================================
    $display("\n=================================================");
    if (error_count == 0)
        $display("  KET QUA: ALL PASS (%0d errors)", error_count);
    else
        $display("  KET QUA: %0d FAIL", error_count);
    $display("=================================================\n");

    #100; $finish;
end

initial begin #50000; $display("[WATCHDOG] TIMEOUT"); $finish; end

endmodule