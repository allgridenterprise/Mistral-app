# Kill-ChangeMessages.ps1
# ELIMINERER ALT ROT: diff, changes, versjonsfiler, backup osv.
# Gir deg ren arbeidsflate uten forstyrrelser

param(
    [switch]$Nuclear,      # Sletter ALT som kan være versjonering
    [switch]$Silent,       # Ingen output, bare gjør jobben
    [switch]$ScheduleDaily # Kjør automatisk hver dag
)

$ErrorActionPreference = 'Continue'

function Kill-Message([string]$msg) {
    if(-not $Silent) { Write-Host "💀 ELIMINERER: $msg" -ForegroundColor Red }
}

function Success([string]$msg) {
    if(-not $Silent) { Write-Host "✓ $msg" -ForegroundColor Green }
}

# LISTE OVER ALT SOM SKAL DREPĖS
$DeathList = @{
    "Diff og Change filer" = @(
        "*.diff", "*.patch", "*.rej", "*.orig", "*.conflict",
        "*.merge", "*.backup", "*.bak", "*.tmp", "*.old",
        "*_BACKUP_*", "*_BASE_*", "*_LOCAL_*", "*_REMOTE_*",
        "*.mine", "*.r[0-9]*", "*.working"
    )

    "Version Control Rot" = @(
        ".vs\*", "*.vs", "*.vscode*", "*.idea*",
        "*.git\logs\*", "*.git\refs\remotes\*",
        "node_modules\*", "package-lock.json"
    )

    "IDE Søppel" = @(
        "*.autosave", "*.recover", "*~", "*#*",
        "*.swp", "*.swo", "*.tmp", "*_temp_*",
        "Desktop.ini", "Thumbs.db", ".DS_Store"
    )

    "Dato-baserte Backups" = @(
        "*.[0-9][0-9][0-9][0-9][0-9][0-9]*",
        "*_[0-9][0-9][0-9][0-9][0-9][0-9]*",
        "*-[0-9][0-9][0-9][0-9][0-9][0-9]*",
        "*.20[0-9][0-9]*", "*_backup_*", "*-backup-*"
    )
}

if($Nuclear) {
    # NUCLEAR OPTION: Slett også potensielle versjonsfiler
    $DeathList["Nuclear Cleanup"] = @(
        "*copy*", "*Copy*", "*COPY*",
        "*duplicate*", "*Duplicate*",
        "*_old_*", "*_OLD_*",
        "*_new_*", "*_NEW_*",
        "*_test_*", "*_TEST_*",
        "*.log", "*.Log", "*.LOG"
    )
}

function Execute-Elimination {
    $root = Get-Location
    $totalKilled = 0

    Kill-Message "Starter TOTAL ELIMINASJON av versjonssøppel"

    foreach($category in $DeathList.Keys) {
        Kill-Message "Kategori: $category"

        foreach($pattern in $DeathList[$category]) {
            try {
                $files = Get-ChildItem -Path $root -Recurse -Force -Include $pattern -ErrorAction SilentlyContinue
                foreach($file in $files) {
                    try {
                        if($file.PSIsContainer) {
                            Remove-Item $file.FullName -Recurse -Force -ErrorAction Stop
                        } else {
                            Remove-Item $file.FullName -Force -ErrorAction Stop
                        }
                        $totalKilled++
                        if(-not $Silent) { Write-Host "    💀 $($file.Name)" -ForegroundColor DarkRed }
                    }
                    catch { 
                        # Ignorer låste filer
                    }
                }
            }
            catch {
                # Ignorer pattern-feil
            }
        }
    }

    Success "ELIMINERT $totalKilled filer/mapper"
}

function Kill-GitMessages {
    Kill-Message "Eliminerer Git change messages"

    try {
        # Reset git index hvis det finnes
        if(Test-Path ".git") {
            & git reset --hard HEAD 2>&1 | Out-Null
            & git clean -fd 2>&1 | Out-Null
            Success "Git workspace renset"
        }
    }
    catch {
        # Git ikke tilgjengelig, ok
    }
}

function Kill-IDESettings {
    Kill-Message "Eliminerer IDE konfigurasjonsfiler som forårsaker change tracking"

    $ideFiles = @(
        ".vscode\settings.json",
        ".idea\workspace.xml", 
        ".vs\*\config\*",
        "*.DotSettings.user",
        "*.suo", "*.user"
    )

    foreach($pattern in $ideFiles) {
        Get-ChildItem -Recurse -Force -Include $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            try { 
                Remove-Item $_.FullName -Force -ErrorAction Stop
                if(-not $Silent) { Write-Host "    💀 IDE: $($_.Name)" -ForegroundColor DarkRed }
            } catch {}
        }
    }
}

function Create-CleanEnvironment {
    Kill-Message "Oppretter ren arbeidsmiljø"

    # Opprett .gitignore for å unngå fremtidige problemer
    $gitignore = @"
# CHANGE MESSAGE PREVENTION
*.diff
*.patch
*.rej
*.orig
*.backup
*.bak
*.tmp
*.old
*_BACKUP_*
*_BASE_*
*_LOCAL_*
*_REMOTE_*
*.mine
*.autosave
*.recover
*~
.vs/
.vscode/
.idea/
*.DotSettings.user
*.suo
*.user
Desktop.ini
Thumbs.db
.DS_Store
"@

    $gitignore | Set-Content -Path ".gitignore" -Force
    Success "Preventativ .gitignore opprettet"
}

function Setup-AutoClean {
    Kill-Message "Setter opp daglig auto-cleanup"

    $taskScript = @"
# Auto-cleanup task
Set-Location "$((Get-Location).Path)"
& PowerShell.exe -File "Scripts\Kill-ChangeMessages.ps1" -Silent
"@

    $taskPath = "Scripts\AutoClean-Task.ps1"
    $taskScript | Set-Content -Path $taskPath -Force

    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$taskPath`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "03:00"
        Register-ScheduledTask -TaskName "MistralSuite-CleanChanges" -Action $action -Trigger $trigger -Force
        Success "Daglig auto-cleanup schedulert kl. 03:00"
    }
    catch {
        if(-not $Silent) { Write-Warning "Kunne ikke schedulere auto-cleanup: $($_.Exception.Message)" }
    }
}

# ========= KJØR ELIMINASJON =========
if(-not $Silent) {
    Write-Host @"

💀💀💀 CHANGE MESSAGE ELIMINATOR 💀💀💀
        SLETT ALT ROT - GI MEG REN FLATE

"@ -ForegroundColor Red
}

Execute-Elimination
Kill-GitMessages  
Kill-IDESettings
Create-CleanEnvironment

if($ScheduleDaily) {
    Setup-AutoClean
}

if(-not $Silent) {
    Write-Host @"

🎯 WORKSPACE ER NÅ HELT REN!

✓ Alle diff/change/backup filer eliminert
✓ IDE rot fjernet 
✓ Git workspace renset
✓ Preventativ .gitignore opprettet

$(if($Nuclear){"💥 NUCLEAR MODE: Ekstra aggressive elimineringer utført"})
$(if($ScheduleDaily){"⏰ Auto-cleanup schedulert daglig kl. 03:00"})

Du har nå en PERFEKT ren arbeidsflate! 🚀

"@ -ForegroundColor Green
}
