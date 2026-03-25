@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "LAUNCHER=%SCRIPT_DIR%win11_optimizer_launcher.ps1"

if not exist "%LAUNCHER%" (
    echo [ERROR] win11_optimizer_launcher.ps1 not found at: %LAUNCHER%
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%LAUNCHER%"
set "EXITCODE=%ERRORLEVEL%"
exit /b %EXITCODE%
