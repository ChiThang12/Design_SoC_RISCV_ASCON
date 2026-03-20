`include "cache_interface/dcache/dcache_defines.vh"

// ============================================================================
// Module: dcache_axi_interface  —  Write-Back version
// Thêm AXI4 ID signals để kết nối vào axi4_crossbar (M1)
//
// FIX-BUG2: refill_addr bị latch sai cycle trong RD_IDLE
//   Controller set refill_addr và refill_start bằng nonblocking (<=) nên
//   giá trị chỉ có hiệu lực ở cuối cycle đó. RD_IDLE chạy cùng posedge
//   sẽ thấy giá trị CŨ.
//   FIX: Thêm state RD_LATCH — 1-cycle buffer, đọc refill_addr ở cycle sau.
//
// FIX-BUG-TIMING: refill_data_valid, refill_done, refill_data, refill_word
//   Nếu là reg (nonblocking <=), chúng có hiệu lực 1 cycle SAU beat.
//   Controller nhận trễ → DRAIN xong muộn → TC01/TC10/TC11 fail/timeout.
//
//   FIX: Đổi tất cả thành COMBINATIONAL (wire):
//     refill_data_valid = (rd_state==RD_R) && RVALID && RREADY
//     refill_done       = refill_data_valid && RLAST
//     refill_data       = refill_data_valid ? M_AXI_RDATA     : refill_data_r
//     refill_word       = refill_data_valid ? rd_word_counter : refill_word_r
//
//   refill_data_r / refill_word_r là internal reg để giữ giá trị ổn định
//   khi valid=0. rd_word_counter tăng SAU khi beat được nhận → giá trị
//   live trong cycle hiện tại luôn = index đúng của beat đang đến.
// ============================================================================
module dcache_axi_interface #(
    parameter ID_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Read Refill Interface
    // ========================================================================
    input wire [31:0]  refill_addr,
    input wire         refill_start,
    input wire         refill_nc,       // [NC-BYPASS] 1 = single-beat (ARLEN=0)
    output reg         refill_busy,
    output wire        refill_done,        // combinational: valid && RLAST
    output wire [31:0] refill_data,        // combinational MUX
    output wire [1:0]  refill_word,        // combinational MUX
    output wire        refill_data_valid,  // combinational: RD_R && RVALID && RREADY

    // ========================================================================
    // Eviction Interface
    // ========================================================================
    input wire [31:0]  evict_addr,
    input wire [31:0]  evict_data_0,
    input wire [31:0]  evict_data_1,
    input wire [31:0]  evict_data_2,
    input wire [31:0]  evict_data_3,
    input wire         evict_start,
    input wire         evict_nc,        // [NC-BYPASS] 1 = single-beat (AWLEN=0)
    input wire [3:0]   evict_wstrb_nc,  // [NC-BYPASS] byte strobe cho NC write
    output reg         evict_busy,
    output reg         evict_done,

    // ========================================================================
    // AXI4 Read Channel
    // ========================================================================
    output wire [ID_WIDTH-1:0] M_AXI_ARID,
    output reg  [31:0]         M_AXI_ARADDR,
    output wire [7:0]          M_AXI_ARLEN,
    output wire [2:0]          M_AXI_ARSIZE,
    output wire [1:0]          M_AXI_ARBURST,
    output wire [2:0]          M_AXI_ARPROT,
    output reg                 M_AXI_ARVALID,
    input  wire                M_AXI_ARREADY,

    input  wire [ID_WIDTH-1:0] M_AXI_RID,
    input  wire [31:0]         M_AXI_RDATA,
    input  wire [1:0]          M_AXI_RRESP,
    input  wire                M_AXI_RLAST,
    input  wire                M_AXI_RVALID,
    output reg                 M_AXI_RREADY,

    // ========================================================================
    // AXI4 Write Channel
    // ========================================================================
    output wire [ID_WIDTH-1:0] M_AXI_AWID,
    output reg  [31:0]         M_AXI_AWADDR,
    output wire [7:0]          M_AXI_AWLEN,
    output wire [2:0]          M_AXI_AWSIZE,
    output wire [1:0]          M_AXI_AWBURST,
    output wire [2:0]          M_AXI_AWPROT,
    output reg                 M_AXI_AWVALID,
    input  wire                M_AXI_AWREADY,

    output reg  [31:0]         M_AXI_WDATA,
    output reg  [3:0]          M_AXI_WSTRB,
    output reg                 M_AXI_WLAST,
    output reg                 M_AXI_WVALID,
    input  wire                M_AXI_WREADY,

    input  wire [ID_WIDTH-1:0] M_AXI_BID,
    input  wire [1:0]          M_AXI_BRESP,
    input  wire                M_AXI_BVALID,
    output reg                 M_AXI_BREADY
);

    // ========================================================================
    // AXI constant signals
    // ========================================================================
    assign M_AXI_ARID    = {ID_WIDTH{1'b0}};
    assign M_AXI_AWID    = {ID_WIDTH{1'b0}};

    // [NC-BYPASS] ARLEN/AWLEN: bình thường = 3 (4-beat cache refill/evict)
    // Khi NC bypass được kích hoạt: = 0 (1-beat single transaction)
    // nc_beat_mode được set bởi controller thông qua refill_nc / evict_nc flags.
    // Giải pháp đơn giản: controller set refill_addr[0]=1 để báo NC mode
    // → NHƯNG điều này sẽ làm địa chỉ sai.
    //
    // Giải pháp đúng: thêm port nc_read / nc_write vào axi_interface.
    // Controller set các port này khi kick NC transaction.
    assign M_AXI_ARLEN   = rd_burst_len;
    assign M_AXI_ARSIZE  = 3'b010;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_AWLEN   = ev_burst_len;
    assign M_AXI_AWSIZE  = 3'b010;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWPROT  = 3'b000;

    // ========================================================================
    // [NC-BYPASS] Burst length registers
    // Normal cache: ARLEN=3 (4-beat), NC bypass: ARLEN=0 (1-beat)
    // ========================================================================
    reg [7:0] rd_burst_len;
    reg [7:0] ev_burst_len;
    reg       rd_nc_mode;    // latch NC mode khi bắt đầu transaction
    reg       ev_nc_mode;

    // ========================================================================
    // Read Refill FSM
    // ========================================================================
    localparam [2:0]
        RD_IDLE  = 3'b000,
        RD_LATCH = 3'b001,
        RD_AR    = 3'b010,
        RD_R     = 3'b011;

    reg [2:0] rd_state;
    reg [1:0] rd_word_counter;

    // Internal latched regs (hold last beat value, used when valid=0)
    reg [31:0] refill_data_r;
    reg [1:0]  refill_word_r;

    // ── Combinational output assignments ─────────────────────────────────────
    // Assert in the SAME cycle as the AXI beat — no pipeline delay.
    assign refill_data_valid = (rd_state == RD_R) && M_AXI_RVALID && M_AXI_RREADY;
    assign refill_done       = refill_data_valid && M_AXI_RLAST;

    // When a beat is arriving: expose LIVE values directly from AXI bus.
    // When idle: expose last latched values (stable, unused by controller).
    assign refill_data = refill_data_valid ? M_AXI_RDATA     : refill_data_r;
    assign refill_word = refill_data_valid ? rd_word_counter : refill_word_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            refill_busy     <= 1'b0;
            refill_data_r   <= 32'h0;
            refill_word_r   <= 2'b00;
            rd_word_counter <= 2'b00;
            M_AXI_ARADDR    <= 32'h0;
            M_AXI_ARVALID   <= 1'b0;
            M_AXI_RREADY    <= 1'b0;
            rd_burst_len    <= 8'd3;
            rd_nc_mode      <= 1'b0;
        end else begin
            case (rd_state)

                // ── RD_IDLE ──────────────────────────────────────────────────
                RD_IDLE: begin
                    refill_busy     <= 1'b0;
                    M_AXI_ARVALID   <= 1'b0;
                    M_AXI_RREADY    <= 1'b0;
                    rd_word_counter <= 2'b00;

                    if (refill_start) begin
                        refill_busy  <= 1'b1;
                        rd_burst_len <= refill_nc ? 8'd0 : 8'd3;
                        rd_nc_mode   <= refill_nc;
                        rd_state     <= RD_LATCH;
                    end
                end

                // ── RD_LATCH: 1-cycle buffer, refill_addr đã stable ──────────
                RD_LATCH: begin
                    M_AXI_ARADDR  <= refill_addr;
                    M_AXI_ARVALID <= 1'b1;
                    rd_state      <= RD_AR;
                end

                // ── RD_AR: chờ ARREADY ───────────────────────────────────────
                RD_AR: begin
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;
                        rd_state      <= RD_R;
                    end
                end

                // ── RD_R: nhận burst (4 beats bình thường, 1 beat NC mode) ──
                // refill_data_valid/done/data/word là COMBO → controller thấy
                // ngay trong cycle RVALID. Chỉ cần latch vào _r để giữ giá trị
                // ổn định sau khi RVALID về 0.
                // rd_word_counter tăng AFTER latch → combo output đọc giá trị
                // TRƯỚC khi tăng = đúng index của beat đang đến.
                RD_R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        refill_data_r <= M_AXI_RDATA;
                        refill_word_r <= rd_word_counter;

                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY    <= 1'b0;
                            refill_busy     <= 1'b0;
                            rd_word_counter <= 2'b00;
                            rd_nc_mode      <= 1'b0;
                            rd_state        <= RD_IDLE;
                        end else begin
                            // NC mode không nên có non-LAST beats, nhưng nếu
                            // slave gửi thêm thì bỏ qua (defensive)
                            rd_word_counter <= rd_word_counter + 1'b1;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // ========================================================================
    // Eviction Write State Machine
    // ========================================================================
    localparam [1:0]
        EV_IDLE = 2'b00,
        EV_AW   = 2'b01,
        EV_W    = 2'b10,
        EV_B    = 2'b11;

    reg [1:0]  ev_state;
    reg [1:0]  ev_beat;
    reg        ev_aw_done;
    reg [31:0] ev_d0, ev_d1, ev_d2, ev_d3;

    function [31:0] ev_word;
        input [1:0] beat;
        begin
            case (beat)
                2'd0: ev_word = ev_d0;
                2'd1: ev_word = ev_d1;
                2'd2: ev_word = ev_d2;
                2'd3: ev_word = ev_d3;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ev_state      <= EV_IDLE;
            evict_busy    <= 1'b0;
            evict_done    <= 1'b0;
            ev_beat       <= 2'b00;
            ev_aw_done    <= 1'b0;
            M_AXI_AWADDR  <= 32'h0;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_WDATA   <= 32'h0;
            M_AXI_WSTRB   <= 4'hf;
            M_AXI_WLAST   <= 1'b0;
            M_AXI_WVALID  <= 1'b0;
            M_AXI_BREADY  <= 1'b0;
            ev_d0 <= 32'h0; ev_d1 <= 32'h0;
            ev_d2 <= 32'h0; ev_d3 <= 32'h0;
            ev_burst_len  <= 8'd3;
            ev_nc_mode    <= 1'b0;
        end else begin
            evict_done <= 1'b0;

            case (ev_state)

                // ── EV_IDLE: latch request, assert AW only ────────────────────
                // KHÔNG assert WVALID ở đây. Nếu AWREADY=1 ngay lập tức,
                // beat 0 sẽ bị consumed trong EV_AW trước khi ev_beat được đếm.
                EV_IDLE: begin
                    evict_busy    <= 1'b0;
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_WLAST   <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    ev_beat       <= 2'b00;
                    ev_aw_done    <= 1'b0;

                    if (evict_start) begin
                        M_AXI_AWADDR  <= evict_addr;
                        ev_d0         <= evict_data_0;
                        ev_d1         <= evict_data_1;
                        ev_d2         <= evict_data_2;
                        ev_d3         <= evict_data_3;
                        ev_burst_len  <= evict_nc ? 8'd0 : 8'd3;
                        ev_nc_mode    <= evict_nc;
                        M_AXI_AWVALID <= 1'b1;
                        evict_busy    <= 1'b1;
                        ev_state      <= EV_AW;
                    end
                end

                // ── EV_AW: chờ AWREADY, rồi bắt đầu write data ──────────────
                EV_AW: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        // Bắt đầu burst: gửi beat 0
                        M_AXI_WVALID  <= 1'b1;
                        M_AXI_WDATA   <= ev_d0;
                        M_AXI_WSTRB   <= ev_nc_mode ? evict_wstrb_nc : 4'hf;
                        M_AXI_WLAST   <= ev_nc_mode ? 1'b1 : 1'b0;
                        ev_beat       <= 2'b00;
                        ev_state      <= EV_W;
                    end
                end

                // ── EV_W: gửi toàn bộ write data burst (beat 0..3) ───────────
                EV_W: begin
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        if (ev_nc_mode || ev_beat == 2'd3) begin
                            // Beat cuối accepted → kết thúc
                            M_AXI_WVALID <= 1'b0;
                            M_AXI_WLAST  <= 1'b0;
                            M_AXI_BREADY <= 1'b1;
                            ev_state     <= EV_B;
                        end else begin
                            // Gửi beat tiếp theo
                            ev_beat     <= ev_beat + 1'b1;
                            M_AXI_WDATA <= ev_word(ev_beat + 1'b1);
                            // WLAST=1 khi đang ở beat 2 (beat kế = 3 = last)
                            M_AXI_WLAST <= (ev_beat == 2'd2) ? 1'b1 : 1'b0;
                        end
                    end
                end

                // ── EV_B: chờ write response ──────────────────────────────────
                EV_B: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BREADY <= 1'b0;
                        evict_done   <= 1'b1;
                        evict_busy   <= 1'b0;
                        ev_state     <= EV_IDLE;
                    end
                end

                default: ev_state <= EV_IDLE;
            endcase
        end
    end

endmodule