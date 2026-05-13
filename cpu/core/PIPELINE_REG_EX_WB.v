`timescale 1ns/1ps

module PIPELINE_REG_EX_WB (
    // --- Clock & Reset ---
    input  wire        clock,
    input  wire        reset,
    
    // --- Control signals input ---
    input  wire        regwrite_in,
    input  wire        memtoreg_in,
    
    // --- Data inputs ---
    input  wire [31:0] alu_result_in,
    input  wire [31:0] mem_data_in,
    
    // --- Register address input ---
    input  wire [4:0]  rd_in,
    
    // --- Control signals output ---
    output reg         regwrite_out,
    output reg         memtoreg_out,
    
    // --- Data outputs ---
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mem_data_out,
    
    // --- Register address output ---
    output reg  [4:0]  rd_out
);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            // Reset: Clear all signals
            regwrite_out <= 1'b0;
            memtoreg_out <= 1'b0;
            alu_result_out <= 32'h00000000;
            mem_data_out <= 32'h00000000;
            rd_out <= 5'b00000;
        end
        else begin
            // Normal operation: Update all signals every clock cycle
            regwrite_out <= regwrite_in;
            memtoreg_out <= memtoreg_in;
            alu_result_out <= alu_result_in;
            mem_data_out <= mem_data_in;
            rd_out <= rd_in;
        end
    end

endmodule