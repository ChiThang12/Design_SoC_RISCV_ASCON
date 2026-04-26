@echo off
REM ============================================
REM run_verilog.bat (with log folder)
REM ============================================

SET STD=
SET SRC=

REM Parse arguments
IF "%~1"=="-g2001" (
    SET STD=-g2001
    SET SRC=%~2
) ELSE IF "%~1"=="-g2005" (
    SET STD=-g2005
    SET SRC=%~2
) ELSE IF "%~1"=="-g2012" (
    SET STD=-g2012
    SET SRC=%~2
) ELSE (
    SET SRC=%~1
)

IF "%SRC%"=="" (
    echo [ERROR] Missing verilog file!
    echo Usage:
    echo   run_verilog tb.v
    echo   run_verilog -g2012 tb.v
    exit /b 1
)

REM Extract file name without extension
FOR %%F IN (%SRC%) DO SET NAME=%%~nF

REM 👉 Tạo thư mục log nếu chưa có
SET LOG_DIR=log
IF NOT EXIST %LOG_DIR% (
    mkdir %LOG_DIR%
)

SET LOG=%LOG_DIR%\%NAME%.log

echo ============================================
echo Source   : %SRC%
IF "%STD%"=="" (
    echo Standard : default
) ELSE (
    echo Standard : %STD%
)
echo Output   : %NAME%.vvp
echo Log file : %LOG%
echo ============================================

iverilog %STD% -o %NAME%.vvp %SRC%
IF ERRORLEVEL 1 (
    echo [ERROR] Compilation failed!
    exit /b 1
)

echo --------------------------------------------
echo Running simulation...
echo --------------------------------------------

REM Ghi cả stdout + stderr vào log
vvp %NAME%.vvp > %LOG% 2>&1

echo --------------------------------------------
echo Done. Log saved to %LOG%
echo ============================================