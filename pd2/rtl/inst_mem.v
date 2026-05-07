`timescale 1ns/1ps

module inst_mem #(
    parameter MEM_SIZE      = 8192,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,

    // Direct read — 1-cycle latency (registered BRAM output)
    input  wire [ADDR_WIDTH-1:0] PC,
    output wire [DATA_WIDTH-1:0] Instruction_Code,

    // Burst Read Interface
    input  wire [ADDR_WIDTH-1:0] burst_addr,
    input  wire [7:0]            burst_len,
    input  wire                  burst_req,
    output wire [DATA_WIDTH-1:0] burst_data,
    output reg                   burst_valid,
    output reg                   burst_last,
    input  wire                  burst_ready,

    // Write port (boot sideband + AXI write path)
    input  wire                    wr_en,
    input  wire [ADDR_WIDTH-1:0]   wr_addr,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    input  wire [DATA_WIDTH/8-1:0] wr_strb
);

    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);
    localparam ADDR_LSB  = $clog2(DATA_WIDTH/8);
    localparam ADDR_BITS = $clog2(MEM_DEPTH);

    // (* ram_style = "block" *)   // uncomment để force BRAM trên Vivado
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // =========================================================================
    // Write port — synchronous byte-enable
    // =========================================================================
    wire [ADDR_BITS-1:0] wr_word_addr = wr_addr[ADDR_BITS+ADDR_LSB-1 : ADDR_LSB];

    integer b;
    always @(posedge clk) begin
        if (wr_en)
            for (b = 0; b < DATA_WIDTH/8; b = b + 1)
                if (wr_strb[b])
                    memory[wr_word_addr][b*8 +: 8] <= wr_data[b*8 +: 8];
    end

    // =========================================================================
    // Burst FSM
    // =========================================================================
    localparam BURST_IDLE   = 1'b0;
    localparam BURST_ACTIVE = 1'b1;

    reg        burst_state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [7:0]  beat_count;
    reg [7:0]  total_beats;

    wire [ADDR_WIDTH-1:0] next_addr    = current_addr + (DATA_WIDTH/8);
    wire                  next_is_last = (beat_count + 8'd1 == total_beats);

    // =========================================================================
    // BRAM read — single registered port, 1-cycle latency
    //
    // Address presented at posedge T → data available at T+1.
    // Timing aligns naturally with burst_valid (both set via registered assign):
    //   T   : burst_req=1  → BRAM samples burst_addr, FSM sets burst_valid<=1
    //   T+1 : burst_valid=1, bram_dout = memory[burst_addr]  ✓
    //
    // When advancing (beat N accepted at T_N): present next_addr to BRAM at T_N
    // so data for beat N+1 is ready at T_N+1 when burst_valid still=1.
    // =========================================================================

    // advance=1 at posedge T_N → we need next beat's address at T_N for BRAM
    wire advance = (burst_state == BURST_ACTIVE) && burst_valid && burst_ready && !burst_last;

    wire [ADDR_WIDTH-1:0] bram_addr_sel;
    assign bram_addr_sel = (burst_state == BURST_IDLE && burst_req) ? burst_addr :
                           advance                                   ? next_addr  :
                           (burst_state == BURST_ACTIVE)             ? current_addr :
                                                                       PC;

    wire [ADDR_BITS-1:0] bram_word_addr = bram_addr_sel[ADDR_BITS+ADDR_LSB-1 : ADDR_LSB];

    reg [DATA_WIDTH-1:0] bram_dout;
    always @(posedge clk)
        bram_dout <= memory[bram_word_addr];

    assign burst_data       = bram_dout;
    assign Instruction_Code = bram_dout;   // 1-cycle latency (vestigial port — ICache sits in front)

    // =========================================================================
    // FSM state update
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            burst_state  <= BURST_IDLE;
            burst_valid  <= 1'b0;
            burst_last   <= 1'b0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            beat_count   <= 8'd0;
            total_beats  <= 8'd0;
        end else begin
            case (burst_state)

                BURST_IDLE: begin
                    if (burst_req) begin
                        current_addr <= burst_addr;
                        beat_count   <= 8'd0;
                        total_beats  <= burst_len;
                        burst_state  <= BURST_ACTIVE;
                        burst_valid  <= 1'b1;
                        burst_last   <= (burst_len == 8'd0);
                    end else begin
                        burst_valid  <= 1'b0;
                        burst_last   <= 1'b0;
                    end
                end

                BURST_ACTIVE: begin
                    if (burst_ready && burst_valid) begin
                        if (burst_last) begin
                            burst_state <= BURST_IDLE;
                            burst_valid <= 1'b0;
                            burst_last  <= 1'b0;
                        end else begin
                            beat_count   <= beat_count + 8'd1;
                            current_addr <= next_addr;
                            burst_valid  <= 1'b1;
                            burst_last   <= next_is_last;
                        end
                    end
                end

                default: burst_state <= BURST_IDLE;

            endcase
        end
    end

    // =========================================================================
    // Memory init — NOP fill (boot_ctrl loads actual program at runtime)
    // =========================================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = 32'h00000013;
    end

endmodule
