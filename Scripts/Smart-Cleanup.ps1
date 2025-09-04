# Smart-Cleanup.ps1
# Et skript for å rydde opp i store prosjektmappestrukturer, kombinert med logging og nøkkelpunkttesting.

param(
    [switch]$Force,              # Hopper over bekreftelser (ja til alt)
    [switch]$Silent,             # Minimalt med output/ingen stopp for spørsmål
    [int]$AutoDeleteDelayMinutes = 10, # Forsinkelse før autosletting (standard: 10 minutter)
    [switch]$RunIntegrityTests   # Kjører nøkkelpunkttesting etter opprydding
)

$ErrorActionPreference = 'Stop'

# ========= Hjelpere =========
function W([string]$msg,[string]$color='Cyan'){ if(-not $Silent){ Write-Host "`n==> $msg" -ForegroundColor $color } }
function OK([string]$msg){ if(-not $Silent){ Write-Host "✓ $msg" -ForegroundColor Green } }
function WARN([string]$msg){ if(-not $Silent){ Write-Host "⚠ $msg" -ForegroundColor DarkYellow } }
function ERR([string]$msg){ Write-Host "✗ $msg" -ForegroundColor Red }

function Ask-YesNo([string]$q,[switch]$defaultYes){
    if($Force -or $Silent){ return $true }
    $def = ($defaultYes) ? 'Y/n' : 'y/N'
    $ans = Read-Host "$q ($def)"
    if([string]::IsNullOrWhiteSpace($ans)){ return [bool]$defaultYes }
    return @('y','yes','j','ja') -contains $ans.ToLowerInvariant()
}

# ========= Regelstyrt sletting med beskyttelse =========
function Cleanup-FilesAndFolders {
    param([string]$root)
    W "Starter smart opprydding i prosjektmappestrukturen: $root" 'Magenta'

    $protected = @(
        'Scripts', 'Setup', 'Output', 'Models', 'src', 'Views', 'ViewModels', 'Resources',
        'MistralApp.csproj', 'App.xaml', 'MainWindow.ps1', 'MainViewModel.ps1', 'appsettings.json'
    )

    $patternsToDelete = @(
        '*.*.bak', '*.bak.*', '*.backup.*', '*.old.*', '*_backup_*', '*-backup-*', '*.BACKUP.*',
        '*.BASE.*', '*.LOCAL.*', '*.REMOTE.*', '*.orig', '*.rej', '*.mine', '*.autosave', '*.recover',
        '*~backup', '*_temp_*', '*_tmp_*', '*.log', '*.tmp', '*.cache', '*.swp', '*.DS_Store',
        'bin', 'obj', 'publish', 'TestResults', '.vs', 'installer', 'temp', 'node_modules', 'dist', 'debug',
        '*.pyc', '__pycache__', '*.suo', '*.user', '*.userosscache', '*.sln.docstates', '*.md', '*.txt',
        '*.rtf', '*.docx', '*.pdf', '*.pptx', '*.xls*', '*.csv', '*.json', '*.xml', '*.yml', '*.yaml', '*.ini', '*.config',
        '.idea', '.vscode', '.git', '.gitignore', '.gitattributes', 'Eksempler', 'examples', 'samples', 'docs'
    )

    $removedItems = @()
    $foundAny = $false
    foreach($pattern in $patternsToDelete){
        W "Søker etter filer/mappemønster: $pattern" 'DarkGray'
        $matches = Get-ChildItem -Path $root -Recurse -Force -Include $pattern -ErrorAction SilentlyContinue
        if ($matches.Count -gt 0) { $foundAny = $true }
        $matches | ForEach-Object {
            $isProtected = $false
            foreach ($p in $protected) {
                if ($_.FullName -like "*\$p*" -or $_.Name -eq $p) {
                    $isProtected = $true
                    break
                }
            }
            if (-not $isProtected) {
                try{
                    Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                    $removedItems += $_.FullName
                    if(-not $Silent){ Write-Host "      SLETTET: $($_.FullName)" -ForegroundColor Magenta }
                }
                catch { WARN "Kunne ikke slette: $($_.FullName)" }
            } else {
                W "Beskyttet: $($_.FullName)" 'Green'
            }
        }
    }

    if($removedItems.Count -gt 0){ OK "Fjernet $($removedItems.Count) filer og mapper basert på regler." }
    elseif (-not $foundAny) { WARN "Ingen mapper eller filer funnet for sletting i hele prosjektet." }
    else { WARN "Ingen filer eller mapper funnet som matcher reglene." }
    return $removedItems
}

# ========= Nøkkelpunkttesting (utvidet) =========
function Run-KeyPointTests {
    param([string]$root)
    W "Kjører nøkkelpunkttesting på utvalgte filer" 'Cyan'

    $keyFiles = @(
        'Scripts\Install-MistralSuite.ps1',
        'Setup\MistralApp-Installer.iss',
        'Output\MistralApp.exe',
        'MistralApp.csproj',
        'App.xaml',
        'MainWindow.ps1',
        'MainViewModel.ps1',
        'appsettings.json'
    )

    foreach ($file in $keyFiles) {
        $fullPath = Join-Path $root $file
        if (Test-Path $fullPath) {
            try {
                W "Tester fil: $fullPath" 'DarkGray'
                $content = Get-Content $fullPath -ErrorAction Stop
                OK "Filtest bestått: $file"
            } catch {
                ERR "Filtest feilet: $file ($($_.Exception.Message))"
            }
        } else {
            WARN "Fil ikke funnet: $file"
        }
    }
}

# ========= Autoslett med forsinkelse =========
function Delayed-AutoDelete {
    param([string]$root,[int]$delayMinutes)
    W "Forsinket autosletting aktivert ($delayMinutes minutter)" 'Yellow'
    Start-Sleep -Seconds ($delayMinutes * 60)
    Cleanup-FilesAndFolders -root $root
    OK "Autosletting fullført etter forsinkelse."
}

# ========= Hovedflyt =========
$root = "C:\Users\DanSolberg\RiderProjects\Mistral"
W "Prosjektrot: $root" 'DarkGray'

# 1) Initial opprydding
$removedItems = Cleanup-FilesAndFolders -root $root

# 2) Nøkkelpunkttesting (valgfritt)
if ($RunIntegrityTests) {
    Run-KeyPointTests -root $root
}

# 3) Forsinket autosletting
if(Ask-YesNo "Aktivere autosletting med forsinkelse på $AutoDeleteDelayMinutes minutter?" -defaultYes){
    Delayed-AutoDelete -root $root -delayMinutes $AutoDeleteDelayMinutes
} else {
    WARN "Autosletting deaktivert."
}

OK "Oppryddingsprosess fullført."
