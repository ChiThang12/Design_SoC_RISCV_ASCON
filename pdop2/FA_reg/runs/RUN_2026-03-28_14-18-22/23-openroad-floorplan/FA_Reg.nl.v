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

 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_0_Left_6 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_0_Right_0 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_1_Left_7 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_1_Right_1 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_2_Left_8 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_2_Right_2 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_3_Left_9 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_3_Right_3 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_4_Left_10 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_4_Right_4 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_5_Left_11 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_5_Right_5 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_0_12 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_2_13 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_4_14 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_5_15 ();
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
