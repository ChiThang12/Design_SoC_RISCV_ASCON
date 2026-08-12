`timescale 1ns/1ps

// ============================================================================
// timer_regfile.v — Timer Register File with AXI4-Full Slave Interface
//
// Address: 0x5003_0000 (S8 in crossbar), 4 KB
// Register Map (all 32-bit, word-aligned):
//   0x00  T0_CTRL    [0]=en [1]=auto_reload [2]=irq_en [3]=count_dir
//   0x04  T0_LOAD    reload value for Timer 0
//   0x08  T0_COUNT   current count (read-only)
//   0x0C  T0_STATUS  [0]=timeout_flag (W1C)
//   0x10  T1_CTRL    [0]=en [1]=auto_reload [2]=irq_en [3]=count_dir
//   0x14  T1_LOAD    reload value for Timer 1
//   0x18  T1_COUNT   current count (read-only)
//   0x1C  T1_STATUS  [0]=timeout_flag (W1C)
//   0x20  WDT_CTRL   [0]=en [1]=irq_en
//   0x24  WDT_LOAD   watchdog timeout period
//   0x28  WDT_FEED   write 0xDEAD_FEED to kick watchdog
//   0x2C  WDT_STATUS [0]=expired_flag (W1C)
// ============================================================================

module timer_regfile #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire clk,
    input  wire rst_n,

    // AXI4-Full Slave
    input  wire [ID_WIDTH-1:0]      S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]    S_AXI_AWADDR,
    input  wire [7:0]               S_AXI_AWLEN,
    input  wire [2:0]               S_AXI_AWSIZE,
    input  wire [1:0]               S_AXI_AWBURST,
    input  wire [2:0]               S_AXI_AWPROT,
    input  wire                     S_AXI_AWVALID,
    output wire                     S_AXI_AWREADY,

    input  wire [DATA_WIDTH-1:0]    S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0]  S_AXI_WSTRB,
    input  wire                     S_AXI_WLAST,
    input  wire                     S_AXI_WVALID,
    output wire                     S_AXI_WREADY,

    output reg  [ID_WIDTH-1:0]      S_AXI_BID,
    output reg  [1:0]               S_AXI_BRESP,
    output reg                      S_AXI_BVALID,
    input  wire                     S_AXI_BREADY,

    input  wire [ID_WIDTH-1:0]      S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]    S_AXI_ARADDR,
    input  wire [7:0]               S_AXI_ARLEN,
    input  wire [2:0]               S_AXI_ARSIZE,
    input  wire [1:0]               S_AXI_ARBURST,
    input  wire [2:0]               S_AXI_ARPROT,
    input  wire                     S_AXI_ARVALID,
    output wire                     S_AXI_ARREADY,

    output reg  [ID_WIDTH-1:0]      S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]    S_AXI_RDATA,
    output reg  [1:0]               S_AXI_RRESP,
    output reg                      S_AXI_RLAST,
    output reg                      S_AXI_RVALID,
    input  wire                     S_AXI_RREADY,

    // ── Timer 0 control/status ────────────────────────────────────────────────
    output reg         t0_en,
    output reg         t0_auto_reload,
    output reg         t0_irq_en,
    output reg         t0_count_dir,
    output reg  [31:0] t0_load,
    input  wire [31:0] t0_count,
    input  wire        t0_timeout_flag,
    output reg         t0_timeout_clr,

    // ── Timer 1 control/status ────────────────────────────────────────────────
    output reg         t1_en,
    output reg         t1_auto_reload,
    output reg         t1_irq_en,
    output reg         t1_count_dir,
    output reg  [31:0] t1_load,
    input  wire [31:0] t1_count,
    input  wire        t1_timeout_flag,
    output reg         t1_timeout_clr,

    // ── WDT control/status ───────────────────────────────────────────────────
    output reg         wdt_en,
    output reg         wdt_irq_en,
    output reg  [31:0] wdt_load,
    output reg         wdt_feed_pulse,  // 1-cycle pulse when DEAD_FEED written
    input  wire [31:0] wdt_count,
    input  wire        wdt_expired_flag,
    output reg         wdt_expired_clr
);

    localparam RESP_OKAY = 2'b00;

    localparam REG_T0_CTRL   = 6'h00;
    localparam REG_T0_LOAD   = 6'h04;
    localparam REG_T0_COUNT  = 6'h08;
    localparam REG_T0_STATUS = 6'h0C;
    localparam REG_T1_CTRL   = 6'h10;
    localparam REG_T1_LOAD   = 6'h14;
    localparam REG_T1_COUNT  = 6'h18;
    localparam REG_T1_STATUS = 6'h1C;
    localparam REG_WDT_CTRL  = 6'h20;
    localparam REG_WDT_LOAD  = 6'h24;
    localparam REG_WDT_FEED  = 6'h28;
    localparam REG_WDT_STAT  = 6'h2C;

    localparam WDT_FEED_MAGIC = 32'hDEAD_FEED;

    // =========================================================================
    // Write FSM
    // =========================================================================
    localparam WR_IDLE = 2'b00, WR_DATA = 2'b01, WR_RESP = 2'b10;
    reg [1:0]            wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_r;
    reg [ID_WIDTH-1:0]   bid_r;

    assign S_AXI_AWREADY = (wr_state == WR_IDLE);
    assign S_AXI_WREADY  = (wr_state == WR_DATA);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            wr_addr_r      <= {ADDR_WIDTH{1'b0}};
            bid_r          <= {ID_WIDTH{1'b0}};
            S_AXI_BID      <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP    <= RESP_OKAY;
            S_AXI_BVALID   <= 1'b0;
            // Timers default off
            t0_en          <= 1'b0; t0_auto_reload <= 1'b0;
            t0_irq_en      <= 1'b0; t0_count_dir   <= 1'b0;
            t0_load        <= 32'hFFFF_FFFF;
            t0_timeout_clr <= 1'b0;
            t1_en          <= 1'b0; t1_auto_reload <= 1'b0;
            t1_irq_en      <= 1'b0; t1_count_dir   <= 1'b0;
            t1_load        <= 32'hFFFF_FFFF;
            t1_timeout_clr <= 1'b0;
            wdt_en         <= 1'b0; wdt_irq_en     <= 1'b0;
            wdt_load       <= 32'hFFFF_FFFF;
            wdt_feed_pulse <= 1'b0;
            wdt_expired_clr<= 1'b0;
        end else begin
            // Default: clear single-cycle pulses
            t0_timeout_clr  <= 1'b0;
            t1_timeout_clr  <= 1'b0;
            wdt_feed_pulse  <= 1'b0;
            wdt_expired_clr <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    if (S_AXI_AWVALID) begin
                        wr_addr_r <= S_AXI_AWADDR;
                        bid_r     <= S_AXI_AWID;
                        wr_state  <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (S_AXI_WVALID) begin
                        case (wr_addr_r[5:0])
                            REG_T0_CTRL: begin
                                t0_en          <= S_AXI_WDATA[0];
                                t0_auto_reload <= S_AXI_WDATA[1];
                                t0_irq_en      <= S_AXI_WDATA[2];
                                t0_count_dir   <= S_AXI_WDATA[3];
                            end
                            REG_T0_LOAD:   t0_load <= S_AXI_WDATA;
                            REG_T0_STATUS: if (S_AXI_WDATA[0]) t0_timeout_clr <= 1'b1;  // W1C
                            REG_T1_CTRL: begin
                                t1_en          <= S_AXI_WDATA[0];
                                t1_auto_reload <= S_AXI_WDATA[1];
                                t1_irq_en      <= S_AXI_WDATA[2];
                                t1_count_dir   <= S_AXI_WDATA[3];
                            end
                            REG_T1_LOAD:   t1_load <= S_AXI_WDATA;
                            REG_T1_STATUS: if (S_AXI_WDATA[0]) t1_timeout_clr <= 1'b1;
                            REG_WDT_CTRL: begin
                                wdt_en     <= S_AXI_WDATA[0];
                                wdt_irq_en <= S_AXI_WDATA[1];
                            end
                            REG_WDT_LOAD: wdt_load <= S_AXI_WDATA;
                            REG_WDT_FEED: begin
                                if (S_AXI_WDATA == WDT_FEED_MAGIC)
                                    wdt_feed_pulse <= 1'b1;
                            end
                            REG_WDT_STAT: if (S_AXI_WDATA[0]) wdt_expired_clr <= 1'b1;
                            default: ;
                        endcase

                        if (S_AXI_WLAST) begin
                            S_AXI_BID    <= bid_r;
                            S_AXI_BRESP  <= RESP_OKAY;
                            S_AXI_BVALID <= 1'b1;
                            wr_state     <= WR_RESP;
                        end else begin
                            wr_addr_r <= wr_addr_r + 4;
                        end
                    end
                end
                WR_RESP: begin
                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Read FSM
    // =========================================================================
    localparam RD_IDLE = 1'b0, RD_DATA = 1'b1;
    reg rd_state;
    reg [ADDR_WIDTH-1:0] rd_addr_r;
    reg [7:0]            rd_len_r;

    assign S_AXI_ARREADY = (rd_state == RD_IDLE);

    function [DATA_WIDTH-1:0] reg_read;
        input [5:0] addr;
        begin
            case (addr)
                REG_T0_CTRL:  reg_read = {28'd0, t0_count_dir, t0_irq_en, t0_auto_reload, t0_en};
                REG_T0_LOAD:  reg_read = t0_load;
                REG_T0_COUNT: reg_read = t0_count;
                REG_T0_STATUS:reg_read = {31'd0, t0_timeout_flag};
                REG_T1_CTRL:  reg_read = {28'd0, t1_count_dir, t1_irq_en, t1_auto_reload, t1_en};
                REG_T1_LOAD:  reg_read = t1_load;
                REG_T1_COUNT: reg_read = t1_count;
                REG_T1_STATUS:reg_read = {31'd0, t1_timeout_flag};
                REG_WDT_CTRL: reg_read = {30'd0, wdt_irq_en, wdt_en};
                REG_WDT_LOAD: reg_read = wdt_load;
                REG_WDT_FEED: reg_read = 32'd0;  // write-only, read returns 0
                REG_WDT_STAT: reg_read = {31'd0, wdt_expired_flag};
                default:      reg_read = 32'd0;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state     <= RD_IDLE;
            S_AXI_RID    <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA  <= 32'd0;
            S_AXI_RRESP  <= RESP_OKAY;
            S_AXI_RLAST  <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            rd_addr_r    <= {ADDR_WIDTH{1'b0}};
            rd_len_r     <= 8'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID) begin
                        rd_addr_r    <= S_AXI_ARADDR;
                        rd_len_r     <= S_AXI_ARLEN;
                        S_AXI_RID    <= S_AXI_ARID;
                        S_AXI_RDATA  <= reg_read(S_AXI_ARADDR[5:0]);
                        S_AXI_RRESP  <= RESP_OKAY;
                        S_AXI_RLAST  <= (S_AXI_ARLEN == 8'd0);
                        S_AXI_RVALID <= 1'b1;
                        rd_state     <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    if (S_AXI_RREADY) begin
                        if (S_AXI_RLAST) begin
                            S_AXI_RVALID <= 1'b0;
                            rd_state     <= RD_IDLE;
                        end else begin
                            rd_len_r    <= rd_len_r - 8'd1;
                            rd_addr_r   <= rd_addr_r + 4;
                            S_AXI_RDATA <= reg_read(rd_addr_r[5:0] + 6'd4);
                            S_AXI_RLAST <= (rd_len_r == 8'd1);
                        end
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
