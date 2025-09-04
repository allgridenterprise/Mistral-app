# Bw-LoginPersonalApi.ps1
# Logger inn i Bitwarden CLI med personlig API-nøkkel, låser opp, og eksporterer BW_SESSION.
# Bruk i CI/CD ved å sette BW_CLIENTID/BW_CLIENTSECRET (PERSONLIG API-nøkkel), og (valgfritt) BW_PASSWORD for uinteraktiv unlock.

param(
    [string]$ClientId,
    [string]$ClientSecret,
    [switch]$PersistEnv,         # setx for å lagre til brukerens miljøvariabler
    [switch]$Quiet               # minimal output
)

$ErrorActionPreference = 'Stop'

function Say($m, [string]$c='Cyan') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

# 0) Forhåndssjekk
try {
    $v = & bw --version 2>$null
    if (-not $v) { throw "bw CLI ikke funnet i PATH" }
    Say "bw CLI: v$($v.Trim())"
} catch {
    ERR "Bitwarden CLI ikke funnet. Installer @bitwarden/cli (npm) og prøv igjen."
    exit 1
}

# 1) Hent inn personlig API-nøkkel
if (-not $ClientId)   { $ClientId   = $env:BW_CLIENTID }
if (-not $ClientSecret) { $ClientSecret = $env:BW_CLIENTSECRET }

if (-not $ClientId) {
    $ClientId = Read-Host "Skriv inn PERSONLIG API Client ID (fra Web Vault → Settings → Security → API Key)"
}
if (-not $ClientSecret) {
    $sec = Read-Host "Skriv inn PERSONLIG API Client Secret" -AsSecureString
    $ClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

if ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($ClientSecret)) {
    ERR "ClientId/ClientSecret mangler. Bruk PERSONLIG API-nøkkel (ikke organisasjonsnøkkel)."
    exit 2
}

$env:BW_CLIENTID = $ClientId
$env:BW_CLIENTSECRET = $ClientSecret
if ($PersistEnv) {
    try {
        setx BW_CLIENTID $ClientId | Out-Null
        setx BW_CLIENTSECRET $ClientSecret | Out-Null
        OK "Lagret BW_CLIENTID/BW_CLIENTSECRET i brukermiljø."
    } catch {
        WARN "Kunne ikke persistere miljøvariabler: $($_.Exception.Message)"
    }
}

# 2) Login med API key
Say "Logger inn med personlig API-nøkkel ..."
$loginOut = & bw login --apikey 2>&1
if ($LASTEXITCODE -ne 0 -or ($loginOut -match "Invalid API Key" -or $loginOut -match "Organization API Key")) {
    ERR "Innlogging feilet. Kontroller at dette er PERSONLIG API-nøkkel (ikke organisasjonsnøkkel)."
    Say ("bw output: " + $loginOut) 'Yellow'
    exit 3
}
OK "Innlogging OK."

# 3) Unlock → BW_SESSION
if ($env:BW_PASSWORD) {
    Say "Låser opp hvelv uinteraktivt med BW_PASSWORD ..."
    $session = & bw unlock --raw --passwordenv BW_PASSWORD 2>$null
} else {
    Say "Låser opp hvelv (interaktiv passordprompt kan komme) ..."
    $session = & bw unlock --raw 2>$null
}
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($session)) {
    ERR "Unlock feilet. Sett eventuelt BW_PASSWORD for uinteraktiv unlock."
    exit 4
}
$env:BW_SESSION = $session
OK "BW_SESSION satt i miljø for denne prosessen."

# 4) Ekko session i stdout (for piping)
[Console]::Out.WriteLine($session)
