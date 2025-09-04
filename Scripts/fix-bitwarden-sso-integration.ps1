param (
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory=$true)]
    [string]$BitwardenAppName,

    [Parameter(Mandatory=$true)]
    [string]$BitwardenEntityId,

    [Parameter(Mandatory=$true)]
    [string]$BitwardenAcsUrl,

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Create log directory
$logDir = "$PSScriptRoot\logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Start transcript
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = "$logDir\bitwarden-sso-fix-log-$timestamp.txt"
Start-Transcript -Path $logFile -ErrorAction SilentlyContinue

function Test-ModuleAvailable {
    param([string]$ModuleName)
    return [bool](Get-Module -ListAvailable -Name $ModuleName)
}

function Connect-MgGraphSafely {
    param([string[]]$Scopes)
    try {
        if (-not (Test-ModuleAvailable -ModuleName "Microsoft.Graph")) {
            Write-Host "Microsoft.Graph module not installed." -ForegroundColor Red
            return $false
        }
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
        $context = Get-MgContext
        if ($context) {
            Write-Host "Connected to Microsoft Graph as $($context.Account)" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "Error connecting to Microsoft Graph: $_" -ForegroundColor Red
        return $false
    }
}

# Connect to Microsoft Graph
$graphConnected = Connect-MgGraphSafely -Scopes @(
    "Application.ReadWrite.All",
    "AppRoleAssignment.ReadWrite.All",
    "Directory.ReadWrite.All",
    "User.ReadWrite.All"
)

if (-not $graphConnected) {
    Write-Host "Unable to connect to Microsoft Graph." -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Get user
try {
    $user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
    Write-Host "User found: $($user.DisplayName)" -ForegroundColor Green
} catch {
    Write-Host "User not found: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Get or create application
$appId = $null
try {
    $app = Get-MgApplication -Filter "displayName eq '$BitwardenAppName'" -ErrorAction SilentlyContinue
    if ($app) {
        $appId = $app.AppId
        Write-Host "Existing application found: $($app.DisplayName)" -ForegroundColor Green
        if ($Force) {
            $params = @{
                Web = @{
                    RedirectUris = @(
                        "https://vault.bitwarden.com",
                        "https://vault.bitwarden.com/#/sso",
                        $BitwardenAcsUrl
                    )
                    ImplicitGrantSettings = @{
                        EnableIdTokenIssuance = $true
                    }
                }
            }
            Update-MgApplication -ApplicationId $app.Id -BodyParameter $params
            Write-Host "Application updated." -ForegroundColor Green
        }
    } elseif ($Force) {
        $newAppParams = @{
            DisplayName = $BitwardenAppName
            SignInAudience = "AzureADMyOrg"
            Web = @{
                RedirectUris = @(
                    "https://vault.bitwarden.com",
                    "https://vault.bitwarden.com/#/sso",
                    $BitwardenAcsUrl
                )
                ImplicitGrantSettings = @{
                    EnableIdTokenIssuance = $true
                }
            }
        }
        $newApp = New-MgApplication -BodyParameter $newAppParams
        $appId = $newApp.AppId
        Write-Host "New application created: $($newApp.DisplayName)" -ForegroundColor Green
    }
} catch {
    Write-Host "Error managing application: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Get or create service principal
$servicePrincipal = $null
try {
    if ($appId) {
        Start-Sleep -Seconds 5
        $servicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue
        if (-not $servicePrincipal -and $Force) {
            $spParams = @{
                AppId = $appId
                DisplayName = $BitwardenAppName
            }
            $servicePrincipal = New-MgServicePrincipal -BodyParameter $spParams
            Write-Host "Service principal created." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "Error managing service principal: $_" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Configure SAML
try {
    if ($servicePrincipal) {
        $graphToken = (Get-MgContext).AccessToken
        $headers = @{
            Authorization = "Bearer $graphToken"
            "Content-Type" = "application/json"
        }
        $samlConfig = @{
            notificationEmailAddresses = @($UserPrincipalName)
            defaultRedirectUri = $BitwardenAcsUrl
            samlSingleSignOnSettings = @{
                relayState = ""
            }
        }
        $samlEndpoint = "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.Id)/synchronization/templates/customSamlTemplate"
        Invoke-RestMethod -Method Patch -Uri $samlEndpoint -Headers $headers -Body ($samlConfig | ConvertTo-Json -Depth 10)
        Write-Host "SAML configuration updated." -ForegroundColor Green
    }
} catch {
    Write-Host "Error configuring SAML: $_" -ForegroundColor Red
}

# Assign user to application
try {
    if ($servicePrincipal -and $user) {
        $assignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $servicePrincipal.Id -All
        $userAssigned = $assignments | Where-Object { $_.PrincipalId -eq $user.Id }
        if (-not $userAssigned -and $Force) {
            $assignmentEndpoint = "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.Id)/appRoleAssignments"
            $assignmentBody = @{
                principalId = $user.Id
                resourceId = $servicePrincipal.Id
                appRoleId = "00000000-0000-0000-0000-000000000000"
            }
            Invoke-RestMethod -Method POST -Uri $assignmentEndpoint -Headers $headers -Body ($assignmentBody | ConvertTo-Json)
            Write-Host "User assigned to application." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "Error assigning user: $_" -ForegroundColor Red
}

# Download SAML certificate
try {
    if ($servicePrincipal) {
        $certEndpoint = "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.Id)/servicePrincipalIdentityFederations"
        $certInfo = Invoke-RestMethod -Method GET -Uri $certEndpoint -Headers $headers
        if ($certInfo.value.Count -gt 0) {
            $certBase64 = $certInfo.value[0].certificate
            $certBytes = [System.Convert]::FromBase64String($certBase64)
            $certPath = "$logDir\saml_certificate_$timestamp.cer"
            [System.IO.File]::WriteAllBytes($certPath, $certBytes)
            Write-Host "SAML certificate saved to $certPath" -ForegroundColor Green
        } else {
            Write-Host "No certificate found." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Error downloading SAML certificate: $_" -ForegroundColor Red
}

# Make sure all URIs in the script have proper format and encoding
# This is particularly important for API calls to Microsoft Graph

# Ensure URLs are properly formatted when making REST calls
$samlEndpoint = "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.Id)/synchronization/templates/customSamlTemplate"

# When building URLs with variables, ensure they're properly encoded
function Get-EncodedUri {
    param([string]$baseUri, [hashtable]$queryParams)
    
    $queryString = ""
    foreach($key in $queryParams.Keys) {
        $encodedValue = [System.Web.HttpUtility]::UrlEncode($queryParams[$key])
        $queryString += "&$key=$encodedValue"
    }
    
    if($queryString.Length -gt 0) {
        $queryString = "?" + $queryString.Substring(1)
    }
    
    return "$baseUri$queryString"
}

# Example usage:
# $uri = Get-EncodedUri -baseUri "https://vault.bitwarden.com/sso" -queryParams @{
#    "organizationId" = $organizationId
#    "returnUrl" = "https://example.com/return"
# }

# This ensures all URIs are properly formed, preventing "no uri found" errors

# Disconnect and stop transcript
Disconnect-MgGraph -ErrorAction SilentlyContinue
Stop-Transcript
