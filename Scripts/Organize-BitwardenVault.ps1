# Organize-BitwardenVault.ps1
# Rydder opp Bitwarden-struktur og organiserer elementer i fornuftige collections

param(
    [switch]$WhatIf,  # Vis hva som vil skje uten å endre
    [switch]$Force    # Gjør endringer uten bekreftelse
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { Write-Host $m -ForegroundColor $c }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }

Say "=== BITWARDEN VAULT ORGANISERING ===" 'Magenta'

if ($WhatIf) { Say "*** WHATIF-MODUS: Ingen endringer gjøres ***" 'Yellow' }

# Sjekk at vi har aktiv session
try {
    $status = & bw status --session $env:BW_SESSION | ConvertFrom-Json
    if ($status.status -ne "unlocked") {
        throw "Vault er ikke låst opp"
    }
    OK "Vault er låst opp og klar"
} catch {
    Say "Vault må være låst opp først. Kjør: `$env:BW_SESSION=`"<session-token>`"" 'Red'
    exit 1
}

# Definer ønsket struktur
$collections = @{
    "01-API-Keys" = @{
        description = "API-nøkler for tjenester (Mistral, OpenAI, etc.)"
        items = @("*api*key*", "*mistral*", "*openai*", "*gemini*", "*anthropic*")
    }
    "02-Development" = @{
        description = "Utviklingsrelaterte secrets"
        items = @("*github*", "*azure*", "*docker*", "*npm*", "*nuget*")
    }
    "03-Infrastructure" = @{
        description = "Server og infrastruktur-tilgang"
        items = @("*server*", "*ssh*", "*database*", "*admin*")
    }
    "04-Business-Apps" = @{
        description = "Forretningsapplikasjoner"
        items = @("*office*", "*teams*", "*sharepoint*", "*dynamics*")
    }
    "05-Personal-Work" = @{
        description = "Personlige arbeidskontoer"
        items = @("*@allgrid.com*", "*personal*")
    }
}

# Hent eksisterende items
Say "Henter eksisterende vault-innhold..."
$allItems = & bw list items --session $env:BW_SESSION | ConvertFrom-Json
Say "Funnet $($allItems.Count) elementer"

# Hent organisasjon og collections
$orgs = & bw list organizations --session $env:BW_SESSION | ConvertFrom-Json
if (-not $orgs -or $orgs.Count -eq 0) {
    Say "Ingen organisasjon funnet. Fortsetter uten org-collections." 'Yellow'
    $org = $null
} else {
    $org = $orgs | Where-Object { $_.name -like "*Allgrid*" } | Select-Object -First 1
    if (-not $org) { $org = $orgs | Select-Object -First 1 }
    Say "Bruker organisasjon: $($org.name) ($($org.id))"
}

$existingCollections = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
Say "Eksisterende collections: $($existingCollections.Count)"

# Opprett manglende collections
foreach ($collName in $collections.Keys) {
    $exists = $existingCollections | Where-Object { $_.name -eq $collName }
    if (-not $exists) {
        $collectionData = @{
            name = $collName
            organizationId = $org?.id
            groups = @()
            externalId = $null
        }

        if ($WhatIf) {
            WARN "Ville opprettet org-collection: $collName"
        } else {
            $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
            try {
                ($collectionData | ConvertTo-Json) | Set-Content $tempFile -Encoding UTF8
                $result = & bw create org-collection --file $tempFile --session $env:BW_SESSION
                if ($LASTEXITCODE -eq 0) {
                    OK "Opprettet org-collection: $collName"
                    # Oppdater cache av collections
                    $existingCollections = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
                } else {
                    WARN "Kunne ikke opprette org-collection $collName`: $result"
                }
            } finally {
                Remove-Item $tempFile -ErrorAction SilentlyContinue
            }
        }
    } else {
        Say "Collection eksisterer allerede: $collName"
    }
}

# Kategoriser og organiser items
Say "`n=== ORGANISERING AV ELEMENTER ==="
$organized = 0
$unmatched = @()

foreach ($item in $allItems) {
    $matched = $false
    $itemName = $item.name.ToLower()
    $itemNotes = ($item.notes ?? "").ToLower()

    foreach ($collName in $collections.Keys) {
        $patterns = $collections[$collName].items
        foreach ($pattern in $patterns) {
            if ($itemName -like $pattern -or $itemNotes -like $pattern) {
                # Finn eller hent collection-id
                $target = $existingCollections | Where-Object { $_.name -eq $collName } | Select-Object -First 1
                if (-not $target) {
                    WARN "Collection '$collName' mangler; hopper over flytting"
                } else {
                    if ($WhatIf) {
                        Say "Ville flyttet '$($item.name)' → $collName"
                    } else {
                        try {
                            # Hent item som JSON, oppdater collectionIds og skriv tilbake
                            $itemJson = & bw get item $item.id --session $env:BW_SESSION | ConvertFrom-Json
                            $current = @()
                            if ($itemJson.collectionIds) { $current = @($itemJson.collectionIds) }
                            if ($current -notcontains $target.id) {
                                $itemJson.collectionIds = @($current + $target.id)

                                $tmp = [System.IO.Path]::GetTempFileName() + ".json"
                                ($itemJson | ConvertTo-Json -Depth 20) | Set-Content $tmp -Encoding UTF8
                                $editRes = & bw edit item $item.id --file $tmp --session $env:BW_SESSION
                                Remove-Item $tmp -ErrorAction SilentlyContinue

                                if ($LASTEXITCODE -eq 0) {
                                    Say "Kategorisert '$($item.name)' → $collName"
                                } else {
                                    WARN "Kunne ikke flytte '$($item.name)' → $collName: $editRes"
                                }
                            } else {
                                Say "'$($item.name)' er allerede i '$collName'"
                            }
                        } catch {
                            WARN "Feil ved flytting av '$($item.name)': $($_.Exception.Message)"
                        }
                    }
                }
                $matched = $true
                $organized++
                break
            }
        }
        if ($matched) { break }
    }

    if (-not $matched) {
        $unmatched += $item
    }
}

# Rapport
Say "`n=== ORGANISERING FULLFØRT ===" 'Green'
Say "Organiserte elementer: $organized"
Say "Uorganiserte elementer: $($unmatched.Count)"

if ($unmatched.Count -gt 0) {
    Say "`nUorganiserte elementer:"
    $unmatched | ForEach-Object { Say "  - $($_.name)" }
    Say "`nVurder å legge disse inn i passende collections manuelt."
}

Say "`n=== ANBEFALINGER ==="
Say @"
✅ Bruk 01-05 prefiks for sortering
✅ Hold API-nøkler i egen collection med streng tilgangskontroll  
✅ Separer utvikling fra produksjon
✅ Reviewer tilganger jevnlig (kvartalsvis)
✅ Aktiver audit logging i Admin Console
"@
