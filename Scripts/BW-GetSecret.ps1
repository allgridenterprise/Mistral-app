# BW-GetSecret.ps1
# Henter første match på navn i vault og skriver valgt felt.
# Eksempler:
#   .\BW-GetSecret.ps1 -Name "Mistral API Key"
#   .\BW-GetSecret.ps1 -Name "OpenAI" -Field notes

param(
    [Parameter(Mandatory=$true)][string]$Name,
    [ValidateSet('password','notes')][string]$Field = 'password',
    [switch]$Raw,     # Skriv kun verdien
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { if (-not $Quiet -and -not $Raw) { Write-Host $m -ForegroundColor $c } }
function ERR($m) { if (-not $Raw) { Write-Host $m -ForegroundColor Red } }

if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) { ERR "BW_SESSION mangler. Kjør BW-Login.ps1 først."; exit 1 }

# Søk
$json = & bw list items --search $Name --session $env:BW_SESSION
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json) -or $json -eq "[]") {
    ERR "Ingen treff for '$Name'."
    exit 2
}

$items = $json | ConvertFrom-Json
$item  = if ($items -is [array]) { $items | Select-Object -First 1 } else { $items }
if (-not $item) { ERR "Ingen element funnet."; exit 3 }

$value = $null
switch ($Field) {
    'password' {
        if ($item.type -eq 1 -and $item.login -and $item.login.password) { $value = $item.login.password }
        else { ERR "Elementet har ikke login.password"; exit 4 }
    }
    'notes' {
        if ($item.notes) { $value = $item.notes } else { ERR "Elementet har ikke notes"; exit 4 }
    }
}

if ($Raw) { [Console]::Out.WriteLine($value) }
else {
    Say "Element: $($item.name)" 'Yellow'
    Say "Felt: $Field"
    Write-Output $value
}
