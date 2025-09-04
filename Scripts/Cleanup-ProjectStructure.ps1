# Cleanup-ProjectStructure.ps1
# Et skript for å rydde opp i prosjektmappestrukturen, fjerne duplikater, backups og sekundære filer.
# Implementerer regelstyrt sletting med forsinket autosletting.

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

# ========= Regelstyrt sletting =========
function Cleanup-FilesAndFolders {
    param([string]$root)
    W "Starter opprydding i prosjektmappestrukturen: $root" 'Magenta'

    # Definer regler for sletting
    $patternsToDelete = @(
        '*.*.bak', '*.bak.*', '*.backup.*', '*.old.*', '*.[0-9][0-9][0-9][0-9]*[0-9][0-9]*.bak',
        '*.20[0-9][0-9][0-9][0-9][0-9][0-9]*', '*_backup_*', '*-backup-*', '*.BACKUP.*', 
        '*.BASE.*', '*.LOCAL.*', '*.REMOTE.*', '*.orig', '*.rej', '*.mine', '*.r[0-9]*',
        '*.autosave', '*.recover', '*~backup', '.vs*backup*', '*_temp_*', '*_tmp_*',
        'bin', 'obj', 'publish', 'TestResults', '.vs', 'Output'
    )

    $removedItems = 0
    foreach($pattern in $patternsToDelete){
        Get-ChildItem -Path $root -Recurse -Force -Include $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            try{
                Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                $removedItems++
                if(-not $Silent){ Write-Host "      SLETTET: $($_.Name)" -ForegroundColor Magenta }
            }
            catch { WARN "Kunne ikke slette: $($_.Name)" }
        }
    }

    if($removedItems -gt 0){ OK "Fjernet $removedItems filer og mapper basert på regler." }
    else { OK "Ingen filer eller mapper funnet som matcher reglene." }
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
$root = (Get-Location).Path
W "Prosjektrot: $root" 'DarkGray'

# 1) Initial opprydding
Cleanup-FilesAndFolders -root $root

# 2) Forsinket autosletting
if(Ask-YesNo "Aktivere autosletting med forsinkelse på $AutoDeleteDelayMinutes minutter?" -defaultYes){
    Delayed-AutoDelete -root $root -delayMinutes $AutoDeleteDelayMinutes
} else {
    WARN "Autosletting deaktivert."
}

OK "Oppryddingsprosess fullført."

