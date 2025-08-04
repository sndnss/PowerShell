<#PSScriptInfo

.DESCRIPTION Retrieves Active Directory user object information using efficient LDAP queries with flexible property selection and Get-ADUser compatibility.

.VERSION 1.2.0.1

.GUID a8c42618-d822-4ab9-93fb-02c8c4608b92

.AUTHOR Tom Stryhn

.COMPANYNAME sndnss aps

.COPYRIGHT 2025 (c) Tom Stryhn

.TAGS Active Directory LDAP User Object Query

.LICENSEURI https://github.com/sndnss/PowerShell/blob/main/LICENSE

.PROJECTURI https://github.com/sndnss/PowerShell/Microsoft/ActiveDirectory/LDAP/Get-LDAPUserObject/

#>

function Get-LDAPUserObject {

<#
.SYNOPSIS
    Retrieves user object information from Active Directory using LDAP queries with flexible property selection.

.DESCRIPTION
    This function searches Active Directory for user objects by name and returns detailed information
    with customizable property selection. It supports pipeline input and can work with different domains and credentials.

.PARAMETER UserName
    One or more user names to search for in Active Directory. Accepts pipeline input.
    Can be SamAccountName, UserPrincipalName, or DisplayName.

.PARAMETER Properties
    Additional AD properties to retrieve beyond the default set. Like Get-ADUser, these properties are added to the default properties.
    Use '*' to retrieve all available properties. Property names match Get-ADUser format (e.g., 'Department', 'Title').
    Default properties always included: Name, UserPrincipalName, SamAccountName, DistinguishedName, Enabled, ObjectClass, ObjectGUID, SID

.PARAMETER Domain
    The domain to search in. If not specified, uses the current domain.

.PARAMETER Credential
    Alternative credentials to use for the LDAP connection.

.PARAMETER BatchSize
    Number of users to process in each batch for large datasets. Defaults to 500. 
    Larger batches use more memory but may be faster. Smaller batches are more memory efficient.

.PARAMETER NoProgress
    Suppress progress reporting during processing. Useful for automated scripts or when redirecting output.

.PARAMETER SearchBy
    Specify which attribute to search by. Valid values: SamAccountName, UserPrincipalName, DisplayName, Name.
    Defaults to SamAccountName for compatibility with Get-ADUser.

.EXAMPLE
    Get-LDAPUserObject -UserName "jdoe"
    
    Retrieves default properties for user jdoe (same as Get-ADUser default output).

.EXAMPLE
    Get-LDAPUserObject -UserName "john.doe@company.com" -SearchBy UserPrincipalName
    
    Retrieves user by UPN with default properties.

.EXAMPLE
    Get-LDAPUserObject -UserName "jdoe" -Properties "Department", "Title", "Manager"
    
    Retrieves default properties PLUS Department, Title, and Manager for jdoe.

.EXAMPLE
    Get-LDAPUserObject -UserName "jdoe" -Properties "*"
    
    Retrieves all available properties for jdoe.

.EXAMPLE
    $users = Import-Csv "users.csv" | Select-Object -ExpandProperty SamAccountName
    Get-LDAPUserObject -UserName $users -BatchSize 100
    
    Processes users from CSV in batches of 100 with progress reporting.

.OUTPUTS
    PSCustomObject with Get-ADUser-compatible property names and structure

.NOTES
    Optimized for PowerShell 5.1 on Windows systems with enterprise-scale batch processing.
    Requires DirectoryServices assemblies (natively available on Windows).
    Output format and property names are compatible with Get-ADUser for easy replacement.
    The function automatically disposes of DirectoryServices objects to prevent resource leaks.
    Includes LDAP injection protection and timeout handling for enterprise environments.
    
    Performance characteristics:
    - Small datasets (1-100): Processes immediately with minimal overhead
    - Medium datasets (100-1000): Uses batch processing with progress reporting
    - Large datasets (1000+): Optimized memory management with garbage collection
    
    For best performance with large datasets:
    - Use appropriate BatchSize (100-1000 depending on available memory)
    - Consider using -NoProgress for automated scripts
    - Monitor memory usage in very large operations (10000+ users)
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
                    throw "User name '$name' contains invalid characters that could cause LDAP injection."
                }
            }
            return $true
        })]
        [string[]]$UserName,
        
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
        [switch]$NoProgress,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('SamAccountName', 'UserPrincipalName', 'DisplayName', 'Name')]
        [string]$SearchBy = 'SamAccountName'
    )
    begin{
        Write-Verbose "Starting LDAP user object retrieval"
        
        # Check for DirectoryServices availability first
        Write-Verbose "Checking DirectoryServices assemblies availability"
        try {
            # Try to load DirectoryServices assemblies
            Add-Type -AssemblyName System.DirectoryServices -ErrorAction Stop
            Write-Verbose "DirectoryServices assemblies loaded successfully"
        }
        catch {
            Write-Error "System.DirectoryServices is not available on this system. This function requires Windows with DirectoryServices components installed. Ensure you are running on a Windows system with Active Directory tools available." -ErrorAction Stop
            return
        }
        
        # Early Active Directory connectivity check
        Write-Verbose "Performing Active Directory connectivity check"
        try {
            # Test if machine is domain-joined and can reach a domain controller
            if ($Domain) {
                # Test specified domain
                $testDomainDN = $Domain
                Write-Verbose "Testing connectivity to specified domain: $Domain"
            } else {
                # Test current domain
                try {
                    $currentDomain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                    $testDomainDN = $currentDomain.Name
                    Write-Verbose "Testing connectivity to current domain: $testDomainDN"
                } catch {
                    Write-Error "This computer is not joined to an Active Directory domain or cannot contact a domain controller. Ensure you are connected to the corporate network and try again." -ErrorAction Stop
                    return
                }
            }
            
            # Build test LDAP path
            $testLdapPath = "LDAP://" + ($testDomainDN -replace '\.', ',DC=' -replace '^', 'DC=')
            
            # Perform lightweight connectivity test
            $testDirectoryEntry = $null
            $testSearcher = $null
            try {
                if ($Credential) {
                    $testDirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($testLdapPath, $Credential.UserName, $Credential.GetNetworkCredential().Password)
                } else {
                    $testDirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($testLdapPath)
                }
                
                # Create a test searcher with minimal timeout
                $testSearcher = New-Object System.DirectoryServices.DirectorySearcher($testDirectoryEntry)
                $testSearcher.ClientTimeout = New-TimeSpan -Seconds 10
                $testSearcher.ServerTimeLimit = New-TimeSpan -Seconds 8
                $testSearcher.Filter = "(objectClass=domain)"
                $testSearcher.PropertiesToLoad.Add("distinguishedName") | Out-Null
                $testSearcher.SizeLimit = 1
                
                # Attempt the test query
                $testResult = $testSearcher.FindOne()
                if ($null -eq $testResult) {
                    Write-Error "Unable to query Active Directory. The domain controller may be unreachable." -ErrorAction Stop
                    return
                }
                
                Write-Verbose "Active Directory connectivity confirmed successfully"
            } finally {
                # Clean up test objects
                if ($testSearcher) { $testSearcher.Dispose() }
                if ($testDirectoryEntry) { $testDirectoryEntry.Dispose() }
            }
        }
        catch [System.DirectoryServices.ActiveDirectory.ActiveDirectoryObjectNotFoundException] {
            Write-Error "Active Directory domain not found. This computer may not be joined to a domain or the domain is unreachable." -ErrorAction Stop
            return
        }
        catch [System.Runtime.InteropServices.COMException] {
            # Handle COM exceptions (more generic than DirectoryServiceCOMException)
            $errorCode = $_.Exception.HResult
            if ($errorCode -eq -2147016672) {
                Write-Error "Access denied to Active Directory. You may not have sufficient permissions or the domain controller is unreachable. Try running as an administrator or use the -Credential parameter." -ErrorAction Stop
            } else {
                Write-Error "Active Directory connectivity test failed: $($_.Exception.Message). Ensure you are connected to the corporate network and can reach a domain controller." -ErrorAction Stop
            }
            return
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error "Access denied to Active Directory. You may not have sufficient permissions. Try running as an administrator or use the -Credential parameter." -ErrorAction Stop
            return
        }
        catch [System.Net.NetworkInformation.NetworkInformationException] {
            Write-Error "Network connectivity issue. Unable to reach the domain controller. Check your network connection and try again." -ErrorAction Stop
            return
        }
        catch {
            Write-Error "Active Directory connectivity test failed: $($_.Exception.Message). This may indicate the computer is not connected to the corporate network or Active Directory is unavailable." -ErrorAction Stop
            return
        }
        
        # Define default properties (same as Get-ADUser)
        $defaultProperties = @('DistinguishedName', 'Enabled', 'GivenName', 'Name', 'ObjectClass', 'ObjectGUID', 'SamAccountName', 'SID', 'Surname', 'UserPrincipalName')
        
        # Single comprehensive mapping from PowerShell property names to LDAP attributes
        $propertyMappings = @{
            'AccountExpirationDate' = @{ LdapName = 'accountexpires'; SpecialHandling = 'AccountExpirationDate' }
            'AccountLockoutTime' = @{ LdapName = 'accountlockouttime'; SpecialHandling = $null }
            'AccountNotDelegated' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'AccountNotDelegated' }
            'AllowReversiblePasswordEncryption' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'AllowReversiblePasswordEncryption' }
            'BadLogonCount' = @{ LdapName = 'badpwdcount'; SpecialHandling = $null }
            'CannotChangePassword' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'CannotChangePassword' }
            'CanonicalName' = @{ LdapName = 'canonicalname'; SpecialHandling = $null }
            'City' = @{ LdapName = 'l'; SpecialHandling = $null }
            'CN' = @{ LdapName = 'cn'; SpecialHandling = $null }
            'Company' = @{ LdapName = 'company'; SpecialHandling = $null }
            'Country' = @{ LdapName = 'c'; SpecialHandling = $null }
            'Created' = @{ LdapName = 'whencreated'; SpecialHandling = $null }
            'Department' = @{ LdapName = 'department'; SpecialHandling = $null }
            'Description' = @{ LdapName = 'description'; SpecialHandling = $null }
            'DisplayName' = @{ LdapName = 'displayname'; SpecialHandling = $null }
            'DistinguishedName' = @{ LdapName = 'distinguishedname'; SpecialHandling = $null }
            'Division' = @{ LdapName = 'division'; SpecialHandling = $null }
            'DoesNotRequirePreAuth' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'DoesNotRequirePreAuth' }
            'EmailAddress' = @{ LdapName = 'mail'; SpecialHandling = $null }
            'EmployeeID' = @{ LdapName = 'employeeid'; SpecialHandling = $null }
            'EmployeeNumber' = @{ LdapName = 'employeenumber'; SpecialHandling = $null }
            'Enabled' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'Enabled' }
            'Fax' = @{ LdapName = 'facsimiletelephonenumber'; SpecialHandling = $null }
            'GivenName' = @{ LdapName = 'givenname'; SpecialHandling = $null }
            'HomeDirectory' = @{ LdapName = 'homedirectory'; SpecialHandling = $null }
            'HomeDrive' = @{ LdapName = 'homedrive'; SpecialHandling = $null }
            'HomePhone' = @{ LdapName = 'homephone'; SpecialHandling = $null }
            'Initials' = @{ LdapName = 'initials'; SpecialHandling = $null }
            'LastBadPasswordAttempt' = @{ LdapName = 'badpasswordtime'; SpecialHandling = 'LastBadPasswordAttempt' }
            'LastLogonDate' = @{ LdapName = 'lastlogontimestamp'; SpecialHandling = 'LastLogonDate' }
            'LockoutTime' = @{ LdapName = 'lockouttime'; SpecialHandling = 'LockoutTime' }
            'LogonWorkstations' = @{ LdapName = 'userworkstations'; SpecialHandling = $null }
            'Manager' = @{ LdapName = 'manager'; SpecialHandling = $null }
            'MemberOf' = @{ LdapName = 'memberof'; SpecialHandling = $null }
            'MobilePhone' = @{ LdapName = 'mobile'; SpecialHandling = $null }
            'Modified' = @{ LdapName = 'whenchanged'; SpecialHandling = $null }
            'Name' = @{ LdapName = 'name'; SpecialHandling = $null }
            'ObjectCategory' = @{ LdapName = 'objectcategory'; SpecialHandling = $null }
            'ObjectClass' = @{ LdapName = 'objectclass'; SpecialHandling = 'ObjectClass' }
            'ObjectGUID' = @{ LdapName = 'objectguid'; SpecialHandling = 'ObjectGUID' }
            'Office' = @{ LdapName = 'physicaldeliveryofficename'; SpecialHandling = $null }
            'OfficePhone' = @{ LdapName = 'telephonenumber'; SpecialHandling = $null }
            'Organization' = @{ LdapName = 'o'; SpecialHandling = $null }
            'OtherName' = @{ LdapName = 'middlename'; SpecialHandling = $null }
            'PasswordLastSet' = @{ LdapName = 'pwdlastset'; SpecialHandling = 'PasswordLastSet' }
            'PasswordNeverExpires' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'PasswordNeverExpires' }
            'PasswordNotRequired' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'PasswordNotRequired' }
            'POBox' = @{ LdapName = 'postofficebox'; SpecialHandling = $null }
            'PostalCode' = @{ LdapName = 'postalcode'; SpecialHandling = $null }
            'PrimaryGroupID' = @{ LdapName = 'primarygroupid'; SpecialHandling = $null }
            'ProfilePath' = @{ LdapName = 'profilepath'; SpecialHandling = $null }
            'SamAccountName' = @{ LdapName = 'samaccountname'; SpecialHandling = $null }
            'ScriptPath' = @{ LdapName = 'scriptpath'; SpecialHandling = $null }
            'SID' = @{ LdapName = 'objectsid'; SpecialHandling = 'SID' }
            'SmartcardLogonRequired' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'SmartcardLogonRequired' }
            'State' = @{ LdapName = 'st'; SpecialHandling = $null }
            'StreetAddress' = @{ LdapName = 'streetaddress'; SpecialHandling = $null }
            'Surname' = @{ LdapName = 'sn'; SpecialHandling = $null }
            'Title' = @{ LdapName = 'title'; SpecialHandling = $null }
            'TrustedForDelegation' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'TrustedForDelegation' }
            'TrustedToAuthForDelegation' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'TrustedToAuthForDelegation' }
            'UseDesKeyOnly' = @{ LdapName = 'useraccountcontrol'; SpecialHandling = 'UseDesKeyOnly' }
            'UserCertificate' = @{ LdapName = 'usercertificate'; SpecialHandling = 'UserCertificate' }
            'UserPrincipalName' = @{ LdapName = 'userprincipalname'; SpecialHandling = $null }
            # Additional LDAP-to-PowerShell mappings for properties that don't follow standard naming
            'adspath' = @{ LdapName = 'adspath'; SpecialHandling = $null }
            'admincount' = @{ LdapName = 'admincount'; SpecialHandling = $null }
            'badPasswordTime' = @{ LdapName = 'badpasswordtime'; SpecialHandling = $null }
            'codePage' = @{ LdapName = 'codepage'; SpecialHandling = $null }
            'countryCode' = @{ LdapName = 'countrycode'; SpecialHandling = $null }
            'dSCorePropagationData' = @{ LdapName = 'dscorepropagationdata'; SpecialHandling = $null }
            'instanceType' = @{ LdapName = 'instancetype'; SpecialHandling = $null }
            'isCriticalSystemObject' = @{ LdapName = 'iscriticalsystemobject'; SpecialHandling = $null }
            'lastLogoff' = @{ LdapName = 'lastlogoff'; SpecialHandling = $null }
            'lastLogon' = @{ LdapName = 'lastlogon'; SpecialHandling = $null }
            'logonCount' = @{ LdapName = 'logoncount'; SpecialHandling = $null }
            'sAMAccountType' = @{ LdapName = 'samaccounttype'; SpecialHandling = $null }
            'uSNChanged' = @{ LdapName = 'usnchanged'; SpecialHandling = $null }
            'uSNCreated' = @{ LdapName = 'usncreated'; SpecialHandling = $null }
        }
        
        # Create reverse mapping for LDAP-to-PowerShell lookups
        $ldapToPropertyMap = @{}
        foreach ($psProperty in $propertyMappings.Keys) {
            $ldapProperty = $propertyMappings[$psProperty].LdapName
            if (-not $ldapToPropertyMap.ContainsKey($ldapProperty)) {
                $ldapToPropertyMap[$ldapProperty] = $psProperty
            }
        }
        
        # Combine default properties with additional properties requested
        if ($Properties) {
            # Add requested properties to defaults (like Get-ADUser behavior)
            $allProperties = $defaultProperties + $Properties | Select-Object -Unique
        } else {
            # Use only default properties if none specified
            $allProperties = $defaultProperties
        }
        
        Write-Verbose "Properties to retrieve: $($allProperties -join ', ')"
        Write-Verbose "Searching by: $SearchBy"
        
        # Initialize variables for proper disposal
        $searcher = $null
        $directoryEntry = $null
        
        # Initialize batch processing variables
        $userQueue = [System.Collections.Generic.List[string]]::new()
        $processedCount = 0
        $totalUsers = 0
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
                # Map property names to LDAP attributes for loading using centralized mapping
                $ldapProperties = foreach ($prop in $allProperties) {
                    if ($propertyMappings.ContainsKey($prop)) {
                        $propertyMappings[$prop].LdapName
                    } else {
                        $prop.ToLower()
                    }
                }
                
                # Performance optimization: Load only the properties we need
                $searcher.PropertiesToLoad.AddRange($ldapProperties) | Out-Null
                Write-Verbose "Loading specific properties: $($allProperties -join ', ')"
            } else {
                Write-Verbose "Loading all available properties"
            }
            
            # Use ArrayList with initial capacity for better memory management
            # Estimate based on batch size for optimal memory allocation
            $estimatedCapacity = if ($BatchSize -gt 100) { $BatchSize } else { 100 }
            $output = New-Object System.Collections.ArrayList($estimatedCapacity)
        }
        catch [System.Runtime.InteropServices.COMException] {
            # Handle COM exceptions (more generic than DirectoryServiceCOMException)
            # Ensure cleanup on initialization failure
            if ($searcher) { $searcher.Dispose(); $searcher = $null }
            if ($directoryEntry) { $directoryEntry.Dispose(); $directoryEntry = $null }
            
            $errorCode = $_.Exception.HResult
            if ($errorCode -eq -2147016672) {
                Write-Error "Access denied. You may not have sufficient permissions to query Active Directory. Try running as an administrator or use the -Credential parameter." -ErrorAction Stop
            } else {
                Write-Error "Directory Services error: $($_.Exception.Message)" -ErrorAction Stop
            }
            return
        }
        catch [System.UnauthorizedAccessException] {
            # Ensure cleanup on initialization failure
            if ($searcher) { $searcher.Dispose(); $searcher = $null }
            if ($directoryEntry) { $directoryEntry.Dispose(); $directoryEntry = $null }
            
            Write-Error "Access denied. You may not have sufficient permissions to query Active Directory. Try running as an administrator or use the -Credential parameter." -ErrorAction Stop
            return
        }
        catch {
            # Ensure cleanup on initialization failure
            if ($searcher) { $searcher.Dispose(); $searcher = $null }
            if ($directoryEntry) { $directoryEntry.Dispose(); $directoryEntry = $null }
            
            Write-Error "Failed to initialize LDAP connection: $($_.Exception.Message)" -ErrorAction Stop
            return
        }
    }

    process{
        # Add users to the queue for batch processing
        foreach($userName in $UserName) {
            $userQueue.Add($userName)
            $totalUsers++
        }
    }

    end {
        try {
            # Process users in batches
            Write-Verbose "Processing $totalUsers users in batches of $BatchSize"
            
            for ($i = 0; $i -lt $userQueue.Count; $i += $BatchSize) {
                $batchNumber++
                $batchEnd = [Math]::Min($i + $BatchSize - 1, $userQueue.Count - 1)
                $currentBatch = $userQueue.GetRange($i, ($batchEnd - $i + 1))
                
                if (-not $NoProgress) {
                    $progressParams = @{
                        Activity = "Processing AD User Objects"
                        Status = "Batch $batchNumber - Processing users $($i + 1) to $($batchEnd + 1) of $totalUsers"
                        PercentComplete = [Math]::Round(($i / $userQueue.Count) * 100, 1)
                        CurrentOperation = "Current batch size: $($currentBatch.Count) users"
                    }
                    Write-Progress @progressParams
                }
                
                Write-Verbose "Processing batch $batchNumber with $($currentBatch.Count) users"
                
                # Process current batch
                $batchProcessedCount = 0
                foreach($userName in $currentBatch) {
                    $batchProcessedCount++
                    $processedCount++
                    $result = $null

                    # Update progress for individual items in large batches
                    if (-not $NoProgress -and $currentBatch.Count -gt 50) {
                        $batchProgress = [Math]::Round(($batchProcessedCount / $currentBatch.Count) * 100, 1)
                        Write-Progress -Id 1 -ParentId 0 -Activity "Processing Batch $batchNumber" -Status "User: $userName" -PercentComplete $batchProgress
                    }

                    Write-Verbose "Processing user: $userName (Overall: $processedCount/$totalUsers)"

                    # Sanitize user name for LDAP filter (additional safety for PS 5.1)
                    $sanitizedName = $userName -replace '[\\\/\(\)\*\&\|\!\=\<\>\~]', ''
                    if ($sanitizedName -ne $userName) {
                        Write-Warning "User name '$userName' contained special characters and was sanitized to '$sanitizedName'"
                    }

                    # Build LDAP filter based on search attribute
                    $searchAttribute = switch ($SearchBy) {
                        'SamAccountName' { 'samaccountname' }
                        'UserPrincipalName' { 'userprincipalname' }
                        'DisplayName' { 'displayname' }
                        'Name' { 'name' }
                        default { 'samaccountname' }
                    }
                    
                    # Set the filter for user objects
                    $searcher.Filter = "(&(objectClass=user)(objectCategory=person)($searchAttribute=$sanitizedName))"

                    try {
                        $result = $searcher.FindOne()

                        if ($null -eq $result) {
                            Write-Warning "User '$userName' not found in Active Directory"
                            continue
                        }

                        Write-Verbose "Found user '$userName' in Active Directory"
                        
                        # Create user object with Get-ADUser-like structure and property order
                        # Use ordered hashtable with estimated capacity for memory efficiency
                        $userObject = [ordered]@{}
                        
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
                                    
                                    # Use centralized mapping for special handling if not explicitly provided
                                    if (-not $SpecialHandling -and $propertyMappings.ContainsKey($Name)) {
                                        $SpecialHandling = $propertyMappings[$Name].SpecialHandling
                                    }
                                    
                                    switch ($SpecialHandling) {
                                        'Enabled' {
                                            $uacValue = $propertyValues[0]
                                            $enabled = -not ($uacValue -band 2)
                                            $userObject[$Name] = $enabled
                                        }
                                        'PasswordNeverExpires' {
                                            $uacValue = $propertyValues[0]
                                            $passwordNeverExpires = ($uacValue -band 65536) -ne 0
                                            $userObject[$Name] = $passwordNeverExpires
                                        }
                                        'CannotChangePassword' {
                                            $uacValue = $propertyValues[0]
                                            $cannotChangePassword = ($uacValue -band 64) -ne 0
                                            $userObject[$Name] = $cannotChangePassword
                                        }
                                        'PasswordNotRequired' {
                                            $uacValue = $propertyValues[0]
                                            $passwordNotRequired = ($uacValue -band 32) -ne 0
                                            $userObject[$Name] = $passwordNotRequired
                                        }
                                        'AllowReversiblePasswordEncryption' {
                                            $uacValue = $propertyValues[0]
                                            $allowReversiblePasswordEncryption = ($uacValue -band 128) -ne 0
                                            $userObject[$Name] = $allowReversiblePasswordEncryption
                                        }
                                        'AccountNotDelegated' {
                                            $uacValue = $propertyValues[0]
                                            $accountNotDelegated = ($uacValue -band 1048576) -ne 0
                                            $userObject[$Name] = $accountNotDelegated
                                        }
                                        'UseDesKeyOnly' {
                                            $uacValue = $propertyValues[0]
                                            $useDesKeyOnly = ($uacValue -band 2097152) -ne 0
                                            $userObject[$Name] = $useDesKeyOnly
                                        }
                                        'ObjectGUID' {
                                            if ($propertyValues[0] -is [byte[]]) {
                                                $guid = New-Object System.Guid(,$propertyValues[0])
                                                $userObject[$Name] = $guid.ToString()
                                            } else {
                                                $userObject[$Name] = $propertyValues[0]
                                            }
                                        }
                                        'SID' {
                                            if ($propertyValues[0] -is [byte[]]) {
                                                $sid = New-Object System.Security.Principal.SecurityIdentifier($propertyValues[0], 0)
                                                $userObject[$Name] = $sid
                                            } else {
                                                $userObject[$Name] = $propertyValues[0]
                                            }
                                        }
                                        'ObjectClass' {
                                            $userObject[$Name] = 'user'
                                        }
                                        'AccountExpirationDate' {
                                            $accountExpires = $propertyValues[0]
                                            if ($accountExpires -eq 0 -or $accountExpires -eq 9223372036854775807) {
                                                $userObject[$Name] = $null
                                            } else {
                                                $userObject[$Name] = [DateTime]::FromFileTime($accountExpires)
                                            }
                                        }
                                        'LastLogonDate' {
                                            $lastLogon = $propertyValues[0]
                                            if ($lastLogon -eq 0) {
                                                $userObject[$Name] = $null
                                            } else {
                                                $userObject[$Name] = [DateTime]::FromFileTime($lastLogon)
                                            }
                                        }
                                        'PasswordLastSet' {
                                            $pwdLastSet = $propertyValues[0]
                                            if ($pwdLastSet -eq 0) {
                                                $userObject[$Name] = $null
                                            } else {
                                                $userObject[$Name] = [DateTime]::FromFileTime($pwdLastSet)
                                            }
                                        }
                                        'LockoutTime' {
                                            $lockoutTime = $propertyValues[0]
                                            if ($lockoutTime -eq 0) {
                                                $userObject[$Name] = $null
                                            } else {
                                                $userObject[$Name] = [DateTime]::FromFileTime($lockoutTime)
                                            }
                                        }
                                        'TrustedForDelegation' {
                                            $uacValue = $propertyValues[0]
                                            $trustedForDelegation = ($uacValue -band 524288) -ne 0
                                            $userObject[$Name] = $trustedForDelegation
                                        }
                                        'TrustedToAuthForDelegation' {
                                            $uacValue = $propertyValues[0]
                                            $trustedToAuthForDelegation = ($uacValue -band 16777216) -ne 0
                                            $userObject[$Name] = $trustedToAuthForDelegation
                                        }
                                        'DoesNotRequirePreAuth' {
                                            $uacValue = $propertyValues[0]
                                            $doesNotRequirePreAuth = ($uacValue -band 4194304) -ne 0
                                            $userObject[$Name] = $doesNotRequirePreAuth
                                        }
                                        'SmartcardLogonRequired' {
                                            $uacValue = $propertyValues[0]
                                            $smartcardLogonRequired = ($uacValue -band 262144) -ne 0
                                            $userObject[$Name] = $smartcardLogonRequired
                                        }
                                        'LastBadPasswordAttempt' {
                                            $badPasswordTime = $propertyValues[0]
                                            if ($badPasswordTime -eq 0) {
                                                $userObject[$Name] = $null
                                            } else {
                                                $userObject[$Name] = [DateTime]::FromFileTime($badPasswordTime)
                                            }
                                        }
                                        'UserCertificate' {
                                            if ($propertyValues.Count -gt 0) {
                                                $certStrings = foreach ($cert in $propertyValues) {
                                                    if ($cert -is [byte[]]) {
                                                        try {
                                                            $x509 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
                                                            "Subject: $($x509.Subject), Thumbprint: $($x509.Thumbprint), NotAfter: $($x509.NotAfter)"
                                                        } catch {
                                                            "Certificate (Length: $($cert.Length) bytes)"
                                                        }
                                                    } else {
                                                        $cert.ToString()
                                                    }
                                                }
                                                $userObject[$Name] = $certStrings -join '; '
                                            } else {
                                                $userObject[$Name] = $null
                                            }
                                        }
                                        default {
                                            if ($propertyValues.Count -eq 1) {
                                                $userObject[$Name] = $propertyValues[0]
                                            } else {
                                                $userObject[$Name] = ($propertyValues -join ', ')
                                                if ($propertyValues.Count -gt 1) {
                                                    Write-Verbose "Property '$Name' for user '$userName' has multiple values: $($propertyValues -join ', ')"
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    # Property not found, add as null if it was specifically requested
                                    if ($allProperties -contains $Name) {
                                        $userObject[$Name] = $null
                                    }
                                }
                            }
                        }
                        
                        # Add properties in Get-ADUser order using centralized mapping
                        & $addProperty 'DistinguishedName' 'distinguishedname'
                        & $addProperty 'Enabled' 'useraccountcontrol'
                        & $addProperty 'GivenName' 'givenname'
                        & $addProperty 'Name' 'name'
                        & $addProperty 'ObjectClass' 'objectclass'
                        & $addProperty 'ObjectGUID' 'objectguid'
                        & $addProperty 'SamAccountName' 'samaccountname'
                        & $addProperty 'SID' 'objectsid'
                        & $addProperty 'Surname' 'sn'
                        & $addProperty 'UserPrincipalName' 'userprincipalname'
                        
                        # Add any additional requested properties
                        if ($Properties) {
                            $additionalProps = $Properties | Where-Object { 
                                $_ -notin @('DistinguishedName', 'Enabled', 'GivenName', 'Name', 'ObjectClass', 'ObjectGUID', 'SamAccountName', 'SID', 'Surname', 'UserPrincipalName', '*') 
                            } | Sort-Object
                            foreach ($prop in $additionalProps) {
                                # Use centralized mapping
                                if ($propertyMappings.ContainsKey($prop)) {
                                    $ldapName = $propertyMappings[$prop].LdapName
                                    & $addProperty $prop $ldapName
                                } else {
                                    # Fallback for unmapped properties
                                    & $addProperty $prop $prop.ToLower()
                                }
                            }
                            
                            # Sort ALL properties alphabetically (like Get-ADUser) when additional properties are requested
                            $sortedUserObject = [ordered]@{}
                            $allPropsToSort = $userObject.Keys | Sort-Object
                            
                            foreach ($prop in $allPropsToSort) {
                                $sortedUserObject[$prop] = $userObject[$prop]
                            }
                            
                            # Replace the original user object with the sorted one
                            $userObject = $sortedUserObject
                        }
                        
                        # If loading all properties, add remaining ones alphabetically
                        if ($loadAllProperties) {
                            # Sort ALL properties alphabetically when loading all properties (like Get-ADUser)
                            $sortedUserObject = [ordered]@{}
                            $allPropsToSort = $userObject.Keys | Sort-Object
                            
                            foreach ($prop in $allPropsToSort) {
                                $sortedUserObject[$prop] = $userObject[$prop]
                            }
                            
                            # Replace the original user object with the sorted one
                            $userObject = $sortedUserObject
                            
                            $remainingProps = $propertyHash.Keys | Where-Object { 
                                # Use centralized reverse mapping
                                $propName = if ($ldapToPropertyMap.ContainsKey($_.ToLower())) {
                                    $ldapToPropertyMap[$_.ToLower()]
                                } else {
                                    $_
                                }
                                -not $userObject.Contains($propName)
                            } | Sort-Object
                            
                            foreach ($ldapProp in $remainingProps) {
                                # Use centralized reverse mapping
                                $propName = if ($ldapToPropertyMap.ContainsKey($ldapProp.ToLower())) {
                                    $ldapToPropertyMap[$ldapProp.ToLower()]
                                } else {
                                    $ldapProp
                                }
                                
                                # Use the centralized addProperty function which will handle special formatting automatically
                                & $addProperty $propName $ldapProp
                            }
                            
                            # Sort ALL properties alphabetically again after adding remaining properties
                            $finalSortedUserObject = [ordered]@{}
                            $finalPropsToSort = $userObject.Keys | Sort-Object
                            
                            foreach ($prop in $finalPropsToSort) {
                                $finalSortedUserObject[$prop] = $userObject[$prop]
                            }
                            
                            $userObject = $finalSortedUserObject
                        }
                        
                        # Convert ordered hashtable to PSCustomObject
                        $userObjectFinal = [PSCustomObject]$userObject
                        
                        [void]$output.Add($userObjectFinal)
                        Write-Verbose "Successfully processed user: $userName"
                        
                        # Explicit cleanup for large result sets (PowerShell 5.1 optimization)
                        $result = $null
                        $propertyHash.Clear()
                        $propertyHash = $null
                        $userObject = $null
                    }
                    catch [System.Runtime.InteropServices.COMException] {
                        # Handle COM exceptions (more generic than DirectoryServiceCOMException)
                        $errorCode = $_.Exception.HResult
                        if ($errorCode -eq -2147016672) {
                            Write-Error "Access denied while querying user '$userName'. You may not have sufficient permissions to query Active Directory."
                        } else {
                            Write-Error "Directory Services error while processing user '$userName': $($_.Exception.Message)"
                        }
                        continue
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Error "Access denied while querying user '$userName'. You may not have sufficient permissions to query Active Directory."
                        continue
                    }
                    catch {
                        Write-Error "Error processing user '$userName': $($_.Exception.Message)"
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
                Write-Progress -Activity "Processing AD User Objects" -Completed
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
        
        Write-Verbose "LDAP user object retrieval completed. Found $($output.Count) objects out of $totalUsers requested."
        
        # Return array and help GC by clearing the ArrayList reference
        if ($output) {
            $result = $output.ToArray()
            $output.Clear()
            $output = $null
        } else {
            $result = @()
        }
        
        if ($userQueue) {
            $userQueue.Clear()
            $userQueue = $null
        }
        
        return $result
    }
}
