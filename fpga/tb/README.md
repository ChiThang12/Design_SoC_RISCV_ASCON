# Testbench

Main terminal simulation testbench:

```text
tb_freertos_kernel_smoke.v
```

It instantiates `soc_hs` in simulation mode and loads the prebuilt firmware:

```text
../os/firmware/test_freertos_kernel_smoke.hex
```

Run from Windows terminal with Icarus Verilog in `PATH`:

```bat
cd fpga\script
00_run_freertos_kernel_smoke_sim.bat
```

Expected marker:

```text
[PASS] freertos_kernel_smoke
```
