# Copyright Allgrid@2024
# ===================================================================
# Setup-AzureGraph.ps1
# Konfigurer Azure CLI og MS Graph API-tilgang for MistralApp
# ===================================================================

param (
    [switch]$Force,         # Tvinger rekonfigurasjon
    [switch]$CleanAccounts  # Rydde opp i tidligere kontoer
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host $msg -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host $msg -ForegroundColor Red }

# Sjekk om Azure CLI er installert
$azCliExists = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCliExists) {
    Write-Err "Azure CLI ikke funnet. Vennligst installer fra https://aka.ms/installazurecli"
    exit 1
}

Write-Step "Verifiserer Azure CLI-installasjon"
$azVersion = az --version | Select-String "azure-cli" | Select-Object -First 1
Write-OK "Azure CLI versjon: $azVersion"

# Sjekk innloggingsstatus
Write-Step "Sjekker Azure-konto"
try {
    $account = az account show | ConvertFrom-Json
    Write-OK "Du er logget inn som: $($account.user.name)"
    
    if ($Force -or $CleanAccounts) {
        Write-Step "Tvungen reautentisering valgt, logger ut..."
        az account clear
        Write-OK "Utlogging fullført"
    }
} catch {
    Write-Warn "Du er ikke logget inn i Azure CLI"
}

# Logg inn
if (-not $account -or $Force -or $CleanAccounts) {
    Write-Step "Logger inn med Azure CLI..."
    az login --use-device-code
    
    # Sjekk om innlogging var vellykket
    try {
        $account = az account show | ConvertFrom-Json
        Write-OK "Innlogging vellykket som: $($account.user.name)"
    } catch {
        Write-Err "Innlogging mislyktes"
        exit 1
    }
}

# Sjekk lisenser og Exchange Online-status
Write-Step "Sjekker Microsoft Graph API-tilgang..."
$token = az account get-access-token --resource https://graph.microsoft.com | ConvertFrom-Json
Write-OK "Token hentet for Microsoft Graph API"

# Lagre token-informasjon til fil for senere bruk
$tokenInfo = @{
    AccessToken = $token.accessToken
    ExpiresOn = $token.expiresOn
    Subscription = $token.subscription
    TenantId = $token.tenant
    TokenType = $token.tokenType
}

$tokenFile = Join-Path $env:LOCALAPPDATA "MistralApp\ms-graph-token.json"
$tokenDir = Split-Path $tokenFile -Parent

# Opprett mappe hvis den ikke eksisterer
if (-not (Test-Path $tokenDir)) {
    New-Item -Path $tokenDir -ItemType Directory -Force | Out-Null
}

# Lagre token
$tokenInfo | ConvertTo-Json | Set-Content -Path $tokenFile
Write-OK "Token lagret til: $tokenFile"

Write-OK "Azure Graph API-oppsett fullført!"
Write-OK "Tenant ID: $($token.tenant)"
Write-OK "Token utløper: $($token.expiresOn)"

