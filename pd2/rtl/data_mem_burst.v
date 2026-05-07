`timescale 1ns/1ps

module data_mem_burst #(
    parameter MEM_SIZE   = 8192,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BASE_ADDR  = 32'h10000000
)(
    input wire clk,
    input wire rst_n,

    // Burst Read Interface
    input  wire [ADDR_WIDTH-1:0] burst_rd_addr,
    input  wire [7:0]            burst_rd_len,
    input  wire                  burst_rd_req,
    output wire [DATA_WIDTH-1:0] burst_rd_data,
    output reg                   burst_rd_valid,
    output reg                   burst_rd_last,
    input  wire                  burst_rd_ready,

    // Burst Write Interface
    input  wire [ADDR_WIDTH-1:0] burst_wr_addr,
    input  wire [DATA_WIDTH-1:0] burst_wr_data,
    input  wire [3:0]            burst_wr_strb,
    input  wire                  burst_wr_valid,
    output wire                  burst_wr_ready,
    input  wire                  burst_wr_last
);
    localparam ADDR_LSB  = $clog2(DATA_WIDTH/8);
    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);
    localparam ADDR_BITS = $clog2(MEM_DEPTH);

    // (* ram_style = "block" *)   // uncomment để force BRAM trên Vivado
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // =========================================================================
    // Burst Write — synchronous byte-enable write port
    //
    // burst_wr_addr (beat 0) comes from slave's write_addr register.
    // Subsequent beats: internal wr_current_addr tracks advancement.
    // BASE_ADDR assumed aligned to MEM_SIZE → lower ADDR_BITS+ADDR_LSB bits
    // give the local word index directly.
    // =========================================================================
    reg [ADDR_WIDTH-1:0] wr_current_addr;
    reg                  wr_first_beat;

    wire [ADDR_WIDTH-1:0] wr_eff_addr  = wr_first_beat ? burst_wr_addr : wr_current_addr;
    wire [ADDR_BITS-1:0]  wr_word_idx  = wr_eff_addr[ADDR_BITS+ADDR_LSB-1 : ADDR_LSB];

    assign burst_wr_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_current_addr <= {ADDR_WIDTH{1'b0}};
            wr_first_beat   <= 1'b1;
        end else if (burst_wr_valid) begin
            if (!burst_wr_last) begin
                wr_current_addr <= wr_eff_addr + (DATA_WIDTH/8);
                wr_first_beat   <= 1'b0;
            end else begin
                wr_first_beat   <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (burst_wr_valid) begin
            if (burst_wr_strb[0]) memory[wr_word_idx][7:0]   <= burst_wr_data[7:0];
            if (burst_wr_strb[1]) memory[wr_word_idx][15:8]  <= burst_wr_data[15:8];
            if (burst_wr_strb[2]) memory[wr_word_idx][23:16] <= burst_wr_data[23:16];
            if (burst_wr_strb[3]) memory[wr_word_idx][31:24] <= burst_wr_data[31:24];
        end
    end

    // =========================================================================
    // Burst Read — BRAM-compatible 1-cycle latency
    //
    // Address mux → BRAM samples at posedge T → burst_rd_data valid at T+1.
    // burst_rd_valid also set at T+1 → RVALID and RDATA aligned. ✓
    //
    // advance=1: present next beat address to BRAM at T so data ready at T+1.
    // hold (burst_rd_ready=0): present current_addr → BRAM re-reads same word.
    // =========================================================================
    localparam RD_IDLE   = 1'b0;
    localparam RD_ACTIVE = 1'b1;

    reg        rd_state;
    reg [ADDR_WIDTH-1:0] rd_current_addr;
    reg [7:0]  rd_beat_count;
    reg [7:0]  rd_total_beats;

    wire [ADDR_WIDTH-1:0] rd_next_addr  = rd_current_addr + (DATA_WIDTH/8);
    wire                  advance_rd    = (rd_state == RD_ACTIVE) && burst_rd_valid
                                          && burst_rd_ready && !burst_rd_last;

    wire [ADDR_WIDTH-1:0] bram_rd_sel;
    assign bram_rd_sel = (rd_state == RD_IDLE && burst_rd_req) ? burst_rd_addr  :
                         advance_rd                             ? rd_next_addr   :
                         (rd_state == RD_ACTIVE)               ? rd_current_addr :
                                                                  {ADDR_WIDTH{1'b0}};

    wire [ADDR_BITS-1:0] bram_rd_word = bram_rd_sel[ADDR_BITS+ADDR_LSB-1 : ADDR_LSB];

    reg [DATA_WIDTH-1:0] bram_rd_ff;
    always @(posedge clk)
        bram_rd_ff <= memory[bram_rd_word];

    assign burst_rd_data = bram_rd_ff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state        <= RD_IDLE;
            burst_rd_valid  <= 1'b0;
            burst_rd_last   <= 1'b0;
            rd_current_addr <= {ADDR_WIDTH{1'b0}};
            rd_beat_count   <= 8'd0;
            rd_total_beats  <= 8'd0;
        end else begin
            case (rd_state)

                RD_IDLE: begin
                    if (burst_rd_req) begin
                        rd_current_addr <= burst_rd_addr;
                        rd_beat_count   <= 8'd0;
                        rd_total_beats  <= burst_rd_len;
                        rd_state        <= RD_ACTIVE;
                        burst_rd_valid  <= 1'b1;
                        burst_rd_last   <= (burst_rd_len == 8'd0);
                    end else begin
                        burst_rd_valid  <= 1'b0;
                        burst_rd_last   <= 1'b0;
                    end
                end

                RD_ACTIVE: begin
                    if (burst_rd_ready && burst_rd_valid) begin
                        if (burst_rd_last) begin
                            rd_state       <= RD_IDLE;
                            burst_rd_valid <= 1'b0;
                            burst_rd_last  <= 1'b0;
                        end else begin
                            rd_beat_count   <= rd_beat_count + 8'd1;
                            rd_current_addr <= rd_next_addr;
                            burst_rd_valid  <= 1'b1;
                            burst_rd_last   <= (rd_beat_count + 8'd1 == rd_total_beats);
                        end
                    end
                end

                default: rd_state <= RD_IDLE;

            endcase
        end
    end

    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = {DATA_WIDTH{1'b0}};
    end

endmodule
