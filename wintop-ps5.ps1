#requires -Version 5.1
<#
.SYNOPSIS
    WinTop PS5 - Windows process/system monitor for Windows PowerShell 5.1.

.DESCRIPTION
    PowerShell 5.1 compatible version of WinTop.
    The interactive keyboard handling is deliberately implemented separately
    from the original WinTop script so sorting/filtering changes are applied
    to the same script-scope state that renders the display.

    Run this from a real console host (powershell.exe, Windows Terminal,
    ConEmu, etc.). PowerShell ISE does not provide a compatible interactive
    console input stream.

.KEYS
    P / 1  CPU       M / 2  Memory       N / 3  PID
    4       Name     5       Threads     6       Handles
    7       CPU Time
    K       Kill PID  D       Delay       /       Filter
    E       Export   + / =   More        -       Less
    Q       Quit
#>

$ErrorActionPreference = 'SilentlyContinue'

# Everything that is changed by a key handler is explicitly script-scoped.
$script:RefreshSeconds = 2
$script:TopCount       = 30
$script:SortBy         = 'CPUPercent'
$script:Descending     = $true
$script:Previous       = @{}
$script:FilterText     = ''
$script:QuitRequested  = $false
$script:ExportRequested = $false
$script:StatusMessage  = ''

function Read-WinTopLine {
    param([string]$Prompt)

    Write-Host ''
    Write-Host -NoNewline $Prompt

    # ReadLine is reliable in Windows PowerShell 5.1 console hosts.
    $value = [Console]::ReadLine()
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Set-WinTopSort {
    param(
        [string]$Column,
        [bool]$Descending
    )

    $script:SortBy = $Column
    $script:Descending = $Descending
    $script:StatusMessage = 'Sort set to {0}' -f $Column
}

function Set-WinTopDelay {
    Clear-Host
    $value = Read-WinTopLine 'New refresh interval in seconds: '

    $seconds = 0
    if ([int]::TryParse($value, [ref]$seconds) -and $seconds -gt 0) {
        $script:RefreshSeconds = $seconds
        $script:StatusMessage = 'Refresh interval set to {0} second(s)' -f $seconds
    }
    else {
        $script:StatusMessage = 'Invalid refresh interval'
    }
}

function Invoke-WinTopKill {
    Clear-Host
    $value = Read-WinTopLine 'PID to kill: '

    $pidValue = 0
    if (-not [int]::TryParse($value, [ref]$pidValue)) {
        $script:StatusMessage = 'Invalid PID'
        return
    }

    $target = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if ($null -eq $target) {
        $script:StatusMessage = 'PID {0} not found' -f $pidValue
        return
    }

    $confirm = Read-WinTopLine ('Kill {0} [{1}]? y/N: ' -f $target.ProcessName, $pidValue)

    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
        $script:StatusMessage = 'Killed PID {0}' -f $pidValue
    }
    else {
        $script:StatusMessage = 'Kill cancelled'
    }
}

function Invoke-WinTopFilter {
    Clear-Host
    $value = Read-WinTopLine 'Filter process name, blank clears filter: '
    $script:FilterText = if ($null -eq $value) { '' } else { $value.Trim() }

    if ([string]::IsNullOrWhiteSpace($script:FilterText)) {
        $script:FilterText = ''
        $script:StatusMessage = 'Filter cleared'
    }
    else {
        $script:StatusMessage = 'Filter set to "{0}"' -f $script:FilterText
    }
}

function Handle-WinTopKey {
    param([char]$KeyChar)

    switch ([string]$KeyChar) {
        'q' { $script:QuitRequested = $true }
        'Q' { $script:QuitRequested = $true }

        '1' { Set-WinTopSort 'CPUPercent' $true }
        '2' { Set-WinTopSort 'WS_MB' $true }
        '3' { Set-WinTopSort 'PID' $false }
        '4' { Set-WinTopSort 'Process' $false }
        '5' { Set-WinTopSort 'Threads' $true }
        '6' { Set-WinTopSort 'Handles' $true }
        '7' { Set-WinTopSort 'CPUTime' $true }

        'P' { Set-WinTopSort 'CPUPercent' $true }
        'p' { Set-WinTopSort 'CPUPercent' $true }

        'M' { Set-WinTopSort 'WS_MB' $true }
        'm' { Set-WinTopSort 'WS_MB' $true }

        'N' { Set-WinTopSort 'PID' $false }
        'n' { Set-WinTopSort 'PID' $false }

        '+' { $script:TopCount += 5; $script:StatusMessage = 'Showing {0} processes' -f $script:TopCount }
        '=' { $script:TopCount += 5; $script:StatusMessage = 'Showing {0} processes' -f $script:TopCount }

        '-' {
            if ($script:TopCount -gt 5) {
                $script:TopCount -= 5
            }
            $script:StatusMessage = 'Showing {0} processes' -f $script:TopCount
        }

        '/' { Invoke-WinTopFilter }

        'D' { Set-WinTopDelay }
        'd' { Set-WinTopDelay }

        'K' { Invoke-WinTopKill }
        'k' { Invoke-WinTopKill }

        'E' { $script:ExportRequested = $true }
        'e' { $script:ExportRequested = $true }
    }
}

function Test-WinTopConsole {
    try {
        $null = [Console]::KeyAvailable
        return $true
    }
    catch {
        return $false
    }
}

function Read-WinTopPendingKeys {
    # Returns $true if at least one key was handled.
    $handled = $false

    try {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            Handle-WinTopKey $key.KeyChar
            $handled = $true

            if ($script:QuitRequested) {
                break
            }
        }
    }
    catch {
        # Do not silently make the keyboard appear broken.
        $script:StatusMessage = 'Console input is unavailable. Run this script in a console window.'
    }

    return $handled
}

function Wait-WinTop {
    param([int]$Seconds)

    $end = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $end -and -not $script:QuitRequested) {
        if (Read-WinTopPendingKeys) {
            # A command was received. Redraw immediately instead of waiting
            # for the remainder of the refresh interval.
            return
        }

        Start-Sleep -Milliseconds 75
    }
}

function Write-WinTopProcessRow {
    param($Process)

    $line = '{0,7} {1,8} {2,9} {3,9} {4,9} {5,9} {6,9} {7}' -f `
        $Process.PID,
        $Process.CPUPercent,
        $Process.CPUTime,
        $Process.WS_MB,
        $Process.PM_MB,
        $Process.Handles,
        $Process.Threads,
        $Process.Process

    if ($Process.CPUPercent -ge 50) {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($Process.CPUPercent -ge 20) {
        Write-Host $line -ForegroundColor Yellow
    }
    else {
        Write-Host $line
    }
}

if (-not (Test-WinTopConsole)) {
    Write-Host 'WinTop PS5 must be run from a real console host.' -ForegroundColor Yellow
    Write-Host 'Use Windows PowerShell 5.1 (powershell.exe), Windows Terminal, or another console host.'
    exit 1
}

while (-not $script:QuitRequested) {

    # Process keys that arrived while the previous screen was being drawn.
    Read-WinTopPendingKeys | Out-Null

    if ($script:QuitRequested) {
        break
    }

    $rawProcesses = @(Get-Process -ErrorAction SilentlyContinue)

    # Apply the filter BEFORE calculating/sorting the displayed process objects.
    if (-not [string]::IsNullOrWhiteSpace($script:FilterText)) {
        $pattern = '*' + $script:FilterText + '*'
        $rawProcesses = @(
            $rawProcesses | Where-Object {
                $_.ProcessName -like $pattern
            }
        )
    }

    $processes = @(
        $rawProcesses | ForEach-Object {
            try {
                $id = $_.Id

                $cpuSeconds = 0
                try {
                    if ($null -ne $_.CPU) {
                        $cpuSeconds = [double]$_.CPU
                    }
                } catch {}

                $cpuPercent = 0

                if ($script:Previous.ContainsKey($id)) {
                    $cpuDelta = $cpuSeconds - $script:Previous[$id]
                    if ($cpuDelta -ge 0 -and $script:RefreshSeconds -gt 0) {
                        $cpuPercent = ($cpuDelta / $script:RefreshSeconds) * 100
                    }
                }

                $script:Previous[$id] = $cpuSeconds

                $handleValue = 0
                $threadValue = 0
                $respondingValue = $true

                try { $handleValue = $_.Handles } catch {}
                try { $threadValue = $_.Threads.Count } catch {}
                try { $respondingValue = $_.Responding } catch {}

                [PSCustomObject]@{
                    PID        = $_.Id
                    CPUPercent = [math]::Round($cpuPercent, 1)
                    CPUTime    = [math]::Round($cpuSeconds, 1)
                    WS_MB      = [math]::Round($_.WorkingSet64 / 1MB, 1)
                    PM_MB      = [math]::Round($_.PagedMemorySize64 / 1MB, 1)
                    Handles    = $handleValue
                    Threads    = $threadValue
                    Responding = $respondingValue
                    Process    = $_.ProcessName
                }
            }
            catch {}
        }
    )

    if ($script:Descending) {
        $topProcesses = @(
            $processes |
                Sort-Object -Property $script:SortBy -Descending |
                Select-Object -First $script:TopCount
        )
    }
    else {
        $topProcesses = @(
            $processes |
                Sort-Object -Property $script:SortBy |
                Select-Object -First $script:TopCount
        )
    }

    if ($script:ExportRequested) {
        $exportPath = Join-Path $PWD ('WinTop_PS5_Export_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $topProcesses | Export-Csv -Path $exportPath -NoTypeInformation
        $script:StatusMessage = 'Exported current view to {0}' -f $exportPath
        $script:ExportRequested = $false
    }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    $uptimeText = 'N/A'
    if ($null -ne $os -and $null -ne $os.LastBootUpTime) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeText = '{0} days, {1:00}:{2:00}:{3:00}' -f `
            $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds
    }

    $cpuLoad = 0
    if ($cpu.Count -gt 0) {
        $cpuLoadValue = ($cpu | Measure-Object -Property LoadPercentage -Average).Average
        if ($null -ne $cpuLoadValue) {
            $cpuLoad = [math]::Round($cpuLoadValue, 1)
        }
    }

    $cpuCount = 0
    if ($null -ne $computerSystem) {
        $cpuCount = $computerSystem.NumberOfLogicalProcessors
    }

    $loggedOnUsers = 0
    try {
        $loggedOnUsers = @(quser 2>$null | Select-Object -Skip 1).Count
    }
    catch {}

    $totalMem = 0
    $freeMem = 0
    if ($null -ne $os) {
        $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeMem = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    }
    $usedMem = [math]::Round($totalMem - $freeMem, 1)

    $threadCount = @(
        $rawProcesses | ForEach-Object {
            try { $_.Threads.Count } catch { 0 }
        }
    ) | Measure-Object -Sum
    $threadCount = if ($null -ne $threadCount.Sum) { $threadCount.Sum } else { 0 }

    $handleCount = @(
        $rawProcesses | ForEach-Object {
            try { $_.Handles } catch { 0 }
        }
    ) | Measure-Object -Sum
    $handleCount = if ($null -ne $handleCount.Sum) { $handleCount.Sum } else { 0 }

    $respondingCount = @($processes | Where-Object { $_.Responding -eq $true }).Count
    $notRespondingCount = @($processes | Where-Object { $_.Responding -eq $false }).Count

    $topMemoryConsumers = @(
        $processes |
            Sort-Object -Property WS_MB -Descending |
            Select-Object -First 5
    )

    Clear-Host

    Write-Host ('Windows top PS5 - {0}' -f (Get-Date))
    Write-Host ('Uptime: {0} | Users: {1} | CPU load: {2}% | Logical CPUs: {3}' -f $uptimeText, $loggedOnUsers, $cpuLoad, $cpuCount)
    Write-Host ('Tasks: {0} | Responding: {1} | Not Responding: {2}' -f $rawProcesses.Count, $respondingCount, $notRespondingCount)
    Write-Host ('Threads: {0} | Handles: {1}' -f $threadCount, $handleCount)
    Write-Host ('Memory: {0} MB used / {1} MB total' -f $usedMem, $totalMem)
    Write-Host ('Sort: {0} | Refresh: {1}s | Showing: {2} | Filter: {3}' -f `
        $script:SortBy, $script:RefreshSeconds, $script:TopCount,
        $(if ([string]::IsNullOrWhiteSpace($script:FilterText)) { '<none>' } else { $script:FilterText }))

    if ($script:StatusMessage -ne '') {
        Write-Host ('Status: {0}' -f $script:StatusMessage) -ForegroundColor Green
        $script:StatusMessage = ''
    }

    Write-Host 'Keys: P/1=CPU  M/2=Mem  N/3=PID  4=Name  5=Threads  6=Handles  7=CPUTime'
    Write-Host '      K=Kill  D=Delay  /=Filter  E=Export  +=More  -=Less  Q=Quit'
    Write-Host ''

    Write-Host 'Top Memory Consumers:'
    foreach ($memProc in $topMemoryConsumers) {
        Write-Host ('  {0,-25} {1,10} MB' -f $memProc.Process, $memProc.WS_MB)
    }

    Write-Host ''

    Write-Host ('{0,7} {1,8} {2,9} {3,9} {4,9} {5,9} {6,9} {7}' -f `
        'PID', 'CPU %', 'CPU Time', 'WS MB', 'PM MB', 'Handles', 'Threads', 'Process')

    Write-Host ('{0,7} {1,8} {2,9} {3,9} {4,9} {5,9} {6,9} {7}' -f `
        '---', '-----', '--------', '-----', '-----', '-------', '-------', '-------')

    foreach ($proc in $topProcesses) {
        Write-WinTopProcessRow -Process $proc
    }

    Wait-WinTop -Seconds $script:RefreshSeconds
}

Clear-Host
Write-Host 'WinTop PS5 stopped.'
