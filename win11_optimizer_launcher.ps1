$ErrorActionPreference = 'Stop'

$scriptPath = [IO.Path]::GetFullPath("$PSScriptRoot\win11_optimizer.ps1")
if (-not (Test-Path $scriptPath)) {
    Write-Host "[ERROR] win11_optimizer.ps1 not found at: $scriptPath"
    exit 1
}

$workDir = Split-Path -Path $scriptPath
$arguments = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', $scriptPath)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $workDir -Verb RunAs -PassThru -ErrorAction Stop
        $p.WaitForExit()
        exit $p.ExitCode
    } catch {
        Write-Host '[ERROR] Elevation was denied or failed.'
        exit 1
    }
}

Set-Location -Path $workDir
& $scriptPath
$exitCode = if ($null -eq $LASTEXITCODE) { if ($?) { 0 } else { 1 } } else { $LASTEXITCODE }
exit $exitCode
