# Copyright Allgrid@2024
# ===================================================================
# Configure-Bitwarden-SSO.ps1
# - Logger inn med Bitwarden SSO (valgfri OrganizationId)
# - Unlocker vault og henter Item (Mistral API Key)
# - Setter MISTRAL_API_KEY i miljø (valgfritt persistere med setx)
# - (Valgfritt) starter appen fra gitt sti
# ===================================================================
param(
    [string]$OrganizationId = "",
    [string]$ItemId,                                      # Bitwarden ItemId (UUID). Valgfri hvis du bruker -ItemName.
    [string]$ItemName,                                    # Alternativt: oppgi navnet på elementet (skriptet slår opp ID).
    [string]$FieldName = "MISTRAL_API_KEY",               # Navn på custom field om ikke login.password brukes
    [switch]$PersistEnv,                                  # setx for å persistere for brukeren
    [string]$AppPath                                      # (valgfritt) sti til MistralApp.exe for oppstart
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host $msg -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host $msg -ForegroundColor DarkYellow }
function Write-Err([string]$msg)  { Write-Host $msg -ForegroundColor Red }

function Ensure-BW {
    Write-Step "Sjekker Bitwarden CLI (bw)..."
    $bw = Get-Command bw -ErrorAction SilentlyContinue
    if (-not $bw) {
        Write-Warn "Fant ikke 'bw' på PATH. Forsøker winget installasjon..."
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            & winget install --id Bitwarden.CLI -e --source winget
            $bw = Get-Command bw -ErrorAction SilentlyContinue
            if (-not $bw) {
                throw "bw ble ikke funnet etter winget install. Installer Bitwarden CLI manuelt og prøv igjen."
            }
        } else {
            throw "winget ikke tilgjengelig. Installer Bitwarden CLI manuelt (https://bitwarden.com/help/cli/)."
        }
    }
    Write-OK "bw funnet: $($bw.Source)"
}

function BW-Login-SSO {
    Write-Step "Bitwarden status og innlogging (SSO)..."
    $st = & bw status --raw | ConvertFrom-Json
    if ($st.status -ne "unauthenticated") {
        Write-OK "Allerede autentisert."
    } else {
        $args = @("login","--sso")
        if ($OrganizationId) { $args += @("--organization-id", $OrganizationId) }
        & bw @args
        $st2 = & bw status --raw | ConvertFrom-Json
        if ($st2.status -eq "unauthenticated") {
            throw "SSO-innlogging feilet. Kontroller OrganizationId/tilgang."
        }
        Write-OK "SSO-innlogging OK."
    }
}

function BW-Unlock {
    Write-Step "Unlocker vault..."
    # bw unlock vil evt. spørre etter masterpassord hvis nødvendig.
    $session = & bw unlock --raw
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($session)) {
        throw "bw unlock mislyktes. Kontroller SSO/Key Connector eller masterpassord."
    }
    $env:BW_SESSION = $session
    Write-OK "Vault unlock OK (BW_SESSION satt)."
}

function BW-Get-ApiKey {
    param([string]$itemId,[string]$fieldName)
    Write-Step "Henter Item $itemId fra Bitwarden..."
    $json = & bw get item $itemId --session $env:BW_SESSION | ConvertFrom-Json

    if (-not $json) { throw "bw get item returnerte ingenting." }

    # 1) custom fields (anbefalt)
    $api = $null
    if ($json.fields) {
        $field = $json.fields | Where-Object { $_.name -eq $fieldName } | Select-Object -First 1
        if ($field -and $field.value) { $api = $field.value }
    }
    # 2) login.password fallback
    if (-not $api -and $json.login -and $json.login.password) {
        $api = $json.login.password
    }
    # 3) secure note fallback (ikke anbefalt, men mulig)
    if (-not $api -and $json.notes) {
        # Enkel heuristikk: første linje uten kolon/format
        $firstLine = ($json.notes -split "(`r`n|`n)") | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -First 1
        if ($firstLine -and ($firstLine -notmatch ":")) { $api = $firstLine.Trim() }
    }

    if ([string]::IsNullOrWhiteSpace($api)) {
        throw "Fant ikke API-nøkkel i Item. Sjekk FieldName='$fieldName' eller at login.password inneholder nøkkel."
    }
    return $api
}

function Set-MistralApiKey([string]$api,[switch]$persist) {
    Write-Step "Setter MISTRAL_API_KEY i miljø..."
    $env:MISTRAL_API_KEY = $api
    Write-OK "MISTRAL_API_KEY satt i gjeldende sesjon."
    if ($persist) {
        setx MISTRAL_API_KEY $api | Out-Null
        Write-OK "MISTRAL_API_KEY persistert (bruker). Lukk/åpne terminal for å lese inn globalt."
    }
}

try {
    Ensure-BW
    BW-Login-SSO
    BW-Unlock
    & bw sync --session $env:BW_SESSION | Out-Null

    # Auto-oppslag av ItemId hvis ikke oppgitt, men ItemName er gitt
    if ([string]::IsNullOrWhiteSpace($ItemId) -and -not [string]::IsNullOrWhiteSpace($ItemName)) {
        Write-Step "Slår opp ItemId for navn: '$ItemName'..."
        $items = & bw list items --search $ItemName --session $env:BW_SESSION | ConvertFrom-Json
        if (-not $items) {
            throw "Fant ingen elementer som matcher navn: '$ItemName'."
        }
        # Først: forsøk eksakt navnematch (case-insensitiv)
        $exact = $items | Where-Object { $_.name -and ($_.name -eq $ItemName) }
        if ($exact.Count -eq 1) {
            $ItemId = $exact[0].id
        } elseif ($exact.Count -gt 1) {
            $list = ($exact | Select-Object id,name) | Out-String
            throw "Flere elementer med eksakt navn '$ItemName' funnet. Spesifiser ItemId. Treff:`n$list"
        } else {
            # Ellers: ta første treff i søket
            if ($items.Count -eq 1) {
                $ItemId = $items[0].id
            } else {
                $list = ($items | Select-Object id,name | Select-Object -First 10) | Out-String
                throw "Flere treff for '$ItemName'. Spesifiser ItemId. Eksempler:`n$list"
            }
        }
        Write-OK "ItemId funnet: $ItemId"
    }

    if ([string]::IsNullOrWhiteSpace($ItemId)) {
        throw "Mangler ItemId. Oppgi -ItemId <UUID> eller -ItemName <Navn>."
    }

    $apiKey = BW-Get-ApiKey -itemId $ItemId -fieldName $FieldName
    Set-MistralApiKey -api $apiKey -persist:$PersistEnv

    if ($AppPath) {
        if (Test-Path $AppPath) {
            Write-Step "Starter app: $AppPath"
            Start-Process -FilePath $AppPath
        } else {
            Write-Warn "AppPath finnes ikke: $AppPath"
        }
    } else {
        Write-OK "Ferdig. Start appen manuelt for test."
    }
}
catch {
    Write-Err $_
    exit 1
}

# Eksempel:
# pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Configure-Bitwarden-SSO.ps1 `
#   -OrganizationId "ORG_GUID_HER" `
#   -ItemId "ITEM_GUID_MED_MISTRAL_KEY" `
#   -FieldName "MISTRAL_API_KEY" `
#   -PersistEnv `
#   -AppPath ".\bin\Release\net8.0-windows\win-x64\publish\MistralApp.exe"
