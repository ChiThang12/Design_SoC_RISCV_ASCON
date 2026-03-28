// ============================================================================
// dma_arbiter.v — Round-Robin Arbitration cho 4 kênh DMA
//
// SỬA LỖI so với bản gốc:
//
//  [FIX-1] Verilog integer dùng trong expression có modulo với reg signal:
//          (rd_last_grant + 1 + i) % NUM_CH
//          → Khi rd_last_grant là reg [1:0] và i là integer, Verilog-2001
//          expand lên 32-bit trước modulo → kết quả đúng, nhưng tool cảnh
//          báo "implicit conversion" và synthesis có thể tạo full 32-bit
//          divider. Fix: dùng lookup table rõ ràng thay vì modulo.
//
//  [FIX-2] Combinational loop tiềm ẩn: rd_next_grant dùng rd_last_grant
//          (reg) và rd_req (input). Nếu công cụ tổng hợp không nhận ra
//          điều này là thuần combinational, có thể tạo latch.
//          Fix: thêm default assignment + đảm bảo mọi path assign rd_next_grant.
//
//  [FIX-3] rd_grant không clear khi kênh release rồi request lại ngay.
//          Bug: rd_busy=1, rd_grant=0001, rd_rel[0]=1 → rd_busy=0, rd_grant=0.
//          Cycle sau: rd_req[0]=1 ngay → rd_grant phải re-arbitrate.
//          Đây là behavior đúng, giữ nguyên nhưng thêm comment rõ hơn.
//
//  [FIX-4] Đặt tên rd_next_grant thành wire (không phải reg) để rõ ràng
//          đây là combinational. Tool Verilog-2001 chấp nhận reg trong always@(*)
//          nhưng wire semantics rõ hơn trong code review.
//          → Giữ là reg vì cần assign trong always@(*) — đây là Verilog style
//          đúng cho combinational logic.
//
// WHY Round-Robin:
//   Nếu ch0 luôn transfer lớn, nó sẽ chiếm bus liên tục → ch1/ch2/ch3 stall.
//   Round-robin đảm bảo sau mỗi grant, ưu tiên xoay sang kênh tiếp theo.
//   "Không cắt burst": một khi kênh được grant, giữ đến khi kênh gửi rel.
//   Điều này tránh AXI ID conflict và simplify channel FSM.
// ============================================================================

module dma_arbiter #(
    parameter NUM_CH = 4
)(
    input  wire clk,
    input  wire rst_n,

    // ── Requests từ các kênh ──────────────────────────────────────────────
    input  wire [NUM_CH-1:0] rd_req,
    output reg  [NUM_CH-1:0] rd_grant,
    input  wire [NUM_CH-1:0] rd_rel,     // release signal từ channel

    input  wire [NUM_CH-1:0] wr_req,
    output reg  [NUM_CH-1:0] wr_grant,
    input  wire [NUM_CH-1:0] wr_rel
);

    // =========================================================================
    // Round-Robin Read Arbiter
    // =========================================================================
    reg [1:0] rd_last_grant;  // index kênh được grant lần trước (0–3)
    reg       rd_busy;        // 1 = bus đang bị giữ

    // [FIX-1] Dùng lookup table thay vì modulo với variable
    // rd_next: kênh nào được grant tiếp theo dựa trên rd_last_grant
    reg [NUM_CH-1:0] rd_next_grant;

    // WHY: always@(*) → synthesis tool nhận ra đây là combinational logic.
    // Mọi output (rd_next_grant) phải được gán trong mọi branch → không latch.
    always @(*) begin
        rd_next_grant = {NUM_CH{1'b0}};  // [FIX-2] default = no grant

        // Lookup table cho 4 kênh: scan theo thứ tự xoay từ rd_last_grant+1
        // Thứ tự ưu tiên (theo rd_last_grant):
        //   0→ scan: 1,2,3,0    1→ scan: 2,3,0,1    2→ scan: 3,0,1,2    3→ scan: 0,1,2,3
        case (rd_last_grant)
            2'd0: begin
                if      (rd_req[1]) rd_next_grant = 4'b0010;
                else if (rd_req[2]) rd_next_grant = 4'b0100;
                else if (rd_req[3]) rd_next_grant = 4'b1000;
                else if (rd_req[0]) rd_next_grant = 4'b0001;
            end
            2'd1: begin
                if      (rd_req[2]) rd_next_grant = 4'b0100;
                else if (rd_req[3]) rd_next_grant = 4'b1000;
                else if (rd_req[0]) rd_next_grant = 4'b0001;
                else if (rd_req[1]) rd_next_grant = 4'b0010;
            end
            2'd2: begin
                if      (rd_req[3]) rd_next_grant = 4'b1000;
                else if (rd_req[0]) rd_next_grant = 4'b0001;
                else if (rd_req[1]) rd_next_grant = 4'b0010;
                else if (rd_req[2]) rd_next_grant = 4'b0100;
            end
            default: begin  // 2'd3
                if      (rd_req[0]) rd_next_grant = 4'b0001;
                else if (rd_req[1]) rd_next_grant = 4'b0010;
                else if (rd_req[2]) rd_next_grant = 4'b0100;
                else if (rd_req[3]) rd_next_grant = 4'b1000;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_grant      <= {NUM_CH{1'b0}};
            rd_last_grant <= 2'd3;  // init: ưu tiên ban đầu cho ch0
            rd_busy       <= 1'b0;
        end else begin
            if (!rd_busy) begin
                // Bus rảnh → arbitrate nếu có request
                if (|rd_req) begin
                    rd_grant  <= rd_next_grant;
                    rd_busy   <= 1'b1;
                    // Latch winner index để round-robin lần sau
                    // WHY: phải latch index chứ không latch rd_next_grant
                    // vì cycle sau rd_req có thể thay đổi
                    case (rd_next_grant)
                        4'b0001: rd_last_grant <= 2'd0;
                        4'b0010: rd_last_grant <= 2'd1;
                        4'b0100: rd_last_grant <= 2'd2;
                        default: rd_last_grant <= 2'd3;
                    endcase
                end
            end else begin
                // Bus bận → chờ kênh được grant gửi release
                // WHY: rd_grant & rd_rel → AND để chỉ release khi đúng kênh được grant
                // gửi rel (không phải kênh khác gửi nhầm)
                if (|(rd_grant & rd_rel)) begin
                    rd_grant <= {NUM_CH{1'b0}};
                    rd_busy  <= 1'b0;
                    // rd_last_grant giữ nguyên → round-robin từ kênh vừa release
                end
            end
        end
    end

    // =========================================================================
    // Round-Robin Write Arbiter (đối xứng với read)
    // WHY: Read bus và Write bus độc lập trong AXI4 (AR và AW channel tách biệt).
    // Cho phép 2 kênh khác nhau đọc và ghi cùng lúc → tăng throughput.
    // =========================================================================
    reg [1:0] wr_last_grant;
    reg       wr_busy;
    reg [NUM_CH-1:0] wr_next_grant;

    always @(*) begin
        wr_next_grant = {NUM_CH{1'b0}};  // [FIX-2] default

        case (wr_last_grant)
            2'd0: begin
                if      (wr_req[1]) wr_next_grant = 4'b0010;
                else if (wr_req[2]) wr_next_grant = 4'b0100;
                else if (wr_req[3]) wr_next_grant = 4'b1000;
                else if (wr_req[0]) wr_next_grant = 4'b0001;
            end
            2'd1: begin
                if      (wr_req[2]) wr_next_grant = 4'b0100;
                else if (wr_req[3]) wr_next_grant = 4'b1000;
                else if (wr_req[0]) wr_next_grant = 4'b0001;
                else if (wr_req[1]) wr_next_grant = 4'b0010;
            end
            2'd2: begin
                if      (wr_req[3]) wr_next_grant = 4'b1000;
                else if (wr_req[0]) wr_next_grant = 4'b0001;
                else if (wr_req[1]) wr_next_grant = 4'b0010;
                else if (wr_req[2]) wr_next_grant = 4'b0100;
            end
            default: begin
                if      (wr_req[0]) wr_next_grant = 4'b0001;
                else if (wr_req[1]) wr_next_grant = 4'b0010;
                else if (wr_req[2]) wr_next_grant = 4'b0100;
                else if (wr_req[3]) wr_next_grant = 4'b1000;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_grant      <= {NUM_CH{1'b0}};
            wr_last_grant <= 2'd3;
            wr_busy       <= 1'b0;
        end else begin
            if (!wr_busy) begin
                if (|wr_req) begin
                    wr_grant  <= wr_next_grant;
                    wr_busy   <= 1'b1;
                    case (wr_next_grant)
                        4'b0001: wr_last_grant <= 2'd0;
                        4'b0010: wr_last_grant <= 2'd1;
                        4'b0100: wr_last_grant <= 2'd2;
                        default: wr_last_grant <= 2'd3;
                    endcase
                end
            end else begin
                if (|(wr_grant & wr_rel)) begin
                    wr_grant <= {NUM_CH{1'b0}};
                    wr_busy  <= 1'b0;
                end
            end
        end
    end

endmodule