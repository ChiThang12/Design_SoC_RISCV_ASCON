`timescale 1ns/1ps

// ============================================================================
// tb_lsu_dcache_bughunt.v
//
// Focus:
//   - Reproduce LSU + DCache integration patterns behind C4 / C9
//   - Exercise sb/lbu on same word through LSU queues and drain FSM
//   - Check whether lsu_idle can rise before DCache data is fence-visible
//
// Run:
//   iverilog -g2012 -o /tmp/tb_lsu_dcache_bughunt.vvp \
//     cache_interface/tb/tb_lsu_dcache_bughunt.v
//   vvp /tmp/tb_lsu_dcache_bughunt.vvp
// ============================================================================

`include "cpu/core/LSU.v"
`include "cache_interface/dcache/dcache_top.v"

module tb_lsu_dcache_bughunt;

reg clk, rst;
initial clk = 1'b0;
always #5 clk = ~clk;

// ============================================================================
// LSU request/result side
// ============================================================================
reg         req_valid;
wire        req_ready;
reg  [31:0] req_addr;
reg  [31:0] req_wdata;
reg  [3:0]  req_wstrb;
reg         req_is_load;
reg  [4:0]  req_rd;
reg  [2:0]  req_funct3;
reg         fence_lsu;

wire        result_valid;
wire [31:0] result_data;
wire [4:0]  result_rd;
reg         result_ack;
wire [31:0] scoreboard;
wire        lsu_idle;

// ============================================================================
// LSU <-> DCache
// ============================================================================
wire        dcache_req;
wire        dcache_we;
wire [31:0] dcache_addr;
wire [31:0] dcache_wdata;
wire [3:0]  dcache_wstrb;
wire [31:0] dcache_rdata;
wire        dcache_ready;

// ============================================================================
// DCache <-> AXI memory model
// ============================================================================
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

LSU dut_lsu (
    .clk(clk),
    .rst(rst),
    .req_valid(req_valid),
    .req_ready(req_ready),
    .req_addr(req_addr),
    .req_wdata(req_wdata),
    .req_wstrb(req_wstrb),
    .req_is_load(req_is_load),
    .req_rd(req_rd),
    .req_funct3(req_funct3),
    .fence(fence_lsu),
    .result_valid(result_valid),
    .result_data(result_data),
    .result_rd(result_rd),
    .result_ack(result_ack),
    .scoreboard(scoreboard),
    .lsu_idle(lsu_idle),
    .dcache_req(dcache_req),
    .dcache_we(dcache_we),
    .dcache_addr(dcache_addr),
    .dcache_wdata(dcache_wdata),
    .dcache_wstrb(dcache_wstrb),
    .dcache_rdata(dcache_rdata),
    .dcache_ready(dcache_ready)
);

dcache_top #(.ID_WIDTH(4)) dut_dcache (
    .clk(clk),
    .rst_n(~rst),
    .cpu_addr(dcache_addr),
    .cpu_wdata(dcache_wdata),
    .cpu_wstrb(dcache_wstrb),
    .cpu_req(dcache_req),
    .cpu_we(dcache_we),
    .cpu_rdata(dcache_rdata),
    .cpu_ready(dcache_ready),
    .fence_type(fence_type),
    .current_addr(current_addr),
    .current_data(current_data),
    .current_valid(current_valid),
    .mem_arid(mem_arid),
    .mem_araddr(mem_araddr),
    .mem_arlen(mem_arlen),
    .mem_arsize(mem_arsize),
    .mem_arburst(mem_arburst),
    .mem_arprot(mem_arprot),
    .mem_arvalid(mem_arvalid),
    .mem_arready(mem_arready),
    .mem_rid(mem_rid),
    .mem_rdata(mem_rdata),
    .mem_rresp(mem_rresp),
    .mem_rlast(mem_rlast),
    .mem_rvalid(mem_rvalid),
    .mem_rready(mem_rready),
    .mem_awid(mem_awid),
    .mem_awaddr(mem_awaddr),
    .mem_awlen(mem_awlen),
    .mem_awsize(mem_awsize),
    .mem_awburst(mem_awburst),
    .mem_awprot(mem_awprot),
    .mem_awvalid(mem_awvalid),
    .mem_awready(mem_awready),
    .mem_wdata(mem_wdata_axi),
    .mem_wstrb(mem_wstrb),
    .mem_wlast(mem_wlast),
    .mem_wvalid(mem_wvalid),
    .mem_wready(mem_wready),
    .mem_bid(mem_bid),
    .mem_bresp(mem_bresp),
    .mem_bvalid(mem_bvalid),
    .mem_bready(mem_bready),
    .stat_hits(stat_hits),
    .stat_misses(stat_misses),
    .stat_writes(stat_writes)
);

// ============================================================================
// Debug probes
// ============================================================================
wire [1:0] probe_load_state     = dut_lsu.load_state;
wire       probe_drain_state    = dut_lsu.drain_state;
wire [2:0] probe_dc_state       = dut_dcache.controller_inst.state;
wire [2:0] probe_flush_state    = dut_dcache.controller_inst.flush_state;
wire       probe_flush_busy     = dut_dcache.controller_inst.flush_busy;
wire       probe_do_deferred    = dut_dcache.controller_inst.do_deferred_write;
wire       probe_dwe            = dut_dcache.data_write_enable;
wire [5:0] probe_dwi            = dut_dcache.data_write_index;
wire [1:0] probe_dwo            = dut_dcache.data_write_offset;
wire [31:0] probe_dwd           = dut_dcache.data_write_data;
wire [3:0]  probe_dwstrb        = dut_dcache.data_write_strb;
wire [63:0] probe_dirty_bitmap  = dut_dcache.controller_inst.dirty_bitmap;
wire [31:0] probe_ev_addr       = dut_dcache.evict_addr;
wire [31:0] probe_ev_d0         = dut_dcache.evict_data_0;
wire [31:0] probe_ev_d1         = dut_dcache.evict_data_1;
wire [31:0] probe_ev_d2         = dut_dcache.evict_data_2;
wire [31:0] probe_ev_d3         = dut_dcache.evict_data_3;
wire        probe_ev_start      = dut_dcache.evict_start;
wire [2:0]  probe_sb_count      = dut_lsu.sb_count;
wire [2:0]  probe_lq_count      = dut_lsu.lq_count;

// ============================================================================
// AXI memory model
// ============================================================================
reg [31:0] axi_mem [0:16383];

assign mem_arready = 1'b1;
assign mem_awready = 1'b1;
assign mem_wready  = 1'b1;

reg        r_active;
reg [31:0] r_base;
reg [2:0]  r_beat;
reg [2:0]  r_arlen;
reg [31:0] r_data_r;
reg        r_valid_r, r_last_r;

assign mem_rdata  = r_data_r;
assign mem_rvalid = r_valid_r;
assign mem_rlast  = r_last_r;
assign mem_rresp  = 2'b00;
assign mem_rid    = 4'h0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        r_active  <= 1'b0;
        r_base    <= 32'h0;
        r_beat    <= 3'd0;
        r_arlen   <= 3'd0;
        r_data_r  <= 32'h0;
        r_valid_r <= 1'b0;
        r_last_r  <= 1'b0;
    end else begin
        if (!r_active) begin
            if (mem_arvalid) begin
                r_active <= 1'b1;
                r_base   <= {mem_araddr[31:4], 4'h0};
                r_beat   <= 3'd0;
                r_arlen  <= mem_arlen[2:0];
            end
        end else if (!r_valid_r) begin
            r_data_r  <= axi_mem[midx({r_base[31:4], 4'h0}) + r_beat];
            r_valid_r <= 1'b1;
            r_last_r  <= (r_beat == r_arlen);
        end else if (mem_rready) begin
            if (r_last_r) begin
                r_active  <= 1'b0;
                r_valid_r <= 1'b0;
                r_last_r  <= 1'b0;
            end else begin
                r_beat   <= r_beat + 1'b1;
                r_data_r <= axi_mem[midx({r_base[31:4], 4'h0}) + r_beat + 1'b1];
                r_last_r <= (r_beat + 1'b1 == r_arlen);
            end
        end
    end
end

reg [31:0] cap_evict_addr;
reg [31:0] cap_d0, cap_d1, cap_d2, cap_d3;
reg [31:0] cap_base;
reg [2:0]  cap_beat;
reg        cap_in_prog;
reg        bvalid_r;

assign mem_bvalid = bvalid_r;
assign mem_bresp  = 2'b00;
assign mem_bid    = 4'h0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        cap_evict_addr <= 32'h0;
        cap_d0 <= 32'h0;
        cap_d1 <= 32'h0;
        cap_d2 <= 32'h0;
        cap_d3 <= 32'h0;
        cap_base <= 32'h0;
        cap_beat <= 3'd0;
        cap_in_prog <= 1'b0;
        bvalid_r <= 1'b0;
    end else begin
        if (!cap_in_prog && mem_awvalid) begin
            cap_evict_addr <= {mem_awaddr[31:4], 4'h0};
            cap_base       <= midx({mem_awaddr[31:4], 4'h0});
            cap_beat       <= 3'd0;
            cap_in_prog    <= 1'b1;
        end
        if (cap_in_prog && mem_wvalid) begin
            axi_mem[cap_base + cap_beat] <= merge_wstrb(
                axi_mem[cap_base + cap_beat], mem_wdata_axi, mem_wstrb
            );
            case (cap_beat)
                3'd0: cap_d0 <= mem_wdata_axi;
                3'd1: cap_d1 <= mem_wdata_axi;
                3'd2: cap_d2 <= mem_wdata_axi;
                3'd3: cap_d3 <= mem_wdata_axi;
            endcase
            cap_beat <= cap_beat + 1'b1;
            if (mem_wlast) begin
                cap_in_prog <= 1'b0;
                bvalid_r    <= 1'b1;
            end
        end
        if (bvalid_r && mem_bready)
            bvalid_r <= 1'b0;
    end
end

// ============================================================================
// Helpers
// ============================================================================
integer cyc;
integer total_pass, total_fail, i;
reg prev_lsu_idle;
reg [31:0] rd;
reg [31:0] exp0, exp1, exp2, exp3;

always @(posedge clk)
    cyc = cyc + 1;

always @(posedge clk or posedge rst) begin
    if (rst)
        prev_lsu_idle <= 1'b0;
    else
        prev_lsu_idle <= lsu_idle;
end

always @(posedge clk) begin
    if (!rst) begin
        if (probe_dwe) begin
            $display("[CYC%0d][DC_WR] dc_st=%0d idx=%0d off=%0d strb=%04b data=%08h",
                cyc, probe_dc_state, probe_dwi, probe_dwo, probe_dwstrb, probe_dwd);
        end
        if (probe_ev_start) begin
            $display("[CYC%0d][EVICT] addr=%08h {%08h %08h %08h %08h}",
                cyc, probe_ev_addr, probe_ev_d0, probe_ev_d1, probe_ev_d2, probe_ev_d3);
        end
        if (lsu_idle && !prev_lsu_idle) begin
            $display("[CYC%0d][LSU_IDLE↑] sb=%0d lq=%0d load_st=%0d drain_st=%0d dc_st=%0d deferred=%b",
                cyc, probe_sb_count, probe_lq_count, probe_load_state,
                probe_drain_state, probe_dc_state, probe_do_deferred);
        end
    end
end

function [13:0] midx;
    input [31:0] addr;
    begin
        midx = (addr - 32'h10000000) >> 2;
    end
endfunction

function [31:0] merge_wstrb;
    input [31:0] old_word;
    input [31:0] new_word;
    input [3:0]  strb;
    begin
        merge_wstrb = old_word;
        if (strb[0]) merge_wstrb[7:0]   = new_word[7:0];
        if (strb[1]) merge_wstrb[15:8]  = new_word[15:8];
        if (strb[2]) merge_wstrb[23:16] = new_word[23:16];
        if (strb[3]) merge_wstrb[31:24] = new_word[31:24];
    end
endfunction

function [31:0] byte_store_word;
    input [31:0] addr;
    input [7:0] data8;
    begin
        case (addr[1:0])
            2'd0: byte_store_word = {24'h0, data8};
            2'd1: byte_store_word = {16'h0, data8, 8'h0};
            2'd2: byte_store_word = {8'h0, data8, 16'h0};
            default: byte_store_word = {data8, 24'h0};
        endcase
    end
endfunction

function [3:0] byte_store_strb;
    input [31:0] addr;
    begin
        case (addr[1:0])
            2'd0: byte_store_strb = 4'b0001;
            2'd1: byte_store_strb = 4'b0010;
            2'd2: byte_store_strb = 4'b0100;
            default: byte_store_strb = 4'b1000;
        endcase
    end
endfunction

task chk;
    input [31:0] got;
    input [31:0] exp;
    input [255:0] name;
    begin
        if (got === exp) begin
            total_pass = total_pass + 1;
            $display("    PASS [%0s] got=%08h", name, got);
        end else begin
            total_fail = total_fail + 1;
            $display("    FAIL [%0s] got=%08h exp=%08h <<<", name, got, exp);
        end
    end
endtask

task tc_header;
    input [8*96-1:0] name;
    begin
        $display("");
        $display("============================================================");
        $display("%0s", name);
        $display("============================================================");
    end
endtask

task mem_set_line;
    input [31:0] base;
    input [31:0] w0, w1, w2, w3;
    begin
        axi_mem[midx(base)  ] = w0;
        axi_mem[midx(base)+1] = w1;
        axi_mem[midx(base)+2] = w2;
        axi_mem[midx(base)+3] = w3;
    end
endtask

task clear_caps;
    begin
        cap_evict_addr = 32'h0;
        cap_d0 = 32'h0;
        cap_d1 = 32'h0;
        cap_d2 = 32'h0;
        cap_d3 = 32'h0;
    end
endtask

task do_reset;
    begin
        rst        = 1'b1;
        req_valid  = 1'b0;
        req_addr   = 32'h0;
        req_wdata  = 32'h0;
        req_wstrb  = 4'h0;
        req_is_load= 1'b0;
        req_rd     = 5'd0;
        req_funct3 = 3'b010;
        fence_lsu  = 1'b0;
        result_ack = 1'b0;
        fence_type = 2'b00;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);
    end
endtask

task lsu_issue_store;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    integer tout;
    begin
        @(negedge clk);
        req_addr    = addr;
        req_wdata   = data;
        req_wstrb   = strb;
        req_is_load = 1'b0;
        req_rd      = 5'd0;
        req_funct3  = 3'b010;
        req_valid   = 1'b1;
        tout = 0;
        @(posedge clk);
        while (!req_ready && tout < 500) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 500)
            $display("[WARN] lsu_issue_store timeout addr=%08h cyc=%0d", addr, cyc);
        @(negedge clk);
        req_valid = 1'b0;
    end
endtask

task lsu_issue_load_and_expect;
    input [31:0] addr;
    input [4:0]  rd_id;
    input [2:0]  funct3;
    input [31:0] exp;
    input [255:0] name;
    integer tout;
    begin
        @(negedge clk);
        req_addr    = addr;
        req_wdata   = 32'h0;
        req_wstrb   = 4'h0;
        req_is_load = 1'b1;
        req_rd      = rd_id;
        req_funct3  = funct3;
        req_valid   = 1'b1;
        tout = 0;
        @(posedge clk);
        while (!req_ready && tout < 500) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 500)
            $display("[WARN] lsu_issue_load timeout addr=%08h cyc=%0d", addr, cyc);
        @(negedge clk);
        req_valid = 1'b0;

        tout = 0;
        while (!result_valid && tout < 1000) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 1000)
            $display("[WARN] result wait timeout addr=%08h cyc=%0d", addr, cyc);
        chk(result_data, exp, name);
        @(negedge clk);
        result_ack = 1'b1;
        @(posedge clk);
        @(negedge clk);
        result_ack = 1'b0;
    end
endtask

task lsu_store_byte;
    input [31:0] addr;
    input [7:0]  data8;
    begin
        lsu_issue_store(addr, byte_store_word(addr, data8), byte_store_strb(addr));
    end
endtask

task wait_lsu_idle;
    integer tout;
    begin
        tout = 0;
        while (!lsu_idle && tout < 2000) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 2000)
            $display("[WARN] wait_lsu_idle timeout cyc=%0d", cyc);
    end
endtask

task do_fence_flush_after_idle;
    integer tout;
    begin
        wait_lsu_idle();
        @(negedge clk);
        fence_type = 2'b01;
        tout = 0;
        while (!probe_flush_busy && tout < 50) begin
            @(posedge clk);
            tout = tout + 1;
        end
        tout = 0;
        while (probe_flush_busy && tout < 5000) begin
            @(posedge clk);
            tout = tout + 1;
        end
        @(negedge clk);
        fence_type = 2'b00;
        repeat (4) @(posedge clk);
    end
endtask

task check_mem_word;
    input [31:0] addr;
    input [31:0] exp;
    input [255:0] name;
    begin
        chk(axi_mem[midx(addr)], exp, name);
    end
endtask

// ============================================================================
// Main
// ============================================================================
initial begin
    $dumpfile("tb_lsu_dcache_bughunt.vcd");
    $dumpvars(0, tb_lsu_dcache_bughunt);

    cyc = 0;
    total_pass = 0;
    total_fail = 0;
    for (i = 0; i < 16384; i = i + 1)
        axi_mem[i] = 32'h0;

    do_reset();

    tc_header("LG01: LSU sb + lbu same byte on cold line");
    mem_set_line(32'h10000600, 32'h00000000, 32'h0, 32'h0, 32'h0);
    lsu_store_byte(32'h10000602, 8'h7A);
    lsu_issue_load_and_expect(32'h10000602, 5'd5, 3'b100, 32'h0000007A, "LG01 lbu");
    wait_lsu_idle();
    lsu_issue_load_and_expect(32'h10000600, 5'd6, 3'b010, 32'h007A0000, "LG01 lw merged");

    tc_header("LG02: C4-like edge/polarity locals through LSU");
    mem_set_line(32'h10000620, 32'h00000000, 32'h0, 32'h0, 32'h0);
    lsu_store_byte(32'h10000622, 8'h01);
    lsu_issue_load_and_expect(32'h10000622, 5'd7, 3'b100, 32'h00000001, "LG02 edge lbu");
    lsu_store_byte(32'h10000623, 8'h01);
    lsu_issue_load_and_expect(32'h10000623, 5'd8, 3'b100, 32'h00000001, "LG02 pol lbu");
    lsu_issue_load_and_expect(32'h10000620, 5'd9, 3'b010, 32'h01010000, "LG02 combined lw");

    tc_header("LG03: LSU C9-like 16 byte stores then immediate fence");
    mem_set_line(32'h10000330, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000);
    lsu_store_byte(32'h10000330, 8'h48);
    lsu_store_byte(32'h10000331, 8'h45);
    lsu_store_byte(32'h10000332, 8'h4C);
    lsu_store_byte(32'h10000333, 8'h4C);
    lsu_store_byte(32'h10000334, 8'h4F);
    lsu_store_byte(32'h10000335, 8'h20);
    lsu_store_byte(32'h10000336, 8'h44);
    lsu_store_byte(32'h10000337, 8'h4D);
    lsu_store_byte(32'h10000338, 8'h41);
    lsu_store_byte(32'h10000339, 8'h2D);
    lsu_store_byte(32'h1000033A, 8'h53);
    lsu_store_byte(32'h1000033B, 8'h4F);
    lsu_store_byte(32'h1000033C, 8'h43);
    lsu_store_byte(32'h1000033D, 8'h21);
    lsu_store_byte(32'h1000033E, 8'h0D);
    lsu_store_byte(32'h1000033F, 8'h0A);
    lsu_issue_load_and_expect(32'h10000330, 5'd10, 3'b010, 32'h4C4C4548, "LG03 cache word0");
    lsu_issue_load_and_expect(32'h10000334, 5'd11, 3'b010, 32'h4D44204F, "LG03 cache word1");
    lsu_issue_load_and_expect(32'h10000338, 5'd12, 3'b010, 32'h4F532D41, "LG03 cache word2");
    lsu_issue_load_and_expect(32'h1000033C, 5'd13, 3'b010, 32'h0A0D2143, "LG03 cache word3");
    clear_caps();
    do_fence_flush_after_idle();
    check_mem_word(32'h10000330, 32'h4C4C4548, "LG03 mem word0");
    check_mem_word(32'h10000334, 32'h4D44204F, "LG03 mem word1");
    check_mem_word(32'h10000338, 32'h4F532D41, "LG03 mem word2");
    check_mem_word(32'h1000033C, 32'h0A0D2143, "LG03 mem word3");

    tc_header("LG04: reordered C9 stores + immediate fence after lsu_idle rise");
    do_reset();
    mem_set_line(32'h10000330, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000);
    exp0 = 32'h00000000;
    exp1 = 32'h00000000;
    exp2 = 32'h00000000;
    exp3 = 32'h00000000;
    lsu_store_byte(32'h10000333, 8'h4C); exp0 = merge_wstrb(exp0, 32'h4C000000, 4'b1000);
    lsu_store_byte(32'h10000330, 8'h48); exp0 = merge_wstrb(exp0, 32'h00000048, 4'b0001);
    lsu_store_byte(32'h10000331, 8'h45); exp0 = merge_wstrb(exp0, 32'h00004500, 4'b0010);
    lsu_store_byte(32'h10000332, 8'h4C); exp0 = merge_wstrb(exp0, 32'h004C0000, 4'b0100);
    lsu_store_byte(32'h10000337, 8'h4D); exp1 = merge_wstrb(exp1, 32'h4D000000, 4'b1000);
    lsu_store_byte(32'h10000334, 8'h4F); exp1 = merge_wstrb(exp1, 32'h0000004F, 4'b0001);
    lsu_store_byte(32'h10000335, 8'h20); exp1 = merge_wstrb(exp1, 32'h00002000, 4'b0010);
    lsu_store_byte(32'h10000336, 8'h44); exp1 = merge_wstrb(exp1, 32'h00440000, 4'b0100);
    lsu_store_byte(32'h1000033A, 8'h53); exp2 = merge_wstrb(exp2, 32'h00530000, 4'b0100);
    lsu_store_byte(32'h10000339, 8'h2D); exp2 = merge_wstrb(exp2, 32'h00002D00, 4'b0010);
    lsu_store_byte(32'h10000338, 8'h41); exp2 = merge_wstrb(exp2, 32'h00000041, 4'b0001);
    lsu_store_byte(32'h1000033B, 8'h4F); exp2 = merge_wstrb(exp2, 32'h4F000000, 4'b1000);
    lsu_store_byte(32'h1000033C, 8'h43); exp3 = merge_wstrb(exp3, 32'h00000043, 4'b0001);
    lsu_store_byte(32'h1000033F, 8'h0A); exp3 = merge_wstrb(exp3, 32'h0A000000, 4'b1000);
    lsu_store_byte(32'h1000033E, 8'h0D); exp3 = merge_wstrb(exp3, 32'h000D0000, 4'b0100);
    lsu_store_byte(32'h1000033D, 8'h21); exp3 = merge_wstrb(exp3, 32'h00002100, 4'b0010);
    clear_caps();
    do_fence_flush_after_idle();
    check_mem_word(32'h10000330, exp0, "LG04 mem word0");
    check_mem_word(32'h10000334, exp1, "LG04 mem word1");
    check_mem_word(32'h10000338, exp2, "LG04 mem word2");
    check_mem_word(32'h1000033C, exp3, "LG04 mem word3");

    $display("");
    $display("============================================================");
    $display("SUMMARY: PASS=%0d FAIL=%0d TOTAL=%0d", total_pass, total_fail, total_pass + total_fail);
    $display("stats: hits=%0d misses=%0d writes=%0d", stat_hits, stat_misses, stat_writes);
    $display("============================================================");
    $finish;
end

initial begin
    #20_000_000;
    $display("[WATCHDOG] timeout");
    $finish;
end

endmodule
