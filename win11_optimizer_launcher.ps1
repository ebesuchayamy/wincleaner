$ErrorActionPreference = 'Stop'

$scriptPath = [IO.Path]::GetFullPath("$PSScriptRoot\win11_optimizer.ps1")
Function Pause-IfInteractive {
    param([string]$Message = $null)
    if ($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected) {
        if ($Message) { Write-Host $Message }
        Write-Host 'Нажмите Enter, чтобы закрыть окно...'
        [void]Read-Host
    }
}
if (-not (Test-Path $scriptPath)) {
    Write-Host "[ERROR] win11_optimizer.ps1 not found at: $scriptPath"
    Pause-IfInteractive
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
        Pause-IfInteractive '[ERROR] Elevation was denied или отменена.'
        exit 1
    }
}

Set-Location -Path $workDir
& $scriptPath
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) {
    $exitCode = if ($?) { 0 } else { 1 }
}
if ($exitCode -ne 0) {
    Pause-IfInteractive "Скрипт завершился с кодом $exitCode. Проверьте сообщения выше."
}
exit $exitCode
