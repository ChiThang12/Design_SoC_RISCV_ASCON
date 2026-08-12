# PYNQ-Z2 full-board constraint for `fpga_top`
#
# Board facts from the PYNQ-Z2 reference manual:
# - Clock input on H16 is the 125 MHz PL clock
# - LED0..LED3 are active-high
# - SW0/SW1 are active-high when switched up
# - UART0 and SPI pins can be routed to the Raspberry Pi header
# - Arduino and Pmod headers are safe 3.3 V PL I/O
#
# Notes:
# - `por_n` and `ext_rst_n` are mapped to SW0/SW1 so you can pull them low
#   by moving the switch down.
# - `tck/tms/tdi/tdo` are left unconstrained because the board already has a
#   dedicated USB-JTAG path; add a header mapping only if you want external
#   JTAG breakout.

## Clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports {clk_in}]
create_clock -name clk_in -period 8.000 [get_ports {clk_in}]

## Reset switches
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports {por_n}]
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 } [get_ports {ext_rst_n}]

## Board LEDs
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports {led_heartbeat}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {wdt_rst_req}]

## UART on Raspberry Pi header
set_property -dict { PACKAGE_PIN U8 IOSTANDARD LVCMOS33 } [get_ports {uart_tx}]
set_property -dict { PACKAGE_PIN W6 IOSTANDARD LVCMOS33 } [get_ports {uart_rx}]

## SPI on Raspberry Pi header
set_property -dict { PACKAGE_PIN C20 IOSTANDARD LVCMOS33 } [get_ports {spi_sck}]
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS33 } [get_ports {spi_mosi}]
set_property -dict { PACKAGE_PIN U7 IOSTANDARD LVCMOS33 } [get_ports {spi_miso}]
set_property -dict { PACKAGE_PIN Y8 IOSTANDARD LVCMOS33 } [get_ports {spi_cs_n}]

## GPIO[0:19] -> Arduino digital I/O
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports {gpio[0]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {gpio[1]}]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {gpio[2]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {gpio[3]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {gpio[4]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {gpio[5]}]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports {gpio[6]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {gpio[7]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {gpio[8]}]
set_property -dict { PACKAGE_PIN V18 IOSTANDARD LVCMOS33 } [get_ports {gpio[9]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {gpio[10]}]
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {gpio[11]}]
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports {gpio[12]}]
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports {gpio[13]}]
set_property -dict { PACKAGE_PIN Y11 IOSTANDARD LVCMOS33 } [get_ports {gpio[14]}]
set_property -dict { PACKAGE_PIN Y12 IOSTANDARD LVCMOS33 } [get_ports {gpio[15]}]
set_property -dict { PACKAGE_PIN W11 IOSTANDARD LVCMOS33 } [get_ports {gpio[16]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {gpio[17]}]
set_property -dict { PACKAGE_PIN T5  IOSTANDARD LVCMOS33 } [get_ports {gpio[18]}]
set_property -dict { PACKAGE_PIN U10 IOSTANDARD LVCMOS33 } [get_ports {gpio[19]}]

## GPIO[20:27] -> Pmod A
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {gpio[20]}]
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {gpio[21]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {gpio[22]}]
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports {gpio[23]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {gpio[24]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {gpio[25]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {gpio[26]}]
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports {gpio[27]}]

## GPIO[28:31] -> Pmod B
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {gpio[28]}]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {gpio[29]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {gpio[30]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {gpio[31]}]

