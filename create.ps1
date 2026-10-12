#################################################
# HelloID-Conn-Prov-Target-Voskamp-VosForce-Create
# PowerShell V2
#################################################

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
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Import Certificate
    $rawP12Certificate = [system.convert]::FromBase64String($actionContext.Configuration.P12CertificateBase64)
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawP12Certificate,  $actionContext.Configuration.CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a Voskamp account exists where $correlationField is: [$correlationValue]"
        $splatGetUserParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/items/users?filter[$($correlationField)][_eq]=$($correlationValue)"
            Method      = 'GET'
            Headers     = @{
                Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
            }
            certificate = $certificate
        }
        $correlatedAccount = (Invoke-RestMethod @splatGetUserParams).data
    }

    if ($correlatedAccount.Count -eq 0) {
        $lifecycleProcess = 'CreateAccount'
    }
    elseif ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount | Select-Object -First 1
        $lifecycleProcess = 'CorrelateAccount'
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/items/users"
                Method      = 'POST'
                Body        = $actionContext.Data | ConvertTo-Json
                Headers     = @{
                    Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
                }
                ContentType = 'application/json'
                certificate = $certificate
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Voskamp account'
                $createdAccount = Invoke-RestMethod @splatCreateParams

                $outputContext.Data = $createdAccount.data | Select-Object -Property @($outputContext.Data.PSObject.Properties.Name)
                $outputContext.AccountReference = $createdAccount.data.Id
            }
            else {
                Write-Information '[DryRun] Create and correlate Voskamp account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Voskamp account'
            $outputContext.Data = $correlatedAccount | Select-Object -Property @($outputContext.Data.PSObject.Properties.Name)
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.Success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-VoskampError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate Voskamp. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate Voskamp. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}