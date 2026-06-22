# ==============================================================================
# SDC Constraints nâng cao cho dmem Sub-module vi Hard Macro SRAM
# Tn s: 100MHz (Period: 10.0ns) | PDK: IHP-SG13G2
# ==============================================================================

# 1. Khai báo Clock chính 
create_clock -name VCLK_100 -period 10.0 [get_ports clk]

set_clock_uncertainty -setup 0.4 [get_clocks VCLK_100]
set_clock_uncertainty -hold  0.1 [get_clocks VCLK_100]

# 2. Lc danh sách cng Inputs đu vào t đng (loi tr clk, rst_n)
set all_in_ports [all_inputs]
set input_ports_to_constrain ""

foreach port $all_in_ports {
    set port_name [get_name $port]
    if { $port_name != "clk" && $port_name != "rst_n" } {
        lappend input_ports_to_constrain $port
    }
}

# 3. Ràng buc Timing Budget biên cho module
set_input_delay  4.0 -clock VCLK_100 $input_ports_to_constrain
set_output_delay 4.0 -clock VCLK_100 [all_outputs]
set_driving_cell -lib_cell sg13g2_buf_2 -pin X $input_ports_to_constrain

# 4. Ràng buc False Path
set_false_path -from [get_ports rst_n]

# 5. Khai báo Quy tc Kim soát Thit k H thng (DRC) cho IHP Node 130nm
set_max_transition 0.5 [current_design]
set_max_fanout 20 [current_design]
set_load 2.0 [all_outputs]

# Ràng buc tht cht transition cho các chân điu khin nhy cm ca SRAM Macro
set_max_transition 0.35 [get_pins dmem/sram_macro_inst/*]

# 6. Thit lp các chu kỳ dài (Multicycle Paths cho Bus AXI4 Slave)
#set_multicycle_path 2 -setup -from [get_ports S_AXI_AWADDR[*]] -to [all_registers]
#set_multicycle_path 1 -hold  -from [get_ports S_AXI_AWADDR[*]] -to [all_registers]
#
#set_multicycle_path 2 -setup -from [get_ports S_AXI_ARADDR[*]] -to [all_registers]
#set_multicycle_path 1 -hold  -from [get_ports S_AXI_ARADDR[*]] -to [all_registers]

# ==============================================================================
# 7. QUN LÝ VÀ PHÂN NHÓM ĐNG TRUYN (PATH GROUPS) - B SUNG REG2MEM & MEM2REG
# ==============================================================================
# Nhóm c bn
group_path -name reg2reg  -from [all_registers] -to [all_registers]
group_path -name in2reg   -from [all_inputs]    -to [all_registers]
group_path -name reg2out  -from [all_registers] -to [all_outputs]
group_path -name in2out   -from [all_inputs]    -to [all_outputs]

# Nhóm Kênh Bus AXI
#group_path -name AXI_WRITE_CHAN -from [get_ports S_AXI_W*]
#group_path -name AXI_READ_CHAN  -to [get_ports S_AXI_R*]

# --- PHN THÊM MI: Tách bit nhóm Timing liên quan ti Hard Macro SRAM ---
# Nhóm reg2mem: T tt c Flip-flops ni b đi ti các chân đu vào điu khin/d liu ca SRAM
#group_path -name reg2mem -to [get_pins dmem/sram_macro_inst/A_*]

# Nhóm mem2reg: T chân d liu đu ra ca SRAM đi ti các Flip-flops ly mu logic tip theo
#group_path -name mem2reg -from [get_pins dmem/sram_macro_inst/A_DOUT[*]]
