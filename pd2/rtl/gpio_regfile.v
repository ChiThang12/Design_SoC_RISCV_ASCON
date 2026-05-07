`timescale 1ns/1ps

// ============================================================================
// gpio_regfile.v — GPIO Register File with AXI4-Lite Slave Interface
//
// Address: 0x5001_0000 (S6 in crossbar)
// Register Map (all 32-bit, word-aligned):
//   0x00  DIR       direction (1=output, 0=input per bit)
//   0x04  DOUT      data output register
//   0x08  DIN       data input (read-only, from gpio_iocell din_sync)
//   0x0C  IRQ_EN    interrupt enable per bit
//   0x10  IRQ_STAT  interrupt status (W1C — write 1 to clear)
//   0x14  IRQ_MODE  0=level, 1=edge per bit
//   0x18  IRQ_POL   0=falling/low, 1=rising/high per bit
// ============================================================================

module gpio_regfile #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter GPIO_WIDTH = 32
)(
    input  wire clk,
    input  wire rst_n,

    // AXI4-Lite slave (simplified: no burst, single beat only)
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

    // GPIO register outputs to iocell
    output reg  [GPIO_WIDTH-1:0]    dir_reg,
    output reg  [GPIO_WIDTH-1:0]    dout_reg,
    output reg  [GPIO_WIDTH-1:0]    irq_en,
    output reg  [GPIO_WIDTH-1:0]    irq_mode,
    output reg  [GPIO_WIDTH-1:0]    irq_pol,

    // GPIO register inputs from iocell
    input  wire [GPIO_WIDTH-1:0]    din_sync,
    input  wire [GPIO_WIDTH-1:0]    irq_raw       // edge/level detect from iocell
);

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // Register addresses (byte, relative to S6_BASE)
    localparam REG_DIR      = 7'h00;
    localparam REG_DOUT     = 7'h04;
    localparam REG_DIN      = 7'h08;
    localparam REG_IRQ_EN   = 7'h0C;
    localparam REG_IRQ_STAT = 7'h10;
    localparam REG_IRQ_MODE = 7'h14;
    localparam REG_IRQ_POL  = 7'h18;

    // IRQ status register (W1C)
    reg [GPIO_WIDTH-1:0] irq_stat;

    // Latch IRQ raw into irq_stat (set on edge/level, cleared by W1C write)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_stat <= {GPIO_WIDTH{1'b0}};
        else
            irq_stat <= (irq_stat | (irq_raw & irq_en)) & ~irq_stat_clr;
    end

    reg [GPIO_WIDTH-1:0] irq_stat_clr;

    // =========================================================================
    // Write FSM
    // =========================================================================
    localparam WR_IDLE = 2'b00, WR_DATA = 2'b01, WR_RESP = 2'b10;
    reg [1:0]            wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_r;
    reg [ID_WIDTH-1:0]   bid_r;

    assign S_AXI_AWREADY = (wr_state == WR_IDLE);
    assign S_AXI_WREADY  = (wr_state == WR_DATA);

    function [DATA_WIDTH-1:0] apply_strb;
        input [DATA_WIDTH-1:0]   old_val;
        input [DATA_WIDTH-1:0]   new_val;
        input [DATA_WIDTH/8-1:0] strb;
        integer k;
        begin
            apply_strb = old_val;
            for (k = 0; k < DATA_WIDTH/8; k = k + 1)
                if (strb[k]) apply_strb[k*8 +: 8] = new_val[k*8 +: 8];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state     <= WR_IDLE;
            wr_addr_r    <= {ADDR_WIDTH{1'b0}};
            bid_r        <= {ID_WIDTH{1'b0}};
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP  <= RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
            dir_reg      <= {GPIO_WIDTH{1'b0}};
            dout_reg     <= {GPIO_WIDTH{1'b0}};
            irq_en       <= {GPIO_WIDTH{1'b0}};
            irq_mode     <= {GPIO_WIDTH{1'b0}};
            irq_pol      <= {GPIO_WIDTH{1'b0}};
            irq_stat_clr <= {GPIO_WIDTH{1'b0}};
        end else begin
            irq_stat_clr <= {GPIO_WIDTH{1'b0}};

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
                        case (wr_addr_r[6:0])
                            REG_DIR:      dir_reg  <= apply_strb(dir_reg,  S_AXI_WDATA, S_AXI_WSTRB);
                            REG_DOUT:     dout_reg <= apply_strb(dout_reg, S_AXI_WDATA, S_AXI_WSTRB);
                            REG_IRQ_EN:   irq_en   <= apply_strb(irq_en,   S_AXI_WDATA, S_AXI_WSTRB);
                            REG_IRQ_STAT: irq_stat_clr <= S_AXI_WDATA & S_AXI_WSTRB;  // W1C
                            REG_IRQ_MODE: irq_mode <= apply_strb(irq_mode, S_AXI_WDATA, S_AXI_WSTRB);
                            REG_IRQ_POL:  irq_pol  <= apply_strb(irq_pol,  S_AXI_WDATA, S_AXI_WSTRB);
                            default: ;    // DIN is read-only, writes ignored
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

    assign S_AXI_ARREADY = (rd_state == RD_IDLE);

    reg [ADDR_WIDTH-1:0] rd_addr_r;
    reg [ID_WIDTH-1:0]   rid_r;
    reg [7:0]            rd_len_r;

    function [DATA_WIDTH-1:0] reg_read;
        input [6:0] addr;
        begin
            case (addr)
                REG_DIR:      reg_read = dir_reg;
                REG_DOUT:     reg_read = dout_reg;
                REG_DIN:      reg_read = din_sync;
                REG_IRQ_EN:   reg_read = irq_en;
                REG_IRQ_STAT: reg_read = irq_stat;
                REG_IRQ_MODE: reg_read = irq_mode;
                REG_IRQ_POL:  reg_read = irq_pol;
                default:      reg_read = {DATA_WIDTH{1'b0}};
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state    <= RD_IDLE;
            S_AXI_RID   <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP <= RESP_OKAY;
            S_AXI_RLAST <= 1'b0;
            S_AXI_RVALID<= 1'b0;
            rd_addr_r   <= {ADDR_WIDTH{1'b0}};
            rid_r       <= {ID_WIDTH{1'b0}};
            rd_len_r    <= 8'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID) begin
                        rid_r     <= S_AXI_ARID;
                        rd_addr_r <= S_AXI_ARADDR;
                        rd_len_r  <= S_AXI_ARLEN;
                        S_AXI_RID    <= S_AXI_ARID;
                        S_AXI_RDATA  <= reg_read(S_AXI_ARADDR[6:0]);
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
                            S_AXI_RDATA <= reg_read(rd_addr_r[6:0] + 7'd4);
                            S_AXI_RLAST <= (rd_len_r == 8'd1);
                        end
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
