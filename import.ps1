#################################################
# HelloID-Conn-Prov-Target-Voskamp-Import
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

    # Import Certificate
    $rawP12Certificate = [system.convert]::FromBase64String($actionContext.Configuration.P12CertificateBase64)
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($rawP12Certificate,  $actionContext.Configuration.CertificatePassword, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)

    Write-Information 'Starting Voskamp account entitlement import'
    $pageSize = 100
    $pageNumber = 1
    do {
        $splatGetUserParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/items/users?limit=$pageSize&page=$pageNumber&meta=total_count&sort=id"
            Method      = 'GET'
            Headers     = @{
                Authorization = "Bearer $($actionContext.Configuration.ApiKey)"
            }
            certificate = $certificate
        }
        $response = Invoke-RestMethod @splatGetUserParams
        foreach ($importedAccount in $response.data) {
            $data = $importedAccount | Select-Object -Property $actionContext.ImportFields

            # Make sure the displayName has a value
            $displayName = "$($importedAccount.first_name) $($importedAccount.last_name)".trim()
            if ([string]::IsNullOrEmpty($displayName)) {
                $displayName = $importedAccount.Id
            }

            # Make sure the userName has a value
            $username = "$($importedAccount.email)"
            if ([string]::IsNullOrWhiteSpace($importedAccount.email)) {
                $username = "$($importedAccount.Id)"
            }

            Write-Output @{
                AccountReference = $importedAccount.Id
                DisplayName      = $displayName
                UserName         = $username.Substring(0, [math]::Min($username.Length, 100))
                Enabled          = $importedAccount.active
                Data             = $data
            }
        }
        $pageNumber++
    } while ($pageNumber -le [math]::Ceiling($response.meta.total_count / $pageSize))

    Write-Information 'Voskamp account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-VoskampError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Voskamp account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Voskamp account entitlements. Error: $($ex.Exception.Message)"
    }
}
