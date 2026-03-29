// ============================================================================
// jtag_tap.v — JTAG TAP Controller (IEEE 1149.1)
//
// 16-state TAP state machine theo chuẩn JTAG.
// Điều khiển bởi TMS. Dữ liệu vào/ra qua TDI/TDO.
//
// IR length = 5 bits (đủ encode 0x01=IDCODE, 0x10=DTMCS, 0x11=DMI, 0x1F=BYPASS)
// DR length phụ thuộc IR hiện tại: BYPASS=1, IDCODE=32, DTMCS=32, DMI=41
//
// Outputs:
//   capture_dr, shift_dr, update_dr  — kích hoạt DR operations
//   capture_ir, shift_ir, update_ir  — kích hoạt IR operations
//   tdo_en  — enable TDO output (chỉ HIGH khi Shift-DR hoặc Shift-IR)
// ============================================================================

module jtag_tap #(
    parameter IR_LEN    = 5,
    parameter IDCODE    = 32'hDEAD_BEEF   // thay bằng JEDEC ID thực
)(
    // ── JTAG pads ─────────────────────────────────────────────────────────
    input  wire tck,
    input  wire tms,
    input  wire tdi,
    output reg  tdo,
    output wire tdo_en,   // active-high: drive TDO pad

    // ── DR data interface (từ jtag_dtm) ───────────────────────────────────
    input  wire [40:0] dr_data_in,   // data nạp khi Capture-DR
    input  wire [5:0]  dr_len,       // số bit của DR hiện tại (1..41)
    output wire [40:0] dr_data_out,  // data sau Shift-DR (tại Update-DR)
    output wire        dr_update,    // pulse 1 cycle: Update-DR
    output wire        dr_capture,   // pulse 1 cycle: Capture-DR

    // ── IR output (để jtag_dtm biết register nào đang chọn) ───────────────
    output reg  [IR_LEN-1:0] ir_reg,     // IR sau Update-IR
    output wire              ir_update   // pulse 1 cycle: Update-IR
);

    // ── TAP state encoding ─────────────────────────────────────────────────
    localparam [3:0]
        TEST_LOGIC_RESET = 4'h0,
        RUN_TEST_IDLE    = 4'h1,
        SELECT_DR        = 4'h2,
        CAPTURE_DR       = 4'h3,
        SHIFT_DR         = 4'h4,
        EXIT1_DR         = 4'h5,
        PAUSE_DR         = 4'h6,
        EXIT2_DR         = 4'h7,
        UPDATE_DR        = 4'h8,
        SELECT_IR        = 4'h9,
        CAPTURE_IR       = 4'hA,
        SHIFT_IR         = 4'hB,
        EXIT1_IR         = 4'hC,
        PAUSE_IR         = 4'hD,
        EXIT2_IR         = 4'hE,
        UPDATE_IR        = 4'hF;

    reg [3:0] state;
    reg [3:0] next_state;

    // ── Next-state logic (combinational) ──────────────────────────────────
    always @(*) begin
        case (state)
            TEST_LOGIC_RESET: next_state = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    next_state = tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_DR:        next_state = tms ? SELECT_IR        : CAPTURE_DR;
            CAPTURE_DR:       next_state = tms ? EXIT1_DR         : SHIFT_DR;
            SHIFT_DR:         next_state = tms ? EXIT1_DR         : SHIFT_DR;
            EXIT1_DR:         next_state = tms ? UPDATE_DR        : PAUSE_DR;
            PAUSE_DR:         next_state = tms ? EXIT2_DR         : PAUSE_DR;
            EXIT2_DR:         next_state = tms ? UPDATE_DR        : SHIFT_DR;
            UPDATE_DR:        next_state = tms ? SELECT_DR        : RUN_TEST_IDLE;
            SELECT_IR:        next_state = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       next_state = tms ? EXIT1_IR         : SHIFT_IR;
            SHIFT_IR:         next_state = tms ? EXIT1_IR         : SHIFT_IR;
            EXIT1_IR:         next_state = tms ? UPDATE_IR        : PAUSE_IR;
            PAUSE_IR:         next_state = tms ? EXIT2_IR         : PAUSE_IR;
            EXIT2_IR:         next_state = tms ? UPDATE_IR        : SHIFT_IR;
            UPDATE_IR:        next_state = tms ? SELECT_DR        : RUN_TEST_IDLE;
            default:          next_state = TEST_LOGIC_RESET;
        endcase
    end

    // ── State register (clocked on rising TCK) ────────────────────────────
    always @(posedge tck)
        state <= next_state;

    // ── IR shift register ──────────────────────────────────────────────────
    reg [IR_LEN-1:0] ir_shift;

    always @(posedge tck) begin
        case (state)
            CAPTURE_IR: ir_shift <= {{(IR_LEN-2){1'b0}}, 2'b01};  // capture pattern
            SHIFT_IR:   ir_shift <= {tdi, ir_shift[IR_LEN-1:1]};  // shift LSB first
            UPDATE_IR:  ir_reg   <= ir_shift;
            default: ;
        endcase
    end

    // ── DR shift register (max 41 bits for DMI) ────────────────────────────
    reg [40:0] dr_shift;
    reg [40:0] dr_update_reg;

    always @(posedge tck) begin
        case (state)
            CAPTURE_DR: dr_shift <= dr_data_in;
            SHIFT_DR:   dr_shift <= {tdi, dr_shift[40:1]};  // shift LSB first
            UPDATE_DR:  dr_update_reg <= dr_shift;
            default: ;
        endcase
    end

    assign dr_data_out = dr_update_reg;
    assign dr_update   = (state == UPDATE_DR);
    assign dr_capture  = (state == CAPTURE_DR);
    assign ir_update   = (state == UPDATE_IR);

    // ── TDO (clocked on falling TCK per JTAG spec) ────────────────────────
    always @(negedge tck) begin
        if (state == SHIFT_DR)
            tdo <= dr_shift[0];
        else if (state == SHIFT_IR)
            tdo <= ir_shift[0];
        else
            tdo <= 1'b0;
    end

    assign tdo_en = (state == SHIFT_DR) || (state == SHIFT_IR);

endmodule