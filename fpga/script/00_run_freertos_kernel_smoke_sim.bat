@echo off
setlocal
pushd "%~dp0"

rem ================================================================
rem Terminal simulation for the FreeRTOS-Kernel smoke test.
rem Requires Icarus Verilog in PATH: iverilog + vvp.
rem ================================================================

set TB=..\tb\tb_freertos_kernel_smoke.v
set HEX=..\os\firmware\test_freertos_kernel_smoke.hex
set RTL_FILELIST=rtl_sources.f
set TOP=run_soc
set SNAPSHOT=run_soc_freertos_kernel_smoke
set LOGDIR=..\sim_log
set WORKDIR=..\sim_work
set OUT=%WORKDIR%\%SNAPSHOT%.vvp
set COMPILE_LOG=%LOGDIR%\iverilog_freertos_kernel_smoke.log
set RUN_LOG=%LOGDIR%\vvp_freertos_kernel_smoke.log

if not exist "%TB%" (
    echo [ERROR] Testbench not found: %TB%
    exit /b 1
)

if not exist "%HEX%" (
    echo [ERROR] Firmware HEX not found: %HEX%
    exit /b 1
)

if not exist "%RTL_FILELIST%" (
    echo [ERROR] RTL filelist not found: %RTL_FILELIST%
    exit /b 1
)

where iverilog >nul 2>nul
if errorlevel 1 (
    echo [ERROR] iverilog not found. Install Icarus Verilog or add it to PATH.
    exit /b 1
)

where vvp >nul 2>nul
if errorlevel 1 (
    echo [ERROR] vvp not found. Install Icarus Verilog or add it to PATH.
    exit /b 1
)

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%WORKDIR%" mkdir "%WORKDIR%"

echo ================================================================
echo  Terminal simulation: FreeRTOS-Kernel smoke
echo ================================================================
echo  RTL : %RTL_FILELIST%
echo  TB  : %TB%
echo  HEX : %HEX%
echo  TOP : %TOP%
echo.

echo [1/2] iverilog compile...
iverilog -g2005 -s %TOP% -D BAUD_DIV=16 -D LOG_LEVEL=0 -D FINISH_ON_PASS -f "%RTL_FILELIST%" -o "%OUT%" "%TB%" > "%COMPILE_LOG%" 2>&1
if errorlevel 1 (
    echo [ERROR] iverilog failed. See %COMPILE_LOG%
    exit /b 1
)

echo [2/2] vvp run...
vvp "%OUT%" +IMEM_HEX="%HEX%" > "%RUN_LOG%" 2>&1
if errorlevel 1 (
    echo [ERROR] vvp returned non-zero. See %RUN_LOG%
    exit /b 1
)

findstr /L /C:"[PASS] freertos_kernel_smoke" "%RUN_LOG%" >nul
if errorlevel 1 (
    echo [FAIL] PASS marker not found. See %RUN_LOG%
    exit /b 1
)

echo.
echo [OK] Simulation PASS: [PASS] freertos_kernel_smoke
echo      Log: %RUN_LOG%

popd
endlocal
