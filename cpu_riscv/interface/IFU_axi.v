// ============================================================================
// IFU_AXI.v - Instruction Fetch Unit with AXI Interface
// ============================================================================
// Mô tả:
//   - Fetch instruction qua memory interface (thay vì trực tiếp inst_mem)
//   - Tương thích với mem_access_unit
//   - State machine xử lý wait states khi memory chưa ready
// ============================================================================

module IFU_AXI (
    input wire clk,
    input wire rst_n,              // Active low reset
    
    // ========================================================================
    // Control signals
    // ========================================================================
    input wire pc_src,              // 0: PC+4 (sequential), 1: target_pc (branch/jump)
    input wire stall,               // 1: giữ nguyên PC (pipeline stall)
    
    // Branch/Jump target address
    input wire [31:0] target_pc,    // Địa chỉ nhảy đến
    
    // ========================================================================
    // Memory Interface (kết nối tới mem_access_unit)
    // ========================================================================
    output reg [31:0] imem_addr,    // Địa chỉ instruction
    output reg        imem_req,     // Request valid
    input wire [31:0] imem_data,    // Instruction data
    input wire        imem_ready,   // Data ready (pulse)
    input wire        imem_error,   // Bus error
    
    // ========================================================================
    // Outputs
    // ========================================================================
    output reg [31:0] PC_out,            // Current PC
    output reg [31:0] Instruction_Code,  // Instruction được fetch
    output reg        fetch_valid         // Instruction valid (không phải đang fetch)
);

    // ========================================================================
    // State Machine Definition
    // ========================================================================
    localparam [1:0]
        FETCH_IDLE   = 2'b00,   // Sẵn sàng fetch
        FETCH_REQ    = 2'b01,   // Đã gửi request, chờ ready
        FETCH_WAIT   = 2'b10;   // Chờ stall release
    
    reg [1:0] fetch_state, fetch_next;
    
    // ========================================================================
    // Program Counter Register
    // ========================================================================
    reg [31:0] PC;
    
    // ========================================================================
    // Next PC Calculation
    // ========================================================================
    wire [31:0] next_pc;
    wire [31:0] pc_plus_4;
    
    assign pc_plus_4 = PC + 32'd4;
    
    // Logic tính next_pc:
    // - Nếu stall=1: giữ nguyên PC
    // - Nếu pc_src=1: nhảy đến target_pc (branch/jump)
    // - Nếu pc_src=0: PC + 4 (sequential)
    assign next_pc = stall ? PC : 
                     pc_src ? target_pc : 
                     pc_plus_4;
    
    // ========================================================================
    // State Machine - Sequential Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_state <= FETCH_IDLE;
        end else begin
            fetch_state <= fetch_next;
        end
    end
    
    // ========================================================================
    // State Machine - Next State Logic
    // ========================================================================
    always @(*) begin
        fetch_next = fetch_state;
        
        case (fetch_state)
            FETCH_IDLE: begin
                // Luôn gửi request khi không stall
                if (!stall) begin
                    fetch_next = FETCH_REQ;
                end
            end
            
            FETCH_REQ: begin
                if (imem_ready) begin
                    // Data đã về
                    if (stall) begin
                        // Nếu pipeline stall, chờ ở WAIT
                        fetch_next = FETCH_WAIT;
                    end else begin
                        // Tiếp tục fetch instruction tiếp theo
                        fetch_next = FETCH_REQ;
                    end
                end
                // Nếu chưa ready, giữ nguyên state
            end
            
            FETCH_WAIT: begin
                // Chờ stall release
                if (!stall) begin
                    fetch_next = FETCH_REQ;
                end
            end
            
            default: fetch_next = FETCH_IDLE;
        endcase
    end
    
    // ========================================================================
    // Program Counter Update
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PC <= 32'h00000000;     // Reset PC về địa chỉ 0x00000000
        end else begin
            // Chỉ update PC khi:
            // 1. Không stall, HOẶC
            // 2. Có branch/jump (pc_src=1)
            if (!stall || pc_src) begin
                PC <= next_pc;
            end
        end
    end
    
    // ========================================================================
    // Memory Request Generation
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_addr <= 32'h00000000;
            imem_req  <= 1'b0;
        end else begin
            case (fetch_state)
                FETCH_IDLE: begin
                    if (!stall) begin
                        imem_addr <= PC;
                        imem_req  <= 1'b1;
                    end else begin
                        imem_req  <= 1'b0;
                    end
                end
                
                FETCH_REQ: begin
                    if (imem_ready) begin
                        if (!stall) begin
                            // Fetch instruction tiếp theo
                            imem_addr <= next_pc;
                            imem_req  <= 1'b1;
                        end else begin
                            // Stall, không fetch nữa
                            imem_req  <= 1'b0;
                        end
                    end
                    // Giữ request high cho đến khi ready
                end
                
                FETCH_WAIT: begin
                    if (!stall) begin
                        // Stall release, fetch tiếp
                        imem_addr <= next_pc;
                        imem_req  <= 1'b1;
                    end else begin
                        imem_req  <= 1'b0;
                    end
                end
                
                default: begin
                    imem_req <= 1'b0;
                end
            endcase
        end
    end
    
    // ========================================================================
    // Instruction Latch
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Instruction_Code <= 32'h00000013;  // NOP (ADDI x0, x0, 0)
        end else if (imem_ready && !imem_error) begin
            Instruction_Code <= imem_data;
        end else if (imem_error) begin
            // Nếu có lỗi bus, insert NOP
            Instruction_Code <= 32'h00000013;
        end
    end
    
    // ========================================================================
    // Fetch Valid Signal
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_valid <= 1'b0;
        end else begin
            // Valid khi đã nhận được instruction (imem_ready pulse)
            fetch_valid <= imem_ready && !imem_error;
        end
    end
    
    // ========================================================================
    // Output Current PC
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PC_out <= 32'h00000000;
        end else begin
            PC_out <= PC;
        end
    end
    
    // ========================================================================
    // Error Handling (Optional - for debug)
    // ========================================================================
    // synthesis translate_off
    always @(posedge clk) begin
        if (imem_error && imem_ready) begin
            $display("[IFU ERROR] Bus error at PC=0x%08h, time=%0t", PC, $time);
        end
    end
    // synthesis translate_on

endmodule