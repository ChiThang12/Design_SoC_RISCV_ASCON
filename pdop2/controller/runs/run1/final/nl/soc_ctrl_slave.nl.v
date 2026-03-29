module soc_ctrl_slave (S_AXI_ARREADY,
    S_AXI_ARVALID,
    S_AXI_AWREADY,
    S_AXI_AWVALID,
    S_AXI_BREADY,
    S_AXI_BVALID,
    S_AXI_RLAST,
    S_AXI_RREADY,
    S_AXI_RVALID,
    S_AXI_WLAST,
    S_AXI_WREADY,
    S_AXI_WVALID,
    ascon_irq,
    clk,
    gpio_irq,
    irq_out,
    rst_n,
    soft_rst_pulse,
    spi_irq,
    timer_irq,
    uart_irq,
    wdt_irq,
    S_AXI_ARADDR,
    S_AXI_ARBURST,
    S_AXI_ARID,
    S_AXI_ARLEN,
    S_AXI_ARPROT,
    S_AXI_ARSIZE,
    S_AXI_AWADDR,
    S_AXI_AWBURST,
    S_AXI_AWID,
    S_AXI_AWLEN,
    S_AXI_AWPROT,
    S_AXI_AWSIZE,
    S_AXI_BID,
    S_AXI_BRESP,
    S_AXI_RDATA,
    S_AXI_RID,
    S_AXI_RRESP,
    S_AXI_WDATA,
    S_AXI_WSTRB,
    dcache_hits,
    dcache_misses,
    dcache_writes,
    icache_hits,
    icache_misses);
 output S_AXI_ARREADY;
 input S_AXI_ARVALID;
 output S_AXI_AWREADY;
 input S_AXI_AWVALID;
 input S_AXI_BREADY;
 output S_AXI_BVALID;
 output S_AXI_RLAST;
 input S_AXI_RREADY;
 output S_AXI_RVALID;
 input S_AXI_WLAST;
 output S_AXI_WREADY;
 input S_AXI_WVALID;
 input ascon_irq;
 input clk;
 input gpio_irq;
 output irq_out;
 input rst_n;
 output soft_rst_pulse;
 input spi_irq;
 input timer_irq;
 input uart_irq;
 input wdt_irq;
 input [31:0] S_AXI_ARADDR;
 input [1:0] S_AXI_ARBURST;
 input [3:0] S_AXI_ARID;
 input [7:0] S_AXI_ARLEN;
 input [2:0] S_AXI_ARPROT;
 input [2:0] S_AXI_ARSIZE;
 input [31:0] S_AXI_AWADDR;
 input [1:0] S_AXI_AWBURST;
 input [3:0] S_AXI_AWID;
 input [7:0] S_AXI_AWLEN;
 input [2:0] S_AXI_AWPROT;
 input [2:0] S_AXI_AWSIZE;
 output [3:0] S_AXI_BID;
 output [1:0] S_AXI_BRESP;
 output [31:0] S_AXI_RDATA;
 output [3:0] S_AXI_RID;
 output [1:0] S_AXI_RRESP;
 input [31:0] S_AXI_WDATA;
 input [3:0] S_AXI_WSTRB;
 input [31:0] dcache_hits;
 input [31:0] dcache_misses;
 input [31:0] dcache_writes;
 input [31:0] icache_hits;
 input [31:0] icache_misses;

 wire _0000_;
 wire _0001_;
 wire _0002_;
 wire _0003_;
 wire _0004_;
 wire _0005_;
 wire _0006_;
 wire _0007_;
 wire _0008_;
 wire _0009_;
 wire _0010_;
 wire _0011_;
 wire _0012_;
 wire _0013_;
 wire _0014_;
 wire _0015_;
 wire _0016_;
 wire _0017_;
 wire _0018_;
 wire _0019_;
 wire _0020_;
 wire _0021_;
 wire _0022_;
 wire _0023_;
 wire _0024_;
 wire _0025_;
 wire _0026_;
 wire _0027_;
 wire _0028_;
 wire _0029_;
 wire _0030_;
 wire _0031_;
 wire _0032_;
 wire _0033_;
 wire _0034_;
 wire _0035_;
 wire _0036_;
 wire _0037_;
 wire _0038_;
 wire _0039_;
 wire _0040_;
 wire _0041_;
 wire _0042_;
 wire _0043_;
 wire _0044_;
 wire _0045_;
 wire _0046_;
 wire _0047_;
 wire _0048_;
 wire _0049_;
 wire _0050_;
 wire _0051_;
 wire _0052_;
 wire _0053_;
 wire _0054_;
 wire _0055_;
 wire _0056_;
 wire _0057_;
 wire _0058_;
 wire _0059_;
 wire _0060_;
 wire _0061_;
 wire _0062_;
 wire _0063_;
 wire _0064_;
 wire _0065_;
 wire _0066_;
 wire _0067_;
 wire _0068_;
 wire _0069_;
 wire _0070_;
 wire _0071_;
 wire _0072_;
 wire _0073_;
 wire _0074_;
 wire _0075_;
 wire _0076_;
 wire _0077_;
 wire _0078_;
 wire _0079_;
 wire _0080_;
 wire _0081_;
 wire _0082_;
 wire _0083_;
 wire _0084_;
 wire _0085_;
 wire _0086_;
 wire _0087_;
 wire _0088_;
 wire _0089_;
 wire _0090_;
 wire _0091_;
 wire _0092_;
 wire _0093_;
 wire _0094_;
 wire _0095_;
 wire _0096_;
 wire _0097_;
 wire _0098_;
 wire _0099_;
 wire _0100_;
 wire _0101_;
 wire _0102_;
 wire _0103_;
 wire _0104_;
 wire _0105_;
 wire _0106_;
 wire _0107_;
 wire _0108_;
 wire _0109_;
 wire _0110_;
 wire _0111_;
 wire _0112_;
 wire _0113_;
 wire _0114_;
 wire _0115_;
 wire _0116_;
 wire _0117_;
 wire _0118_;
 wire _0119_;
 wire _0120_;
 wire _0121_;
 wire _0122_;
 wire _0123_;
 wire _0124_;
 wire _0125_;
 wire _0126_;
 wire _0127_;
 wire _0128_;
 wire _0129_;
 wire _0130_;
 wire _0131_;
 wire _0132_;
 wire _0133_;
 wire _0134_;
 wire _0135_;
 wire _0136_;
 wire _0137_;
 wire _0138_;
 wire _0139_;
 wire _0140_;
 wire _0141_;
 wire _0142_;
 wire _0143_;
 wire _0144_;
 wire _0145_;
 wire _0146_;
 wire _0147_;
 wire _0148_;
 wire _0149_;
 wire _0150_;
 wire _0151_;
 wire _0152_;
 wire _0153_;
 wire _0154_;
 wire _0155_;
 wire _0156_;
 wire _0157_;
 wire _0158_;
 wire _0159_;
 wire _0160_;
 wire _0161_;
 wire _0162_;
 wire _0163_;
 wire _0164_;
 wire _0165_;
 wire _0166_;
 wire _0167_;
 wire _0168_;
 wire _0169_;
 wire _0170_;
 wire _0171_;
 wire _0172_;
 wire _0173_;
 wire _0174_;
 wire _0175_;
 wire _0176_;
 wire _0177_;
 wire _0178_;
 wire _0179_;
 wire _0180_;
 wire _0181_;
 wire _0182_;
 wire _0183_;
 wire _0184_;
 wire _0185_;
 wire _0186_;
 wire _0187_;
 wire _0188_;
 wire _0189_;
 wire _0190_;
 wire _0191_;
 wire _0192_;
 wire _0193_;
 wire _0194_;
 wire _0195_;
 wire _0196_;
 wire _0197_;
 wire _0198_;
 wire _0199_;
 wire _0200_;
 wire _0201_;
 wire _0202_;
 wire _0203_;
 wire _0204_;
 wire _0205_;
 wire _0206_;
 wire _0207_;
 wire _0208_;
 wire _0209_;
 wire _0210_;
 wire _0211_;
 wire _0212_;
 wire _0213_;
 wire _0214_;
 wire _0215_;
 wire _0216_;
 wire _0217_;
 wire _0218_;
 wire _0219_;
 wire _0220_;
 wire _0221_;
 wire _0222_;
 wire _0223_;
 wire _0224_;
 wire _0225_;
 wire _0226_;
 wire _0227_;
 wire _0228_;
 wire _0229_;
 wire _0230_;
 wire _0231_;
 wire _0232_;
 wire _0233_;
 wire _0234_;
 wire _0235_;
 wire _0236_;
 wire _0237_;
 wire _0238_;
 wire _0239_;
 wire _0240_;
 wire _0241_;
 wire _0242_;
 wire _0243_;
 wire _0244_;
 wire _0245_;
 wire _0246_;
 wire _0247_;
 wire _0248_;
 wire _0249_;
 wire _0250_;
 wire _0251_;
 wire _0252_;
 wire _0253_;
 wire _0254_;
 wire _0255_;
 wire _0256_;
 wire _0257_;
 wire _0258_;
 wire _0259_;
 wire _0260_;
 wire _0261_;
 wire _0262_;
 wire _0263_;
 wire _0264_;
 wire _0265_;
 wire _0266_;
 wire _0267_;
 wire _0268_;
 wire _0269_;
 wire _0270_;
 wire _0271_;
 wire _0272_;
 wire _0273_;
 wire _0274_;
 wire _0275_;
 wire _0276_;
 wire _0277_;
 wire _0278_;
 wire _0279_;
 wire _0280_;
 wire _0281_;
 wire _0282_;
 wire _0283_;
 wire _0284_;
 wire _0285_;
 wire _0286_;
 wire _0287_;
 wire _0288_;
 wire _0289_;
 wire _0290_;
 wire _0291_;
 wire _0292_;
 wire _0293_;
 wire _0294_;
 wire _0295_;
 wire _0296_;
 wire _0297_;
 wire _0298_;
 wire _0299_;
 wire _0300_;
 wire _0301_;
 wire _0302_;
 wire _0303_;
 wire _0304_;
 wire _0305_;
 wire _0306_;
 wire _0307_;
 wire _0308_;
 wire _0309_;
 wire _0310_;
 wire _0311_;
 wire _0312_;
 wire _0313_;
 wire _0314_;
 wire _0315_;
 wire _0316_;
 wire _0317_;
 wire _0318_;
 wire _0319_;
 wire _0320_;
 wire _0321_;
 wire _0322_;
 wire _0323_;
 wire _0324_;
 wire _0325_;
 wire _0326_;
 wire _0327_;
 wire _0328_;
 wire _0329_;
 wire _0330_;
 wire _0331_;
 wire _0332_;
 wire _0333_;
 wire _0334_;
 wire _0335_;
 wire _0336_;
 wire _0337_;
 wire _0338_;
 wire _0339_;
 wire _0340_;
 wire _0341_;
 wire _0342_;
 wire _0343_;
 wire _0344_;
 wire _0345_;
 wire _0346_;
 wire _0347_;
 wire _0348_;
 wire _0349_;
 wire _0350_;
 wire _0351_;
 wire _0352_;
 wire _0353_;
 wire _0354_;
 wire _0355_;
 wire _0356_;
 wire _0357_;
 wire _0358_;
 wire _0359_;
 wire _0360_;
 wire _0361_;
 wire _0362_;
 wire _0363_;
 wire _0364_;
 wire _0365_;
 wire _0366_;
 wire _0367_;
 wire _0368_;
 wire _0369_;
 wire _0370_;
 wire _0371_;
 wire _0372_;
 wire _0373_;
 wire _0374_;
 wire _0375_;
 wire _0376_;
 wire _0377_;
 wire _0378_;
 wire _0379_;
 wire _0380_;
 wire _0381_;
 wire _0382_;
 wire _0383_;
 wire _0384_;
 wire _0385_;
 wire _0386_;
 wire _0387_;
 wire _0388_;
 wire _0389_;
 wire _0390_;
 wire _0391_;
 wire _0392_;
 wire _0393_;
 wire _0394_;
 wire _0395_;
 wire _0396_;
 wire _0397_;
 wire _0398_;
 wire _0399_;
 wire _0400_;
 wire _0401_;
 wire _0402_;
 wire _0403_;
 wire _0404_;
 wire _0405_;
 wire _0406_;
 wire _0407_;
 wire _0408_;
 wire _0409_;
 wire _0410_;
 wire _0411_;
 wire _0412_;
 wire _0413_;
 wire _0414_;
 wire _0415_;
 wire _0416_;
 wire _0417_;
 wire _0418_;
 wire _0419_;
 wire _0420_;
 wire _0421_;
 wire _0422_;
 wire _0423_;
 wire _0424_;
 wire _0425_;
 wire _0426_;
 wire _0427_;
 wire _0428_;
 wire _0429_;
 wire _0430_;
 wire _0431_;
 wire _0432_;
 wire _0433_;
 wire _0434_;
 wire _0435_;
 wire _0436_;
 wire _0437_;
 wire _0438_;
 wire _0439_;
 wire _0440_;
 wire _0441_;
 wire _0442_;
 wire _0443_;
 wire _0444_;
 wire _0445_;
 wire _0446_;
 wire _0447_;
 wire _0448_;
 wire _0449_;
 wire _0450_;
 wire _0451_;
 wire _0452_;
 wire _0453_;
 wire _0454_;
 wire _0455_;
 wire _0456_;
 wire _0457_;
 wire _0458_;
 wire _0459_;
 wire _0460_;
 wire _0461_;
 wire _0462_;
 wire _0463_;
 wire _0464_;
 wire _0465_;
 wire _0466_;
 wire _0467_;
 wire _0468_;
 wire _0469_;
 wire _0470_;
 wire _0471_;
 wire _0472_;
 wire _0473_;
 wire _0474_;
 wire _0475_;
 wire _0476_;
 wire _0477_;
 wire _0478_;
 wire _0479_;
 wire _0480_;
 wire _0481_;
 wire _0482_;
 wire _0483_;
 wire _0484_;
 wire _0485_;
 wire _0486_;
 wire _0487_;
 wire _0488_;
 wire _0489_;
 wire _0490_;
 wire _0491_;
 wire _0492_;
 wire _0493_;
 wire _0494_;
 wire _0495_;
 wire _0496_;
 wire _0497_;
 wire _0498_;
 wire _0499_;
 wire _0500_;
 wire _0501_;
 wire _0502_;
 wire _0503_;
 wire _0504_;
 wire _0505_;
 wire _0506_;
 wire _0507_;
 wire _0508_;
 wire _0509_;
 wire _0510_;
 wire _0511_;
 wire _0512_;
 wire _0513_;
 wire _0514_;
 wire _0515_;
 wire _0516_;
 wire _0517_;
 wire _0518_;
 wire _0519_;
 wire _0520_;
 wire _0521_;
 wire _0522_;
 wire _0523_;
 wire _0524_;
 wire _0525_;
 wire _0526_;
 wire _0527_;
 wire _0528_;
 wire _0529_;
 wire _0530_;
 wire _0531_;
 wire _0532_;
 wire _0533_;
 wire _0534_;
 wire _0535_;
 wire _0536_;
 wire _0537_;
 wire _0538_;
 wire _0539_;
 wire _0540_;
 wire _0541_;
 wire _0542_;
 wire _0543_;
 wire _0544_;
 wire _0545_;
 wire _0546_;
 wire _0547_;
 wire _0548_;
 wire _0549_;
 wire _0550_;
 wire _0551_;
 wire _0552_;
 wire _0553_;
 wire _0554_;
 wire _0555_;
 wire _0556_;
 wire _0557_;
 wire _0558_;
 wire _0559_;
 wire _0560_;
 wire _0561_;
 wire _0562_;
 wire _0563_;
 wire _0564_;
 wire _0565_;
 wire _0566_;
 wire _0567_;
 wire _0568_;
 wire _0569_;
 wire _0570_;
 wire _0571_;
 wire \ar_addr_lat[0] ;
 wire \ar_addr_lat[10] ;
 wire \ar_addr_lat[11] ;
 wire \ar_addr_lat[1] ;
 wire \ar_addr_lat[2] ;
 wire \ar_addr_lat[3] ;
 wire \ar_addr_lat[4] ;
 wire \ar_addr_lat[5] ;
 wire \ar_addr_lat[6] ;
 wire \ar_addr_lat[7] ;
 wire \ar_addr_lat[8] ;
 wire \ar_addr_lat[9] ;
 wire ar_done;
 wire \aw_addr_lat[0] ;
 wire \aw_addr_lat[10] ;
 wire \aw_addr_lat[11] ;
 wire \aw_addr_lat[1] ;
 wire \aw_addr_lat[2] ;
 wire \aw_addr_lat[3] ;
 wire \aw_addr_lat[4] ;
 wire \aw_addr_lat[5] ;
 wire \aw_addr_lat[6] ;
 wire \aw_addr_lat[7] ;
 wire \aw_addr_lat[8] ;
 wire \aw_addr_lat[9] ;
 wire aw_done;
 wire \cycle_cnt_r[0] ;
 wire \cycle_cnt_r[10] ;
 wire \cycle_cnt_r[11] ;
 wire \cycle_cnt_r[12] ;
 wire \cycle_cnt_r[13] ;
 wire \cycle_cnt_r[14] ;
 wire \cycle_cnt_r[15] ;
 wire \cycle_cnt_r[16] ;
 wire \cycle_cnt_r[17] ;
 wire \cycle_cnt_r[18] ;
 wire \cycle_cnt_r[19] ;
 wire \cycle_cnt_r[1] ;
 wire \cycle_cnt_r[20] ;
 wire \cycle_cnt_r[21] ;
 wire \cycle_cnt_r[22] ;
 wire \cycle_cnt_r[23] ;
 wire \cycle_cnt_r[24] ;
 wire \cycle_cnt_r[25] ;
 wire \cycle_cnt_r[26] ;
 wire \cycle_cnt_r[27] ;
 wire \cycle_cnt_r[28] ;
 wire \cycle_cnt_r[29] ;
 wire \cycle_cnt_r[2] ;
 wire \cycle_cnt_r[30] ;
 wire \cycle_cnt_r[31] ;
 wire \cycle_cnt_r[3] ;
 wire \cycle_cnt_r[4] ;
 wire \cycle_cnt_r[5] ;
 wire \cycle_cnt_r[6] ;
 wire \cycle_cnt_r[7] ;
 wire \cycle_cnt_r[8] ;
 wire \cycle_cnt_r[9] ;
 wire \irq_mask_r[0] ;
 wire \irq_mask_r[1] ;
 wire \irq_mask_r[2] ;
 wire \irq_mask_r[3] ;
 wire \irq_mask_r[4] ;
 wire \irq_mask_r[5] ;
 wire \irq_prev[0] ;
 wire \irq_prev[1] ;
 wire \irq_prev[2] ;
 wire \irq_prev[3] ;
 wire \irq_prev[4] ;
 wire \irq_prev[5] ;
 wire \irq_status_r[0] ;
 wire \irq_status_r[1] ;
 wire \irq_status_r[2] ;
 wire \irq_status_r[3] ;
 wire \irq_status_r[4] ;
 wire \irq_status_r[5] ;
 wire \w_data_lat[0] ;
 wire \w_data_lat[1] ;
 wire \w_data_lat[2] ;
 wire \w_data_lat[3] ;
 wire \w_data_lat[4] ;
 wire \w_data_lat[5] ;
 wire w_done;
 wire \w_strb_lat[0] ;

 sky130_fd_sc_hd__inv_2 _0572_ (.A(aw_done),
    .Y(S_AXI_AWREADY));
 sky130_fd_sc_hd__inv_2 _0573_ (.A(ar_done),
    .Y(S_AXI_ARREADY));
 sky130_fd_sc_hd__inv_2 _0574_ (.A(w_done),
    .Y(S_AXI_WREADY));
 sky130_fd_sc_hd__inv_2 _0575_ (.A(soft_rst_pulse),
    .Y(_0135_));
 sky130_fd_sc_hd__inv_2 _0576_ (.A(\cycle_cnt_r[1] ),
    .Y(_0136_));
 sky130_fd_sc_hd__inv_2 _0577_ (.A(\cycle_cnt_r[2] ),
    .Y(_0137_));
 sky130_fd_sc_hd__inv_2 _0578_ (.A(\cycle_cnt_r[4] ),
    .Y(_0138_));
 sky130_fd_sc_hd__inv_2 _0579_ (.A(\cycle_cnt_r[15] ),
    .Y(_0139_));
 sky130_fd_sc_hd__inv_2 _0580_ (.A(\cycle_cnt_r[20] ),
    .Y(_0140_));
 sky130_fd_sc_hd__inv_2 _0581_ (.A(\cycle_cnt_r[24] ),
    .Y(_0141_));
 sky130_fd_sc_hd__inv_2 _0582_ (.A(\cycle_cnt_r[28] ),
    .Y(_0142_));
 sky130_fd_sc_hd__inv_2 _0583_ (.A(\cycle_cnt_r[30] ),
    .Y(_0143_));
 sky130_fd_sc_hd__inv_2 _0584_ (.A(\ar_addr_lat[3] ),
    .Y(_0144_));
 sky130_fd_sc_hd__inv_2 _0585_ (.A(\ar_addr_lat[2] ),
    .Y(_0145_));
 sky130_fd_sc_hd__inv_2 _0586_ (.A(\ar_addr_lat[4] ),
    .Y(_0146_));
 sky130_fd_sc_hd__inv_2 _0587_ (.A(\ar_addr_lat[5] ),
    .Y(_0147_));
 sky130_fd_sc_hd__inv_2 _0588_ (.A(ascon_irq),
    .Y(_0148_));
 sky130_fd_sc_hd__inv_2 _0589_ (.A(uart_irq),
    .Y(_0149_));
 sky130_fd_sc_hd__inv_2 _0590_ (.A(gpio_irq),
    .Y(_0150_));
 sky130_fd_sc_hd__inv_2 _0591_ (.A(spi_irq),
    .Y(_0151_));
 sky130_fd_sc_hd__inv_2 _0592_ (.A(timer_irq),
    .Y(_0152_));
 sky130_fd_sc_hd__inv_2 _0593_ (.A(wdt_irq),
    .Y(_0153_));
 sky130_fd_sc_hd__inv_2 _0594_ (.A(S_AXI_BRESP[1]),
    .Y(_0154_));
 sky130_fd_sc_hd__a22o_2 _0595_ (.A1(\irq_mask_r[0] ),
    .A2(\irq_status_r[0] ),
    .B1(\irq_mask_r[2] ),
    .B2(\irq_status_r[2] ),
    .X(_0155_));
 sky130_fd_sc_hd__a221o_2 _0596_ (.A1(\irq_mask_r[3] ),
    .A2(\irq_status_r[3] ),
    .B1(\irq_mask_r[5] ),
    .B2(\irq_status_r[5] ),
    .C1(_0155_),
    .X(_0156_));
 sky130_fd_sc_hd__a221o_2 _0597_ (.A1(\irq_mask_r[1] ),
    .A2(\irq_status_r[1] ),
    .B1(\irq_mask_r[4] ),
    .B2(\irq_status_r[4] ),
    .C1(_0156_),
    .X(irq_out));
 sky130_fd_sc_hd__nor2_2 _0598_ (.A(\cycle_cnt_r[0] ),
    .B(soft_rst_pulse),
    .Y(_0000_));
 sky130_fd_sc_hd__a21oi_2 _0599_ (.A1(\cycle_cnt_r[0] ),
    .A2(\cycle_cnt_r[1] ),
    .B1(soft_rst_pulse),
    .Y(_0157_));
 sky130_fd_sc_hd__o21a_2 _0600_ (.A1(\cycle_cnt_r[0] ),
    .A2(\cycle_cnt_r[1] ),
    .B1(_0157_),
    .X(_0011_));
 sky130_fd_sc_hd__a21o_2 _0601_ (.A1(\cycle_cnt_r[0] ),
    .A2(\cycle_cnt_r[1] ),
    .B1(\cycle_cnt_r[2] ),
    .X(_0158_));
 sky130_fd_sc_hd__and3_2 _0602_ (.A(\cycle_cnt_r[0] ),
    .B(\cycle_cnt_r[1] ),
    .C(\cycle_cnt_r[2] ),
    .X(_0159_));
 sky130_fd_sc_hd__nand3_2 _0603_ (.A(\cycle_cnt_r[0] ),
    .B(\cycle_cnt_r[1] ),
    .C(\cycle_cnt_r[2] ),
    .Y(_0160_));
 sky130_fd_sc_hd__and3_2 _0604_ (.A(_0135_),
    .B(_0158_),
    .C(_0160_),
    .X(_0022_));
 sky130_fd_sc_hd__a41o_2 _0605_ (.A1(\cycle_cnt_r[0] ),
    .A2(\cycle_cnt_r[1] ),
    .A3(\cycle_cnt_r[2] ),
    .A4(\cycle_cnt_r[3] ),
    .B1(soft_rst_pulse),
    .X(_0161_));
 sky130_fd_sc_hd__o21ba_2 _0606_ (.A1(\cycle_cnt_r[3] ),
    .A2(_0159_),
    .B1_N(_0161_),
    .X(_0025_));
 sky130_fd_sc_hd__a41o_2 _0607_ (.A1(\cycle_cnt_r[0] ),
    .A2(\cycle_cnt_r[1] ),
    .A3(\cycle_cnt_r[2] ),
    .A4(\cycle_cnt_r[3] ),
    .B1(\cycle_cnt_r[4] ),
    .X(_0162_));
 sky130_fd_sc_hd__nand2_2 _0608_ (.A(\cycle_cnt_r[3] ),
    .B(\cycle_cnt_r[4] ),
    .Y(_0163_));
 sky130_fd_sc_hd__o211a_2 _0609_ (.A1(_0160_),
    .A2(_0163_),
    .B1(_0162_),
    .C1(_0135_),
    .X(_0026_));
 sky130_fd_sc_hd__a31o_2 _0610_ (.A1(\cycle_cnt_r[3] ),
    .A2(\cycle_cnt_r[4] ),
    .A3(_0159_),
    .B1(\cycle_cnt_r[5] ),
    .X(_0164_));
 sky130_fd_sc_hd__nand3_2 _0611_ (.A(\cycle_cnt_r[3] ),
    .B(\cycle_cnt_r[4] ),
    .C(\cycle_cnt_r[5] ),
    .Y(_0165_));
 sky130_fd_sc_hd__nor2_2 _0612_ (.A(_0160_),
    .B(_0165_),
    .Y(_0166_));
 sky130_fd_sc_hd__o211a_2 _0613_ (.A1(_0160_),
    .A2(_0165_),
    .B1(_0164_),
    .C1(_0135_),
    .X(_0027_));
 sky130_fd_sc_hd__a21oi_2 _0614_ (.A1(\cycle_cnt_r[6] ),
    .A2(_0166_),
    .B1(soft_rst_pulse),
    .Y(_0167_));
 sky130_fd_sc_hd__o21a_2 _0615_ (.A1(\cycle_cnt_r[6] ),
    .A2(_0166_),
    .B1(_0167_),
    .X(_0028_));
 sky130_fd_sc_hd__a21oi_2 _0616_ (.A1(\cycle_cnt_r[6] ),
    .A2(_0166_),
    .B1(\cycle_cnt_r[7] ),
    .Y(_0168_));
 sky130_fd_sc_hd__and2_2 _0617_ (.A(\cycle_cnt_r[6] ),
    .B(\cycle_cnt_r[7] ),
    .X(_0169_));
 sky130_fd_sc_hd__nand2_2 _0618_ (.A(\cycle_cnt_r[6] ),
    .B(\cycle_cnt_r[7] ),
    .Y(_0170_));
 sky130_fd_sc_hd__nor3_2 _0619_ (.A(_0160_),
    .B(_0165_),
    .C(_0170_),
    .Y(_0171_));
 sky130_fd_sc_hd__a311oi_2 _0620_ (.A1(\cycle_cnt_r[6] ),
    .A2(\cycle_cnt_r[7] ),
    .A3(_0166_),
    .B1(_0168_),
    .C1(soft_rst_pulse),
    .Y(_0029_));
 sky130_fd_sc_hd__a21oi_2 _0621_ (.A1(\cycle_cnt_r[8] ),
    .A2(_0171_),
    .B1(soft_rst_pulse),
    .Y(_0172_));
 sky130_fd_sc_hd__o21a_2 _0622_ (.A1(\cycle_cnt_r[8] ),
    .A2(_0171_),
    .B1(_0172_),
    .X(_0030_));
 sky130_fd_sc_hd__a21oi_2 _0623_ (.A1(\cycle_cnt_r[8] ),
    .A2(_0171_),
    .B1(\cycle_cnt_r[9] ),
    .Y(_0173_));
 sky130_fd_sc_hd__nand2_2 _0624_ (.A(\cycle_cnt_r[8] ),
    .B(\cycle_cnt_r[9] ),
    .Y(_0174_));
 sky130_fd_sc_hd__a311oi_2 _0625_ (.A1(\cycle_cnt_r[8] ),
    .A2(\cycle_cnt_r[9] ),
    .A3(_0171_),
    .B1(_0173_),
    .C1(soft_rst_pulse),
    .Y(_0031_));
 sky130_fd_sc_hd__a31oi_2 _0626_ (.A1(\cycle_cnt_r[8] ),
    .A2(\cycle_cnt_r[9] ),
    .A3(_0171_),
    .B1(\cycle_cnt_r[10] ),
    .Y(_0175_));
 sky130_fd_sc_hd__and4_2 _0627_ (.A(\cycle_cnt_r[8] ),
    .B(\cycle_cnt_r[9] ),
    .C(\cycle_cnt_r[10] ),
    .D(_0171_),
    .X(_0176_));
 sky130_fd_sc_hd__nor3_2 _0628_ (.A(soft_rst_pulse),
    .B(_0175_),
    .C(_0176_),
    .Y(_0001_));
 sky130_fd_sc_hd__and3_2 _0629_ (.A(\cycle_cnt_r[9] ),
    .B(\cycle_cnt_r[10] ),
    .C(\cycle_cnt_r[11] ),
    .X(_0177_));
 sky130_fd_sc_hd__a31o_2 _0630_ (.A1(\cycle_cnt_r[8] ),
    .A2(_0171_),
    .A3(_0177_),
    .B1(soft_rst_pulse),
    .X(_0178_));
 sky130_fd_sc_hd__o21ba_2 _0631_ (.A1(\cycle_cnt_r[11] ),
    .A2(_0176_),
    .B1_N(_0178_),
    .X(_0002_));
 sky130_fd_sc_hd__a31oi_2 _0632_ (.A1(\cycle_cnt_r[8] ),
    .A2(_0171_),
    .A3(_0177_),
    .B1(\cycle_cnt_r[12] ),
    .Y(_0179_));
 sky130_fd_sc_hd__nand3_2 _0633_ (.A(\cycle_cnt_r[10] ),
    .B(\cycle_cnt_r[11] ),
    .C(\cycle_cnt_r[12] ),
    .Y(_0180_));
 sky130_fd_sc_hd__nor2_2 _0634_ (.A(_0174_),
    .B(_0180_),
    .Y(_0181_));
 sky130_fd_sc_hd__nor4b_2 _0635_ (.A(_0160_),
    .B(_0165_),
    .C(_0170_),
    .D_N(_0181_),
    .Y(_0182_));
 sky130_fd_sc_hd__a211oi_2 _0636_ (.A1(_0171_),
    .A2(_0181_),
    .B1(_0179_),
    .C1(soft_rst_pulse),
    .Y(_0003_));
 sky130_fd_sc_hd__a31o_2 _0637_ (.A1(\cycle_cnt_r[13] ),
    .A2(_0171_),
    .A3(_0181_),
    .B1(soft_rst_pulse),
    .X(_0183_));
 sky130_fd_sc_hd__o21ba_2 _0638_ (.A1(\cycle_cnt_r[13] ),
    .A2(_0182_),
    .B1_N(_0183_),
    .X(_0004_));
 sky130_fd_sc_hd__a31o_2 _0639_ (.A1(\cycle_cnt_r[13] ),
    .A2(_0171_),
    .A3(_0181_),
    .B1(\cycle_cnt_r[14] ),
    .X(_0184_));
 sky130_fd_sc_hd__nand4_2 _0640_ (.A(\cycle_cnt_r[13] ),
    .B(\cycle_cnt_r[14] ),
    .C(_0171_),
    .D(_0181_),
    .Y(_0185_));
 sky130_fd_sc_hd__and3_2 _0641_ (.A(_0135_),
    .B(_0184_),
    .C(_0185_),
    .X(_0005_));
 sky130_fd_sc_hd__and3_2 _0642_ (.A(\cycle_cnt_r[13] ),
    .B(\cycle_cnt_r[14] ),
    .C(\cycle_cnt_r[15] ),
    .X(_0186_));
 sky130_fd_sc_hd__and4_2 _0643_ (.A(_0166_),
    .B(_0169_),
    .C(_0181_),
    .D(_0186_),
    .X(_0187_));
 sky130_fd_sc_hd__nand4_2 _0644_ (.A(_0166_),
    .B(_0169_),
    .C(_0181_),
    .D(_0186_),
    .Y(_0188_));
 sky130_fd_sc_hd__a221oi_2 _0645_ (.A1(_0182_),
    .A2(_0186_),
    .B1(_0185_),
    .B2(_0139_),
    .C1(soft_rst_pulse),
    .Y(_0006_));
 sky130_fd_sc_hd__a41oi_2 _0646_ (.A1(\cycle_cnt_r[16] ),
    .A2(_0171_),
    .A3(_0181_),
    .A4(_0186_),
    .B1(soft_rst_pulse),
    .Y(_0189_));
 sky130_fd_sc_hd__o21a_2 _0647_ (.A1(\cycle_cnt_r[16] ),
    .A2(_0187_),
    .B1(_0189_),
    .X(_0007_));
 sky130_fd_sc_hd__a41oi_2 _0648_ (.A1(\cycle_cnt_r[16] ),
    .A2(_0171_),
    .A3(_0181_),
    .A4(_0186_),
    .B1(\cycle_cnt_r[17] ),
    .Y(_0190_));
 sky130_fd_sc_hd__and2_2 _0649_ (.A(\cycle_cnt_r[16] ),
    .B(\cycle_cnt_r[17] ),
    .X(_0191_));
 sky130_fd_sc_hd__a211oi_2 _0650_ (.A1(_0187_),
    .A2(_0191_),
    .B1(_0190_),
    .C1(soft_rst_pulse),
    .Y(_0008_));
 sky130_fd_sc_hd__a41oi_2 _0651_ (.A1(_0171_),
    .A2(_0181_),
    .A3(_0186_),
    .A4(_0191_),
    .B1(\cycle_cnt_r[18] ),
    .Y(_0192_));
 sky130_fd_sc_hd__and3_2 _0652_ (.A(\cycle_cnt_r[16] ),
    .B(\cycle_cnt_r[17] ),
    .C(\cycle_cnt_r[18] ),
    .X(_0193_));
 sky130_fd_sc_hd__a311oi_2 _0653_ (.A1(\cycle_cnt_r[18] ),
    .A2(_0187_),
    .A3(_0191_),
    .B1(_0192_),
    .C1(soft_rst_pulse),
    .Y(_0009_));
 sky130_fd_sc_hd__a41o_2 _0654_ (.A1(_0171_),
    .A2(_0181_),
    .A3(_0186_),
    .A4(_0193_),
    .B1(\cycle_cnt_r[19] ),
    .X(_0194_));
 sky130_fd_sc_hd__and4_2 _0655_ (.A(\cycle_cnt_r[16] ),
    .B(\cycle_cnt_r[17] ),
    .C(\cycle_cnt_r[18] ),
    .D(\cycle_cnt_r[19] ),
    .X(_0195_));
 sky130_fd_sc_hd__nand4_2 _0656_ (.A(\cycle_cnt_r[16] ),
    .B(\cycle_cnt_r[17] ),
    .C(\cycle_cnt_r[18] ),
    .D(\cycle_cnt_r[19] ),
    .Y(_0196_));
 sky130_fd_sc_hd__nand4_2 _0657_ (.A(_0171_),
    .B(_0181_),
    .C(_0186_),
    .D(_0195_),
    .Y(_0197_));
 sky130_fd_sc_hd__and3_2 _0658_ (.A(_0135_),
    .B(_0194_),
    .C(_0197_),
    .X(_0010_));
 sky130_fd_sc_hd__o21ai_2 _0659_ (.A1(_0140_),
    .A2(_0197_),
    .B1(_0135_),
    .Y(_0198_));
 sky130_fd_sc_hd__a21oi_2 _0660_ (.A1(_0140_),
    .A2(_0197_),
    .B1(_0198_),
    .Y(_0012_));
 sky130_fd_sc_hd__o21bai_2 _0661_ (.A1(_0140_),
    .A2(_0197_),
    .B1_N(\cycle_cnt_r[21] ),
    .Y(_0199_));
 sky130_fd_sc_hd__nand2_2 _0662_ (.A(\cycle_cnt_r[20] ),
    .B(\cycle_cnt_r[21] ),
    .Y(_0200_));
 sky130_fd_sc_hd__nor2_2 _0663_ (.A(_0197_),
    .B(_0200_),
    .Y(_0201_));
 sky130_fd_sc_hd__o311a_2 _0664_ (.A1(_0188_),
    .A2(_0196_),
    .A3(_0200_),
    .B1(_0199_),
    .C1(_0135_),
    .X(_0013_));
 sky130_fd_sc_hd__and3_2 _0665_ (.A(\cycle_cnt_r[20] ),
    .B(\cycle_cnt_r[21] ),
    .C(\cycle_cnt_r[22] ),
    .X(_0202_));
 sky130_fd_sc_hd__a41oi_2 _0666_ (.A1(_0182_),
    .A2(_0186_),
    .A3(_0195_),
    .A4(_0202_),
    .B1(soft_rst_pulse),
    .Y(_0203_));
 sky130_fd_sc_hd__o21a_2 _0667_ (.A1(\cycle_cnt_r[22] ),
    .A2(_0201_),
    .B1(_0203_),
    .X(_0014_));
 sky130_fd_sc_hd__a31oi_2 _0668_ (.A1(_0187_),
    .A2(_0195_),
    .A3(_0202_),
    .B1(\cycle_cnt_r[23] ),
    .Y(_0204_));
 sky130_fd_sc_hd__nand4_2 _0669_ (.A(\cycle_cnt_r[20] ),
    .B(\cycle_cnt_r[21] ),
    .C(\cycle_cnt_r[22] ),
    .D(\cycle_cnt_r[23] ),
    .Y(_0205_));
 sky130_fd_sc_hd__nor2_2 _0670_ (.A(_0196_),
    .B(_0205_),
    .Y(_0206_));
 sky130_fd_sc_hd__nand4_2 _0671_ (.A(_0171_),
    .B(_0181_),
    .C(_0186_),
    .D(_0206_),
    .Y(_0207_));
 sky130_fd_sc_hd__a31o_2 _0672_ (.A1(_0182_),
    .A2(_0186_),
    .A3(_0206_),
    .B1(soft_rst_pulse),
    .X(_0208_));
 sky130_fd_sc_hd__nor2_2 _0673_ (.A(_0208_),
    .B(_0204_),
    .Y(_0015_));
 sky130_fd_sc_hd__a21oi_2 _0674_ (.A1(_0141_),
    .A2(_0207_),
    .B1(soft_rst_pulse),
    .Y(_0209_));
 sky130_fd_sc_hd__o41a_2 _0675_ (.A1(_0141_),
    .A2(_0188_),
    .A3(_0196_),
    .A4(_0205_),
    .B1(_0209_),
    .X(_0016_));
 sky130_fd_sc_hd__o21bai_2 _0676_ (.A1(_0141_),
    .A2(_0207_),
    .B1_N(\cycle_cnt_r[25] ),
    .Y(_0210_));
 sky130_fd_sc_hd__nand2_2 _0677_ (.A(\cycle_cnt_r[24] ),
    .B(\cycle_cnt_r[25] ),
    .Y(_0211_));
 sky130_fd_sc_hd__nor2_2 _0678_ (.A(_0207_),
    .B(_0211_),
    .Y(_0212_));
 sky130_fd_sc_hd__o211a_2 _0679_ (.A1(_0207_),
    .A2(_0211_),
    .B1(_0210_),
    .C1(_0135_),
    .X(_0017_));
 sky130_fd_sc_hd__and3_2 _0680_ (.A(\cycle_cnt_r[24] ),
    .B(\cycle_cnt_r[25] ),
    .C(\cycle_cnt_r[26] ),
    .X(_0213_));
 sky130_fd_sc_hd__a41oi_2 _0681_ (.A1(_0182_),
    .A2(_0186_),
    .A3(_0206_),
    .A4(_0213_),
    .B1(soft_rst_pulse),
    .Y(_0214_));
 sky130_fd_sc_hd__o21a_2 _0682_ (.A1(\cycle_cnt_r[26] ),
    .A2(_0212_),
    .B1(_0214_),
    .X(_0018_));
 sky130_fd_sc_hd__a31oi_2 _0683_ (.A1(_0187_),
    .A2(_0206_),
    .A3(_0213_),
    .B1(\cycle_cnt_r[27] ),
    .Y(_0215_));
 sky130_fd_sc_hd__nand4_2 _0684_ (.A(\cycle_cnt_r[24] ),
    .B(\cycle_cnt_r[25] ),
    .C(\cycle_cnt_r[26] ),
    .D(\cycle_cnt_r[27] ),
    .Y(_0216_));
 sky130_fd_sc_hd__nor3_2 _0685_ (.A(_0196_),
    .B(_0205_),
    .C(_0216_),
    .Y(_0217_));
 sky130_fd_sc_hd__nand3_2 _0686_ (.A(\cycle_cnt_r[27] ),
    .B(_0206_),
    .C(_0213_),
    .Y(_0218_));
 sky130_fd_sc_hd__a31o_2 _0687_ (.A1(_0182_),
    .A2(_0186_),
    .A3(_0217_),
    .B1(soft_rst_pulse),
    .X(_0219_));
 sky130_fd_sc_hd__nor2_2 _0688_ (.A(_0219_),
    .B(_0215_),
    .Y(_0019_));
 sky130_fd_sc_hd__o21ai_2 _0689_ (.A1(_0188_),
    .A2(_0218_),
    .B1(_0142_),
    .Y(_0220_));
 sky130_fd_sc_hd__nor3_2 _0690_ (.A(_0142_),
    .B(_0188_),
    .C(_0218_),
    .Y(_0221_));
 sky130_fd_sc_hd__o311a_2 _0691_ (.A1(_0142_),
    .A2(_0207_),
    .A3(_0216_),
    .B1(_0220_),
    .C1(_0135_),
    .X(_0020_));
 sky130_fd_sc_hd__and2_2 _0692_ (.A(\cycle_cnt_r[28] ),
    .B(\cycle_cnt_r[29] ),
    .X(_0222_));
 sky130_fd_sc_hd__nand4_2 _0693_ (.A(_0182_),
    .B(_0186_),
    .C(_0217_),
    .D(_0222_),
    .Y(_0223_));
 sky130_fd_sc_hd__a41oi_2 _0694_ (.A1(_0182_),
    .A2(_0186_),
    .A3(_0217_),
    .A4(_0222_),
    .B1(soft_rst_pulse),
    .Y(_0224_));
 sky130_fd_sc_hd__o21a_2 _0695_ (.A1(\cycle_cnt_r[29] ),
    .A2(_0221_),
    .B1(_0224_),
    .X(_0021_));
 sky130_fd_sc_hd__nand2_2 _0696_ (.A(\cycle_cnt_r[30] ),
    .B(_0222_),
    .Y(_0225_));
 sky130_fd_sc_hd__nor3_2 _0697_ (.A(_0188_),
    .B(_0218_),
    .C(_0225_),
    .Y(_0226_));
 sky130_fd_sc_hd__o31ai_2 _0698_ (.A1(_0188_),
    .A2(_0218_),
    .A3(_0225_),
    .B1(_0135_),
    .Y(_0227_));
 sky130_fd_sc_hd__a21oi_2 _0699_ (.A1(_0143_),
    .A2(_0223_),
    .B1(_0227_),
    .Y(_0023_));
 sky130_fd_sc_hd__and4_2 _0700_ (.A(\cycle_cnt_r[28] ),
    .B(\cycle_cnt_r[29] ),
    .C(\cycle_cnt_r[30] ),
    .D(\cycle_cnt_r[31] ),
    .X(_0228_));
 sky130_fd_sc_hd__a41oi_2 _0701_ (.A1(_0182_),
    .A2(_0186_),
    .A3(_0217_),
    .A4(_0228_),
    .B1(soft_rst_pulse),
    .Y(_0229_));
 sky130_fd_sc_hd__o21a_2 _0702_ (.A1(\cycle_cnt_r[31] ),
    .A2(_0226_),
    .B1(_0229_),
    .X(_0024_));
 sky130_fd_sc_hd__and3b_2 _0703_ (.A_N(S_AXI_BVALID),
    .B(w_done),
    .C(aw_done),
    .X(_0230_));
 sky130_fd_sc_hd__nor4_2 _0704_ (.A(\aw_addr_lat[9] ),
    .B(\aw_addr_lat[8] ),
    .C(\aw_addr_lat[11] ),
    .D(\aw_addr_lat[10] ),
    .Y(_0231_));
 sky130_fd_sc_hd__nor2_2 _0705_ (.A(\aw_addr_lat[1] ),
    .B(\aw_addr_lat[0] ),
    .Y(_0232_));
 sky130_fd_sc_hd__nor2_2 _0706_ (.A(\aw_addr_lat[7] ),
    .B(\aw_addr_lat[6] ),
    .Y(_0233_));
 sky130_fd_sc_hd__nor4_2 _0707_ (.A(\aw_addr_lat[1] ),
    .B(\aw_addr_lat[0] ),
    .C(\aw_addr_lat[7] ),
    .D(\aw_addr_lat[6] ),
    .Y(_0234_));
 sky130_fd_sc_hd__nand3_2 _0708_ (.A(_0230_),
    .B(_0231_),
    .C(_0234_),
    .Y(_0235_));
 sky130_fd_sc_hd__nor3b_2 _0709_ (.A(\aw_addr_lat[5] ),
    .B(\aw_addr_lat[4] ),
    .C_N(\w_strb_lat[0] ),
    .Y(_0236_));
 sky130_fd_sc_hd__and4b_2 _0710_ (.A_N(\aw_addr_lat[3] ),
    .B(\w_data_lat[0] ),
    .C(_0236_),
    .D(\aw_addr_lat[2] ),
    .X(_0237_));
 sky130_fd_sc_hd__and4_2 _0711_ (.A(_0230_),
    .B(_0231_),
    .C(_0234_),
    .D(_0237_),
    .X(_0038_));
 sky130_fd_sc_hd__and3b_2 _0712_ (.A_N(\aw_addr_lat[2] ),
    .B(\aw_addr_lat[3] ),
    .C(_0236_),
    .X(_0238_));
 sky130_fd_sc_hd__and4_2 _0713_ (.A(_0230_),
    .B(_0231_),
    .C(_0232_),
    .D(_0233_),
    .X(_0239_));
 sky130_fd_sc_hd__nand3_2 _0714_ (.A(\w_data_lat[0] ),
    .B(_0238_),
    .C(_0239_),
    .Y(_0240_));
 sky130_fd_sc_hd__o2bb2ai_2 _0715_ (.A1_N(\irq_status_r[0] ),
    .A2_N(_0240_),
    .B1(_0148_),
    .B2(\irq_prev[0] ),
    .Y(_0032_));
 sky130_fd_sc_hd__nand3_2 _0716_ (.A(\w_data_lat[1] ),
    .B(_0238_),
    .C(_0239_),
    .Y(_0241_));
 sky130_fd_sc_hd__o2bb2ai_2 _0717_ (.A1_N(\irq_status_r[1] ),
    .A2_N(_0241_),
    .B1(_0149_),
    .B2(\irq_prev[1] ),
    .Y(_0033_));
 sky130_fd_sc_hd__nand3_2 _0718_ (.A(\w_data_lat[2] ),
    .B(_0238_),
    .C(_0239_),
    .Y(_0242_));
 sky130_fd_sc_hd__o2bb2ai_2 _0719_ (.A1_N(\irq_status_r[2] ),
    .A2_N(_0242_),
    .B1(_0150_),
    .B2(\irq_prev[2] ),
    .Y(_0034_));
 sky130_fd_sc_hd__nand3_2 _0720_ (.A(\w_data_lat[3] ),
    .B(_0238_),
    .C(_0239_),
    .Y(_0243_));
 sky130_fd_sc_hd__o2bb2ai_2 _0721_ (.A1_N(\irq_status_r[3] ),
    .A2_N(_0243_),
    .B1(_0151_),
    .B2(\irq_prev[3] ),
    .Y(_0035_));
 sky130_fd_sc_hd__nand3_2 _0722_ (.A(\w_data_lat[4] ),
    .B(_0238_),
    .C(_0239_),
    .Y(_0244_));
 sky130_fd_sc_hd__o2bb2ai_2 _0723_ (.A1_N(\irq_status_r[4] ),
    .A2_N(_0244_),
    .B1(_0152_),
    .B2(\irq_prev[4] ),
    .Y(_0036_));
 sky130_fd_sc_hd__nand3_2 _0724_ (.A(\w_data_lat[5] ),
    .B(_0238_),
    .C(_0239_),
    .Y(_0245_));
 sky130_fd_sc_hd__o2bb2ai_2 _0725_ (.A1_N(\irq_status_r[5] ),
    .A2_N(_0245_),
    .B1(_0153_),
    .B2(\irq_prev[5] ),
    .Y(_0037_));
 sky130_fd_sc_hd__nand2_2 _0726_ (.A(S_AXI_RVALID),
    .B(S_AXI_RREADY),
    .Y(_0246_));
 sky130_fd_sc_hd__nor2_2 _0727_ (.A(S_AXI_RVALID),
    .B(S_AXI_ARREADY),
    .Y(_0247_));
 sky130_fd_sc_hd__or2_2 _0728_ (.A(S_AXI_RVALID),
    .B(S_AXI_ARREADY),
    .X(_0248_));
 sky130_fd_sc_hd__o21a_2 _0729_ (.A1(ar_done),
    .A2(S_AXI_RVALID),
    .B1(_0246_),
    .X(_0039_));
 sky130_fd_sc_hd__nor2_2 _0730_ (.A(S_AXI_RDATA[0]),
    .B(_0247_),
    .Y(_0249_));
 sky130_fd_sc_hd__nor2_2 _0731_ (.A(\ar_addr_lat[7] ),
    .B(\ar_addr_lat[6] ),
    .Y(_0250_));
 sky130_fd_sc_hd__nor3b_2 _0732_ (.A(\ar_addr_lat[7] ),
    .B(\ar_addr_lat[6] ),
    .C_N(\ar_addr_lat[4] ),
    .Y(_0251_));
 sky130_fd_sc_hd__nor2_2 _0733_ (.A(\ar_addr_lat[9] ),
    .B(\ar_addr_lat[8] ),
    .Y(_0252_));
 sky130_fd_sc_hd__nor2_2 _0734_ (.A(\ar_addr_lat[11] ),
    .B(\ar_addr_lat[10] ),
    .Y(_0253_));
 sky130_fd_sc_hd__nor2_2 _0735_ (.A(\ar_addr_lat[8] ),
    .B(\ar_addr_lat[11] ),
    .Y(_0254_));
 sky130_fd_sc_hd__nor2_2 _0736_ (.A(\ar_addr_lat[9] ),
    .B(\ar_addr_lat[10] ),
    .Y(_0255_));
 sky130_fd_sc_hd__nor4_2 _0737_ (.A(\ar_addr_lat[9] ),
    .B(\ar_addr_lat[8] ),
    .C(\ar_addr_lat[11] ),
    .D(\ar_addr_lat[10] ),
    .Y(_0256_));
 sky130_fd_sc_hd__nand2_2 _0738_ (.A(_0252_),
    .B(_0253_),
    .Y(_0257_));
 sky130_fd_sc_hd__nand3_2 _0739_ (.A(_0254_),
    .B(_0255_),
    .C(_0147_),
    .Y(_0258_));
 sky130_fd_sc_hd__and3_2 _0740_ (.A(_0256_),
    .B(_0147_),
    .C(_0251_),
    .X(_0259_));
 sky130_fd_sc_hd__nand4_2 _0741_ (.A(_0251_),
    .B(_0254_),
    .C(_0255_),
    .D(_0147_),
    .Y(_0260_));
 sky130_fd_sc_hd__nor2_2 _0742_ (.A(\ar_addr_lat[1] ),
    .B(\ar_addr_lat[0] ),
    .Y(_0261_));
 sky130_fd_sc_hd__nor4b_2 _0743_ (.A(\ar_addr_lat[1] ),
    .B(\ar_addr_lat[0] ),
    .C(\ar_addr_lat[2] ),
    .D_N(\ar_addr_lat[3] ),
    .Y(_0262_));
 sky130_fd_sc_hd__nand4_2 _0744_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[0]),
    .Y(_0263_));
 sky130_fd_sc_hd__and4bb_2 _0745_ (.A_N(\ar_addr_lat[1] ),
    .B_N(\ar_addr_lat[0] ),
    .C(\ar_addr_lat[3] ),
    .D(\ar_addr_lat[2] ),
    .X(_0264_));
 sky130_fd_sc_hd__nand4_2 _0746_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[0]),
    .D(_0261_),
    .Y(_0265_));
 sky130_fd_sc_hd__nor3_2 _0747_ (.A(\ar_addr_lat[1] ),
    .B(\ar_addr_lat[0] ),
    .C(\ar_addr_lat[3] ),
    .Y(_0266_));
 sky130_fd_sc_hd__nor4_2 _0748_ (.A(\ar_addr_lat[1] ),
    .B(\ar_addr_lat[0] ),
    .C(\ar_addr_lat[3] ),
    .D(\ar_addr_lat[2] ),
    .Y(_0267_));
 sky130_fd_sc_hd__nand3_2 _0749_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .Y(_0268_));
 sky130_fd_sc_hd__nand4_2 _0750_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[0]),
    .Y(_0269_));
 sky130_fd_sc_hd__nor4b_2 _0751_ (.A(\ar_addr_lat[1] ),
    .B(\ar_addr_lat[0] ),
    .C(\ar_addr_lat[3] ),
    .D_N(\ar_addr_lat[2] ),
    .Y(_0270_));
 sky130_fd_sc_hd__nand4_2 _0752_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[0]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0271_));
 sky130_fd_sc_hd__a41o_2 _0753_ (.A1(_0263_),
    .A2(_0265_),
    .A3(_0269_),
    .A4(_0271_),
    .B1(_0260_),
    .X(_0272_));
 sky130_fd_sc_hd__nor3_2 _0754_ (.A(\ar_addr_lat[4] ),
    .B(\ar_addr_lat[7] ),
    .C(\ar_addr_lat[6] ),
    .Y(_0273_));
 sky130_fd_sc_hd__nand2_2 _0755_ (.A(_0250_),
    .B(_0146_),
    .Y(_0274_));
 sky130_fd_sc_hd__nor4b_2 _0756_ (.A(\ar_addr_lat[4] ),
    .B(\ar_addr_lat[7] ),
    .C(\ar_addr_lat[6] ),
    .D_N(\ar_addr_lat[5] ),
    .Y(_0275_));
 sky130_fd_sc_hd__nand3_2 _0757_ (.A(_0250_),
    .B(_0146_),
    .C(\ar_addr_lat[5] ),
    .Y(_0276_));
 sky130_fd_sc_hd__nand3_2 _0758_ (.A(_0256_),
    .B(_0270_),
    .C(_0275_),
    .Y(_0277_));
 sky130_fd_sc_hd__nand4_2 _0759_ (.A(\cycle_cnt_r[0] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0278_));
 sky130_fd_sc_hd__nor2_2 _0760_ (.A(_0258_),
    .B(_0274_),
    .Y(_0279_));
 sky130_fd_sc_hd__nand4_2 _0761_ (.A(_0252_),
    .B(_0253_),
    .C(_0273_),
    .D(_0147_),
    .Y(_0280_));
 sky130_fd_sc_hd__o31a_2 _0762_ (.A1(_0258_),
    .A2(_0268_),
    .A3(_0274_),
    .B1(_0247_),
    .X(_0281_));
 sky130_fd_sc_hd__and3_2 _0763_ (.A(\ar_addr_lat[5] ),
    .B(_0254_),
    .C(_0255_),
    .X(_0282_));
 sky130_fd_sc_hd__and4_2 _0764_ (.A(\ar_addr_lat[5] ),
    .B(_0252_),
    .C(_0253_),
    .D(_0273_),
    .X(_0283_));
 sky130_fd_sc_hd__o211a_2 _0765_ (.A1(_0268_),
    .A2(_0280_),
    .B1(_0247_),
    .C1(_0278_),
    .X(_0284_));
 sky130_fd_sc_hd__nand4_2 _0766_ (.A(\irq_mask_r[0] ),
    .B(\ar_addr_lat[3] ),
    .C(\ar_addr_lat[2] ),
    .D(_0261_),
    .Y(_0285_));
 sky130_fd_sc_hd__nand4_2 _0767_ (.A(_0145_),
    .B(_0261_),
    .C(\irq_status_r[0] ),
    .D(\ar_addr_lat[3] ),
    .Y(_0286_));
 sky130_fd_sc_hd__nand2_2 _0768_ (.A(_0285_),
    .B(_0286_),
    .Y(_0287_));
 sky130_fd_sc_hd__nor3_2 _0769_ (.A(_0257_),
    .B(_0268_),
    .C(_0276_),
    .Y(_0288_));
 sky130_fd_sc_hd__a22oi_2 _0770_ (.A1(_0279_),
    .A2(_0287_),
    .B1(_0288_),
    .B2(dcache_writes[0]),
    .Y(_0289_));
 sky130_fd_sc_hd__a31oi_2 _0771_ (.A1(_0284_),
    .A2(_0289_),
    .A3(_0272_),
    .B1(_0249_),
    .Y(_0040_));
 sky130_fd_sc_hd__nor2_2 _0772_ (.A(S_AXI_RDATA[1]),
    .B(_0247_),
    .Y(_0290_));
 sky130_fd_sc_hd__nand4_2 _0773_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[1]),
    .Y(_0291_));
 sky130_fd_sc_hd__nand4_2 _0774_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[1]),
    .D(_0261_),
    .Y(_0292_));
 sky130_fd_sc_hd__and3_2 _0775_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[1]),
    .C(_0266_),
    .X(_0293_));
 sky130_fd_sc_hd__nand4_2 _0776_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[1]),
    .Y(_0294_));
 sky130_fd_sc_hd__nand3_2 _0777_ (.A(_0291_),
    .B(_0292_),
    .C(_0294_),
    .Y(_0295_));
 sky130_fd_sc_hd__o21ai_2 _0778_ (.A1(_0295_),
    .A2(_0293_),
    .B1(_0259_),
    .Y(_0296_));
 sky130_fd_sc_hd__nand4_2 _0779_ (.A(\irq_mask_r[1] ),
    .B(\ar_addr_lat[3] ),
    .C(\ar_addr_lat[2] ),
    .D(_0261_),
    .Y(_0297_));
 sky130_fd_sc_hd__nand4_2 _0780_ (.A(_0145_),
    .B(_0261_),
    .C(\irq_status_r[1] ),
    .D(\ar_addr_lat[3] ),
    .Y(_0298_));
 sky130_fd_sc_hd__nand2_2 _0781_ (.A(_0297_),
    .B(_0298_),
    .Y(_0299_));
 sky130_fd_sc_hd__a21oi_2 _0782_ (.A1(_0279_),
    .A2(_0299_),
    .B1(_0248_),
    .Y(_0300_));
 sky130_fd_sc_hd__a2bb2oi_2 _0783_ (.A1_N(_0136_),
    .A2_N(_0277_),
    .B1(_0288_),
    .B2(dcache_writes[1]),
    .Y(_0301_));
 sky130_fd_sc_hd__a31oi_2 _0784_ (.A1(_0301_),
    .A2(_0296_),
    .A3(_0300_),
    .B1(_0290_),
    .Y(_0041_));
 sky130_fd_sc_hd__nor2_2 _0785_ (.A(S_AXI_RDATA[2]),
    .B(_0247_),
    .Y(_0302_));
 sky130_fd_sc_hd__nand4_2 _0786_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[2]),
    .Y(_0303_));
 sky130_fd_sc_hd__nand4_2 _0787_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[2]),
    .D(_0261_),
    .Y(_0304_));
 sky130_fd_sc_hd__and3_2 _0788_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[2]),
    .C(_0266_),
    .X(_0305_));
 sky130_fd_sc_hd__nand4_2 _0789_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[2]),
    .Y(_0306_));
 sky130_fd_sc_hd__nand3_2 _0790_ (.A(_0303_),
    .B(_0304_),
    .C(_0306_),
    .Y(_0307_));
 sky130_fd_sc_hd__o21ai_2 _0791_ (.A1(_0307_),
    .A2(_0305_),
    .B1(_0259_),
    .Y(_0308_));
 sky130_fd_sc_hd__nand4_2 _0792_ (.A(_0145_),
    .B(_0261_),
    .C(\irq_status_r[2] ),
    .D(\ar_addr_lat[3] ),
    .Y(_0309_));
 sky130_fd_sc_hd__nand4_2 _0793_ (.A(\irq_mask_r[2] ),
    .B(\ar_addr_lat[3] ),
    .C(\ar_addr_lat[2] ),
    .D(_0261_),
    .Y(_0310_));
 sky130_fd_sc_hd__nand2_2 _0794_ (.A(_0309_),
    .B(_0310_),
    .Y(_0311_));
 sky130_fd_sc_hd__a21oi_2 _0795_ (.A1(_0311_),
    .A2(_0279_),
    .B1(_0248_),
    .Y(_0312_));
 sky130_fd_sc_hd__a2bb2oi_2 _0796_ (.A1_N(_0137_),
    .A2_N(_0277_),
    .B1(_0288_),
    .B2(dcache_writes[2]),
    .Y(_0313_));
 sky130_fd_sc_hd__a31oi_2 _0797_ (.A1(_0313_),
    .A2(_0308_),
    .A3(_0312_),
    .B1(_0302_),
    .Y(_0042_));
 sky130_fd_sc_hd__nor2_2 _0798_ (.A(S_AXI_RDATA[3]),
    .B(_0247_),
    .Y(_0314_));
 sky130_fd_sc_hd__nand2_2 _0799_ (.A(dcache_hits[3]),
    .B(_0262_),
    .Y(_0315_));
 sky130_fd_sc_hd__nand4_2 _0800_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[3]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0316_));
 sky130_fd_sc_hd__nand4_2 _0801_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[3]),
    .D(_0261_),
    .Y(_0317_));
 sky130_fd_sc_hd__nand4_2 _0802_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[3]),
    .Y(_0318_));
 sky130_fd_sc_hd__nand4_2 _0803_ (.A(_0315_),
    .B(_0316_),
    .C(_0317_),
    .D(_0318_),
    .Y(_0319_));
 sky130_fd_sc_hd__nand2_2 _0804_ (.A(_0319_),
    .B(_0259_),
    .Y(_0320_));
 sky130_fd_sc_hd__a41oi_2 _0805_ (.A1(dcache_writes[3]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0321_));
 sky130_fd_sc_hd__nand4_2 _0806_ (.A(_0145_),
    .B(_0261_),
    .C(\irq_status_r[3] ),
    .D(\ar_addr_lat[3] ),
    .Y(_0322_));
 sky130_fd_sc_hd__nand4_2 _0807_ (.A(\irq_mask_r[3] ),
    .B(\ar_addr_lat[3] ),
    .C(\ar_addr_lat[2] ),
    .D(_0261_),
    .Y(_0323_));
 sky130_fd_sc_hd__a21o_2 _0808_ (.A1(_0322_),
    .A2(_0323_),
    .B1(_0280_),
    .X(_0324_));
 sky130_fd_sc_hd__nand4_2 _0809_ (.A(\cycle_cnt_r[3] ),
    .B(_0270_),
    .C(_0273_),
    .D(_0282_),
    .Y(_0325_));
 sky130_fd_sc_hd__a41oi_2 _0810_ (.A1(_0320_),
    .A2(_0321_),
    .A3(_0324_),
    .A4(_0325_),
    .B1(_0314_),
    .Y(_0043_));
 sky130_fd_sc_hd__nor2_2 _0811_ (.A(S_AXI_RDATA[4]),
    .B(_0247_),
    .Y(_0326_));
 sky130_fd_sc_hd__nand4_2 _0812_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[4]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0327_));
 sky130_fd_sc_hd__nand4_2 _0813_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[4]),
    .D(_0261_),
    .Y(_0328_));
 sky130_fd_sc_hd__and4_2 _0814_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[4]),
    .X(_0329_));
 sky130_fd_sc_hd__nand4_2 _0815_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[4]),
    .Y(_0330_));
 sky130_fd_sc_hd__nand3_2 _0816_ (.A(_0327_),
    .B(_0328_),
    .C(_0330_),
    .Y(_0331_));
 sky130_fd_sc_hd__o21ai_2 _0817_ (.A1(_0329_),
    .A2(_0331_),
    .B1(_0259_),
    .Y(_0332_));
 sky130_fd_sc_hd__nand4_2 _0818_ (.A(_0145_),
    .B(_0261_),
    .C(\irq_status_r[4] ),
    .D(\ar_addr_lat[3] ),
    .Y(_0333_));
 sky130_fd_sc_hd__nand4_2 _0819_ (.A(\irq_mask_r[4] ),
    .B(\ar_addr_lat[3] ),
    .C(\ar_addr_lat[2] ),
    .D(_0261_),
    .Y(_0334_));
 sky130_fd_sc_hd__nand2_2 _0820_ (.A(_0333_),
    .B(_0334_),
    .Y(_0335_));
 sky130_fd_sc_hd__a21oi_2 _0821_ (.A1(_0335_),
    .A2(_0279_),
    .B1(_0248_),
    .Y(_0336_));
 sky130_fd_sc_hd__a2bb2oi_2 _0822_ (.A1_N(_0138_),
    .A2_N(_0277_),
    .B1(_0288_),
    .B2(dcache_writes[4]),
    .Y(_0337_));
 sky130_fd_sc_hd__a31oi_2 _0823_ (.A1(_0337_),
    .A2(_0332_),
    .A3(_0336_),
    .B1(_0326_),
    .Y(_0044_));
 sky130_fd_sc_hd__nor2_2 _0824_ (.A(S_AXI_RDATA[5]),
    .B(_0247_),
    .Y(_0338_));
 sky130_fd_sc_hd__nand4_2 _0825_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[5]),
    .Y(_0339_));
 sky130_fd_sc_hd__nand4_2 _0826_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[5]),
    .Y(_0340_));
 sky130_fd_sc_hd__nand4_2 _0827_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[5]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0341_));
 sky130_fd_sc_hd__nand4_2 _0828_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[5]),
    .D(_0261_),
    .Y(_0342_));
 sky130_fd_sc_hd__a41o_2 _0829_ (.A1(_0339_),
    .A2(_0340_),
    .A3(_0341_),
    .A4(_0342_),
    .B1(_0260_),
    .X(_0343_));
 sky130_fd_sc_hd__a41oi_2 _0830_ (.A1(\cycle_cnt_r[5] ),
    .A2(_0256_),
    .A3(_0270_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0344_));
 sky130_fd_sc_hd__nand4_2 _0831_ (.A(_0145_),
    .B(_0261_),
    .C(\irq_status_r[5] ),
    .D(\ar_addr_lat[3] ),
    .Y(_0345_));
 sky130_fd_sc_hd__nand4_2 _0832_ (.A(\irq_mask_r[5] ),
    .B(\ar_addr_lat[3] ),
    .C(\ar_addr_lat[2] ),
    .D(_0261_),
    .Y(_0346_));
 sky130_fd_sc_hd__a21oi_2 _0833_ (.A1(_0345_),
    .A2(_0346_),
    .B1(_0280_),
    .Y(_0347_));
 sky130_fd_sc_hd__a21oi_2 _0834_ (.A1(dcache_writes[5]),
    .A2(_0288_),
    .B1(_0347_),
    .Y(_0348_));
 sky130_fd_sc_hd__a31oi_2 _0835_ (.A1(_0348_),
    .A2(_0343_),
    .A3(_0344_),
    .B1(_0338_),
    .Y(_0045_));
 sky130_fd_sc_hd__nand2_2 _0836_ (.A(dcache_misses[6]),
    .B(_0264_),
    .Y(_0349_));
 sky130_fd_sc_hd__nand2_2 _0837_ (.A(icache_hits[6]),
    .B(_0267_),
    .Y(_0350_));
 sky130_fd_sc_hd__nand4_2 _0838_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[6]),
    .Y(_0351_));
 sky130_fd_sc_hd__nand4_2 _0839_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[6]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0352_));
 sky130_fd_sc_hd__a41oi_2 _0840_ (.A1(_0349_),
    .A2(_0350_),
    .A3(_0351_),
    .A4(_0352_),
    .B1(_0260_),
    .Y(_0353_));
 sky130_fd_sc_hd__nand4_2 _0841_ (.A(dcache_writes[6]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0354_));
 sky130_fd_sc_hd__nand4_2 _0842_ (.A(\cycle_cnt_r[6] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0355_));
 sky130_fd_sc_hd__nand3_2 _0843_ (.A(_0354_),
    .B(_0355_),
    .C(_0247_),
    .Y(_0356_));
 sky130_fd_sc_hd__o22a_2 _0844_ (.A1(S_AXI_RDATA[6]),
    .A2(_0247_),
    .B1(_0356_),
    .B2(_0353_),
    .X(_0046_));
 sky130_fd_sc_hd__nand2_2 _0845_ (.A(dcache_misses[7]),
    .B(_0264_),
    .Y(_0357_));
 sky130_fd_sc_hd__nand2_2 _0846_ (.A(icache_misses[7]),
    .B(_0270_),
    .Y(_0358_));
 sky130_fd_sc_hd__nand4_2 _0847_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[7]),
    .Y(_0359_));
 sky130_fd_sc_hd__nand4_2 _0848_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[7]),
    .Y(_0360_));
 sky130_fd_sc_hd__a41oi_2 _0849_ (.A1(_0357_),
    .A2(_0358_),
    .A3(_0359_),
    .A4(_0360_),
    .B1(_0260_),
    .Y(_0361_));
 sky130_fd_sc_hd__nand4_2 _0850_ (.A(\cycle_cnt_r[7] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0362_));
 sky130_fd_sc_hd__nand4_2 _0851_ (.A(dcache_writes[7]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0363_));
 sky130_fd_sc_hd__nand3_2 _0852_ (.A(_0362_),
    .B(_0363_),
    .C(_0247_),
    .Y(_0364_));
 sky130_fd_sc_hd__o22a_2 _0853_ (.A1(S_AXI_RDATA[7]),
    .A2(_0247_),
    .B1(_0364_),
    .B2(_0361_),
    .X(_0047_));
 sky130_fd_sc_hd__nand2_2 _0854_ (.A(dcache_misses[8]),
    .B(_0264_),
    .Y(_0365_));
 sky130_fd_sc_hd__nand2_2 _0855_ (.A(icache_hits[8]),
    .B(_0267_),
    .Y(_0366_));
 sky130_fd_sc_hd__nand4_2 _0856_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[8]),
    .Y(_0367_));
 sky130_fd_sc_hd__nand4_2 _0857_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[8]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0368_));
 sky130_fd_sc_hd__a41oi_2 _0858_ (.A1(_0365_),
    .A2(_0366_),
    .A3(_0367_),
    .A4(_0368_),
    .B1(_0260_),
    .Y(_0369_));
 sky130_fd_sc_hd__nand4_2 _0859_ (.A(dcache_writes[8]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0370_));
 sky130_fd_sc_hd__nand4_2 _0860_ (.A(\cycle_cnt_r[8] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0371_));
 sky130_fd_sc_hd__nand3_2 _0861_ (.A(_0370_),
    .B(_0371_),
    .C(_0247_),
    .Y(_0372_));
 sky130_fd_sc_hd__o22a_2 _0862_ (.A1(S_AXI_RDATA[8]),
    .A2(_0247_),
    .B1(_0372_),
    .B2(_0369_),
    .X(_0048_));
 sky130_fd_sc_hd__nand2_2 _0863_ (.A(dcache_misses[9]),
    .B(_0264_),
    .Y(_0373_));
 sky130_fd_sc_hd__nand2_2 _0864_ (.A(icache_hits[9]),
    .B(_0267_),
    .Y(_0374_));
 sky130_fd_sc_hd__nand4_2 _0865_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[9]),
    .Y(_0375_));
 sky130_fd_sc_hd__nand4_2 _0866_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[9]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0376_));
 sky130_fd_sc_hd__a41oi_2 _0867_ (.A1(_0373_),
    .A2(_0374_),
    .A3(_0375_),
    .A4(_0376_),
    .B1(_0260_),
    .Y(_0377_));
 sky130_fd_sc_hd__nand4_2 _0868_ (.A(dcache_writes[9]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0378_));
 sky130_fd_sc_hd__nand4_2 _0869_ (.A(\cycle_cnt_r[9] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0379_));
 sky130_fd_sc_hd__nand3_2 _0870_ (.A(_0378_),
    .B(_0379_),
    .C(_0247_),
    .Y(_0380_));
 sky130_fd_sc_hd__o22a_2 _0871_ (.A1(S_AXI_RDATA[9]),
    .A2(_0247_),
    .B1(_0380_),
    .B2(_0377_),
    .X(_0049_));
 sky130_fd_sc_hd__nand2_2 _0872_ (.A(dcache_misses[10]),
    .B(_0264_),
    .Y(_0381_));
 sky130_fd_sc_hd__nand2_2 _0873_ (.A(icache_hits[10]),
    .B(_0267_),
    .Y(_0382_));
 sky130_fd_sc_hd__nand4_2 _0874_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[10]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0383_));
 sky130_fd_sc_hd__nand4_2 _0875_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[10]),
    .Y(_0384_));
 sky130_fd_sc_hd__a41oi_2 _0876_ (.A1(_0381_),
    .A2(_0382_),
    .A3(_0383_),
    .A4(_0384_),
    .B1(_0260_),
    .Y(_0385_));
 sky130_fd_sc_hd__nand4_2 _0877_ (.A(dcache_writes[10]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0386_));
 sky130_fd_sc_hd__nand4_2 _0878_ (.A(\cycle_cnt_r[10] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0387_));
 sky130_fd_sc_hd__nand3_2 _0879_ (.A(_0386_),
    .B(_0387_),
    .C(_0247_),
    .Y(_0388_));
 sky130_fd_sc_hd__o22a_2 _0880_ (.A1(S_AXI_RDATA[10]),
    .A2(_0247_),
    .B1(_0388_),
    .B2(_0385_),
    .X(_0050_));
 sky130_fd_sc_hd__nand2_2 _0881_ (.A(dcache_misses[11]),
    .B(_0264_),
    .Y(_0389_));
 sky130_fd_sc_hd__nand2_2 _0882_ (.A(icache_hits[11]),
    .B(_0267_),
    .Y(_0390_));
 sky130_fd_sc_hd__nand4_2 _0883_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[11]),
    .Y(_0391_));
 sky130_fd_sc_hd__nand4_2 _0884_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[11]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0392_));
 sky130_fd_sc_hd__a41oi_2 _0885_ (.A1(_0389_),
    .A2(_0390_),
    .A3(_0391_),
    .A4(_0392_),
    .B1(_0260_),
    .Y(_0393_));
 sky130_fd_sc_hd__nand4_2 _0886_ (.A(dcache_writes[11]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0394_));
 sky130_fd_sc_hd__nand4_2 _0887_ (.A(\cycle_cnt_r[11] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0395_));
 sky130_fd_sc_hd__nand3_2 _0888_ (.A(_0394_),
    .B(_0395_),
    .C(_0247_),
    .Y(_0396_));
 sky130_fd_sc_hd__o22a_2 _0889_ (.A1(S_AXI_RDATA[11]),
    .A2(_0247_),
    .B1(_0396_),
    .B2(_0393_),
    .X(_0051_));
 sky130_fd_sc_hd__nand2_2 _0890_ (.A(dcache_misses[12]),
    .B(_0264_),
    .Y(_0397_));
 sky130_fd_sc_hd__nand2_2 _0891_ (.A(icache_hits[12]),
    .B(_0267_),
    .Y(_0398_));
 sky130_fd_sc_hd__nand4_2 _0892_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[12]),
    .Y(_0399_));
 sky130_fd_sc_hd__nand4_2 _0893_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[12]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0400_));
 sky130_fd_sc_hd__a41oi_2 _0894_ (.A1(_0397_),
    .A2(_0398_),
    .A3(_0399_),
    .A4(_0400_),
    .B1(_0260_),
    .Y(_0401_));
 sky130_fd_sc_hd__nand4_2 _0895_ (.A(dcache_writes[12]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0402_));
 sky130_fd_sc_hd__nand4_2 _0896_ (.A(\cycle_cnt_r[12] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0403_));
 sky130_fd_sc_hd__nand3_2 _0897_ (.A(_0402_),
    .B(_0403_),
    .C(_0247_),
    .Y(_0404_));
 sky130_fd_sc_hd__o22a_2 _0898_ (.A1(S_AXI_RDATA[12]),
    .A2(_0247_),
    .B1(_0404_),
    .B2(_0401_),
    .X(_0052_));
 sky130_fd_sc_hd__nand2_2 _0899_ (.A(dcache_misses[13]),
    .B(_0264_),
    .Y(_0405_));
 sky130_fd_sc_hd__nand2_2 _0900_ (.A(icache_hits[13]),
    .B(_0267_),
    .Y(_0406_));
 sky130_fd_sc_hd__nand4_2 _0901_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[13]),
    .Y(_0407_));
 sky130_fd_sc_hd__nand4_2 _0902_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[13]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0408_));
 sky130_fd_sc_hd__a41oi_2 _0903_ (.A1(_0405_),
    .A2(_0406_),
    .A3(_0407_),
    .A4(_0408_),
    .B1(_0260_),
    .Y(_0409_));
 sky130_fd_sc_hd__nand4_2 _0904_ (.A(dcache_writes[13]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0410_));
 sky130_fd_sc_hd__nand4_2 _0905_ (.A(\cycle_cnt_r[13] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0411_));
 sky130_fd_sc_hd__nand3_2 _0906_ (.A(_0410_),
    .B(_0411_),
    .C(_0247_),
    .Y(_0412_));
 sky130_fd_sc_hd__o22a_2 _0907_ (.A1(S_AXI_RDATA[13]),
    .A2(_0247_),
    .B1(_0412_),
    .B2(_0409_),
    .X(_0053_));
 sky130_fd_sc_hd__nor2_2 _0908_ (.A(S_AXI_RDATA[14]),
    .B(_0247_),
    .Y(_0413_));
 sky130_fd_sc_hd__nand4_2 _0909_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[14]),
    .D(_0261_),
    .Y(_0414_));
 sky130_fd_sc_hd__nand4_2 _0910_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[14]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0415_));
 sky130_fd_sc_hd__nand4_2 _0911_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[14]),
    .Y(_0416_));
 sky130_fd_sc_hd__nand4_2 _0912_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[14]),
    .Y(_0417_));
 sky130_fd_sc_hd__a41o_2 _0913_ (.A1(_0414_),
    .A2(_0415_),
    .A3(_0416_),
    .A4(_0417_),
    .B1(_0260_),
    .X(_0418_));
 sky130_fd_sc_hd__nand2_2 _0914_ (.A(dcache_writes[14]),
    .B(_0288_),
    .Y(_0419_));
 sky130_fd_sc_hd__a41oi_2 _0915_ (.A1(\cycle_cnt_r[14] ),
    .A2(_0256_),
    .A3(_0270_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0420_));
 sky130_fd_sc_hd__a31oi_2 _0916_ (.A1(_0418_),
    .A2(_0420_),
    .A3(_0419_),
    .B1(_0413_),
    .Y(_0054_));
 sky130_fd_sc_hd__nand2_2 _0917_ (.A(dcache_misses[15]),
    .B(_0264_),
    .Y(_0421_));
 sky130_fd_sc_hd__nand2_2 _0918_ (.A(icache_hits[15]),
    .B(_0267_),
    .Y(_0422_));
 sky130_fd_sc_hd__nand4_2 _0919_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[15]),
    .Y(_0423_));
 sky130_fd_sc_hd__nand4_2 _0920_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[15]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0424_));
 sky130_fd_sc_hd__a41oi_2 _0921_ (.A1(_0421_),
    .A2(_0422_),
    .A3(_0423_),
    .A4(_0424_),
    .B1(_0260_),
    .Y(_0425_));
 sky130_fd_sc_hd__nand4_2 _0922_ (.A(dcache_writes[15]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0426_));
 sky130_fd_sc_hd__nand4_2 _0923_ (.A(\cycle_cnt_r[15] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0427_));
 sky130_fd_sc_hd__nand3_2 _0924_ (.A(_0426_),
    .B(_0427_),
    .C(_0247_),
    .Y(_0428_));
 sky130_fd_sc_hd__o22a_2 _0925_ (.A1(S_AXI_RDATA[15]),
    .A2(_0247_),
    .B1(_0428_),
    .B2(_0425_),
    .X(_0055_));
 sky130_fd_sc_hd__nor2_2 _0926_ (.A(S_AXI_RDATA[16]),
    .B(_0247_),
    .Y(_0429_));
 sky130_fd_sc_hd__nand2_2 _0927_ (.A(icache_hits[16]),
    .B(_0267_),
    .Y(_0430_));
 sky130_fd_sc_hd__nand4_2 _0928_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[16]),
    .D(_0261_),
    .Y(_0431_));
 sky130_fd_sc_hd__nand4_2 _0929_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[16]),
    .Y(_0432_));
 sky130_fd_sc_hd__nand4_2 _0930_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[16]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0433_));
 sky130_fd_sc_hd__a41o_2 _0931_ (.A1(_0430_),
    .A2(_0431_),
    .A3(_0432_),
    .A4(_0433_),
    .B1(_0260_),
    .X(_0434_));
 sky130_fd_sc_hd__nand4_2 _0932_ (.A(\cycle_cnt_r[16] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0435_));
 sky130_fd_sc_hd__a41oi_2 _0933_ (.A1(dcache_writes[16]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0436_));
 sky130_fd_sc_hd__a31oi_2 _0934_ (.A1(_0434_),
    .A2(_0435_),
    .A3(_0436_),
    .B1(_0429_),
    .Y(_0056_));
 sky130_fd_sc_hd__nor2_2 _0935_ (.A(S_AXI_RDATA[17]),
    .B(_0247_),
    .Y(_0437_));
 sky130_fd_sc_hd__nand4_2 _0936_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[17]),
    .Y(_0438_));
 sky130_fd_sc_hd__nand4_2 _0937_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[17]),
    .D(_0261_),
    .Y(_0439_));
 sky130_fd_sc_hd__and4_2 _0938_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[17]),
    .X(_0440_));
 sky130_fd_sc_hd__nand4_2 _0939_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[17]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0441_));
 sky130_fd_sc_hd__nand3_2 _0940_ (.A(_0438_),
    .B(_0439_),
    .C(_0441_),
    .Y(_0442_));
 sky130_fd_sc_hd__o21ai_2 _0941_ (.A1(_0440_),
    .A2(_0442_),
    .B1(_0259_),
    .Y(_0443_));
 sky130_fd_sc_hd__nand4_2 _0942_ (.A(\cycle_cnt_r[17] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0444_));
 sky130_fd_sc_hd__a41oi_2 _0943_ (.A1(dcache_writes[17]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0445_));
 sky130_fd_sc_hd__a31oi_2 _0944_ (.A1(_0443_),
    .A2(_0445_),
    .A3(_0444_),
    .B1(_0437_),
    .Y(_0057_));
 sky130_fd_sc_hd__nor2_2 _0945_ (.A(S_AXI_RDATA[18]),
    .B(_0247_),
    .Y(_0446_));
 sky130_fd_sc_hd__nand4_2 _0946_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[18]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0447_));
 sky130_fd_sc_hd__nand4_2 _0947_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[18]),
    .D(_0261_),
    .Y(_0448_));
 sky130_fd_sc_hd__and4_2 _0948_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[18]),
    .X(_0449_));
 sky130_fd_sc_hd__nand4_2 _0949_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[18]),
    .Y(_0450_));
 sky130_fd_sc_hd__nand3_2 _0950_ (.A(_0447_),
    .B(_0448_),
    .C(_0450_),
    .Y(_0451_));
 sky130_fd_sc_hd__o21ai_2 _0951_ (.A1(_0449_),
    .A2(_0451_),
    .B1(_0259_),
    .Y(_0452_));
 sky130_fd_sc_hd__nand4_2 _0952_ (.A(\cycle_cnt_r[18] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0453_));
 sky130_fd_sc_hd__a41oi_2 _0953_ (.A1(dcache_writes[18]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0454_));
 sky130_fd_sc_hd__a31oi_2 _0954_ (.A1(_0452_),
    .A2(_0454_),
    .A3(_0453_),
    .B1(_0446_),
    .Y(_0058_));
 sky130_fd_sc_hd__nand2_2 _0955_ (.A(icache_misses[19]),
    .B(_0270_),
    .Y(_0455_));
 sky130_fd_sc_hd__nand4_2 _0956_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[19]),
    .D(_0261_),
    .Y(_0456_));
 sky130_fd_sc_hd__nand4_2 _0957_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[19]),
    .Y(_0457_));
 sky130_fd_sc_hd__nand4_2 _0958_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[19]),
    .Y(_0458_));
 sky130_fd_sc_hd__a41o_2 _0959_ (.A1(_0455_),
    .A2(_0456_),
    .A3(_0457_),
    .A4(_0458_),
    .B1(_0260_),
    .X(_0459_));
 sky130_fd_sc_hd__nand4_2 _0960_ (.A(\cycle_cnt_r[19] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0460_));
 sky130_fd_sc_hd__nand4_2 _0961_ (.A(dcache_writes[19]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0461_));
 sky130_fd_sc_hd__and3_2 _0962_ (.A(_0460_),
    .B(_0461_),
    .C(_0247_),
    .X(_0462_));
 sky130_fd_sc_hd__a2bb2oi_2 _0963_ (.A1_N(S_AXI_RDATA[19]),
    .A2_N(_0247_),
    .B1(_0459_),
    .B2(_0462_),
    .Y(_0059_));
 sky130_fd_sc_hd__nand2_2 _0964_ (.A(dcache_misses[20]),
    .B(_0264_),
    .Y(_0463_));
 sky130_fd_sc_hd__nand2_2 _0965_ (.A(icache_hits[20]),
    .B(_0267_),
    .Y(_0464_));
 sky130_fd_sc_hd__nand4_2 _0966_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[20]),
    .Y(_0465_));
 sky130_fd_sc_hd__nand4_2 _0967_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[20]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0466_));
 sky130_fd_sc_hd__a41oi_2 _0968_ (.A1(_0463_),
    .A2(_0464_),
    .A3(_0465_),
    .A4(_0466_),
    .B1(_0260_),
    .Y(_0467_));
 sky130_fd_sc_hd__nand4_2 _0969_ (.A(\cycle_cnt_r[20] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0468_));
 sky130_fd_sc_hd__nand4_2 _0970_ (.A(dcache_writes[20]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0469_));
 sky130_fd_sc_hd__nand3_2 _0971_ (.A(_0468_),
    .B(_0469_),
    .C(_0247_),
    .Y(_0470_));
 sky130_fd_sc_hd__o22a_2 _0972_ (.A1(S_AXI_RDATA[20]),
    .A2(_0247_),
    .B1(_0470_),
    .B2(_0467_),
    .X(_0060_));
 sky130_fd_sc_hd__nor2_2 _0973_ (.A(S_AXI_RDATA[21]),
    .B(_0247_),
    .Y(_0471_));
 sky130_fd_sc_hd__nand4_2 _0974_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[21]),
    .D(_0261_),
    .Y(_0472_));
 sky130_fd_sc_hd__nand4_2 _0975_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[21]),
    .Y(_0473_));
 sky130_fd_sc_hd__nand4_2 _0976_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[21]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0474_));
 sky130_fd_sc_hd__nand4_2 _0977_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[21]),
    .Y(_0475_));
 sky130_fd_sc_hd__a41o_2 _0978_ (.A1(_0472_),
    .A2(_0473_),
    .A3(_0474_),
    .A4(_0475_),
    .B1(_0260_),
    .X(_0476_));
 sky130_fd_sc_hd__nand4_2 _0979_ (.A(\cycle_cnt_r[21] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0477_));
 sky130_fd_sc_hd__a41oi_2 _0980_ (.A1(dcache_writes[21]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0478_));
 sky130_fd_sc_hd__a31oi_2 _0981_ (.A1(_0476_),
    .A2(_0478_),
    .A3(_0477_),
    .B1(_0471_),
    .Y(_0061_));
 sky130_fd_sc_hd__nand2_2 _0982_ (.A(dcache_hits[22]),
    .B(_0262_),
    .Y(_0479_));
 sky130_fd_sc_hd__nand4_2 _0983_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[22]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0480_));
 sky130_fd_sc_hd__nand4_2 _0984_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[22]),
    .Y(_0481_));
 sky130_fd_sc_hd__nand4_2 _0985_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[22]),
    .D(_0261_),
    .Y(_0482_));
 sky130_fd_sc_hd__a41oi_2 _0986_ (.A1(_0479_),
    .A2(_0480_),
    .A3(_0481_),
    .A4(_0482_),
    .B1(_0260_),
    .Y(_0483_));
 sky130_fd_sc_hd__nand4_2 _0987_ (.A(\cycle_cnt_r[22] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0484_));
 sky130_fd_sc_hd__nand4_2 _0988_ (.A(dcache_writes[22]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0485_));
 sky130_fd_sc_hd__o2111ai_2 _0989_ (.A1(_0268_),
    .A2(_0280_),
    .B1(_0247_),
    .C1(_0484_),
    .D1(_0485_),
    .Y(_0486_));
 sky130_fd_sc_hd__o22a_2 _0990_ (.A1(S_AXI_RDATA[22]),
    .A2(_0247_),
    .B1(_0483_),
    .B2(_0486_),
    .X(_0062_));
 sky130_fd_sc_hd__nor2_2 _0991_ (.A(S_AXI_RDATA[23]),
    .B(_0247_),
    .Y(_0487_));
 sky130_fd_sc_hd__nand4_2 _0992_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[23]),
    .Y(_0488_));
 sky130_fd_sc_hd__nand4_2 _0993_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[23]),
    .D(_0261_),
    .Y(_0489_));
 sky130_fd_sc_hd__and3_2 _0994_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[23]),
    .C(_0266_),
    .X(_0490_));
 sky130_fd_sc_hd__nand4_2 _0995_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[23]),
    .Y(_0491_));
 sky130_fd_sc_hd__nand3_2 _0996_ (.A(_0488_),
    .B(_0489_),
    .C(_0491_),
    .Y(_0492_));
 sky130_fd_sc_hd__o21ai_2 _0997_ (.A1(_0492_),
    .A2(_0490_),
    .B1(_0259_),
    .Y(_0493_));
 sky130_fd_sc_hd__nand4_2 _0998_ (.A(\cycle_cnt_r[23] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0494_));
 sky130_fd_sc_hd__nand4_2 _0999_ (.A(dcache_writes[23]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0495_));
 sky130_fd_sc_hd__a41oi_2 _1000_ (.A1(_0493_),
    .A2(_0494_),
    .A3(_0281_),
    .A4(_0495_),
    .B1(_0487_),
    .Y(_0063_));
 sky130_fd_sc_hd__nor2_2 _1001_ (.A(S_AXI_RDATA[24]),
    .B(_0247_),
    .Y(_0496_));
 sky130_fd_sc_hd__nand4_2 _1002_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[24]),
    .Y(_0497_));
 sky130_fd_sc_hd__nand4_2 _1003_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[24]),
    .D(_0261_),
    .Y(_0498_));
 sky130_fd_sc_hd__and4_2 _1004_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[24]),
    .C(_0261_),
    .D(_0144_),
    .X(_0499_));
 sky130_fd_sc_hd__nand4_2 _1005_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[24]),
    .Y(_0500_));
 sky130_fd_sc_hd__nand3_2 _1006_ (.A(_0497_),
    .B(_0498_),
    .C(_0500_),
    .Y(_0501_));
 sky130_fd_sc_hd__o21ai_2 _1007_ (.A1(_0499_),
    .A2(_0501_),
    .B1(_0259_),
    .Y(_0502_));
 sky130_fd_sc_hd__nand4_2 _1008_ (.A(\cycle_cnt_r[24] ),
    .B(_0270_),
    .C(_0273_),
    .D(_0282_),
    .Y(_0503_));
 sky130_fd_sc_hd__nand4_2 _1009_ (.A(dcache_writes[24]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0504_));
 sky130_fd_sc_hd__a41oi_2 _1010_ (.A1(_0281_),
    .A2(_0502_),
    .A3(_0503_),
    .A4(_0504_),
    .B1(_0496_),
    .Y(_0064_));
 sky130_fd_sc_hd__nor2_2 _1011_ (.A(S_AXI_RDATA[25]),
    .B(_0247_),
    .Y(_0505_));
 sky130_fd_sc_hd__nand4_2 _1012_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[25]),
    .Y(_0506_));
 sky130_fd_sc_hd__nand4_2 _1013_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[25]),
    .D(_0261_),
    .Y(_0507_));
 sky130_fd_sc_hd__and4_2 _1014_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[25]),
    .X(_0508_));
 sky130_fd_sc_hd__nand4_2 _1015_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[25]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0509_));
 sky130_fd_sc_hd__nand3_2 _1016_ (.A(_0506_),
    .B(_0507_),
    .C(_0509_),
    .Y(_0510_));
 sky130_fd_sc_hd__o21ai_2 _1017_ (.A1(_0508_),
    .A2(_0510_),
    .B1(_0259_),
    .Y(_0511_));
 sky130_fd_sc_hd__a41oi_2 _1018_ (.A1(dcache_writes[25]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0512_));
 sky130_fd_sc_hd__nand4_2 _1019_ (.A(\cycle_cnt_r[25] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0513_));
 sky130_fd_sc_hd__a31oi_2 _1020_ (.A1(_0511_),
    .A2(_0512_),
    .A3(_0513_),
    .B1(_0505_),
    .Y(_0065_));
 sky130_fd_sc_hd__nor2_2 _1021_ (.A(S_AXI_RDATA[26]),
    .B(_0247_),
    .Y(_0514_));
 sky130_fd_sc_hd__nand4_2 _1022_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[26]),
    .Y(_0515_));
 sky130_fd_sc_hd__nand4_2 _1023_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[26]),
    .D(_0261_),
    .Y(_0516_));
 sky130_fd_sc_hd__and4_2 _1024_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[26]),
    .X(_0517_));
 sky130_fd_sc_hd__nand4_2 _1025_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[26]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0518_));
 sky130_fd_sc_hd__nand3_2 _1026_ (.A(_0515_),
    .B(_0516_),
    .C(_0518_),
    .Y(_0519_));
 sky130_fd_sc_hd__o21ai_2 _1027_ (.A1(_0517_),
    .A2(_0519_),
    .B1(_0259_),
    .Y(_0520_));
 sky130_fd_sc_hd__and3_2 _1028_ (.A(_0266_),
    .B(_0145_),
    .C(dcache_writes[26]),
    .X(_0521_));
 sky130_fd_sc_hd__and3_2 _1029_ (.A(\cycle_cnt_r[26] ),
    .B(\ar_addr_lat[2] ),
    .C(_0266_),
    .X(_0522_));
 sky130_fd_sc_hd__o21ai_2 _1030_ (.A1(_0521_),
    .A2(_0522_),
    .B1(_0283_),
    .Y(_0523_));
 sky130_fd_sc_hd__a31oi_2 _1031_ (.A1(_0520_),
    .A2(_0523_),
    .A3(_0281_),
    .B1(_0514_),
    .Y(_0066_));
 sky130_fd_sc_hd__nand3_2 _1032_ (.A(\cycle_cnt_r[27] ),
    .B(_0261_),
    .C(_0144_),
    .Y(_0524_));
 sky130_fd_sc_hd__o2bb2ai_2 _1033_ (.A1_N(dcache_writes[27]),
    .A2_N(_0267_),
    .B1(_0524_),
    .B2(_0145_),
    .Y(_0525_));
 sky130_fd_sc_hd__a21oi_2 _1034_ (.A1(_0283_),
    .A2(_0525_),
    .B1(_0248_),
    .Y(_0526_));
 sky130_fd_sc_hd__nand2_2 _1035_ (.A(dcache_hits[27]),
    .B(_0262_),
    .Y(_0527_));
 sky130_fd_sc_hd__nand2_2 _1036_ (.A(icache_misses[27]),
    .B(_0270_),
    .Y(_0528_));
 sky130_fd_sc_hd__nand2_2 _1037_ (.A(dcache_misses[27]),
    .B(_0264_),
    .Y(_0529_));
 sky130_fd_sc_hd__nand2_2 _1038_ (.A(icache_hits[27]),
    .B(_0267_),
    .Y(_0530_));
 sky130_fd_sc_hd__nand4_2 _1039_ (.A(_0527_),
    .B(_0528_),
    .C(_0529_),
    .D(_0530_),
    .Y(_0531_));
 sky130_fd_sc_hd__nand2_2 _1040_ (.A(_0531_),
    .B(_0259_),
    .Y(_0532_));
 sky130_fd_sc_hd__a2bb2oi_2 _1041_ (.A1_N(S_AXI_RDATA[27]),
    .A2_N(_0247_),
    .B1(_0526_),
    .B2(_0532_),
    .Y(_0067_));
 sky130_fd_sc_hd__nor2_2 _1042_ (.A(S_AXI_RDATA[28]),
    .B(_0247_),
    .Y(_0533_));
 sky130_fd_sc_hd__nand4_2 _1043_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[28]),
    .Y(_0534_));
 sky130_fd_sc_hd__nand4_2 _1044_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[28]),
    .D(_0261_),
    .Y(_0535_));
 sky130_fd_sc_hd__and4_2 _1045_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[28]),
    .X(_0536_));
 sky130_fd_sc_hd__nand4_2 _1046_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[28]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0537_));
 sky130_fd_sc_hd__nand3_2 _1047_ (.A(_0534_),
    .B(_0535_),
    .C(_0537_),
    .Y(_0538_));
 sky130_fd_sc_hd__o21ai_2 _1048_ (.A1(_0536_),
    .A2(_0538_),
    .B1(_0259_),
    .Y(_0539_));
 sky130_fd_sc_hd__nand4_2 _1049_ (.A(\cycle_cnt_r[28] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0540_));
 sky130_fd_sc_hd__a41oi_2 _1050_ (.A1(dcache_writes[28]),
    .A2(_0256_),
    .A3(_0267_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0541_));
 sky130_fd_sc_hd__a31oi_2 _1051_ (.A1(_0539_),
    .A2(_0541_),
    .A3(_0540_),
    .B1(_0533_),
    .Y(_0068_));
 sky130_fd_sc_hd__nor2_2 _1052_ (.A(S_AXI_RDATA[29]),
    .B(_0247_),
    .Y(_0542_));
 sky130_fd_sc_hd__nand4_2 _1053_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[29]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0543_));
 sky130_fd_sc_hd__nand4_2 _1054_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[29]),
    .D(_0261_),
    .Y(_0544_));
 sky130_fd_sc_hd__and3_2 _1055_ (.A(_0266_),
    .B(_0145_),
    .C(icache_hits[29]),
    .X(_0545_));
 sky130_fd_sc_hd__nand4_2 _1056_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[29]),
    .Y(_0546_));
 sky130_fd_sc_hd__nand3_2 _1057_ (.A(_0543_),
    .B(_0544_),
    .C(_0546_),
    .Y(_0547_));
 sky130_fd_sc_hd__o21ai_2 _1058_ (.A1(_0545_),
    .A2(_0547_),
    .B1(_0259_),
    .Y(_0548_));
 sky130_fd_sc_hd__nand4_2 _1059_ (.A(\cycle_cnt_r[29] ),
    .B(_0270_),
    .C(_0273_),
    .D(_0282_),
    .Y(_0549_));
 sky130_fd_sc_hd__nand4_2 _1060_ (.A(dcache_writes[29]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0550_));
 sky130_fd_sc_hd__a41oi_2 _1061_ (.A1(_0281_),
    .A2(_0548_),
    .A3(_0549_),
    .A4(_0550_),
    .B1(_0542_),
    .Y(_0069_));
 sky130_fd_sc_hd__nor2_2 _1062_ (.A(S_AXI_RDATA[30]),
    .B(_0247_),
    .Y(_0551_));
 sky130_fd_sc_hd__nand4_2 _1063_ (.A(\ar_addr_lat[2] ),
    .B(icache_misses[30]),
    .C(_0261_),
    .D(_0144_),
    .Y(_0552_));
 sky130_fd_sc_hd__nand4_2 _1064_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[30]),
    .D(_0261_),
    .Y(_0553_));
 sky130_fd_sc_hd__and4_2 _1065_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[30]),
    .X(_0554_));
 sky130_fd_sc_hd__nand4_2 _1066_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[30]),
    .Y(_0555_));
 sky130_fd_sc_hd__nand3_2 _1067_ (.A(_0552_),
    .B(_0553_),
    .C(_0555_),
    .Y(_0556_));
 sky130_fd_sc_hd__o21ai_2 _1068_ (.A1(_0554_),
    .A2(_0556_),
    .B1(_0259_),
    .Y(_0557_));
 sky130_fd_sc_hd__a41oi_2 _1069_ (.A1(\cycle_cnt_r[30] ),
    .A2(_0256_),
    .A3(_0270_),
    .A4(_0275_),
    .B1(_0248_),
    .Y(_0558_));
 sky130_fd_sc_hd__nand2_2 _1070_ (.A(dcache_writes[30]),
    .B(_0288_),
    .Y(_0559_));
 sky130_fd_sc_hd__a31oi_2 _1071_ (.A1(_0557_),
    .A2(_0558_),
    .A3(_0559_),
    .B1(_0551_),
    .Y(_0070_));
 sky130_fd_sc_hd__nor2_2 _1072_ (.A(S_AXI_RDATA[31]),
    .B(_0247_),
    .Y(_0560_));
 sky130_fd_sc_hd__nand2_2 _1073_ (.A(icache_misses[31]),
    .B(_0270_),
    .Y(_0561_));
 sky130_fd_sc_hd__nand4_2 _1074_ (.A(\ar_addr_lat[3] ),
    .B(\ar_addr_lat[2] ),
    .C(dcache_misses[31]),
    .D(_0261_),
    .Y(_0562_));
 sky130_fd_sc_hd__nand4_2 _1075_ (.A(_0261_),
    .B(_0145_),
    .C(_0144_),
    .D(icache_hits[31]),
    .Y(_0563_));
 sky130_fd_sc_hd__nand4_2 _1076_ (.A(\ar_addr_lat[3] ),
    .B(_0261_),
    .C(_0145_),
    .D(dcache_hits[31]),
    .Y(_0564_));
 sky130_fd_sc_hd__nand4_2 _1077_ (.A(_0561_),
    .B(_0562_),
    .C(_0563_),
    .D(_0564_),
    .Y(_0565_));
 sky130_fd_sc_hd__nand2_2 _1078_ (.A(_0565_),
    .B(_0259_),
    .Y(_0566_));
 sky130_fd_sc_hd__nand4_2 _1079_ (.A(\cycle_cnt_r[31] ),
    .B(_0256_),
    .C(_0270_),
    .D(_0275_),
    .Y(_0567_));
 sky130_fd_sc_hd__nand4_2 _1080_ (.A(dcache_writes[31]),
    .B(_0256_),
    .C(_0267_),
    .D(_0275_),
    .Y(_0568_));
 sky130_fd_sc_hd__a41oi_2 _1081_ (.A1(_0566_),
    .A2(_0567_),
    .A3(_0281_),
    .A4(_0568_),
    .B1(_0560_),
    .Y(_0071_));
 sky130_fd_sc_hd__and2_2 _1082_ (.A(S_AXI_ARREADY),
    .B(S_AXI_ARVALID),
    .X(_0569_));
 sky130_fd_sc_hd__mux2_1 _1083_ (.A0(S_AXI_RID[0]),
    .A1(S_AXI_ARID[0]),
    .S(_0569_),
    .X(_0072_));
 sky130_fd_sc_hd__mux2_1 _1084_ (.A0(S_AXI_RID[1]),
    .A1(S_AXI_ARID[1]),
    .S(_0569_),
    .X(_0073_));
 sky130_fd_sc_hd__mux2_1 _1085_ (.A0(S_AXI_RID[2]),
    .A1(S_AXI_ARID[2]),
    .S(_0569_),
    .X(_0074_));
 sky130_fd_sc_hd__mux2_1 _1086_ (.A0(S_AXI_RID[3]),
    .A1(S_AXI_ARID[3]),
    .S(_0569_),
    .X(_0075_));
 sky130_fd_sc_hd__mux2_1 _1087_ (.A0(\ar_addr_lat[0] ),
    .A1(S_AXI_ARADDR[0]),
    .S(_0569_),
    .X(_0076_));
 sky130_fd_sc_hd__mux2_1 _1088_ (.A0(\ar_addr_lat[1] ),
    .A1(S_AXI_ARADDR[1]),
    .S(_0569_),
    .X(_0077_));
 sky130_fd_sc_hd__mux2_1 _1089_ (.A0(\ar_addr_lat[2] ),
    .A1(S_AXI_ARADDR[2]),
    .S(_0569_),
    .X(_0078_));
 sky130_fd_sc_hd__mux2_1 _1090_ (.A0(\ar_addr_lat[3] ),
    .A1(S_AXI_ARADDR[3]),
    .S(_0569_),
    .X(_0079_));
 sky130_fd_sc_hd__mux2_1 _1091_ (.A0(\ar_addr_lat[4] ),
    .A1(S_AXI_ARADDR[4]),
    .S(_0569_),
    .X(_0080_));
 sky130_fd_sc_hd__mux2_1 _1092_ (.A0(\ar_addr_lat[5] ),
    .A1(S_AXI_ARADDR[5]),
    .S(_0569_),
    .X(_0081_));
 sky130_fd_sc_hd__mux2_1 _1093_ (.A0(\ar_addr_lat[6] ),
    .A1(S_AXI_ARADDR[6]),
    .S(_0569_),
    .X(_0082_));
 sky130_fd_sc_hd__mux2_1 _1094_ (.A0(\ar_addr_lat[7] ),
    .A1(S_AXI_ARADDR[7]),
    .S(_0569_),
    .X(_0083_));
 sky130_fd_sc_hd__mux2_1 _1095_ (.A0(\ar_addr_lat[8] ),
    .A1(S_AXI_ARADDR[8]),
    .S(_0569_),
    .X(_0084_));
 sky130_fd_sc_hd__mux2_1 _1096_ (.A0(\ar_addr_lat[9] ),
    .A1(S_AXI_ARADDR[9]),
    .S(_0569_),
    .X(_0085_));
 sky130_fd_sc_hd__mux2_1 _1097_ (.A0(\ar_addr_lat[10] ),
    .A1(S_AXI_ARADDR[10]),
    .S(_0569_),
    .X(_0086_));
 sky130_fd_sc_hd__mux2_1 _1098_ (.A0(\ar_addr_lat[11] ),
    .A1(S_AXI_ARADDR[11]),
    .S(_0569_),
    .X(_0087_));
 sky130_fd_sc_hd__o2bb2a_2 _1099_ (.A1_N(S_AXI_RVALID),
    .A2_N(S_AXI_RREADY),
    .B1(S_AXI_ARVALID),
    .B2(ar_done),
    .X(_0088_));
 sky130_fd_sc_hd__a21oi_2 _1100_ (.A1(aw_done),
    .A2(w_done),
    .B1(S_AXI_BVALID),
    .Y(_0570_));
 sky130_fd_sc_hd__a21oi_2 _1101_ (.A1(S_AXI_BREADY),
    .A2(S_AXI_BVALID),
    .B1(_0570_),
    .Y(_0089_));
 sky130_fd_sc_hd__o2bb2a_2 _1102_ (.A1_N(S_AXI_BREADY),
    .A2_N(S_AXI_BVALID),
    .B1(w_done),
    .B2(S_AXI_WVALID),
    .X(_0090_));
 sky130_fd_sc_hd__and2_2 _1103_ (.A(S_AXI_WREADY),
    .B(S_AXI_WVALID),
    .X(_0571_));
 sky130_fd_sc_hd__mux2_1 _1104_ (.A0(\w_data_lat[0] ),
    .A1(S_AXI_WDATA[0]),
    .S(_0571_),
    .X(_0091_));
 sky130_fd_sc_hd__mux2_1 _1105_ (.A0(\w_data_lat[1] ),
    .A1(S_AXI_WDATA[1]),
    .S(_0571_),
    .X(_0092_));
 sky130_fd_sc_hd__mux2_1 _1106_ (.A0(\w_data_lat[2] ),
    .A1(S_AXI_WDATA[2]),
    .S(_0571_),
    .X(_0093_));
 sky130_fd_sc_hd__mux2_1 _1107_ (.A0(\w_data_lat[3] ),
    .A1(S_AXI_WDATA[3]),
    .S(_0571_),
    .X(_0094_));
 sky130_fd_sc_hd__mux2_1 _1108_ (.A0(\w_data_lat[4] ),
    .A1(S_AXI_WDATA[4]),
    .S(_0571_),
    .X(_0095_));
 sky130_fd_sc_hd__mux2_1 _1109_ (.A0(\w_data_lat[5] ),
    .A1(S_AXI_WDATA[5]),
    .S(_0571_),
    .X(_0096_));
 sky130_fd_sc_hd__mux2_1 _1110_ (.A0(\w_strb_lat[0] ),
    .A1(S_AXI_WSTRB[0]),
    .S(_0571_),
    .X(_0097_));
 sky130_fd_sc_hd__and2_2 _1111_ (.A(S_AXI_AWREADY),
    .B(S_AXI_AWVALID),
    .X(_0122_));
 sky130_fd_sc_hd__mux2_1 _1112_ (.A0(S_AXI_BID[0]),
    .A1(S_AXI_AWID[0]),
    .S(_0122_),
    .X(_0098_));
 sky130_fd_sc_hd__mux2_1 _1113_ (.A0(S_AXI_BID[1]),
    .A1(S_AXI_AWID[1]),
    .S(_0122_),
    .X(_0099_));
 sky130_fd_sc_hd__mux2_1 _1114_ (.A0(S_AXI_BID[2]),
    .A1(S_AXI_AWID[2]),
    .S(_0122_),
    .X(_0100_));
 sky130_fd_sc_hd__mux2_1 _1115_ (.A0(S_AXI_BID[3]),
    .A1(S_AXI_AWID[3]),
    .S(_0122_),
    .X(_0101_));
 sky130_fd_sc_hd__mux2_1 _1116_ (.A0(\aw_addr_lat[0] ),
    .A1(S_AXI_AWADDR[0]),
    .S(_0122_),
    .X(_0102_));
 sky130_fd_sc_hd__mux2_1 _1117_ (.A0(\aw_addr_lat[1] ),
    .A1(S_AXI_AWADDR[1]),
    .S(_0122_),
    .X(_0103_));
 sky130_fd_sc_hd__mux2_1 _1118_ (.A0(\aw_addr_lat[2] ),
    .A1(S_AXI_AWADDR[2]),
    .S(_0122_),
    .X(_0104_));
 sky130_fd_sc_hd__mux2_1 _1119_ (.A0(\aw_addr_lat[3] ),
    .A1(S_AXI_AWADDR[3]),
    .S(_0122_),
    .X(_0105_));
 sky130_fd_sc_hd__mux2_1 _1120_ (.A0(\aw_addr_lat[4] ),
    .A1(S_AXI_AWADDR[4]),
    .S(_0122_),
    .X(_0106_));
 sky130_fd_sc_hd__mux2_1 _1121_ (.A0(\aw_addr_lat[5] ),
    .A1(S_AXI_AWADDR[5]),
    .S(_0122_),
    .X(_0107_));
 sky130_fd_sc_hd__mux2_1 _1122_ (.A0(\aw_addr_lat[6] ),
    .A1(S_AXI_AWADDR[6]),
    .S(_0122_),
    .X(_0108_));
 sky130_fd_sc_hd__mux2_1 _1123_ (.A0(\aw_addr_lat[7] ),
    .A1(S_AXI_AWADDR[7]),
    .S(_0122_),
    .X(_0109_));
 sky130_fd_sc_hd__mux2_1 _1124_ (.A0(\aw_addr_lat[8] ),
    .A1(S_AXI_AWADDR[8]),
    .S(_0122_),
    .X(_0110_));
 sky130_fd_sc_hd__mux2_1 _1125_ (.A0(\aw_addr_lat[9] ),
    .A1(S_AXI_AWADDR[9]),
    .S(_0122_),
    .X(_0111_));
 sky130_fd_sc_hd__mux2_1 _1126_ (.A0(\aw_addr_lat[10] ),
    .A1(S_AXI_AWADDR[10]),
    .S(_0122_),
    .X(_0112_));
 sky130_fd_sc_hd__mux2_1 _1127_ (.A0(\aw_addr_lat[11] ),
    .A1(S_AXI_AWADDR[11]),
    .S(_0122_),
    .X(_0113_));
 sky130_fd_sc_hd__o2bb2a_2 _1128_ (.A1_N(S_AXI_BREADY),
    .A2_N(S_AXI_BVALID),
    .B1(S_AXI_AWVALID),
    .B2(aw_done),
    .X(_0114_));
 sky130_fd_sc_hd__and3_2 _1129_ (.A(\aw_addr_lat[2] ),
    .B(\aw_addr_lat[3] ),
    .C(_0236_),
    .X(_0123_));
 sky130_fd_sc_hd__nand3_2 _1130_ (.A(\aw_addr_lat[2] ),
    .B(\aw_addr_lat[3] ),
    .C(_0236_),
    .Y(_0124_));
 sky130_fd_sc_hd__nor2_2 _1131_ (.A(_0235_),
    .B(_0124_),
    .Y(_0125_));
 sky130_fd_sc_hd__o21a_2 _1132_ (.A1(_0235_),
    .A2(_0124_),
    .B1(\irq_mask_r[0] ),
    .X(_0126_));
 sky130_fd_sc_hd__a21o_2 _1133_ (.A1(\w_data_lat[0] ),
    .A2(_0125_),
    .B1(_0126_),
    .X(_0115_));
 sky130_fd_sc_hd__o21bai_2 _1134_ (.A1(_0235_),
    .A2(_0124_),
    .B1_N(\irq_mask_r[1] ),
    .Y(_0127_));
 sky130_fd_sc_hd__o31a_2 _1135_ (.A1(\w_data_lat[1] ),
    .A2(_0235_),
    .A3(_0124_),
    .B1(_0127_),
    .X(_0116_));
 sky130_fd_sc_hd__o21a_2 _1136_ (.A1(_0235_),
    .A2(_0124_),
    .B1(\irq_mask_r[2] ),
    .X(_0128_));
 sky130_fd_sc_hd__a31o_2 _1137_ (.A1(\w_data_lat[2] ),
    .A2(_0239_),
    .A3(_0123_),
    .B1(_0128_),
    .X(_0117_));
 sky130_fd_sc_hd__o21a_2 _1138_ (.A1(_0235_),
    .A2(_0124_),
    .B1(\irq_mask_r[3] ),
    .X(_0129_));
 sky130_fd_sc_hd__a31o_2 _1139_ (.A1(\w_data_lat[3] ),
    .A2(_0239_),
    .A3(_0123_),
    .B1(_0129_),
    .X(_0118_));
 sky130_fd_sc_hd__o21a_2 _1140_ (.A1(_0235_),
    .A2(_0124_),
    .B1(\irq_mask_r[4] ),
    .X(_0130_));
 sky130_fd_sc_hd__a31o_2 _1141_ (.A1(\w_data_lat[4] ),
    .A2(_0239_),
    .A3(_0123_),
    .B1(_0130_),
    .X(_0119_));
 sky130_fd_sc_hd__o21a_2 _1142_ (.A1(_0235_),
    .A2(_0124_),
    .B1(\irq_mask_r[5] ),
    .X(_0131_));
 sky130_fd_sc_hd__a31o_2 _1143_ (.A1(\w_data_lat[5] ),
    .A2(_0239_),
    .A3(_0123_),
    .B1(_0131_),
    .X(_0120_));
 sky130_fd_sc_hd__o21ba_2 _1144_ (.A1(\aw_addr_lat[2] ),
    .A2(\aw_addr_lat[3] ),
    .B1_N(\aw_addr_lat[4] ),
    .X(_0132_));
 sky130_fd_sc_hd__a21o_2 _1145_ (.A1(\aw_addr_lat[2] ),
    .A2(\aw_addr_lat[3] ),
    .B1(\aw_addr_lat[4] ),
    .X(_0133_));
 sky130_fd_sc_hd__mux2_1 _1146_ (.A0(_0132_),
    .A1(_0133_),
    .S(\aw_addr_lat[5] ),
    .X(_0134_));
 sky130_fd_sc_hd__o22ai_2 _1147_ (.A1(_0154_),
    .A2(_0230_),
    .B1(_0235_),
    .B2(_0134_),
    .Y(_0121_));
 sky130_fd_sc_hd__dfrtp_2 _1148_ (.CLK(clk),
    .D(_0039_),
    .RESET_B(rst_n),
    .Q(S_AXI_RVALID));
 sky130_fd_sc_hd__dfrtp_2 _1149_ (.CLK(clk),
    .D(_0040_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[0]));
 sky130_fd_sc_hd__dfrtp_2 _1150_ (.CLK(clk),
    .D(_0041_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[1]));
 sky130_fd_sc_hd__dfrtp_2 _1151_ (.CLK(clk),
    .D(_0042_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[2]));
 sky130_fd_sc_hd__dfrtp_2 _1152_ (.CLK(clk),
    .D(_0043_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[3]));
 sky130_fd_sc_hd__dfrtp_2 _1153_ (.CLK(clk),
    .D(_0044_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[4]));
 sky130_fd_sc_hd__dfrtp_2 _1154_ (.CLK(clk),
    .D(_0045_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[5]));
 sky130_fd_sc_hd__dfrtp_2 _1155_ (.CLK(clk),
    .D(_0046_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[6]));
 sky130_fd_sc_hd__dfrtp_2 _1156_ (.CLK(clk),
    .D(_0047_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[7]));
 sky130_fd_sc_hd__dfrtp_2 _1157_ (.CLK(clk),
    .D(_0048_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[8]));
 sky130_fd_sc_hd__dfrtp_2 _1158_ (.CLK(clk),
    .D(_0049_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[9]));
 sky130_fd_sc_hd__dfrtp_2 _1159_ (.CLK(clk),
    .D(_0050_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[10]));
 sky130_fd_sc_hd__dfrtp_2 _1160_ (.CLK(clk),
    .D(_0051_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[11]));
 sky130_fd_sc_hd__dfrtp_2 _1161_ (.CLK(clk),
    .D(_0052_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[12]));
 sky130_fd_sc_hd__dfrtp_2 _1162_ (.CLK(clk),
    .D(_0053_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[13]));
 sky130_fd_sc_hd__dfrtp_2 _1163_ (.CLK(clk),
    .D(_0054_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[14]));
 sky130_fd_sc_hd__dfrtp_2 _1164_ (.CLK(clk),
    .D(_0055_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[15]));
 sky130_fd_sc_hd__dfrtp_2 _1165_ (.CLK(clk),
    .D(_0056_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[16]));
 sky130_fd_sc_hd__dfrtp_2 _1166_ (.CLK(clk),
    .D(_0057_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[17]));
 sky130_fd_sc_hd__dfrtp_2 _1167_ (.CLK(clk),
    .D(_0058_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[18]));
 sky130_fd_sc_hd__dfrtp_2 _1168_ (.CLK(clk),
    .D(_0059_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[19]));
 sky130_fd_sc_hd__dfrtp_2 _1169_ (.CLK(clk),
    .D(_0060_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[20]));
 sky130_fd_sc_hd__dfrtp_2 _1170_ (.CLK(clk),
    .D(_0061_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[21]));
 sky130_fd_sc_hd__dfrtp_2 _1171_ (.CLK(clk),
    .D(_0062_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[22]));
 sky130_fd_sc_hd__dfrtp_2 _1172_ (.CLK(clk),
    .D(_0063_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[23]));
 sky130_fd_sc_hd__dfrtp_2 _1173_ (.CLK(clk),
    .D(_0064_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[24]));
 sky130_fd_sc_hd__dfrtp_2 _1174_ (.CLK(clk),
    .D(_0065_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[25]));
 sky130_fd_sc_hd__dfrtp_2 _1175_ (.CLK(clk),
    .D(_0066_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[26]));
 sky130_fd_sc_hd__dfrtp_2 _1176_ (.CLK(clk),
    .D(_0067_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[27]));
 sky130_fd_sc_hd__dfrtp_2 _1177_ (.CLK(clk),
    .D(_0068_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[28]));
 sky130_fd_sc_hd__dfrtp_2 _1178_ (.CLK(clk),
    .D(_0069_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[29]));
 sky130_fd_sc_hd__dfrtp_2 _1179_ (.CLK(clk),
    .D(_0070_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[30]));
 sky130_fd_sc_hd__dfrtp_2 _1180_ (.CLK(clk),
    .D(_0071_),
    .RESET_B(rst_n),
    .Q(S_AXI_RDATA[31]));
 sky130_fd_sc_hd__dfrtp_2 _1181_ (.CLK(clk),
    .D(_0072_),
    .RESET_B(rst_n),
    .Q(S_AXI_RID[0]));
 sky130_fd_sc_hd__dfrtp_2 _1182_ (.CLK(clk),
    .D(_0073_),
    .RESET_B(rst_n),
    .Q(S_AXI_RID[1]));
 sky130_fd_sc_hd__dfrtp_2 _1183_ (.CLK(clk),
    .D(_0074_),
    .RESET_B(rst_n),
    .Q(S_AXI_RID[2]));
 sky130_fd_sc_hd__dfrtp_2 _1184_ (.CLK(clk),
    .D(_0075_),
    .RESET_B(rst_n),
    .Q(S_AXI_RID[3]));
 sky130_fd_sc_hd__dfrtp_2 _1185_ (.CLK(clk),
    .D(_0076_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1186_ (.CLK(clk),
    .D(_0077_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1187_ (.CLK(clk),
    .D(_0078_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1188_ (.CLK(clk),
    .D(_0079_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1189_ (.CLK(clk),
    .D(_0080_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1190_ (.CLK(clk),
    .D(_0081_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1191_ (.CLK(clk),
    .D(_0082_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[6] ));
 sky130_fd_sc_hd__dfrtp_2 _1192_ (.CLK(clk),
    .D(_0083_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[7] ));
 sky130_fd_sc_hd__dfrtp_2 _1193_ (.CLK(clk),
    .D(_0084_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[8] ));
 sky130_fd_sc_hd__dfrtp_2 _1194_ (.CLK(clk),
    .D(_0085_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[9] ));
 sky130_fd_sc_hd__dfrtp_2 _1195_ (.CLK(clk),
    .D(_0086_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[10] ));
 sky130_fd_sc_hd__dfrtp_2 _1196_ (.CLK(clk),
    .D(_0087_),
    .RESET_B(rst_n),
    .Q(\ar_addr_lat[11] ));
 sky130_fd_sc_hd__dfrtp_2 _1197_ (.CLK(clk),
    .D(_0088_),
    .RESET_B(rst_n),
    .Q(ar_done));
 sky130_fd_sc_hd__dfrtp_2 _1198_ (.CLK(clk),
    .D(_0089_),
    .RESET_B(rst_n),
    .Q(S_AXI_BVALID));
 sky130_fd_sc_hd__dfrtp_2 _1199_ (.CLK(clk),
    .D(_0090_),
    .RESET_B(rst_n),
    .Q(w_done));
 sky130_fd_sc_hd__dfrtp_2 _1200_ (.CLK(clk),
    .D(_0091_),
    .RESET_B(rst_n),
    .Q(\w_data_lat[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1201_ (.CLK(clk),
    .D(_0092_),
    .RESET_B(rst_n),
    .Q(\w_data_lat[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1202_ (.CLK(clk),
    .D(_0093_),
    .RESET_B(rst_n),
    .Q(\w_data_lat[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1203_ (.CLK(clk),
    .D(_0094_),
    .RESET_B(rst_n),
    .Q(\w_data_lat[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1204_ (.CLK(clk),
    .D(_0095_),
    .RESET_B(rst_n),
    .Q(\w_data_lat[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1205_ (.CLK(clk),
    .D(_0096_),
    .RESET_B(rst_n),
    .Q(\w_data_lat[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1206_ (.CLK(clk),
    .D(_0097_),
    .RESET_B(rst_n),
    .Q(\w_strb_lat[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1207_ (.CLK(clk),
    .D(_0098_),
    .RESET_B(rst_n),
    .Q(S_AXI_BID[0]));
 sky130_fd_sc_hd__dfrtp_2 _1208_ (.CLK(clk),
    .D(_0099_),
    .RESET_B(rst_n),
    .Q(S_AXI_BID[1]));
 sky130_fd_sc_hd__dfrtp_2 _1209_ (.CLK(clk),
    .D(_0100_),
    .RESET_B(rst_n),
    .Q(S_AXI_BID[2]));
 sky130_fd_sc_hd__dfrtp_2 _1210_ (.CLK(clk),
    .D(_0101_),
    .RESET_B(rst_n),
    .Q(S_AXI_BID[3]));
 sky130_fd_sc_hd__dfrtp_2 _1211_ (.CLK(clk),
    .D(_0102_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1212_ (.CLK(clk),
    .D(_0103_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1213_ (.CLK(clk),
    .D(_0104_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1214_ (.CLK(clk),
    .D(_0105_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1215_ (.CLK(clk),
    .D(_0106_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1216_ (.CLK(clk),
    .D(_0107_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1217_ (.CLK(clk),
    .D(_0108_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[6] ));
 sky130_fd_sc_hd__dfrtp_2 _1218_ (.CLK(clk),
    .D(_0109_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[7] ));
 sky130_fd_sc_hd__dfrtp_2 _1219_ (.CLK(clk),
    .D(_0110_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[8] ));
 sky130_fd_sc_hd__dfrtp_2 _1220_ (.CLK(clk),
    .D(_0111_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[9] ));
 sky130_fd_sc_hd__dfrtp_2 _1221_ (.CLK(clk),
    .D(_0112_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[10] ));
 sky130_fd_sc_hd__dfrtp_2 _1222_ (.CLK(clk),
    .D(_0113_),
    .RESET_B(rst_n),
    .Q(\aw_addr_lat[11] ));
 sky130_fd_sc_hd__dfrtp_2 _1223_ (.CLK(clk),
    .D(_0114_),
    .RESET_B(rst_n),
    .Q(aw_done));
 sky130_fd_sc_hd__dfrtp_2 _1224_ (.CLK(clk),
    .D(_0038_),
    .RESET_B(rst_n),
    .Q(soft_rst_pulse));
 sky130_fd_sc_hd__dfrtp_2 _1225_ (.CLK(clk),
    .D(_0000_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1226_ (.CLK(clk),
    .D(_0011_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1227_ (.CLK(clk),
    .D(_0022_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1228_ (.CLK(clk),
    .D(_0025_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1229_ (.CLK(clk),
    .D(_0026_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1230_ (.CLK(clk),
    .D(_0027_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1231_ (.CLK(clk),
    .D(_0028_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[6] ));
 sky130_fd_sc_hd__dfrtp_2 _1232_ (.CLK(clk),
    .D(_0029_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[7] ));
 sky130_fd_sc_hd__dfrtp_2 _1233_ (.CLK(clk),
    .D(_0030_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[8] ));
 sky130_fd_sc_hd__dfrtp_2 _1234_ (.CLK(clk),
    .D(_0031_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[9] ));
 sky130_fd_sc_hd__dfrtp_2 _1235_ (.CLK(clk),
    .D(_0001_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[10] ));
 sky130_fd_sc_hd__dfrtp_2 _1236_ (.CLK(clk),
    .D(_0002_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[11] ));
 sky130_fd_sc_hd__dfrtp_2 _1237_ (.CLK(clk),
    .D(_0003_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[12] ));
 sky130_fd_sc_hd__dfrtp_2 _1238_ (.CLK(clk),
    .D(_0004_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[13] ));
 sky130_fd_sc_hd__dfrtp_2 _1239_ (.CLK(clk),
    .D(_0005_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[14] ));
 sky130_fd_sc_hd__dfrtp_2 _1240_ (.CLK(clk),
    .D(_0006_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[15] ));
 sky130_fd_sc_hd__dfrtp_2 _1241_ (.CLK(clk),
    .D(_0007_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[16] ));
 sky130_fd_sc_hd__dfrtp_2 _1242_ (.CLK(clk),
    .D(_0008_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[17] ));
 sky130_fd_sc_hd__dfrtp_2 _1243_ (.CLK(clk),
    .D(_0009_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[18] ));
 sky130_fd_sc_hd__dfrtp_2 _1244_ (.CLK(clk),
    .D(_0010_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[19] ));
 sky130_fd_sc_hd__dfrtp_2 _1245_ (.CLK(clk),
    .D(_0012_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[20] ));
 sky130_fd_sc_hd__dfrtp_2 _1246_ (.CLK(clk),
    .D(_0013_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[21] ));
 sky130_fd_sc_hd__dfrtp_2 _1247_ (.CLK(clk),
    .D(_0014_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[22] ));
 sky130_fd_sc_hd__dfrtp_2 _1248_ (.CLK(clk),
    .D(_0015_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[23] ));
 sky130_fd_sc_hd__dfrtp_2 _1249_ (.CLK(clk),
    .D(_0016_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[24] ));
 sky130_fd_sc_hd__dfrtp_2 _1250_ (.CLK(clk),
    .D(_0017_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[25] ));
 sky130_fd_sc_hd__dfrtp_2 _1251_ (.CLK(clk),
    .D(_0018_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[26] ));
 sky130_fd_sc_hd__dfrtp_2 _1252_ (.CLK(clk),
    .D(_0019_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[27] ));
 sky130_fd_sc_hd__dfrtp_2 _1253_ (.CLK(clk),
    .D(_0020_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[28] ));
 sky130_fd_sc_hd__dfrtp_2 _1254_ (.CLK(clk),
    .D(_0021_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[29] ));
 sky130_fd_sc_hd__dfrtp_2 _1255_ (.CLK(clk),
    .D(_0023_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[30] ));
 sky130_fd_sc_hd__dfrtp_2 _1256_ (.CLK(clk),
    .D(_0024_),
    .RESET_B(rst_n),
    .Q(\cycle_cnt_r[31] ));
 sky130_fd_sc_hd__dfrtp_2 _1257_ (.CLK(clk),
    .D(_0032_),
    .RESET_B(rst_n),
    .Q(\irq_status_r[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1258_ (.CLK(clk),
    .D(_0033_),
    .RESET_B(rst_n),
    .Q(\irq_status_r[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1259_ (.CLK(clk),
    .D(_0034_),
    .RESET_B(rst_n),
    .Q(\irq_status_r[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1260_ (.CLK(clk),
    .D(_0035_),
    .RESET_B(rst_n),
    .Q(\irq_status_r[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1261_ (.CLK(clk),
    .D(_0036_),
    .RESET_B(rst_n),
    .Q(\irq_status_r[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1262_ (.CLK(clk),
    .D(_0037_),
    .RESET_B(rst_n),
    .Q(\irq_status_r[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1263_ (.CLK(clk),
    .D(ascon_irq),
    .RESET_B(rst_n),
    .Q(\irq_prev[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1264_ (.CLK(clk),
    .D(uart_irq),
    .RESET_B(rst_n),
    .Q(\irq_prev[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1265_ (.CLK(clk),
    .D(gpio_irq),
    .RESET_B(rst_n),
    .Q(\irq_prev[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1266_ (.CLK(clk),
    .D(spi_irq),
    .RESET_B(rst_n),
    .Q(\irq_prev[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1267_ (.CLK(clk),
    .D(timer_irq),
    .RESET_B(rst_n),
    .Q(\irq_prev[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1268_ (.CLK(clk),
    .D(wdt_irq),
    .RESET_B(rst_n),
    .Q(\irq_prev[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1269_ (.CLK(clk),
    .D(_0115_),
    .RESET_B(rst_n),
    .Q(\irq_mask_r[0] ));
 sky130_fd_sc_hd__dfrtp_2 _1270_ (.CLK(clk),
    .D(_0116_),
    .RESET_B(rst_n),
    .Q(\irq_mask_r[1] ));
 sky130_fd_sc_hd__dfrtp_2 _1271_ (.CLK(clk),
    .D(_0117_),
    .RESET_B(rst_n),
    .Q(\irq_mask_r[2] ));
 sky130_fd_sc_hd__dfrtp_2 _1272_ (.CLK(clk),
    .D(_0118_),
    .RESET_B(rst_n),
    .Q(\irq_mask_r[3] ));
 sky130_fd_sc_hd__dfrtp_2 _1273_ (.CLK(clk),
    .D(_0119_),
    .RESET_B(rst_n),
    .Q(\irq_mask_r[4] ));
 sky130_fd_sc_hd__dfrtp_2 _1274_ (.CLK(clk),
    .D(_0120_),
    .RESET_B(rst_n),
    .Q(\irq_mask_r[5] ));
 sky130_fd_sc_hd__dfrtp_2 _1275_ (.CLK(clk),
    .D(_0121_),
    .RESET_B(rst_n),
    .Q(S_AXI_BRESP[1]));
 sky130_fd_sc_hd__conb_1 _1276_ (.HI(S_AXI_RLAST));
 sky130_fd_sc_hd__conb_1 _1277_ (.LO(S_AXI_BRESP[0]));
 sky130_fd_sc_hd__conb_1 _1278_ (.LO(S_AXI_RRESP[0]));
 sky130_fd_sc_hd__conb_1 _1279_ (.LO(S_AXI_RRESP[1]));
endmodule
