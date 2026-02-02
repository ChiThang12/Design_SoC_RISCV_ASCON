// ============================================================================
// inst_mem_axi_slave.v - Instruction Memory AXI4 Full Slave
// ============================================================================
// Description:
//   - AXI4 Full slave wrapper for instruction memory
//   - Supports burst read transactions for I-Cache line fills
//   - Read-only (write operations return SLVERR)
//   - Optimized for cache coherency
//
// Author: ChiThang
// Updated: Upgraded from AXI4-Lite to AXI4 Full
// ============================================================================

`include "memory_axi4full/inst_mem.v"

module inst_mem_axi_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE = 4096,
    parameter MEM_INIT_FILE = ""
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4 Full Slave Interface
    // ========================================================================
    
    // Write Address Channel (not supported - instruction memory is read-only)
    input wire [ADDR_WIDTH-1:0]  S_AXI_AWADDR,
    input wire [7:0]             S_AXI_AWLEN,    // Burst length - 1
    input wire [2:0]             S_AXI_AWSIZE,   // 2^AWSIZE bytes per beat
    input wire [1:0]             S_AXI_AWBURST,  // Burst type
    input wire [2:0]             S_AXI_AWPROT,
    input wire                   S_AXI_AWVALID,
    output reg                   S_AXI_AWREADY,
    
    // Write Data Channel (not supported)
    input wire [DATA_WIDTH-1:0]  S_AXI_WDATA,
    input wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input wire                   S_AXI_WLAST,
    input wire                   S_AXI_WVALID,
    output reg                   S_AXI_WREADY,
    
    // Write Response Channel (always returns error)
    output reg [1:0]             S_AXI_BRESP,
    output reg                   S_AXI_BVALID,
    input wire                   S_AXI_BREADY,
    
    // Read Address Channel
    input wire [ADDR_WIDTH-1:0]  S_AXI_ARADDR,
    input wire [7:0]             S_AXI_ARLEN,    // Burst length - 1 (0-255)
    input wire [2:0]             S_AXI_ARSIZE,   // Transfer size
    input wire [1:0]             S_AXI_ARBURST,  // 00=FIXED, 01=INCR, 10=WRAP
    input wire [2:0]             S_AXI_ARPROT,
    input wire                   S_AXI_ARVALID,
    output reg                   S_AXI_ARREADY,
    
    // Read Data Channel
    output wire [DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0]            S_AXI_RRESP,
    output wire                  S_AXI_RLAST,
    output wire                  S_AXI_RVALID,
    input wire                   S_AXI_RREADY
);

    // ========================================================================
    // AXI Response Codes
    // ========================================================================
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;
    
    // Burst types
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;
    
    // ========================================================================
    // Read State Machine
    // ========================================================================
    localparam [1:0]
        RD_IDLE    = 2'b00,
        RD_BURST   = 2'b01,
        RD_WAIT    = 2'b10;
    
    reg [1:0] rd_state, rd_next;
    
    // ========================================================================
    // Write State Machine (for error responses)
    // ========================================================================
    localparam [1:0]
        WR_IDLE = 2'b00,
        WR_ADDR = 2'b01,
        WR_DATA = 2'b10,
        WR_RESP = 2'b11;
    
    reg [1:0] wr_state, wr_next;
    
    // ========================================================================
    // Internal Signals
    // ========================================================================
    // Read transaction registers
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0] burst_length;
    reg [2:0] burst_size;
    reg [1:0] burst_type;
    
    // Simple PC interface (for single reads)
    wire [ADDR_WIDTH-1:0] simple_pc;
    wire [DATA_WIDTH-1:0] simple_inst;
    
    // Burst interface
    wire [ADDR_WIDTH-1:0] burst_addr;
    wire [7:0] burst_len;
    reg burst_req;
    wire [DATA_WIDTH-1:0] burst_data;
    wire burst_valid;
    wire burst_last;
    wire burst_ready;
    
    // Use burst interface when in burst state
    assign simple_pc = read_addr;
    assign burst_addr = read_addr;
    assign burst_len = burst_length;
    assign burst_ready = S_AXI_RREADY;
    
    // Connect outputs
    assign S_AXI_RDATA = burst_data;
    assign S_AXI_RRESP = RESP_OKAY;
    assign S_AXI_RLAST = burst_last;
    assign S_AXI_RVALID = burst_valid;
    
    // ========================================================================
    // Instruction Memory Instance
    // ========================================================================
    inst_mem #(
        .MEM_SIZE(MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) imem (
        .clk(clk),
        .rst_n(rst_n),
        
        // Simple interface (unused in burst mode)
        .PC(simple_pc),
        .Instruction_Code(simple_inst),
        
        // Burst interface
        .burst_addr(burst_addr),
        .burst_len(burst_len),
        .burst_req(burst_req),
        .burst_data(burst_data),
        .burst_valid(burst_valid),
        .burst_last(burst_last),
        .burst_ready(burst_ready)
    );
    
    // ========================================================================
    // Read State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
        end else begin
            rd_state <= rd_next;
        end
    end
    
    // ========================================================================
    // Read State Machine - Combinational
    // ========================================================================
    always @(*) begin
        rd_next = rd_state;
        
        case (rd_state)
            RD_IDLE: begin
                if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                    rd_next = RD_BURST;
                end
            end
            
            RD_BURST: begin
                // Stay in burst until last transfer
                if (S_AXI_RVALID && S_AXI_RREADY && S_AXI_RLAST) begin
                    rd_next = RD_IDLE;
                end
            end
            
            default: rd_next = RD_IDLE;
        endcase
    end
    
    // ========================================================================
    // Read Address Channel Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY <= 1'b0;
            read_addr     <= {ADDR_WIDTH{1'b0}};
            burst_length  <= 8'd0;
            burst_size    <= 3'd0;
            burst_type    <= 2'd0;
            burst_req     <= 1'b0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    S_AXI_ARREADY <= 1'b1;  // Always ready in idle
                    burst_req <= 1'b0;
                    
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        // Latch burst parameters
                        read_addr    <= S_AXI_ARADDR;
                        burst_length <= S_AXI_ARLEN;
                        burst_size   <= S_AXI_ARSIZE;
                        burst_type   <= S_AXI_ARBURST;
                        
                        // Trigger burst read
                        burst_req <= 1'b1;
                        S_AXI_ARREADY <= 1'b0;
                    end
                end
                
                RD_BURST: begin
                    S_AXI_ARREADY <= 1'b0;
                    burst_req <= 1'b0;  // Clear after one cycle
                end
                
                default: begin
                    S_AXI_ARREADY <= 1'b0;
                    burst_req <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write Channels - Not Supported (Return Error)
    // ========================================================================
    
    // Write state machine - sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
        end else begin
            wr_state <= wr_next;
        end
    end
    
    // Write state machine - combinational
    always @(*) begin
        wr_next = wr_state;
        
        case (wr_state)
            WR_IDLE: begin
                if (S_AXI_AWVALID) begin
                    wr_next = WR_ADDR;
                end
            end
            
            WR_ADDR: begin
                wr_next = WR_DATA;
            end
            
            WR_DATA: begin
                if (S_AXI_WVALID && S_AXI_WLAST) begin
                    wr_next = WR_RESP;
                end
            end
            
            WR_RESP: begin
                if (S_AXI_BREADY) begin
                    wr_next = WR_IDLE;
                end
            end
            
            default: wr_next = WR_IDLE;
        endcase
    end
    
    // Write address channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY <= 1'b0;
        end else begin
            if (wr_state == WR_IDLE && S_AXI_AWVALID) begin
                S_AXI_AWREADY <= 1'b1;
            end else begin
                S_AXI_AWREADY <= 1'b0;
            end
        end
    end
    
    // Write data channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_WREADY <= 1'b0;
        end else begin
            if (wr_state == WR_DATA && S_AXI_WVALID) begin
                S_AXI_WREADY <= 1'b1;
            end else begin
                S_AXI_WREADY <= 1'b0;
            end
        end
    end
    
    // Write response channel (always error)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BRESP  <= RESP_SLVERR;
            S_AXI_BVALID <= 1'b0;
        end else begin
            case (wr_state)
                WR_DATA: begin
                    if (S_AXI_WVALID && S_AXI_WLAST) begin
                        S_AXI_BRESP  <= RESP_SLVERR;  // Read-only memory
                        S_AXI_BVALID <= 1'b1;
                    end
                end
                
                WR_RESP: begin
                    if (S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_BVALID <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Debug/Simulation
    // ========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (S_AXI_ARVALID && S_AXI_ARREADY) begin
            $display("[IMEM AXI] Read burst: addr=0x%h, len=%0d, size=%0d, type=%0d @ %0t",
                     S_AXI_ARADDR, S_AXI_ARLEN + 1, S_AXI_ARSIZE, S_AXI_ARBURST, $time);
        end
        
        if (S_AXI_RVALID && S_AXI_RREADY) begin
            $display("[IMEM AXI] Read data: data=0x%h, last=%b @ %0t",
                     S_AXI_RDATA, S_AXI_RLAST, $time);
        end
        
        if (wr_state == WR_RESP && S_AXI_BREADY) begin
            $display("[IMEM WARNING] Write attempt to ROM rejected @ %0t", $time);
        end
    end
    `endif

endmodule