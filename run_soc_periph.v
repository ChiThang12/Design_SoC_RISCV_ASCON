`timescale 1ns/1ps

`include "soc_hs.v"

// ============================================================================
//  run_soc_periph.v  —  DMA + Peripheral Debug Testbench  v1.0
//
//  Derived from: run_soc_ascon.v v6.0
//  Focus: General-purpose DMA (S11/M3), UART RX/TX loopback, GPIO, Timer, PLIC
//
//  Key differences from run_soc_ascon.v:
//  - [NEW-A] UART RX loopback: uart_tx → uart_rx (with 1 CLK delay)
//  - [NEW-C] DMA-specific monitoring: S11 CH decode, M3 AXI beats
//  - [NEW-D] Timer IRQ monitoring: timer0/timer1/wdt_rst_req events
//  - [NEW-E] GPIO input stimulus: configurable pin toggles
//  - [EXTENDED] Timeout: 500000 cycles (ASCON was 200000)
//  - Firmware selection via symlink: ln -sf tests/test_*.hex gnu_toolchain/memory/program.hex
// ============================================================================
`define LOG_LEVEL       2
`define TIMEOUT         900000
`define HALT_STABLE     60
`define DMEM_DUMP_BASE  32'h10000000
`define DMEM_DUMP_WORDS 32
`define DMEM_ROW_WORDS  4
`define MATCH2_THRESH   20000
`define MATCH4_THRESH   20000
`define BAUD_DIV        868

module run_soc_periph;

// [NOTE] To run different firmware test:
//   ln -sf tests/test_uart.hex gnu_toolchain/memory/program.hex
//   iverilog -g2005 -o run_periph run_soc_periph.v && vvp run_periph

parameter CLK_PERIOD = 10;

// Clock & Reset
reg clk;
reg por_n_r;
reg ext_rst_n_r;

initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// JTAG pins
reg  jtag_tck_r;
reg  jtag_tms_r;
reg  jtag_tdi_r;
wire jtag_tdo_w;
wire jtag_tdo_en_w;

// UART: [NEW-A] loopback instead of tied to 1'b1
wire uart_tx_w;
wire uart_rx_w;
assign #(CLK_PERIOD) uart_rx_w = uart_tx_w;  // ← UART RX loopback via delay

// GPIO
wire [31:0] gpio_w;
reg  [31:0] gpio_in_r;
assign gpio_w = gpio_in_r;
wire [31:0] gpio_out_w = chip.core_gpio_out;
wire [31:0] gpio_oe_w  = chip.core_gpio_oe;

// WDT reset request
wire wdt_rst_req_w;

assign jtag_tdo_en_w = chip.core_tdo_en;

// DUT instantiation
soc_hs #(.SIM_MODE(1)) chip (
    .clk_in      (clk),
    .por_n       (por_n_r),
    .ext_rst_n   (ext_rst_n_r),
    .uart_tx     (uart_tx_w),
    .uart_rx     (uart_rx_w),
    .tck         (jtag_tck_r),
    .tms         (jtag_tms_r),
    .tdi         (jtag_tdi_r),
    .tdo         (jtag_tdo_w),
    .spi_sck     (),
    .spi_mosi    (),
    .spi_miso    (1'b1),
    .spi_cs_n    (),
    .gpio        (gpio_w),
    .wdt_rst_req (wdt_rst_req_w)
);

// ============================================================================
// SIGNAL TAPS (from soc_top internal wires)
// ============================================================================

// CPU Pipeline
wire [31:0] pc_if     = chip.u_soc_top.u_cpu.pc_if;
wire [31:0] instr_if  = chip.u_soc_top.u_cpu.instr_if;
wire        stall_if  = chip.u_soc_top.u_cpu.stall_if;

// CPU ↔ Caches
wire [31:0] ic_cpu_addr  = chip.u_soc_top.cpu_imem_addr;
wire        ic_cpu_req   = chip.u_soc_top.cpu_imem_valid;
wire        ic_cpu_ready = chip.u_soc_top.icache_imem_ready;

wire [31:0] dc_addr  = chip.u_soc_top.cpu_dcache_addr;
wire [31:0] dc_wdata = chip.u_soc_top.cpu_dcache_wdata;
wire [3:0]  dc_wstrb = chip.u_soc_top.cpu_dcache_wstrb;
wire        dc_req   = chip.u_soc_top.cpu_dcache_req;
wire        dc_we    = chip.u_soc_top.cpu_dcache_we;
wire [31:0] dc_rdata = chip.u_soc_top.dcache_cpu_rdata;
wire        dc_ready = chip.u_soc_top.dcache_cpu_ready;

// AXI Masters
wire [31:0] m0_araddr  = chip.u_soc_top.m0_araddr;
wire [7:0]  m0_arlen   = chip.u_soc_top.m0_arlen;
wire        m0_arvalid = chip.u_soc_top.m0_arvalid;
wire        m0_arready = chip.u_soc_top.m0_arready;
wire [31:0] m0_rdata   = chip.u_soc_top.m0_rdata;
wire [1:0]  m0_rresp   = chip.u_soc_top.m0_rresp;
wire        m0_rlast   = chip.u_soc_top.m0_rlast;
wire        m0_rvalid  = chip.u_soc_top.m0_rvalid;
wire        m0_rready  = chip.u_soc_top.m0_rready;

wire [31:0] m1_araddr  = chip.u_soc_top.m1_araddr;
wire [7:0]  m1_arlen   = chip.u_soc_top.m1_arlen;
wire        m1_arvalid = chip.u_soc_top.m1_arvalid;
wire        m1_arready = chip.u_soc_top.m1_arready;
wire [31:0] m1_rdata   = chip.u_soc_top.m1_rdata;
wire        m1_rvalid  = chip.u_soc_top.m1_rvalid;
wire        m1_rready  = chip.u_soc_top.m1_rready;
wire [31:0] m1_awaddr  = chip.u_soc_top.m1_awaddr;
wire        m1_awvalid = chip.u_soc_top.m1_awvalid;
wire        m1_awready = chip.u_soc_top.m1_awready;
wire [31:0] m1_wdata   = chip.u_soc_top.m1_wdata;
wire        m1_wvalid  = chip.u_soc_top.m1_wvalid;
wire        m1_wready  = chip.u_soc_top.m1_wready;

wire [31:0] m2_araddr  = chip.u_soc_top.m2_araddr;
wire        m2_arvalid = chip.u_soc_top.m2_arvalid;
wire        m2_arready = chip.u_soc_top.m2_arready;
wire [31:0] m2_rdata   = chip.u_soc_top.m2_rdata;
wire        m2_rvalid  = chip.u_soc_top.m2_rvalid;
wire        m2_rready  = chip.u_soc_top.m2_rready;

// [NEW-C] M3 (General-purpose DMA) — full AR/AW/W/R/B channels
wire [3:0]  m3_arid    = chip.u_soc_top.m3_arid;
wire [31:0] m3_araddr  = chip.u_soc_top.m3_araddr;
wire [7:0]  m3_arlen   = chip.u_soc_top.m3_arlen;
wire [2:0]  m3_arsize  = chip.u_soc_top.m3_arsize;
wire        m3_arvalid = chip.u_soc_top.m3_arvalid;
wire        m3_arready = chip.u_soc_top.m3_arready;
wire [31:0] m3_rdata   = chip.u_soc_top.m3_rdata;
wire [1:0]  m3_rresp   = chip.u_soc_top.m3_rresp;
wire        m3_rlast   = chip.u_soc_top.m3_rlast;
wire        m3_rvalid  = chip.u_soc_top.m3_rvalid;
wire        m3_rready  = chip.u_soc_top.m3_rready;

wire [3:0]  m3_awid    = chip.u_soc_top.m3_awid;
wire [31:0] m3_awaddr  = chip.u_soc_top.m3_awaddr;
wire [7:0]  m3_awlen   = chip.u_soc_top.m3_awlen;
wire [2:0]  m3_awsize  = chip.u_soc_top.m3_awsize;
wire        m3_awvalid = chip.u_soc_top.m3_awvalid;
wire        m3_awready = chip.u_soc_top.m3_awready;
wire [31:0] m3_wdata   = chip.u_soc_top.m3_wdata;
wire [3:0]  m3_wstrb   = chip.u_soc_top.m3_wstrb;
wire        m3_wlast   = chip.u_soc_top.m3_wlast;
wire        m3_wvalid  = chip.u_soc_top.m3_wvalid;
wire        m3_wready  = chip.u_soc_top.m3_wready;
wire [3:0]  m3_bid     = chip.u_soc_top.m3_bid;
wire [1:0]  m3_bresp   = chip.u_soc_top.m3_bresp;
wire        m3_bvalid  = chip.u_soc_top.m3_bvalid;
wire        m3_bready  = chip.u_soc_top.m3_bready;

// Slaves (selected)
wire [31:0] s1_araddr  = chip.u_soc_top.s1_araddr;
wire        s1_arvalid = chip.u_soc_top.s1_arvalid;
wire        s1_arready = chip.u_soc_top.s1_arready;
wire [31:0] s1_awaddr  = chip.u_soc_top.s1_awaddr;
wire        s1_awvalid = chip.u_soc_top.s1_awvalid;
wire        s1_awready = chip.u_soc_top.s1_awready;
wire [31:0] s1_wdata   = chip.u_soc_top.s1_wdata;
wire        s1_wvalid  = chip.u_soc_top.s1_wvalid;

// [NEW-C] S5 (UART), S6 (GPIO), S8 (Timer), S11 (DMA Ctrl)
wire [31:0] s5_awaddr  = chip.u_soc_top.s5_awaddr;
wire        s5_awvalid = chip.u_soc_top.s5_awvalid;
wire        s5_awready = chip.u_soc_top.s5_awready;
wire [31:0] s5_wdata   = chip.u_soc_top.s5_wdata;
wire        s5_wvalid  = chip.u_soc_top.s5_wvalid;
wire        s5_wready  = chip.u_soc_top.s5_wready;
wire [31:0] s5_araddr  = chip.u_soc_top.s5_araddr;
wire        s5_arvalid = chip.u_soc_top.s5_arvalid;
wire        s5_arready = chip.u_soc_top.s5_arready;
wire [31:0] s5_rdata   = chip.u_soc_top.s5_rdata;
wire        s5_rvalid  = chip.u_soc_top.s5_rvalid;
wire        s5_rready  = chip.u_soc_top.s5_rready;

wire [31:0] s6_awaddr  = chip.u_soc_top.s6_awaddr;
wire        s6_awvalid = chip.u_soc_top.s6_awvalid;
wire        s6_awready = chip.u_soc_top.s6_awready;
wire [31:0] s6_wdata   = chip.u_soc_top.s6_wdata;
wire        s6_wvalid  = chip.u_soc_top.s6_wvalid;

wire [31:0] s8_awaddr  = chip.u_soc_top.s8_awaddr;
wire        s8_awvalid = chip.u_soc_top.s8_awvalid;
wire        s8_awready = chip.u_soc_top.s8_awready;
wire [31:0] s8_wdata   = chip.u_soc_top.s8_wdata;
wire        s8_wvalid  = chip.u_soc_top.s8_wvalid;

wire [31:0] s11_araddr  = chip.u_soc_top.s11_araddr;
wire        s11_arvalid = chip.u_soc_top.s11_arvalid;
wire        s11_arready = chip.u_soc_top.s11_arready;
wire [31:0] s11_awaddr  = chip.u_soc_top.s11_awaddr;
wire        s11_awvalid = chip.u_soc_top.s11_awvalid;
wire        s11_awready = chip.u_soc_top.s11_awready;
wire [31:0] s11_wdata   = chip.u_soc_top.s11_wdata;
wire        s11_wvalid  = chip.u_soc_top.s11_wvalid;
wire        s11_wready  = chip.u_soc_top.s11_wready;

// Interrupts
wire        ext_irq        = chip.u_soc_top.external_irq;
wire        uart_irq_w     = chip.u_soc_top.uart_irq;
wire        gpio_irq_w     = chip.u_soc_top.gpio_irq;
wire        timer0_irq_w   = chip.u_soc_top.timer0_irq;
wire        timer1_irq_w   = chip.u_soc_top.timer1_irq;
wire        wdt_rst_req    = chip.u_soc_top.wdt_rst_req;
wire        dma_irq_w      = chip.u_soc_top.dma_irq;
wire        ascon_irq_w    = chip.u_soc_top.ascon_irq;

// Reset signals (internal)
wire fabric_rst_n_w = chip.u_soc_top.fabric_rst_n;
wire cpu_rst_n_w    = chip.u_soc_top.cpu_rst_n;
wire boot_done_w    = chip.u_soc_top.boot_done;

// Note: lsu_sb_empty signal not available — using simple PC-stuck detection instead

// ============================================================================
// Testbench Control
// ============================================================================

integer cycle_count;
integer instr_count;
integer halt_cnt;
integer program_done;

// UART monitoring
reg [7:0]  uart_rx_buf [0:255];
integer    uart_rx_count;
reg [7:0]  uart_line_buf [0:127];
integer    uart_line_len;
integer    uart_pass_cnt;
integer    uart_fail_cnt;
reg        uart_all_pass;
reg        uart_some_fail;
integer    uart_tx_byte_cnt;

// IRQ counters
integer uart_irq_cnt;
integer gpio_irq_cnt;
integer timer0_irq_cnt;
integer timer1_irq_cnt;
integer dma_irq_cnt;
integer ascon_irq_cnt;
integer plic_meip_cnt;

// Edge detect state
reg prev_uart_irq;
reg prev_gpio_irq;
reg prev_timer0_irq;
reg prev_timer1_irq;
reg prev_dma_irq;
reg prev_ext_irq;

// Halt / Loop detection
reg [31:0] prev_pc;
reg [31:0] pc_ring [0:7];
integer    ring_ptr;
integer    match2, match4;

// DMA monitoring  [NEW-C]
integer    m3_ar_beat_cnt;
integer    m3_aw_beat_cnt;
reg [31:0] m3_last_ar_addr;
reg [7:0]  m3_last_ar_len;

// GPIO monitoring [NEW-E]
reg [31:0] prev_gpio_out;
reg [31:0] prev_gpio_oe;

// ============================================================================
// Cycle & Instruction Counter
// ============================================================================

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        cycle_count <= 0;
        instr_count <= 0;
    end else begin
        cycle_count <= cycle_count + 1;
        if (cpu_rst_n_w && ic_cpu_req && ic_cpu_ready && !stall_if && instr_if != 32'h0) begin
            instr_count <= instr_count + 1;
        end
    end
end

// ============================================================================
// UART TX Monitor (8N1 Sampler)
// ============================================================================

integer baud_half;
integer baud_full;

initial begin
    baud_half = (`BAUD_DIV * CLK_PERIOD) / 2;
    baud_full = `BAUD_DIV * CLK_PERIOD;
    uart_rx_count = 0;
    uart_tx_byte_cnt = 0;
    forever begin
        @(negedge uart_tx_w);
        #(baud_half + baud_full);
        begin : uart_rx_frame
            reg [7:0] rx_byte;
            integer   b;
            rx_byte = 8'h00;
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = uart_tx_w;
                if (b < 7) #baud_full;
            end
            #baud_full;
            uart_tx_byte_cnt = uart_tx_byte_cnt + 1;
            if (rx_byte >= 8'h20 && rx_byte <= 8'h7E)
                $display("[%6d] [UART-TX] char='%s'  (0x%02h)  #%0d", cycle_count, rx_byte, rx_byte, uart_tx_byte_cnt);
            else if (rx_byte == 8'h0A)
                $display("[%6d] [UART-TX] newline", cycle_count);
            else if (rx_byte == 8'h0D)
                ;  // skip CR
            else
                $display("[%6d] [UART-TX] byte=0x%02h  #%0d", cycle_count, rx_byte, uart_tx_byte_cnt);
            
            if (uart_rx_count < 256) begin
                uart_rx_buf[uart_rx_count] = rx_byte;
                uart_rx_count = uart_rx_count + 1;
            end
            
            if (rx_byte == 8'h0A) begin
                parse_uart_line();
                uart_line_len = 0;
            end else if (rx_byte != 8'h0D) begin
                if (uart_line_len < 127) begin
                    uart_line_buf[uart_line_len] = rx_byte;
                    uart_line_len = uart_line_len + 1;
                end
            end
        end
    end
end

task parse_uart_line;
    integer p;
    reg match_pass, match_fail, match_all_pass, match_some_fail;
    begin
        match_pass      = (uart_line_len >= 6 && uart_line_buf[0] == "[" && 
                           uart_line_buf[1] == "P" && uart_line_buf[2] == "A");
        match_fail      = (uart_line_len >= 6 && uart_line_buf[0] == "[" && 
                           uart_line_buf[1] == "F" && uart_line_buf[2] == "A");
        match_all_pass  = (uart_line_len >= 8 && uart_line_buf[0] == "A" && 
                           uart_line_buf[1] == "L" && uart_line_buf[2] == "L");
        match_some_fail = (uart_line_len >= 9 && uart_line_buf[0] == "S" && 
                           uart_line_buf[1] == "O" && uart_line_buf[2] == "M");
        
        if (match_pass) begin
            uart_pass_cnt = uart_pass_cnt + 1;
            $write("[%6d] [TEST-RESULT] *** PASS #%0d *** : ", cycle_count, uart_pass_cnt);
            for (p = 0; p < uart_line_len; p = p + 1) $write("%s", uart_line_buf[p]);
            $display("");
        end else if (match_fail) begin
            uart_fail_cnt = uart_fail_cnt + 1;
            $write("[%6d] [TEST-RESULT] *** FAIL #%0d *** : ", cycle_count, uart_fail_cnt);
            for (p = 0; p < uart_line_len; p = p + 1) $write("%s", uart_line_buf[p]);
            $display("");
        end else if (match_all_pass) begin
            uart_all_pass = 1'b1;
            program_done = 1;
            print_report("ALL_PASS from firmware");
            #(CLK_PERIOD * 4);
            $finish(0);
        end else if (match_some_fail) begin
            uart_some_fail = 1'b1;
            program_done = 1;
            print_report("SOME_FAIL from firmware");
            #(CLK_PERIOD * 4);
            $finish(1);
        end
    end
endtask

// ============================================================================
// IRQ Edge Logger [NEW-C/D]
// ============================================================================

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_uart_irq    <= 1'b0;
        prev_gpio_irq    <= 1'b0;
        prev_timer0_irq  <= 1'b0;
        prev_timer1_irq  <= 1'b0;
        prev_dma_irq     <= 1'b0;
        prev_ext_irq     <= 1'b0;
    end else if (fabric_rst_n_w) begin
        // UART IRQ
        if (uart_irq_w && !prev_uart_irq) begin
            uart_irq_cnt = uart_irq_cnt + 1;
            $display("[%6d] [UART] irq_out raised #%0d  → PLIC", cycle_count, uart_irq_cnt);
        end
        // GPIO IRQ
        if (gpio_irq_w && !prev_gpio_irq) begin
            gpio_irq_cnt = gpio_irq_cnt + 1;
            $display("[%6d] [GPIO] irq raised #%0d  → PLIC  (gpio_in=0x%08h  gpio_out=0x%08h)",
                     cycle_count, gpio_irq_cnt, gpio_in_r, gpio_out_w);
        end
        // Timer0 IRQ [NEW-D]
        if (timer0_irq_w && !prev_timer0_irq) begin
            timer0_irq_cnt = timer0_irq_cnt + 1;
            $display("[%6d] [TIMER0] irq raised #%0d  → PLIC src[5]", cycle_count, timer0_irq_cnt);
        end
        // Timer1 IRQ [NEW-D]
        if (timer1_irq_w && !prev_timer1_irq) begin
            timer1_irq_cnt = timer1_irq_cnt + 1;
            $display("[%6d] [TIMER1] irq raised #%0d  → PLIC src[6]", cycle_count, timer1_irq_cnt);
        end
        // DMA IRQ [NEW-C]
        if (dma_irq_w && !prev_dma_irq) begin
            dma_irq_cnt = dma_irq_cnt + 1;
            $display("[%6d] [DMA] irq_out raised #%0d  → PLIC src[9]", cycle_count, dma_irq_cnt);
        end
        // PLIC meip (external IRQ)
        if (ext_irq && !prev_ext_irq) begin
            plic_meip_cnt = plic_meip_cnt + 1;
            $display("[%6d] [PLIC] meip raised #%0d  → CPU.external_irq", cycle_count, plic_meip_cnt);
        end
        // WDT reset request [NEW-D]
        if (wdt_rst_req) begin
            $display("[%6d] [WDT] rst_req ASSERTED — watchdog triggered!", cycle_count);
        end
        
        prev_uart_irq    <= uart_irq_w;
        prev_gpio_irq    <= gpio_irq_w;
        prev_timer0_irq  <= timer0_irq_w;
        prev_timer1_irq  <= timer1_irq_w;
        prev_dma_irq     <= dma_irq_w;
        prev_ext_irq     <= ext_irq;
    end
end

// ============================================================================
// DMA S11 Write Decoder [NEW-C]
// ============================================================================

integer s11_dma_wr_cnt;

always @(posedge clk) begin
    if (ext_rst_n_r && fabric_rst_n_w) begin
        if (s11_wvalid && s11_wready) begin
            s11_dma_wr_cnt = s11_dma_wr_cnt + 1;
        end
        
        // Decode DMA channel register writes
        if (s11_wvalid && s11_wready && s11_awvalid) begin
            begin : s11_decode
                reg [11:0] offset;
                reg [1:0]  ch;
                reg [1:0]  reg_sel;
                offset  = s11_awaddr[11:0];
                ch      = offset[5:4];
                reg_sel = offset[3:2];
                
                if (offset[11:6] == 6'b000000) begin
                    case (reg_sel)
                        2'd0: $display("[%6d] [DMA-CFG] CH%0d SRC  = 0x%08h", cycle_count, ch, s11_wdata);
                        2'd1: $display("[%6d] [DMA-CFG] CH%0d DST  = 0x%08h", cycle_count, ch, s11_wdata);
                        2'd2: $display("[%6d] [DMA-CFG] CH%0d LEN  = 0x%08h", cycle_count, ch, s11_wdata);
                        2'd3: begin
                            $write("[%6d] [DMA-CFG] CH%0d CTRL = 0x%08h", cycle_count, ch, s11_wdata);
                            if (s11_wdata[1]) $write(" [START!]");
                            $display("");
                        end
                    endcase
                end
            end
        end
    end
end

// ============================================================================
// PC Snapshot every 20K cycles (diagnose where CPU is stuck)
// ============================================================================

always @(posedge clk) begin
    if (cpu_rst_n_w && cycle_count > 0 && (cycle_count % 20000) == 0) begin
        $display("[%6d] [PC-SNAP] pc_if=0x%08h  instr=0x%08h  dc_req=%b",
                 cycle_count, pc_if, instr_if, dc_req);
    end
end

// ============================================================================
// [DBG-NC] Trace dcache NC_WRITE state around UART duplicate window
// ============================================================================
wire        dbg_nc_just     = chip.u_soc_top.u_dcache.controller_inst.nc_just_completed;
wire        dbg_flush_busy  = chip.u_soc_top.u_dcache.controller_inst.flush_busy;
wire [2:0]  dbg_dc_state    = chip.u_soc_top.u_dcache.controller_inst.state;
wire        dbg_evict_done  = chip.u_soc_top.u_dcache.controller_inst.evict_done;
wire        dbg_drain_state = chip.u_soc_top.u_cpu.lsu_unit.drain_state;
wire [1:0]  dbg_sb_count    = chip.u_soc_top.u_cpu.lsu_unit.sb_count;
wire        dbg_do_store    = chip.u_soc_top.u_cpu.lsu_unit.do_store;
wire        dbg_do_drain_pop= chip.u_soc_top.u_cpu.lsu_unit.do_drain_pop;
wire        dbg_lsu_req_v   = chip.u_soc_top.u_cpu.lsu_req_valid;
wire        dbg_lsu_req_r   = chip.u_soc_top.u_cpu.lsu_req_ready;
wire        dbg_lsu_req_fire= chip.u_soc_top.u_cpu.lsu_req_fire;
wire        dbg_lsu_req_sent= chip.u_soc_top.u_cpu.lsu_req_sent;
wire        dbg_lsu_req_new = chip.u_soc_top.u_cpu.lsu_req_new;
wire        dbg_memwrite_mem= chip.u_soc_top.u_cpu.memwrite_mem;
wire        dbg_memread_mem = chip.u_soc_top.u_cpu.memread_mem;
wire [31:0] dbg_alu_mem     = chip.u_soc_top.u_cpu.alu_result_mem;
wire [31:0] dbg_pc4_mem     = chip.u_soc_top.u_cpu.pc_plus_4_mem;

// [DBG-PC] Pipeline PC + flush signals for drop-char trace
wire [31:0] dbg_pc_if       = chip.u_soc_top.u_cpu.pc_if;
wire [31:0] dbg_pc_id       = chip.u_soc_top.u_cpu.pc_id;
wire [31:0] dbg_pc_ex       = chip.u_soc_top.u_cpu.pc_ex;
wire [31:0] dbg_pc_mem      = chip.u_soc_top.u_cpu.pc_plus_4_mem - 32'd4;
wire        dbg_flush_if_id = chip.u_soc_top.u_cpu.flush_if_id_final;
wire        dbg_flush_id_ex = chip.u_soc_top.u_cpu.flush_id_ex_final;
wire        dbg_mispredict  = chip.u_soc_top.u_cpu.mispredict_ex;
// [DBG-STALL] Hazard unit internals
wire        dbg_stall_any   = chip.u_soc_top.u_cpu.stall_any;
wire        dbg_fence_stall = chip.u_soc_top.u_cpu.fence_stall;
wire        dbg_lsu_dep_st  = chip.u_soc_top.u_cpu.lsu_dep_stall;
wire        dbg_lsu_idle    = chip.u_soc_top.u_cpu.lsu_idle;
wire        dbg_lq_empty    = chip.u_soc_top.u_cpu.lsu_unit.lq_empty;
// Pass-once internals
wire        dbg_stall_ex_mem= chip.u_soc_top.u_cpu.stall_ex_mem;
wire        dbg_same_sig    = chip.u_soc_top.u_cpu.ex_mem_reg.same_stalled_sig;
wire        dbg_sig_valid   = chip.u_soc_top.u_cpu.ex_mem_reg.stalled_sig_valid_r;
// [DBG-WB] WB forwarding + WAW trace + scoreboard direct probe
wire [31:0] dbg_scoreboard  = chip.u_soc_top.u_cpu.lsu_scoreboard;
wire [4:0]  dbg_rs1_id      = chip.u_soc_top.u_cpu.rs1_id;
wire        dbg_rs1_used    = chip.u_soc_top.u_cpu.rs1_used_id;
wire        dbg_memtoreg_wb = chip.u_soc_top.u_cpu.memtoreg_wb;
wire [4:0]  dbg_rd_wb       = chip.u_soc_top.u_cpu.rd_wb;
wire [31:0] dbg_wbdata      = chip.u_soc_top.u_cpu.write_back_data_wb;
wire        dbg_lsu_commit  = chip.u_soc_top.u_cpu.lsu_result_commit;
wire [4:0]  dbg_lsu_rd      = chip.u_soc_top.u_cpu.lsu_result_rd;
wire        dbg_fwd_a_wb    = chip.u_soc_top.u_cpu.fwd_a_wb;
wire        dbg_fwd_a_mem   = chip.u_soc_top.u_cpu.fwd_a_mem;
wire        dbg_mw_ex       = chip.u_soc_top.u_cpu.memwrite_ex;

// [DBG-NC] $display gated off — enable by changing 0 to 1 below to re-trace
// dcache NC_WRITE / LSU activity in cycle window for debug.
always @(posedge clk) begin
    if (1'b0 && ext_rst_n_r && fabric_rst_n_w &&
        cycle_count >= 4120 && cycle_count <= 4160) begin
        $display("[%6d] [DBG-NC] dc=%0d fb=%b nj=%b ed=%b dq=%b sb=%0d ds=%b doSt=%b doPop=%b lvR=%b lFr=%b lSnt=%b lNew=%b mW=%b mR=%b alu=%08h pc4=%08h",
            cycle_count, dbg_dc_state, dbg_flush_busy, dbg_nc_just,
            dbg_evict_done, dc_req, dbg_sb_count, dbg_drain_state,
            dbg_do_store, dbg_do_drain_pop, dbg_lsu_req_v, dbg_lsu_req_fire,
            dbg_lsu_req_sent, dbg_lsu_req_new, dbg_memwrite_mem, dbg_memread_mem,
            dbg_alu_mem, dbg_pc4_mem);
    end
end

// [DBG-PC] Pipeline trace — bật quanh window SW 't' và SW '\r'
always @(posedge clk) begin
    if (1'b1 && ext_rst_n_r && fabric_rst_n_w && (
        (cycle_count >= 24340 && cycle_count <= 24440) ||
        (cycle_count >= 24900 && cycle_count <= 25100)
    )) begin
        $display("[%6d] [DBG-PC] IF=%08h ID=%08h EX=%08h MEM=%08h | fIF=%b fEX=%b | mW=%b mWex=%b sb=%0d lq=%0d | stall=%b lds=%b idle=%b | lsuCmt=%b scb15=%b rs1=%02d rs1u=%b | fwdAm=%b fwdAw=%b mtWb=%b rdWb=%02d wbDat=%08h alu=%08h",
            cycle_count,
            dbg_pc_if, dbg_pc_id, dbg_pc_ex, dbg_pc_mem,
            dbg_flush_if_id, dbg_flush_id_ex,
            dbg_memwrite_mem, dbg_mw_ex, dbg_sb_count,
            chip.u_soc_top.u_cpu.lsu_unit.lq_count,
            dbg_stall_any, dbg_lsu_dep_st, dbg_lsu_idle,
            dbg_lsu_commit, dbg_scoreboard[15], dbg_rs1_id, dbg_rs1_used,
            dbg_fwd_a_mem, dbg_fwd_a_wb, dbg_memtoreg_wb, dbg_rd_wb,
            dbg_wbdata, dbg_alu_mem);
    end
end

// ============================================================================
// UART S5 AXI Write Logger — diagnostic: xem CPU có write vào UART không
// ============================================================================

integer s5_aw_cnt;
integer s5_ar_cnt;
reg prev_uart_tx;
// s5_rdata, s5_rvalid, s5_rready declared in signal taps section above

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        s5_aw_cnt    <= 0;
        s5_ar_cnt    <= 0;
        prev_uart_tx <= 1'b1;
    end else if (fabric_rst_n_w) begin
        // Log AW handshakes on S5 (UART writes)
        if (s5_awvalid && s5_awready) begin
            s5_aw_cnt = s5_aw_cnt + 1;
            $display("[%6d] [UART-AW] #%0d ADDR=0x%08h", cycle_count, s5_aw_cnt, s5_awaddr);
        end
        // Log W handshakes on S5 (UART write data) — only on actual handshake
        if (s5_wvalid && s5_wready) begin
            $display("[%6d] [UART-W ] DATA=0x%08h", cycle_count, s5_wdata);
        end
        // Log AR handshakes on S5 (UART reads)
        if (s5_arvalid && s5_arready) begin
            s5_ar_cnt = s5_ar_cnt + 1;
            if (s5_ar_cnt <= 5)
                $display("[%6d] [UART-AR] #%0d ADDR=0x%08h", cycle_count, s5_ar_cnt, s5_araddr);
            else if (s5_ar_cnt == 6)
                $display("[%6d] [UART-AR] ... (suppressing further AR logs)", cycle_count);
        end
        // Log R handshakes on S5 (UART read data returned)
        if (s5_rvalid && s5_rready) begin
            if (s5_ar_cnt <= 6)
                $display("[%6d] [UART-R ] DATA=0x%08h (STATUS bit1=TX_FULL=%b bit0=TX_EMPTY=%b)",
                         cycle_count, s5_rdata, s5_rdata[1], s5_rdata[0]);
        end
        // Log uart_tx line transitions
        if (uart_tx_w !== prev_uart_tx) begin
            $display("[%6d] [UART-TX-LINE] uart_tx=%b (was %b)",
                     cycle_count, uart_tx_w, prev_uart_tx);
            prev_uart_tx <= uart_tx_w;
        end
    end
end

// ============================================================================
// DMA M3 AXI Traffic [NEW-C]
// ============================================================================

always @(posedge clk) begin
    if (ext_rst_n_r && fabric_rst_n_w) begin
        // AR (Read Address) beats
        if (m3_arvalid && m3_arready) begin
            m3_ar_beat_cnt = m3_ar_beat_cnt + 1;
            m3_last_ar_addr = m3_araddr;
            m3_last_ar_len  = m3_arlen;
            $display("[%6d] [DMA-M3-AR] ADDR=0x%08h  LEN=%0d (bursts %0d beats)", 
                     cycle_count, m3_araddr, m3_arlen, m3_arlen+1);
        end
        
        // AW (Write Address) beats
        if (m3_awvalid && m3_awready) begin
            m3_aw_beat_cnt = m3_aw_beat_cnt + 1;
            $display("[%6d] [DMA-M3-AW] ADDR=0x%08h  LEN=%0d (bursts %0d beats)",
                     cycle_count, m3_awaddr, m3_awlen, m3_awlen+1);
        end
        
        // M3 DONE (both AR and AW complete)
        if ((m3_rvalid && m3_rready && m3_rlast) && (m3_bvalid && m3_bready)) begin
            $display("[%6d] [DMA-M3-DONE] Transfer complete — AR beats=%0d, AW beats=%0d",
                     cycle_count, m3_ar_beat_cnt, m3_aw_beat_cnt);
        end
    end
end

// ============================================================================
// GPIO Output Change Logger [NEW-E]
// ============================================================================

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        prev_gpio_out <= 32'h0;
        prev_gpio_oe  <= 32'h0;
    end else if (fabric_rst_n_w) begin
        if (gpio_out_w !== prev_gpio_out || gpio_oe_w !== prev_gpio_oe) begin
            $display("[%6d] [GPIO-OUT] gpio_out=0x%08h  OE=0x%08h", 
                     cycle_count, gpio_out_w, gpio_oe_w);
            prev_gpio_out <= gpio_out_w;
            prev_gpio_oe  <= gpio_oe_w;
        end
    end
end

// ============================================================================
// GPIO Input Stimulus [NEW-E]
// ============================================================================

initial begin
    gpio_in_r = 32'h0;
    @(posedge cpu_rst_n_w);
    #(CLK_PERIOD * 5000);
    
    // GPIO pin 0 toggle
    $display("[%6d] [GPIO-STIM] Asserting gpio_in[0] (100 cycles)", cycle_count);
    gpio_in_r[0] = 1'b1;
    #(CLK_PERIOD * 100);
    gpio_in_r[0] = 1'b0;
    #(CLK_PERIOD * 100);
    
    // GPIO pin 8 toggle (edge trigger for IRQ)
    $display("[%6d] [GPIO-STIM] Asserting gpio_in[8] (100 cycles)", cycle_count);
    gpio_in_r[8] = 1'b1;
    #(CLK_PERIOD * 100);
    gpio_in_r[8] = 1'b0;
    #(CLK_PERIOD * 100);
    
    // GPIO pin 16 toggle
    $display("[%6d] [GPIO-STIM] Asserting gpio_in[16] (100 cycles)", cycle_count);
    gpio_in_r[16] = 1'b1;
    #(CLK_PERIOD * 100);
    gpio_in_r[16] = 1'b0;
    #(CLK_PERIOD * 100);
end

// ============================================================================
// Halt/Loop Detection
// ============================================================================

always @(posedge clk) begin
    if (!ext_rst_n_r) begin
        halt_cnt   <= 0;
        ring_ptr   <= 0;
        match2     <= 0;
        match4     <= 0;
    end else if (cycle_count > 30 && cpu_rst_n_w) begin

        // Halt detection (stuck at same PC — simplified)
        if (pc_if === prev_pc && !dc_req) begin
            halt_cnt <= halt_cnt + 1;
            if (halt_cnt >= `HALT_STABLE && !program_done) begin
                program_done = 1;
                $display("[%0d] HALT detected — waiting 350K cycles for UART TX drain...", cycle_count);
                #(CLK_PERIOD * 350000);
                print_report("HALT LOOP DETECTED");
                $finish;
            end
        end else begin
            halt_cnt <= 0;
        end

        // 2-cycle loop
        if (pc_if === pc_ring[(ring_ptr + 6) % 8] && !dc_req) begin
            match2 = match2 + 1;
            if (match2 >= `MATCH2_THRESH && !program_done) begin
                program_done = 1;
                $display("[%0d] 2-CYCLE LOOP detected — waiting 350K cycles for UART TX drain...", cycle_count);
                #(CLK_PERIOD * 350000);
                print_report("2-CYCLE LOOP DETECTED");
                $finish;
            end
        end else match2 = 0;

        // 4-cycle loop
        if (pc_if === pc_ring[(ring_ptr + 4) % 8] && !dc_req) begin
            match4 = match4 + 1;
            if (match4 >= `MATCH4_THRESH && !program_done) begin
                program_done = 1;
                $display("[%0d] 4-CYCLE LOOP detected — waiting 350K cycles for UART TX drain...", cycle_count);
                #(CLK_PERIOD * 350000);
                print_report("4-CYCLE LOOP DETECTED");
                $finish;
            end
        end else match4 = 0;

        pc_ring[ring_ptr] <= pc_if;
        ring_ptr <= (ring_ptr + 1) % 8;
        prev_pc  <= pc_if;
    end
end

// Watchdog timeout
initial begin
    #(CLK_PERIOD * `TIMEOUT);
    if (!program_done) begin
        program_done = 1;
        print_report("WATCHDOG TIMEOUT");
    end
    $finish;
end

// ============================================================================
// Main Reset & Test Sequence
// ============================================================================

initial begin
    // Initialize
    jtag_tck_r = 1'b0;
    jtag_tms_r = 1'b1;
    jtag_tdi_r = 1'b0;
    program_done = 0;
    cycle_count = 0;
    instr_count = 0;
    uart_pass_cnt = 0;
    uart_fail_cnt = 0;
    uart_all_pass = 0;
    uart_some_fail = 0;
    uart_irq_cnt = 0;
    gpio_irq_cnt = 0;
    timer0_irq_cnt = 0;
    timer1_irq_cnt = 0;
    dma_irq_cnt = 0;
    ascon_irq_cnt = 0;
    plic_meip_cnt = 0;
    s11_dma_wr_cnt = 0;
    m3_ar_beat_cnt = 0;
    m3_aw_beat_cnt = 0;
    
    // Reset sequence
    por_n_r     = 1'b0;
    ext_rst_n_r = 1'b0;
    repeat(20) @(posedge clk);
    
    ext_rst_n_r = 1'b1;
    $display("[%6d] ext_rst_n released (por_n still LOW)", cycle_count);
    repeat(1020) @(posedge clk);
    
    por_n_r = 1'b1;
    $display("[%6d] por_n released — waiting for fabric_rst_n...", cycle_count);
    
    @(posedge fabric_rst_n_w);
    $display("[%6d] fabric_rst_n released -> boot_ctrl loading IMEM...", cycle_count);
    
    @(posedge boot_done_w);
    $display("[%6d] boot_done asserted -> waiting for cpu_rst_n...", cycle_count);
    
    @(posedge cpu_rst_n_w);
    repeat(3) @(posedge clk);
    
    $display("[%6d] cpu_rst_n released -> CPU execution started\n", cycle_count);
    
    $dumpfile("waveform_periph.vcd");
    $dumpvars(0, run_soc_periph);
end

// ============================================================================
// print_report Task
// ============================================================================

task print_report;
    input [255:0] reason;
    begin
        $display("");
        $display("=================================================================");
        $display("  RISC-V SoC Testbench — DMA + Peripheral Verification");
        $display("=================================================================");
        $display("  Reason: %s", reason);
        $display("=================================================================");
        $display("");
        
        $display("Performance:");
        $display("  Cycles:     %0d", cycle_count);
        $display("  Instructions: %0d", instr_count);
        if (instr_count > 0)
            $display("  CPI:        %.2f", (cycle_count * 1.0) / instr_count);
        $display("");
        
        $display("Interrupts:");
        $display("  UART IRQ:   %0d", uart_irq_cnt);
        $display("  GPIO IRQ:   %0d", gpio_irq_cnt);
        $display("  Timer0 IRQ: %0d", timer0_irq_cnt);
        $display("  Timer1 IRQ: %0d", timer1_irq_cnt);
        $display("  DMA IRQ:    %0d", dma_irq_cnt);
        $display("  PLIC meip:  %0d", plic_meip_cnt);
        $display("");
        
        $display("UART Test Results:");
        $display("  TX bytes:   %0d", uart_tx_byte_cnt);
        $display("  [PASS]:     %0d", uart_pass_cnt);
        $display("  [FAIL]:     %0d", uart_fail_cnt);
        if (uart_all_pass) $display("  ALL_PASS:   YES");
        if (uart_some_fail) $display("  SOME_FAIL:  YES");
        $display("");
        
        $display("DMA Activity:");
        $display("  S11 writes: %0d", s11_dma_wr_cnt);
        $display("  M3 AR beats: %0d", m3_ar_beat_cnt);
        $display("  M3 AW beats: %0d", m3_aw_beat_cnt);
        $display("");
        
        $display("=================================================================");
        $display("  Time: %0d cycles @ 100 MHz = %.2f us", 
                 cycle_count, cycle_count * 10.0 / 1000.0);
        $display("=================================================================");
        $display("");
    end
endtask

endmodule
