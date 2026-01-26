// ============================================================================
// Testbench: tb_icache_axi_interface (AXI4 Full)
// ============================================================================
// Description:
//   Test AXI4 interface with burst support and simulated memory
// ============================================================================

`timescale 1ns/1ps
`include "icache_axi_interface.v"
module tb_icache_axi_interface;

    // Clock and Reset
    reg clk;
    reg rst_n;
    
    // Control Interface
    reg [31:0] refill_addr;
    reg        refill_start;
    wire       refill_busy;
    wire       refill_done;
    
    // Data Output
    wire [31:0] refill_data;
    wire [1:0]  refill_word;
    wire        refill_data_valid;
    
    // AXI4 Master
    wire [31:0] M_AXI_ARADDR;
    wire [7:0]  M_AXI_ARLEN;
    wire [2:0]  M_AXI_ARSIZE;
    wire [1:0]  M_AXI_ARBURST;
    wire [2:0]  M_AXI_ARPROT;
    wire        M_AXI_ARVALID;
    reg         M_AXI_ARREADY;
    
    reg  [31:0] M_AXI_RDATA;
    reg  [1:0]  M_AXI_RRESP;
    reg         M_AXI_RLAST;
    reg         M_AXI_RVALID;
    wire        M_AXI_RREADY;
    
    // ========================================================================
    // DUT Instance
    // ========================================================================
    icache_axi_interface dut (
        .clk(clk),
        .rst_n(rst_n),
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARPROT(M_AXI_ARPROT),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );
    
    // ========================================================================
    // Simulated Memory
    // ========================================================================
    reg [31:0] memory [0:1023];
     integer i;
    initial begin
       
        for (i = 0; i < 1024; i = i + 1) begin
            memory[i] = 32'hA000_0000 + i;
        end
    end
    
    // ========================================================================
    // Clock Generation (100MHz)
    // ========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // ========================================================================
    // AXI4 Slave Model (with Burst Support)
    // ========================================================================
    reg [31:0] ar_addr_latched;
    reg [7:0]  ar_len_latched;
    reg [2:0]  beat_counter;
    reg [1:0]  axi_state;
    
    localparam AXI_IDLE = 2'b00;
    localparam AXI_AR   = 2'b01;
    localparam AXI_R    = 2'b10;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_ARREADY   <= 1'b0;
            M_AXI_RVALID    <= 1'b0;
            M_AXI_RDATA     <= 32'h0;
            M_AXI_RRESP     <= 2'b00;
            M_AXI_RLAST     <= 1'b0;
            ar_addr_latched <= 32'h0;
            ar_len_latched  <= 8'h0;
            beat_counter    <= 0;
            axi_state       <= AXI_IDLE;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    M_AXI_ARREADY <= 1'b0;
                    M_AXI_RVALID  <= 1'b0;
                    M_AXI_RLAST   <= 1'b0;
                    
                    if (M_AXI_ARVALID) begin
                        M_AXI_ARREADY <= 1'b1;
                        axi_state     <= AXI_AR;
                    end
                end
                
                AXI_AR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        // Latch address and burst info
                        ar_addr_latched <= M_AXI_ARADDR;
                        ar_len_latched  <= M_AXI_ARLEN;
                        beat_counter    <= 0;
                        M_AXI_ARREADY   <= 1'b0;
                        axi_state       <= AXI_R;
                    end
                end
                
                AXI_R: begin
                    // Provide data
                    M_AXI_RVALID <= 1'b1;
                    M_AXI_RDATA  <= memory[(ar_addr_latched[11:2] + beat_counter)];
                    M_AXI_RRESP  <= 2'b00; // OKAY
                    
                    // Check if last beat
                    if (beat_counter == ar_len_latched) begin
                        M_AXI_RLAST <= 1'b1;
                    end else begin
                        M_AXI_RLAST <= 1'b0;
                    end
                    
                    // Wait for ready
                    if (M_AXI_RREADY && M_AXI_RVALID) begin
                        if (M_AXI_RLAST) begin
                            // Burst complete
                            M_AXI_RVALID <= 1'b0;
                            M_AXI_RLAST  <= 1'b0;
                            axi_state    <= AXI_IDLE;
                        end else begin
                            // Continue burst
                            beat_counter <= beat_counter + 1;
                        end
                    end
                end
                
                default: axi_state <= AXI_IDLE;
            endcase
        end
    end
    
    // ========================================================================
    // Test Stimulus
    // ========================================================================
    integer word_count;
    reg [31:0] received_words [0:3];
    integer start_time, end_time, cycles;
    initial begin
        $display("========================================");
        $display("Starting AXI4 Interface Testbench");
        $display("========================================");
        
        // Initialize signals
        rst_n = 0;
        refill_addr = 0;
        refill_start = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // ====================================================================
        // TEST 1: Single burst refill (4 beats)
        // ====================================================================
        $display("\n[TEST 1] Single AXI4 burst from address 0x00000100");
        refill_addr = 32'h0000_0100;
        refill_start = 1;
        #10;
        refill_start = 0;
        
        // Wait for busy
        wait(refill_busy);
        $display("  Refill started, busy asserted");
        
        // Collect data
        word_count = 0;
        while (!refill_done) begin
            @(posedge clk);
            if (refill_data_valid) begin
                received_words[word_count] = refill_data;
                $display("  Word %0d: 0x%08h", refill_word, refill_data);
                word_count = word_count + 1;
            end
        end
        
        // Verify
        if (word_count != 4) begin
            $display("  [FAIL] Expected 4 words, got %0d", word_count);
            $finish;
        end
        
        if (received_words[0] !== 32'hA000_0040) begin
            $display("  [FAIL] Word 0: Expected 0xA0000040, got 0x%08h", 
                     received_words[0]);
            $finish;
        end
        
        $display("  [PASS] Burst completed successfully");
        #50;
        
        // ====================================================================
        // TEST 2: Verify AXI4 signals
        // ====================================================================
        $display("\n[TEST 2] Verify AXI4 burst signals");
        refill_addr = 32'h0000_0200;
        refill_start = 1;
        #10;
        refill_start = 0;
        
        wait(M_AXI_ARVALID);
        @(posedge clk);
        
        if (M_AXI_ARLEN !== 8'd3) begin
            $display("  [FAIL] ARLEN should be 3 (4 beats), got %0d", M_AXI_ARLEN);
            $finish;
        end
        
        if (M_AXI_ARSIZE !== 3'b010) begin
            $display("  [FAIL] ARSIZE should be 3'b010 (4 bytes)");
            $finish;
        end
        
        if (M_AXI_ARBURST !== 2'b01) begin
            $display("  [FAIL] ARBURST should be 2'b01 (INCR)");
            $finish;
        end
        
        $display("  [PASS] AXI4 burst parameters correct");
        $display("    ARLEN   = %0d (4 beats)", M_AXI_ARLEN);
        $display("    ARSIZE  = 0x%01h (4 bytes)", M_AXI_ARSIZE);
        $display("    ARBURST = 0x%01h (INCR)", M_AXI_ARBURST);
        
        wait(refill_done);
        #50;
        
        // ====================================================================
        // TEST 3: Back-to-back bursts
        // ====================================================================
        $display("\n[TEST 3] Back-to-back burst transfers");
        
        // First burst
        refill_addr = 32'h0000_0300;
        refill_start = 1;
        #10;
        refill_start = 0;
        wait(refill_done);
        $display("  First burst done");
        #20;
        
        // Second burst immediately
        refill_addr = 32'h0000_0400;
        refill_start = 1;
        #10;
        refill_start = 0;
        wait(refill_done);
        $display("  Second burst done");
        $display("  [PASS] Back-to-back bursts successful");
        #50;
        
        // ====================================================================
        // TEST 4: RLAST signal verification
        // ====================================================================
        $display("\n[TEST 4] Verify RLAST signal on last beat");
        refill_addr = 32'h0000_0500;
        refill_start = 1;
        #10;
        refill_start = 0;
        
        word_count = 0;
        while (!refill_done) begin
            @(posedge clk);
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                word_count = word_count + 1;
                if (word_count == 4) begin
                    if (!M_AXI_RLAST) begin
                        $display("  [FAIL] RLAST should be asserted on last beat");
                        $finish;
                    end
                end else begin
                    if (M_AXI_RLAST) begin
                        $display("  [FAIL] RLAST asserted too early (beat %0d)", word_count);
                        $finish;
                    end
                end
            end
        end
        $display("  [PASS] RLAST correctly indicates last beat");
        #50;
        
        // ====================================================================
        // TEST 5: Different addresses
        // ====================================================================
        $display("\n[TEST 5] Test different addresses");
        refill_addr = 32'h0000_0000;
        refill_start = 1;
        #10;
        refill_start = 0;
        wait(refill_done);
        $display("  Address 0x00000000 - Done");
        #20;
        
        refill_addr = 32'h0000_0FC0;
        refill_start = 1;
        #10;
        refill_start = 0;
        wait(refill_done);
        $display("  Address 0x00000FC0 - Done");
        $display("  [PASS] Different addresses work correctly");
        #50;
        
        // ====================================================================
        // TEST 6: Burst efficiency measurement
        // ====================================================================
        $display("\n[TEST 6] Measure burst efficiency");
        
        
        start_time = $time;
        refill_addr = 32'h0000_0600;
        refill_start = 1;
        #10;
        refill_start = 0;
        wait(refill_done);
        end_time = $time;
        
        cycles = (end_time - start_time) / 10; // 10ns clock period
        $display("  Burst transfer took %0d cycles", cycles);
        
        if (cycles < 10) begin
            $display("  [PASS] Efficient burst transfer (< 10 cycles)");
        end else begin
            $display("  [WARN] Burst took longer than expected");
        end
        
        // ====================================================================
        // Test Complete
        // ====================================================================
        #100;
        $display("\n========================================");
        $display("All AXI4 Interface Tests PASSED!");
        $display("========================================");
        $display("Performance Summary:");
        $display("  - Single AR transaction per 4-word line");
        $display("  - Burst length: 4 beats (ARLEN=3)");
        $display("  - Transfer time: ~%0d cycles", cycles);
        $display("========================================");
        $finish;
    end
    
    // ========================================================================
    // Monitor AXI transactions
    // ========================================================================
    always @(posedge clk) begin
        if (M_AXI_ARVALID && M_AXI_ARREADY) begin
            $display("  [AXI AR] Addr: 0x%08h, Len: %0d, Size: %0d, Burst: %0d", 
                     M_AXI_ARADDR, M_AXI_ARLEN, M_AXI_ARSIZE, M_AXI_ARBURST);
        end
        if (M_AXI_RVALID && M_AXI_RREADY) begin
            $display("  [AXI R]  Data: 0x%08h%s", 
                     M_AXI_RDATA, M_AXI_RLAST ? " [LAST]" : "");
        end
    end
    
    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("tb_icache_axi_interface.vcd");
        $dumpvars(0, tb_icache_axi_interface);
    end
    
    // ========================================================================
    // Timeout
    // ========================================================================
    initial begin
        #100000;
        $display("\n[ERROR] Test timeout!");
        $finish;
    end

endmodule