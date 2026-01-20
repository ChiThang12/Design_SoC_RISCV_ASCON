`include "memory/data_mem.v"

module data_mem_axi_slave (
    input wire clk,
    input wire rst_n,
    
    // ========================================================================
    // AXI4-Lite Slave Interface
    // ========================================================================
    
    // Write Address Channel
    input wire [31:0] S_AXI_AWADDR,
    input wire [2:0]  S_AXI_AWPROT,
    input wire        S_AXI_AWVALID,
    output reg        S_AXI_AWREADY,
    
    // Write Data Channel
    input wire [31:0] S_AXI_WDATA,
    input wire [3:0]  S_AXI_WSTRB,
    input wire        S_AXI_WVALID,
    output reg        S_AXI_WREADY,
    
    // Write Response Channel
    output reg [1:0]  S_AXI_BRESP,
    output reg        S_AXI_BVALID,
    input wire        S_AXI_BREADY,
    
    // Read Address Channel
    input wire [31:0] S_AXI_ARADDR,
    input wire [2:0]  S_AXI_ARPROT,
    input wire        S_AXI_ARVALID,
    output reg        S_AXI_ARREADY,
    
    // Read Data Channel
    output reg [31:0] S_AXI_RDATA,
    output reg [1:0]  S_AXI_RRESP,
    output reg        S_AXI_RVALID,
    input wire        S_AXI_RREADY
);

    // ========================================================================
    // AXI Response Codes
    // ========================================================================
    localparam [1:0] RESP_OKAY = 2'b00;
    
    // ========================================================================
    // State Machine for Read Channel
    // ========================================================================
    localparam [1:0]
        RD_IDLE  = 2'b00,
        RD_WAIT  = 2'b01,
        RD_RESP  = 2'b10;
    
    reg [1:0] rd_state, rd_next;
    
    // ========================================================================
    // State Machine for Write Channel
    // ========================================================================
    localparam [1:0]
        WR_IDLE  = 2'b00,
        WR_ADDR  = 2'b01,
        WR_DATA  = 2'b10,
        WR_RESP  = 2'b11;
    
    reg [1:0] wr_state, wr_next;
    
    // ========================================================================
    // Internal Signals
    // ========================================================================
    reg [31:0] wr_addr_latched;
    reg [31:0] wr_data_latched;
    reg [3:0]  wr_strb_latched;
    
    reg [31:0] rd_addr_latched;
    reg [2:0]  rd_prot_latched;
    
    reg mem_write_enable;
    wire [31:0] mem_read_data;
    
    // ========================================================================
    // Decode byte_size and sign extension
    // ========================================================================
    reg [1:0] byte_size_wr;
    reg [1:0] byte_size_rd;
    reg sign_ext;
    
    // Write: Decode from WSTRB
    always @(*) begin
        case (wr_strb_latched)
            // Byte operations (1 byte active)
            4'b0001: byte_size_wr = 2'b00;
            4'b0010: byte_size_wr = 2'b00;
            4'b0100: byte_size_wr = 2'b00;
            4'b1000: byte_size_wr = 2'b00;
            
            // Halfword operations (2 consecutive bytes)
            4'b0011: byte_size_wr = 2'b01;
            4'b1100: byte_size_wr = 2'b01;
            
            // Word operation (4 bytes)
            4'b1111: byte_size_wr = 2'b10;
            
            default: byte_size_wr = 2'b10;
        endcase
    end
    
    // Read: Decode from ARPROT[2:1]
    // ARPROT[2:1]: 00=byte, 01=halfword, 10=word
    // ARPROT[0]: 0=unsigned, 1=signed
    always @(*) begin
        byte_size_rd = rd_prot_latched[2:1];
        sign_ext = rd_prot_latched[0];
    end
    
    // ========================================================================
    // Memory address and control signals
    // ========================================================================
    wire [31:0] mem_addr;
    assign mem_addr = mem_write_enable ? wr_addr_latched : rd_addr_latched;
    
    wire [1:0] byte_size_mem;
    assign byte_size_mem = mem_write_enable ? byte_size_wr : byte_size_rd;
    
    // ========================================================================
    // Data Memory Instance
    // ========================================================================
    data_mem dmem (
        .clock(clk),
        .address(mem_addr),
        .write_data(wr_data_latched),
        .memwrite(mem_write_enable),
        .memread(!mem_write_enable && (rd_state == RD_WAIT)),
        .byte_size(byte_size_mem),
        .sign_ext(sign_ext),
        .read_data(mem_read_data)
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
                if (S_AXI_ARVALID) begin
                    rd_next = RD_WAIT;
                end
            end
            
            RD_WAIT: begin
                rd_next = RD_RESP;
            end
            
            RD_RESP: begin
                if (S_AXI_RREADY) begin
                    rd_next = RD_IDLE;
                end
            end
            
            default: rd_next = RD_IDLE;
        endcase
    end
    
    // ========================================================================
    // Read Address Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_ARREADY <= 1'b0;
            rd_addr_latched <= 32'h0;
            rd_prot_latched <= 3'h0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID) begin
                        S_AXI_ARREADY <= 1'b1;
                        rd_addr_latched <= S_AXI_ARADDR;
                        rd_prot_latched <= S_AXI_ARPROT;
                    end else begin
                        S_AXI_ARREADY <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_ARREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Read Data Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_RDATA  <= 32'h0;
            S_AXI_RRESP  <= RESP_OKAY;
            S_AXI_RVALID <= 1'b0;
        end else begin
            case (rd_state)
                RD_WAIT: begin
                    S_AXI_RDATA  <= mem_read_data;
                    S_AXI_RRESP  <= RESP_OKAY;
                    S_AXI_RVALID <= 1'b1;
                end
                
                RD_RESP: begin
                    if (S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_RVALID <= 1'b0;
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
                wr_next = WR_DATA;
            end
            
            WR_DATA: begin
                if (S_AXI_WVALID) begin
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
            wr_addr_latched <= 32'h0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (S_AXI_AWVALID) begin
                        S_AXI_AWREADY <= 1'b1;
                        wr_addr_latched <= S_AXI_AWADDR;
                    end else begin
                        S_AXI_AWREADY <= 1'b0;
                    end
                end
                
                WR_ADDR: begin
                    S_AXI_AWREADY <= 1'b0;
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
            wr_data_latched <= 32'h0;
            wr_strb_latched <= 4'h0;
        end else begin
            case (wr_state)
                WR_DATA: begin
                    if (S_AXI_WVALID) begin
                        S_AXI_WREADY <= 1'b1;
                        wr_data_latched <= S_AXI_WDATA;
                        wr_strb_latched <= S_AXI_WSTRB;
                    end else begin
                        S_AXI_WREADY <= 1'b0;
                    end
                end
                
                default: begin
                    S_AXI_WREADY <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Memory Write Enable Control
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_write_enable <= 1'b0;
        end else begin
            if (wr_state == WR_DATA && S_AXI_WVALID && !mem_write_enable) begin
                mem_write_enable <= 1'b1;
            end else begin
                mem_write_enable <= 1'b0;
            end
        end
    end
    
    // ========================================================================
    // Write Response Channel
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            S_AXI_BRESP  <= RESP_OKAY;
            S_AXI_BVALID <= 1'b0;
        end else begin
            case (wr_state)
                WR_DATA: begin
                    if (S_AXI_WVALID) begin
                        S_AXI_BRESP  <= RESP_OKAY;
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
    // Debug: Monitor memory accesses
    // ========================================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (mem_write_enable) begin
            $display("[DMEM WRITE] addr=0x%08h, data=0x%08h, strb=%b, size=%0d, time=%0t",
                     wr_addr_latched, wr_data_latched, wr_strb_latched, byte_size_wr, $time);
        end
        if (rd_state == RD_WAIT) begin
            $display("[DMEM READ]  addr=0x%08h, data=0x%08h, size=%0d, sign_ext=%b, time=%0t",
                     rd_addr_latched, mem_read_data, byte_size_rd, sign_ext, $time);
        end
    end
    // synthesis translate_on

endmodule