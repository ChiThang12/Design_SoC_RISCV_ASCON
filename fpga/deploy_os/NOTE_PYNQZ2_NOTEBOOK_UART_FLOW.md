# PYNQ-Z2 Notebook UART Deployment Note

## Goal

This flow lets a PYNQ notebook act like a terminal host for the RISC-V SoC without using an external UART cable.

JTAG is used only to program the FPGA bitstream.

Runtime communication path:

```text
PYNQ notebook
  -> PS DDR buffer
  -> AXI DMA MM2S
  -> AXI4-Stream bytes
  -> axis_uart_bridge
  -> UART RX into SoC

SoC UART TX
  -> axis_uart_bridge
  -> AXI4-Stream bytes
  -> AXI DMA S2MM
  -> PS DDR buffer
  -> PYNQ notebook monitor
```

The bridge does not implement a Linux shell. It only transports bytes. Commands such as `ls`, `mkdir`, `cat`, `status`, or `monitor on` must be implemented by firmware running on the RISC-V SoC.

## Files Added

```text
fpga/src/axis_uart_bridge.v
fpga/src/pynqz2_notebook_uart_top.v
fpga/tb/tb_axis_uart_bridge.v
fpga/script/06_run_axis_uart_bridge_tb.bat
fpga/notebook/pynq_notebook_uart_demo.py
```

`axis_uart_bridge.v`

Converts AXI4-Stream byte packets to UART serial data going into the SoC, and converts UART serial data coming from the SoC back into AXI4-Stream byte packets.

`pynqz2_notebook_uart_top.v`

Wraps `soc_hs` and replaces external UART pins with the notebook UART bridge. This is the intended FPGA top for the PYNQ notebook flow.

`pynq_notebook_uart_demo.py`

Example PYNQ Python host script. It loads the overlay, sends firmware bytes through DMA to boot the SoC, then sends terminal-style commands and monitors UART responses.

## Vivado Block Design

Use the normal PYNQ-Z2/Zynq flow:

```text
ZYNQ7 Processing System
AXI DMA
Processor System Reset
AXI Interconnect / SmartConnect
pynqz2_notebook_uart_top
```

Recommended connections:

```text
Zynq PS FCLK_CLK0
  -> pynqz2_notebook_uart_top.clk_in
  -> AXI DMA clock
  -> reset block clock

Zynq PS FCLK_RESET0_N or reset block output
  -> pynqz2_notebook_uart_top.ext_rst_n

External or reset block reset
  -> pynqz2_notebook_uart_top.por_n

AXI DMA M_AXIS_MM2S
  -> pynqz2_notebook_uart_top.s_axis_*

pynqz2_notebook_uart_top.m_axis_*
  -> AXI DMA S_AXIS_S2MM

Zynq PS M_AXI_GP0
  -> AXI DMA S_AXI_LITE

AXI DMA memory ports
  -> Zynq PS HP port or suitable DDR path
```

The stream ports on `pynqz2_notebook_uart_top` are:

```text
s_axis_tdata[7:0]
s_axis_tkeep
s_axis_tvalid
s_axis_tlast
s_axis_tready

m_axis_tdata[7:0]
m_axis_tkeep
m_axis_tvalid
m_axis_tlast
m_axis_tready
```

The wrapper currently emits one byte per output packet with `m_axis_tlast=1`. This makes notebook-side monitoring simple because each S2MM receive can complete on a single UART byte.

## Clock And Baud

Default wrapper parameter:

```verilog
BAUD_DIV = 868
```

At 100 MHz this is approximately 115200 baud.

If the PYNQ fabric clock is different, update `BAUD_DIV`:

```text
BAUD_DIV = fabric_clock_hz / target_baud
```

Examples:

```text
100 MHz / 115200 ~= 868
50 MHz  / 115200 ~= 434
125 MHz / 115200 ~= 1085
```

## Boot Flow

`pynqz2_notebook_uart_top` instantiates the SoC with:

```verilog
.SIM_MODE(0)
```

This means the SoC expects raw little-endian firmware bytes over UART boot.

The notebook must send:

```text
fpga/os/firmware/test_freertos_kernel_smoke.bin
```

not the `.hex` file.

The `.hex` file is for simulation and `$readmemh`. The `.bin` file is for UART boot on FPGA.

## Notebook Flow

Python example:

```python
from pynq_notebook_uart_demo import NotebookUartBridge

bridge = NotebookUartBridge(
    bitstream="soc_rvas_notebook_uart.bit",
    dma_name="axi_dma_0",
)

bridge.boot("test_freertos_kernel_smoke.bin")
bridge.monitor(seconds=3)

bridge.send_line("status")
bridge.send_line("monitor on")
bridge.send_line("read 0x50000000")
bridge.monitor(seconds=5)
```

You may need to change:

```python
BITSTREAM = "soc_rvas_notebook_uart.bit"
FIRMWARE_BIN = "test_freertos_kernel_smoke.bin"
DMA_NAME = "axi_dma_0"
```

based on the generated Vivado overlay and block design names.

## About Commands Like ls And mkdir

The bridge only moves bytes. It does not create commands.

Commands such as:

```text
ls
mkdir
cat
rm
echo
status
monitor on
```

work only if the RISC-V firmware implements a command parser and, for file commands, a filesystem.

Current smoke firmware is mainly expected to print:

```text
[PASS] freertos_kernel_smoke
```

It is not a Linux shell.

Recommended firmware command roadmap:

```text
help
status
reboot
peek <addr>
poke <addr> <value>
ascon selftest
dma selftest
uart echo on/off
```

Later, if a filesystem is added:

```text
ls
mkdir
cat
write
rm
```

For `ls` and `mkdir`, the firmware needs at least one storage backend:

```text
RAM filesystem
SPI flash filesystem
SD card filesystem
host-backed virtual filesystem over UART protocol
```

The fastest bring-up option is a RAM filesystem because it avoids SD/SPI driver complexity.

## Simulation Tests

Run bridge behavior test:

```bat
cd fpga\script
06_run_axis_uart_bridge_tb.bat
```

Expected:

```text
[OK] AXIS UART bridge TB PASS
```

Run existing SoC smoke simulation:

```bat
cd fpga\script
00_run_freertos_kernel_smoke_sim.bat
```

Expected:

```text
[OK] Simulation PASS: [PASS] freertos_kernel_smoke
```

## Vivado Validation Checklist

After synthesis, check:

```text
No missing top ports
AXI DMA stream width is 8 bits
TKEEP/TLAST are connected
FCLK frequency matches BAUD_DIV
AXI DMA is visible in PYNQ overlay IP dictionary
Bitstream and HWH are copied together
```

In notebook:

```python
ol = Overlay("soc_rvas_notebook_uart.bit")
ol.ip_dict.keys()
```

Confirm the DMA name matches `DMA_NAME`.

## Expected Bring-Up Sequence

1. Generate bitstream with `pynqz2_notebook_uart_top` as top.
2. Copy `.bit` and `.hwh` to PYNQ board.
3. Copy `test_freertos_kernel_smoke.bin` to the same notebook directory.
4. Open Jupyter notebook on PYNQ.
5. Import `NotebookUartBridge`.
6. Call `bridge.boot(...)`.
7. Call `bridge.monitor(...)`.
8. Look for:

```text
[PASS] freertos_kernel_smoke
```

If no UART output appears, first verify:

```text
FCLK frequency
BAUD_DIV
DMA IP name
DMA stream direction
reset polarity
firmware .bin path
```

