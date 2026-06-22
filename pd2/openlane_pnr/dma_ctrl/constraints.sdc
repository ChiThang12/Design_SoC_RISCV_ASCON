# ============================================================================
# File Name   : ascon_top.sdc
# Design Top  : ascon_ip_top
# Technology  : IHP SG13G2 (130nm)
# Target Freq : 100 MHz (Period = 10.0 ns)
# ============================================================================

# 1. Khai báo Clock chính (10.0ns cho tần số 100MHz)
create_clock -name VCLK_100 -period 10.0 [get_ports clk]

# Thiết lập độ bất định chân Clock (Clock Uncertainty) bảo vệ cho nút IHP 130nm
set_clock_uncertainty -setup 0.4 [get_clocks VCLK_100]
set_clock_uncertainty -hold  0.1 [get_clocks VCLK_100]

# 2. Lọc tự động toàn bộ Input Ports (Ngoại trừ chân clk và rst_n) - Đúng theo mẫu của bạn
set all_in_ports [all_inputs]
set input_ports_to_constrain ""

foreach port $all_in_ports {
    set port_name [get_name $port]
    if { $port_name != "clk" && $port_name != "rst_n" } {
        lappend input_ports_to_constrain $port
    }
}

# 3. Ràng buộc Timing Budget biên hệ thống (Boundary IO Delays - 40% chu kỳ)
set_input_delay  4.0 -clock VCLK_100 $input_ports_to_constrain
set_output_delay 4.0 -clock VCLK_100 [all_outputs]
set_driving_cell -lib_cell sg13g2_buf_2 -pin X $input_ports_to_constrain
set_load 2.0 [all_outputs]

# 4. Ràng buộc đường dẫn không đồng bộ (False Paths)
set_false_path -from [get_ports rst_n]

# 5. Khai báo quy tắc kiểm tra thiết kế hình học (DRC) định hướng tiến trình
set_max_transition 0.5 [current_design]
set_max_fanout 20 [current_design]

set_max_transition 0.35 [get_pins u_ascon_core/u_perm/stage_st_reg[*][*]/D]

# ==============================================================================
# 6. PHÂN NHÓM ĐƯỜNG TRUYỀN TIMING (PATH GROUPS CHUẨN STANDARD CELL CHO ASCON)
# ==============================================================================
# Phân nhóm cơ bản để quản lý các đường truyền Flip-Flop nội bộ và cổng biên IO
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name in2reg  -from [all_inputs]    -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]
group_path -name in2out  -from [all_inputs]    -to [all_outputs]

# --- PHẦN THÊM MỚI ĐẶC THÙ CHO ASCON: Tách biệt trục dữ liệu Mật mã và luồng Bus DMA ---

# Nhóm mật mã hạng nặng (Crypto Core): Từ ngõ ra State Register phóng qua Permutation rồi quay về lối vào
#group_path -name crypto_core \
    #-from [get_pins u_ascon_core/u_state_reg/state_out_reg[*]/Q] \
    #-to   [get_pins u_ascon_core/u_state_reg/state_in[*]]

# Nhóm DMA AXI Master: Ràng buộc riêng cho các Flip-Flops điều khiển phát lệnh đọc/ghi Burst đi ra ngoài biên hệ thống
#group_path -name dma_axi_master \
    #-to [get_ports M_AXI_AWADDR[*]] \
    #-to [get_ports M_AXI_WDATA[*]] \
    -to [get_ports M_AXI_ARADDR[*]]



