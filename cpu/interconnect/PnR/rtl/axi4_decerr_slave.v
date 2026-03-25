// ============================================================================
// axi4_decerr_slave.v
// Xử lý giao dịch tới địa chỉ không ánh xạ — trả về DECERR
//
// Read:  Nhận AR → phát R với RDATA=0xDEAD_BEEF, RRESP=DECERR, RLAST=1
// Write: Nhận AW → consume W (drain burst) → phát B với BRESP=DECERR
// ============================================================================

module axi4_decerr_slave #(
    parameter ID_WIDTH   = 4,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,

    // AR channel
    input  wire [ID_WIDTH-1:0]   s_arid,
    input  wire [ADDR_WIDTH-1:0] s_araddr,
    input  wire [7:0]            s_arlen,
    input  wire                  s_arvalid,
    output reg                   s_arready,

    // R channel
    output reg  [ID_WIDTH-1:0]   s_rid,
    output reg  [DATA_WIDTH-1:0] s_rdata,
    output reg  [1:0]            s_rresp,
    output reg                   s_rlast,
    output reg                   s_rvalid,
    input  wire                  s_rready,

    // AW channel
    input  wire [ID_WIDTH-1:0]   s_awid,
    input  wire [ADDR_WIDTH-1:0] s_awaddr,
    input  wire [7:0]            s_awlen,
    input  wire                  s_awvalid,
    output reg                   s_awready,

    // W channel
    input  wire                  s_wlast,
    input  wire                  s_wvalid,
    output reg                   s_wready,

    // B channel
    output reg  [ID_WIDTH-1:0]   s_bid,
    output reg  [1:0]            s_bresp,
    output reg                   s_bvalid,
    input  wire                  s_bready
);

    // ========================================================================
    // Read FSM
    // ========================================================================
    localparam [1:0] RS_IDLE = 2'd0,
                     RS_RESP = 2'd1,
                     RS_WAIT = 2'd2;

    reg [1:0]          rs_state;
    reg [ID_WIDTH-1:0] r_pending_id;
    reg [7:0]          r_beat_cnt;
    reg [7:0]          r_len_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs_state     <= RS_IDLE;
            s_arready    <= 1'b1;
            s_rvalid     <= 1'b0;
            s_rdata      <= 32'hDEAD_BEEF;
            s_rresp      <= 2'b11;
            s_rlast      <= 1'b0;
            s_rid        <= {ID_WIDTH{1'b0}};
            r_beat_cnt   <= 8'h0;
            r_len_latch  <= 8'h0;
            r_pending_id <= {ID_WIDTH{1'b0}};
        end else begin
            case (rs_state)
                RS_IDLE: begin
                    s_arready <= 1'b1;
                    s_rvalid  <= 1'b0;
                    if (s_arvalid && s_arready) begin
                        r_pending_id <= s_arid;
                        r_len_latch  <= s_arlen;
                        r_beat_cnt   <= 8'h0;
                        s_arready    <= 1'b0;
                        rs_state     <= RS_RESP;
                    end
                end

                RS_RESP: begin
                    s_rid    <= r_pending_id;
                    s_rdata  <= 32'hDEAD_BEEF;
                    s_rresp  <= 2'b11; // DECERR
                    s_rlast  <= (r_beat_cnt == r_len_latch);
                    s_rvalid <= 1'b1;
                    rs_state <= RS_WAIT;
                end

                RS_WAIT: begin
                    if (s_rvalid && s_rready) begin
                        if (s_rlast) begin
                            s_rvalid  <= 1'b0;
                            s_rlast   <= 1'b0;
                            s_arready <= 1'b1;
                            rs_state  <= RS_IDLE;
                        end else begin
                            r_beat_cnt <= r_beat_cnt + 1'b1;
                            s_rlast    <= (r_beat_cnt + 1'b1 == r_len_latch);
                            rs_state   <= RS_RESP;
                        end
                    end
                end

                default: rs_state <= RS_IDLE;
            endcase
        end
    end

    // ========================================================================
    // Write FSM
    // ========================================================================
    localparam [1:0] WS_IDLE  = 2'd0,
                     WS_DRAIN = 2'd1,
                     WS_RESP  = 2'd2;

    reg [1:0]          ws_state;
    reg [ID_WIDTH-1:0] w_pending_id;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ws_state     <= WS_IDLE;
            s_awready    <= 1'b1;
            s_wready     <= 1'b0;
            s_bvalid     <= 1'b0;
            s_bresp      <= 2'b11;
            s_bid        <= {ID_WIDTH{1'b0}};
            w_pending_id <= {ID_WIDTH{1'b0}};
        end else begin
            case (ws_state)
                WS_IDLE: begin
                    s_awready <= 1'b1;
                    s_wready  <= 1'b0;
                    s_bvalid  <= 1'b0;
                    if (s_awvalid && s_awready) begin
                        w_pending_id <= s_awid;
                        s_awready    <= 1'b0;
                        s_wready     <= 1'b1;
                        ws_state     <= WS_DRAIN;
                    end
                end

                WS_DRAIN: begin
                    // Consume toàn bộ burst, bỏ dữ liệu
                    if (s_wvalid && s_wready && s_wlast) begin
                        s_wready <= 1'b0;
                        s_bid    <= w_pending_id;
                        s_bresp  <= 2'b11; // DECERR
                        s_bvalid <= 1'b1;
                        ws_state <= WS_RESP;
                    end
                end

                WS_RESP: begin
                    if (s_bvalid && s_bready) begin
                        s_bvalid  <= 1'b0;
                        s_awready <= 1'b1;
                        ws_state  <= WS_IDLE;
                    end
                end

                default: ws_state <= WS_IDLE;
            endcase
        end
    end

endmodule