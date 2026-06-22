# =========================================================================
# SDC for riscv_cpu_core (IHP-13sg2 @ 100MHz)
# =========================================================================

# 1. Units
set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA

# 2. Clock Definition (100MHz -> 10ns period)
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition 0.15 [get_clocks clk]

# 3. Input Delays (20% of period = 2ns)
set input_ports [list rst imem_rdata imem_ready dcache_rdata dcache_ready \
                      external_irq timer_irq sw_irq debug_haltreq debug_resumereq]
set_input_delay -clock clk 2.0 $input_ports

# 4. Output Delays (20% of period = 2ns)
set output_ports [list imem_addr imem_valid dcache_addr dcache_wdata dcache_wstrb \
                       dcache_req dcache_we dcache_fence_type debug_halted debug_running]
set_output_delay -clock clk 2.0 $output_ports

# 5. Environment (Sky130 Specific)
set_driving_cell -lib_cell sg13g2_inv_1 [all_inputs]
set_load 0.035 [all_outputs]

# 6. False Paths
set_false_path -from [get_ports rst]
set_false_path -from [get_ports {external_irq timer_irq sw_irq}]

# 7. Derate (OCV - On Chip Variation)
set_timing_derate -early 0.95
set_timing_derate -late 1.05

group_path -name reg2reg  -from [all_registers] -to [all_registers]
group_path -name in2reg   -from [all_inputs]    -to [all_registers]
group_path -name reg2out  -from [all_registers] -to [all_outputs]
group_path -name in2out   -from [all_inputs]    -to [all_outputs]


