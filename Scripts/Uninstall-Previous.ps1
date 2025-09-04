# ===================================================================
# Uninstall-Previous.ps1
# Avinstallerer tidligere installerte versjoner av Mistral Suite
# ===================================================================

param(
    [switch]$Silent,        # Stille avinstallering uten brukerinteraksjon
    [switch]$Force          # Tvang avinstallering selv om feil oppstår
)

$ErrorActionPreference = if ($Force) { 'Continue' } else { 'Stop' }

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "✗ $msg" -ForegroundColor Red }

Write-Step "Søker etter tidligere installasjoner av Mistral Suite..."

# 1. Stopp alle kjørende prosesser
Write-Step "Stopper kjørende MistralApp-prosesser..."
$processes = Get-Process -Name "MistralApp*" -ErrorAction SilentlyContinue
if ($processes) {
    foreach ($proc in $processes) {
        try {
            $proc | Stop-Process -Force
            Write-OK "Stoppet prosess: $($proc.ProcessName) (PID: $($proc.Id))"
        }
        catch {
            Write-Warn "Kunne ikke stoppe prosess: $($proc.ProcessName)"
        }
    }
} else {
    Write-OK "Ingen kjørende MistralApp-prosesser funnet"
}

# 2. Søk i Windows "Programs and Features" (via registry)
Write-Step "Søker i Windows Programs and Features..."
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$found = $false
foreach ($key in $uninstallKeys) {
    try {
        Get-ItemProperty $key -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like "*Mistral*" -or $_.DisplayName -like "*MistralApp*" -or $_.DisplayName -like "*Mistral Suite*"
        } | ForEach-Object {
            $found = $true
            $displayName = $_.DisplayName
            $uninstallString = $_.UninstallString

            Write-Warn "Funnet installasjon: $displayName"
            Write-Host "Avinstallerer: $uninstallString" -ForegroundColor Gray

            if (-not $Silent) {
                $response = Read-Host "Avinstaller '$displayName'? (J/N)"
                if ($response -notmatch '^[JjYy]') {
                    Write-Warn "Hoppet over: $displayName"
                    return
                }
            }

            try {
                if ($uninstallString -match '(.+\.exe)(.*)') {
                    $exe = $matches[1].Trim('"')
                    $args = $matches[2].Trim()

                    # Legg til silent-flagg hvis mulig
                    if ($Silent -and $args -notmatch '/S|/SILENT|/QUIET') {
                        $args += " /SILENT"
                    }

                    Write-Host "Kjører: $exe $args" -ForegroundColor Gray
                    Start-Process -FilePath $exe -ArgumentList $args -Wait -NoNewWindow
                    Write-OK "Avinstallert: $displayName"
                } else {
                    Write-Warn "Ukjent avinstallingsformat: $uninstallString"
                }
            }
            catch {
                Write-Err "Feil ved avinstallering av '$displayName': $($_.Exception.Message)"
            }
        }
    }
    catch {
        # Ignorer registry-feil
    }
}

# 3. Manuell filsletting
Write-Step "Sjekker for manuelle installasjoner..."
$commonPaths = @(
    "$env:ProgramFiles\Mistral Suite",
    "$env:ProgramFiles\MistralApp", 
    "${env:ProgramFiles(x86)}\Mistral Suite",
    "${env:ProgramFiles(x86)}\MistralApp",
    "$env:LOCALAPPDATA\MistralSuite",
    "$env:APPDATA\MistralSuite"
)

foreach ($path in $commonPaths) {
    if (Test-Path $path) {
        Write-Warn "Funnet manuell installasjon: $path"

        if (-not $Silent) {
            $response = Read-Host "Slett '$path'? (J/N)"
            if ($response -notmatch '^[JjYy]') {
                Write-Warn "Hoppet over: $path"
                continue
            }
        }

        try {
            Remove-Item $path -Recurse -Force
            Write-OK "Slettet: $path"
            $found = $true
        }
        catch {
            Write-Err "Kunne ikke slette: $path - $($_.Exception.Message)"
        }
    }
}

# 4. Fjern snarveier
Write-Step "Fjerner snarveier..."
$shortcutPaths = @(
    "$env:PUBLIC\Desktop\Mistral Suite.lnk",
    "$env:PUBLIC\Desktop\MistralApp.lnk",
    "$env:USERPROFILE\Desktop\Mistral Suite.lnk",
    "$env:USERPROFILE\Desktop\MistralApp.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Mistral Suite.lnk"
)

foreach ($shortcut in $shortcutPaths) {
    if (Test-Path $shortcut) {
        try {
            Remove-Item $shortcut -Force
            Write-OK "Fjernet snarvei: $shortcut"
            $found = $true
        }
        catch {
            Write-Warn "Kunne ikke fjerne snarvei: $shortcut"
        }
    }
}

# Resultat
if (-not $found) {
    Write-OK "Ingen tidligere installasjoner funnet"
} else {
    Write-OK "Avinstallering fullført"
    Write-Host "`nDu kan nå installere den nye versjonen trygt." -ForegroundColor Green
}
