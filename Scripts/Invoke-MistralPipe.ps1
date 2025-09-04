[CmdletBinding(SupportsShouldProcess = $true)]
<#
.SYNOPSIS
    Hovedskript for Mistral Suite: bygger, publiserer, kjører og henter hemmeligheter.
.DESCRIPTION
    Erstatter de fleste tidligere skript. Henter hemmeligheter fra Bitwarden Secrets Manager.
.PARAMETER Action
    Hovedoperasjonen: 'All', 'Build', 'Run', 'Clean'.
#>
param(
    [ValidateSet('All', 'Build', 'Run', 'Clean')]
    [string]$Action = 'All',
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$Start,
    [switch]$NoSecrets
)
$ErrorActionPreference = 'Stop'
function Write-Header($Message) { Write-Host "
=== $Message ===" -ForegroundColor Cyan }
function Write-Ok($Message) { Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Err($Message) { Write-Host "✗ $Message" -ForegroundColor Red }

function Sync-SecretsFromBitwarden {
    Write-Header "Henter hemmeligheter fra Bitwarden Secrets Manager"
    $config = @{ OrgId = '2a879b27-765a-4678-aaa5-b31c00bd99ae'; ProjectId = '7033c654-3752-46dd-a06c-b34c00ff9e06'; ApiBase = 'https://api.bitwarden.com/secrets-manager/public' }
    if ([string]::IsNullOrWhiteSpace($env:BITWARDEN_ACCESS_TOKEN)) {
        $sec = Read-Host -Prompt "BITWARDEN_ACCESS_TOKEN (skjules)" -AsSecureString
        if (-not $sec) { throw "Token er påkrevd." }; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $env:BITWARDEN_ACCESS_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
    $token = ($env:BITWARDEN_ACCESS_TOKEN).Trim(); $headers = @{ Authorization = "Bearer $token"; 'Bitwarden-Organization-Id' = $config.OrgId }
    try {
        $uri = "$($config.ApiBase)/secrets?projectId=$($config.ProjectId)"
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -TimeoutSec 30
        if (-not $response.data) { throw "Ingen hemmeligheter funnet." }
        $secretMap = @{}; foreach ($secret in $response.data) { $key = $secret.key ?? $secret.name; if ($key) { $secretMap[$key] = $secret.value } }
        $envMap = @{'openai-api-key'='OPENAI_API_KEY';'openai-org-id'='OPENAI_ORG_ID';'MISTRAL_API_KEY'='MISTRAL_API_KEY';'graph-client-id'='GRAPH_CLIENT_ID';'graph-client-secret'='GRAPH_CLIENT_SECRET';'graph-tenant-id'='GRAPH_TENANT_ID'}
        foreach ($key in $envMap.Keys) { if ($secretMap.ContainsKey($key)) { [Environment]::SetEnvironmentVariable($envMap[$key], $secretMap[$key], 'Process') } }
        Write-Ok "Hemmeligheter er lastet inn i miljøet."
    } catch { Write-Err "Kunne ikke hente hemmeligheter: $($_.Exception.Message)"; throw }
}
function Invoke-Clean { if ($PSCmdlet.ShouldProcess("mapper: bin, obj", "Slett")) { Write-Header "Rydder bygg-mapper"; Get-ChildItem -Path ".\bin", ".\obj" -Recurse -Force | Remove-Item -Recurse -Force; Write-Ok "Ryddeoperasjon fullført." } }
function Invoke-Build { Write-Header "Bygger prosjektet (Configuration: $Configuration)"; dotnet build -c $Configuration; Write-Ok "Bygging fullført." }
function Start-App { Write-Header "Starter applikasjonen"; $exePath = Get-ChildItem -Path ".\bin\$Configuration\net*" -Filter "*.exe" -Recurse | Select-Object -First 1; if ($exePath) { Write-Host "Starter: $($exePath.FullName)"; Start-Process $exePath.FullName } else { Write-Err "Fant ingen .exe-fil å starte." } }

if (-not $NoSecrets) { Sync-SecretsFromBitwarden }
switch ($Action) {
    'Clean' { Invoke-Clean }
    'Build' { Invoke-Build }
    'Run'   { Start-App }
    'All'   { Invoke-Clean; Invoke-Build; if ($Start) { Start-App } }
}
Write-Host "
✓ Ferdig." -ForegroundColor Green
