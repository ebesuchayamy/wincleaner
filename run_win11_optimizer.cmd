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

set "PS_COMMAND=$script = [IO.Path]::GetFullPath('%PS_SCRIPT%'); ^
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); ^
if (-not $isAdmin) { ^
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','RemoteSigned','-File', $script -Verb RunAs -Wait -PassThru; ^
    exit $p.ExitCode ^
} ^
& $script; exit $LASTEXITCODE"

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "%PS_COMMAND%"
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%
