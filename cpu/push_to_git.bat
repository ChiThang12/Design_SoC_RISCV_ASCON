@echo off
REM ============================================
REM push_to_git.bat
REM Usage:
REM   push_to_git "commit message"
REM ============================================

IF "%~1"=="" (
    echo [ERROR] Missing commit message!
    echo Usage:
    echo   push_to_git "commit message"
    exit /b 1
)

SET MSG=%~1

echo ============================================
echo Git add + commit
echo Message: "%MSG%"
echo ============================================

git add .

git commit -m "%MSG%"
IF ERRORLEVEL 1 (
    echo [ERROR] Git commit failed!
    exit /b 1
)

echo --------------------------------------------
echo Commit done successfully.
echo ============================================
