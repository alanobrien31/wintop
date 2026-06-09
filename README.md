# WinTop

A Linux `top` inspired process and system monitoring utility for Microsoft Windows written entirely in PowerShell.

WinTop provides a continuously refreshing view of system activity, process statistics, CPU usage, memory consumption, and other operational metrics directly from the console without requiring any additional software.

---

## Features

* Live process monitoring
* Real-time CPU utilization calculation
* Sort by:

  * CPU Usage
  * Memory Usage
  * PID
  * Process Name
  * Thread Count
  * Handle Count
  * Total CPU Time
* Process filtering
* Process termination by PID
* Adjustable refresh interval
* Export current view to CSV
* System uptime display
* Logged-on user count
* CPU load percentage
* Logical CPU count
* Memory utilization statistics
* Process, thread and handle totals
* Top memory consumer summary
* Responding vs non-responding process counts
* High CPU process highlighting
* Safe handling of protected and transient processes

---

## Requirements

* Windows PowerShell 5.1 or later
* PowerShell 7.x supported
* Windows 10 / Windows 11
* Windows Server 2016+
* Administrator privileges recommended for full visibility of all processes

---

## Installation

Clone the repository:

```powershell
git clone https://github.com/<your-github-username>/WinTop.git
cd WinTop
```

Or download the latest release and extract the contents.

---

## Usage

Launch WinTop from a PowerShell console:

```powershell
.\WinTop.ps1
```

---

## Keyboard Shortcuts

| Key   | Action                                 |
| ----- | -------------------------------------- |
| Q     | Quit                                   |
| P / 1 | Sort by CPU %                          |
| M / 2 | Sort by Memory                         |
| N / 3 | Sort by PID                            |
| 4     | Sort by Process Name                   |
| 5     | Sort by Thread Count                   |
| 6     | Sort by Handle Count                   |
| 7     | Sort by Total CPU Time                 |
| K     | Kill Process by PID                    |
| D     | Change Refresh Interval                |
| /     | Filter Process Name                    |
| E     | Export Current View to CSV             |
| +     | Increase Number of Displayed Processes |
| -     | Decrease Number of Displayed Processes |

---

## Example Display

```text
Windows top - 2026-06-09 14:25:12

Uptime: 15 days, 04:12:55
Users: 2
CPU Load: 18%
Logical CPUs: 16

Tasks: 243
Responding: 238
Not Responding: 5

Threads: 3854
Handles: 152341

Memory: 18,452 MB used / 32,768 MB total
```

---

## CSV Export

Press:

```text
E
```

to export the currently displayed process list.

Export files are saved in the current working directory:

```text
WinTop_Export_YYYYMMDD_HHMMSS.csv
```

---

## Why WinTop?

Windows includes tools such as Task Manager, Resource Monitor, and Performance Monitor. WinTop provides a lightweight alternative that can be launched directly from a PowerShell session and operated entirely from the keyboard.

The goal is to provide a familiar experience for Linux administrators while remaining native to Windows and PowerShell.

---

## Version History

### v1.1.2

* Added process filtering
* Added process termination
* Added CSV export
* Added CPU load statistics
* Added logical CPU count
* Added memory consumer summary
* Added responding/non-responding process counts
* Added high CPU highlighting
* Improved keyboard responsiveness

---

## Contributing

Contributions, feature requests, bug reports, and suggestions are welcome.

Please open an issue or submit a pull request.

---

## License

MIT License

Copyright (c) 2026 Alan O'Brien
