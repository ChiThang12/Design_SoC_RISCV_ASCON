// ============================================================================
// Module: dcache_axi_interface  —  Write-Back version
// ============================================================================
// FIX-BUG2: refill_done bị trễ 1 cycle sau beat cuối (RLAST).
//   Trước: RLAST → RD_DONE (cycle N+1) → refill_done=1 (cycle N+1)
//          Nhưng refill_data_valid=1 cũng ở cycle N → không bao giờ cùng lúc
//   Fix:   Assert refill_done=1 CÙNG CYCLE với beat RLAST (không cần RD_DONE state)
//          Xóa RD_DONE state, về RD_IDLE trực tiếp từ RD_R khi RLAST
//          → Controller có thể detect (refill_data_valid & refill_done) cùng cycle
//          → Tránh thêm 1 cycle REFILL_DRAIN không cần thiết khi CWF = last beat
//
// FIX-BUG4: BREADY timing — assert BREADY ngay khi vào EV_B (không chờ cycle sau).
//   Trước: EV_AW → set BREADY → posedge → EV_B với BREADY=1 đúng, nhưng nếu
//          BVALID đã lên cùng cycle set BREADY thì phải chờ 1 cycle nữa
//   Fix:   Không thay đổi lớn — BREADY đã set trước khi vào EV_B (đúng).
//          Tuy nhiên, trong EV_B check BVALID & BREADY (không chỉ BVALID) để
//          tuân thủ AXI handshake đúng.
// ============================================================================

`include "cpu/interface/dcache/dcache_defines.vh"

module dcache_axi_interface (
    input wire clk,
    input wire rst_n,

    // ========================================================================
    // Read Refill Interface
    // ========================================================================
    input wire [31:0]  refill_addr,
    input wire         refill_start,
    output reg         refill_busy,
    output reg         refill_done,      // FIX-BUG2: assert cùng cycle RLAST
    output reg [31:0]  refill_data,
    output reg [1:0]   refill_word,
    output reg         refill_data_valid,

    // ========================================================================
    // Eviction Interface
    // Burst write 4 words — toàn bộ dirty cache line
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
    output reg [31:0]  M_AXI_ARADDR,
    output wire [7:0]  M_AXI_ARLEN,
    output wire [2:0]  M_AXI_ARSIZE,
    output wire [1:0]  M_AXI_ARBURST,
    output wire [2:0]  M_AXI_ARPROT,
    output reg         M_AXI_ARVALID,
    input wire         M_AXI_ARREADY,

    input wire [31:0]  M_AXI_RDATA,
    input wire [1:0]   M_AXI_RRESP,
    input wire         M_AXI_RLAST,
    input wire         M_AXI_RVALID,
    output reg         M_AXI_RREADY,

    // ========================================================================
    // AXI4 Write Channel (eviction burst 4 beats)
    // ========================================================================
    output reg [31:0]  M_AXI_AWADDR,
    output wire [7:0]  M_AXI_AWLEN,
    output wire [2:0]  M_AXI_AWSIZE,
    output wire [1:0]  M_AXI_AWBURST,
    output wire [2:0]  M_AXI_AWPROT,
    output reg         M_AXI_AWVALID,
    input wire         M_AXI_AWREADY,

    output reg [31:0]  M_AXI_WDATA,
    output reg [3:0]   M_AXI_WSTRB,
    output reg         M_AXI_WLAST,
    output reg         M_AXI_WVALID,
    input wire         M_AXI_WREADY,

    input wire [1:0]   M_AXI_BRESP,
    input wire         M_AXI_BVALID,
    output reg         M_AXI_BREADY
);

    // ========================================================================
    // Constant tie-offs
    // ========================================================================
    assign M_AXI_ARLEN   = 8'd3;        // 4-beat burst (ARLEN=N-1)
    assign M_AXI_ARSIZE  = 3'b010;      // 4 bytes per beat
    assign M_AXI_ARBURST = 2'b01;       // INCR
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_AWLEN   = 8'd3;        // Eviction = 4-beat burst
    assign M_AXI_AWSIZE  = 3'b010;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWPROT  = 3'b000;

    // ========================================================================
    // Read Refill State Machine
    // FIX-BUG2: Xóa RD_DONE state — refill_done assert cùng cycle RLAST
    // ========================================================================
    localparam [1:0]
        RD_IDLE = 2'b00,
        RD_AR   = 2'b01,
        RD_R    = 2'b10;
        // RD_DONE đã xóa

    reg [1:0] rd_state;
    reg [1:0] rd_word_counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state          <= RD_IDLE;
            refill_busy       <= 1'b0;
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;
            refill_data       <= 32'h0;
            refill_word       <= 2'b00;
            rd_word_counter   <= 2'b00;
            M_AXI_ARADDR      <= 32'h0;
            M_AXI_ARVALID     <= 1'b0;
            M_AXI_RREADY      <= 1'b0;
        end else begin
            // Defaults — pulse signals
            refill_done       <= 1'b0;
            refill_data_valid <= 1'b0;

            case (rd_state)
                // ─────────────────────────────────────────────────────────────
                RD_IDLE: begin
                    refill_busy     <= 1'b0;
                    M_AXI_ARVALID   <= 1'b0;
                    M_AXI_RREADY    <= 1'b0;
                    rd_word_counter <= 2'b00;
                    if (refill_start) begin
                        M_AXI_ARADDR  <= refill_addr;
                        M_AXI_ARVALID <= 1'b1;
                        refill_busy   <= 1'b1;
                        rd_state      <= RD_AR;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                RD_AR: begin
                    if (M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;
                        rd_state      <= RD_R;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // FIX-BUG2: Không dùng RD_DONE state nữa.
                // refill_done được assert CÙNG CYCLE với beat cuối (RLAST).
                // Controller nhận refill_data_valid=1 + refill_done=1 cùng lúc
                // → có thể detect "last beat = critical word" và về IDLE thẳng.
                // ─────────────────────────────────────────────────────────────
                RD_R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        refill_data       <= M_AXI_RDATA;
                        refill_word       <= rd_word_counter;
                        refill_data_valid <= 1'b1;

                        if (M_AXI_RLAST) begin
                            // Beat cuối: assert refill_done cùng cycle
                            refill_done   <= 1'b1;     // FIX: không chờ RD_DONE
                            M_AXI_RREADY  <= 1'b0;
                            refill_busy   <= 1'b0;
                            rd_state      <= RD_IDLE;
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
    // Burst write 4 words (entire dirty cache line) → DMEM
    // AW và W channel chạy song song để maximize throughput
    // FIX-BUG4: EV_B check BVALID & BREADY (không chỉ BVALID) — AXI compliance
    // ========================================================================
    localparam [1:0]
        EV_IDLE = 2'b00,
        EV_AW   = 2'b01,   // AW + W channels (parallel)
        EV_W    = 2'b10,   // W còn gửi, AW đã xong trước
        EV_B    = 2'b11;   // Chờ B response

    reg [1:0]  ev_state;
    reg [1:0]  ev_beat;
    reg        ev_aw_done;

    // Latch toàn bộ dirty line khi evict_start
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
            evict_done <= 1'b0;  // pulse default

            case (ev_state)
                // ─────────────────────────────────────────────────────────────
                EV_IDLE: begin
                    evict_busy    <= 1'b0;
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WVALID  <= 1'b0;
                    M_AXI_WLAST   <= 1'b0;
                    M_AXI_BREADY  <= 1'b0;
                    ev_beat       <= 2'b00;
                    ev_aw_done    <= 1'b0;

                    if (evict_start) begin
                        M_AXI_AWADDR <= evict_addr;
                        ev_d0 <= evict_data_0;
                        ev_d1 <= evict_data_1;
                        ev_d2 <= evict_data_2;
                        ev_d3 <= evict_data_3;

                        // Kick AW + W beat 0 đồng thời
                        M_AXI_AWVALID <= 1'b1;
                        M_AXI_WDATA   <= evict_data_0;
                        M_AXI_WSTRB   <= 4'hf;
                        M_AXI_WLAST   <= 1'b0;
                        M_AXI_WVALID  <= 1'b1;
                        evict_busy    <= 1'b1;
                        ev_state      <= EV_AW;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // EV_AW: AW và W chạy song song
                // ─────────────────────────────────────────────────────────────
                EV_AW: begin
                    // AW handshake
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        ev_aw_done    <= 1'b1;
                    end

                    // W beat advance
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        if (ev_beat == 2'd3) begin
                            // Beat 3 accepted → W done
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

                // ─────────────────────────────────────────────────────────────
                // EV_W: W xong, chờ AW
                // ─────────────────────────────────────────────────────────────
                EV_W: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        M_AXI_BREADY  <= 1'b1;
                        ev_state      <= EV_B;
                    end
                end

                // ─────────────────────────────────────────────────────────────
                // EV_B: Chờ write response
                // FIX-BUG4: Check BVALID & BREADY (AXI: handshake khi cả 2 assert)
                // ─────────────────────────────────────────────────────────────
                EV_B: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin  // FIX: thêm & M_AXI_BREADY
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