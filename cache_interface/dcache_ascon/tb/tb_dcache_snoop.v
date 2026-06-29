`timescale 1ns/1ps
`include "cache_interface/dcache_ascon/dcache_top.v"

module tb_dcache_snoop;
    localparam [1:0] STATE_I = 2'b00;
    localparam [1:0] STATE_S = 2'b01;
    localparam [1:0] STATE_E = 2'b10;
    localparam [1:0] STATE_M = 2'b11;

    reg clk, rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg  [31:0] cpu_addr, cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    reg         cpu_req, cpu_we;
    wire [31:0] cpu_rdata;
    wire        cpu_ready;
    reg  [1:0]  fence_type;

    wire [31:0] current_addr, current_data;
    wire        current_valid;

    wire [3:0]  mem_arid, mem_awid;
    reg  [3:0]  mem_rid, mem_bid;
    wire [31:0] mem_araddr, mem_awaddr, mem_wdata;
    reg  [31:0] mem_rdata;
    wire [7:0]  mem_arlen, mem_awlen;
    wire [2:0]  mem_arsize, mem_awsize, mem_arprot, mem_awprot;
    wire [1:0]  mem_arburst, mem_awburst;
    reg  [1:0]  mem_rresp, mem_bresp;
    wire        mem_arvalid, mem_awvalid, mem_wvalid, mem_wlast;
    reg         mem_arready, mem_awready, mem_wready;
    reg         mem_rvalid, mem_rlast, mem_bvalid;
    wire        mem_rready, mem_bready;
    wire [3:0]  mem_wstrb;

    reg  [31:0] dc_snoop_addr;
    reg  [1:0]  dc_snoop_cmd;
    reg         dc_snoop_req_valid;
    wire        dc_snoop_req_ready;
    wire        dc_snoop_resp_valid;
    wire        dc_snoop_resp_hit;
    wire [127:0] dc_snoop_resp_data;

    wire [31:0] stat_hits, stat_misses, stat_writes;

    dcache_top #(.ID_WIDTH(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .fence_type(fence_type),
        .miss_snoop_enable(1'b0),
        .current_addr(current_addr), .current_data(current_data), .current_valid(current_valid),
        .mem_arid(mem_arid), .mem_araddr(mem_araddr), .mem_arlen(mem_arlen),
        .mem_arsize(mem_arsize), .mem_arburst(mem_arburst), .mem_arprot(mem_arprot),
        .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
        .mem_rid(mem_rid), .mem_rdata(mem_rdata), .mem_rresp(mem_rresp),
        .mem_rlast(mem_rlast), .mem_rvalid(mem_rvalid), .mem_rready(mem_rready),
        .mem_awid(mem_awid), .mem_awaddr(mem_awaddr), .mem_awlen(mem_awlen),
        .mem_awsize(mem_awsize), .mem_awburst(mem_awburst), .mem_awprot(mem_awprot),
        .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_wlast(mem_wlast),
        .mem_wvalid(mem_wvalid), .mem_wready(mem_wready),
        .mem_bid(mem_bid), .mem_bresp(mem_bresp), .mem_bvalid(mem_bvalid), .mem_bready(mem_bready),
        .dc_snoop_addr(dc_snoop_addr), .dc_snoop_cmd(dc_snoop_cmd),
        .dc_snoop_req_valid(dc_snoop_req_valid), .dc_snoop_req_ready(dc_snoop_req_ready),
        .dc_snoop_resp_valid(dc_snoop_resp_valid), .dc_snoop_resp_hit(dc_snoop_resp_hit),
        .dc_snoop_resp_data(dc_snoop_resp_data),
        .miss_snoop_addr(), .miss_snoop_cmd(), .miss_snoop_req_valid(),
        .miss_snoop_req_ready(1'b0), .miss_snoop_resp_valid(1'b0),
        .miss_snoop_resp_hit(1'b0), .miss_snoop_resp_data(128'h0),
        .stat_hits(stat_hits), .stat_misses(stat_misses), .stat_writes(stat_writes),
        .stat_peer_snoop_reqs(), .stat_peer_snoop_hits(), .stat_c2c_forwards(),
        .stat_c2c_fill_cycles(), .stat_mem_refills()
    );

    reg [31:0] mem [0:1023];
    integer pass_count, fail_count;
    integer wb_count;

    function [9:0] midx;
        input [31:0] addr;
        begin
            midx = addr[11:2];
        end
    endfunction

    task check;
        input cond;
        input [8*64-1:0] msg;
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

    task cpu_read;
        input [31:0] addr;
        output [31:0] data;
        integer timeout;
        begin
            @(posedge clk);
            cpu_addr <= addr; cpu_we <= 1'b0; cpu_wdata <= 32'h0; cpu_wstrb <= 4'h0; cpu_req <= 1'b1;
            timeout = 0;
            while (!cpu_ready && timeout < 200) begin @(posedge clk); timeout = timeout + 1; end
            data = cpu_rdata;
            cpu_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        integer timeout;
        begin
            @(posedge clk);
            cpu_addr <= addr; cpu_we <= 1'b1; cpu_wdata <= data; cpu_wstrb <= 4'hf; cpu_req <= 1'b1;
            timeout = 0;
            while (!cpu_ready && timeout < 200) begin @(posedge clk); timeout = timeout + 1; end
            cpu_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task snoop;
        input [31:0] addr;
        input [1:0]  cmd;
        output       hit;
        output [127:0] data;
        integer timeout;
        begin
            @(posedge clk);
            dc_snoop_addr <= addr; dc_snoop_cmd <= cmd; dc_snoop_req_valid <= 1'b1;
            timeout = 0;
            while (!dc_snoop_req_ready && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
            @(posedge clk);
            dc_snoop_req_valid <= 1'b0;
            timeout = 0;
            while (!dc_snoop_resp_valid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
            hit = dc_snoop_resp_hit;
            data = dc_snoop_resp_data;
            @(posedge clk);
        end
    endtask

    reg [31:0] rd;
    reg        snp_hit;
    reg [127:0] snp_data;

    integer i;
    initial begin
        pass_count = 0; fail_count = 0; wb_count = 0;
        rst_n = 1'b0;
        cpu_addr = 0; cpu_wdata = 0; cpu_wstrb = 0; cpu_req = 0; cpu_we = 0; fence_type = 0;
        dc_snoop_addr = 0; dc_snoop_cmd = 0; dc_snoop_req_valid = 0;
        mem_arready = 1; mem_awready = 1; mem_wready = 1;
        mem_rid = 0; mem_rdata = 0; mem_rresp = 0; mem_rlast = 0; mem_rvalid = 0;
        mem_bid = 0; mem_bresp = 0; mem_bvalid = 0;
        for (i = 0; i < 1024; i = i + 1) mem[i] = 32'h0;
        mem[midx(32'h1000_0080) + 0] = 32'h1111_0000;
        mem[midx(32'h1000_0080) + 1] = 32'h2222_0000;
        mem[midx(32'h1000_0080) + 2] = 32'h3333_0000;
        mem[midx(32'h1000_0080) + 3] = 32'h4444_0000;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        cpu_read(32'h1000_0080, rd);
        repeat (4) @(posedge clk);
        check(rd == 32'h1111_0000, "initial refill read");
        check(dut.tag_array_inst.states[8] == STATE_E, "refill installs line in exclusive state");
        cpu_write(32'h1000_0080, 32'haaaa_0001);
        cpu_write(32'h1000_0084, 32'hbbbb_0002);
        @(posedge clk);
        check(dut.tag_array_inst.states[8] == STATE_M, "local writes promote line to modified state");

        snoop(32'h1000_0080, 2'b01, snp_hit, snp_data);
        check(snp_hit === 1'b1, "snoop read hits dirty cache line");
        check(snp_data == 128'h4444_0000_3333_0000_bbbb_0002_aaaa_0001, "snoop read returns full cache line");
        check(dut.tag_array_inst.states[8] == STATE_M, "dirty owner keeps modified state after snoop read");

        snoop(32'h1000_0080, 2'b10, snp_hit, snp_data);
        check(snp_hit === 1'b1, "snoop invalidate hits line");
        repeat (8) @(posedge clk);
        check(wb_count >= 1, "dirty snoop invalidate issues writeback");
        check(mem[midx(32'h1000_0080) + 0] == 32'haaaa_0001, "writeback preserves dirty word 0");
        check(mem[midx(32'h1000_0080) + 1] == 32'hbbbb_0002, "writeback preserves dirty word 1");
        check(mem[midx(32'h1000_0080) + 2] == 32'h3333_0000, "writeback preserves clean word 2");
        check(mem[midx(32'h1000_0080) + 3] == 32'h4444_0000, "writeback preserves clean word 3");
        check(dut.tag_array_inst.states[8] == STATE_I, "invalidate clears cache line state");
        snoop(32'h1000_0080, 2'b01, snp_hit, snp_data);
        check(snp_hit === 1'b0, "snoop read misses after invalidate");

        $display("SUMMARY: %0d PASS / %0d FAIL", pass_count, fail_count);
        if (fail_count != 0) $fatal(1);
        $finish;
    end

    reg [31:0] r_base;
    reg [2:0]  r_beat;
    reg [7:0]  r_len;
    reg        r_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_active <= 0; r_beat <= 0; r_len <= 0; mem_rvalid <= 0; mem_rlast <= 0; mem_rdata <= 0;
        end else begin
            if (!r_active && mem_arvalid) begin
                r_active <= 1'b1; r_beat <= 0; r_len <= mem_arlen; r_base <= {mem_araddr[31:4], 4'h0};
            end else if (r_active && (!mem_rvalid || mem_rready)) begin
                mem_rvalid <= 1'b1;
                mem_rdata <= mem[midx(r_base) + r_beat];
                mem_rlast <= (r_beat == r_len[2:0]);
                if (r_beat == r_len[2:0]) begin
                    r_active <= 1'b0;
                end else begin
                    r_beat <= r_beat + 1'b1;
                end
            end else if (mem_rvalid && mem_rready) begin
                mem_rvalid <= 1'b0;
                mem_rlast <= 1'b0;
            end
        end
    end

    reg [31:0] w_base;
    reg [2:0]  w_beat;
    reg        w_active;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_base <= 0; w_beat <= 0; w_active <= 0; mem_bvalid <= 0;
        end else begin
            if (!w_active && mem_awvalid) begin
                w_active <= 1'b1; w_beat <= 0; w_base <= {mem_awaddr[31:4], 4'h0}; wb_count <= wb_count + 1;
            end
            if (w_active && mem_wvalid) begin
                mem[midx(w_base) + w_beat] <= mem_wdata;
                w_beat <= w_beat + 1'b1;
                if (mem_wlast) begin
                    w_active <= 1'b0;
                    mem_bvalid <= 1'b1;
                end
            end
            if (mem_bvalid && mem_bready) mem_bvalid <= 1'b0;
        end
    end
endmodule
