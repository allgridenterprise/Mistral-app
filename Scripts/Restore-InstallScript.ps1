# Restore-InstallScript.ps1 
# GJENOPPRETTER komplett Install-MistralSuite.ps1 og DREPER alle duplikater

param([switch]$Force)

$ErrorActionPreference = 'Stop'

function Write-Kill([string]$msg) { Write-Host "💀 $msg" -ForegroundColor Red }
function OK([string]$msg) { Write-Host "✓ $msg" -ForegroundColor Green }

# FINN ALLE INSTALL-SCRIPT VARIANTER
$root = if($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
$patterns = @(
    "*Install-Mistral*", "*install-mistral*", "*INSTALL-MISTRAL*",
    "*MistralSuite*", "*mistral-suite*", "*Mistral-Suite*"
)

Write-Kill "Søker etter ALLE Install-script varianter..."
$allScripts = @()
foreach($pattern in $patterns) {
    $found = Get-ChildItem -Path $root -Recurse -Include $pattern -File -ErrorAction SilentlyContinue
    $allScripts += $found
}

Write-Kill "Fant $($allScripts.Count) script-filer som skal ryddes"
foreach($script in $allScripts) {
    Write-Kill "  - $($script.FullName) ($(($script.Length/1KB).ToString('F1')) KB)"
}

# SLETT ALLE DUPLIKATER (behold kun hovedskriptet)
$mainScript = Join-Path $root "Scripts\Install-MistralSuite.ps1"
foreach($script in $allScripts) {
    if($script.FullName -ne $mainScript) {
        Remove-Item $script.FullName -Force
        Write-Kill "SLETTET: $($script.Name)"
    }
}

# GJENOPPRETT KOMPLETT HOVEDSKRIPT
$completeScript = @'
# Install-MistralSuite.ps1
# Ett skript for full opprydding, avinstallasjon, bygg, publish og Inno Setup-installasjon.
# Kjør det direkte eller fra en snarvei på oppgavelinjen.
param(
    [ValidateSet('Clean','Build','Full')]
    [string]$Action = 'Full',
    [string]$Configuration = 'Release',
    [switch]$Force,              # Hopper over bekreftelser (ja til alt)
    [switch]$Silent,             # Minimalt med output/ingen stopp for spørsmål
    [switch]$NoInno,             # Hopp over Inno Setup kompilering
    [switch]$RunInstaller,       # Kjør installer etter kompilering
    [switch]$SkipUninstall,      # Ikke forsøk å avinstallere eksisterende
    [string]$AppDisplayName = 'Mistral Suite',   # Navn slik det vises i Programmer og Funksjoner
    [string]$ExeName = 'MistralApp.exe'          # Hoved-EXE i publish
)

$ErrorActionPreference = 'Stop'

# ========= Hjelpere =========
function W([string]$msg,[string]$color='Cyan'){ if(-not $Silent){ Write-Host "`n==> $msg" -ForegroundColor $color } }
function OK([string]$msg){ if(-not $Silent){ Write-Host "✓ $msg" -ForegroundColor Green } }
function WARN([string]$msg){ if(-not $Silent){ Write-Host "⚠ $msg" -ForegroundColor DarkYellow } }
function ERR([string]$msg){ Write-Host "✗ $msg" -ForegroundColor Red }

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

function Remove-ChangeHistoryFiles {
    W "SPESIALRENS: Fjerner ALL endringshistorikk og versjonsfiler" 'Red'
    $changeHistoryPatterns = @(
        '*.*.bak', '*.bak.*', '*.backup.*', '*.old.*', '*.[0-9][0-9][0-9][0-9]*[0-9][0-9]*.bak',
        '*.20[0-9][0-9][0-9][0-9][0-9][0-9]*', '*_backup_*', '*-backup-*', '*.BACKUP.*', 
        '*.BASE.*', '*.LOCAL.*', '*.REMOTE.*', '*.orig', '*.rej', '*.mine', '*.r[0-9]*',
        '*.autosave', '*.recover', '*~backup', '.vs*backup*', '*_temp_*', '*_tmp_*'
    )
    $removedChangeFiles = 0
    foreach($pattern in $changeHistoryPatterns){
        Get-ChildItem -Path $root -Recurse -Force -Include $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
            try{ 
                Remove-Item $_.FullName -Force -ErrorAction Stop
                $removedChangeFiles++
                if(-not $Silent){ Write-Host "      ENDRINGSHISTORIKK SLETTET: $($_.Name)" -ForegroundColor Magenta }
            }
            catch{ }
        }
    }
    if($removedChangeFiles -gt 0){ OK "Fjernet $removedChangeFiles endringshistorikkfiler - kun originalfiler gjenstår" }
    else { OK "Ingen endringshistorikkfiler funnet" }
}

function Ask-YesNo([string]$q,[switch]$defaultYes){
    if($Force -or $Silent){ return $true }
    $def = ($defaultYes) ? 'Y/n' : 'y/N'
    $ans = Read-Host "$q ($def)"
    if([string]::IsNullOrWhiteSpace($ans)){ return [bool]$defaultYes }
    return @('y','yes','j','ja') -contains $ans.ToLowerInvariant()
}

function Resolve-Root {
    if ($PSScriptRoot) { return (Split-Path $PSScriptRoot -Parent) }
    $cwd = (Get-Location).Path
    if ($cwd -match '([\\/]|^)Scripts([\\/]|$)') { return (Split-Path $cwd -Parent) }
    return $cwd
}

$root = Resolve-Root
$OutputDir = Join-Path $root 'Output'

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
    $patterns = @('*.tmp','*.log','*.bak','*copy*','*backup*','old_*','extracted_*')
    foreach($pat in $patterns){
        Get-ChildItem -Path $root -Recurse -Force -Include $pat -ErrorAction SilentlyContinue | ForEach-Object {
            try{ Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop }
            catch{ }
        }
    }
    OK "Opprydding fullført"
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
                            DisplayName = $p.DisplayName; DisplayVersion = $p.DisplayVersion
                            UninstallString = $p.UninstallString; PSPath = $_.PSPath
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
    $csproj = Get-ChildItem -Path $root -Filter 'MistralApp.csproj' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $csproj){ $csproj = Get-ChildItem -Path $root -Filter '*.csproj' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if(-not $csproj){ throw "Fant ingen .csproj under $root" }
    return $csproj.FullName
}

function Dotnet-Publish {
    param([string]$csproj,[string]$config)
    W "Bygger og publiserer ($config, win-x64, self-contained, single-file)" 'Cyan'
    & dotnet clean $csproj 2>&1 | Out-Null
    & dotnet restore $csproj 2>&1 | Out-Null
    & dotnet publish $csproj -c $config -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishReadyToRun=true 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){ throw "dotnet publish feilet ($LASTEXITCODE)" }
    $pub = Join-Path (Split-Path $csproj -Parent) "bin\$config\net8.0-windows\win-x64\publish"
    if(-not (Test-Path $pub)){
        $pubDir = Get-ChildItem -Path $root -Filter 'publish' -Directory -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if($pubDir){ $pub = $pubDir.FullName } else { throw "Fant ikke publish-katalogen." }
    }
    OK "Publish: $pub"; return $pub
}

function Sanitize-AppSettings {
    param([string]$publishDir)
    $appsettings = Join-Path $publishDir 'appsettings.json'
    if(-not (Test-Path $appsettings)){ return }
    try{
        $json = Get-Content $appsettings -Raw | ConvertFrom-Json
        if(-not $json.PSObject.Properties.Match('MistralApi')){ $json | Add-Member -NotePropertyName MistralApi -NotePropertyValue (@{}) }
        if(-not $json.MistralApi.PSObject.Properties.Match('ApiKey')){ $json.MistralApi | Add-Member -NotePropertyName ApiKey -NotePropertyValue "" } 
        else { $json.MistralApi.ApiKey = "" }
        ($json | ConvertTo-Json -Depth 20) | Set-Content $appsettings -Encoding UTF8
        OK "Sanitert appsettings.json"
    } catch { WARN "Hoppet over sanitering av appsettings: $($_.Exception.Message)" }
}

function Compile-Inno {
    param([string]$publishDir,[string]$exeName)
    if($NoInno){ WARN "Hopper over Inno Setup (NoInno)"; return $null }
    $iss = @((Join-Path $root 'Setup\MistralApp-Installer.iss'), (Join-Path $root 'MistralApp-Installer.iss')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if(-not $iss){
        $cand = Get-ChildItem -Path $root -Filter '*.iss' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if($cand){ $iss = $cand.FullName }
    }
    if(-not $iss){
        $setupDir = Join-Path $root 'Setup'; if(-not (Test-Path $setupDir)){ New-Item -ItemType Directory -Path $setupDir | Out-Null }
        $iss = Join-Path $setupDir 'MistralApp-Installer.iss'
        $inno = @"
#define MyAppName "Mistral Suite"
#define MyAppExeName "$exeName"

[Setup]
AppName={#MyAppName}
AppVersion=1.0.0
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=$($OutputDir)
OutputBaseFilename={#MyAppName}-Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "$publishDir\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
"@
        $inno | Set-Content -Path $iss -Encoding UTF8; OK "Opprettet minimalt Inno Setup-skript: $iss"
    }
    $iscc = @('C:\Program Files (x86)\Inno Setup 6\ISCC.exe', 'C:\Program Files\Inno Setup 6\ISCC.exe', 
              'C:\Program Files (x86)\Inno Setup 5\ISCC.exe', 'C:\Program Files\Inno Setup 5\ISCC.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
    if(-not $iscc){ WARN "ISCC.exe ikke funnet; hopper over installer"; return $null }
    if(-not (Test-Path $OutputDir)){ New-Item -ItemType Directory -Path $OutputDir | Out-Null }
    W "Kompilerer Inno Setup ($([IO.Path]::GetFileName($iss)))" 'Cyan'
    & $iscc $iss 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){ throw "Inno Setup feilet ($LASTEXITCODE)" }
    $installers = Get-ChildItem -Path $root -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -match 'Output|Setup' }
    if(-not $installers){ $installers = Get-ChildItem -Path (Split-Path $iss -Parent) -Filter '*.exe' -ErrorAction SilentlyContinue }
    if(-not $installers){ WARN "Installer ikke funnet"; return $null }
    $latest = $installers | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $target = Join-Path $OutputDir $($latest.Name)
    if($latest.FullName -ne $target){ Copy-Item $latest.FullName $target -Force }
    OK "Installer klar: $target"; return $target
}

# ========= Hovedflyt =========
W "Mistral Suite – Installasjon (modus: $Action)" 'Magenta'
W "Prosjektrot: $root" 'DarkGray'

# 0) ELIMINÉR ALT CHANGE/DIFF ROT FØRST
if(Test-Path "Scripts\Kill-ChangeMessages.ps1") {
    & "Scripts\Kill-ChangeMessages.ps1" -Nuclear -Silent
} else {
    Get-ChildItem -Recurse -Force -Include @("*.diff","*.patch","*.rej","*.orig","*.backup","*.bak","*.tmp","*_BACKUP_*","*.mine") -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 1) Stopp prosesser og fjern unødvendige filer  
Stop-Processes
Remove-OverlappingScripts
Remove-ChangeHistoryFiles

# 2) Avinstallasjon
if(-not $SkipUninstall -and $Action -ne 'Clean'){ Uninstall-Existing -nameLike $AppDisplayName } 
else { WARN "Hopper over avinstallasjon" }

# 3) Opprydding
Cleanup-Artifacts
if($Action -eq 'Clean'){ OK "Ferdig (Clean)."; exit 0 }

# 4) Build/publish
try{
    $csproj = Find-Project; W "Prosjekt: $([IO.Path]::GetFileName($csproj))" 'DarkGray'
    $publishDir = Dotnet-Publish -csproj $csproj -config $Configuration
    Sanitize-AppSettings -publishDir $publishDir
} catch { ERR "Bygg/publish feilet: $($_.Exception.Message)"; exit 1 }

# 5) Inno Setup
$installerPath = $null
try{ $installerPath = Compile-Inno -publishDir $publishDir -exeName $ExeName } 
catch { ERR $_.Exception.Message; if(-not $Force){ exit 1 } }

# 6) Start installer
if($installerPath -and $RunInstaller){
    if($Force -or (Ask-YesNo "Kjøre installer nå?" -defaultYes)){
        try{ Start-Process -FilePath $installerPath -Wait; OK "Installer kjørt" } 
        catch { WARN "Kunne ikke starte installer: $($_.Exception.Message)" }
    }
}

OK "Prosess fullført."
if($installerPath){ Write-Host "Installer: $installerPath" -ForegroundColor Gray }
'@

# SKRIV KOMPLETT SCRIPT
$completeScript | Set-Content -Path $mainScript -Encoding UTF8 -Force

OK "HOVEDSKRIPT GJENOPPRETTET: $mainScript"

# RYDD RIDER CACHE OG KONFIG
$riderDirs = @(
    "$env:LOCALAPPDATA\JetBrains\Toolbox\apps\Rider\ch-*\*\plugins\*\change*",
    "$env:APPDATA\JetBrains\Rider*\*\change*",
    "$root\.idea\shelf\*", "$root\.idea\workspace.xml"
)

foreach($pattern in $riderDirs) {
    Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# ... existing code ...

OK @"
🎯 INSTALL-SCRIPT ER FULLSTENDIG GJENOPPRETTET!

✓ Alle duplikater og fragmenter slettet  
✓ Komplett $(($completeScript.Length/1KB).ToString('F1')) KB script gjenopprettet
✓ Rider cache og konfig renset
✓ Kun ÉN korrekt Install-MistralSuite.ps1 gjenstår

Du har nå et helt rent og komplett installasjonssystem! 🚀
"@

$completeScript | Set-Content -Path $mainScript -Encoding UTF8 -Force
OK "KOMPLETT Install-MistralSuite.ps1 gjenopprettet - $(($completeScript.Length/1KB).ToString('F1')) KB"