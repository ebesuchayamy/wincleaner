#Requires -RunAsAdministrator
# Win11 Optimizer — PowerShell GUI Application

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#region Configuration
$script:AppName    = "Win11 Optimizer"
$script:DataDir    = "$env:ProgramData\Win11Optimizer"
$script:LogPath    = "$script:DataDir\log.txt"
$script:BackupPath = "$script:DataDir\backup.json"
#endregion

#region Init
if (-not (Test-Path $script:DataDir)) {
    New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
}
#endregion

#region Helpers

Function Write-Log {
    param([string]$Message)
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

Function Load-Backup {
    if (Test-Path $script:BackupPath) {
        $json = Get-Content $script:BackupPath -Raw -Encoding UTF8
        $obj  = $json | ConvertFrom-Json
        # ConvertFrom-Json returns a fixed-size array in Items; convert to ArrayList
        $list = [System.Collections.ArrayList]@()
        foreach ($i in $obj.Items) { [void]$list.Add($i) }
        return [PSCustomObject]@{ Items = $list }
    }
    return [PSCustomObject]@{ Items = [System.Collections.ArrayList]@() }
}

Function Save-Backup {
    param($Backup)
    $Backup | ConvertTo-Json -Depth 10 | Set-Content $script:BackupPath -Encoding UTF8
}

Function Set-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        $backup  = Load-Backup
        $existed = $false
        $oldValue = $null
        $oldType  = $Type

        if (Test-Path $Path) {
            $prop = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $prop) {
                $existed  = $true
                $oldValue = $prop.$Name
                # Determine existing registry value kind
                $isHKLM  = $Path -match '^HKLM:'
                $subPath = $Path -replace '^HK[LC][MU]:\\', ''
                try {
                    $rootKey = if ($isHKLM) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
                    $rk      = $rootKey.OpenSubKey($subPath)
                    if ($rk) {
                        $oldType = $rk.GetValueKind($Name).ToString()
                        $rk.Close()
                    }
                } catch { }
            }
        }

        $entry = [PSCustomObject]@{
            Type     = "Registry"
            Path     = $Path
            Name     = $Name
            OldValue = $oldValue
            OldType  = $oldType
            Existed  = $existed
        }
        [void]$backup.Items.Add($entry)
        Save-Backup $backup

        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        Write-Log "Реестр: $Path\$Name = $Value (Тип=$Type)"
    } catch {
        Write-Log "ОШИБКА Set-RegistryValueSafe: $_"
    }
}

Function Backup-ServiceState {
    param([string]$ServiceName)
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        $wmi = Get-WmiObject Win32_Service -Filter "Name='$ServiceName'" -ErrorAction Stop
        $backup = Load-Backup
        $entry = [PSCustomObject]@{
            Type           = "Service"
            Name           = $ServiceName
            OldStartupType = $wmi.StartMode
            OldRunning     = ($svc.Status -eq 'Running')
        }
        [void]$backup.Items.Add($entry)
        Save-Backup $backup
        Write-Log "Резерв службы: $ServiceName (StartMode=$($entry.OldStartupType), Running=$($entry.OldRunning))"
    } catch {
        Write-Log "ОШИБКА Backup-ServiceState ($ServiceName): $_"
    }
}

Function Confirm-Action {
    param(
        [string]$Title,
        [string]$Message
    )
    $result = [System.Windows.Forms.MessageBox]::Show(
        $Message, $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

Function Undo-Changes {
    if (-not (Test-Path $script:BackupPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Файл резервной копии не найден.",
            "Отмена изменений",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    $backup = Load-Backup
    if ($backup.Items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Нет сохранённых изменений для отмены.",
            "Отмена изменений",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    $count = 0
    foreach ($item in $backup.Items) {
        try {
            if ($item.Type -eq "Registry") {
                if ($item.Existed) {
                    if (-not (Test-Path $item.Path)) {
                        New-Item -Path $item.Path -Force | Out-Null
                    }
                    Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.OldValue
                    Write-Log "Undo реестр: $($item.Path)\$($item.Name) = $($item.OldValue)"
                } else {
                    if (Test-Path $item.Path) {
                        Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
                        Write-Log "Undo реестр (удалено): $($item.Path)\$($item.Name)"
                    }
                }
                $count++
            } elseif ($item.Type -eq "Service") {
                $startMap = @{
                    "Auto"      = "Automatic"
                    "Automatic" = "Automatic"
                    "Manual"    = "Manual"
                    "Disabled"  = "Disabled"
                }
                $startType = if ($startMap.ContainsKey($item.OldStartupType)) { $startMap[$item.OldStartupType] } else { "Manual" }
                Set-Service -Name $item.Name -StartupType $startType -ErrorAction SilentlyContinue
                if ($item.OldRunning) {
                    Start-Service -Name $item.Name -ErrorAction SilentlyContinue
                }
                Write-Log "Undo служба: $($item.Name) -> StartupType=$startType, Running=$($item.OldRunning)"
                $count++
            }
        } catch {
            $loc = if ($item.Type -eq "Service") { $item.Name } else { "$($item.Path)\$($item.Name)" }
            Write-Log "ОШИБКА Undo ($($item.Type) / $loc): $_"
        }
    }
    Save-Backup ([PSCustomObject]@{ Items = [System.Collections.ArrayList]@() })
    [System.Windows.Forms.MessageBox]::Show(
        "Отменено изменений: $count.",
        "Отмена изменений",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    Write-Log "Undo завершён: восстановлено $count изменений."
}

#endregion

#region Optimization (Services)

Function Disable-SysMain {
    if (-not (Confirm-Action "Отключение SysMain" (
        "Будет отключена служба SysMain (SuperFetch).`r`n" +
        "Это снизит нагрузку на HDD/SSD, но может немного замедлить`r`n" +
        "первый запуск приложений.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    Backup-ServiceState "SysMain"
    try {
        Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
        Set-Service  -Name "SysMain" -StartupType Disabled
        Write-Log "SysMain отключена."
        [System.Windows.Forms.MessageBox]::Show("SysMain успешно отключена.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-Log "ОШИБКА Disable-SysMain: $_"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Function Disable-WindowsSearch {
    if (-not (Confirm-Action "Отключение Windows Search" (
        "Будет отключена служба Windows Search (индексирование файлов).`r`n" +
        "Поиск через меню Пуск будет работать медленнее.`r`n`r`n" +
        "Риск: СРЕДНИЙ`r`n`r`nПродолжить?"
    ))) { return }
    Backup-ServiceState "WSearch"
    try {
        Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
        Set-Service  -Name "WSearch" -StartupType Disabled
        Write-Log "WSearch отключена."
        [System.Windows.Forms.MessageBox]::Show("Windows Search успешно отключена.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-Log "ОШИБКА Disable-WindowsSearch: $_"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Function Disable-DiagTrack {
    if (-not (Confirm-Action "Отключение DiagTrack" (
        "Будет отключена служба диагностического отслеживания`r`n" +
        "(Connected User Experiences and Telemetry).`r`n" +
        "Microsoft перестанет получать телеметрические данные с этого ПК.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    Backup-ServiceState "DiagTrack"
    try {
        Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
        Set-Service  -Name "DiagTrack" -StartupType Disabled
        Write-Log "DiagTrack отключена."
        [System.Windows.Forms.MessageBox]::Show("DiagTrack успешно отключена.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-Log "ОШИБКА Disable-DiagTrack: $_"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

#endregion

#region Cleaning

Function Clear-TempFiles {
    if (-not (Confirm-Action "Очистка временных файлов" (
        "Будут удалены временные файлы из папок %TEMP% и Windows\Temp.`r`n" +
        "Некоторые файлы могут быть заблокированы открытыми приложениями.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    try {
        $paths = @("$env:TEMP", "$env:SystemRoot\Temp")
        $count = 0
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $items = Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($i in $items) {
                    Remove-Item -Path $i.FullName -Force -Recurse -ErrorAction SilentlyContinue
                    $count++
                }
            }
        }
        Write-Log "Временные файлы: удалено объектов $count."
        [System.Windows.Forms.MessageBox]::Show("Удалено объектов: $count.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-Log "ОШИБКА Clear-TempFiles: $_"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Function Clear-Prefetch {
    if (-not (Confirm-Action "Очистка Prefetch" (
        "Будут удалены файлы Prefetch из C:\Windows\Prefetch.`r`n" +
        "Первый запуск приложений после очистки может быть медленнее.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    try {
        $p = "$env:SystemRoot\Prefetch"
        if (Test-Path $p) {
            $count = (Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue | Measure-Object).Count
            Remove-Item -Path "$p\*" -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "Prefetch очищен: удалено $count файлов."
            [System.Windows.Forms.MessageBox]::Show("Prefetch очищен ($count файлов).", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            [System.Windows.Forms.MessageBox]::Show("Папка Prefetch не найдена.", "Информация", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    } catch {
        Write-Log "ОШИБКА Clear-Prefetch: $_"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

Function Clear-EventLogs {
    if (-not (Confirm-Action "Очистка журналов событий" (
        "Все журналы событий Windows будут очищены.`r`n" +
        "Это может затруднить диагностику прошлых проблем.`r`n`r`n" +
        "Риск: СРЕДНИЙ`r`n`r`nПродолжить?"
    ))) { return }
    try {
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 }
        foreach ($log in $logs) {
            try {
                [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($log.LogName)
            } catch { }
        }
        Write-Log "Журналы событий очищены."
        [System.Windows.Forms.MessageBox]::Show("Журналы событий успешно очищены.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-Log "ОШИБКА Clear-EventLogs: $_"
        [System.Windows.Forms.MessageBox]::Show("Ошибка: $_", "Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

#endregion

#region Privacy

Function Disable-AdvertisingId {
    if (-not (Confirm-Action "Отключение рекламного ID" (
        "Будет отключён рекламный идентификатор Windows для текущего пользователя.`r`n" +
        "Приложения больше не смогут использовать его для таргетированной рекламы.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" `
        -Name "Enabled" -Value 0 -Type "DWord"
    Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 -Type "DWord"
    Write-Log "Рекламный ID отключён."
    [System.Windows.Forms.MessageBox]::Show("Рекламный идентификатор отключён.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

Function Disable-TailoredExperiences {
    if (-not (Confirm-Action "Отключение персонализированных предложений" (
        "Будут отключены персонализированные предложения и рекомендации Microsoft.`r`n" +
        "Содержимое экрана блокировки и меню Пуск станет менее персонализированным.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Set-RegistryValueSafe -Path $cdmPath -Name "SubscribedContent-338393Enabled" -Value 0 -Type "DWord"
    Set-RegistryValueSafe -Path $cdmPath -Name "SubscribedContent-353694Enabled" -Value 0 -Type "DWord"
    Set-RegistryValueSafe -Path $cdmPath -Name "SubscribedContent-353696Enabled" -Value 0 -Type "DWord"
    Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" `
        -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Type "DWord"
    Write-Log "Персонализированные предложения отключены."
    [System.Windows.Forms.MessageBox]::Show("Персонализированные предложения отключены.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

Function Set-MinimalDiagnosticData {
    if (-not (Confirm-Action "Минимизация диагностики" (
        "Уровень диагностических данных будет установлен на минимальный (Basic).`r`n" +
        "Обновления Windows продолжат работать в штатном режиме.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    # AllowTelemetry: 1 = Basic (minimum for Home/Pro; 0 = Security, Enterprise only)
    Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 1 -Type "DWord"
    Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" `
        -Name "AllowTelemetry" -Value 1 -Type "DWord"
    Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" `
        -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Type "DWord"
    Write-Log "Уровень диагностики снижен до минимума."
    [System.Windows.Forms.MessageBox]::Show("Уровень диагностики снижен до минимума.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

Function Disable-AppLaunchTracking {
    if (-not (Confirm-Action "Отключение отслеживания запуска приложений" (
        "Будет отключено отслеживание запуска приложений,`r`n" +
        "используемое для формирования предложений в меню Пуск.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    Set-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
        -Name "Start_TrackProgs" -Value 0 -Type "DWord"
    Write-Log "Отслеживание запуска приложений отключено."
    [System.Windows.Forms.MessageBox]::Show("Отслеживание запуска приложений отключено.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

Function Disable-TipsAndSuggestions {
    if (-not (Confirm-Action "Отключение советов и предложений" (
        "Будут отключены советы, предложения и потребительские функции Windows.`r`n" +
        "Экран блокировки и центр уведомлений не будут показывать подсказки.`r`n`r`n" +
        "Риск: НИЗКИЙ`r`n`r`nПродолжить?"
    ))) { return }
    $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Set-RegistryValueSafe -Path $cdmPath -Name "SoftLandingEnabled"          -Value 0 -Type "DWord"
    Set-RegistryValueSafe -Path $cdmPath -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type "DWord"
    Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" -Value 1 -Type "DWord"
    Set-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableSoftLanding" -Value 1 -Type "DWord"
    Write-Log "Советы и предложения Windows отключены."
    [System.Windows.Forms.MessageBox]::Show("Советы и предложения отключены.", "Готово", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

#endregion

#region GUI

$form = New-Object System.Windows.Forms.Form
$form.Text            = $script:AppName
$form.Size            = New-Object System.Drawing.Size(620, 510)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

$tabControl          = New-Object System.Windows.Forms.TabControl
$tabControl.Size     = New-Object System.Drawing.Size(596, 440)
$tabControl.Location = New-Object System.Drawing.Point(8, 8)

# Helper: create a standard button
Function New-TabButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 270, [int]$H = 38)
    $b          = New-Object System.Windows.Forms.Button
    $b.Text     = $Text
    $b.Size     = New-Object System.Drawing.Size($W, $H)
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    return $b
}

# ── Tab 1: Оптимизация ──────────────────────────────────────────────────────
$tabOpt      = New-Object System.Windows.Forms.TabPage
$tabOpt.Text = "Оптимизация"

$btnSysMain   = New-TabButton "Отключить SysMain"         10  10
$btnWSearch   = New-TabButton "Отключить Windows Search"  10  58
$btnDiagTrack = New-TabButton "Отключить DiagTrack"       10 106

$btnSysMain.Add_Click(   { Disable-SysMain })
$btnWSearch.Add_Click(   { Disable-WindowsSearch })
$btnDiagTrack.Add_Click( { Disable-DiagTrack })

$lblOptHint          = New-Object System.Windows.Forms.Label
$lblOptHint.Text     = "Службы можно восстановить на вкладке «Восстановление»."
$lblOptHint.Size     = New-Object System.Drawing.Size(540, 20)
$lblOptHint.Location = New-Object System.Drawing.Point(10, 160)

$tabOpt.Controls.AddRange(@($btnSysMain, $btnWSearch, $btnDiagTrack, $lblOptHint))

# ── Tab 2: Очистка ───────────────────────────────────────────────────────────
$tabClean      = New-Object System.Windows.Forms.TabPage
$tabClean.Text = "Очистка"

$btnTemp      = New-TabButton "Очистить %TEMP%"              10  10
$btnPrefetch  = New-TabButton "Очистить Prefetch"            10  58
$btnEventLogs = New-TabButton "Очистить журналы событий"     10 106

$btnTemp.Add_Click(      { Clear-TempFiles })
$btnPrefetch.Add_Click(  { Clear-Prefetch })
$btnEventLogs.Add_Click( { Clear-EventLogs })

$lblCleanHint          = New-Object System.Windows.Forms.Label
$lblCleanHint.Text     = "Очистка файлов необратима — резервная копия не создаётся."
$lblCleanHint.Size     = New-Object System.Drawing.Size(540, 20)
$lblCleanHint.Location = New-Object System.Drawing.Point(10, 160)

$tabClean.Controls.AddRange(@($btnTemp, $btnPrefetch, $btnEventLogs, $lblCleanHint))

# ── Tab 3: Конфиденциальность (NEW) ─────────────────────────────────────────
$tabPrivacy      = New-Object System.Windows.Forms.TabPage
$tabPrivacy.Text = "Конфиденциальность"

$btnAdvId    = New-TabButton "Отключить рекламный ID"                    10  10
$btnTailored = New-TabButton "Отключить персонализированные предложения"  10  58
$btnDiagMin  = New-TabButton "Минимизировать диагностику"                10 106
$btnAppTrack = New-TabButton "Откл. отслеживание запуска приложений"     10 154
$btnTips     = New-TabButton "Отключить советы и предложения"            10 202

$btnAdvId.Add_Click(    { Disable-AdvertisingId })
$btnTailored.Add_Click( { Disable-TailoredExperiences })
$btnDiagMin.Add_Click(  { Set-MinimalDiagnosticData })
$btnAppTrack.Add_Click( { Disable-AppLaunchTracking })
$btnTips.Add_Click(     { Disable-TipsAndSuggestions })

$lblPrivHint          = New-Object System.Windows.Forms.Label
$lblPrivHint.Text     = "Изменения реестра можно отменить на вкладке «Восстановление»."
$lblPrivHint.Size     = New-Object System.Drawing.Size(540, 20)
$lblPrivHint.Location = New-Object System.Drawing.Point(10, 256)

$tabPrivacy.Controls.AddRange(@($btnAdvId, $btnTailored, $btnDiagMin, $btnAppTrack, $btnTips, $lblPrivHint))

# ── Tab 4: Восстановление ────────────────────────────────────────────────────
$tabRestore      = New-Object System.Windows.Forms.TabPage
$tabRestore.Text = "Восстановление"

$lblRestoreInfo          = New-Object System.Windows.Forms.Label
$lblRestoreInfo.Text     = "Восстановить изменения из резервной копии (реестр и службы):"
$lblRestoreInfo.Size     = New-Object System.Drawing.Size(540, 20)
$lblRestoreInfo.Location = New-Object System.Drawing.Point(10, 10)

$btnUndo = New-TabButton "Отменить все изменения (Undo)" 10 40 300 42
$btnUndo.Add_Click({ Undo-Changes })

$lblPaths          = New-Object System.Windows.Forms.Label
$lblPaths.Text     = "Журнал:  $script:LogPath`r`nРезерв: $script:BackupPath"
$lblPaths.Size     = New-Object System.Drawing.Size(560, 40)
$lblPaths.Location = New-Object System.Drawing.Point(10, 100)

$lblUndoNote          = New-Object System.Windows.Forms.Label
$lblUndoNote.Text     = "Undo восстанавливает реестр и службы.`r`nУдалённые файлы и деинсталлированные приложения не восстанавливаются."
$lblUndoNote.Size     = New-Object System.Drawing.Size(560, 40)
$lblUndoNote.Location = New-Object System.Drawing.Point(10, 155)

$tabRestore.Controls.AddRange(@($lblRestoreInfo, $btnUndo, $lblPaths, $lblUndoNote))

# ── Assemble ─────────────────────────────────────────────────────────────────
$tabControl.TabPages.AddRange(@($tabOpt, $tabClean, $tabPrivacy, $tabRestore))
$form.Controls.Add($tabControl)

$lblStatus          = New-Object System.Windows.Forms.Label
$lblStatus.Text     = "Лог: $script:LogPath"
$lblStatus.Size     = New-Object System.Drawing.Size(596, 20)
$lblStatus.Location = New-Object System.Drawing.Point(8, 458)
$form.Controls.Add($lblStatus)

#endregion

Write-Log "Win11 Optimizer запущен."
[void]$form.ShowDialog()
