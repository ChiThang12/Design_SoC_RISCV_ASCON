# ==============================================================================
# SDC hiệu chỉnh hoàn toàn cho OpenROAD 
# ==============================================================================

# 1. Khai báo Clock
create_clock -name VCLK_100 -period 10.0 [get_ports clk]

# 2. Tạo danh sách inputs nhưng loại bỏ clk và rst_n
# Chúng ta dùng hàm lsearch để lọc trong danh sách Tcl
set all_in_ports [all_inputs]
set input_ports_to_constrain ""

foreach port $all_in_ports {
    set port_name [get_name $port]
    if { $port_name != "clk" && $port_name != "rst_n" } {
        lappend input_ports_to_constrain $port
    }
}

# 3. Áp dụng Input Delay lên danh sách đã lọc
set_input_delay 4.0 -clock VCLK_100 $input_ports_to_constrain

# 4. Các ràng buộc khác giữ nguyên
set_output_delay 4.0 -clock VCLK_100 [all_outputs]
set_false_path -from [get_ports rst_n]
set_false_path -to [get_pins data_array_inst/data_array_macro/A_BIST_*]

# DRC cho PDK IHP-SG13G2
set_max_transition 0.4 [get_pins data_array_inst/data_array_macro/*]
set_max_transition 0.5 [current_design]
set_max_fanout 20 [current_design]
set_load 2.0 [all_outputs]

# 3. Multicycle Path
#set_multicycle_path 2 -setup -to [get_pins data_array_inst/data_array_macro/A_ADDR[*]]
#set_multicycle_path 1 -hold  -to [get_pins data_array_inst/data_array_macro/A_ADDR[*]]
set_multicycle_path 2 -setup -from [get_ports cpu_addr[*]] -to [get_ports mem_araddr[*]]
set_multicycle_path 1 -hold  -from [get_ports cpu_addr[*]] -to [get_ports mem_araddr[*]]

# 4. Group paths
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name in2reg -from [all_inputs] -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]
group_path -name in2out -from [all_inputs] -to [all_outputs]




