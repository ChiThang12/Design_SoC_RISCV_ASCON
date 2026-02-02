// ============================================================================
// data_mem_axi4_slave.v - Data Memory AXI4 Full Slave
// ============================================================================
// Description:
//   - AXI4 Full slave wrapper for data memory
//   - Supports burst read transactions for D-Cache line fills
//   - Supports burst write transactions for write-back policy
//   - Single writes for write-through policy
//   - Based on inst_mem_axi_slave.v structure
//
// Author: ChiThang
// Created: For DCache integration
// ============================================================================

`include "memory_axi4full/data_mem_burst.v"

module data_mem_axi4_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_SIZE = 1024
)(
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4 Full Slave Interface
    // ========================================================================
    
    // Write Address Channel
    input wire [ADDR_WIDTH-1:0]  S_AXI_AWADDR,
    input wire [7:0]             S_AXI_AWLEN,
    input wire [2:0]             S_AXI_AWSIZE,
    input wire [1:0]             S_AXI_AWBURST,
    input wire [2:0]             S_AXI_AWPROT,
    input wire                   S_AXI_AWVALID,
    output reg                   S_AXI_AWREADY,
    
    // Write Data Channel
    input wire [DATA_WIDTH-1:0]  S_AXI_WDATA,
    input wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input wire                   S_AXI_WLAST,
    input wire                   S_AXI_WVALID,
    output reg                   S_AXI_WREADY,
    
    // Write Response Channel
    output reg [1:0]             S_AXI_BRESP,
    output reg                   S_AXI_BVALID,
    input wire                   S_AXI_BREADY,
    
    // Read Address Channel
    input wire [ADDR_WIDTH-1:0]  S_AXI_ARADDR,
    input wire [7:0]             S_AXI_ARLEN,
    input wire [2:0]             S_AXI_ARSIZE,
    input wire [1:0]             S_AXI_ARBURST,
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
    localparam [1:0] RESP_OKAY = 2'b00;
    
    // Burst types
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;
    
    // ========================================================================
    // Read State Machine
    // ========================================================================
    localparam [1:0]
        RD_IDLE  = 2'b00,
        RD_BURST = 2'b01;
    
    reg [1:0] rd_state, rd_next;
    
    // ========================================================================
    // Write State Machine
    // ========================================================================
    localparam [2:0]
        WR_IDLE  = 3'b000,
        WR_ADDR  = 3'b001,
        WR_BURST = 3'b010,
        WR_RESP  = 3'b011;
    
    reg [2:0] wr_state, wr_next;
    
    // ========================================================================
    // Internal Signals
    // ========================================================================
    // Read transaction registers
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0] rd_burst_length;
    reg [2:0] rd_burst_size;
    reg [1:0] rd_burst_type;
    
    // Write transaction registers
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [7:0] wr_burst_length;
    reg [2:0] wr_burst_size;
    reg [1:0] wr_burst_type;
    reg [7:0] wr_beat_count;
    
    // Burst read interface
    wire [ADDR_WIDTH-1:0] burst_rd_addr;
    wire [7:0] burst_rd_len;
    reg burst_rd_req;
    wire [DATA_WIDTH-1:0] burst_rd_data;
    wire burst_rd_valid;
    wire burst_rd_last;
    wire burst_rd_ready;
    
    // Burst write interface
    wire [ADDR_WIDTH-1:0] burst_wr_addr;
    wire [7:0] burst_wr_len;
    wire [DATA_WIDTH-1:0] burst_wr_data;
    wire [3:0] burst_wr_strb;
    wire burst_wr_valid;
    wire burst_wr_ready;
    wire burst_wr_last;
    
    // Simple interface (for single transfers)
    wire [ADDR_WIDTH-1:0] simple_addr;
    wire [DATA_WIDTH-1:0] simple_wdata;
    wire simple_memwrite;
    wire simple_memread;
    wire [1:0] simple_byte_size;
    wire simple_sign_ext;
    wire [DATA_WIDTH-1:0] simple_rdata;
    
    assign burst_rd_addr = read_addr;
    assign burst_rd_len = rd_burst_length;
    assign burst_rd_ready = S_AXI_RREADY;
    
    assign burst_wr_addr = write_addr;
    assign burst_wr_len = wr_burst_length;
    assign burst_wr_data = S_AXI_WDATA;
    assign burst_wr_strb = S_AXI_WSTRB;
    assign burst_wr_valid = (wr_state == WR_BURST) && S_AXI_WVALID;
    assign burst_wr_last = S_AXI_WLAST;
    
    // Connect read outputs
    assign S_AXI_RDATA = burst_rd_data;
    assign S_AXI_RRESP = RESP_OKAY;
    assign S_AXI_RLAST = burst_rd_last;
    assign S_AXI_RVALID = burst_rd_valid;
    
    // Simple interface (unused in burst mode, keep for compatibility)
    assign simple_addr = 32'h0;
    assign simple_wdata = 32'h0;
    assign simple_memwrite = 1'b0;
    assign simple_memread = 1'b0;
    assign simple_byte_size = 2'b10;
    assign simple_sign_ext = 1'b0;
    
    // ========================================================================
    // Data Memory Instance
    // ========================================================================
    data_mem_burst #(
        .MEM_SIZE(MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dmem (
        .clk(clk),
        .rst_n(rst_n),
        
        // Simple interface
        .address(simple_addr),
        .write_data(simple_wdata),
        .memwrite(simple_memwrite),
        .memread(simple_memread),
        .byte_size(simple_byte_size),
        .sign_ext(simple_sign_ext),
        .read_data(simple_rdata),
        
        // Burst read interface
        .burst_rd_addr(burst_rd_addr),
        .burst_rd_len(burst_rd_len),
        .burst_rd_req(burst_rd_req),
        .burst_rd_data(burst_rd_data),
        .burst_rd_valid(burst_rd_valid),
        .burst_rd_last(burst_rd_last),
        .burst_rd_ready(burst_rd_ready),
        
        // Burst write interface
        .burst_wr_addr(burst_wr_addr),
        .burst_wr_len(burst_wr_len),
        .burst_wr_data(burst_wr_data),
        .burst_wr_strb(burst_wr_strb),
        .burst_wr_valid(burst_wr_valid),
        .burst_wr_ready(burst_wr_ready),
        .burst_wr_last(burst_wr_last)
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
            read_addr <= {ADDR_WIDTH{1'b0}};
            rd_burst_length <= 8'd0;
            rd_burst_size <= 3'd0;
            rd_burst_type <= 2'd0;
            burst_rd_req <= 1'b0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    S_AXI_ARREADY <= 1'b1;
                    burst_rd_req <= 1'b0;
                    
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        read_addr <= S_AXI_ARADDR;
                        rd_burst_length <= S_AXI_ARLEN;
                        rd_burst_size <= S_AXI_ARSIZE;
                        rd_burst_type <= S_AXI_ARBURST;
                        burst_rd_req <= 1'b1;
                        S_AXI_ARREADY <= 1'b0;
                    end
                end
                
                RD_BURST: begin
                    S_AXI_ARREADY <= 1'b0;
                    burst_rd_req <= 1'b0;
                end
                
                default: begin
                    S_AXI_ARREADY <= 1'b0;
                    burst_rd_req <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write State Machine - Sequential
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
        end else begin
            wr_state <= wr_next;
        end
    end
    
    // ========================================================================
    // Write State Machine - Combinational
    // ========================================================================
    always @(*) begin
        wr_next = wr_state;
        
        case (wr_state)
            WR_IDLE: begin
                if (S_AXI_AWVALID) begin
                    wr_next = WR_ADDR;
                end
            end
            
            WR_ADDR: begin
                wr_next = WR_BURST;
            end
            
            WR_BURST: begin
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
    
    // ========================================================================
    // Write Address Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_AWREADY <= 1'b0;
            write_addr <= {ADDR_WIDTH{1'b0}};
            wr_burst_length <= 8'd0;
            wr_burst_size <= 3'd0;
            wr_burst_type <= 2'd0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (S_AXI_AWVALID) begin
                        S_AXI_AWREADY <= 1'b1;
                        write_addr <= S_AXI_AWADDR;
                        wr_burst_length <= S_AXI_AWLEN;
                        wr_burst_size <= S_AXI_AWSIZE;
                        wr_burst_type <= S_AXI_AWBURST;
                    end else begin
                        S_AXI_AWREADY <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_AWREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write Data Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_WREADY <= 1'b0;
            wr_beat_count <= 8'd0;
        end else begin
            case (wr_state)
                WR_BURST: begin
                    if (S_AXI_WVALID && burst_wr_ready) begin
                        S_AXI_WREADY <= 1'b1;
                        if (!S_AXI_WLAST) begin
                            wr_beat_count <= wr_beat_count + 1'b1;
                        end else begin
                            wr_beat_count <= 8'd0;
                        end
                    end else begin
                        S_AXI_WREADY <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_WREADY <= 1'b0;
                    wr_beat_count <= 8'd0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Write Response Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BRESP <= RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
        end else begin
            case (wr_state)
                WR_BURST: begin
                    if (S_AXI_WVALID && S_AXI_WLAST) begin
                        S_AXI_BRESP <= RESP_OKAY;
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
            $display("[DMEM AXI] Read burst: addr=0x%h, len=%0d, size=%0d @ %0t",
                     S_AXI_ARADDR, S_AXI_ARLEN + 1, S_AXI_ARSIZE, $time);
        end
        
        if (S_AXI_RVALID && S_AXI_RREADY) begin
            $display("[DMEM AXI] Read data: data=0x%h, last=%b @ %0t",
                     S_AXI_RDATA, S_AXI_RLAST, $time);
        end
        
        if (S_AXI_AWVALID && S_AXI_AWREADY) begin
            $display("[DMEM AXI] Write burst: addr=0x%h, len=%0d, size=%0d @ %0t",
                     S_AXI_AWADDR, S_AXI_AWLEN + 1, S_AXI_AWSIZE, $time);
        end
        
        if (S_AXI_WVALID && S_AXI_WREADY) begin
            $display("[DMEM AXI] Write data: data=0x%h, strb=%b, last=%b @ %0t",
                     S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WLAST, $time);
        end
    end
    `endif

endmodule