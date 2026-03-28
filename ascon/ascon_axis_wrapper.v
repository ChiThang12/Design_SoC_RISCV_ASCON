// ============================================================================
// Module: ascon_AXIS_WRAPPER  (v10 — remove double-include)
//
// FIX vs v9:
//   FIX-BUG4: Xóa `include "ascon/rtl/ascon_CORE.v"
//             ascon_CORE phải được compile TRƯỚC file này qua filelist.
//             Giữ `include bên trong sẽ gây "module redefinition" error
//             khi ascon_top.v instantiate cả u_axis lẫn u_core_cpu.
//
// STREAM ORDER:
//   beat 0 : KEY[127:64]    (IS_KEY_HI)
//   beat 1 : KEY[63:0]      (IS_KEY_LO)
//   beat 2 : NONCE[127:64]  (IS_NONCE_HI)
//   beat 3 : NONCE[63:0]    (IS_NONCE_LO)
//   beat 4 : AD[127:64]     (IS_AD_HI)
//   beat 5 : AD[63:0]+last  (IS_AD_LO)
//   beat 6 : PT[127:64]     (IS_PT_HI)
//   beat 7 : PT[63:0]+last  (IS_PT_LO)
// ============================================================================

// FIX-BUG4: ascon_CORE KHÔNG được `include ở đây.
// Compile filelist phải đảm bảo ascon_CORE.v được compile TRƯỚC file này.
// `include "ascon/rtl/ascon_CORE.v"
module ascon_AXIS_WRAPPER #(
    parameter G_COMB_RND_128  = 6,
    parameter G_COMB_RND_128A = 4,
    parameter G_SBOX_PIPELINE = 0,  // PERMUTATION v8 chỉ hỗ trợ =0
    parameter G_DUAL_RATE     = 1,
    parameter G_AXI_DATA_W    = 64
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode,
    input  wire        enc_dec,

    input  wire [6:0]  i_ad_len,
    input  wire [6:0]  i_data_len,

    input  wire [G_AXI_DATA_W-1:0] s_axis_tdata,
    input  wire                    s_axis_tvalid,
    input  wire                    s_axis_tlast,
    output wire                    s_axis_tready,

    output reg  [G_AXI_DATA_W-1:0] m_axis_tdata,
    output reg                      m_axis_tvalid,
    output reg                      m_axis_tlast,
    input  wire                     m_axis_tready,

    output wire [127:0]            o_tag,
    output wire                    o_tag_valid,
    output wire                    o_busy
);

    localparam [3:0]
        IS_IDLE      = 4'd0,
        IS_KEY_HI    = 4'd1,
        IS_KEY_LO    = 4'd2,
        IS_NONCE_HI  = 4'd3,
        IS_NONCE_LO  = 4'd4,
        IS_AD_HI     = 4'd5,
        IS_AD_LO     = 4'd6,
        IS_AD_WAIT   = 4'd7,
        IS_START     = 4'd8,
        IS_PT_HI     = 4'd9,
        IS_PT_LO     = 4'd10,
        IS_WAIT_DONE = 4'd11;

    localparam [1:0]
        OS_IDLE = 2'd0,
        OS_HI   = 2'd1,
        OS_LO   = 2'd2;

    reg [3:0] in_state;
    reg [1:0] out_state;

    reg [127:0] reg_key, reg_nonce, reg_ad, reg_pt;
    reg [63:0]  beat_hi_buf;
    reg         ad_hi_last, pt_hi_last;

    reg        core_start_pulse;
    reg        started;
    reg [1:0]  core_mode;
    reg        core_ad_valid;
    reg        core_ad_last;
    reg        core_data_last;
    reg [6:0]  core_data_len;
    reg [6:0]  core_ad_len_r;

    wire [127:0] core_data_out;
    wire         core_data_out_valid;
    wire [127:0] core_tag_out;
    wire         core_tag_valid;
    wire         core_tag_match;
    wire         core_done;
    wire         core_busy;

    ascon_CORE #(
        .G_COMB_RND_128 (G_COMB_RND_128),
        .G_COMB_RND_128A(G_COMB_RND_128A),
        .G_SBOX_PIPELINE(G_SBOX_PIPELINE),
        .G_DUAL_RATE    (G_DUAL_RATE),
        .G_AXI_DATA_W   (G_AXI_DATA_W)
    ) u_core (
        .clk(clk), .rst_n(rst_n),
        .start(core_start_pulse), .mode(core_mode), .enc_dec(enc_dec),
        .key_in(reg_key), .nonce_in(reg_nonce),
        .ad_in(reg_ad), .ad_valid(core_ad_valid), .ad_last(core_ad_last),
        .data_in(reg_pt), .data_last(core_data_last), .data_len(core_data_len),
        .tag_received(128'h0),
        .data_out(core_data_out), .data_out_valid(core_data_out_valid),
        .tag_out(core_tag_out), .tag_valid(core_tag_valid),
        .tag_match(core_tag_match), .done(core_done), .busy(core_busy)
    );

    assign s_axis_tready = (in_state == IS_KEY_HI)   ||
                           (in_state == IS_KEY_LO)   ||
                           (in_state == IS_NONCE_HI) ||
                           (in_state == IS_NONCE_LO) ||
                           (in_state == IS_AD_HI)    ||
                           (in_state == IS_AD_LO)    ||
                           (in_state == IS_PT_HI)    ||
                           (in_state == IS_PT_LO);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_state         <= IS_IDLE;
            reg_key          <= 128'b0;
            reg_nonce        <= 128'b0;
            reg_ad           <= 128'b0;
            reg_pt           <= 128'b0;
            beat_hi_buf      <= 64'b0;
            ad_hi_last       <= 1'b0;
            pt_hi_last       <= 1'b0;
            core_start_pulse <= 1'b0;
            started          <= 1'b0;
            core_mode        <= 2'b00;
            core_ad_valid    <= 1'b0;
            core_ad_last     <= 1'b0;
            core_data_last   <= 1'b0;
            core_data_len    <= 7'd16;
            core_ad_len_r    <= 7'd16;
        end else begin

            core_start_pulse <= 1'b0;

            if (core_done) begin
                core_ad_valid  <= 1'b0;
                core_ad_last   <= 1'b0;
                core_data_last <= 1'b0;
                started        <= 1'b0;
            end

            case (in_state)

                IS_IDLE: begin
                    core_mode <= mode;
                    in_state  <= IS_KEY_HI;
                end

                IS_KEY_HI: begin
                    if (s_axis_tvalid) begin
                        reg_key[127:64] <= s_axis_tdata;
                        in_state        <= IS_KEY_LO;
                    end
                end

                IS_KEY_LO: begin
                    if (s_axis_tvalid) begin
                        reg_key[63:0] <= s_axis_tdata;
                        in_state      <= IS_NONCE_HI;
                    end
                end

                IS_NONCE_HI: begin
                    if (s_axis_tvalid) begin
                        reg_nonce[127:64] <= s_axis_tdata;
                        in_state          <= IS_NONCE_LO;
                    end
                end

                IS_NONCE_LO: begin
                    if (s_axis_tvalid) begin
                        reg_nonce[63:0] <= s_axis_tdata;
                        in_state        <= IS_AD_HI;
                    end
                end

                IS_AD_HI: begin
                    if (s_axis_tvalid) begin
                        beat_hi_buf <= s_axis_tdata;
                        ad_hi_last  <= s_axis_tlast;
                        in_state    <= IS_AD_LO;
                    end
                end

                IS_AD_LO: begin
                    if (s_axis_tvalid) begin
                        reg_ad        <= {beat_hi_buf, s_axis_tdata};
                        core_ad_valid <= 1'b1;
                        core_ad_last  <= ad_hi_last | s_axis_tlast;
                        core_ad_len_r <= i_ad_len;
                        in_state      <= IS_AD_WAIT;
                    end
                end

                IS_AD_WAIT: begin
                    in_state <= IS_START;
                end

                IS_START: begin
                    if (!started) begin
                        core_start_pulse <= 1'b1;
                        started          <= 1'b1;
                    end
                    if (core_ad_last)
                        in_state <= IS_PT_HI;
                    else
                        in_state <= IS_AD_HI;
                end

                IS_PT_HI: begin
                    if (s_axis_tvalid) begin
                        beat_hi_buf <= s_axis_tdata;
                        pt_hi_last  <= s_axis_tlast;
                        in_state    <= IS_PT_LO;
                    end
                end

                IS_PT_LO: begin
                    if (s_axis_tvalid) begin
                        reg_pt         <= {beat_hi_buf, s_axis_tdata};
                        core_data_last <= pt_hi_last | s_axis_tlast;
                        core_data_len  <= i_data_len;
                        if (pt_hi_last | s_axis_tlast)
                            in_state <= IS_WAIT_DONE;
                        else
                            in_state <= IS_PT_HI;
                    end
                end

                IS_WAIT_DONE: begin
                    if (core_done) in_state <= IS_IDLE;
                end

                default: in_state <= IS_IDLE;
            endcase
        end
    end

    // Output FSM
    reg [127:0] ct_buf;
    reg         ct_is_last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_state     <= OS_IDLE;
            m_axis_tdata  <= {G_AXI_DATA_W{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            ct_buf        <= 128'b0;
            ct_is_last    <= 1'b0;
        end else begin
            case (out_state)
                OS_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;
                    if (core_data_out_valid) begin
                        ct_buf     <= core_data_out;
                        ct_is_last <= core_done;
                        out_state  <= OS_HI;
                    end
                end
                OS_HI: begin
                    m_axis_tdata  <= ct_buf[127:64];
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= 1'b0;
                    if (m_axis_tready) out_state <= OS_LO;
                end
                OS_LO: begin
                    m_axis_tdata  <= ct_buf[63:0];
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= ct_is_last;
                    if (m_axis_tready) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tlast  <= 1'b0;
                        out_state     <= OS_IDLE;
                    end
                end
                default: out_state <= OS_IDLE;
            endcase
        end
    end

    assign o_tag       = core_tag_out;
    assign o_tag_valid = core_tag_valid;
    assign o_busy      = core_busy;

endmodule