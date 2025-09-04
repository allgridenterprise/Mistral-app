# New-BwSecureNoteFromJson.ps1
# Oppretter en Bitwarden Secure Note direkte fra JSON.
# Kilde kan være: -Json (string), -FromFile (sti) eller utklippstavlen (clipboard) hvis ingenting er spesifisert.
# Valgfritt: legg inn i organisasjon og collection (oppretter collection om den ikke finnes).

param(
    [string]$Json,
    [string]$FromFile,
    [string]$OrganizationName = "Allgrid",
    [string]$CollectionName,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

# 0) Sjekk bw CLI
try {
    $bwVer = (& bw --version 2>$null).Trim()
    if (-not $bwVer) { throw "bw CLI ikke funnet i PATH." }
    Say "bw CLI: v$bwVer"
} catch {
    ERR "Bitwarden CLI ikke funnet. Installer @bitwarden/cli og prøv igjen."
    exit 1
}

# 1) Hent JSON
if (-not $Json -and -not $FromFile) {
    try { $Json = Get-Clipboard -Raw } catch { }
}
if ($FromFile) {
    if (-not (Test-Path $FromFile)) { ERR "Fant ikke fil: $FromFile"; exit 2 }
    $Json = Get-Content $FromFile -Raw
}
if ([string]::IsNullOrWhiteSpace($Json)) {
    ERR "Ingen JSON funnet. Oppgi -Json, -FromFile eller kopier JSON til utklippstavlen."
    exit 2
}

# 2) Parse og normaliser JSON (sikre type/name)
try {
    $obj = $Json | ConvertFrom-Json
} catch {
    ERR "Ugyldig JSON: $($_.Exception.Message)"
    exit 3
}

# type: 2 = Secure Note
if ($null -eq $obj.type) {
    $obj | Add-Member -NotePropertyName type -NotePropertyValue 2 -Force
} elseif ([int]$obj.type -ne 2) {
    WARN "JSON.type != 2. Justerer til Secure Note (2)."
    $obj.type = 2
}

# name: påkrevd
if ([string]::IsNullOrWhiteSpace($obj.name)) {
    $fallbackName = "Device: $($env:COMPUTERNAME) ($(Get-Date -Format 'yyyyMMdd-HHmm'))"
    WARN "JSON.name tom. Setter navn til: $fallbackName"
    $obj | Add-Member -NotePropertyName name -NotePropertyValue $fallbackName -Force
}

# secureNote-blokk
if ($null -eq $obj.secureNote) {
    $obj | Add-Member -NotePropertyName secureNote -NotePropertyValue (@{ type = 0 }) -Force
} else {
    if ($null -eq $obj.secureNote.type) { $obj.secureNote | Add-Member -NotePropertyName type -NotePropertyValue 0 -Force }
}

# 3) Sikre BW_SESSION
function Ensure-Session {
    if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) {
        try { $env:BW_SESSION = & bw unlock --raw 2>$null } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) {
        ERR "BW_SESSION mangler. Kjør 'bw login --sso' og deretter 'bw unlock --raw' (sett til BW_SESSION)."
        exit 4
    }
}
Ensure-Session

# 4) Organisasjon og collection (valgfritt)
$orgId = $null
try {
    $orgs = & bw list organizations --session $env:BW_SESSION | ConvertFrom-Json
    if ($orgs -and $orgs.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($OrganizationName)) {
            $org = $orgs | Select-Object -First 1
        } else {
            $org = $orgs | Where-Object { $_.name -like "*$OrganizationName*" } | Select-Object -First 1
            if (-not $org) { $org = $orgs | Select-Object -First 1 }
        }
        if ($org) { $orgId = $org.id; Say "Organisasjon: $($org.name) ($orgId)" }
    }
} catch {
    WARN "Kunne ikke hente organisasjoner: $($_.Exception.Message)"
}

if ($orgId) { $obj | Add-Member -NotePropertyName organizationId -NotePropertyValue $orgId -Force }

$collectionId = $null
if ($orgId -and -not [string]::IsNullOrWhiteSpace($CollectionName)) {
    try {
        $collections = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
        $c = $collections | Where-Object { $_.organizationId -eq $orgId -and $_.name -eq $CollectionName } | Select-Object -First 1
        if (-not $c) {
            $collData = @{
                name = $CollectionName
                organizationId = $orgId
                groups = @()
                externalId = $null
            } | ConvertTo-Json
            $tmpC = [IO.Path]::GetTempFileName() + ".json"
            $collData | Set-Content $tmpC -Encoding UTF8
            $crt = & bw create org-collection --file $tmpC --session $env:BW_SESSION
            Remove-Item $tmpC -ErrorAction SilentlyContinue
            if ($LASTEXITCODE -eq 0) {
                $collections = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
                $c = $collections | Where-Object { $_.organizationId -eq $orgId -and $_.name -eq $CollectionName } | Select-Object -First 1
                if ($c) { OK "Opprettet collection: $CollectionName" }
            } else {
                WARN "Kunne ikke opprette collection '$CollectionName'. Fortsetter uten."
            }
        }
        if ($c) { $collectionId = $c.id }
    } catch {
        WARN "Feil ved henting/oppretting av collection: $($_.Exception.Message)"
    }
}

if ($collectionId) {
    if ($obj.PSObject.Properties.Name -notcontains 'collectionIds' -or -not $obj.collectionIds) {
        $obj | Add-Member -NotePropertyName collectionIds -NotePropertyValue @($collectionId) -Force
    } elseif ($obj.collectionIds -notcontains $collectionId) {
        $obj.collectionIds += $collectionId
    }
}

# 5) Opprett notatet
$tmp = [IO.Path]::GetTempFileName() + ".json"
try {
    ($obj | ConvertTo-Json -Depth 20) | Set-Content $tmp -Encoding UTF8
    Say "Oppretter Secure Note: '$($obj.name)'" 'Green'
    $res = & bw create item --file $tmp --session $env:BW_SESSION
    if ($LASTEXITCODE -ne 0) {
        ERR "Opprettelse feilet: $res"
        exit 5
    }
    OK "Secure Note opprettet!"
} finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
