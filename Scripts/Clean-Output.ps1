# Clean-Output.ps1
# Rydder Output og samler artefakter (publish, NativeTools, installer) i en ryddig struktur.

param(
    [string]$RootPath,
    [switch]$Purge,         # Slett eksisterende Output før rekonstruksjon
    [switch]$KeepLogs       # Behold eksisterende loggfiler
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { Write-Host $m -ForegroundColor $c }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }

# Finn prosjektrot
if (-not $RootPath -or -not (Test-Path $RootPath)) {
    if ($PSScriptRoot) {
        $RootPath = (Split-Path $PSScriptRoot -Parent)
    } else {
        $RootPath = (Get-Location).Path
    }
}
Say "Prosjektrot: $RootPath"

# Kataloger
$output = Join-Path $RootPath "Output"
$pub    = Join-Path $RootPath "bin\Release\net8.0-windows\win-x64\publish"
$ntDir  = Join-Path $RootPath "NativeTools"

if ($Purge -and (Test-Path $output)) {
    Remove-Item $output -Recurse -Force -ErrorAction SilentlyContinue
    OK "Slettet eksisterende Output"
}

# Etabler struktur
$dirs = @(
    (Join-Path $output "Publish"),
    (Join-Path $output "NativeTools"),
    (Join-Path $output "Installer"),
    (Join-Path $output "Logs")
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# Kopier publish
if (Test-Path $pub) {
    Copy-Item (Join-Path $pub "*") (Join-Path $output "Publish") -Recurse -Force
    OK "Kopierte publish → Output\Publish"
} else {
    WARN "Fant ikke publish-katalog: $pub"
}

# Kopier NativeTools EXE
if (Test-Path $ntDir) {
    Get-ChildItem $ntDir -Filter "*.exe" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $output "NativeTools") -Force
    }
    OK "Kopierte verktøy → Output\NativeTools"
} else {
    WARN "Fant ikke NativeTools-katalog"
}

# Finn Inno Setup-resultat hvis finnes
$installer = Get-ChildItem (Join-Path $RootPath "Output") -Filter "*.exe" -File -ErrorAction SilentlyContinue |
             Where-Object { $_.DirectoryName -eq (Resolve-Path $output).Path } |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($installer) {
    Move-Item $installer.FullName (Join-Path $output "Installer") -Force
    OK "Flyttet installer → Output\Installer"
}

# Opsjonelt beholde/logge
if (-not $KeepLogs) {
    Get-ChildItem (Join-Path $output "Logs") -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

OK "Output er ryddet og samlet."
