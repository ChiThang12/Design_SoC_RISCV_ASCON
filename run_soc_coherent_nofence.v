`timescale 1ns/1ps

`include "soc_hs.v"

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "gnu_toolchain/tests/test_ascon_dma_coherent_nofence.hex"
`endif

`ifndef TIMEOUT
  `define TIMEOUT 2000000
`endif

module run_soc_coherent_nofence;
    parameter CLK_PERIOD = 10;

    localparam [31:0] RET_RUNNING = 32'hCAFE0001;
    localparam [31:0] RET_PASS    = 32'hCAFE0000;
    localparam [31:0] PT_WORD0    = 32'hA5A50001;
    localparam [31:0] PT_WORD1    = 32'h5A5A0002;
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
    wire [31:0] m2_araddr = chip.u_soc_top.m2_araddr;
    wire [31:0] m2_awaddr = chip.u_soc_top.m2_awaddr;

    wire dma_start = chip.u_soc_top.u_ascon.u_slave.dma_start;
    wire dma_done  = chip.u_soc_top.u_ascon.u_slave.status_dma_done;
    wire dma_error = chip.u_soc_top.u_ascon.u_slave.status_dma_error |
                     chip.u_soc_top.u_ascon.u_slave.status_error;
    wire [31:0] coh_ctrl = {30'h0, chip.u_soc_top.u_ascon.u_slave.reg_dma_coh_ctrl};
    wire [31:0] result_mailbox = chip.u_soc_top.u_ascon.u_slave.reg_wdt_cfg;

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
    reg saw_expected_snoop_data;
    reg saw_expected_core_ptext;
    reg saw_dma_start;
    reg saw_dma_done;
    reg saw_dma_error;
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

    always @(posedge clk) begin
        if (!ext_rst_n_r) begin
            snoop_read_req_cnt <= 0;
            snoop_read_hit_cnt <= 0;
            snoop_write_req_cnt <= 0;
            snoop_write_hit_cnt <= 0;
            m2_ar_cnt <= 0;
            m2_aw_cnt <= 0;
            core_start_cnt <= 0;
            saw_expected_snoop_data <= 1'b0;
            saw_expected_core_ptext <= 1'b0;
            saw_dma_start <= 1'b0;
            saw_dma_done <= 1'b0;
            saw_dma_error <= 1'b0;
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
                $display("[%0d] M2_AW addr=%08h", cycle_count, m2_awaddr);
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
            $display("\n================ COHERENT NO-FENCE SUMMARY ================");
            $display("cycles                  : %0d", cycle_count);
            $display("result_mailbox          : 0x%08h", result_mailbox);
            $display("dma_start/done/error    : %0d/%0d/%0d", saw_dma_start, saw_dma_done, saw_dma_error);
            $display("snoop read req/hit      : %0d/%0d", snoop_read_req_cnt, snoop_read_hit_cnt);
            $display("snoop inv req/hit       : %0d/%0d", snoop_write_req_cnt, snoop_write_hit_cnt);
            $display("expected snoop/coredata : %0d/%0d", saw_expected_snoop_data, saw_expected_core_ptext);
            $display("M2 AR/AW                : %0d/%0d", m2_ar_cnt, m2_aw_cnt);
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
                if (coh_ctrl[1:0] !== 2'b11) fail("coherence control not enabled");
                if (snoop_read_req_cnt < 1) fail("no snoop read request observed");
                if (snoop_read_hit_cnt < 1) fail("no snoop read hit observed");
                if (!saw_expected_snoop_data) fail("snoop data did not match dirty plaintext");
                if (!saw_expected_core_ptext) fail("DMA did not present dirty plaintext to core data input");
                if (m2_ar_cnt != 0) fail("DMA issued AXI read despite snoop hit");
                if (m2_aw_cnt < 1) fail("DMA did not write output");

                print_summary;
                $display("[PASS] SoC coherent DMA no-fence test passed");
                $finish;
            end
        end

        fail("timeout waiting for result mailbox");
    end
endmodule
