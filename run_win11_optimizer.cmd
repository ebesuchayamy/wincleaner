@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%" >nul
set "PS_SCRIPT=%SCRIPT_DIR%win11_optimizer.ps1"

if not exist "%PS_SCRIPT%" (
    echo [ERROR] win11_optimizer.ps1 not found at: %PS_SCRIPT%
    popd >nul
    exit /b 1
)

set "PS_COMMAND=$script = [IO.Path]::GetFullPath('%PS_SCRIPT%'); ^
$workDir = Split-Path -Path $script; ^
$arguments = @('-NoProfile','-ExecutionPolicy','RemoteSigned','-File', $script); ^
$elevationError = '[ERROR] Elevation was denied or failed.'; ^
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); ^
if (-not $isAdmin) { ^
    try { ^
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $workDir -Verb RunAs -PassThru -ErrorAction Stop; ^
        $p.WaitForExit(); ^
        exit $p.ExitCode ^
    } catch { ^
        Write-Host $elevationError; ^
        exit 1 ^
    } ^
} ^
Set-Location -Path $workDir; ^
& $script; ^
$exitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } elseif ($?) { 0 } else { 1 }; ^
exit $exitCode"

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "%PS_COMMAND%"
set "EXITCODE=%ERRORLEVEL%"
popd >nul
exit /b %EXITCODE%
