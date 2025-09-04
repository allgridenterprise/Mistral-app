# Build-NativeTools.ps1
# Kompilerer C++-verktøy for Bitwarden-automatisering

param(
    [switch]$Force,     # Tving rekompilering selv om .exe finnes
    [switch]$Verbose    # Vis detaljert output
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { Write-Host $m -ForegroundColor $c }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

$root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
$nativeDir = Join-Path $root "NativeTools"

if (-not (Test-Path $nativeDir)) {
    ERR "NativeTools-mappen finnes ikke: $nativeDir"
    exit 1
}

Say "Bygger native verktøy i: $nativeDir"

# Finn tilgjengelige kompilatorer
$compilers = @()

# 1) Visual Studio Build Tools (cl.exe)
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    try {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($vsPath) {
            $vcvarsall = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
            if (Test-Path $vcvarsall) {
                $compilers += @{
                    Name = "MSVC"
                    SetupCmd = "`"$vcvarsall`" x64"
                    CompileCmd = "cl /EHsc /O2 {SOURCE} /Fe:{TARGET} /link User32.lib Shlwapi.lib"
                }
            }
        }
    } catch {
        if ($Verbose) { WARN "VS detection feilet: $($_.Exception.Message)" }
    }
}

# 2) MinGW (g++)
$mingwPaths = @(
    "C:\mingw64\bin\g++.exe",
    "C:\msys64\mingw64\bin\g++.exe", 
    "C:\TDM-GCC-64\bin\g++.exe"
)
foreach ($gppPath in $mingwPaths) {
    if (Test-Path $gppPath) {
        $compilers += @{
            Name = "MinGW"
            SetupCmd = ""
            CompileCmd = "`"$gppPath`" -std=c++17 -O2 -static {SOURCE} -o {TARGET}"
        }
        break
    }
}

# 3) g++ i PATH
try {
    $null = Get-Command "g++" -ErrorAction Stop
    $compilers += @{
        Name = "GCC"
        SetupCmd = ""
        CompileCmd = "g++ -std=c++17 -O2 -static {SOURCE} -o {TARGET}"
    }
} catch { }

if ($compilers.Count -eq 0) {
    ERR @"
Ingen C++-kompilator funnet. Installer en av følgende:
1) Visual Studio Build Tools: https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022
2) MinGW-w64: https://www.mingw-w64.org/downloads/
3) MSYS2 med mingw-w64: https://www.msys2.org/
"@
    exit 2
}

$compiler = $compilers[0]
Say "Bruker kompilator: $($compiler.Name)"

# Bygger funksjon
function Build-CppFile($sourcePath, $targetName) {
    $source = Join-Path $nativeDir $sourcePath
    $target = Join-Path $nativeDir "$targetName.exe"

    if (-not (Test-Path $source)) {
        WARN "Kilde ikke funnet: $source"
        return $false
    }

    if ((Test-Path $target) -and -not $Force) {
        $sourceTime = (Get-Item $source).LastWriteTime
        $targetTime = (Get-Item $target).LastWriteTime
        if ($targetTime -gt $sourceTime) {
            OK "$targetName.exe er oppdatert"
            return $true
        }
    }

    Say "Kompilerer $sourcePath → $targetName.exe"

    try {
        $cmd = $compiler.CompileCmd -replace '\{SOURCE\}', "`"$source`"" -replace '\{TARGET\}', "`"$target`""

        if ($compiler.SetupCmd) {
            # Kjør med Visual Studio environment
            $batchScript = @"
@echo off
call $($compiler.SetupCmd)
$cmd
"@
            $tempBat = [System.IO.Path]::GetTempFileName() + ".bat"
            $batchScript | Set-Content $tempBat -Encoding ASCII

            $result = & cmd.exe /c "`"$tempBat`"" 2>&1
            Remove-Item $tempBat -ErrorAction SilentlyContinue
        } else {
            # Direkte kommando
            $result = Invoke-Expression $cmd 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            ERR "Kompilering feilet for $targetName"
            if ($Verbose) { Write-Host $result }
            return $false
        }

        if (Test-Path $target) {
            OK "Bygget $targetName.exe"
            return $true
        } else {
            ERR "Kompilering fullført, men $targetName.exe ble ikke opprettet"
            return $false
        }
    } catch {
        ERR "Feil under kompilering av $targetName`: $($_.Exception.Message)"
        return $false
    }
}

# Bygg begge verktøyene
$success = $true

if (-not (Build-CppFile "BwSsoOrchestrator.cpp" "BwSsoOrchestrator")) {
    $success = $false
}

if (-not (Build-CppFile "BwServiceLogin.cpp" "BwServiceLogin")) {
    $success = $false
}

if ($success) {
    OK @"
Kompilering fullført! Du kan nå teste:

Interaktiv SSO (desktop):
  .\NativeTools\BwSsoOrchestrator.exe --item "Mistral API Key"

Headless (CI/CD):
  `$env:BW_CLIENTID="<service-account-id>"
  `$env:BW_CLIENTSECRET="<service-account-secret>"
  .\NativeTools\BwServiceLogin.exe --get-password "Mistral API Key"
"@
} else {
    ERR "En eller flere kompilatorer feilet"
    exit 1
}
