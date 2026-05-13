`timescale 1ns/1ps

module reg_file (
    // --- Clock & Reset ---
    input  wire        clock,
    input  wire        reset,

    // --- Read ports (asynchronous, combinational) ---
    input  wire [4:0]  read_reg_num1,      // rs1
    input  wire [4:0]  read_reg_num2,      // rs2
    output wire [31:0] read_data1,         // data from rs1
    output wire [31:0] read_data2,         // data from rs2

    // --- Write port (synchronous — negedge clock) ---
    input  wire        regwrite,           // write enable
    input  wire [4:0]  write_reg,          // rd
    input  wire [31:0] write_data          // data to write to rd
);

    // 32 registers, each 32-bit
    reg [31:0] registers [31:0];

    integer i;

    // ========================================================================
    // WRITE at NEGEDGE clock
    // ========================================================================
    // WHY negedge: WB stage computes write_data by posedge. At negedge
    // (half cycle later), write_data is stable and written into the register
    // array. The NEXT posedge, any ID stage read sees the updated value
    // without needing a forwarding MUX bypass.
    //
    // This eliminates the internal forwarding path that was:
    //   (regwrite && write_reg == read_reg) ? write_data : registers[addr]
    // which added a 5-bit comparator + 32-bit 2:1 MUX to the read path.
    // ========================================================================
    always @(negedge clock or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'h00000000;
        end else begin
            if (regwrite && (write_reg != 5'b00000))
                registers[write_reg] <= write_data;
            registers[0] <= 32'h00000000;  // x0 always zero
        end
    end

    // ========================================================================
    // READ: Pure combinational (no forwarding MUX)
    // ========================================================================
    assign read_data1 = (read_reg_num1 == 5'b00000) ? 32'h00000000
                                                     : registers[read_reg_num1];

    assign read_data2 = (read_reg_num2 == 5'b00000) ? 32'h00000000
                                                     : registers[read_reg_num2];

endmodule