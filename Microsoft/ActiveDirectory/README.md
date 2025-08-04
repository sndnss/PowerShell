# Active Directory PowerShell Tools
PowerShell tools for Microsoft Active Directory management and administration

## Available Tools

### [Add-IPAddressToObject](./Add-IPAddressToObject/)
DNS resolution and IP address enrichment for Active Directory computer objects
- High-performance DNS lookups with IPv4 and IPv6 support
- Pipeline-compatible design for bulk operations
- Integration with Get-ADComputer and LDAP query results

### [LDAP](./LDAP/)
LDAP-based tools for Active Directory operations
- **Get-LDAPComputerObject** - High-performance LDAP computer object queries
- **Get-LDAPUserObject** - High-performance LDAP user object queries

## Getting Started
Navigate to the specific tool directories for detailed documentation, examples, and usage instructions.
- Configurable timeout and retry mechanisms
- Detailed resolution tracking and error reporting

**Use Cases:**
- Network inventory and documentation
- IP address mapping for computer objects
- Network security assessments
- Asset management and tracking

### [LDAP/Get-LDAPComputerObject](./LDAP/Get-LDAPComputerObject/)
Retrieves Active Directory computer object information using efficient LDAP queries.

**Key Features:**
- High-performance LDAP queries
- Flexible property selection
- Get-ADComputer compatibility
- Batch processing for large datasets
- Custom domain and credential support

**Use Cases:**
- Computer object enumeration
- Asset discovery and inventory
- Security assessments
- Compliance reporting

### [LDAP/Get-LDAPUserObject](./LDAP/Get-LDAPUserObject/)
Retrieves Active Directory user object information using efficient LDAP queries.

**Key Features:**
- High-performance LDAP queries
- Flexible property selection
- Get-ADUser compatibility
- Batch processing for large datasets
- Custom domain and credential support

**Use Cases:**
- User object enumeration
- Identity management and auditing
- Security assessments
- Compliance reporting

## Quick Start

### Loading Functions
```powershell
# Load the Add-IPAddressToObject function
. .\Microsoft\ActiveDirectory\Add-IPAddressToObject\Add-IPAddressToObject.ps1

# Load the Get-LDAPComputerObject function
. .\Microsoft\ActiveDirectory\LDAP\Get-LDAPComputerObject\Get-LDAPComputerObject.ps1

# Load the Get-LDAPUserObject function
. .\Microsoft\ActiveDirectory\LDAP\Get-LDAPUserObject\Get-LDAPUserObject.ps1
```

### Basic Usage
```powershell
# Get help for any function
Get-Help Add-IPAddressToObject -Detailed
Get-Help Get-LDAPComputerObject -Examples
Get-Help Get-LDAPUserObject -Examples

# Simple computer query with IP resolution
Get-LDAPComputerObject -ComputerName "SERVER01" | Add-IPAddressToObject

# Bulk processing with filtering
Get-LDAPComputerObject -Properties OperatingSystem | 
    Where-Object { $_.OperatingSystem -like "*Server*" } | 
    Add-IPAddressToObject -IPv4Only
```

## Requirements

### System Requirements
- PowerShell 5.1 or higher
- Windows Server 2016+ or Windows 10+
- Network connectivity to domain controllers

### Permissions
- Domain user account (minimum)
- Read access to Active Directory
- DNS query permissions
- Network access for IP resolution

### Optional Dependencies
- Active Directory PowerShell module (for comparison operations)
- DNS server access for hostname resolution
- LDAP access to target domains

## Examples

### Computer Discovery and IP Mapping
```powershell
# Find all enabled computers and resolve their IP addresses
Get-LDAPComputerObject -Properties OperatingSystem,LastLogonDate | 
    Where-Object { $_.Enabled -eq $true } |
    Add-IPAddressToObject -TimeoutSeconds 3

# Get servers with their network information
Get-LDAPComputerObject -Properties OperatingSystem | 
    Where-Object { $_.OperatingSystem -like "*Server*" } |
    Add-IPAddressToObject -IPv4Only |
    Select-Object Name, OperatingSystem, DNSHostName, IPv4Addresses
```

### Security Assessment Scenarios
```powershell
# Find computers with outdated operating systems
Get-LDAPComputerObject -Properties OperatingSystem,LastLogonDate |
    Where-Object { 
        $_.OperatingSystem -like "*Windows 7*" -or 
        $_.OperatingSystem -like "*Server 2008*" 
    } |
    Add-IPAddressToObject

# Identify computers without recent logons
$cutoffDate = (Get-Date).AddDays(-90)
Get-LDAPComputerObject -Properties LastLogonDate |
    Where-Object { $_.LastLogonDate -lt $cutoffDate } |
    Add-IPAddressToObject -IPv4Only
```

### Cross-Domain Operations
```powershell
# Query remote domain with credentials
$cred = Get-Credential
Get-LDAPComputerObject -Domain "remote.domain.com" -Credential $cred |
    Add-IPAddressToObject -TimeoutSeconds 5
```

### Performance Optimization
```powershell
# Batch processing for large environments
Get-LDAPComputerObject -BatchSize 1000 |
    Add-IPAddressToObject -TimeoutSeconds 2 -Concurrent 10

# Quick resolution for time-sensitive operations
Get-LDAPComputerObject -ComputerName $computerList |
    Add-IPAddressToObject -QuickTimeout -IPv4Only
```

## Performance Notes

### Optimization Strategies
- **Batch Processing**: Use appropriate batch sizes for your environment
- **Timeout Configuration**: Adjust DNS resolution timeouts based on network conditions
- **Property Selection**: Request only needed properties to reduce query time
- **Concurrent Operations**: Balance concurrent DNS resolutions with network capacity

### Large Environment Considerations
- Process computers in batches to manage memory usage
- Use streaming operations for very large datasets
- Consider time-of-day for network-intensive operations
- Monitor DNS server performance during bulk operations

### Network Considerations
- DNS resolution timeout affects overall processing time
- Multiple concurrent resolutions can impact network performance
- Consider local DNS caching for repeated operations
- Network latency affects both LDAP queries and DNS resolution

### Memory Management
- Functions designed for pipeline processing to minimize memory usage
- Large result sets automatically use streaming where possible
- Garbage collection optimized for bulk operations
- Progress reporting available for long-running tasks
