# Cleanup-MistralStructure.ps1
# Et skript for å rydde opp i prosjektmappestrukturen fra toppnivå og nedover.

param(
    [switch]$Force,              # Hopper over bekreftelser (ja til alt)
    [switch]$Silent,             # Minimalt med output/ingen stopp for spørsmål
    [int]$AutoDeleteDelayMinutes = 10 # Forsinkelse før autosletting (standard: 10 minutter)
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

# ========= Logg prosjektstruktur (kun toppnivå) =========
function Log-ProjectStructure {
    param([string]$root)
    W "Logger prosjektstruktur for: $root" 'Magenta'
    Get-ChildItem -Path $root -Force | ForEach-Object {
        $type = if ($_ -is [System.IO.DirectoryInfo]) { "MAPPE" } else { "FIL" }
        $size = if ($_ -is [System.IO.FileInfo]) { "$([math]::Round($_.Length / 1KB, 2)) KB" } else { "N/A" }
        Write-Host "  - [$type] $($_.Name) ($size)" -ForegroundColor DarkGray
    }
}

# ========= Regelstyrt og smart sletting =========
function Cleanup-FilesAndFolders {
    param([string]$root)
    W "Starter smart opprydding i prosjektmappestrukturen: $root" 'Magenta'

    # Beskytt kjernefiler og -mapper
    $protected = @(
        'Scripts', 'Setup', 'Output', 'Models', 'src', 'Views', 'ViewModels', 'Resources',
        'MistralApp.csproj', 'App.xaml', 'MainWindow.ps1', 'MainViewModel.ps1', 'appsettings.json'
    )

    # Utvidede mønstre for å fange "sagflis"
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

# ========= Behold kun primære filer =========
function Retain-PrimaryFiles {
    param([string]$root)
    W "Beholder kun primære filer og mapper" 'Cyan'

    $primaryFiles = @(
        'Scripts\Install-MistralSuite.ps1',
        'Setup\MistralApp-Installer.iss',
        'Output\MistralApp.exe',
        'MistralApp.csproj',
        'App.xaml',
        'MainWindow.ps1',
        'MainViewModel.ps1',
        'appsettings.json'
    )

    $allFiles = Get-ChildItem -Path $root -Recurse -Force -File -ErrorAction SilentlyContinue
    foreach ($file in $allFiles) {
        if ($primaryFiles -notcontains $file.FullName -and $primaryFiles -notcontains $file.Name) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
                OK "Slettet sekundær fil: $file.FullName"
            } catch {
                WARN "Kunne ikke slette fil: $file.FullName"
            }
        }
    }
}

# ========= Autoslett med forsinkelse =========
function Delayed-AutoDelete {
    param([string]$root,[int]$delayMinutes)
    W "Forsinket autosletting aktivert ($delayMinutes minutter)" 'Yellow'
    Start-Sleep -Seconds ($delayMinutes * 60)
    Cleanup-FilesAndFolders -root $root
    Retain-PrimaryFiles -root $root
    OK "Autosletting fullført etter forsinkelse."
}

# ========= Slett Output-mappen først =========
function Remove-OutputFolder {
    param([string]$root)
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
}

# ========= Hovedflyt =========
$root = "C:\Users\DanSolberg\RiderProjects\Mistral"
W "Prosjektrot: $root" 'DarkGray'

# Slett Output-mappen først for visuell bekreftelse
Remove-OutputFolder -root $root

# 1) Logg prosjektstruktur
Log-ProjectStructure -root $root

# 2) Initial opprydding
$removedItems = Cleanup-FilesAndFolders -root $root

# 3) Behold kun primære filer
Retain-PrimaryFiles -root $root

# 4) Forsinket autosletting
if(Ask-YesNo "Aktivere autosletting med forsinkelse på $AutoDeleteDelayMinutes minutter?" -defaultYes){
    Delayed-AutoDelete -root $root -delayMinutes $AutoDeleteDelayMinutes
} else {
    WARN "Autosletting deaktivert."
}

OK "Oppryddingsprosess fullført."
