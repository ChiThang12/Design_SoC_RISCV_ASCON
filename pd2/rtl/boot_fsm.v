`timescale 1ns/1ps

// ============================================================================
// boot_fsm.v — Boot FSM
//
// Runs on fabric_rst_n domain (independent of cpu_rst_n).
// Copies PROG_WORDS words from boot_rom into IMEM via sideband write port,
// one word per clock cycle. Asserts boot_done when finished (sticky).
//
// Timing:
//   Cycle 0: rst_n rises → move to WRITING, write word 0
//   Cycle N-1: write word PROG_WORDS-1
//   Cycle N: move to DONE, assert boot_done
//   cpu_rst_n in clk_reset_ctrl: released when boot_done=1
// ============================================================================

module boot_fsm #(
    parameter PROG_WORDS = 2048
)(
    input  wire                          clk,
    input  wire                          rst_n,       // fabric_rst_n

    // ROM read port
    output reg  [$clog2(PROG_WORDS)-1:0] rom_addr,
    input  wire [31:0]                   rom_data,

    // IMEM sideband write port
    output reg                           boot_we,
    output reg  [31:0]                   boot_addr,   // byte address
    output reg  [31:0]                   boot_wdata,

    // Status
    output reg                           boot_done
);

    localparam ST_IDLE    = 2'd0;
    localparam ST_WRITING = 2'd1;
    localparam ST_DONE    = 2'd2;

    reg [1:0]                          state;
    reg [$clog2(PROG_WORDS)-1:0]       word_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            word_idx   <= {$clog2(PROG_WORDS){1'b0}};
            rom_addr   <= {$clog2(PROG_WORDS){1'b0}};
            boot_we    <= 1'b0;
            boot_addr  <= 32'h0;
            boot_wdata <= 32'h0;
            boot_done  <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // One cycle after rst_n, immediately start writing
                    state      <= ST_WRITING;
                    word_idx   <= {$clog2(PROG_WORDS){1'b0}};
                    rom_addr   <= {$clog2(PROG_WORDS){1'b0}};
                    boot_we    <= 1'b0;
                    boot_done  <= 1'b0;
                end

                ST_WRITING: begin
                    // Drive sideband write for current word_idx
                    // rom_addr was set previous cycle → rom_data is valid now
                    boot_we    <= 1'b1;
                    boot_addr  <= {word_idx, 2'b00};   // byte address
                    boot_wdata <= rom_data;

                    if (word_idx == PROG_WORDS - 1) begin
                        state    <= ST_DONE;
                        rom_addr <= {$clog2(PROG_WORDS){1'b0}};
                    end else begin
                        word_idx <= word_idx + 1'b1;
                        rom_addr <= word_idx + 1'b1;   // pre-fetch next word
                    end
                end

                ST_DONE: begin
                    boot_we   <= 1'b0;
                    boot_done <= 1'b1;   // sticky, never cleared
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
