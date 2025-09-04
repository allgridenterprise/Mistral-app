#
# BitwardenSSO-Configure.ps1
#
# Dette skriptet konfigurerer Bitwarden SSO med Windows Hello for Business
# og rydder opp i potensielle autentiseringsproblemer.
#

param(
    [string]$Email = 'dan@allgrid.com',
    [int]$SessionTimeout = 1440,  # 24 timer i minutter
    [switch]$Force
)

# Fargede utskrifter for bedre lesbarhet
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    else {
        $input | Write-Output
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Success($message) {
    Write-ColorOutput Green "✓ $message"
}

function Write-Info($message) {
    Write-ColorOutput Cyan "ℹ $message"
}

function Write-Warning($message) {
    Write-ColorOutput Yellow "⚠ $message"
}

function Write-Error($message) {
    Write-ColorOutput Red "✗ $message"
}

Write-Info "==============================================="
Write-Info "  Bitwarden SSO og Windows Hello konfigurering"
Write-Info "==============================================="
Write-Info ""

# 1. Sjekk om Bitwarden er installert
Write-Info "Sjekker Bitwarden installasjon..."
$bitwardenDir = Join-Path $env:APPDATA "Bitwarden"
if (-not (Test-Path $bitwardenDir)) {
    Write-Warning "Bitwarden-katalogen ikke funnet. Oppretter ny..."
    try {
        New-Item -ItemType Directory -Path $bitwardenDir -Force | Out-Null
        Write-Success "Opprettet Bitwarden-katalog: $bitwardenDir"
    } catch {
        Write-Error "Kunne ikke opprette Bitwarden-katalog: $($_.Exception.Message)"
        exit 1
    }
}

# 2. Fjern eventuelle konflikterende fingerprints
Write-Info "Fjerner eventuelle fingerprint-filer..."
$fingerprintPath = Join-Path $bitwardenDir "fingerprint.json"
if (Test-Path $fingerprintPath) {
    try {
        Remove-Item $fingerprintPath -Force
        Write-Success "Fjernet fingerprint.json for å unngå synkroniseringsproblemer"
    } catch {
        Write-Error "Kunne ikke fjerne fingerprint.json: $($_.Exception.Message)"
    }
}

# 3. Oppdater Bitwarden-konfigurasjon
Write-Info "Oppdaterer Bitwarden-konfigurasjon for SSO..."
$configPath = Join-Path $bitwardenDir "data.json"
$config = $null

try {
    if (Test-Path $configPath) {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
        Write-Info "Eksisterende konfigurasjon funnet, oppdaterer..."
    } else {
        Write-Info "Ingen eksisterende konfigurasjon funnet, oppretter ny..."
        $config = [PSCustomObject]@{}
    }
    
    # Oppdater eller legg til konfigurasjonsverdier
    $config | Add-Member -NotePropertyName "rememberedEmail" -NotePropertyValue $Email -Force
    $config | Add-Member -NotePropertyName "ssoEmail" -NotePropertyValue $Email -Force
    $config | Add-Member -NotePropertyName "ssoStateEmail" -NotePropertyValue $Email -Force
    $config | Add-Member -NotePropertyName "autoFillOnPageLoadDefault" -NotePropertyValue $true -Force
    $config | Add-Member -NotePropertyName "enableAutoFillOnPageLoad" -NotePropertyValue $true -Force
    $config | Add-Member -NotePropertyName "vaultTimeout" -NotePropertyValue $SessionTimeout -Force
    $config | Add-Member -NotePropertyName "vaultTimeoutAction" -NotePropertyValue "lock" -Force
    $config | Add-Member -NotePropertyName "usesKeyConnector" -NotePropertyValue $true -Force
    $config | Add-Member -NotePropertyName "biometricUnlock" -NotePropertyValue $true -Force
    $config | Add-Member -NotePropertyName "biometricText" -NotePropertyValue "Windows Hello" -Force
    $config | Add-Member -NotePropertyName "enableWindowsHello" -NotePropertyValue $true -Force

    # Lagre konfigurasjon
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Force
    Write-Success "Bitwarden-konfigurasjon oppdatert for SSO og Windows Hello"

} catch {
    Write-Error "Kunne ikke oppdatere Bitwarden-konfigurasjon: $($_.Exception.Message)"
}

# 4. Konfigurer Windows Hello
Write-Info "Konfigurerer Windows Hello for Business..."
try {
    # Enable biometric login in Windows settings
    $biometricPath = "HKLM:\SOFTWARE\Policies\Microsoft\Biometrics"
    if (-not (Test-Path $biometricPath)) {
        New-Item -Path $biometricPath -Force | Out-Null
    }
    Set-ItemProperty -Path $biometricPath -Name "Enabled" -Value 1 -Type DWord -Force
    
    # Enable Windows Hello
    $helloPath = "HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork"
    if (-not (Test-Path $helloPath)) {
        New-Item -Path $helloPath -Force | Out-Null
    }
    Set-ItemProperty -Path $helloPath -Name "Enabled" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $helloPath -Name "RequireSecurityDevice" -Value 0 -Type DWord -Force
    
    Write-Success "Windows Hello for Business er konfigurert"
} catch {
    Write-Warning "Kunne ikke konfigurere Windows Hello (krever administratorrettigheter): $($_.Exception.Message)"
}

# 5. Konfigurer Mistral app integrasjon med Bitwarden
Write-Info "Konfigurerer Mistral app integrasjon med Bitwarden..."
$mistralConfigDir = Join-Path $env:APPDATA "MistralSuite"
if (-not (Test-Path $mistralConfigDir)) {
    try {
        New-Item -ItemType Directory -Path $mistralConfigDir -Force | Out-Null
        Write-Success "Opprettet MistralSuite-konfigurasjonskatalog"
    } catch {
        Write-Error "Kunne ikke opprette MistralSuite-konfigurasjonskatalog: $($_.Exception.Message)"
    }
}

$mistralConfigPath = Join-Path $mistralConfigDir "appsettings.json"
try {
    $mistralConfig = $null
    if (Test-Path $mistralConfigPath) {
        $mistralConfig = Get-Content -Path $mistralConfigPath -Raw | ConvertFrom-Json
    } else {
        $mistralConfig = [PSCustomObject]@{}
    }
    
    # Oppdater eller legg til Bitwarden-konfigurasjon
    if (-not ($mistralConfig.PSObject.Properties.Name -contains "BitwardenConfig")) {
        $mistralConfig | Add-Member -NotePropertyName "BitwardenConfig" -NotePropertyValue @{} -Force
    }
    
    $mistralConfig.BitwardenConfig = @{
        Email = $Email
        UseWindowsHello = $true
        SessionTimeout = $SessionTimeout
    }
    
    # Lagre konfigurasjon
    $mistralConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $mistralConfigPath -Force
    Write-Success "Mistral app konfigurasjon oppdatert for Bitwarden SSO"
} catch {
    Write-Error "Kunne ikke oppdatere Mistral app konfigurasjon: $($_.Exception.Message)"
}

# 6. Konfigurer Microsoft 365 innstillinger for å unngå SSO-konflikter
Write-Info "Konfigurerer Microsoft 365 innstillinger..."
try {
    # Forsøk å fjerne cached credentials for Office 365
    $credentialPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Identity"
    if (Test-Path $credentialPath) {
        if ($Force -or (Read-Host "Vil du fjerne lagrede Office 365 legitimasjoner for å unngå SSO-konflikter? (j/n)").ToLower() -eq 'j') {
            Remove-ItemProperty -Path $credentialPath -Name "EnableADAL" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $credentialPath -Name "Version" -ErrorAction SilentlyContinue
            Write-Success "Fjernet cached Office 365 legitimasjoner"
        }
    }
} catch {
    Write-Warning "Kunne ikke fjerne Office 365 legitimasjoner: $($_.Exception.Message)"
}

Write-Info ""
Write-Success "=== Bitwarden SSO og Windows Hello konfigurering fullført ==="
Write-Info "E-post: $Email"
Write-Info "Session timeout: $SessionTimeout minutter"
Write-Info ""
Write-Info "For at endringene skal tre i kraft:"
Write-Info "1. Start Mistral app på nytt"
Write-Info "2. Logg inn på Bitwarden med SSO"
Write-Info "3. Aktiver Windows Hello når du blir spurt"
Write-Info ""

