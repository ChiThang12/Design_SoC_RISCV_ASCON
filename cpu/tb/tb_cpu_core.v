// ============================================================================
// Testbench Debug: tb_cpu_debug
// ============================================================================
// Muc tieu: Debug RISC-V SoC theo tung buoc:
//
//   [PHASE 1] Reset & Boot Check      - rst_n, counter = 0, PC boot address
//   [PHASE 2] Instruction Fetch Debug - ICache miss->hit pattern, AXI burst
//   [PHASE 3] Execute Monitor         - CPU khong bi stall, pipeline tien
//   [PHASE 4] DCache Read/Write       - LOAD/STORE qua DCache + AXI write-through
//
// Cach chay:
//   iverilog -o sim tb_cpu_debug.v && vvp sim
// ============================================================================

`timescale 1ns/1ps
`include "cpu/cpu_core.v"

module tb_cpu_debug;

// ============================================================================
// THAM SO
// ============================================================================
parameter CLK_PERIOD    = 10;    // 100 MHz
parameter PHASE1_CYCLES = 20;
parameter PHASE2_CYCLES = 200;
parameter PHASE3_CYCLES = 500;
parameter PHASE4_CYCLES = 500;
parameter TIMEOUT_MAX   = 5000;

// ============================================================================
// SIGNALS
// ============================================================================
reg         clk;
reg         rst_n;

wire [31:0] icache_hits;
wire [31:0] icache_misses;
wire [31:0] dcache_hits;
wire [31:0] dcache_misses;
wire [31:0] dcache_writes;

integer total_errors;
integer phase_errors;
integer snap_ifetch;
integer snap_dcache_hits;
integer snap_dcache_misses;

// Dem transaction tu monitors
integer cnt_ifetch;
integer cnt_icache_miss;
integer cnt_dcache_rd;
integer cnt_dcache_wr;

// ============================================================================
// CLOCK
// ============================================================================
initial clk = 0;
always  #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// DUT
// ============================================================================
riscv_soc_top_cached dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .icache_hits  (icache_hits),
    .icache_misses(icache_misses),
    .dcache_hits  (dcache_hits),
    .dcache_misses(dcache_misses),
    .dcache_writes(dcache_writes)
);

// ============================================================================
// WAVEFORM DUMP
// ============================================================================
initial begin
    $dumpfile("tb_cpu_debug.vcd");
    $dumpvars(0, tb_cpu_debug);
end

// ============================================================================
// WATCHDOG
// ============================================================================
initial begin
    #(CLK_PERIOD * TIMEOUT_MAX);
    $display("[WATCHDOG] TIMEOUT sau %0d cycles - simulation bi treo!", TIMEOUT_MAX);
    $finish;
end

// ============================================================================
// MONITOR 1: Instruction Fetch
// In moi khi CPU nhan duoc 1 instruction (valid && ready)
// ============================================================================
always @(posedge clk) begin
    if (rst_n && dut.cpu_imem_valid && dut.cpu_imem_ready) begin
        $display("[%0t] IFETCH  PC=0x%08h  INSTR=0x%08h  (%0s)",
            $time,
            dut.cpu_imem_addr,
            dut.cpu_imem_rdata,
            decode_instr(dut.cpu_imem_rdata));
        cnt_ifetch = cnt_ifetch + 1;
    end
end

// ============================================================================
// MONITOR 2: ICache AXI Miss -> Memory
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        if (dut.icache_arvalid && dut.icache_arready) begin
            $display("[%0t] ICACHE_MISS >> AR  addr=0x%08h  len=%0d  burst=%0d",
                $time, dut.icache_araddr, dut.icache_arlen, dut.icache_arburst);
            cnt_icache_miss = cnt_icache_miss + 1;
        end
        if (dut.icache_rvalid && dut.icache_rready) begin
            $display("[%0t] ICACHE_MISS << R   data=0x%08h  last=%0b  resp=%0d",
                $time, dut.icache_rdata, dut.icache_rlast, dut.icache_rresp);
            if (dut.icache_rresp !== 2'b00)
                $display("     [WARN] ICache RRESP=%0b bao loi! Nen la 2'b00",
                         dut.icache_rresp);
        end
    end
end

// ============================================================================
// MONITOR 3: DCache CPU Interface (LOAD / STORE)
// ============================================================================
always @(posedge clk) begin
    if (rst_n && dut.cpu_dmem_valid && dut.cpu_dmem_ready) begin
        if (dut.cpu_dmem_we) begin
            $display("[%0t] STORE   addr=0x%08h  data=0x%08h  strb=0b%04b  (%0s)",
                $time,
                dut.cpu_dmem_addr,
                dut.cpu_dmem_wdata,
                dut.cpu_dmem_wstrb,
                strb_decode(dut.cpu_dmem_wstrb));
            cnt_dcache_wr = cnt_dcache_wr + 1;
        end else begin
            $display("[%0t] LOAD    addr=0x%08h  rdata=0x%08h",
                $time,
                dut.cpu_dmem_addr,
                dut.cpu_dmem_rdata);
            cnt_dcache_rd = cnt_dcache_rd + 1;
        end
    end
end

// ============================================================================
// MONITOR 4: DCache AXI Transactions (miss refill + write-through)
// ============================================================================
always @(posedge clk) begin
    if (rst_n) begin
        // Read miss refill
        if (dut.dcache_arvalid && dut.dcache_arready)
            $display("[%0t] DCACHE  >> AR  addr=0x%08h  len=%0d",
                $time, dut.dcache_araddr, dut.dcache_arlen);
        if (dut.dcache_rvalid && dut.dcache_rready) begin
            $display("[%0t] DCACHE  << R   data=0x%08h  last=%0b",
                $time, dut.dcache_rdata, dut.dcache_rlast);
            if (dut.dcache_rresp !== 2'b00)
                $display("     [WARN] DCache RRESP=%0b bao loi!", dut.dcache_rresp);
        end
        // Write-through
        if (dut.dcache_awvalid && dut.dcache_awready)
            $display("[%0t] DCACHE  >> AW  addr=0x%08h",
                $time, dut.dcache_awaddr);
        if (dut.dcache_wvalid && dut.dcache_wready)
            $display("[%0t] DCACHE  >> W   data=0x%08h  strb=0x%01h  last=%0b",
                $time, dut.dcache_wdata, dut.dcache_wstrb, dut.dcache_wlast);
        if (dut.dcache_bvalid && dut.dcache_bready) begin
            $display("[%0t] DCACHE  << B   resp=%0d", $time, dut.dcache_bresp);
            if (dut.dcache_bresp !== 2'b00)
                $display("     [WARN] DCache BRESP=%0b bao loi!", dut.dcache_bresp);
        end
    end
end

// ============================================================================
// TASK: wait_n_cycles
// ============================================================================
task wait_n_cycles;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
    end
endtask

// ============================================================================
// TASK: print_stats
// ============================================================================
task print_stats;
    begin
        $display("  +--------------------------------------------+");
        $display("  | Cache Stats  t=%0t", $time);
        $display("  | ICache  hits=%-5d  misses=%-5d",
                 icache_hits, icache_misses);
        if ((icache_hits + icache_misses) > 0)
            $display("  | ICache  hit_rate = %0d%%",
                     (icache_hits * 100) / (icache_hits + icache_misses));
        $display("  | DCache  hits=%-5d  misses=%-5d  writes=%-5d",
                 dcache_hits, dcache_misses, dcache_writes);
        if ((dcache_hits + dcache_misses) > 0)
            $display("  | DCache  hit_rate = %0d%%",
                     (dcache_hits * 100) / (dcache_hits + dcache_misses));
        $display("  +--------------------------------------------+");
    end
endtask

// ============================================================================
// TASK: assert_true
// ============================================================================
task assert_true;
    input        cond;
    input [79:0] label;
    begin
        if (cond)
            $display("  [PASS] %0s", label);
        else begin
            $display("  [FAIL] %0s", label);
            total_errors = total_errors + 1;
            phase_errors = phase_errors + 1;
        end
    end
endtask

// ============================================================================
// FUNCTION: decode RISC-V instruction name (RV32I)
// ============================================================================
function [63:0] decode_instr;
    input [31:0] instr;
    reg [6:0] op;
    reg [2:0] f3;
    reg [6:0] f7;
    begin
        op = instr[6:0];
        f3 = instr[14:12];
        f7 = instr[31:25];
        casez (op)
            7'b0110011: begin
                case ({f7, f3})
                    10'b0000000_000: decode_instr = "ADD     ";
                    10'b0100000_000: decode_instr = "SUB     ";
                    10'b0000000_001: decode_instr = "SLL     ";
                    10'b0000000_010: decode_instr = "SLT     ";
                    10'b0000000_011: decode_instr = "SLTU    ";
                    10'b0000000_100: decode_instr = "XOR     ";
                    10'b0000000_101: decode_instr = "SRL     ";
                    10'b0100000_101: decode_instr = "SRA     ";
                    10'b0000000_110: decode_instr = "OR      ";
                    10'b0000000_111: decode_instr = "AND     ";
                    default:         decode_instr = "R-??    ";
                endcase
            end
            7'b0010011: begin
                if (instr == 32'h00000013)
                    decode_instr = "NOP     ";
                else
                    case (f3)
                        3'b000: decode_instr = "ADDI    ";
                        3'b001: decode_instr = "SLLI    ";
                        3'b010: decode_instr = "SLTI    ";
                        3'b011: decode_instr = "SLTIU   ";
                        3'b100: decode_instr = "XORI    ";
                        3'b101: decode_instr = f7[5] ? "SRAI    " : "SRLI    ";
                        3'b110: decode_instr = "ORI     ";
                        3'b111: decode_instr = "ANDI    ";
                        default: decode_instr = "I-ALU?  ";
                    endcase
            end
            7'b0000011: begin
                case (f3)
                    3'b000: decode_instr = "LB      ";
                    3'b001: decode_instr = "LH      ";
                    3'b010: decode_instr = "LW      ";
                    3'b100: decode_instr = "LBU     ";
                    3'b101: decode_instr = "LHU     ";
                    default: decode_instr = "LOAD-?  ";
                endcase
            end
            7'b0100011: begin
                case (f3)
                    3'b000: decode_instr = "SB      ";
                    3'b001: decode_instr = "SH      ";
                    3'b010: decode_instr = "SW      ";
                    default: decode_instr = "STORE-? ";
                endcase
            end
            7'b1100011: begin
                case (f3)
                    3'b000: decode_instr = "BEQ     ";
                    3'b001: decode_instr = "BNE     ";
                    3'b100: decode_instr = "BLT     ";
                    3'b101: decode_instr = "BGE     ";
                    3'b110: decode_instr = "BLTU    ";
                    3'b111: decode_instr = "BGEU    ";
                    default: decode_instr = "BR-??   ";
                endcase
            end
            7'b1101111: decode_instr = "JAL     ";
            7'b1100111: decode_instr = "JALR    ";
            7'b0110111: decode_instr = "LUI     ";
            7'b0010111: decode_instr = "AUIPC   ";
            7'b1110011: decode_instr = instr[20] ? "EBREAK  " : "ECALL   ";
            7'b0001111: decode_instr = "FENCE   ";
            7'b0000000: decode_instr = "ILLEGAL ";
            default:    decode_instr = "UNKNOWN ";
        endcase
    end
endfunction

// ============================================================================
// FUNCTION: decode write strobe
// ============================================================================
function [63:0] strb_decode;
    input [3:0] strb;
    begin
        case (strb)
            4'b0001: strb_decode = "SB[b0]  ";
            4'b0010: strb_decode = "SB[b1]  ";
            4'b0100: strb_decode = "SB[b2]  ";
            4'b1000: strb_decode = "SB[b3]  ";
            4'b0011: strb_decode = "SH[1:0] ";
            4'b1100: strb_decode = "SH[3:2] ";
            4'b1111: strb_decode = "SW[word]";
            default: strb_decode = "STRB-?? ";
        endcase
    end
endfunction

// ============================================================================
// MAIN TEST SEQUENCE
// ============================================================================
initial begin
    // Khoi tao tat ca
    total_errors     = 0;
    phase_errors     = 0;
    cnt_ifetch       = 0;
    cnt_icache_miss  = 0;
    cnt_dcache_rd    = 0;
    cnt_dcache_wr    = 0;
    snap_ifetch      = 0;
    snap_dcache_hits = 0;
    snap_dcache_misses = 0;
    rst_n            = 0;

    $display("");
    $display("=======================================================");
    $display("   RISC-V SoC Debug Testbench  -  Step by Step        ");
    $display("=======================================================");
    $display("   CLK: %0d MHz   |   DUT: riscv_soc_top_cached", 1000/CLK_PERIOD);
    $display("   ICache: 4KB direct-mapped");
    $display("   DCache: 8KB write-through direct-mapped");
    $display("   AXI4 Full memory interface");
    $display("");

    // =========================================================================
    // PHASE 1: RESET CHECK
    // =========================================================================
    $display("-------------------------------------------------------");
    $display(" PHASE 1: Reset & Boot Check");
    $display("-------------------------------------------------------");
    $display(" >> Giu rst_n=0 trong %0d cycles...", PHASE1_CYCLES/2);

    phase_errors = 0;
    wait_n_cycles(PHASE1_CYCLES / 2);

    // Check khi dang reset
    $display(" >> Kiem tra trang thai khi rst_n=0:");
    assert_true(icache_hits   == 0, "icache_hits   = 0 khi reset    ");
    assert_true(icache_misses == 0, "icache_misses = 0 khi reset    ");
    assert_true(dcache_hits   == 0, "dcache_hits   = 0 khi reset    ");
    assert_true(dcache_misses == 0, "dcache_misses = 0 khi reset    ");
    assert_true(dcache_writes == 0, "dcache_writes = 0 khi reset    ");
    assert_true(dut.cpu_imem_valid == 1'b0,
                "cpu_imem_valid = 0 (no fetch during reset)  ");
    assert_true(dut.cpu_dmem_valid == 1'b0,
                "cpu_dmem_valid = 0 (no dmem during reset)   ");

    // De-assert reset
    $display(" >> De-assert rst_n=1, doi CPU boot...");
    @(posedge clk);
    rst_n = 1;
    #1; // settle sau rising edge

    // Doi toi da 10 cycle de CPU bat dau fetch
    begin : blk_wait_boot
        integer i;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            if (cnt_ifetch > 0 || cnt_icache_miss > 0) begin
                i = 10; // thoat som
            end
        end
    end

    $display(" >> Kiem tra sau reset:");
    assert_true(cnt_ifetch > 0 || cnt_icache_miss > 0,
                "CPU bat dau fetch sau reset           ");
    assert_true(dut.cpu_imem_addr < 32'h00001000,
                "PC boot tu vung thap (< 0x1000)       ");

    $display(" PHASE 1 DONE - errors=%0d", phase_errors);

    // =========================================================================
    // PHASE 2: INSTRUCTION FETCH & ICACHE DEBUG
    // =========================================================================
    $display("");
    $display("-------------------------------------------------------");
    $display(" PHASE 2: Instruction Fetch & ICache Debug");
    $display("-------------------------------------------------------");
    $display(" >> Log IFETCH = CPU nhan instruction (imem valid+ready)");
    $display(" >> Log ICACHE_MISS = cache miss, AXI AR burst toi memory");
    $display(" >> Moi cache miss nen fetch 4 words (len=3 tuc 4 beats)");
    $display(" >> Sau 1 miss: 3 fetch tiep theo phai la HIT");
    $display(" >> Quan sat %0d cycles...", PHASE2_CYCLES);
    $display("");

    phase_errors = 0;
    snap_ifetch  = cnt_ifetch;

    wait_n_cycles(PHASE2_CYCLES);

    $display("");
    $display(" >> Tong ket PHASE 2:");
    $display("    IFetch total:  %0d  (+%0d trong phase nay)",
             cnt_ifetch, cnt_ifetch - snap_ifetch);
    $display("    ICache AR req: %0d", cnt_icache_miss);
    print_stats();

    assert_true((cnt_ifetch - snap_ifetch) > 20,
                "CPU fetch > 20 instrs trong phase 2         ");
    assert_true((icache_hits + icache_misses) > 0,
                "ICache counter dang tang                     ");
    assert_true(icache_hits >= icache_misses,
                "ICache hit rate >= 50%                       ");

    if (dut.cpu_imem_rdata == 32'h00000013 ||
        dut.cpu_imem_rdata == 32'h00000000) begin
        $display(" [WARN] Lenh dang la NOP/ZERO = 0x%08h",
                 dut.cpu_imem_rdata);
        $display("        -> inst_mem co the chua co chuong trinh thuc te!");
        $display("        -> Them $readmemh() trong inst_mem_axi_slave.");
    end else begin
        $display(" [INFO] Lenh hien tai: 0x%08h  = %0s",
                 dut.cpu_imem_rdata, decode_instr(dut.cpu_imem_rdata));
    end

    $display(" PHASE 2 DONE - errors=%0d", phase_errors);

    // =========================================================================
    // PHASE 3: EXECUTE MONITOR
    // =========================================================================
    $display("");
    $display("-------------------------------------------------------");
    $display(" PHASE 3: Execute Monitor (Pipeline khong bi stall)");
    $display("-------------------------------------------------------");
    $display(" >> Kiem tra CPU lien tuc fetch - khong dung giua chung.");
    $display(" >> Quan sat %0d cycles...", PHASE3_CYCLES);
    $display("");

    phase_errors = 0;
    snap_ifetch  = cnt_ifetch;

    wait_n_cycles(PHASE3_CYCLES);

    $display("");
    $display(" >> Tong ket PHASE 3:");
    $display("    Them %0d IFetch trong %0d cycles",
             cnt_ifetch - snap_ifetch, PHASE3_CYCLES);

    if (PHASE3_CYCLES > 0)
        $display("    IPC ~= %0d/1000 (ly tuong = 1000 voi pipeline day)",
                 ((cnt_ifetch - snap_ifetch) * 1000) / PHASE3_CYCLES);

    assert_true((cnt_ifetch - snap_ifetch) > (PHASE3_CYCLES / 5),
                "CPU fetch > 20% so cycles (khong stall dai)  ");
    assert_true(icache_hits > 100,
                "ICache co nhieu hit (pipeline on dinh)        ");

    if (dut.icache_arvalid && !dut.icache_arready)
        $display(" [WARN] ICache AR bi block: arvalid=1 arready=0 tai t=%0t", $time);

    $display(" PHASE 3 DONE - errors=%0d", phase_errors);

    // =========================================================================
    // PHASE 4: DCACHE READ / WRITE
    // =========================================================================
    $display("");
    $display("-------------------------------------------------------");
    $display(" PHASE 4: DCache Load/Store Debug");
    $display("-------------------------------------------------------");
    $display(" >> Log LOAD/STORE = CPU truy cap data memory");
    $display(" >> Log DCACHE >> AR/R = cache miss refill tu memory");
    $display(" >> Log DCACHE >> AW/W/<< B = write-through len memory");
    $display(" >> DCache la write-through: moi STORE phai co AW+W+B");
    $display(" >> Quan sat %0d cycles...", PHASE4_CYCLES);
    $display("");

    phase_errors       = 0;
    snap_dcache_hits   = dcache_hits;
    snap_dcache_misses = dcache_misses;

    wait_n_cycles(PHASE4_CYCLES);

    $display("");
    $display(" >> Tong ket PHASE 4:");
    $display("    LOAD  transactions: %0d", cnt_dcache_rd);
    $display("    STORE transactions: %0d", cnt_dcache_wr);
    print_stats();

    if (cnt_dcache_rd == 0 && cnt_dcache_wr == 0) begin
        $display(" [INFO] Chua co DCache activity trong toan bo simulation.");
        $display("        Nguyen nhan co the:");
        $display("        1. inst_mem chi chua NOP -> CPU chua den lenh LOAD/STORE");
        $display("        2. cpu_dmem_valid = 0 do pipeline chua toi lenh mem");
        $display("        3. DCache ready = 0 khien CPU bi stall vo han");
        $display("");
        $display(" [GUY Y] Nap chuong trinh test vao inst_mem voi:");
        $display("   lui  t0, 0xDEAD          # t0 = 0xDEAD0000");
        $display("   addi t0, t0, 0x123       # t0 = 0xDEAD0123 (gia tri test)");
        $display("   li   t1, 0               # t1 = 0 (dia chi MEM)");
        $display("   sw   t0, 0(t1)           # STORE: MEM[0] = t0 (test write-through)");
        $display("   lw   t2, 0(t1)           # LOAD:  t2 = MEM[0] (test read hit)");
        $display("   addi t1, t1, 64          # t1 = 64 (dia chi cache line khac)");
        $display("   lw   t3, 0(t1)           # LOAD:  t3 = MEM[64] (test read miss)");
    end else begin
        if (cnt_dcache_wr > 0) begin
            $display(" >> Kiem tra Write-Through:");
            assert_true(dcache_writes > 0,
                        "stat_writes tang khi co STORE         ");
            $display("    -> Moi STORE phai co: AW -> W -> B tren AXI");
            $display("    -> Dem writes theo AXI: xem log DCACHE >> AW phia tren");
        end

        if (cnt_dcache_rd > 0) begin
            $display(" >> Kiem tra Read:");
            if (dcache_misses > snap_dcache_misses)
                $display("    -> Co DCache miss -> AR -> R burst: OK");
            else
                $display("    -> Toan bo LOAD la HIT (cacheline da warm)");

            assert_true(
                (dcache_hits + dcache_misses) == $unsigned(cnt_dcache_rd),
                "stat: hit + miss == total reads         ");
        end
    end

    $display(" PHASE 4 DONE - errors=%0d", phase_errors);

    // =========================================================================
    // TONG KET
    // =========================================================================
    $display("");
    $display("=======================================================");
    $display(" TONG KET CUOI");
    $display("=======================================================");
    $display("   IFetch total         : %0d instructions", cnt_ifetch);
    $display("   ICache AXI miss (AR) : %0d burst requests", cnt_icache_miss);
    $display("   DCache LOAD          : %0d", cnt_dcache_rd);
    $display("   DCache STORE         : %0d", cnt_dcache_wr);
    $display("");
    print_stats();
    $display("");

    if (total_errors == 0)
        $display("   KET QUA: >> TAT CA PASS << Khong co loi nao.");
    else
        $display("   KET QUA: >> %0d LOI << Xem chi tiet tung PHASE o tren.",
                 total_errors);

    $display("=======================================================");
    $display("   Ket thuc tai t=%0t", $time);
    $display("=======================================================");

    #(CLK_PERIOD * 2);
    $finish;
end

endmodule