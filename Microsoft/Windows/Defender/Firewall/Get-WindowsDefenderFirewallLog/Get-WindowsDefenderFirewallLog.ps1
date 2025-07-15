#Requires -RunAsAdministrator

<#PSScriptInfo

.DESCRIPTION Retrieves Windows Defender Firewall Log entries from a specified file.

.VERSION 2.0.0.0

.GUID 27edc000-e50f-4241-baec-395b761a8a6e

.AUTHOR Tom Stryhn

.COMPANYNAME sndnss aps

.COPYRIGHT 2025 (c) Tom Stryhn

.TAGS Microsoft Windows Defender Firewall Log Reader

.LICENSEURI https://github.com/sndnss/PowerShell/blob/main/LICENSE

.PROJECTURI https://github.com/sndnss/PowerShell/Microsoft/Windows/Defender/Firewall/Get-WindowsDefenderFirewallLog/

#>

function Get-WindowsDefenderFirewallLog {

<#
.SYNOPSIS
Retrieves Windows Defender Firewall Log entries.

.DESCRIPTION
The Get-WindowsDefenderFirewallLog function reads Windows Defender Firewall Log entries from a firewall log file and filters them based on specified criteria. The function returns structured objects with proper data types and calculated fields for enhanced analysis.

Output includes:
- DateTime objects for proper time-based filtering and sorting
- Integer types for ports, packet sizes, and process IDs
- Boolean flags for easy filtering (IsBlocked, IsAllowed, SourceIsLocal, etc.)
- Calculated Direction field (Incoming, Outgoing, Internal, Transit, Unknown)
- Protocol number mappings for network analysis

.PARAMETER FirewallLogPath
Specifies the path to the Windows Defender Firewall Log file. Default is "$env:windir\System32\LogFiles\Firewall\pfirewall.log".

.PARAMETER Action
Filters log entries by action (ALLOW, DROP, INFO-EVENTS-LOST).

.PARAMETER Incoming
Filters to only show incoming traffic.

.PARAMETER Outgoing
Filters to only show outgoing traffic.

.PARAMETER DisableLocalIPDetection
Disables local IP address detection and direction filtering. Use this when analyzing firewall logs from remote computers or different network segments where local IP detection is not relevant. When disabled, all entries will show 'Unknown' for the Direction field and direction-based filtering is bypassed.

.PARAMETER MaxResults
Limits the number of log entries returned. Use 0 for unlimited results (default).

.PARAMETER StreamingMode
Forces streaming mode for memory-efficient processing of large files. Automatically enabled for files larger than 25MB.

.EXAMPLE
Get-WindowsDefenderFirewallLog -Action ALLOW -Incoming
Retrieves all incoming ALLOW log entries.

.EXAMPLE
Get-WindowsDefenderFirewallLog -Action DROP -Outgoing
Retrieves all outgoing DROP log entries.

.EXAMPLE
Get-WindowsDefenderFirewallLog -FirewallLogPath "C:\CustomPath\firewall.log" -Verbose
Retrieves all log entries from a custom log file path with verbose output showing processing statistics.

.EXAMPLE
Get-WindowsDefenderFirewallLog -MaxResults 100 -StreamingMode
Retrieves the first 100 log entries using streaming mode for memory efficiency.

.EXAMPLE
Get-WindowsDefenderFirewallLog -Action DROP | Where-Object { $_.DestinationPort -eq 443 }
Retrieves all blocked HTTPS traffic (port 443) using the typed DestinationPort field.

.EXAMPLE
Get-WindowsDefenderFirewallLog | Where-Object { $_.DateTime -gt (Get-Date).AddHours(-1) -and $_.Direction -eq 'Incoming' }
Retrieves all incoming traffic from the last hour using the DateTime and Direction calculated fields.

.EXAMPLE
Get-WindowsDefenderFirewallLog | Where-Object { $_.IsBlocked -and $_.PacketSize -gt 1000 } | Sort-Object PacketSize -Descending
Retrieves all blocked traffic with large packets, sorted by packet size.

.EXAMPLE
Get-WindowsDefenderFirewallLog -FirewallLogPath "\\RemoteServer\logs\firewall.log" -DisableLocalIPDetection
Analyzes a firewall log from a remote server without attempting local IP detection.

.NOTES
This function requires administrator privileges to access the default firewall log file.
The function includes comprehensive error handling for file access, network interface enumeration, and log parsing.
Use -Verbose parameter to see detailed processing information and troubleshooting data.
For large files (>25MB), streaming mode is automatically enabled to optimize memory usage.
Use -MaxResults to limit output and improve performance when you only need recent entries.

Enhanced Output Features:
- DateTime objects for time-based analysis and filtering
- Proper integer types for numerical fields (ports, sizes, PIDs)
- Boolean flags for easy filtering (IsBlocked, IsAllowed, SourceIsLocal, DestIsLocal)
- Calculated Direction field (Incoming, Outgoing, Internal, Transit, Unknown)
- Protocol number mappings for network analysis tools

#>

    [CmdletBinding()]
    param (
        # Parameter for the Path to the LogFile
        [Parameter()]
        [ValidateScript({
            if (-not (Test-Path -Path $_)) {
                throw "The specified firewall log path does not exist: $_"
            }
            if (-not (Test-Path -Path $_ -PathType Leaf)) {
                throw "The specified path is not a file: $_"
            }
            return $true
        })]
        [string]
        $FirewallLogPath = "$env:windir\System32\LogFiles\Firewall\pfirewall.log",

        # Parameter to filter on ALLOW, DROP or the INFO-EVENTS-LOST
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
        $Outgoing,

        # Switch to disable local IP detection for analyzing remote firewall logs
        [Parameter()]
        [switch]
        $DisableLocalIPDetection,

        # Maximum number of entries to return (0 = unlimited)
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $MaxResults = 0,

        # Process file in streaming mode for better memory efficiency with large files
        [Parameter()]
        [switch]
        $StreamingMode
    )

    begin {
        # Validate firewall log file exists and is accessible
        if (-not (Test-Path -Path $FirewallLogPath)) {
            $errorMessage = "Firewall log file not found: $FirewallLogPath"
            Write-Error -Message $errorMessage -Category ObjectNotFound -ErrorAction Stop
        }

        try {
            # Test file access by attempting to read first line
            $null = Get-Content -Path $FirewallLogPath -TotalCount 1 -ErrorAction Stop
        }
        catch {
            $errorMessage = "Cannot access firewall log file: $FirewallLogPath. Error: $($_.Exception.Message)"
            Write-Error -Message $errorMessage -Category PermissionDenied -ErrorAction Stop
        }

        # Create hashtable of local IP addresses with error handling for efficient lookup
        $localIPLookup = @{}
        if (-not $DisableLocalIPDetection) {
            try {
                $localIPs = (Get-NetIPAddress -AddressFamily IPv4, IPv6 -ErrorAction Stop).IPAddress | ForEach-Object {
                    # Removes zone index from IPv6 addresses and passes on IPv4 addresses
                    if ($_ -match "\%") {
                        ($_ -split '%')[0]
                    } else {
                        $_
                    }
                }
                
                # Create hashtable for O(1) IP lookups instead of O(n) array contains
                $localIPs | ForEach-Object { $localIPLookup[$_] = $true }
                
                if ($localIPLookup.Count -eq 0) {
                    Write-Warning "No local IP addresses found. Traffic direction filtering may not work correctly."
                } else {
                    $ipList = ($localIPs | Sort-Object) -join ', '
                    Write-Verbose "Found $($localIPLookup.Count) local IP addresses for traffic direction filtering: $ipList"
                }
            }
            catch {
                Write-Warning "Failed to retrieve local IP addresses: $($_.Exception.Message). Traffic direction filtering will be disabled."
                $localIPLookup = @{}
            }
        } else {
            Write-Verbose "Local IP detection disabled - direction filtering and calculated direction fields will show 'Unknown'"
        }

        # Parse the log file header to understand field layout and create dynamic mapping
        $fieldMapping = @{}
        $expectedFieldCount = 0
        try {
            $headerLines = Get-Content -Path $FirewallLogPath -TotalCount 10 -ErrorAction Stop
            $fieldsLine = $headerLines | Where-Object { $_ -match "^#Fields:" } | Select-Object -First 1
            
            if ($fieldsLine) {
                $fieldNames = ($fieldsLine -replace "^#Fields:\s*", "") -split '\s+'
                $expectedFieldCount = $fieldNames.Count
                
                # Create mapping of field names to array indices for dynamic field access
                for ($i = 0; $i -lt $fieldNames.Count; $i++) {
                    $fieldMapping[$fieldNames[$i]] = $i
                }
                
                Write-Verbose "Parsed log header: Found $expectedFieldCount fields: $($fieldNames -join ', ')"
            } else {
                Write-Warning "No #Fields header found in log file. Using default field mapping."
                # Fallback to default mapping if no header found
                $expectedFieldCount = 16
            }
        }
        catch {
            Write-Warning "Failed to parse log file header: $($_.Exception.Message). Using default field mapping."
            $expectedFieldCount = 16
        }
    }

    process {
        # Initialize performance counters
        $processedEntries = 0
        $skippedEntries = 0
        $totalLines = 0
        $outputCount = 0
        
        # Check file size for progress reporting decision
        $fileInfo = Get-Item -Path $FirewallLogPath
        $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
        $showProgress = $fileSizeMB -gt 10 # Show progress for files larger than 10MB
        
        if ($showProgress) {
            Write-Verbose "Processing large log file ($fileSizeMB MB). Progress will be displayed."
        }

        # Determine processing method based on StreamingMode parameter or file size
        $useStreaming = $StreamingMode -or ($fileSizeMB -gt 25) # Auto-enable for files > 25MB
        
        if ($useStreaming) {
            Write-Verbose "Using streaming mode for memory-efficient processing."
            
            # Stream processing - memory efficient for large files
            try {
                Get-Content -Path $FirewallLogPath -ReadCount 1000 | ForEach-Object {
                    foreach ($logEntry in $_) {
                        $totalLines++
                        
                        # Show progress every 10000 lines for large files
                        if ($showProgress -and ($totalLines % 10000 -eq 0)) {
                            Write-Progress -Activity "Processing Firewall Log" -Status "Processed $totalLines lines, Found $outputCount matches" -PercentComplete -1
                        }
                        
                        # Process the log entry
                        $result = ProcessLogEntry -logEntry $logEntry -localIPLookup $localIPLookup -Action $Action -Incoming $Incoming -Outgoing $Outgoing -fieldMapping $fieldMapping -expectedFieldCount $expectedFieldCount -DisableLocalIPDetection $DisableLocalIPDetection
                        
                        if ($result.ShouldOutput) {
                            $result.LogEntry
                            $outputCount++
                            $processedEntries++
                            
                            # Check MaxResults limit
                            if ($MaxResults -gt 0 -and $outputCount -ge $MaxResults) {
                                Write-Verbose "Reached MaxResults limit of $MaxResults entries."
                                if ($showProgress) { Write-Progress -Activity "Processing Firewall Log" -Completed }
                                return
                            }
                        } elseif ($result.WasSkipped) {
                            $skippedEntries++
                        }
                    }
                }
            }
            catch {
                $errorMessage = "Failed to read firewall log file: $FirewallLogPath. Error: $($_.Exception.Message)"
                Write-Error -Message $errorMessage -Category ReadError -ErrorAction Stop
            }
        }
        else {
            # Traditional processing for smaller files
            try {
                $fileContent = Get-Content -Path $FirewallLogPath -ErrorAction Stop
                
                if ($null -eq $fileContent -or $fileContent.Count -eq 0) {
                    Write-Warning "The firewall log file appears to be empty: $FirewallLogPath"
                    return
                }
                
                $totalLines = $fileContent.Count
                Write-Verbose "Processing $totalLines lines from log file."
                
                foreach ($logEntry in $fileContent) {
                    # Process the log entry
                    $result = ProcessLogEntry -logEntry $logEntry -localIPLookup $localIPLookup -Action $Action -Incoming $Incoming -Outgoing $Outgoing -fieldMapping $fieldMapping -expectedFieldCount $expectedFieldCount -DisableLocalIPDetection $DisableLocalIPDetection
                    
                    if ($result.ShouldOutput) {
                        $result.LogEntry
                        $outputCount++
                        $processedEntries++
                        
                        # Check MaxResults limit
                        if ($MaxResults -gt 0 -and $outputCount -ge $MaxResults) {
                            Write-Verbose "Reached MaxResults limit of $MaxResults entries."
                            break
                        }
                    } elseif ($result.WasSkipped) {
                        $skippedEntries++
                    }
                }
            }
            catch {
                $errorMessage = "Failed to read firewall log file: $FirewallLogPath. Error: $($_.Exception.Message)"
                Write-Error -Message $errorMessage -Category ReadError -ErrorAction Stop
            }
        }
        
        # Clean up progress display
        if ($showProgress) {
            Write-Progress -Activity "Processing Firewall Log" -Completed
        }
        
        # Provide summary information
        Write-Verbose "Processing complete. Total lines: $totalLines, Entries output: $outputCount, Entries skipped: $skippedEntries, File size: $fileSizeMB MB"
    }

    end {}
}

# Helper function - Safe integer conversion for firewall log processing
function ConvertToInt {
    param([string]$value)
    $result = 0
    if ([string]::IsNullOrEmpty($value) -or $value -eq '-') {
        return $null
    }
    if ([int]::TryParse($value, [ref]$result)) {
        return $result
    }
    return $null
}

# Helper function - Process individual log entries efficiently for Get-WindowsDefenderFirewallLog
function ProcessLogEntry {
    param(
        [string]$logEntry,
        [hashtable]$localIPLookup,
        [string]$Action,
        [switch]$Incoming,
        [switch]$Outgoing,
        [hashtable]$fieldMapping,
        [int]$expectedFieldCount,
        [switch]$DisableLocalIPDetection
    )
    
    # Return object indicating processing result
    $result = @{
        ShouldOutput = $false
        LogEntry = $null
        WasSkipped = $false
    }
    
    # Skip header lines and empty lines early
    if (($logEntry -match "^\#") -or ($logEntry.Length -le 3)) {
        return $result
    }
    
    try {
        $logEntryValues = $logEntry -split ' '
        
        # Validate field count early to avoid unnecessary processing
        # INFO-EVENTS-LOST entries have 17 fields (missing 'path'), standard entries have 18 fields
        $minRequiredFields = if ($logEntryValues.Count -gt 2 -and $logEntryValues[2] -eq 'INFO-EVENTS-LOST') { 
            14  # Minimum for INFO-EVENTS-LOST entries
        } else { 
            14  # Minimum required fields across all formats
        }
        
        if ($logEntryValues.Count -lt $minRequiredFields) {
            Write-Verbose "Skipping malformed log entry (insufficient fields): $logEntry"
            $result.WasSkipped = $true
            return $result
        }
        
        # Early filtering - check Action first before creating object
        $actionField = if ($fieldMapping -and $fieldMapping.ContainsKey('action')) { 
            $logEntryValues[$fieldMapping['action']] 
        } else { 
            $logEntryValues[2] # Fallback to standard position
        }
        
        # Warn if field count doesn't match expected (but still process)
        # INFO-EVENTS-LOST entries have one less field (missing 'path') than standard entries
        if ($expectedFieldCount -gt 0 -and $logEntryValues.Count -ne $expectedFieldCount) {
            if ($actionField -eq 'INFO-EVENTS-LOST' -and $logEntryValues.Count -eq ($expectedFieldCount - 1)) {
                # Expected for INFO-EVENTS-LOST entries - they omit the 'path' field
                Write-Verbose "INFO-EVENTS-LOST entry with expected field count ($($logEntryValues.Count))"
            } else {
                Write-Verbose "Field count mismatch - Expected: $expectedFieldCount, Found: $($logEntryValues.Count), Entry type: $actionField"
            }
        }
        if ($Action -and ($actionField -ne $Action)) {
            return $result
        }
        
        # Early filtering - check traffic direction before creating object
        # Handle INFO-EVENTS-LOST entries which don't have valid IP addresses
        $srcIPField = if ($fieldMapping -and $fieldMapping.ContainsKey('src-ip')) { 
            $fieldMapping['src-ip'] 
        } else { 
            4 # Fallback to standard position
        }
        $dstIPField = if ($fieldMapping -and $fieldMapping.ContainsKey('dst-ip')) { 
            $fieldMapping['dst-ip'] 
        } else { 
            5 # Fallback to standard position
        }
        
        $srcIP = if ($logEntryValues.Count -gt $srcIPField) { $logEntryValues[$srcIPField] } else { '-' }
        $dstIP = if ($logEntryValues.Count -gt $dstIPField) { $logEntryValues[$dstIPField] } else { '-' }
        
        # Skip direction filtering for INFO-EVENTS-LOST or malformed entries
        # Also skip when DisableLocalIPDetection is enabled for remote log analysis
        if ($actionField -ne 'INFO-EVENTS-LOST' -and $srcIP -ne '-' -and $dstIP -ne '-' -and -not $DisableLocalIPDetection) {
            # Helper function to check if IP is local (including IPv4/IPv6 patterns)
            function IsLocalIP {
                param($ip)
                # Check hashtable first for exact matches (fastest)
                if ($localIPLookup.ContainsKey($ip)) { return $true }
                
                # Check IPv6 patterns for common local addresses
                if ($ip -like 'fe80::*') { return $true }  # Link-local
                if ($ip -like 'fd*' -or $ip -like 'fc*') { return $true }  # Unique local
                if ($ip -eq '::1') { return $true }  # IPv6 loopback
                
                # Check IPv4 patterns for private and loopback ranges
                if ($ip -like '127.*') { return $true }  # IPv4 loopback range
                if ($ip -like '10.*' -or $ip -like '192.168.*' -or $ip -like '172.16.*' -or $ip -like '172.17.*' -or $ip -like '172.18.*' -or $ip -like '172.19.*' -or $ip -like '172.20.*' -or $ip -like '172.21.*' -or $ip -like '172.22.*' -or $ip -like '172.23.*' -or $ip -like '172.24.*' -or $ip -like '172.25.*' -or $ip -like '172.26.*' -or $ip -like '172.27.*' -or $ip -like '172.28.*' -or $ip -like '172.29.*' -or $ip -like '172.30.*' -or $ip -like '172.31.*') { return $true }  # Private IPv4
                
                return $false
            }
            
            $isLocalSrc = IsLocalIP $srcIP
            $isLocalDst = IsLocalIP $dstIP
            
            # Apply direction filters early
            if ($Incoming -and $Outgoing) {
                # Both flags: only internal traffic (both IPs local)
                if (-not ($isLocalSrc -and $isLocalDst)) {
                    return $result
                }
            }
            elseif ($Incoming) {
                # Incoming only: destination must be local
                if (-not $isLocalDst) {
                    return $result
                }
            }
            elseif ($Outgoing) {
                # Outgoing only: source must be local
                if (-not $isLocalSrc) {
                    return $result
                }
            }
        } else {
            # For INFO-EVENTS-LOST entries or when DisableLocalIPDetection is enabled, set defaults
            $isLocalSrc = $false
            $isLocalDst = $false
        }
        
        # Only create the output object if it passes all filters
        # Determine traffic direction for calculated field (Unknown when DisableLocalIPDetection is used)
        $direction = if ($DisableLocalIPDetection) { 
            'Unknown' 
        } elseif ($isLocalSrc -and $isLocalDst) { 
            'Internal' 
        } elseif ($isLocalDst) { 
            'Incoming' 
        } elseif ($isLocalSrc) { 
            'Outgoing' 
        } else { 
            'Transit' 
        }
        
        # Parse and convert data types with error handling
        try {
            $dateField = if ($fieldMapping -and $fieldMapping.ContainsKey('date')) { 
                $fieldMapping['date'] 
            } else { 
                0 # Fallback to standard position
            }
            $timeField = if ($fieldMapping -and $fieldMapping.ContainsKey('time')) { 
                $fieldMapping['time'] 
            } else { 
                1 # Fallback to standard position
            }
            
            $dateTimeString = "$($logEntryValues[$dateField]) $($logEntryValues[$timeField])"
            $dateTime = [DateTime]::ParseExact($dateTimeString, "yyyy-MM-dd HH:mm:ss", $null)
        }
        catch {
            # Fallback to current date if parsing fails
            Write-Verbose "Failed to parse datetime '$dateTimeString', using current time"
            $dateTime = Get-Date
        }
        
        # Helper function to get field value safely with dynamic field mapping
        function GetFieldValue {
            param($field, $defaultValue = '')
            if ($fieldMapping -and $fieldMapping.ContainsKey($field)) {
                $index = $fieldMapping[$field]
                if ($logEntryValues.Count -gt $index) {
                    return $logEntryValues[$index]
                }
            } else {
                # Fallback to standard positions for compatibility
                $standardIndex = switch ($field) {
                    'date' { 0 }
                    'time' { 1 }
                    'action' { 2 }
                    'protocol' { 3 }
                    'src-ip' { 4 }
                    'dst-ip' { 5 }
                    'src-port' { 6 }
                    'dst-port' { 7 }
                    'size' { 8 }
                    'tcpflags' { 9 }
                    'tcpsyn' { 10 }
                    'tcpack' { 11 }
                    'tcpwin' { 12 }
                    'icmptype' { 13 }
                    'icmpcode' { 14 }
                    'info' { 15 }
                    'path' { 16 }
                    'pid' { 17 }
                    default { -1 }
                }
                if ($standardIndex -ge 0 -and $logEntryValues.Count -gt $standardIndex) {
                    return $logEntryValues[$standardIndex]
                }
            }
            return $defaultValue
        }
        
        # Helper function to get integer field value safely with dynamic field mapping
        function GetFieldValueInt {
            param($field, $defaultValue = $null)
            if ($fieldMapping -and $fieldMapping.ContainsKey($field)) {
                $index = $fieldMapping[$field]
                if ($logEntryValues.Count -gt $index) {
                    return ConvertToInt $logEntryValues[$index]
                }
            } else {
                # Fallback to standard positions for compatibility
                $standardIndex = switch ($field) {
                    'src-port' { 6 }
                    'dst-port' { 7 }
                    'size' { 8 }
                    'tcpwin' { 12 }
                    'icmptype' { 13 }
                    'icmpcode' { 14 }
                    'pid' { 17 }
                    default { -1 }
                }
                if ($standardIndex -ge 0 -and $logEntryValues.Count -gt $standardIndex) {
                    return ConvertToInt $logEntryValues[$standardIndex]
                }
            }
            return $defaultValue
        }
        
        $logEntryOutput = [PSCustomObject]@{
            # Combined DateTime field (proper DateTime type)
            'DateTime'       = $dateTime
            
            # Action and protocol
            'Action'         = GetFieldValue 'action' ''
            'Protocol'       = GetFieldValue 'protocol' ''
            
            # IP addresses
            'SourceIP'       = GetFieldValue 'src-ip' ''
            'DestinationIP'  = GetFieldValue 'dst-ip' ''
            
            # Ports (converted to integers)
            'SourcePort'     = GetFieldValueInt 'src-port'
            'DestinationPort'= GetFieldValueInt 'dst-port'
            
            # Packet size (converted to integer)
            'PacketSize'     = GetFieldValueInt 'size'
            
            # TCP fields
            'TCPFlags'       = GetFieldValue 'tcpflags' ''
            'TCPSyn'         = GetFieldValue 'tcpsyn' ''
            'TCPAck'         = GetFieldValue 'tcpack' ''
            'TCPWin'         = GetFieldValueInt 'tcpwin'
            
            # ICMP fields
            'ICMPType'       = GetFieldValueInt 'icmptype'
            'ICMPCode'       = GetFieldValueInt 'icmpcode'
            
            # Additional fields
            'Info'           = GetFieldValue 'info' ''
            'Path'           = GetFieldValue 'path' ''
            'ProcessID'      = GetFieldValueInt 'pid'
            
            # Calculated fields for enhanced analysis
            'Direction'      = $direction
            'IsBlocked'      = ($actionField -eq 'DROP')
            'IsAllowed'      = ($actionField -eq 'ALLOW')
            'SourceIsLocal'  = $isLocalSrc
            'DestIsLocal'    = $isLocalDst
            'IsInternalTraffic' = ($isLocalSrc -and $isLocalDst)
            'ProtocolNumber' = switch (GetFieldValue 'protocol') {
                'TCP' { 6 }
                'UDP' { 17 }
                'ICMP' { 1 }
                'ICMPv6' { 58 }
                default { $null }
            }
            'HasPath'        = -not [string]::IsNullOrEmpty((GetFieldValue 'path')) -and (GetFieldValue 'path') -ne '-'
            'HasProcessID'   = $null -ne (GetFieldValueInt 'pid') -and (GetFieldValueInt 'pid') -ne 0
        }
        
        $result.ShouldOutput = $true
        $result.LogEntry = $logEntryOutput
        return $result
    }
    catch {
        Write-Verbose "Error processing log entry: $logEntry. Error: $($_.Exception.Message)"
        $result.WasSkipped = $true
        return $result
    }
}
