`include "cpu/interface/dcache/dcache_defines.vh"

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

    assign M_AXI_ARLEN   = 8'd3;
    assign M_AXI_ARSIZE  = 3'b010;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_AWLEN   = 8'd3;
    assign M_AXI_AWSIZE  = 3'b010;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWPROT  = 3'b000;

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
        end else begin
            case (rd_state)

                // ── RD_IDLE ──────────────────────────────────────────────────
                RD_IDLE: begin
                    refill_busy     <= 1'b0;
                    M_AXI_ARVALID   <= 1'b0;
                    M_AXI_RREADY    <= 1'b0;
                    rd_word_counter <= 2'b00;

                    if (refill_start) begin
                        refill_busy <= 1'b1;
                        rd_state    <= RD_LATCH;
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

                // ── RD_R: nhận burst (4 beats) ───────────────────────────────
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
                            rd_state        <= RD_IDLE;
                        end else begin
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
        end else begin
            evict_done <= 1'b0;

            case (ev_state)
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
                        ev_d0 <= evict_data_0;
                        ev_d1 <= evict_data_1;
                        ev_d2 <= evict_data_2;
                        ev_d3 <= evict_data_3;

                        M_AXI_AWVALID <= 1'b1;
                        M_AXI_WDATA   <= evict_data_0;
                        M_AXI_WSTRB   <= 4'hf;
                        M_AXI_WLAST   <= 1'b0;
                        M_AXI_WVALID  <= 1'b1;
                        evict_busy    <= 1'b1;
                        ev_state      <= EV_AW;
                    end
                end

                EV_AW: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        ev_aw_done    <= 1'b1;
                    end

                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        if (ev_beat == 2'd3) begin
                            M_AXI_WVALID <= 1'b0;
                            M_AXI_WLAST  <= 1'b0;

                            if (ev_aw_done || (M_AXI_AWVALID && M_AXI_AWREADY)) begin
                                M_AXI_BREADY <= 1'b1;
                                ev_state     <= EV_B;
                            end else begin
                                ev_state <= EV_W;
                            end
                        end else begin
                            ev_beat     <= ev_beat + 1'b1;
                            M_AXI_WDATA <= ev_word(ev_beat + 1'b1);
                            M_AXI_WLAST <= (ev_beat == 2'd2) ? 1'b1 : 1'b0;
                        end
                    end
                end

                EV_W: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        M_AXI_BREADY  <= 1'b1;
                        ev_state      <= EV_B;
                    end
                end

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