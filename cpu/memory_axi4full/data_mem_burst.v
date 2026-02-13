// ============================================================================
// data_mem_burst.v - Data Memory with Burst Read/Write Support
// ============================================================================
// Description:
//   - Data memory array (1KB)
//   - Supports both single access and burst read/write
//   - Read/Write memory (RAM)
//   - Byte-enable write support
//   - Based on inst_mem.v structure
//
// Author: ChiThang
// Created: For DCache integration
// ============================================================================

module data_mem_burst #(
    parameter MEM_SIZE = 1024,        // Memory size in bytes (1KB)
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // Simple Interface (for backwards compatibility with data_mem_axi_slave)
    // ========================================================================
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire                  memwrite,
    input  wire                  memread,
    input  wire [1:0]            byte_size,
    input  wire                  sign_ext,
    output reg  [DATA_WIDTH-1:0] read_data,
    
    // ========================================================================
    // Burst Read Interface (for cache line fills)
    // ========================================================================
    input  wire [ADDR_WIDTH-1:0] burst_rd_addr,
    input  wire [7:0]            burst_rd_len,
    input  wire                  burst_rd_req,
    output reg  [DATA_WIDTH-1:0] burst_rd_data,
    output reg                   burst_rd_valid,
    output reg                   burst_rd_last,
    input  wire                  burst_rd_ready,
    
    // ========================================================================
    // Burst Write Interface (for write-through or write-back)
    // ========================================================================
    input  wire [ADDR_WIDTH-1:0] burst_wr_addr,
    input  wire [7:0]            burst_wr_len,
    input  wire [DATA_WIDTH-1:0] burst_wr_data,
    input  wire [3:0]            burst_wr_strb,
    input  wire                  burst_wr_valid,
    output wire                   burst_wr_ready,
    input  wire                  burst_wr_last
);

    // ========================================================================
    // Local Parameters
    // ========================================================================
    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);  // 256 words
    localparam ADDR_LSB = $clog2(DATA_WIDTH/8);        // 2 for 32-bit
    
    // ========================================================================
    // Memory Array (byte-addressable for flexibility)
    // ========================================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    
    // ========================================================================
    // Helper function to get word address
    // ========================================================================
    function [9:0] get_word_addr;
        input [31:0] byte_addr;
        begin
            get_word_addr = byte_addr[9:2];
        end
    endfunction
    
    // ========================================================================
    // Simple Read/Write Interface (Combinational/Sequential)
    // ========================================================================
    wire [9:0] simple_word_addr;
    wire [1:0] byte_offset;
    wire [9:0] aligned_addr;
    
    assign simple_word_addr = address[9:2];
    assign byte_offset = address[1:0];
    assign aligned_addr = {address[9:2], 2'b00};
    
    // Simple write (sequential - same as original data_mem.v)
    always @(posedge clk) begin
        if (memwrite && !burst_wr_valid) begin  // Priority to burst
            case (byte_size)
                2'b00: begin  // Store Byte
                    case (byte_offset)
                        2'b00: memory[aligned_addr + 0] <= write_data[7:0];
                        2'b01: memory[aligned_addr + 1] <= write_data[7:0];
                        2'b10: memory[aligned_addr + 2] <= write_data[7:0];
                        2'b11: memory[aligned_addr + 3] <= write_data[7:0];
                    endcase
                end
                
                2'b01: begin  // Store Halfword
                    case (byte_offset[1])
                        1'b0: begin
                            memory[aligned_addr + 0] <= write_data[7:0];
                            memory[aligned_addr + 1] <= write_data[15:8];
                        end
                        1'b1: begin
                            memory[aligned_addr + 2] <= write_data[7:0];
                            memory[aligned_addr + 3] <= write_data[15:8];
                        end
                    endcase
                end
                
                2'b10: begin  // Store Word
                    memory[aligned_addr + 0] <= write_data[7:0];
                    memory[aligned_addr + 1] <= write_data[15:8];
                    memory[aligned_addr + 2] <= write_data[23:16];
                    memory[aligned_addr + 3] <= write_data[31:24];
                end
            endcase
        end
    end
    
    // Simple read (combinational - same as original)
    always @(*) begin
        if (memread) begin
            case (byte_size)
                2'b00: begin  // Load Byte
                    case (byte_offset)
                        2'b00: read_data = sign_ext ? 
                            {{24{memory[aligned_addr + 0][7]}}, memory[aligned_addr + 0]} :
                            {24'h000000, memory[aligned_addr + 0]};
                        2'b01: read_data = sign_ext ?
                            {{24{memory[aligned_addr + 1][7]}}, memory[aligned_addr + 1]} :
                            {24'h000000, memory[aligned_addr + 1]};
                        2'b10: read_data = sign_ext ?
                            {{24{memory[aligned_addr + 2][7]}}, memory[aligned_addr + 2]} :
                            {24'h000000, memory[aligned_addr + 2]};
                        2'b11: read_data = sign_ext ?
                            {{24{memory[aligned_addr + 3][7]}}, memory[aligned_addr + 3]} :
                            {24'h000000, memory[aligned_addr + 3]};
                    endcase
                end
                
                2'b01: begin  // Load Halfword
                    case (byte_offset[1])
                        1'b0: read_data = sign_ext ?
                            {{16{memory[aligned_addr + 1][7]}}, 
                             memory[aligned_addr + 1], memory[aligned_addr + 0]} :
                            {16'h0000, memory[aligned_addr + 1], memory[aligned_addr + 0]};
                        1'b1: read_data = sign_ext ?
                            {{16{memory[aligned_addr + 3][7]}}, 
                             memory[aligned_addr + 3], memory[aligned_addr + 2]} :
                            {16'h0000, memory[aligned_addr + 3], memory[aligned_addr + 2]};
                    endcase
                end
                
                2'b10: begin  // Load Word
                    read_data = {memory[aligned_addr + 3], memory[aligned_addr + 2],
                               memory[aligned_addr + 1], memory[aligned_addr + 0]};
                end
                
                default: read_data = 32'h00000000;
            endcase
        end else begin
            read_data = 32'h00000000;
        end
    end
    
    // ========================================================================
    // Burst Read State Machine
    // ========================================================================
    localparam RD_BURST_IDLE = 1'b0;
    localparam RD_BURST_ACTIVE = 1'b1;
    
    reg rd_burst_state;
    reg [ADDR_WIDTH-1:0] rd_current_addr;
    reg [7:0] rd_beat_count;
    reg [7:0] rd_total_beats;
    
    wire [ADDR_WIDTH-1:0] rd_word_addr;
    assign rd_word_addr = rd_current_addr[ADDR_WIDTH-1:ADDR_LSB];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_burst_state <= RD_BURST_IDLE;
            burst_rd_data  <= {DATA_WIDTH{1'b0}};
            burst_rd_valid <= 1'b0;
            burst_rd_last  <= 1'b0;
            rd_current_addr <= {ADDR_WIDTH{1'b0}};
            rd_beat_count  <= 8'd0;
            rd_total_beats <= 8'd0;
        end else begin
            case (rd_burst_state)
                RD_BURST_IDLE: begin
                    if (burst_rd_req) begin
                        rd_current_addr <= burst_rd_addr;
                        rd_beat_count   <= 8'd0;
                        rd_total_beats  <= burst_rd_len;
                        rd_burst_state  <= RD_BURST_ACTIVE;
                        
                        // Output first word
                        burst_rd_data <= {
                            memory[burst_rd_addr + 3],
                            memory[burst_rd_addr + 2],
                            memory[burst_rd_addr + 1],
                            memory[burst_rd_addr + 0]
                        };
                        burst_rd_valid <= 1'b1;
                        burst_rd_last  <= (burst_rd_len == 8'd0);
                    end else begin
                        burst_rd_valid <= 1'b0;
                        burst_rd_last  <= 1'b0;
                    end
                end
                
                RD_BURST_ACTIVE: begin
                    if (burst_rd_ready && burst_rd_valid) begin
                        if (burst_rd_last) begin
                            rd_burst_state <= RD_BURST_IDLE;
                            burst_rd_valid <= 1'b0;
                            burst_rd_last  <= 1'b0;
                        end else begin
                            rd_beat_count   <= rd_beat_count + 1'b1;
                            rd_current_addr <= rd_current_addr + (DATA_WIDTH/8);
                            
                            // Output next word
                            burst_rd_data <= {
                                memory[rd_current_addr + 7],
                                memory[rd_current_addr + 6],
                                memory[rd_current_addr + 5],
                                memory[rd_current_addr + 4]
                            };
                            burst_rd_valid <= 1'b1;
                            burst_rd_last  <= (rd_beat_count + 1 == rd_total_beats);
                        end
                    end
                end
            endcase
        end
    end
    
    // ========================================================================
    // Burst Write Logic
    // ========================================================================
    reg [ADDR_WIDTH-1:0] wr_current_addr;
    
    assign burst_wr_ready = 1'b1;  // memory luôn sẵn sàng nhận write
                                    // (không có back-pressure thực sự)

    // Giữ lại phần ghi memory trong always @(posedge clk):
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_current_addr <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (burst_wr_valid && burst_wr_ready) begin
                if (burst_wr_strb[0]) memory[wr_current_addr+0] <= burst_wr_data[7:0];
                if (burst_wr_strb[1]) memory[wr_current_addr+1] <= burst_wr_data[15:8];
                if (burst_wr_strb[2]) memory[wr_current_addr+2] <= burst_wr_data[23:16];
                if (burst_wr_strb[3]) memory[wr_current_addr+3] <= burst_wr_data[31:24];

                if (!burst_wr_last)
                    wr_current_addr <= wr_current_addr + (DATA_WIDTH/8);
                else
                    wr_current_addr <= burst_wr_addr;
            end else if (!burst_wr_valid) begin
                wr_current_addr <= burst_wr_addr;
            end
        end
    end
        
    // ========================================================================
    // Memory Initialization
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            memory[i] = 8'h00;
        end
    end
    
    // ========================================================================
    // Debug/Simulation
    // ========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (burst_rd_req && rd_burst_state == RD_BURST_IDLE) begin
            $display("[DMEM] Burst read: addr=0x%h, len=%0d", burst_rd_addr, burst_rd_len + 1);
        end
        if (burst_rd_valid && burst_rd_ready) begin
            $display("[DMEM] Burst read data[%0d]: addr=0x%h, data=0x%h, last=%b",
                     rd_beat_count, rd_current_addr, burst_rd_data, burst_rd_last);
        end
        if (burst_wr_valid && burst_wr_ready) begin
            $display("[DMEM] Burst write: addr=0x%h, data=0x%h, strb=%b, last=%b",
                     wr_current_addr, burst_wr_data, burst_wr_strb, burst_wr_last);
        end
    end
    `endif

endmodule