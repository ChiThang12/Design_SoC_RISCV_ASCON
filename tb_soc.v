// ============================================================================
// tb_soc.v  —  Testbench for RISC-V SoC with ASCON Accelerator
//
// Purpose: Test basic SoC functionality before running firmware
//   - Clock & reset generation
//   - UART output monitoring
//   - DMEM state verification (plaintext/ciphertext/tag)
//   - DMA flow verification
//
// Test Flow:
//   1. Power-up reset sequence
//   2. Wait for CPU to boot
//   3. Monitor UART for firmware output ("OK\r\n" or error codes)
//   4. Check DMEM for ciphertext + tag after DMA completes
//   5. Verify results or report failure
//
// Compile:
//   cd /path/to/soc_root
//   iverilog -g2005 -I. -o sim_soc.vvp tb_soc.v
//   vvp sim_soc.vvp
// ============================================================================

`timescale 1ns / 1ps
`include "soc_top.v"
module tb_soc ();

    // ========================================================================
    // Clock & Reset Signals
    // ========================================================================
    reg  clk;
    reg  por_n;           // Power-On Reset (active-low)
    reg  ext_rst_n;       // External reset (active-low)
    wire uart_tx;
    wire uart_rx = 1'b1;  // UART RX not driven (CPU sends only)
    wire tck = 1'b0;      // JTAG TCK tied off
    wire tms = 1'b0;      // JTAG TMS tied off
    wire tdi = 1'b0;      // JTAG TDI tied off
    wire tdo;
    wire tdo_en;

    // ========================================================================
    // Test Parameters
    // ========================================================================
    localparam CLK_PERIOD   = 10;       // 10 ns = 100 MHz
    localparam MAX_SIM_TIME = 500_000;  // 500 µs = 5 ms simulation time (extended for DMA)
    localparam UART_BAUD    = 115200;
    localparam UART_BIT_NS  = 1_000_000_000 / UART_BAUD;  // ~8680 ns per bit

    // ========================================================================
    // DUT: SoC Top
    // ========================================================================
    soc_top #(
        .DATA_WIDTH    (32),
        .ADDR_WIDTH    (32),
        .ID_WIDTH      (4),
        .IMEM_SIZE     (8192),
        .DMEM_SIZE     (8192),
        .IMEM_INIT_FILE("gnu_toolchain/program.hex"),
        .POR_CYCLES    (1000),
        .SOFT_RST_STRETCH(8),
        .JTAG_IDCODE   (32'hDEAD_0001),
        .S0_BASE       (32'h0000_0000),  // IMEM
        .S0_MASK       (32'hFFFF_E000),
        .S1_BASE       (32'h1000_0000),  // DMEM
        .S1_MASK       (32'hFFFF_E000),
        .S2_BASE       (32'h2000_0000),  // ASCON
        .S2_MASK       (32'hFFFF_F000),
        .S3_BASE       (32'h3000_0000),  // SoC-Ctrl
        .S3_MASK       (32'hFFFF_F000),
        .S4_BASE       (32'h4000_0000),  // CLINT
        .S4_MASK       (32'hFFFF_0000),
        .S5_BASE       (32'h5000_0000),  // UART
        .S5_MASK       (32'hFFFF_F000),
        .S6_BASE       (32'h5001_0000),  // GPIO
        .S6_MASK       (32'hFFFF_F000),
        .S7_BASE       (32'h5002_0000),  // SPI
        .S7_MASK       (32'hFFFF_F000),
        .S8_BASE       (32'h5003_0000),  // Timer/WDT
        .S8_MASK       (32'hFFFF_F000),
        .S9_BASE       (32'h5004_0000),  // PLIC
        .S9_MASK       (32'hFFFF_F000),
        .S10_BASE      (32'h6000_0000),  // OTP
        .S10_MASK      (32'hFFFF_F000),
        .S11_BASE      (32'h6001_0000),  // DMA-Ctrl
        .S11_MASK      (32'hFFFF_F000)
    ) u_soc (
        .clk       (clk),
        .por_n     (por_n),
        .ext_rst_n (ext_rst_n),
        .uart_tx   (uart_tx),
        .uart_rx   (uart_rx),
        .tck       (tck),
        .tms       (tms),
        .tdi       (tdi),
        .tdo       (tdo),
        .tdo_en    (tdo_en)
    );

    // ========================================================================
    // SECTION 1: Clock Generation
    // ========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // SECTION 2: Reset Sequence
    // ========================================================================
    initial begin
        $display("[TB] Reset sequence starting...");
        
        // Power-on reset active (assert por_n and ext_rst_n)
        por_n     = 1'b0;
        ext_rst_n = 1'b0;
        
        // Hold reset for at least 20 clock cycles (POR_CYCLES=1000)
        repeat (100) @(posedge clk);
        
        // Release POR first
        por_n = 1'b1;
        repeat (50) @(posedge clk);
        
        // Release external reset
        ext_rst_n = 1'b1;
        
        $display("[TB] Reset released at time %0t", $time);
    end

    // ========================================================================
    // SECTION 3: UART Monitor (Receive CPU output)
    // ========================================================================
    reg [7:0] uart_rx_byte;
    integer uart_bit_idx;
    integer uart_sample_time;

    task uart_receive_byte(output [7:0] byte_out);
        integer i, sample_loc;
        reg bit_val;
    begin
        // Wait for START bit (uart_tx goes low)
        wait (uart_tx == 1'b0);
        #(UART_BIT_NS * 1.5);  // Sample at middle of first data bit
        
        byte_out = 8'h00;
        // Read 8 data bits (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            bit_val = uart_tx;
            byte_out = {bit_val, byte_out[7:1]};
            #UART_BIT_NS;
        end
        
        // Skip STOP bit
        #UART_BIT_NS;
    end
    endtask

    integer uart_timeout_count = 0;
    integer uart_char_count = 0;

    initial begin
        #(CLK_PERIOD * 200);  // Wait for reset to settle
        
        // Monitor UART for up to 64 characters (or until timeout)
        $display("[TB] Starting UART monitor...");
        
        for (uart_char_count = 0; uart_char_count < 64; uart_char_count = uart_char_count + 1) begin
            uart_timeout_count = 0;
            
            // Wait for START bit with timeout
            while (uart_tx == 1'b1 && uart_timeout_count < 1_000_000) begin
                uart_timeout_count = uart_timeout_count + 1;
                #CLK_PERIOD;
            end
            
            if (uart_timeout_count >= 1_000_000) begin
                $display("[TB] UART timeout (no more data after %0d chars)", uart_char_count);
            end else begin
                // Receive one byte
                uart_receive_byte(uart_rx_byte);
                
                // Print received character
                if (uart_rx_byte >= 32 && uart_rx_byte < 127) begin
                    $display("[UART #%0d] 0x%02X = '%c'", uart_char_count, uart_rx_byte, uart_rx_byte);
                end else if (uart_rx_byte == 8'h0D) begin
                    $display("[UART #%0d] 0x%02X = CR", uart_char_count, uart_rx_byte);
                end else if (uart_rx_byte == 8'h0A) begin
                    $display("[UART #%0d] 0x%02X = LF", uart_char_count, uart_rx_byte);
                end else begin
                    $display("[UART #%0d] 0x%02X (non-printable)", uart_char_count, uart_rx_byte);
                end
            end
        end
        
        $display("[TB] UART monitor complete");
    end

    // ========================================================================
    // SECTION 4: DMEM Monitoring (Check plaintext/ciphertext)
    // ========================================================================
    function [31:0] dmem_read_word(input [14:0] byte_offset);
        dmem_read_word = {u_soc.u_dmem.dmem.memory[byte_offset+3],
                          u_soc.u_dmem.dmem.memory[byte_offset+2],
                          u_soc.u_dmem.dmem.memory[byte_offset+1],
                          u_soc.u_dmem.dmem.memory[byte_offset+0]};
    endfunction
    
    initial begin
        #(CLK_PERIOD * 50_000);  // Wait MUCH longer for DMA to complete (~500 µs)
        
        $display("\n[TB] === DMEM State After DMA ===");
        $display("[DMEM] PTEXT_0    @ 0x1000_0000 = 0x%08X", dmem_read_word(0));
        $display("[DMEM] PTEXT_1    @ 0x1000_0004 = 0x%08X", dmem_read_word(4));
        $display("[DMEM] CTEXT_0    @ 0x1000_0010 = 0x%08X", dmem_read_word(16));
        $display("[DMEM] CTEXT_1    @ 0x1000_0014 = 0x%08X", dmem_read_word(20));
        $display("[DMEM] TAG_0      @ 0x1000_0020 = 0x%08X", dmem_read_word(32));
        $display("[DMEM] TAG_1      @ 0x1000_0024 = 0x%08X", dmem_read_word(36));
        $display("[DMEM] TAG_2      @ 0x1000_0028 = 0x%08X", dmem_read_word(40));
        $display("[DMEM] TAG_3      @ 0x1000_002C = 0x%08X", dmem_read_word(44));
        $display("[DMEM] RETCODE    @ 0x1000_0058 = 0x%08X", dmem_read_word(88));
        
        // Check if RETCODE is 0 (success)
        if (dmem_read_word(88) == 32'h0) begin
            $display("[TB] ✓ SUCCESS: RETCODE = 0 (DMA completed successfully)");
        end else if (dmem_read_word(88) == 32'hFFFFFFFF) begin
            $display("[TB] ✗ PENDING: RETCODE still uninitialized");
        end else begin
            $display("[TB] ✗ ERROR: RETCODE = 0x%08X (see firmware for error codes)", 
                     dmem_read_word(88));
        end
    end

    // ========================================================================
    // SECTION 5: Simulation Control
    // ========================================================================
    initial begin
        #(CLK_PERIOD * MAX_SIM_TIME);
        $display("\n[TB] === Simulation Timeout (reached %0d ns) ===", CLK_PERIOD * MAX_SIM_TIME);
        $display("[TB] Test suspended (may continue if needed)");
        $finish;
    end

    // ========================================================================
    // SECTION 6: Waveform Dump (optional)
    // ========================================================================
    initial begin
        // Uncomment to generate VCD file for waveform viewing
        // $dumpfile("tb_soc.vcd");
        // $dumpvars(0, tb_soc);
    end

    // ========================================================================
    // SECTION 7: Test Summary
    // ========================================================================
    initial begin
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════════╗");
        $display("║  RISC-V SoC + ASCON Accelerator Testbench                     ║");
        $display("║  Clock: 100 MHz (10 ns period)                               ║");
        $display("║  Test Duration: %0d ns (~%0d µs)                          ║",
                 CLK_PERIOD * MAX_SIM_TIME, (CLK_PERIOD * MAX_SIM_TIME) / 1000);
        $display("║                                                                ║");
        $display("║  Monitoring:                                                   ║");
        $display("║    - UART output (plaintext → ciphertext messages)            ║");
        $display("║    - DMEM state (PTEXT, CTEXT, TAG, RETCODE)                  ║");
        $display("║    - DMA completion (by RETCODE value)                        ║");
        $display("║                                                                ║");
        $display("║  Expected UART output: \"OK\\r\\nC:...T:...\\r\\n\"            ║");
        $display("║  On success: RETCODE @ 0x1000_0058 should be 0x0000_0000      ║");
        $display("║  On timeout: CPU still running (extend MAX_SIM_TIME)          ║");
        $display("║  On error: RETCODE = 0xFFFF_XXXX (see firmware comments)      ║");
        $display("╚════════════════════════════════════════════════════════════════╝\n");
    end

endmodule
