`timescale 1ns/1ps

`include "soc_hs.v"

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "gnu_toolchain/tests/test_ascon_dma_coherent_nofence_128b.hex"
`endif

`ifndef TIMEOUT
  `define TIMEOUT 2000000
`endif

module run_soc_coherent_nofence_128b;
    parameter CLK_PERIOD = 10;

    localparam [31:0] RET_RUNNING = 32'hCAFE0001;
    localparam [31:0] RET_PASS    = 32'hCAFE0000;
    localparam [31:0] PT_WORD0    = 32'hA5000000;
    localparam [31:0] PT_WORD1    = 32'h5A000000;
    localparam [63:0] PT_SNOOP64  = {PT_WORD1, PT_WORD0};

    reg clk;
    reg por_n_r;
    reg ext_rst_n_r;
    reg jtag_tck_r;
    reg jtag_tms_r;
    reg jtag_tdi_r;
    wire jtag_tdo_w;
    wire uart_tx_w;
    wire uart_rx_w = 1'b1;
    wire [31:0] gpio_w;
    reg  [31:0] gpio_in_r;
    assign gpio_w = gpio_in_r;
    wire wdt_rst_req_w;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    soc_hs #(.SIM_MODE(1), .IMEM_INIT_FILE(`IMEM_INIT_FILE)) chip (
        .clk_in(clk),
        .por_n(por_n_r),
        .ext_rst_n(ext_rst_n_r),
        .uart_tx(uart_tx_w),
        .uart_rx(uart_rx_w),
        .tck(jtag_tck_r),
        .tms(jtag_tms_r),
        .tdi(jtag_tdi_r),
        .tdo(jtag_tdo_w),
        .spi_sck(),
        .spi_mosi(),
        .spi_miso(1'b1),
        .spi_cs_n(),
        .gpio(gpio_w),
        .wdt_rst_req(wdt_rst_req_w)
    );

    wire fabric_rst_n_w = chip.u_soc_top.fabric_rst_n;
    wire cpu_rst_n_w    = chip.u_soc_top.cpu_rst_n;
    wire [31:0] pc_if   = chip.u_soc_top.u_cpu.pc_if;

    wire dc_snoop_req_fire  = chip.u_soc_top.dc_snoop_req_valid && chip.u_soc_top.dc_snoop_req_ready;
    wire dc_snoop_resp_fire = chip.u_soc_top.dc_snoop_resp_valid;
    wire [1:0] dc_snoop_cmd = chip.u_soc_top.dc_snoop_cmd;
    wire [31:0] dc_snoop_addr = chip.u_soc_top.dc_snoop_addr;
    wire dc_snoop_hit = chip.u_soc_top.dc_snoop_resp_hit;
    wire [127:0] dc_snoop_data = chip.u_soc_top.dc_snoop_resp_data;

    wire m2_ar_fire = chip.u_soc_top.m2_arvalid && chip.u_soc_top.m2_arready;
    wire m2_aw_fire = chip.u_soc_top.m2_awvalid && chip.u_soc_top.m2_awready;
    wire m2_wlast_fire = chip.u_soc_top.m2_wvalid && chip.u_soc_top.m2_wready && chip.u_soc_top.m2_wlast;
    wire m2_b_fire = chip.u_soc_top.m2_bvalid && chip.u_soc_top.m2_bready;
    wire [31:0] m2_araddr = chip.u_soc_top.m2_araddr;
    wire [31:0] m2_awaddr = chip.u_soc_top.m2_awaddr;

    wire dma_start = chip.u_soc_top.u_ascon.u_slave.dma_start;
    wire dma_done  = chip.u_soc_top.u_ascon.dma_done_w;
    wire dma_error = chip.u_soc_top.u_ascon.u_slave.status_dma_error |
                     chip.u_soc_top.u_ascon.u_slave.status_error;
    wire [31:0] coh_ctrl = {30'h0, chip.u_soc_top.u_ascon.u_slave.reg_dma_coh_ctrl};
    wire [31:0] result_mailbox = chip.u_soc_top.u_ascon.u_slave.reg_wdt_cfg;

    // DEBUG: ctrl_fsm / write engine internals
    wire [28:0] dbg_exp_wr_beats = chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.expected_wr_beats;
    wire [28:0] dbg_wr_beats_done = chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.wr_beats_done;
    wire        dbg_wr_fifo_full = chip.u_soc_top.u_ascon.u_dma.u_wr_fifo.full;
    wire        dbg_tag_latch_pending = chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.tag_latch_pending;
    wire [2:0]  dbg_push_state = chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.push_state;
    wire [28:0] dbg_remaining_beats = chip.u_soc_top.u_ascon.u_dma.u_wr_engine.remaining_beats;
    wire [3:0]  dbg_wr_state = chip.u_soc_top.u_ascon.u_dma.u_wr_engine.state;
    wire [31:0] dbg_wr_fifo_count = chip.u_soc_top.u_ascon.u_dma.u_wr_fifo.count;
    wire        dbg_wr_error = chip.u_soc_top.u_ascon.u_dma.u_wr_engine.wr_error;
    wire        dbg_rd_error = chip.u_soc_top.u_ascon.u_dma.u_rd_engine.rd_error;
    wire [28:0] dbg_total_blocks = chip.u_soc_top.u_ascon.u_dma.u_ctrl_fsm.total_blocks;
    wire [31:0] dbg_byte_len = chip.u_soc_top.u_ascon.u_dma.byte_len;
    wire        dbg_core_tag_valid = chip.u_soc_top.u_ascon.core_tag_valid_w;

    // Crossbar M1 (DCache) AXI monitoring — see if DCache is caching STATUS reads
    wire m1_ar_fire = chip.u_soc_top.m1_arvalid && chip.u_soc_top.m1_arready;
    wire m1_r_fire  = chip.u_soc_top.m1_rvalid  && chip.u_soc_top.m1_rready;
    wire m1_aw_fire = chip.u_soc_top.m1_awvalid && chip.u_soc_top.m1_awready;
    wire m1_w_fire  = chip.u_soc_top.m1_wvalid  && chip.u_soc_top.m1_wready;
    wire [31:0] m1_awaddr = chip.u_soc_top.m1_awaddr;
    wire [31:0] m1_wdata  = chip.u_soc_top.m1_wdata;
    wire [3:0]  m1_wstrb  = chip.u_soc_top.m1_wstrb;

    wire core_start = chip.u_soc_top.u_ascon.core_start_mux;
    wire dma_core_data_valid = chip.u_soc_top.u_ascon.dma_core_data_valid;
    wire dma_core_data_ready = chip.u_soc_top.u_ascon.dma_core_data_ready;
    wire [31:0] dma_ptext_0 = chip.u_soc_top.u_ascon.dma_core_ptext_0;
    wire [31:0] dma_ptext_1 = chip.u_soc_top.u_ascon.dma_core_ptext_1;

    integer cycle_count;
    integer snoop_read_req_cnt;
    integer snoop_read_hit_cnt;
    integer snoop_write_req_cnt;
    integer snoop_write_hit_cnt;
    integer m2_ar_cnt;
    integer m2_aw_cnt;
    integer core_start_cnt;
    integer dma_start_cycle;
    integer last_m2_aw_cycle;
    integer last_m2_wlast_cycle;
    integer last_m2_b_cycle;
    reg saw_expected_snoop_data;
    reg saw_expected_core_ptext;
    reg saw_dma_start;
    reg saw_dma_done;
    reg saw_dma_error;
    reg saw_mailbox_pass;
    reg dma_start_q;
    reg dma_done_q;
    reg dma_error_q;
    reg core_start_q;
    reg dma_core_data_valid_q;
    reg [1:0] last_snoop_cmd;

    always @(posedge clk) begin
        if (!ext_rst_n_r) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    reg dbg_triggered;
    initial dbg_triggered = 0;

    // STATUS read tracking
    reg [31:0] last_status_val;
    reg [31:0] max_status_val;
    reg        saw_status_bits345;
    initial begin last_status_val = 0; max_status_val = 0; saw_status_bits345 = 0; end
    // M1 AR count to ASCON region (== cache misses for STATUS read)
    integer m1_ar_ascon_cnt;
    // DCache state
    wire [2:0] dcache_state = chip.u_soc_top.u_dcache.controller_inst.state;
    wire [2:0] dcache_next_state = chip.u_soc_top.u_dcache.controller_inst.next_state;
    // Count all slave STATUS reads
    integer slave_status_rd_cnt;
    // Count NC_READ entries
    integer dcache_nc_read_cnt;
    // Count poll loop iterations (PC=0x414 = loop start)
    integer poll_loop_cnt;
    // Track whether DCache is stuck in AR wait for NC read
    wire [2:0] axi_rd_state = chip.u_soc_top.u_dcache.axi_interface_inst.rd_state;

    always @(posedge clk) begin
        if (!ext_rst_n_r) begin
            snoop_read_req_cnt <= 0;
            snoop_read_hit_cnt <= 0;
            snoop_write_req_cnt <= 0;
            snoop_write_hit_cnt <= 0;
            m2_ar_cnt <= 0;
            m2_aw_cnt <= 0;
            core_start_cnt <= 0;
            dma_start_cycle <= -1;
            last_m2_aw_cycle <= -1;
            last_m2_wlast_cycle <= -1;
            last_m2_b_cycle <= -1;
            saw_expected_snoop_data <= 1'b0;
            saw_expected_core_ptext <= 1'b0;
            m1_ar_ascon_cnt <= 0;
            slave_status_rd_cnt <= 0;
            dcache_nc_read_cnt <= 0;
            poll_loop_cnt <= 0;
            saw_dma_start <= 1'b0;
            saw_dma_done <= 1'b0;
            saw_dma_error <= 1'b0;
            saw_mailbox_pass <= 1'b0;
            dma_start_q <= 1'b0;
            dma_done_q <= 1'b0;
            dma_error_q <= 1'b0;
            core_start_q <= 1'b0;
            dma_core_data_valid_q <= 1'b0;
            last_snoop_cmd <= 2'b00;
        end else begin
            dma_start_q <= dma_start;
            dma_done_q <= dma_done;
            dma_error_q <= dma_error;
            core_start_q <= core_start;
            dma_core_data_valid_q <= dma_core_data_valid;

            if (dma_start && !dma_start_q) begin
                saw_dma_start <= 1'b1;
                dma_start_cycle <= cycle_count;
                $display("[%0d] DMA_START coh_ctrl=%0h", cycle_count, coh_ctrl);
            end
            if (dma_done && !dma_done_q) begin
                saw_dma_done <= 1'b1;
                $display("[%0d] DMA_DONE", cycle_count);
            end
            if (dma_error && !dma_error_q) begin
                saw_dma_error <= 1'b1;
                $display("[%0d] DMA_ERROR", cycle_count);
            end

            if (dc_snoop_req_fire) begin
                last_snoop_cmd <= dc_snoop_cmd;
                if (dc_snoop_cmd == 2'b01) begin
                    snoop_read_req_cnt <= snoop_read_req_cnt + 1;
                    $display("[%0d] SNOOP_RD_REQ addr=%08h", cycle_count, dc_snoop_addr);
                end else if (dc_snoop_cmd == 2'b10) begin
                    snoop_write_req_cnt <= snoop_write_req_cnt + 1;
                    $display("[%0d] SNOOP_INV_REQ addr=%08h", cycle_count, dc_snoop_addr);
                end
            end

            if (dc_snoop_resp_fire) begin
                $display("[%0d] SNOOP_RESP hit=%0b data=%032h", cycle_count, dc_snoop_hit, dc_snoop_data);
                if (last_snoop_cmd == 2'b01 && dc_snoop_hit) begin
                    snoop_read_hit_cnt <= snoop_read_hit_cnt + 1;
                    if (dc_snoop_data[63:0] == PT_SNOOP64)
                        saw_expected_snoop_data <= 1'b1;
                end else if (last_snoop_cmd == 2'b10 && dc_snoop_hit) begin
                    snoop_write_hit_cnt <= snoop_write_hit_cnt + 1;
                end
            end

            if (m2_ar_fire) begin
                m2_ar_cnt <= m2_ar_cnt + 1;
                $display("[%0d] M2_AR addr=%08h", cycle_count, m2_araddr);
            end
            if (m2_aw_fire) begin
                m2_aw_cnt <= m2_aw_cnt + 1;
                last_m2_aw_cycle <= cycle_count;
                $display("[%0d] M2_AW addr=%08h", cycle_count, m2_awaddr);
            end
            if (m2_wlast_fire) begin
                last_m2_wlast_cycle <= cycle_count;
                $display("[%0d] M2_WLAST", cycle_count);
            end
            if (m2_b_fire) begin
                last_m2_b_cycle <= cycle_count;
                $display("[%0d] M2_B", cycle_count);
            end

            if (core_start && !core_start_q) begin
                core_start_cnt <= core_start_cnt + 1;
                $display("[%0d] CORE_START ptext0=%08h ptext1=%08h", cycle_count, dma_ptext_0, dma_ptext_1);
            end

            if (dma_core_data_valid && !dma_core_data_valid_q) begin
                $display("[%0d] DMA_CORE_DATA valid ready=%0b ptext0=%08h ptext1=%08h",
                         cycle_count, dma_core_data_ready, dma_ptext_0, dma_ptext_1);
                if (dma_ptext_0 == PT_WORD0 && dma_ptext_1 == PT_WORD1)
                    saw_expected_core_ptext <= 1'b1;
            end

            // CRITICAL: track ALL M1 ARs (not just ASCON) to see DCache read activity
            if (m1_ar_fire) begin
                if (chip.u_soc_top.m1_araddr >= 32'h20000000 &&
                    chip.u_soc_top.m1_araddr < 32'h20001000)
                begin
                    m1_ar_ascon_cnt <= m1_ar_ascon_cnt + 1;
                    $display("[%0d] [M1_AR] addr=%08h ASCON cnt=%0d",
                        cycle_count, chip.u_soc_top.m1_araddr, m1_ar_ascon_cnt + 1);
                end else begin
                    $display("[%0d] [M1_AR] addr=%08h (other region)",
                        cycle_count, chip.u_soc_top.m1_araddr);
                end
            end
            // Track M1 R responses (data coming back to DCache from crossbar)
            if (m1_r_fire) begin
                $display("[%0d] [M1_R] data=%08h", cycle_count, chip.u_soc_top.m1_rdata);
            end

            // Track M1 AW writes (CPU stores reaching crossbar)
            if (m1_aw_fire) begin
                if (chip.u_soc_top.m1_awaddr >= 32'h20000000 &&
                    chip.u_soc_top.m1_awaddr < 32'h20001000)
                    $display("[%0d] [M1_AW] addr=%08h (ASCON)", cycle_count, chip.u_soc_top.m1_awaddr);
                else if (chip.u_soc_top.m1_awaddr >= 32'h10000000 &&
                         chip.u_soc_top.m1_awaddr < 32'h10001000)
                    $display("[%0d] [M1_AW] addr=%08h (DMEM)", cycle_count, chip.u_soc_top.m1_awaddr);
                else
                    $display("[%0d] [M1_AW] addr=%08h (OTHER)", cycle_count, chip.u_soc_top.m1_awaddr);
            end
            if (m1_w_fire) begin
                if (chip.u_soc_top.m1_wstrb != 4'h0)
                    $display("[%0d] [M1_W] data=%08h strb=%04b %s", cycle_count, m1_wdata, m1_wstrb,
                        (m1_wdata == 32'hCAFE0000 || m1_wdata == 32'hCAFE0001) ? "*** MAILBOX ***" : "");
            end

            // DEBUG: ALL CPU reads from ASCON slave (AXI R-channel) — no suppression
            if (chip.u_soc_top.u_ascon.u_slave.S_AXI_RVALID &&
                chip.u_soc_top.u_ascon.u_slave.S_AXI_RREADY)
            begin
                if (chip.u_soc_top.u_ascon.u_slave.rd_addr_lat == 12'h004) begin
                    $display("[%0d] [SLAVE_RD] addr=%03x data=%08h dma_done=%0d bits345=%0d",
                        cycle_count, chip.u_soc_top.u_ascon.u_slave.rd_addr_lat,
                        chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA,
                        dma_done, chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA[5:3]);
                    last_status_val <= chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA;
                end else begin
                    $display("[%0d] [SLAVE_RD] addr=%03x data=%08h (NON-STATUS!)",
                        cycle_count, chip.u_soc_top.u_ascon.u_slave.rd_addr_lat,
                        chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA);
                end
                if (chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA > max_status_val)
                    max_status_val <= chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA;
                if (chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA & 32'h38)
                    saw_status_bits345 <= 1'b1;
                slave_status_rd_cnt <= slave_status_rd_cnt + 1;
            end

            // Track NC_READ entries: detect state transition to NC_READ
            if (dcache_state != 3'b110 && dcache_next_state == 3'b110)
                dcache_nc_read_cnt <= dcache_nc_read_cnt + 1;

            // Track poll loop iterations: count each time PC reaches poll loop addrs
            if (pc_if == 32'h414)
                poll_loop_cnt <= poll_loop_cnt + 1;
            // DEBUG: print ALL PC values after poll loop starts (cycle 6900+)
            if (cycle_count > 6900)
                $display("[%0d] [PC] pc=0x%08h", cycle_count, pc_if);

            // DEBUG: ctrl_fsm / write engine state tracing
            if (dbg_remaining_beats <= 4 && dbg_remaining_beats > 0 && !dbg_triggered) begin
                dbg_triggered <= 1'b1;
                $display("[%0d] [DBG] remaining_beats=%0d state=%0d fifo_cnt=%0d push_state=%0d tag_pend=%0d",
                    cycle_count, dbg_remaining_beats, dbg_wr_state, dbg_wr_fifo_count, dbg_push_state, dbg_tag_latch_pending);
                $display("[%0d] [DBG] exp_wr=%0d wr_done=%0d wr_full=%0d wr_error=%0d rd_error=%0d byte_len=%0d total_blk=%0d",
                    cycle_count, dbg_exp_wr_beats, dbg_wr_beats_done, dbg_wr_fifo_full, dbg_wr_error, dbg_rd_error, dbg_byte_len, dbg_total_blocks);
            end
            if (dbg_triggered) begin
                if (dbg_wr_state != 4'd0 && dbg_wr_state != 4'd8) begin
                    $display("[%0d] [DBG] WR advancing: state=%0d remaining=%0d fifo_cnt=%0d AW_cnt=%0d",
                        cycle_count, dbg_wr_state, dbg_remaining_beats, dbg_wr_fifo_count, m2_aw_cnt);
                end
                if (m2_aw_fire) begin
                    $display("[%0d] [DBG] NEW AW after remaining=%0d, addr=%08h", cycle_count, dbg_remaining_beats, m2_awaddr);
                end
                if (m2_b_fire) begin
                    $display("[%0d] [DBG] B after remaining=%0d, AW_cnt=%0d", cycle_count, dbg_remaining_beats, m2_aw_cnt);
                end
            end
        end
    end

    task fail;
        input [8*96-1:0] msg;
        begin
            $display("\n[FAIL] %0s", msg);
            print_summary;
            $fatal(1);
        end
    endtask

    task print_summary;
        begin
            $display("\n================ COHERENT NO-FENCE 128B SUMMARY ================");
            $display("cycles                  : %0d", cycle_count);
            $display("result_mailbox          : 0x%08h", result_mailbox);
            $display("dma_start/done/error    : %0d/%0d/%0d", saw_dma_start, saw_dma_done, saw_dma_error);
            $display("completion source        : mailbox PASS + internal dma_done");
            $display("snoop read req/hit      : %0d/%0d", snoop_read_req_cnt, snoop_read_hit_cnt);
            $display("snoop inv req/hit       : %0d/%0d", snoop_write_req_cnt, snoop_write_hit_cnt);
            $display("expected snoop/coredata : %0d/%0d", saw_expected_snoop_data, saw_expected_core_ptext);
            $display("M2 AR/AW                : %0d/%0d", m2_ar_cnt, m2_aw_cnt);
            $display("dma_start_cycle         : %0d", dma_start_cycle);
            $display("last M2 AW/WLAST/B      : %0d/%0d/%0d", last_m2_aw_cycle, last_m2_wlast_cycle, last_m2_b_cycle);
            if (dma_start_cycle >= 0 && last_m2_b_cycle >= 0)
                $display("fair write-complete cyc : %0d", last_m2_b_cycle - dma_start_cycle);
            else if (dma_start_cycle >= 0 && last_m2_wlast_cycle >= 0)
                $display("fair write-last cyc     : %0d", last_m2_wlast_cycle - dma_start_cycle);
            $display("PC at exit              : 0x%08h", pc_if);
            $display("max STATUS seen         : 0x%08h", max_status_val);
            $display("saw STATUS bits 3/4/5   : %0d", saw_status_bits345);
            $display("last STATUS seen        : 0x%08h", last_status_val);
            $display("M1 AR to ASCON          : %0d", m1_ar_ascon_cnt);
            $display("slave STATUS reads      : %0d", slave_status_rd_cnt);
            $display("DCache NC_READ entries  : %0d", dcache_nc_read_cnt);
            $display("poll loop iterations    : %0d", poll_loop_cnt);
            $display("===========================================================\n");
        end
    endtask

    initial begin
        por_n_r = 1'b0;
        ext_rst_n_r = 1'b0;
        jtag_tck_r = 1'b0;
        jtag_tms_r = 1'b1;
        jtag_tdi_r = 1'b0;
        gpio_in_r = 32'h0;

        repeat (20) @(posedge clk);
        ext_rst_n_r = 1'b1;
        repeat (12) @(posedge clk);
        por_n_r = 1'b1;

        wait (fabric_rst_n_w === 1'b1 && cpu_rst_n_w === 1'b1);
        $display("[TB] reset released, IMEM=%s", `IMEM_INIT_FILE);

        while (cycle_count < `TIMEOUT) begin
            @(posedge clk);
            if (result_mailbox !== RET_RUNNING && result_mailbox !== 32'h0 && !saw_mailbox_pass) begin
                if (result_mailbox !== RET_PASS)
                    fail("firmware reported failure");

                saw_mailbox_pass = 1'b1;
            end

            if (saw_mailbox_pass && saw_dma_done && last_m2_b_cycle >= last_m2_wlast_cycle) begin
                if (!saw_dma_start) fail("DMA did not start");
                if (saw_dma_error) fail("DMA/core error asserted");
                if (coh_ctrl[1:0] !== 2'b11) fail("coherence control not enabled");
                if (snoop_read_req_cnt != 8) fail("unexpected snoop read request count for 128B line-snoop");
                if (snoop_read_hit_cnt != 8) fail("unexpected snoop read hit count for 128B line-snoop");
                if (!saw_expected_snoop_data) fail("snoop data did not match dirty plaintext");
                if (m2_ar_cnt != 0) fail("DMA issued AXI read despite snoop hit");
                if (m2_aw_cnt != 2) fail("DMA did not issue expected 2 output write bursts");

                print_summary;
                $display("[PASS] SoC coherent DMA no-fence 128B test passed (internal dma_done completion)");
                $finish;
            end
        end

        fail("timeout waiting for result mailbox");
    end
endmodule
