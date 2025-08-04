<#PSScriptInfo

.DESCRIPTION Retrieves Active Directory computer object information using efficient LDAP queries with flexible property selection and Get-ADComputer compatibility.

.VERSION 1.0.0.0

.GUID 99b42518-c711-49b8-92ea-01b7b3507a91

.AUTHOR Tom Stryhn

.COMPANYNAME sndnss aps

.COPYRIGHT 2025 (c) Tom Stryhn

.TAGS Active Directory LDAP Computer Object Query

.LICENSEURI https://github.com/sndnss/PowerShell/blob/main/LICENSE

.PROJECTURI https://github.com/sndnss/PowerShell/Microsoft/ActiveDirectory/LDAP/Get-LDAPComputerObject/

#>

function Get-LDAPComputerObject {

<#
.SYNOPSIS
    Retrieves computer object information from Active Directory using LDAP queries with flexible property selection.

.DESCRIPTION
    This function searches Active Directory for computer objects by name and returns detailed information
    with customizable property selection. It supports pipeline input and can work with different domains and credentials.

.PARAMETER ComputerName
    One or more computer names to search for in Active Directory. Accepts pipeline input.

.PARAMETER Properties
    Additional AD properties to retrieve beyond the default set. Like Get-ADComputer, these properties are added to the default properties.
    Use '*' to retrieve all available properties. Property names match Get-ADComputer format (e.g., 'OperatingSystem', 'Description').
    Default properties always included: Name, DNSHostName, DistinguishedName, Enabled, ObjectClass, ObjectGUID, SamAccountName, SID, UserPrincipalName

.PARAMETER Domain
    The domain to search in. If not specified, uses the current domain.

.PARAMETER Credential
    Alternative credentials to use for the LDAP connection.

.PARAMETER BatchSize
    Number of computers to process in each batch for large datasets. Defaults to 500. 
    Larger batches use more memory but may be faster. Smaller batches are more memory efficient.

.PARAMETER NoProgress
    Suppress progress reporting during processing. Useful for automated scripts or when redirecting output.

.EXAMPLE
    Get-LDAPComputerObject -ComputerName "SERVER01"
    
    Retrieves default properties for SERVER01 (same as Get-ADComputer default output).

.EXAMPLE
    Get-LDAPComputerObject -ComputerName "SERVER01" -Properties "OperatingSystem", "Description"
    
    Retrieves default properties PLUS OperatingSystem and Description for SERVER01.

.EXAMPLE
    Get-LDAPComputerObject -ComputerName "SERVER01" -Properties "*"
    
    Retrieves all available properties for SERVER01.

.EXAMPLE
    $computers = 1..1000 | ForEach-Object { "SERVER$_" }
    Get-LDAPComputerObject -ComputerName $computers -BatchSize 100
    
    Processes 1000 computers in batches of 100 with progress reporting.

.OUTPUTS
    PSCustomObject with Get-ADComputer-compatible property names and structure

.NOTES
    Optimized for PowerShell 5.1 on Windows systems with enterprise-scale batch processing.
    Requires DirectoryServices assemblies (natively available on Windows).
    Output format and property names are compatible with Get-ADComputer for easy replacement.
    The function automatically disposes of DirectoryServices objects to prevent resource leaks.
    Includes LDAP injection protection and timeout handling for enterprise environments.
    
    Performance characteristics:
    - Small datasets (1-100): Processes immediately with minimal overhead
    - Medium datasets (100-1000): Uses batch processing with progress reporting
    - Large datasets (1000+): Optimized memory management with garbage collection
    
    For best performance with large datasets:
    - Use appropriate BatchSize (100-1000 depending on available memory)
    - Consider using -NoProgress for automated scripts
    - Monitor memory usage in very large operations (10000+ computers)
#>

    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
            )]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            foreach ($name in $_) {
                if ($name -match '[\\\/\(\)\*\&\|\!\=\<\>\~]') {
                    throw "Computer name '$name' contains invalid characters that could cause LDAP injection."
                }
            }
            return $true
        })]
        [string[]]$ComputerName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Properties,
        
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if ($_ -and $_ -notmatch '^[a-zA-Z0-9\-\.]+$') {
                throw "Domain name '$_' contains invalid characters."
            }
            return $true
        })]
        [string]$Domain,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,
        
        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 500,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoProgress
    )
    begin{
        Write-Verbose "Starting LDAP computer object retrieval"
        
        # Define default properties (same as Get-ADComputer)
        $defaultProperties = @('Name', 'DNSHostName', 'DistinguishedName', 'Enabled', 'ObjectClass', 'ObjectGUID', 'SamAccountName', 'SID', 'UserPrincipalName')
        
        # Combine default properties with additional properties requested
        if ($Properties) {
            # Add requested properties to defaults (like Get-ADComputer behavior)
            $allProperties = $defaultProperties + $Properties | Select-Object -Unique
        } else {
            # Use only default properties if none specified
            $allProperties = $defaultProperties
        }
        
        Write-Verbose "Properties to retrieve: $($allProperties -join ', ')"
        
        # Initialize variables for proper disposal
        $searcher = $null
        $directoryEntry = $null
        
        # Initialize batch processing variables
        $computerQueue = [System.Collections.Generic.List[string]]::new()
        $processedCount = 0
        $totalComputers = 0
        $batchNumber = 0
        
        try {
            # Determine domain to use
            if ($Domain) {
                $domainDN = $Domain
                Write-Verbose "Using specified domain: $Domain"
            } else {
                $domainDN = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
                Write-Verbose "Using current domain: $domainDN"
            }
            
            # Build LDAP path
            $ldapPath = "LDAP://" + ($domainDN -replace '\.', ',DC=' -replace '^', 'DC=')
            Write-Verbose "LDAP Path: $ldapPath"
            
            # Create directory entry with or without credentials
            if ($Credential) {
                $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $Credential.UserName, $Credential.GetNetworkCredential().Password)
                Write-Verbose "Using provided credentials for LDAP connection"
            } else {
                $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath)
                Write-Verbose "Using current user credentials for LDAP connection"
            }
            
            # Create searcher once for better performance
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
            
            # Set search timeout for PowerShell 5.1 environments (30 seconds)
            $searcher.ClientTimeout = New-TimeSpan -Seconds 30
            $searcher.ServerTimeLimit = New-TimeSpan -Seconds 25
            
            # Handle property selection
            $loadAllProperties = $allProperties -contains "*"
            if (-not $loadAllProperties) {
                # Map property names to LDAP attributes for loading
                $ldapProperties = foreach ($prop in $allProperties) {
                    switch ($prop) {
                        'Name' { 'name' }
                        'CN' { 'cn' }
                        'DNSHostName' { 'dnshostname' }
                        'DistinguishedName' { 'distinguishedname' }
                        'ObjectGUID' { 'objectguid' }
                        'ObjectClass' { 'objectclass' }
                        'SamAccountName' { 'samaccountname' }
                        'SID' { 'objectsid' }
                        'UserPrincipalName' { 'userprincipalname' }
                        'Enabled' { 'useraccountcontrol' }
                        'OperatingSystem' { 'operatingsystem' }
                        'OperatingSystemVersion' { 'operatingsystemversion' }
                        'OperatingSystemServicePack' { 'operatingsystemservicepack' }
                        'Created' { 'whencreated' }
                        'Modified' { 'whenchanged' }
                        'LastLogonDate' { 'lastlogontimestamp' }
                        'PasswordLastSet' { 'pwdlastset' }
                        default { $prop.ToLower() }
                    }
                }
                
                # Performance optimization: Load only the properties we need
                $searcher.PropertiesToLoad.AddRange($ldapProperties)
                Write-Verbose "Loading specific properties: $($allProperties -join ', ')"
            } else {
                Write-Verbose "Loading all available properties"
            }
            
            # Use ArrayList with initial capacity for better memory management
            # Estimate based on batch size for optimal memory allocation
            $estimatedCapacity = if ($BatchSize -gt 100) { $BatchSize } else { 100 }
            $output = New-Object System.Collections.ArrayList($estimatedCapacity)
        }
        catch [System.DirectoryServices.DirectoryServiceCOMException] {
            # Ensure cleanup on initialization failure
            if ($searcher) { $searcher.Dispose(); $searcher = $null }
            if ($directoryEntry) { $directoryEntry.Dispose(); $directoryEntry = $null }
            
            if ($_.Exception.ExtendedError -eq -2147016672) {
                Write-Error "Access denied. You may not have sufficient permissions to query Active Directory. Try running as an administrator or use the -Credential parameter."
            } else {
                Write-Error "Directory Services error: $($_.Exception.Message)"
            }
            throw
        }
        catch [System.UnauthorizedAccessException] {
            # Ensure cleanup on initialization failure
            if ($searcher) { $searcher.Dispose(); $searcher = $null }
            if ($directoryEntry) { $directoryEntry.Dispose(); $directoryEntry = $null }
            
            Write-Error "Access denied. You may not have sufficient permissions to query Active Directory. Try running as an administrator or use the -Credential parameter."
            throw
        }
        catch {
            # Ensure cleanup on initialization failure
            if ($searcher) { $searcher.Dispose(); $searcher = $null }
            if ($directoryEntry) { $directoryEntry.Dispose(); $directoryEntry = $null }
            
            Write-Error "Failed to initialize LDAP connection: $($_.Exception.Message)"
            throw
        }
    }

    process{
        # Add computers to the queue for batch processing
        foreach($comName in $ComputerName) {
            $computerQueue.Add($comName)
            $totalComputers++
        }
    }

    end {
        try {
            # Process computers in batches
            Write-Verbose "Processing $totalComputers computers in batches of $BatchSize"
            
            for ($i = 0; $i -lt $computerQueue.Count; $i += $BatchSize) {
                $batchNumber++
                $batchEnd = [Math]::Min($i + $BatchSize - 1, $computerQueue.Count - 1)
                $currentBatch = $computerQueue.GetRange($i, ($batchEnd - $i + 1))
                
                if (-not $NoProgress) {
                    $progressParams = @{
                        Activity = "Processing AD Computer Objects"
                        Status = "Batch $batchNumber - Processing computers $($i + 1) to $($batchEnd + 1) of $totalComputers"
                        PercentComplete = [Math]::Round(($i / $computerQueue.Count) * 100, 1)
                        CurrentOperation = "Current batch size: $($currentBatch.Count) computers"
                    }
                    Write-Progress @progressParams
                }
                
                Write-Verbose "Processing batch $batchNumber with $($currentBatch.Count) computers"
                
                # Process current batch
                $batchProcessedCount = 0
                foreach($comName in $currentBatch) {
                    $batchProcessedCount++
                    $processedCount++
                    $result = $null

                    # Update progress for individual items in large batches
                    if (-not $NoProgress -and $currentBatch.Count -gt 50) {
                        $batchProgress = [Math]::Round(($batchProcessedCount / $currentBatch.Count) * 100, 1)
                        Write-Progress -Id 1 -ParentId 0 -Activity "Processing Batch $batchNumber" -Status "Computer: $comName" -PercentComplete $batchProgress
                    }

                    Write-Verbose "Processing computer: $comName (Overall: $processedCount/$totalComputers)"

                    # Sanitize computer name for LDAP filter (additional safety for PS 5.1)
                    $sanitizedName = $comName -replace '[\\\/\(\)\*\&\|\!\=\<\>\~]', ''
                    if ($sanitizedName -ne $comName) {
                        Write-Warning "Computer name '$comName' contained special characters and was sanitized to '$sanitizedName'"
                    }

                    # Reuse the searcher and just update the filter
                    $searcher.Filter = "(&(objectClass=computer)(cn=$sanitizedName))"

                    try {
                        $result = $searcher.FindOne()

                        if ($null -eq $result) {
                            Write-Warning "Computer '$comName' not found in Active Directory"
                            continue
                        }

                        Write-Verbose "Found computer '$comName' in Active Directory"
                        
                        # Create computer object with Get-ADComputer-like structure and property order
                        # Use ordered hashtable with estimated capacity for memory efficiency
                        $computerObject = [ordered]@{}
                        
                        # Pre-allocate property hash with estimated size to reduce memory reallocations
                        $propertyHash = [hashtable]::new($result.Properties.PropertyNames.Count)
                        foreach ($propertyName in $result.Properties.PropertyNames) {
                            $propertyHash[$propertyName.ToLower()] = $result.Properties[$propertyName]
                        }
                        
                        # Helper function to add properties in the correct order
                        $addProperty = {
                            param($Name, $LdapName, $SpecialHandling = $null)
                            
                            if ($loadAllProperties -or ($allProperties -contains $Name)) {
                                if ($propertyHash.ContainsKey($LdapName.ToLower())) {
                                    $propertyValues = $propertyHash[$LdapName.ToLower()]
                                    
                                    switch ($SpecialHandling) {
                                        'Enabled' {
                                            $uacValue = $propertyValues[0]
                                            $enabled = -not ($uacValue -band 2)
                                            $computerObject[$Name] = $enabled
                                        }
                                        'ObjectGUID' {
                                            if ($propertyValues[0] -is [byte[]]) {
                                                $guid = New-Object System.Guid(,$propertyValues[0])
                                                $computerObject[$Name] = $guid.ToString()
                                            } else {
                                                $computerObject[$Name] = $propertyValues[0]
                                            }
                                        }
                                        'SID' {
                                            if ($propertyValues[0] -is [byte[]]) {
                                                $sid = New-Object System.Security.Principal.SecurityIdentifier($propertyValues[0], 0)
                                                $computerObject[$Name] = $sid
                                            } else {
                                                $computerObject[$Name] = $propertyValues[0]
                                            }
                                        }
                                        'ObjectClass' {
                                            $computerObject[$Name] = 'computer'
                                        }
                                        default {
                                            if ($propertyValues.Count -eq 1) {
                                                $computerObject[$Name] = $propertyValues[0]
                                            } else {
                                                $computerObject[$Name] = ($propertyValues -join ', ')
                                                if ($propertyValues.Count -gt 1) {
                                                    Write-Verbose "Property '$Name' for computer '$comName' has multiple values: $($propertyValues -join ', ')"
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    # Property not found, add as null if it was specifically requested
                                    if ($allProperties -contains $Name) {
                                        $computerObject[$Name] = $null
                                    }
                                }
                            }
                        }
                        
                        # Add properties in Get-ADComputer order
                        & $addProperty 'DistinguishedName' 'distinguishedname'
                        & $addProperty 'DNSHostName' 'dnshostname'
                        & $addProperty 'Enabled' 'useraccountcontrol' 'Enabled'
                        & $addProperty 'Name' 'name'
                        & $addProperty 'ObjectClass' 'objectclass' 'ObjectClass'
                        & $addProperty 'ObjectGUID' 'objectguid' 'ObjectGUID'
                        & $addProperty 'SamAccountName' 'samaccountname'
                        & $addProperty 'SID' 'objectsid' 'SID'
                        & $addProperty 'UserPrincipalName' 'userprincipalname'
                        
                        # Add any additional requested properties in alphabetical order
                        if ($Properties) {
                            $additionalProps = $Properties | Where-Object { 
                                $_ -notin @('DistinguishedName', 'DNSHostName', 'Enabled', 'Name', 'ObjectClass', 'ObjectGUID', 'SamAccountName', 'SID', 'UserPrincipalName', '*') 
                            } | Sort-Object
                            foreach ($prop in $additionalProps) {
                                $ldapName = switch ($prop) {
                                    'CN' { 'cn' }
                                    'OperatingSystem' { 'operatingsystem' }
                                    'OperatingSystemVersion' { 'operatingsystemversion' }
                                    'OperatingSystemServicePack' { 'operatingsystemservicepack' }
                                    'Created' { 'whencreated' }
                                    'Modified' { 'whenchanged' }
                                    'LastLogonDate' { 'lastlogontimestamp' }
                                    'PasswordLastSet' { 'pwdlastset' }
                                    'Description' { 'description' }
                                    'Location' { 'location' }
                                    default { $prop.ToLower() }
                                }
                                & $addProperty $prop $ldapName
                            }
                        }
                        
                        # If loading all properties, add remaining ones alphabetically
                        if ($loadAllProperties) {
                            $remainingProps = $propertyHash.Keys | Where-Object { 
                                $propName = switch ($_.ToLower()) {
                                    'name' { 'Name' }
                                    'cn' { 'CN' }
                                    'dnshostname' { 'DNSHostName' }
                                    'distinguishedname' { 'DistinguishedName' }
                                    'objectguid' { 'ObjectGUID' }
                                    'objectclass' { 'ObjectClass' }
                                    'samaccountname' { 'SamAccountName' }
                                    'objectsid' { 'SID' }
                                    'userprincipalname' { 'UserPrincipalName' }
                                    'useraccountcontrol' { 'Enabled' }
                                    'operatingsystem' { 'OperatingSystem' }
                                    'operatingsystemversion' { 'OperatingSystemVersion' }
                                    'operatingsystemservicepack' { 'OperatingSystemServicePack' }
                                    'whencreated' { 'Created' }
                                    'whenchanged' { 'Modified' }
                                    'lastlogontimestamp' { 'LastLogonDate' }
                                    'pwdlastset' { 'PasswordLastSet' }
                                    'description' { 'Description' }
                                    'location' { 'Location' }
                                    default { $_ }
                                }
                                -not $computerObject.Contains($propName)
                            } | Sort-Object
                            
                            foreach ($ldapProp in $remainingProps) {
                                $propName = switch ($ldapProp.ToLower()) {
                                    'operatingsystem' { 'OperatingSystem' }
                                    'operatingsystemversion' { 'OperatingSystemVersion' }
                                    'operatingsystemservicepack' { 'OperatingSystemServicePack' }
                                    'whencreated' { 'Created' }
                                    'whenchanged' { 'Modified' }
                                    'lastlogontimestamp' { 'LastLogonDate' }
                                    'pwdlastset' { 'PasswordLastSet' }
                                    'description' { 'Description' }
                                    'location' { 'Location' }
                                    default { $ldapProp }
                                }
                                & $addProperty $propName $ldapProp
                            }
                        }
                        
                        # Convert ordered hashtable to PSCustomObject
                        $computerObjectFinal = [PSCustomObject]$computerObject
                        
                        [void]$output.Add($computerObjectFinal)
                        Write-Verbose "Successfully processed computer: $comName"
                        
                        # Explicit cleanup for large result sets (PowerShell 5.1 optimization)
                        $result = $null
                        $propertyHash.Clear()
                        $propertyHash = $null
                        $computerObject = $null
                    }
                    catch [System.DirectoryServices.DirectoryServiceCOMException] {
                        if ($_.Exception.ExtendedError -eq -2147016672) {
                            Write-Error "Access denied while querying computer '$comName'. You may not have sufficient permissions to query Active Directory."
                        } else {
                            Write-Error "Directory Services error while processing computer '$comName': $($_.Exception.Message)"
                        }
                        continue
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Error "Access denied while querying computer '$comName'. You may not have sufficient permissions to query Active Directory."
                        continue
                    }
                    catch {
                        Write-Error "Error processing computer '$comName': $($_.Exception.Message)"
                        continue
                    }
                }
                
                # End of batch - perform garbage collection for large datasets
                if ($BatchSize -ge 100) {
                    Write-Verbose "Completed batch $batchNumber. Performing garbage collection."
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                }
                
                # Clear nested progress bar
                if (-not $NoProgress -and $currentBatch.Count -gt 50) {
                    Write-Progress -Id 1 -Activity "Processing Batch $batchNumber" -Completed
                }
            }
            
            # Clear main progress bar
            if (-not $NoProgress) {
                Write-Progress -Activity "Processing AD Computer Objects" -Completed
            }
        }
        finally {
            # Ensure proper cleanup regardless of how execution ends
            try {
                if ($searcher) {
                    $searcher.Dispose()
                    $searcher = $null
                }
            }
            catch {
                Write-Verbose "Error disposing searcher: $($_.Exception.Message)"
            }
            
            try {
                if ($directoryEntry) {
                    $directoryEntry.Dispose()
                    $directoryEntry = $null
                }
            }
            catch {
                Write-Verbose "Error disposing directory entry: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "LDAP computer object retrieval completed. Found $($output.Count) objects out of $totalComputers requested."
        
        # Return array and help GC by clearing the ArrayList reference
        $result = $output.ToArray()
        $output.Clear()
        $output = $null
        $computerQueue.Clear()
        $computerQueue = $null
        
        return $result
    }
}