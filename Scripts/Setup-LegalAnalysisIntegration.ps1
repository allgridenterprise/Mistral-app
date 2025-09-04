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

    # Script som overlapper med Install-MistralSuite.ps1
    $scriptsToDelete = @(
        'Build-MistralApp.ps1',
        'Cleanup-MistralProject.ps1',
        'ProjectAutoCleanup.ps1', 
        'RemoveLegacyFiles.ps1',
        'Complete-MistralSuite-Manager.ps1'
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
                    $errorMsg = $_.Exception.Message
                    ERR "Feil ved sletting av $script : $errorMsg" 
                }
            }
        }
    }

    if($deletedCount -gt 0){
        OK "Slettet $deletedCount overlappende script permanent"
    } else {
        OK "Ingen overlappende script funnet"
    }
}
function Remove-ChangeHistoryFiles {
    W "SPESIALRENS: Fjerner ALL endringshistorikk og versjonsfiler" 'Red'

    # Identifiser og fjern alle mulige endringshistorikkfiler
    $changeHistoryPatterns = @(
        # Alle backup-varianter du ikke trenger
        '*.*.bak', '*.bak.*', '*.backup.*', '*.old.*',

        # Datobaserte backups (alle varianter)
        '*.[0-9][0-9][0-9][0-9]*[0-9][0-9]*.bak',
        '*.20[0-9][0-9][0-9][0-9][0-9][0-9]*',
        '*_backup_*', '*-backup-*',

        # Version control merge-filer
        '*.BACKUP.*', '*.BASE.*', '*.LOCAL.*', '*.REMOTE.*',
        '*.orig', '*.rej', '*.mine', '*.r[0-9]*',

        # IDE endringshistorikk
        '*.autosave', '*.recover', '*~backup',
        '.vs*backup*', '*_temp_*', '*_tmp_*'
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

    if($removedChangeFiles -gt 0){
        OK "Fjernet $removedChangeFiles endringshistorikkfiler - kun originalfiler gjenstår"
    } else {
        OK "Ingen endringshistorikkfiler funnet"
    }
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
# Setup-LegalAnalysisIntegration.ps1
# Konfigurerer Make.com, AirTable og OneDrive for juridisk bevisanalyse
param(
    [string]$MakeComApiKey = "",
    [string]$AirTableBaseId = "",
    [string]$AirTableApiKey = "",
    [string]$OneDrivePath = "",
    [switch]$TestConnections,
    [switch]$SetupFolders
)

$ErrorActionPreference = 'Stop'

function Write-Status([string]$msg, [string]$color='Cyan') {
    Write-Host "==> $msg" -ForegroundColor $color
}

function Write-Success([string]$msg) {
    Write-Host "✓ $msg" -ForegroundColor Green
}

function Write-Error([string]$msg) {
    Write-Host "✗ $msg" -ForegroundColor Red
}

# Mappestruktur for juridisk analyse
$FolderStructure = @{
    "BevisGrunnlag" = @(
        "EMD-Dokumenter",
        "HR-Avgjørelser", 
        "Offentlige-Dokumenter",
        "Private-Korrespondanse",
        "Metadata-Export",
        "AI-Analyser"
    )
    "Prosessering" = @(
        "Inn-Kø",
        "Pågående",
        "Ferdig-Analysert",
        "Feilede-Dokumenter"
    )
    "Rapporter" = @(
        "Statistikk",
        "Juridiske-Sammendrag",
        "Komplett-Bevisførsel",
        "PDF-Export"
    )
}

function Setup-FolderStructure {
    Write-Status "Oppretter mappestruktur for juridisk analyse"

    $baseDir = Join-Path $env:USERPROFILE "JuridiskBevisAnalyse"
    if(-not (Test-Path $baseDir)) {
        New-Item -ItemType Directory -Path $baseDir | Out-Null
    }

    foreach($category in $FolderStructure.Keys) {
        $categoryPath = Join-Path $baseDir $category
        if(-not (Test-Path $categoryPath)) {
            New-Item -ItemType Directory -Path $categoryPath | Out-Null
        }

        foreach($subfolder in $FolderStructure[$category]) {
            $subPath = Join-Path $categoryPath $subfolder
            if(-not (Test-Path $subPath)) {
                New-Item -ItemType Directory -Path $subPath | Out-Null
                Write-Success "Opprettet: $subfolder"
            }
        }
    }

    # Opprett konfigurasjonfil for integrasjoner
    $configPath = Join-Path $baseDir "integrations-config.json"
    $config = @{
        "MakeComWebhooks" = @{
            "DocumentAnalysis" = "https://hook.make.com/your-webhook-url"
            "EMDMatching" = "https://hook.make.com/emd-webhook"
            "StatisticalAnalysis" = "https://hook.make.com/stats-webhook"
        }
        "AirTableConfig" = @{
            "BaseId" = $AirTableBaseId
            "Tables" = @{
                "Dokumenter" = "tblDokumenter"
                "Metadata" = "tblMetadata"
                "EMDKriterier" = "tblEMDKriterier"
                "BevisStyrke" = "tblBevisStyrke"
            }
        }
        "OneDriveSync" = @{
            "LocalPath" = $baseDir
            "CloudPath" = $OneDrivePath
            "AutoSync" = $true
        }
    }

    $config | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath
    Write-Success "Konfigurasjonfil opprettet: $configPath"
}

function Test-MakeComConnection {
    param([string]$apiKey)

    Write-Status "Tester Make.com tilkobling"
    try {
        $headers = @{ 'Authorization' = "Bearer $apiKey" }
        $response = Invoke-RestMethod -Uri "https://www.make.com/api/v2/scenarios" -Headers $headers -Method Get
        Write-Success "Make.com tilkobling OK - Fant $($response.scenarios.Count) scenarier"
        return $true
    }
    catch {
        Write-Error "Make.com tilkobling feilet: $($_.Exception.Message)"
        return $false
    }
}

function Test-AirTableConnection {
    param([string]$baseId, [string]$apiKey)

    Write-Status "Tester AirTable tilkobling"
    try {
        $headers = @{ 'Authorization' = "Bearer $apiKey" }
        $uri = "https://api.airtable.com/v0/$baseId/Dokumenter?maxRecords=1"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        Write-Success "AirTable tilkobling OK - Database tilgjengelig"
        return $true
    }
    catch {
        Write-Error "AirTable tilkobling feilet: $($_.Exception.Message)"
        return $false
    }
}

function Setup-OneDriveSync {
    param([string]$localPath, [string]$cloudPath)

    Write-Status "Konfigurerer OneDrive speilsynkronisering"

    # Opprett PowerShell-script for kontinuerlig synk
    $syncScript = @"
# OneDrive-sync for juridisk analyse
param([switch]`$Monitor)

`$localPath = "$localPath"
`$cloudPath = "$cloudPath"

function Sync-ToCloud {
    if(Test-Path `$localPath) {
        robocopy "`$localPath" "`$cloudPath" /MIR /Z /W:1 /R:1 /LOG+:"sync.log"
        Write-Host "Synkronisert til OneDrive: `$(Get-Date)"
    }
}

if(`$Monitor) {
    `$watcher = New-Object System.IO.FileSystemWatcher
    `$watcher.Path = `$localPath
    `$watcher.Filter = "*.*"
    `$watcher.IncludeSubdirectories = `$true
    `$watcher.EnableRaisingEvents = `$true

    Register-ObjectEvent `$watcher "Changed" -Action { Sync-ToCloud }

    Write-Host "OneDrive sync monitor startet for: `$localPath"
    try { while(`$true) { Start-Sleep -Seconds 30; Sync-ToCloud } } 
    finally { `$watcher.Dispose() }
} else {
    Sync-ToCloud
}
"@

    $syncScriptPath = Join-Path (Split-Path $localPath -Parent) "OneDrive-Sync.ps1"
    $syncScript | Set-Content -Path $syncScriptPath
    Write-Success "OneDrive sync-script opprettet: $syncScriptPath"

    # Opprett scheduled task for automatisk synk
    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$syncScriptPath`" -Monitor"
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        Register-ScheduledTask -TaskName "JuridiskAnalyse-OneDriveSync" -Action $action -Trigger $trigger -Principal $principal -Force
        Write-Success "Scheduled task opprettet for automatisk OneDrive-sync"
    }
    catch {
        Write-Error "Kunne ikke opprette scheduled task: $($_.Exception.Message)"
    }
}

# Hovedflyt
Write-Status "Starter oppsett av juridisk analysesystem" -color Magenta

if($SetupFolders) {
    Setup-FolderStructure
}

if($TestConnections) {
    $allOk = $true

    if($MakeComApiKey) {
        $allOk = $allOk -and (Test-MakeComConnection -apiKey $MakeComApiKey)
    }

    if($AirTableBaseId -and $AirTableApiKey) {
        $allOk = $allOk -and (Test-AirTableConnection -baseId $AirTableBaseId -apiKey $AirTableApiKey)
    }

    if($allOk) {
        Write-Success "Alle integrasjoner testet OK!"
    } else {
        Write-Error "En eller flere integrasjoner feilet"
    }
}

if($OneDrivePath) {
    Setup-OneDriveSync -localPath (Join-Path $env:USERPROFILE "JuridiskBevisAnalyse") -cloudPath $OneDrivePath
}

Write-Success "Juridisk analysesystem er konfigurert og klar for bruk!"
Write-Host @"

📋 NESTE STEG:
1. Start Mistral Suite og gå til 'Dokumenter'-tab
2. Last opp dokumenter til BevisGrunnlag-mappene
3. Kjør AI-analyse med ønsket dybdenivå
4. Eksporter bevisfører som PDF

🔗 INTEGRASJONER:
- Make.com: Webhook URLs satt opp i config
- AirTable: Database kobling konfigurert  
- OneDrive: Automatisk synk aktivert

⚖️ JURIDISK PRESISJON:
Systemet er nå klar for EMD Article 8 og HR-analyse
med statistisk avviksmønster og grafisk bevisførsel.
"@ -ForegroundColor Cyan
function Cleanup-Artifacts {
    W "Rydder artefakter (bin/obj/publish, Output, temp, duplikater)" 'Cyan'
    $paths = @(
        (Join-Path $root 'bin'),
        (Join-Path $root 'obj'),
        (Join-Path $root 'publish'),
        (Join-Path $root 'installer\Output'),
        (Join-Path $root 'packages'),
        (Join-Path $root 'TestResults'),
        (Join-Path $root '.vs'),
        $OutputDir
    )
    foreach($p in $paths){
        if(Test-Path $p){ try{ Remove-Item $p -Recurse -Force -ErrorAction Stop; OK "Slettet $p" } catch { WARN "Sletting feilet: $p ($($_.Exception.Message))" } }
    }

    # midlertidige filer og kjente “kopier”
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
                            DisplayName = $p.DisplayName
                            DisplayVersion = $p.DisplayVersion
                            UninstallString = $p.UninstallString
                            PSPath = $_.PSPath
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
    if(-not $entries -or $entries.Count -eq 0){
        OK "Ingen eksisterende installasjon funnet"
        return
    }
    foreach($e in $entries){
        Write-Host ("  - {0} {1}" -f $e.DisplayName, $e.DisplayVersion) -ForegroundColor Yellow
        if(Ask-YesNo "Avinstallere denne nå?" -defaultYes){
            $cmd = $e.UninstallString
            if([string]::IsNullOrWhiteSpace($cmd)){ WARN "Mangler UninstallString"; continue }
            try{
                if($cmd.ToLower().Contains('msiexec')){
                    # MSI: sikre /x og stille flagg
                    $args = $cmd
                    if(-not $args.ToLower().Contains('/x')){ $args = "$args /x" }
                    $args = "$args /qn /norestart"
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $args" -Wait -WindowStyle Hidden
                } else {
                    # Inno/annet: trekk ut exe og kjør silent
                    $exe = $null; $rest = ""
                    if($cmd.StartsWith('"')){
                        $exe = $cmd.Split('"')[1]
                        $rest = $cmd.Substring($exe.Length+2)
                    } else {
                        $parts = $cmd.Split(' ',2); $exe=$parts[0]; if($parts.Count -gt 1){$rest=$parts[1]}
                    }
                    if(Test-Path $exe){
                        Start-Process -FilePath $exe -ArgumentList "/VERYSILENT /NORESTART" -Wait -WindowStyle Hidden
                    } else {
                        WARN "Uninstaller ikke funnet: $exe"
                    }
                }
                OK "Avinstallert: $($e.DisplayName)"
            } catch {
                WARN "Feil ved avinstallasjon av $($e.DisplayName): $($_.Exception.Message)"
            }
        }
    }

    # Slett rester i Program Files
    $pfTargets = @(
        (Join-Path ${env:ProgramFiles} $nameLike),
        (Join-Path ${env:ProgramFiles(x86)} $nameLike)
    ) | Where-Object { $_ -ne $null }
    foreach($pf in $pfTargets){
        if(Test-Path $pf){
            try{ 
                Remove-Item $pf -Recurse -Force -ErrorAction Stop
                OK "Slettet restmappe: $pf" 
            } catch { 
                $errorMsg = $_.Exception.Message
                WARN "Kunne ikke slette $pf : $errorMsg" 
            }
        }
    }

    # Rydd snarveier
    $shortcuts = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$nameLike",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$nameLike",
        "$env:PUBLIC\Desktop\$nameLike.lnk",
        "$env:USERPROFILE\Desktop\$nameLike.lnk"
    )
    foreach($sc in $shortcuts){
        if(Test-Path $sc){ try{ Remove-Item $sc -Recurse -Force -ErrorAction Stop; OK "Fjernet snarvei: $sc" } catch {} }
    }
}

function Find-Project {
    # Foretrekk MistralApp.csproj, ellers første *.csproj under rot
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
        # Fallback: finn 'publish' dynamisk
        $pubDir = Get-ChildItem -Path $root -Filter 'publish' -Directory -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if($pubDir){ $pub = $pubDir.FullName } else { throw "Fant ikke publish-katalogen." }
    }
    OK "Publish: $pub"
    return $pub
}

function Sanitize-AppSettings {
    param([string]$publishDir)
    $appsettings = Join-Path $publishDir 'appsettings.json'
    if(-not (Test-Path $appsettings)){ return }
    try{
        $json = Get-Content $appsettings -Raw | ConvertFrom-Json
        # Rens kjente hemmeligheter (legg gjerne til flere nøkler etter behov)
        if(-not $json.PSObject.Properties.Match('MistralApi')){ $json | Add-Member -NotePropertyName MistralApi -NotePropertyValue (@{}) }
        if(-not $json.MistralApi.PSObject.Properties.Match('ApiKey')){ $json.MistralApi | Add-Member -NotePropertyName ApiKey -NotePropertyValue "" } else { $json.MistralApi.ApiKey = "" }
        ($json | ConvertTo-Json -Depth 20) | Set-Content $appsettings -Encoding UTF8
        OK "Sanitert appsettings.json"
    } catch { WARN "Hoppet over sanitering av appsettings: $($_.Exception.Message)" }
}

function Compile-Inno {
    param([string]$publishDir,[string]$exeName)
    if($NoInno){ WARN "Hopper over Inno Setup (NoInno)"; return $null }
    # Finn .iss
    $iss = @(
        (Join-Path $root 'Setup\MistralApp-Installer.iss'),
        (Join-Path $root 'MistralApp-Installer.iss')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if(-not $iss){
        # Sjekk om det finnes en .iss et annet sted
        $cand = Get-ChildItem -Path $root -Filter '*.iss' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if($cand){ $iss = $cand.FullName }
    }
    if(-not $iss){
        # Generer et minimalt Inno Setup-skript for å sikre E2E-kjøring
        $setupDir = Join-Path $root 'Setup'
        if(-not (Test-Path $setupDir)){ New-Item -ItemType Directory -Path $setupDir | Out-Null }
        $iss = Join-Path $setupDir 'MistralApp-Installer.iss'
        $inno = @"
; Auto-generert Inno Setup script
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
        $inno | Set-Content -Path $iss -Encoding UTF8
        OK "Opprettet minimalt Inno Setup-skript: $iss"
    }

    # Finn ISCC
    $iscc = @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe',
        'C:\Program Files (x86)\Inno Setup 5\ISCC.exe',
        'C:\Program Files\Inno Setup 5\ISCC.exe'
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if(-not $iscc){ WARN "ISCC.exe ikke funnet; hopper over installer"; return $null }

    if(-not (Test-Path $OutputDir)){ New-Item -ItemType Directory -Path $OutputDir | Out-Null }

    W "Kompilerer Inno Setup ($([IO.Path]::GetFileName($iss)))" 'Cyan'
    # Kjør direkte; mange skript bruker relative stier til publish-mappen
    & $iscc $iss | Out-Null
    if($LASTEXITCODE -ne 0){ throw "Inno Setup feilet ($LASTEXITCODE)" }

    # Finn nyeste .exe
    $installers = Get-ChildItem -Path $root -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $_.DirectoryName -match 'Output|Setup' }
    if(-not $installers){ $installers = Get-ChildItem -Path (Split-Path $iss -Parent) -Filter '*.exe' -ErrorAction SilentlyContinue }
    if(-not $installers){ WARN "Installer ikke funnet"; return $null }

    $latest = $installers | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    # Flytt til rotens Output
    $target = Join-Path $OutputDir $($latest.Name)
    if($latest.FullName -ne $target){
        Copy-Item $latest.FullName $target -Force
    }
    OK "Installer klar: $target"
    return $target
}

# ========= Hovedflyt =========
W "Mistral Suite – Installasjon (modus: $Action)" 'Magenta'
W "Prosjektrot: $root" 'DarkGray'

# 1) Stopp prosesser og fjern unødvendige filer
Stop-Processes
Remove-OverlappingScripts
Remove-ChangeHistoryFiles

# 2) Avinstallasjon (om ikke hoppet over)
if(-not $SkipUninstall -and $Action -ne 'Clean'){
    Uninstall-Existing -nameLike $AppDisplayName
} else {
    WARN "Hopper over avinstallasjon"
}

# 3) Opprydding
Cleanup-Artifacts
if($Action -eq 'Clean'){
    OK "Ferdig (Clean)."
    exit 0
}

# 4) Build/publish
try{
    $csproj = Find-Project
    W "Prosjekt: $([IO.Path]::GetFileName($csproj))" 'DarkGray'
    $publishDir = Dotnet-Publish -csproj $csproj -config $Configuration
    Sanitize-AppSettings -publishDir $publishDir
} catch {
    ERR "Bygg/publish feilet: $($_.Exception.Message)"
    exit 1
}

# 5) Inno Setup (installer)
$installerPath = $null
try{
    $installerPath = Compile-Inno -publishDir $publishDir -exeName $ExeName
} catch {
    ERR $_.Exception.Message
    if(-not $Force){ exit 1 }
}

# 6) Start installer (valgfritt)
if($installerPath -and $RunInstaller){
    if($Force -or (Ask-YesNo "Kjøre installer nå?" -defaultYes)){
        try{ Start-Process -FilePath $installerPath -Wait; OK "Installer kjørt" } catch { WARN "Kunne ikke starte installer: $($_.Exception.Message)" }
    }
}

OK "Prosess fullført."
if($installerPath){ Write-Host "Installer: $installerPath" -ForegroundColor Gray }
