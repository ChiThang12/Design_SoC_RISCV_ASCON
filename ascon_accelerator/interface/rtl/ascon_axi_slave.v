// ============================================================================
// Module  : ascon_axi_slave
// Project : ASCON Crypto Accelerator IP
// Version : 2.0 (modular)
//
// Description:
//   Top-level AXI4-Lite Slave register interface for the ASCON accelerator IP.
//   Instantiates four submodules:
//
//     axi_write_channel  — AW/W/B handshake, latches address + data
//     axi_read_channel   — AR/R handshake, drives read response
//     ascon_reg_bank     — register storage, write decode, read mux,
//                          control pulse generation, status capture
//     ascon_irq_ctrl     — interrupt masking and output
//
// Hierarchy:
//   ascon_axi_slave
//   ├── axi_write_channel
//   ├── axi_read_channel
//   ├── ascon_reg_bank
//   └── ascon_irq_ctrl
//
// External interfaces:
//   S_AXI_*      : AXI4-Lite Slave (from CPU / crossbar)
//   core_*       : to/from ascon_CORE
//   dma_*        : to/from ascon_dma
//   irq          : interrupt output (connect to PLIC / GIC)
//
// Register Map base: 0x2000_0000 (see 03_SO_DO_DIA_CHI.md)
// Full register map: see ascon_reg_bank.v header
// ============================================================================

`include "ascon_accelerator/rtl/ascon_axi_write_channel.v"
`include "ascon_accelerator/rtl/ascon_axi_read_channel.v"
`include "ascon_accelerator/rtl/ascon_reg_bank.v"
`include "ascon_accelerator/rtl/ascon_irq_ctrl.v"

module ascon_axi_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
) (
    input  wire                      clk,
    input  wire                      rst_n,

    // =========================================================================
    // AXI4-Lite Slave Interface
    // =========================================================================

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire                      S_AXI_AWVALID,
    output wire                      S_AXI_AWREADY,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0]   S_AXI_WSTRB,
    input  wire                      S_AXI_WVALID,
    output wire                      S_AXI_WREADY,

    // Write Response Channel
    output wire [ID_WIDTH-1:0]       S_AXI_BID,
    output wire [1:0]                S_AXI_BRESP,
    output wire                      S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire                      S_AXI_ARVALID,
    output wire                      S_AXI_ARREADY,

    // Read Data Channel
    output wire [ID_WIDTH-1:0]       S_AXI_RID,
    output wire [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                S_AXI_RRESP,
    output wire                      S_AXI_RLAST,
    output wire                      S_AXI_RVALID,
    input  wire                      S_AXI_RREADY,

    // =========================================================================
    // Interface to ascon_CORE
    // =========================================================================
    output wire [127:0]              core_key,
    output wire [127:0]              core_nonce,
    output wire [127:0]              core_data_in,
    output wire [6:0]                core_data_len,
    output wire                      core_enc_dec,
    output wire [1:0]                core_mode,
    output wire                      core_start,
    output wire                      core_soft_rst,

    input  wire                      core_busy,
    input  wire                      core_done,
    input  wire                      core_data_out_valid,
    input  wire [127:0]              core_data_out,
    input  wire [127:0]              core_tag_out,
    input  wire                      core_tag_valid,

    // =========================================================================
    // Interface to ascon_dma
    // =========================================================================
    output wire [31:0]               dma_src_addr,
    output wire [31:0]               dma_dst_addr,
    output wire [31:0]               dma_length,
    output wire                      dma_en,
    output wire [7:0]                dma_burst_len,
    output wire                      dma_rd_only,
    output wire                      dma_wr_only,
    output wire                      dma_start,
    output wire                      dma_soft_rst,

    input  wire                      dma_busy,
    input  wire                      dma_done,
    input  wire                      dma_error,
    input  wire                      dma_status_rd_done,
    input  wire                      dma_status_wr_done,
    input  wire                      dma_status_rd_error,
    input  wire                      dma_status_wr_error,
    input  wire                      dma_status_fifo_overflow,
    input  wire [31:0]               dma_err_addr,

    // =========================================================================
    // Interrupt
    // =========================================================================
    output wire                      irq
);

    // =========================================================================
    // Internal wires between submodules
    // =========================================================================

    // axi_write_channel → ascon_reg_bank
    wire [11:0]            wr_addr;
    wire [DATA_WIDTH-1:0]  wr_data;
    wire [DATA_WIDTH/8-1:0] wr_strb;
    wire                   do_write;

    // axi_read_channel ↔ ascon_reg_bank
    wire [11:0]            rd_addr;
    wire                   rd_req;
    wire [DATA_WIDTH-1:0]  rd_data;

    // ascon_reg_bank → ascon_irq_ctrl
    wire                   status_done;
    wire                   status_dma_done;
    wire                   status_error;
    wire                   status_dma_error;
    wire [2:0]             irq_en_bus;

    // =========================================================================
    // Submodule: axi_write_channel
    // =========================================================================
    axi_write_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_wr_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .S_AXI_AWID     (S_AXI_AWID),
        .S_AXI_AWADDR   (S_AXI_AWADDR),
        .S_AXI_AWVALID  (S_AXI_AWVALID),
        .S_AXI_AWREADY  (S_AXI_AWREADY),
        .S_AXI_WDATA    (S_AXI_WDATA),
        .S_AXI_WSTRB    (S_AXI_WSTRB),
        .S_AXI_WVALID   (S_AXI_WVALID),
        .S_AXI_WREADY   (S_AXI_WREADY),
        .S_AXI_BID      (S_AXI_BID),
        .S_AXI_BRESP    (S_AXI_BRESP),
        .S_AXI_BVALID   (S_AXI_BVALID),
        .S_AXI_BREADY   (S_AXI_BREADY),
        .wr_addr        (wr_addr),
        .wr_data        (wr_data),
        .wr_strb        (wr_strb),
        .do_write       (do_write)
    );

    // =========================================================================
    // Submodule: axi_read_channel
    // =========================================================================
    axi_read_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_rd_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .S_AXI_ARID     (S_AXI_ARID),
        .S_AXI_ARADDR   (S_AXI_ARADDR),
        .S_AXI_ARVALID  (S_AXI_ARVALID),
        .S_AXI_ARREADY  (S_AXI_ARREADY),
        .S_AXI_RID      (S_AXI_RID),
        .S_AXI_RDATA    (S_AXI_RDATA),
        .S_AXI_RRESP    (S_AXI_RRESP),
        .S_AXI_RLAST    (S_AXI_RLAST),
        .S_AXI_RVALID   (S_AXI_RVALID),
        .S_AXI_RREADY   (S_AXI_RREADY),
        .rd_addr        (rd_addr),
        .rd_req         (rd_req),
        .rd_data        (rd_data)
    );

    // =========================================================================
    // Submodule: ascon_reg_bank
    // =========================================================================
    ascon_reg_bank #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_reg_bank (
        .clk                      (clk),
        .rst_n                    (rst_n),
        // Write port
        .wr_addr                  (wr_addr),
        .wr_data                  (wr_data),
        .wr_strb                  (wr_strb),
        .do_write                 (do_write),
        // Read port
        .rd_addr                  (rd_addr),
        .rd_data                  (rd_data),
        // Control pulses
        .core_start               (core_start),
        .core_soft_rst            (core_soft_rst),
        .dma_start                (dma_start),
        .dma_soft_rst             (dma_soft_rst),
        // Core outputs
        .core_key                 (core_key),
        .core_nonce               (core_nonce),
        .core_data_in             (core_data_in),
        .core_data_len            (core_data_len),
        .core_enc_dec             (core_enc_dec),
        .core_mode                (core_mode),
        // Core status inputs
        .core_busy                (core_busy),
        .core_done                (core_done),
        .core_data_out_valid      (core_data_out_valid),
        .core_data_out            (core_data_out),
        .core_tag_out             (core_tag_out),
        .core_tag_valid           (core_tag_valid),
        // DMA config outputs
        .dma_src_addr             (dma_src_addr),
        .dma_dst_addr             (dma_dst_addr),
        .dma_length               (dma_length),
        .dma_en                   (dma_en),
        .dma_burst_len            (dma_burst_len),
        .dma_rd_only              (dma_rd_only),
        .dma_wr_only              (dma_wr_only),
        // DMA aggregate status inputs
        .dma_busy                 (dma_busy),
        .dma_done                 (dma_done),
        .dma_error                (dma_error),
        // DMA detailed status inputs (for DMA_STATUS 0x110)
        .dma_status_rd_done       (dma_status_rd_done),
        .dma_status_wr_done       (dma_status_wr_done),
        .dma_status_rd_error      (dma_status_rd_error),
        .dma_status_wr_error      (dma_status_wr_error),
        .dma_status_fifo_overflow (dma_status_fifo_overflow),
        .dma_err_addr             (dma_err_addr),
        // Sticky status to IRQ controller
        .status_done              (status_done),
        .status_dma_done          (status_dma_done),
        .status_error             (status_error),
        .status_dma_error         (status_dma_error),
        // IRQ_EN to IRQ controller
        .irq_en_bus               (irq_en_bus)
    );

    // IRQ_EN bus: reg_bank exposes irq_en through a dedicated output
    // (added as output port in reg_bank — see wire below)
    // For now wire directly: reg_bank outputs irq_en_bus [2:0]
    // This requires adding output wire [2:0] irq_en_bus to ascon_reg_bank.
    // Alternative shown here: pass individual bits.

    // =========================================================================
    // Submodule: ascon_irq_ctrl
    // =========================================================================
    ascon_irq_ctrl u_irq (
        .status_done      (status_done),
        .status_dma_done  (status_dma_done),
        .status_error     (status_error),
        .status_dma_error (status_dma_error),
        .irq_en_done      (irq_en_bus[0]),
        .irq_en_dma_done  (irq_en_bus[1]),
        .irq_en_error     (irq_en_bus[2]),
        .irq              (irq)
    );

endmodule