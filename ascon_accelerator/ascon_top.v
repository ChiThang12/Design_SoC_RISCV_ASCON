// ============================================================================
// Module  : ascon_top
// Project : ASCON Crypto Accelerator IP
// Version : 1.0
//
// Description:
//   Top-level wrapper for the ASCON cryptographic accelerator IP.
//   Integrates three sub-blocks:
//     1. ascon_axi_slave  — AXI4-Lite register interface (CPU ↔ IP)
//     2. ascon_CORE       — ASCON-128/128a permutation engine
//     3. ascon_dma        — DMA engine (IP ↔ memory bus, AXI4 Full Master)
//
//   Dual-personality operation:
//     - SLAVE mode  : CPU programs KEY/NONCE/PTEXT via AXI4-Lite slave port,
//                     triggers encryption/decryption, polls STATUS or awaits IRQ.
//     - DMA mode    : CPU programs DMA_SRC/DMA_DST/DMA_LEN, sets DMA_EN+START;
//                     IP fetches plaintext from memory, encrypts, writes back
//                     ciphertext + tag automatically.
//
//   Block diagram:
//
//     RISC-V CPU
//       │
//       │  AXI4-Lite (S_AXI_*)           AXI4-Full (M_AXI_*)
//       │                                      │
//       ▼                                      ▼
//   ┌─────────────────┐               ┌─────────────────┐
//   │  ascon_axi_slave│               │    ascon_dma    │
//   │  (reg bank,     │◄──────────────│  (read engine,  │
//   │   AXI-Lite s/m) │   control     │   write engine, │
//   └───────┬─────────┘               │   FIFOs, FSM)   │
//           │ core_*                  └────────┬────────┘
//           ▼                                  │ core_*
//   ┌───────────────┐                          │
//   │  ascon_CORE   │◄─────────────────────────┘
//   │ (permutation  │
//   │  engine)      │
//   └───────────────┘
//
// Port groups:
//   clk / rst_n          — clock and active-low reset
//   S_AXI_*              — AXI4-Lite slave (from RISC-V CPU)
//   M_AXI_*              — AXI4-Full master (to memory crossbar)
//   irq                  — level interrupt to RISC-V PLIC
//
// Parameters:
//   ADDR_WIDTH       — address bus width (default 32)
//   S_DATA_WIDTH     — AXI4-Lite data bus width (default 32)
//   M_AXI_DATA_WIDTH — AXI4-Full data bus width (default 64)
//   S_ID_WIDTH       — Slave ID width (default 4)
//   M_AXI_ID_WIDTH   — Master ID width (default 4)
//   RD_FIFO_DEPTH    — DMA read FIFO depth in entries (default 4)
//   WR_FIFO_DEPTH    — DMA write FIFO depth in entries (default 8)
// ============================================================================

`include "ascon_accelerator/rtl/ascon_CORE.v"          // pulls in sub-modules
`include "ascon_accelerator/interface/rtl/ascon_axi_slave.v"
`include "ascon_accelerator/dma/rtl/ascon_dma.v"       // pulls in DMA sub-modules

module ascon_top #(
    parameter ADDR_WIDTH       = 32,
    parameter S_DATA_WIDTH     = 32,
    parameter M_AXI_DATA_WIDTH = 64,
    parameter S_ID_WIDTH       = 4,
    parameter M_AXI_ID_WIDTH   = 4,
    parameter RD_FIFO_DEPTH    = 4,
    parameter WR_FIFO_DEPTH    = 8
) (
    input  wire                         clk,
    input  wire                         rst_n,

    // =========================================================================
    // AXI4-Lite Slave — RISC-V CPU register access
    // =========================================================================

    // Write Address Channel
    input  wire [S_ID_WIDTH-1:0]        S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]        S_AXI_AWADDR,
    input  wire [2:0]                   S_AXI_AWPROT,
    input  wire                         S_AXI_AWVALID,
    output wire                         S_AXI_AWREADY,

    // Write Data Channel
    input  wire [S_DATA_WIDTH-1:0]      S_AXI_WDATA,
    input  wire [S_DATA_WIDTH/8-1:0]    S_AXI_WSTRB,
    input  wire                         S_AXI_WVALID,
    output wire                         S_AXI_WREADY,

    // Write Response Channel
    output wire [S_ID_WIDTH-1:0]        S_AXI_BID,
    output wire [1:0]                   S_AXI_BRESP,
    output wire                         S_AXI_BVALID,
    input  wire                         S_AXI_BREADY,

    // Read Address Channel
    input  wire [S_ID_WIDTH-1:0]        S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]        S_AXI_ARADDR,
    input  wire [2:0]                   S_AXI_ARPROT,
    input  wire                         S_AXI_ARVALID,
    output wire                         S_AXI_ARREADY,

    // Read Data Channel
    output wire [S_ID_WIDTH-1:0]        S_AXI_RID,
    output wire [S_DATA_WIDTH-1:0]      S_AXI_RDATA,
    output wire [1:0]                   S_AXI_RRESP,
    output wire                         S_AXI_RLAST,
    output wire                         S_AXI_RVALID,
    input  wire                         S_AXI_RREADY,

    // =========================================================================
    // AXI4-Full Master — DMA memory access
    // =========================================================================

    // Write Address Channel
    output wire [M_AXI_ID_WIDTH-1:0]   M_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]        M_AXI_AWADDR,
    output wire [7:0]                   M_AXI_AWLEN,
    output wire [2:0]                   M_AXI_AWSIZE,
    output wire [1:0]                   M_AXI_AWBURST,
    output wire [3:0]                   M_AXI_AWCACHE,
    output wire [2:0]                   M_AXI_AWPROT,
    output wire                         M_AXI_AWVALID,
    input  wire                         M_AXI_AWREADY,

    // Write Data Channel
    output wire [M_AXI_DATA_WIDTH-1:0]    M_AXI_WDATA,
    output wire [M_AXI_DATA_WIDTH/8-1:0]  M_AXI_WSTRB,
    output wire                            M_AXI_WLAST,
    output wire                            M_AXI_WVALID,
    input  wire                            M_AXI_WREADY,

    // Write Response Channel
    input  wire [M_AXI_ID_WIDTH-1:0]   M_AXI_BID,
    input  wire [1:0]                   M_AXI_BRESP,
    input  wire                         M_AXI_BVALID,
    output wire                         M_AXI_BREADY,

    // Read Address Channel
    output wire [M_AXI_ID_WIDTH-1:0]   M_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]        M_AXI_ARADDR,
    output wire [7:0]                   M_AXI_ARLEN,
    output wire [2:0]                   M_AXI_ARSIZE,
    output wire [1:0]                   M_AXI_ARBURST,
    output wire [3:0]                   M_AXI_ARCACHE,
    output wire [2:0]                   M_AXI_ARPROT,
    output wire                         M_AXI_ARVALID,
    input  wire                         M_AXI_ARREADY,

    // Read Data Channel
    input  wire [M_AXI_ID_WIDTH-1:0]   M_AXI_RID,
    input  wire [M_AXI_DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0]                   M_AXI_RRESP,
    input  wire                         M_AXI_RLAST,
    input  wire                         M_AXI_RVALID,
    output wire                         M_AXI_RREADY,

    // =========================================================================
    // Interrupt
    // =========================================================================
    output wire                         irq
);

    // =========================================================================
    // Internal wires — axi_slave ↔ CORE
    // =========================================================================
    wire [127:0] w_core_key;
    wire [127:0] w_core_nonce;
    wire [127:0] w_core_data_in;
    wire [6:0]   w_core_data_len;
    wire         w_core_enc_dec;
    wire [1:0]   w_core_mode;
    wire         w_core_start_slave;    // start pulse from AXI slave (CPU path)
    wire         w_core_soft_rst;

    wire         w_core_busy;
    wire         w_core_done;
    wire         w_core_data_out_valid;
    wire [127:0] w_core_data_out;
    wire [127:0] w_core_tag_out;
    wire         w_core_tag_valid;

    // =========================================================================
    // Internal wires — axi_slave ↔ DMA
    // =========================================================================
    wire [31:0]  w_dma_src_addr;
    wire [31:0]  w_dma_dst_addr;
    wire [31:0]  w_dma_length;
    wire         w_dma_en;
    wire         w_dma_start_slave;    // DMA start pulse from AXI slave
    wire         w_dma_soft_rst;

    wire         w_dma_busy;
    wire         w_dma_done;
    wire         w_dma_error;

    // =========================================================================
    // Internal wires — DMA ↔ CORE
    // =========================================================================
    wire [31:0]  w_dma_core_ptext_0;
    wire [31:0]  w_dma_core_ptext_1;
    wire         w_dma_core_data_valid;
    wire         w_dma_core_data_ready;  // handshake (not used by current CORE)
    wire         w_dma_core_start;       // start pulse from DMA (DMA path)

    // Results flowing DMA → CORE output side
    // In DMA mode the AXI slave captures ctext/tag from CORE directly;
    // the DMA ctrl_fsm also reads them to write back to memory.
    wire [31:0]  w_dma_core_ctext_0;
    wire [31:0]  w_dma_core_ctext_1;
    wire [31:0]  w_dma_core_tag_0;
    wire [31:0]  w_dma_core_tag_1;
    wire [31:0]  w_dma_core_tag_2;
    wire [31:0]  w_dma_core_tag_3;

    // =========================================================================
    // START mux — CORE start can come from CPU (slave) or DMA
    // Priority: DMA has higher priority when DMA_EN is asserted
    // =========================================================================
    wire w_core_start = w_dma_en ? w_dma_core_start : w_core_start_slave;

    // =========================================================================
    // DMA start mux — only propagate DMA start when DMA_EN=1
    // =========================================================================
    wire w_dma_start = w_dma_en & w_dma_start_slave;

    // =========================================================================
    // CORE data input mux — DMA mode overrides slave plaintext registers
    // In DMA mode, plaintext comes from DMA (loaded from memory).
    // In slave mode, plaintext comes from AXI slave PTEXT registers.
    // =========================================================================
    wire [127:0] w_core_data_in_mux = w_dma_en
        ? {w_dma_core_ptext_0, w_dma_core_ptext_1, 64'h0}
        : w_core_data_in;

    // data_valid / data_ready for DMA handshake
    // In slave mode both are ignored (CORE accepts data_in combinatorially)
    // In DMA  mode the DMA ctrl_fsm drives core_data_valid
    assign w_dma_core_data_ready = ~w_core_busy; // simple back-pressure

    // Ciphertext / tag slices for DMA write-back
    assign w_dma_core_ctext_0 = w_core_data_out[127:96];
    assign w_dma_core_ctext_1 = w_core_data_out[95:64];
    assign w_dma_core_tag_0   = w_core_tag_out[127:96];
    assign w_dma_core_tag_1   = w_core_tag_out[95:64];
    assign w_dma_core_tag_2   = w_core_tag_out[63:32];
    assign w_dma_core_tag_3   = w_core_tag_out[31:0];

    // =========================================================================
    // ascon_axi_slave instantiation
    // =========================================================================
    ascon_axi_slave #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (S_DATA_WIDTH),
        .ID_WIDTH   (S_ID_WIDTH)
    ) u_axi_slave (
        .clk                (clk),
        .rst_n              (rst_n),

        // AXI4-Lite slave ports
        .S_AXI_AWID         (S_AXI_AWID),
        .S_AXI_AWADDR       (S_AXI_AWADDR),
        .S_AXI_AWPROT       (S_AXI_AWPROT),
        .S_AXI_AWVALID      (S_AXI_AWVALID),
        .S_AXI_AWREADY      (S_AXI_AWREADY),

        .S_AXI_WDATA        (S_AXI_WDATA),
        .S_AXI_WSTRB        (S_AXI_WSTRB),
        .S_AXI_WVALID       (S_AXI_WVALID),
        .S_AXI_WREADY       (S_AXI_WREADY),

        .S_AXI_BID          (S_AXI_BID),
        .S_AXI_BRESP        (S_AXI_BRESP),
        .S_AXI_BVALID       (S_AXI_BVALID),
        .S_AXI_BREADY       (S_AXI_BREADY),

        .S_AXI_ARID         (S_AXI_ARID),
        .S_AXI_ARADDR       (S_AXI_ARADDR),
        .S_AXI_ARPROT       (S_AXI_ARPROT),
        .S_AXI_ARVALID      (S_AXI_ARVALID),
        .S_AXI_ARREADY      (S_AXI_ARREADY),

        .S_AXI_RID          (S_AXI_RID),
        .S_AXI_RDATA        (S_AXI_RDATA),
        .S_AXI_RRESP        (S_AXI_RRESP),
        .S_AXI_RLAST        (S_AXI_RLAST),
        .S_AXI_RVALID       (S_AXI_RVALID),
        .S_AXI_RREADY       (S_AXI_RREADY),

        // To/from CORE
        .core_key           (w_core_key),
        .core_nonce         (w_core_nonce),
        .core_data_in       (w_core_data_in),
        .core_data_len      (w_core_data_len),
        .core_enc_dec       (w_core_enc_dec),
        .core_mode          (w_core_mode),
        .core_start         (w_core_start_slave),
        .core_soft_rst      (w_core_soft_rst),

        .core_busy          (w_core_busy),
        .core_done          (w_core_done),
        .core_data_out_valid(w_core_data_out_valid),
        .core_data_out      (w_core_data_out),
        .core_tag_out       (w_core_tag_out),
        .core_tag_valid     (w_core_tag_valid),

        // To/from DMA
        .dma_src_addr       (w_dma_src_addr),
        .dma_dst_addr       (w_dma_dst_addr),
        .dma_length         (w_dma_length),
        .dma_en             (w_dma_en),
        .dma_start          (w_dma_start_slave),
        .dma_soft_rst       (w_dma_soft_rst),

        .dma_busy           (w_dma_busy),
        .dma_done           (w_dma_done),
        .dma_error          (w_dma_error),

        // Interrupt
        .irq                (irq)
    );

    // =========================================================================
    // ascon_CORE instantiation
    // =========================================================================
    ascon_CORE u_core (
        .clk            (clk),
        .rst_n          (rst_n),

        .start          (w_core_start),
        .mode           (w_core_mode),
        .enc_dec        (w_core_enc_dec),
        .key_in         (w_core_key),
        .nonce_in       (w_core_nonce),

        // AD: tied off (Phase 1 — no associated data path in slave/DMA)
        .ad_in          (128'h0),
        .ad_valid       (1'b0),
        .ad_last        (1'b0),

        // Plaintext — muxed between slave registers and DMA FIFO
        .data_in        (w_core_data_in_mux),
        .data_last      (1'b1),           // always single block in Phase 1
        .data_len       (w_core_data_len),

        // Tag verification — not used in Phase 1
        .tag_received   (128'h0),

        // Outputs
        .data_out       (w_core_data_out),
        .data_out_valid (w_core_data_out_valid),
        .tag_out        (w_core_tag_out),
        .tag_valid      (w_core_tag_valid),
        .tag_match      (),               // unused in Phase 1
        .done           (w_core_done),
        .busy           (w_core_busy)
    );

    // =========================================================================
    // ascon_dma instantiation
    // =========================================================================
    ascon_dma #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .AXI_DATA_WIDTH (M_AXI_DATA_WIDTH),
        .AXI_ID_WIDTH   (M_AXI_ID_WIDTH),
        .RD_FIFO_DEPTH  (RD_FIFO_DEPTH),
        .WR_FIFO_DEPTH  (WR_FIFO_DEPTH)
    ) u_dma (
        .clk                 (clk),
        .rst_n               (rst_n),

        // Control from AXI slave register bank
        .src_addr            (w_dma_src_addr),
        .dst_addr            (w_dma_dst_addr),
        .byte_len            (w_dma_length),
        .burst_len           (8'd0),        // Phase 1: single-beat

        .dma_start           (w_dma_start),
        .dma_soft_rst        (w_dma_soft_rst),

        // Status → AXI slave
        .dma_busy            (w_dma_busy),
        .dma_done            (w_dma_done),
        .dma_error           (w_dma_error),

        // Extended status (not connected to slave in Phase 1 — optional)
        .status_rd_done      (),
        .status_wr_done      (),
        .status_rd_error     (),
        .status_wr_error     (),
        .status_fifo_overflow(),
        .dma_err_addr        (),

        // DMA → CORE (plaintext push)
        .core_ptext_0        (w_dma_core_ptext_0),
        .core_ptext_1        (w_dma_core_ptext_1),
        .core_data_valid     (w_dma_core_data_valid),
        .core_data_ready     (w_dma_core_data_ready),
        .core_start          (w_dma_core_start),
        .core_busy           (w_core_busy),
        .core_done           (w_core_done),

        // CORE → DMA (ciphertext + tag read-back for DMA write)
        .core_ctext_0        (w_dma_core_ctext_0),
        .core_ctext_1        (w_dma_core_ctext_1),
        .core_tag_0          (w_dma_core_tag_0),
        .core_tag_1          (w_dma_core_tag_1),
        .core_tag_2          (w_dma_core_tag_2),
        .core_tag_3          (w_dma_core_tag_3),

        // AXI4-Full Master
        .M_AXI_AWID          (M_AXI_AWID),
        .M_AXI_AWADDR        (M_AXI_AWADDR),
        .M_AXI_AWLEN         (M_AXI_AWLEN),
        .M_AXI_AWSIZE        (M_AXI_AWSIZE),
        .M_AXI_AWBURST       (M_AXI_AWBURST),
        .M_AXI_AWCACHE       (M_AXI_AWCACHE),
        .M_AXI_AWPROT        (M_AXI_AWPROT),
        .M_AXI_AWVALID       (M_AXI_AWVALID),
        .M_AXI_AWREADY       (M_AXI_AWREADY),

        .M_AXI_WDATA         (M_AXI_WDATA),
        .M_AXI_WSTRB         (M_AXI_WSTRB),
        .M_AXI_WLAST         (M_AXI_WLAST),
        .M_AXI_WVALID        (M_AXI_WVALID),
        .M_AXI_WREADY        (M_AXI_WREADY),

        .M_AXI_BID           (M_AXI_BID),
        .M_AXI_BRESP         (M_AXI_BRESP),
        .M_AXI_BVALID        (M_AXI_BVALID),
        .M_AXI_BREADY        (M_AXI_BREADY),

        .M_AXI_ARID          (M_AXI_ARID),
        .M_AXI_ARADDR        (M_AXI_ARADDR),
        .M_AXI_ARLEN         (M_AXI_ARLEN),
        .M_AXI_ARSIZE        (M_AXI_ARSIZE),
        .M_AXI_ARBURST       (M_AXI_ARBURST),
        .M_AXI_ARCACHE       (M_AXI_ARCACHE),
        .M_AXI_ARPROT        (M_AXI_ARPROT),
        .M_AXI_ARVALID       (M_AXI_ARVALID),
        .M_AXI_ARREADY       (M_AXI_ARREADY),

        .M_AXI_RID           (M_AXI_RID),
        .M_AXI_RDATA         (M_AXI_RDATA),
        .M_AXI_RRESP         (M_AXI_RRESP),
        .M_AXI_RLAST         (M_AXI_RLAST),
        .M_AXI_RVALID        (M_AXI_RVALID),
        .M_AXI_RREADY        (M_AXI_RREADY)
    );

endmodule