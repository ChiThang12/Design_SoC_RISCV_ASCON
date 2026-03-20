// Simple debug testbench for prefetch issue
`timescale 1ns/1ps
`include "cpu/interface/icache/tb/icache_controller.v"
module tb_debug_prefetch;

    reg clk, rst_n;
    reg [31:0] cpu_addr;
    reg cpu_req;
    wire [31:0] cpu_rdata;
    wire cpu_ready;
    
    // Internal signals
    wire [31:0] refill_addr;
    wire refill_start;
    reg refill_busy;
    reg refill_done;
    reg [31:0] refill_data;
    reg [1:0] refill_word;
    reg refill_data_valid;
    
    // Dummy signals
    wire [5:0] tag_lookup_index;
    wire [21:0] tag_lookup_tag;
    wire tag_update_valid;
    wire [5:0] tag_update_index;
    wire [21:0] tag_update_tag;
    wire tag_flush_all;
    wire [5:0] data_read_index;
    wire [1:0] data_read_offset;
    wire data_write_enable;
    wire [5:0] data_write_index;
    wire [1:0] data_write_offset;
    wire [31:0] data_write_data;
    wire [31:0] stat_hits, stat_misses;
    
    // DUT
    icache_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .flush(1'b0),
        
        .tag_lookup_index(tag_lookup_index),
        .tag_lookup_tag(tag_lookup_tag),
        .tag_hit(1'b0),
        .tag_update_valid(tag_update_valid),
        .tag_update_index(tag_update_index),
        .tag_update_tag(tag_update_tag),
        .tag_flush_all(tag_flush_all),
        
        .data_read_index(data_read_index),
        .data_read_offset(data_read_offset),
        .data_read_data(32'h0),
        .data_write_enable(data_write_enable),
        .data_write_index(data_write_index),
        .data_write_offset(data_write_offset),
        .data_write_data(data_write_data),
        
        .refill_addr(refill_addr),
        .refill_start(refill_start),
        .refill_busy(refill_busy),
        .refill_done(refill_done),
        .refill_data(refill_data),
        .refill_word(refill_word),
        .refill_data_valid(refill_data_valid),
        
        .stat_hits(stat_hits),
        .stat_misses(stat_misses)
    );
    
    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Memory model
    reg [31:0] memory [0:255];
    reg [2:0] refill_state;
    reg [1:0] refill_counter;
    reg [31:0] refill_base;
    integer i;
    initial begin
        
        for (i = 0; i < 256; i = i + 1)
            memory[i] = 32'hDEAD0000 + i;
    end
    
    // FAST PIPELINED MEMORY MODEL
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refill_busy <= 0;
            refill_done <= 0;
            refill_data <= 0;
            refill_word <= 0;
            refill_data_valid <= 0;
            refill_state <= 0;
            refill_counter <= 0;
        end else begin
            refill_done <= 0;
            refill_data_valid <= 0;
            
            case (refill_state)
                0: begin
                    if (refill_start) begin
                        refill_busy <= 1;
                        refill_base <= refill_addr;
                        refill_counter <= 0;
                        refill_state <= 1;
                        $display("    [MEM] FAST Refill start: addr=0x%08x", refill_addr);
                        
                        // FAST: Start burst immediately, send word 0 next cycle
                    end
                end
                
                1: begin  // Burst data - one word per cycle
                    refill_data <= memory[refill_base[11:2] + refill_counter];
                    refill_word <= refill_counter;
                    refill_data_valid <= 1;
                    $display("    [MEM] Transfer word %0d: data=0x%08x", refill_counter, memory[refill_base[11:2] + refill_counter]);
                    
                    if (refill_counter == 3)
                        refill_state <= 2;
                    else
                        refill_counter <= refill_counter + 1;
                end
                
                2: begin  // Done
                    refill_done <= 1;
                    refill_busy <= 0;
                    refill_state <= 0;
                    $display("    [MEM] Refill complete - 4 cycles total");
                end
            endcase
        end
    end
    
    // Test
    integer cycle;
    initial begin
        $display("========================================");
        $display("Debug Prefetch Issue");
        $display("========================================\n");
        
        rst_n = 0;
        cpu_req = 0;
        cpu_addr = 32'h00000000;
        cycle = 0;
        
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        
        $display("Starting sequential fetch from 0x0000...\n");
        cpu_req = 1;
        
        repeat(25) begin
            @(negedge clk);  // Check at negedge for current cycle
            cycle = cycle + 1;
            
            $display("[Cycle %2d] PC=0x%04x | State=%0d | Ready=%b | Hit=%b | FillBusy=%b | Should_Pfetch=%b | RefillBusy=%b", 
                     cycle, cpu_addr, dut.state, cpu_ready, dut.cache_hit, 
                     dut.fill_busy, dut.should_prefetch, refill_busy);
            
            $display("           Line0: valid=%b tag=0x%05x idx=%02d | Line1: valid=%b tag=0x%05x idx=%02d",
                     dut.line_valid[0], dut.line_tag[0], dut.line_index[0],
                     dut.line_valid[1], dut.line_tag[1], dut.line_index[1]);
            
            @(posedge clk);
            
            if (cpu_ready) begin
                $display("           → FETCH: data=0x%08x\n", cpu_rdata);
                cpu_addr = cpu_addr + 4;
            end else begin
                $display("           → STALL\n");
            end
            
            // if (cpu_addr >= 32'h00000020) break;
        end
        
        $display("\n========================================");
        $display("Final Stats:");
        $display("  Hits:   %0d", stat_hits);
        $display("  Misses: %0d", stat_misses);
        $display("========================================");
        
        #100;
        $finish;
    end
    initial begin
        $dumpfile("tb_debug_prefetch.vcd");
        $dumpvars(0, tb_debug_prefetch);
    end
    initial begin
        #5000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule