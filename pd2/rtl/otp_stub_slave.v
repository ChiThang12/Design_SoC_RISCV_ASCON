`timescale 1ns/1ps

// ============================================================================
// otp_stub_slave.v — Minimal OTP stub (S10 @ 0x6000_0000)
//
// Trả về fixed read-only data thay vì DECERR:
//   0x000  DEVICE_ID  = 32'hA5C0_CAFE  (chip identity)
//   0x004  OTP_VER    = 32'h0000_0001  (OTP layout version)
//   other  = 32'hDEAD_BEEF             (unprogrammed / reserved)
//
// Writes: always OKAY (ignored) — OTP is physically write-once;
// stub accepts writes silently to avoid spurious SLVERR.
// ============================================================================

module otp_stub_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // AXI4-Full slave (same port naming as other slaves in this SoC)
    input  wire [ID_WIDTH-1:0]    s_arid,
    input  wire [ADDR_WIDTH-1:0]  s_araddr,
    input  wire [7:0]             s_arlen,
    input  wire [2:0]             s_arsize,
    input  wire [1:0]             s_arburst,
    input  wire                   s_arvalid,
    output wire                   s_arready,

    output wire [ID_WIDTH-1:0]    s_rid,
    output wire [DATA_WIDTH-1:0]  s_rdata,
    output wire [1:0]             s_rresp,
    output wire                   s_rlast,
    output wire                   s_rvalid,
    input  wire                   s_rready,

    input  wire [ID_WIDTH-1:0]    s_awid,
    input  wire [ADDR_WIDTH-1:0]  s_awaddr,
    input  wire [7:0]             s_awlen,
    input  wire                   s_awvalid,
    output wire                   s_awready,

    input  wire [DATA_WIDTH-1:0]  s_wdata,
    input  wire [3:0]             s_wstrb,
    input  wire                   s_wlast,
    input  wire                   s_wvalid,
    output wire                   s_wready,

    output wire [ID_WIDTH-1:0]    s_bid,
    output wire [1:0]             s_bresp,
    output wire                   s_bvalid,
    input  wire                   s_bready
);

// ── Read channel ─────────────────────────────────────────────────────────────
reg [ID_WIDTH-1:0]   ar_id_r;
reg [ADDR_WIDTH-1:0] ar_addr_r;
reg [7:0]            ar_len_r;
reg [7:0]            ar_beat_r;   // beats remaining in burst
reg                  ar_active;

reg                  rvalid_r;
reg [DATA_WIDTH-1:0] rdata_r;
reg                  rlast_r;

wire [11:0] rd_offset = ar_addr_r[11:0] + {ar_beat_r, 2'b00}; // word-addressed

// OTP read data mux
wire [DATA_WIDTH-1:0] otp_rdata =
    (rd_offset == 12'h000) ? 32'hA5C0_CAFE :   // DEVICE_ID
    (rd_offset == 12'h004) ? 32'h0000_0001 :   // OTP_VER
                              32'hDEAD_BEEF;    // unprogrammed

assign s_arready = !ar_active;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ar_active  <= 1'b0;
        ar_id_r    <= {ID_WIDTH{1'b0}};
        ar_addr_r  <= {ADDR_WIDTH{1'b0}};
        ar_len_r   <= 8'd0;
        ar_beat_r  <= 8'd0;
        rvalid_r   <= 1'b0;
        rdata_r    <= {DATA_WIDTH{1'b0}};
        rlast_r    <= 1'b0;
    end else begin
        if (s_arvalid && s_arready) begin
            ar_id_r   <= s_arid;
            ar_addr_r <= s_araddr;
            ar_len_r  <= s_arlen;
            ar_beat_r <= 8'd0;
            ar_active <= 1'b1;
        end

        if (ar_active && !rvalid_r) begin
            rvalid_r <= 1'b1;
            rdata_r  <= otp_rdata;
            rlast_r  <= (ar_beat_r == ar_len_r);
        end

        if (rvalid_r && s_rready) begin
            rvalid_r <= 1'b0;
            if (!rlast_r) begin
                ar_beat_r <= ar_beat_r + 8'd1;
            end else begin
                ar_active <= 1'b0;
            end
        end
    end
end

assign s_rid    = ar_id_r;
assign s_rdata  = rdata_r;
assign s_rresp  = 2'b00;   // OKAY
assign s_rlast  = rlast_r;
assign s_rvalid = rvalid_r;

// ── Write channel (accept & ignore) ─────────────────────────────────────────
reg aw_active;
reg w_active;
reg bvalid_r;
reg [ID_WIDTH-1:0] aw_id_r;

assign s_awready = !aw_active;
assign s_wready  = aw_active && !bvalid_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        aw_active <= 1'b0;
        w_active  <= 1'b0;
        bvalid_r  <= 1'b0;
        aw_id_r   <= {ID_WIDTH{1'b0}};
    end else begin
        if (s_awvalid && s_awready) begin
            aw_id_r   <= s_awid;
            aw_active <= 1'b1;
        end
        if (s_wvalid && s_wready && s_wlast) begin
            bvalid_r <= 1'b1;
        end
        if (bvalid_r && s_bready) begin
            bvalid_r  <= 1'b0;
            aw_active <= 1'b0;
        end
    end
end

assign s_bid    = aw_id_r;
assign s_bresp  = 2'b00;   // OKAY (silent accept)
assign s_bvalid = bvalid_r;

endmodule
// ============================================================================
// END: otp_stub_slave.v
// ============================================================================
