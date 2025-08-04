# Add-IPAddressToObject
DNS resolution function that adds IP address information to Active Directory computer objects with enhanced error handling and performance optimization

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Performance](#performance)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Parameters](#parameters)
- [Examples](#examples)
- [Output Properties](#output-properties)
- [Integration Scenarios](#integration-scenarios)
- [Performance Optimization](#performance-optimization)
- [Troubleshooting](#troubleshooting)
- [Compatibility](#compatibility)

## Overview
Add-IPAddressToObject is a PowerShell function that enhances Active Directory computer objects by adding resolved IP address information. It works seamlessly with Get-ADComputer, Get-LDAPComputerObject, or any other source that provides DNS hostname properties, making it an essential tool for network inventory, security assessments, and asset management.

**Key Benefits:**
- Seamless integration with AD PowerShell cmdlets
- High-performance DNS resolution with timeout controls
- Comprehensive error handling and reporting
- Support for both IPv4 and IPv6 resolution
- Pipeline-optimized for bulk operations
- Enhanced tracking and statistics

## Features

### DNS Resolution Capabilities
- **Dual Stack Support**: Resolves both IPv4 (A records) and IPv6 (AAAA records)
- **Selective Resolution**: IPv4-only or IPv6-only options for specific requirements
- **Timeout Control**: Configurable DNS resolution timeouts with QuickTimeout support
- **Multiple Hostname Support**: Handles comma/semicolon-separated hostname strings
- **Error Resilience**: Individual hostname failures don't stop processing

### Integration Features
- **Pipeline Compatible**: Full pipeline input and output support
- **Multi-Source Support**: Works with Get-ADComputer, Get-LDAPComputerObject, and custom objects
- **Property Flexibility**: Configurable hostname property name
- **Output Options**: Array or comma-separated string output formats
- **Statistics Tracking**: Built-in resolution statistics and error reporting

### Performance Optimization
- **Efficient Collections**: ArrayList usage for better performance than array concatenation
- **QuickTimeout**: Automatic fast-fail for unresponsive DNS queries
- **Minimal Memory Footprint**: Optimized object processing
- **Error Isolation**: Individual hostname errors don't affect batch processing

## Performance

### DNS Resolution Speed
| Scenario | Standard Timeout | QuickTimeout (≤5s) | Improvement |
|----------|------------------|-------------------|-------------|
| Responsive DNS | ~500ms per host | ~500ms per host | No change |
| Slow DNS | ~30s per host | ~2s per host | 15x faster |
| Failed DNS | ~30s per host | ~1s per host | 30x faster |
| Bulk Operations | Variable | Predictable | Consistent timing |

### Processing Efficiency
- **Memory Usage**: Optimized with ArrayList collections
- **Error Handling**: Individual failures don't block processing
- **Batch Operations**: Efficient pipeline processing for large datasets
- **Resource Management**: Proper cleanup and garbage collection

## Requirements

### System Requirements
- PowerShell 5.1 or higher
- DNS resolution capabilities
- Network connectivity to DNS servers

### Permissions
- Standard user account (for DNS resolution)
- Network access to DNS servers
- No special AD permissions required (works with any object source)

### Compatible Input Sources
- Get-ADComputer output
- Get-LDAPComputerObject output
- Custom PSObjects with hostname properties
- Any object containing DNS hostname information

## Quick Start

### Loading the Function
```powershell
# Load the function
. .\Microsoft\ActiveDirectory\Add-IPAddressToObject\Add-IPAddressToObject.ps1

# Get help
Get-Help Add-IPAddressToObject -Detailed
```

### Basic Usage
```powershell
# Add IP addresses to a single computer
Get-ADComputer "SERVER01" | Add-IPAddressToObject

# Add IP addresses to multiple computers
Get-ADComputer -Filter "Name -like 'SERVER*'" | Add-IPAddressToObject

# Use with Get-LDAPComputerObject for better performance
Get-LDAPComputerObject -ComputerName "SERVER01" | Add-IPAddressToObject
```

## Parameters

### InputObject
**Type:** PSObject[]  
**Required:** Yes  
**Pipeline:** Yes  
**Description:** Objects containing DNS hostname information from any source.

```powershell
# Pipeline input (recommended)
Get-ADComputer "SERVER01" | Add-IPAddressToObject

# Direct parameter input
$computers = Get-ADComputer -Filter *
Add-IPAddressToObject -InputObject $computers
```

### HostnameProperty
**Type:** String  
**Required:** No  
**Default:** 'DNSHostName'  
**Description:** Property name containing the DNS hostname(s).

```powershell
# Default property (DNSHostName)
Get-ADComputer "SERVER01" | Add-IPAddressToObject

# Custom property name
$customObjects | Add-IPAddressToObject -HostnameProperty "ComputerName"
```

### IPv4Only / IPv6Only
**Type:** Switch  
**Required:** No  
**Description:** Resolve only IPv4 or IPv6 addresses. Cannot be used together.

```powershell
# IPv4 addresses only
Get-ADComputer -Filter * | Add-IPAddressToObject -IPv4Only

# IPv6 addresses only
Get-ADComputer -Filter * | Add-IPAddressToObject -IPv6Only

# Both IPv4 and IPv6 (default)
Get-ADComputer -Filter * | Add-IPAddressToObject
```

### TimeoutSeconds
**Type:** Integer  
**Required:** No  
**Default:** 5  
**Range:** 1-300  
**Description:** DNS resolution timeout. Values ≤5 enable QuickTimeout for faster failure detection.

```powershell
# Quick timeout for responsive environments
Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 2

# Longer timeout for slow networks
Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 15
```

### AsString
**Type:** Switch  
**Required:** No  
**Description:** Return IP addresses as comma-separated string instead of array.

```powershell
# Array output (default) - like Get-ADComputer multi-value properties
$computer = Get-ADComputer "SERVER01" | Add-IPAddressToObject
$computer.IPAddress  # Returns: @("192.168.1.10", "fe80::1")

# String output - for compatibility or display
$computer = Get-ADComputer "SERVER01" | Add-IPAddressToObject -AsString
$computer.IPAddress  # Returns: "192.168.1.10, fe80::1"
```

## Examples

### Basic Computer Inventory
```powershell
# Get all computers with IP addresses
$inventory = Get-ADComputer -Filter * | Add-IPAddressToObject
$inventory | Select-Object Name, DNSHostName, IPAddress, IPAddressCount

# Export to CSV for documentation
$inventory | Export-Csv "ComputerInventory.csv" -NoTypeInformation
```

### High-Performance Operations
```powershell
# Use Get-LDAPComputerObject for better performance with large datasets
$computers = Get-LDAPComputerObject | Add-IPAddressToObject -IPv4Only -TimeoutSeconds 3

# Process specific computer list efficiently
$serverList = @("SERVER01", "SERVER02", "SERVER03")
$servers = Get-LDAPComputerObject -ComputerName $serverList | Add-IPAddressToObject
```

### Network Security Assessment
```powershell
# Find computers with multiple IP addresses (multi-homed)
Get-ADComputer -Filter * | 
    Add-IPAddressToObject | 
    Where-Object { $_.IPAddressCount -gt 1 } |
    Select-Object Name, DNSHostName, IPAddress

# Identify computers with DNS resolution issues
Get-ADComputer -Filter * | 
    Add-IPAddressToObject | 
    Where-Object { $_.DNSResolutionErrors.Count -gt 0 } |
    Select-Object Name, DNSHostName, DNSResolutionErrors
```

### IPv6 Network Analysis
```powershell
# Get IPv6 addresses for network planning
Get-ADComputer -Filter * | 
    Add-IPAddressToObject -IPv6Only | 
    Where-Object { $_.IPAddressCount -gt 0 } |
    Select-Object Name, IPAddress

# Compare IPv4 vs IPv6 deployment
$computers = Get-ADComputer -Filter * | Add-IPAddressToObject
$ipv4Count = ($computers | Add-IPAddressToObject -IPv4Only | Where-Object { $_.IPAddressCount -gt 0 }).Count
$ipv6Count = ($computers | Add-IPAddressToObject -IPv6Only | Where-Object { $_.IPAddressCount -gt 0 }).Count
Write-Host "IPv4: $ipv4Count computers, IPv6: $ipv6Count computers"
```

### Custom Object Integration
```powershell
# Work with custom objects
$customComputers = Import-Csv "computers.csv"  # Columns: ComputerName, Environment
$customComputers | Add-IPAddressToObject -HostnameProperty "ComputerName"

# Create custom reports
$customComputers | 
    Add-IPAddressToObject -HostnameProperty "ComputerName" -AsString |
    Select-Object ComputerName, Environment, IPAddress, IPAddressCount |
    Export-Csv "NetworkReport.csv" -NoTypeInformation
```

### Error Handling and Troubleshooting
```powershell
# Identify DNS resolution problems
$results = Get-ADComputer -Filter * | Add-IPAddressToObject -Verbose

# Computers with resolution errors
$problemComputers = $results | Where-Object { $_.DNSResolutionErrors.Count -gt 0 }
$problemComputers | Select-Object Name, DNSHostName, DNSResolutionErrors

# Computers without IP addresses
$noIPComputers = $results | Where-Object { $_.IPAddressCount -eq 0 }
$noIPComputers | Select-Object Name, DNSHostName, ResolvedHostnameCount
```

### Performance Testing
```powershell
# Compare different timeout settings
Measure-Command { 
    Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 2 
}

Measure-Command { 
    Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 10 
}

# Test with different input sources
Measure-Command { 
    Get-ADComputer -Filter * | Add-IPAddressToObject 
}

Measure-Command { 
    Get-LDAPComputerObject | Add-IPAddressToObject 
}
```

## Output Properties

### Original Properties
All original object properties are preserved unchanged.

### Added Properties
| Property | Type | Description |
|----------|------|-------------|
| IPAddress | Array/String | Resolved IP addresses (array by default, string with -AsString) |
| DNSResolutionErrors | Array | Any DNS resolution errors encountered |
| ResolvedHostnameCount | Integer | Number of hostnames processed |
| IPAddressCount | Integer | Number of unique IP addresses found |

### Property Examples
```powershell
$computer = Get-ADComputer "SERVER01" | Add-IPAddressToObject

# Access resolved IP addresses
$computer.IPAddress                 # @("192.168.1.10", "fe80::abc:123")
$computer.IPAddressCount           # 2
$computer.ResolvedHostnameCount    # 1
$computer.DNSResolutionErrors      # @() (empty if no errors)

# Check for resolution issues
if ($computer.DNSResolutionErrors.Count -gt 0) {
    Write-Warning "DNS resolution issues: $($computer.DNSResolutionErrors -join '; ')"
}
```

## Integration Scenarios

### Get-ADComputer Integration
```powershell
# Standard Get-ADComputer workflow enhanced with IP resolution
$computers = Get-ADComputer -Filter "OperatingSystem -like '*Server*'" -Properties OperatingSystem, LastLogonDate
$enhancedComputers = $computers | Add-IPAddressToObject

# Use enhanced data for reporting
$enhancedComputers | 
    Select-Object Name, OperatingSystem, LastLogonDate, IPAddress, IPAddressCount |
    Where-Object { $_.IPAddressCount -gt 0 } |
    Export-Csv "ServerInventory.csv" -NoTypeInformation
```

### Get-LDAPComputerObject Integration
```powershell
# High-performance workflow for large environments
$computers = Get-LDAPComputerObject -Properties OperatingSystem, LastLogonDate
$networkInventory = $computers | Add-IPAddressToObject -IPv4Only -TimeoutSeconds 3

# Filter and process results
$activeServers = $networkInventory | 
    Where-Object { 
        $_.OperatingSystem -like "*Server*" -and 
        $_.IPAddressCount -gt 0 -and
        $_.LastLogonDate -gt (Get-Date).AddDays(-30)
    }
```

### Security Assessment Workflows
```powershell
# Security-focused computer analysis
function Get-ComputerSecurityInfo {
    param([string[]]$ComputerName)
    
    # Get computer information with IP addresses
    $computers = if ($ComputerName) {
        Get-LDAPComputerObject -ComputerName $ComputerName
    } else {
        Get-LDAPComputerObject -Properties OperatingSystem, LastLogonDate
    }
    
    $results = $computers | Add-IPAddressToObject
    
    # Analyze for security concerns
    foreach ($computer in $results) {
        [PSCustomObject]@{
            Name = $computer.Name
            DNSHostName = $computer.DNSHostName
            IPAddresses = $computer.IPAddress -join "; "
            IPAddressCount = $computer.IPAddressCount
            MultiHomed = $computer.IPAddressCount -gt 1
            DNSIssues = $computer.DNSResolutionErrors.Count -gt 0
            LastLogon = $computer.LastLogonDate
            OperatingSystem = $computer.OperatingSystem
            SecurityScore = if ($computer.DNSResolutionErrors.Count -gt 0) { "High Risk" } 
                           elseif ($computer.IPAddressCount -eq 0) { "Medium Risk" }
                           elseif ($computer.IPAddressCount -gt 1) { "Review Required" }
                           else { "Normal" }
        }
    }
}

# Run security assessment
$securityReport = Get-ComputerSecurityInfo
$securityReport | Where-Object { $_.SecurityScore -ne "Normal" }
```

### Asset Management Integration
```powershell
# Complete asset inventory workflow
function New-AssetInventoryReport {
    param(
        [string]$OutputPath = "AssetInventory.xlsx",
        [switch]$IncludeNetworkInfo
    )
    
    Write-Host "Gathering computer information..."
    $computers = Get-LDAPComputerObject -Properties OperatingSystem, LastLogonDate, Description
    
    if ($IncludeNetworkInfo) {
        Write-Host "Resolving IP addresses..."
        $computers = $computers | Add-IPAddressToObject -TimeoutSeconds 5
    }
    
    # Create comprehensive inventory
    $inventory = $computers | ForEach-Object {
        [PSCustomObject]@{
            ComputerName = $_.Name
            DNSHostName = $_.DNSHostName
            OperatingSystem = $_.OperatingSystem
            LastLogonDate = $_.LastLogonDate
            Description = $_.Description
            Enabled = $_.Enabled
            IPAddresses = if ($IncludeNetworkInfo) { $_.IPAddress -join "; " } else { "Not Collected" }
            IPAddressCount = if ($IncludeNetworkInfo) { $_.IPAddressCount } else { $null }
            DNSIssues = if ($IncludeNetworkInfo) { $_.DNSResolutionErrors.Count -gt 0 } else { $null }
            InventoryDate = Get-Date
        }
    }
    
    # Export results
    $inventory | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "Inventory exported to: $OutputPath"
    
    return $inventory
}

# Generate complete inventory with network information
$inventory = New-AssetInventoryReport -IncludeNetworkInfo
```

## Performance Optimization

### DNS Resolution Optimization
```powershell
# Quick timeout for responsive environments
Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 2

# Selective resolution to reduce processing time
Get-ADComputer -Filter * | Add-IPAddressToObject -IPv4Only -TimeoutSeconds 3

# Batch processing for large datasets
$computerBatches = Get-ADComputer -Filter * | Group-Object { [Math]::Floor($_.Name[0] / 10) }
$results = foreach ($batch in $computerBatches) {
    $batch.Group | Add-IPAddressToObject -TimeoutSeconds 5
}
```

### Memory Management
```powershell
# Process results in chunks for very large environments
$allComputers = Get-LDAPComputerObject
$chunkSize = 1000
$results = @()

for ($i = 0; $i -lt $allComputers.Count; $i += $chunkSize) {
    $chunk = $allComputers[$i..($i + $chunkSize - 1)]
    $chunkResults = $chunk | Add-IPAddressToObject -IPv4Only -TimeoutSeconds 3
    $results += $chunkResults
    
    # Force garbage collection for large datasets
    [System.GC]::Collect()
    Write-Progress -Activity "Processing Computers" -Status "Processed $($i + $chunk.Count) of $($allComputers.Count)" -PercentComplete (($i / $allComputers.Count) * 100)
}
```

### Network Optimization
```powershell
# Optimize for different network conditions
function Get-OptimalDNSSettings {
    param([string]$NetworkType = "Corporate")
    
    switch ($NetworkType) {
        "Corporate" { 
            return @{ TimeoutSeconds = 5; IPv4Only = $false }
        }
        "Remote" { 
            return @{ TimeoutSeconds = 10; IPv4Only = $true }
        }
        "HighLatency" { 
            return @{ TimeoutSeconds = 15; IPv4Only = $true }
        }
        "Testing" { 
            return @{ TimeoutSeconds = 2; IPv4Only = $true }
        }
    }
}

# Apply optimal settings
$settings = Get-OptimalDNSSettings -NetworkType "Corporate"
Get-ADComputer -Filter * | Add-IPAddressToObject @settings
```

## Troubleshooting

### Common Issues

#### "No valid DNS hostnames found"
**Cause:** Object missing DNSHostName property or property is empty  
**Solutions:**
```powershell
# Check if property exists
$computer = Get-ADComputer "SERVER01"
$computer.PSObject.Properties.Name -contains "DNSHostName"

# Verify property value
$computer.DNSHostName

# Use custom property name if needed
$customObjects | Add-IPAddressToObject -HostnameProperty "ComputerName"
```

#### DNS resolution timeouts
**Cause:** Network latency or unresponsive DNS servers  
**Solutions:**
```powershell
# Increase timeout for slow networks
Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 15

# Use QuickTimeout for faster failure detection
Get-ADComputer -Filter * | Add-IPAddressToObject -TimeoutSeconds 3

# Check DNS server connectivity
Test-NetConnection -ComputerName "8.8.8.8" -Port 53
```

#### High DNS resolution errors
**Cause:** Invalid hostnames, DNS server issues, or network problems  
**Solutions:**
```powershell
# Identify problematic hostnames
$results = Get-ADComputer -Filter * | Add-IPAddressToObject -Verbose
$errorComputers = $results | Where-Object { $_.DNSResolutionErrors.Count -gt 0 }
$errorComputers.DNSResolutionErrors

# Test specific hostname resolution
Resolve-DnsName -Name "problematic-hostname.domain.com" -Type A -ErrorAction SilentlyContinue
```

#### Memory usage with large datasets
**Cause:** Processing thousands of computers simultaneously  
**Solutions:**
```powershell
# Process in smaller batches
$computers = Get-ADComputer -Filter *
$batchSize = 500
for ($i = 0; $i -lt $computers.Count; $i += $batchSize) {
    $batch = $computers[$i..($i + $batchSize - 1)]
    $batch | Add-IPAddressToObject | Export-Csv "Batch$i.csv" -Append -NoTypeInformation
}

# Use streaming processing
Get-ADComputer -Filter * | ForEach-Object { $_ | Add-IPAddressToObject }
```

### Debugging
```powershell
# Enable verbose output for troubleshooting
Get-ADComputer "SERVER01" | Add-IPAddressToObject -Verbose

# Check DNS configuration
Get-DnsClientServerAddress

# Test DNS resolution manually
Resolve-DnsName -Name "server01.domain.com" -Type A
Resolve-DnsName -Name "server01.domain.com" -Type AAAA
```

## Compatibility

### PowerShell Version Compatibility
- **PowerShell 5.1**: Full compatibility
- **PowerShell Core 6+**: Full compatibility
- **PowerShell 7+**: Full compatibility with enhanced performance

### Input Object Compatibility
Perfect compatibility with:
- Get-ADComputer output (all versions)
- Get-LDAPComputerObject output
- Custom PSObjects with hostname properties
- Import-Csv output with hostname columns

### Integration Compatibility
```powershell
# Drop-in enhancement for existing Get-ADComputer workflows
# Replace this:
$computers = Get-ADComputer -Filter *

# With this:
$computers = Get-ADComputer -Filter * | Add-IPAddressToObject

# All existing property access continues to work
$computers | Select-Object Name, OperatingSystem, Enabled
```

### Output Format Compatibility
```powershell
# Array output (default) compatible with PowerShell conventions
$computer.IPAddress[0]  # First IP address
$computer.IPAddress.Count  # Number of IP addresses

# String output compatible with CSV export and legacy systems
$computer.IPAddress  # "192.168.1.10, fe80::abc"
```
