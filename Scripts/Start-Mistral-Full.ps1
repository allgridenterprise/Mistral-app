#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Release','Debug')]
    [string]$Configuration = 'Release',
    [switch]$StartAfter,              # start GUI etter bygg
    [switch]$KeepLogs = $true,        # bevar Output\logs
    [string]$ProjectName = 'MistralApp' # forsøker først denne .csproj
)

$ErrorActionPreference = 'Stop'

# Start GUI som standard etter vellykket publish hvis ikke eksplisitt satt
if (-not $PSBoundParameters.ContainsKey('StartAfter')) { $StartAfter = $true }

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

# Finn .csproj
$csproj = $null
$preferred = Get-ChildItem -Path $projectRoot -Filter "$ProjectName.csproj" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($preferred) { $csproj = $preferred.FullName }
if (-not $csproj) {
    $any = Get-ChildItem -Path $projectRoot -Filter '*.csproj' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($any) { $csproj = $any.FullName }
}
if (-not $csproj) { ERR "Fant ingen .csproj under $projectRoot"; exit 1 }
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
    try { $restoreOut | Out-File -FilePath $pubLog -Encoding UTF8 } catch {}
    ERR "dotnet restore feilet – se logg"; exit 1
}

# dotnet publish (WPF WinExe, self-contained, folder layout for stability)
W "Publiserer app (win-x64, self-contained, folder layout)" 'Cyan'
$args = @(
    'publish', $csproj, '-c', $Configuration, '-r', 'win-x64',
    '--self-contained', 'true',
    '-p:PublishSingleFile=false',
    '-p:IncludeNativeLibrariesForSelfExtract=false',
    '-p:PublishReadyToRun=false',
    '-p:Platform=x64'
)
$pubOut = & dotnet @args 2>&1
try { $pubOut | Out-File -FilePath $pubLog -Encoding UTF8 } catch {}

if ($LASTEXITCODE -ne 0) {
    ERR "dotnet publish feilet – siste linjer:"
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
if (-not (Test-Path $pubDir)) { ERR "Fant ikke publish-katalog."; exit 1 }
W ("Publish-katalog: {0}" -f $pubDir) 'DarkGray'

# Kopier til Output\
W "Kopierer artefakter til Output\" 'Cyan'
Copy-Item -Path (Join-Path $pubDir '*') -Destination $outputDir -Recurse -Force -ErrorAction Stop
$exe = Join-Path $outputDir "$($ProjectName).exe"
if (-not (Test-Path $exe)) {
    $cand = Get-ChildItem -Path $outputDir -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cand) { $exe = $cand.FullName }
}
if (-not (Test-Path $exe)) { ERR "Fant ikke .exe etter kopiering til Output\"; exit 1 }

OK ("Ferdig. EXE: {0}" -f $exe)

# Sørg for at Output\appsettings.json finnes og er gyldig JSON
try {
    $wd = Split-Path -Parent $exe
    $appCfg = Join-Path $wd 'appsettings.json'
    $needsWrite = $false
    if (-not (Test-Path $appCfg)) {
        $needsWrite = $true
    } else {
        try {
            # Valider JSON
            $null = Get-Content -Path $appCfg -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            WARN ("Ugyldig appsettings.json oppdaget – genererer minimal standardfil: {0}" -f $appCfg)
            $needsWrite = $true
        }
    }
    if ($needsWrite) {
        $defaultJson = @'
{
  "Secrets": {
    "MISTRAL_API_KEY": "",
    "OPENAI_API_KEY": "",
    "AIRTABLE_API_KEY": "",
    "AIRTABLE_BASE_ID": "",
    "AIRTABLE_TABLE": "",
    "MAKE_WEBHOOK_URL": "",
    "Map": {
      "MISTRAL_API_KEY": "Mistral API Key",
      "OPENAI_API_KEY": "OpenAI API Key",
      "AIRTABLE_API_KEY": "Airtable API Key",
      "AIRTABLE_BASE_ID": "Airtable Base ID",
      "AIRTABLE_TABLE": "Airtable Table",
      "MAKE_WEBHOOK_URL": "Make Webhook URL"
    }
  }
}
'@
        $defaultJson | Set-Content -Path $appCfg -Encoding UTF8
        OK ("Opprettet/erstattet appsettings.json: {0}" -f $appCfg)
    }
} catch {
    WARN ("Klarte ikke å sikre appsettings.json: {0}" -f $_.Exception.Message)
}

if ($StartAfter) {
    W "Starter applikasjonen" 'DarkGray'
    $wd = Split-Path -Parent $exe

    # Aktiver LocalDumps for MistralApp.exe (minidump ved tidlig native-krasj)
    try {
        $dumpKey = 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting\LocalDumps\MistralApp.exe'
        if (-not (Test-Path $dumpKey)) { New-Item -Path $dumpKey -Force | Out-Null }
        New-ItemProperty -Path $dumpKey -Name DumpType -Value 2 -PropertyType DWord -Force | Out-Null    # 2 = Full dump
        New-ItemProperty -Path $dumpKey -Name DumpCount -Value 5 -PropertyType DWord -Force | Out-Null
        $ld = Join-Path $env:LOCALAPPDATA 'CrashDumps'
        if (-not (Test-Path $ld)) { New-Item -ItemType Directory -Path $ld -Force | Out-Null }
        New-ItemProperty -Path $dumpKey -Name DumpFolder -Value $ld -PropertyType ExpandString -Force | Out-Null
    } catch { WARN ("Kunne ikke konfigurere LocalDumps: {0}" -f $_.Exception.Message) }

    try {
        $p = Start-Process -FilePath $exe -WorkingDirectory $wd -PassThru -ErrorAction Stop
        # Vent inntil 6 sekunder – hvis prosessen dør raskt, rapporter
        try { Wait-Process -Id $p.Id -Timeout 6 -ErrorAction SilentlyContinue } catch {}
        if ($p.HasExited) {
            ERR ("Applikasjonen avsluttet umiddelbart (ExitCode {0}). Viser runtime-logg om tilgjengelig..." -f $p.ExitCode)

            # 1) Prøv ved siden av EXE
            $rtLogs = Get-ChildItem -Path (Join-Path $wd 'logs') -Filter 'runtime-*.log' -File -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $printed = $false
            if ($rtLogs) {
                W ("Hale av {0}:" -f $rtLogs.Name) 'DarkGray'
                Get-Content -Path $rtLogs.FullName -Tail 120 | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
                $printed = $true
            }

            # 2) Prøv LocalAppData\MistralSuite\logs
            if (-not $printed) {
                $localLogDir = Join-Path $env:LOCALAPPDATA 'MistralSuite\logs'
                $rtLocal = Get-ChildItem -Path $localLogDir -Filter 'runtime-*.log' -File -ErrorAction SilentlyContinue |
                           Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($rtLocal) {
                    W ("Hale av {0}:" -f $rtLocal.Name) 'DarkGray'
                    Get-Content -Path $rtLocal.FullName -Tail 120 | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
                    $printed = $true
                }
            }

            # 3) Fallback: vis relevante Application‑eventer de siste 5 minuttene
            if (-not $printed) {
                WARN "Fant ingen runtime-logger. Viser relevante Windows Application‑eventer (siste 5 min)..."
                try {
                    $since = (Get-Date).AddMinutes(-5)
                    $events = Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$since } -ErrorAction SilentlyContinue |
                              Where-Object {
                                  ($_.ProviderName -in @('.NET Runtime','Application Error')) -or
                                  ($_.Message -like '*MistralApp.exe*')
                              } | Select-Object -Last 10
                    if ($events) {
                        $events | ForEach-Object {
                            Write-Host ("[{0}] {1} - {2}" -f $_.TimeCreated, $_.ProviderName, $_.Id) -ForegroundColor DarkGray
                            Write-Host ($_.Message) -ForegroundColor DarkGray
                            Write-Host "----" -ForegroundColor DarkGray
                        }
                    } else {
                        WARN "Ingen relevante Application‑eventer funnet"
                    }
                } catch {
                    WARN ("Kunne ikke lese Application‑logg: {0}" -f $_.Exception.Message)
                }
            }

            # 4) Siste fallback: forsøk å kjøre DLL via dotnet og vis tekstlig output
            if (-not $printed) {
                $dll = Join-Path $wd 'MistralApp.dll'
                if (-not (Test-Path $dll)) {
                    $dllCand = Get-ChildItem -Path $wd -Filter '*.dll' -File -ErrorAction SilentlyContinue |
                               Where-Object { $_.Name -like 'MistralApp*.dll' } |
                               Select-Object -First 1
                    if ($dllCand) { $dll = $dllCand.FullName }
                }
                if (Test-Path $dll) {
                    WARN "Prøver å starte via 'dotnet <dll>' for å fange evt. managed-feil..."
                    try {
                        $dotnetOut = & dotnet $dll 2>&1
                        $dotnetOut | Select-Object -Last 80 | ForEach-Object { Write-Host $_ -ForegroundColor DarkRed }
                    } catch {
                        WARN ("dotnet <dll> feilet: {0}" -f $_.Exception.Message)
                    }
                }
            }
        } else {
            OK ("Prosess startet (PID {0})" -f $p.Id)
        }
    } catch {
        ERR ("Kunne ikke starte applikasjonen: {0}" -f $_.Exception.Message)
    }
}

exit 0







