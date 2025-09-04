#requires -Version 7.0
param(
    [switch]$RunStart # Kjør Start-Mistral-Full etter reparasjon
)

$ErrorActionPreference = 'Stop'

function W([string]$m,[string]$c='Cyan'){ Write-Host "==> $m" -ForegroundColor $c }
function OK([string]$m){ Write-Host "✓ $m" -ForegroundColor Green }
function WARN([string]$m){ Write-Host "⚠ $m" -ForegroundColor DarkYellow }
function ERR([string]$m){ Write-Host "✗ $m" -ForegroundColor Red }

# Finn prosjektrot
$scriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$projectRoot = Split-Path -Parent $scriptDir
$scriptsDir  = Join-Path $projectRoot 'Scripts'

$installPath = Join-Path $scriptsDir  'Install-MistralSuite.ps1'
$startPath   = Join-Path $scriptsDir  'Start-Mistral-Full.ps1'
$csprojPath  = Join-Path $projectRoot 'MistralApp.csproj'
$fixProfile  = Join-Path $scriptsDir  'Fix-BuildProfile.ps1'

# Backup
$backupDir = Join-Path $projectRoot 'Output\backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Backup-File([string]$path){
    if (-not (Test-Path $path)) { return }
    $name = [IO.Path]::GetFileName($path)
    $dest = Join-Path $backupDir "$stamp.$name.bak"
    Copy-Item $path $dest -Force
    W ("Backup: {0} -> {1}" -f $name, $dest) 'DarkGray'
}

function Sanitize-InstallScript([string]$path){
    if (-not (Test-Path $path)) { ERR "Installer ikke funnet: $path"; return }
    Backup-File $path
    $raw = Get-Content -Path $path -Raw -Encoding UTF8

    # Fjern alle markdown-kodegjerder (``` og ```powershell) linjevis
    $content = ($raw -split "`r?`n")
    $clean = foreach($ln in $content){
        if ($ln -match '^\s*```(?:powershell)?\s*$') { continue }
        $ln
    }

    # Fjern eksplisitte [CmdletBinding()] hvis den står i veien
    $text = [regex]::Replace(($clean -join "`n"), '^\s*\[CmdletBinding\(\)\]\s*', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)

    # Sørg for at #requires er øverst (fjern ev. eksisterende og sett korrekt)
    $text = [regex]::Replace($text, '^\s*#requires\s+-Version\s+[\d\.]+\s*', '', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $text = "#requires -Version 7.0`n" + $text.TrimStart()

    Set-Content -Path $path -Value $text -Encoding UTF8
    OK "Sanitert Install-MistralSuite.ps1 (fjernet kodegjerder/normalisert topp)"
}

function Sanitize-StartScript([string]$path){
    if (-not (Test-Path $path)) { return }
    Backup-File $path
    $txt = Get-Content -Path $path -Raw -Encoding UTF8
    # Normaliser eldre referanser til $root -> $projectRoot for Fix-BuildProfile/lookup
    $txt = $txt -replace 'Join-Path\s+\$root\s+''Scripts\\Fix-BuildProfile\.ps1''', 'Join-Path $projectRoot ''Scripts\Fix-BuildProfile.ps1'''
    $txt = $txt -replace 'Get-ChildItem\s+-Path\s+\$root\s+-Filter\s+''MistralApp\.csproj''', 'Get-ChildItem -Path $projectRoot -Filter ''MistralApp.csproj'''
    Set-Content -Path $path -Value $txt -Encoding UTF8
    OK "Start-Mistral-Full.ps1 verifisert"
}

function Sanitize-Csproj([string]$path){
    if (-not (Test-Path $path)) { ERR "Mangler csproj: $path"; return }
    Backup-File $path
    [xml]$xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($path)
    $proj = $xml.SelectSingleNode("/*[local-name()='Project']")
    if (-not $proj) { ERR "Ugyldig csproj (mangler <Project>)"; return }

    # Fjern Remove-noder som ekskluderer GUI
    $removeTargetsCompile = @(
        "Views\FileBrowserView.xaml.cs",
        "Views\ConfiguratorView.xaml.cs",
        "MainWindow.xaml.cs"
    )
    $removeTargetsPage = @(
        "Views\FileBrowserView.xaml",
        "Views\ConfiguratorView.xaml",
        "MainWindow.xaml"
    )
    foreach($t in $removeTargetsCompile){
        $nodes = $proj.SelectNodes("*[local-name()='ItemGroup']/*[local-name()='Compile' and @Remove='$t']")
        if ($nodes) { foreach($n in @($nodes)) { $null = $n.ParentNode.RemoveChild($n) } }
    }
    foreach($t in $removeTargetsPage){
        $nodes = $proj.SelectNodes("*[local-name()='ItemGroup']/*[local-name()='Page' and @Remove='$t']")
        if ($nodes) { foreach($n in @($nodes)) { $null = $n.ParentNode.RemoveChild($n) } }
    }

    $xml.Save($path)
    OK "Ryddet csproj (GUI-filer inkluderes)"
}

# Kjør reparasjon
W "Starter auto-reparasjon..." 'Cyan'
Sanitize-InstallScript -path $installPath
Sanitize-StartScript   -path $startPath
Sanitize-Csproj        -path $csprojPath

# Oppdater via Fix-BuildProfile – deaktiver MSI her for å unngå Wix-støy
if (Test-Path $fixProfile) {
    try {
        & $fixProfile -CsprojPath $csprojPath -EnableInstaller:$false
        if ($LASTEXITCODE -eq 0) { OK "Fix-BuildProfile fullført" } else { WARN "Fix-BuildProfile returnerte $LASTEXITCODE" }
    } catch {
        WARN "Fix-BuildProfile feilet: $($_.Exception.Message)"
    }
} else {
    WARN "Fix-BuildProfile.ps1 ikke funnet – hopper over"
}

OK "Auto-reparasjon ferdig."
if ($RunStart) {
    if (Test-Path $startPath) {
        W "Starter full installasjonssekvens..." 'Cyan'
        & $startPath -Configuration 'Release'
    } else {
        WARN "Start-skript ikke funnet: $startPath"
    }
}
