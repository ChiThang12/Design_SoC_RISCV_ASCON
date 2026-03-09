// ============================================================================
// Module  : axi_read_channel
// Project : ASCON Crypto Accelerator IP
// Parent  : ascon_axi_slave
//
// Description:
//   Handles AXI4-Lite read handshake:
//     - Accepts ARADDR in one cycle (de-asserts ARREADY immediately)
//     - Presents rd_addr + rd_req pulse to reg_bank for data fetch
//     - Registers returned rd_data and drives RVALID/RDATA/RRESP
//     - Holds RVALID until RREADY
//     - RLAST always 1 (AXI4-Lite: single beat)
//     - Echoes ARID back as RID
// ============================================================================

module axi_read_channel #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ── AXI4-Lite Read Address Channel ───────────────────────────────────────
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire                    S_AXI_ARVALID,
    output reg                     S_AXI_ARREADY,

    // ── AXI4-Lite Read Data Channel ──────────────────────────────────────────
    output reg  [ID_WIDTH-1:0]     S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output reg  [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,   // always 1 (Lite)
    output reg                     S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // ── Interface to reg_bank (read side) ────────────────────────────────────
    output wire [11:0]             rd_addr,       // captured ARADDR[11:0]
    output wire                    rd_req,        // 1-cycle pulse: address captured
    input  wire [DATA_WIDTH-1:0]   rd_data        // read data from reg_bank (combinational)
);

    reg [11:0]         rd_addr_lat;
    reg [ID_WIDTH-1:0] rd_id_lat;
    reg                rd_pending;

    assign rd_addr = rd_addr_lat;
    assign rd_req  = rd_pending && !S_AXI_RVALID;
    assign S_AXI_RLAST = 1'b1;

    // -------------------------------------------------------------------------
    // Accept read address
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY <= 1'b1;
            rd_pending    <= 1'b0;
            rd_addr_lat   <= 12'h0;
            rd_id_lat     <= {ID_WIDTH{1'b0}};
        end else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                rd_addr_lat   <= S_AXI_ARADDR[11:0];
                rd_id_lat     <= S_AXI_ARID;
                rd_pending    <= 1'b1;
                S_AXI_ARREADY <= 1'b0;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                rd_pending    <= 1'b0;
                S_AXI_ARREADY <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Drive read response (1-cycle after rd_req)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA  <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP  <= 2'b00;
            S_AXI_RID    <= {ID_WIDTH{1'b0}};
        end else begin
            if (rd_req) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RDATA  <= rd_data;
                S_AXI_RRESP  <= 2'b00; // OKAY
                S_AXI_RID    <= rd_id_lat;
            end else if (S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

endmodule