@echo off
REM ============================================
REM lint_verilog.bat
REM Usage:
REM   lint_verilog <file.v>
REM   lint_verilog -g2012 <file.v>
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
    echo   lint_verilog cpu.v
    echo   lint_verilog -g2012 cpu.v
    exit /b 1
)

echo ============================================
echo Linting   : %SRC%
IF "%STD%"=="" (
    echo Standard : default
) ELSE (
    echo Standard : %STD%
)
echo ============================================

iverilog %STD% -Wall -tnull %SRC%
IF ERRORLEVEL 1 (
    echo [ERROR] Lint failed!
    exit /b 1
)

echo --------------------------------------------
echo Lint finished with no fatal errors.
echo ============================================
