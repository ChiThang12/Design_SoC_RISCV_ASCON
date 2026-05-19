`timescale 1ns/1ps

// ============================================================================
// tb_dcache_bughunt.v
//
// Focus:
//   - Reproduce C4-like stack byte-store patterns
//   - Reproduce C9-like 16x byte-store + fence/writeback pattern
//   - Separate "cache-visible wrong" from "writeback wrong"
//
// Run:
//   iverilog -g2012 -o /tmp/tb_dcache_bughunt.vvp cache_interface/tb/tb_dcache_bughunt.v
//   vvp /tmp/tb_dcache_bughunt.vvp
// ============================================================================

`include "cache_interface/dcache/dcache_top.v"

module tb_dcache_bughunt;

reg clk, rst_n;
initial clk = 1'b0;
always #5 clk = ~clk;

reg  [31:0] cpu_addr, cpu_wdata;
reg  [3:0]  cpu_wstrb;
reg         cpu_req, cpu_we;
reg  [1:0]  fence_type;
wire [31:0] cpu_rdata;
wire        cpu_ready;

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
    .clk(clk),
    .rst_n(rst_n),
    .cpu_addr(cpu_addr),
    .cpu_wdata(cpu_wdata),
    .cpu_wstrb(cpu_wstrb),
    .cpu_req(cpu_req),
    .cpu_we(cpu_we),
    .cpu_rdata(cpu_rdata),
    .cpu_ready(cpu_ready),
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

wire [2:0] probe_state        = dut.controller_inst.state;
wire [2:0] probe_flush_state  = dut.controller_inst.flush_state;
wire [5:0] probe_flush_index  = dut.controller_inst.flush_index;
wire       probe_flush_busy   = dut.controller_inst.flush_busy;
wire       probe_dwe          = dut.data_write_enable;
wire [5:0] probe_dwi          = dut.data_write_index;
wire [1:0] probe_dwo          = dut.data_write_offset;
wire [31:0] probe_dwd         = dut.data_write_data;
wire [3:0] probe_dwstrb       = dut.data_write_strb;
wire       probe_tag_hit      = dut.tag_hit;
wire       probe_tag_dirty    = dut.tag_dirty_out;
wire [63:0] probe_dirty_bitmap = dut.controller_inst.dirty_bitmap;
wire       probe_do_deferred  = dut.controller_inst.do_deferred_write;
wire [5:0] probe_def_index    = dut.controller_inst.deferred_index;
wire [1:0] probe_def_offset   = dut.controller_inst.deferred_offset;
wire [31:0] probe_def_wdata   = dut.controller_inst.deferred_wdata;
wire [3:0] probe_def_wstrb    = dut.controller_inst.deferred_wstrb;
wire [31:0] probe_ev_addr     = dut.evict_addr;
wire [31:0] probe_ev_d0       = dut.evict_data_0;
wire [31:0] probe_ev_d1       = dut.evict_data_1;
wire [31:0] probe_ev_d2       = dut.evict_data_2;
wire [31:0] probe_ev_d3       = dut.evict_data_3;
wire       probe_ev_start     = dut.evict_start;
wire       probe_ev_done      = dut.evict_done;

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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cap_evict_addr <= 32'h0;
        cap_d0         <= 32'h0;
        cap_d1         <= 32'h0;
        cap_d2         <= 32'h0;
        cap_d3         <= 32'h0;
        cap_base       <= 32'h0;
        cap_beat       <= 3'd0;
        cap_in_prog    <= 1'b0;
        bvalid_r       <= 1'b0;
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

integer cyc;
integer total_pass;
integer total_fail;
integer i;
integer sidx;
reg [31:0] rd;
reg [31:0] expected_word;
reg [31:0] exp0, exp1, exp2, exp3;
reg [31:0] stream_addr [0:15];
reg [7:0]  stream_data [0:15];

initial begin
    cyc = 0;
    total_pass = 0;
    total_fail = 0;
end

always @(posedge clk)
    cyc = cyc + 1;

always @(posedge clk) begin
    if (probe_dwe) begin
        $display("[CYC%0d][DWR] state=%0d idx=%0d off=%0d strb=%04b data=%08h hit=%b dirty=%b",
            cyc, probe_state, probe_dwi, probe_dwo, probe_dwstrb, probe_dwd,
            probe_tag_hit, probe_tag_dirty);
    end
    if (probe_do_deferred) begin
        $display("[CYC%0d][DEF] idx=%0d off=%0d strb=%04b data=%08h",
            cyc, probe_def_index, probe_def_offset, probe_def_wstrb, probe_def_wdata);
    end
    if (probe_ev_start) begin
        $display("[CYC%0d][EVICT] addr=%08h {%08h %08h %08h %08h}",
            cyc, probe_ev_addr, probe_ev_d0, probe_ev_d1, probe_ev_d2, probe_ev_d3);
    end
    if (probe_flush_busy) begin
        $display("[CYC%0d][FLUSH] state=%0d idx=%0d bitmap=%016h ev_done=%b",
            cyc, probe_flush_state, probe_flush_index, probe_dirty_bitmap, probe_ev_done);
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
    input [7:0]  data8;
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

task clear_captures;
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
        rst_n      = 1'b0;
        cpu_addr   = 32'h0;
        cpu_wdata  = 32'h0;
        cpu_wstrb  = 4'hF;
        cpu_req    = 1'b0;
        cpu_we     = 1'b0;
        fence_type = 2'b00;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
    end
endtask

task cpu_write_word;
    input [31:0] addr;
    input [31:0] data;
    input [3:0]  strb;
    integer tout;
    begin
        @(negedge clk);
        cpu_addr  = addr;
        cpu_wdata = data;
        cpu_wstrb = strb;
        cpu_req   = 1'b1;
        cpu_we    = 1'b1;
        tout = 0;
        @(posedge clk);
        while (!cpu_ready && tout < 500) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 500)
            $display("[WARN] cpu_write_word timeout addr=%08h cyc=%0d", addr, cyc);
        @(negedge clk);
        cpu_req = 1'b0;
        cpu_we  = 1'b0;
    end
endtask

task cpu_store_byte;
    input [31:0] addr;
    input [7:0]  data8;
    begin
        cpu_write_word(addr, byte_store_word(addr, data8), byte_store_strb(addr));
    end
endtask

task cpu_store_stream16;
    integer idx;
    integer tout;
    begin
        idx = 0;
        @(negedge clk);
        cpu_addr  = stream_addr[0];
        cpu_wdata = byte_store_word(stream_addr[0], stream_data[0]);
        cpu_wstrb = byte_store_strb(stream_addr[0]);
        cpu_req   = 1'b1;
        cpu_we    = 1'b1;
        while (idx < 16) begin
            tout = 0;
            @(posedge clk);
            while (!cpu_ready && tout < 500) begin
                @(posedge clk);
                tout = tout + 1;
            end
            if (tout >= 500)
                $display("[WARN] cpu_store_stream16 timeout idx=%0d addr=%08h cyc=%0d",
                    idx, stream_addr[idx], cyc);
            idx = idx + 1;
            @(negedge clk);
            if (idx < 16) begin
                cpu_addr  = stream_addr[idx];
                cpu_wdata = byte_store_word(stream_addr[idx], stream_data[idx]);
                cpu_wstrb = byte_store_strb(stream_addr[idx]);
                cpu_req   = 1'b1;
                cpu_we    = 1'b1;
            end else begin
                cpu_req   = 1'b0;
                cpu_we    = 1'b0;
            end
        end
    end
endtask

task cpu_read_word;
    input [31:0] addr;
    output [31:0] data;
    integer tout;
    begin
        @(negedge clk);
        cpu_addr  = addr;
        cpu_wstrb = 4'hF;
        cpu_req   = 1'b1;
        cpu_we    = 1'b0;
        tout = 0;
        @(posedge clk);
        while (!cpu_ready && tout < 500) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 500)
            $display("[WARN] cpu_read_word timeout addr=%08h cyc=%0d", addr, cyc);
        data = cpu_rdata;
        @(negedge clk);
        cpu_req = 1'b0;
    end
endtask

task do_fence_flush;
    integer tout;
    begin
        @(negedge clk);
        fence_type = 2'b01;
        repeat (2) @(posedge clk);
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
        if (tout >= 5000)
            $display("[WARN] fence flush timeout cyc=%0d", cyc);
        @(negedge clk);
        fence_type = 2'b00;
        repeat (6) @(posedge clk);
    end
endtask

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

task check_mem_word;
    input [31:0] addr;
    input [31:0] exp;
    input [255:0] name;
    begin
        chk(axi_mem[midx(addr)], exp, name);
    end
endtask

initial begin
    $dumpfile("tb_dcache_bughunt.vcd");
    $dumpvars(0, tb_dcache_bughunt);

    for (i = 0; i < 16384; i = i + 1)
        axi_mem[i] = 32'h0;

    do_reset();

    tc_header("BG01: byte write hit + immediate readback same word");
    mem_set_line(32'h10000400, 32'h11223344, 32'h0, 32'h0, 32'h0);
    cpu_read_word(32'h10000400, rd);
    chk(rd, 32'h11223344, "BG01 refill");
    cpu_store_byte(32'h10000401, 8'hAA);
    cpu_read_word(32'h10000400, rd);
    chk(rd, 32'h1122AA44, "BG01 post-byte-read");

    tc_header("BG02: C4-like stack locals, two byte stores in same word");
    mem_set_line(32'h10000420, 32'h00000000, 32'h0, 32'h0, 32'h0);
    cpu_store_byte(32'h10000422, 8'h01);
    cpu_read_word(32'h10000420, rd);
    chk(rd, 32'h00010000, "BG02 after edge=1");
    cpu_store_byte(32'h10000423, 8'h01);
    cpu_read_word(32'h10000420, rd);
    chk(rd, 32'h01010000, "BG02 after polarity=1");
    cpu_store_byte(32'h10000422, 8'h00);
    cpu_read_word(32'h10000420, rd);
    chk(rd, 32'h01000000, "BG02 clear edge only");

    tc_header("BG03: byte write-allocate on cold line with mixed offsets");
    mem_set_line(32'h10000440, 32'hAABBCCDD, 32'h01020304, 32'h0, 32'h0);
    cpu_store_byte(32'h10000443, 8'h11);
    cpu_store_byte(32'h10000440, 8'h22);
    cpu_store_byte(32'h10000441, 8'h33);
    cpu_store_byte(32'h10000442, 8'h44);
    cpu_read_word(32'h10000440, rd);
    chk(rd, 32'h11443322, "BG03 merged cold-line word");

    tc_header("BG04: C9 pre-fence cache-visible message build");
    mem_set_line(32'h10000330, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000);
    cpu_store_byte(32'h10000330, 8'h48);
    cpu_store_byte(32'h10000331, 8'h45);
    cpu_store_byte(32'h10000332, 8'h4C);
    cpu_store_byte(32'h10000333, 8'h4C);
    cpu_store_byte(32'h10000334, 8'h4F);
    cpu_store_byte(32'h10000335, 8'h20);
    cpu_store_byte(32'h10000336, 8'h44);
    cpu_store_byte(32'h10000337, 8'h4D);
    cpu_store_byte(32'h10000338, 8'h41);
    cpu_store_byte(32'h10000339, 8'h2D);
    cpu_store_byte(32'h1000033A, 8'h53);
    cpu_store_byte(32'h1000033B, 8'h4F);
    cpu_store_byte(32'h1000033C, 8'h43);
    cpu_store_byte(32'h1000033D, 8'h21);
    cpu_store_byte(32'h1000033E, 8'h0D);
    cpu_store_byte(32'h1000033F, 8'h0A);
    cpu_read_word(32'h10000330, rd);
    chk(rd, 32'h4C4C4548, "BG04 cache word0 HELL");
    cpu_read_word(32'h10000334, rd);
    chk(rd, 32'h4D44204F, "BG04 cache word1 O DM");
    cpu_read_word(32'h10000338, rd);
    chk(rd, 32'h4F532D41, "BG04 cache word2 A-SO");
    cpu_read_word(32'h1000033C, rd);
    chk(rd, 32'h0A0D2143, "BG04 cache word3 C!CRLF");

    tc_header("BG05: C9 post-fence writeback visibility to external memory");
    clear_captures();
    do_fence_flush();
    check_mem_word(32'h10000330, 32'h4C4C4548, "BG05 mem word0");
    check_mem_word(32'h10000334, 32'h4D44204F, "BG05 mem word1");
    check_mem_word(32'h10000338, 32'h4F532D41, "BG05 mem word2");
    check_mem_word(32'h1000033C, 32'h0A0D2143, "BG05 mem word3");

    tc_header("BG06: dirty conflict eviction after byte-updated line");
    mem_set_line(32'h10000500, 32'hFFFFFFFF, 32'hEEEEEEEE, 32'hDDDDDDDD, 32'hCCCCCCCC);
    cpu_store_byte(32'h10000500, 8'h10);
    cpu_store_byte(32'h10000501, 8'h20);
    cpu_store_byte(32'h10000502, 8'h30);
    cpu_store_byte(32'h10000503, 8'h40);
    mem_set_line(32'h10001500, 32'h12345678, 32'h87654321, 32'hA5A5A5A5, 32'h5A5A5A5A);
    cpu_read_word(32'h10001500, rd);
    chk(rd, 32'h12345678, "BG06 conflict refill");
    check_mem_word(32'h10000500, 32'h40302010, "BG06 evicted word0");
    check_mem_word(32'h10000504, 32'hEEEEEEEE, "BG06 evicted word1");

    tc_header("BG07: repeated C9 line rebuild after reset");
    do_reset();
    mem_set_line(32'h10000330, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000);
    exp0 = 32'h00000000;
    exp1 = 32'h00000000;
    exp2 = 32'h00000000;
    exp3 = 32'h00000000;
    cpu_store_byte(32'h10000333, 8'h4C); exp0 = merge_wstrb(exp0, 32'h4C000000, 4'b1000);
    cpu_store_byte(32'h10000330, 8'h48); exp0 = merge_wstrb(exp0, 32'h00000048, 4'b0001);
    cpu_store_byte(32'h10000331, 8'h45); exp0 = merge_wstrb(exp0, 32'h00004500, 4'b0010);
    cpu_store_byte(32'h10000332, 8'h4C); exp0 = merge_wstrb(exp0, 32'h004C0000, 4'b0100);
    cpu_store_byte(32'h10000337, 8'h4D); exp1 = merge_wstrb(exp1, 32'h4D000000, 4'b1000);
    cpu_store_byte(32'h10000334, 8'h4F); exp1 = merge_wstrb(exp1, 32'h0000004F, 4'b0001);
    cpu_store_byte(32'h10000335, 8'h20); exp1 = merge_wstrb(exp1, 32'h00002000, 4'b0010);
    cpu_store_byte(32'h10000336, 8'h44); exp1 = merge_wstrb(exp1, 32'h00440000, 4'b0100);
    cpu_store_byte(32'h1000033A, 8'h53); exp2 = merge_wstrb(exp2, 32'h00530000, 4'b0100);
    cpu_store_byte(32'h10000339, 8'h2D); exp2 = merge_wstrb(exp2, 32'h00002D00, 4'b0010);
    cpu_store_byte(32'h10000338, 8'h41); exp2 = merge_wstrb(exp2, 32'h00000041, 4'b0001);
    cpu_store_byte(32'h1000033B, 8'h4F); exp2 = merge_wstrb(exp2, 32'h4F000000, 4'b1000);
    cpu_store_byte(32'h1000033C, 8'h43); exp3 = merge_wstrb(exp3, 32'h00000043, 4'b0001);
    cpu_store_byte(32'h1000033F, 8'h0A); exp3 = merge_wstrb(exp3, 32'h0A000000, 4'b1000);
    cpu_store_byte(32'h1000033E, 8'h0D); exp3 = merge_wstrb(exp3, 32'h000D0000, 4'b0100);
    cpu_store_byte(32'h1000033D, 8'h21); exp3 = merge_wstrb(exp3, 32'h00002100, 4'b0010);
    cpu_read_word(32'h10000330, rd); chk(rd, exp0, "BG07 cache word0");
    cpu_read_word(32'h10000334, rd); chk(rd, exp1, "BG07 cache word1");
    cpu_read_word(32'h10000338, rd); chk(rd, exp2, "BG07 cache word2");
    cpu_read_word(32'h1000033C, rd); chk(rd, exp3, "BG07 cache word3");
    do_fence_flush();
    check_mem_word(32'h10000330, exp0, "BG07 mem word0");
    check_mem_word(32'h10000334, exp1, "BG07 mem word1");
    check_mem_word(32'h10000338, exp2, "BG07 mem word2");
    check_mem_word(32'h1000033C, exp3, "BG07 mem word3");

    tc_header("BG08: continuous request stream, no idle gap between stores");
    do_reset();
    mem_set_line(32'h10000330, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000);
    stream_addr[0]  = 32'h10000330; stream_data[0]  = 8'h48;
    stream_addr[1]  = 32'h10000331; stream_data[1]  = 8'h45;
    stream_addr[2]  = 32'h10000332; stream_data[2]  = 8'h4C;
    stream_addr[3]  = 32'h10000333; stream_data[3]  = 8'h4C;
    stream_addr[4]  = 32'h10000334; stream_data[4]  = 8'h4F;
    stream_addr[5]  = 32'h10000335; stream_data[5]  = 8'h20;
    stream_addr[6]  = 32'h10000336; stream_data[6]  = 8'h44;
    stream_addr[7]  = 32'h10000337; stream_data[7]  = 8'h4D;
    stream_addr[8]  = 32'h10000338; stream_data[8]  = 8'h41;
    stream_addr[9]  = 32'h10000339; stream_data[9]  = 8'h2D;
    stream_addr[10] = 32'h1000033A; stream_data[10] = 8'h53;
    stream_addr[11] = 32'h1000033B; stream_data[11] = 8'h4F;
    stream_addr[12] = 32'h1000033C; stream_data[12] = 8'h43;
    stream_addr[13] = 32'h1000033D; stream_data[13] = 8'h21;
    stream_addr[14] = 32'h1000033E; stream_data[14] = 8'h0D;
    stream_addr[15] = 32'h1000033F; stream_data[15] = 8'h0A;
    cpu_store_stream16();
    cpu_read_word(32'h10000330, rd); chk(rd, 32'h4C4C4548, "BG08 cache word0");
    cpu_read_word(32'h10000334, rd); chk(rd, 32'h4D44204F, "BG08 cache word1");
    cpu_read_word(32'h10000338, rd); chk(rd, 32'h4F532D41, "BG08 cache word2");
    cpu_read_word(32'h1000033C, rd); chk(rd, 32'h0A0D2143, "BG08 cache word3");
    do_fence_flush();
    check_mem_word(32'h10000330, 32'h4C4C4548, "BG08 mem word0");
    check_mem_word(32'h10000334, 32'h4D44204F, "BG08 mem word1");
    check_mem_word(32'h10000338, 32'h4F532D41, "BG08 mem word2");
    check_mem_word(32'h1000033C, 32'h0A0D2143, "BG08 mem word3");

    $display("");
    $display("============================================================");
    $display("SUMMARY: PASS=%0d FAIL=%0d TOTAL=%0d", total_pass, total_fail, total_pass + total_fail);
    $display("stats: hits=%0d misses=%0d writes=%0d", stat_hits, stat_misses, stat_writes);
    $display("============================================================");
    $finish;
end

initial begin
    #10_000_000;
    $display("[WATCHDOG] timeout");
    $finish;
end

endmodule
