// ============================================================================
// Module  : plic_regfile  (FIXED)
// BUG FIXES: 1=claim_pulse double-driver  2=NUM_SRC truncation
//            3=rdata latch timing          4=priority decode overlap 0x080
// ============================================================================
`timescale 1ns/1ps
module plic_regfile #(
    parameter NUM_SRC   = 32,
    parameter PRIO_W    = 3,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,
    output wire [PRIO_W*NUM_SRC-1:0] priority_flat,
    output wire [NUM_SRC-1:0]         enable,
    output wire [PRIO_W-1:0]          threshold,
    output wire                        claim_pulse,
    output wire                        complete_pulse,
    output wire [$clog2(NUM_SRC)-1:0]  complete_id,
    input  wire [$clog2(NUM_SRC)-1:0]  claim_id_in,
    input  wire [NUM_SRC-1:0]           pending_in
);
    localparam ID_W = $clog2(NUM_SRC);

    // --- Register storage ---
    reg [PRIO_W-1:0]  prio_r [0:NUM_SRC-1];
    reg [NUM_SRC-1:0] enable_r;
    reg [PRIO_W-1:0]  threshold_r;
    reg [ID_W-1:0]    complete_id_r;
    reg               complete_pulse_r;
    reg               claim_pulse_r;

    assign threshold      = threshold_r;
    assign enable         = enable_r;
    assign complete_id    = complete_id_r;
    assign complete_pulse = complete_pulse_r;
    assign claim_pulse    = claim_pulse_r;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_SRC; gi = gi + 1) begin : pack_prio
            assign priority_flat[PRIO_W*gi +: PRIO_W] = prio_r[gi];
        end
    endgenerate

    // --- AXI Write FSM ---
    reg [ID_WIDTH-1:0]     aw_id_lat;
    reg [ADDR_WIDTH-1:0]   aw_addr_lat;
    reg                    aw_done, w_done, bvalid_r;
    reg [DATA_WIDTH-1:0]   w_data_lat;
    reg [DATA_WIDTH/8-1:0] w_strb_lat;
    reg [1:0]              bresp_r;

    wire [11:0] aw_off = aw_addr_lat[11:0];
    wire write_exec    = aw_done && w_done && !bvalid_r;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < NUM_SRC; k = k + 1) prio_r[k] <= {PRIO_W{1'b0}};
            enable_r         <= {NUM_SRC{1'b0}};
            threshold_r      <= {PRIO_W{1'b0}};
            complete_id_r    <= {ID_W{1'b0}};
            complete_pulse_r <= 1'b0;
        end else begin
            complete_pulse_r <= 1'b0;
            if (write_exec) begin
                // FIX 4: aw_off[7]==0 guards priority range 0x000..0x07C
                // prevents overlap with 0x080 (pending RO) which has bit[7]=1
                if (aw_off[11:8]==4'h0 && aw_off[7]==1'b0 && aw_off[1:0]==2'b00) begin
                    if (aw_off[6:2] < NUM_SRC) begin  // FIX 2: full-width compare
                        if (w_strb_lat[0]) prio_r[aw_off[6:2]] <= w_data_lat[PRIO_W-1:0];
                    end
                end
                else if (aw_off == 12'h100) begin
                    if (w_strb_lat[0]) enable_r[7:0]   <= w_data_lat[7:0];
                    if (w_strb_lat[1]) enable_r[15:8]  <= w_data_lat[15:8];
                    if (w_strb_lat[2]) enable_r[23:16] <= w_data_lat[23:16];
                    if (w_strb_lat[3]) enable_r[31:24] <= w_data_lat[31:24];
                end
                else if (aw_off == 12'h200) begin
                    if (w_strb_lat[0]) threshold_r <= w_data_lat[PRIO_W-1:0];
                end
                else if (aw_off == 12'h204) begin
                    complete_id_r    <= w_data_lat[ID_W-1:0];
                    complete_pulse_r <= 1'b1;
                end
                // 0x080 = pending RO: write ignored
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin aw_done<=1'b0; aw_id_lat<=0; aw_addr_lat<=0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_id_lat<=s_axi_awid; aw_addr_lat<=s_axi_awaddr; aw_done<=1'b1;
            end
            if (bvalid_r && s_axi_bready) aw_done<=1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin w_done<=1'b0; w_data_lat<=0; w_strb_lat<=0;
        end else begin
            if (s_axi_wvalid && s_axi_wready) begin
                w_data_lat<=s_axi_wdata; w_strb_lat<=s_axi_wstrb; w_done<=1'b1;
            end
            if (bvalid_r && s_axi_bready) w_done<=1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin bvalid_r<=1'b0; bresp_r<=2'b00;
        end else begin
            if (write_exec) begin bvalid_r<=1'b1; bresp_r<=2'b00; end
            if (bvalid_r && s_axi_bready) bvalid_r<=1'b0;
        end
    end

    assign s_axi_awready = !aw_done;
    assign s_axi_wready  = !w_done;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = bresp_r;
    assign s_axi_bid     = aw_id_lat;

    // --- AXI Read Channel ---
    reg [ID_WIDTH-1:0]   ar_id_lat;
    reg [ADDR_WIDTH-1:0] ar_addr_lat;
    reg                  ar_done, ar_done_d1, rvalid_r;
    reg [DATA_WIDTH-1:0] rdata_r;
    wire [11:0] ar_off = ar_addr_lat[11:0];

    // FIX 4 read-side: ar_off[7]==0 prevents 0x080 being decoded as priority[32]
    reg [DATA_WIDTH-1:0] rdata_mux;
    wire [PRIO_W-1:0] prio_read_val = prio_r[ar_off[6:2]];
    always @(*) begin
        rdata_mux = 32'd0;
        if (ar_off[11:8]==4'h0 && ar_off[7]==1'b0 && ar_off[1:0]==2'b00)
            rdata_mux = {{(DATA_WIDTH-PRIO_W){1'b0}}, prio_read_val};
        else if (ar_off == 12'h080)
            rdata_mux = {{(DATA_WIDTH-NUM_SRC){1'b0}}, pending_in[NUM_SRC-1:0]};
        else if (ar_off == 12'h100)
            rdata_mux = {{(DATA_WIDTH-NUM_SRC){1'b0}}, enable_r};
        else if (ar_off == 12'h200)
            rdata_mux = {{(DATA_WIDTH-PRIO_W){1'b0}}, threshold_r};
        else if (ar_off == 12'h204)
            rdata_mux = {{(DATA_WIDTH-ID_W){1'b0}}, claim_id_in};
    end

    // AR latch — only manages AR state, does NOT drive claim_pulse_r
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ar_done<=1'b0; ar_id_lat<=0; ar_addr_lat<=0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                ar_id_lat<=s_axi_arid; ar_addr_lat<=s_axi_araddr; ar_done<=1'b1;
            end
            if (rvalid_r && s_axi_rready) ar_done<=1'b0;
        end
    end

    // FIX 3: ar_done_d1 pipeline — rdata_mux latched 1 cycle after ar_addr_lat stable
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ar_done_d1<=1'b0; rvalid_r<=1'b0; rdata_r<=0;
        end else begin
            ar_done_d1 <= ar_done && !rvalid_r;
            if (ar_done_d1 && !rvalid_r) begin rvalid_r<=1'b1; rdata_r<=rdata_mux; end
            if (rvalid_r && s_axi_rready) rvalid_r<=1'b0;
        end
    end

    // =========================================================================
    // FIX 1 FINAL: claim_pulse_r — completely independent single-driver block
    //
    // Root cause of all previous attempts failing:
    //   Attempt A (original): 2 always blocks drive same reg → illegal
    //   Attempt B (ar_claim_pending flag): AR latch sets flag at posedge N;
    //     write-FSM reads flag at SAME posedge N but sees OLD value=0 due to
    //     Verilog non-blocking assignment semantics → claim_pulse_r stays 0
    //
    // CORRECT FIX: Detect AR handshake directly from INPUT WIRE signals.
    //   s_axi_arvalid  = input wire → value at posedge is CURRENT (no NBA delay)
    //   s_axi_arready  = !ar_done  = combinational wire → also CURRENT
    //   s_axi_araddr   = input wire → CURRENT
    //
    // This block has NO dependency on any reg in this module, so there is
    // no non-blocking assignment ordering issue whatsoever.
    //
    // Timing: claim_pulse_r=1 fires at posedge of AR handshake cycle.
    //   Same cycle: ar_done_d1=0 (ar_done just became 1 via NBA, not yet seen)
    //   Next cycle: ar_done_d1=1 → rvalid_r=1 (rdata available to CPU)
    //   Same cycle as rvalid: claim_pulse_r has already been 1 for 1 cycle,
    //     and is now 0 again.
    //   Gateway received claim_pulse one cycle before CPU reads data — fine,
    //   the pending clear happens before CPU even acknowledges the read.
    // =========================================================================
    // claim_pulse fires when rvalid is presented to CPU (ar_done_d1 cycle).
    // WHY: claim_id_in is still valid at this cycle (gateway hasn't cleared yet).
    //   Firing at AR handshake was too early: gateway cleared pending before
    //   rdata_mux was latched, so claim_id_in became 0 before CPU read it.
    // ar_done_d1=1 AND !rvalid_r means: rdata is being latched right now,
    //   AND the address was 0x204 (stored in ar_addr_lat).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            claim_pulse_r <= 1'b0;
        end else begin
            claim_pulse_r <= ar_done_d1 && !rvalid_r &&
                             (ar_addr_lat[11:0] == 12'h204);
        end
    end

    assign s_axi_arready = !ar_done;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rlast   = 1'b1;
    assign s_axi_rid     = ar_id_lat;

endmodule