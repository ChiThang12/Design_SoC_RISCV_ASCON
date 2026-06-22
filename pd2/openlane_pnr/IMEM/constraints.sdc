# ==============================================================================
# SDC Constraints cho inst_mem_axi_slave (Target: 100MHz)
# Đã tích hợp cấu trúc Dual-SRAM Bank (RM_IHPSG13_2P_1024x32_c2_bm_bist)
# ==============================================================================

# 1. Khai báo Clock chính (100MHz -> Chu kỳ 10.0ns)
create_clock -name VCLK_100 -period 10.0 [get_ports clk]

# Cấu hình độ bất định chân Clock cho tiến trình IHP 130nm
set_clock_uncertainty -setup 0.4 [get_clocks VCLK_100]
set_clock_uncertainty -hold  0.1 [get_clocks VCLK_100]

# 2. Tạo danh sách các cổng Inputs (loại trừ clk, rst_n)
set all_in_ports [all_inputs]
set input_ports_to_constrain ""

foreach port $all_in_ports {
    set port_name [get_name $port]
    if { $port_name != "clk" && $port_name != "rst_n" } {
        lappend input_ports_to_constrain $port
    }
}

# 3. Áp dụng Timing Budget biên ranh giới (40% Chu kỳ)
set_input_delay  4.0 -clock VCLK_100 $input_ports_to_constrain
set_output_delay 4.0 -clock VCLK_100 [all_outputs]
set_driving_cell -lib_cell sg13g2_buf_2 -pin X $input_ports_to_constrain
set_load 2.0 [all_outputs]

# 4. Ràng buộc đường dẫn không đồng bộ (False Paths)
set_false_path -from [get_ports rst_n]

# Vô hiệu hóa timing trên các chân BIST nội bộ không dùng của cả 2 Bank
set_false_path -to [get_pins imem/sram_bank0_inst/*BIST*]
set_false_path -to [get_pins imem/sram_bank1_inst/*BIST*]

# 5. Các ràng buộc quy tắc kiểm tra thiết kế (DRC) cho PDK IHP-SG13G2
# 0.5 make timing slack in2out closely zero
#set_max_transition 0.5 [current_design]
# 0.35 make timing slack gap bigger
set_max_transition 0.35 [current_design]
set_max_fanout 20 [current_design]

# Ép chặt Transition cho các chân Port điều khiển nhạy cảm của 2 khối SRAM Macro
set_max_transition 0.35 [get_pins imem/sram_bank0_inst/*]
set_max_transition 0.35 [get_pins imem/sram_bank1_inst/*]

# 6. Ràng buộc chu kỳ dài (Multicycle Paths cho các kênh AXI Slave)
#set_multicycle_path 2 -setup -from [get_ports S_AXI_AWADDR[*]] -to [all_registers]
#set_multicycle_path 1 -hold  -from [get_ports S_AXI_AWADDR[*]] -to [all_registers]
#
#set_multicycle_path 2 -setup -from [get_ports S_AXI_ARADDR[*]] -to [all_registers]
#set_multicycle_path 1 -hold  -from [get_ports S_AXI_ARADDR[*]] -to [all_registers]

# ==============================================================================
# 7. PHÂN NHÓM ĐƯỜNG TRUYỀN TIMING (PATH GROUPS NÂNG CAO)
# ==============================================================================
# Nhóm cơ bản hệ thống
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name in2reg  -from [all_inputs]    -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]
group_path -name in2out  -from [all_inputs]    -to [all_outputs]

# Nhóm điều khiển giao tiếp Bus AXI
#group_path -name AXI_WRITE_KÊNH -from [get_ports S_AXI_W*]
#group_path -name AXI_READ_KÊNH  -to [get_ports S_AXI_R*]

# Nhóm `reg2mem`: Flip-Flops logic nội bộ lái tới các chân Port đầu vào (Cổng A & B) của 2 SRAM
#group_path -name reg2mem -to [get_pins imem/sram_bank0_inst/A_*] \
                         #-to [get_pins imem/sram_bank0_inst/B_*] \
                         #-to [get_pins imem/sram_bank1_inst/A_*] \
                         #-to [get_pins imem/sram_bank1_inst/B_*]

# Nhóm `mem2reg`: Từ chân dữ liệu đầu ra Port A (`A_DOUT`) của 2 SRAM trả về logic đích
#group_path -name mem2reg -from [get_pins imem/sram_bank0_inst/A_DOUT[*]] \
                         #-from [get_pins imem/sram_bank1_inst/A_DOUT[*]]



