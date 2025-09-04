# ===================================================================
# Setup-MistralApiKey-Bitwarden.ps1
# - SSO-login (valgfri OrganizationId)
# - Unlock vault og hent API-nøkkel fra element: "Mistral-Suit_Api-Key"
# - Sett MISTRAL_API_KEY (i sesjon + persister med setx)
# - Start appen fra publish
# ===================================================================
param(
    [string]$OrganizationId = "",
    [string]$ItemName = "Mistral-Suit_Api-Key",
    [string]$FieldName = "MISTRAL_API_KEY"
)

$ErrorActionPreference = 'Stop'
function Step([string]$m){ Write-Host "`n==> $m" -ForegroundColor Cyan }
function OK([string]$m){ Write-Host $m -ForegroundColor Green }
function Warn([string]$m){ Write-Host $m -ForegroundColor DarkYellow }
function Err([string]$m){ Write-Host $m -ForegroundColor Red }

# Finn prosjektrot (støtter kjøring fra Scripts eller rot)
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $cwd = (Get-Location).Path
    if ($cwd -match '([\\/]|^)Scripts([\\/]|$)') { $projectRoot = Split-Path $cwd -Parent } else { $projectRoot = $cwd }
} else {
    $projectRoot = Split-Path $PSScriptRoot -Parent
}
OK "Prosjektrot: $projectRoot"

# Sikre Bitwarden CLI
Step "Sjekker Bitwarden CLI (bw)..."
$bw = Get-Command bw -ErrorAction SilentlyContinue
if (-not $bw) {
    Warn "Fant ikke 'bw' på PATH. Forsøker winget installasjon..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id Bitwarden.CLI -e --source winget
        $bw = Get-Command bw -ErrorAction SilentlyContinue
        if (-not $bw) { throw "Installer Bitwarden CLI manuelt: https://bitwarden.com/help/cli/" }
    } else {
        throw "winget ikke tilgjengelig. Installer Bitwarden CLI manuelt."
    }
}
OK "bw funnet."

# SSO-login
Step "Autentiserer (SSO)..."
$st = & bw status --raw | ConvertFrom-Json
if ($st.status -eq "unauthenticated") {
    $args = @("login","--sso"); if ($OrganizationId){ $args += @("--organization-id",$OrganizationId) }
    & bw @args
    $st = & bw status --raw | ConvertFrom-Json
    if ($st.status -eq "unauthenticated") { throw "SSO-innlogging feilet." }
}
OK "Autentisert."

# Unlock
Step "Unlocker vault..."
$session = & bw unlock --raw
if ([string]::IsNullOrWhiteSpace($session)) {
    Warn "Fikk ikke BW_SESSION automatisk. Kjør 'bw unlock --raw' i et nytt vindu og lim inn token her."
    $session = Read-Host "Lim inn BW_SESSION"
}
if ([string]::IsNullOrWhiteSpace($session)) { throw "Mangler BW_SESSION." }
$env:BW_SESSION = $session
OK "Vault unlock OK."

# Sync
& bw sync --session $env:BW_SESSION | Out-Null

# Slå opp ItemId fra navn (eksakt match først, ellers første treff)
Step "Slår opp element: '$ItemName'..."
$items = & bw list items --search $ItemName --session $env:BW_SESSION | ConvertFrom-Json
if (-not $items) { throw "Fant ingen elementer som matcher '$ItemName'." }
$exact = $items | Where-Object { $_.name -and ($_.name -eq $ItemName) }
$item = $null
if ($exact.Count -eq 1) { $item = $exact[0] }
elseif ($exact.Count -gt 1) {
    $list = ($exact | Select-Object id,name | Out-String)
    throw "Flere elementer med eksakt navn. Spesifiser mer unikt navn. Treff:`n$list"
}
else {
    if ($items.Count -eq 1) { $item = $items[0] }
    else {
        $list = ($items | Select-Object id,name | Select-Object -First 10 | Out-String)
        throw "Flere treff. Spesifiser mer unikt navn. Eksempler:`n$list"
    }
}
OK "ItemId: $($item.id)"

# Hent API key (custom field foretrukket, ellers login.password, ellers notes)
Step "Henter API-nøkkel..."
$full = & bw get item $item.id --session $env:BW_SESSION | ConvertFrom-Json
$api = $null
if ($full.fields) {
    $f = $full.fields | Where-Object { $_.name -eq $FieldName } | Select-Object -First 1
    if ($f -and $f.value) { $api = $f.value }
}
if (-not $api -and $full.login -and $full.login.password) { $api = $full.login.password }
if (-not $api -and $full.notes) {
    $firstLine = ($full.notes -split "(`r`n|`n)") | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -First 1
    if ($firstLine -and ($firstLine -notmatch ":")) { $api = $firstLine.Trim() }
}
if (-not $api) { throw "Fant ikke API-nøkkel i '$ItemName'. Sjekk custom field '$FieldName' eller login.password." }

# Sett miljøvariabel
Step "Setter MISTRAL_API_KEY..."
$env:MISTRAL_API_KEY = $api
OK "Satt i denne sesjonen."
setx MISTRAL_API_KEY $api | Out-Null
OK "Persistert for brukeren (åpne ny terminal/app for global effekt)."

# Start app fra publish
$publish = Join-Path $projectRoot "bin\Release\net8.0-windows\win-x64\publish\MistralApp.exe"
if (Test-Path $publish) {
    Step "Starter app: $publish"
    Start-Process -FilePath $publish
} else {
    Warn "Fant ikke $publish. Kjør build/publish først."
}
OK "Ferdig."
