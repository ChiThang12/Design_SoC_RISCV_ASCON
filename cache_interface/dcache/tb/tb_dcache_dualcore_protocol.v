`timescale 1ns/1ps
`include "cache_interface/dcache/dcache_top.v"
`include "cache_interface/dcache/dcache_snoop_bus_2way.v"
`include "cache_interface/dcache/dcache_snoop_arb_3to1.v"

module tb_dcache_dualcore_protocol;
    localparam [1:0] STATE_I = 2'b00;
    localparam [1:0] STATE_E = 2'b10;
    localparam [1:0] STATE_M = 2'b11;

    localparam [31:0] LINE_ADDR = 32'h1000_0080;

    reg clk, rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg  [31:0] cpu0_addr, cpu0_wdata;
    reg  [3:0]  cpu0_wstrb;
    reg         cpu0_req, cpu0_we;
    wire [31:0] cpu0_rdata;
    wire        cpu0_ready;
    reg  [1:0]  cpu0_fence_type;

    reg  [31:0] cpu1_addr, cpu1_wdata;
    reg  [3:0]  cpu1_wstrb;
    reg         cpu1_req, cpu1_we;
    wire [31:0] cpu1_rdata;
    wire        cpu1_ready;
    reg  [1:0]  cpu1_fence_type;

    wire [3:0]  mem0_arid, mem0_awid, mem1_arid, mem1_awid;
    reg  [3:0]  mem0_rid, mem0_bid, mem1_rid, mem1_bid;
    wire [31:0] mem0_araddr, mem0_awaddr, mem0_wdata;
    wire [31:0] mem1_araddr, mem1_awaddr, mem1_wdata;
    reg  [31:0] mem0_rdata, mem1_rdata;
    wire [7:0]  mem0_arlen, mem0_awlen, mem1_arlen, mem1_awlen;
    wire [2:0]  mem0_arsize, mem0_awsize, mem0_arprot, mem0_awprot;
    wire [2:0]  mem1_arsize, mem1_awsize, mem1_arprot, mem1_awprot;
    wire [1:0]  mem0_arburst, mem0_awburst, mem1_arburst, mem1_awburst;
    reg  [1:0]  mem0_rresp, mem0_bresp, mem1_rresp, mem1_bresp;
    wire        mem0_arvalid, mem0_awvalid, mem0_wvalid, mem0_wlast;
    wire        mem1_arvalid, mem1_awvalid, mem1_wvalid, mem1_wlast;
    reg         mem0_arready, mem0_awready, mem0_wready;
    reg         mem1_arready, mem1_awready, mem1_wready;
    reg         mem0_rvalid, mem0_rlast, mem0_bvalid;
    reg         mem1_rvalid, mem1_rlast, mem1_bvalid;
    wire        mem0_rready, mem0_bready, mem1_rready, mem1_bready;
    wire [3:0]  mem0_wstrb, mem1_wstrb;

    reg  [31:0] up_snoop_addr;
    reg  [1:0]  up_snoop_cmd;
    reg         up_snoop_req_valid;
    wire        up_snoop_req_ready;
    wire        up_snoop_resp_valid;
    wire        up_snoop_resp_hit;
    wire [127:0] up_snoop_resp_data;

    wire [31:0] bus_snoop_addr;
    wire [1:0]  bus_snoop_cmd;
    wire        bus_snoop_req_valid;
    wire        bus_snoop_req_ready;
    wire        bus_snoop_resp_valid;
    wire        bus_snoop_resp_hit;
    wire [127:0] bus_snoop_resp_data;

    wire [31:0] cpu1_miss_snoop_addr;
    wire [1:0]  cpu1_miss_snoop_cmd;
    wire        cpu1_miss_snoop_req_valid;
    wire        cpu1_miss_snoop_req_ready;
    wire        cpu1_miss_snoop_resp_valid;
    wire        cpu1_miss_snoop_resp_hit;
    wire [127:0] cpu1_miss_snoop_resp_data;

    wire [31:0] dc0_snoop_addr, dc1_snoop_addr;
    wire [1:0]  dc0_snoop_cmd, dc1_snoop_cmd;
    wire        dc0_snoop_req_valid, dc1_snoop_req_valid;
    wire        dc0_snoop_req_ready, dc1_snoop_req_ready;
    wire        dc0_snoop_resp_valid, dc1_snoop_resp_valid;
    wire        dc0_snoop_resp_hit, dc1_snoop_resp_hit;
    wire [127:0] dc0_snoop_resp_data, dc1_snoop_resp_data;

    wire [31:0] stat0_hits, stat0_misses, stat0_writes;
    wire [31:0] stat1_hits, stat1_misses, stat1_writes;
    wire [31:0] stat0_peer_snoop_reqs, stat0_peer_snoop_hits, stat0_c2c_forwards, stat0_c2c_fill_cycles, stat0_mem_refills;
    wire [31:0] stat1_peer_snoop_reqs, stat1_peer_snoop_hits, stat1_c2c_forwards, stat1_c2c_fill_cycles, stat1_mem_refills;

    reg [31:0] mem [0:1023];
    integer pass_count, fail_count;
    integer wb0_count, wb1_count;
    integer i;

    function [9:0] midx;
        input [31:0] addr;
        begin
            midx = addr[11:2];
        end
    endfunction

    task check;
        input cond;
        input [8*80-1:0] msg;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", msg);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", msg);
            end
        end
    endtask

    task cpu0_read;
        input [31:0] addr;
        output [31:0] data;
        integer timeout;
        begin
            @(posedge clk);
            cpu0_addr <= addr;
            cpu0_we <= 1'b0;
            cpu0_wdata <= 32'h0;
            cpu0_wstrb <= 4'h0;
            cpu0_req <= 1'b1;
            timeout = 0;
            while (!cpu0_ready && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            data = cpu0_rdata;
            cpu0_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task cpu0_write;
        input [31:0] addr;
        input [31:0] data;
        integer timeout;
        begin
            @(posedge clk);
            cpu0_addr <= addr;
            cpu0_we <= 1'b1;
            cpu0_wdata <= data;
            cpu0_wstrb <= 4'hf;
            cpu0_req <= 1'b1;
            timeout = 0;
            while (!cpu0_ready && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            cpu0_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task cpu1_read;
        input [31:0] addr;
        output [31:0] data;
        integer timeout;
        begin
            @(posedge clk);
            cpu1_addr <= addr;
            cpu1_we <= 1'b0;
            cpu1_wdata <= 32'h0;
            cpu1_wstrb <= 4'h0;
            cpu1_req <= 1'b1;
            timeout = 0;
            while (!cpu1_ready && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            data = cpu1_rdata;
            cpu1_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task cpu1_write;
        input [31:0] addr;
        input [31:0] data;
        integer timeout;
        begin
            @(posedge clk);
            cpu1_addr <= addr;
            cpu1_we <= 1'b1;
            cpu1_wdata <= data;
            cpu1_wstrb <= 4'hf;
            cpu1_req <= 1'b1;
            timeout = 0;
            while (!cpu1_ready && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            cpu1_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task issue_upstream_snoop;
        input [31:0] addr;
        input [1:0] cmd;
        output hit;
        output [127:0] data;
        integer timeout;
        begin
            @(posedge clk);
            up_snoop_addr <= addr;
            up_snoop_cmd <= cmd;
            up_snoop_req_valid <= 1'b1;
            timeout = 0;
            while (!up_snoop_req_ready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            @(posedge clk);
            up_snoop_req_valid <= 1'b0;
            timeout = 0;
            while (!up_snoop_resp_valid && timeout < 200) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            hit = up_snoop_resp_hit;
            data = up_snoop_resp_data;
            @(posedge clk);
        end
    endtask

    reg [31:0] rd0, rd1;
    reg        snp_hit;
    reg [127:0] snp_data;

    dcache_top #(.ID_WIDTH(4)) dcache0 (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu0_addr), .cpu_wdata(cpu0_wdata), .cpu_wstrb(cpu0_wstrb),
        .cpu_req(cpu0_req), .cpu_we(cpu0_we), .cpu_rdata(cpu0_rdata), .cpu_ready(cpu0_ready),
        .fence_type(cpu0_fence_type),
        .miss_snoop_enable(1'b0),
        .current_addr(), .current_data(), .current_valid(),
        .mem_arid(mem0_arid), .mem_araddr(mem0_araddr), .mem_arlen(mem0_arlen),
        .mem_arsize(mem0_arsize), .mem_arburst(mem0_arburst), .mem_arprot(mem0_arprot),
        .mem_arvalid(mem0_arvalid), .mem_arready(mem0_arready),
        .mem_rid(mem0_rid), .mem_rdata(mem0_rdata), .mem_rresp(mem0_rresp),
        .mem_rlast(mem0_rlast), .mem_rvalid(mem0_rvalid), .mem_rready(mem0_rready),
        .mem_awid(mem0_awid), .mem_awaddr(mem0_awaddr), .mem_awlen(mem0_awlen),
        .mem_awsize(mem0_awsize), .mem_awburst(mem0_awburst), .mem_awprot(mem0_awprot),
        .mem_awvalid(mem0_awvalid), .mem_awready(mem0_awready),
        .mem_wdata(mem0_wdata), .mem_wstrb(mem0_wstrb), .mem_wlast(mem0_wlast),
        .mem_wvalid(mem0_wvalid), .mem_wready(mem0_wready),
        .mem_bid(mem0_bid), .mem_bresp(mem0_bresp), .mem_bvalid(mem0_bvalid), .mem_bready(mem0_bready),
        .dc_snoop_addr(dc0_snoop_addr), .dc_snoop_cmd(dc0_snoop_cmd),
        .dc_snoop_req_valid(dc0_snoop_req_valid), .dc_snoop_req_ready(dc0_snoop_req_ready),
        .dc_snoop_resp_valid(dc0_snoop_resp_valid), .dc_snoop_resp_hit(dc0_snoop_resp_hit),
        .dc_snoop_resp_data(dc0_snoop_resp_data),
        .miss_snoop_addr(), .miss_snoop_cmd(), .miss_snoop_req_valid(),
        .miss_snoop_req_ready(1'b0), .miss_snoop_resp_valid(1'b0),
        .miss_snoop_resp_hit(1'b0), .miss_snoop_resp_data(128'h0),
        .stat_hits(stat0_hits), .stat_misses(stat0_misses), .stat_writes(stat0_writes),
        .stat_peer_snoop_reqs(stat0_peer_snoop_reqs), .stat_peer_snoop_hits(stat0_peer_snoop_hits),
        .stat_c2c_forwards(stat0_c2c_forwards), .stat_c2c_fill_cycles(stat0_c2c_fill_cycles),
        .stat_mem_refills(stat0_mem_refills)
    );

    dcache_top #(.ID_WIDTH(4)) dcache1 (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu1_addr), .cpu_wdata(cpu1_wdata), .cpu_wstrb(cpu1_wstrb),
        .cpu_req(cpu1_req), .cpu_we(cpu1_we), .cpu_rdata(cpu1_rdata), .cpu_ready(cpu1_ready),
        .fence_type(cpu1_fence_type),
        .miss_snoop_enable(1'b1),
        .current_addr(), .current_data(), .current_valid(),
        .mem_arid(mem1_arid), .mem_araddr(mem1_araddr), .mem_arlen(mem1_arlen),
        .mem_arsize(mem1_arsize), .mem_arburst(mem1_arburst), .mem_arprot(mem1_arprot),
        .mem_arvalid(mem1_arvalid), .mem_arready(mem1_arready),
        .mem_rid(mem1_rid), .mem_rdata(mem1_rdata), .mem_rresp(mem1_rresp),
        .mem_rlast(mem1_rlast), .mem_rvalid(mem1_rvalid), .mem_rready(mem1_rready),
        .mem_awid(mem1_awid), .mem_awaddr(mem1_awaddr), .mem_awlen(mem1_awlen),
        .mem_awsize(mem1_awsize), .mem_awburst(mem1_awburst), .mem_awprot(mem1_awprot),
        .mem_awvalid(mem1_awvalid), .mem_awready(mem1_awready),
        .mem_wdata(mem1_wdata), .mem_wstrb(mem1_wstrb), .mem_wlast(mem1_wlast),
        .mem_wvalid(mem1_wvalid), .mem_wready(mem1_wready),
        .mem_bid(mem1_bid), .mem_bresp(mem1_bresp), .mem_bvalid(mem1_bvalid), .mem_bready(mem1_bready),
        .dc_snoop_addr(dc1_snoop_addr), .dc_snoop_cmd(dc1_snoop_cmd),
        .dc_snoop_req_valid(dc1_snoop_req_valid), .dc_snoop_req_ready(dc1_snoop_req_ready),
        .dc_snoop_resp_valid(dc1_snoop_resp_valid), .dc_snoop_resp_hit(dc1_snoop_resp_hit),
        .dc_snoop_resp_data(dc1_snoop_resp_data),
        .miss_snoop_addr(cpu1_miss_snoop_addr),
        .miss_snoop_cmd(cpu1_miss_snoop_cmd),
        .miss_snoop_req_valid(cpu1_miss_snoop_req_valid),
        .miss_snoop_req_ready(cpu1_miss_snoop_req_ready),
        .miss_snoop_resp_valid(cpu1_miss_snoop_resp_valid),
        .miss_snoop_resp_hit(cpu1_miss_snoop_resp_hit),
        .miss_snoop_resp_data(cpu1_miss_snoop_resp_data),
        .stat_hits(stat1_hits), .stat_misses(stat1_misses), .stat_writes(stat1_writes),
        .stat_peer_snoop_reqs(stat1_peer_snoop_reqs), .stat_peer_snoop_hits(stat1_peer_snoop_hits),
        .stat_c2c_forwards(stat1_c2c_forwards), .stat_c2c_fill_cycles(stat1_c2c_fill_cycles),
        .stat_mem_refills(stat1_mem_refills)
    );

    dcache_snoop_arb_3to1 snoop_arb (
        .clk(clk),
        .rst_n(rst_n),
        .req0_addr(32'h0),
        .req0_cmd(2'b00),
        .req0_valid(1'b0),
        .req0_ready(),
        .req0_resp_valid(),
        .req0_resp_hit(),
        .req0_resp_data(),
        .req1_addr(cpu1_miss_snoop_addr),
        .req1_cmd(cpu1_miss_snoop_cmd),
        .req1_valid(cpu1_miss_snoop_req_valid),
        .req1_ready(cpu1_miss_snoop_req_ready),
        .req1_resp_valid(cpu1_miss_snoop_resp_valid),
        .req1_resp_hit(cpu1_miss_snoop_resp_hit),
        .req1_resp_data(cpu1_miss_snoop_resp_data),
        .req2_addr(up_snoop_addr),
        .req2_cmd(up_snoop_cmd),
        .req2_valid(up_snoop_req_valid),
        .req2_ready(up_snoop_req_ready),
        .req2_resp_valid(up_snoop_resp_valid),
        .req2_resp_hit(up_snoop_resp_hit),
        .req2_resp_data(up_snoop_resp_data),
        .up_addr(bus_snoop_addr),
        .up_cmd(bus_snoop_cmd),
        .up_valid(bus_snoop_req_valid),
        .up_ready(bus_snoop_req_ready),
        .up_resp_valid(bus_snoop_resp_valid),
        .up_resp_hit(bus_snoop_resp_hit),
        .up_resp_data(bus_snoop_resp_data)
    );

    dcache_snoop_bus_2way snoop_bus (
        .clk(clk),
        .rst_n(rst_n),
        .up_snoop_addr(bus_snoop_addr),
        .up_snoop_cmd(bus_snoop_cmd),
        .up_snoop_req_valid(bus_snoop_req_valid),
        .up_snoop_req_ready(bus_snoop_req_ready),
        .up_snoop_resp_valid(bus_snoop_resp_valid),
        .up_snoop_resp_hit(bus_snoop_resp_hit),
        .up_snoop_resp_data(bus_snoop_resp_data),
        .dc0_snoop_addr(dc0_snoop_addr),
        .dc0_snoop_cmd(dc0_snoop_cmd),
        .dc0_snoop_req_valid(dc0_snoop_req_valid),
        .dc0_snoop_req_ready(dc0_snoop_req_ready),
        .dc0_snoop_resp_valid(dc0_snoop_resp_valid),
        .dc0_snoop_resp_hit(dc0_snoop_resp_hit),
        .dc0_snoop_resp_data(dc0_snoop_resp_data),
        .dc1_snoop_addr(dc1_snoop_addr),
        .dc1_snoop_cmd(dc1_snoop_cmd),
        .dc1_snoop_req_valid(dc1_snoop_req_valid),
        .dc1_snoop_req_ready(dc1_snoop_req_ready),
        .dc1_snoop_resp_valid(dc1_snoop_resp_valid),
        .dc1_snoop_resp_hit(dc1_snoop_resp_hit),
        .dc1_snoop_resp_data(dc1_snoop_resp_data)
    );

    initial begin
        pass_count = 0;
        fail_count = 0;
        wb0_count = 0;
        wb1_count = 0;
        rst_n = 1'b0;
        cpu0_addr = 0;
        cpu0_wdata = 0;
        cpu0_wstrb = 0;
        cpu0_req = 0;
        cpu0_we = 0;
        cpu0_fence_type = 0;
        cpu1_addr = 0;
        cpu1_wdata = 0;
        cpu1_wstrb = 0;
        cpu1_req = 0;
        cpu1_we = 0;
        cpu1_fence_type = 0;
        up_snoop_addr = 0;
        up_snoop_cmd = 0;
        up_snoop_req_valid = 0;
        mem0_arready = 1;
        mem0_awready = 1;
        mem0_wready = 1;
        mem0_rid = 0;
        mem0_rdata = 0;
        mem0_rresp = 0;
        mem0_rlast = 0;
        mem0_rvalid = 0;
        mem0_bid = 0;
        mem0_bresp = 0;
        mem0_bvalid = 0;
        mem1_arready = 1;
        mem1_awready = 1;
        mem1_wready = 1;
        mem1_rid = 0;
        mem1_rdata = 0;
        mem1_rresp = 0;
        mem1_rlast = 0;
        mem1_rvalid = 0;
        mem1_bid = 0;
        mem1_bresp = 0;
        mem1_bvalid = 0;

        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'h0;

        mem[midx(LINE_ADDR) + 0] = 32'h1111_0000;
        mem[midx(LINE_ADDR) + 1] = 32'h2222_0000;
        mem[midx(LINE_ADDR) + 2] = 32'h3333_0000;
        mem[midx(LINE_ADDR) + 3] = 32'h4444_0000;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        cpu0_read(LINE_ADDR, rd0);
        repeat (4) @(posedge clk);
        check(rd0 == 32'h1111_0000, "CPU0 refill gets baseline data");
        check(dcache0.tag_array_inst.states[8] == STATE_E, "CPU0 owns line in E after refill");
        check(dcache1.tag_array_inst.states[8] == STATE_I, "CPU1 line starts invalid");

        cpu0_write(LINE_ADDR, 32'haaaa_0001);
        cpu0_write(LINE_ADDR + 32'h4, 32'hbbbb_0002);
        @(posedge clk);
        check(dcache0.tag_array_inst.states[8] == STATE_M, "CPU0 write promotes line to M");

        issue_upstream_snoop(LINE_ADDR, 2'b01, snp_hit, snp_data);
        check(snp_hit === 1'b1, "protocol snoop-read hits latest owner");
        check(snp_data == 128'h4444_0000_3333_0000_bbbb_0002_aaaa_0001,
              "protocol snoop-read returns CPU0 modified line");
        check(dcache0.tag_array_inst.states[8] == STATE_M,
              "current RTL keeps dirty owner in M after snoop-read");
        check(dcache1.tag_array_inst.states[8] == STATE_I,
              "CPU1 cache stays invalid until it performs its own fill");

        cpu1_read(LINE_ADDR, rd1);
        repeat (8) @(posedge clk);
        check(wb0_count >= 1, "CPU1 read miss auto-snoop forces CPU0 dirty writeback");
        check(mem[midx(LINE_ADDR) + 0] == 32'haaaa_0001, "shared memory gets updated word 0");
        check(mem[midx(LINE_ADDR) + 1] == 32'hbbbb_0002, "shared memory gets updated word 1");
        check(dcache0.tag_array_inst.states[8] == STATE_I, "CPU0 line invalidates after CPU1 miss-snoop");
        check(rd1 == 32'haaaa_0001, "CPU1 observe sees CPU0 latest data");
        check(dcache1.tag_array_inst.states[8] == STATE_E, "CPU1 refill installs latest line after auto-snoop");
        check(stat1_peer_snoop_reqs == 1 && stat1_peer_snoop_hits == 1,
              "CPU1 records one peer snoop request and one hit");
        check(stat1_c2c_forwards == 1, "CPU1 read miss completes through direct cache-to-cache forwarding");
        check(stat1_mem_refills == 0, "CPU1 avoids memory refill on peer-forwarded miss");
        check(stat0_writes != 0 && stat1_misses != 0, "both caches participated in protocol flow");

        cpu1_write(LINE_ADDR + 32'h8, 32'hcccc_0003);
        repeat (4) @(posedge clk);
        check(dcache1.tag_array_inst.states[8] == STATE_M, "CPU1 write makes line modified for DMA checks");

        issue_upstream_snoop(LINE_ADDR, 2'b01, snp_hit, snp_data);
        check(snp_hit === 1'b1, "DMA-style coherent read snoop hits CPU1 owner");
        check(snp_data == 128'h4444_0000_cccc_0003_bbbb_0002_aaaa_0001,
              "DMA-style coherent read returns CPU1 latest line");

        issue_upstream_snoop(LINE_ADDR, 2'b10, snp_hit, snp_data);
        repeat (8) @(posedge clk);
        check(snp_hit === 1'b1, "DMA-style coherent write invalidate hits CPU1 owner");
        check(wb1_count >= 1, "DMA-style invalidate forces CPU1 dirty writeback");
        check(mem[midx(LINE_ADDR) + 2] == 32'hcccc_0003, "DMA-style invalidate updates shared memory word 2");
        check(dcache1.tag_array_inst.states[8] == STATE_I, "CPU1 line invalidates after DMA-style write");

        $display("SUMMARY: %0d PASS / %0d FAIL", pass_count, fail_count);
        if (fail_count != 0)
            $fatal(1);
        $finish;
    end

    reg [31:0] mem0_r_base;
    reg [2:0]  mem0_r_beat;
    reg [7:0]  mem0_r_len;
    reg        mem0_r_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem0_r_active <= 0;
            mem0_r_beat <= 0;
            mem0_r_len <= 0;
            mem0_rvalid <= 0;
            mem0_rlast <= 0;
            mem0_rdata <= 0;
        end else begin
            if (!mem0_r_active && mem0_arvalid) begin
                mem0_r_active <= 1'b1;
                mem0_r_beat <= 0;
                mem0_r_len <= mem0_arlen;
                mem0_r_base <= {mem0_araddr[31:4], 4'h0};
            end else if (mem0_r_active && (!mem0_rvalid || mem0_rready)) begin
                mem0_rvalid <= 1'b1;
                mem0_rdata <= mem[midx(mem0_r_base) + mem0_r_beat];
                mem0_rlast <= (mem0_r_beat == mem0_r_len[2:0]);
                if (mem0_r_beat == mem0_r_len[2:0]) begin
                    mem0_r_active <= 1'b0;
                end else begin
                    mem0_r_beat <= mem0_r_beat + 1'b1;
                end
            end else if (mem0_rvalid && mem0_rready) begin
                mem0_rvalid <= 1'b0;
                mem0_rlast <= 1'b0;
            end
        end
    end

    reg [31:0] mem0_w_base;
    reg [2:0]  mem0_w_beat;
    reg        mem0_w_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem0_w_base <= 0;
            mem0_w_beat <= 0;
            mem0_w_active <= 0;
            mem0_bvalid <= 0;
        end else begin
            if (!mem0_w_active && mem0_awvalid) begin
                mem0_w_active <= 1'b1;
                mem0_w_beat <= 0;
                mem0_w_base <= {mem0_awaddr[31:4], 4'h0};
                wb0_count <= wb0_count + 1;
            end
            if (mem0_w_active && mem0_wvalid) begin
                mem[midx(mem0_w_base) + mem0_w_beat] <= mem0_wdata;
                mem0_w_beat <= mem0_w_beat + 1'b1;
                if (mem0_wlast) begin
                    mem0_w_active <= 1'b0;
                    mem0_bvalid <= 1'b1;
                end
            end
            if (mem0_bvalid && mem0_bready)
                mem0_bvalid <= 1'b0;
        end
    end

    reg [31:0] mem1_r_base;
    reg [2:0]  mem1_r_beat;
    reg [7:0]  mem1_r_len;
    reg        mem1_r_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem1_r_active <= 0;
            mem1_r_beat <= 0;
            mem1_r_len <= 0;
            mem1_rvalid <= 0;
            mem1_rlast <= 0;
            mem1_rdata <= 0;
        end else begin
            if (!mem1_r_active && mem1_arvalid) begin
                mem1_r_active <= 1'b1;
                mem1_r_beat <= 0;
                mem1_r_len <= mem1_arlen;
                mem1_r_base <= {mem1_araddr[31:4], 4'h0};
            end else if (mem1_r_active && (!mem1_rvalid || mem1_rready)) begin
                mem1_rvalid <= 1'b1;
                mem1_rdata <= mem[midx(mem1_r_base) + mem1_r_beat];
                mem1_rlast <= (mem1_r_beat == mem1_r_len[2:0]);
                if (mem1_r_beat == mem1_r_len[2:0]) begin
                    mem1_r_active <= 1'b0;
                end else begin
                    mem1_r_beat <= mem1_r_beat + 1'b1;
                end
            end else if (mem1_rvalid && mem1_rready) begin
                mem1_rvalid <= 1'b0;
                mem1_rlast <= 1'b0;
            end
        end
    end

    reg [31:0] mem1_w_base;
    reg [2:0]  mem1_w_beat;
    reg        mem1_w_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem1_w_base <= 0;
            mem1_w_beat <= 0;
            mem1_w_active <= 0;
            mem1_bvalid <= 0;
        end else begin
            if (!mem1_w_active && mem1_awvalid) begin
                mem1_w_active <= 1'b1;
                mem1_w_beat <= 0;
                mem1_w_base <= {mem1_awaddr[31:4], 4'h0};
                wb1_count <= wb1_count + 1;
            end
            if (mem1_w_active && mem1_wvalid) begin
                mem[midx(mem1_w_base) + mem1_w_beat] <= mem1_wdata;
                mem1_w_beat <= mem1_w_beat + 1'b1;
                if (mem1_wlast) begin
                    mem1_w_active <= 1'b0;
                    mem1_bvalid <= 1'b1;
                end
            end
            if (mem1_bvalid && mem1_bready)
                mem1_bvalid <= 1'b0;
        end
    end

endmodule
