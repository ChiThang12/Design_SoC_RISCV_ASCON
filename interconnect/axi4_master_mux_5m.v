// ============================================================================
// axi4_master_mux_5m.v  (v2 — Round-Robin Arbitration)
//
// CHANGES vs v1 (Fixed Priority):
//   FIX-ARB-RR : Thay thế Fixed Priority bằng Round-Robin cho cả Read và Write.
//
//   Vấn đề với Fixed Priority:
//     M0 (ICache) luôn thắng → M2/M3/M4 có thể bị starvation khi ICache và
//     DCache liên tục request. DMA bị delay vô thời hạn → system hang.
//
//   Giải pháp Round-Robin:
//     - Thêm reg last_rd_grant [2:0] và last_wr_grant [2:0]
//       lưu master VỪA ĐƯỢC PHỤC VỤ xong (update khi RLAST / B-handshake)
//     - next_winner bắt đầu tìm từ (last_grant + 1) mod 5 thay vì từ M0
//     - Burst lock: KHÔNG thay grant khi đang giữa burst (giữ nguyên)
//
//   Ràng buộc giữ nguyên từ v1:
//     - Không cắt burst: hold grant đến RLAST (read) / B-handshake (write)
//     - M4 (JTAG): vẫn tham gia Round-Robin bình thường (không special-case)
//     - KHÔNG thay đổi port, signal name, coding style
//     - Mux/demux channels (AR/R/AW/W/B) giữ nguyên 100%
//
// Masters:
//   M0 = ICache    (tham gia Round-Robin)
//   M1 = DCache    (tham gia Round-Robin)
//   M2 = ASCON DMA (tham gia Round-Robin)
//   M3 = DMA Ctrl  (tham gia Round-Robin)
//   M4 = JTAG DM   (tham gia Round-Robin — thấp hơn vẫn tự nhiên vì ít request)
//
// ID tagging: giữ nguyên — 3 bit cao của ID = master index
// ============================================================================

module axi4_master_mux_5m #(
    parameter ID_WIDTH   = 4,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Master 0 — ICache
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m0_arid,
    input  wire [ADDR_WIDTH-1:0] m0_araddr,
    input  wire [7:0]            m0_arlen,
    input  wire [2:0]            m0_arsize,
    input  wire [1:0]            m0_arburst,
    input  wire [2:0]            m0_arprot,
    input  wire                  m0_arvalid,
    output wire                  m0_arready,

    output wire [ID_WIDTH-1:0]   m0_rid,
    output wire [DATA_WIDTH-1:0] m0_rdata,
    output wire [1:0]            m0_rresp,
    output wire                  m0_rlast,
    output wire                  m0_rvalid,
    input  wire                  m0_rready,

    input  wire [ID_WIDTH-1:0]   m0_awid,
    input  wire [ADDR_WIDTH-1:0] m0_awaddr,
    input  wire [7:0]            m0_awlen,
    input  wire [2:0]            m0_awsize,
    input  wire [1:0]            m0_awburst,
    input  wire [2:0]            m0_awprot,
    input  wire                  m0_awvalid,
    output wire                  m0_awready,

    input  wire [DATA_WIDTH-1:0] m0_wdata,
    input  wire [STRB_WIDTH-1:0] m0_wstrb,
    input  wire                  m0_wlast,
    input  wire                  m0_wvalid,
    output wire                  m0_wready,

    output wire [ID_WIDTH-1:0]   m0_bid,
    output wire [1:0]            m0_bresp,
    output wire                  m0_bvalid,
    input  wire                  m0_bready,

    // ========================================================================
    // Master 1 — DCache
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m1_arid,
    input  wire [ADDR_WIDTH-1:0] m1_araddr,
    input  wire [7:0]            m1_arlen,
    input  wire [2:0]            m1_arsize,
    input  wire [1:0]            m1_arburst,
    input  wire [2:0]            m1_arprot,
    input  wire                  m1_arvalid,
    output wire                  m1_arready,

    output wire [ID_WIDTH-1:0]   m1_rid,
    output wire [DATA_WIDTH-1:0] m1_rdata,
    output wire [1:0]            m1_rresp,
    output wire                  m1_rlast,
    output wire                  m1_rvalid,
    input  wire                  m1_rready,

    input  wire [ID_WIDTH-1:0]   m1_awid,
    input  wire [ADDR_WIDTH-1:0] m1_awaddr,
    input  wire [7:0]            m1_awlen,
    input  wire [2:0]            m1_awsize,
    input  wire [1:0]            m1_awburst,
    input  wire [2:0]            m1_awprot,
    input  wire                  m1_awvalid,
    output wire                  m1_awready,

    input  wire [DATA_WIDTH-1:0] m1_wdata,
    input  wire [STRB_WIDTH-1:0] m1_wstrb,
    input  wire                  m1_wlast,
    input  wire                  m1_wvalid,
    output wire                  m1_wready,

    output wire [ID_WIDTH-1:0]   m1_bid,
    output wire [1:0]            m1_bresp,
    output wire                  m1_bvalid,
    input  wire                  m1_bready,

    // ========================================================================
    // Master 2 — ASCON DMA (64-bit via width converter → 32-bit)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m2_arid,
    input  wire [ADDR_WIDTH-1:0] m2_araddr,
    input  wire [7:0]            m2_arlen,
    input  wire [2:0]            m2_arsize,
    input  wire [1:0]            m2_arburst,
    input  wire [2:0]            m2_arprot,
    input  wire                  m2_arvalid,
    output wire                  m2_arready,

    output wire [ID_WIDTH-1:0]   m2_rid,
    output wire [DATA_WIDTH-1:0] m2_rdata,
    output wire [1:0]            m2_rresp,
    output wire                  m2_rlast,
    output wire                  m2_rvalid,
    input  wire                  m2_rready,

    input  wire [ID_WIDTH-1:0]   m2_awid,
    input  wire [ADDR_WIDTH-1:0] m2_awaddr,
    input  wire [7:0]            m2_awlen,
    input  wire [2:0]            m2_awsize,
    input  wire [1:0]            m2_awburst,
    input  wire [2:0]            m2_awprot,
    input  wire                  m2_awvalid,
    output wire                  m2_awready,

    input  wire [DATA_WIDTH-1:0] m2_wdata,
    input  wire [STRB_WIDTH-1:0] m2_wstrb,
    input  wire                  m2_wlast,
    input  wire                  m2_wvalid,
    output wire                  m2_wready,

    output wire [ID_WIDTH-1:0]   m2_bid,
    output wire [1:0]            m2_bresp,
    output wire                  m2_bvalid,
    input  wire                  m2_bready,

    // ========================================================================
    // Master 3 — DMA Controller (multi-channel general purpose)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m3_arid,
    input  wire [ADDR_WIDTH-1:0] m3_araddr,
    input  wire [7:0]            m3_arlen,
    input  wire [2:0]            m3_arsize,
    input  wire [1:0]            m3_arburst,
    input  wire [2:0]            m3_arprot,
    input  wire                  m3_arvalid,
    output wire                  m3_arready,

    output wire [ID_WIDTH-1:0]   m3_rid,
    output wire [DATA_WIDTH-1:0] m3_rdata,
    output wire [1:0]            m3_rresp,
    output wire                  m3_rlast,
    output wire                  m3_rvalid,
    input  wire                  m3_rready,

    input  wire [ID_WIDTH-1:0]   m3_awid,
    input  wire [ADDR_WIDTH-1:0] m3_awaddr,
    input  wire [7:0]            m3_awlen,
    input  wire [2:0]            m3_awsize,
    input  wire [1:0]            m3_awburst,
    input  wire [2:0]            m3_awprot,
    input  wire                  m3_awvalid,
    output wire                  m3_awready,

    input  wire [DATA_WIDTH-1:0] m3_wdata,
    input  wire [STRB_WIDTH-1:0] m3_wstrb,
    input  wire                  m3_wlast,
    input  wire                  m3_wvalid,
    output wire                  m3_wready,

    output wire [ID_WIDTH-1:0]   m3_bid,
    output wire [1:0]            m3_bresp,
    output wire                  m3_bvalid,
    input  wire                  m3_bready,

    // ========================================================================
    // Master 4 — JTAG Debug Module (system bus access)
    // ========================================================================
    input  wire [ID_WIDTH-1:0]   m4_arid,
    input  wire [ADDR_WIDTH-1:0] m4_araddr,
    input  wire [7:0]            m4_arlen,
    input  wire [2:0]            m4_arsize,
    input  wire [1:0]            m4_arburst,
    input  wire [2:0]            m4_arprot,
    input  wire                  m4_arvalid,
    output wire                  m4_arready,

    output wire [ID_WIDTH-1:0]   m4_rid,
    output wire [DATA_WIDTH-1:0] m4_rdata,
    output wire [1:0]            m4_rresp,
    output wire                  m4_rlast,
    output wire                  m4_rvalid,
    input  wire                  m4_rready,

    input  wire [ID_WIDTH-1:0]   m4_awid,
    input  wire [ADDR_WIDTH-1:0] m4_awaddr,
    input  wire [7:0]            m4_awlen,
    input  wire [2:0]            m4_awsize,
    input  wire [1:0]            m4_awburst,
    input  wire [2:0]            m4_awprot,
    input  wire                  m4_awvalid,
    output wire                  m4_awready,

    input  wire [DATA_WIDTH-1:0] m4_wdata,
    input  wire [STRB_WIDTH-1:0] m4_wstrb,
    input  wire                  m4_wlast,
    input  wire                  m4_wvalid,
    output wire                  m4_wready,

    output wire [ID_WIDTH-1:0]   m4_bid,
    output wire [1:0]            m4_bresp,
    output wire                  m4_bvalid,
    input  wire                  m4_bready,

    // ========================================================================
    // Slave Port
    // ========================================================================
    output wire [ID_WIDTH-1:0]   s_arid,
    output wire [ADDR_WIDTH-1:0] s_araddr,
    output wire [7:0]            s_arlen,
    output wire [2:0]            s_arsize,
    output wire [1:0]            s_arburst,
    output wire [2:0]            s_arprot,
    output wire                  s_arvalid,
    input  wire                  s_arready,

    input  wire [ID_WIDTH-1:0]   s_rid,
    input  wire [DATA_WIDTH-1:0] s_rdata,
    input  wire [1:0]            s_rresp,
    input  wire                  s_rlast,
    input  wire                  s_rvalid,
    output wire                  s_rready,

    output wire [ID_WIDTH-1:0]   s_awid,
    output wire [ADDR_WIDTH-1:0] s_awaddr,
    output wire [7:0]            s_awlen,
    output wire [2:0]            s_awsize,
    output wire [1:0]            s_awburst,
    output wire [2:0]            s_awprot,
    output wire                  s_awvalid,
    input  wire                  s_awready,

    output wire [DATA_WIDTH-1:0] s_wdata,
    output wire [STRB_WIDTH-1:0] s_wstrb,
    output wire                  s_wlast,
    output wire                  s_wvalid,
    input  wire                  s_wready,

    input  wire [ID_WIDTH-1:0]   s_bid,
    input  wire [1:0]            s_bresp,
    input  wire                  s_bvalid,
    output wire                  s_bready
);

    // ========================================================================
    // ID Tag constants — 3 bits → supports 8 masters (5 used)
    // ========================================================================
    localparam [2:0] TAG_M0 = 3'b000;
    localparam [2:0] TAG_M1 = 3'b001;
    localparam [2:0] TAG_M2 = 3'b010;
    localparam [2:0] TAG_M3 = 3'b011;
    localparam [2:0] TAG_M4 = 3'b100;

    // ========================================================================
    // Read Arbitration FSM — Round-Robin, no burst cut
    //
    // Cách hoạt động:
    //   1. Khi rd_arb == RD_IDLE: dùng last_rd_grant để bắt đầu tìm từ
    //      master KẾ TIẾP thay vì luôn từ M0.
    //      WHY: Nếu luôn ưu tiên M0, ICache chiếm bus liên tục → DMA starvation.
    //
    //   2. rd_arb giữ nguyên trong suốt burst (đến RLAST).
    //      WHY: AXI không cho phép cắt giữa burst — slave expect toàn bộ beat.
    //
    //   3. Khi RLAST + rready: cập nhật last_rd_grant = master vừa xong,
    //      rồi chuyển về RD_IDLE để chọn master tiếp theo.
    //      WHY: last_rd_grant cần biết điểm bắt đầu vòng quay tiếp theo.
    // ========================================================================
    localparam [2:0] RD_IDLE = 3'd0,
                     RD_M0   = 3'd1,
                     RD_M1   = 3'd2,
                     RD_M2   = 3'd3,
                     RD_M3   = 3'd4,
                     RD_M4   = 3'd5;

    reg [2:0] rd_arb;

    // last_rd_grant: lưu master index (0-4) vừa được phục vụ xong.
    // Khởi tạo = 3'd4 → vòng đầu tiên bắt đầu từ M0 (4+1 mod 5 = 0).
    reg [2:0] last_rd_grant;

    // ────────────────────────────────────────────────────────────────────────
    // Round-Robin next winner (combinational)
    // Bắt đầu tìm từ (last+1) mod 5, quét một vòng đầy đủ.
    // Trả về RD_IDLE nếu không có ai request.
    // ────────────────────────────────────────────────────────────────────────
    /* verilator lint_off BLKSEQ */
    function [2:0] rd_rr_next;
        input [2:0] last;   // master index 0-4 vừa phục vụ xong
        input       r0, r1, r2, r3, r4;   // arvalid của M0..M4
        reg   [2:0] nxt;
        begin
            nxt = RD_IDLE;
            // WHY case thay vì loop: Verilog không có modular arithmetic đẹp trong
            // combinational function. Case tường minh, synthesis-friendly, dễ verify.
            case (last)
                3'd0: begin // M0 vừa xong → thử M1,M2,M3,M4,M0
                    if      (r1) nxt = RD_M1;
                    else if (r2) nxt = RD_M2;
                    else if (r3) nxt = RD_M3;
                    else if (r4) nxt = RD_M4;
                    else if (r0) nxt = RD_M0;
                end
                3'd1: begin // M1 vừa xong → thử M2,M3,M4,M0,M1
                    if      (r2) nxt = RD_M2;
                    else if (r3) nxt = RD_M3;
                    else if (r4) nxt = RD_M4;
                    else if (r0) nxt = RD_M0;
                    else if (r1) nxt = RD_M1;
                end
                3'd2: begin // M2 vừa xong → thử M3,M4,M0,M1,M2
                    if      (r3) nxt = RD_M3;
                    else if (r4) nxt = RD_M4;
                    else if (r0) nxt = RD_M0;
                    else if (r1) nxt = RD_M1;
                    else if (r2) nxt = RD_M2;
                end
                3'd3: begin // M3 vừa xong → thử M4,M0,M1,M2,M3
                    if      (r4) nxt = RD_M4;
                    else if (r0) nxt = RD_M0;
                    else if (r1) nxt = RD_M1;
                    else if (r2) nxt = RD_M2;
                    else if (r3) nxt = RD_M3;
                end
                3'd4: begin // M4 vừa xong → thử M0,M1,M2,M3,M4
                    if      (r0) nxt = RD_M0;
                    else if (r1) nxt = RD_M1;
                    else if (r2) nxt = RD_M2;
                    else if (r3) nxt = RD_M3;
                    else if (r4) nxt = RD_M4;
                end
                default: begin // fallback: fixed priority (không nên xảy ra)
                    if      (r0) nxt = RD_M0;
                    else if (r1) nxt = RD_M1;
                    else if (r2) nxt = RD_M2;
                    else if (r3) nxt = RD_M3;
                    else if (r4) nxt = RD_M4;
                end
            endcase
            rd_rr_next = nxt;
        end
    endfunction
    /* verilator lint_on BLKSEQ */

    // ────────────────────────────────────────────────────────────────────────
    // Read Arbitration FSM (sequential)
    // ────────────────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_arb        <= RD_IDLE;
            last_rd_grant <= 3'd4;  // khởi đầu vòng tại M0
        end else begin
            case (rd_arb)
                RD_IDLE: begin
                    rd_arb <= rd_rr_next(last_rd_grant,
                                         m0_arvalid, m1_arvalid,
                                         m2_arvalid, m3_arvalid, m4_arvalid);
                end
                RD_M0: begin
                    // Giữ grant cho đến khi RLAST của burst kết thúc
                    // WHY: rd_resp_to_m0 dùng tag trên RID → chỉ release
                    //      khi đúng response cho M0 (không nhầm burst khác)
                    if (s_rvalid && m0_rready && s_rlast) begin
                        last_rd_grant <= 3'd0;
                        rd_arb        <= rd_rr_next(3'd0,
                                                     m0_arvalid, m1_arvalid,
                                                     m2_arvalid, m3_arvalid, m4_arvalid);
                    end
                end
                RD_M1: begin
                    if (s_rvalid && m1_rready && s_rlast) begin
                        last_rd_grant <= 3'd1;
                        rd_arb        <= rd_rr_next(3'd1,
                                                     m0_arvalid, m1_arvalid,
                                                     m2_arvalid, m3_arvalid, m4_arvalid);
                    end
                end
                RD_M2: begin
                    if (s_rvalid && m2_rready && s_rlast) begin
                        last_rd_grant <= 3'd2;
                        rd_arb        <= rd_rr_next(3'd2,
                                                     m0_arvalid, m1_arvalid,
                                                     m2_arvalid, m3_arvalid, m4_arvalid);
                    end
                end
                RD_M3: begin
                    if (s_rvalid && m3_rready && s_rlast) begin
                        last_rd_grant <= 3'd3;
                        rd_arb        <= rd_rr_next(3'd3,
                                                     m0_arvalid, m1_arvalid,
                                                     m2_arvalid, m3_arvalid, m4_arvalid);
                    end
                end
                RD_M4: begin
                    if (s_rvalid && m4_rready && s_rlast) begin
                        last_rd_grant <= 3'd4;
                        rd_arb        <= rd_rr_next(3'd4,
                                                     m0_arvalid, m1_arvalid,
                                                     m2_arvalid, m3_arvalid, m4_arvalid);
                    end
                end
                default: rd_arb <= RD_IDLE;
            endcase
        end
    end

    // Grant decode — giống v1 nhưng KHÔNG có IDLE combinational bypass.
    // WHY bỏ IDLE bypass: Trong v1, IDLE bypass (rd_grant_m0 = IDLE && m0_arvalid)
    //   gây glitch 1 cycle — mux chọn M0 ngay khi IDLE dù next_winner chưa xác định.
    //   Với RR, ta cần đợi FSM chuyển trạng thái đúng để tránh chọn sai master.
    //   Hệ quả: có thể trễ thêm 1 cycle khi idle → first request. Chấp nhận được.
    wire rd_grant_m0 = (rd_arb == RD_M0);
    wire rd_grant_m1 = (rd_arb == RD_M1);
    wire rd_grant_m2 = (rd_arb == RD_M2);
    wire rd_grant_m3 = (rd_arb == RD_M3);
    wire rd_grant_m4 = (rd_arb == RD_M4);

    // ========================================================================
    // Write Arbitration FSM — Round-Robin, no burst cut
    //
    // Burst lock: giữ grant đến khi B-handshake (s_bvalid & mx_bready).
    // WHY dùng B-handshake thay vì WLAST: sau WLAST slave vẫn đang xử lý,
    // B-channel mới là điểm hoàn thành thực sự của write transaction.
    // ========================================================================
    localparam [2:0] WR_IDLE = 3'd0,
                     WR_M0   = 3'd1,
                     WR_M1   = 3'd2,
                     WR_M2   = 3'd3,
                     WR_M3   = 3'd4,
                     WR_M4   = 3'd5;

    reg [2:0] wr_arb;
    reg [2:0] last_wr_grant;

    // ────────────────────────────────────────────────────────────────────────
    // Round-Robin next winner for Write (giống Read, dùng awvalid)
    // ────────────────────────────────────────────────────────────────────────
    /* verilator lint_off BLKSEQ */
    function [2:0] wr_rr_next;
        input [2:0] last;
        input       w0, w1, w2, w3, w4;
        reg   [2:0] nxt;
        begin
            nxt = WR_IDLE;
            case (last)
                3'd0: begin
                    if      (w1) nxt = WR_M1;
                    else if (w2) nxt = WR_M2;
                    else if (w3) nxt = WR_M3;
                    else if (w4) nxt = WR_M4;
                    else if (w0) nxt = WR_M0;
                end
                3'd1: begin
                    if      (w2) nxt = WR_M2;
                    else if (w3) nxt = WR_M3;
                    else if (w4) nxt = WR_M4;
                    else if (w0) nxt = WR_M0;
                    else if (w1) nxt = WR_M1;
                end
                3'd2: begin
                    if      (w3) nxt = WR_M3;
                    else if (w4) nxt = WR_M4;
                    else if (w0) nxt = WR_M0;
                    else if (w1) nxt = WR_M1;
                    else if (w2) nxt = WR_M2;
                end
                3'd3: begin
                    if      (w4) nxt = WR_M4;
                    else if (w0) nxt = WR_M0;
                    else if (w1) nxt = WR_M1;
                    else if (w2) nxt = WR_M2;
                    else if (w3) nxt = WR_M3;
                end
                3'd4: begin
                    if      (w0) nxt = WR_M0;
                    else if (w1) nxt = WR_M1;
                    else if (w2) nxt = WR_M2;
                    else if (w3) nxt = WR_M3;
                    else if (w4) nxt = WR_M4;
                end
                default: begin
                    if      (w0) nxt = WR_M0;
                    else if (w1) nxt = WR_M1;
                    else if (w2) nxt = WR_M2;
                    else if (w3) nxt = WR_M3;
                    else if (w4) nxt = WR_M4;
                end
            endcase
            wr_rr_next = nxt;
        end
    endfunction
    /* verilator lint_on BLKSEQ */

    // ────────────────────────────────────────────────────────────────────────
    // Write Arbitration FSM (sequential)
    // ────────────────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_arb        <= WR_IDLE;
            last_wr_grant <= 3'd4;
        end else begin
            case (wr_arb)
                WR_IDLE: begin
                    wr_arb <= wr_rr_next(last_wr_grant,
                                          m0_awvalid, m1_awvalid,
                                          m2_awvalid, m3_awvalid, m4_awvalid);
                end
                WR_M0: begin
                    if (s_bvalid && m0_bready) begin
                        last_wr_grant <= 3'd0;
                        wr_arb        <= wr_rr_next(3'd0,
                                                     m0_awvalid, m1_awvalid,
                                                     m2_awvalid, m3_awvalid, m4_awvalid);
                    end
                end
                WR_M1: begin
                    if (s_bvalid && m1_bready) begin
                        last_wr_grant <= 3'd1;
                        wr_arb        <= wr_rr_next(3'd1,
                                                     m0_awvalid, m1_awvalid,
                                                     m2_awvalid, m3_awvalid, m4_awvalid);
                    end
                end
                WR_M2: begin
                    if (s_bvalid && m2_bready) begin
                        last_wr_grant <= 3'd2;
                        wr_arb        <= wr_rr_next(3'd2,
                                                     m0_awvalid, m1_awvalid,
                                                     m2_awvalid, m3_awvalid, m4_awvalid);
                    end
                end
                WR_M3: begin
                    if (s_bvalid && m3_bready) begin
                        last_wr_grant <= 3'd3;
                        wr_arb        <= wr_rr_next(3'd3,
                                                     m0_awvalid, m1_awvalid,
                                                     m2_awvalid, m3_awvalid, m4_awvalid);
                    end
                end
                WR_M4: begin
                    if (s_bvalid && m4_bready) begin
                        last_wr_grant <= 3'd4;
                        wr_arb        <= wr_rr_next(3'd4,
                                                     m0_awvalid, m1_awvalid,
                                                     m2_awvalid, m3_awvalid, m4_awvalid);
                    end
                end
                default: wr_arb <= WR_IDLE;
            endcase
        end
    end

    wire wr_grant_m0 = (wr_arb == WR_M0);
    wire wr_grant_m1 = (wr_arb == WR_M1);
    wire wr_grant_m2 = (wr_arb == WR_M2);
    wire wr_grant_m3 = (wr_arb == WR_M3);
    wire wr_grant_m4 = (wr_arb == WR_M4);

    // ========================================================================
    // AR Channel Mux → Slave  [KHÔNG THAY ĐỔI từ v1]
    // ========================================================================
    assign s_arvalid = rd_grant_m0 ? m0_arvalid :
                       rd_grant_m1 ? m1_arvalid :
                       rd_grant_m2 ? m2_arvalid :
                       rd_grant_m3 ? m3_arvalid :
                       rd_grant_m4 ? m4_arvalid : 1'b0;

    assign s_araddr  = rd_grant_m0 ? m0_araddr :
                       rd_grant_m1 ? m1_araddr :
                       rd_grant_m2 ? m2_araddr :
                       rd_grant_m3 ? m3_araddr : m4_araddr;

    assign s_arlen   = rd_grant_m0 ? m0_arlen :
                       rd_grant_m1 ? m1_arlen :
                       rd_grant_m2 ? m2_arlen :
                       rd_grant_m3 ? m3_arlen : m4_arlen;

    assign s_arsize  = rd_grant_m0 ? m0_arsize :
                       rd_grant_m1 ? m1_arsize :
                       rd_grant_m2 ? m2_arsize :
                       rd_grant_m3 ? m3_arsize : m4_arsize;

    assign s_arburst = rd_grant_m0 ? m0_arburst :
                       rd_grant_m1 ? m1_arburst :
                       rd_grant_m2 ? m2_arburst :
                       rd_grant_m3 ? m3_arburst : m4_arburst;

    assign s_arprot  = rd_grant_m0 ? m0_arprot :
                       rd_grant_m1 ? m1_arprot :
                       rd_grant_m2 ? m2_arprot :
                       rd_grant_m3 ? m3_arprot : m4_arprot;

    // ID tagging: top 3 bits = master index
    assign s_arid = rd_grant_m0 ? {TAG_M0, m0_arid[ID_WIDTH-4:0]} :
                    rd_grant_m1 ? {TAG_M1, m1_arid[ID_WIDTH-4:0]} :
                    rd_grant_m2 ? {TAG_M2, m2_arid[ID_WIDTH-4:0]} :
                    rd_grant_m3 ? {TAG_M3, m3_arid[ID_WIDTH-4:0]} :
                                  {TAG_M4, m4_arid[ID_WIDTH-4:0]};

    assign m0_arready = rd_grant_m0 ? s_arready : 1'b0;
    assign m1_arready = rd_grant_m1 ? s_arready : 1'b0;
    assign m2_arready = rd_grant_m2 ? s_arready : 1'b0;
    assign m3_arready = rd_grant_m3 ? s_arready : 1'b0;
    assign m4_arready = rd_grant_m4 ? s_arready : 1'b0;

    // ========================================================================
    // R Channel Demux ← Slave  [KHÔNG THAY ĐỔI từ v1]
    // ========================================================================
    wire [2:0] rd_resp_tag = s_rid[ID_WIDTH-1:ID_WIDTH-3];

    wire rd_resp_to_m0 = (rd_resp_tag == TAG_M0);
    wire rd_resp_to_m1 = (rd_resp_tag == TAG_M1);
    wire rd_resp_to_m2 = (rd_resp_tag == TAG_M2);
    wire rd_resp_to_m3 = (rd_resp_tag == TAG_M3);
    wire rd_resp_to_m4 = (rd_resp_tag == TAG_M4);

    // Strip tag bits when returning to master
    wire [ID_WIDTH-4:0] s_rid_user = s_rid[ID_WIDTH-4:0];
    assign m0_rid = {{3{1'b0}}, s_rid_user};
    assign m1_rid = {{3{1'b0}}, s_rid_user};
    assign m2_rid = {{3{1'b0}}, s_rid_user};
    assign m3_rid = {{3{1'b0}}, s_rid_user};
    assign m4_rid = {{3{1'b0}}, s_rid_user};

    assign m0_rdata  = s_rdata;
    assign m1_rdata  = s_rdata;
    assign m2_rdata  = s_rdata;
    assign m3_rdata  = s_rdata;
    assign m4_rdata  = s_rdata;

    assign m0_rresp  = s_rresp;
    assign m1_rresp  = s_rresp;
    assign m2_rresp  = s_rresp;
    assign m3_rresp  = s_rresp;
    assign m4_rresp  = s_rresp;

    assign m0_rlast  = s_rlast && rd_resp_to_m0;
    assign m1_rlast  = s_rlast && rd_resp_to_m1;
    assign m2_rlast  = s_rlast && rd_resp_to_m2;
    assign m3_rlast  = s_rlast && rd_resp_to_m3;
    assign m4_rlast  = s_rlast && rd_resp_to_m4;

    assign m0_rvalid = s_rvalid && rd_resp_to_m0;
    assign m1_rvalid = s_rvalid && rd_resp_to_m1;
    assign m2_rvalid = s_rvalid && rd_resp_to_m2;
    assign m3_rvalid = s_rvalid && rd_resp_to_m3;
    assign m4_rvalid = s_rvalid && rd_resp_to_m4;

    assign s_rready  = rd_resp_to_m0 ? m0_rready :
                       rd_resp_to_m1 ? m1_rready :
                       rd_resp_to_m2 ? m2_rready :
                       rd_resp_to_m3 ? m3_rready :
                       rd_resp_to_m4 ? m4_rready : 1'b0;

    // ========================================================================
    // AW Channel Mux → Slave  [KHÔNG THAY ĐỔI từ v1]
    // ========================================================================
    assign s_awvalid = wr_grant_m0 ? m0_awvalid :
                       wr_grant_m1 ? m1_awvalid :
                       wr_grant_m2 ? m2_awvalid :
                       wr_grant_m3 ? m3_awvalid :
                       wr_grant_m4 ? m4_awvalid : 1'b0;

    assign s_awaddr  = wr_grant_m0 ? m0_awaddr :
                       wr_grant_m1 ? m1_awaddr :
                       wr_grant_m2 ? m2_awaddr :
                       wr_grant_m3 ? m3_awaddr : m4_awaddr;

    assign s_awlen   = wr_grant_m0 ? m0_awlen :
                       wr_grant_m1 ? m1_awlen :
                       wr_grant_m2 ? m2_awlen :
                       wr_grant_m3 ? m3_awlen : m4_awlen;

    assign s_awsize  = wr_grant_m0 ? m0_awsize :
                       wr_grant_m1 ? m1_awsize :
                       wr_grant_m2 ? m2_awsize :
                       wr_grant_m3 ? m3_awsize : m4_awsize;

    assign s_awburst = wr_grant_m0 ? m0_awburst :
                       wr_grant_m1 ? m1_awburst :
                       wr_grant_m2 ? m2_awburst :
                       wr_grant_m3 ? m3_awburst : m4_awburst;

    assign s_awprot  = wr_grant_m0 ? m0_awprot :
                       wr_grant_m1 ? m1_awprot :
                       wr_grant_m2 ? m2_awprot :
                       wr_grant_m3 ? m3_awprot : m4_awprot;

    assign s_awid    = wr_grant_m0 ? {TAG_M0, m0_awid[ID_WIDTH-4:0]} :
                       wr_grant_m1 ? {TAG_M1, m1_awid[ID_WIDTH-4:0]} :
                       wr_grant_m2 ? {TAG_M2, m2_awid[ID_WIDTH-4:0]} :
                       wr_grant_m3 ? {TAG_M3, m3_awid[ID_WIDTH-4:0]} :
                                     {TAG_M4, m4_awid[ID_WIDTH-4:0]};

    assign m0_awready = wr_grant_m0 ? s_awready : 1'b0;
    assign m1_awready = wr_grant_m1 ? s_awready : 1'b0;
    assign m2_awready = wr_grant_m2 ? s_awready : 1'b0;
    assign m3_awready = wr_grant_m3 ? s_awready : 1'b0;
    assign m4_awready = wr_grant_m4 ? s_awready : 1'b0;

    // ========================================================================
    // W Channel Mux → Slave  [KHÔNG THAY ĐỔI từ v1]
    // ========================================================================
    assign s_wdata  = wr_grant_m0 ? m0_wdata :
                      wr_grant_m1 ? m1_wdata :
                      wr_grant_m2 ? m2_wdata :
                      wr_grant_m3 ? m3_wdata : m4_wdata;

    assign s_wstrb  = wr_grant_m0 ? m0_wstrb :
                      wr_grant_m1 ? m1_wstrb :
                      wr_grant_m2 ? m2_wstrb :
                      wr_grant_m3 ? m3_wstrb : m4_wstrb;

    assign s_wlast  = wr_grant_m0 ? m0_wlast :
                      wr_grant_m1 ? m1_wlast :
                      wr_grant_m2 ? m2_wlast :
                      wr_grant_m3 ? m3_wlast : m4_wlast;

    assign s_wvalid = wr_grant_m0 ? m0_wvalid :
                      wr_grant_m1 ? m1_wvalid :
                      wr_grant_m2 ? m2_wvalid :
                      wr_grant_m3 ? m3_wvalid :
                      wr_grant_m4 ? m4_wvalid : 1'b0;

    assign m0_wready = wr_grant_m0 ? s_wready : 1'b0;
    assign m1_wready = wr_grant_m1 ? s_wready : 1'b0;
    assign m2_wready = wr_grant_m2 ? s_wready : 1'b0;
    assign m3_wready = wr_grant_m3 ? s_wready : 1'b0;
    assign m4_wready = wr_grant_m4 ? s_wready : 1'b0;

    // ========================================================================
    // B Channel Demux ← Slave  [KHÔNG THAY ĐỔI từ v1]
    // ========================================================================
    wire [2:0] wr_resp_tag = s_bid[ID_WIDTH-1:ID_WIDTH-3];

    wire wr_resp_to_m0 = (wr_resp_tag == TAG_M0);
    wire wr_resp_to_m1 = (wr_resp_tag == TAG_M1);
    wire wr_resp_to_m2 = (wr_resp_tag == TAG_M2);
    wire wr_resp_to_m3 = (wr_resp_tag == TAG_M3);
    wire wr_resp_to_m4 = (wr_resp_tag == TAG_M4);

    wire [ID_WIDTH-4:0] s_bid_user = s_bid[ID_WIDTH-4:0];
    assign m0_bid = {{3{1'b0}}, s_bid_user};
    assign m1_bid = {{3{1'b0}}, s_bid_user};
    assign m2_bid = {{3{1'b0}}, s_bid_user};
    assign m3_bid = {{3{1'b0}}, s_bid_user};
    assign m4_bid = {{3{1'b0}}, s_bid_user};

    assign m0_bresp  = s_bresp;
    assign m1_bresp  = s_bresp;
    assign m2_bresp  = s_bresp;
    assign m3_bresp  = s_bresp;
    assign m4_bresp  = s_bresp;

    assign m0_bvalid = s_bvalid && wr_resp_to_m0;
    assign m1_bvalid = s_bvalid && wr_resp_to_m1;
    assign m2_bvalid = s_bvalid && wr_resp_to_m2;
    assign m3_bvalid = s_bvalid && wr_resp_to_m3;
    assign m4_bvalid = s_bvalid && wr_resp_to_m4;

    assign s_bready  = wr_resp_to_m0 ? m0_bready :
                       wr_resp_to_m1 ? m1_bready :
                       wr_resp_to_m2 ? m2_bready :
                       wr_resp_to_m3 ? m3_bready :
                       wr_resp_to_m4 ? m4_bready : 1'b0;

endmodule