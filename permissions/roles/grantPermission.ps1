################################################################
# HelloID-Conn-Prov-Target-Voskamp-GrantPermission-Roles
# PowerShell V2
################################################################

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

# Begin
try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Import Certificate
    $rawP12Certificate = [system.convert]::FromBase64String($actionContext.Configuration.P12CertificateBase64)
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawP12Certificate, $actionContext.Configuration.CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    Write-Information 'Verifying if a Voskamp account exists'
    $splatGetUserParams = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/items/users/$($actionContext.References.Account)"
        Method      = 'GET'
        Headers     = @{
            Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
        }
        certificate = $certificate
    }

    try {
        $correlatedAccount = (Invoke-RestMethod @splatGetUserParams).data
    }
    catch {
        $ex = $_
        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
            $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $errorObj = Resolve-VoskampError -ErrorObject $ex
            if (-not ($errorObj.FriendlyMessage -contains "You don't have permission to access this.")) {
                throw $_
            }
        }
        else {
            throw $_
        }
    }


    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'GrantPermission'
        $splatGetUserPermissionsParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/items/authorizations?filter[user_id][_eq]=$($actionContext.References.Account)"
            Method      = 'GET'
            Headers     = @{
                Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
            }
            certificate = $certificate
        }
        $correlatedAccountPermissions = (Invoke-RestMethod @splatGetUserPermissionsParams).data
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'GrantPermission' {
            if ($correlatedAccountPermissions.group_id -contains $actionContext.References.Permission.Reference) {
                Write-Information "Voskamp account already has the permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)]"
            }
            else {
                $splatGrantPermission = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/items/authorizations"
                    Method      = 'POST'
                    Headers     = @{
                        Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
                    }
                    body        = @{
                        user_id  = $actionContext.References.Account
                        group_id = $actionContext.References.Permission.Reference
                    } | ConvertTo-Json
                    ContentType = 'application/json'
                    certificate = $certificate
                }
                if (-not($actionContext.DryRun -eq $true)) {
                    Write-Information "Granting Voskamp permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)]"
                    $null = (Invoke-RestMethod @splatGrantPermission).data

                }
                else {
                    Write-Information "[DryRun] Grant Voskamp permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)], will be executed during enforcement"
                }
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Grant permission [$($actionContext.PermissionDisplayName)] was successful"
                    IsError = $false
                })
            $outputContext.Success = $true
            break
        }

        'NotFound' {
            Write-Information "Voskamp account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Voskamp account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-VoskampError -ErrorObject $ex
        $auditLogMessage = "Could not grant Voskamp permission for account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not grant Voskamp permission for account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}