// ============================================================================
// Module  : uart_axi_slave
// Project : RISC-V SoC — UART peripheral
//
// AXI4-Full slave interface cho UART. Xử lý các thanh ghi:
//   0x00  TX_DATA    WO  [7:0]   ghi byte vào TX FIFO
//   0x04  RX_DATA    RO  [7:0]   đọc byte từ RX FIFO
//   0x08  STATUS     RO  [4:0]   tx_full|tx_empty|rx_full|rx_empty|rx_overrun
//   0x0C  CTRL       RW  [1:0]   rx_irq_en|tx_irq_en
//   0x10  BAUD_DIV   RW  [15:0]  baud divisor
//   0x14  IRQ_STATUS RW1C[1:0]   tx_empty_irq|rx_valid_irq (ghi 1 để xóa)
//
// WHY AXI4-Full (không phải Lite):
//   Crossbar của SoC chỉ hỗ trợ AXI4-Full. Tuy UART chỉ cần register access
//   đơn giản, vẫn phải implement đủ AWLEN/ARLEN/WLAST/BID/RID.
//   Tất cả burst đều xử lý như single-beat (AWLEN/ARLEN bị ignore).
//
// AXI4-Full handshake:
//   Write: AW channel → W channel → B channel (response)
//   Read:  AR channel → R channel (response với RID)
// ============================================================================

module uart_axi_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // =========================================================================
    // AXI4-Full Write Address Channel
    // =========================================================================
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    // AXI4-Full Write Data Channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    // AXI4-Full Write Response Channel
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    // =========================================================================
    // AXI4-Full Read Address Channel
    // =========================================================================
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    // AXI4-Full Read Data Channel
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // =========================================================================
    // Register interface → UART datapath
    // =========================================================================
    // TX FIFO
    output wire [7:0]  reg_tx_data,
    output wire        reg_tx_push,   // 1-cycle strobe: ghi byte vào TX FIFO
    input  wire        tx_fifo_full,
    input  wire        tx_fifo_empty,

    // RX FIFO
    input  wire [7:0]  reg_rx_data,
    output wire        reg_rx_pop,    // 1-cycle strobe: pop byte từ RX FIFO
    input  wire        rx_fifo_full,
    input  wire        rx_fifo_empty,
    input  wire        rx_overrun,

    // Config
    output wire [15:0] reg_baud_div,
    output wire        reg_rx_irq_en,
    output wire        reg_tx_irq_en,

    // IRQ
    input  wire        tx_empty_irq_in,  // từ datapath
    input  wire        rx_valid_irq_in,
    output wire        irq_out
);

    // =========================================================================
    // Register bank
    // =========================================================================
    reg [15:0] baud_div_r;
    reg        rx_irq_en_r, tx_irq_en_r;
    reg        tx_irq_r, rx_irq_r;   // IRQ status (sticky, RW1C)

    assign reg_baud_div  = baud_div_r;
    assign reg_rx_irq_en = rx_irq_en_r;
    assign reg_tx_irq_en = tx_irq_en_r;
    assign irq_out       = (tx_irq_r & tx_irq_en_r) | (rx_irq_r & rx_irq_en_r);

    // =========================================================================
    // Write FSM
    // WHY FSM: AXI4 tách kênh AW và W → cần latch awid và awaddr riêng,
    //   sau đó chờ W beat, rồi mới xử lý, cuối cùng trả B response.
    // =========================================================================
    localparam WS_IDLE  = 2'd0;
    localparam WS_DATA  = 2'd1;
    localparam WS_RESP  = 2'd2;

    reg [1:0]            wr_state;
    reg [ID_WIDTH-1:0]   wr_id;
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg                  awready_r, wready_r, bvalid_r;
    reg [ID_WIDTH-1:0]   bid_r;
    reg                  tx_push_r;
    reg [7:0]            tx_data_r;

    assign s_axi_awready = awready_r;
    assign s_axi_wready  = wready_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bid     = bid_r;
    assign s_axi_bresp   = 2'b00;   // OKAY
    assign reg_tx_push   = tx_push_r;
    assign reg_tx_data   = tx_data_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state    <= WS_IDLE;
            wr_id       <= {ID_WIDTH{1'b0}};
            wr_addr     <= {ADDR_WIDTH{1'b0}};
            awready_r   <= 1'b1;
            wready_r    <= 1'b0;
            bvalid_r    <= 1'b0;
            bid_r       <= {ID_WIDTH{1'b0}};
            tx_push_r   <= 1'b0;
            tx_data_r   <= 8'd0;
            baud_div_r  <= 16'd867;   // default 115200 @ 100MHz
            rx_irq_en_r <= 1'b0;
            tx_irq_en_r <= 1'b0;
            tx_irq_r    <= 1'b0;
            rx_irq_r    <= 1'b0;
        end else begin
            tx_push_r <= 1'b0;

            // Sticky IRQ: set khi event xảy ra
            if (tx_empty_irq_in) tx_irq_r <= 1'b1;
            if (rx_valid_irq_in) rx_irq_r <= 1'b1;

            case (wr_state)
                WS_IDLE: begin
                    awready_r <= 1'b1;
                    if (s_axi_awvalid && awready_r) begin
                        wr_id     <= s_axi_awid;
                        wr_addr   <= s_axi_awaddr;
                        awready_r <= 1'b0;
                        wready_r  <= 1'b1;
                        wr_state  <= WS_DATA;
                    end
                end

                WS_DATA: begin
                    if (s_axi_wvalid && wready_r) begin
                        wready_r <= 1'b0;
                        // Decode địa chỉ (offset = addr[7:0])
                        case (wr_addr[7:2])   // word-aligned → dùng [7:2]
                            6'h00: begin  // 0x00 TX_DATA
                                if (!tx_fifo_full) begin
                                    tx_data_r <= s_axi_wdata[7:0];
                                    tx_push_r <= 1'b1;
                                end
                            end
                            6'h03: begin  // 0x0C CTRL
                                tx_irq_en_r <= s_axi_wdata[0];
                                rx_irq_en_r <= s_axi_wdata[1];
                            end
                            6'h04: begin  // 0x10 BAUD_DIV
                                baud_div_r <= s_axi_wdata[15:0];
                            end
                            6'h05: begin  // 0x14 IRQ_STATUS (RW1C: ghi 1 để xóa)
                                if (s_axi_wdata[0]) tx_irq_r <= 1'b0;
                                if (s_axi_wdata[1]) rx_irq_r <= 1'b0;
                            end
                            default: ;  // read-only regs: ignore write
                        endcase
                        bvalid_r <= 1'b1;
                        bid_r    <= wr_id;
                        wr_state <= WS_RESP;
                    end
                end

                WS_RESP: begin
                    if (s_axi_bready && bvalid_r) begin
                        bvalid_r <= 1'b0;
                        wr_state <= WS_IDLE;
                    end
                end

                default: wr_state <= WS_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Read FSM
    // =========================================================================
    localparam RS_IDLE = 1'b0;
    localparam RS_RESP = 1'b1;

    reg             rd_state;
    reg [ID_WIDTH-1:0]   ar_id;
    reg [ADDR_WIDTH-1:0] ar_addr;
    reg             arready_r, rvalid_r;
    reg [DATA_WIDTH-1:0] rdata_r;
    reg [ID_WIDTH-1:0]   rid_r;
    reg             rx_pop_r;

    assign s_axi_arready = arready_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rid     = rid_r;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rlast   = rvalid_r;   // single-beat burst: RLAST = RVALID
    assign reg_rx_pop    = rx_pop_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state  <= RS_IDLE;
            arready_r <= 1'b1;
            rvalid_r  <= 1'b0;
            rdata_r   <= {DATA_WIDTH{1'b0}};
            rid_r     <= {ID_WIDTH{1'b0}};
            rx_pop_r  <= 1'b0;
            ar_id     <= {ID_WIDTH{1'b0}};
            ar_addr   <= {ADDR_WIDTH{1'b0}};
        end else begin
            rx_pop_r <= 1'b0;

            case (rd_state)
                RS_IDLE: begin
                    arready_r <= 1'b1;
                    if (s_axi_arvalid && arready_r) begin
                        ar_id     <= s_axi_arid;
                        ar_addr   <= s_axi_araddr;
                        arready_r <= 1'b0;

                        // Decode và latch read data
                        case (s_axi_araddr[7:2])
                            6'h00: rdata_r <= 32'd0;  // TX_DATA: write-only, return 0
                            6'h01: begin               // 0x04 RX_DATA
                                rdata_r  <= {24'd0, reg_rx_data};
                                rx_pop_r <= !rx_fifo_empty;
                            end
                            6'h02: rdata_r <= {27'd0,  // 0x08 STATUS
                                               rx_overrun,
                                               rx_fifo_full,
                                               rx_fifo_empty,
                                               tx_fifo_full,
                                               tx_fifo_empty};
                            6'h03: rdata_r <= {30'd0, rx_irq_en_r, tx_irq_en_r}; // 0x0C CTRL
                            6'h04: rdata_r <= {16'd0, baud_div_r};                // 0x10 BAUD_DIV
                            6'h05: rdata_r <= {30'd0, rx_irq_r, tx_irq_r};       // 0x14 IRQ_STATUS
                            default: rdata_r <= 32'hDEAD_BEEF;
                        endcase

                        rid_r    <= s_axi_arid;
                        rvalid_r <= 1'b1;
                        rd_state <= RS_RESP;
                    end
                end

                RS_RESP: begin
                    if (s_axi_rready && rvalid_r) begin
                        rvalid_r  <= 1'b0;
                        arready_r <= 1'b1;
                        rd_state  <= RS_IDLE;
                    end
                end

                default: rd_state <= RS_IDLE;
            endcase
        end
    end

endmodule