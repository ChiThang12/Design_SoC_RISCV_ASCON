@echo off
setlocal
pushd "%~dp0"

rem ================================================================
rem Send prebuilt FreeRTOS firmware to the FPGA UART bootloader.
rem Boot protocol: raw little-endian binary, no header, no ACK.
rem Edit COM_PORT for your board.
rem ================================================================

set COM_PORT=COM5
set BAUD=115200
set FW=..\os\firmware\test_freertos_kernel_smoke.bin

if not exist "%FW%" (
    echo [ERROR] Firmware binary not found: %FW%
    exit /b 1
)

echo Sending %FW% to %COM_PORT% at %BAUD% baud...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$port='%COM_PORT%'; $baud=%BAUD%; $fw=Resolve-Path '%FW%'; $bytes=[System.IO.File]::ReadAllBytes($fw); $sp=New-Object System.IO.Ports.SerialPort($port,$baud,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One); $sp.Open(); Start-Sleep -Milliseconds 200; $sp.Write($bytes,0,$bytes.Length); Start-Sleep -Milliseconds 200; $sp.Close(); Write-Host ('Sent {0} bytes' -f $bytes.Length)"

popd
endlocal
