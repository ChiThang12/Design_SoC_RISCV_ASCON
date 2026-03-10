`include "cpu/interface/dcache/dcache_defines.vh"

// ============================================================================
// Module: dcache_axi_interface  —  Write-Back version
// Thêm AXI4 ID signals để kết nối vào axi4_crossbar (M1)
//
// FIX-BUG1: rd_word_counter không tăng ở beat cuối (RLAST)
//   → word 3 bị ghi vào offset 2, refill_done assert với refill_word sai
//   FIX: tăng rd_word_counter TRƯỚC KHI latch vào refill_word
//        bằng cách dùng wire next_word_counter, output refill_word
//        bằng wire (combinational), không đợi đến cycle sau.
//
// FIX-BUG2: refill_addr bị latch sai cycle trong RD_IDLE
//   Controller set refill_addr và refill_start cùng cycle (cả 2 là reg).
//   RD_IDLE latch M_AXI_ARADDR <= refill_addr ngay khi refill_start=1,
//   nhưng refill_addr chỉ available cycle ĐÓ (controller vừa drive nó).
//   Do cả 2 là sequential, không có race — nhưng vấn đề thực là
//   controller dùng nonblocking (<=) nên refill_addr update vào END OF
//   cycle, và RD_IDLE cũng chạy cùng posedge → chúng thấy GIÁ TRỊ CŨ.
//   FIX: Thêm state RD_LATCH — 1 cycle buffer để đợi refill_addr stable,
//        rồi mới drive M_AXI_ARADDR và chuyển sang RD_AR.
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
    output reg         refill_done,
    output reg [31:0]  refill_data,
    output wire [1:0]  refill_word,       // FIX-BUG1: wire (combinational)
    output reg         refill_data_valid,

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

    // DCache luôn dùng ARID = 0, AWID = 0
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
    // Read Refill State Machine
    //
    // FIX-BUG2: Thêm state RD_LATCH giữa RD_IDLE và RD_AR.
    //   RD_IDLE  : phát hiện refill_start=1, chuyển sang RD_LATCH
    //   RD_LATCH : refill_addr đã stable (1 full cycle sau khi controller set),
    //              latch vào M_AXI_ARADDR, assert ARVALID, chuyển sang RD_AR
    //   RD_AR    : chờ ARREADY
    //   RD_R     : nhận burst data
    // ========================================================================
    localparam [2:0]
        RD_IDLE  = 3'b000,
        RD_LATCH = 3'b001,   // FIX-BUG2: 1-cycle pipeline buffer
        RD_AR    = 3'b010,
        RD_R     = 3'b011;

    reg [2:0] rd_state;

    // FIX-BUG1: rd_word_counter đếm số beat đã nhận (0..3)
    //   refill_word = current counter VALUE khi beat valid
    //   Counter tăng sau mỗi beat (kể cả LAST beat để reset chuẩn)
    reg [1:0]  rd_word_counter;
    assign refill_word = rd_word_counter;   // combinational: luôn = giá trị hiện tại

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state          <= RD_IDLE;
            refill_busy       <= 1'b0;
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            refill_data       <= 32'h0;
            rd_word_counter   <= 2'b00;
            M_AXI_ARADDR      <= 32'h0;
            M_AXI_ARVALID     <= 1'b0;
            M_AXI_RREADY      <= 1'b0;
        end else begin
            // Default: pulse signals LOW mỗi cycle
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;

            case (rd_state)

                // ── RD_IDLE: chờ controller kích hoạt refill ─────────────────
                RD_IDLE: begin
                    refill_busy     <= 1'b0;
                    M_AXI_ARVALID   <= 1'b0;
                    M_AXI_RREADY    <= 1'b0;
                    rd_word_counter <= 2'b00;

                    if (refill_start) begin
                        // FIX-BUG2: KHÔNG latch refill_addr ở đây vì nó vừa
                        // được drive bởi controller trong cùng posedge (nonblocking).
                        // Chuyển sang RD_LATCH để đợi 1 cycle cho addr stable.
                        refill_busy <= 1'b1;
                        rd_state    <= RD_LATCH;
                    end
                end

                // ── RD_LATCH: 1-cycle buffer, refill_addr đã stable ──────────
                // FIX-BUG2: Tại đây refill_addr từ controller đã update xong
                // (cycle trước đó controller đã drive bằng <=, cycle này ta đọc).
                RD_LATCH: begin
                    M_AXI_ARADDR  <= refill_addr;   // addr stable, latch đúng
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
                // FIX-BUG1: rd_word_counter output là refill_word (wire),
                //   nên controller thấy ĐÚNG index ngay khi beat valid.
                //   Sau khi latch data, tăng counter để sẵn sàng cho beat tiếp.
                //   LAST beat: tăng counter (không quan trọng vì về IDLE reset),
                //   set refill_done = 1 cùng cycle với refill_data_valid = 1.
                RD_R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        refill_data       <= M_AXI_RDATA;
                        // refill_word = rd_word_counter (wire) → controller thấy ngay
                        refill_data_valid <= 1'b1;

                        if (M_AXI_RLAST) begin
                            // FIX-BUG1: assert refill_done cùng cycle với data valid
                            // refill_word = rd_word_counter = 3 (đúng, là beat cuối)
                            refill_done     <= 1'b1;
                            M_AXI_RREADY    <= 1'b0;
                            refill_busy     <= 1'b0;
                            rd_word_counter <= 2'b00;  // reset cho lần sau
                            rd_state        <= RD_IDLE;
                        end else begin
                            // Tăng counter: beat tiếp sẽ là word (counter+1)
                            rd_word_counter <= rd_word_counter + 1'b1;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // ========================================================================
    // Eviction Write State Machine  (không thay đổi logic, chỉ giữ nguyên)
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