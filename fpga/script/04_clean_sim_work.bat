@echo off
setlocal
pushd "%~dp0"

rem Remove generated terminal-simulation work files.

if exist ..\sim_work rmdir /s /q ..\sim_work
if exist ..\sim_log\iverilog_*.log del /q ..\sim_log\iverilog_*.log
if exist ..\sim_log\vvp_*.log del /q ..\sim_log\vvp_*.log
if exist waveform_soc.vcd del /q waveform_soc.vcd
if exist ..\waveform_soc.vcd del /q ..\waveform_soc.vcd

echo Clean done.

popd
endlocal
