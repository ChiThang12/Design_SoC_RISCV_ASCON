`timescale 1ns/1ps
// ============================================================
// Testbench : plic_top_tb
// DUT       : plic_top (+ plic_regfile, plic_gateway, plic_priority_encoder)
// Simulator : Icarus Verilog
//
// Compile:
//   iverilog -o sim.vvp plic_top_tb.v plic_top.v \
//            plic_regfile.v plic_gateway.v plic_priority_encoder.v
//   (hoặc nếu plic_top.v dùng `include thì chỉ cần:)
//   iverilog -o sim.vvp plic_top_tb.v plic_top.v
//
// Run     : vvp sim.vvp
// Wave    : gtkwave dump.vcd
// ============================================================

// ============================================================
// THIẾT KẾ TEST
// ============================================================
// Nhóm 1 — AXI4 Protocol:
//   TC_AXI_01 : Single write + read-back priority register
//   TC_AXI_02 : Byte strobe — chỉ ghi byte thấp nhất
//   TC_AXI_03 : BID == AWID tracking
//   TC_AXI_04 : RID == ARID tracking
//   TC_AXI_05 : RLAST assert ở beat cuối (single beat)
//   TC_AXI_06 : Ghi địa chỉ ngoài vùng register → vẫn BRESP=OKAY (DUT không có SLVERR)
//
// Nhóm 2 — Reset:
//   TC_RST_01 : meip=0 sau reset
//   TC_RST_02 : pending=0 sau reset
//   TC_RST_03 : enable=0 sau reset, priority=0 sau reset
//
// Nhóm 3 — PLIC Functional:
//   PLIC_01 : priority=0 → không bao giờ claim (luôn bị filter vì 0 <= threshold=0)
//   PLIC_02 : IRQ flow cơ bản — 1 source, priority>threshold → meip assert
//   PLIC_03 : Claim flow — đọc 0x204 → claim_pulse → gateway clear pending
//   PLIC_04 : Complete flow — ghi 0x204 → complete → gateway in_service clear
//             → meip deassert sau complete
//   PLIC_05 : 2 source cùng pending, priority khác → claim trả source cao hơn
//   PLIC_06 : threshold mask — threshold >= priority → meip không assert
//   PLIC_07 : enable mask — enable[N]=0 → meip không assert dù pending
//   PLIC_08 : Đọc claim khi không có ngắt → trả về 0
//   PLIC_09 : Đọc pending register phản ánh gateway state
//   PLIC_10 : Tie-break — 2 source cùng priority → source ID nhỏ hơn thắng
//   PLIC_11 : Gateway in_service — trong khi claim chưa complete,
//             IRQ mới không set pending
//   PLIC_12 : Gateway sau complete — IRQ mới được nhận lại
// ============================================================
`include "plic/rtl/plic_top.v"
module plic_top_tb;

// ---- Parameters ----
parameter CLK_PERIOD = 10;   // 10ns = 100MHz
parameter NUM_SRC    = 32;
parameter PRIO_W     = 3;
parameter AXI_AW     = 32;
parameter AXI_DW     = 32;
parameter AXI_IW     = 4;

// ---- Base address (offset vào DUT — TB dùng offset trực tiếp) ----
// Vì DUT lấy addr[11:0] làm offset, ta chỉ cần đặt địa chỉ đúng
parameter BASE = 32'h5004_0000;   // Base address (tùy chọn, DUT chỉ dùng [11:0])

// Các offset register
parameter OFF_PRIO0     = 12'h000;  // priority[0]
parameter OFF_PRIO1     = 12'h004;  // priority[1]
parameter OFF_PRIO2     = 12'h008;  // priority[2]
parameter OFF_PRIO3     = 12'h00C;  // priority[3]
parameter OFF_PENDING   = 12'h080;  // pending (RO)
parameter OFF_ENABLE    = 12'h100;  // enable[0]
parameter OFF_THRESHOLD = 12'h200;  // threshold
parameter OFF_CLAIM     = 12'h204;  // claim (R) / complete (W)

// ---- Clock & Reset ----
reg clk;
reg rst_n;
initial clk = 1'b0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---- AXI4-Full Master Signals ----
reg  [AXI_IW-1:0]  awid;
reg  [AXI_AW-1:0]  awaddr;
reg  [7:0]          awlen;
reg  [2:0]          awsize;
reg  [1:0]          awburst;
reg  [2:0]          awprot;
reg                 awvalid;
wire                awready;

reg  [AXI_DW-1:0]  wdata;
reg  [3:0]          wstrb;
reg                 wlast;
reg                 wvalid;
wire                wready;

wire [AXI_IW-1:0]  bid;
wire [1:0]          bresp;
wire                bvalid;
reg                 bready;

reg  [AXI_IW-1:0]  arid;
reg  [AXI_AW-1:0]  araddr;
reg  [7:0]          arlen;
reg  [2:0]          arsize;
reg  [1:0]          arburst;
reg  [2:0]          arprot;
reg                 arvalid;
wire                arready;

wire [AXI_IW-1:0]  rid;
wire [AXI_DW-1:0]  rdata;
wire [1:0]          rresp;
wire                rlast;
wire                rvalid;
reg                 rready;

// ---- IRQ Sources & meip output ----
reg  [NUM_SRC-1:0]  irq_src;
wire                 meip;

// ---- DUT Instantiation ----
// Lưu ý: plic_top.v dùng `include nên không cần list các file con
// Nếu compile tách file thì xóa `include trong plic_top.v
plic_top #(
    .NUM_SRC    (NUM_SRC),
    .PRIO_W     (PRIO_W),
    .ADDR_WIDTH (AXI_AW),
    .DATA_WIDTH (AXI_DW),
    .ID_WIDTH   (AXI_IW)
) u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    // AW
    .s_axi_awid     (awid),
    .s_axi_awaddr   (awaddr),
    .s_axi_awlen    (awlen),
    .s_axi_awsize   (awsize),
    .s_axi_awburst  (awburst),
    .s_axi_awprot   (awprot),
    .s_axi_awvalid  (awvalid),
    .s_axi_awready  (awready),
    // W
    .s_axi_wdata    (wdata),
    .s_axi_wstrb    (wstrb),
    .s_axi_wlast    (wlast),
    .s_axi_wvalid   (wvalid),
    .s_axi_wready   (wready),
    // B
    .s_axi_bid      (bid),
    .s_axi_bresp    (bresp),
    .s_axi_bvalid   (bvalid),
    .s_axi_bready   (bready),
    // AR
    .s_axi_arid     (arid),
    .s_axi_araddr   (araddr),
    .s_axi_arlen    (arlen),
    .s_axi_arsize   (arsize),
    .s_axi_arburst  (arburst),
    .s_axi_arprot   (arprot),
    .s_axi_arvalid  (arvalid),
    .s_axi_arready  (arready),
    // R
    .s_axi_rid      (rid),
    .s_axi_rdata    (rdata),
    .s_axi_rresp    (rresp),
    .s_axi_rlast    (rlast),
    .s_axi_rvalid   (rvalid),
    .s_axi_rready   (rready),
    // IRQ
    .irq_src        (irq_src),
    .meip           (meip)
);

// ---- Waveform Dump ----
initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, plic_top_tb);
end

// ---- Timeout Watchdog ----
// PLIC không có baud divider nên mỗi transaction chỉ vài cycle
initial begin
    #500_000;
    $display("[FAIL] Simulation TIMEOUT — có thể AXI deadlock!");
    $finish;
end

// ============================================================
// BFM — AXI4-Full Master Tasks
// ============================================================

// Biến tạm để nhận giá trị đọc về
reg [31:0] rd_data;
integer    pass_count;
integer    fail_count;

// ---- axi_write: single-beat write ----
// WHY task: đảm bảo đúng giao thức AXI — chờ ready trước khi deassert valid
task axi_write;
    input [3:0]  t_id;
    input [31:0] t_addr;
    input [31:0] t_data;
    input [3:0]  t_strb;
    begin
        // Chờ 1 cycle để đảm bảo channel idle từ transaction trước
        @(posedge clk); #1;
        // AW channel: assert và chờ handshake
        awid    = t_id;
        awaddr  = t_addr;
        awlen   = 8'h00;      // 1 beat (AWLEN=0 → 1 transfer)
        awsize  = 3'b010;     // 4 bytes per beat
        awburst = 2'b01;      // INCR
        awprot  = 3'b000;
        awvalid = 1'b1;
        // Đợi DUT sẵn sàng nhận địa chỉ
        wait(awready === 1'b1);
        @(posedge clk); #1;
        awvalid = 1'b0;

        // W channel: gửi data
        wdata  = t_data;
        wstrb  = t_strb;
        wlast  = 1'b1;        // BẮT BUỘC với single beat — DUT dùng để kết thúc burst
        wvalid = 1'b1;
        wait(wready === 1'b1);
        @(posedge clk); #1;
        wvalid = 1'b0;
        wlast  = 1'b0;

        // B channel: nhận response
        bready = 1'b1;
        wait(bvalid === 1'b1);
        // Check BID == AWID (quan trọng khi có nhiều transaction in-flight)
        if (bid !== t_id) begin
            $display("[FAIL] AXI: BID=%0d != AWID=%0d tại addr 0x%08h", bid, t_id, t_addr);
            fail_count = fail_count + 1;
        end
        // Check BRESP == OKAY
        if (bresp !== 2'b00) begin
            $display("[FAIL] AXI: BRESP=2'b%02b (error) tại addr 0x%08h", bresp, t_addr);
            fail_count = fail_count + 1;
        end
        @(posedge clk); #1;
        bready = 1'b0;
    end
endtask

// ---- axi_read: single-beat read ----
task axi_read;
    input  [3:0]  t_id;
    input  [31:0] t_addr;
    output [31:0] t_rdata;
    begin
        // Chờ 1 cycle để đảm bảo channel idle từ transaction trước
        @(posedge clk); #1;
        // AR channel
        arid    = t_id;
        araddr  = t_addr;
        arlen   = 8'h00;
        arsize  = 3'b010;
        arburst = 2'b01;
        arprot  = 3'b000;
        arvalid = 1'b1;
        wait(arready === 1'b1);
        @(posedge clk); #1;
        arvalid = 1'b0;

        // R channel
        rready = 1'b1;
        wait(rvalid === 1'b1);
        t_rdata = rdata;
        // Check RID == ARID
        if (rid !== t_id) begin
            $display("[FAIL] AXI: RID=%0d != ARID=%0d tại addr 0x%08h", rid, t_id, t_addr);
            fail_count = fail_count + 1;
        end
        // Check RRESP == OKAY
        if (rresp !== 2'b00) begin
            $display("[FAIL] AXI: RRESP=2'b%02b (error) tại addr 0x%08h", rresp, t_addr);
            fail_count = fail_count + 1;
        end
        // Check RLAST — với single beat phải assert
        if (rlast !== 1'b1) begin
            $display("[FAIL] AXI: RLAST không assert ở beat cuối, addr 0x%08h", t_addr);
            fail_count = fail_count + 1;
        end
        @(posedge clk); #1;
        rready = 1'b0;
        // Thêm 1 idle cycle sau handshake: đảm bảo ar_done clear trước transaction kế tiếp
        @(posedge clk); #1;
    end
endtask

// ---- check_eq: so sánh và in PASS/FAIL ----
task check_eq;
    input [31:0] actual;
    input [31:0] expected;
    input [8*32-1:0] name;   // tên test (string tối đa 32 ký tự)
    begin
        if (actual === expected) begin
            $display("[PASS] %s: 0x%08h", name, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] %s: got 0x%08h, expect 0x%08h", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---- check_bit: so sánh 1 bit ----
task check_bit;
    input actual;
    input expected;
    input [8*32-1:0] name;
    begin
        if (actual === expected) begin
            $display("[PASS] %s: %b", name, actual);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] %s: got %b, expect %b", name, actual, expected);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---- do_reset: reset sequence an toàn ----
// WHY 10 cycle: đủ để flush pipeline AXI bên trong DUT
task do_reset;
    begin
        rst_n   = 1'b0;
        // Khởi tạo tất cả master signal về 0 (không drive X vào DUT)
        awvalid = 1'b0; wvalid  = 1'b0; bready  = 1'b0;
        arvalid = 1'b0; rready  = 1'b0;
        awid    = 4'h0; awaddr  = 32'h0; awlen   = 8'h0;
        awsize  = 3'b010; awburst = 2'b01; awprot = 3'b0;
        wdata   = 32'h0; wstrb   = 4'hF;  wlast  = 1'b0;
        arid    = 4'h0; araddr  = 32'h0; arlen   = 8'h0;
        arsize  = 3'b010; arburst = 2'b01; arprot = 3'b0;
        irq_src = {NUM_SRC{1'b0}};
        repeat(10) @(posedge clk);
        // Deassert đồng bộ SAU cạnh lên để tránh metastability
        rst_n = 1'b1;
        repeat(5) @(posedge clk);   // Chờ pipeline ổn định
    end
endtask

// ---- Wrappers: ghi/đọc theo offset ----
// Dùng địa chỉ = BASE + offset để DUT nhận đúng [11:0]
task write_reg;
    input [11:0] offset;
    input [31:0] data;
    input [3:0]  strb;
    begin
        axi_write(4'h1, BASE | {20'h0, offset}, data, strb);
    end
endtask

task read_reg;
    input  [11:0] offset;
    output [31:0] data;
    begin
        axi_read(4'h2, BASE | {20'h0, offset}, data);
    end
endtask

// ---- Helper: trigger rising edge trên irq_src[N] ----
// WHY cần 3 cycle minimum sau khi gọi xong:
//   Cycle T+0: irq_src đổi 0→1 (sau posedge)
//   Cycle T+1: gateway latch irq_prev=1, irq_edge=1 → pending_r <= 1
//   Cycle T+2: pending_r = 1 (stable, propagate ra output)
//   Cycle T+3: encoder thấy pending, meip có thể assert
// → Sau khi gọi trigger_irq, TB phải chờ ít nhất 4 cycle trước khi check.
task trigger_irq;
    input [4:0] src;   // source số (1..31)
    begin
        // Đảm bảo bắt đầu từ 0 (nếu đang HIGH thì tạo cạnh xuống trước)
        irq_src[src] = 1'b0;
        @(posedge clk); #1;
        // Tạo cạnh lên — gateway sẽ detect irq_edge = irq_in & ~irq_prev
        irq_src[src] = 1'b1;
        // Chờ 2 cycle để gateway set pending_r và output stable
        @(posedge clk); #1;
        @(posedge clk); #1;
    end
endtask

task release_irq;
    input [4:0] src;
    begin
        irq_src[src] = 1'b0;
        @(posedge clk); #1;
    end
endtask

// ---- Helper: thực hiện claim/complete cycle đầy đủ ----
task do_claim_complete;
    output [31:0] claimed_id;
    begin
        read_reg(OFF_CLAIM, claimed_id);
        // Dùng wait_meip_clear thay repeat cố định — chắc chắn pending=0
        wait_meip_clear;
        write_reg(OFF_CLAIM, claimed_id, 4'hF);
        repeat(3) @(posedge clk);
    end
endtask

// ---- Helper: chờ meip deassert (timeout 200 cycle) ----
// WHY: thay vì repeat(N) cố định, poll meip để không phụ thuộc vào
//      timing chain cụ thể của implementation (an toàn khi DUT thay đổi).
task wait_meip_clear;
    integer cnt;
    begin
        cnt = 0;
        while (meip !== 1'b0 && cnt < 200) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
        end
        if (cnt >= 200) begin
            $display("[FAIL] wait_meip_clear: TIMEOUT — meip van=1 sau 200 cycle");
            fail_count = fail_count + 1;
        end
        // 1 cycle extra để encoder output ổn định
        @(posedge clk); #1;
    end
endtask

// ---- Helper: chờ meip assert (timeout 200 cycle) ----
task wait_meip_set;
    integer cnt;
    begin
        cnt = 0;
        while (meip !== 1'b1 && cnt < 200) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
        end
        if (cnt >= 200) begin
            $display("[FAIL] wait_meip_set: TIMEOUT — meip van=0 sau 200 cycle");
            fail_count = fail_count + 1;
        end
        @(posedge clk); #1;
    end
endtask

// ============================================================
// MAIN TEST
// ============================================================
integer i;
reg [31:0] tmp;
reg [31:0] claimed;

initial begin
    pass_count = 0;
    fail_count = 0;

    $display("============================================================");
    $display("=== START: plic_top Testbench ===");
    $display("============================================================");

    // ===========================================================
    // NHÓM RESET — kiểm tra trạng thái sau power-on reset
    // ===========================================================
    $display("\n--- NHOM RESET ---");

    do_reset;

    // TC_RST_01: meip phải = 0 ngay sau reset
    // WHY: không có source nào pending, encoder output = 0
    check_bit(meip, 1'b0, "TC_RST_01: meip=0 sau reset");

    // TC_RST_02: Đọc enable register sau reset → phải = 0
    // WHY: không có source nào được enable → ngắt bị mask hoàn toàn
    read_reg(OFF_ENABLE, rd_data);
    check_eq(rd_data, 32'h0, "TC_RST_02: enable=0 sau reset");

    // TC_RST_03: Đọc threshold sau reset → phải = 0
    // WHY: PLIC spec không quy định default, code reset về 0
    read_reg(OFF_THRESHOLD, rd_data);
    check_eq(rd_data, 32'h0, "TC_RST_03: threshold=0 sau reset");

    // TC_RST_04: Đọc priority[1] sau reset → phải = 0
    read_reg(OFF_PRIO1, rd_data);
    check_eq(rd_data, 32'h0, "TC_RST_04: priority[1]=0 sau reset");

    // TC_RST_05: Đọc pending sau reset → phải = 0
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data, 32'h0, "TC_RST_05: pending=0 sau reset");

    // TC_RST_06: Claim register (0x204) khi không có pending → phải = 0
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h0, "TC_RST_06: claim=0 khi khong co IRQ");

    // ===========================================================
    // NHÓM AXI4 PROTOCOL
    // ===========================================================
    $display("\n--- NHOM AXI4 PROTOCOL ---");

    do_reset;

    // TC_AXI_01: Single write + read-back priority[1]
    // WHY: kiểm tra data path cơ bản, không bị stuck
    write_reg(OFF_PRIO1, 32'h00000005, 4'hF);
    read_reg(OFF_PRIO1, rd_data);
    // priority[1] là PRIO_W=3 bit → mask 3 bit thấp
    check_eq(rd_data & 32'h7, 32'h5, "TC_AXI_01: write/read priority[1]=5");

    // TC_AXI_02: Byte strobe — chỉ ghi byte 0 (strb=4'h1)
    // WHY: WSTRB quan trọng, ghi sai byte có thể corrupt register khác
    // Reset priority[2] về 0 trước
    write_reg(OFF_PRIO2, 32'h00000000, 4'hF);
    // Ghi priority[2]=7 chỉ qua byte strobe 0
    write_reg(OFF_PRIO2, 32'h00000007, 4'h1);   // strb=0001 → byte[0] = 0x07
    read_reg(OFF_PRIO2, rd_data);
    check_eq(rd_data & 32'h7, 32'h7, "TC_AXI_02: byte strobe wstrb=4h1 ghi dung");

    // TC_AXI_03: Ghi strb=4'h0 không được thay đổi register
    // WHY: strb=0 có nghĩa là không ghi byte nào, register phải giữ nguyên
    write_reg(OFF_PRIO1, 32'h00000000, 4'h0);   // strb=0 → không ghi gì
    read_reg(OFF_PRIO1, rd_data);
    check_eq(rd_data & 32'h7, 32'h5, "TC_AXI_03: strb=0 khong thay doi register");

    // TC_AXI_04: BID == AWID — dùng ID=5
    // WHY: Out-of-order completion cần ID tracking đúng
    // Dùng trực tiếp axi_write với custom ID
    @(posedge clk); #1;
    awid = 4'h5; awaddr = BASE | 32'h004; awlen = 8'h0;
    awsize = 3'b010; awburst = 2'b01; awprot = 3'b0;
    awvalid = 1'b1;
    wait(awready === 1'b1); @(posedge clk); #1;
    awvalid = 1'b0;
    wdata = 32'h3; wstrb = 4'hF; wlast = 1'b1; wvalid = 1'b1;
    wait(wready === 1'b1); @(posedge clk); #1;
    wvalid = 1'b0; wlast = 1'b0;
    bready = 1'b1;
    wait(bvalid === 1'b1);
    if (bid === 4'h5) begin
        $display("[PASS] TC_AXI_04: BID=5 == AWID=5");
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] TC_AXI_04: BID=%0d != AWID=5", bid);
        fail_count = fail_count + 1;
    end
    @(posedge clk); #1; bready = 1'b0;

    // TC_AXI_05: RID == ARID — dùng ID=7
    @(posedge clk); #1;
    arid = 4'h7; araddr = BASE | 32'h004; arlen = 8'h0;
    arsize = 3'b010; arburst = 2'b01; arprot = 3'b0;
    arvalid = 1'b1;
    wait(arready === 1'b1); @(posedge clk); #1;
    arvalid = 1'b0;
    rready = 1'b1;
    wait(rvalid === 1'b1);
    if (rid === 4'h7) begin
        $display("[PASS] TC_AXI_05: RID=7 == ARID=7");
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] TC_AXI_05: RID=%0d != ARID=7", rid);
        fail_count = fail_count + 1;
    end
    // TC_AXI_06: RLAST assert cho single beat
    if (rlast === 1'b1) begin
        $display("[PASS] TC_AXI_06: RLAST=1 cho single-beat read");
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL] TC_AXI_06: RLAST=0, expect 1 cho single-beat");
        fail_count = fail_count + 1;
    end
    @(posedge clk); #1; rready = 1'b0;

    // TC_AXI_07: Write/read enable register đầy đủ 32 bit
    // WHY: enable bitmap là 32 bit, cần kiểm tra tất cả byte lane
    write_reg(OFF_ENABLE, 32'hDEAD_BEEF, 4'hF);
    read_reg(OFF_ENABLE, rd_data);
    check_eq(rd_data, 32'hDEAD_BEEF, "TC_AXI_07: enable R/W 32bit");

    // ===========================================================
    // NHÓM PLIC FUNCTIONAL
    // ===========================================================
    $display("\n--- NHOM PLIC FUNCTIONAL ---");

    do_reset;

    // *** PLIC_01: priority=0 → không bao giờ được claim ***
    // WHY: PLIC spec: source với priority=0 bị disable vĩnh viễn
    //      Encoder kiểm tra prio[i] > threshold (0 > 0 = false) → bị lọc
    $display("\n[TEST] PLIC_01: priority=0 khong duoc claim");
    write_reg(OFF_ENABLE, 32'hFFFF_FFFF, 4'hF);   // enable tất cả
    write_reg(OFF_THRESHOLD, 32'h0, 4'hF);          // threshold=0
    write_reg(OFF_PRIO1, 32'h0, 4'hF);              // priority[1]=0 (disabled)
    trigger_irq(5'd1);
    repeat(5) @(posedge clk);
    check_bit(meip, 1'b0, "PLIC_01: priority=0 -> meip=0");
    release_irq(5'd1);
    // Complete để clear nếu có claim lỡ
    write_reg(OFF_CLAIM, 32'h1, 4'hF);
    repeat(3) @(posedge clk);

    // *** PLIC_02: IRQ flow cơ bản ***
    // WHY: đây là luồng cơ bản nhất — source có priority > threshold → meip
    $display("\n[TEST] PLIC_02: IRQ flow co ban");
    do_reset;
    // Cấu hình: source 1, priority=5, threshold=2, enable=1
    write_reg(OFF_PRIO1,     32'h5, 4'hF);   // priority[1] = 5
    write_reg(OFF_THRESHOLD, 32'h2, 4'hF);   // threshold = 2
    write_reg(OFF_ENABLE,    32'h2, 4'hF);   // enable bit[1] = 1 (source 1)
    // Trigger IRQ source 1
    trigger_irq(5'd1);
    // trigger_irq đã chờ 2 cycle nội bộ. Thêm 3 cycle để encoder propagate.
    repeat(3) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_02: meip=1 sau khi source 1 trigger");
    // Đọc pending register
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data & 32'h2, 32'h2, "PLIC_02: pending[1]=1");

    // *** PLIC_03: Claim flow ***
    // WHY: Đọc 0x204 → claim_pulse fire cùng cycle rvalid → gateway clear
    //      pending_r (T+1) → meip deassert (T+1 vì encoder combinational).
    //      Dùng wait_meip_clear để không phụ thuộc vào cycle count cố định.
    $display("\n[TEST] PLIC_03: Claim flow");
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h1, "PLIC_03: claim tra ve source ID=1");
    // Chờ meip=0 đảm bảo pending đã được clear hoàn toàn
    wait_meip_clear;
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data & 32'h2, 32'h0, "PLIC_03: pending[1]=0 sau claim");

    // *** PLIC_04: Complete flow → meip deassert ***
    // WHY: wait_meip_clear trong PLIC_03 đã đảm bảo meip=0 ở đây.
    //      Complete để giải phóng in_service, cho phép gateway nhận IRQ mới.
    $display("\n[TEST] PLIC_04: Complete flow");
    // meip đã=0 (được đảm bảo bởi wait_meip_clear ở PLIC_03)
    check_bit(meip, 1'b0, "PLIC_04: meip=0 sau claim (pending cleared)");
    // Ghi complete: giải phóng in_service
    write_reg(OFF_CLAIM, 32'h1, 4'hF);
    repeat(3) @(posedge clk);
    // Không có IRQ mới → meip vẫn 0
    check_bit(meip, 1'b0, "PLIC_04: meip=0 sau complete (khong co IRQ moi)");
    release_irq(5'd1);

    // *** PLIC_05: 2 source cùng pending, priority khác → claim trả source cao hơn ***
    // WHY: encoder phải chọn đúng source có priority lớn nhất
    $display("\n[TEST] PLIC_05: 2 source priority khac nhau");
    do_reset;
    write_reg(OFF_PRIO1,     32'h3, 4'hF);   // priority[1] = 3
    write_reg(OFF_PRIO2,     32'h6, 4'hF);   // priority[2] = 6 (cao hơn)
    write_reg(OFF_THRESHOLD, 32'h1, 4'hF);   // threshold = 1
    write_reg(OFF_ENABLE,    32'h6, 4'hF);   // enable bit[1] và bit[2]
    // Trigger cả 2 source — trigger_irq mỗi lần đã chờ 2 cycle
    trigger_irq(5'd1);
    trigger_irq(5'd2);
    repeat(3) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_05: meip=1 khi 2 source pending");
    // Claim → phải nhận source 2 (priority cao hơn)
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h2, "PLIC_05: claim tra source 2 (priority cao hon)");
    // Chờ chain: ar_claim_pending → claim_pulse_r → gateway src2 clear pending
    // Cycle+1: claim_pulse_r = 1
    // Cycle+2: gateway pending_r[2] <= 0
    // Cycle+3: pending_r stable
    repeat(5) @(posedge clk);
    // Complete source 2 — in_service[2] clear
    write_reg(OFF_CLAIM, 32'h2, 4'hF);
    // Chờ complete_pulse propagate → gateway in_service[2] clear
    // Đồng thời encoder thấy src1 vẫn pending → meip vẫn assert
    repeat(5) @(posedge clk);
    // Source 1 vẫn pending → meip vẫn assert
    check_bit(meip, 1'b1, "PLIC_05: meip=1 sau complete src2 (src1 van pending)");
    // Claim source 1 — src2 đã clear pending, encoder chỉ thấy src1
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h1, "PLIC_05: claim lan 2 tra source 1");
    // Chờ chain claim_pulse cho src1
    repeat(5) @(posedge clk);
    // Complete source 1
    write_reg(OFF_CLAIM, 32'h1, 4'hF);
    repeat(6) @(posedge clk);
    check_bit(meip, 1'b0, "PLIC_05: meip=0 sau complete src1 (het pending)");
    release_irq(5'd1);
    release_irq(5'd2);

    // *** PLIC_06: threshold mask ***
    // WHY: nếu threshold >= priority của source, meip không được assert
    //      Đây là cơ chế preemption level của PLIC
    $display("\n[TEST] PLIC_06: threshold mask");
    do_reset;
    write_reg(OFF_PRIO1,     32'h3, 4'hF);   // priority[1] = 3
    write_reg(OFF_THRESHOLD, 32'h4, 4'hF);   // threshold = 4 > priority → mask
    write_reg(OFF_ENABLE,    32'h2, 4'hF);   // enable source 1
    trigger_irq(5'd1);
    repeat(5) @(posedge clk);
    check_bit(meip, 1'b0, "PLIC_06: meip=0 khi threshold>priority (bi mask)");
    // Hạ threshold xuống thấp hơn priority → meip phải assert
    write_reg(OFF_THRESHOLD, 32'h2, 4'hF);   // threshold = 2 < priority=3
    repeat(3) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_06: meip=1 sau khi ha threshold");
    // Cleanup
    do_claim_complete(claimed);
    release_irq(5'd1);

    // *** PLIC_07: enable mask ***
    // WHY: enable[N]=0 → source N không đến được context kể cả khi pending
    $display("\n[TEST] PLIC_07: enable mask");
    do_reset;
    write_reg(OFF_PRIO1,     32'h5, 4'hF);   // priority[1] = 5
    write_reg(OFF_THRESHOLD, 32'h0, 4'hF);   // threshold = 0
    write_reg(OFF_ENABLE,    32'h0, 4'hF);   // enable = 0 → source 1 bị mask
    trigger_irq(5'd1);
    repeat(5) @(posedge clk);
    check_bit(meip, 1'b0, "PLIC_07: meip=0 khi enable[1]=0");
    // Enable source 1
    write_reg(OFF_ENABLE, 32'h2, 4'hF);
    repeat(3) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_07: meip=1 sau khi enable[1]=1");
    do_claim_complete(claimed);
    release_irq(5'd1);

    // *** PLIC_08: Đọc claim khi không có pending → trả về 0 ***
    // WHY: PLIC spec — nếu không có source đủ điều kiện, claim trả về 0
    $display("\n[TEST] PLIC_08: claim khi khong co pending");
    do_reset;
    // Không trigger IRQ nào
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h0, "PLIC_08: claim=0 khi khong co pending");

    // *** PLIC_09: Đọc pending register phản ánh gateway state ***
    // WHY: CPU cần đọc pending để biết source nào đang chờ xử lý
    $display("\n[TEST] PLIC_09: pending register");
    do_reset;
    write_reg(OFF_ENABLE,    32'hFFFFFFFE, 4'hF);  // enable source 1..31
    write_reg(OFF_PRIO1,     32'h4, 4'hF);
    write_reg(OFF_PRIO3,     32'h2, 4'hF);
    write_reg(OFF_THRESHOLD, 32'h1, 4'hF);
    trigger_irq(5'd1);
    trigger_irq(5'd3);
    repeat(3) @(posedge clk);
    read_reg(OFF_PENDING, rd_data);
    // pending[1] và pending[3] phải set
    check_eq(rd_data & 32'hA, 32'hA, "PLIC_09: pending[1] va pending[3] set");
    // Cleanup: claim và complete từng source theo thứ tự priority
    // do_claim_complete gọi wait_meip_clear — chỉ dùng khi chắc chắn
    // chỉ còn 1 source. Ở đây có 2 source nên claim thủ công.
    // Claim src1 (priority cao hơn → encoder trả về 1)
    read_reg(OFF_CLAIM, rd_data);   // claim src1
    repeat(3) @(posedge clk);       // chờ pending[1] clear
    write_reg(OFF_CLAIM, rd_data, 4'hF);  // complete src1
    repeat(3) @(posedge clk);
    // Bây giờ chỉ còn src3 → meip vẫn = 1, dùng do_claim_complete được
    do_claim_complete(claimed);   // claim + complete src3 → meip = 0
    release_irq(5'd1);
    release_irq(5'd3);

    // *** PLIC_10: Tie-break — 2 source cùng priority → source ID nhỏ thắng ***
    // WHY: encoder loop ngược từ NUM_SRC-1 xuống 1, overwrite khi
    //      prio[i] > claim_prio → source thấp hơn (loop sau) ghi đè
    //      → source ID nhỏ nhất thắng khi cùng priority
    $display("\n[TEST] PLIC_10: tie-break source ID nho hon thang");
    do_reset;
    write_reg(12'h008, 32'h5, 4'hF);  // priority[2] = 5  (offset 0x008)
    write_reg(12'h00C, 32'h5, 4'hF);  // priority[3] = 5  (offset 0x00C)
    write_reg(OFF_THRESHOLD, 32'h2, 4'hF);
    write_reg(OFF_ENABLE, 32'hE, 4'hF);   // enable 1,2,3
    trigger_irq(5'd2);
    trigger_irq(5'd3);
    repeat(5) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_10: meip=1 khi 2 source pending");
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h2, "PLIC_10: tie-break -> source 2 (ID nho hon) thang");
    write_reg(OFF_CLAIM, 32'h2, 4'hF);
    repeat(4) @(posedge clk);
    do_claim_complete(claimed);   // claim source 3
    release_irq(5'd2);
    release_irq(5'd3);

    // *** PLIC_11: Gateway in_service — IRQ mới trong khi claim chưa complete ***
    // WHY: sau claim, gateway set in_service=1. Nếu peripheral tiếp tục
    //      assert (hoặc có edge mới), gateway KHÔNG set pending mới.
    //      Chỉ sau complete mới nhận IRQ mới.
    $display("\n[TEST] PLIC_11: gateway in_service block IRQ moi");
    do_reset;
    write_reg(OFF_PRIO1,     32'h4, 4'hF);
    write_reg(OFF_THRESHOLD, 32'h1, 4'hF);
    write_reg(OFF_ENABLE,    32'h2, 4'hF);
    trigger_irq(5'd1);
    repeat(4) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_11: meip=1 truoc claim");
    // Claim (đọc 0x204) — claim_pulse fire cùng cycle rvalid
    read_reg(OFF_CLAIM, rd_data);
    check_eq(rd_data, 32'h1, "PLIC_11: claim=1");
    // Chờ meip=0: đảm bảo gateway đã xử lý claim_pulse (pending_r=0, in_service=1)
    wait_meip_clear;
    // Thả IRQ và trigger lại (edge mới) trong khi đang in_service
    release_irq(5'd1);
    @(posedge clk); #1;
    irq_src[1] = 1'b1;   // edge mới — nhưng in_service=1 → gateway block
    repeat(4) @(posedge clk);
    // Vì in_service=1, gateway KHÔNG latch pending mới
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data & 32'h2, 32'h0, "PLIC_11: pending=0 trong khi in_service");
    check_bit(meip, 1'b0, "PLIC_11: meip=0 trong khi in_service");
    // Ghi complete → in_service clear
    write_reg(OFF_CLAIM, 32'h1, 4'hF);
    // irq_src[1] vẫn HIGH nhưng không có edge MỚI sau complete
    // (irq_prev đã=1 từ trước) → irq_edge=0 → pending không set
    repeat(4) @(posedge clk);
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data & 32'h2, 32'h0, "PLIC_11: pending=0 sau complete (khong co edge moi)");
    irq_src[1] = 1'b0;

    // *** PLIC_12: Gateway sau complete — nhận IRQ mới ***
    // WHY: sau complete, in_service=0. Peripheral gửi IRQ mới (edge)
    //      → gateway phải latch pending mới
    $display("\n[TEST] PLIC_12: gateway nhan IRQ moi sau complete");
    do_reset;
    write_reg(OFF_PRIO1,     32'h4, 4'hF);
    write_reg(OFF_THRESHOLD, 32'h1, 4'hF);
    write_reg(OFF_ENABLE,    32'h2, 4'hF);
    // IRQ lần 1
    trigger_irq(5'd1);
    repeat(4) @(posedge clk);
    do_claim_complete(claimed);  // claim + complete lần 1
    // IRQ lần 2 — phải được nhận sau complete
    release_irq(5'd1);
    @(posedge clk); #1;
    trigger_irq(5'd1);    // edge mới sau complete
    repeat(4) @(posedge clk);
    check_bit(meip, 1'b1, "PLIC_12: meip=1 sau IRQ moi (post complete)");
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data & 32'h2, 32'h2, "PLIC_12: pending[1]=1 IRQ moi sau complete");
    do_claim_complete(claimed);
    release_irq(5'd1);

    // ===========================================================
    // NHÓM CORNER CASE
    // ===========================================================
    $display("\n--- NHOM CORNER CASE ---");

    // TC_EDGE_01: Ghi 0x0 và 0x7 vào priority (max value với PRIO_W=3)
    $display("\n[TEST] TC_EDGE_01: ghi 0x0 va 0x7 (max) vao priority");
    do_reset;
    write_reg(OFF_PRIO1, 32'h7, 4'hF);   // max priority
    read_reg(OFF_PRIO1, rd_data);
    check_eq(rd_data & 32'h7, 32'h7, "TC_EDGE_01: priority=7 (max, PRIO_W=3)");
    write_reg(OFF_PRIO1, 32'h0, 4'hF);   // min priority
    read_reg(OFF_PRIO1, rd_data);
    check_eq(rd_data & 32'h7, 32'h0, "TC_EDGE_01: priority=0 (min)");

    // TC_EDGE_02: Ghi 0xFFFFFFFF vào enable → đọc lại
    // WHY: với NUM_SRC=32, enable nên nhận toàn bộ 32 bit
    write_reg(OFF_ENABLE, 32'hFFFF_FFFF, 4'hF);
    read_reg(OFF_ENABLE, rd_data);
    check_eq(rd_data, 32'hFFFF_FFFF, "TC_EDGE_02: enable=0xFFFFFFFF");

    // TC_EDGE_03: Ghi 0x0 vào enable
    write_reg(OFF_ENABLE, 32'h0, 4'hF);
    read_reg(OFF_ENABLE, rd_data);
    check_eq(rd_data, 32'h0, "TC_EDGE_03: enable=0x00000000");

    // TC_EDGE_04: Pending register là RO — ghi không có tác dụng
    // WHY: pending được điều khiển bởi gateway, không phải AXI write
    $display("\n[TEST] TC_EDGE_04: pending RO - ghi khong thay doi");
    do_reset;
    write_reg(OFF_PENDING, 32'hFFFF_FFFF, 4'hF);  // ghi vào RO register
    read_reg(OFF_PENDING, rd_data);
    check_eq(rd_data, 32'h0, "TC_EDGE_04: pending RO khong thay doi khi ghi");

    // TC_EDGE_05: Source 0 luôn = 0 (reserved per PLIC spec)
    // WHY: plic_top gán pending[0]=0, priority[0] không ảnh hưởng
    $display("\n[TEST] TC_EDGE_05: source 0 reserved = 0");
    do_reset;
    write_reg(OFF_PRIO0,     32'h7, 4'hF);  // priority[0] = 7
    write_reg(OFF_ENABLE,    32'h1, 4'hF);  // enable source 0
    write_reg(OFF_THRESHOLD, 32'h0, 4'hF);
    irq_src[0] = 1'b0; @(posedge clk); #1;
    irq_src[0] = 1'b1; @(posedge clk); #1;  // "trigger" source 0
    repeat(5) @(posedge clk);
    check_bit(meip, 1'b0, "TC_EDGE_05: source 0 reserved, meip=0 du priority=7");
    irq_src[0] = 1'b0;

    // TC_EDGE_06: Back-to-back write — ghi nhiều priority liên tiếp không gap
    // WHY: kiểm tra DUT không deadlock khi AW/W channel sử dụng liên tục
    $display("\n[TEST] TC_EDGE_06: back-to-back writes");
    do_reset;
    // Ghi priority[1..7] = 1..7 (đều fit trong PRIO_W=3 bits)
    // priority[8] = 8 nhưng PRIO_W=3 → DUT lưu 8[2:0] = 0 → bỏ qua i=8
    for (i = 1; i <= 7; i = i + 1) begin
        write_reg(4*i, i, 4'hF);  // priority[i] = i (i=1..7 đều < 2^3=8)
    end
    // Read-back kiểm tra priority[1] = 1
    read_reg(12'h004, rd_data);
    check_eq(rd_data & 32'h7, 32'h1, "TC_EDGE_06: priority[1]=1 sau back-to-back");
    // Read-back priority[7] = 7 (max hợp lệ với PRIO_W=3)
    read_reg(12'h01C, rd_data);
    check_eq(rd_data & 32'h7, 32'h7, "TC_EDGE_06: priority[7]=7 sau back-to-back");
    // Ghi priority[8] với value=1 (fit 3-bit) để kiểm tra offset 0x020
    write_reg(12'h020, 32'h5, 4'hF);  // priority[8] = 5
    read_reg(12'h020, rd_data);
    check_eq(rd_data & 32'h7, 32'h5, "TC_EDGE_06: priority[8]=5 offset 0x020");

    // TC_EDGE_07: Mid-transaction reset
    // WHY: nếu reset xảy ra giữa giao dịch, DUT phải recover sạch
    $display("\n[TEST] TC_EDGE_07: reset giua transaction");
    // Bắt đầu AW channel nhưng không hoàn thành
    @(posedge clk); #1;
    awid = 4'h3; awaddr = BASE | 32'h004; awlen = 8'h0;
    awsize = 3'b010; awburst = 2'b01; awprot = 3'b0;
    awvalid = 1'b1;
    // Đợi 1 cycle rồi reset (không chờ awready)
    @(posedge clk);
    rst_n = 1'b0;           // Assert reset giữa chừng
    awvalid = 1'b0;
    repeat(5) @(posedge clk);
    rst_n = 1'b1;
    repeat(5) @(posedge clk);
    // DUT phải trở lại trạng thái bình thường
    check_bit(meip, 1'b0, "TC_EDGE_07: meip=0 sau mid-transaction reset");
    // Thực hiện giao dịch mới phải thành công
    write_reg(OFF_PRIO1, 32'h4, 4'hF);
    read_reg(OFF_PRIO1, rd_data);
    check_eq(rd_data & 32'h7, 32'h4, "TC_EDGE_07: giao dich sau reset thanh cong");

    // ===========================================================
    // SUMMARY
    // ===========================================================
    $display("\n============================================================");
    $display("=== DONE: %0d PASS, %0d FAIL ===", pass_count, fail_count);
    $display("============================================================");
    if (fail_count == 0)
        $display(">>> ALL TESTS PASSED — San sang tich hop vao soc_top.v <<<");
    else
        $display(">>> CO %0d TEST THAT BAI — Can sua truoc khi tich hop <<<", fail_count);
    $finish;
end

endmodule