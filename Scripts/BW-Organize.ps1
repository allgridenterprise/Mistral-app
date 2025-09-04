# BW-Organize.ps1
# Kategoriserer elementer i noen få, fornuftige collections.
# Default: WhatIf. Bruk -Apply for å gjøre faktiske endringer.

param(
    [switch]$Apply,
    [string]$OrganizationName = "Allgrid",
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) { ERR "BW_SESSION mangler. Kjør BW-Login.ps1 først."; exit 1 }

# Definer struktur
$collections = @{
    "01-API-Keys"     = @("*api*key*", "*mistral*", "*openai*", "*gemini*", "*anthropic*")
    "02-Development"  = @("*github*", "*nuget*", "*docker*", "*dev.azure*", "*gitlab*", "*gitkraken*")
    "03-Infrastructure"= @("*server*", "*ssh*", "*admin*", "*azure*", "*aws*", "*gcp*")
    "04-Business-Apps"= @("*office*", "*teams*", "*sharepoint*", "*outlook*", "*microsoft*")
    "05-Personal-Work"= @("*@allgrid.com*", "*personal*", "*linkedin*", "*facebook*")
}

# Finn org
$orgId = $null
try {
    $orgs = & bw list organizations --session $env:BW_SESSION | ConvertFrom-Json
    $org = $orgs | Where-Object { $_.name -like "*$OrganizationName*" } | Select-Object -First 1
    if (-not $org) { $org = $orgs | Select-Object -First 1 }
    if ($org) { $orgId = $org.id; Say "Organisasjon: $($org.name)" }
} catch { }

# Hent items/collections
$items = & bw list items --session $env:BW_SESSION | ConvertFrom-Json
$existing = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json

# Sikre collections
foreach ($name in $collections.Keys) {
    $c = $existing | Where-Object { $_.name -eq $name -and ($orgId -eq $null -or $_.organizationId -eq $orgId) } | Select-Object -First 1
    if (-not $c) {
        $def = @{ name=$name; organizationId=$orgId; groups=@(); externalId=$null } | ConvertTo-Json
        $tmp = [IO.Path]::GetTempFileName()+".json"; $def | Set-Content $tmp -Encoding UTF8
        $res = & bw create org-collection --file $tmp --session $env:BW_SESSION
        Remove-Item $tmp -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0) {
            $existing = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
            OK "Opprettet: $name"
        } else {
            WARN "Kunne ikke opprette '$name': $res"
        }
    }
}

# Flytting
[int]$moved = 0
foreach ($it in $items) {
    $nm = ($it.name ?? "").ToLower()
    $nt = ($it.notes ?? "").ToLower()
    foreach ($kv in $collections.GetEnumerator()) {
        $targetName = $kv.Key
        $patterns = $kv.Value
        $hit = $false
        foreach ($p in $patterns) {
            if ($nm -like $p -or $nt -like $p) { $hit = $true; break }
        }
        if ($hit) {
            $target = $existing | Where-Object { $_.name -eq $targetName } | Select-Object -First 1
            if (-not $target) { break }
            $has = $false
            if ($it.collectionIds) { $has = ($it.collectionIds -contains $target.id) }
            if (-not $has) {
                if ($Apply) {
                    try {
                        $full = & bw get item $it.id --session $env:BW_SESSION | ConvertFrom-Json
                        $cur = @()
                        if ($full.collectionIds) { $cur = @($full.collectionIds) }
                        $full.collectionIds = @($cur + $target.id)

                        $tmp = [IO.Path]::GetTempFileName()+".json"
                        ($full | ConvertTo-Json -Depth 20) | Set-Content $tmp -Encoding UTF8
                        $edit = & bw edit item $it.id --file $tmp --session $env:BW_SESSION
                        Remove-Item $tmp -ErrorAction SilentlyContinue
                        if ($LASTEXITCODE -eq 0) { $moved++; Say "Flyttet '$($it.name)' → $targetName" }
                        else { WARN "Edit feilet for '$($it.name)': $edit" }
                    } catch { WARN "Feil ved flytting av '$($it.name)': $($_.Exception.Message)" }
                } else {
                    Say "[WhatIf] Ville flyttet '$($it.name)' → $targetName"
                }
            }
            break
        }
    }
}

if ($Apply) { OK "Ferdig. Flyttet: $moved" } else { WARN "Kjør med -Apply for å utføre endringer." }
