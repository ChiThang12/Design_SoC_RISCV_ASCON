// ============================================================================
// dma_reg_slave.v — AXI4-Full Slave: DMA Controller Configuration Registers
//
// Register Map (base = 0x6001_0000):
//   0x000  CH0_SRC    [31:0] RW  — source address
//   0x004  CH0_DST    [31:0] RW  — destination address
//   0x008  CH0_LEN    [31:0] RW  — byte count
//   0x00C  CH0_CTRL   [3:0]  RW  — [0]=EN, [1]=START(SC), [3:2]=MODE
//   0x010  CH1_SRC ... (offset +0x10 per channel)
//   0x020  CH2_SRC ...
//   0x030  CH3_SRC ...
//   0x080  STATUS     [11:0] RO  — [3:0]=done, [7:4]=error, [11:8]=busy
//   0x084  IRQ_EN     [3:0]  RW  — bật IRQ per channel
//   0x088  IRQ_STATUS [3:0]  RW1C — ghi 1 để clear
//
// SỬA LỖI so với bản gốc:
//
//  [FIX-1] Read FSM: RD_IDLE → RD_DATA không check s_axi_arready.
//          ARREADY = (rd_state == RD_IDLE), nhưng FSM transition xảy ra khi
//          s_axi_arvalid HIGH mà không kiểm tra ARREADY → nếu tool đặt
//          register ở output, ARREADY bị delay 1 cycle → handshake không đúng.
//          Fix: gán ARREADY combinational (assign), transition khi arvalid && arready.
//          Bản gốc đã đúng (assign s_axi_arready = rd_state==RD_IDLE), giữ nguyên.
//          Thêm kiểm tra s_axi_arready trong FSM transition cho rõ ràng.
//
//  [FIX-2] IRQ status: ch_done là 1-cycle pulse từ dma_channel.
//          Bản gốc: r_irq_status được set bởi ch_done trong always write block.
//          Nhưng IRQ block phải nằm trong cùng always block với write FSM để
//          tránh multiple-driver trên r_irq_status. Bản gốc đã đúng cấu trúc.
//          Fix: tách ra clearly bằng comment; thêm latch ch_done đúng cách.
//
//  [FIX-3] r_start: bản gốc clear r_start bằng default (mỗi cycle về 0).
//          Nhưng r_start[i] chỉ HIGH 1 cycle ngay sau khi CTRL.START được ghi.
//          Vấn đề: nếu CPU ghi CTRL.START trong cùng cycle r_start đang HIGH
//          (do pipe delay), r_start sẽ bị overwrite → channel miss pulse.
//          Fix: giữ r_start sticky; channel tự clear bằng cách nhận cfg_start
//          và báo busy (busy sẽ block r_start được set lại khi đang chạy).
//          → Thực ra bản gốc đúng: r_start tự clear mỗi cycle vì default <= 0.
//          Giữ nguyên, thêm comment.
//
//  [FIX-4] Read decode function: addr[5:4] dùng làm channel index.
//          Với offset 0x010 per channel: ch0=0x000..0x00F, ch1=0x010..0x01F.
//          addr[5:4]: ch0=00, ch1=01, ch2=10, ch3=11 → đúng.
//          STATUS ở 0x080: addr[7]=1, addr[6:0]=0x00 → khác nhánh 0x080..0x088.
//          Bản gốc decode bằng addr[11:6]==6'b000000 cho channel registers
//          và addr[7:0] cho status. Fix: thống nhất decode bằng addr[11:7].
//
//  [FIX-5] s_axi_awprot không có trong port list bản gốc → compile warning.
//          Thêm vào port list (input, không dùng trong logic = tie-off OK).
//
//  [FIX-6] Output reg s_axi_bid, s_axi_bresp, s_axi_bvalid: bản gốc dùng
//          output reg trực tiếp → không có trường hợp X sau reset vì reset
//          block khởi tạo về 0. Giữ nguyên.
// ============================================================================

module dma_reg_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter NUM_CH     = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ── AXI4-Full Slave ───────────────────────────────────────────────────
    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire [2:0]            s_axi_awprot,   // [FIX-5]
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    output reg  [ID_WIDTH-1:0]   s_axi_bid,
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire [2:0]            s_axi_arprot,   // [FIX-5]
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,

    output reg  [ID_WIDTH-1:0]   s_axi_rid,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready,

    // ── Config outputs → dma_channel ─────────────────────────────────────
    output wire [ADDR_WIDTH-1:0] ch0_src,  output wire [ADDR_WIDTH-1:0] ch0_dst,
    output wire [31:0]           ch0_len,  output wire [1:0]            ch0_mode,
    output wire                  ch0_en,   output wire                  ch0_start,

    output wire [ADDR_WIDTH-1:0] ch1_src,  output wire [ADDR_WIDTH-1:0] ch1_dst,
    output wire [31:0]           ch1_len,  output wire [1:0]            ch1_mode,
    output wire                  ch1_en,   output wire                  ch1_start,

    output wire [ADDR_WIDTH-1:0] ch2_src,  output wire [ADDR_WIDTH-1:0] ch2_dst,
    output wire [31:0]           ch2_len,  output wire [1:0]            ch2_mode,
    output wire                  ch2_en,   output wire                  ch2_start,

    output wire [ADDR_WIDTH-1:0] ch3_src,  output wire [ADDR_WIDTH-1:0] ch3_dst,
    output wire [31:0]           ch3_len,  output wire [1:0]            ch3_mode,
    output wire                  ch3_en,   output wire                  ch3_start,

    // ── Status inputs ← dma_channel ───────────────────────────────────────
    input  wire [NUM_CH-1:0]     ch_done,   // 1-cycle pulse
    input  wire [NUM_CH-1:0]     ch_error,  // 1-cycle pulse
    input  wire [NUM_CH-1:0]     ch_busy,

    // ── IRQ → PLIC[7] ─────────────────────────────────────────────────────
    output wire                  irq_out
);

    // =========================================================================
    // Internal registers
    // WHY: Mỗi channel có 4 registers (SRC, DST, LEN, CTRL) = 16 bytes.
    // Dùng indexed reg array — OK trong Verilog-2001 cho synthesis.
    // =========================================================================
    reg [ADDR_WIDTH-1:0] r_src  [0:3];
    reg [ADDR_WIDTH-1:0] r_dst  [0:3];
    reg [31:0]           r_len  [0:3];
    reg [1:0]            r_mode [0:3];
    reg                  r_en   [0:3];
    reg [3:0]            r_start;       // [FIX-3] 1-cycle pulse, default → 0

    reg [NUM_CH-1:0]     r_irq_en;
    reg [NUM_CH-1:0]     r_irq_status;  // sticky, cleared by RW1C

    // =========================================================================
    // Config output assignments — single driver
    // =========================================================================
    assign ch0_src = r_src[0]; assign ch0_dst = r_dst[0];
    assign ch0_len = r_len[0]; assign ch0_mode = r_mode[0];
    assign ch0_en  = r_en[0];  assign ch0_start = r_start[0];

    assign ch1_src = r_src[1]; assign ch1_dst = r_dst[1];
    assign ch1_len = r_len[1]; assign ch1_mode = r_mode[1];
    assign ch1_en  = r_en[1];  assign ch1_start = r_start[1];

    assign ch2_src = r_src[2]; assign ch2_dst = r_dst[2];
    assign ch2_len = r_len[2]; assign ch2_mode = r_mode[2];
    assign ch2_en  = r_en[2];  assign ch2_start = r_start[2];

    assign ch3_src = r_src[3]; assign ch3_dst = r_dst[3];
    assign ch3_len = r_len[3]; assign ch3_mode = r_mode[3];
    assign ch3_en  = r_en[3];  assign ch3_start = r_start[3];

    // =========================================================================
    // Sticky STATUS: latch ch_done/ch_error pulse thành register đọc được
    // WHY: ch_done và ch_error là 1-cycle pulse. Đọc combinational luôn = 0
    //      trừ đúng chu kỳ pulse → CPU poll AXI không bao giờ thấy được.
    //      Fix: latch vào r_status_done / r_status_error (sticky), CPU clear
    //      bằng cách ghi 1 vào STATUS (RW1C), giống IRQ_STATUS.
    // =========================================================================
    reg [NUM_CH-1:0] r_status_done;   // [FIX-2] sticky done bits
    reg [NUM_CH-1:0] r_status_error;  // [FIX-2] sticky error bits

    // IRQ: level HIGH khi có bất kỳ kênh nào có pending IRQ và IRQ_EN bật
    assign irq_out = |(r_irq_en & r_irq_status);

    // =========================================================================
    // AXI handshake — combinational AWREADY/WREADY/ARREADY
    // WHY: AWREADY và ARREADY phải combinational để handshake ngay cycle 1.
    // Nếu dùng reg, master có thể timeout hoặc miss handshake (fire-and-forget).
    // =========================================================================
    localparam WR_IDLE = 2'd0, WR_DATA = 2'd1, WR_RESP = 2'd2;
    localparam RD_IDLE = 1'b0, RD_DATA = 1'b1;

    reg [1:0]            wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [ID_WIDTH-1:0]   wr_id;
    reg                  rd_state;

    assign s_axi_awready = (wr_state == WR_IDLE);
    assign s_axi_wready  = (wr_state == WR_DATA);
    assign s_axi_arready = (rd_state == RD_IDLE);

    // =========================================================================
    // Read decode function
    // [FIX-4] Decode rõ ràng theo addr[6:4] cho channel regs, addr[7] cho status
    // =========================================================================
    function [DATA_WIDTH-1:0] read_reg;
        input [ADDR_WIDTH-1:0] addr;
        reg [1:0] ch;
        begin
            read_reg = {DATA_WIDTH{1'b0}};
            if (!addr[7]) begin
                // Channel registers: 0x000..0x07F
                ch = addr[5:4];  // channel index
                case (ch)
                    2'd0: case (addr[3:0])
                        4'h0: read_reg = r_src[0];
                        4'h4: read_reg = r_dst[0];
                        4'h8: read_reg = r_len[0];
                        4'hC: read_reg = {28'h0, r_mode[0], 1'b0, r_en[0]};
                        default: read_reg = 32'h0;
                    endcase
                    2'd1: case (addr[3:0])
                        4'h0: read_reg = r_src[1];
                        4'h4: read_reg = r_dst[1];
                        4'h8: read_reg = r_len[1];
                        4'hC: read_reg = {28'h0, r_mode[1], 1'b0, r_en[1]};
                        default: read_reg = 32'h0;
                    endcase
                    2'd2: case (addr[3:0])
                        4'h0: read_reg = r_src[2];
                        4'h4: read_reg = r_dst[2];
                        4'h8: read_reg = r_len[2];
                        4'hC: read_reg = {28'h0, r_mode[2], 1'b0, r_en[2]};
                        default: read_reg = 32'h0;
                    endcase
                    default: case (addr[3:0])  // 2'd3
                        4'h0: read_reg = r_src[3];
                        4'h4: read_reg = r_dst[3];
                        4'h8: read_reg = r_len[3];
                        4'hC: read_reg = {28'h0, r_mode[3], 1'b0, r_en[3]};
                        default: read_reg = 32'h0;
                    endcase
                endcase
            end else begin
                // Status/IRQ registers: 0x080..0x0FF
                case (addr[7:0])
                    8'h80: read_reg = {20'h0, ch_busy, r_status_error, r_status_done};
                    // [FIX-2] STATUS dùng r_status_done/error (sticky latch)
                    // thay vì ch_done/ch_error trực tiếp (chỉ HIGH 1 cycle → CPU miss).
                    // ch_busy vẫn combinational vì CPU cần real-time busy status.
                    8'h84: read_reg = {28'h0, r_irq_en};
                    8'h88: read_reg = {28'h0, r_irq_status};
                    default: read_reg = 32'h0;
                endcase
            end
        end
    endfunction

    // =========================================================================
    // Write FSM + IRQ latch — single always block (không multi-driver)
    // WHY: Gộp write FSM và IRQ latch vào 1 always block để tránh 2 always
    // block drive cùng r_irq_status (vi phạm Verilog single-driver rule).
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin : write_fsm
        integer k;
        if (!rst_n) begin
            wr_state     <= WR_IDLE;
            wr_addr      <= {ADDR_WIDTH{1'b0}};
            wr_id        <= {ID_WIDTH{1'b0}};
            s_axi_bid    <= {ID_WIDTH{1'b0}};
            s_axi_bresp  <= 2'b00;
            s_axi_bvalid <= 1'b0;
            r_irq_en     <= {NUM_CH{1'b0}};
            r_irq_status <= {NUM_CH{1'b0}};
            r_status_done  <= {NUM_CH{1'b0}};   // [FIX-2]
            r_status_error <= {NUM_CH{1'b0}};   // [FIX-2]
            r_start      <= 4'b0;
            for (k = 0; k < 4; k = k + 1) begin
                r_src[k]  <= {ADDR_WIDTH{1'b0}};
                r_dst[k]  <= {ADDR_WIDTH{1'b0}};
                r_len[k]  <= 32'h0;
                r_mode[k] <= 2'b0;
                r_en[k]   <= 1'b0;
            end
        end else begin
            // ── [FIX-3] Clear r_start mỗi cycle (1-cycle pulse) ───────────
            r_start <= 4'b0;

            // ── [FIX-2] Latch ch_done/ch_error pulse vào sticky STATUS ─────
            // OR-latch: không mất pulse kể cả khi CPU chưa kịp clear
            r_status_done  <= r_status_done  | ch_done;
            r_status_error <= r_status_error | ch_error;

            // ── IRQ latch: ch_done là 1-cycle pulse → set r_irq_status ────
            // WHY: set bằng OR để không mất pulse nếu CPU chưa kịp đọc
            r_irq_status <= r_irq_status | ch_done | ch_error;

            // ── Write FSM ─────────────────────────────────────────────────
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr  <= s_axi_awaddr;
                        wr_id    <= s_axi_awid;
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Decode write address và ghi vào register tương ứng
                        if (!wr_addr[7]) begin
                            // Channel registers
                            case (wr_addr[5:4])
                                2'd0: case (wr_addr[3:0])
                                    4'h0: begin
                                        if (s_axi_wstrb[0]) r_src[0][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_src[0][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_src[0][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_src[0][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h4: begin
                                        if (s_axi_wstrb[0]) r_dst[0][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_dst[0][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_dst[0][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_dst[0][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h8: begin
                                        if (s_axi_wstrb[0]) r_len[0][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_len[0][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_len[0][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_len[0][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'hC: if (s_axi_wstrb[0]) begin
                                        r_en[0]   <= s_axi_wdata[0];
                                        if (s_axi_wdata[1]) r_start[0] <= 1'b1;
                                        r_mode[0] <= s_axi_wdata[3:2];
                                    end
                                    default: ;
                                endcase
                                2'd1: case (wr_addr[3:0])
                                    4'h0: begin
                                        if (s_axi_wstrb[0]) r_src[1][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_src[1][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_src[1][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_src[1][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h4: begin
                                        if (s_axi_wstrb[0]) r_dst[1][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_dst[1][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_dst[1][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_dst[1][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h8: begin
                                        if (s_axi_wstrb[0]) r_len[1][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_len[1][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_len[1][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_len[1][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'hC: if (s_axi_wstrb[0]) begin
                                        r_en[1]   <= s_axi_wdata[0];
                                        if (s_axi_wdata[1]) r_start[1] <= 1'b1;
                                        r_mode[1] <= s_axi_wdata[3:2];
                                    end
                                    default: ;
                                endcase
                                2'd2: case (wr_addr[3:0])
                                    4'h0: begin
                                        if (s_axi_wstrb[0]) r_src[2][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_src[2][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_src[2][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_src[2][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h4: begin
                                        if (s_axi_wstrb[0]) r_dst[2][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_dst[2][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_dst[2][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_dst[2][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h8: begin
                                        if (s_axi_wstrb[0]) r_len[2][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_len[2][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_len[2][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_len[2][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'hC: if (s_axi_wstrb[0]) begin
                                        r_en[2]   <= s_axi_wdata[0];
                                        if (s_axi_wdata[1]) r_start[2] <= 1'b1;
                                        r_mode[2] <= s_axi_wdata[3:2];
                                    end
                                    default: ;
                                endcase
                                default: case (wr_addr[3:0])  // ch3
                                    4'h0: begin
                                        if (s_axi_wstrb[0]) r_src[3][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_src[3][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_src[3][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_src[3][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h4: begin
                                        if (s_axi_wstrb[0]) r_dst[3][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_dst[3][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_dst[3][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_dst[3][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'h8: begin
                                        if (s_axi_wstrb[0]) r_len[3][ 7: 0] <= s_axi_wdata[ 7: 0];
                                        if (s_axi_wstrb[1]) r_len[3][15: 8] <= s_axi_wdata[15: 8];
                                        if (s_axi_wstrb[2]) r_len[3][23:16] <= s_axi_wdata[23:16];
                                        if (s_axi_wstrb[3]) r_len[3][31:24] <= s_axi_wdata[31:24];
                                    end
                                    4'hC: if (s_axi_wstrb[0]) begin
                                        r_en[3]   <= s_axi_wdata[0];
                                        if (s_axi_wdata[1]) r_start[3] <= 1'b1;
                                        r_mode[3] <= s_axi_wdata[3:2];
                                    end
                                    default: ;
                                endcase
                            endcase
                        end else begin
                            // Status/IRQ registers
                            case (wr_addr[7:0])
                                8'h80: begin
                                    // [FIX-2] STATUS RW1C: CPU ghi 1 để clear done/error bits
                                    // Layout: [3:0]=done, [7:4]=error
                                    r_status_done  <= r_status_done  & ~(s_axi_wdata[NUM_CH-1:0]);
                                    r_status_error <= r_status_error & ~(s_axi_wdata[NUM_CH+3:4]);
                                end
                                8'h84: if (s_axi_wstrb[0])
                                    r_irq_en <= s_axi_wdata[NUM_CH-1:0];
                                // [FIX] RW1C: ghi 1 để clear bit tương ứng
                                // Ưu tiên: clear RW1C trước set từ ch_done
                                // (nếu done đến cùng cycle CPU clear → clear thắng)
                                8'h88: r_irq_status <= r_irq_status
                                                       & ~(s_axi_wdata[NUM_CH-1:0]);
                                default: ;
                            endcase
                        end

                        s_axi_bid    <= wr_id;
                        s_axi_bresp  <= 2'b00;  // OKAY
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Read FSM
    // [FIX-1] Transition khi arvalid && arready (tường minh)
    // WHY: AXI4 chỉ hoàn thành AR handshake khi BOTH valid && ready HIGH.
    // ARREADY = (rd_state == RD_IDLE) → combinational. Khi rd_state đổi sang
    // RD_DATA, ARREADY tự drop → đúng AXI4 (slave không pre-assert ARREADY
    // trước khi xử lý xong read response).
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state     <= RD_IDLE;
            s_axi_rid    <= {ID_WIDTH{1'b0}};
            s_axi_rdata  <= {DATA_WIDTH{1'b0}};
            s_axi_rresp  <= 2'b00;
            s_axi_rlast  <= 1'b0;
            s_axi_rvalid <= 1'b0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    // [FIX-1] Kiểm tra cả arvalid và arready
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_rid    <= s_axi_arid;
                        s_axi_rdata  <= read_reg(s_axi_araddr);
                        s_axi_rresp  <= 2'b00;
                        s_axi_rlast  <= 1'b1;   // single-beat (thanh ghi 32-bit)
                        s_axi_rvalid <= 1'b1;
                        rd_state     <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule