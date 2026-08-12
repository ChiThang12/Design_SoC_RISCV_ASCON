`timescale 1ns/1ps

module tb_axis_uart_bridge;
    localparam CLK_PERIOD = 10;
    localparam BAUD_DIV   = 16;

    reg clk;
    reg rst_n;

    reg  [7:0] s_axis_tdata;
    reg        s_axis_tkeep;
    reg        s_axis_tvalid;
    reg        s_axis_tlast;
    wire       s_axis_tready;

    wire [7:0] m_axis_tdata;
    wire       m_axis_tkeep;
    wire       m_axis_tvalid;
    wire       m_axis_tlast;
    reg        m_axis_tready;

    wire host_uart_to_soc;
    reg  soc_uart_to_host;

    integer received_count;
    reg [8*64-1:0] received_text;

    axis_uart_bridge #(
        .BAUD_DIV(BAUD_DIV)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tkeep    (s_axis_tkeep),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tlast    (s_axis_tlast),
        .s_axis_tready   (s_axis_tready),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tkeep    (m_axis_tkeep),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tlast    (m_axis_tlast),
        .m_axis_tready   (m_axis_tready),
        .uart_tx_to_soc  (host_uart_to_soc),
        .uart_rx_from_soc(soc_uart_to_host)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        s_axis_tdata = 8'h00;
        s_axis_tkeep = 1'b1;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b1;
        soc_uart_to_host = 1'b1;
        received_count = 0;
        received_text = {8*64{1'b0}};

        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        fork
            begin
                axis_send_string("status\n");
                axis_send_string("read 0x50000000\n");
                axis_send_string("monitor on\n");
            end
            begin
                repeat (900) @(posedge clk);
                uart_send_soc_byte("[");
                uart_send_soc_byte("O");
                uart_send_soc_byte("K");
                uart_send_soc_byte("]");
                uart_send_soc_byte(" ");
                uart_send_soc_byte("m");
                uart_send_soc_byte("o");
                uart_send_soc_byte("n");
                uart_send_soc_byte("\n");
            end
        join

        repeat (2000) @(posedge clk);

        if (received_count >= 9) begin
            $display("[PASS] axis_uart_bridge notebook stream test");
            $finish;
        end else begin
            $display("[FAIL] expected notebook RX bytes, got %0d", received_count);
            $finish;
        end
    end

    task axis_send_byte;
        input [7:0] b;
    begin
        @(posedge clk);
        s_axis_tdata <= b;
        s_axis_tkeep <= 1'b1;
        s_axis_tvalid <= 1'b1;
        s_axis_tlast <= 1'b1;
        while (!s_axis_tready) @(posedge clk);
        @(posedge clk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
    end
    endtask

    task axis_send_string;
        input [8*64-1:0] str;
        integer i;
        reg [7:0] ch;
    begin
        for (i = 63; i >= 0; i = i - 1) begin
            ch = str[i*8 +: 8];
            if (ch != 8'h00)
                axis_send_byte(ch);
        end
    end
    endtask

    task uart_send_soc_byte;
        input [7:0] b;
        integer i;
    begin
        soc_uart_to_host <= 1'b0;
        repeat (BAUD_DIV) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            soc_uart_to_host <= b[i];
            repeat (BAUD_DIV) @(posedge clk);
        end
        soc_uart_to_host <= 1'b1;
        repeat (BAUD_DIV) @(posedge clk);
    end
    endtask

    always @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready && m_axis_tkeep) begin
            received_text <= {received_text[8*63-1:0], m_axis_tdata};
            received_count <= received_count + 1;
            $write("%c", m_axis_tdata);
        end
    end
endmodule
