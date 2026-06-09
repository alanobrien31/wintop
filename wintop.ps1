###############################################################################
#
# Script Name : WinTop.ps1
# Version     : 1.1.2
# Author      : Alan O'Brien
# Created     : 09-Jun-2026
# Last Updated: 09-Jun-2026
#
# Description:
# ------------
# WinTop is a Linux "top" inspired monitoring utility for Microsoft Windows.
# It provides a live refreshing view of process, memory, CPU and system activity
# directly from PowerShell.
#
# Keyboard Commands:
# ------------------
# Q    - Quit
# P/1  - Sort by CPU %
# M/2  - Sort by Memory
# N/3  - Sort by PID
# 4    - Sort by Process Name
# 5    - Sort by Thread Count
# 6    - Sort by Handle Count
# 7    - Sort by Total CPU Time
# K    - Kill Process by PID
# D    - Change Refresh Delay
# /    - Filter Process Name
# E    - Export Current View to CSV
# +    - Increase Number of Displayed Processes
# -    - Decrease Number of Displayed Processes
#
###############################################################################

$ErrorActionPreference = "SilentlyContinue"

$refreshSeconds = 2
$topCount = 30
$sortBy = "CPUPercent"
$descending = $true
$previous = @{}
$filter = ""
$quit = $false
$exportRequested = $false
$statusMessage = ""

function Read-ConsoleLine {
    param([string]$Prompt)

    Write-Host ""
    Write-Host -NoNewline $Prompt
    return [Console]::ReadLine()
}

function Set-Sort {
    param(
        [string]$Column,
        [bool]$Desc
    )

    $script:sortBy = $Column
    $script:descending = $Desc
}

function Set-RefreshDelay {
    Clear-Host
    $newDelay = Read-ConsoleLine "New refresh interval in seconds: "

    if ($newDelay -as [int]) {
        if ([int]$newDelay -gt 0) {
            $script:refreshSeconds = [int]$newDelay
            $script:statusMessage = "Refresh interval set to $refreshSeconds second(s)"
        }
    }
}

function Invoke-KillProcess {
    Clear-Host
    $pidToKill = Read-ConsoleLine "PID to kill: "

    if ($pidToKill -as [int]) {
        $target = Get-Process -Id ([int]$pidToKill) -ErrorAction SilentlyContinue

        if ($target) {
            $confirm = Read-ConsoleLine "Kill $($target.ProcessName) [$pidToKill]? y/N: "

            if ($confirm -eq "y" -or $confirm -eq "Y") {
                Stop-Process -Id ([int]$pidToKill) -Force -ErrorAction SilentlyContinue
                $script:statusMessage = "Killed PID $pidToKill"
            }
            else {
                $script:statusMessage = "Kill cancelled"
            }
        }
        else {
            $script:statusMessage = "PID $pidToKill not found"
        }
    }
}

function Handle-KeyPress {
    param([char]$KeyChar)

    switch ($KeyChar) {
        'q' { $script:quit = $true }
        'Q' { $script:quit = $true }

        '1' { Set-Sort "CPUPercent" $true }
        '2' { Set-Sort "WS_MB" $true }
        '3' { Set-Sort "PID" $false }
        '4' { Set-Sort "Process" $false }
        '5' { Set-Sort "Threads" $true }
        '6' { Set-Sort "Handles" $true }
        '7' { Set-Sort "CPUTime" $true }

        'P' { Set-Sort "CPUPercent" $true }
        'p' { Set-Sort "CPUPercent" $true }

        'M' { Set-Sort "WS_MB" $true }
        'm' { Set-Sort "WS_MB" $true }

        'N' { Set-Sort "PID" $false }
        'n' { Set-Sort "PID" $false }

        '+' { $script:topCount += 5 }
        '=' { $script:topCount += 5 }

        '-' {
            if ($script:topCount -gt 5) {
                $script:topCount -= 5
            }
        }

        '/' {
            Clear-Host
            $script:filter = Read-ConsoleLine "Filter process name, blank clears filter: "
        }

        'D' { Set-RefreshDelay }
        'd' { Set-RefreshDelay }

        'K' { Invoke-KillProcess }
        'k' { Invoke-KillProcess }

        'E' { $script:exportRequested = $true }
        'e' { $script:exportRequested = $true }
    }
}

function Wait-WithKeyPolling {
    param([int]$Seconds)

    $end = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $end -and -not $script:quit) {
        try {
            while ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                Handle-KeyPress $key.KeyChar
            }
        }
        catch {
        }

        Start-Sleep -Milliseconds 100
    }
}

function Write-ProcessRow {
    param($Process)

    $line = "{0,7} {1,8} {2,9} {3,9} {4,9} {5,9} {6,9} {7}" -f `
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

while (-not $quit) {

    try {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            Handle-KeyPress $key.KeyChar
        }
    }
    catch {
    }

    if ($quit) {
        break
    }

    $rawProcesses = Get-Process -ErrorAction SilentlyContinue

    if ($filter -ne "") {
        $rawProcesses = $rawProcesses | Where-Object {
            $_.ProcessName -like "*$filter*"
        }
    }

    $processes = $rawProcesses | ForEach-Object {
        try {
            $id = $_.Id
            $cpuSeconds = if ($_.CPU) { $_.CPU } else { 0 }
            $cpuPercent = 0

            if ($previous.ContainsKey($id)) {
                $cpuDelta = $cpuSeconds - $previous[$id]

                if ($cpuDelta -ge 0) {
                    $cpuPercent = ($cpuDelta / $refreshSeconds) * 100
                }
            }

            $previous[$id] = $cpuSeconds

            $handleValue = 0
            $threadValue = 0
            $respondingValue = $true

            try { $handleValue = $_.Handles } catch { $handleValue = 0 }
            try { $threadValue = $_.Threads.Count } catch { $threadValue = 0 }
            try { $respondingValue = $_.Responding } catch { $respondingValue = $true }

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
        catch {
        }
    }

    if ($descending) {
        $topProcesses = $processes |
            Sort-Object $sortBy -Descending |
            Select-Object -First $topCount
    }
    else {
        $topProcesses = $processes |
            Sort-Object $sortBy |
            Select-Object -First $topCount
    }

    if ($exportRequested) {
        $exportPath = Join-Path $PWD ("WinTop_Export_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        $topProcesses | Export-Csv -Path $exportPath -NoTypeInformation
        $statusMessage = "Exported current view to $exportPath"
        $exportRequested = $false
    }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
    $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeText = "{0} days, {1:00}:{2:00}:{3:00}" -f `
        $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds

    $cpuLoad = [math]::Round(($cpu | Measure-Object LoadPercentage -Average).Average, 1)
    $cpuCount = $computerSystem.NumberOfLogicalProcessors

    try {
        $loggedOnUsers = (quser 2>$null | Select-Object -Skip 1).Count
    }
    catch {
        $loggedOnUsers = 0
    }

    $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeMem  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedMem  = [math]::Round($totalMem - $freeMem, 1)

    $threadCount = ($rawProcesses | ForEach-Object {
        try { $_.Threads.Count } catch { 0 }
    } | Measure-Object -Sum).Sum

    $handleCount = ($rawProcesses | ForEach-Object {
        try { $_.Handles } catch { 0 }
    } | Measure-Object -Sum).Sum

    $respondingCount = ($processes | Where-Object { $_.Responding -eq $true }).Count
    $notRespondingCount = ($processes | Where-Object { $_.Responding -eq $false }).Count

    $topMemoryConsumers = $processes |
        Sort-Object WS_MB -Descending |
        Select-Object -First 5

    Clear-Host

    Write-Host "Windows top - $(Get-Date)"
    Write-Host "Uptime: $uptimeText | Users: $loggedOnUsers | CPU load: $cpuLoad% | Logical CPUs: $cpuCount"
    Write-Host "Tasks: $($rawProcesses.Count) | Responding: $respondingCount | Not Responding: $notRespondingCount"
    Write-Host "Threads: $threadCount | Handles: $handleCount"
    Write-Host "Memory: $usedMem MB used / $totalMem MB total"
    Write-Host "Sort: $sortBy | Refresh: ${refreshSeconds}s | Showing: $topCount | Filter: $filter"

    if ($statusMessage -ne "") {
        Write-Host "Status: $statusMessage" -ForegroundColor Green
        $statusMessage = ""
    }

    Write-Host "Keys: P/1=CPU  M/2=Mem  N/3=PID  4=Name  5=Threads  6=Handles  7=CPUTime"
    Write-Host "      K=Kill  D=Delay  /=Filter  E=Export  +=More  -=Less  Q=Quit"
    Write-Host ""

    Write-Host "Top Memory Consumers:"
    foreach ($memProc in $topMemoryConsumers) {
        Write-Host ("  {0,-25} {1,10} MB" -f $memProc.Process, $memProc.WS_MB)
    }

    Write-Host ""

    Write-Host ("{0,7} {1,8} {2,9} {3,9} {4,9} {5,9} {6,9} {7}" -f `
        "PID", "CPU %", "CPU Time", "WS MB", "PM MB", "Handles", "Threads", "Process")

    Write-Host ("{0,7} {1,8} {2,9} {3,9} {4,9} {5,9} {6,9} {7}" -f `
        "---", "-----", "--------", "-----", "-----", "-------", "-------", "-------")

    foreach ($proc in $topProcesses) {
        Write-ProcessRow -Process $proc
    }

    Wait-WithKeyPolling -Seconds $refreshSeconds
}