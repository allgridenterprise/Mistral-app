$ErrorActionPreference = 'Stop'

function W($m)
{
    Write-Host "==> $m" -ForegroundColor Cyan
}
function OK($m)
{
    Write-Host "✓ $m" -ForegroundColor Green
}
function WARN($m)
{
    Write-Host "⚠ $m" -ForegroundColor DarkYellow
}

# Init flagg
$okConfigured = $false

# Finn/lag kjente modulstier og sett Ctrl+Alt+V
$base = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$cands = @(
    (Join-Path $base 'PastePlain\settings.json'), # ny modul
    (Join-Path $base 'PastePlain\PastePlain.json'), # eldre modul
    (Join-Path $base 'settings.json')                # samlet settings
) | Where-Object { Test-Path $_ }

# Hvis ingen settings-filer finnes ennå, forsøk å opprette standard modul-mappe + settings.json
if (-not $cands -or $cands.Count -eq 0)
{
    $moduleDir = Join-Path $base 'PastePlain'
    if (-not (Test-Path $moduleDir))
    {
        New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null
    }
    $seed = @{
        enabled = $true
        properties = @{ activation_shortcut = @{ win = $false; alt = $true; ctrl = $true; shift = $false; key = 'V'; code = 86 } }
    }
    $target = Join-Path $moduleDir 'settings.json'
    $seed | ConvertTo-Json -Depth 10 | Set-Content -Path $target -Encoding UTF8
    OK "Opprettet: $target"
    $cands = @($target)
    $okConfigured = $true
}

# behold nåværende verdi av $okConfigured
$okConfigured = $okConfigured
foreach ($file in $cands)
{
    try
    {
        $json = Get-Content -Path $file -Raw | ConvertFrom-Json
    }
    catch
    {
        continue
    }
    $changed = $false

    # enabled
    if ($json.PSObject.Properties.Name -contains 'enabled')
    {
        if (-not $json.enabled)
        {
            $json.enabled = $true; $changed = $true
        }
    }

    # eldre skjema
    if ($json.PSObject.Properties.Name -contains 'pastePlainHotkey')
    {
        $hot = $json.pastePlainHotkey; if (-not $hot)
        {
            $hot = @{ }
        }
        $hot.win = $false; $hot.alt = $true; $hot.ctrl = $true; $hot.shift = $false; $hot.key = 'V'; $hot.code = 86
        $json.pastePlainHotkey = $hot; $changed = $true
    }

    # vanlig skjema
    if ($json.PSObject.Properties.Name -contains 'properties')
    {
        if (-not $json.properties)
        {
            $json | Add-Member -Name 'properties' -MemberType NoteProperty -Value (@{ })
        }
        if (-not ($json.properties.PSObject.Properties.Name -contains 'activation_shortcut'))
        {
            $json.properties.activation_shortcut = @{ win = $false; alt = $true; ctrl = $true; shift = $false; key = 'V'; code = 86 }
            $changed = $true
        }
        else
        {
            $act = $json.properties.activation_shortcut
            $act.win = $false; $act.alt = $true; $act.ctrl = $true; $act.shift = $false; $act.key = 'V'; $act.code = 86
            $changed = $true
        }
    }

    if ($changed)
    {
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $file -Encoding UTF8
        OK "Oppdatert Ctrl+Alt+V i: $file"
        $okConfigured = $true
    }
}

if (-not $okConfigured)
{
    WARN "Fant ingen skrivbar settings-fil – åpner modulen for manuell binding (trykk Ctrl+Alt+V i feltet)..."
    try
    {
        Start-Process 'powertoys://' -ArgumentList 'settings?module=PastePlain' | Out-Null
    }
    catch
    {
    }
}

# Restart PowerToys med sikre stier
Get-Process -Name PowerToys -ErrorAction SilentlyContinue | ForEach-Object { try
{
    $_ | Stop-Process -Force
}
catch
{
} }
Start-Sleep -Seconds 2
$runnerCandidates = @(
    (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'),
    (Join-Path ${env:LOCALAPPDATA} 'PowerToys\PowerToys.exe'),
    (Join-Path ${env:LOCALAPPDATA} 'Programs\PowerToys\PowerToys.exe'),
    (Join-Path ${env:LOCALAPPDATA} 'Microsoft\WindowsApps\PowerToys.exe')
)
$runnerExe = $runnerCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
try
{
    if ($runnerExe)
    {
        $wd = Split-Path -Parent $runnerExe
        if ($wd)
        {
            Start-Process -FilePath $runnerExe -WorkingDirectory $wd | Out-Null
        }
        else
        {
            Start-Process -FilePath $runnerExe | Out-Null
        }
        OK "PowerToys startet på nytt"
    }
    else
    {
        WARN "Fant ingen PowerToys.exe i kjente stier – start manuelt fra Start-meny."
    }
}
catch
{
    WARN "Kunne ikke starte PowerToys: $( $_.Exception.Message )"
}
