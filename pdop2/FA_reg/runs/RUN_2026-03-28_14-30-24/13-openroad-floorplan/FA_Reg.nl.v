module FA_Reg (a,
    b,
    cin,
    clk,
    cout,
    rst_n,
    sum);
 input a;
 input b;
 input cin;
 input clk;
 output cout;
 input rst_n;
 output sum;

 wire _0_;
 wire _1_;
 wire _2_;
 wire cout_comb;
 wire sum_comb;

 sky130_fd_sc_hd__inv_2 _3_ (.A(cin),
    .Y(_0_));
 sky130_fd_sc_hd__nand2_2 _4_ (.A(b),
    .B(a),
    .Y(_1_));
 sky130_fd_sc_hd__xnor2_2 _5_ (.A(b),
    .B(a),
    .Y(_2_));
 sky130_fd_sc_hd__o21ai_2 _6_ (.A1(_0_),
    .A2(_2_),
    .B1(_1_),
    .Y(cout_comb));
 sky130_fd_sc_hd__xnor2_2 _7_ (.A(cin),
    .B(_2_),
    .Y(sum_comb));
 sky130_fd_sc_hd__dfrtp_2 _8_ (.CLK(clk),
    .D(sum_comb),
    .RESET_B(rst_n),
    .Q(sum));
 sky130_fd_sc_hd__dfrtp_2 _9_ (.CLK(clk),
    .D(cout_comb),
    .RESET_B(rst_n),
    .Q(cout));
endmodule
