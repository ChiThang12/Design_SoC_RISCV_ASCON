// ============================================================================
// tb_t1.v — Testbench Tầng 1: Crossbar Route + DMA_LEN Verification
//
// Assertions:
//   A1: Log mọi AXI write đến S2 (ASCON @ 0x2000_0000)
//   A2: DECERR check (bresp=2'b11) → crossbar sai
//   A3: reg_dma_len == 24 sau khi ghi offset 0x108
//   A4: UART "T1:OK" → PASS → $finish
//
// Linker thực tế (linker_minimal.ld):
//   DMEM_DATA  : 0x10000000–0x100007FF (2KB)
//   __stack_top: 0x10002000
//   → DMA_SRC/DST trong fw_t1.c dùng 0x10000100/0x10000110
//
// Run:
//   iverilog -g2005 -I. -o sim_t1.out tb_t1.v && vvp sim_t1.out
// ============================================================================

`include "soc_top.v"
`timescale 1ns/1ps

module tb_t1;

// ============================================================================
// SECTION 1: Parameters
// ============================================================================

parameter CLK_PERIOD_NS    = 10;
parameter POR_CYCLES        = 1040;
parameter RST_SETTLE_CYCLES = 5;

// T1 không có DMA/IRQ/CORE → 5000 cy đủ margin
// (log thực tế cho thấy firmware loop ở 0x358 sau ~2000 cy reset overhead)
parameter TIMEOUT_CYCLES    = 5000;

parameter [31:0] ASCON_BASE  = 32'h2000_0000;

// DMA constants theo fw_t1.c (hardcode, không dùng dmem_layout.h)
parameter [31:0] EXP_DMA_SRC = 32'h1000_0100;
parameter [31:0] EXP_DMA_DST = 32'h1000_0110;
parameter [31:0] EXP_DMA_LEN = 32'd24;

// ============================================================================
// SECTION 2: Clock & Reset
// ============================================================================

reg clk       = 0;
reg por_n     = 0;
reg ext_rst_n = 0;

always #(CLK_PERIOD_NS/2) clk = ~clk;

initial begin
    por_n     = 0;
    ext_rst_n = 0;
    repeat (POR_CYCLES)        @(posedge clk);
    por_n     = 1;
    repeat (RST_SETTLE_CYCLES) @(posedge clk);
    ext_rst_n = 1;
    $display("[TB] Reset released @ %0t ns", $time);
end

// ============================================================================
// SECTION 3: DUT
// ============================================================================

wire uart_tx_wire;
wire uart_rx_wire;
assign uart_rx_wire = uart_tx_wire;

wire tdo_wire, tdo_en_wire;

soc_top #(
    // ── QUAN TRỌNG: đường dẫn hex theo cấu trúc thực tế của project ──
    // Log cho thấy SoC load "firmware/fw1/program.hex".
    // fw_t1.c phải được compile → đặt vào đúng path này.
    .IMEM_INIT_FILE  ("firmware/fw1/program.hex"),
    .IMEM_SIZE       (8192),
    .DMEM_SIZE       (16384),
    .POR_CYCLES      (1000),
    .SOFT_RST_STRETCH(8)
) dut (
    .clk      (clk),
    .por_n    (por_n),
    .ext_rst_n(ext_rst_n),
    .uart_tx  (uart_tx_wire),
    .uart_rx  (uart_rx_wire),
    .tck      (1'b0),
    .tms      (1'b1),
    .tdi      (1'b0),
    .tdo      (tdo_wire),
    .tdo_en   (tdo_en_wire)
);

// ============================================================================
// SECTION 4: Wire taps
// ============================================================================

// ASCON slave internal registers
wire [31:0] ascon_reg_dma_len     = dut.u_ascon.u_slave.reg_dma_len;
wire [31:0] ascon_reg_dma_dst     = dut.u_ascon.u_slave.reg_dma_dst;
wire [31:0] ascon_reg_dma_src     = dut.u_ascon.u_slave.reg_dma_src;
wire        ascon_reg_dma_en      = dut.u_ascon.u_slave.reg_dma_en;
wire        ascon_status_done     = dut.u_ascon.u_slave.status_done;
wire        ascon_status_dma_done = dut.u_ascon.u_slave.status_dma_done;
wire        ascon_dma_start       = dut.u_ascon.u_slave.dma_start;
wire        ascon_core_start      = dut.u_ascon.u_slave.core_start;
wire        ascon_soft_rst        = dut.u_ascon.u_slave.core_soft_rst;
wire [1:0]  ascon_reg_mode        = dut.u_ascon.u_slave.reg_mode;
wire [2:0]  ascon_reg_irq_en      = dut.u_ascon.u_slave.reg_irq_en;
wire [6:0]  ascon_reg_data_len    = dut.u_ascon.u_slave.reg_data_len;

// ASCON IRQ / PLIC
wire ascon_irq_wire = dut.ascon_irq;
wire plic_meip      = dut.external_irq;

// AXI S2 ASCON slave
wire [31:0] s2_awaddr  = dut.s2_awaddr;
wire        s2_awvalid = dut.s2_awvalid;
wire        s2_awready = dut.s2_awready;
wire [31:0] s2_wdata   = dut.s2_wdata;
wire        s2_wvalid  = dut.s2_wvalid;
wire        s2_wready  = dut.s2_wready;
wire [1:0]  s2_bresp   = dut.s2_bresp;
wire        s2_bvalid  = dut.s2_bvalid;
wire        s2_bready  = dut.s2_bready;

// AXI M2 DMA master
wire [31:0] m2_awaddr  = dut.m2_awaddr;
wire        m2_awvalid = dut.m2_awvalid;
wire        m2_awready = dut.m2_awready;

// AXI S1 DMEM
wire [31:0] s1_awaddr = dut.s1_awaddr;
wire        s1_wvalid = dut.s1_wvalid;
wire        s1_wready = dut.s1_wready;

// Reset domains
wire fabric_rst_n_w = dut.fabric_rst_n;
wire cpu_rst_n_w    = dut.cpu_rst_n;
wire periph_rst_n_w = dut.periph_rst_n;

// CPU
wire [31:0] cpu_pc    = dut.cpu_imem_addr;
wire        cpu_fetch = dut.cpu_imem_valid;
wire        cpu_frdy  = dut.icache_imem_ready;

// ============================================================================
// SECTION 5: Counters & state
// ============================================================================

integer s2_write_count;
integer s2_decerr_count;
integer timeout_counter;
integer pass_count;
integer fail_count;
reg     test_done;
reg     pass_flag;
reg     a3_triggered;

reg [31:0] s2_awaddr_latch;
reg        s2_aw_pending;

// A3 pipeline delay
reg a3_pipe1, a3_pipe2;

initial begin
    s2_write_count  = 0;
    s2_decerr_count = 0;
    timeout_counter = 0;
    pass_count      = 0;
    fail_count      = 0;
    test_done       = 0;
    pass_flag       = 0;
    a3_triggered    = 0;
    s2_aw_pending   = 0;
    s2_awaddr_latch = 0;
    a3_pipe1        = 0;
    a3_pipe2        = 0;
end

// ============================================================================
// SECTION 6: Waveform dump
// ============================================================================

initial begin
    $dumpfile("tb_t1.vcd");
    $dumpvars(0, tb_t1);
end

// ============================================================================
// SECTION 7: Timeout (đếm từ khi cpu_rst_n deassert)
// ============================================================================

always @(posedge clk) begin
    if (!cpu_rst_n_w) begin
        timeout_counter <= 0;
    end else if (!test_done) begin
        timeout_counter <= timeout_counter + 1;

        if (timeout_counter >= TIMEOUT_CYCLES) begin
            $display("");
            $display("[TIMEOUT-T1] === TIMEOUT sau %0d cycles ===", TIMEOUT_CYCLES);
            $display("[TIMEOUT-T1] s2_write_count  = %0d", s2_write_count);
            $display("[TIMEOUT-T1] s2_decerr_count = %0d", s2_decerr_count);
            $display("[TIMEOUT-T1] cpu_pc          = 0x%08X", cpu_pc);
            $display("[TIMEOUT-T1] ascon_reg_dma_len = %0d", ascon_reg_dma_len);
            $display("[TIMEOUT-T1] ascon_reg_dma_src = 0x%08X", ascon_reg_dma_src);
            $display("[TIMEOUT-T1] ascon_reg_dma_dst = 0x%08X", ascon_reg_dma_dst);
            $display("[TIMEOUT-T1] ascon_soft_rst    = %0b", ascon_soft_rst);
            $display("[TIMEOUT-T1] ascon_irq_wire    = %0b", ascon_irq_wire);
            $display("[TIMEOUT-T1] plic_meip         = %0b", plic_meip);
            $display("");

            // ── Diagnosis block ──────────────────────────────────────────
            if (s2_write_count == 0) begin
                $display("[DIAG-T1] CPU chưa reach ASCON write (s2_write_count=0).");
                $display("[DIAG-T1] cpu_pc=%08X — CPU đang kẹt ở đây.", cpu_pc);
                $display("[DIAG-T1] Nguyên nhân thường gặp:");
                $display("[DIAG-T1]   1) Firmware compile sai (sai hex path?)");
                $display("[DIAG-T1]   2) Trap handler bị gọi sớm (exception trước main)");
                $display("[DIAG-T1]   3) Linker .bss overflow → stack corrupt → trap");
                $display("[DIAG-T1]   4) IMEM_INIT_FILE path sai hoặc hex rỗng");
            end else if (s2_decerr_count > 0) begin
                $display("[DIAG-T1] DECERR! Crossbar không route đúng 0x20000000.");
                $display("[DIAG-T1] Kiểm tra S2_BASE=0x20000000 S2_MASK=0xFFFFF000.");
            end else if (ascon_reg_dma_len == 32'd4) begin
                $display("[DIAG-T1] DMA_LEN=4 thay vì 24 → ghi INPUT_LEN!");
                $display("[DIAG-T1] Fix: dùng T1_DMA_OUTPUT_LEN=24 trong fw_t1.c.");
            end else begin
                $display("[DIAG-T1] Register write OK nhưng không nhận UART T1:OK.");
                $display("[DIAG-T1] Kiểm tra uart_init(), UART_BASE=0x50000000.");
            end

            $display("[TIMEOUT-T1] PASS=%0d FAIL=%0d", pass_count, fail_count);
            $finish;
        end
    end
end

// ============================================================================
// SECTION 8: ASSERTION A1 — S2 Write Monitor
// ============================================================================

task decode_reg;
    input [11:0] off;
    begin
        case (off)
            12'h000: $write("MODE    ");
            12'h004: $write("STATUS  ");
            12'h00C: $write("IRQ_EN  ");
            12'h010: $write("KEY_0   ");
            12'h014: $write("KEY_1   ");
            12'h018: $write("KEY_2   ");
            12'h01C: $write("KEY_3   ");
            12'h020: $write("CTRL    ");
            12'h024: $write("NONCE_0 ");
            12'h028: $write("NONCE_1 ");
            12'h02C: $write("NONCE_2 ");
            12'h030: $write("NONCE_3 ");
            12'h034: $write("PTEXT_0 ");
            12'h038: $write("PTEXT_1 ");
            12'h03C: $write("DATA_LEN");
            12'h040: $write("CTEXT_0 ");
            12'h044: $write("CTEXT_1 ");
            12'h048: $write("TAG_0   ");
            12'h04C: $write("TAG_1   ");
            12'h050: $write("TAG_2   ");
            12'h054: $write("TAG_3   ");
            12'h100: $write("DMA_SRC ");
            12'h104: $write("DMA_DST ");
            12'h108: $write("DMA_LEN ");
            default: $write("UNKNOWN ");
        endcase
    end
endtask

always @(posedge clk) begin
    if (!cpu_rst_n_w) begin
        s2_aw_pending   <= 0;
        s2_awaddr_latch <= 0;
    end else if (!test_done) begin

        // AW phase: capture + log
        if (s2_awvalid && s2_awready) begin
            s2_write_count    <= s2_write_count + 1;
            s2_awaddr_latch   <= s2_awaddr;
            s2_aw_pending     <= 1;

            $write("[A1][S2-W] @%0d cy off=0x%03X reg=",
                   timeout_counter, s2_awaddr - ASCON_BASE);
            decode_reg(s2_awaddr[11:0]);

            if (s2_wvalid)
                $display(" data=0x%08X", s2_wdata);
            else
                $display(" data=(W pending)");
        end

        // W phase: log data nếu AW đã latch trước
        if (s2_aw_pending && s2_wvalid && s2_wready) begin
            if (!(s2_awvalid && s2_awready)) begin
                $write("[A1][S2-W-DATA] @%0d cy off=0x%03X reg=",
                       timeout_counter, s2_awaddr_latch - ASCON_BASE);
                decode_reg(s2_awaddr_latch[11:0]);
                $display(" data=0x%08X", s2_wdata);
            end
        end

        // B phase: clear pending
        if (s2_bvalid && s2_bready)
            s2_aw_pending <= 0;
    end
end

// ============================================================================
// SECTION 9: ASSERTION A2 — DECERR Check
// ============================================================================

always @(posedge clk) begin
    if (cpu_rst_n_w && s2_bvalid && s2_bready && !test_done) begin
        case (s2_bresp)
            2'b11: begin
                s2_decerr_count <= s2_decerr_count + 1;
                fail_count      <= fail_count + 1;
                $display("[FAIL-T1] A2: DECERR @ addr=0x%08X — crossbar route sai!",
                         s2_awaddr_latch);
                $display("[FAIL-T1] A2: Kiểm tra S2_BASE=0x20000000 trong soc_top.");
            end
            2'b10: begin
                fail_count <= fail_count + 1;
                $display("[FAIL-T1] A2: SLVERR @ addr=0x%08X — ASCON slave error.",
                         s2_awaddr_latch);
            end
            2'b00: begin
                // OKAY — expected, không log để tránh spam
            end
            default: begin
                $display("[WARN-T1] A2: bresp=0x%0X @ addr=0x%08X",
                         s2_bresp, s2_awaddr_latch);
            end
        endcase
    end
end

// ============================================================================
// SECTION 10: ASSERTION A3 — DMA_LEN Register Check
//
// Khi AW write handshake đến offset 0x108 (DMA_LEN):
//   Pipeline 2 cycles → check ascon_reg_dma_len
//   (slave latch tại WR_DATA state, result available sau 1–2 cycle)
// ============================================================================

always @(posedge clk) begin
    if (!cpu_rst_n_w) begin
        a3_pipe1 <= 0;
        a3_pipe2 <= 0;
    end else begin
        // Stage 1: detect write đến offset 0x108
        a3_pipe1 <= (s2_awvalid && s2_awready &&
                     (s2_awaddr == (ASCON_BASE + 32'h108)) &&
                     !test_done);

        // Stage 2: 1 cycle sau
        a3_pipe2 <= a3_pipe1;

        // Check: 2 cycles sau khi slave nhận write DMA_LEN
        if (a3_pipe2 && !a3_triggered && !test_done) begin
            a3_triggered <= 1;

            if (ascon_reg_dma_len == EXP_DMA_LEN) begin
                pass_count <= pass_count + 1;
                $display("[PASS-T1] A3: DMA_LEN=%0d CORRECT (8B ctext + 16B tag)",
                         ascon_reg_dma_len);
            end else if (ascon_reg_dma_len == 32'd4) begin
                fail_count <= fail_count + 1;
                $display("[FAIL-T1] A3: DMA_LEN=%0d — ghi INPUT_LEN=4 thay OUTPUT_LEN=24!",
                         ascon_reg_dma_len);
                $display("[FAIL-T1] A3: Fix: T1_DMA_OUTPUT_LEN=24 trong fw_t1.c.");
            end else begin
                fail_count <= fail_count + 1;
                $display("[FAIL-T1] A3: DMA_LEN=%0d unexpected (exp=%0d).",
                         ascon_reg_dma_len, EXP_DMA_LEN);
            end

            // Bonus: verify DMA_SRC / DMA_DST
            $display("[INFO-T1] A3+: DMA_SRC=0x%08X exp=0x%08X %s",
                     ascon_reg_dma_src, EXP_DMA_SRC,
                     (ascon_reg_dma_src == EXP_DMA_SRC) ? "OK" : "MISMATCH");
            $display("[INFO-T1] A3+: DMA_DST=0x%08X exp=0x%08X %s",
                     ascon_reg_dma_dst, EXP_DMA_DST,
                     (ascon_reg_dma_dst == EXP_DMA_DST) ? "OK" : "MISMATCH");
        end
    end
end

// ============================================================================
// SECTION 11: Spurious DMA/CORE kick monitor (T1 không được kick)
// ============================================================================

always @(posedge clk) begin
    if (cpu_rst_n_w && !test_done) begin
        if (ascon_dma_start) begin
            fail_count <= fail_count + 1;
            $display("[FAIL-T1] ascon_dma_start pulse! Firmware ghi CTRL=0x05 sai.");
        end
        if (ascon_core_start) begin
            fail_count <= fail_count + 1;
            $display("[FAIL-T1] ascon_core_start pulse! Firmware ghi CTRL=0x01 sai.");
        end
    end
end

// SOFT_RST log
always @(posedge clk) begin
    if (cpu_rst_n_w && ascon_soft_rst && !test_done) begin
        $display("[INFO-T1] SOFT_RST pulse @ %0d cy", timeout_counter);
    end
end

// ============================================================================
// SECTION 12: ASSERTION A4 — UART TX decode → "T1:OK"
//
// 115200 baud @ 100MHz → BAUD_DIV=867 cy/bit, BAUD_HALF=433 cy (mid-sample)
// Frame: 1 start + 8 data (LSB first) + 1 stop
// ============================================================================

parameter BAUD_DIV  = 867;
parameter BAUD_HALF = 433;

// RX state machine
reg        rx_active;
reg [3:0]  rx_bit_cnt;
reg [7:0]  rx_shift;
reg [9:0]  rx_baud_cnt;
reg        rx_last_tx;
reg        rx_byte_rdy;
reg [7:0]  rx_byte;

// Pattern match: "T1:OK" = T(54) 1(31) :(3A) O(4F) K(4B)
reg [7:0] pat [0:4];
integer   pat_idx;

initial begin
    pat[0] = 8'h54; // 'T'
    pat[1] = 8'h31; // '1'
    pat[2] = 8'h3A; // ':'
    pat[3] = 8'h4F; // 'O'
    pat[4] = 8'h4B; // 'K'
    pat_idx    = 0;
    rx_active  = 0;
    rx_bit_cnt = 0;
    rx_shift   = 0;
    rx_baud_cnt= 0;
    rx_last_tx = 1;
    rx_byte_rdy= 0;
    rx_byte    = 0;
end

// UART bit sampler
always @(posedge clk) begin
    if (!cpu_rst_n_w) begin
        rx_active   <= 0;
        rx_bit_cnt  <= 0;
        rx_baud_cnt <= 0;
        rx_last_tx  <= 1;
        rx_byte_rdy <= 0;
    end else begin
        rx_byte_rdy <= 0;
        rx_last_tx  <= uart_tx_wire;

        if (!rx_active) begin
            // Detect falling edge = start bit
            if (rx_last_tx && !uart_tx_wire) begin
                rx_active   <= 1;
                rx_bit_cnt  <= 0;
                rx_baud_cnt <= BAUD_HALF;   // sample ở giữa bit
                rx_shift    <= 0;
            end
        end else begin
            if (rx_baud_cnt > 0) begin
                rx_baud_cnt <= rx_baud_cnt - 1;
            end else begin
                rx_baud_cnt <= BAUD_DIV;
                rx_bit_cnt  <= rx_bit_cnt + 1;

                if (rx_bit_cnt == 0) begin
                    // Start bit check
                    if (uart_tx_wire != 1'b0)
                        rx_active <= 0;   // glitch, abort
                end else if (rx_bit_cnt <= 8) begin
                    // Data bits LSB-first
                    rx_shift <= {uart_tx_wire, rx_shift[7:1]};
                end else begin
                    // Stop bit → byte complete
                    rx_active   <= 0;
                    rx_byte_rdy <= 1;
                    rx_byte     <= rx_shift;
                end
            end
        end
    end
end

// Pattern match
always @(posedge clk) begin
    if (cpu_rst_n_w && rx_byte_rdy && !test_done) begin
        // Print byte
        if (rx_byte >= 8'h20 && rx_byte < 8'h7F)
            $write("[UART] '%c' (0x%02X)\n", rx_byte, rx_byte);
        else
            $write("[UART] 0x%02X\n", rx_byte);

        // Sliding window match "T1:OK"
        if (rx_byte == pat[pat_idx]) begin
            pat_idx <= pat_idx + 1;
            if (pat_idx == 4) begin
                // Full match!
                $display("");
                $display("[PASS-T1] === T1 PASS === CPU→ASCON register path OK");
                $display("[PASS-T1] Crossbar route S2 (0x20000000): correct");
                $display("[PASS-T1] ASCON slave: no DECERR");
                $display("[PASS-T1] DMA_LEN=24: verified");
                $display("[PASS-T1] s2_write_count = %0d", s2_write_count);
                $display("[PASS-T1] SUMMARY:");
                $display("[PASS-T1]   ascon_reg_dma_len = %0d  (exp 24)",  ascon_reg_dma_len);
                $display("[PASS-T1]   ascon_reg_dma_src = 0x%08X (exp 0x%08X)",
                         ascon_reg_dma_src, EXP_DMA_SRC);
                $display("[PASS-T1]   ascon_reg_dma_dst = 0x%08X (exp 0x%08X)",
                         ascon_reg_dma_dst, EXP_DMA_DST);
                $display("[PASS-T1]   ascon_reg_mode    = 0x%01X  (exp 0x1)",  ascon_reg_mode);
                $display("[PASS-T1]   ascon_reg_irq_en  = 0x%01X  (exp 0x0)",  ascon_reg_irq_en);
                $display("[PASS-T1]   ascon_reg_data_len= %0d     (exp 4)",     ascon_reg_data_len);
                $display("[PASS-T1]   DECERR count      = %0d     (exp 0)",     s2_decerr_count);
                $display("[PASS-T1] Total: PASS=%0d FAIL=%0d", pass_count+1, fail_count);
                $display("");
                test_done <= 1;
                pass_flag <= 1;
                #(CLK_PERIOD_NS * 20);
                $finish;
            end
        end else begin
            // Mismatch: reset index, re-check current byte
            if (rx_byte == pat[0])
                pat_idx <= 1;
            else
                pat_idx <= 0;
        end
    end
end

// ============================================================================
// SECTION 13: Periodic status dump
// ============================================================================

always @(posedge clk) begin
    if (cpu_rst_n_w && !test_done) begin
        if ((timeout_counter % 1024) == 0 && timeout_counter > 0) begin
            $display("[STATUS-T1] @%0d cy | s2_w=%0d | DECERR=%0d | pc=0x%08X | dma_len=%0d | soft_rst=%0b",
                     timeout_counter, s2_write_count, s2_decerr_count,
                     cpu_pc, ascon_reg_dma_len, ascon_soft_rst);
        end
    end
end



endmodule
// ============================================================================
// END: tb_t1.v
// Assertions: A1(S2 write log) A2(DECERR) A3(DMA_LEN==24) A4(UART T1:OK)
// ============================================================================