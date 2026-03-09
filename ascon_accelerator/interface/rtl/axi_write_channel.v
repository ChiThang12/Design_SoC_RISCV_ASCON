// ============================================================================
// Module  : axi_write_channel
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_axi_slave
//
// Description:
//   Handles AXI4-Lite write handshake:
//     - Accepts AWADDR and WDATA independently (they may arrive in any order)
//     - Fires a 1-cycle 'do_write' pulse when both are latched
//     - Returns BVALID/BRESP after write completes
//     - Echoes AWID back as BID
//
// Handshake rules:
//   AWREADY de-asserts after accepting one address, re-asserts after do_write
//   WREADY  de-asserts after accepting one data,    re-asserts after do_write
//   BVALID  held until BREADY = 1
// ============================================================================

module axi_write_channel #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                      clk,
    input  wire                      rst_n,

    // ── AXI4-Lite Write Address Channel ──────────────────────────────────────
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire                      S_AXI_AWVALID,
    output reg                       S_AXI_AWREADY,

    // ── AXI4-Lite Write Data Channel ─────────────────────────────────────────
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output reg                       S_AXI_WREADY,

    // ── AXI4-Lite Write Response Channel ─────────────────────────────────────
    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output reg  [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // ── Decoded write output (to reg_bank) ───────────────────────────────────
    output wire [11:0]               wr_addr,     // captured AWADDR[11:0]
    output wire [DATA_WIDTH-1:0]     wr_data,     // captured WDATA
    output wire [DATA_WIDTH/8-1:0]   wr_strb,     // captured WSTRB
    output wire                      do_write     // 1-cycle pulse: fire register write
);

    // -------------------------------------------------------------------------
    // Internal latches
    // -------------------------------------------------------------------------
    reg [11:0]         wr_addr_lat;
    reg [ID_WIDTH-1:0] wr_id_lat;
    reg                wr_addr_valid;

    reg [DATA_WIDTH-1:0]   wr_data_lat;
    reg [DATA_WIDTH/8-1:0] wr_strb_lat;
    reg                    wr_data_valid;

    // Fire when both address and data are latched, and response channel is free
    assign do_write = wr_addr_valid && wr_data_valid &&
                      (!S_AXI_BVALID || S_AXI_BREADY);

    assign wr_addr = wr_addr_lat;
    assign wr_data = wr_data_lat;
    assign wr_strb = wr_strb_lat;

    // -------------------------------------------------------------------------
    // Accept write address
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY <= 1'b1;
            wr_addr_valid <= 1'b0;
            wr_addr_lat   <= 12'h0;
            wr_id_lat     <= {ID_WIDTH{1'b0}};
        end else begin
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                wr_addr_lat   <= S_AXI_AWADDR[11:0];
                wr_id_lat     <= S_AXI_AWID;
                wr_addr_valid <= 1'b1;
                S_AXI_AWREADY <= 1'b0;
            end else if (do_write) begin
                wr_addr_valid <= 1'b0;
                S_AXI_AWREADY <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Accept write data
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_WREADY  <= 1'b1;
            wr_data_valid <= 1'b0;
            wr_data_lat   <= {DATA_WIDTH{1'b0}};
            wr_strb_lat   <= {(DATA_WIDTH/8){1'b0}};
        end else begin
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                wr_data_lat   <= S_AXI_WDATA;
                wr_strb_lat   <= S_AXI_WSTRB;
                wr_data_valid <= 1'b1;
                S_AXI_WREADY  <= 1'b0;
            end else if (do_write) begin
                wr_data_valid <= 1'b0;
                S_AXI_WREADY  <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Write response
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BVALID <= 1'b0;
            S_AXI_BRESP  <= 2'b00;
            S_AXI_BID    <= {ID_WIDTH{1'b0}};
        end else begin
            if (do_write) begin
                S_AXI_BVALID <= 1'b1;
                S_AXI_BRESP  <= 2'b00; // OKAY
                S_AXI_BID    <= wr_id_lat;
            end else if (S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

endmodule