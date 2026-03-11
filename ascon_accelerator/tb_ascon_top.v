// ============================================================================
// Testbench : ascon_top_tb_soc
// DUT       : ascon_ip_top  (ascon_axi_slave + ascon_CORE + ascon_dma)
// Version   : 2.0  — SoC-accurate scenario
//
// Mô phỏng đúng theo firmware SoC (main.c) đã debug trong Soc_ascon_11032026.md
//
// Kịch bản test:
//   TEST 1 — CPU-Direct mode  (dma_en=0):
//       Bước giống firmware:
//         1. SOFT_RST
//         2. Ghi KEY / NONCE vào slave registers (qua AXI4-Lite)
//         3. Ghi PTEXT vào slave registers
//         4. Ghi MODE = 0 (encrypt, ascon-128)
//         5. Ghi CTRL = DMA_EN (bit2=0, giữ 0)  → latch reg_dma_en=0
//         6. Ghi CTRL = START  (bit0=1)          → core_start pulse
//         7. Poll STATUS.DONE
//         8. Đọc CTEXT_0/1, TAG_0..3
//         9. Verify kết quả so sánh với expected
//        10. SOFT_RST cleanup
//
//   TEST 2 — DMA mode  (dma_en=1):
//       Bước giống firmware:
//         1. SOFT_RST
//         2. Ghi KEY / NONCE vào slave registers
//         3. Ghi DMA_SRC / DMA_DST / DMA_LEN
//         4. AXI write barrier: đọc lại DMA_SRC (fence)
//         5. Ghi MODE = 0
//         6. Ghi IRQ_EN = 1 (enable done-IRQ)
//         7. Ghi CTRL = DMA_EN (bit2=1) → latch reg_dma_en=1
//         8. NOP delay (2 cycles)
//         9. Ghi CTRL = DMA_EN|START (0x05) → dma_start pulse
//        10. Poll STATUS.DMA_DONE hoặc chờ IRQ
//        11. Đọc DMEM tại DST_ADDR (ctext + tag ghi ra bởi DMA)
//        12. Verify
//        13. SOFT_RST cleanup
//
// DMEM model  : bram 64KB tại 0x1000_0000
//   0x1000_0000 : plaintext source (8 bytes)
//   0x1000_0010 : ciphertext dest  (8 bytes)
//   0x1000_0020 : auth tag dest    (16 bytes)
//
// AXI4-Lite slave base : 0x2000_0000
//
// Test vector (same key/nonce/ptext cho cả 2 mode để so sánh kết quả):
//   KEY   = 128'h000102030405060708090A0B0C0D0E0F
//   NONCE = 128'h000102030405060708090A0B0C0D0E0F
//   PTEXT = 64'h4865_6C6C_6F21_0000  ("Hello!\x00\x00")
//   data_len = 7'd8
//   mode = 2'b00 (ASCON-128 encrypt)
// ============================================================================

`timescale 1ns/1ps
`include "ascon_accelerator/ascon_top.v"
module ascon_top_tb_soc;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_PERIOD    = 10;   // 100 MHz
    parameter S_ADDR_WIDTH  = 32;
    parameter S_DATA_WIDTH  = 32;
    parameter S_ID_WIDTH    = 4;
    parameter M_ADDR_WIDTH  = 32;
    parameter M_DATA_WIDTH  = 64;
    parameter M_ID_WIDTH    = 4;

    // AXI4-Lite Slave base address (CPU → ASCON registers)
    parameter [31:0] ASCON_BASE  = 32'h2000_0000;

    // DMEM base (AXI4-Full Master DMA read/write)
    parameter [31:0] DMEM_BASE   = 32'h1000_0000;

    // DMEM offsets
    parameter [31:0] DMEM_PTEXT_OFF = 32'h00;
    parameter [31:0] DMEM_CTEXT_OFF = 32'h10;
    // TAG bắt đầu ngay sau CTEXT: DST_ADDR+8 (CTEXT=8B, sau đó TAG=16B)
    // DMA ghi: beat[0]=0x10→CTEXT(8B), beat[1]=0x18→TAG[127:64], beat[2]=0x20→TAG[63:0]
    parameter [31:0] DMEM_TAG_OFF   = 32'h18;

    // DMA total bytes: 8 ptext
    parameter [31:0] DMA_LEN     = 32'h00000008;

    // Poll timeout (cycles)
    parameter integer POLL_TIMEOUT = 500000;

    // ASCON register offsets
    localparam [11:0]
        OFF_CTRL     = 12'h000,
        OFF_STATUS   = 12'h004,
        OFF_MODE     = 12'h008,
        OFF_IRQ_EN   = 12'h00C,
        OFF_KEY_0    = 12'h010,
        OFF_KEY_1    = 12'h014,
        OFF_KEY_2    = 12'h018,
        OFF_KEY_3    = 12'h01C,
        OFF_NONCE_0  = 12'h020,
        OFF_NONCE_1  = 12'h024,
        OFF_NONCE_2  = 12'h028,
        OFF_NONCE_3  = 12'h02C,
        OFF_PTEXT_0  = 12'h030,
        OFF_PTEXT_1  = 12'h034,
        OFF_CTEXT_0  = 12'h040,
        OFF_CTEXT_1  = 12'h044,
        OFF_TAG_0    = 12'h048,
        OFF_TAG_1    = 12'h04C,
        OFF_TAG_2    = 12'h050,
        OFF_TAG_3    = 12'h054,
        OFF_DMA_SRC  = 12'h100,
        OFF_DMA_DST  = 12'h104,
        OFF_DMA_LEN  = 12'h108;

    // CTRL bits
    localparam CTRL_START   = 32'h1;
    localparam CTRL_SOFT_RST= 32'h2;
    localparam CTRL_DMA_EN  = 32'h4;

    // STATUS bits
    localparam STATUS_BUSY      = 32'h01;
    localparam STATUS_DONE      = 32'h02;
    localparam STATUS_DMA_BUSY  = 32'h04;
    localparam STATUS_DMA_DONE  = 32'h08;

    // =========================================================================
    // Test vector
    // =========================================================================
    localparam [127:0] TEST_KEY   = 128'h000102030405060708090A0B0C0D0E0F;
    localparam [127:0] TEST_NONCE = 128'h000102030405060708090A0B0C0D0E0F;
    // Plaintext: "Hello!\x00\x00" = 8 bytes
    localparam [63:0]  TEST_PTEXT = 64'h48656C6C6F210000;
    localparam [6:0]   TEST_DLEN  = 7'd8;

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    reg clk   = 0;
    reg rst_n = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // AXI4-Lite Slave signals (CPU → ASCON)
    // =========================================================================
    // Write Address
    reg  [S_ID_WIDTH-1:0]     s_awid    = 0;
    reg  [S_ADDR_WIDTH-1:0]   s_awaddr  = 0;
    reg  [7:0]                s_awlen   = 0;
    reg  [2:0]                s_awsize  = 3'b010;
    reg  [1:0]                s_awburst = 2'b01;
    reg  [2:0]                s_awprot  = 0;
    reg                       s_awvalid = 0;
    wire                      s_awready;

    // Write Data
    reg  [S_DATA_WIDTH-1:0]   s_wdata   = 0;
    reg  [S_DATA_WIDTH/8-1:0] s_wstrb   = 4'hF;
    reg                       s_wlast   = 1;
    reg                       s_wvalid  = 0;
    wire                      s_wready;

    // Write Response
    wire [S_ID_WIDTH-1:0]     s_bid;
    wire [1:0]                s_bresp;
    wire                      s_bvalid;
    reg                       s_bready  = 1;

    // Read Address
    reg  [S_ID_WIDTH-1:0]     s_arid    = 0;
    reg  [S_ADDR_WIDTH-1:0]   s_araddr  = 0;
    reg  [7:0]                s_arlen   = 0;
    reg  [2:0]                s_arsize  = 3'b010;
    reg  [1:0]                s_arburst = 2'b01;
    reg  [2:0]                s_arprot  = 0;
    reg                       s_arvalid = 0;
    wire                      s_arready;

    // Read Data
    wire [S_ID_WIDTH-1:0]     s_rid;
    wire [S_DATA_WIDTH-1:0]   s_rdata;
    wire [1:0]                s_rresp;
    wire                      s_rlast;
    wire                      s_rvalid;
    reg                       s_rready  = 1;

    // =========================================================================
    // AXI4-Full Master signals (DMA → DMEM model)
    // =========================================================================
    wire [M_ID_WIDTH-1:0]     m_awid;
    wire [M_ADDR_WIDTH-1:0]   m_awaddr;
    wire [7:0]                m_awlen;
    wire [2:0]                m_awsize;
    wire [1:0]                m_awburst;
    wire [3:0]                m_awcache;
    wire [2:0]                m_awprot;
    wire                      m_awvalid;
    reg                       m_awready = 0;

    wire [M_DATA_WIDTH-1:0]   m_wdata;
    wire [M_DATA_WIDTH/8-1:0] m_wstrb;
    wire                      m_wlast;
    wire                      m_wvalid;
    reg                       m_wready  = 0;

    reg  [M_ID_WIDTH-1:0]     m_bid     = 0;
    reg  [1:0]                m_bresp   = 0;
    reg                       m_bvalid  = 0;
    wire                      m_bready;

    wire [M_ID_WIDTH-1:0]     m_arid;
    wire [M_ADDR_WIDTH-1:0]   m_araddr;
    wire [7:0]                m_arlen;
    wire [2:0]                m_arsize;
    wire [1:0]                m_arburst;
    wire [3:0]                m_arcache;
    wire [2:0]                m_arprot;
    wire                      m_arvalid;
    reg                       m_arready = 0;

    reg  [M_ID_WIDTH-1:0]     m_rid     = 0;
    reg  [M_DATA_WIDTH-1:0]   m_rdata   = 0;
    reg  [1:0]                m_rresp   = 0;
    reg                       m_rlast   = 0;
    reg                       m_rvalid  = 0;
    wire                      m_rready;

    // IRQ
    wire irq;

    // =========================================================================
    // DUT
    // =========================================================================
    ascon_ip_top #(
        .S_ADDR_WIDTH (S_ADDR_WIDTH),
        .S_DATA_WIDTH (S_DATA_WIDTH),
        .S_ID_WIDTH   (S_ID_WIDTH),
        .M_ADDR_WIDTH (M_ADDR_WIDTH),
        .M_DATA_WIDTH (M_DATA_WIDTH),
        .M_ID_WIDTH   (M_ID_WIDTH),
        .RD_FIFO_DEPTH(4),
        .WR_FIFO_DEPTH(8)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),

        // AXI4-Lite Slave
        .S_AXI_AWID     (s_awid),
        .S_AXI_AWADDR   (s_awaddr),
        .S_AXI_AWLEN    (s_awlen),
        .S_AXI_AWSIZE   (s_awsize),
        .S_AXI_AWBURST  (s_awburst),
        .S_AXI_AWPROT   (s_awprot),
        .S_AXI_AWVALID  (s_awvalid),
        .S_AXI_AWREADY  (s_awready),

        .S_AXI_WDATA    (s_wdata),
        .S_AXI_WSTRB    (s_wstrb),
        .S_AXI_WLAST    (s_wlast),
        .S_AXI_WVALID   (s_wvalid),
        .S_AXI_WREADY   (s_wready),

        .S_AXI_BID      (s_bid),
        .S_AXI_BRESP    (s_bresp),
        .S_AXI_BVALID   (s_bvalid),
        .S_AXI_BREADY   (s_bready),

        .S_AXI_ARID     (s_arid),
        .S_AXI_ARADDR   (s_araddr),
        .S_AXI_ARLEN    (s_arlen),
        .S_AXI_ARSIZE   (s_arsize),
        .S_AXI_ARBURST  (s_arburst),
        .S_AXI_ARPROT   (s_arprot),
        .S_AXI_ARVALID  (s_arvalid),
        .S_AXI_ARREADY  (s_arready),

        .S_AXI_RID      (s_rid),
        .S_AXI_RDATA    (s_rdata),
        .S_AXI_RRESP    (s_rresp),
        .S_AXI_RLAST    (s_rlast),
        .S_AXI_RVALID   (s_rvalid),
        .S_AXI_RREADY   (s_rready),

        // AXI4-Full Master (DMA)
        .M_AXI_AWID     (m_awid),
        .M_AXI_AWADDR   (m_awaddr),
        .M_AXI_AWLEN    (m_awlen),
        .M_AXI_AWSIZE   (m_awsize),
        .M_AXI_AWBURST  (m_awburst),
        .M_AXI_AWCACHE  (m_awcache),
        .M_AXI_AWPROT   (m_awprot),
        .M_AXI_AWVALID  (m_awvalid),
        .M_AXI_AWREADY  (m_awready),

        .M_AXI_WDATA    (m_wdata),
        .M_AXI_WSTRB    (m_wstrb),
        .M_AXI_WLAST    (m_wlast),
        .M_AXI_WVALID   (m_wvalid),
        .M_AXI_WREADY   (m_wready),

        .M_AXI_BID      (m_bid),
        .M_AXI_BRESP    (m_bresp),
        .M_AXI_BVALID   (m_bvalid),
        .M_AXI_BREADY   (m_bready),

        .M_AXI_ARID     (m_arid),
        .M_AXI_ARADDR   (m_araddr),
        .M_AXI_ARLEN    (m_arlen),
        .M_AXI_ARSIZE   (m_arsize),
        .M_AXI_ARBURST  (m_arburst),
        .M_AXI_ARCACHE  (m_arcache),
        .M_AXI_ARPROT   (m_arprot),
        .M_AXI_ARVALID  (m_arvalid),
        .M_AXI_ARREADY  (m_arready),

        .M_AXI_RID      (m_rid),
        .M_AXI_RDATA    (m_rdata),
        .M_AXI_RRESP    (m_rresp),
        .M_AXI_RLAST    (m_rlast),
        .M_AXI_RVALID   (m_rvalid),
        .M_AXI_RREADY   (m_rready),

        .irq            (irq)
    );

    // =========================================================================
    // DMEM model — 64KB BRAM cho DMA master
    // Address range: 0x1000_0000 ~ 0x1000_FFFF
    // Data width: 64-bit (AXI4-Full)
    // =========================================================================
    reg [63:0] dmem [0:8191];   // 8192 × 64-bit = 64KB

    integer i;
    initial begin
        for (i = 0; i < 8192; i = i + 1)
            dmem[i] = 64'h0;
        // Pre-load plaintext tại 0x1000_0000 (offset 0, word index 0)
        // TEST_PTEXT = 64'h48656C6C_6F210000
        dmem[0] = {TEST_PTEXT[7:0],   TEST_PTEXT[15:8],
                   TEST_PTEXT[23:16], TEST_PTEXT[31:24],
                   TEST_PTEXT[39:32], TEST_PTEXT[47:40],
                   TEST_PTEXT[55:48], TEST_PTEXT[63:56]};
        // Byte-swap vì DMA đọc big-endian từ memory:
        // ptext[63:56] = byte 0 (địa chỉ thấp nhất) → AXI RDATA[63:56]
        // Giả sử DMA dùng little-endian host byte order, không swap:
        // => store raw value
        dmem[0] = TEST_PTEXT;  // 64'h48656C6C6F210000
    end

    // DMEM read port — AXI4-Full Master Read
    // Handshake: ARVALID/ARREADY → RVALID/RREADY
    // Phase 1: 1-beat burst (ARLEN=0), RLAST=1
    reg [M_ADDR_WIDTH-1:0] dmem_ar_addr_lat;
    reg [M_ID_WIDTH-1:0]   dmem_ar_id_lat;
    reg [1:0]              dmem_rd_state;

    localparam DMRD_IDLE = 2'b00, DMRD_DATA = 2'b01, DMRD_WAIT = 2'b10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_arready       <= 1'b1;
            m_rvalid        <= 1'b0;
            m_rdata         <= 64'h0;
            m_rresp         <= 2'b00;
            m_rlast         <= 1'b0;
            m_rid           <= {M_ID_WIDTH{1'b0}};
            dmem_rd_state   <= DMRD_IDLE;
        end else begin
            case (dmem_rd_state)
                DMRD_IDLE: begin
                    if (m_arvalid && m_arready) begin
                        dmem_ar_addr_lat <= m_araddr;
                        dmem_ar_id_lat   <= m_arid;
                        m_arready        <= 1'b0;
                        dmem_rd_state    <= DMRD_DATA;
                    end
                end
                DMRD_DATA: begin
                    // Serve read data (1-beat)
                    m_rvalid <= 1'b1;
                    m_rid    <= dmem_ar_id_lat;
                    m_rresp  <= 2'b00;
                    m_rlast  <= 1'b1;
                    if (dmem_ar_addr_lat >= DMEM_BASE &&
                        dmem_ar_addr_lat < (DMEM_BASE + 32'h10000)) begin
                        m_rdata <= dmem[(dmem_ar_addr_lat - DMEM_BASE) >> 3];
                        $display("[DMEM-RD] addr=0x%08X  data=0x%016X  (t=%0t)",
                                 dmem_ar_addr_lat,
                                 dmem[(dmem_ar_addr_lat - DMEM_BASE) >> 3],
                                 $time);
                    end else begin
                        m_rdata <= 64'hDEAD_BEEF_DEAD_BEEF;
                        $display("[DMEM-RD][WARN] addr=0x%08X OUT OF RANGE  (t=%0t)",
                                 dmem_ar_addr_lat, $time);
                    end
                    dmem_rd_state <= DMRD_WAIT;
                end
                DMRD_WAIT: begin
                    if (m_rvalid && m_rready) begin
                        m_rvalid      <= 1'b0;
                        m_rlast       <= 1'b0;
                        m_arready     <= 1'b1;
                        dmem_rd_state <= DMRD_IDLE;
                    end
                end
                default: dmem_rd_state <= DMRD_IDLE;
            endcase
        end
    end

    // DMEM write port — AXI4-Full Master Write
    // DMA ghi ctext + tag ra DMEM
    // Burst: AWLEN tùy DMA (Phase 1: AWLEN=2, 3 beats × 64-bit = 24 bytes)
    reg [M_ADDR_WIDTH-1:0] dmem_aw_addr_lat;
    reg [M_ID_WIDTH-1:0]   dmem_aw_id_lat;
    reg [7:0]              dmem_aw_len_lat;
    reg [7:0]              dmem_wr_beat_cnt;
    reg [2:0]              dmem_wr_state;
    reg [M_ADDR_WIDTH-1:0] dmem_wr_cur_addr;

    localparam DMWR_IDLE = 3'b000, DMWR_ADDR = 3'b001,
               DMWR_DATA = 3'b010, DMWR_RESP = 3'b011, DMWR_DONE = 3'b100;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_awready       <= 1'b1;
            m_wready        <= 1'b0;
            m_bvalid        <= 1'b0;
            m_bresp         <= 2'b00;
            m_bid           <= {M_ID_WIDTH{1'b0}};
            dmem_wr_state   <= DMWR_IDLE;
            dmem_wr_beat_cnt<= 8'h0;
        end else begin
            case (dmem_wr_state)
                DMWR_IDLE: begin
                    m_wready <= 1'b0;
                    if (m_awvalid && m_awready) begin
                        dmem_aw_addr_lat  <= m_awaddr;
                        dmem_aw_id_lat    <= m_awid;
                        dmem_aw_len_lat   <= m_awlen;
                        dmem_wr_cur_addr  <= m_awaddr;
                        dmem_wr_beat_cnt  <= 8'h0;
                        m_awready         <= 1'b0;
                        m_wready          <= 1'b1;
                        dmem_wr_state     <= DMWR_DATA;
                        $display("[DMEM-WR] AW accepted: addr=0x%08X len=%0d  (t=%0t)",
                                 m_awaddr, m_awlen, $time);
                    end
                end
                DMWR_DATA: begin
                    if (m_wvalid && m_wready) begin
                        // Write to DMEM
                        if (dmem_wr_cur_addr >= DMEM_BASE &&
                            dmem_wr_cur_addr < (DMEM_BASE + 32'h10000)) begin
                            dmem[(dmem_wr_cur_addr - DMEM_BASE) >> 3] <= m_wdata;
                            $display("[DMEM-WR]   beat[%0d] addr=0x%08X data=0x%016X strb=0x%02X  (t=%0t)",
                                     dmem_wr_beat_cnt, dmem_wr_cur_addr,
                                     m_wdata, m_wstrb, $time);
                        end else begin
                            $display("[DMEM-WR][WARN] addr=0x%08X OUT OF RANGE  (t=%0t)",
                                     dmem_wr_cur_addr, $time);
                        end
                        dmem_wr_cur_addr  <= dmem_wr_cur_addr + 8;
                        dmem_wr_beat_cnt  <= dmem_wr_beat_cnt + 1;
                        if (m_wlast) begin
                            m_wready      <= 1'b0;
                            dmem_wr_state <= DMWR_RESP;
                        end
                    end
                end
                DMWR_RESP: begin
                    m_bvalid      <= 1'b1;
                    m_bid         <= dmem_aw_id_lat;
                    m_bresp       <= 2'b00;
                    dmem_wr_state <= DMWR_DONE;
                end
                DMWR_DONE: begin
                    if (m_bvalid && m_bready) begin
                        m_bvalid      <= 1'b0;
                        m_awready     <= 1'b1;
                        dmem_wr_state <= DMWR_IDLE;
                    end
                end
                default: dmem_wr_state <= DMWR_IDLE;
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite helper tasks
    // =========================================================================

    // axi_write: CPU ghi 1 word vào ASCON slave
    // addr: địa chỉ đầy đủ (ví dụ: ASCON_BASE + OFF_KEY_0)
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        integer timeout_cnt;
        begin
            @(posedge clk); #1;
            // Phase 1: drive AW
            s_awaddr  = addr;
            s_awvalid = 1'b1;
            s_awid    = 4'h1;
            // Phase 2: drive W (same cycle — matches SoC behavior)
            s_wdata   = data;
            s_wstrb   = strb;
            s_wvalid  = 1'b1;
            s_wlast   = 1'b1;

            // Wait for AW handshake
            timeout_cnt = 0;
            @(posedge clk); #1;
            while (!s_awready && timeout_cnt < 100) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
            end
            s_awvalid = 1'b0;

            // Wait for W handshake
            timeout_cnt = 0;
            while (!s_wready && timeout_cnt < 100) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
            end
            s_wvalid = 1'b0;

            // Wait for B (write response)
            timeout_cnt = 0;
            while (!s_bvalid && timeout_cnt < 100) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
            end
            @(posedge clk); #1;
        end
    endtask

    // axi_read: CPU đọc 1 word từ ASCON slave
    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        integer timeout_cnt;
        begin
            @(posedge clk); #1;
            s_araddr  = addr;
            s_arid    = 4'h2;
            s_arvalid = 1'b1;

            // Wait AR handshake
            timeout_cnt = 0;
            @(posedge clk); #1;
            while (!s_arready && timeout_cnt < 100) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
            end
            s_arvalid = 1'b0;

            // Wait R data
            s_rready  = 1'b1;
            timeout_cnt = 0;
            while (!s_rvalid && timeout_cnt < 100) begin
                @(posedge clk); #1;
                timeout_cnt = timeout_cnt + 1;
            end
            data = s_rdata;
            @(posedge clk); #1;
        end
    endtask

    // nop_delay: 2 NOP cycles (giống firmware)
    task nop_delay;
        begin
            @(posedge clk); #1;
            @(posedge clk); #1;
        end
    endtask

    // =========================================================================
    // Poll STATUS register (giống step6_wait_done trong firmware)
    // mask: bit cần check (STATUS_DONE hoặc STATUS_DMA_DONE)
    // =========================================================================
    task poll_status_done;
        input [31:0] mask;
        input [63:0] timeout_cycles;
        output       timed_out;
        reg  [31:0]  status_val;
        integer      cnt;
        begin
            timed_out = 1'b0;
            cnt = 0;
            status_val = 32'h0;
            while (!(status_val & mask) && cnt < timeout_cycles) begin
                axi_read(ASCON_BASE + OFF_STATUS, status_val);
                cnt = cnt + 1;
            end
            if (cnt >= timeout_cycles) begin
                $display("[POLL][TIMEOUT] mask=0x%08X status=0x%08X after %0d reads",
                         mask, status_val, cnt);
                timed_out = 1'b1;
            end else begin
                $display("[POLL][DONE]    mask=0x%08X status=0x%08X after %0d reads  (t=%0t)",
                         mask, status_val, cnt, $time);
            end
        end
    endtask

    // =========================================================================
    // Result registers
    // =========================================================================
    reg [31:0] r_ctext_0, r_ctext_1;
    reg [31:0] r_tag_0, r_tag_1, r_tag_2, r_tag_3;
    reg [63:0] dma_ctext;
    reg [127:0] dma_tag;
    reg         test_timed_out;

    // =========================================================================
    // MAIN TEST
    // =========================================================================
    integer pass_count, fail_count;
reg [31:0] fence_val;
    initial begin
        pass_count = 0;
        fail_count = 0;

        // -----------------------------------------------------------------
        // RESET
        // -----------------------------------------------------------------
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(5)  @(posedge clk);

        $display("============================================================");
        $display(" ascon_ip_top SoC Testbench — START");
        $display(" KEY   = %032X", TEST_KEY);
        $display(" NONCE = %032X", TEST_NONCE);
        $display(" PTEXT = %016X  (%0d bytes)", TEST_PTEXT, 8);
        $display("============================================================");

        // =================================================================
        // TEST 1 — CPU-Direct mode  (dma_en = 0)
        // =================================================================
        $display("\n--- TEST 1: CPU-Direct mode ---");

        // Step 1: SOFT_RST (CTRL[1] = 1)
        $display("[T1-S1] SOFT_RST");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_SOFT_RST, 4'hF);
        nop_delay();

        // Step 2: Write KEY
        $display("[T1-S2] Write KEY");
        axi_write(ASCON_BASE + OFF_KEY_0, TEST_KEY[127:96], 4'hF);
        axi_write(ASCON_BASE + OFF_KEY_1, TEST_KEY[95:64],  4'hF);
        axi_write(ASCON_BASE + OFF_KEY_2, TEST_KEY[63:32],  4'hF);
        axi_write(ASCON_BASE + OFF_KEY_3, TEST_KEY[31:0],   4'hF);

        // Step 3: Write NONCE
        $display("[T1-S3] Write NONCE");
        axi_write(ASCON_BASE + OFF_NONCE_0, TEST_NONCE[127:96], 4'hF);
        axi_write(ASCON_BASE + OFF_NONCE_1, TEST_NONCE[95:64],  4'hF);
        axi_write(ASCON_BASE + OFF_NONCE_2, TEST_NONCE[63:32],  4'hF);
        axi_write(ASCON_BASE + OFF_NONCE_3, TEST_NONCE[31:0],   4'hF);

        // Step 4: Write PTEXT
        $display("[T1-S4] Write PTEXT");
        axi_write(ASCON_BASE + OFF_PTEXT_0, TEST_PTEXT[63:32], 4'hF);
        axi_write(ASCON_BASE + OFF_PTEXT_1, TEST_PTEXT[31:0],  4'hF);

        // Step 5: Write MODE = 0 (encrypt, ascon-128)
        $display("[T1-S5] Write MODE=0x00");
        axi_write(ASCON_BASE + OFF_MODE, 32'h00000000, 4'hF);

        // Step 6: DMA_EN=0 (latch reg_dma_en trước)
        $display("[T1-S6] CTRL = 0x00 (clear DMA_EN)");
        axi_write(ASCON_BASE + OFF_CTRL, 32'h00000000, 4'hF);
        nop_delay();

        // Step 7: START (core_start pulse)
        $display("[T1-S7] CTRL = START (0x01)");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_START, 4'hF);

        // Step 8: Poll STATUS.DONE (bit1)
        $display("[T1-S8] Poll STATUS.DONE ...");
        poll_status_done(STATUS_DONE, POLL_TIMEOUT, test_timed_out);
        if (test_timed_out) begin
            $display("[T1][FAIL] Timed out waiting for DONE");
            fail_count = fail_count + 1;
        end

        // Step 9: Read CTEXT + TAG
        $display("[T1-S9] Read CTEXT / TAG from slave registers");
        axi_read(ASCON_BASE + OFF_CTEXT_0, r_ctext_0);
        axi_read(ASCON_BASE + OFF_CTEXT_1, r_ctext_1);
        axi_read(ASCON_BASE + OFF_TAG_0,   r_tag_0);
        axi_read(ASCON_BASE + OFF_TAG_1,   r_tag_1);
        axi_read(ASCON_BASE + OFF_TAG_2,   r_tag_2);
        axi_read(ASCON_BASE + OFF_TAG_3,   r_tag_3);

        $display("[T1] CTEXT = %08X_%08X", r_ctext_0, r_ctext_1);
        $display("[T1] TAG   = %08X_%08X_%08X_%08X",
                 r_tag_0, r_tag_1, r_tag_2, r_tag_3);

        // Verify: kết quả phải khác 0 (core đã chạy)
        if ({r_ctext_0, r_ctext_1} == 64'h0) begin
            $display("[T1][FAIL] CTEXT = 0 — core did not produce output");
            fail_count = fail_count + 1;
        end else begin
            $display("[T1][PASS] CTEXT non-zero");
            pass_count = pass_count + 1;
        end

        if ({r_tag_0, r_tag_1, r_tag_2, r_tag_3} == 128'h0) begin
            $display("[T1][FAIL] TAG = 0 — tag not generated");
            fail_count = fail_count + 1;
        end else begin
            $display("[T1][PASS] TAG non-zero");
            pass_count = pass_count + 1;
        end

        // Step 10: SOFT_RST cleanup
        $display("[T1-S10] SOFT_RST cleanup");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_SOFT_RST, 4'hF);
        nop_delay();
        repeat(5) @(posedge clk);

        // =================================================================
        // TEST 2 — DMA mode  (dma_en = 1)
        // =================================================================
        $display("\n--- TEST 2: DMA mode ---");

        // Step 1: SOFT_RST
        $display("[T2-S1] SOFT_RST");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_SOFT_RST, 4'hF);
        nop_delay();

        // Step 2: Write KEY
        $display("[T2-S2] Write KEY");
        axi_write(ASCON_BASE + OFF_KEY_0, TEST_KEY[127:96], 4'hF);
        axi_write(ASCON_BASE + OFF_KEY_1, TEST_KEY[95:64],  4'hF);
        axi_write(ASCON_BASE + OFF_KEY_2, TEST_KEY[63:32],  4'hF);
        axi_write(ASCON_BASE + OFF_KEY_3, TEST_KEY[31:0],   4'hF);

        // Step 3: Write NONCE
        $display("[T2-S3] Write NONCE");
        axi_write(ASCON_BASE + OFF_NONCE_0, TEST_NONCE[127:96], 4'hF);
        axi_write(ASCON_BASE + OFF_NONCE_1, TEST_NONCE[95:64],  4'hF);
        axi_write(ASCON_BASE + OFF_NONCE_2, TEST_NONCE[63:32],  4'hF);
        axi_write(ASCON_BASE + OFF_NONCE_3, TEST_NONCE[31:0],   4'hF);

        // Step 4: Write DMA_SRC / DMA_DST / DMA_LEN
        $display("[T2-S4] Write DMA config");
        axi_write(ASCON_BASE + OFF_DMA_SRC, DMEM_BASE + DMEM_PTEXT_OFF, 4'hF);
        axi_write(ASCON_BASE + OFF_DMA_DST, DMEM_BASE + DMEM_CTEXT_OFF, 4'hF);
        axi_write(ASCON_BASE + OFF_DMA_LEN, DMA_LEN, 4'hF);

        // Step 4b: AXI write barrier — đọc lại DMA_SRC để flush AXI pipeline
        // (Fix Lỗi #5 từ debug log)
        begin
            
            axi_read(ASCON_BASE + OFF_DMA_SRC, fence_val);
            $display("[T2-S4] AXI fence: DMA_SRC readback = 0x%08X (expected 0x%08X)",
                     fence_val, (DMEM_BASE + DMEM_PTEXT_OFF) & 32'hFFFFFFFF);
            if (fence_val !== ((DMEM_BASE + DMEM_PTEXT_OFF) & 32'hFFFFFFFF)) begin
                $display("[T2][WARN] DMA_SRC readback mismatch! Possible AXI pipeline issue.");
            end
        end

        // Step 5: Write MODE = 0
        $display("[T2-S5] Write MODE=0x00");
        axi_write(ASCON_BASE + OFF_MODE, 32'h00000000, 4'hF);

        // Step 6: Write IRQ_EN = 0x01 (enable core done IRQ)
        $display("[T2-S6] Write IRQ_EN=0x01");
        axi_write(ASCON_BASE + OFF_IRQ_EN, 32'h00000003, 4'hF);

        // Step 7: CTRL = DMA_EN (latch reg_dma_en=1, NO start yet)
        // Fix Lỗi #3 + #4: tách 2 lần ghi
        $display("[T2-S7] CTRL = DMA_EN (0x04) — latch reg_dma_en=1");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_DMA_EN, 4'hF);

        // Step 8: NOP delay (2 cycles — cho DMA_EN ổn định)
        nop_delay();

        // Step 9: CTRL = DMA_EN | START (0x05) → dma_start pulse
        $display("[T2-S9] CTRL = DMA_EN|START (0x05) — dma_start");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_DMA_EN | CTRL_START, 4'hF);

        // Step 10: Poll STATUS.DMA_DONE (bit3)
        $display("[T2-S10] Poll STATUS.DMA_DONE ...");
        poll_status_done(STATUS_DMA_DONE, POLL_TIMEOUT, test_timed_out);
        if (test_timed_out) begin
            $display("[T2][FAIL] Timed out waiting for DMA_DONE");
            fail_count = fail_count + 1;
        end

        // Wait 1 extra cycle cho DMA write hoàn tất
        repeat(5) @(posedge clk);

        // Step 11: Đọc kết quả từ DMEM (DMA đã ghi ra)
        $display("[T2-S11] Read CTEXT+TAG from DMEM");
        // CTEXT tại 0x1000_0010 (word index 2 của 64-bit dmem)
        dma_ctext = dmem[(DMEM_CTEXT_OFF) >> 3];
        // TAG tại 0x1000_0020 và 0x1000_0028
        dma_tag[127:64] = dmem[(DMEM_TAG_OFF) >> 3];
        dma_tag[63:0]   = dmem[(DMEM_TAG_OFF + 8) >> 3];

        $display("[T2] DMEM CTEXT [0x%08X] = %016X",
                 (DMEM_BASE + DMEM_CTEXT_OFF) & 32'hFFFFFFFF, dma_ctext);
        $display("[T2] DMEM TAG   [0x%08X] = %016X_%016X",
                 (DMEM_BASE + DMEM_TAG_OFF) & 32'hFFFFFFFF, dma_tag[127:64], dma_tag[63:0]);

        // Step 12: Verify
        // DMA ctext phải khác 0
        if (dma_ctext == 64'h0) begin
            $display("[T2][FAIL] DMEM CTEXT = 0 — DMA did not write output");
            fail_count = fail_count + 1;
        end else begin
            $display("[T2][PASS] DMEM CTEXT non-zero");
            pass_count = pass_count + 1;
        end

        if (dma_tag == 128'h0) begin
            $display("[T2][FAIL] DMEM TAG = 0 — DMA did not write tag");
            fail_count = fail_count + 1;
        end else begin
            $display("[T2][PASS] DMEM TAG non-zero");
            pass_count = pass_count + 1;
        end

        // Cross-check: T1 và T2 phải cho cùng kết quả (same key/nonce/ptext)
        $display("\n--- Cross-check T1 vs T2 (same vector) ---");
        if ({r_ctext_0, r_ctext_1} === dma_ctext) begin
            $display("[XCHECK][PASS] CTEXT T1 == T2 : %016X", dma_ctext);
            pass_count = pass_count + 1;
        end else begin
            $display("[XCHECK][FAIL] CTEXT MISMATCH:");
            $display("  T1 (CPU-Direct) = %08X_%08X", r_ctext_0, r_ctext_1);
            $display("  T2 (DMA)        = %016X", dma_ctext);
            fail_count = fail_count + 1;
        end

        if ({r_tag_0, r_tag_1, r_tag_2, r_tag_3} === dma_tag) begin
            $display("[XCHECK][PASS] TAG   T1 == T2 : %032X", dma_tag);
            pass_count = pass_count + 1;
        end else begin
            $display("[XCHECK][FAIL] TAG MISMATCH:");
            $display("  T1 (CPU-Direct) = %08X_%08X_%08X_%08X",
                     r_tag_0, r_tag_1, r_tag_2, r_tag_3);
            $display("  T2 (DMA)        = %032X", dma_tag);
            fail_count = fail_count + 1;
        end

        // Step 13: SOFT_RST cleanup
        $display("[T2-S13] SOFT_RST cleanup");
        axi_write(ASCON_BASE + OFF_CTRL, CTRL_SOFT_RST, 4'hF);
        nop_delay();
        repeat(5) @(posedge clk);

        // =================================================================
        // SUMMARY
        // =================================================================
        $display("\n============================================================");
        $display(" SUMMARY: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** SOME TESTS FAILED ***");
        $display("============================================================");
        $finish;
    end

    // =========================================================================
    // IRQ monitor
    // =========================================================================
    always @(posedge irq) begin
        $display("[IRQ] Interrupt received at t=%0t", $time);
    end

    // =========================================================================
    // DMA activity monitor (probe internal DUT signals for debug)
    // =========================================================================
    `ifdef SIMULATION
    initial begin
        $dumpfile("ascon_top_soc.vcd");
        $dumpvars(0, ascon_top_tb_soc);
    end
    `endif

    // Safety watchdog — prevent infinite loop
    initial begin
        #(CLK_PERIOD * 2000000);
        $display("[WATCHDOG] Simulation timeout at t=%0t", $time);
        $finish;
    end

endmodule