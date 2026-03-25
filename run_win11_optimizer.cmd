@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul
set "PS_SCRIPT=%SCRIPT_DIR%win11_optimizer.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] win11_optimizer.ps1 not found in %SCRIPT_DIR%
    popd >nul
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%
