module clk_reset_ctrl (clk_core,
    clk_in,
    clk_periph,
    core_clk_en,
    cpu_rst_n,
    ext_rst_n,
    fabric_rst_n,
    ndmreset,
    periph_clk_en,
    periph_rst_n,
    por_n,
    soft_rst_pulse,
    test_en);
 output clk_core;
 input clk_in;
 output clk_periph;
 input core_clk_en;
 output cpu_rst_n;
 input ext_rst_n;
 output fabric_rst_n;
 input ndmreset;
 input periph_clk_en;
 output periph_rst_n;
 input por_n;
 input soft_rst_pulse;
 input test_en;

 wire _000_;
 wire _001_;
 wire _002_;
 wire _003_;
 wire _004_;
 wire _005_;
 wire _006_;
 wire _007_;
 wire _008_;
 wire _009_;
 wire _010_;
 wire _011_;
 wire _012_;
 wire _013_;
 wire _014_;
 wire _015_;
 wire _016_;
 wire _017_;
 wire _018_;
 wire _019_;
 wire _020_;
 wire _021_;
 wire _022_;
 wire _023_;
 wire _024_;
 wire _025_;
 wire _026_;
 wire _027_;
 wire _028_;
 wire _029_;
 wire _030_;
 wire _031_;
 wire _032_;
 wire _033_;
 wire _034_;
 wire _035_;
 wire _036_;
 wire _037_;
 wire _038_;
 wire _039_;
 wire _040_;
 wire _041_;
 wire _042_;
 wire _043_;
 wire _044_;
 wire _045_;
 wire _046_;
 wire _047_;
 wire _048_;
 wire _049_;
 wire _050_;
 wire _051_;
 wire _052_;
 wire _053_;
 wire _054_;
 wire _055_;
 wire _056_;
 wire _057_;
 wire _058_;
 wire combined_cpu_rst_n;
 wire combined_rst_n;
 wire por_n_stretched;
 wire \u_clk_core.en_latch ;
 wire \u_clk_core.u_latch.d ;
 wire \u_clk_periph.en_latch ;
 wire \u_clk_periph.u_latch.d ;
 wire \u_por.ctr[0] ;
 wire \u_por.ctr[1] ;
 wire \u_por.ctr[2] ;
 wire \u_por.ctr[3] ;
 wire \u_por.ctr[4] ;
 wire \u_por.ctr[5] ;
 wire \u_por.ctr[6] ;
 wire \u_por.ctr[7] ;
 wire \u_por.ctr[8] ;
 wire \u_por.ctr[9] ;
 wire \u_soft.ctr[0] ;
 wire \u_soft.ctr[1] ;
 wire \u_soft.ctr[2] ;
 wire \u_soft.ctr[3] ;
 wire \u_soft.rst_active ;
 wire \u_sync_cpu.ff1 ;
 wire \u_sync_fabric.ff1 ;
 wire \u_sync_ndm.ff1 ;
 wire \u_sync_ndm.ff2 ;

 sky130_fd_sc_hd__inv_2 _059_ (.A(\u_soft.rst_active ),
    .Y(_024_));
 sky130_fd_sc_hd__inv_2 _060_ (.A(\u_por.ctr[3] ),
    .Y(_025_));
 sky130_fd_sc_hd__inv_2 _061_ (.A(\u_por.ctr[4] ),
    .Y(_026_));
 sky130_fd_sc_hd__inv_2 _062_ (.A(ndmreset),
    .Y(_002_));
 sky130_fd_sc_hd__and3_2 _063_ (.A(_024_),
    .B(ext_rst_n),
    .C(por_n_stretched),
    .X(combined_rst_n));
 sky130_fd_sc_hd__and4_2 _064_ (.A(_024_),
    .B(ext_rst_n),
    .C(por_n_stretched),
    .D(\u_sync_ndm.ff2 ),
    .X(combined_cpu_rst_n));
 sky130_fd_sc_hd__nand2b_2 _065_ (.A_N(\u_soft.ctr[3] ),
    .B(\u_soft.rst_active ),
    .Y(_027_));
 sky130_fd_sc_hd__and3_2 _066_ (.A(\u_soft.ctr[2] ),
    .B(\u_soft.ctr[0] ),
    .C(\u_soft.ctr[1] ),
    .X(_028_));
 sky130_fd_sc_hd__a2bb2o_2 _067_ (.A1_N(_028_),
    .A2_N(_027_),
    .B1(_024_),
    .B2(soft_rst_pulse),
    .X(_000_));
 sky130_fd_sc_hd__and2_2 _068_ (.A(\u_clk_core.en_latch ),
    .B(clk_in),
    .X(clk_core));
 sky130_fd_sc_hd__or2_2 _069_ (.A(test_en),
    .B(core_clk_en),
    .X(\u_clk_core.u_latch.d ));
 sky130_fd_sc_hd__and2_2 _070_ (.A(clk_in),
    .B(\u_clk_periph.en_latch ),
    .X(clk_periph));
 sky130_fd_sc_hd__or2_2 _071_ (.A(test_en),
    .B(periph_clk_en),
    .X(\u_clk_periph.u_latch.d ));
 sky130_fd_sc_hd__and3_2 _072_ (.A(\u_por.ctr[7] ),
    .B(\u_por.ctr[8] ),
    .C(\u_por.ctr[9] ),
    .X(_029_));
 sky130_fd_sc_hd__nand3_2 _073_ (.A(\u_por.ctr[7] ),
    .B(\u_por.ctr[8] ),
    .C(\u_por.ctr[9] ),
    .Y(_030_));
 sky130_fd_sc_hd__and2_2 _074_ (.A(\u_por.ctr[5] ),
    .B(\u_por.ctr[6] ),
    .X(_031_));
 sky130_fd_sc_hd__nand2_2 _075_ (.A(_025_),
    .B(_026_),
    .Y(_032_));
 sky130_fd_sc_hd__o211ai_2 _076_ (.A1(\u_por.ctr[3] ),
    .A2(\u_por.ctr[4] ),
    .B1(\u_por.ctr[5] ),
    .C1(\u_por.ctr[6] ),
    .Y(_033_));
 sky130_fd_sc_hd__nand3_2 _077_ (.A(_029_),
    .B(_032_),
    .C(_031_),
    .Y(_034_));
 sky130_fd_sc_hd__inv_2 _078_ (.A(_034_),
    .Y(_001_));
 sky130_fd_sc_hd__o21a_2 _079_ (.A1(_030_),
    .A2(_033_),
    .B1(\u_por.ctr[0] ),
    .X(_035_));
 sky130_fd_sc_hd__and4b_2 _080_ (.A_N(\u_por.ctr[0] ),
    .B(_029_),
    .C(_032_),
    .D(_031_),
    .X(_036_));
 sky130_fd_sc_hd__nor2_2 _081_ (.A(_035_),
    .B(_036_),
    .Y(_004_));
 sky130_fd_sc_hd__nand2_2 _082_ (.A(\u_por.ctr[1] ),
    .B(\u_por.ctr[0] ),
    .Y(_037_));
 sky130_fd_sc_hd__a31oi_2 _083_ (.A1(_029_),
    .A2(_032_),
    .A3(_031_),
    .B1(_037_),
    .Y(_038_));
 sky130_fd_sc_hd__a21oi_2 _084_ (.A1(_034_),
    .A2(\u_por.ctr[0] ),
    .B1(\u_por.ctr[1] ),
    .Y(_039_));
 sky130_fd_sc_hd__nor2_2 _085_ (.A(_038_),
    .B(_039_),
    .Y(_005_));
 sky130_fd_sc_hd__nand3_2 _086_ (.A(\u_por.ctr[1] ),
    .B(\u_por.ctr[0] ),
    .C(\u_por.ctr[2] ),
    .Y(_040_));
 sky130_fd_sc_hd__o21bai_2 _087_ (.A1(_030_),
    .A2(_033_),
    .B1_N(_040_),
    .Y(_041_));
 sky130_fd_sc_hd__o22a_2 _088_ (.A1(_040_),
    .A2(_001_),
    .B1(\u_por.ctr[2] ),
    .B2(_038_),
    .X(_006_));
 sky130_fd_sc_hd__and4_2 _089_ (.A(\u_por.ctr[1] ),
    .B(\u_por.ctr[0] ),
    .C(\u_por.ctr[2] ),
    .D(\u_por.ctr[3] ),
    .X(_042_));
 sky130_fd_sc_hd__nand4_2 _090_ (.A(\u_por.ctr[1] ),
    .B(\u_por.ctr[0] ),
    .C(\u_por.ctr[2] ),
    .D(\u_por.ctr[3] ),
    .Y(_043_));
 sky130_fd_sc_hd__o2bb2a_2 _091_ (.A1_N(_025_),
    .A2_N(_041_),
    .B1(_043_),
    .B2(_001_),
    .X(_007_));
 sky130_fd_sc_hd__o21ai_2 _092_ (.A1(_043_),
    .A2(_001_),
    .B1(\u_por.ctr[4] ),
    .Y(_044_));
 sky130_fd_sc_hd__o211ai_2 _093_ (.A1(_030_),
    .A2(_033_),
    .B1(_042_),
    .C1(_026_),
    .Y(_045_));
 sky130_fd_sc_hd__nand2_2 _094_ (.A(_044_),
    .B(_045_),
    .Y(_008_));
 sky130_fd_sc_hd__a21oi_2 _095_ (.A1(\u_por.ctr[4] ),
    .A2(_042_),
    .B1(\u_por.ctr[5] ),
    .Y(_046_));
 sky130_fd_sc_hd__nand2_2 _096_ (.A(\u_por.ctr[4] ),
    .B(\u_por.ctr[5] ),
    .Y(_047_));
 sky130_fd_sc_hd__nor2_2 _097_ (.A(_043_),
    .B(_047_),
    .Y(_048_));
 sky130_fd_sc_hd__o21ai_2 _098_ (.A1(_046_),
    .A2(_048_),
    .B1(_034_),
    .Y(_009_));
 sky130_fd_sc_hd__and3_2 _099_ (.A(\u_por.ctr[4] ),
    .B(\u_por.ctr[5] ),
    .C(\u_por.ctr[6] ),
    .X(_049_));
 sky130_fd_sc_hd__nand2_2 _100_ (.A(_042_),
    .B(_049_),
    .Y(_050_));
 sky130_fd_sc_hd__o21bai_2 _101_ (.A1(_043_),
    .A2(_047_),
    .B1_N(\u_por.ctr[6] ),
    .Y(_051_));
 sky130_fd_sc_hd__a32o_2 _102_ (.A1(_029_),
    .A2(_031_),
    .A3(_032_),
    .B1(_050_),
    .B2(_051_),
    .X(_010_));
 sky130_fd_sc_hd__nand4_2 _103_ (.A(\u_por.ctr[4] ),
    .B(\u_por.ctr[5] ),
    .C(\u_por.ctr[6] ),
    .D(\u_por.ctr[7] ),
    .Y(_052_));
 sky130_fd_sc_hd__nor2_2 _104_ (.A(_043_),
    .B(_052_),
    .Y(_053_));
 sky130_fd_sc_hd__a21oi_2 _105_ (.A1(_042_),
    .A2(_049_),
    .B1(\u_por.ctr[7] ),
    .Y(_054_));
 sky130_fd_sc_hd__o21ai_2 _106_ (.A1(_053_),
    .A2(_054_),
    .B1(_034_),
    .Y(_011_));
 sky130_fd_sc_hd__o21bai_2 _107_ (.A1(_043_),
    .A2(_052_),
    .B1_N(\u_por.ctr[8] ),
    .Y(_055_));
 sky130_fd_sc_hd__nand2_2 _108_ (.A(\u_por.ctr[8] ),
    .B(_053_),
    .Y(_018_));
 sky130_fd_sc_hd__a21o_2 _109_ (.A1(_055_),
    .A2(_018_),
    .B1(_001_),
    .X(_012_));
 sky130_fd_sc_hd__a21o_2 _110_ (.A1(\u_por.ctr[8] ),
    .A2(_053_),
    .B1(\u_por.ctr[9] ),
    .X(_013_));
 sky130_fd_sc_hd__o21a_2 _111_ (.A1(soft_rst_pulse),
    .A2(\u_soft.rst_active ),
    .B1(\u_soft.ctr[0] ),
    .X(_019_));
 sky130_fd_sc_hd__or3b_2 _112_ (.A(soft_rst_pulse),
    .B(\u_soft.rst_active ),
    .C_N(\u_soft.ctr[0] ),
    .X(_020_));
 sky130_fd_sc_hd__o21ai_2 _113_ (.A1(\u_soft.ctr[0] ),
    .A2(_027_),
    .B1(_020_),
    .Y(_014_));
 sky130_fd_sc_hd__o22ai_2 _114_ (.A1(soft_rst_pulse),
    .A2(\u_soft.rst_active ),
    .B1(_027_),
    .B2(_028_),
    .Y(_021_));
 sky130_fd_sc_hd__o211a_2 _115_ (.A1(soft_rst_pulse),
    .A2(\u_soft.rst_active ),
    .B1(\u_soft.ctr[0] ),
    .C1(\u_soft.ctr[1] ),
    .X(_022_));
 sky130_fd_sc_hd__o21ai_2 _116_ (.A1(\u_soft.ctr[1] ),
    .A2(_019_),
    .B1(_021_),
    .Y(_023_));
 sky130_fd_sc_hd__a21oi_2 _117_ (.A1(\u_soft.ctr[1] ),
    .A2(_019_),
    .B1(_023_),
    .Y(_015_));
 sky130_fd_sc_hd__o21a_2 _118_ (.A1(\u_soft.ctr[2] ),
    .A2(_022_),
    .B1(_021_),
    .X(_016_));
 sky130_fd_sc_hd__and3b_2 _119_ (.A_N(soft_rst_pulse),
    .B(_024_),
    .C(\u_soft.ctr[3] ),
    .X(_017_));
 sky130_fd_sc_hd__inv_2 _120_ (.A(ndmreset),
    .Y(_003_));
 sky130_fd_sc_hd__dfrtp_2 _121_ (.CLK(clk_in),
    .D(_001_),
    .RESET_B(por_n),
    .Q(por_n_stretched));
 sky130_fd_sc_hd__dfrtp_2 _122_ (.CLK(clk_in),
    .D(_004_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[0] ));
 sky130_fd_sc_hd__dfrtp_2 _123_ (.CLK(clk_in),
    .D(_005_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[1] ));
 sky130_fd_sc_hd__dfrtp_2 _124_ (.CLK(clk_in),
    .D(_006_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[2] ));
 sky130_fd_sc_hd__dfrtp_2 _125_ (.CLK(clk_in),
    .D(_007_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[3] ));
 sky130_fd_sc_hd__dfrtp_2 _126_ (.CLK(clk_in),
    .D(_008_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[4] ));
 sky130_fd_sc_hd__dfrtp_2 _127_ (.CLK(clk_in),
    .D(_009_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[5] ));
 sky130_fd_sc_hd__dfrtp_2 _128_ (.CLK(clk_in),
    .D(_010_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[6] ));
 sky130_fd_sc_hd__dfrtp_2 _129_ (.CLK(clk_in),
    .D(_011_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[7] ));
 sky130_fd_sc_hd__dfrtp_2 _130_ (.CLK(clk_in),
    .D(_012_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[8] ));
 sky130_fd_sc_hd__dfrtp_2 _131_ (.CLK(clk_in),
    .D(_013_),
    .RESET_B(por_n),
    .Q(\u_por.ctr[9] ));
 sky130_fd_sc_hd__dfrtp_2 _132_ (.CLK(clk_in),
    .D(_000_),
    .RESET_B(por_n_stretched),
    .Q(\u_soft.rst_active ));
 sky130_fd_sc_hd__dfrtp_2 _133_ (.CLK(clk_in),
    .D(_056_),
    .RESET_B(_002_),
    .Q(\u_sync_ndm.ff1 ));
 sky130_fd_sc_hd__dfrtp_2 _134_ (.CLK(clk_in),
    .D(\u_sync_ndm.ff1 ),
    .RESET_B(_003_),
    .Q(\u_sync_ndm.ff2 ));
 sky130_fd_sc_hd__dfrtp_2 _135_ (.CLK(clk_in),
    .D(_058_),
    .RESET_B(combined_rst_n),
    .Q(\u_sync_fabric.ff1 ));
 sky130_fd_sc_hd__dfrtp_2 _136_ (.CLK(clk_in),
    .D(\u_sync_fabric.ff1 ),
    .RESET_B(combined_rst_n),
    .Q(fabric_rst_n));
 sky130_fd_sc_hd__dfrtp_2 _137_ (.CLK(clk_in),
    .D(_057_),
    .RESET_B(combined_cpu_rst_n),
    .Q(\u_sync_cpu.ff1 ));
 sky130_fd_sc_hd__dfrtp_2 _138_ (.CLK(clk_in),
    .D(\u_sync_cpu.ff1 ),
    .RESET_B(combined_cpu_rst_n),
    .Q(cpu_rst_n));
 sky130_fd_sc_hd__dfrtp_2 _139_ (.CLK(clk_in),
    .D(_014_),
    .RESET_B(por_n_stretched),
    .Q(\u_soft.ctr[0] ));
 sky130_fd_sc_hd__dfrtp_2 _140_ (.CLK(clk_in),
    .D(_015_),
    .RESET_B(por_n_stretched),
    .Q(\u_soft.ctr[1] ));
 sky130_fd_sc_hd__dfrtp_2 _141_ (.CLK(clk_in),
    .D(_016_),
    .RESET_B(por_n_stretched),
    .Q(\u_soft.ctr[2] ));
 sky130_fd_sc_hd__dfrtp_2 _142_ (.CLK(clk_in),
    .D(_017_),
    .RESET_B(por_n_stretched),
    .Q(\u_soft.ctr[3] ));
 sky130_fd_sc_hd__dlxtn_1 _143_ (.D(\u_clk_core.u_latch.d ),
    .GATE_N(clk_in),
    .Q(\u_clk_core.en_latch ));
 sky130_fd_sc_hd__dlxtn_1 _144_ (.D(\u_clk_periph.u_latch.d ),
    .GATE_N(clk_in),
    .Q(\u_clk_periph.en_latch ));
 sky130_fd_sc_hd__conb_1 _145_ (.HI(_056_));
 sky130_fd_sc_hd__conb_1 _146_ (.HI(_057_));
 sky130_fd_sc_hd__conb_1 _147_ (.HI(_058_));
 sky130_fd_sc_hd__buf_2 _148_ (.A(cpu_rst_n),
    .X(periph_rst_n));
endmodule
