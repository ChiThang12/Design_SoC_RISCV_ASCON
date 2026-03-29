###############################################################################
# Created by write_sdc
###############################################################################
current_design clk_reset_ctrl
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 10.0000 
set_clock_uncertainty 0.2500 clk
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {clk_in}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {core_clk_en}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ext_rst_n}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {ndmreset}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {periph_clk_en}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {por_n}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {soft_rst_pulse}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {test_en}]
set_output_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {clk_core}]
set_output_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {clk_periph}]
set_output_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {cpu_rst_n}]
set_output_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {fabric_rst_n}]
set_output_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {periph_rst_n}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0334 [get_ports {clk_core}]
set_load -pin_load 0.0334 [get_ports {clk_periph}]
set_load -pin_load 0.0334 [get_ports {cpu_rst_n}]
set_load -pin_load 0.0334 [get_ports {fabric_rst_n}]
set_load -pin_load 0.0334 [get_ports {periph_rst_n}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {clk_in}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {core_clk_en}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {ext_rst_n}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {ndmreset}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {periph_clk_en}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {por_n}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {soft_rst_pulse}]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {test_en}]
###############################################################################
# Design Rules
###############################################################################
set_max_transition 0.7500 [current_design]
set_max_capacitance 0.2000 [current_design]
set_max_fanout 10.0000 [current_design]
