`timescale 1ns/1ps

// =============================================================================
// Module   : soc_ctrl_slave
// Project  : RISC-V + ASCON SoC
// Target   : S3 slave @ 0x3000_0000
//
// Changes vs previous version:
//   [Fix-PLIC] irq_out đã chuyển sang PLIC. irq_out port vẫn giữ để
//              tương thích ngược với soc_top.v — nối vào PLIC irq_sources.
//              Khi PLIC active, CPU external_irq = PLIC.meip (không dùng irq_out trực tiếp nữa).
//
//   [Fix-IRQ]  IRQ_STATUS mở rộng từ 1-bit lên 6-bit:
//              Bit[0]: ASCON_IRQ
//              Bit[1]: UART_IRQ  (từ plic / uart_top.irq_out)
//              Bit[2]: GPIO_IRQ
//              Bit[3]: SPI_IRQ
//              Bit[4]: TIMER_IRQ
//              Bit[5]: WDT_IRQ
//
//   [Fix-IRQ]  IRQ_MASK mở rộng 6-bit tương ứng.
//
//   [Fix-NEW]  Thêm HART_ID register tại 0x028 → read = 0x0.
//
//   [Fix-NEW]  Thêm input port cho uart/gpio/spi/timer/wdt irq.
//              (tie to 0 trong soc_top cho đến khi peripheral được kết nối)
// =============================================================================

`timescale 1ns/1ps

module soc_ctrl_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // ----------------------------------------------------------------
    // AXI4-Full slave port
    // ----------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]    S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]  S_AXI_AWADDR,
    input  wire [7:0]             S_AXI_AWLEN,
    input  wire [2:0]             S_AXI_AWSIZE,
    input  wire [1:0]             S_AXI_AWBURST,
    input  wire [2:0]             S_AXI_AWPROT,
    input  wire                   S_AXI_AWVALID,
    output wire                   S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]  S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                   S_AXI_WLAST,
    input  wire                   S_AXI_WVALID,
    output wire                   S_AXI_WREADY,

    output wire [ID_WIDTH-1:0]    S_AXI_BID,
    output wire [1:0]             S_AXI_BRESP,
    output wire                   S_AXI_BVALID,
    input  wire                   S_AXI_BREADY,

    input  wire [ID_WIDTH-1:0]    S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]  S_AXI_ARADDR,
    input  wire [7:0]             S_AXI_ARLEN,
    input  wire [2:0]             S_AXI_ARSIZE,
    input  wire [1:0]             S_AXI_ARBURST,
    input  wire [2:0]             S_AXI_ARPROT,
    input  wire                   S_AXI_ARVALID,
    output wire                   S_AXI_ARREADY,

    output wire [ID_WIDTH-1:0]    S_AXI_RID,
    output wire [DATA_WIDTH-1:0]  S_AXI_RDATA,
    output wire [1:0]             S_AXI_RRESP,
    output wire                   S_AXI_RLAST,
    output wire                   S_AXI_RVALID,
    input  wire                   S_AXI_RREADY,

    // ----------------------------------------------------------------
    // SoC status inputs
    // ----------------------------------------------------------------
    input  wire [31:0]            icache_hits,
    input  wire [31:0]            icache_misses,
    input  wire [31:0]            dcache_hits,
    input  wire [31:0]            dcache_misses,
    input  wire [31:0]            dcache_writes,

    // [Fix-IRQ] 6 IRQ sources — tie unused ones to 0 in soc_top
    input  wire                   ascon_irq,
    input  wire                   uart_irq,    // từ uart_top.irq_out
    input  wire                   gpio_irq,    // từ gpio_top.irq_out
    input  wire                   spi_irq,     // từ spi_top.irq_out
    input  wire                   timer_irq,   // từ timer_wdt_top (GPT expire)
    input  wire                   wdt_irq,     // từ timer_wdt_top (WDT warn)

    // [A2] Performance counter inputs — từ CPU core
    input  wire                   perf_stall_in,      // = stall_any
    input  wire                   perf_instr_ret_in,  // = regwrite_wb && !stall_any

    // ----------------------------------------------------------------
    // SoC control outputs
    // ----------------------------------------------------------------
    // [Fix-PLIC] irq_out vẫn giữ để nối vào PLIC irq_sources[8] (ASCON).
    // Khi PLIC active, CPU external_irq = PLIC.meip thay vì irq_out trực tiếp.
    output wire                   irq_out,

    output wire                   soft_rst_pulse
);

// =============================================================================
// Register Address Map
// =============================================================================
localparam ADDR_SYS_ID      = 12'h000;  // RO  0x3000_0000
localparam ADDR_SYS_CTRL    = 12'h004;  // WO  0x3000_0004
localparam ADDR_IRQ_STATUS  = 12'h008;  // RW1C 0x3000_0008  [6-bit]
localparam ADDR_IRQ_MASK    = 12'h00C;  // RW  0x3000_000C  [6-bit]
localparam ADDR_ICACHE_HITS = 12'h010;  // RO
localparam ADDR_ICACHE_MISS = 12'h014;  // RO
localparam ADDR_DCACHE_HITS = 12'h018;  // RO
localparam ADDR_DCACHE_MISS = 12'h01C;  // RO
localparam ADDR_DCACHE_WR   = 12'h020;  // RO
localparam ADDR_CYCLE_CNT   = 12'h024;  // RO  cycle[31:0]
localparam ADDR_HART_ID     = 12'h028;  // RO  = 32'h0
localparam ADDR_PERF_CTRL   = 12'h02C;  // RW  [0]=enable [1]=reset_on_read
localparam ADDR_CYCLE_HI    = 12'h030;  // RO  cycle[63:32]
localparam ADDR_INSTR_LO    = 12'h034;  // RO  instr_ret[31:0]
localparam ADDR_INSTR_HI    = 12'h038;  // RO  instr_ret[63:32]
localparam ADDR_STALL_CNT   = 12'h03C;  // RO  stall_cycles[31:0]

localparam SYS_ID_VALUE     = 32'hA5C0_0001;

// =============================================================================
// Soft-Reset Pulse
// =============================================================================
reg soft_rst_pending;
assign soft_rst_pulse = soft_rst_pending;

// =============================================================================
// [Fix-IRQ] 6-bit IRQ registers
// =============================================================================
reg [5:0] irq_mask_r;    // [5:0] = {wdt, timer, spi, gpio, uart, ascon}
reg [5:0] irq_status_r;  // sticky W1C

// irq_out: OR of all masked IRQ sources → nối vào PLIC source[8] hoặc
// tạm thời nối trực tiếp vào CPU external_irq trước khi có PLIC
assign irq_out = |(irq_status_r & irq_mask_r);

// =============================================================================
// IRQ Edge Detect & Sticky Latch
// =============================================================================
reg [5:0] irq_prev;
wire [5:0] irq_raw   = {wdt_irq, timer_irq, spi_irq, gpio_irq, uart_irq, ascon_irq};
wire [5:0] irq_rising = irq_raw & ~irq_prev;

reg [5:0] irq_w1c_mask;   // bits to clear this cycle (from write path)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        irq_prev     <= 6'd0;
        irq_status_r <= 6'd0;
    end else begin
        irq_prev <= irq_raw;
        // W1C has priority over set (to avoid re-arming same cycle)
        irq_status_r <= (irq_status_r & ~irq_w1c_mask) | irq_rising;
    end
end

// =============================================================================
// [A2] PERF_CTRL register — [0]=perf_en (gate all counter increments)
// Write handler is below in the AXI write section.
// =============================================================================
reg perf_ctrl_r;
wire perf_en = perf_ctrl_r;

// =============================================================================
// CYCLE_CNT (64-bit), INSTR_CNT (64-bit), STALL_CNT (32-bit)
// perf_ror_trigger defined in Read Channel section — resets on INSTR_HI read
// =============================================================================
reg [63:0] cycle_cnt_r;
reg [63:0] instr_cnt_r;
reg [31:0] stall_cnt_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_cnt_r <= 64'd0;
        instr_cnt_r <= 64'd0;
        stall_cnt_r <= 32'd0;
    end else if (soft_rst_pulse) begin
        cycle_cnt_r <= 64'd0;
        instr_cnt_r <= 64'd0;
        stall_cnt_r <= 32'd0;
    end else begin
        if (perf_en)
            cycle_cnt_r <= cycle_cnt_r + 64'd1;
        if (perf_en && perf_instr_ret_in)
            instr_cnt_r <= instr_cnt_r + 64'd1;
        if (perf_en && perf_stall_in)
            stall_cnt_r <= stall_cnt_r + 32'd1;
    end
end

// =============================================================================
// AXI Write Channel
// =============================================================================
reg [ID_WIDTH-1:0]     aw_id_lat;
reg [ADDR_WIDTH-1:0]   aw_addr_lat;
reg                    aw_done;
reg                    w_done;
reg [DATA_WIDTH-1:0]   w_data_lat;
reg [DATA_WIDTH/8-1:0] w_strb_lat;
reg                    bvalid_r;
reg [1:0]              bresp_r;

wire [11:0] aw_offset = aw_addr_lat[11:0];

wire aw_is_ro = (aw_offset == ADDR_SYS_ID)      ||
                (aw_offset == ADDR_ICACHE_HITS)  ||
                (aw_offset == ADDR_ICACHE_MISS)  ||
                (aw_offset == ADDR_DCACHE_HITS)  ||
                (aw_offset == ADDR_DCACHE_MISS)  ||
                (aw_offset == ADDR_DCACHE_WR)    ||
                (aw_offset == ADDR_CYCLE_CNT)    ||
                (aw_offset == ADDR_HART_ID)      ||
                (aw_offset == ADDR_CYCLE_HI)     ||
                (aw_offset == ADDR_INSTR_LO)     ||
                (aw_offset == ADDR_INSTR_HI)     ||
                (aw_offset == ADDR_STALL_CNT);

wire write_execute = aw_done && w_done && !bvalid_r;

// Soft-reset pulse
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        soft_rst_pending <= 1'b0;
    end else begin
        soft_rst_pending <= 1'b0;
        if (write_execute && (aw_offset == ADDR_SYS_CTRL))
            if (w_data_lat[0] & w_strb_lat[0])
                soft_rst_pending <= 1'b1;
    end
end

// IRQ_MASK write (6-bit)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        irq_mask_r <= 6'd0;
    end else begin
        if (write_execute && (aw_offset == ADDR_IRQ_MASK)) begin
            if (w_strb_lat[0]) irq_mask_r <= w_data_lat[5:0];
        end
    end
end

// [A2] PERF_CTRL write
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        perf_ctrl_r <= 1'b1;       // default: counters enabled
    end else if (soft_rst_pulse) begin
        perf_ctrl_r <= 1'b1;
    end else begin
        if (write_execute && (aw_offset == ADDR_PERF_CTRL)) begin
            if (w_strb_lat[0]) perf_ctrl_r <= w_data_lat[0];
        end
    end
end

// IRQ_STATUS W1C (6-bit)
always @(*) begin
    irq_w1c_mask = 6'd0;
    if (write_execute && (aw_offset == ADDR_IRQ_STATUS))
        if (w_strb_lat[0])
            irq_w1c_mask = w_data_lat[5:0];  // write 1 to clear
end

// AW latch
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        aw_done <= 1'b0; aw_id_lat <= {ID_WIDTH{1'b0}}; aw_addr_lat <= {ADDR_WIDTH{1'b0}};
    end else begin
        if (S_AXI_AWVALID && S_AXI_AWREADY) begin
            aw_id_lat <= S_AXI_AWID; aw_addr_lat <= S_AXI_AWADDR; aw_done <= 1'b1;
        end
        if (bvalid_r && S_AXI_BREADY) aw_done <= 1'b0;
    end
end

// W latch
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        w_done <= 1'b0; w_data_lat <= {DATA_WIDTH{1'b0}}; w_strb_lat <= {(DATA_WIDTH/8){1'b0}};
    end else begin
        if (S_AXI_WVALID && S_AXI_WREADY) begin
            w_data_lat <= S_AXI_WDATA; w_strb_lat <= S_AXI_WSTRB; w_done <= 1'b1;
        end
        if (bvalid_r && S_AXI_BREADY) w_done <= 1'b0;
    end
end

// B channel
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bvalid_r <= 1'b0; bresp_r <= 2'b00;
    end else begin
        if (write_execute) begin
            bvalid_r <= 1'b1;
            bresp_r  <= (aw_is_ro) ? 2'b10 : 2'b00; // SLVERR for RO
        end
        if (bvalid_r && S_AXI_BREADY) bvalid_r <= 1'b0;
    end
end

assign S_AXI_AWREADY = !aw_done;
assign S_AXI_WREADY  = !w_done;
assign S_AXI_BVALID  = bvalid_r;
assign S_AXI_BRESP   = bresp_r;
assign S_AXI_BID     = aw_id_lat;

// =============================================================================
// AXI Read Channel
// =============================================================================
reg [ID_WIDTH-1:0]   ar_id_lat;
reg [ADDR_WIDTH-1:0] ar_addr_lat;
reg                  ar_done;
reg                  rvalid_r;
reg [DATA_WIDTH-1:0] rdata_r;

wire [11:0] ar_offset = ar_addr_lat[11:0];

reg [DATA_WIDTH-1:0] rdata_mux;
always @(*) begin
    case (ar_offset)
        ADDR_SYS_ID     : rdata_mux = SYS_ID_VALUE;
        ADDR_SYS_CTRL   : rdata_mux = 32'd0;
        ADDR_IRQ_STATUS : rdata_mux = {26'd0, irq_status_r};
        ADDR_IRQ_MASK   : rdata_mux = {26'd0, irq_mask_r};
        ADDR_ICACHE_HITS: rdata_mux = icache_hits;
        ADDR_ICACHE_MISS: rdata_mux = icache_misses;
        ADDR_DCACHE_HITS: rdata_mux = dcache_hits;
        ADDR_DCACHE_MISS: rdata_mux = dcache_misses;
        ADDR_DCACHE_WR  : rdata_mux = dcache_writes;
        ADDR_CYCLE_CNT  : rdata_mux = cycle_cnt_r[31:0];
        ADDR_HART_ID    : rdata_mux = 32'd0;
        ADDR_PERF_CTRL  : rdata_mux = {31'd0, perf_ctrl_r};
        ADDR_CYCLE_HI   : rdata_mux = cycle_cnt_r[63:32];
        ADDR_INSTR_LO   : rdata_mux = instr_cnt_r[31:0];
        ADDR_INSTR_HI   : rdata_mux = instr_cnt_r[63:32];
        ADDR_STALL_CNT  : rdata_mux = stall_cnt_r;
        default         : rdata_mux = 32'd0;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ar_done <= 1'b0; ar_id_lat <= {ID_WIDTH{1'b0}}; ar_addr_lat <= {ADDR_WIDTH{1'b0}};
    end else begin
        if (S_AXI_ARVALID && S_AXI_ARREADY) begin
            ar_id_lat <= S_AXI_ARID; ar_addr_lat <= S_AXI_ARADDR; ar_done <= 1'b1;
        end
        if (rvalid_r && S_AXI_RREADY) ar_done <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rvalid_r <= 1'b0; rdata_r <= {DATA_WIDTH{1'b0}};
    end else begin
        if (ar_done && !rvalid_r) begin
            rvalid_r <= 1'b1; rdata_r <= rdata_mux;
        end
        if (rvalid_r && S_AXI_RREADY) rvalid_r <= 1'b0;
    end
end

assign S_AXI_ARREADY = !ar_done;
assign S_AXI_RVALID  = rvalid_r;
assign S_AXI_RDATA   = rdata_r;
assign S_AXI_RRESP   = 2'b00;
assign S_AXI_RLAST   = 1'b1;
assign S_AXI_RID     = ar_id_lat;

endmodule
// =============================================================================
// END: soc_ctrl_slave.v
// =============================================================================