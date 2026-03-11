// =============================================================================
// Module   : soc_ctrl_slave
// Project  : RISC-V + ASCON SoC v3
// Language : Verilog IEEE 1364-2001 (Icarus Verilog compatible)
// Target   : S3 slave @ 0x3000_0000 on axi4_crossbar_3m4s
//
// Changes vs previous version:
//   - Thêm output port irq_out = irq_status_r & irq_mask_r → nối vào CPU
//   - Thêm output port soft_rst_pulse → soc_top expose ra ngoài / testbench tap
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
    // AXI4-Full slave port (single-beat; AWLEN/ARLEN/WLAST ignored)
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
    input  wire                   ascon_irq,

    // ----------------------------------------------------------------
    // SoC control outputs
    // ----------------------------------------------------------------
    // [IMP-2] irq_out: nối vào CPU external_irq port
    //   HIGH khi ascon_irq sticky đã set VÀ IRQ_MASK bit[0]=1 (enabled)
    output wire                   irq_out,

    // [IMP-E] soft_rst_pulse: pulse 1 cycle khi CPU ghi SYS_CTRL[0]=1
    //   soc_top expose ra output port hoặc dùng để reset domain khác
    output wire                   soft_rst_pulse
);

// =============================================================================
// [C] Register File - Address Decode Constants
// =============================================================================
localparam ADDR_SYS_ID      = 12'h000;
localparam ADDR_SYS_CTRL    = 12'h004;
localparam ADDR_IRQ_STATUS  = 12'h008;
localparam ADDR_IRQ_MASK    = 12'h00C;
localparam ADDR_ICACHE_HITS = 12'h010;
localparam ADDR_ICACHE_MISS = 12'h014;
localparam ADDR_DCACHE_HITS = 12'h018;
localparam ADDR_DCACHE_MISS = 12'h01C;
localparam ADDR_DCACHE_WR   = 12'h020;
localparam ADDR_CYCLE_CNT   = 12'h024;

localparam SYS_ID_VALUE     = 32'hA5C0_0001;

// =============================================================================
// [E] Soft-Reset Pulse Generator
// =============================================================================
reg soft_rst_pending;

// [IMP-E] expose soft_rst_pulse ra output port
assign soft_rst_pulse = soft_rst_pending;

// =============================================================================
// [C] Register Declarations
// =============================================================================
reg irq_mask_r;
reg irq_status_r;
reg [31:0] cycle_cnt_r;

// =============================================================================
// [IMP-2] IRQ output: kết hợp sticky status với mask
//   irq_out HIGH → CPU nhận external interrupt
//   CPU có thể kiểm tra IRQ_STATUS để biết nguồn, rồi W1C để clear
// =============================================================================
assign irq_out = irq_status_r & irq_mask_r;

// =============================================================================
// [D] IRQ Sticky Logic
// =============================================================================
reg ascon_irq_prev;
wire ascon_irq_rising = ascon_irq & ~ascon_irq_prev;

reg irq_w1c_clear;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ascon_irq_prev <= 1'b0;
        irq_status_r   <= 1'b0;
    end else begin
        ascon_irq_prev <= ascon_irq;
        if (irq_w1c_clear)
            irq_status_r <= 1'b0;
        else if (ascon_irq_rising)
            irq_status_r <= 1'b1;
    end
end

// =============================================================================
// [C] CYCLE_CNT
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle_cnt_r <= 32'd0;
    else if (soft_rst_pulse)
        cycle_cnt_r <= 32'd0;
    else
        cycle_cnt_r <= cycle_cnt_r + 32'd1;
end

// =============================================================================
// [A] AXI Write Channel
// =============================================================================
reg [ID_WIDTH-1:0]    aw_id_lat;
reg [ADDR_WIDTH-1:0]  aw_addr_lat;
reg                   aw_done;
reg                   w_done;
reg [DATA_WIDTH-1:0]  w_data_lat;
reg [DATA_WIDTH/8-1:0] w_strb_lat;
reg                   bvalid_r;
reg [1:0]             bresp_r;

wire [11:0] aw_offset = aw_addr_lat[11:0];

wire aw_is_ro = (aw_offset == ADDR_SYS_ID)      ||
                (aw_offset == ADDR_ICACHE_HITS)  ||
                (aw_offset == ADDR_ICACHE_MISS)  ||
                (aw_offset == ADDR_DCACHE_HITS)  ||
                (aw_offset == ADDR_DCACHE_MISS)  ||
                (aw_offset == ADDR_DCACHE_WR)    ||
                (aw_offset == ADDR_CYCLE_CNT)    ||
                (aw_offset == ADDR_IRQ_STATUS);

wire write_execute = aw_done && w_done && !bvalid_r;

// Soft-reset
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        soft_rst_pending <= 1'b0;
    end else begin
        soft_rst_pending <= 1'b0;
        if (write_execute && (aw_offset == ADDR_SYS_CTRL)) begin
            if (w_data_lat[0] & w_strb_lat[0])
                soft_rst_pending <= 1'b1;
        end
    end
end

// IRQ_MASK write
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        irq_mask_r <= 1'b0;
    end else begin
        if (write_execute && (aw_offset == ADDR_IRQ_MASK)) begin
            if (w_strb_lat[0])
                irq_mask_r <= w_data_lat[0];
        end
    end
end

// IRQ_STATUS W1C
always @(*) begin
    irq_w1c_clear = 1'b0;
    if (write_execute && (aw_offset == ADDR_IRQ_STATUS)) begin
        if (w_strb_lat[0] && w_data_lat[0])
            irq_w1c_clear = 1'b1;
    end
end

// AW channel latch
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        aw_done     <= 1'b0;
        aw_id_lat   <= {ID_WIDTH{1'b0}};
        aw_addr_lat <= {ADDR_WIDTH{1'b0}};
    end else begin
        if (S_AXI_AWVALID && S_AXI_AWREADY) begin
            aw_id_lat   <= S_AXI_AWID;
            aw_addr_lat <= S_AXI_AWADDR;
            aw_done     <= 1'b1;
        end
        if (bvalid_r && S_AXI_BREADY)
            aw_done <= 1'b0;
    end
end

// W channel latch
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        w_done     <= 1'b0;
        w_data_lat <= {DATA_WIDTH{1'b0}};
        w_strb_lat <= {(DATA_WIDTH/8){1'b0}};
    end else begin
        if (S_AXI_WVALID && S_AXI_WREADY) begin
            w_data_lat <= S_AXI_WDATA;
            w_strb_lat <= S_AXI_WSTRB;
            w_done     <= 1'b1;
        end
        if (bvalid_r && S_AXI_BREADY)
            w_done <= 1'b0;
    end
end

// B channel
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bvalid_r <= 1'b0;
        bresp_r  <= 2'b00;
    end else begin
        if (write_execute) begin
            bvalid_r <= 1'b1;
            if (aw_is_ro && (aw_offset != ADDR_IRQ_STATUS))
                bresp_r <= 2'b10; // SLVERR
            else
                bresp_r <= 2'b00; // OKAY
        end
        if (bvalid_r && S_AXI_BREADY)
            bvalid_r <= 1'b0;
    end
end

assign S_AXI_AWREADY = !aw_done;
assign S_AXI_WREADY  = !w_done;
assign S_AXI_BVALID  = bvalid_r;
assign S_AXI_BRESP   = bresp_r;
assign S_AXI_BID     = aw_id_lat;

// =============================================================================
// [B] AXI Read Channel
// =============================================================================
reg [ID_WIDTH-1:0]    ar_id_lat;
reg [ADDR_WIDTH-1:0]  ar_addr_lat;
reg                   ar_done;
reg                   rvalid_r;
reg [DATA_WIDTH-1:0]  rdata_r;

wire [11:0] ar_offset = ar_addr_lat[11:0];

reg [DATA_WIDTH-1:0] rdata_mux;
always @(*) begin
    case (ar_offset)
        ADDR_SYS_ID     : rdata_mux = SYS_ID_VALUE;
        ADDR_SYS_CTRL   : rdata_mux = 32'd0;
        ADDR_IRQ_STATUS : rdata_mux = {31'd0, irq_status_r};
        ADDR_IRQ_MASK   : rdata_mux = {31'd0, irq_mask_r};
        ADDR_ICACHE_HITS: rdata_mux = icache_hits;
        ADDR_ICACHE_MISS: rdata_mux = icache_misses;
        ADDR_DCACHE_HITS: rdata_mux = dcache_hits;
        ADDR_DCACHE_MISS: rdata_mux = dcache_misses;
        ADDR_DCACHE_WR  : rdata_mux = dcache_writes;
        ADDR_CYCLE_CNT  : rdata_mux = cycle_cnt_r;
        default         : rdata_mux = 32'd0;
    endcase
end

// AR channel latch
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ar_done     <= 1'b0;
        ar_id_lat   <= {ID_WIDTH{1'b0}};
        ar_addr_lat <= {ADDR_WIDTH{1'b0}};
    end else begin
        if (S_AXI_ARVALID && S_AXI_ARREADY) begin
            ar_id_lat   <= S_AXI_ARID;
            ar_addr_lat <= S_AXI_ARADDR;
            ar_done     <= 1'b1;
        end
        if (rvalid_r && S_AXI_RREADY)
            ar_done <= 1'b0;
    end
end

// R channel
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rvalid_r <= 1'b0;
        rdata_r  <= {DATA_WIDTH{1'b0}};
    end else begin
        if (ar_done && !rvalid_r) begin
            rvalid_r <= 1'b1;
            rdata_r  <= rdata_mux;
        end
        if (rvalid_r && S_AXI_RREADY)
            rvalid_r <= 1'b0;
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