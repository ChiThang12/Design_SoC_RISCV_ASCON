`timescale 1ns/1ps

`include "soc_hs.v"

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "gnu_toolchain/tests/test_ascon_dma_coherent_nofence_256b.hex"
`endif

`ifndef PAYLOAD_BYTES
  `define PAYLOAD_BYTES 256
`endif

`ifndef TIMEOUT
  `define TIMEOUT 5000000
`endif

`ifndef COH_CTRL_VALUE
  `define COH_CTRL_VALUE 3
`endif

module run_soc_coherent_nofence_sweep;
    parameter CLK_PERIOD = 10;

    localparam [31:0] RET_RUNNING = 32'hCAFE0001;
    localparam [31:0] RET_PASS    = 32'hCAFE0000;
    localparam [31:0] PT_WORD0    = 32'hA5000000;
    localparam [31:0] PT_WORD1    = 32'h5A000000;
    localparam [63:0] PT_SNOOP64  = {PT_WORD1, PT_WORD0};

    localparam integer PAYLOAD_BYTES = `PAYLOAD_BYTES;
    localparam integer COH_CTRL_VALUE = `COH_CTRL_VALUE;
    localparam integer EXPECT_SNOOP_READS = ((COH_CTRL_VALUE & 1) != 0) ?
                                            (PAYLOAD_BYTES / 16) : 0;
    localparam integer EXPECT_INV_REQ = ((COH_CTRL_VALUE & 2) != 0) ?
                                        ((PAYLOAD_BYTES + 16 + 15) / 16) : 0;
    localparam integer EXPECT_WR_BEATS = (PAYLOAD_BYTES / 8) + 2;
    localparam integer EXPECT_AW = (EXPECT_WR_BEATS + 15) / 16;

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

`ifdef COH_REG_TRACE
    always @(posedge clk) begin
        if (chip.u_soc_top.s2_awvalid && chip.u_soc_top.s2_awready) begin
            if ((chip.u_soc_top.s2_awaddr[11:0] >= 12'h150 && chip.u_soc_top.s2_awaddr[11:0] <= 12'h158) ||
                chip.u_soc_top.s2_awaddr[11:0] == 12'h020) begin
                $display("[COH-REG] cycle=%0d AW addr=%08x", cycle_count, chip.u_soc_top.s2_awaddr);
            end
        end
        if (chip.u_soc_top.s2_wvalid && chip.u_soc_top.s2_wready) begin
            if ((chip.u_soc_top.u_ascon.u_slave.wr_addr_lat >= 12'h150 &&
                 chip.u_soc_top.u_ascon.u_slave.wr_addr_lat <= 12'h158) ||
                chip.u_soc_top.u_ascon.u_slave.wr_addr_lat == 12'h020) begin
                $display("[COH-REG] cycle=%0d W addr_lat=%03x data=%08x strb=%0h last=%0b reg_dma_coh_ctrl=%0d",
                         cycle_count,
                         chip.u_soc_top.u_ascon.u_slave.wr_addr_lat,
                         chip.u_soc_top.s2_wdata,
                         chip.u_soc_top.s2_wstrb,
                         chip.u_soc_top.s2_wlast,
                         chip.u_soc_top.u_ascon.u_slave.reg_dma_coh_ctrl);
            end
        end
        if (chip.u_soc_top.s2_bvalid && chip.u_soc_top.s2_bready) begin
            if ((chip.u_soc_top.u_ascon.u_slave.wr_addr_lat >= 12'h150 &&
                 chip.u_soc_top.u_ascon.u_slave.wr_addr_lat <= 12'h158) ||
                chip.u_soc_top.u_ascon.u_slave.wr_addr_lat == 12'h020) begin
                $display("[COH-REG] cycle=%0d B addr_lat=%03x resp=%0b reg_dma_coh_ctrl=%0d dma_start=%0b",
                         cycle_count,
                         chip.u_soc_top.u_ascon.u_slave.wr_addr_lat,
                         chip.u_soc_top.s2_bresp,
                         chip.u_soc_top.u_ascon.u_slave.reg_dma_coh_ctrl,
                         chip.u_soc_top.u_ascon.u_slave.dma_start);
            end
        end
    end
`endif

    wire dc_snoop_req_fire  = chip.u_soc_top.dc_snoop_req_valid && chip.u_soc_top.dc_snoop_req_ready;
    wire dc_snoop_resp_fire = chip.u_soc_top.dc_snoop_resp_valid;
    wire [1:0] dc_snoop_cmd = chip.u_soc_top.dc_snoop_cmd;
    wire dc_snoop_hit = chip.u_soc_top.dc_snoop_resp_hit;
    wire [127:0] dc_snoop_data = chip.u_soc_top.dc_snoop_resp_data;

    wire m2_ar_fire = chip.u_soc_top.m2_arvalid && chip.u_soc_top.m2_arready;
    wire m2_aw_fire = chip.u_soc_top.m2_awvalid && chip.u_soc_top.m2_awready;
    wire m2_wlast_fire = chip.u_soc_top.m2_wvalid && chip.u_soc_top.m2_wready && chip.u_soc_top.m2_wlast;
    wire m2_b_fire = chip.u_soc_top.m2_bvalid && chip.u_soc_top.m2_bready;

    wire dma_start = chip.u_soc_top.u_ascon.u_slave.dma_start;
    wire dma_done  = chip.u_soc_top.u_ascon.dma_done_w;
    wire dma_error = chip.u_soc_top.u_ascon.u_slave.status_dma_error |
                     chip.u_soc_top.u_ascon.u_slave.status_error;
    wire [31:0] coh_ctrl = {30'h0, chip.u_soc_top.u_ascon.u_slave.reg_dma_coh_ctrl};
    wire [31:0] result_mailbox = chip.u_soc_top.u_ascon.u_slave.reg_wdt_cfg;
    wire [31:0] max_wr_fifo_count = chip.u_soc_top.u_ascon.u_dma.u_wr_fifo.count;

    wire dma_core_data_valid = chip.u_soc_top.u_ascon.dma_core_data_valid;
    wire [31:0] dma_ptext_0 = chip.u_soc_top.u_ascon.dma_core_ptext_0;
    wire [31:0] dma_ptext_1 = chip.u_soc_top.u_ascon.dma_core_ptext_1;

    integer cycle_count;
    integer snoop_read_req_cnt;
    integer snoop_read_hit_cnt;
    integer snoop_inv_req_cnt;
    integer snoop_inv_hit_cnt;
    integer m2_ar_cnt;
    integer m2_aw_cnt;
    integer dma_start_cycle;
    integer dma_done_cycle;
    integer last_m2_aw_cycle;
    integer last_m2_wlast_cycle;
    integer last_m2_b_cycle;
    integer peak_wr_fifo_count;
    integer slave_status_rd_cnt;
    reg saw_expected_snoop_data;
    reg saw_expected_core_ptext;
    reg saw_dma_start;
    reg saw_dma_done;
    reg saw_dma_error;
    reg saw_mailbox_pass;
    reg dma_start_q;
    reg dma_done_q;
    reg dma_error_q;
    reg dma_core_data_valid_q;
    reg [1:0] last_snoop_cmd;
    reg [31:0] last_status_val;
    reg [31:0] max_status_val;

    always @(posedge clk) begin
        if (!ext_rst_n_r)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    always @(posedge clk) begin
        if (!ext_rst_n_r) begin
            snoop_read_req_cnt <= 0;
            snoop_read_hit_cnt <= 0;
            snoop_inv_req_cnt <= 0;
            snoop_inv_hit_cnt <= 0;
            m2_ar_cnt <= 0;
            m2_aw_cnt <= 0;
            dma_start_cycle <= -1;
            dma_done_cycle <= -1;
            last_m2_aw_cycle <= -1;
            last_m2_wlast_cycle <= -1;
            last_m2_b_cycle <= -1;
            peak_wr_fifo_count <= 0;
            slave_status_rd_cnt <= 0;
            saw_expected_snoop_data <= 1'b0;
            saw_expected_core_ptext <= 1'b0;
            saw_dma_start <= 1'b0;
            saw_dma_done <= 1'b0;
            saw_dma_error <= 1'b0;
            saw_mailbox_pass <= 1'b0;
            dma_start_q <= 1'b0;
            dma_done_q <= 1'b0;
            dma_error_q <= 1'b0;
            dma_core_data_valid_q <= 1'b0;
            last_snoop_cmd <= 2'b00;
            last_status_val <= 32'h0;
            max_status_val <= 32'h0;
        end else begin
            dma_start_q <= dma_start;
            dma_done_q <= dma_done;
            dma_error_q <= dma_error;
            dma_core_data_valid_q <= dma_core_data_valid;

            if (max_wr_fifo_count > peak_wr_fifo_count)
                peak_wr_fifo_count <= max_wr_fifo_count;

            if (dma_start && !dma_start_q) begin
                saw_dma_start <= 1'b1;
                dma_start_cycle <= cycle_count;
                $display("[%0d] DMA_START payload=%0dB coh_ctrl=%0h", cycle_count, PAYLOAD_BYTES, coh_ctrl);
            end
            if (dma_done && !dma_done_q) begin
                saw_dma_done <= 1'b1;
                dma_done_cycle <= cycle_count;
                $display("[%0d] DMA_DONE", cycle_count);
            end
            if (dma_error && !dma_error_q) begin
                saw_dma_error <= 1'b1;
                $display("[%0d] DMA_ERROR", cycle_count);
            end

            if (dc_snoop_req_fire) begin
                last_snoop_cmd <= dc_snoop_cmd;
                if (dc_snoop_cmd == 2'b01)
                    snoop_read_req_cnt <= snoop_read_req_cnt + 1;
                else if (dc_snoop_cmd == 2'b10)
                    snoop_inv_req_cnt <= snoop_inv_req_cnt + 1;
            end

            if (dc_snoop_resp_fire) begin
                if (last_snoop_cmd == 2'b01 && dc_snoop_hit) begin
                    snoop_read_hit_cnt <= snoop_read_hit_cnt + 1;
                    if (dc_snoop_data[63:0] == PT_SNOOP64)
                        saw_expected_snoop_data <= 1'b1;
                end else if (last_snoop_cmd == 2'b10 && dc_snoop_hit) begin
                    snoop_inv_hit_cnt <= snoop_inv_hit_cnt + 1;
                end
            end

            if (m2_ar_fire)
                m2_ar_cnt <= m2_ar_cnt + 1;
            if (m2_aw_fire) begin
                m2_aw_cnt <= m2_aw_cnt + 1;
                last_m2_aw_cycle <= cycle_count;
            end
            if (m2_wlast_fire)
                last_m2_wlast_cycle <= cycle_count;
            if (m2_b_fire)
                last_m2_b_cycle <= cycle_count;

            if (dma_core_data_valid && !dma_core_data_valid_q) begin
                if (dma_ptext_0 == PT_WORD0 && dma_ptext_1 == PT_WORD1)
                    saw_expected_core_ptext <= 1'b1;
            end

            if (chip.u_soc_top.u_ascon.u_slave.S_AXI_RVALID &&
                chip.u_soc_top.u_ascon.u_slave.S_AXI_RREADY &&
                chip.u_soc_top.u_ascon.u_slave.rd_addr_lat == 12'h004) begin
                slave_status_rd_cnt <= slave_status_rd_cnt + 1;
                last_status_val <= chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA;
                if (chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA > max_status_val)
                    max_status_val <= chip.u_soc_top.u_ascon.u_slave.S_AXI_RDATA;
            end
        end
    end

    task print_summary;
        integer fair_cycles;
        integer done_cycles;
        real mbps_fair;
        real mbps_done;
        begin
            fair_cycles = (dma_start_cycle >= 0 && last_m2_b_cycle >= 0) ?
                          (last_m2_b_cycle - dma_start_cycle) : -1;
            done_cycles = (dma_start_cycle >= 0 && dma_done_cycle >= 0) ?
                          (dma_done_cycle - dma_start_cycle) : -1;
            mbps_fair = (fair_cycles > 0) ? ((PAYLOAD_BYTES * 8.0 * 100.0) / fair_cycles) : 0.0;
            mbps_done = (done_cycles > 0) ? ((PAYLOAD_BYTES * 8.0 * 100.0) / done_cycles) : 0.0;
            $display("\n================ COHERENT NO-FENCE SWEEP SUMMARY ================");
            $display("payload_bytes           : %0d", PAYLOAD_BYTES);
            $display("result_mailbox          : 0x%08h", result_mailbox);
            $display("dma_start/done/error    : %0d/%0d/%0d", saw_dma_start, saw_dma_done, saw_dma_error);
            $display("snoop read req/hit      : %0d/%0d expected=%0d", snoop_read_req_cnt, snoop_read_hit_cnt, EXPECT_SNOOP_READS);
            $display("snoop inv req/hit       : %0d/%0d expected=%0d", snoop_inv_req_cnt, snoop_inv_hit_cnt, EXPECT_INV_REQ);
            $display("M2 AR/AW                : %0d/%0d expected_aw=%0d", m2_ar_cnt, m2_aw_cnt, EXPECT_AW);
            $display("expected snoop/coredata : %0d/%0d", saw_expected_snoop_data, saw_expected_core_ptext);
            $display("dma_start_cycle         : %0d", dma_start_cycle);
            $display("dma_done_cycle          : %0d", dma_done_cycle);
            $display("last M2 AW/WLAST/B      : %0d/%0d/%0d", last_m2_aw_cycle, last_m2_wlast_cycle, last_m2_b_cycle);
            $display("fair write-complete cyc : %0d", fair_cycles);
            $display("dma done cyc            : %0d", done_cycles);
            $display("throughput fair Mbps    : %0.2f", mbps_fair);
            $display("throughput done Mbps    : %0.2f", mbps_done);
            $display("peak WR FIFO count      : %0d", peak_wr_fifo_count);
            $display("max STATUS seen         : 0x%08h", max_status_val);
            $display("last STATUS seen        : 0x%08h", last_status_val);
            $display("slave STATUS reads      : %0d", slave_status_rd_cnt);
            $display("PC at exit              : 0x%08h", pc_if);
            $display("CSV,%0d,%0d,%0d,%0.2f,%0d,%0.2f,%0d,%0d,%0d,%0d,%0d,%0d",
                     PAYLOAD_BYTES, fair_cycles, done_cycles, mbps_fair, m2_aw_cnt,
                     mbps_done, snoop_read_req_cnt, snoop_inv_req_cnt, m2_ar_cnt,
                     peak_wr_fifo_count, dma_start_cycle, last_m2_b_cycle);
            $display("=================================================================\n");
        end
    endtask

    task fail;
        input [8*128-1:0] msg;
        begin
            $display("\n[FAIL] %0s", msg);
            print_summary;
            $fatal(1);
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
        $display("[TB] reset released, IMEM=%s, PAYLOAD_BYTES=%0d", `IMEM_INIT_FILE, PAYLOAD_BYTES);
        $display("[TB] expected snoop_reads=%0d inv=%0d aw=%0d coh_ctrl=%0d",
                 EXPECT_SNOOP_READS, EXPECT_INV_REQ, EXPECT_AW, COH_CTRL_VALUE);

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
                if (coh_ctrl[1:0] !== COH_CTRL_VALUE[1:0]) fail("unexpected coherence control");
                if (snoop_read_req_cnt < EXPECT_SNOOP_READS) fail("too few snoop read requests");
                if (((COH_CTRL_VALUE & 1) != 0) && (snoop_read_hit_cnt <= 0)) fail("no snoop read hits observed");
                if (((COH_CTRL_VALUE & 1) == 0) && (m2_ar_cnt <= 0)) fail("AXI read fallback not observed");
                if (snoop_inv_req_cnt != EXPECT_INV_REQ) fail("unexpected snoop invalidate count");
                if (((COH_CTRL_VALUE & 1) != 0) && !saw_expected_snoop_data) fail("snoop data did not match first dirty plaintext line");
                if (!saw_expected_core_ptext) fail("DMA did not present dirty plaintext to core");
                if (m2_aw_cnt != EXPECT_AW) fail("unexpected output write burst count");
                print_summary;
                $display("[PASS] SoC coherent no-fence sweep payload=%0dB passed", PAYLOAD_BYTES);
                $finish;
            end
        end

        fail("timeout waiting for result mailbox");
    end
endmodule
