`timescale 1ns/1ps

// ============================================================================
// File     : tb_ascon_axi_slave.v
// Version  : 2.0  (original TB — pair with ascon_axi_slave v1.1 fixed RTL)
// ============================================================================

`timescale 1ns/1ps
`include "ascon_accelerator/interface/ascon_axi_slave.v"
module tb_ascon_axi_slave;

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH   = 4;
    parameter CLK_PERIOD = 10;
    parameter [31:0] BASE = 32'h2000_0000;

    parameter [11:0]
        O_CTRL=12'h000, O_STATUS=12'h004, O_MODE=12'h008,  O_IRQ_EN=12'h00C,
        O_KEY_0=12'h010,O_KEY_1=12'h014,  O_KEY_2=12'h018, O_KEY_3=12'h01C,
        O_NONCE_0=12'h020,O_NONCE_1=12'h024,O_NONCE_2=12'h028,O_NONCE_3=12'h02C,
        O_PTEXT_0=12'h030,O_PTEXT_1=12'h034,
        O_CTEXT_0=12'h040,O_CTEXT_1=12'h044,
        O_TAG_0=12'h048,O_TAG_1=12'h04C,O_TAG_2=12'h050,O_TAG_3=12'h054,
        O_DMA_SRC=12'h100,O_DMA_DST=12'h104,O_DMA_LEN=12'h108;
    parameter [11:0] O_UNMAPPED = 12'hFFC;

    // ── Clock / Reset ─────────────────────────────────────────────────────────
    reg clk, rst_n;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── AXI master signals ────────────────────────────────────────────────────
    reg  [ID_WIDTH-1:0]     M_AWID;   reg  [ADDR_WIDTH-1:0]   M_AWADDR;
    reg  [2:0]              M_AWPROT; reg                     M_AWVALID;
    wire                    M_AWREADY;
    reg  [DATA_WIDTH-1:0]   M_WDATA;  reg  [DATA_WIDTH/8-1:0] M_WSTRB;
    reg                     M_WVALID; wire                    M_WREADY;
    wire [ID_WIDTH-1:0]     M_BID;    wire [1:0]              M_BRESP;
    wire                    M_BVALID; reg                     M_BREADY;
    reg  [ID_WIDTH-1:0]     M_ARID;   reg  [ADDR_WIDTH-1:0]   M_ARADDR;
    reg  [2:0]              M_ARPROT; reg                     M_ARVALID;
    wire                    M_ARREADY;
    wire [ID_WIDTH-1:0]     M_RID;    wire [DATA_WIDTH-1:0]   M_RDATA;
    wire [1:0]              M_RRESP;  wire                    M_RLAST;
    wire                    M_RVALID; reg                     M_RREADY;

    // ── Core / DMA mock inputs ────────────────────────────────────────────────
    reg        core_busy, core_done, core_data_out_valid, core_tag_valid;
    reg [127:0] core_data_out, core_tag_out;
    reg         dma_busy, dma_done, dma_error;

    // ── DUT outputs ───────────────────────────────────────────────────────────
    wire [127:0] core_key, core_nonce, core_data_in;
    wire [6:0]   core_data_len;
    wire         core_enc_dec;
    wire [1:0]   core_mode_out;
    wire         core_start_out, core_soft_rst_out;
    wire [31:0]  dma_src_addr, dma_dst_addr, dma_length;
    wire         dma_en, dma_start_out, dma_soft_rst_out, irq;

    // ── DUT ───────────────────────────────────────────────────────────────────
    ascon_axi_slave #(.ADDR_WIDTH(ADDR_WIDTH),.DATA_WIDTH(DATA_WIDTH),.ID_WIDTH(ID_WIDTH)) dut (
        .clk(clk),.rst_n(rst_n),
        .S_AXI_AWID(M_AWID),.S_AXI_AWADDR(M_AWADDR),.S_AXI_AWPROT(M_AWPROT),
        .S_AXI_AWVALID(M_AWVALID),.S_AXI_AWREADY(M_AWREADY),
        .S_AXI_WDATA(M_WDATA),.S_AXI_WSTRB(M_WSTRB),
        .S_AXI_WVALID(M_WVALID),.S_AXI_WREADY(M_WREADY),
        .S_AXI_BID(M_BID),.S_AXI_BRESP(M_BRESP),
        .S_AXI_BVALID(M_BVALID),.S_AXI_BREADY(M_BREADY),
        .S_AXI_ARID(M_ARID),.S_AXI_ARADDR(M_ARADDR),.S_AXI_ARPROT(M_ARPROT),
        .S_AXI_ARVALID(M_ARVALID),.S_AXI_ARREADY(M_ARREADY),
        .S_AXI_RID(M_RID),.S_AXI_RDATA(M_RDATA),.S_AXI_RRESP(M_RRESP),
        .S_AXI_RLAST(M_RLAST),.S_AXI_RVALID(M_RVALID),.S_AXI_RREADY(M_RREADY),
        .core_key(core_key),.core_nonce(core_nonce),.core_data_in(core_data_in),
        .core_data_len(core_data_len),.core_enc_dec(core_enc_dec),
        .core_mode(core_mode_out),.core_start(core_start_out),
        .core_soft_rst(core_soft_rst_out),.core_busy(core_busy),
        .core_done(core_done),.core_data_out_valid(core_data_out_valid),
        .core_data_out(core_data_out),.core_tag_out(core_tag_out),
        .core_tag_valid(core_tag_valid),
        .dma_src_addr(dma_src_addr),.dma_dst_addr(dma_dst_addr),
        .dma_length(dma_length),.dma_en(dma_en),
        .dma_start(dma_start_out),.dma_soft_rst(dma_soft_rst_out),
        .dma_busy(dma_busy),.dma_done(dma_done),.dma_error(dma_error),
        .irq(irq)
    );

    // ── Scoreboard ────────────────────────────────────────────────────────────
    integer pass_count, fail_count;
    task check;
        input [1023:0] tc_name; input cond; input [1023:0] msg;
        begin
            if (cond) begin $display("  [PASS] %0s -- %0s",tc_name,msg); pass_count=pass_count+1; end
            else      begin $display("  [FAIL] %0s -- %0s  (@%0t)",tc_name,msg,$time); fail_count=fail_count+1; end
        end
    endtask
    task wait_cycles; input integer n; integer i;
        begin for(i=0;i<n;i=i+1) @(posedge clk); end
    endtask

    // ── Pulse observers ───────────────────────────────────────────────────────
    reg obs_core_start, obs_core_soft_rst, obs_dma_start, obs_dma_soft_rst;
    always @(posedge clk) begin
        if (core_start_out)    obs_core_start    <= 1'b1;
        if (core_soft_rst_out) obs_core_soft_rst <= 1'b1;
        if (dma_start_out)     obs_dma_start     <= 1'b1;
        if (dma_soft_rst_out)  obs_dma_soft_rst  <= 1'b1;
    end
    task clear_pulse_flags; begin
        @(negedge clk);
        obs_core_start=1'b0; obs_core_soft_rst=1'b0;
        obs_dma_start=1'b0;  obs_dma_soft_rst=1'b0;
    end endtask

    // ── AXI Write task ────────────────────────────────────────────────────────
    task axi_write;
        input [ADDR_WIDTH-1:0] addr; input [DATA_WIDTH-1:0] data;
        input [3:0] strb; input [ID_WIDTH-1:0] id; input integer bready_delay;
        integer t;
        begin
            @(posedge clk); #1;
            M_AWID=id; M_AWADDR=addr; M_AWPROT=0; M_AWVALID=1'b1;
            M_WDATA=data; M_WSTRB=strb; M_WVALID=1'b1;
            t=0; while(!M_AWREADY&&t<200) begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_AWVALID=1'b0;
            t=0; while(!M_WREADY&&t<200)  begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_WVALID=1'b0;
            if(bready_delay>0) begin M_BREADY=1'b0; repeat(bready_delay) @(posedge clk);#1; end
            M_BREADY=1'b1;
            t=0; while(!M_BVALID&&t<200) begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_BREADY=1'b0;
        end
    endtask

    // ── AXI Write data-first task ─────────────────────────────────────────────
    task axi_write_data_first;
        input [ADDR_WIDTH-1:0] addr; input [DATA_WIDTH-1:0] data;
        input [3:0] strb; input [ID_WIDTH-1:0] id;
        integer t;
        begin
            @(posedge clk);#1; M_WDATA=data;M_WSTRB=strb;M_WVALID=1'b1;M_AWVALID=1'b0;
            t=0; while(!M_WREADY&&t<200) begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_WVALID=1'b0;
            repeat(2) @(posedge clk);#1;
            M_AWID=id;M_AWADDR=addr;M_AWPROT=0;M_AWVALID=1'b1;
            t=0; while(!M_AWREADY&&t<200) begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_AWVALID=1'b0;
            M_BREADY=1'b1;
            t=0; while(!M_BVALID&&t<200) begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_BREADY=1'b0;
        end
    endtask

    // ── AXI Read task ─────────────────────────────────────────────────────────
    reg [DATA_WIDTH-1:0] rd_data_cap;
    reg [ID_WIDTH-1:0]   rd_id_cap;
    reg [1:0]            rd_resp_cap;
    task axi_read;
        input [ADDR_WIDTH-1:0] addr; input [ID_WIDTH-1:0] id;
        input integer rready_delay;
        integer t;
        begin
            @(posedge clk);#1;
            M_ARID=id;M_ARADDR=addr;M_ARPROT=0;M_ARVALID=1'b1;
            t=0; while(!M_ARREADY&&t<200) begin @(posedge clk);#1;t=t+1; end
            @(posedge clk);#1; M_ARVALID=1'b0;
            if(rready_delay>0) begin M_RREADY=1'b0; repeat(rready_delay) @(posedge clk);#1; end
            M_RREADY=1'b1;
            t=0; while(!M_RVALID&&t<200) begin @(posedge clk);#1;t=t+1; end
            rd_data_cap=M_RDATA; rd_id_cap=M_RID; rd_resp_cap=M_RRESP;
            @(posedge clk);#1; M_RREADY=1'b0;
        end
    endtask

    // ── Reset task ────────────────────────────────────────────────────────────
    task apply_reset; begin
        rst_n=1'b0;
        M_AWVALID=0;M_AWID=0;M_AWADDR=0;M_AWPROT=0;
        M_WVALID=0;M_WDATA=0;M_WSTRB=4'hF;M_BREADY=0;
        M_ARVALID=0;M_ARID=0;M_ARADDR=0;M_ARPROT=0;M_RREADY=0;
        core_busy=0;core_done=0;core_data_out_valid=0;
        core_data_out=0;core_tag_out=0;core_tag_valid=0;
        dma_busy=0;dma_done=0;dma_error=0;
        repeat(6) @(posedge clk); #1; rst_n=1'b1;
        obs_core_start=0;obs_core_soft_rst=0;obs_dma_start=0;obs_dma_soft_rst=0;
        repeat(2) @(posedge clk);
    end endtask

    // =========================================================================
    // MAIN TEST
    // =========================================================================
    initial begin
        $dumpfile("tb_ascon_axi_slave.vcd");
        $dumpvars(0,tb_ascon_axi_slave);
        pass_count=0; fail_count=0;
        obs_core_start=0;obs_core_soft_rst=0;obs_dma_start=0;obs_dma_soft_rst=0;

        $display("================================================================");
        $display("   ASCON AXI Slave Testbench v2.0  (RTL fixed v1.1)");
        $display("================================================================");

        // ── TC1 : Reset & Idle ────────────────────────────────────────────────
        $display("\n[TC1] Reset and Idle state check");
        apply_reset;
        check("TC1",M_AWREADY===1'b1,"AWREADY=1 after reset");
        check("TC1",M_WREADY===1'b1,"WREADY=1 after reset");
        check("TC1",M_BVALID===1'b0,"BVALID=0 after reset");
        check("TC1",M_ARREADY===1'b1,"ARREADY=1 after reset");
        check("TC1",M_RVALID===1'b0,"RVALID=0 after reset");
        check("TC1",irq===1'b0,"irq=0 after reset");
        check("TC1",core_start_out===1'b0,"core_start=0 after reset");
        check("TC1",dma_start_out===1'b0,"dma_start=0 after reset");
        check("TC1",core_soft_rst_out===1'b0,"core_soft_rst=0 after reset");
        check("TC1",dma_soft_rst_out===1'b0,"dma_soft_rst=0 after reset");
        check("TC1",dma_en===1'b0,"dma_en=0 after reset");
        check("TC1",core_data_len===7'd8,"core_data_len=8 (constant)");

        // ── TC2 : Basic R/W ───────────────────────────────────────────────────
        $display("\n[TC2] Basic register R/W: MODE, IRQ_EN, DMA_SRC/DST/LEN");
        apply_reset;
        axi_write(BASE|O_MODE,32'h2,4'hF,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_MODE,4'h2,0);
        check("TC2",rd_data_cap===32'h2,"MODE=0x2 write/readback");
        check("TC2",rd_resp_cap===2'b00,"MODE read RRESP=OKAY");
        axi_write(BASE|O_IRQ_EN,32'h7,4'hF,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_IRQ_EN,4'h2,0);
        check("TC2",rd_data_cap===32'h7,"IRQ_EN=0x7 write/readback");
        axi_write(BASE|O_DMA_SRC,32'hDEAD_0000,4'hF,4'h1,0);
        axi_write(BASE|O_DMA_DST,32'hCAFE_0000,4'hF,4'h1,0);
        axi_write(BASE|O_DMA_LEN,32'h10,4'hF,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_DMA_SRC,4'h1,0); check("TC2",rd_data_cap===32'hDEAD_0000,"DMA_SRC readback");
        axi_read(BASE|O_DMA_DST,4'h1,0); check("TC2",rd_data_cap===32'hCAFE_0000,"DMA_DST readback");
        axi_read(BASE|O_DMA_LEN,4'h1,0); check("TC2",rd_data_cap===32'h10,"DMA_LEN readback");
        check("TC2",dma_src_addr===32'hDEAD_0000,"dma_src_addr wire");
        check("TC2",dma_dst_addr===32'hCAFE_0000,"dma_dst_addr wire");
        check("TC2",dma_length===32'h10,"dma_length wire");
        axi_write(BASE|O_MODE,32'h1,4'hF,4'h1,0); wait_cycles(1);
        check("TC2",core_enc_dec===1'b1,"core_enc_dec=1");
        check("TC2",core_mode_out===2'b01,"core_mode wire");

        // ── TC3 : WO registers ────────────────────────────────────────────────
        $display("\n[TC3] WO registers return 0 on read; wires carry actual values");
        apply_reset;
        axi_write(BASE|O_KEY_0,  32'hAABBCCDD,4'hF,4'h1,0);
        axi_write(BASE|O_KEY_1,  32'h11223344,4'hF,4'h1,0);
        axi_write(BASE|O_KEY_2,  32'h55667788,4'hF,4'h1,0);
        axi_write(BASE|O_KEY_3,  32'h99AABBCC,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_0,32'h12345678,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_1,32'hABCDABCD,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_2,32'hDEF0DEF0,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_3,32'h87654321,4'hF,4'h1,0);
        axi_write(BASE|O_PTEXT_0,32'hDEADBEEF,4'hF,4'h1,0);
        axi_write(BASE|O_PTEXT_1,32'hCAFEBABE,4'hF,4'h1,0);
        wait_cycles(1);
        axi_read(BASE|O_KEY_0,4'h1,0);   check("TC3",rd_data_cap===32'h0,"KEY_0 read=0 (WO)");
        axi_read(BASE|O_KEY_1,4'h1,0);   check("TC3",rd_data_cap===32'h0,"KEY_1 read=0 (WO)");
        axi_read(BASE|O_KEY_2,4'h1,0);   check("TC3",rd_data_cap===32'h0,"KEY_2 read=0 (WO)");
        axi_read(BASE|O_KEY_3,4'h1,0);   check("TC3",rd_data_cap===32'h0,"KEY_3 read=0 (WO)");
        axi_read(BASE|O_NONCE_0,4'h1,0); check("TC3",rd_data_cap===32'h0,"NONCE_0 read=0 (WO)");
        axi_read(BASE|O_PTEXT_0,4'h1,0); check("TC3",rd_data_cap===32'h0,"PTEXT_0 read=0 (WO)");
        axi_read(BASE|O_PTEXT_1,4'h1,0); check("TC3",rd_data_cap===32'h0,"PTEXT_1 read=0 (WO)");
        check("TC3",core_key[127:96]===32'hAABBCCDD,"core_key[127:96]");
        check("TC3",core_key[95:64] ===32'h11223344,"core_key[95:64]");
        check("TC3",core_key[63:32] ===32'h55667788,"core_key[63:32]");
        check("TC3",core_key[31:0]  ===32'h99AABBCC,"core_key[31:0]");
        check("TC3",core_nonce[127:96]===32'h12345678,"core_nonce[127:96]");
        check("TC3",core_nonce[95:64] ===32'hABCDABCD,"core_nonce[95:64]");
        check("TC3",core_nonce[63:32] ===32'hDEF0DEF0,"core_nonce[63:32]");
        check("TC3",core_nonce[31:0]  ===32'h87654321,"core_nonce[31:0]");
        check("TC3",core_data_in[127:96]===32'hDEADBEEF,"core_data_in[127:96]");
        check("TC3",core_data_in[95:64] ===32'hCAFEBABE,"core_data_in[95:64]");
        check("TC3",core_data_in[63:0]  ===64'h0,       "core_data_in[63:0] zero-pad");

        // ── TC4 : RO registers ────────────────────────────────────────────────
        $display("\n[TC4] RO registers: writes silently accepted, data discarded");
        apply_reset;
        axi_write(BASE|O_CTEXT_0,32'hDEADBEEF,4'hF,4'h1,0); check("TC4",M_BRESP===2'b00,"Write CTEXT_0: BRESP=OKAY");
        axi_write(BASE|O_CTEXT_1,32'hCAFEBABE,4'hF,4'h1,0); check("TC4",M_BRESP===2'b00,"Write CTEXT_1: BRESP=OKAY");
        axi_write(BASE|O_TAG_0,  32'h11111111,4'hF,4'h1,0); check("TC4",M_BRESP===2'b00,"Write TAG_0: BRESP=OKAY");
        axi_write(BASE|O_STATUS, 32'hFFFFFFFF,4'hF,4'h1,0); check("TC4",M_BRESP===2'b00,"Write STATUS: BRESP=OKAY");
        wait_cycles(1);
        axi_read(BASE|O_CTEXT_0,4'h1,0); check("TC4",rd_data_cap===32'h0,"CTEXT_0 unchanged after write attempt");
        axi_read(BASE|O_CTEXT_1,4'h1,0); check("TC4",rd_data_cap===32'h0,"CTEXT_1 unchanged after write attempt");
        axi_read(BASE|O_TAG_0,  4'h1,0); check("TC4",rd_data_cap===32'h0,"TAG_0 unchanged after write attempt");

        // ── TC5 : START, DMA_EN=0 ─────────────────────────────────────────────
        $display("\n[TC5] CTRL[0]=START DMA_EN=0 -> core_start only, dma_start=0");
        apply_reset; clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h1,4'hF,4'h1,0); wait_cycles(3);
        check("TC5",obs_core_start===1'b1,"core_start pulsed");
        check("TC5",obs_dma_start===1'b0,"dma_start NOT pulsed (DMA_EN=0)");
        check("TC5",dma_en===1'b0,"dma_en wire=0");

        // ── TC6 : DMA_EN=1 + START ────────────────────────────────────────────
        $display("\n[TC6] CTRL DMA_EN=1 + START -> core_start AND dma_start");
        apply_reset; clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h5,4'hF,4'h1,0); wait_cycles(3);
        check("TC6",obs_core_start===1'b1,"core_start pulsed with DMA_EN=1");
        check("TC6",obs_dma_start===1'b1,"dma_start pulsed with DMA_EN=1");
        check("TC6",dma_en===1'b1,"dma_en wire=1");
        axi_read(BASE|O_CTRL,4'h1,0); check("TC6",rd_data_cap[2]===1'b1,"CTRL[2] DMA_EN readback=1");
        apply_reset; clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h4,4'hF,4'h1,0); wait_cycles(1);
        axi_write(BASE|O_CTRL,32'h1,4'hF,4'h1,0); wait_cycles(3);
        check("TC6",obs_core_start===1'b1,"core_start pulsed (DMA_EN pre-set)");
        check("TC6",obs_dma_start===1'b1,"dma_start pulsed (DMA_EN pre-set)");

        // ── TC7 : SOFT_RST ────────────────────────────────────────────────────
        $display("\n[TC7] CTRL[1]=SOFT_RST clears DONE/DMA_DONE/ERROR; preserves KEY");
        apply_reset;
        axi_write(BASE|O_KEY_0,32'hAABBCCDD,4'hF,4'h1,0); wait_cycles(1);
        @(posedge clk);#1; core_done=1'b1; @(posedge clk);#1; core_done=1'b0; wait_cycles(1);
        axi_read(BASE|O_STATUS,4'h1,0); check("TC7",rd_data_cap[1]===1'b1,"STATUS[1] DONE=1 after core_done");
        @(posedge clk);#1; dma_done=1'b1;  @(posedge clk);#1; dma_done=1'b0;  wait_cycles(1);
        axi_read(BASE|O_STATUS,4'h1,0); check("TC7",rd_data_cap[3]===1'b1,"STATUS[3] DMA_DONE=1 after dma_done");
        @(posedge clk);#1; dma_error=1'b1; @(posedge clk);#1; dma_error=1'b0; wait_cycles(1);
        axi_read(BASE|O_STATUS,4'h1,0); check("TC7",rd_data_cap[5]===1'b1,"STATUS[5] DMA_ERROR=1 after dma_error");
        clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h2,4'hF,4'h1,0); wait_cycles(3);
        check("TC7",obs_core_soft_rst===1'b1,"core_soft_rst pulsed");
        check("TC7",obs_dma_soft_rst===1'b1,"dma_soft_rst pulsed");
        axi_read(BASE|O_STATUS,4'h1,0);
        check("TC7",rd_data_cap[1]===1'b0,"STATUS[1] DONE cleared after SOFT_RST");
        check("TC7",rd_data_cap[3]===1'b0,"STATUS[3] DMA_DONE cleared after SOFT_RST");
        check("TC7",rd_data_cap[5]===1'b0,"STATUS[5] DMA_ERROR cleared after SOFT_RST");
        check("TC7",core_key[127:96]===32'hAABBCCDD,"KEY_0 preserved across SOFT_RST");

        // ── TC8 : START ignored when busy ─────────────────────────────────────
        $display("\n[TC8] START ignored when core_busy=1");
        apply_reset; clear_pulse_flags;
        core_busy=1'b1; axi_write(BASE|O_CTRL,32'h1,4'hF,4'h1,0); wait_cycles(5);
        check("TC8",obs_core_start===1'b0,"core_start NOT pulsed when core_busy=1");
        check("TC8",obs_dma_start===1'b0,"dma_start NOT pulsed when core_busy=1");
        core_busy=1'b0;
        clear_pulse_flags; dma_busy=1'b1;
        axi_write(BASE|O_CTRL,32'h5,4'hF,4'h1,0); wait_cycles(5);
        check("TC8",obs_core_start===1'b0,"core_start NOT pulsed when dma_busy=1");
        dma_busy=1'b0;
        clear_pulse_flags; axi_write(BASE|O_CTRL,32'h1,4'hF,4'h1,0); wait_cycles(3);
        check("TC8",obs_core_start===1'b1,"core_start fires after busy clears");

        // ── TC9 : STATUS ──────────────────────────────────────────────────────
        $display("\n[TC9] STATUS: core_busy[0], DONE[1], dma_busy[2], DMA_DONE[3], DMA_ERROR[5]");
        apply_reset;
        core_busy=1'b1; wait_cycles(1); axi_read(BASE|O_STATUS,4'h1,0);
        check("TC9",rd_data_cap[0]===1'b1,"STATUS[0] BUSY=1");
        check("TC9",rd_data_cap[2]===1'b0,"STATUS[2] DMA_BUSY=0"); core_busy=1'b0;
        dma_busy=1'b1; wait_cycles(1); axi_read(BASE|O_STATUS,4'h1,0);
        check("TC9",rd_data_cap[0]===1'b0,"STATUS[0] BUSY=0");
        check("TC9",rd_data_cap[2]===1'b1,"STATUS[2] DMA_BUSY=1"); dma_busy=1'b0;
        @(posedge clk);#1;core_done=1'b1;@(posedge clk);#1;core_done=1'b0; wait_cycles(1);
        axi_read(BASE|O_STATUS,4'h1,0); check("TC9",rd_data_cap[1]===1'b1,"STATUS[1] DONE sticky");
        @(posedge clk);#1;dma_done=1'b1;@(posedge clk);#1;dma_done=1'b0; wait_cycles(1);
        axi_read(BASE|O_STATUS,4'h1,0); check("TC9",rd_data_cap[3]===1'b1,"STATUS[3] DMA_DONE sticky");
        @(posedge clk);#1;dma_error=1'b1;@(posedge clk);#1;dma_error=1'b0; wait_cycles(1);
        axi_read(BASE|O_STATUS,4'h1,0);
        check("TC9",rd_data_cap[5]===1'b1,"STATUS[5] DMA_ERROR sticky");
        check("TC9",rd_data_cap[4]===1'b0,"STATUS[4] ERROR=0 (not set)");

        // ── TC10 : CTEXT/TAG capture ──────────────────────────────────────────
        $display("\n[TC10] CTEXT/TAG captured on core_data_out_valid / core_tag_valid");
        apply_reset;
        core_data_out=128'hDEADBEEF_CAFEBABE_01234567_89ABCDEF;
        @(posedge clk);#1;core_data_out_valid=1'b1;
        @(posedge clk);#1;core_data_out_valid=1'b0; wait_cycles(1);
        axi_read(BASE|O_CTEXT_0,4'h1,0); check("TC10",rd_data_cap===32'hDEADBEEF,"CTEXT_0=core_data_out[127:96]");
        axi_read(BASE|O_CTEXT_1,4'h1,0); check("TC10",rd_data_cap===32'hCAFEBABE,"CTEXT_1=core_data_out[95:64]");
        core_tag_out=128'h11111111_22222222_33333333_44444444;
        @(posedge clk);#1;core_tag_valid=1'b1;
        @(posedge clk);#1;core_tag_valid=1'b0; wait_cycles(1);
        axi_read(BASE|O_TAG_0,4'h1,0); check("TC10",rd_data_cap===32'h11111111,"TAG_0 captured");
        axi_read(BASE|O_TAG_1,4'h1,0); check("TC10",rd_data_cap===32'h22222222,"TAG_1 captured");
        axi_read(BASE|O_TAG_2,4'h1,0); check("TC10",rd_data_cap===32'h33333333,"TAG_2 captured");
        axi_read(BASE|O_TAG_3,4'h1,0); check("TC10",rd_data_cap===32'h44444444,"TAG_3 captured");
        axi_read(BASE|O_CTEXT_0,4'h1,0); check("TC10",rd_data_cap===32'hDEADBEEF,"CTEXT_0 still valid after tag capture");

        // ── TC11 : IRQ ────────────────────────────────────────────────────────
        $display("\n[TC11] IRQ: DONE_IRQ_EN, DMA_DONE_IRQ_EN, ERROR_IRQ_EN");
        apply_reset;
        @(posedge clk);#1;core_done=1'b1;@(posedge clk);#1;core_done=1'b0; wait_cycles(1);
        check("TC11",irq===1'b0,"irq=0 when IRQ_EN=0 even with DONE set");
        axi_write(BASE|O_IRQ_EN,32'h1,4'hF,4'h1,0); wait_cycles(1);
        check("TC11",irq===1'b1,"irq=1 after enabling DONE_IRQ_EN");
        axi_write(BASE|O_IRQ_EN,32'h0,4'hF,4'h1,0); wait_cycles(1);
        check("TC11",irq===1'b0,"irq=0 after clearing IRQ_EN");
        apply_reset; axi_write(BASE|O_IRQ_EN,32'h2,4'hF,4'h1,0);
        @(posedge clk);#1;dma_done=1'b1;@(posedge clk);#1;dma_done=1'b0; wait_cycles(1);
        check("TC11",irq===1'b1,"irq=1 after dma_done with DMA_DONE_IRQ_EN");
        apply_reset; axi_write(BASE|O_IRQ_EN,32'h4,4'hF,4'h1,0);
        @(posedge clk);#1;dma_error=1'b1;@(posedge clk);#1;dma_error=1'b0; wait_cycles(1);
        check("TC11",irq===1'b1,"irq=1 after dma_error with ERROR_IRQ_EN");
        apply_reset; axi_write(BASE|O_IRQ_EN,32'h7,4'hF,4'h1,0);
        @(posedge clk);#1;core_done=1'b1;dma_done=1'b1;dma_error=1'b1;
        @(posedge clk);#1;core_done=1'b0;dma_done=1'b0;dma_error=1'b0; wait_cycles(1);
        check("TC11",irq===1'b1,"irq=1 with all three flags + all IRQ_EN bits");

        // ── TC12 : IRQ cleared after SOFT_RST ─────────────────────────────────
        $display("\n[TC12] IRQ cleared after SOFT_RST clears sticky flags");
        axi_write(BASE|O_CTRL,32'h2,4'hF,4'h1,0); wait_cycles(3);
        check("TC12",irq===1'b0,"irq=0 after SOFT_RST");
        axi_read(BASE|O_STATUS,4'h1,0);
        check("TC12",rd_data_cap[1]===1'b0,"DONE cleared after SOFT_RST");
        check("TC12",rd_data_cap[3]===1'b0,"DMA_DONE cleared after SOFT_RST");
        check("TC12",rd_data_cap[5]===1'b0,"DMA_ERROR cleared after SOFT_RST");

        // ── TC13 : W before AW ────────────────────────────────────────────────
        $display("\n[TC13] AXI write: data arrives before address (W before AW)");
        apply_reset;
        axi_write_data_first(BASE|O_MODE,32'h3,4'hF,4'h5); wait_cycles(1);
        axi_read(BASE|O_MODE,4'h1,0);
        check("TC13",rd_data_cap===32'h3,"MODE correct after W-before-AW");
        check("TC13",rd_resp_cap===2'b00,"RRESP=OKAY after W-before-AW");

        // ── TC14 : BREADY delayed ─────────────────────────────────────────────
        $display("\n[TC14] AXI write backpressure: BREADY delayed 5 cycles");
        apply_reset;
        axi_write(BASE|O_DMA_SRC,32'h1234_5678,4'hF,4'h3,5); wait_cycles(1);
        axi_read(BASE|O_DMA_SRC,4'h1,0);
        check("TC14",rd_data_cap===32'h1234_5678,"Write committed despite BREADY delay");
        check("TC14",M_BRESP===2'b00,"BRESP=OKAY with delayed BREADY");

        // ── TC15 : RREADY delayed ─────────────────────────────────────────────
        $display("\n[TC15] AXI read backpressure: RREADY delayed 5 cycles");
        apply_reset;
        axi_write(BASE|O_DMA_DST,32'hABCD_EF00,4'hF,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_DMA_DST,4'h2,5);
        check("TC15",rd_data_cap===32'hABCD_EF00,"Read data correct despite RREADY delay");
        check("TC15",rd_resp_cap===2'b00,"RRESP=OKAY with delayed RREADY");

        // ── TC16 : Unmapped address ───────────────────────────────────────────
        $display("\n[TC16] Unmapped address: read returns 0, write OKAY");
        apply_reset;
        axi_write(BASE|O_UNMAPPED,32'hDEAD_BEEF,4'hF,4'h1,0);
        check("TC16",M_BRESP===2'b00,"Write to unmapped: BRESP=OKAY");
        axi_read(BASE|O_UNMAPPED,4'h1,0);
        check("TC16",rd_data_cap===32'h0,"Read from unmapped returns 0");
        check("TC16",rd_resp_cap===2'b00,"Read from unmapped: RRESP=OKAY");
        axi_read(BASE|O_DMA_LEN,4'h1,0);
        check("TC16",rd_data_cap===32'h8,"DMA_LEN default=8 (unmapped write did not corrupt)");

        // ── TC17 : WSTRB ──────────────────────────────────────────────────────
        $display("\n[TC17] WSTRB byte-enable: partial word write");
        apply_reset;
        axi_write(BASE|O_DMA_SRC,32'hAABBCCDD,4'hF,4'h1,0); wait_cycles(1);
        axi_write(BASE|O_DMA_SRC,32'h000000FF,4'h1,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_DMA_SRC,4'h1,0); check("TC17",rd_data_cap===32'hAABBCCFF,"WSTRB=0x1: byte[0] updated only");
        axi_write(BASE|O_DMA_SRC,32'h11000000,4'h8,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_DMA_SRC,4'h1,0); check("TC17",rd_data_cap===32'h11BBCCFF,"WSTRB=0x8: byte[3] updated only");
        axi_write(BASE|O_DMA_SRC,32'h0000EEFF,4'h3,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_DMA_SRC,4'h1,0); check("TC17",rd_data_cap===32'h11BBEEFF,"WSTRB=0x3: bytes[1:0] updated only");

        // ── TC18 : AXI ID echo ────────────────────────────────────────────────
        $display("\n[TC18] AXI ID echo: BID=AWID, RID=ARID");
        apply_reset;
        axi_write(BASE|O_MODE,32'h1,4'hF,4'hA,0); check("TC18",M_BID===4'hA,"BID echoes AWID=0xA");
        axi_write(BASE|O_MODE,32'h2,4'hF,4'hF,0); check("TC18",M_BID===4'hF,"BID echoes AWID=0xF");
        axi_write(BASE|O_MODE,32'h0,4'hF,4'h0,0); check("TC18",M_BID===4'h0,"BID echoes AWID=0x0");
        axi_read(BASE|O_MODE,4'h7,0); check("TC18",rd_id_cap===4'h7,"RID echoes ARID=0x7");
        axi_read(BASE|O_MODE,4'h3,0); check("TC18",rd_id_cap===4'h3,"RID echoes ARID=0x3");
        axi_read(BASE|O_MODE,4'h0,0); check("TC18",rd_id_cap===4'h0,"RID echoes ARID=0x0");

        // ── TC19 : B2B writes ─────────────────────────────────────────────────
        $display("\n[TC19] Consecutive back-to-back AXI writes");
        apply_reset;
        axi_write(BASE|O_KEY_0,32'h1,4'hF,4'h1,0);
        axi_write(BASE|O_KEY_1,32'h2,4'hF,4'h1,0);
        axi_write(BASE|O_KEY_2,32'h3,4'hF,4'h1,0);
        axi_write(BASE|O_KEY_3,32'h4,4'hF,4'h1,0); wait_cycles(1);
        check("TC19",core_key[127:96]===32'h1,"B2B write: KEY_0");
        check("TC19",core_key[95:64] ===32'h2,"B2B write: KEY_1");
        check("TC19",core_key[63:32] ===32'h3,"B2B write: KEY_2");
        check("TC19",core_key[31:0]  ===32'h4,"B2B write: KEY_3");
        axi_write(BASE|O_NONCE_0,32'hAAAAAAAA,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_1,32'hBBBBBBBB,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_2,32'hCCCCCCCC,4'hF,4'h1,0);
        axi_write(BASE|O_NONCE_3,32'hDDDDDDDD,4'hF,4'h1,0); wait_cycles(1);
        check("TC19",core_nonce[127:96]===32'hAAAAAAAA,"B2B write: NONCE_0");
        check("TC19",core_nonce[31:0]  ===32'hDDDDDDDD,"B2B write: NONCE_3");
        check("TC19",core_data_len===7'd8,"core_data_len constant=8");

        // ── TC20 : B2B reads ──────────────────────────────────────────────────
        $display("\n[TC20] Consecutive back-to-back AXI reads");
        apply_reset;
        axi_write(BASE|O_MODE,   32'h3,       4'hF,4'h1,0);
        axi_write(BASE|O_IRQ_EN, 32'h5,       4'hF,4'h1,0);
        axi_write(BASE|O_DMA_SRC,32'hAAAAAAAA,4'hF,4'h1,0);
        axi_write(BASE|O_DMA_DST,32'hBBBBBBBB,4'hF,4'h1,0);
        axi_write(BASE|O_DMA_LEN,32'h20,      4'hF,4'h1,0); wait_cycles(1);
        axi_read(BASE|O_MODE,   4'h1,0); check("TC20",rd_data_cap===32'h3,       "B2B read: MODE");
        axi_read(BASE|O_IRQ_EN, 4'h1,0); check("TC20",rd_data_cap===32'h5,       "B2B read: IRQ_EN");
        axi_read(BASE|O_DMA_SRC,4'h1,0); check("TC20",rd_data_cap===32'hAAAAAAAA,"B2B read: DMA_SRC");
        axi_read(BASE|O_DMA_DST,4'h1,0); check("TC20",rd_data_cap===32'hBBBBBBBB,"B2B read: DMA_DST");
        axi_read(BASE|O_DMA_LEN,4'h1,0); check("TC20",rd_data_cap===32'h20,      "B2B read: DMA_LEN");
        check("TC20",M_RLAST===1'b1,"RLAST=1 (AXI4-Lite constant)");

        // ── TC21 : 1-cycle pulse width ────────────────────────────────────────
        $display("\n[TC21] core_start and dma_start are exactly 1-cycle pulses");
        apply_reset;
        begin : tc21
            integer pcs,pds,i; pcs=0;pds=0;
            @(posedge clk);#1;
            M_AWID=4'h1;M_AWADDR=BASE|O_CTRL;M_AWPROT=0;M_AWVALID=1'b1;
            M_WDATA=32'h5;M_WSTRB=4'hF;M_WVALID=1'b1;
            for(i=0;i<20;i=i+1) begin @(posedge clk); if(core_start_out)pcs=pcs+1; if(dma_start_out)pds=pds+1; end
            #1;M_AWVALID=1'b0;M_WVALID=1'b0;M_BREADY=1'b1;@(posedge clk);#1;M_BREADY=1'b0;
            check("TC21",pcs===1,"core_start is exactly 1-cycle pulse");
            check("TC21",pds===1,"dma_start is exactly 1-cycle pulse");
        end

        // ── TC22 : soft_rst 1-cycle ───────────────────────────────────────────
        $display("\n[TC22] core_soft_rst and dma_soft_rst are exactly 1-cycle pulses");
        apply_reset;
        begin : tc22
            integer pcr,pdr,i; pcr=0;pdr=0;
            @(posedge clk);#1;
            M_AWID=4'h1;M_AWADDR=BASE|O_CTRL;M_AWPROT=0;M_AWVALID=1'b1;
            M_WDATA=32'h2;M_WSTRB=4'hF;M_WVALID=1'b1;
            for(i=0;i<20;i=i+1) begin @(posedge clk); if(core_soft_rst_out)pcr=pcr+1; if(dma_soft_rst_out)pdr=pdr+1; end
            #1;M_AWVALID=1'b0;M_WVALID=1'b0;M_BREADY=1'b1;@(posedge clk);#1;M_BREADY=1'b0;
            check("TC22",pcr===1,"core_soft_rst is exactly 1-cycle pulse");
            check("TC22",pdr===1,"dma_soft_rst is exactly 1-cycle pulse");
        end

        // ── TC23 : START+DMA_EN=0 no dma_start ───────────────────────────────
        $display("\n[TC23] START with DMA_EN=0: dma_start must not fire");
        apply_reset;
        axi_read(BASE|O_CTRL,4'h1,0); check("TC23",rd_data_cap[2]===1'b0,"DMA_EN=0 after reset");
        clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h1,4'hF,4'h1,0); wait_cycles(3);
        check("TC23",obs_core_start===1'b1,"core_start fired");
        check("TC23",obs_dma_start===1'b0,"dma_start NOT fired (DMA_EN=0)");
        axi_write(BASE|O_CTRL,32'h4,4'hF,4'h1,0); clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h0,4'hF,4'h1,0); wait_cycles(1);
        axi_write(BASE|O_CTRL,32'h1,4'hF,4'h1,0); wait_cycles(3);
        check("TC23",obs_dma_start===1'b0,"dma_start NOT fired after DMA_EN cleared");

        // ── TC24 : SOFT_RST fires both ────────────────────────────────────────
        $display("\n[TC24] SOFT_RST: core_soft_rst and dma_soft_rst fire together");
        apply_reset;
        @(posedge clk);#1;core_done=1'b1;dma_done=1'b1;
        @(posedge clk);#1;core_done=1'b0;dma_done=1'b0; wait_cycles(1);
        clear_pulse_flags;
        axi_write(BASE|O_CTRL,32'h2,4'hF,4'h1,0); wait_cycles(3);
        check("TC24",obs_core_soft_rst===1'b1,"core_soft_rst fires with SOFT_RST");
        check("TC24",obs_dma_soft_rst===1'b1,"dma_soft_rst fires with SOFT_RST");
        axi_write(BASE|O_IRQ_EN,32'h7,4'hF,4'h1,0); wait_cycles(1);
        check("TC24",irq===1'b0,"irq=0 after SOFT_RST clears all flags");

        // ── Summary ───────────────────────────────────────────────────────────
        $display("\n================================================================");
        $display("   TEST RESULTS SUMMARY");
        $display("================================================================");
        $display("   PASS : %0d", pass_count);
        $display("   FAIL : %0d", fail_count);
        if (fail_count == 0) $display("   *** ALL TESTS PASSED ***");
        else                 $display("   *** %0d TEST(S) FAILED ***", fail_count);
        $display("================================================================");
        #100; $finish;
    end

    // ── Watchdog ──────────────────────────────────────────────────────────────
    initial begin #1_000_000; $display("[WATCHDOG] Timeout at %0t!",$time); $finish; end

    // ── Monitors ──────────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if(M_AWVALID&&M_AWREADY) $display("[AXI-AW @%0t] addr=%08h id=%0h",$time,M_AWADDR,M_AWID);
        if(M_WVALID&&M_WREADY)   $display("[AXI-W  @%0t] data=%08h strb=%0h",$time,M_WDATA,M_WSTRB);
        if(M_BVALID&&M_BREADY)   $display("[AXI-B  @%0t] resp=%0b id=%0h",$time,M_BRESP,M_BID);
        if(M_ARVALID&&M_ARREADY) $display("[AXI-AR @%0t] addr=%08h id=%0h",$time,M_ARADDR,M_ARID);
        if(M_RVALID&&M_RREADY)   $display("[AXI-R  @%0t] data=%08h resp=%0b id=%0h last=%0b",$time,M_RDATA,M_RRESP,M_RID,M_RLAST);
        if(core_start_out)    $display("[CTRL @%0t] core_start    PULSE",$time);
        if(core_soft_rst_out) $display("[CTRL @%0t] core_soft_rst PULSE",$time);
        if(dma_start_out)     $display("[CTRL @%0t] dma_start     PULSE",$time);
        if(dma_soft_rst_out)  $display("[CTRL @%0t] dma_soft_rst  PULSE",$time);
        if(irq)               $display("[IRQ  @%0t] irq=1",$time);
    end

endmodule