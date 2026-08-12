`timescale 1ns/1ps

// ============================================================================
// riscv_dm.v — RISC-V Debug Module
//
// Chuẩn: RISC-V External Debug Support v0.13.2
// Nhận DMI bus từ jtag_dtm, thực hiện debug operations.
// System Bus Access (SBA): AXI4-Full master → Crossbar M4 (đọc/ghi memory
// trực tiếp khi CPU đang halted, không cần CPU làm trung gian).
//
// DMI Address Map (7-bit addr):
//   0x04 = data0     RW  32-bit data buffer (argument/result)
//   0x10 = dmcontrol RW  [0]=dmactive, [1]=ndmreset, [16]=haltreq, [17]=resumereq
//   0x11 = dmstatus  RO  [8]=anyhalted, [9]=allhalted, [10]=anyrunning, [11]=allrunning
//   0x12 = hartinfo  RO  [23:20]=nscratch=1, [16:12]=dataaddr
//   0x16 = abstractcs RW [28:24]=cmderr, [3:0]=datacount=1
//   0x17 = command   WO  [31:24]=cmdtype, [23:0]=control
//   0x38 = sbcs      RW  System Bus Access Control/Status
//   0x39 = sbaddress0 RW  SBA address [31:0]
//   0x3C = sbdata0   RW  SBA data [31:0]
//
// Sub-modules:
//   (không có sub-module thêm — DM đủ nhỏ để viết trong 1 module)
// ============================================================================

module riscv_dm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4,
    parameter ABITS      = 7
)(
    input  wire clk,
    input  wire rst_n,

    // ── DMI bus (từ jtag_dtm) ─────────────────────────────────────────────
    input  wire [ABITS-1:0] dmi_addr,
    input  wire [31:0]      dmi_data_wr,
    input  wire [1:0]       dmi_op,      // 01=read, 10=write
    input  wire             dmi_req_valid,
    output reg              dmi_req_ready,

    output reg  [31:0]      dmi_data_rd,
    output reg  [1:0]       dmi_rsp_op,  // 00=OK, 10=fail, 11=busy
    output reg              dmi_rsp_valid,
    input  wire             dmi_rsp_ready,

    // ── CPU debug interface ────────────────────────────────────────────────
    output wire             ndmreset,     // non-debug reset → soc_top
    output wire             haltreq,      // halt request → CPU
    output wire             resumereq,    // resume request → CPU
    input  wire             halted,       // CPU halted status
    input  wire             running,      // CPU running status

    // ── AXI4-Full Master (M4 → Crossbar: System Bus Access) ───────────────
    output reg  [ID_WIDTH-1:0]   m_axi_arid,
    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire [2:0]            m_axi_arprot,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [ID_WIDTH-1:0]   m_axi_rid,
    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready,

    output reg  [ID_WIDTH-1:0]   m_axi_awid,
    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire [2:0]            m_axi_awprot,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,

    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [3:0]            m_axi_wstrb,
    output wire                  m_axi_wlast,
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,

    input  wire [ID_WIDTH-1:0]   m_axi_bid,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready
);

    // Fixed AXI attributes for SBA (single-word transfers only)
    assign m_axi_arlen   = 8'd0;    // 1 beat
    assign m_axi_arsize  = 3'd2;    // 4 bytes
    assign m_axi_arburst = 2'b01;   // INCR
    assign m_axi_arprot  = 3'b000;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'd2;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_wstrb   = 4'hF;
    assign m_axi_wlast   = 1'b1;
    assign m_axi_rready  = 1'b1;
    assign m_axi_bready  = 1'b1;

    // ── Debug Module Registers ────────────────────────────────────────────
    reg         dm_active;
    reg         ndmreset_r;
    reg         haltreq_r;
    reg         resumereq_r;
    reg [31:0]  data0;           // abstract argument/result
    reg [2:0]   cmderr;          // abstract command error
    reg         abstract_busy;

    // System Bus Access registers
    reg [31:0]  sbaddress0;
    reg [31:0]  sbdata0;
    reg         sb_readonaddr;   // auto-read on sbaddress write
    reg         sb_busy;
    reg [2:0]   sberror;

    assign ndmreset  = ndmreset_r;
    assign haltreq   = haltreq_r && dm_active;
    assign resumereq = resumereq_r && dm_active;

    // ── DMI transaction handler ────────────────────────────────────────────
    // Simple single-cycle response for register reads/writes
    // SBA transactions take multiple cycles (AXI)

    localparam DMI_OP_NOP   = 2'b00;
    localparam DMI_OP_READ  = 2'b01;
    localparam DMI_OP_WRITE = 2'b10;

    // DMI register addresses
    localparam [6:0]
        ADDR_DATA0      = 7'h04,
        ADDR_DMCONTROL  = 7'h10,
        ADDR_DMSTATUS   = 7'h11,
        ADDR_HARTINFO   = 7'h12,
        ADDR_ABSTRACTCS = 7'h16,
        ADDR_COMMAND    = 7'h17,
        ADDR_SBCS       = 7'h38,
        ADDR_SBADDRESS0 = 7'h39,
        ADDR_SBDATA0    = 7'h3C;

    // Abstract command FSM
    localparam [1:0] ABS_IDLE = 2'd0, ABS_EXEC = 2'd1, ABS_DONE = 2'd2;
    reg [1:0] abs_state;
    reg [31:0] abs_cmd_r;

    // SBA FSM
    localparam [2:0] SBA_IDLE = 3'd0, SBA_AR = 3'd1, SBA_RD = 3'd2,
                     SBA_AW   = 3'd3, SBA_WD = 3'd4, SBA_WR = 3'd5;
    reg [2:0] sba_state;
    reg       sba_is_write;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dm_active    <= 1'b0;
            ndmreset_r   <= 1'b0;
            haltreq_r    <= 1'b0;
            resumereq_r  <= 1'b0;
            data0        <= 32'h0;
            cmderr       <= 3'h0;
            abstract_busy <= 1'b0;
            sbaddress0   <= 32'h0;
            sbdata0      <= 32'h0;
            sb_readonaddr <= 1'b0;
            sb_busy      <= 1'b0;
            sberror      <= 3'h0;
            abs_state    <= ABS_IDLE;
            sba_state    <= SBA_IDLE;

            dmi_req_ready <= 1'b1;
            dmi_rsp_valid <= 1'b0;
            dmi_rsp_op    <= 2'b00;
            dmi_data_rd   <= 32'h0;

            m_axi_arvalid <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
        end else begin

            // ── Default: de-assert pulses ───────────────────────────────────
            resumereq_r  <= 1'b0;

            // ── SBA state machine ───────────────────────────────────────────
            case (sba_state)
                SBA_IDLE: begin
                    sb_busy <= 1'b0;
                end
                SBA_AR: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_arid    <= 4'd3;   // JTAG DM master ID
                    m_axi_araddr  <= sbaddress0;
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        sba_state     <= SBA_RD;
                    end
                end
                SBA_RD: begin
                    if (m_axi_rvalid) begin
                        sbdata0   <= m_axi_rdata;
                        sberror   <= (m_axi_rresp != 2'b00) ? 3'd4 : 3'd0;
                        sba_state <= SBA_IDLE;
                        sb_busy   <= 1'b0;
                    end
                end
                SBA_AW: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awid    <= 4'd3;
                    m_axi_awaddr  <= sbaddress0;
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        sba_state     <= SBA_WD;
                    end
                end
                SBA_WD: begin
                    m_axi_wvalid <= 1'b1;
                    m_axi_wdata  <= sbdata0;
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        sba_state    <= SBA_WR;
                    end
                end
                SBA_WR: begin
                    if (m_axi_bvalid) begin
                        sberror   <= (m_axi_bresp != 2'b00) ? 3'd4 : 3'd0;
                        sba_state <= SBA_IDLE;
                        sb_busy   <= 1'b0;
                    end
                end
                default: sba_state <= SBA_IDLE;
            endcase

            // ── DMI request handler ─────────────────────────────────────────
            dmi_rsp_valid <= 1'b0;

            if (dmi_req_valid && dmi_req_ready) begin
                dmi_req_ready <= 1'b0;  // busy processing

                if (dmi_op == DMI_OP_READ) begin
                    dmi_rsp_op <= 2'b00;  // OK
                    case (dmi_addr)
                        ADDR_DATA0: dmi_data_rd <= data0;

                        ADDR_DMCONTROL: dmi_data_rd <= {
                            14'b0, resumereq_r, haltreq_r,
                            6'b0, 1'b0, 1'b0,  // hartsello, hartselhi
                            4'b0, ndmreset_r, dm_active
                        };

                        ADDR_DMSTATUS: dmi_data_rd <= {
                            14'b0,
                            ~halted, ~halted,   // anyrunning, allrunning
                            halted,  halted,    // anyhalted, allhalted
                            1'b1,    1'b1,      // authenticated, authbusy=0
                            1'b0,    1'b0,      // anyunavail, allunavail
                            1'b0,    1'b0,      // anynonexistent
                            4'h2                // version = 0.13
                        };

                        ADDR_HARTINFO: dmi_data_rd <= {
                            8'b0, 4'd1,   // nscratch=1
                            3'b0, 1'b0,   // accessreg for data
                            12'h400       // dataaddr (relative)
                        };

                        ADDR_ABSTRACTCS: dmi_data_rd <= {
                            3'b0, cmderr,
                            11'b0, abstract_busy,
                            12'b0, 4'd1   // datacount=1
                        };

                        ADDR_SBCS: dmi_data_rd <= {
                            3'h1,       // sbversion=1
                            6'b0,       // reserved
                            3'b0,       // sbbusyerror, sbbusy, sbreadonaddr
                            2'b01,      // sbaccess=01 (32-bit)
                            1'b0,       // sbautoincrement
                            sb_readonaddr,
                            sberror,
                            1'b0,       // sbreadondata
                            sb_busy,
                            7'd32       // sbasize=32
                        };

                        ADDR_SBADDRESS0: dmi_data_rd <= sbaddress0;
                        ADDR_SBDATA0:    dmi_data_rd <= sbdata0;
                        default:         dmi_data_rd <= 32'h0;
                    endcase

                end else if (dmi_op == DMI_OP_WRITE) begin
                    dmi_data_rd <= 32'h0;
                    dmi_rsp_op  <= 2'b00;
                    case (dmi_addr)
                        ADDR_DATA0:    data0 <= dmi_data_wr;

                        ADDR_DMCONTROL: begin
                            dm_active   <= dmi_data_wr[0];
                            ndmreset_r  <= dmi_data_wr[1];
                            haltreq_r   <= dmi_data_wr[31];
                            if (dmi_data_wr[30]) resumereq_r <= 1'b1;
                        end

                        ADDR_ABSTRACTCS: begin
                            // Write 1 to cmderr bits [10:8] to clear
                            if (dmi_data_wr[10:8] == cmderr)
                                cmderr <= 3'h0;
                        end

                        ADDR_COMMAND: begin
                            // cmdtype=0 (access register)
                            // aarsize=2 (32-bit), transfer=1, postexec=0
                            // regno = dmi_data_wr[15:0]
                            // Simplified: just store, firmware handles
                            abs_cmd_r     <= dmi_data_wr;
                            abstract_busy <= 1'b1;
                            // data0 ← GPR[regno] (hooked via CPU debug port)
                            // For tape-out: connect to CPU halt/resume/regread port
                            cmderr        <= 3'h0;
                            abstract_busy <= 1'b0;
                        end

                        ADDR_SBCS: begin
                            sb_readonaddr <= dmi_data_wr[20];
                            // Clear sberror by writing 1
                            if (dmi_data_wr[14:12] != 3'h0) sberror <= 3'h0;
                        end

                        ADDR_SBADDRESS0: begin
                            sbaddress0 <= dmi_data_wr;
                            // Auto-read if sbreadonaddr=1
                            if (sb_readonaddr && !sb_busy && sberror == 3'h0) begin
                                sb_busy   <= 1'b1;
                                sba_state <= SBA_AR;
                            end
                        end

                        ADDR_SBDATA0: begin
                            sbdata0   <= dmi_data_wr;
                            // Trigger write
                            if (!sb_busy && sberror == 3'h0) begin
                                sb_busy   <= 1'b1;
                                sba_state <= SBA_AW;
                            end
                        end

                        default: ;
                    endcase
                end

                dmi_rsp_valid <= 1'b1;
                dmi_req_ready <= 1'b1;
            end
        end
    end

endmodule