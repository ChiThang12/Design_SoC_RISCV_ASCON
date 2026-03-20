`timescale 1ns/1ps
// =============================================================================
// Testbench: tb_data_path
// Mục đích : Trace luồng dữ liệu
//            RISCV -> DCache (M1) -> Crossbar -> DMEM (S1)
//            DMA   (M2)           -> Crossbar -> DMEM (S1)
// =============================================================================
`include "soc_top.v"
module tb_data_path;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 32;
parameter ID_WIDTH   = 4;
parameter CLK_PERIOD = 10; // 100 MHz

// S1 = DMEM base 0x1000_0000
parameter [31:0] DMEM_BASE = 32'h1000_0000;

// ---------------------------------------------------------------------------
// Clock / Reset
// ---------------------------------------------------------------------------
reg clk     = 0;
reg ext_rst_n = 0;

always #(CLK_PERIOD/2) clk = ~clk;

// Bật reset sau 5 chu kỳ
initial begin
    ext_rst_n = 0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    ext_rst_n = 1;
    $display("[%0t] RST released", $time);
end

// ---------------------------------------------------------------------------
// DUT
// ---------------------------------------------------------------------------
wire soft_rst_pulse;

soc_top #(
    .DATA_WIDTH     (DATA_WIDTH),
    .ADDR_WIDTH     (ADDR_WIDTH),
    .ID_WIDTH       (ID_WIDTH),
    .IMEM_SIZE      (8192),
    .DMEM_SIZE      (8192),
    .IMEM_INIT_FILE ("cpu/memory_axi4full/program.hex"),
    // Slave address map
    .S0_BASE (32'h0000_0000), .S0_MASK (32'hFFFF_E000),
    .S1_BASE (32'h1000_0000), .S1_MASK (32'hFFFF_E000),
    .S2_BASE (32'h2000_0000), .S2_MASK (32'hFFFF_F000),
    .S3_BASE (32'h3000_0000), .S3_MASK (32'hFFFF_F000),
    .S4_BASE (32'h4000_0000), .S4_MASK (32'hFFFF_0000)
) dut (
    .clk          (clk),
    .ext_rst_n    (ext_rst_n),
    .soft_rst_pulse(soft_rst_pulse)
);

// ---------------------------------------------------------------------------
// Shorthand wire aliases (tap vào internal nets của DUT)
// ---------------------------------------------------------------------------

// --- CPU <-> DCache ---
wire [31:0] cpu_dcache_addr  = dut.cpu_dcache_addr;
wire [31:0] cpu_dcache_wdata = dut.cpu_dcache_wdata;
wire [3:0]  cpu_dcache_wstrb = dut.cpu_dcache_wstrb;
wire        cpu_dcache_req   = dut.cpu_dcache_req;
wire        cpu_dcache_we    = dut.cpu_dcache_we;
wire [31:0] dcache_cpu_rdata = dut.dcache_cpu_rdata;
wire        dcache_cpu_ready = dut.dcache_cpu_ready;
wire [1:0]  cpu_dcache_fence_type = dut.cpu_dcache_fence_type;
// Convenience: any fence đang active
wire        cpu_dcache_fence = |cpu_dcache_fence_type;

// --- DCache AXI Master (M1) ---
// Write address channel
wire [3:0]  m1_awid     = dut.m1_awid;
wire [31:0] m1_awaddr   = dut.m1_awaddr;
wire [7:0]  m1_awlen    = dut.m1_awlen;
wire        m1_awvalid  = dut.m1_awvalid;
wire        m1_awready  = dut.m1_awready;
// Write data channel
wire [31:0] m1_wdata    = dut.m1_wdata;
wire [3:0]  m1_wstrb    = dut.m1_wstrb;
wire        m1_wlast    = dut.m1_wlast;
wire        m1_wvalid   = dut.m1_wvalid;
wire        m1_wready   = dut.m1_wready;
// Write response
wire [3:0]  m1_bid      = dut.m1_bid;
wire [1:0]  m1_bresp    = dut.m1_bresp;
wire        m1_bvalid   = dut.m1_bvalid;
wire        m1_bready   = dut.m1_bready;
// Read address channel
wire [3:0]  m1_arid     = dut.m1_arid;
wire [31:0] m1_araddr   = dut.m1_araddr;
wire        m1_arvalid  = dut.m1_arvalid;
wire        m1_arready  = dut.m1_arready;
// Read data channel
wire [3:0]  m1_rid      = dut.m1_rid;
wire [31:0] m1_rdata    = dut.m1_rdata;
wire [1:0]  m1_rresp    = dut.m1_rresp;
wire        m1_rlast    = dut.m1_rlast;
wire        m1_rvalid   = dut.m1_rvalid;
wire        m1_rready   = dut.m1_rready;

// --- DMEM Slave port (S1) ---
wire [31:0] s1_awaddr   = dut.s1_awaddr;
wire        s1_awvalid  = dut.s1_awvalid;
wire        s1_awready  = dut.s1_awready;
wire [31:0] s1_wdata    = dut.s1_wdata;
wire [3:0]  s1_wstrb    = dut.s1_wstrb;
wire        s1_wlast    = dut.s1_wlast;
wire        s1_wvalid   = dut.s1_wvalid;
wire        s1_wready   = dut.s1_wready;
wire [1:0]  s1_bresp    = dut.s1_bresp;
wire        s1_bvalid   = dut.s1_bvalid;
wire        s1_bready   = dut.s1_bready;
wire [31:0] s1_araddr   = dut.s1_araddr;
wire        s1_arvalid  = dut.s1_arvalid;
wire        s1_arready  = dut.s1_arready;
wire [31:0] s1_rdata    = dut.s1_rdata;
wire [1:0]  s1_rresp    = dut.s1_rresp;
wire        s1_rlast    = dut.s1_rlast;
wire        s1_rvalid   = dut.s1_rvalid;
wire        s1_rready   = dut.s1_rready;

// --- DMA 64-bit Master ---
wire [31:0] dma_awaddr  = dut.dma_awaddr;
wire [7:0]  dma_awlen   = dut.dma_awlen;
wire        dma_awvalid = dut.dma_awvalid;
wire        dma_awready = dut.dma_awready;
wire [63:0] dma_wdata   = dut.dma_wdata;
wire [7:0]  dma_wstrb   = dut.dma_wstrb;
wire        dma_wlast   = dut.dma_wlast;
wire        dma_wvalid  = dut.dma_wvalid;
wire        dma_wready  = dut.dma_wready;
wire [1:0]  dma_bresp   = dut.dma_bresp;
wire        dma_bvalid  = dut.dma_bvalid;
wire        dma_bready  = dut.dma_bready;
wire [31:0] dma_araddr  = dut.dma_araddr;
wire        dma_arvalid = dut.dma_arvalid;
wire        dma_arready = dut.dma_arready;
wire [63:0] dma_rdata   = dut.dma_rdata;
wire        dma_rlast   = dut.dma_rlast;
wire        dma_rvalid  = dut.dma_rvalid;
wire        dma_rready  = dut.dma_rready;

// --- Width converter output to crossbar M2 (32-bit side) ---
wire [31:0] m2_awaddr   = dut.m2_awaddr;
wire        m2_awvalid  = dut.m2_awvalid;
wire        m2_awready  = dut.m2_awready;
wire [31:0] m2_wdata    = dut.m2_wdata;
wire [3:0]  m2_wstrb    = dut.m2_wstrb;
wire        m2_wlast    = dut.m2_wlast;
wire        m2_wvalid   = dut.m2_wvalid;
wire        m2_wready   = dut.m2_wready;

// ---------------------------------------------------------------------------
// Monitor task: in màu theo từng stage
// ---------------------------------------------------------------------------

// ===================== STAGE 1: CPU → DCache =====================
always @(posedge clk) begin
    if (ext_rst_n && cpu_dcache_req) begin
        if (cpu_dcache_we)
            $display("[%0t] [CPU->DCACHE] WRITE  addr=0x%08h data=0x%08h strb=%04b",
                     $time, cpu_dcache_addr, cpu_dcache_wdata, cpu_dcache_wstrb);
        else
            $display("[%0t] [CPU->DCACHE] READ   addr=0x%08h",
                     $time, cpu_dcache_addr);
    end
end

always @(posedge clk) begin
    if (ext_rst_n && dcache_cpu_ready && !cpu_dcache_we)
        $display("[%0t] [DCACHE->CPU] RDATA  data=0x%08h",
                 $time, dcache_cpu_rdata);
end

always @(posedge clk) begin
    if (ext_rst_n && cpu_dcache_fence) begin
        if (cpu_dcache_fence_type == 2'b01)
            $display("[%0t] [CPU->DCACHE] FENCE w,w  (flush dirty only, stack safe)",  $time);
        else if (cpu_dcache_fence_type == 2'b10)
            $display("[%0t] [CPU->DCACHE] FENCE r,r  (invalidate only)",               $time);
        else
            $display("[%0t] [CPU->DCACHE] FENCE iorw (flush + invalidate)",             $time);
    end
end

// ===================== STAGE 2: DCache AXI Master (M1) =====================
always @(posedge clk) begin
    if (ext_rst_n && m1_awvalid && m1_awready)
        $display("[%0t] [M1-AW] id=%0d addr=0x%08h len=%0d  *** DCache AW handshake ***",
                 $time, m1_awid, m1_awaddr, m1_awlen);
end

always @(posedge clk) begin
    if (ext_rst_n && m1_wvalid && m1_wready)
        $display("[%0t] [M1-W ] data=0x%08h strb=%04b last=%b  *** DCache W beat ***",
                 $time, m1_wdata, m1_wstrb, m1_wlast);
end

always @(posedge clk) begin
    if (ext_rst_n && m1_bvalid && m1_bready)
        $display("[%0t] [M1-B ] id=%0d resp=%02b  *** DCache Write Response ***",
                 $time, m1_bid, m1_bresp);
end

always @(posedge clk) begin
    if (ext_rst_n && m1_arvalid && m1_arready)
        $display("[%0t] [M1-AR] id=%0d addr=0x%08h  *** DCache AR handshake ***",
                 $time, m1_arid, m1_araddr);
end

always @(posedge clk) begin
    if (ext_rst_n && m1_rvalid && m1_rready)
        $display("[%0t] [M1-R ] id=%0d data=0x%08h resp=%02b last=%b  *** DCache R beat ***",
                 $time, m1_rid, m1_rdata, m1_rresp, m1_rlast);
end

// ===================== STAGE 3: DMEM Slave port (S1) =====================
always @(posedge clk) begin
    if (ext_rst_n && s1_awvalid && s1_awready)
        $display("[%0t] [S1-AW] addr=0x%08h  *** DMEM AW handshake ***",
                 $time, s1_awaddr);
end

always @(posedge clk) begin
    if (ext_rst_n && s1_wvalid && s1_wready)
        $display("[%0t] [S1-W ] data=0x%08h strb=%04b last=%b  *** DMEM W beat ***",
                 $time, s1_wdata, s1_wstrb, s1_wlast);
end

always @(posedge clk) begin
    if (ext_rst_n && s1_bvalid && s1_bready)
        $display("[%0t] [S1-B ] resp=%02b  *** DMEM Write Response ***",
                 $time, s1_bresp);
end

always @(posedge clk) begin
    if (ext_rst_n && s1_arvalid && s1_arready)
        $display("[%0t] [S1-AR] addr=0x%08h  *** DMEM AR handshake ***",
                 $time, s1_araddr);
end

always @(posedge clk) begin
    if (ext_rst_n && s1_rvalid && s1_rready)
        $display("[%0t] [S1-R ] data=0x%08h resp=%02b last=%b  *** DMEM R beat ***",
                 $time, s1_rdata, s1_rresp, s1_rlast);
end

// ===================== STAGE 4: DMA 64-bit master =====================
always @(posedge clk) begin
    if (ext_rst_n && dma_awvalid && dma_awready)
        $display("[%0t] [DMA-AW] addr=0x%08h len=%0d  *** DMA AW handshake (64-bit) ***",
                 $time, dma_awaddr, dma_awlen);
end

always @(posedge clk) begin
    if (ext_rst_n && dma_wvalid && dma_wready)
        $display("[%0t] [DMA-W ] data=0x%016h strb=%08b last=%b  *** DMA W beat (64-bit) ***",
                 $time, dma_wdata, dma_wstrb, dma_wlast);
end

always @(posedge clk) begin
    if (ext_rst_n && dma_bvalid && dma_bready)
        $display("[%0t] [DMA-B ] resp=%02b  *** DMA Write Response ***",
                 $time, dma_bresp);
end

always @(posedge clk) begin
    if (ext_rst_n && dma_arvalid && dma_arready)
        $display("[%0t] [DMA-AR] addr=0x%08h  *** DMA AR handshake (64-bit) ***",
                 $time, dma_araddr);
end

always @(posedge clk) begin
    if (ext_rst_n && dma_rvalid && dma_rready)
        $display("[%0t] [DMA-R ] data=0x%016h last=%b  *** DMA R beat (64-bit) ***",
                 $time, dma_rdata, dma_rlast);
end

// ===================== STAGE 5: Width Converter output → Crossbar M2 =====================
always @(posedge clk) begin
    if (ext_rst_n && m2_awvalid && m2_awready)
        $display("[%0t] [M2-AW] addr=0x%08h  *** WConv->Crossbar AW (32-bit) ***",
                 $time, m2_awaddr);
end

always @(posedge clk) begin
    if (ext_rst_n && m2_wvalid && m2_wready)
        $display("[%0t] [M2-W ] data=0x%08h strb=%04b last=%b  *** WConv->Crossbar W beat (32-bit) ***",
                 $time, m2_wdata, m2_wstrb, m2_wlast);
end

// ---------------------------------------------------------------------------
// Bộ đếm transaction để thống kê
// ---------------------------------------------------------------------------
integer cnt_cpu_req  = 0;
integer cnt_cpu_wr   = 0;
integer cnt_cpu_rd   = 0;
integer cnt_m1_aw    = 0;
integer cnt_m1_w     = 0;
integer cnt_m1_ar    = 0;
integer cnt_s1_aw    = 0;
integer cnt_s1_ar    = 0;
integer cnt_dma_aw   = 0;
integer cnt_dma_ar   = 0;
integer cnt_m2_aw    = 0;

always @(posedge clk) begin
    if (ext_rst_n) begin
        if (cpu_dcache_req)               cnt_cpu_req  <= cnt_cpu_req  + 1;
        if (cpu_dcache_req && cpu_dcache_we) cnt_cpu_wr <= cnt_cpu_wr  + 1;
        if (cpu_dcache_req && !cpu_dcache_we) cnt_cpu_rd<= cnt_cpu_rd  + 1;
        if (m1_awvalid && m1_awready)     cnt_m1_aw    <= cnt_m1_aw   + 1;
        if (m1_wvalid  && m1_wready)      cnt_m1_w     <= cnt_m1_w    + 1;
        if (m1_arvalid && m1_arready)     cnt_m1_ar    <= cnt_m1_ar   + 1;
        if (s1_awvalid && s1_awready)     cnt_s1_aw    <= cnt_s1_aw   + 1;
        if (s1_arvalid && s1_arready)     cnt_s1_ar    <= cnt_s1_ar   + 1;
        if (dma_awvalid && dma_awready)   cnt_dma_aw   <= cnt_dma_aw  + 1;
        if (dma_arvalid && dma_arready)   cnt_dma_ar   <= cnt_dma_ar  + 1;
        if (m2_awvalid && m2_awready)     cnt_m2_aw    <= cnt_m2_aw   + 1;
    end
end

// ---------------------------------------------------------------------------
// Timeout watchdog: 500 µs
// ---------------------------------------------------------------------------
initial begin
    #7000;
    $display("[WATCHDOG] Simulation timeout 500us reached. Stopping.");
    print_summary();
    $finish;
end

// ---------------------------------------------------------------------------
// Kiểm tra lỗi AXI response
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (ext_rst_n) begin
        if (m1_bvalid && m1_bready && m1_bresp != 2'b00)
            $display("[%0t] *** ERROR *** M1 BRESP = %02b (non-OKAY)", $time, m1_bresp);
        if (m1_rvalid && m1_rready && m1_rresp != 2'b00)
            $display("[%0t] *** ERROR *** M1 RRESP = %02b (non-OKAY)", $time, m1_rresp);
        if (s1_bvalid && s1_bready && s1_bresp != 2'b00)
            $display("[%0t] *** ERROR *** S1 BRESP = %02b (non-OKAY)", $time, s1_bresp);
        if (s1_rvalid && s1_rready && s1_rresp != 2'b00)
            $display("[%0t] *** ERROR *** S1 RRESP = %02b (non-OKAY)", $time, s1_rresp);
        if (dma_bvalid && dma_bready && dma_bresp != 2'b00)
            $display("[%0t] *** ERROR *** DMA BRESP = %02b (non-OKAY)", $time, dma_bresp);
    end
end

// ---------------------------------------------------------------------------
// Kiểm tra địa chỉ DMEM có nằm đúng range không
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (ext_rst_n) begin
        if (s1_awvalid && s1_awready)
            if ((s1_awaddr & 32'hFFFF_E000) != 32'h1000_0000)
                $display("[%0t] *** ADDR WARNING *** S1 AW addr=0x%08h ngoài DMEM range!",
                         $time, s1_awaddr);
        if (s1_arvalid && s1_arready)
            if ((s1_araddr & 32'hFFFF_E000) != 32'h1000_0000)
                $display("[%0t] *** ADDR WARNING *** S1 AR addr=0x%08h ngoài DMEM range!",
                         $time, s1_araddr);
    end
end

// ---------------------------------------------------------------------------
// VCD dump
// ---------------------------------------------------------------------------
initial begin
    $dumpfile("tb_data_path.vcd");
    $dumpvars(0, tb_data_path);  // dump tất cả
    // Nếu quá lớn, dùng selective dump:
    // $dumpvars(1, dut.u_dcache);
    // $dumpvars(1, dut.u_dmem);
    // $dumpvars(1, dut.u_ascon);
    // $dumpvars(1, dut.u_width_conv);
end

// ---------------------------------------------------------------------------
// Task in bản tóm tắt
// ---------------------------------------------------------------------------
task print_summary;
    begin
        $display("========================================");
        $display("  DATA PATH TRANSACTION SUMMARY");
        $display("========================================");
        $display("  CPU dcache req total : %0d", cnt_cpu_req);
        $display("  CPU dcache WRITE     : %0d", cnt_cpu_wr);
        $display("  CPU dcache READ      : %0d", cnt_cpu_rd);
        $display("  M1 AW handshakes     : %0d  (DCache -> Crossbar)", cnt_m1_aw);
        $display("  M1 W beats           : %0d", cnt_m1_w);
        $display("  M1 AR handshakes     : %0d", cnt_m1_ar);
        $display("  S1 AW handshakes     : %0d  (Crossbar -> DMEM)", cnt_s1_aw);
        $display("  S1 AR handshakes     : %0d", cnt_s1_ar);
        $display("  DMA AW handshakes    : %0d  (ASCON DMA 64-bit)", cnt_dma_aw);
        $display("  DMA AR handshakes    : %0d", cnt_dma_ar);
        $display("  M2 AW handshakes     : %0d  (WConv 32-bit -> Crossbar)", cnt_m2_aw);
        $display("========================================");
        if (cnt_s1_aw != cnt_m1_aw + cnt_m2_aw)
            $display("  [WARN] S1 AW count (%0d) != M1+M2 AW (%0d). Có thể crossbar drop hoặc lỗi route.",
                     cnt_s1_aw, cnt_m1_aw + cnt_m2_aw);
        else
            $display("  [OK] AW transaction count khớp.");
    end
endtask

// ---------------------------------------------------------------------------
// Main: chạy đủ thời gian cho CPU boot và DMA khởi động
// ---------------------------------------------------------------------------
initial begin
    $display("=== tb_data_path: start ===");
    $display("  Theo dõi: CPU->DCache->DMEM và DMA->Width Converter->DMEM");
    $display("  DMEM base = 0x%08h", DMEM_BASE);

    // Chờ reset xong
    @(posedge ext_rst_n);
    $display("[%0t] Reset done, CPU running...", $time);

    // Chạy 20000 chu kỳ để CPU thực hiện store/load và DMA kịp kick off
    repeat(20000) @(posedge clk);

    $display("[%0t] === Simulation ended normally ===", $time);
    print_summary();
    $finish;
end

endmodule