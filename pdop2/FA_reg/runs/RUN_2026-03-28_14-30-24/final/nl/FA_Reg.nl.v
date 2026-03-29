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
 wire net1;
 wire net2;
 wire net3;
 wire net4;
 wire net5;
 wire net6;
 wire clknet_0_clk;
 wire clknet_1_0__leaf_clk;
 wire clknet_1_1__leaf_clk;

 sky130_fd_sc_hd__inv_2 _3_ (.A(net3),
    .Y(_0_));
 sky130_fd_sc_hd__nand2_1 _4_ (.A(net2),
    .B(net1),
    .Y(_1_));
 sky130_fd_sc_hd__xnor2_1 _5_ (.A(net2),
    .B(net1),
    .Y(_2_));
 sky130_fd_sc_hd__o21ai_1 _6_ (.A1(_0_),
    .A2(_2_),
    .B1(_1_),
    .Y(cout_comb));
 sky130_fd_sc_hd__xnor2_1 _7_ (.A(net3),
    .B(_2_),
    .Y(sum_comb));
 sky130_fd_sc_hd__dfrtp_1 _8_ (.CLK(clknet_1_0__leaf_clk),
    .D(sum_comb),
    .RESET_B(net4),
    .Q(net6));
 sky130_fd_sc_hd__dfrtp_1 _9_ (.CLK(clknet_1_1__leaf_clk),
    .D(cout_comb),
    .RESET_B(net4),
    .Q(net5));
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_0_Right_0 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_1_Right_1 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_2_Right_2 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_3_Right_3 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_4_Right_4 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_5_Right_5 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_6_Right_6 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_7_Right_7 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_8_Right_8 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_9_Right_9 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_0_Left_10 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_1_Left_11 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_2_Left_12 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_3_Left_13 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_4_Left_14 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_5_Left_15 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_6_Left_16 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_7_Left_17 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_8_Left_18 ();
 sky130_fd_sc_hd__decap_3 PHY_EDGE_ROW_9_Left_19 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_0_20 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_0_21 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_1_22 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_2_23 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_3_24 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_4_25 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_5_26 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_6_27 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_7_28 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_8_29 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_9_30 ();
 sky130_fd_sc_hd__tapvpwrvgnd_1 TAP_TAPCELL_ROW_9_31 ();
 sky130_fd_sc_hd__buf_1 input1 (.A(a),
    .X(net1));
 sky130_fd_sc_hd__buf_1 input2 (.A(b),
    .X(net2));
 sky130_fd_sc_hd__buf_1 input3 (.A(cin),
    .X(net3));
 sky130_fd_sc_hd__buf_1 input4 (.A(rst_n),
    .X(net4));
 sky130_fd_sc_hd__buf_2 output5 (.A(net5),
    .X(cout));
 sky130_fd_sc_hd__buf_2 output6 (.A(net6),
    .X(sum));
 sky130_fd_sc_hd__clkbuf_16 clkbuf_0_clk (.A(clk),
    .X(clknet_0_clk));
 sky130_fd_sc_hd__clkbuf_16 clkbuf_1_0__f_clk (.A(clknet_0_clk),
    .X(clknet_1_0__leaf_clk));
 sky130_fd_sc_hd__clkbuf_16 clkbuf_1_1__f_clk (.A(clknet_0_clk),
    .X(clknet_1_1__leaf_clk));
 sky130_ef_sc_hd__decap_12 FILLER_0_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_0_15 ();
 sky130_fd_sc_hd__fill_1 FILLER_0_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_0_29 ();
 sky130_ef_sc_hd__decap_12 FILLER_0_41 ();
 sky130_fd_sc_hd__decap_3 FILLER_0_53 ();
 sky130_fd_sc_hd__decap_3 FILLER_0_57 ();
 sky130_fd_sc_hd__fill_1 FILLER_0_80 ();
 sky130_ef_sc_hd__decap_12 FILLER_1_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_1_15 ();
 sky130_ef_sc_hd__decap_12 FILLER_1_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_1_39 ();
 sky130_fd_sc_hd__decap_4 FILLER_1_51 ();
 sky130_fd_sc_hd__fill_1 FILLER_1_55 ();
 sky130_ef_sc_hd__decap_12 FILLER_1_57 ();
 sky130_ef_sc_hd__decap_12 FILLER_1_69 ();
 sky130_ef_sc_hd__decap_12 FILLER_2_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_2_15 ();
 sky130_fd_sc_hd__fill_1 FILLER_2_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_2_29 ();
 sky130_ef_sc_hd__decap_12 FILLER_2_41 ();
 sky130_ef_sc_hd__decap_12 FILLER_2_53 ();
 sky130_ef_sc_hd__decap_12 FILLER_2_65 ();
 sky130_fd_sc_hd__fill_1 FILLER_2_77 ();
 sky130_ef_sc_hd__decap_12 FILLER_3_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_3_15 ();
 sky130_ef_sc_hd__decap_12 FILLER_3_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_3_39 ();
 sky130_fd_sc_hd__decap_4 FILLER_3_51 ();
 sky130_fd_sc_hd__fill_1 FILLER_3_55 ();
 sky130_fd_sc_hd__fill_2 FILLER_3_57 ();
 sky130_fd_sc_hd__fill_2 FILLER_3_79 ();
 sky130_ef_sc_hd__decap_12 FILLER_4_6 ();
 sky130_fd_sc_hd__fill_1 FILLER_4_18 ();
 sky130_fd_sc_hd__decap_6 FILLER_4_22 ();
 sky130_ef_sc_hd__decap_12 FILLER_4_29 ();
 sky130_ef_sc_hd__decap_12 FILLER_4_41 ();
 sky130_fd_sc_hd__decap_6 FILLER_4_53 ();
 sky130_fd_sc_hd__fill_1 FILLER_4_59 ();
 sky130_fd_sc_hd__fill_1 FILLER_4_80 ();
 sky130_fd_sc_hd__decap_6 FILLER_5_6 ();
 sky130_fd_sc_hd__fill_1 FILLER_5_12 ();
 sky130_fd_sc_hd__fill_1 FILLER_5_20 ();
 sky130_ef_sc_hd__decap_12 FILLER_5_35 ();
 sky130_fd_sc_hd__decap_8 FILLER_5_47 ();
 sky130_fd_sc_hd__fill_1 FILLER_5_55 ();
 sky130_fd_sc_hd__fill_2 FILLER_5_57 ();
 sky130_fd_sc_hd__fill_2 FILLER_5_79 ();
 sky130_ef_sc_hd__decap_12 FILLER_6_6 ();
 sky130_fd_sc_hd__decap_8 FILLER_6_18 ();
 sky130_fd_sc_hd__fill_2 FILLER_6_26 ();
 sky130_ef_sc_hd__decap_12 FILLER_6_29 ();
 sky130_ef_sc_hd__decap_12 FILLER_6_41 ();
 sky130_ef_sc_hd__decap_12 FILLER_6_53 ();
 sky130_fd_sc_hd__decap_8 FILLER_6_65 ();
 sky130_ef_sc_hd__decap_12 FILLER_7_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_7_15 ();
 sky130_ef_sc_hd__decap_12 FILLER_7_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_7_39 ();
 sky130_fd_sc_hd__decap_4 FILLER_7_51 ();
 sky130_fd_sc_hd__fill_1 FILLER_7_55 ();
 sky130_ef_sc_hd__decap_12 FILLER_7_57 ();
 sky130_ef_sc_hd__decap_12 FILLER_7_69 ();
 sky130_ef_sc_hd__decap_12 FILLER_8_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_8_15 ();
 sky130_fd_sc_hd__fill_1 FILLER_8_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_8_29 ();
 sky130_ef_sc_hd__decap_12 FILLER_8_41 ();
 sky130_ef_sc_hd__decap_12 FILLER_8_53 ();
 sky130_ef_sc_hd__decap_12 FILLER_8_65 ();
 sky130_fd_sc_hd__decap_4 FILLER_8_77 ();
 sky130_ef_sc_hd__decap_12 FILLER_9_3 ();
 sky130_ef_sc_hd__decap_12 FILLER_9_15 ();
 sky130_fd_sc_hd__fill_1 FILLER_9_27 ();
 sky130_ef_sc_hd__decap_12 FILLER_9_29 ();
 sky130_ef_sc_hd__decap_12 FILLER_9_41 ();
 sky130_fd_sc_hd__decap_3 FILLER_9_53 ();
 sky130_fd_sc_hd__decap_3 FILLER_9_57 ();
 sky130_fd_sc_hd__fill_1 FILLER_9_80 ();
endmodule
