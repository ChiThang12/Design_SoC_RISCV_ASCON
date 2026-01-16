module data_mem(
    input             clock,
    input      [31:0] address,
    input      [31:0] write_data,
    input             memwrite,
    input             memread,
    input      [1:0]  byte_size,
    input             sign_ext,
    output reg [31:0] read_data
);

    // ============================================================
    // Word-addressed memory (32-bit wide)
    // ============================================================
    reg [31:0] mem [0:256-1];

    wire [7:0] word_addr;
    assign word_addr = address[9:2]; // word aligned

    wire [1:0] byte_offset;
    assign byte_offset = address[1:0];

    // ============================================================
    // WRITE (SYNC)
    // ============================================================
    always @(posedge clock) begin
        if (memwrite) begin
            case (byte_size)
                2'b00: begin // SB
                    mem[word_addr][byte_offset*8 +: 8] <= write_data[7:0];
                end

                2'b01: begin // SH
                    mem[word_addr][byte_offset*8 +: 16] <= write_data[15:0];
                end

                2'b10: begin // SW
                    mem[word_addr] <= write_data;
                end
            endcase
        end
    end

    // ============================================================
    // READ (SYNC ? BRAM STYLE)
    // ============================================================
    reg [31:0] read_word;

    always @(posedge clock) begin
        if (memread)
            read_word <= mem[word_addr];
    end

    // ============================================================
    // EXTENSION LOGIC (COMBINATIONAL)
    // ============================================================
    always @(*) begin
        case (byte_size)
            2'b00: begin // LB/LBU
                if (sign_ext)
                    read_data = {{24{read_word[byte_offset*8 + 7]}},
                                  read_word[byte_offset*8 +: 8]};
                else
                    read_data = {24'b0,
                                  read_word[byte_offset*8 +: 8]};
            end

            2'b01: begin // LH/LHU
                if (sign_ext)
                    read_data = {{16{read_word[byte_offset*8 + 15]}},
                                  read_word[byte_offset*8 +: 16]};
                else
                    read_data = {16'b0,
                                  read_word[byte_offset*8 +: 16]};
            end

            default: begin // LW
                read_data = read_word;
            end
        endcase
    end

endmodule
