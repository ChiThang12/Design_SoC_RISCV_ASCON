# ==============================================================================
# SDC for axi4_crossbar_3m12s (Technology: 130nm)
# Target Frequency: 100MHz | Period: 10.0ns
# ==============================================================================

create_clock -name sys_clk -period 10.0 [get_ports clk]

set_max_fanout 20 [current_design]
set_max_transition 0.5 [current_design]

set_clock_uncertainty 0.25 [get_clocks sys_clk]
set_clock_transition  0.15 [get_clocks sys_clk]

# OCV
set_timing_derate -early 0.95 [current_design]
set_timing_derate -late  1.05 [current_design]
# Derate riêng cho Net delay để dự phòng sụt áp (IR Drop) trên các đường bus dài
set_timing_derate -late  1.05 -net_delay [current_design]

# 4. Phân nhóm Path & Critical Range
group_path -name reg2reg -from [all_registers] -to [all_registers]
group_path -name in2reg  -from [all_inputs]    -to [all_registers]
group_path -name reg2out -from [all_registers] -to [all_outputs]

set_input_delay 3.0 -clock sys_clk [get_ports * -filter "name != clk"] 
set_output_delay 3.0 -clock sys_clk [all_outputs]

set_load 0.05 [all_outputs]

# ------------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports S*_BASE*]
set_false_path -from [get_ports S*_MASK*]

# ==============================================================================
# END OF SDC
# ==============================================================================



