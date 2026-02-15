// ============================================================================
// inst_mem_axi_slave.v - AXI4 Full Slave (v3 - 8-beat burst support)
// ============================================================================
// - S_AXI_ARREADY = wire combinational (= IDLE state)
// - burst_req     = wire combinational (= AR handshake)
// - burst_addr    = S_AXI_ARADDR trực tiếp khi handshake (zero-latency)
// - burst_len     = S_AXI_ARLEN (pass thẳng từ master, hỗ trợ bất kỳ ARLEN)
//   → ARLEN=3  : 4-beat  (4 words, line cũ)
//   → ARLEN=7  : 8-beat  (8 words, line mới)
// ============================================================================

`include "cpu/memory_axi4full/inst_mem.v"

module inst_mem_axi_slave #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_SIZE      = 4096,
    parameter MEM_INIT_FILE = "cpu/memory_axi4full/program.hex"
)(
    input wire clk,
    input wire rst_n,

    // Write channels (read-only memory, always SLVERR)
    input wire [ADDR_WIDTH-1:0]    S_AXI_AWADDR,
    input wire [7:0]               S_AXI_AWLEN,
    input wire [2:0]               S_AXI_AWSIZE,
    input wire [1:0]               S_AXI_AWBURST,
    input wire [2:0]               S_AXI_AWPROT,
    input wire                     S_AXI_AWVALID,
    output reg                     S_AXI_AWREADY,

    input wire [DATA_WIDTH-1:0]    S_AXI_WDATA,
    input wire [DATA_WIDTH/8-1:0]  S_AXI_WSTRB,
    input wire                     S_AXI_WLAST,
    input wire                     S_AXI_WVALID,
    output reg                     S_AXI_WREADY,

    output reg [1:0]               S_AXI_BRESP,
    output reg                     S_AXI_BVALID,
    input wire                     S_AXI_BREADY,

    // Read channels
    input wire [ADDR_WIDTH-1:0]    S_AXI_ARADDR,
    input wire [7:0]               S_AXI_ARLEN,
    input wire [2:0]               S_AXI_ARSIZE,
    input wire [1:0]               S_AXI_ARBURST,
    input wire [2:0]               S_AXI_ARPROT,
    input wire                     S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,   // wire combinational

    output wire [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output wire                    S_AXI_RVALID,
    input wire                     S_AXI_RREADY
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // =========================================================================
    // Read state machine — 2 state
    // =========================================================================
    localparam RD_IDLE  = 1'b0;
    localparam RD_BURST = 1'b1;
    reg rd_state;

    // ARREADY = combinational: sẵn sàng ngay khi IDLE
    assign S_AXI_ARREADY = (rd_state == RD_IDLE);

    // AR handshake
    wire ar_handshake = S_AXI_ARVALID && S_AXI_ARREADY;

    // burst_req = combinational: imem nhận lệnh ngay cycle handshake
    wire burst_req = ar_handshake;

    // =========================================================================
    // Latch AR params khi handshake
    // burst_len latch S_AXI_ARLEN — imem dùng để detect RLAST
    // ARLEN=3 → 4 beat, ARLEN=7 → 8 beat (generic, không hardcode)
    // =========================================================================
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [7:0]            burst_len_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_addr   <= {ADDR_WIDTH{1'b0}};
            burst_len_r <= 8'd0;
        end else if (ar_handshake) begin
            read_addr   <= S_AXI_ARADDR;
            burst_len_r <= S_AXI_ARLEN;
        end
    end

    // =========================================================================
    // Read state machine sequential
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_state <= RD_IDLE;
        else case (rd_state)
            RD_IDLE:  if (ar_handshake)                              rd_state <= RD_BURST;
            RD_BURST: if (S_AXI_RVALID && S_AXI_RREADY && S_AXI_RLAST) rd_state <= RD_IDLE;
            default:  rd_state <= RD_IDLE;
        endcase
    end

    // =========================================================================
    // Instruction Memory
    // burst_addr: dùng S_AXI_ARADDR trực tiếp khi handshake (zero-latency
    //             first beat), sau đó dùng read_addr đã latch
    // burst_len:  khi handshake dùng S_AXI_ARLEN trực tiếp để imem thấy
    //             đúng ngay cycle burst_req=1
    // =========================================================================
    wire [ADDR_WIDTH-1:0] burst_addr = ar_handshake ? S_AXI_ARADDR : read_addr;
    wire [7:0]            burst_len  = ar_handshake ? S_AXI_ARLEN  : burst_len_r;

    wire [DATA_WIDTH-1:0] burst_data;
    wire                  burst_valid;
    wire                  burst_last;
    wire [DATA_WIDTH-1:0] simple_inst; // unused

    inst_mem #(
        .MEM_SIZE(MEM_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) imem (
        .clk(clk),
        .rst_n(rst_n),
        .PC(burst_addr),
        .Instruction_Code(simple_inst),
        .burst_addr(burst_addr),
        .burst_len(burst_len),
        .burst_req(burst_req),
        .burst_data(burst_data),
        .burst_valid(burst_valid),
        .burst_last(burst_last),
        .burst_ready(S_AXI_RREADY)
    );

    assign S_AXI_RDATA  = burst_data;
    assign S_AXI_RRESP  = RESP_OKAY;
    assign S_AXI_RLAST  = burst_last;
    assign S_AXI_RVALID = burst_valid;

    // =========================================================================
    // Write channels — always SLVERR (read-only memory)
    // =========================================================================
    localparam [1:0] WR_IDLE = 2'b00, WR_DATA = 2'b01, WR_RESP = 2'b10;
    reg [1:0] wr_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state      <= WR_IDLE;
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BRESP   <= RESP_SLVERR;
            S_AXI_BVALID  <= 1'b0;
        end else begin
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            case (wr_state)
                WR_IDLE: if (S_AXI_AWVALID) begin
                    S_AXI_AWREADY <= 1'b1;
                    wr_state      <= WR_DATA;
                end
                WR_DATA: begin
                    S_AXI_WREADY <= 1'b1;
                    if (S_AXI_WVALID && S_AXI_WLAST) begin
                        S_AXI_BRESP  <= RESP_SLVERR;
                        S_AXI_BVALID <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end
                WR_RESP: if (S_AXI_BREADY) begin
                    S_AXI_BVALID <= 1'b0;
                    wr_state     <= WR_IDLE;
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Debug
    // =========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (ar_handshake)
            $display("[IMEM] Burst start: addr=0x%h len=%0d @ %0t",
                     S_AXI_ARADDR, S_AXI_ARLEN+1, $time);
        if (S_AXI_RVALID && S_AXI_RREADY)
            $display("[IMEM] Beat: data=0x%h last=%b @ %0t",
                     S_AXI_RDATA, S_AXI_RLAST, $time);
    end
    `endif

endmodule