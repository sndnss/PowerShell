#Requires -RunAsAdministrator

<#PSScriptInfo

.DESCRIPTION Retrieves Windows Defender Firewall Log entries from a specified file.

.VERSION 1.0.0.0

.GUID 27edc000-e50f-4241-baec-395b761a8a6e

.AUTHOR Tom Stryhn

.COMPANYNAME Soundness ApS [sndnss aps]

.COPYRIGHT 2024 (c) Tom Stryhn

.TAGS Microsoft Windows Defender Firewall Log Reader

.LICENSEURI https://github.com/sndnss/PowerShell/blob/main/LICENSE

.PROJECTURI https://github.com/sndnss/PowerShell/Microsoft/Windows/Defender/Firewall/Get-WindowsDefenderFirewallLog/

#>

function Get-WindowsDefenderFirewallLog {

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

    [CmdletBinding()]
    param (
        # Parameter for the Path to the LogFile
        [Parameter()]
        [string]
        $FirewallLogPath = "$env:windir\System32\LogFiles\Firewall\pfirewall.log",

        # Parameter to sort on ALLOW, DROP or the INFO-EVENTS-LOST
        [Parameter()]
        [ValidateSet('ALLOW', 'DROP', 'INFO-EVENTS-LOST')]
        [string]
        $Action,

        # Switch used to show Incoming Traffic
        [Parameter()]
        [switch]
        $Incoming,

        # Switch used to show Outgoing Traffic
        [Parameter()]
        [switch]
        $Outgoing
    )

    begin {
        # Create an array of local IP addresses
        $localIPAddresses = @()
        $localIPAddresses += (Get-NetIPAddress).IPAddress | ForEach-Object {
            # Removes zone index from IPv6 addresses and passes on IPv4 addresses
            if ($_ -match "\%") {
                ($_ -split '%')[0]
            } else {
                $_
            }
        }
    }

    process {
        # Read the entire content of the file
        $fileContent = Get-Content $FirewallLogPath

        # Process LogEntries and filters at the same time
        foreach ($logEntry in $fileContent) {
            # Skips the header lines, and the empty line
            if (($logEntry -notmatch "^\#") -and ($logEntry.Length -gt 3)) {
                $logEntryValues = $logEntry -split ' '
                $logEntryOutput = [PSCustomObject]@{
                    'date'        = $logEntryValues[0]
                    'time'        = $logEntryValues[1]
                    'action'      = $logEntryValues[2]
                    'protocol'    = $logEntryValues[3]
                    'src-ip'      = $logEntryValues[4]
                    'dst-ip'      = $logEntryValues[5]
                    'src-port'    = $logEntryValues[6]
                    'dst-port'    = $logEntryValues[7]
                    'size'        = $logEntryValues[8]
                    'tcpflags'    = $logEntryValues[9]
                    'tcpsyn'      = $logEntryValues[10]
                    'tcpack'      = $logEntryValues[11]
                    'tcpwin'      = $logEntryValues[12]
                    'icmptype'    = $logEntryValues[13]
                    'icmpcode'    = $logEntryValues[14]
                    'info'        = $logEntryValues[15]
                    'path'        = $logEntryValues[16]
                    'pid'         = $logEntryValues[17]
                }

                # Checks for Incoming and Outgoing switch
                if ($Incoming -and $Outgoing) {
                    # Filters based on a Local IP in the src-ip and dst-ip
                    if (($localIPAddresses -contains $logEntryValues[4]) -and ($localIPAddresses -contains $logEntryValues[5])) {
                        # Checks for Action parameter and match
                        if ((-not $Action) -or ($logEntryValues[2] -eq $Action)) {
                            $logEntryOutput
                        }
                    }
                }
                # Checks for Incoming switch
                elseif ($Incoming) {
                    # Filters based on a Local IP in the dst-ip
                    if ($localIPAddresses -contains $logEntryValues[5]) {
                        # Checks for Action parameter and match
                        if ((-not $Action) -or ($logEntryValues[2] -eq $Action)) {
                            $logEntryOutput
                        }
                    }
                }
                # Checks for Outgoing switch
                elseif ($Outgoing) {
                    # Filters based on a Local IP in the src-ip
                    if ($localIPAddresses -contains $logEntryValues[4]) {
                        # Checks for Action parameter and match
                        if ((-not $Action) -or ($logEntryValues[2] -eq $Action)) {
                            $logEntryOutput
                        }
                    }
                }
                else {
                    # Checks for Action parameter and match
                    if ((-not $Action) -or ($logEntryValues[2] -eq $Action)) {
                        $logEntryOutput
                    }
                }
            }
        }
    }

    end {}
}
