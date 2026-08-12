# PYNQ-Z2 / FPGA top timing constraint
# Target fabric clock: 50 MHz

create_clock -name clk_in -period 20.000 [get_ports clk_in]

