# FPGA Terminal Simulation Package

Muc tieu chinh cua thu muc nay la **mo phong tren terminal truoc**, voi RTL + testbench + firmware HEX da chuan bi san. Windows khong can GCC/RISC-V toolchain, chi can Icarus Verilog (`iverilog` + `vvp`) trong `PATH`.

Trang thai package:

- RTL da duoc copy phang vao `src/`.
- Testbench can thiet nam trong `tb/`.
- Firmware OS da build san nam trong `os/firmware/`.
- Script Windows `.bat` nam trong `script/`, chay truc tiep tu terminal.
- RTL compile bang filelist `script/rtl_sources.f`; khong dung include-flow.
- Top synthesis: `fpga_top`.
- Profile bring-up: single-core, UART boot, FreeRTOS-Kernel smoke.

## Thu Muc

- `src/`: RTL Verilog package. Tat ca file `.v` nam cung cap trong thu muc nay.
- `tb/`: testbench simulation cho FreeRTOS kernel smoke.
- `os/firmware/`: firmware da build san.
- `os/source/`: source C cua cac test OS.
- `os/freertos_port/`: port FreeRTOS machine-mode cua SoC.
- `os/FreeRTOS-Kernel/`: cac file kernel toi thieu dung cho smoke hien tai.
- `script/`: script `.bat` de chay tren Windows.

## Firmware Da Chuan Bi

Firmware chinh:

```text
os/firmware/test_freertos_kernel_smoke.hex
os/firmware/test_freertos_kernel_smoke.bin
```

Dung file nao:

- `.hex`: dung cho simulation hoac BRAM/init `$readmemh`.
- `.bin`: dung de gui qua UART bootloader tren FPGA.

Boot controller hardware `SIM_MODE=0` nhan raw binary little-endian qua UART, khong nhan text hex.

## Chay Mo Phong Tren Windows Terminal

Day la buoc can lam dau tien.

Mo terminal Windows bat ky da co `iverilog` va `vvp` trong `PATH`, sau do chay:

```bat
cd fpga\script
00_run_freertos_kernel_smoke_sim.bat
```

Script nay se tu dong:

1. Compile RTL package bang `script/rtl_sources.f`.
2. Compile testbench `tb/tb_freertos_kernel_smoke.v` bang `iverilog`.
3. Load firmware HEX co san:

```text
os/firmware/test_freertos_kernel_smoke.hex
```

4. Chay simulation bang `vvp`.
5. Kiem tra marker:

```text
[PASS] freertos_kernel_smoke
```

Log simulation nam o:

```text
fpga/sim_log/vvp_freertos_kernel_smoke.log
```

Neu thay:

```text
[OK] Simulation PASS: [PASS] freertos_kernel_smoke
```

thi goi RTL + TB + HEX da san sang de sang buoc build/nạp FPGA.

## Build Vivado Project

Buoc nay lam sau khi simulation PASS.

Trong Vivado, add RTL theo filelist:

```text
fpga/script/rtl_sources.f
```

Sau do set top:

```text
fpga_top
```

Profile synthesis hien tai:

```text
top      = fpga_top
SIM_MODE = 0
ENABLE_CPU1 = 0
```

Nghia la FPGA se dung UART bootloader va single-core profile.

## Script Simulation Khac

Notebook-host TB, mo phong host/notebook monitor UART console:

```bat
cd fpga\script
05_run_notebook_host_sim.bat
```

Shortcut debug kernel smoke:

```bat
cd fpga\script
02_run_freertos_kernel_smoke_sim.bat
```

## Nap Firmware Qua UART Bootloader

Sau khi bitstream da duoc nap len FPGA:

1. Mo `fpga/script/03_send_firmware_uart.bat`.
2. Sua `COM_PORT=COM5` thanh cong COM cua board.
3. Chay:

```bat
cd fpga\script
03_send_firmware_uart.bat
```

Script gui file:

```text
os/firmware/test_freertos_kernel_smoke.bin
```

qua UART 115200 baud.

## UART Log Can Thay

Neu OS boot dung, UART output can co:

```text
[PASS] freertos_kernel_smoke
```

Khi thay dong nay tren board, co the chot moc:

```text
FreeRTOS-Kernel smoke runs on FPGA at 100 MHz.
```

## Luu Y Quan Trong

- Truoc mat chi bring-up single-core.
- Chua nen day 150/200 MHz truoc khi board PASS o 100 MHz.
- `src/` la goi RTL phang. `fpga_top.v` la wrapper FPGA co dinh `SIM_MODE=0`, `ENABLE_CPU1=0`.
- Khong dung Verilog include-flow trong `src/`; compile RTL bang `script/rtl_sources.f`.
- Khi tao project Vivado, add cac file trong filelist va set top `fpga_top`.

## Thu Tu De Xuat

1. Chay simulation package bang `05_run_notebook_host_sim.bat` hoac `00_run_freertos_kernel_smoke_sim.bat`.
2. Tao Vivado project va add RTL theo `script/rtl_sources.f`.
3. Them constraint `.xdc` cho clock, reset, UART, GPIO/JTAG neu can.
4. Generate bitstream 100 MHz.
5. Nap bitstream len FPGA.
6. Gui `test_freertos_kernel_smoke.bin` bang `03_send_firmware_uart.bat`.
7. Doc UART log va tim `[PASS] freertos_kernel_smoke`.
8. Sau khi PASS, moi bat dau timing optimization len 125/150/200 MHz.

Neu ban muon chay 50 MHz, dung constraint trong:

```text
fpga/constraints/pynqz2_50mhz.sdc
fpga/constraints/pynqz2_50mhz.xdc
```

Heartbeat LED cua FreeRTOS duoc dua ra port `led_heartbeat` va firmware
toggling GPIO bit 0. Neu muon nhin LED tren board, map port nay ra chan LED
thuc te trong constraint.
