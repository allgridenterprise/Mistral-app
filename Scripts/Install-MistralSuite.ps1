#requires -Version 7.0
# Install-MistralSuite.ps1
# Ett skript for full opprydding, avinstallasjon, bygg, publish og Inno Setup-installasjon.

param(
    [ValidateSet('Clean','Build','Full')]
    [string]$Action,
    [string]$Configuration,
    [switch]$Force,              # Hopper over bekreftelser (ja til alt)
    [switch]$Silent,             # Minimalt med output/ingen stopp for spørsmål
    [switch]$NoInno,             # Hopp over Inno Setup kompilering
    [switch]$RunInstaller,       # Kjør installer etter kompilering
    [switch]$SkipUninstall,      # Ikke forsøk å avinstallere eksisterende
    [switch]$KeepApiKeys,        # Behold API-nøkler i appsettings.json (standard: true)
    [string]$AppDisplayName,     # Navn slik det vises i Programmer og Funksjoner
    [string]$ExeName,            # Hoved-EXE i publish
    [switch]$ConfigureBitwardenSSO,              # Konfigurer Bitwarden SSO under installasjon
    [string]$BitwardenEmail,     # E-post for Bitwarden SSO
    [int]$SessionTimeout,        # Session timeout i minutter (24 timer)
    [switch]$AutoLaunch          # Start GUI etter publish/install
)

# Sett standardverdier dersom ikke oppgitt
if (-not $PSBoundParameters.ContainsKey('Action')) { $Action = 'Full' }
if (-not $PSBoundParameters.ContainsKey('Configuration')) { $Configuration = 'Release' }
if (-not $PSBoundParameters.ContainsKey('KeepApiKeys')) { $KeepApiKeys = $true }
if (-not $PSBoundParameters.ContainsKey('AppDisplayName')) { $AppDisplayName = 'Mistral Suite' }
if (-not $PSBoundParameters.ContainsKey('ExeName')) { $ExeName = 'MistralApp.exe' }
if (-not $PSBoundParameters.ContainsKey('BitwardenEmail')) { $BitwardenEmail = 'dan@allgrid.com' }
if (-not $PSBoundParameters.ContainsKey('SessionTimeout')) { $SessionTimeout = 1440 }

# Installer metadata (kanonisk)
$Script:InstallerName    = 'Install-MistralSuite.ps1'
$Script:InstallerVersion = '2.0.0'
$Script:InstallerUpdated = '2025-08-26'

function Assert-CanonicalScript {
    try {
        $canonical = $MyInvocation.MyCommand.Path
        $rootPath  = Resolve-Root
        $candidates = Get-ChildItem -Path $rootPath -Filter 'Install-MistralSuite.ps1' -Recurse -ErrorAction SilentlyContinue
        if ($null -eq $candidates -or $candidates.Count -le 1) {
            OK "Installer: $canonical (kanonisk)"
            return
        }
        $others = $candidates | Where-Object { $_.FullName -ne $canonical }
        if ($others -and $others.Count -gt 0) {
            WARN "Fant ${($others.Count)} andre Install-MistralSuite.ps1 i prosjektet:"
            foreach ($o in $others) { Write-Host "  - $($o.FullName)" -ForegroundColor DarkYellow }
            OK "Bruker KUN: $canonical"
        } else {
            OK "Installer: $canonical (kanonisk)"
        }
    }
    catch {
        WARN "Kunne ikke verifisere kanonisk installer: $($_.Exception.Message)"
    }
}

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$exitCode = 0
$progressPoints = @()

# ========= Hjelpere =========
function W([string]$msg,[string]$color='Cyan'){ if(-not $Silent){ Write-Host "`n==> $msg" -ForegroundColor $color } }
function OK([string]$msg){ if(-not $Silent){ Write-Host "✓ $msg" -ForegroundColor Green } }
function WARN([string]$msg){ if(-not $Silent){ Write-Host "⚠ $msg" -ForegroundColor DarkYellow } }
function ERR([string]$msg){ Write-Host "✗ $msg" -ForegroundColor Red }
function PROGRESS([string]$step) { $script:progressPoints += $step; W "[$($progressPoints.Count)/$totalSteps] $step" 'Blue' }

function Show-LatestPublishLog {
    param([int]$Tail = 80)
    try {
        $logDir = Join-Path $root "Output\logs"
        if (-not (Test-Path $logDir)) {
            WARN "Loggmappe finnes ikke: $logDir"
            return
        }

        # Prøv å finne publish-*.log først, ellers fall tilbake til nyeste fil
        $latest = Get-ChildItem -Path $logDir -Filter 'publish-*.log' -File -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            $latest = Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if (-not $latest) {
            WARN "Fant ingen publish-loggfiler i $logDir"
            return
        }

        W "Siste publish-logg: $($latest.FullName)" 'DarkGray'
        $lines = Get-Content -Path $latest.FullName -Tail $Tail -ErrorAction SilentlyContinue
        if ($null -ne $lines) {
            Write-Host "----- Siste $Tail linjer fra $($latest.Name) -----" -ForegroundColor DarkGray
            $lines | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
        }
    } catch {
        WARN "Kunne ikke lese siste publish-logg: $($_.Exception.Message)"
    }
}

function Resolve-WixBin {
    param()
    try {
        function Test-WixBinPath([string]$path) {
            if (-not $path) { return $false }
            $candle = Join-Path $path 'candle.exe'
            $light  = Join-Path $path 'light.exe'
            return (Test-Path $candle) -and (Test-Path $light)
        }

        # 1) Sjekk miljøvariabel først
        if ($env:WIXBIN -and (Test-WixBinPath $env:WIXBIN)) {
            $script:WixBin = $env:WIXBIN
            OK ("WIXBIN funnet (env): {0}" -f $script:WixBin)
            return
        }

        # 2) Kjente installasjonsstier
        $candidates = @(
            'C:\Program Files (x86)\WiX Toolset v3.11\bin',
            'C:\Program Files (x86)\WiX Toolset v3.14\bin',
            'C:\Program Files\WiX Toolset v4\bin',
            "$env:ProgramFiles (x86)\WiX Toolset v3.11\bin",
            "$env:ProgramFiles (x86)\WiX Toolset v3.14\bin",
            "$env:ProgramFiles\WiX Toolset v4\bin"
        ) | Where-Object { $_ -and (Test-Path $_) }

        foreach ($p in $candidates) {
            if (Test-WixBinPath $p) {
                $script:WixBin = $p
                $env:WIXBIN = $p
                $env:WIX = Split-Path $p -Parent
                OK ("WIXBIN valgt: {0}" -f $script:WixBin)
                return
            }
        }

        # 3) Ikke funnet: ikke auto‑installer – deaktiver MSI nå for å unngå heng
        WARN "WiX Toolset ikke funnet – hopper over auto‑install og deaktiverer MSI i denne kjøringen."
        if (Test-Path Env:WIXBIN) { Remove-Item Env:WIXBIN -Force -ErrorAction SilentlyContinue }
        if (Test-Path Env:WIX)    { Remove-Item Env:WIX    -Force -ErrorAction SilentlyContinue }
        $script:WixBin = $null
        # Tving NoInno=true i dette skriptet slik at Inno/installer hoppes over
        try { Set-Variable -Name NoInno -Scope Script -Value $true -Force } catch {}
        return
    } catch {
        WARN "Resolve-WixBin feilet: $($_.Exception.Message)"
        if (Test-Path Env:WIXBIN) { Remove-Item Env:WIXBIN -Force -ErrorAction SilentlyContinue }
        if (Test-Path Env:WIX)    { Remove-Item Env:WIX    -Force -ErrorAction SilentlyContinue }
        $script:WixBin = $null
    }
}

function Invoke-BuildProfileFix {
    param([switch]$EnableInstaller)
    try {
        $fix = Join-Path $root 'Scripts\Fix-BuildProfile.ps1'
        if (Test-Path $fix) {
            W ("Forbereder build-profil via Fix-BuildProfile.ps1 (EnableInstaller={0})" -f [bool]$EnableInstaller) 'Cyan'
            # Finn csproj robust – søk rekursivt fra prosjektrot
            $csprojItem = Get-ChildItem -Path $root -Filter 'MistralApp.csproj' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $csprojItem) {
                WARN "Fant ikke MistralApp.csproj – hopper over Fix-BuildProfile"
                return
            }
            # Kall eksplisitt (robust mot mellomrom i stier)
            try {
                & $fix -CsprojPath $csprojItem.FullName -EnableInstaller:([bool]$EnableInstaller)
                if ($LASTEXITCODE -eq 0) {
                    OK "Build-profil er oppdatert (csproj patchet)"
                } else {
                    WARN "Fix-BuildProfile.ps1 returnerte kode $LASTEXITCODE – fortsetter likevel"
                }
            } catch {
                WARN "Fix-BuildProfile.ps1 feilet: $($_.Exception.Message)"
            }
        } else {
            WARN "Fix-BuildProfile.ps1 ikke funnet – hopper over build-profil patch"
        }
    } catch {
        WARN "Build-profil patch feilet: $($_.Exception.Message)"
    }
}

function Remove-OutputFolder {
    W "Sletter Output-mappen for å sikre ren installasjon" 'Magenta'
    $outputPath = Join-Path $root "Output"
    if (Test-Path $outputPath) {
        try {
            Remove-Item $outputPath -Recurse -Force -ErrorAction Stop
            OK "Output-mappen er slettet: $outputPath"
        } catch {
            WARN "Kunne ikke slette Output-mappen: $outputPath"
        }
    } else {
        WARN "Fant ingen Output-mappe å slette."
    }
    # Opprett Output-mappen på nytt (tom)
    try {
        New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
        OK "Output-mappen er opprettet på nytt: $outputPath"
    } catch {
        WARN "Kunne ikke opprette Output-mappen: $outputPath"
    }
}

function Remove-AllOutputFolders {
    W "Sletter alle Output-mapper for å sikre ren installasjon (bevarer logs)" 'Magenta'
    $outputPaths = @(
        (Join-Path $root "Output"),
        (Join-Path $root "Setup\Output")
    )
    $deletedCount = 0
    foreach ($outputPath in $outputPaths) {
        if (Test-Path $outputPath) {
            try {
                if ($outputPath -like "*\Output" -and (Test-Path (Join-Path $outputPath "logs"))) {
                    # Bevar logs: slett alt annet enn logs
                    Get-ChildItem -LiteralPath $outputPath -Force | Where-Object { $_.Name -ne 'logs' } | ForEach-Object {
                        try {
                            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                        } catch {
                            WARN "Kunne ikke slette: $($_.FullName) ($($_.Exception.Message))"
                        }
                    }
                    OK "Renset Output (bevarte logs): $outputPath"
                    $deletedCount++
                } else {
                    Remove-Item $outputPath -Recurse -Force -ErrorAction Stop
                    OK "Output-mappen er slettet: $outputPath"
                    $deletedCount++
                }
            } catch {
                WARN "Kunne ikke slette Output-mappen: $outputPath ($($_.Exception.Message))"
            }
        } else {
            WARN "Fant ingen Output-mappe å slette: $outputPath"
        }
    }
    if ($deletedCount -gt 0) {
        OK "Ryddet totalt $deletedCount Output-mapper (logs bevart der det fantes)."
    } else {
        WARN "Ingen Output-mapper funnet for sletting."
    }

    # Opprett alle Output-mapper på nytt (logs-mappe beholdes hvis den fantes)
    foreach ($outputPath in $outputPaths) {
        try {
            if (-not (Test-Path $outputPath)) {
                New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
                OK "Output-mappen er opprettet på nytt: $outputPath"
            } else {
                # Sørg for at logs-mappen finnes
                if ($outputPath -like "*\Output") {
                    $logs = Join-Path $outputPath "logs"
                    if (-not (Test-Path $logs)) { New-Item -ItemType Directory -Path $logs -Force | Out-Null }
                }
            }
        } catch {
            WARN "Kunne ikke opprette Output-mappen: $outputPath"
        }
    }
}

function Remove-ChangeHistoryFiles {
    W "SPESIALRENS: Fjerner ALL endringshistorikk og versjonsfiler" 'Red'
    $historyPatterns = @(
        '*.bak', '*.old', '*.backup', '*.tmp', 
        '*.[0-9][0-9][0-9][0-9]*[0-9][0-9]*.bak',
        '*_backup_*', '*-backup-*', '*.BACKUP.*', 
        '*.history', '*.versjon*', '*.version*',
        '*.r[0-9]*', '*.REMOTE.*', '*.LOCAL.*', '*.BASE.*'
    )
    
    $removedCount = 0
    foreach($pattern in $historyPatterns) {
        Get-ChildItem -Path $root -Recurse -Include $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $fileName = $_.FullName
                Remove-Item $fileName -Force -ErrorAction Stop
                Write-Host "      ENDRINGSHISTORIKK SLETTET: $($_.Name)" -ForegroundColor Magenta
                $removedCount++
            }
            catch {
                WARN "Kunne ikke slette endringshistorikk: $($_.FullName)"
            }
        }
    }
    
    if($removedCount -gt 0) { 
        OK "Fjernet $removedCount endringshistorikkfiler - kun originalfiler gjenstår"
    }
    else {
        OK "Ingen endringshistorikkfiler funnet"
    }
}

function Remove-OverlappingScripts {
    W "Fjerner overlappende bygge- og installeringsscript PERMANENT" 'Red'
    $scriptsToDelete = @(
        'Build-MistralApp.ps1', 'Cleanup-MistralProject.ps1', 'ProjectAutoCleanup.ps1', 
        'RemoveLegacyFiles.ps1', 'Complete-MistralSuite-Manager.ps1'
    )
    $deletedCount = 0
    foreach($script in $scriptsToDelete){
        $scriptPath = Join-Path $root $script
        if(Test-Path $scriptPath){
            if($Force -or $Silent -or (Ask-YesNo "Slette $script permanent?" -defaultYes)){
                try{
                    Remove-Item $scriptPath -Force -ErrorAction Stop
                    OK "SLETTET PERMANENT: $script"
                    $deletedCount++
                }
                catch{ 
                    ERR "Feil ved sletting av $script : $($_.Exception.Message)" 
                }
            }
        }
    }
    if($deletedCount -gt 0){ OK "Slettet $deletedCount overlappende script permanent" } 
    else { OK "Ingen overlappende script funnet" }
}

# Fjerner dupliserte hjelpefunksjoner her

function Ask-YesNo([string]$q,[switch]$defaultYes){
    if($Force -or $Silent){ return $true }
    $def = ($defaultYes) ? 'Y/n' : 'y/N'
    $ans = Read-Host "$q ($def)"
    if([string]::IsNullOrWhiteSpace($ans)){ return [bool]$defaultYes }
    return @('y','yes','j','ja') -contains $ans.ToLowerInvariant()
}

function Create-MinimalProject {
    param([string]$path)

    W "Oppretter minimal MistralApp.csproj..." 'Cyan'

    $minimalProject = @'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <UseWPF>true</UseWPF>
    <AssemblyName>MistralApp</AssemblyName>
    <RootNamespace>MistralApp</RootNamespace>
    <ApplicationManifest>app.manifest</ApplicationManifest>
    <StartupObject>MistralApp.App</StartupObject>
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="8.0.0" />
    <PackageReference Include="System.Net.Http" Version="4.3.4" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>

  <ItemGroup>
    <None Update="appsettings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>

</Project>
'@

    try {
        Set-Content -Path $path -Value $minimalProject -Encoding UTF8
        OK "Opprettet $path"

        # Opprett også en minimal App.xaml hvis den ikke finnes
        $appXamlPath = Join-Path (Split-Path $path -Parent) "App.xaml"
        if(-not (Test-Path $appXamlPath)) {
            $appXaml = @'
<Application x:Class="MistralApp.App"
             xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             StartupUri="MainWindow.xaml">
</Application>
'@
            Set-Content -Path $appXamlPath -Value $appXaml -Encoding UTF8
            OK "Opprettet App.xaml"
        }

        # Opprett App.xaml.cs
        $appCsPath = Join-Path (Split-Path $path -Parent) "App.xaml.cs"
        if(-not (Test-Path $appCsPath)) {
            $appCs = @'
using System.Windows;

namespace MistralApp
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
        }
    }
}
'@
            Set-Content -Path $appCsPath -Value $appCs -Encoding UTF8
            OK "Opprettet App.xaml.cs"
        }

        # Opprett MainWindow.xaml hvis den ikke finnes
        $mainWindowPath = Join-Path (Split-Path $path -Parent) "MainWindow.xaml"
        if(-not (Test-Path $mainWindowPath)) {
            $mainWindow = @'
<Window x:Class="MistralApp.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Mistral Suite" Height="600" Width="800">
    <Grid>
        <TextBlock Text="Mistral Suite - Minimal App" 
                   HorizontalAlignment="Center" 
                   VerticalAlignment="Center" 
                   FontSize="24"/>
    </Grid>
</Window>
'@
            Set-Content -Path $mainWindowPath -Value $mainWindow -Encoding UTF8
            OK "Opprettet MainWindow.xaml"
        }

        # Opprett MainWindow.xaml.cs
        $mainWindowCsPath = Join-Path (Split-Path $path -Parent) "MainWindow.xaml.cs"
        if(-not (Test-Path $mainWindowCsPath)) {
            $mainWindowCs = @'
using System.Windows;

namespace MistralApp
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
        }
    }
}
'@
            Set-Content -Path $mainWindowCsPath -Value $mainWindowCs -Encoding UTF8
            OK "Opprettet MainWindow.xaml.cs"
        }

    } catch {
        throw "Kunne ikke opprette prosjektfil: $($_.Exception.Message)"
    }
}

function Resolve-Root {
    if ($PSScriptRoot) { return (Split-Path $PSScriptRoot -Parent) }
    $cwd = (Get-Location).Path
    if ($cwd -match '([\\/]|^)Scripts([\\/]|$)') { return (Split-Path $cwd -Parent) }
    return $cwd
}

$root = Resolve-Root
$OutputDir = Join-Path $root 'Output'
$totalSteps = 7 # Total antall hovedtrinn i prosessen

function Stop-Processes {
    param([string[]]$names = @('MistralApp','MistralSuite','Mistral'))
    W "Stopper ev. kjørende prosesser" 'Cyan'
    foreach($n in $names){
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try{ Stop-Process -Id $_.Id -Force -ErrorAction Stop; OK "Stoppet $($_.ProcessName) (PID $($_.Id))" }
            catch{ WARN "Kunne ikke stoppe $($_.ProcessName): $($_.Exception.Message)" }
        }
    }
}

function Cleanup-Artifacts {
    W "Rydder artefakter (bin/obj/publish, Output, temp, duplikater)" 'Cyan'
    $paths = @(
        (Join-Path $root 'bin'), (Join-Path $root 'obj'), (Join-Path $root 'publish'),
        (Join-Path $root 'installer\Output'), (Join-Path $root 'packages'), 
        (Join-Path $root 'TestResults'), (Join-Path $root '.vs'), $OutputDir
    )
    foreach($p in $paths){
        if(Test-Path $p){ 
            try{ Remove-Item $p -Recurse -Force -ErrorAction Stop; OK "Slettet $p" } 
            catch { WARN "Sletting feilet: $p ($($_.Exception.Message))" } 
        }
    }
    OK "Output-mappen og andre artefakter er slettet og klar for regenerering."
}

function Get-UninstallEntries {
    param([string]$nameLike)
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $res = @()
    foreach($r in $roots){
        if(Test-Path $r){
            Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
                try{
                    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                    if($p.DisplayName -and ($p.DisplayName -like "*$nameLike*")){
                        $res += [pscustomobject]@{
                            DisplayName     = $p.DisplayName
                            DisplayVersion  = $p.DisplayVersion
                            UninstallString = $p.UninstallString
                            InstallLocation = $p.InstallLocation
                            PSPath          = $_.PSPath
                        }
                    }
                } catch {}
            }
        }
    }
    return $res
}

function Uninstall-Existing {
    param([string]$nameLike)
    W "Avinstallerer tidligere versjoner av '$nameLike'" 'Cyan'
    $entries = Get-UninstallEntries -nameLike $nameLike
    if(-not $entries -or $entries.Count -eq 0){ OK "Ingen eksisterende installasjon funnet"; return }
    foreach($e in $entries){
        Write-Host ("  - {0} {1}" -f $e.DisplayName, $e.DisplayVersion) -ForegroundColor Yellow
        if(Ask-YesNo "Avinstallere denne nå?" -defaultYes){
            $cmd = $e.UninstallString
            if([string]::IsNullOrWhiteSpace($cmd)){ WARN "Mangler UninstallString"; continue }
            try{
                if($cmd.ToLower().Contains('msiexec')){
                    $args = $cmd; if(-not $args.ToLower().Contains('/x')){ $args = "$args /x" }
                    $args = "$args /qn /norestart"
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $args" -Wait -WindowStyle Hidden
                } else {
                    $exe = $null; $rest = ""
                    if($cmd.StartsWith('"')){ $exe = $cmd.Split('"')[1]; $rest = $cmd.Substring($exe.Length+2) } 
                    else { $parts = $cmd.Split(' ',2); $exe=$parts[0]; if($parts.Count -gt 1){$rest=$parts[1]} }
                    if(Test-Path $exe){ Start-Process -FilePath $exe -ArgumentList "/VERYSILENT /NORESTART" -Wait -WindowStyle Hidden }
                    else { WARN "Uninstaller ikke funnet: $exe" }
                }
                OK "Avinstallert: $($e.DisplayName)"
            } catch { WARN "Feil ved avinstallasjon av $($e.DisplayName): $($_.Exception.Message)" }
        }
    }
    # Slett rester
    $pfTargets = @((Join-Path ${env:ProgramFiles} $nameLike), (Join-Path ${env:ProgramFiles(x86)} $nameLike)) | Where-Object { $_ -ne $null }
    foreach($pf in $pfTargets){
        if(Test-Path $pf){ try{ Remove-Item $pf -Recurse -Force -ErrorAction Stop; OK "Slettet restmappe: $pf" } 
        catch { WARN "Kunne ikke slette $pf : $($_.Exception.Message)" } }
    }
}

function Find-Project {
    W "Søker etter prosjektfil..." 'Yellow'

    # Søk spesifikt etter MistralApp.csproj først
    $csproj = Get-ChildItem -Path $root -Filter 'MistralApp.csproj' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if(-not $csproj) { 
        W "MistralApp.csproj ikke funnet, søker etter andre .csproj-filer..." 'Yellow'
        $csproj = Get-ChildItem -Path $root -Filter '*.csproj' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 
    }

    if(-not $csproj) { 
        ERR "Fant ingen .csproj-filer under $root"
        ERR "Tilgjengelige filer i rot-katalogen:"
        Get-ChildItem -Path $root | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor DarkYellow }

        # Tilby å opprette en minimal prosjektfil
        if(Ask-YesNo "Vil du opprette en minimal MistralApp.csproj?" -defaultYes) {
            $projPath = Join-Path $root "MistralApp.csproj"
            Create-MinimalProject -path $projPath
            $csproj = Get-Item $projPath
        } else {
            throw "Ingen .NET-prosjektfiler funnet. Opprett MistralApp.csproj eller plasser scriptet i riktig mappe." 
        }
    }

    # Valider prosjektfilen
    $projPath = $csproj.FullName
    OK "Fant prosjektfil: $([IO.Path]::GetFileName($projPath))"

    # GHOST HUNTER: Finn XML-interferenser
    try {
        $content = Get-Content $projPath -Raw
        W "Analyserer XML-struktur for interferenser..." 'Yellow'

        # Tell <Project> tags
        $projectTags = ($content | Select-String -Pattern '<Project' -AllMatches).Matches.Count
        $closingProjectTags = ($content | Select-String -Pattern '</Project>' -AllMatches).Matches.Count

        if($projectTags -gt 1) {
            ERR "FUNNET INTERFERENS: $projectTags <Project> tags funnet (skal være 1)"
            ERR "Dupliserte Project-elementer detektert!"

            # Vis linjene rundt hvert <Project> tag
            $lines = $content -split "`n"
            for($i = 0; $i -lt $lines.Count; $i++) {
                if($lines[$i] -match '<Project') {
                    ERR "  Linje $($i+1): $($lines[$i].Trim())"
                }
            }

            # Tilby å reparere
            if(Ask-YesNo "Vil du automatisk reparere prosjektfilen?" -defaultYes) {
                W "Reparerer prosjektfil..." 'Magenta'
                Repair-ProjectFile -path $projPath
            } else {
                throw "Prosjektfilen har ugyldig XML-struktur og må repareres manuelt"
            }
        } else {
            OK "XML-struktur ser riktig ut ($projectTags Project-tag)"
        }

        # Test XML-parsing
        try {
            [xml]$xmlTest = $content
            OK "XML er gyldig og kan parses"
        } catch {
            ERR "XML-parsing feilet: $($_.Exception.Message)"

            # DEEP GHOST DETECTION: Vis faktisk innhold rundt problematiske linjer
            ERR "DEEP GHOST ANALYSIS av prosjektfilen:"
            $lines = $content -split "`n"
            for($i = 0; $i -lt [Math]::Min(20, $lines.Count); $i++) {
                $lineNum = $i + 1
                $indicator = if($lineNum -eq 15 -or $lineNum -eq 97) { " <<< PROBLEM LINE" } else { "" }
                ERR "  ${lineNum}: $($lines[$i])$indicator"
            }

            if(Ask-YesNo "Vil du overskrive med en ren prosjektfil?" -defaultYes) {
                Create-MinimalProject -path $projPath
                OK "Prosjektfil overskrevet med ren versjon"
            } else {
                throw "Ugyldig XML i prosjektfilen"
            }
        }

        # Framework-sjekk
        if($content -match '<TargetFramework>([^<]+)</TargetFramework>') {
            $framework = $matches[1]
            W "Target Framework: $framework" 'DarkGray'
        } else {
            WARN "Kunne ikke finne TargetFramework"
        }

        # WPF-sjekk
        if($content -match '<UseWPF>true</UseWPF>') {
            OK "Dette er en WPF-applikasjon"
        } else {
            WARN "UseWPF ikke funnet - kan føre til byggefeil"
        }

    } catch {
        ERR "Kritisk feil ved validering av prosjektfil: $($_.Exception.Message)"
        if(Ask-YesNo "Vil du erstatte med garantert fungerende prosjektfil?" -defaultYes) {
            Create-MinimalProject -path $projPath
            OK "Prosjektfil erstattet med garantert ren versjon"
        } else {
            throw "Kan ikke fortsette med korrupt prosjektfil"
        }
    }

    # XAML GHOST HUNTER: Skann alle XAML-filer for ghosts
    W "Skanner XAML-filer for konkurrerende indre kodeblokker..." 'Magenta'
    $xamlFiles = Get-ChildItem -Path (Split-Path $projPath -Parent) -Filter "*.xaml" -Recurse

    foreach($xamlFile in $xamlFiles) {
        W "Analyserer: $($xamlFile.Name)" 'Yellow'
        try {
            $xamlContent = Get-Content $xamlFile.FullName -Raw
            $xamlLines = $xamlContent -split "`n"

            # Spesifikk analyse av problematiske linjer
            if($xamlFile.Name -eq "App.xaml") {
                ERR "APP.XAML GHOST DETECTION - Linje 15 og omegn:"
                for($i = 10; $i -lt [Math]::Min(20, $xamlLines.Count); $i++) {
                    $lineNum = $i + 1
                    $indicator = if($lineNum -eq 15) { " <<< ERROR LINE" } else { "" }
                    ERR "  ${lineNum}: $($xamlLines[$i].Trim())$indicator"
                }

                # Tell root elements
                $rootElements = ($xamlContent | Select-String -Pattern '<\w+\s+x:Class=' -AllMatches).Matches.Count
                if($rootElements -gt 1) {
                    ERR "GHOST FOUND: $rootElements root elements med x:Class (skal være 1)"
                }
            }

            if($xamlFile.Name -eq "MainWindow.xaml") {
                ERR "MAINWINDOW.XAML GHOST DETECTION - Linje 97 og omegn:"
                for($i = 92; $i -lt [Math]::Min(102, $xamlLines.Count); $i++) {
                    $lineNum = $i + 1
                    $indicator = if($lineNum -eq 97) { " <<< ERROR LINE" } else { "" }
                    ERR "  ${lineNum}: $($xamlLines[$i].Trim())$indicator"
                }

                # Tell x:Class attributter
                $xClassCount = ($xamlContent | Select-String -Pattern 'x:Class=' -AllMatches).Matches.Count
                if($xClassCount -gt 1) {
                    ERR "GHOST FOUND: $xClassCount x:Class attributter (skal være 1)"
                }
            }

        } catch {
            ERR "Feil ved analyse av $($xamlFile.Name): $($_.Exception.Message)"
        }
    }

    # TILBY GHOST ELIMINATION
    if(Ask-YesNo "Vil du utføre komplett XAML ghost elimination?" -defaultYes) {
        W "Utfører komplett XAML ghost elimination..." 'Red'
        Eliminate-XamlGhosts -projectDir (Split-Path $projPath -Parent)
    }

    return $projPath
}







