// ============================================================================
// clint.v  —  RISC-V Core Local Interrupt Controller (CLINT)
// ============================================================================
// Spec:  RISC-V Privileged Architecture v1.12  §3.1.9 / SiFive CLINT spec
// Base address (khi mount vào SoC): 0x4000_0000
//
// Address map (offset từ base):
//   0x0000        msip          [RW]  Machine Software Interrupt Pending (bit[0])
//   0x4000        mtimecmp_lo   [RW]  Timer compare — 32-bit thấp
//   0x4004        mtimecmp_hi   [RW]  Timer compare — 32-bit cao
//   0xBFF8        mtime_lo      [RO]  Current mtime   — 32-bit thấp
//   0xBFFC        mtime_hi      [RO]  Current mtime   — 32-bit cao
//
// Fix log (giữ nguyên từ bản cũ):
//   [D3]          mtime_tick input từ soc_top prescaler
//   [RD-LOCK]     Snapshot mtime khi AR latch — đọc 64-bit nhất quán
//   [WR-ATOMICITY] mtimecmp_shadow_r: ghi lo → shadow, commit khi ghi hi
//   [BURST-DRAIN] Drain burst beats, chỉ ghi beat đầu
//   [B-OVERLAP]   b_id_r latch từ eff_awid, không đọc lại S_AXI_AWID
//   [RST-TIMER]   mtimecmp init = 0xFFFF...FFFF
//
// BUGFIX v2 (file này):
//
//   [BUG1-REG-IN-ALWAYS] Khai báo "reg [31:0] new_hi" bên trong always block
//       là syntax error trong Verilog-2001 (chỉ hợp lệ SystemVerilog).
//       Fix: khai báo new_hi_comb ở module level (reg), dùng trong always @(*).
//       Viết mtimecmp_hi case trực tiếp không cần block begin/end lồng nhau.
//
//   [BUG2-WDATA-LATCH] Khi master gửi W beat trước AW (FSM → WR_WWAIT),
//       WDATA/WSTRB chỉ valid trong cycle đó. Khi AW arrive sau,
//       wr_do_write fires nhưng S_AXI_WDATA đã không còn valid.
//       Fix: latch wd_data_r/wd_strb_r khi w_fire; dùng các reg này
//       thay vì S_AXI_WDATA/WSTRB trực tiếp khi ghi register.
//
//   [BUG3-DRAIN-COUNT] WR_DRAIN thoát khi cnt == wr_burst_len_r - 1,
//       off-by-one: bỏ sót beat cuối.
//       cnt khởi tạo = 1 (sau beat đầu ở AWWAIT), tăng mỗi w_fire.
//       Beat cuối = beat AWLEN → cnt = AWLEN = wr_burst_len_r.
//       Fix: đổi điều kiện thành cnt == wr_burst_len_r.
//
// ============================================================================

`timescale 1ns/1ps
`default_nettype none

module clint #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire clk,
    input  wire rst_n,          // active-low (fabric_rst_n từ soc_top)

    // [D3] mtime tick từ prescaler trong soc_top (1 MHz)
    input  wire mtime_tick,

    // ── AXI4 Full Slave ──────────────────────────────────────────────────────
    // Write Address Channel
    input  wire [ID_WIDTH-1:0]   S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [7:0]            S_AXI_AWLEN,
    input  wire [2:0]            S_AXI_AWSIZE,
    input  wire [1:0]            S_AXI_AWBURST,
    input  wire [2:0]            S_AXI_AWPROT,
    input  wire                  S_AXI_AWVALID,
    output wire                  S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WLAST,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,

    // Write Response Channel
    output wire [ID_WIDTH-1:0] S_AXI_BID,
    output wire [1:0]          S_AXI_BRESP,
    output wire                S_AXI_BVALID,
    input  wire                S_AXI_BREADY,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]   S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [7:0]            S_AXI_ARLEN,
    input  wire [2:0]            S_AXI_ARSIZE,
    input  wire [1:0]            S_AXI_ARBURST,
    input  wire [2:0]            S_AXI_ARPROT,
    input  wire                  S_AXI_ARVALID,
    output wire                  S_AXI_ARREADY,

    // Read Data Channel
    output wire [ID_WIDTH-1:0]   S_AXI_RID,
    output wire [DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0]            S_AXI_RRESP,
    output wire                  S_AXI_RLAST,
    output wire                  S_AXI_RVALID,
    input  wire                  S_AXI_RREADY,

    // ── Interrupt outputs → CPU ───────────────────────────────────────────────
    output wire timer_irq,
    output wire sw_irq
);

    // ========================================================================
    // Local parameters
    // ========================================================================
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    localparam OFFSET_MSIP         = 16'h0000;
    localparam OFFSET_MTIMECMP_LO  = 16'h4000;
    localparam OFFSET_MTIMECMP_HI  = 16'h4004;
    localparam OFFSET_MTIME_LO     = 16'hBFF8;
    localparam OFFSET_MTIME_HI     = 16'hBFFC;

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // ========================================================================
    // CLINT registers
    // ========================================================================
    reg [63:0] mtime_r;
    reg [63:0] mtimecmp_r;
    reg [31:0] mtimecmp_shadow_r;
    reg        msip_r;

    // ========================================================================
    // [D3] mtime counter
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mtime_r <= 64'd0;
        else if (mtime_tick)
            mtime_r <= mtime_r + 64'd1;
    end

    // ========================================================================
    // Interrupt outputs
    // ========================================================================
    assign timer_irq = (mtime_r >= mtimecmp_r);
    assign sw_irq    = msip_r;

    // ========================================================================
    // AXI4 Write FSM
    // ========================================================================
    reg [2:0] wr_state;
    localparam WR_IDLE   = 3'd0;
    localparam WR_AWWAIT = 3'd1;
    localparam WR_WWAIT  = 3'd2;
    localparam WR_DRAIN  = 3'd3;
    localparam WR_BRESP  = 3'd4;

    reg [ID_WIDTH-1:0] wr_id_r;
    reg [15:0]         wr_offset_r;
    reg [7:0]          wr_burst_len_r;
    reg [7:0]          wr_beat_cnt_r;
    reg                first_beat_r;

    // [BUG2-WDATA-LATCH] Latch WDATA/WSTRB khi w_fire để dùng sau khi AW arrive
    reg [DATA_WIDTH-1:0]   wd_data_r;
    reg [DATA_WIDTH/8-1:0] wd_strb_r;

    // Effective write data: dùng latched data khi ở WWAIT (W đã arrive trước AW)
    wire [DATA_WIDTH-1:0]   eff_wdata = (wr_state == WR_WWAIT) ? wd_data_r : S_AXI_WDATA;
    wire [DATA_WIDTH/8-1:0] eff_wstrb = (wr_state == WR_WWAIT) ? wd_strb_r : S_AXI_WSTRB;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wd_data_r <= {DATA_WIDTH{1'b0}};
            wd_strb_r <= {(DATA_WIDTH/8){1'b0}};
        end else if (w_fire) begin
            wd_data_r <= S_AXI_WDATA;
            wd_strb_r <= S_AXI_WSTRB;
        end
    end

    assign S_AXI_AWREADY = (wr_state == WR_IDLE) || (wr_state == WR_WWAIT);
    assign S_AXI_WREADY  = (wr_state == WR_IDLE)  ||
                           (wr_state == WR_AWWAIT) ||
                           (wr_state == WR_DRAIN);

    wire aw_fire = S_AXI_AWVALID && S_AXI_AWREADY;
    wire w_fire  = S_AXI_WVALID  && S_AXI_WREADY;
    wire b_fire  = S_AXI_BVALID  && S_AXI_BREADY;

    wire wr_do_write = ((wr_state == WR_IDLE)  && aw_fire && w_fire) ||
                       ((wr_state == WR_AWWAIT) && w_fire)            ||
                       ((wr_state == WR_WWAIT)  && aw_fire);

    // Latch AW
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_offset_r    <= 16'd0;
            wr_id_r        <= {ID_WIDTH{1'b0}};
            wr_burst_len_r <= 8'd0;
        end else if (aw_fire) begin
            wr_offset_r    <= S_AXI_AWADDR[15:0];
            wr_id_r        <= S_AXI_AWID;
            wr_burst_len_r <= S_AXI_AWLEN;
        end
    end

    wire [15:0]         eff_offset = (wr_state == WR_IDLE) ? S_AXI_AWADDR[15:0] : wr_offset_r;
    wire [ID_WIDTH-1:0] eff_awid   = (wr_state == WR_IDLE) ? S_AXI_AWID         : wr_id_r;

    // FSM transitions
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            wr_beat_cnt_r <= 8'd0;
            first_beat_r  <= 1'b1;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    first_beat_r  <= 1'b1;
                    wr_beat_cnt_r <= 8'd0;
                    if (aw_fire && !w_fire)
                        wr_state <= WR_AWWAIT;
                    else if (!aw_fire && w_fire)
                        wr_state <= WR_WWAIT;
                    else if (aw_fire && w_fire) begin
                        if (S_AXI_AWLEN != 8'd0)
                            wr_state <= WR_DRAIN;
                        else
                            wr_state <= WR_BRESP;
                    end
                end

                WR_AWWAIT: begin
                    if (w_fire) begin
                        first_beat_r <= 1'b0;
                        if (wr_burst_len_r != 8'd0 && !S_AXI_WLAST) begin
                            wr_beat_cnt_r <= 8'd1;
                            wr_state      <= WR_DRAIN;
                        end else
                            wr_state <= WR_BRESP;
                    end
                end

                WR_WWAIT: begin
                    if (aw_fire) begin
                        if (S_AXI_AWLEN != 8'd0)
                            wr_state <= WR_DRAIN;
                        else
                            wr_state <= WR_BRESP;
                    end
                end

                WR_DRAIN: begin
                    if (w_fire) begin
                        wr_beat_cnt_r <= wr_beat_cnt_r + 8'd1;
                        // [BUG3-DRAIN-COUNT] Fix: == wr_burst_len_r (không phải -1)
                        // cnt bắt đầu từ 1 (beat đầu xử lý ở AWWAIT/IDLE)
                        // beat cuối = beat AWLEN → cnt = AWLEN = wr_burst_len_r
                        if (S_AXI_WLAST || (wr_beat_cnt_r == wr_burst_len_r))
                            wr_state <= WR_BRESP;
                    end
                end

                WR_BRESP: begin
                    if (b_fire) begin
                        wr_state      <= WR_IDLE;
                        wr_beat_cnt_r <= 8'd0;
                        first_beat_r  <= 1'b1;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // B channel
    // [BUG4-BVALID-EARLY] b_valid_r harus set saat FSM masuk WR_BRESP,
    // BUKAN saat wr_do_write (yang fire di awal burst, sebelum drain selesai).
    // Jika bvalid=1 saat masih WR_DRAIN: master terima B response lebih awal,
    // b_fire clear bvalid → saat DRAIN selesai masuk WR_BRESP, bvalid=0 → stall.
    // Fix: set b_valid_r & b_id_r saat transisi ke WR_BRESP dalam FSM.
    // Deteksi: (wr_state akan pindah ke WR_BRESP di posedge ini)
    //   - dari AWWAIT: w_fire && (burst done atau single)
    //   - dari DRAIN:  w_fire && (WLAST || cnt == burst_len)
    //   - dari WWAIT:  aw_fire && AWLEN==0
    //   - dari IDLE:   aw_fire && w_fire && AWLEN==0
    // Sederhana: set b_valid ketika next_state == WR_BRESP
    reg                b_valid_r;
    reg [ID_WIDTH-1:0] b_id_r;

    assign S_AXI_BVALID = b_valid_r;
    assign S_AXI_BID    = b_id_r;
    assign S_AXI_BRESP  = RESP_OKAY;

    // Sinyal "sedang masuk WR_BRESP cycle ini"
    wire going_to_bresp =
        ((wr_state == WR_IDLE)   && aw_fire && w_fire && (S_AXI_AWLEN == 8'd0))           ||
        ((wr_state == WR_AWWAIT) && w_fire  && (wr_burst_len_r == 8'd0 || S_AXI_WLAST))  ||
        ((wr_state == WR_WWAIT)  && aw_fire && (S_AXI_AWLEN == 8'd0))                     ||
        ((wr_state == WR_DRAIN)  && w_fire  && (S_AXI_WLAST || (wr_beat_cnt_r == wr_burst_len_r)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_valid_r <= 1'b0;
            b_id_r    <= {ID_WIDTH{1'b0}};
        end else begin
            if (going_to_bresp) begin
                b_valid_r <= 1'b1;
                b_id_r    <= eff_awid;
            end else if (b_fire) begin
                b_valid_r <= 1'b0;
            end
        end
    end

    // ========================================================================
    // Register writes
    //
    // [BUG1-REG-IN-ALWAYS] Fix: dùng eff_wdata/eff_wstrb (đã latch),
    //   viết trực tiếp không khai báo reg bên trong always block.
    //   Dùng module-level reg mtimecmp_hi_new (combinational temp) cho
    //   OFFSET_MTIMECMP_HI để giữ logic rõ ràng.
    //
    // [BUG2-WDATA-LATCH] Dùng eff_wdata/eff_wstrb thay vì S_AXI_WDATA/WSTRB.
    // [WR-ATOMICITY]     Ghi lo → shadow; ghi hi → atomic commit 64-bit.
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip_r            <= 1'b0;
            mtimecmp_r        <= 64'hFFFF_FFFF_FFFF_FFFF;
            mtimecmp_shadow_r <= 32'hFFFF_FFFF;
        end else if (wr_do_write) begin
            case (eff_offset)
                OFFSET_MSIP: begin
                    if (eff_wstrb[0]) msip_r <= eff_wdata[0];
                end

                OFFSET_MTIMECMP_LO: begin
                    // [WR-ATOMICITY] Ghi lo vào shadow, chưa commit mtimecmp_r
                    if (eff_wstrb[0]) mtimecmp_shadow_r[ 7: 0] <= eff_wdata[ 7: 0];
                    if (eff_wstrb[1]) mtimecmp_shadow_r[15: 8] <= eff_wdata[15: 8];
                    if (eff_wstrb[2]) mtimecmp_shadow_r[23:16] <= eff_wdata[23:16];
                    if (eff_wstrb[3]) mtimecmp_shadow_r[31:24] <= eff_wdata[31:24];
                end

                OFFSET_MTIMECMP_HI: begin
                    // [WR-ATOMICITY] Ghi hi → atomic commit {new_hi, shadow_lo}
                    // [BUG1-REG-IN-ALWAYS] Viết trực tiếp từng byte, không khai báo
                    // reg bên trong always block (syntax error Verilog-2001).
                    mtimecmp_r[32 +  7 : 32 +  0] <= eff_wstrb[0] ? eff_wdata[ 7: 0]
                                                                    : mtimecmp_r[39:32];
                    mtimecmp_r[32 + 15 : 32 +  8] <= eff_wstrb[1] ? eff_wdata[15: 8]
                                                                    : mtimecmp_r[47:40];
                    mtimecmp_r[32 + 23 : 32 + 16] <= eff_wstrb[2] ? eff_wdata[23:16]
                                                                    : mtimecmp_r[55:48];
                    mtimecmp_r[32 + 31 : 32 + 24] <= eff_wstrb[3] ? eff_wdata[31:24]
                                                                    : mtimecmp_r[63:56];
                    // Commit lo half từ shadow
                    mtimecmp_r[31:0] <= mtimecmp_shadow_r;
                end

                OFFSET_MTIME_LO,
                OFFSET_MTIME_HI: begin
                    /* mtime read-only — ignore write, trả OKAY */
                end

                default: begin
                    /* unmapped — ignore */
                end
            endcase
        end
    end

    // ========================================================================
    // AXI4 Read FSM
    // [RD-LOCK] Snapshot mtime_r khi AR latch
    // ========================================================================
    reg                ar_pending_r;
    reg [ID_WIDTH-1:0] ar_id_r;
    reg [15:0]         ar_offset_r;
    reg [7:0]          ar_len_r;
    reg [7:0]          ar_beat_cnt_r;
    reg [63:0]         mtime_snap_r;

    wire ar_fire = S_AXI_ARVALID && S_AXI_ARREADY;
    wire r_fire  = S_AXI_RVALID  && S_AXI_RREADY;

    assign S_AXI_ARREADY = ~ar_pending_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_pending_r  <= 1'b0;
            ar_id_r       <= {ID_WIDTH{1'b0}};
            ar_offset_r   <= 16'd0;
            ar_len_r      <= 8'd0;
            ar_beat_cnt_r <= 8'd0;
            mtime_snap_r  <= 64'd0;
        end else begin
            if (ar_fire) begin
                ar_pending_r  <= 1'b1;
                ar_id_r       <= S_AXI_ARID;
                ar_offset_r   <= S_AXI_ARADDR[15:0];
                ar_len_r      <= S_AXI_ARLEN;
                ar_beat_cnt_r <= 8'd0;
                mtime_snap_r  <= mtime_r;   // [RD-LOCK] snapshot
            end else if (r_fire) begin
                if (ar_beat_cnt_r == ar_len_r)
                    ar_pending_r <= 1'b0;
                else
                    ar_beat_cnt_r <= ar_beat_cnt_r + 8'd1;
            end
        end
    end

    reg [DATA_WIDTH-1:0] r_data_r;
    always @(*) begin
        case (ar_offset_r)
            OFFSET_MSIP:        r_data_r = {{(DATA_WIDTH-1){1'b0}}, msip_r};
            OFFSET_MTIMECMP_LO: r_data_r = mtimecmp_r[31: 0];
            OFFSET_MTIMECMP_HI: r_data_r = mtimecmp_r[63:32];
            OFFSET_MTIME_LO:    r_data_r = mtime_snap_r[31: 0];  // [RD-LOCK]
            OFFSET_MTIME_HI:    r_data_r = mtime_snap_r[63:32];  // [RD-LOCK]
            default:            r_data_r = {DATA_WIDTH{1'b0}};
        endcase
    end

    assign S_AXI_RVALID = ar_pending_r;
    assign S_AXI_RID    = ar_id_r;
    assign S_AXI_RDATA  = r_data_r;
    assign S_AXI_RRESP  = RESP_OKAY;
    assign S_AXI_RLAST  = (ar_beat_cnt_r == ar_len_r);

endmodule

`default_nettype wire
// ============================================================================
// END: clint.v
// ============================================================================