// ============================================================================
// tb_dcache.v  —  Debug Testbench v2 cho dcache (Write-Back + Write-Allocate)
// ============================================================================
// Biên dịch:
//   iverilog -g2012 -o tb_dcache.vvp tb_dcache.v && vvp tb_dcache.vvp
//
// BUG FIXES so với v1:
//   [F1] cpu_write/cpu_read: giữ req HIGH liên tục đến khi cpu_ready
//   [F2] do_fence: timeout tăng lên 5000, wait thứ tự đúng
//   [F3] Tất cả reg tạm (nc_ar_seen, hits_before...) khai báo module-level
//        (Verilog-2001 không cho khai báo reg bên trong begin..end)
//   [F4] Clear cap_evict_addr/cap_d0..3 trước mỗi fence để tránh stale data
//   [F6] TC09: đổi sang set=60 để tránh conflict với TC02 (set=8)
//   [F7] TC12/13/14/15: dùng set 55/57/58/59 (địa chỉ riêng)
//   [F8] cap_base dùng hàm midx() thay vì tính tay
//
// Test cases:
//   TC01  Read miss + refill                  (set 4)
//   TC02  Write miss + write-allocate          (set 8)
//   TC03  Read hit + stat_hits check
//   TC04  Write hit (dirty mark)
//   TC05  Partial write strobe byte/halfword   (set 12)
//   TC06  Flush single dirty line              (set 47)
//   TC07  Flush 3 dirty lines                  (set 20,30,40)
//   TC08  Conflict miss clean evict            (set 5)
//   TC09  Conflict miss dirty evict LOOKUP     (set 60)
//   TC10  Non-cacheable read bypass
//   TC11  Non-cacheable write bypass
//   TC12  Fence flush+invalidate               (set 55)
//   TC13  Write-allocate partial strobe merge  (set 57)
//   TC14  Back-to-back writes same line        (set 58)
//   TC15  Read after fence.i must re-fetch     (set 59)
// ============================================================================

`timescale 1ns/1ps
`include "cache_interface/dcache/dcache_top.v"

module tb_dcache;

// ============================================================================
// Clock / Reset
// ============================================================================
reg clk, rst_n;
initial clk = 0;
always #5 clk = ~clk;

// ============================================================================
// DUT ports
// ============================================================================
reg  [31:0] cpu_addr, cpu_wdata;
reg  [3:0]  cpu_wstrb;
reg         cpu_req, cpu_we;
wire [31:0] cpu_rdata;
wire        cpu_ready;
reg  [1:0]  fence_type;

wire [31:0] current_addr, current_data;
wire        current_valid;

wire [3:0]  mem_arid, mem_awid, mem_bid, mem_rid;
wire [31:0] mem_araddr, mem_awaddr, mem_wdata_axi, mem_rdata;
wire [7:0]  mem_arlen, mem_awlen;
wire [2:0]  mem_arsize, mem_awsize, mem_arprot, mem_awprot;
wire [1:0]  mem_arburst, mem_awburst, mem_rresp, mem_bresp;
wire        mem_arvalid, mem_arready;
wire        mem_rlast, mem_rvalid, mem_rready;
wire        mem_awvalid, mem_awready;
wire        mem_wlast, mem_wvalid, mem_wready;
wire        mem_bvalid, mem_bready;
wire [3:0]  mem_wstrb;
wire [31:0] stat_hits, stat_misses, stat_writes;

dcache_top #(.ID_WIDTH(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .cpu_addr(cpu_addr),   .cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
    .cpu_req(cpu_req),     .cpu_we(cpu_we),
    .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
    .fence_type(fence_type),
    .current_addr(current_addr), .current_data(current_data),
    .current_valid(current_valid),
    .mem_arid(mem_arid),     .mem_araddr(mem_araddr),   .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize), .mem_arburst(mem_arburst), .mem_arprot(mem_arprot),
    .mem_arvalid(mem_arvalid),.mem_arready(mem_arready),
    .mem_rid(mem_rid),       .mem_rdata(mem_rdata),     .mem_rresp(mem_rresp),
    .mem_rlast(mem_rlast),   .mem_rvalid(mem_rvalid),   .mem_rready(mem_rready),
    .mem_awid(mem_awid),     .mem_awaddr(mem_awaddr),   .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize), .mem_awburst(mem_awburst), .mem_awprot(mem_awprot),
    .mem_awvalid(mem_awvalid),.mem_awready(mem_awready),
    .mem_wdata(mem_wdata_axi),.mem_wstrb(mem_wstrb),
    .mem_wlast(mem_wlast),   .mem_wvalid(mem_wvalid),   .mem_wready(mem_wready),
    .mem_bid(mem_bid),       .mem_bresp(mem_bresp),
    .mem_bvalid(mem_bvalid), .mem_bready(mem_bready),
    .stat_hits(stat_hits),   .stat_misses(stat_misses), .stat_writes(stat_writes)
);

// ============================================================================
// Internal probes
// ============================================================================
wire [2:0]  probe_flush_state  = dut.controller_inst.flush_state;
wire [5:0]  probe_flush_index  = dut.controller_inst.flush_index;
wire        probe_flush_busy   = dut.controller_inst.flush_busy;
wire [2:0]  probe_main_state   = dut.controller_inst.state;
wire [63:0] probe_dirty_bitmap = dut.controller_inst.dirty_bitmap;

wire [5:0]  probe_dra_index    = dut.data_read_all_index;
wire [31:0] probe_drw0         = dut.data_read_word_0;
wire [31:0] probe_drw1         = dut.data_read_word_1;
wire [31:0] probe_drw2         = dut.data_read_word_2;
wire [31:0] probe_drw3         = dut.data_read_word_3;

wire        probe_dwe          = dut.data_write_enable;
wire [5:0]  probe_dwi          = dut.data_write_index;
wire [1:0]  probe_dwo          = dut.data_write_offset;
wire [31:0] probe_dwd          = dut.data_write_data;
wire [3:0]  probe_dwstrb       = dut.data_write_strb;

wire [31:0] probe_ev_d0        = dut.evict_data_0;
wire [31:0] probe_ev_d1        = dut.evict_data_1;
wire [31:0] probe_ev_d2        = dut.evict_data_2;
wire [31:0] probe_ev_d3        = dut.evict_data_3;
wire [31:0] probe_ev_addr      = dut.evict_addr;
wire        probe_ev_start     = dut.evict_start;
wire        probe_ev_busy      = dut.evict_busy;
wire        probe_ev_done      = dut.evict_done;

wire        probe_tag_hit      = dut.tag_hit;
wire        probe_tag_dirty    = dut.tag_dirty_out;

// ============================================================================
// AXI memory model  (base=0x1000_0000, 64KB = 16384 words)
// ============================================================================
reg [31:0] axi_mem [0:16383];

assign mem_arready = 1'b1;
assign mem_awready = 1'b1;
assign mem_wready  = 1'b1;

// Read channel
reg        r_active;
reg [31:0] r_base;
reg [2:0]  r_beat;
reg [2:0]  r_arlen;   // [FIX-NC] latch ARLEN to support 1-beat NC reads
reg [31:0] r_data_r;
reg        r_valid_r, r_last_r;

assign mem_rdata  = r_data_r;
assign mem_rvalid = r_valid_r;
assign mem_rlast  = r_last_r;
assign mem_rresp  = 2'b00;
assign mem_rid    = 4'h0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_active<=0; r_base<=0; r_beat<=0; r_arlen<=0;
        r_data_r<=0; r_valid_r<=0; r_last_r<=0;
    end else begin
        if (!r_active) begin
            if (mem_arvalid) begin
                r_base   <= {mem_araddr[31:4], 4'h0};
                r_arlen  <= mem_arlen[2:0];   // [FIX-NC] latch burst length
                r_beat   <= 0; r_active <= 1;
            end
        end else begin
            if (!r_valid_r) begin
                r_data_r  <= axi_mem[midx({r_base[31:4],4'h0}) + r_beat];
                r_valid_r <= 1;
                r_last_r  <= (r_beat == r_arlen);   // [FIX-NC]
            end else if (mem_rready) begin
                if (r_last_r) begin
                    r_valid_r<=0; r_last_r<=0; r_active<=0;
                end else begin
                    r_beat    <= r_beat + 1;
                    r_data_r  <= axi_mem[midx({r_base[31:4],4'h0}) + r_beat + 1];
                    r_last_r  <= (r_beat+1 == r_arlen);   // [FIX-NC]
                end
            end
        end
    end
end

// Write / evict capture
reg [31:0] cap_evict_addr;
reg [31:0] cap_d0, cap_d1, cap_d2, cap_d3;
reg [2:0]  cap_beat;
reg        cap_in_prog;
reg        bvalid_r;
reg [31:0] cap_base;

assign mem_bvalid = bvalid_r;
assign mem_bresp  = 2'b00;
assign mem_bid    = 4'h0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cap_evict_addr<=0; cap_base<=0;
        cap_d0<=0; cap_d1<=0; cap_d2<=0; cap_d3<=0;
        cap_beat<=0; cap_in_prog<=0; bvalid_r<=0;
    end else begin
        if (!cap_in_prog && mem_awvalid) begin
            cap_evict_addr <= {mem_awaddr[31:4], 4'h0};
            cap_base       <= midx({mem_awaddr[31:4],4'h0});
            cap_beat       <= 0; cap_in_prog <= 1;
        end
        if (cap_in_prog && mem_wvalid) begin
            axi_mem[cap_base + cap_beat] <= mem_wdata_axi;
            case (cap_beat)
                0: cap_d0 <= mem_wdata_axi;
                1: cap_d1 <= mem_wdata_axi;
                2: cap_d2 <= mem_wdata_axi;
                3: cap_d3 <= mem_wdata_axi;
            endcase
            cap_beat <= cap_beat + 1;
            if (mem_wlast) begin cap_in_prog<=0; bvalid_r<=1; end
        end
        if (bvalid_r && mem_bready) bvalid_r <= 0;
    end
end

// ============================================================================
// Cycle counter
// ============================================================================
integer cyc;
initial cyc = 0;
always @(posedge clk) cyc = cyc + 1;

// ============================================================================
// Scoreboard
// ============================================================================
integer total_pass, total_fail;
initial begin total_pass=0; total_fail=0; end

// ============================================================================
// Monitors
// ============================================================================
always @(posedge clk) begin
    if (probe_flush_busy)
        $display("[CYC%4d][FLUSH fsm=%0d idx=%2d] ev_start=%b busy=%b done=%b addr=%08h bitmap=%016h",
            cyc, probe_flush_state, probe_flush_index,
            probe_ev_start, probe_ev_busy, probe_ev_done,
            probe_ev_addr, probe_dirty_bitmap);
end
always @(posedge clk) begin
    if (probe_dwe)
        $display("[CYC%4d][DA_WR] idx=%2d off=%1d strb=%04b data=%08h",
            cyc, probe_dwi, probe_dwo, probe_dwstrb, probe_dwd);
end
always @(posedge clk) begin
    if (mem_awvalid && mem_awready)
        $display("[CYC%4d][AXI_AW] awaddr=%08h", cyc, mem_awaddr);
    if (mem_wvalid && mem_wready)
        $display("[CYC%4d][AXI_W ] beat=%0d wdata=%08h wlast=%b",
            cyc, cap_beat, mem_wdata_axi, mem_wlast);
    if (mem_arvalid && mem_arready)
        $display("[CYC%4d][AXI_AR] araddr=%08h", cyc, mem_araddr);
end
always @(posedge clk) begin
    if (probe_ev_start)
        $display("[CYC%4d][EV_START] addr=%08h {%08h %08h %08h %08h}",
            cyc, probe_ev_addr,
            probe_ev_d0, probe_ev_d1, probe_ev_d2, probe_ev_d3);
end

// ============================================================================
// Functions & Tasks
// ============================================================================
function [13:0] midx;
    input [31:0] addr;
    midx = (addr - 32'h10000000) >> 2;
endfunction

task mem_set_line;
    input [31:0] base, w0, w1, w2, w3;
    begin
        axi_mem[midx(base)  ] = w0;
        axi_mem[midx(base)+1] = w1;
        axi_mem[midx(base)+2] = w2;
        axi_mem[midx(base)+3] = w3;
    end
endtask

// [F1] Giữ req/we HIGH liên tục đến khi cpu_ready lên
task cpu_write;
    input [31:0] addr, data;
    input [3:0]  strb;
    integer tout;
    begin
        @(negedge clk);
        cpu_addr=addr; cpu_wdata=data; cpu_wstrb=strb;
        cpu_req=1'b1; cpu_we=1'b1; tout=0;
        @(posedge clk);
        while (!cpu_ready && tout<500) begin @(posedge clk); tout=tout+1; end
        if (tout>=500) $display("[WARN] cpu_write TIMEOUT %08h cyc=%0d",addr,cyc);
        @(negedge clk); cpu_req=1'b0; cpu_we=1'b0;
    end
endtask

task cpu_read;
    input  [31:0] addr;
    output [31:0] rdata;
    integer tout;
    begin
        @(negedge clk);
        cpu_addr=addr; cpu_wstrb=4'hF;
        cpu_req=1'b1; cpu_we=1'b0; tout=0;
        @(posedge clk);
        while (!cpu_ready && tout<500) begin @(posedge clk); tout=tout+1; end
        if (tout>=500) $display("[WARN] cpu_read TIMEOUT %08h cyc=%0d",addr,cyc);
        rdata=cpu_rdata;
        @(negedge clk); cpu_req=1'b0;
    end
endtask

task do_reset;
    begin
        rst_n=0; cpu_req=0; cpu_we=0;
        cpu_addr=0; cpu_wdata=0; cpu_wstrb=4'hF; fence_type=0;
        repeat(4) @(posedge clk);
        rst_n=1; repeat(2) @(posedge clk);
    end
endtask

// [F2] Fence với timeout 5000, đợi đúng thứ tự
task do_fence;
    input [1:0] ftype;
    integer tout;
    begin
        @(negedge clk);
        fence_type=ftype; cpu_req=1'b0; cpu_we=1'b0;
        repeat(3) @(posedge clk);
        tout=0;
        while (!probe_flush_busy && tout<30) begin @(posedge clk); tout=tout+1; end
        tout=0;
        while (probe_flush_busy && tout<5000) begin @(posedge clk); tout=tout+1; end
        if (tout>=5000) $display("[WARN] do_fence TIMEOUT flush_busy stuck cyc=%0d",cyc);
        @(negedge clk); fence_type=2'b00;
        repeat(10) @(posedge clk);
    end
endtask

task chk;
    input [31:0]  got, exp;
    input [255:0] name;
    begin
        if (got===exp) begin
            $display("    PASS  [%0s] = 0x%08h", name, exp);
            total_pass=total_pass+1;
        end else begin
            $display("    FAIL  [%0s] got=0x%08h  exp=0x%08h  <<<", name, got, exp);
            total_fail=total_fail+1;
        end
    end
endtask

task tc_header;
    input [8*80-1:0] name;
    begin
        $display("\n============================================================");
        $display("  %0s", name);
        $display("============================================================");
    end
endtask

// ============================================================================
// [F3] Module-level vars — không khai báo reg bên trong begin..end (Verilog-2001)
// ============================================================================
reg [31:0] rd;
integer    i;
reg        nc_ar_seen, nc_aw_seen;
integer    nc_tout;
reg [31:0] hits_before;

// ============================================================================
// MAIN
// ============================================================================
initial begin
    $dumpfile("tb_dcache.vcd");
    $dumpvars(0, tb_dcache);

    for (i=0; i<16384; i=i+1)
        axi_mem[i] = {16'hBEEF, i[15:0]};

    do_reset();

    // ========================================================================
    // TC01 — Read miss + refill  (set=4, addr=0x10000040)
    // ========================================================================
    tc_header("TC01: Read miss + refill");
    mem_set_line(32'h10000040, 32'h11223344, 32'h55667788, 32'h99AABBCC, 32'hDDEEFF00);
    cpu_read(32'h10000040, rd); chk(rd, 32'h11223344, "TC01 miss word0");
    cpu_read(32'h10000044, rd); chk(rd, 32'h55667788, "TC01 hit  word1");
    cpu_read(32'h10000048, rd); chk(rd, 32'h99AABBCC, "TC01 hit  word2");
    cpu_read(32'h1000004C, rd); chk(rd, 32'hDDEEFF00, "TC01 hit  word3");

    // ========================================================================
    // TC02 — Write miss + write-allocate  (set=8, addr=0x10000080)
    // ========================================================================
    tc_header("TC02: Write miss + write-allocate");
    mem_set_line(32'h10000080, 32'hAAAA0001, 32'hAAAA0002, 32'hAAAA0003, 32'hAAAA0004);
    cpu_write(32'h10000088, 32'hDEADBEEF, 4'hF);
    cpu_read(32'h10000080, rd); chk(rd, 32'hAAAA0001, "TC02 word0 unchanged");
    cpu_read(32'h10000084, rd); chk(rd, 32'hAAAA0002, "TC02 word1 unchanged");
    cpu_read(32'h10000088, rd); chk(rd, 32'hDEADBEEF, "TC02 word2 written");
    cpu_read(32'h1000008C, rd); chk(rd, 32'hAAAA0004, "TC02 word3 unchanged");

    // ========================================================================
    // TC03 — Read hit + stat_hits
    // ========================================================================
    tc_header("TC03: Read hit + stat check");
    hits_before = stat_hits;
    cpu_read(32'h10000044, rd);
    chk(rd, 32'h55667788, "TC03 hit value");
    if (stat_hits > hits_before) begin
        $display("    PASS  [TC03 stat_hits] %0d -> %0d", hits_before, stat_hits);
        total_pass=total_pass+1;
    end else begin
        $display("    FAIL  [TC03 stat_hits] no increase %0d -> %0d  <<<", hits_before, stat_hits);
        total_fail=total_fail+1;
    end

    // ========================================================================
    // TC04 — Write hit
    // ========================================================================
    tc_header("TC04: Write hit (dirty mark)");
    cpu_write(32'h10000044, 32'hCAFECAFE, 4'hF);
    cpu_read (32'h10000044, rd); chk(rd, 32'hCAFECAFE, "TC04 write-hit readback");
    cpu_read (32'h10000040, rd); chk(rd, 32'h11223344, "TC04 word0 intact");
    cpu_read (32'h10000048, rd); chk(rd, 32'h99AABBCC, "TC04 word2 intact");

    // ========================================================================
    // TC05 — Partial write strobe  (set=12, addr=0x100000C0)
    // ========================================================================
    tc_header("TC05: Partial write strobe");
    mem_set_line(32'h100000C0, 32'h12345678, 32'hABCDEF01, 32'h23456789, 32'hBCDEF012);
    cpu_read (32'h100000C0, rd);
    chk(rd, 32'h12345678, "TC05 refill word0");
    cpu_write(32'h100000C0, 32'hFFFFFFAA, 4'b0001);   // byte[0] = 0xAA
    cpu_read (32'h100000C0, rd);
    chk(rd, 32'h123456AA, "TC05 byte0 strobe");
    cpu_write(32'h100000C4, 32'hBEEF0000, 4'b1100);   // byte[3:2]
    cpu_read (32'h100000C4, rd);
    chk(rd, 32'hBEEFEF01, "TC05 halfword strobe");

    // ========================================================================
    // TC06 — Flush single dirty line  (set=47, addr=0x10001EF0)
    // [F4] clear cap trước fence
    // ========================================================================
    tc_header("TC06: Flush single dirty line");
    mem_set_line(32'h10001EF0, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000070);
    cpu_write(32'h10001EF0, 32'h00000000, 4'hF);
    cpu_write(32'h10001EF4, 32'h00000000, 4'hF);
    cpu_write(32'h10001EF8, 32'h00000000, 4'hF);
    cpu_write(32'h10001EFC, 32'h00000070, 4'hF);
    @(negedge clk);
    cap_evict_addr=32'h0; cap_d0=32'h0; cap_d1=32'h0; cap_d2=32'h0; cap_d3=32'h0;
    do_fence(2'b01);
    chk(cap_evict_addr, 32'h10001EF0, "TC06 evict addr");
    chk(cap_d0, 32'h00000000, "TC06 word0");
    chk(cap_d1, 32'h00000000, "TC06 word1");
    chk(cap_d2, 32'h00000000, "TC06 word2");
    chk(cap_d3, 32'h00000070, "TC06 word3");

    // ========================================================================
    // TC07 — Flush 3 dirty lines  (set 20,30,40)
    // ========================================================================
    tc_header("TC07: Flush 3 dirty lines");
    // set=20 → 20<<4=0x140 → 0x10000140
    mem_set_line(32'h10000140, 32'h0, 32'h0, 32'h0, 32'h0);
    cpu_write(32'h10000140, 32'hF0F0F001, 4'hF);
    cpu_write(32'h10000144, 32'hF0F0F002, 4'hF);
    cpu_write(32'h10000148, 32'hF0F0F003, 4'hF);
    cpu_write(32'h1000014C, 32'hF0F0F004, 4'hF);
    // set=30 → 0x100001E0
    mem_set_line(32'h100001E0, 32'h0, 32'h0, 32'h0, 32'h0);
    cpu_write(32'h100001E0, 32'hE0E0E001, 4'hF);
    cpu_write(32'h100001E4, 32'hE0E0E002, 4'hF);
    cpu_write(32'h100001E8, 32'hE0E0E003, 4'hF);
    cpu_write(32'h100001EC, 32'hE0E0E004, 4'hF);
    // set=40 → 0x10000280
    mem_set_line(32'h10000280, 32'h0, 32'h0, 32'h0, 32'h0);
    cpu_write(32'h10000280, 32'hD0D0D001, 4'hF);
    cpu_write(32'h10000284, 32'hD0D0D002, 4'hF);
    cpu_write(32'h10000288, 32'hD0D0D003, 4'hF);
    cpu_write(32'h1000028C, 32'hD0D0D004, 4'hF);
    do_fence(2'b01);
    chk(axi_mem[midx(32'h10000140)  ], 32'hF0F0F001, "TC07 set20 w0");
    chk(axi_mem[midx(32'h10000140)+1], 32'hF0F0F002, "TC07 set20 w1");
    chk(axi_mem[midx(32'h10000140)+2], 32'hF0F0F003, "TC07 set20 w2");
    chk(axi_mem[midx(32'h10000140)+3], 32'hF0F0F004, "TC07 set20 w3");
    chk(axi_mem[midx(32'h100001E0)  ], 32'hE0E0E001, "TC07 set30 w0");
    chk(axi_mem[midx(32'h100001E0)+1], 32'hE0E0E002, "TC07 set30 w1");
    chk(axi_mem[midx(32'h100001E0)+2], 32'hE0E0E003, "TC07 set30 w2");
    chk(axi_mem[midx(32'h100001E0)+3], 32'hE0E0E004, "TC07 set30 w3");
    chk(axi_mem[midx(32'h10000280)  ], 32'hD0D0D001, "TC07 set40 w0");
    chk(axi_mem[midx(32'h10000280)+1], 32'hD0D0D002, "TC07 set40 w1");
    chk(axi_mem[midx(32'h10000280)+2], 32'hD0D0D003, "TC07 set40 w2");
    chk(axi_mem[midx(32'h10000280)+3], 32'hD0D0D004, "TC07 set40 w3");

    // ========================================================================
    // TC08 — Conflict miss clean evict  (set=5)
    //   A=0x10000050 (tag=0x40000), B=0x10001050 (tag=0x40004)
    // ========================================================================
    tc_header("TC08: Conflict miss clean evict");
    mem_set_line(32'h10000050, 32'hC001C001, 32'hC002C002, 32'hC003C003, 32'hC004C004);
    mem_set_line(32'h10001050, 32'hD001D001, 32'hD002D002, 32'hD003D003, 32'hD004D004);
    cpu_read(32'h10000050, rd); chk(rd, 32'hC001C001, "TC08 read A");
    cpu_read(32'h10001050, rd); chk(rd, 32'hD001D001, "TC08 read B conflict");
    cpu_read(32'h10000054, rd); chk(rd, 32'hC002C002, "TC08 re-read A word1");

    // ========================================================================
    // TC09 — Conflict miss dirty evict via LOOKUP  (set=60)
    // [F6] set=60 → 60<<4=0x3C0 → A=0x100003C0, B=0x100013C0
    // ========================================================================
    tc_header("TC09: Conflict miss dirty evict (LOOKUP)");
    mem_set_line(32'h100003C0, 32'h0, 32'h0, 32'h0, 32'h0);
    cpu_write(32'h100003C0, 32'hCAFECAFE, 4'hF);
    cpu_write(32'h100003C4, 32'hBABEBABE, 4'hF);
    cpu_write(32'h100003C8, 32'hFACEFACE, 4'hF);
    cpu_write(32'h100003CC, 32'hDEADDEAD, 4'hF);
    mem_set_line(32'h100013C0, 32'hAB010203, 32'hAB040506, 32'hAB070809, 32'hAB0A0B0C);
    $display("  -- conflict read triggers dirty evict --");
    cpu_read(32'h100013C0, rd);
    chk(rd, 32'hAB010203, "TC09 refill word0 after evict");
    chk(axi_mem[midx(32'h100003C0)  ], 32'hCAFECAFE, "TC09 evicted w0");
    chk(axi_mem[midx(32'h100003C0)+1], 32'hBABEBABE, "TC09 evicted w1");
    chk(axi_mem[midx(32'h100003C0)+2], 32'hFACEFACE, "TC09 evicted w2");
    chk(axi_mem[midx(32'h100003C0)+3], 32'hDEADDEAD, "TC09 evicted w3");

    // ========================================================================
    // TC10 — Non-cacheable read bypass  (addr 0x2000_0000, bits[31:29]=001)
    // [F3] nc_ar_seen, nc_tout khai báo module level
    // ========================================================================
    tc_header("TC10: Non-cacheable read bypass");
    nc_ar_seen = 1'b0;
    @(negedge clk);
    cpu_addr=32'h20000000; cpu_wstrb=4'hF; cpu_req=1'b1; cpu_we=1'b0;
    nc_tout=0;
    @(posedge clk);
    while (nc_tout < 20) begin
        if (mem_arvalid) nc_ar_seen=1'b1;
        @(posedge clk); nc_tout=nc_tout+1;
    end
    @(negedge clk); cpu_req=1'b0;
    repeat(15) @(posedge clk);
    if (nc_ar_seen) begin
        $display("    PASS  [TC10 NC arvalid] AXI read issued"); total_pass=total_pass+1;
    end else begin
        $display("    FAIL  [TC10 NC arvalid] no AXI read  <<<"); total_fail=total_fail+1;
    end

    // ========================================================================
    // TC11 — Non-cacheable write bypass
    // ========================================================================
    tc_header("TC11: Non-cacheable write bypass");
    nc_aw_seen = 1'b0;
    @(negedge clk);
    cpu_addr=32'h20000010; cpu_wdata=32'hDEADBEEF; cpu_wstrb=4'hF;
    cpu_req=1'b1; cpu_we=1'b1;
    nc_tout=0;
    @(posedge clk);
    while (nc_tout < 20) begin
        if (mem_awvalid) nc_aw_seen=1'b1;
        @(posedge clk); nc_tout=nc_tout+1;
    end
    @(negedge clk); cpu_req=1'b0; cpu_we=1'b0;
    repeat(20) @(posedge clk);
    if (nc_aw_seen) begin
        $display("    PASS  [TC11 NC awvalid] AXI write issued"); total_pass=total_pass+1;
    end else begin
        $display("    FAIL  [TC11 NC awvalid] no AXI write  <<<"); total_fail=total_fail+1;
    end

    // ========================================================================
    // TC12 — Fence flush+invalidate  (set=55, addr=0x10000370)
    // [F4] clear cap; [F7] set=55
    // ========================================================================
    tc_header("TC12: Fence flush + invalidate");
    mem_set_line(32'h10000370, 32'h11111111, 32'h22222222, 32'h33333333, 32'h44444444);
    cpu_write(32'h10000370, 32'hAA000001, 4'hF);
    cpu_write(32'h10000374, 32'hAA000002, 4'hF);
    cpu_write(32'h10000378, 32'hAA000003, 4'hF);
    cpu_write(32'h1000037C, 32'hAA000004, 4'hF);
    @(negedge clk);
    cap_evict_addr=32'h0; cap_d0=32'h0; cap_d1=32'h0; cap_d2=32'h0; cap_d3=32'h0;
    do_fence(2'b11);
    chk(axi_mem[midx(32'h10000370)  ], 32'hAA000001, "TC12 evict w0");
    chk(axi_mem[midx(32'h10000370)+1], 32'hAA000002, "TC12 evict w1");
    chk(axi_mem[midx(32'h10000370)+2], 32'hAA000003, "TC12 evict w2");
    chk(axi_mem[midx(32'h10000370)+3], 32'hAA000004, "TC12 evict w3");
    // Sau invalidate → read phải miss, lấy từ axi_mem (data vừa evict)
    cpu_read(32'h10000370, rd);
    chk(rd, 32'hAA000001, "TC12 re-read after invalidate");

    // ========================================================================
    // TC13 — Write-allocate partial strobe  (set=57, addr=0x10000390)
    // [F7]
    // ========================================================================
    tc_header("TC13: Write-allocate partial strobe merge");
    mem_set_line(32'h10000390, 32'hDEAD0001, 32'hDEAD0002, 32'hDEAD0003, 32'hDEAD0004);
    cpu_write(32'h1000039C, 32'hFFFFFF55, 4'b0001);   // byte[0] of word[3]
    cpu_read(32'h10000390, rd); chk(rd, 32'hDEAD0001, "TC13 w0 intact");
    cpu_read(32'h10000394, rd); chk(rd, 32'hDEAD0002, "TC13 w1 intact");
    cpu_read(32'h10000398, rd); chk(rd, 32'hDEAD0003, "TC13 w2 intact");
    cpu_read(32'h1000039C, rd); chk(rd, 32'hDEAD0055, "TC13 w3 byte0 merged");

    // ========================================================================
    // TC14 — Back-to-back writes  (set=58, addr=0x100003A0)
    // [F7]
    // ========================================================================
    tc_header("TC14: Back-to-back writes same line");
    mem_set_line(32'h100003A0, 32'h0, 32'h0, 32'h0, 32'h0);
    cpu_write(32'h100003A0, 32'hBB000001, 4'hF);
    cpu_write(32'h100003A4, 32'hBB000002, 4'hF);
    cpu_write(32'h100003A8, 32'hBB000003, 4'hF);
    cpu_write(32'h100003AC, 32'hBB000004, 4'hF);
    cpu_read(32'h100003A0, rd); chk(rd, 32'hBB000001, "TC14 w0");
    cpu_read(32'h100003A4, rd); chk(rd, 32'hBB000002, "TC14 w1");
    cpu_read(32'h100003A8, rd); chk(rd, 32'hBB000003, "TC14 w2");
    cpu_read(32'h100003AC, rd); chk(rd, 32'hBB000004, "TC14 w3");

    // ========================================================================
    // TC15 — Read after fence.i must re-fetch  (set=59, addr=0x100003B0)
    // [F7]
    // ========================================================================
    tc_header("TC15: Read after fence.i (invalidate only) re-fetch");
    mem_set_line(32'h100003B0, 32'hCC000001, 32'hCC000002, 32'hCC000003, 32'hCC000004);
    cpu_read(32'h100003B0, rd);
    chk(rd, 32'hCC000001, "TC15 initial read");
    // Giả lập DMA cập nhật memory
    axi_mem[midx(32'h100003B0)  ] = 32'hFF000001;
    axi_mem[midx(32'h100003B0)+1] = 32'hFF000002;
    axi_mem[midx(32'h100003B0)+2] = 32'hFF000003;
    axi_mem[midx(32'h100003B0)+3] = 32'hFF000004;
    do_fence(2'b10);   // invalidate only (không flush)
    cpu_read(32'h100003B0, rd);
    chk(rd, 32'hFF000001, "TC15 re-read new data w0");
    cpu_read(32'h100003B4, rd);
    chk(rd, 32'hFF000002, "TC15 re-read new data w1");

    // ========================================================================
    // Summary
    // ========================================================================
    repeat(10) @(posedge clk);
    $display("\n============================================================");
    $display("  SUMMARY: %0d PASS  /  %0d FAIL  /  %0d TOTAL",
             total_pass, total_fail, total_pass+total_fail);
    $display("  Stats: hits=%0d  misses=%0d  writes=%0d",
             stat_hits, stat_misses, stat_writes);
    $display("============================================================\n");
    $finish;
end

// Watchdog 10ms
initial begin
    #10_000_000;
    $display("[WATCHDOG] Timeout — forced stop");
    $finish;
end

endmodule