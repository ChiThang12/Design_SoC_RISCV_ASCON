`timescale 1ns/1ps
`include "cpu/riscv_cpu_core_v2.v"

module tb_hotspots_v2;

reg clk, rst;
initial clk = 1'b0;
always #5 clk = ~clk;

wire [31:0] imem_addr;
wire        imem_valid;
reg  [31:0] imem_rdata;
reg         imem_ready;

wire [31:0] dcache_addr;
wire [31:0] dcache_wdata;
wire [3:0]  dcache_wstrb;
wire        dcache_req;
wire        dcache_we;
reg  [31:0] dcache_rdata;
reg         dcache_ready;

reg external_irq, timer_irq, sw_irq;

riscv_cpu_core dut (
    .clk             (clk),
    .rst             (rst),
    .imem_addr       (imem_addr),
    .imem_valid      (imem_valid),
    .imem_rdata      (imem_rdata),
    .imem_ready      (imem_ready),
    .dcache_addr     (dcache_addr),
    .dcache_wdata    (dcache_wdata),
    .dcache_wstrb    (dcache_wstrb),
    .dcache_req      (dcache_req),
    .dcache_we       (dcache_we),
    .dcache_rdata    (dcache_rdata),
    .dcache_ready    (dcache_ready),
    .dcache_fence_type(),
    .external_irq    (external_irq),
    .timer_irq       (timer_irq),
    .sw_irq          (sw_irq),
    .debug_haltreq   (1'b0),
    .debug_resumereq (1'b0),
    .debug_halted    (),
    .debug_running   (),
    .cpu_wfi_o       ()
);

reg [31:0] imem [0:255];
reg [31:0] dmem [0:255];
reg [3:0]  dcache_miss_cycles;

always @(*) begin
    if (!imem_valid || rst) begin
        imem_rdata = 32'h0000_0013;
        imem_ready = 1'b0;
    end else begin
        imem_rdata = imem[imem_addr[9:2]];
        imem_ready = 1'b1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)
        dcache_miss_cycles <= 4'd0;
    else if (dcache_req && (dcache_addr == 32'h1000_0000) && !dcache_we && (dcache_miss_cycles != 4'd6))
        dcache_miss_cycles <= dcache_miss_cycles + 4'd1;
    else if (!dcache_req)
        dcache_miss_cycles <= 4'd0;
end

always @(*) begin
    if (!dcache_req || rst) begin
        dcache_rdata = 32'h0;
        dcache_ready = 1'b0;
    end else if ((dcache_addr == 32'h1000_0000) && !dcache_we && (dcache_miss_cycles != 4'd6)) begin
        dcache_rdata = 32'h0;
        dcache_ready = 1'b0;
    end else begin
        dcache_ready = 1'b1;
        if (dcache_we)
            dcache_rdata = 32'h0;
        else
            dcache_rdata = dmem[(dcache_addr - 32'h1000_0000) >> 2];
    end
end

always @(posedge clk) begin
    if (!rst && dcache_req && dcache_we && dcache_ready) begin
        if (dcache_wstrb[0]) dmem[(dcache_addr - 32'h1000_0000) >> 2][7:0]   <= dcache_wdata[7:0];
        if (dcache_wstrb[1]) dmem[(dcache_addr - 32'h1000_0000) >> 2][15:8]  <= dcache_wdata[15:8];
        if (dcache_wstrb[2]) dmem[(dcache_addr - 32'h1000_0000) >> 2][23:16] <= dcache_wdata[23:16];
        if (dcache_wstrb[3]) dmem[(dcache_addr - 32'h1000_0000) >> 2][31:24] <= dcache_wdata[31:24];
    end
end

function [31:0] enc_i;
    input [11:0] imm;
    input [4:0]  rs1;
    input [2:0]  f3;
    input [4:0]  rd;
    input [6:0]  op;
    enc_i = {imm, rs1, f3, rd, op};
endfunction

function [31:0] enc_s;
    input [11:0] imm;
    input [4:0]  rs2;
    input [4:0]  rs1;
    input [2:0]  f3;
    enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
endfunction

function [31:0] enc_u;
    input [19:0] imm;
    input [4:0]  rd;
    input [6:0]  op;
    enc_u = {imm, rd, op};
endfunction

localparam [6:0] OP_LUI   = 7'b0110111;
localparam [6:0] OP_LOAD  = 7'b0000011;
localparam [6:0] OP_IMMED = 7'b0010011;
localparam [2:0] F3_ADD   = 3'b000;
localparam [2:0] F3_LW    = 3'b010;
localparam [2:0] F3_SW    = 3'b010;

integer i;
integer addi6_wb_cycle;
integer load5_wb_cycle;
integer addi4_wb_cycle;
integer cycle_count;

task clear_memories;
    begin
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h0000_0013;
            dmem[i] = 32'h0;
        end
    end
endtask

task do_reset;
    begin
        rst = 1'b1;
        external_irq = 1'b0;
        timer_irq = 1'b0;
        sw_irq = 1'b0;
        addi6_wb_cycle = -1;
        load5_wb_cycle = -1;
        addi4_wb_cycle = -1;
        cycle_count = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
    end
endtask

always @(posedge clk) begin
    if (!rst) begin
        cycle_count <= cycle_count + 1;
        if (dut.regwrite_wb && (dut.rd_wb == 5'd6) && (addi6_wb_cycle < 0))
            addi6_wb_cycle <= cycle_count;
        if (dut.regwrite_wb && (dut.rd_wb == 5'd5) && (load5_wb_cycle < 0))
            load5_wb_cycle <= cycle_count;
        if (dut.regwrite_wb && (dut.rd_wb == 5'd4) && (addi4_wb_cycle < 0))
            addi4_wb_cycle <= cycle_count;
    end
end

initial begin
    $dumpfile("tb_hotspots_v2.vcd");
    $dumpvars(0, tb_hotspots_v2);

    clear_memories();

    // TC1: OP-IMM must not falsely stall on rs2 immediate bits matching pending load rd.
    dmem[0] = 32'h1234_5678;
    imem[0] = enc_u(20'h10000, 5'd1, OP_LUI);
    imem[1] = enc_i(12'd0, 5'd1, F3_LW, 5'd5, OP_LOAD);
    imem[2] = enc_i(12'd5, 5'd0, F3_ADD, 5'd6, OP_IMMED);
    imem[3] = enc_i(12'd9, 5'd0, F3_ADD, 5'd7, OP_IMMED);
    do_reset();
    repeat (24) @(posedge clk);

    if (dut.register_file.registers[6] !== 32'd5) begin
        $display("FAIL TC1: x6 = 0x%08h, expected 0x00000005", dut.register_file.registers[6]);
        $finish(1);
    end
    if (dut.register_file.registers[5] !== 32'h1234_5678) begin
        $display("FAIL TC1: x5 = 0x%08h, expected 0x12345678", dut.register_file.registers[5]);
        $finish(1);
    end
    if ((addi6_wb_cycle < 0) || (load5_wb_cycle < 0) || (addi6_wb_cycle >= load5_wb_cycle)) begin
        $display("FAIL TC1: addi x6 WB cycle=%0d, load x5 WB cycle=%0d", addi6_wb_cycle, load5_wb_cycle);
        $finish(1);
    end
    $display("PASS TC1: OP-IMM bypasses false rs2 hazard (x6 WB @ %0d, x5 WB @ %0d)", addi6_wb_cycle, load5_wb_cycle);

    // TC2: FENCE must not block forward progress after pending LSU traffic drains.
    clear_memories();
    dmem[1] = 32'hCAFE_BABE;
    imem[0] = enc_u(20'h10000, 5'd1, OP_LUI);
    imem[1] = enc_i(12'd1, 5'd0, F3_ADD, 5'd2, OP_IMMED);
    imem[2] = enc_s(12'd8, 5'd2, 5'd1, F3_SW);
    imem[3] = enc_i(12'd4, 5'd1, F3_LW, 5'd3, OP_LOAD);
    imem[4] = 32'h0ff0_000f; // fence iorw, iorw
    imem[5] = enc_i(12'd7, 5'd0, F3_ADD, 5'd4, OP_IMMED);
    do_reset();
    repeat (40) @(posedge clk);

    if (dut.register_file.registers[3] !== 32'hCAFE_BABE) begin
        $display("FAIL TC2: x3 = 0x%08h, expected 0xCAFEBABE", dut.register_file.registers[3]);
        $finish(1);
    end
    if (dut.register_file.registers[4] !== 32'd7) begin
        $display("FAIL TC2: x4 = 0x%08h, expected 0x00000007", dut.register_file.registers[4]);
        $finish(1);
    end
    if (dmem[2] !== 32'h0000_0001) begin
        $display("FAIL TC2: mem[0x10000008] = 0x%08h, expected 0x00000001", dmem[2]);
        $finish(1);
    end
    if (addi4_wb_cycle < 0) begin
        $display("FAIL TC2: instruction after FENCE never retired");
        $finish(1);
    end
    $display("PASS TC2: FENCE allows progress after LSU drains (x4 WB @ %0d)", addi4_wb_cycle);

    $display("PASS: hotspot checks completed");
    $finish(0);
end

endmodule
