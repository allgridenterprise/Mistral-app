[CmdletBinding()]
param(
    [ValidateSet('3.11.2', '3.14.0')]
    [string]$Version = '3.11.2',
    [switch]$Quiet = $true
)

$ErrorActionPreference = 'Stop'

function W([string]$m, [string]$c = 'Cyan')
{
    Write-Host "==> $m" -ForegroundColor $c
}
function OK([string]$m)
{
    Write-Host "✓ $m" -ForegroundColor Green
}
function WARN([string]$m)
{
    Write-Host "⚠ $m" -ForegroundColor DarkYellow
}
function ERR([string]$m)
{
    Write-Host "✗ $m" -ForegroundColor Red
}

function Test-WixBin([string]$path)
{
    if (-not $path)
    {
        return $false
    }
    $candle = Join-Path $path 'candle.exe'
    $light = Join-Path $path 'light.exe'
    (Test-Path $candle) -and (Test-Path $light)
}

# 0) Informasjon
W ("Starter WiX Toolset installasjon (versjon: {0})" -f $Version) 'Magenta'
$expectedBins = @(
    'C:\Program Files (x86)\WiX Toolset v3.11\bin',
    'C:\Program Files (x86)\WiX Toolset v3.14\bin',
    'C:\Program Files\WiX Toolset v4\bin'
)

# 1) Sjekk om WiX allerede finnes
foreach ($b in $expectedBins)
{
    if (Test-WixBin $b)
    {
        OK ("WiX allerede installert: {0}" -f $b)
        $env:WIXBIN = $b
        $env:WIX = Split-Path $b -Parent
        try
        {
            setx WIXBIN $env:WIXBIN /M | Out-Null
            setx WIX    $env:WIX    /M | Out-Null
            OK "Miljøvariablene WIX/WIXBIN er satt permanent"
        }
        catch
        {
            WARN "Kunne ikke oppdatere permanente miljøvariabler: $( $_.Exception.Message )"
        }
        exit 0
    }
}

# 2) Last ned offisiell bootstrapper (uten MS Store)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$urls = switch ($Version)
{
    '3.11.2' {
        @('https://github.com/wixtoolset/wix3/releases/download/wix3112rtm/wix311.exe')
    }
    '3.14.0' {
        @('https://github.com/wixtoolset/wix3/releases/download/wix314rtm/wix314.exe')
    }
}
$tempDir = Join-Path $env:TEMP "WiX-Install"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$outFile = Join-Path $tempDir ("wix{0}.exe" -f $Version.Replace('.', ''))

$downloaded = $false
foreach ($u in $urls)
{
    try
    {
        W ("Laster ned WiX {0} fra {1}" -f $Version, $u) 'Cyan'
        Invoke-WebRequest -Uri $u -OutFile $outFile -UseBasicParsing -TimeoutSec 180
        if (Test-Path $outFile)
        {
            $downloaded = $true; break
        }
    }
    catch
    {
        WARN "Nedlasting feilet fra $u: $($_.Exception.Message)"
    }
}
if (-not $downloaded)
{
    ERR "Kunne ikke laste ned WiX installasjonsprogram."
    exit 2
}

# 3) Silent install
try
{
    $args = if ($Quiet)
    {
        '/quiet /norestart'
    }
    else
    {
        '/passive'
    }
    W ("Installerer WiX {0} ({1})..." -f $Version, ($Quiet ? 'quiet' : 'passive')) 'Cyan'
    $p = Start-Process -FilePath $outFile -ArgumentList $args -Wait -PassThru
    if ($p.ExitCode -ne 0)
    {
        ERR ("WiX installasjon feilet (exit {0})" -f $p.ExitCode)
        exit 3
    }
}
catch
{
    ERR "Kjøring av WiX-installasjon feilet: $( $_.Exception.Message )"
    exit 3
}

# 4) Finn installert bin
$found = $null
foreach ($b in $expectedBins)
{
    if (Test-WixBin $b)
    {
        $found = $b; break
    }
}
if (-not $found)
{
    ERR "Finner ikke candle.exe/light.exe etter installasjon."
    exit 4
}

# 5) Sett miljøvariabler for økt og permanent
$env:WIXBIN = $found
$env:WIX = Split-Path $found -Parent
try
{
    setx WIXBIN $env:WIXBIN /M | Out-Null
    setx WIX    $env:WIX    /M | Out-Null
}
catch
{
    WARN "Kunne ikke sette permanente miljøvariabler: $( $_.Exception.Message )"
}

OK ("WiX installert: {0}" -f $env:WIXBIN)
OK "WIX/WIXBIN miljøvariabler er satt"

# 6) Tips videre
Write-Host "`nDu kan nå kjøre MSI-bygg i kjeden. Åpne en ny PowerShell 7-økt og kjør: .\Start-Mistral.ps1" -ForegroundColor Gray
exit 0
