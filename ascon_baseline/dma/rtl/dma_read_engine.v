`timescale 1ns/1ps

// ============================================================================
// Module  : dma_read_engine
// Project : ASCON Crypto Accelerator IP
//
// Notes:
//   - Legacy mode keeps the existing AXI burst flow.
//   - Coherent mode snoops each 64-bit beat first. A snoop hit pushes data
//     directly into the RD FIFO, while a miss falls back to a single-beat AXI
//     read for that address.
// ============================================================================

module dma_read_engine #(
    parameter ADDR_WIDTH     = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 4
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // Control
    input  wire [ADDR_WIDTH-1:0]      src_addr,
    input  wire [7:0]                 burst_len,
    input  wire                       dma_start,
    input  wire                       rd_start,
    output reg                        rd_busy,
    output reg                        rd_done,
    output reg                        rd_error,
    output reg  [ADDR_WIDTH-1:0]      rd_err_addr,

    // Optional coherent sideband snoop
    input  wire                       coherent_read_en,
    output reg                        snoop_req_valid,
    output reg  [1:0]                 snoop_req_cmd,
    output reg  [ADDR_WIDTH-1:0]      snoop_req_addr,
    input  wire                       snoop_req_ready,
    input  wire                       snoop_resp_valid,
    input  wire                       snoop_resp_hit,
    input  wire [AXI_DATA_WIDTH-1:0]  snoop_resp_data,

    // RD FIFO push interface
    output reg  [AXI_DATA_WIDTH-1:0]  fifo_din,
    output reg                        fifo_push,
    input  wire                       fifo_full,

    // AXI4 Read Address Channel
    output reg  [AXI_ID_WIDTH-1:0]    M_AXI_ARID,
    output reg  [ADDR_WIDTH-1:0]      M_AXI_ARADDR,
    output reg  [7:0]                 M_AXI_ARLEN,
    output wire [2:0]                 M_AXI_ARSIZE,
    output wire [1:0]                 M_AXI_ARBURST,
    output wire [3:0]                 M_AXI_ARCACHE,
    output wire [2:0]                 M_AXI_ARPROT,
    output reg                        M_AXI_ARVALID,
    input  wire                       M_AXI_ARREADY,

    // AXI4 Read Data Channel
    input  wire [AXI_ID_WIDTH-1:0]    M_AXI_RID,
    input  wire [AXI_DATA_WIDTH-1:0]  M_AXI_RDATA,
    input  wire [1:0]                 M_AXI_RRESP,
    input  wire                       M_AXI_RLAST,
    input  wire                       M_AXI_RVALID,
    output reg                        M_AXI_RREADY
);

    assign M_AXI_ARSIZE  = 3'b011;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARCACHE = 4'b0010;
    assign M_AXI_ARPROT  = 3'b000;

    localparam [2:0]
        RD_IDLE     = 3'd0,
        RD_SNP_REQ  = 3'd1,
        RD_SNP_WAIT = 3'd2,
        RD_ADDR     = 3'd3,
        RD_DATA     = 3'd4,
        RD_DONE     = 3'd5;

    reg [2:0] state;

    reg [ADDR_WIDTH-1:0] cur_src_addr;
    reg [ADDR_WIDTH-1:0] last_rd_src_addr;
    reg [ADDR_WIDTH-1:0] tx_start_addr;
    reg [ADDR_WIDTH-1:0] work_addr;
    reg [28:0]           tx_total_beats;
    reg [28:0]           tx_beat_idx;
    reg [7:0]            burst_len_r;
    reg [7:0]            beat_cnt;

    wire [ADDR_WIDTH-1:0] legacy_beat_addr =
        M_AXI_ARADDR + {{(ADDR_WIDTH-11){1'b0}}, beat_cnt, 3'b000};
    wire [ADDR_WIDTH-1:0] current_err_addr = coherent_read_en ? work_addr : legacy_beat_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= RD_IDLE;
            rd_busy          <= 1'b0;
            rd_done          <= 1'b0;
            rd_error         <= 1'b0;
            rd_err_addr      <= {ADDR_WIDTH{1'b0}};
            snoop_req_valid  <= 1'b0;
            snoop_req_cmd    <= 2'b00;
            snoop_req_addr   <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARVALID    <= 1'b0;
            M_AXI_ARID       <= {AXI_ID_WIDTH{1'b0}};
            M_AXI_ARADDR     <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARLEN      <= 8'h00;
            M_AXI_RREADY     <= 1'b0;
            fifo_push        <= 1'b0;
            fifo_din         <= {AXI_DATA_WIDTH{1'b0}};
            beat_cnt         <= 8'h00;
            burst_len_r      <= 8'h00;
            cur_src_addr     <= {ADDR_WIDTH{1'b0}};
            last_rd_src_addr <= {ADDR_WIDTH{1'b1}};
            tx_start_addr    <= {ADDR_WIDTH{1'b0}};
            work_addr        <= {ADDR_WIDTH{1'b0}};
            tx_total_beats   <= 29'd0;
            tx_beat_idx      <= 29'd0;
        end else begin
            rd_done         <= 1'b0;
            fifo_push       <= 1'b0;
            snoop_req_valid <= 1'b0;

            if (dma_start)
                last_rd_src_addr <= {ADDR_WIDTH{1'b1}};

            case (state)
                RD_IDLE: begin
                    rd_busy      <= 1'b0;
                    M_AXI_ARVALID<= 1'b0;
                    M_AXI_RREADY <= 1'b0;
                    beat_cnt     <= 8'h00;

                    if (rd_start) begin
                        rd_busy        <= 1'b1;
                        rd_error       <= 1'b0;
                        rd_err_addr    <= {ADDR_WIDTH{1'b0}};
                        burst_len_r    <= burst_len;
                        tx_total_beats <= {21'd0, burst_len} + 29'd1;
                        tx_beat_idx    <= 29'd0;
                        M_AXI_ARID     <= {AXI_ID_WIDTH{1'b0}};

                        if (src_addr != last_rd_src_addr) begin
                            tx_start_addr <= src_addr;
                            work_addr     <= src_addr;
                            cur_src_addr  <= src_addr;
                            if (!coherent_read_en)
                                M_AXI_ARADDR <= src_addr;
                        end else begin
                            tx_start_addr <= cur_src_addr;
                            work_addr     <= cur_src_addr;
                            if (!coherent_read_en)
                                M_AXI_ARADDR <= cur_src_addr;
                        end
                        last_rd_src_addr <= src_addr;

                        if (coherent_read_en) begin
                            state <= RD_SNP_REQ;
                        end else begin
                            M_AXI_ARLEN   <= burst_len;
                            M_AXI_ARVALID <= 1'b1;
                            state         <= RD_ADDR;
                        end
                    end
                end

                RD_SNP_REQ: begin
                    rd_busy         <= 1'b1;
                    if (!fifo_full) begin
                        snoop_req_valid <= 1'b1;
                        snoop_req_cmd   <= 2'b01;
                        snoop_req_addr  <= work_addr;
                        if (snoop_req_ready)
                            state <= RD_SNP_WAIT;
                    end
                end

                RD_SNP_WAIT: begin
                    rd_busy <= 1'b1;
                    if (snoop_resp_valid) begin
                        if (snoop_resp_hit) begin
                            if (!fifo_full) begin
                                fifo_din  <= snoop_resp_data;
                                fifo_push <= 1'b1;
                                if (tx_beat_idx + 29'd1 >= tx_total_beats) begin
                                    cur_src_addr <= tx_start_addr + (tx_total_beats << 3);
                                    state        <= RD_DONE;
                                end else begin
                                    tx_beat_idx <= tx_beat_idx + 29'd1;
                                    work_addr   <= work_addr + 32'd8;
                                    state       <= RD_SNP_REQ;
                                end
                            end else begin
                                rd_error    <= 1'b1;
                                rd_err_addr <= work_addr;
                            end
                        end else begin
                            M_AXI_ARADDR  <= work_addr;
                            M_AXI_ARLEN   <= 8'd0;
                            M_AXI_ARVALID <= 1'b1;
                            state         <= RD_ADDR;
                        end
                    end
                end

                RD_ADDR: begin
                    rd_busy <= 1'b1;
                    if (M_AXI_ARREADY && M_AXI_ARVALID) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= ~fifo_full;
                        if (coherent_read_en)
                            beat_cnt <= 8'h00;
                        state <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    rd_busy <= 1'b1;
                    M_AXI_RREADY <= ~fifo_full;

                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        if (M_AXI_RRESP != 2'b00) begin
                            rd_error <= 1'b1;
                            if (!rd_error)
                                rd_err_addr <= current_err_addr;
                        end

                        if (!fifo_full) begin
                            fifo_din  <= M_AXI_RDATA;
                            fifo_push <= 1'b1;
                        end else begin
                            rd_error <= 1'b1;
                            if (!rd_error)
                                rd_err_addr <= current_err_addr;
                        end

                        beat_cnt <= beat_cnt + 8'h01;

                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY <= 1'b0;
                            if (coherent_read_en) begin
                                if (tx_beat_idx + 29'd1 >= tx_total_beats) begin
                                    cur_src_addr <= tx_start_addr + (tx_total_beats << 3);
                                    state        <= RD_DONE;
                                end else begin
                                    tx_beat_idx <= tx_beat_idx + 29'd1;
                                    work_addr   <= work_addr + 32'd8;
                                    state       <= RD_SNP_REQ;
                                end
                            end else begin
                                cur_src_addr <= M_AXI_ARADDR + {22'b0, burst_len_r, 3'b000} + 32'd8;
                                state        <= RD_DONE;
                            end
                        end
                    end
                end

                RD_DONE: begin
                    rd_busy <= 1'b1;
                    rd_done <= 1'b1;
                    state   <= RD_IDLE;
                end

                default: begin
                    state <= RD_IDLE;
                end
            endcase
        end
    end

endmodule
