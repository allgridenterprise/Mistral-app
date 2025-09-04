#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Release','Debug')]
    [string]$Configuration = 'Release',
    [switch]$StartAfter,              # start GUI etter bygg
    [switch]$KeepLogs = $true,        # bevar Output\logs
    [string]$ProjectName = 'MistralApp' # forsøker først denne .csproj
)

function Ensure-AppSettingsJsonInPublish {
    param([string]$Configuration = 'Release')
    try {
        # Prosjektnivå (Scripts ligger under prosjektrot)
        $root = Split-Path -Path $PSScriptRoot -Parent
        # Standard WPF publish-sti
        $publishDir = Join-Path $root "bin\$Configuration\net8.0-windows\win-x64\publish"
        if (-not (Test-Path $publishDir)) {
            # Fallback hvis runtime er annet enn win-x64
            $publishDir = Join-Path $root "bin\$Configuration\net8.0-windows\publish"
        }
        if (-not (Test-Path $publishDir)) { return }

        $appsettingsPath = Join-Path $publishDir "appsettings.json"
        if (-not (Test-Path $appsettingsPath)) {
            $minimal = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
"@
            Set-Content -Path $appsettingsPath -Value $minimal -Encoding UTF8 -Force
            Write-Host "✓ Opprettet minimal appsettings.json i publish: $appsettingsPath"
        }
    } catch {
        Write-Warning "Kunne ikke sikre appsettings.json i publish: $($_.Exception.Message)"
    }
}

$ErrorActionPreference = 'Stop'

function W([string]$m,[string]$c='Cyan'){ Write-Host "==> $m" -ForegroundColor $c }
function OK([string]$m){ Write-Host "✓ $m" -ForegroundColor Green }
function WARN([string]$m){ Write-Host "⚠ $m" -ForegroundColor DarkYellow }
function ERR([string]$m){ Write-Host "✗ $m" -ForegroundColor Red }

# Finn prosjektrot (parent av Scripts)
$scriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptDir
$logsDir     = Join-Path $projectRoot 'Output\logs'
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$ts          = Get-Date -Format 'yyyyMMdd-HHmmss'
$pubLog      = Join-Path $logsDir "publish-OneClick-$ts.log"

try {
    # Finn .csproj
    $csproj = $null
    $preferred = Get-ChildItem -Path $projectRoot -Filter "$ProjectName.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($preferred) { $csproj = $preferred.FullName }
    if (-not $csproj) {
        $any = Get-ChildItem -Path $projectRoot -Filter '*.csproj' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($any) { $csproj = $any.FullName }
    }
    if (-not $csproj) { throw "Fant ingen .csproj under $projectRoot" }
    W ("Prosjekt: {0}" -f (Split-Path $csproj -Leaf)) 'DarkGray'

    # Stopp ev. prosesser
    W "Stopper ev. kjørende app-prosesser" 'Cyan'
    foreach($n in @('MistralApp','MistralSuite','Mistral')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; OK ("Stoppet {0} (PID {1})" -f $_.ProcessName, $_.Id) }
            catch { WARN ("Kunne ikke stoppe {0}: {1}" -f $_.ProcessName, $_.Exception.Message) }
        }
    }

    # Opprydding (bin/obj/publish i prosjektmappe, samt Output\)
    $projDir   = Split-Path $csproj -Parent
    W "Rydder artefakter (bin/obj/publish, Output)" 'Cyan'
    foreach($p in @(
        (Join-Path $projDir 'bin'),
        (Join-Path $projDir 'obj'),
        (Join-Path $projDir 'publish')
    )) {
        if (Test-Path $p) {
            try { Remove-Item $p -Recurse -Force -ErrorAction Stop; OK ("Slettet {0}" -f $p) }
            catch { WARN ("Sletting feilet: {0} ({1})" -f $p, $_.Exception.Message) }
        }
    }
    $outputDir = Join-Path $projectRoot 'Output'
    if (Test-Path $outputDir) {
        try {
            if ($KeepLogs -and (Test-Path (Join-Path $outputDir 'logs'))) {
                Get-ChildItem -LiteralPath $outputDir -Force | Where-Object { $_.Name -ne 'logs' } | ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {}
                }
                OK "Renset Output (bevarte logs)"
            } else {
                Remove-Item $outputDir -Recurse -Force -ErrorAction Stop
                OK "Slettet Output"
            }
        } catch { WARN ("Kunne ikke slette Output: {0}" -f $_.Exception.Message) }
    }
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

    # dotnet restore
    W "Gjenoppretter pakker" 'Cyan'
    $restoreOut = & dotnet restore $csproj 2>&1
    if ($LASTEXITCODE -ne 0) {
        $restoreOut | Out-File -FilePath $pubLog -Encoding UTF8
        ERR "dotnet restore feilet – se logg"; exit 1
    }

    # dotnet publish (WPF WinExe, self-contained, single-file)
    W "Publiserer app (win-x64, self-contained, single-file)" 'Cyan'
    $args = @(
        'publish', $csproj, '-c', $Configuration, '-r', 'win-x64',
        '--self-contained', 'true',
        '-p:PublishSingleFile=true',
        '-p:IncludeNativeLibrariesForSelfExtract=true',
        '-p:PublishReadyToRun=false'
    )
    $pubOut = & dotnet @args 2>&1
    try { $pubOut | Out-File -FilePath $pubLog -Encoding UTF8 } catch {}

    if ($LASTEXITCODE -ne 0) {
        ERR "dotnet publish feilet – se logg:"
        $pubOut | Select-Object -Last 50 | ForEach-Object { Write-Host $_ -ForegroundColor DarkRed }
        Write-Host "Logg: $pubLog" -ForegroundColor DarkGray
        exit 1
    }
    OK ("Publish fullført. Logg: {0}" -f $pubLog) 

    # Finn publish-katalog
    $pubDir = Join-Path $projDir ("bin\{0}\net8.0-windows\win-x64\publish" -f $Configuration)
    if (-not (Test-Path $pubDir)) {
        $pubDirObj = Get-ChildItem -Path $projDir -Filter 'publish' -Directory -Recurse -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($pubDirObj) { $pubDir = $pubDirObj.FullName }
    }
    if (-not (Test-Path $pubDir)) { throw "Fant ikke publish-katalog." }
    W ("Publish-katalog: {0}" -f $pubDir) 'DarkGray'

    # Kopier til Output\
    W "Kopierer artefakter til Output\" 'Cyan'
    Copy-Item -Path (Join-Path $pubDir '*') -Destination $outputDir -Recurse -Force -ErrorAction Stop
    $exe = Join-Path $outputDir "$($ProjectName).exe"
    if (-not (Test-Path $exe)) {
        $cand = Get-ChildItem -Path $outputDir -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cand) { $exe = $cand.FullName }
    }
    if (-not (Test-Path $exe)) { throw "Fant ikke .exe etter kopiering til Output\" }

    OK ("Ferdig. EXE: {0}" -f $exe)

    if ($StartAfter) {
        W "Starter applikasjonen" 'DarkGray'
        $wd = Split-Path -Parent $exe
        Start-Process -FilePath $exe -WorkingDirectory $wd | Out-Null
    }

    exit 0
}
catch {
    ERR ("Uventet feil: {0}" -f $_.Exception.Message)
    if (Test-Path $pubLog) { Write-Host ("Se logg: {0}" -f $pubLog) -ForegroundColor DarkGray }
    exit 1
}
