<#PSScriptInfo

.DESCRIPTION Adds resolved IP address information (IPv4 and IPv6) to objects containing DNS hostname information with enhanced error handling and performance optimization.

.VERSION 1.0.0.0

.GUID 48de05db-6f2a-4971-bb3a-66633803464e

.AUTHOR Tom Stryhn

.COMPANYNAME sndnss aps

.COPYRIGHT 2025 (c) Tom Stryhn

.TAGS DNS Resolution IP Address Network Computer Object Add-Member

.LICENSEURI https://github.com/sndnss/PowerShell/blob/main/LICENSE

.PROJECTURI https://github.com/sndnss/PowerShell/Microsoft/ActiveDirectory/Add-IPAddressToObject/

#>

function Add-IPAddressToObject {

<#
.SYNOPSIS
    Adds resolved IP address information to objects containing DNS hostname information.

.DESCRIPTION
    This function takes objects containing DNS hostname information and adds resolved IP address
    information to them. It works with computer objects from Get-ADComputer, Get-LDAPComputerObject, 
    or any other source that provides DNS hostname properties. The function resolves hostnames to 
    both IPv4 and IPv6 addresses, supports pipeline input, and includes enhanced error handling,
    performance optimizations, and detailed resolution tracking.

.PARAMETER InputObject
    Objects with DNS hostname information. Can be from Get-ADComputer, Get-LDAPComputerObject, 
    or any other source. Accepts pipeline input.

.PARAMETER HostnameProperty
    The property name that contains the DNS hostname(s). Defaults to 'DNSHostName'.

.PARAMETER IPv4Only
    Resolve only IPv4 addresses (A records). Cannot be used with IPv6Only.

.PARAMETER IPv6Only
    Resolve only IPv6 addresses (AAAA records). Cannot be used with IPv4Only.

.PARAMETER TimeoutSeconds
    Controls DNS resolution timeout behavior. Values ≤5 seconds enable QuickTimeout for faster 
    failure detection. Uses native Resolve-DnsName timeout capabilities. Defaults to 5 seconds.

.PARAMETER AsString
    Returns IP addresses as a comma-separated string instead of an array. Use this for 
    compatibility with legacy systems or when string format is preferred.

.EXAMPLE
    Get-LDAPComputerObject -ComputerName "SERVER01" | Add-IPAddressToObject
    
    Gets AD information for SERVER01 using LDAP and adds resolved IP address information.

.EXAMPLE
    Get-ADComputer -Filter "Name -like 'SERVER*'" | Add-IPAddressToObject -IPv4Only
    
    Gets multiple computers using Get-ADComputer and adds only IPv4 address information.

.EXAMPLE
    Get-LDAPComputerObject -ComputerName "SERVER01", "SERVER02" | Add-IPAddressToObject -IPv4Only
    
    Gets AD information for multiple computers using LDAP and adds only IPv4 address information.

.EXAMPLE
    $computers = Get-ADComputer -Filter * -Properties DNSHostName
    $computers | Add-IPAddressToObject
    
    Gets all computers with Get-ADComputer and adds IP address information.

.EXAMPLE
    $computers = Get-LDAPComputerObject -ComputerName $computerList -Properties "name", "dnshostname"
    $computers | Add-IPAddressToObject
    
    Two-step process: get AD info with LDAP, then add network information.

.EXAMPLE
    Get-ADComputer -Filter "Name -like 'SERVER*'" | Add-IPAddressToObject -TimeoutSeconds 10
    
    Gets computers and resolves IP address information with a 10-second timeout per hostname.

.EXAMPLE
    Get-ADComputer -Filter * | Add-IPAddressToObject -AsString
    
    Gets all computers and returns IP addresses as comma-separated strings instead of arrays.

.EXAMPLE
    $computers = Get-LDAPComputerObject -ComputerName "SERVER01" | Add-IPAddressToObject
    $computers.IPAddress  # Returns array: @("192.168.1.10", "fe80::1")
    
    Default behavior returns IP addresses as an array (like Get-ADComputer multi-value properties).

.OUTPUTS
    Enhanced PSCustomObject with the following added properties:
    - IPAddress: Array of resolved IP addresses (default) or comma-separated string (with -AsString)
    - DNSResolutionErrors: Array of any DNS resolution errors encountered
    - ResolvedHostnameCount: Number of hostnames processed
    - IPAddressCount: Number of unique IP addresses found

.NOTES
    Requires DNS resolution capabilities.
    Works with any object containing DNS hostname properties (Get-ADComputer, Get-LDAPComputerObject, etc.).
    Performance optimized with ArrayList usage and individual error handling.
    Supports both comma and semicolon-separated hostname strings.
    Uses native Resolve-DnsName timeout features (-QuickTimeout) for efficient resolution.
    Compatible with PowerShell 5.1 and later versions.
#>

    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
            )]
        [PSObject[]]$InputObject,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$HostnameProperty = 'DNSHostName',
        
        [Parameter(Mandatory = $false)]
        [switch]$IPv4Only,
        
        [Parameter(Mandatory = $false)]
        [switch]$IPv6Only,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 5,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsString
    )
    
    begin {
        # Validate that both IPv4Only and IPv6Only are not specified
        if ($IPv4Only -and $IPv6Only) {
            throw "Cannot specify both -IPv4Only and -IPv6Only parameters simultaneously."
        }
    }
    
    process {
        foreach ($computerObj in $InputObject) {
            Write-Verbose "Processing object to add IP address information"
            
            # Use ArrayList for better performance than += operations
            $ipAddressList = [System.Collections.ArrayList]::new()
            $hostnames = @()
            $errors = @()
            
            # Validate that the object has the required property
            if (-not $computerObj.PSObject.Properties.Name -contains $HostnameProperty) {
                Write-Warning "Object does not contain property '$HostnameProperty'. Skipping resolution."
                if ($AsString) {
                    $computerObj | Add-Member -MemberType NoteProperty -Name 'IPAddress' -Value '' -Force
                } else {
                    $computerObj | Add-Member -MemberType NoteProperty -Name 'IPAddress' -Value @() -Force
                }
                $computerObj | Add-Member -MemberType NoteProperty -Name 'DNSResolutionErrors' -Value @() -Force
                $computerObj
                continue
            }
            
            # Extract hostnames from the object with improved processing
            $hostnameValue = $computerObj.$HostnameProperty
            if ($hostnameValue) {
                try {
                    if ($hostnameValue -is [string]) {
                        # Handle single hostname or comma/semicolon-separated string
                        $hostnames = $hostnameValue -split '[,;]' | ForEach-Object { 
                            $_.Trim() 
                        } | Where-Object { 
                            $_ -and $_.Length -gt 0 
                        }
                    } elseif ($hostnameValue -is [array]) {
                        # Array of hostnames
                        $hostnames = $hostnameValue | Where-Object { $_ -and $_.ToString().Trim().Length -gt 0 }
                    } else {
                        # Convert other types to string
                        $hostnames = @($hostnameValue.ToString().Trim()) | Where-Object { $_.Length -gt 0 }
                    }
                } catch {
                    $errorMsg = "Failed to process hostname property: $($_.Exception.Message)"
                    Write-Warning $errorMsg
                    $errors += $errorMsg
                }
            }
            
            if ($hostnames.Count -gt 0) {
                foreach ($hostname in $hostnames) {
                    if ([string]::IsNullOrWhiteSpace($hostname)) {
                        continue
                    }
                    
                    Write-Verbose "Resolving DNS for: $hostname"
                    
                    try {
                        # Resolve based on parameters with built-in timeout handling
                        if (-not $IPv6Only) {
                            try {
                                $resolveParams = @{
                                    Name = $hostname
                                    Type = 'A'
                                    ErrorAction = 'Stop'
                                }
                                if ($TimeoutSeconds -le 5) { $resolveParams.QuickTimeout = $true }
                                
                                $ipv4Results = Resolve-DnsName @resolveParams
                                foreach ($result in $ipv4Results) {
                                    if ($result.IP4Address) {
                                        [void]$ipAddressList.Add($result.IP4Address)
                                    } elseif ($result.IPAddress) {
                                        [void]$ipAddressList.Add($result.IPAddress)
                                    }
                                }
                            } catch {
                                $errors += "IPv4 resolution failed for '$hostname': $($_.Exception.Message)"
                            }
                        }
                        
                        if (-not $IPv4Only) {
                            try {
                                $resolveParams = @{
                                    Name = $hostname
                                    Type = 'AAAA'
                                    ErrorAction = 'Stop'
                                }
                                if ($TimeoutSeconds -le 5) { $resolveParams.QuickTimeout = $true }
                                
                                $ipv6Results = Resolve-DnsName @resolveParams
                                foreach ($result in $ipv6Results) {
                                    if ($result.IP6Address) {
                                        [void]$ipAddressList.Add($result.IP6Address)
                                    } elseif ($result.IPAddress) {
                                        [void]$ipAddressList.Add($result.IPAddress)
                                    }
                                }
                            } catch {
                                $errors += "IPv6 resolution failed for '$hostname': $($_.Exception.Message)"
                            }
                        }
                    } catch {
                        $errorMsg = "DNS resolution failed for '$hostname': $($_.Exception.Message)"
                        Write-Warning $errorMsg
                        $errors += $errorMsg
                    }
                }
                
                # Remove duplicates more efficiently while preserving array structure
                $uniqueIpAddresses = @($ipAddressList.ToArray() | Select-Object -Unique)
                Write-Verbose "Found $($uniqueIpAddresses.Count) unique IP address(es)"
            } else {
                Write-Verbose "No valid DNS hostnames found, skipping DNS resolution"
                $uniqueIpAddresses = @()
            }
            
            # Add IP address information and error information to the object
            if ($AsString) {
                $computerObj | Add-Member -MemberType NoteProperty -Name 'IPAddress' -Value ($uniqueIpAddresses -join ', ') -Force
            } else {
                $computerObj | Add-Member -MemberType NoteProperty -Name 'IPAddress' -Value $uniqueIpAddresses -Force
            }
            $computerObj | Add-Member -MemberType NoteProperty -Name 'DNSResolutionErrors' -Value $errors -Force
            $computerObj | Add-Member -MemberType NoteProperty -Name 'ResolvedHostnameCount' -Value $hostnames.Count -Force
            $computerObj | Add-Member -MemberType NoteProperty -Name 'IPAddressCount' -Value $uniqueIpAddresses.Count -Force
            
            # Output the enhanced object
            $computerObj
        }
    }
}
