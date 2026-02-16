// ============================================================================
// LSU.v - Load-Store Unit (Non-blocking Memory Subsystem)
// ============================================================================
// ICARUS VERILOG COMPATIBLE VERSION
// ============================================================================

module LSU (
    input wire clk,
    input wire rst,
    input wire result_ack, 
    // ========================================================================
    // PIPELINE INTERFACE - Request từ EX stage
    // ========================================================================
    input  wire        req_valid,       // Pipeline muốn gửi memory request
    output wire        req_ready,       // LSU sẵn sàng nhận request
    input  wire [31:0] req_addr,        // Memory address
    input  wire [31:0] req_wdata,       // Write data
    input  wire [3:0]  req_wstrb,       // Write strobe
    input  wire        req_is_load,     // 1=load, 0=store
    input  wire [4:0]  req_rd,          // Destination register
    input  wire [2:0]  req_funct3,      // funct3 (LB, LH, LW, LBU, LHU)
    
    // ========================================================================
    // PIPELINE INTERFACE - Result trả về WB stage
    // ========================================================================
    output wire        result_valid,    // LSU có kết quả sẵn sàng
    output wire [31:0] result_data,     // Load data
    output wire [4:0]  result_rd,       // Destination register
    
    // ========================================================================
    // SCOREBOARD INTERFACE - Tracking pending loads
    // ========================================================================
    output wire [31:0] scoreboard,      // Bitmask: bit[i]=1 → register x[i] đang chờ load
    
    // ========================================================================
    // MEMORY INTERFACE (AXI-like)
    // ========================================================================
    output reg  [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg  [3:0]  dmem_wstrb,
    output reg         dmem_valid,
    output reg         dmem_we,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_ready
);

    // ========================================================================
    // PARAMETERS
    // ========================================================================
    localparam QUEUE_DEPTH = 4;
    
    // ========================================================================
    // Request Queue (FIFO) - Fixed depth 4
    // ========================================================================
    reg [31:0] queue_addr   [0:3];
    reg [31:0] queue_wdata  [0:3];
    reg [3:0]  queue_wstrb  [0:3];
    reg        queue_is_load[0:3];
    reg [4:0]  queue_rd     [0:3];
    reg [2:0]  queue_funct3 [0:3];
    reg        queue_valid  [0:3];
    
    // Queue pointers - 2 bits for depth=4
    reg [1:0] wr_ptr;  // Write pointer (0-3)
    reg [1:0] rd_ptr;  // Read pointer (0-3)
    reg [2:0] count;   // Entry counter (0-4)
    
    // Queue status
    wire queue_full  = (count == 3'd4);
    wire queue_empty = (count == 3'd0);
    
    // Request ready = queue chưa full
    assign req_ready = !queue_full;
    
    // ========================================================================
    // Result Buffer (cho load instructions)
    // ========================================================================
    reg        result_buffer_valid;
    reg [31:0] result_buffer_data;
    reg [4:0]  result_buffer_rd;
    
    assign result_valid = result_buffer_valid;
    assign result_data  = result_buffer_data;
    assign result_rd    = result_buffer_rd;
    
    // ========================================================================
    // Scoreboard - Track pending loads
    // ========================================================================
    reg [31:0] scoreboard_reg;
    assign scoreboard = scoreboard_reg;
    
    // ========================================================================
    // FSM States
    // ========================================================================
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] WAIT_MEM = 2'b01;
    localparam [1:0] PROCESS  = 2'b10;
    
    reg [1:0] state;
    
    // ========================================================================
    // Current request being processed
    // ========================================================================
    reg [31:0] current_addr;
    reg [31:0] current_wdata;
    reg [3:0]  current_wstrb;
    reg        current_is_load;
    reg [4:0]  current_rd;
    reg [2:0]  current_funct3;
    
    // ========================================================================
    // Queue Management
    // ========================================================================
    integer i;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 2'b00;
            rd_ptr <= 2'b00;
            count  <= 3'b000;
            for (i = 0; i < 4; i = i + 1) begin
                queue_valid[i] <= 1'b0;
            end
        end else begin
            // Handle enqueue and dequeue simultaneously
            case ({req_valid && req_ready, !queue_empty && state == IDLE})
                2'b10: begin
                    // Only enqueue
                    queue_addr[wr_ptr]    <= req_addr;
                    queue_wdata[wr_ptr]   <= req_wdata;
                    queue_wstrb[wr_ptr]   <= req_wstrb;
                    queue_is_load[wr_ptr] <= req_is_load;
                    queue_rd[wr_ptr]      <= req_rd;
                    queue_funct3[wr_ptr]  <= req_funct3;
                    queue_valid[wr_ptr]   <= 1'b1;
                    wr_ptr <= wr_ptr + 2'b01;
                    count  <= count + 3'b001;
                end
                
                2'b01: begin
                    // Only dequeue
                    queue_valid[rd_ptr] <= 1'b0;
                    rd_ptr <= rd_ptr + 2'b01;
                    count  <= count - 3'b001;
                end
                
                2'b11: begin
                    // Both enqueue and dequeue
                    queue_addr[wr_ptr]    <= req_addr;
                    queue_wdata[wr_ptr]   <= req_wdata;
                    queue_wstrb[wr_ptr]   <= req_wstrb;
                    queue_is_load[wr_ptr] <= req_is_load;
                    queue_rd[wr_ptr]      <= req_rd;
                    queue_funct3[wr_ptr]  <= req_funct3;
                    queue_valid[wr_ptr]   <= 1'b1;
                    wr_ptr <= wr_ptr + 2'b01;
                    
                    queue_valid[rd_ptr] <= 1'b0;
                    rd_ptr <= rd_ptr + 2'b01;
                    // count stays the same
                end
                
                default: begin
                    // No change
                end
            endcase
        end
    end
    
    // ========================================================================
    // LSU FSM - Xử lý memory requests
    // ========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            dmem_valid <= 1'b0;
            dmem_we    <= 1'b0;
            dmem_addr  <= 32'h0;
            dmem_wdata <= 32'h0;
            dmem_wstrb <= 4'h0;
            result_buffer_valid <= 1'b0;
            result_buffer_data  <= 32'h0;
            result_buffer_rd    <= 5'h0;
            scoreboard_reg <= 32'h0;
            current_addr    <= 32'h0;
            current_wdata   <= 32'h0;
            current_wstrb   <= 4'h0;
            current_is_load <= 1'b0;
            current_rd      <= 5'h0;
            current_funct3  <= 3'h0;
        end else begin
            case (state)
                // ============================================================
                // IDLE: Chờ request từ queue
                // ============================================================
                IDLE: begin
                    if (!queue_empty && queue_valid[rd_ptr]) begin
                        // Lấy request từ queue
                        current_addr    <= queue_addr[rd_ptr];
                        current_wdata   <= queue_wdata[rd_ptr];
                        current_wstrb   <= queue_wstrb[rd_ptr];
                        current_is_load <= queue_is_load[rd_ptr];
                        current_rd      <= queue_rd[rd_ptr];
                        current_funct3  <= queue_funct3[rd_ptr];
                        
                        // Gửi request xuống memory
                        dmem_addr  <= queue_addr[rd_ptr];
                        dmem_wdata <= queue_wdata[rd_ptr];
                        dmem_wstrb <= queue_wstrb[rd_ptr];
                        dmem_we    <= !queue_is_load[rd_ptr];  // 0=load, 1=store
                        dmem_valid <= 1'b1;
                        
                        // Update scoreboard: Mark register as pending
                        if (queue_is_load[rd_ptr] && queue_rd[rd_ptr] != 5'b0) begin
                            scoreboard_reg[queue_rd[rd_ptr]] <= 1'b1;
                        end
                        
                        state <= WAIT_MEM;
                    end else begin
                        dmem_valid <= 1'b0;
                        result_buffer_valid <= 1'b0;
                    end
                end
                
                // ============================================================
                // WAIT_MEM: Chờ memory response
                // ============================================================
                WAIT_MEM: begin
                    if (dmem_ready) begin
                        dmem_valid <= 1'b0;
                        
                        // Nếu là LOAD: Lưu kết quả vào result buffer
                        if (current_is_load) begin
                            result_buffer_valid <= 1'b1;
                            result_buffer_rd    <= current_rd;
                            
                            // Extend data dựa theo funct3
                            case (current_funct3)
                                3'b000: result_buffer_data <= {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};    // LB
                                3'b001: result_buffer_data <= {{16{dmem_rdata[15]}}, dmem_rdata[15:0]}; // LH
                                3'b010: result_buffer_data <= dmem_rdata;                                // LW
                                3'b100: result_buffer_data <= {24'h0, dmem_rdata[7:0]};                  // LBU
                                3'b101: result_buffer_data <= {16'h0, dmem_rdata[15:0]};                 // LHU
                                default: result_buffer_data <= dmem_rdata;
                            endcase
                            
                            // Clear scoreboard bit
                            if (current_rd != 5'b0) begin
                                scoreboard_reg[current_rd] <= 1'b0;
                            end
                        end else begin
                            // STORE: không có result
                            result_buffer_valid <= 1'b0;
                        end
                        
                        state <= PROCESS;
                    end
                end
                
                // ============================================================
                // PROCESS: Clear result buffer, quay lại IDLE
                // ============================================================
                PROCESS: begin
                        if (result_ack) begin  // New input signal
                            result_buffer_valid <= 1'b0;
                            state <= IDLE;
                        end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule