# ==============================================================================
# SDC Constraints for riscv_cpu_core (Timing Optimization Version)
# Target Frequency: 100MHz (10.0ns)
# Focus: Max Fanout Control & Slew Rate Improvement
# ==============================================================================

# 1. Clock Definition
set clk_name clk
set clk_period 10.0
set clk_port [get_ports clk]

create_clock -name $clk_name -period $clk_period $clk_port
set_clock_uncertainty 0.25 [get_clocks $clk_name]
set_clock_transition 0.15 [get_clocks $clk_name]

# 2. Design Constraints (Khắt khe hơn để ép tool chèn Buffer)
set_max_fanout 5 [current_design]
set_max_transition 0.5 [current_design]
set_max_capacitance 0.1 [current_design]

# 3. Input Constraints
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_4 -pin X [all_inputs]

# Đặt input delay chiếm 30% chu kỳ để dành 70% cho logic bên trong (EX/MEM stage)
set_input_delay -clock $clk_name -max 3.0 [all_inputs]
set_input_delay -clock $clk_name -min 0.5 [all_inputs]

# 4. Output Constraints
set_load 0.05 [all_outputs]
set_output_delay -clock $clk_name -max 3.0 [all_outputs]
set_output_delay -clock $clk_name -min 0.2 [all_outputs]

# 5. Timing Derate (OCV)
set_timing_derate -early 0.95
set_timing_derate -late  1.05

# 6. False Paths (Quan trọng để tool bỏ qua các net không cần thiết)
set_false_path -from [get_ports rst]
set_false_path -through [get_ports external_irq]
set_false_path -through [get_ports timer_irq]
set_false_path -through [get_ports sw_irq]

# 7. Path Groups & Critical Range
# Ép tool tập trung tối ưu các path có slack âm trong khoảng 2ns
group_path -name internal_logic -from [all_registers] -to [all_registers] -critical_range 2.0
group_path -name input_path -from [all_inputs] -critical_range 2.0
group_path -name output_path -to [all_outputs] -critical_range 2.0

# 8. Set Max Delay cho các net quan trọng (Forwarding/Hazard logic)
# Nếu bạn biết tên net forwarding, có thể ép thêm (ví dụ tham khảo):
# set_max_delay 8.0 -from [get_cells -hier *fwd_unit*]



