// ============================================================================
// jtag_dtm.v — JTAG Debug Transport Module
//
// Kết nối jtag_tap (JTAG side) với DMI bus (riscv_dm side).
// Chuẩn: RISC-V External Debug Support v0.13.2
//
// IR registers:
//   0x01 = IDCODE   (32-bit): chip identification
//   0x10 = DTMCS    (32-bit): DTM control/status
//   0x11 = DMI      (41-bit): [40:34]=addr, [33:2]=data, [1:0]=op
//   0x1F = BYPASS   (1-bit):  JTAG bypass
//   other: BYPASS
//
// DMI op encoding:
//   2'b00 = NOP
//   2'b01 = READ   (addr → data return)
//   2'b10 = WRITE  (addr ← data)
//   2'b11 = reserved
//
// DTMCS bits:
//   [3:0]  = version (= 0x1 cho spec v0.13)
//   [9:4]  = abits   (= 7: địa chỉ DMI 7 bit)
//   [11:10]= dmistat (0=OK, 1=reserved, 2=fail, 3=busy)
//   [16]   = dmireset (write 1 to clear sticky error)
// ============================================================================

module jtag_dtm #(
    parameter IDCODE_VAL = 32'hDEAD_0001,  // Thay bằng JEDEC ID thực tế
    parameter ABITS      = 7               // DMI address bits
)(
    // ── JTAG interface (từ/tới pad) ───────────────────────────────────────
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output wire tdo,
    output wire tdo_en,

    // ── System clock domain ────────────────────────────────────────────────
    // DMI bus: jtag_dtm → riscv_dm
    // (async FIFO / 2FF sync không viết ở đây để giữ module đơn giản;
    //  trong SoC thực tế cần CDC nếu tck và clk khác miền)
    input  wire        clk,
    input  wire        rst_n,

    output reg  [ABITS-1:0]  dmi_addr,
    output reg  [31:0]       dmi_data_wr,
    output reg  [1:0]        dmi_op,
    output reg               dmi_req_valid,
    input  wire              dmi_req_ready,

    input  wire [31:0]       dmi_data_rd,
    input  wire [1:0]        dmi_rsp_op,    // 0=OK, 2=fail, 3=busy
    input  wire              dmi_rsp_valid,
    output wire              dmi_rsp_ready
);

    localparam IR_IDCODE = 5'h01;
    localparam IR_DTMCS  = 5'h10;
    localparam IR_DMI    = 5'h11;
    localparam IR_BYPASS = 5'h1F;

    // ── IR và DR length decoder ────────────────────────────────────────────
    wire [4:0] ir_reg;
    reg  [5:0] dr_len;
    reg  [40:0] dr_cap;  // data nạp vào DR khi Capture-DR

    always @(*) begin
        case (ir_reg)
            IR_BYPASS: begin dr_len = 6'd1;  dr_cap = 41'b0; end
            IR_IDCODE: begin dr_len = 6'd32; dr_cap = {9'b0, IDCODE_VAL}; end
            IR_DTMCS:  begin
                dr_len = 6'd32;
                // version=1, abits=7, dmistat=OK
                dr_cap = {9'b0, 16'b0, 1'b0, 1'b0, 2'b00,
                          ABITS[5:0], 4'h1};
            end
            IR_DMI:    begin dr_len = 6'd41; dr_cap = 41'b0; end
            default:   begin dr_len = 6'd1;  dr_cap = 41'b0; end
        endcase
    end

    // ── Instantiate TAP ────────────────────────────────────────────────────
    wire [40:0] dr_data_out;
    wire        dr_update_pulse;
    wire        dr_capture_pulse;
    wire        ir_update_pulse;

    jtag_tap #(
        .IR_LEN (5),
        .IDCODE (IDCODE_VAL)
    ) u_tap (
        .tck       (tck),
        .tms       (tms),
        .tdi       (tdi),
        .tdo       (tdo),
        .tdo_en    (tdo_en),

        .dr_data_in (dr_cap),
        .dr_len     (dr_len),
        .dr_data_out(dr_data_out),
        .dr_update  (dr_update_pulse),
        .dr_capture (dr_capture_pulse),

        .ir_reg     (ir_reg),
        .ir_update  (ir_update_pulse)
    );

    // ── DMI request: translate Update-DR (DMI) → DMI bus ──────────────────
    // Clock domain crossing: tck → clk
    // Simple approach: pulse stretcher (safe khi tck << clk, là trường hợp
    // thông thường: tck ≤ 25 MHz, clk = 100 MHz)
    reg dmi_update_tck;   // in tck domain
    reg [1:0] dmi_update_sync;  // sync FFs in clk domain

    always @(posedge tck)
        dmi_update_tck <= dr_update_pulse && (ir_reg == IR_DMI);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            dmi_update_sync <= 2'b00;
        else
            dmi_update_sync <= {dmi_update_sync[0], dmi_update_tck};
    end

    wire dmi_update_clk = dmi_update_sync[1];  // synchronized to clk

    // Latch DMI fields (in tck domain at Update-DR)
    reg [ABITS-1:0] dmi_addr_lat;
    reg [31:0]      dmi_data_lat;
    reg [1:0]       dmi_op_lat;

    always @(posedge tck) begin
        if (dr_update_pulse && ir_reg == IR_DMI) begin
            dmi_addr_lat <= dr_data_out[40:40-ABITS+1];
            dmi_data_lat <= dr_data_out[33:2];
            dmi_op_lat   <= dr_data_out[1:0];
        end
    end

    // Drive DMI bus in clk domain
    reg dmi_pending;
    assign dmi_rsp_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmi_req_valid <= 1'b0;
            dmi_pending   <= 1'b0;
        end else begin
            if (dmi_update_clk && !dmi_pending && dmi_op_lat != 2'b00) begin
                dmi_addr     <= dmi_addr_lat;
                dmi_data_wr  <= dmi_data_lat;
                dmi_op       <= dmi_op_lat;
                dmi_req_valid <= 1'b1;
                dmi_pending   <= 1'b1;
            end else if (dmi_req_valid && dmi_req_ready) begin
                dmi_req_valid <= 1'b0;
            end

            if (dmi_rsp_valid && dmi_pending) begin
                dmi_pending <= 1'b0;
            end
        end
    end

endmodule