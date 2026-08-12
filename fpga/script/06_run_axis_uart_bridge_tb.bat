@echo off
setlocal
pushd "%~dp0"

set TB=..\tb\tb_axis_uart_bridge.v
set RTL=..\src\axis_uart_bridge.v
set TOP=tb_axis_uart_bridge
set LOGDIR=..\sim_log
set WORKDIR=..\sim_work
set OUT=%WORKDIR%\%TOP%.vvp
set COMPILE_LOG=%LOGDIR%\iverilog_axis_uart_bridge.log
set RUN_LOG=%LOGDIR%\vvp_axis_uart_bridge.log

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%WORKDIR%" mkdir "%WORKDIR%"

iverilog -g2005 -s %TOP% -o "%OUT%" "%RTL%" "%TB%" > "%COMPILE_LOG%" 2>&1
if errorlevel 1 (
    echo [ERROR] iverilog failed. See %COMPILE_LOG%
    exit /b 1
)

vvp "%OUT%" > "%RUN_LOG%" 2>&1
if errorlevel 1 (
    echo [ERROR] vvp failed. See %RUN_LOG%
    exit /b 1
)

findstr /L /C:"[PASS] axis_uart_bridge notebook stream test" "%RUN_LOG%" >nul
if errorlevel 1 (
    echo [FAIL] PASS marker not found. See %RUN_LOG%
    exit /b 1
)

echo [OK] AXIS UART bridge TB PASS
echo      Log: %RUN_LOG%

popd
endlocal
