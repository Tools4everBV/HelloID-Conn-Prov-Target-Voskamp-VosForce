####################################################################
# HelloID-Conn-Prov-Target-Voskamp-VosForce-ImportPermissions-Roles
# PowerShell V2
####################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-VoskampError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($errorDetailsObject -and $errorDetailsObject.errors -and $errorDetailsObject.errors.message) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.errors.message -join '; '
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            Write-Warning $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting Voskamp permission entitlement import'
    # Import Certificate
    $rawP12Certificate = [system.convert]::FromBase64String($actionContext.Configuration.P12CertificateBase64)
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawP12Certificate, $actionContext.Configuration.CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    # Retrieve users
    $pageSizeUsers = 100
    $pageNumberUsers = 1
    $retrievedUsers = [System.Collections.Generic.List[object]]::new()
    do {
        $splatGetUserParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/items/users?limit=$pageSizeUsers&page=$pageNumberUsers&meta=total_count&sort=id"
            Method      = 'GET'
            Headers     = @{
                Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
            }
            certificate = $certificate
        }
        $response = Invoke-RestMethod @splatGetUserParams
        if ($response.Data) {
            $retrievedUsers.AddRange($response.Data)
        }
        $pageNumberUsers++
    } while ($pageNumberUsers -le [math]::Ceiling($response.Meta.total_count / $pageSizeUsers))
    $usersGrouped = $retrievedUsers | Group-Object -Property id -AsHashTable -AsString
    Write-Information "Retrieved $($retrievedUsers.count) users"

    # Retrieve roles
    $pageSizeRoles = 100
    $pageNumberRoles = 1
    $retrievedRoles = [System.Collections.Generic.List[object]]::new()
    do {
        $splatGetRoleParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/items/roles?limit=$pageSizeRoles&page=$pageNumberRoles&meta=total_count&sort=id"
            Method      = 'GET'
            Headers     = @{
                Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
            }
            certificate = $certificate
        }
        $response = (Invoke-RestMethod @splatGetRoleParams)

        if ($response.Data) {
            $retrievedRoles.AddRange($response.Data)
        }
        $pageNumberRoles++
    } while ($pageNumberRoles -le [math]::Ceiling($response.Meta.total_count / $pageSizeRoles))
    $rolesGrouped = $retrievedRoles | Group-Object -Property id -AsHashTable -AsString
    Write-Information "Retrieved $($retrievedRoles.count) roles"

    # Retrieve authorizations
    $pageSizeAuthorizations = 100
    $pageNumberAuth = 1
    do {
        $splatImportPermissionParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/items/authorizations?limit=$pageSizeAuthorizations&page=$pageNumberAuth&meta=total_count&sort=id"
            Method      = 'GET'
            Headers     = @{
                Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
            }
            certificate = $certificate
        }
        $importedPermissions = (Invoke-RestMethod @splatImportPermissionParams)

        $importedPermissionsGrouped = $importedPermissions.Data | Group-Object -Property group_id
        foreach ($importedPermission in $importedPermissionsGrouped) {
            $roleDetails = $rolesGrouped["$($importedPermission.Name)"]
            if ($null -eq $roleDetails) {
                Write-Warning "No role found for imported authorization [$($importedPermission.Name)]."
                continue
            }

            $membersId = [System.Collections.Generic.List[object]]::new()
            foreach ($user in $importedPermission.Group.user_id) {
                if ( $null -eq $usersGrouped -or $null -eq $usersGrouped["$user"].id) {
                    Write-Warning "No user account found for user ID [$($user)]."
                }
                else {
                    $membersId.Add($usersGrouped["$user"].id)
                }
            }

            if ($membersId.count -gt 0) {
                $permission = @{
                    PermissionReference = @{
                        Reference = [int]($importedPermission.Name)
                    }
                    Description         = "$($roleDetails.group_name)"
                    DisplayName         = "$($roleDetails.group_name)"
                    AccountReferences   = @($membersId)
                }
                Write-Output $permission
            }
        }
        $pageNumberAuth++
    } while ($pageNumberAuth -le [math]::Ceiling($importedPermissions.Meta.total_count / $pageSizeAuthorizations))
    Write-Information "Retrieved $($importedPermissions.Meta.total_count) Authorizations"
    Write-Information 'Voskamp permission entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-VoskampError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Voskamp permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Voskamp permission entitlements. Error: $($ex.Exception.Message)"
    }
}