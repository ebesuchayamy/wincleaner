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

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$script = [IO.Path]::GetFullPath('%PS_SCRIPT%'); $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if (-not $isAdmin) { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File', $script -Verb RunAs -Wait -PassThru; exit $p.ExitCode } & $script; exit $LASTEXITCODE"
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%
