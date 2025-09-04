# BW-Login.ps1
# Enkelt login-skript for Bitwarden:
#  - SSO (standard) eller personlig API-nøkkel (--apikey)
#  - Unlock av hvelv og eksport av BW_SESSION
#  - Best effort frigjøring av port 8065 for SSO

param(
    [switch]$UseApi,                  # Bruk personlig API-nøkkel istedenfor SSO
    [string]$ClientId,                # Personlig API Client ID (ellers BW_CLIENTID)
    [string]$ClientSecret,            # Personlig API Client Secret (ellers BW_CLIENTSECRET)
    [switch]$PersistEnv,              # Persister BW_CLIENTID/BW_CLIENTSECRET (setx)
    [switch]$Quiet                    # Minimal output
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

# Sjekk bw
try {
    $v = (& bw --version 2>$null).Trim()
    if (-not $v) { throw "bw CLI ikke funnet i PATH." }
    Say "bw CLI: v$v"
} catch {
    ERR "Bitwarden CLI ikke funnet. Installer @bitwarden/cli (npm) og prøv igjen."
    exit 1
}

# Frigjør port 8065 (SSO bruker denne)
function Free-Port8065 {
    try {
        $lines = netstat -ano | Select-String ":8065"
        foreach ($ln in $lines) {
            if ($ln -match "\s+(\d+)$") {
                $pid = [int]$matches[1]
                try { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue; Say "Drepte PID $pid på 8065" 'Yellow' } catch { }
            }
        }
    } catch { }
}

if ($UseApi) {
    # Personlig API‑nøkkel
    if (-not $ClientId)     { $ClientId     = $env:BW_CLIENTID }
    if (-not $ClientSecret) { $ClientSecret = $env:BW_CLIENTSECRET }

    if ([string]::IsNullOrWhiteSpace($ClientId))     { $ClientId = Read-Host "PERSONLIG API Client ID" }
    if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
        $sec = Read-Host "PERSONLIG API Client Secret" -AsSecureString
        $ClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    }

    if ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
        ERR "ClientId/ClientSecret mangler. Dette må være personlig API‑nøkkel (ikke org‑nøkkel)."
        exit 2
    }

    $env:BW_CLIENTID = $ClientId
    $env:BW_CLIENTSECRET = $ClientSecret
    if ($PersistEnv) {
        try { setx BW_CLIENTID $ClientId  | Out-Null; setx BW_CLIENTSECRET $ClientSecret | Out-Null; OK "Lagret BW_CLIENTID/BW_CLIENTSECRET i brukermiljø." } catch { }
    }

    Say "Logger inn med personlig API-nøkkel ..."
    $out = & bw login --apikey 2>&1
    if ($LASTEXITCODE -ne 0 -or ($out -match "Invalid API Key" -or $out -match "Organization API Key")) {
        ERR "Innlogging feilet. Sjekk at dette er personlig API‑nøkkel."
        Say ("bw output: " + $out) 'Yellow'
        exit 3
    }
    OK "Innlogging OK."
} else {
    Free-Port8065
    Say "Logger inn via SSO ..."
    $out = & bw login --sso 2>&1
    if ($LASTEXITCODE -ne 0) { ERR "SSO-innlogging feilet: $out"; exit 3 }
    OK "SSO-innlogging OK."
}

# Unlock
if ($env:BW_PASSWORD) {
    Say "Låser opp hvelv (uinteraktivt) ..."
    $session = & bw unlock --raw --passwordenv BW_PASSWORD 2>$null
} else {
    Say "Låser opp hvelv ..."
    $session = & bw unlock --raw 2>$null
}
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($session)) { ERR "Unlock feilet."; exit 4 }

$env:BW_SESSION = $session
OK "BW_SESSION satt for denne økten."
# Echo session til stdout hvis du vil bruke piping
[Console]::Out.WriteLine($session)
