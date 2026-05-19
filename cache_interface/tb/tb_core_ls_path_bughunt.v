`timescale 1ns/1ps

// ============================================================================
// tb_core_ls_path_bughunt.v
//
// Cut from riscv_cpu_core_v2, but only keeps the minimal environment needed
// to preserve the real pipeline / hazard / LSU / DCache timing on load-store
// paths. Focuses on reproducing C4/C9 races at core level.
// ============================================================================

`include "cpu/riscv_cpu_core_v2.v"
`include "cache_interface/dcache/dcache_top.v"

module tb_core_ls_path_bughunt;

reg clk, rst;
wire rst_n = ~rst;
initial clk = 1'b0;
always #5 clk = ~clk;

// ============================================================================
// CPU <-> IMEM
// ============================================================================
wire [31:0] imem_addr;
wire        imem_valid;
reg  [31:0] imem_rdata;
reg         imem_ready;

// ============================================================================
// CPU <-> DCache
// ============================================================================
wire [31:0] cpu_dcache_addr;
wire [31:0] cpu_dcache_wdata;
wire [3:0]  cpu_dcache_wstrb;
wire        cpu_dcache_req;
wire        cpu_dcache_we;
wire [31:0] cpu_dcache_rdata;
wire        cpu_dcache_ready;
wire [1:0]  cpu_dcache_fence_type;

// ============================================================================
// DCache <-> AXI memory model
// ============================================================================
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

wire [31:0] dc_debug_addr, dc_debug_data;
wire        dc_debug_valid;
wire debug_halted, debug_running, cpu_wfi_o, perf_stall_o, perf_instr_ret_o;

riscv_cpu_core u_cpu (
    .clk               (clk),
    .rst               (rst),
    .imem_addr         (imem_addr),
    .imem_valid        (imem_valid),
    .imem_rdata        (imem_rdata),
    .imem_ready        (imem_ready),
    .dcache_addr       (cpu_dcache_addr),
    .dcache_wdata      (cpu_dcache_wdata),
    .dcache_wstrb      (cpu_dcache_wstrb),
    .dcache_req        (cpu_dcache_req),
    .dcache_we         (cpu_dcache_we),
    .dcache_rdata      (cpu_dcache_rdata),
    .dcache_ready      (cpu_dcache_ready),
    .dcache_fence_type (cpu_dcache_fence_type),
    .external_irq      (1'b0),
    .timer_irq         (1'b0),
    .sw_irq            (1'b0),
    .debug_haltreq     (1'b0),
    .debug_resumereq   (1'b0),
    .debug_halted      (debug_halted),
    .debug_running     (debug_running),
    .cpu_wfi_o         (cpu_wfi_o),
    .perf_stall_o      (perf_stall_o),
    .perf_instr_ret_o  (perf_instr_ret_o)
);

dcache_top #(
    .CACHE_SIZE (8192),
    .LINE_SIZE  (16),
    .ADDR_WIDTH (32),
    .DATA_WIDTH (32),
    .ID_WIDTH   (4)
) u_dcache (
    .clk           (clk),
    .rst_n         (rst_n),
    .cpu_addr      (cpu_dcache_addr),
    .cpu_wdata     (cpu_dcache_wdata),
    .cpu_wstrb     (cpu_dcache_wstrb),
    .cpu_req       (cpu_dcache_req),
    .cpu_we        (cpu_dcache_we),
    .cpu_rdata     (cpu_dcache_rdata),
    .cpu_ready     (cpu_dcache_ready),
    .fence_type    (cpu_dcache_fence_type),
    .current_addr  (dc_debug_addr),
    .current_data  (dc_debug_data),
    .current_valid (dc_debug_valid),
    .mem_arid      (mem_arid),
    .mem_araddr    (mem_araddr),
    .mem_arlen     (mem_arlen),
    .mem_arsize    (mem_arsize),
    .mem_arburst   (mem_arburst),
    .mem_arprot    (mem_arprot),
    .mem_arvalid   (mem_arvalid),
    .mem_arready   (mem_arready),
    .mem_rid       (mem_rid),
    .mem_rdata     (mem_rdata),
    .mem_rresp     (mem_rresp),
    .mem_rlast     (mem_rlast),
    .mem_rvalid    (mem_rvalid),
    .mem_rready    (mem_rready),
    .mem_awid      (mem_awid),
    .mem_awaddr    (mem_awaddr),
    .mem_awlen     (mem_awlen),
    .mem_awsize    (mem_awsize),
    .mem_awburst   (mem_awburst),
    .mem_awprot    (mem_awprot),
    .mem_awvalid   (mem_awvalid),
    .mem_awready   (mem_awready),
    .mem_wdata     (mem_wdata_axi),
    .mem_wstrb     (mem_wstrb),
    .mem_wlast     (mem_wlast),
    .mem_wvalid    (mem_wvalid),
    .mem_wready    (mem_wready),
    .mem_bid       (mem_bid),
    .mem_bresp     (mem_bresp),
    .mem_bvalid    (mem_bvalid),
    .mem_bready    (mem_bready),
    .stat_hits     (stat_hits),
    .stat_misses   (stat_misses),
    .stat_writes   (stat_writes)
);

// ============================================================================
// Core / DCache probes
// ============================================================================
wire        probe_fence_stall   = u_cpu.fence_stall;
wire        probe_lsu_idle      = u_cpu.lsu_idle;
wire        probe_lsu_req_valid = u_cpu.lsu_req_valid;
wire        probe_lsu_req_ready = u_cpu.lsu_req_ready;
wire        probe_lsu_req_fire  = u_cpu.lsu_req_fire;
wire        probe_lsu_req_sent  = u_cpu.lsu_req_sent;
wire        probe_lsu_req_new   = u_cpu.lsu_req_new;
wire        probe_lsu_req_valid_raw = u_cpu.lsu_req_valid_raw;
wire        probe_stall         = u_cpu.stall;
wire        probe_stall_if      = u_cpu.stall_if;
wire        probe_lsu_dep_stall = u_cpu.lsu_dep_stall;
wire        probe_flush_if_id   = u_cpu.flush_if_id;
wire        probe_flush_id_ex   = u_cpu.flush_id_ex;
wire [31:0] probe_pc_if         = u_cpu.pc_if;
wire [31:0] probe_pc_id         = u_cpu.pc_id;
wire [31:0] probe_pc_ex         = u_cpu.pc_ex;
wire [31:0] probe_instr_id      = u_cpu.instr_id;
wire        probe_memwrite_ex   = u_cpu.memwrite_ex;
wire        probe_memwrite_mem  = u_cpu.memwrite_mem;
wire        probe_memread_mem   = u_cpu.memread_mem;
wire [31:0] probe_alu_result_mem = u_cpu.alu_result_mem;
wire [31:0] probe_write_data_mem = u_cpu.write_data_mem;
wire [31:0] probe_pc_plus_4_mem = u_cpu.pc_plus_4_mem;
wire [4:0]  probe_rd_mem        = u_cpu.rd_mem;
wire [2:0]  probe_dc_state      = u_dcache.controller_inst.state;
wire        probe_do_deferred   = u_dcache.controller_inst.do_deferred_write;
wire        probe_flush_busy    = u_dcache.controller_inst.flush_busy;
wire [2:0]  probe_flush_state   = u_dcache.controller_inst.flush_state;
wire        probe_dwe           = u_dcache.controller_inst.data_write_enable;
wire [5:0]  probe_dwi           = u_dcache.controller_inst.data_write_index;
wire [1:0]  probe_dwo           = u_dcache.controller_inst.data_write_offset;
wire [31:0] probe_dwd           = u_dcache.controller_inst.data_write_data;
wire [3:0]  probe_dwstrb        = u_dcache.controller_inst.data_write_strb;
wire [31:0] probe_ev_addr       = u_dcache.evict_addr;
wire [31:0] probe_ev_d0         = u_dcache.evict_data_0;
wire [31:0] probe_ev_d1         = u_dcache.evict_data_1;
wire [31:0] probe_ev_d2         = u_dcache.evict_data_2;
wire [31:0] probe_ev_d3         = u_dcache.evict_data_3;
wire        probe_ev_start      = u_dcache.evict_start;

// ============================================================================
// IMEM behavioral model
// ============================================================================
reg [31:0] imem [0:1023];

always @(*) begin
    if (!imem_valid || rst) begin
        imem_rdata = 32'h0000_0013;
        imem_ready = 1'b0;
    end else begin
        imem_rdata = imem[imem_addr[11:2]];
        imem_ready = 1'b1;
    end
end

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
// Register probes
// ============================================================================
wire [31:0] rf_sp = u_cpu.register_file.registers[2];
wire [31:0] rf_t0 = u_cpu.register_file.registers[5];
wire [31:0] rf_t1 = u_cpu.register_file.registers[6];
wire [31:0] rf_t2 = u_cpu.register_file.registers[7];
wire [31:0] rf_s0 = u_cpu.register_file.registers[8];
wire [31:0] rf_s1 = u_cpu.register_file.registers[9];
wire [31:0] rf_s2 = u_cpu.register_file.registers[18];
wire [31:0] rf_s3 = u_cpu.register_file.registers[19];
wire [31:0] rf_a0 = u_cpu.register_file.registers[10];

// ============================================================================
// Helpers / encoders
// ============================================================================
integer cyc, pass_cnt, fail_cnt, i, wp;

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

function [31:0] enc_i;
    input [11:0] imm;
    input [4:0] rs1;
    input [2:0] f3;
    input [4:0] rd;
    input [6:0] op;
    begin
        enc_i = {imm, rs1, f3, rd, op};
    end
endfunction

function [31:0] enc_s;
    input [11:0] imm;
    input [4:0] rs2, rs1;
    input [2:0] f3;
    begin
        enc_s = {imm[11:5], rs2, rs1, f3, imm[4:0], 7'b0100011};
    end
endfunction

function [31:0] enc_u;
    input [19:0] imm;
    input [4:0] rd;
    input [6:0] op;
    begin
        enc_u = {imm, rd, op};
    end
endfunction

function [31:0] enc_j;
    input [20:0] imm;
    input [4:0] rd;
    begin
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    end
endfunction

task wi;
    input [31:0] ins;
    begin
        imem[wp] = ins;
        wp = wp + 1;
    end
endtask

task clr_imem;
    begin
        for (i = 0; i < 1024; i = i + 1)
            imem[i] = 32'h00000013;
    end
endtask

task clr_mem;
    begin
        for (i = 0; i < 16384; i = i + 1)
            axi_mem[i] = 32'h0;
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
        rst = 1'b1;
        repeat (6) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

task chk;
    input [31:0] got;
    input [31:0] exp;
    input [255:0] name;
    begin
        if (got === exp) begin
            pass_cnt = pass_cnt + 1;
            $display("    PASS [%0s] got=%08h", name, got);
        end else begin
            fail_cnt = fail_cnt + 1;
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

task wait_for_pc;
    input [31:0] pc_target;
    integer tout;
    begin
        tout = 0;
        while ((imem_addr !== pc_target) && tout < 200000) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 200000)
            $display("[WARN] wait_for_pc timeout target=%08h cyc=%0d", pc_target, cyc);
    end
endtask

task wait_flush_done;
    integer tout;
    begin
        tout = 0;
        while ((!probe_lsu_idle || probe_flush_busy || (cpu_dcache_fence_type != 2'b00)) && tout < 20000) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 20000)
            $display("[WARN] wait_flush_done timeout cyc=%0d", cyc);
        repeat (10) @(posedge clk);
    end
endtask

task load_prog_c4_like;
    begin
        clr_imem();
        wp = 0;
        wi(enc_u(20'h10000, 5'd2, 7'b0110111));      // lui   sp,0x10000
        wi(enc_i(12'h620,  5'd2, 3'b000, 5'd2, 7'b0010011)); // addi sp,sp,0x620
        wi(enc_i(12'd1,    5'd0, 3'b000, 5'd5, 7'b0010011)); // addi t0,x0,1
        wi(enc_s(12'd2,    5'd5, 5'd2, 3'b000));     // sb    t0,2(sp)
        wi(enc_i(12'd2,    5'd2, 3'b100, 5'd6, 7'b0000011)); // lbu t1,2(sp)
        wi(enc_s(12'd3,    5'd5, 5'd2, 3'b000));     // sb    t0,3(sp)
        wi(enc_i(12'd3,    5'd2, 3'b100, 5'd7, 7'b0000011)); // lbu t2,3(sp)
        wi(enc_i(12'd0,    5'd2, 3'b010, 5'd8, 7'b0000011)); // lw  s0,0(sp)
        wi(enc_j(21'd0,    5'd0));                   // jal x0,0
    end
endtask

task load_prog_c9_like;
    begin
        clr_imem();
        wp = 0;
        wi(enc_u(20'h10000, 5'd10, 7'b0110111));     // lui a0,0x10000
        wi(enc_i(12'h330,  5'd10, 3'b000, 5'd10, 7'b0010011)); // addi a0,a0,0x330

        wi(enc_i(12'd72, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd0,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd69, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd1,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd76, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd2,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd76, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd3,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd79, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd4,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd32, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd5,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd68, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd6,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd77, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd7,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd65, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd8,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd45, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd9,  5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd83, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd10, 5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd79, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd11, 5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd67, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd12, 5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd33, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd13, 5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd13, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd14, 5'd5, 5'd10, 3'b000));
        wi(enc_i(12'd10, 5'd0, 3'b000, 5'd5, 7'b0010011)); wi(enc_s(12'd15, 5'd5, 5'd10, 3'b000));

        wi(32'h0330000F); // fence rw,rw
        wi(enc_i(12'd0,  5'd10, 3'b010, 5'd8,  7'b0000011)); // lw s0,0(a0)
        wi(enc_i(12'd4,  5'd10, 3'b010, 5'd9,  7'b0000011)); // lw s1,4(a0)
        wi(enc_i(12'd8,  5'd10, 3'b010, 5'd18, 7'b0000011)); // lw s2,8(a0)
        wi(enc_i(12'd12, 5'd10, 3'b010, 5'd19, 7'b0000011)); // lw s3,12(a0)
        wi(enc_j(21'd0, 5'd0)); // jal x0,0
    end
endtask

always @(posedge clk)
    cyc = cyc + 1;

always @(posedge clk) begin
    if (!rst) begin
        if ((cyc >= 104) && (cyc <= 170)) begin
            $display("[CYC%0d][PIPE] if=%08h id=%08h ex=%08h instr_id=%08h stall=%b ifs=%b dep=%b fstall=%b fl_if=%b fl_id=%b mem_ex=%b mem_mem=%b ld_mem=%b addr_mem=%08h wdat_mem=%08h rd_mem=%0d raw=%b sent=%b new=%b fire=%b",
                cyc, probe_pc_if, probe_pc_id, probe_pc_ex, probe_instr_id,
                probe_stall, probe_stall_if, probe_lsu_dep_stall, probe_fence_stall,
                probe_flush_if_id, probe_flush_id_ex,
                probe_memwrite_ex, probe_memwrite_mem, probe_memread_mem,
                probe_alu_result_mem, probe_write_data_mem, probe_rd_mem,
                probe_lsu_req_valid_raw, probe_lsu_req_sent, probe_lsu_req_new, probe_lsu_req_fire);
        end
        if (probe_lsu_req_fire) begin
            $display("[CYC%0d][LSU-REQ] addr=%08h we=%b strb=%04b wdata=%08h rd=%0d fstall=%b idle=%b",
                cyc, cpu_dcache_addr, cpu_dcache_we, cpu_dcache_wstrb, cpu_dcache_wdata,
                u_cpu.rd_mem, probe_fence_stall, probe_lsu_idle);
        end
        if (probe_dwe) begin
            $display("[CYC%0d][DC-WR] st=%0d idx=%0d off=%0d strb=%04b data=%08h def=%b",
                cyc, probe_dc_state, probe_dwi, probe_dwo, probe_dwstrb, probe_dwd,
                probe_do_deferred);
        end
        if (|cpu_dcache_fence_type) begin
            $display("[CYC%0d][FENCE] type=%02b stall=%b lsu_idle=%b flush_st=%0d",
                cyc, cpu_dcache_fence_type, probe_fence_stall, probe_lsu_idle, probe_flush_state);
        end
        if (probe_ev_start) begin
            $display("[CYC%0d][EVICT] addr=%08h {%08h %08h %08h %08h}",
                cyc, probe_ev_addr, probe_ev_d0, probe_ev_d1, probe_ev_d2, probe_ev_d3);
        end
    end
end

initial begin
    $dumpfile("tb_core_ls_path_bughunt.vcd");
    $dumpvars(0, tb_core_ls_path_bughunt);

    cyc = 0;
    pass_cnt = 0;
    fail_cnt = 0;
    clr_imem();
    clr_mem();

    tc_header("CG01: core-cut C4-like sb/lbu stack pattern");
    load_prog_c4_like();
    do_reset();
    wait_for_pc(32'h00000020);
    repeat (80) @(posedge clk);
    chk(rf_t1, 32'h00000001, "CG01 t1 lbu edge");
    chk(rf_t2, 32'h00000001, "CG01 t2 lbu polarity");
    chk(rf_s0, 32'h01010000, "CG01 s0 combined lw");

    tc_header("CG02: core-cut C9-like 16 byte stores + fence");
    clr_mem();
    clear_caps();
    load_prog_c9_like();
    do_reset();
    wait_for_pc(32'h00000098);
    wait_flush_done();
    chk(rf_s0, 32'h4C4C4548, "CG02 s0 word0");
    chk(rf_s1, 32'h4D44204F, "CG02 s1 word1");
    chk(rf_s2, 32'h4F532D41, "CG02 s2 word2");
    chk(rf_s3, 32'h0A0D2143, "CG02 s3 word3");
    chk(axi_mem[midx(32'h10000330)],   32'h4C4C4548, "CG02 mem word0");
    chk(axi_mem[midx(32'h10000334)],   32'h4D44204F, "CG02 mem word1");
    chk(axi_mem[midx(32'h10000338)],   32'h4F532D41, "CG02 mem word2");
    chk(axi_mem[midx(32'h1000033C)],   32'h0A0D2143, "CG02 mem word3");

    $display("");
    $display("============================================================");
    $display("SUMMARY: PASS=%0d FAIL=%0d TOTAL=%0d", pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    $display("stats: hits=%0d misses=%0d writes=%0d", stat_hits, stat_misses, stat_writes);
    $display("============================================================");
    $finish;
end

initial begin
    #30_000_000;
    $display("[WATCHDOG] timeout");
    $finish;
end

endmodule
