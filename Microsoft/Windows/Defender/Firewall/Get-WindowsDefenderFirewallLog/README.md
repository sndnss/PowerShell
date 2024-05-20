# Get-WindowsDefenderFirewallLog
Retrieves Windows Defender Firewall Log-entries from a specified Windows Defender Firewall Log-file
## Table of Content
  - [Version Changes](#version-changes)
  - [Background](#background)
  - [Examples](#examples)
  - [Builtin Help](#builtin-help)
## Version Changes
##### 1.0.0.0
- First version published on GitHub
## Background
As part of the process to secure and harden an environment, enabling the host-based firewall on Windows Servers and Workstations is a crucial task, which we have done numerous times. Various scripts have been developed to facilitate this process, this is the current one used to help get a quick overview, when parsing the log-files generated, to identify ports and ip-addresses to and from, which the traffic flows locally on a computer.
## Quickload
If your host has access to the internet, this codesnippet can be used to load the function directly into your environment, be aware that it might trigger an alarm or two, as it is considered in-memory code execution.
```PowerShell
$remoteURL = 'https://raw.githubusercontent.com/sndnss/PowerShell/main/Microsoft/Windows/Defender/Firewall/Get-WindowsDefenderFirewallLog/Get-WindowsDefenderFirewallLog.ps1'       
$remoteCode = (Invoke-WebRequest -Uri $remoteURL -UseBasicParsing).Content
Invoke-Expression -Command $remoteCode
```
## Examples
When using the `Get-WindowsDefenderFirewallLog`, it's a good idea to use `Group-Object` with the command, to get a better overview.
```PowerShell
    PS C:\> Get-WindowsDefenderFirewallLog -Incoming -Action DROP | Group-Object 'dst-port'

    Count Name                      Group
    ----- ----                      -----
      200 135                       {@{date=2024-04-25; time=09:59:01; action=DROP; proto...
        1 56367                     {@{date=2024-04-29; time=16:47:35; action=DROP; proto...
        2 53                        {@{date=2024-05-20; time=01:37:14; action=DROP; proto...
        1 123                       {@{date=2024-05-20; time=01:37:14; action=DROP; proto...
```
## Builtin Help
```PowerShell
<#
.SYNOPSIS
Retrieves Windows Defender Firewall Log entries.

.DESCRIPTION
The Get-WindowsDefenderFirewallLog function reads Windows Defender Firewall Log entries from a firewall log file and filters them based on specified criteria.

.PARAMETER FirewallLogPath
Specifies the path to the Windows Defender Firewall Log file. Default is "$env:windir\System32\LogFiles\Firewall\pfirewall.log".

.PARAMETER Action
Filters log entries by action (ALLOW, DROP, INFO-EVENTS-LOST).

.PARAMETER Incoming
Filters to only show incoming traffic.

.PARAMETER Outgoing
Filters to only show outgoing traffic.

.EXAMPLE
Get-WindowsDefenderFirewallLog -Action ALLOW -Incoming
Retrieves all incoming ALLOW log entries.

.EXAMPLE
Get-WindowsDefenderFirewallLog -Action DROP -Outgoing
Retrieves all outgoing DROP log entries.

#>

```
