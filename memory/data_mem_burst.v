// ============================================================================
// data_mem_burst.v - Data Memory with Burst Read/Write Support
// ============================================================================
// FIXES:
//   [CRIT-1] burst_wr_addr lệch 1 cycle khi simultaneous W:
//            Dùng wr_first_beat + burst_wr_addr trực tiếp (đã có trong code),
//            nhưng bug thực sự là data_mem_axi4_slave truyền write_addr (đã latch,
//            lệch 1 cycle) vào burst_wr_addr thay vì S_AXI_AWADDR trực tiếp.
//            → Fix tại AXI slave. Ở đây giữ wr_first_beat logic, đảm bảo đúng.
//
//   [CRIT-2] Burst read beat 1+: offset +4..+7 thay vì dùng addr đã advance:
//            Code gốc dùng rd_current_addr TRƯỚC KHI advance (+4..+7),
//            nhưng rd_current_addr chỉ được update cuối cycle (non-blocking).
//            Fix: tính next_rd_addr combinational, dùng để đọc memory[] ngay.
//
//   [BURST-RD-TIMING] Beat đầu dùng registered output → 1 cycle latency.
//            Không thể zero-latency như inst_mem vì data_mem_burst là sequential.
//            Giữ nguyên để đảm bảo timing closure. AXI slave cần biết điều này.
// ============================================================================

module data_mem_burst #(
    parameter MEM_SIZE   = 8192,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter BASE_ADDR  = 32'h10000000
)(
    input wire clk,
    input wire rst_n,

    // Simple Interface
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire [DATA_WIDTH-1:0] write_data,
    input  wire                  memwrite,
    input  wire                  memread,
    input  wire [1:0]            byte_size,
    input  wire                  sign_ext,
    output reg  [DATA_WIDTH-1:0] read_data,

    // Burst Read Interface
    input  wire [ADDR_WIDTH-1:0] burst_rd_addr,
    input  wire [7:0]            burst_rd_len,
    input  wire                  burst_rd_req,
    output reg  [DATA_WIDTH-1:0] burst_rd_data,
    output reg                   burst_rd_valid,
    output reg                   burst_rd_last,
    input  wire                  burst_rd_ready,

    // Burst Write Interface
    input  wire [ADDR_WIDTH-1:0] burst_wr_addr,
    input  wire [7:0]            burst_wr_len,
    input  wire [DATA_WIDTH-1:0] burst_wr_data,
    input  wire [3:0]            burst_wr_strb,
    input  wire                  burst_wr_valid,
    output wire                  burst_wr_ready,
    input  wire                  burst_wr_last
);

    localparam ADDR_BITS = $clog2(MEM_SIZE);
    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);
    localparam ADDR_LSB  = $clog2(DATA_WIDTH/8);

    // ========================================================================
    // Memory Array (byte-addressable)
    // ========================================================================
    reg [7:0] memory [0:MEM_SIZE-1];

    // ========================================================================
    // Simple Interface
    // ========================================================================
    wire [ADDR_BITS-1:0] simple_word_addr;
    wire [1:0]           byte_offset;
    wire [ADDR_BITS-1:0] aligned_addr;

    assign simple_word_addr = address[ADDR_BITS-1:2];
    assign byte_offset      = address[1:0];
    assign aligned_addr     = {address[ADDR_BITS-1:2], 2'b00};

    // Simple write
    always @(posedge clk) begin
        if (memwrite && !burst_wr_valid) begin
            case (byte_size)
                2'b00: begin
                    case (byte_offset)
                        2'b00: memory[aligned_addr + 0] <= write_data[7:0];
                        2'b01: memory[aligned_addr + 1] <= write_data[7:0];
                        2'b10: memory[aligned_addr + 2] <= write_data[7:0];
                        2'b11: memory[aligned_addr + 3] <= write_data[7:0];
                    endcase
                end
                2'b01: begin
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
                2'b10: begin
                    memory[aligned_addr + 0] <= write_data[7:0];
                    memory[aligned_addr + 1] <= write_data[15:8];
                    memory[aligned_addr + 2] <= write_data[23:16];
                    memory[aligned_addr + 3] <= write_data[31:24];
                end
            endcase
        end
    end

    // Simple read (combinational)
    always @(*) begin
        if (memread) begin
            case (byte_size)
                2'b00: begin
                    case (byte_offset)
                        2'b00: read_data = sign_ext ?
                            {{24{memory[aligned_addr+0][7]}}, memory[aligned_addr+0]} :
                            {24'h0, memory[aligned_addr+0]};
                        2'b01: read_data = sign_ext ?
                            {{24{memory[aligned_addr+1][7]}}, memory[aligned_addr+1]} :
                            {24'h0, memory[aligned_addr+1]};
                        2'b10: read_data = sign_ext ?
                            {{24{memory[aligned_addr+2][7]}}, memory[aligned_addr+2]} :
                            {24'h0, memory[aligned_addr+2]};
                        2'b11: read_data = sign_ext ?
                            {{24{memory[aligned_addr+3][7]}}, memory[aligned_addr+3]} :
                            {24'h0, memory[aligned_addr+3]};
                    endcase
                end
                2'b01: begin
                    case (byte_offset[1])
                        1'b0: read_data = sign_ext ?
                            {{16{memory[aligned_addr+1][7]}},
                             memory[aligned_addr+1], memory[aligned_addr+0]} :
                            {16'h0, memory[aligned_addr+1], memory[aligned_addr+0]};
                        1'b1: read_data = sign_ext ?
                            {{16{memory[aligned_addr+3][7]}},
                             memory[aligned_addr+3], memory[aligned_addr+2]} :
                            {16'h0, memory[aligned_addr+3], memory[aligned_addr+2]};
                    endcase
                end
                2'b10: begin
                    read_data = {memory[aligned_addr+3], memory[aligned_addr+2],
                                 memory[aligned_addr+1], memory[aligned_addr+0]};
                end
                default: read_data = 32'h0;
            endcase
        end else begin
            read_data = 32'h0;
        end
    end

    // ========================================================================
    // Burst Read State Machine
    // [FIX-CRIT-2] Tính next_rd_local combinational để đọc memory đúng cycle
    // ========================================================================
    localparam RD_BURST_IDLE   = 1'b0;
    localparam RD_BURST_ACTIVE = 1'b1;

    reg        rd_burst_state;
    reg [ADDR_WIDTH-1:0] rd_current_addr;
    reg [7:0]  rd_beat_count;
    reg [7:0]  rd_total_beats;

    // [FIX-CRIT-2] next address tính combinational — dùng cho memory read trong
    // cùng cycle mà rd_current_addr được advance (non-blocking update cuối cycle)
    wire [ADDR_WIDTH-1:0] rd_next_addr;
    wire [ADDR_WIDTH-1:0] rd_next_local;
    assign rd_next_addr  = rd_current_addr + (DATA_WIDTH/8);
    assign rd_next_local = rd_next_addr - BASE_ADDR;

    // Local offset cho beat hiện tại (beat đầu dùng burst_rd_addr)
    wire [ADDR_WIDTH-1:0] rd_first_local;
    assign rd_first_local = burst_rd_addr - BASE_ADDR;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_burst_state  <= RD_BURST_IDLE;
            burst_rd_data   <= {DATA_WIDTH{1'b0}};
            burst_rd_valid  <= 1'b0;
            burst_rd_last   <= 1'b0;
            rd_current_addr <= {ADDR_WIDTH{1'b0}};
            rd_beat_count   <= 8'd0;
            rd_total_beats  <= 8'd0;
        end else begin
            case (rd_burst_state)

                RD_BURST_IDLE: begin
                    if (burst_rd_req) begin
                        rd_current_addr <= burst_rd_addr;
                        rd_beat_count   <= 8'd0;
                        rd_total_beats  <= burst_rd_len;
                        rd_burst_state  <= RD_BURST_ACTIVE;

                        // Beat đầu: dùng rd_first_local (burst_rd_addr - BASE_ADDR)
                        burst_rd_data <= {
                            memory[rd_first_local + 3],
                            memory[rd_first_local + 2],
                            memory[rd_first_local + 1],
                            memory[rd_first_local + 0]
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
                            rd_current_addr <= rd_next_addr;

                            // [FIX-CRIT-2] Dùng rd_next_local (combinational từ
                            // rd_current_addr hiện tại + 4) thay vì
                            // rd_current_addr + 4..+7 (lệch vì non-blocking update)
                            burst_rd_data <= {
                                memory[rd_next_local + 3],
                                memory[rd_next_local + 2],
                                memory[rd_next_local + 1],
                                memory[rd_next_local + 0]
                            };
                            burst_rd_valid <= 1'b1;
                            burst_rd_last  <= (rd_beat_count + 8'd1 == rd_total_beats);
                        end
                    end
                end

            endcase
        end
    end

    // ========================================================================
    // Burst Write Logic
    // [FIX-CRIT-1] wr_first_beat dùng burst_wr_addr trực tiếp (absolute addr từ
    // AXI slave), không qua write_addr latch để tránh off-by-1-cycle.
    // Phần còn lại của fix CRIT-1 nằm ở data_mem_axi4_slave: burst_wr_addr phải
    // được nối tới S_AXI_AWADDR trực tiếp (không qua write_addr registered).
    // ========================================================================
    reg [ADDR_WIDTH-1:0] wr_current_addr;
    reg                  wr_first_beat;

    wire [ADDR_WIDTH-1:0] wr_effective_addr;
    assign wr_effective_addr = wr_first_beat ? burst_wr_addr : wr_current_addr;

    wire [ADDR_WIDTH-1:0] wr_local_addr;
    assign wr_local_addr = wr_effective_addr - BASE_ADDR;

    assign burst_wr_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_current_addr <= {ADDR_WIDTH{1'b0}};
            wr_first_beat   <= 1'b1;
        end else begin
            if (burst_wr_valid && burst_wr_ready) begin
                if (burst_wr_strb[0]) memory[wr_local_addr+0] <= burst_wr_data[7:0];
                if (burst_wr_strb[1]) memory[wr_local_addr+1] <= burst_wr_data[15:8];
                if (burst_wr_strb[2]) memory[wr_local_addr+2] <= burst_wr_data[23:16];
                if (burst_wr_strb[3]) memory[wr_local_addr+3] <= burst_wr_data[31:24];

                if (!burst_wr_last) begin
                    wr_current_addr <= wr_effective_addr + (DATA_WIDTH/8);
                    wr_first_beat   <= 1'b0;
                end else begin
                    wr_first_beat   <= 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // Memory Initialization
    // ========================================================================
    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1)
            memory[i] = 8'h00;
    end

    // ========================================================================
    // Debug/Simulation
    // ========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (burst_rd_req && rd_burst_state == RD_BURST_IDLE)
            $display("[DMEM] Burst read: addr=0x%h, len=%0d", burst_rd_addr, burst_rd_len+1);
        if (burst_rd_valid && burst_rd_ready)
            $display("[DMEM] Burst read data[%0d]: addr=0x%h, data=0x%h, last=%b",
                     rd_beat_count, rd_current_addr, burst_rd_data, burst_rd_last);
        if (burst_wr_valid && burst_wr_ready)
            $display("[DMEM] Burst write: addr=0x%h (local=0x%h), data=0x%h, strb=%b, last=%b",
                     wr_effective_addr, wr_local_addr, burst_wr_data, burst_wr_strb, burst_wr_last);
    end
    `endif

endmodule