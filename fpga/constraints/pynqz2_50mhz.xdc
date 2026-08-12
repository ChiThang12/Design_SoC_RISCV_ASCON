# Vivado-compatible timing constraint for a 50 MHz fabric clock
# PYNQ-Z2 onboard LED0 is R14 and is active-high.

create_clock -name clk_in -period 20.000 [get_ports clk_in]

set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports { led_heartbeat }]
