`timescale 1ns/1ps

// ============================================================================
// tb_notebook_host.v
//
// Generic SoC simulation harness that behaves like a tiny notebook-side host:
//   - loads firmware from fpga/os/firmware through soc_hs SIM_MODE=1
//   - monitors the SoC UART TX stream as a console
//   - can inject host command bytes into SoC UART RX from a text/binary file
//
// Override examples:
//   +IMEM_HEX=D:/Design_SoC_RISCV_ASCON H3/fpga/os/firmware/test_freertos_kernel_smoke.hex
//   +HOST_TX_FILE=../tb/host_commands.txt
//   +HOST_TX_DELAY=5000
//   +TIMEOUT=2000000
//   +VCD=../sim_log/notebook_host.vcd
//
// Compile-time overrides:
//   -D BAUD_DIV=16          fast sim firmware
//   -D BAUD_DIV=868         115200 baud at 100 MHz firmware
//   -D FINISH_ON_PASS       finish when "[PASS]" appears on UART
// ============================================================================

`ifndef IMEM_INIT_FILE
  `define IMEM_INIT_FILE "D:/Design_SoC_RISCV_ASCON H3/fpga/os/firmware/test_freertos_kernel_smoke.hex"
`endif

`ifndef BAUD_DIV
  `define BAUD_DIV 16
`endif

`ifndef DEFAULT_TIMEOUT
  `define DEFAULT_TIMEOUT 1500000
`endif

module tb_notebook_host;

    localparam CLK_PERIOD_NS = 10;
    localparam UART_BIT_CYCLES = (`BAUD_DIV < 1) ? 1 : `BAUD_DIV;

    reg clk;
    reg por_n;
    reg ext_rst_n;

    wire uart_tx;
    reg  uart_rx;

    reg  jtag_tck;
    reg  jtag_tms;
    reg  jtag_tdi;
    wire jtag_tdo;

    wire spi_sck;
    wire spi_mosi;
    wire spi_cs_n;
    wire [31:0] gpio;
    wire wdt_rst_req;

    integer timeout_cycles;
    integer host_tx_delay;
    integer host_fd;
    integer host_ch;
    integer i;
    reg [8*512-1:0] host_tx_file;
    reg [8*512-1:0] vcd_file;

    reg pass_seen;
    integer pass_match;

    assign gpio = 32'hzzzz_zzzz;

    soc_hs #(
        .SIM_MODE(1),
        .IMEM_INIT_FILE(`IMEM_INIT_FILE),
        .ENABLE_CPU1(0)
    ) dut (
        .clk_in     (clk),
        .por_n      (por_n),
        .ext_rst_n  (ext_rst_n),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .tck        (jtag_tck),
        .tms        (jtag_tms),
        .tdi        (jtag_tdi),
        .tdo        (jtag_tdo),
        .spi_sck    (spi_sck),
        .spi_mosi   (spi_mosi),
        .spi_miso   (1'b1),
        .spi_cs_n   (spi_cs_n),
        .gpio       (gpio),
        .wdt_rst_req(wdt_rst_req)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    initial begin
        timeout_cycles = `DEFAULT_TIMEOUT;
        host_tx_delay  = 0;
        if (!$value$plusargs("TIMEOUT=%d", timeout_cycles))
            timeout_cycles = `DEFAULT_TIMEOUT;
        if (!$value$plusargs("HOST_TX_DELAY=%d", host_tx_delay))
            host_tx_delay = 0;

        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_notebook_host);
        end

        por_n     = 1'b0;
        ext_rst_n = 1'b0;
        uart_rx   = 1'b1;
        jtag_tck  = 1'b0;
        jtag_tms  = 1'b1;
        jtag_tdi  = 1'b0;
        pass_seen  = 1'b0;
        pass_match = 0;

        $display("[NB-HOST] Firmware default: %0s", `IMEM_INIT_FILE);
        $display("[NB-HOST] UART bit cycles: %0d", UART_BIT_CYCLES);

        repeat (20) @(posedge clk);
        ext_rst_n = 1'b1;
        repeat (1200) @(posedge clk);
        por_n = 1'b1;

        fork
            notebook_host_tx_thread();
            timeout_thread();
        join
    end

    task timeout_thread;
    begin
        repeat (timeout_cycles) @(posedge clk);
        $display("");
        $display("[NB-HOST][TIMEOUT] No terminal PASS before %0d cycles", timeout_cycles);
        $display("[NB-HOST] boot_done=%0b cpu_rst_n=%0b uart_active=%0b",
                 dut.u_soc_top.boot_done,
                 dut.u_soc_top.cpu_rst_n,
                 dut.u_soc_top.uart_active);
        $finish;
    end
    endtask

    task notebook_host_tx_thread;
    begin
        wait (dut.u_soc_top.boot_done === 1'b1);
        $display("[NB-HOST] boot_done observed at %0t", $time);
        repeat (host_tx_delay) @(posedge clk);

        if ($value$plusargs("HOST_TX_FILE=%s", host_tx_file)) begin
            host_fd = $fopen(host_tx_file, "rb");
            if (host_fd == 0) begin
                $display("[NB-HOST][WARN] Cannot open HOST_TX_FILE=%0s", host_tx_file);
            end else begin
                $display("[NB-HOST] sending HOST_TX_FILE=%0s", host_tx_file);
                host_ch = $fgetc(host_fd);
                while (host_ch >= 0) begin
                    host_send_byte(host_ch[7:0]);
                    host_ch = $fgetc(host_fd);
                end
                $fclose(host_fd);
                $display("[NB-HOST] host TX file completed at %0t", $time);
            end
        end
    end
    endtask

    task host_send_byte;
        input [7:0] b;
    begin
        uart_rx <= 1'b0;  // start
        repeat (UART_BIT_CYCLES) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx <= b[i];
            repeat (UART_BIT_CYCLES) @(posedge clk);
        end
        uart_rx <= 1'b1;  // stop
        repeat (UART_BIT_CYCLES) @(posedge clk);
    end
    endtask

    task monitor_uart_byte;
        reg [7:0] b;
        integer bit_idx;
    begin
        @(negedge uart_tx);
        repeat (UART_BIT_CYCLES + (UART_BIT_CYCLES/2)) @(posedge clk);
        for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            b[bit_idx] = uart_tx;
            repeat (UART_BIT_CYCLES) @(posedge clk);
        end
        repeat (UART_BIT_CYCLES) @(posedge clk);

        if (b == 8'h0a) begin
            $write("\n");
        end else if (b != 8'h0d) begin
            $write("%c", b);
        end

        update_pass_detector(b);
        if (pass_seen && (b == 8'h0a)) begin
            $display("[NB-HOST] PASS line completed at %0t", $time);
`ifdef FINISH_ON_PASS
            $finish;
`endif
        end
    end
    endtask

    task update_pass_detector;
        input [7:0] b;
    begin
        case (pass_match)
            0: pass_match = (b == 8'h5b) ? 1 : 0; // [
            1: pass_match = (b == 8'h50) ? 2 : ((b == 8'h5b) ? 1 : 0); // P
            2: pass_match = (b == 8'h41) ? 3 : ((b == 8'h5b) ? 1 : 0); // A
            3: pass_match = (b == 8'h53) ? 4 : ((b == 8'h5b) ? 1 : 0); // S
            4: pass_match = (b == 8'h53) ? 5 : ((b == 8'h5b) ? 1 : 0); // S
            5: pass_match = (b == 8'h5d) ? 6 : ((b == 8'h5b) ? 1 : 0); // ]
            default: pass_match = 0;
        endcase

        if (pass_match == 6) begin
            pass_seen = 1'b1;
        end
    end
    endtask

    initial begin
        forever begin
            monitor_uart_byte();
        end
    end

endmodule
