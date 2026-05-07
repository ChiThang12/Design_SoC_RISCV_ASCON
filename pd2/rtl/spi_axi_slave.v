`timescale 1ns/1ps
// spi_axi_slave.v — AXI4-Full register slave cho SPI peripheral
//
// Register map (offset từ 0x5002_0000):
//   0x00  TX_DATA    WO [7:0]   ghi byte vào TX FIFO
//   0x04  RX_DATA    RO [7:0]   đọc byte từ RX FIFO
//   0x08  STATUS     RO [5:0]   {rx_overrun,rx_full,rx_empty,tx_full,tx_empty,busy}
//   0x0C  CTRL       RW [7:0]   {spi_en,cs_auto,cpol,cpha,--,--,rx_irq_en,tx_irq_en}
//   0x10  DIVIDER    RW [15:0]  SCK = clk/(2*(DIVIDER+1))
//   0x14  IRQ_STATUS RW1C [1:0] {rx_valid_irq, tx_empty_irq}
//   0x18  CS_CTRL    RW [3:0]   CS manual control (khi cs_auto=0)

module spi_axi_slave #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32,
    parameter AXI_ID_WIDTH   = 4
)(
    input  wire clk,
    input  wire rst_n,

    // AXI4-Full Slave
    input  wire [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]                s_axi_awlen,
    input  wire [2:0]                s_axi_awsize,
    input  wire [1:0]                s_axi_awburst,
    input  wire                      s_axi_awvalid,
    output reg                       s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                      s_axi_wlast,
    input  wire                      s_axi_wvalid,
    output reg                       s_axi_wready,
    output reg  [AXI_ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]                s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,
    input  wire [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]                s_axi_arlen,
    input  wire [2:0]                s_axi_arsize,
    input  wire [1:0]                s_axi_arburst,
    input  wire                      s_axi_arvalid,
    output reg                       s_axi_arready,
    output reg  [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output reg  [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]                s_axi_rresp,
    output reg                       s_axi_rlast,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready,

    // → spi_core & spi_top
    output reg  [7:0]  reg_tx_data,
    output reg         reg_tx_push,    // 1-cycle pulse
    input  wire        tx_fifo_full,
    input  wire        tx_fifo_empty,

    input  wire [7:0]  reg_rx_data,
    output reg         reg_rx_pop,     // 1-cycle pulse
    input  wire        rx_fifo_full,
    input  wire        rx_fifo_empty,
    input  wire        rx_overrun,
    input  wire        spi_busy,

    output reg  [15:0] reg_divider,
    output reg         reg_spi_en,
    output reg         reg_cs_auto,
    output reg         reg_cpol,
    output reg         reg_cpha,
    output reg         reg_rx_irq_en,
    output reg         reg_tx_irq_en,
    output reg  [3:0]  reg_cs_ctrl,

    input  wire        tx_empty_irq_in,
    input  wire        rx_valid_irq_in,
    output wire        irq_out
);

    // ── Write FSM ─────────────────────────────────────────────────────────────
    localparam WS_IDLE = 2'd0, WS_DATA = 2'd1, WS_RESP = 2'd2;
    reg [1:0]               ws;
    reg [AXI_ID_WIDTH-1:0]  wr_id;
    reg [4:0]               wr_addr_lat;  // [4:2] = register select

    // ── Read FSM ──────────────────────────────────────────────────────────────
    localparam RS_IDLE = 1'd0, RS_RESP = 1'd1;
    reg                     rs;
    reg [AXI_ID_WIDTH-1:0]  rd_id;

    // ── IRQ sticky flags ──────────────────────────────────────────────────────
    reg tx_irq_r, rx_irq_r;
    assign irq_out = (reg_tx_irq_en & tx_irq_r) | (reg_rx_irq_en & rx_irq_r);

    // ── Default register values ───────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_divider   <= 16'd4;    // SCK = clk/10 = 10 MHz @ 100 MHz
            reg_spi_en    <= 1'b0;
            reg_cs_auto   <= 1'b1;
            reg_cpol      <= 1'b0;
            reg_cpha      <= 1'b0;
            reg_rx_irq_en <= 1'b0;
            reg_tx_irq_en <= 1'b0;
            reg_cs_ctrl   <= 4'hF;     // CS deasserted (active-low)
            tx_irq_r      <= 1'b0;
            rx_irq_r      <= 1'b0;
        end else begin
            // Edge-detect IRQ set
            if (tx_empty_irq_in) tx_irq_r <= 1'b1;
            if (rx_valid_irq_in) rx_irq_r <= 1'b1;
        end
    end

    // ── Write FSM ─────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws           <= WS_IDLE;
            s_axi_awready<= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
            s_axi_bid    <= {AXI_ID_WIDTH{1'b0}};
            wr_id        <= {AXI_ID_WIDTH{1'b0}};
            wr_addr_lat  <= 5'd0;
            reg_tx_data  <= 8'd0;
            reg_tx_push  <= 1'b0;
        end else begin
            reg_tx_push <= 1'b0;  // default pulse-clear

            case (ws)
                WS_IDLE: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id       <= s_axi_awid;
                        wr_addr_lat <= s_axi_awaddr[4:0];
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        ws <= WS_DATA;
                    end
                end
                WS_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready <= 1'b0;
                        case (wr_addr_lat[4:2])
                            3'd0: begin  // 0x00 TX_DATA
                                if (!tx_fifo_full) begin
                                    reg_tx_data <= s_axi_wdata[7:0];
                                    reg_tx_push <= 1'b1;
                                end
                            end
                            3'd3: begin  // 0x0C CTRL
                                reg_spi_en    <= s_axi_wdata[7];
                                reg_cs_auto   <= s_axi_wdata[6];
                                reg_cpol      <= s_axi_wdata[5];
                                reg_cpha      <= s_axi_wdata[4];
                                reg_rx_irq_en <= s_axi_wdata[1];
                                reg_tx_irq_en <= s_axi_wdata[0];
                            end
                            3'd4: begin  // 0x10 DIVIDER
                                reg_divider <= s_axi_wdata[15:0];
                            end
                            3'd5: begin  // 0x14 IRQ_STATUS RW1C
                                if (s_axi_wdata[0]) tx_irq_r <= 1'b0;
                                if (s_axi_wdata[1]) rx_irq_r <= 1'b0;
                            end
                            3'd6: begin  // 0x18 CS_CTRL
                                reg_cs_ctrl <= s_axi_wdata[3:0];
                            end
                            default: ;
                        endcase
                        s_axi_bid    <= wr_id;
                        s_axi_bresp  <= 2'b00;
                        s_axi_bvalid <= 1'b1;
                        ws <= WS_RESP;
                    end
                end
                WS_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        ws <= WS_IDLE;
                    end
                end
                default: ws <= WS_IDLE;
            endcase
        end
    end

    // ── Read FSM ──────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs            <= RS_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rid     <= {AXI_ID_WIDTH{1'b0}};
            s_axi_rdata   <= {AXI_DATA_WIDTH{1'b0}};
            rd_id         <= {AXI_ID_WIDTH{1'b0}};
            reg_rx_pop    <= 1'b0;
        end else begin
            reg_rx_pop <= 1'b0;

            case (rs)
                RS_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id         <= s_axi_arid;
                        s_axi_arready <= 1'b0;
                        s_axi_rid     <= s_axi_arid;
                        s_axi_rresp   <= 2'b00;
                        s_axi_rlast   <= 1'b1;
                        case (s_axi_araddr[4:2])
                            3'd0: s_axi_rdata <= {24'd0, reg_tx_data};  // TX_DATA (last written)
                            3'd1: begin  // 0x04 RX_DATA
                                s_axi_rdata <= {24'd0, reg_rx_data};
                                if (!rx_fifo_empty) reg_rx_pop <= 1'b1;
                            end
                            3'd2: s_axi_rdata <= {26'd0, rx_overrun, rx_fifo_full,
                                                  rx_fifo_empty, tx_fifo_full,
                                                  tx_fifo_empty, spi_busy};
                            3'd3: s_axi_rdata <= {24'd0, reg_spi_en, reg_cs_auto,
                                                  reg_cpol, reg_cpha, 2'b00,
                                                  reg_rx_irq_en, reg_tx_irq_en};
                            3'd4: s_axi_rdata <= {16'd0, reg_divider};
                            3'd5: s_axi_rdata <= {30'd0, rx_irq_r, tx_irq_r};
                            3'd6: s_axi_rdata <= {28'd0, reg_cs_ctrl};
                            default: s_axi_rdata <= 32'hDEAD_BEEF;
                        endcase
                        s_axi_rvalid <= 1'b1;
                        rs <= RS_RESP;
                    end
                end
                RS_RESP: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rs <= RS_IDLE;
                    end
                end
                default: rs <= RS_IDLE;
            endcase
        end
    end

endmodule
