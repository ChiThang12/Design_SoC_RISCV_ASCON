@echo off
REM ============================================
REM clean.bat
REM Remove simulation/build generated files
REM ============================================

echo ============================================
echo Cleaning generated files...
echo ============================================

DEL /Q *.vvp 2>NUL
DEL /Q *.vcd 2>NUL
DEL /Q *.log 2>NUL
DEL /Q *.out 2>NUL
DEL /Q *.fst 2>NUL

echo --------------------------------------------
echo Clean done.
echo ============================================
