`timescale 1ns/1ps

`define USE_ASCON_LEGACY
`include "soc_hs.v"

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "gnu_toolchain/tests/test_ascon_dma_fence_512b.hex"
`endif

`ifndef TIMEOUT
  `define TIMEOUT 3000000
`endif

module run_soc_fence_512b;
    parameter CLK_PERIOD = 10;

    localparam [31:0] RET_RUNNING = 32'hCAFE0001;
    localparam [31:0] RET_PASS    = 32'hCAFE0000;
    localparam [31:0] PT_WORD0    = 32'hA5000000;
    localparam [31:0] PT_WORD1    = 32'h5A000000;

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

    wire m2_ar_fire    = chip.u_soc_top.m2_arvalid && chip.u_soc_top.m2_arready;
    wire m2_aw_fire    = chip.u_soc_top.m2_awvalid && chip.u_soc_top.m2_awready;
    wire m2_wlast_fire = chip.u_soc_top.m2_wvalid && chip.u_soc_top.m2_wready && chip.u_soc_top.m2_wlast;
    wire m2_b_fire     = chip.u_soc_top.m2_bvalid && chip.u_soc_top.m2_bready;

    wire dma_start = chip.u_soc_top.u_ascon.u_slave.dma_start;
    wire dma_done  = chip.u_soc_top.u_ascon.dma_done_w;
    wire dma_error = chip.u_soc_top.u_ascon.u_slave.status_dma_error |
                     chip.u_soc_top.u_ascon.u_slave.status_error;
    wire [31:0] result_mailbox = chip.u_soc_top.u_ascon.u_slave.reg_wdt_cfg;

    wire [31:0] dbg_cnt_rd_issue_w         = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_rd_issue_w;
    wire [31:0] dbg_cnt_rd_done_w          = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_rd_done_w;
    wire [31:0] dbg_cnt_wr_done_w          = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_wr_done_w;
    wire [31:0] dbg_cnt_payload_feed_w     = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_payload_feed_w;
    wire [31:0] dbg_cnt_payload_chain_w    = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_payload_chain_w;
    wire [31:0] dbg_cnt_write_chain_w      = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_write_chain_w;
    wire [31:0] dbg_cnt_ingress_swap_w     = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_ingress_swap_w;
    wire [31:0] dbg_cnt_egress_swap_w      = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_egress_swap_w;
    wire [31:0] dbg_cnt_busy_cycles_w      = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_busy_cycles_w;
    wire [31:0] dbg_cnt_core_wait_cycles_w = chip.u_soc_top.u_ascon.u_dma.dbg_cnt_core_wait_cycles_w;

    integer cycle_count;
    integer m2_ar_cnt;
    integer m2_aw_cnt;
    integer dma_start_cycle;
    integer last_m2_aw_cycle;
    integer last_m2_wlast_cycle;
    integer last_m2_b_cycle;
    reg saw_dma_start;
    reg saw_dma_done;
    reg saw_dma_error;
    reg dma_start_q;
    reg dma_done_q;
    reg dma_error_q;

    always @(posedge clk) begin
        if (!ext_rst_n_r)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

    always @(posedge clk) begin
        if (!ext_rst_n_r) begin
            m2_ar_cnt <= 0;
            m2_aw_cnt <= 0;
            dma_start_cycle <= -1;
            last_m2_aw_cycle <= -1;
            last_m2_wlast_cycle <= -1;
            last_m2_b_cycle <= -1;
            saw_dma_start <= 1'b0;
            saw_dma_done <= 1'b0;
            saw_dma_error <= 1'b0;
            dma_start_q <= 1'b0;
            dma_done_q <= 1'b0;
            dma_error_q <= 1'b0;
        end else begin
            dma_start_q <= dma_start;
            dma_done_q  <= dma_done;
            dma_error_q <= dma_error;

            if (dma_start && !dma_start_q) begin
                saw_dma_start <= 1'b1;
                dma_start_cycle <= cycle_count;
                $display("[%0d] DMA_START 512B", cycle_count);
            end
            if (dma_done && !dma_done_q) begin
                saw_dma_done <= 1'b1;
                $display("[%0d] DMA_DONE 512B", cycle_count);
            end
            if (dma_error && !dma_error_q) begin
                saw_dma_error <= 1'b1;
                $display("[%0d] DMA_ERROR 512B", cycle_count);
            end

            if (m2_ar_fire) begin
                m2_ar_cnt <= m2_ar_cnt + 1;
            end
            if (m2_aw_fire) begin
                m2_aw_cnt <= m2_aw_cnt + 1;
                last_m2_aw_cycle <= cycle_count;
            end
            if (m2_wlast_fire)
                last_m2_wlast_cycle <= cycle_count;
            if (m2_b_fire)
                last_m2_b_cycle <= cycle_count;
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
            $display("\n================ FENCE 512B SUMMARY ================");
            $display("cycles                  : %0d", cycle_count);
            $display("result_mailbox          : 0x%08h", result_mailbox);
            $display("dma_start/done/error    : %0d/%0d/%0d", saw_dma_start, saw_dma_done, saw_dma_error);
            $display("M2 AR/AW                : %0d/%0d", m2_ar_cnt, m2_aw_cnt);
            $display("dma_start_cycle         : %0d", dma_start_cycle);
            $display("last M2 AW/WLAST/B      : %0d/%0d/%0d", last_m2_aw_cycle, last_m2_wlast_cycle, last_m2_b_cycle);
            if (dma_start_cycle >= 0 && last_m2_b_cycle >= 0)
                $display("fair write-complete cyc : %0d", last_m2_b_cycle - dma_start_cycle);
            $display("dbg rd_issue/rd_done    : %0d/%0d", dbg_cnt_rd_issue_w, dbg_cnt_rd_done_w);
            $display("dbg wr_done             : %0d", dbg_cnt_wr_done_w);
            $display("dbg payload feed/chain  : %0d/%0d", dbg_cnt_payload_feed_w, dbg_cnt_payload_chain_w);
            $display("dbg write chain         : %0d", dbg_cnt_write_chain_w);
            $display("dbg ingress/egress swap : %0d/%0d", dbg_cnt_ingress_swap_w, dbg_cnt_egress_swap_w);
            $display("dbg busy/core-wait cyc  : %0d/%0d", dbg_cnt_busy_cycles_w, dbg_cnt_core_wait_cycles_w);
            $display("PC                      : 0x%08h", pc_if);
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
            if (result_mailbox !== RET_RUNNING && result_mailbox !== 32'h0) begin
                if (result_mailbox !== RET_PASS)
                    fail("firmware reported failure");

                if (!saw_dma_start) fail("DMA did not start");
                if (!saw_dma_done) fail("DMA did not complete");
                if (saw_dma_error) fail("DMA/core error asserted");
                if (dbg_cnt_payload_feed_w == 0) fail("payload feeder never fired");
                if (dbg_cnt_rd_issue_w == 0 || dbg_cnt_wr_done_w == 0) fail("debug counters did not advance");

                print_summary;
                $display("[PASS] SoC software-fenced DMA 512B test passed");
                $finish;
            end
        end

        fail("timeout waiting for result mailbox");
    end
endmodule
