#######################################################
# Find-LostMistralScript.ps1
# Finner sannsynlig "tapt" PowerShell-skript som
# avinstallerer, rydder, bygger og lager Inno-installer
# med ekstra hint for SSO/Bitwarden-relaterte spor
#######################################################

param(
    [string]$ProjectPath = "C:\Users\DanSolberg\RiderProjects\Mistral app",
    [switch]$Deep, # Søk også i brukerprofil (Desktop/Downloads/Documents/OneDrive)
    [switch]$OpenBest, # Åpne beste treff automatisk
    [switch]$CopyIntoProject, # Kopier beste treff inn i prosjektets /scripts
    [string]$AuditPath, # Auditer et spesifikt skript (hopper over søk)
    [switch]$AuditOnly, # Kun audit, ikke åpne/kopiere/søke videre
    [switch]$OpenPath, # Åpne -AuditPath eller beste treff etter audit
    [switch]$RunBest            # Kjør beste treff direkte (uten wrapper)
)

Write-Host "`n===== Søker etter tapt build-/installer-skript =====" -ForegroundColor Cyan

# Kataloger å søke i
$searchRoots = New-Object System.Collections.Generic.List[string]
if (Test-Path $ProjectPath)
{
    $searchRoots.Add($ProjectPath)
}

if ($Deep)
{
    $userProfile = $env:USERPROFILE
    $candidateUserDirs = @(
        (Join-Path $userProfile "Desktop"),
        (Join-Path $userProfile "Downloads"),
        (Join-Path $userProfile "Documents"),
        (Join-Path $userProfile "OneDrive")
    )
    foreach ($d in $candidateUserDirs)
    {
        if (Test-Path $d)
        {
            $searchRoots.Add($d)
        }
    }
}

# Filtrering
$excludePathsLike = @(".git", "node_modules", "bin", "obj", ".vs", "packages")

# Nøkkelord for scoring
$keywordGroups = @(
# Kraftige signaler: Avinstallasjon / installer
    @{ Weight = 5; Terms = @("UninstallString", "msiexec", "/x", "Uninstall", "/VERYSILENT", "Compil32.exe", "ISCC.exe", "Inno Setup", ".iss") },
    # Bygg og output
    @{ Weight = 4; Terms = @("MSBuild", "dotnet build", "/t:Clean;Build", "/t:Clean,Build", "/p:OutDir", "Configuration=", "Any CPU", "Release", "Debug") },
    # Opprydding
    @{ Weight = 3; Terms = @("Remove-Item", "Stop-Process", "build", "dist", "Program Files", "Transcript", "Out-Dir", "Clean up", "Cleanup") },
    # csproj inklusjon
    @{ Weight = 3; Terms = @("<Compile Include=", ".csproj", "ItemGroup", "CreateElement", "Include-Missing", "Get-ChildItem *.cs") },
    # 64-bit preferanser (prioriterer skript som låser til x64)
    @{ Weight = 5; Terms = @("x64", "{pf64}", "pf64", "ArchitecturesInstallIn64BitMode", "ArchitecturesAllowed=x64", "DefaultDirName={pf64}", "Use64BitLauncher", "/p:Platform=x64", "PlatformTarget=x64", "64-bit") },
    # Launcher-relatert (prioriterer skript som heter/fungerer som launcher)
    @{ Weight = 5; Terms = @("launcher", "Mistral Suite Launcher", "CreateShortcut", "WScript.Shell", "StartMenu", "DesktopIcon", "Start-Process .*Mistral", "Launcher") },
    # SSO/Bitwarden spor
    @{ Weight = 2; Terms = @("Bitwarden", "SSO", "ClientId", "Secret", "bw.exe", "login --sso") },
    # Logging/UX
    @{ Weight = 1; Terms = @("Write-Host", "Step", "==>", "Status", "Transcript") }
)

function Score-File
{
    param([string]$Path)
    try
    {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
    }
    catch
    {
        return 0
    }
    $score = 0
    foreach ($group in $keywordGroups)
    {
        foreach ($term in $group.Terms)
        {
            if ($content -match [regex]::Escape($term))
            {
                $score += $group.Weight
            }
        }
    }

    # Ekstra vekt på 64-bit, nedvekt på x86/Win32
    $has64 = (
    $content -match "ArchitecturesInstallIn64BitMode" -or
            $content -match "ArchitecturesAllowed\s*=\s*x64" -or
            $content -match "\{pf64\}" -or
            $content -match "\bPlatformTarget\s*=\s*x64\b" -or
            $content -match "/p:Platform\s*=\s*x64" -or
            $content -match "Use64BitLauncher" -or
            $content -match "\bx64\b" -or
            $content -match "64-bit"
    )
    $hasX86 = (
    $content -match "\b(x86|Win32)\b" -or
            $content -match "Program Files \(x86\)"
    )
    if ($has64)
    {
        $score += 6
    }
    if ($hasX86 -and -not $has64)
    {
        $score -= 4
    }

    # Bonus om både uninstall + ISCC + Build finnes
    $hasUninstall = ($content -match "UninstallString" -or $content -match "msiexec" -or $content -match "VERYSILENT")
    $hasInno = ($content -match "Inno Setup" -or $content -match "ISCC" -or $content -match "\.iss")
    $hasBuild = ($content -match "MSBuild" -or $content -match "dotnet build" -or $content -match "OutDir")
    if ($hasUninstall -and $hasInno -and $hasBuild)
    {
        $score += 10
    }
    elseif (($hasInno -and $hasBuild) -or ($hasUninstall -and $hasBuild))
    {
        $score += 6
    }

    # Liten bonus for lengde (mer omfattende skript)
    try
    {
        $lines = ($content -split "`n").Count
        if ($lines -gt 300)
        {
            $score += 5
        }
        elseif ($lines -gt 150)
        {
            $score += 3
        }
        elseif ($lines -gt 80)
        {
            $score += 1
        }
    }
    catch
    {
    }

    # Ekstra poeng for "launcher" i filnavn/innhold
    try
    {
        $fileName = [IO.Path]::GetFileName($Path)
        if ($fileName -match '(?i)launcher' -or $fileName -match '(?i)mistral.*launcher' -or $fileName -match '(?i)suite.*launcher')
        {
            $score += 8
        }
        if ($content -match '(?i)\blauncher\b' -or
                $content -match '(?i)CreateShortcut' -or
                $content -match '(?i)WScript\.Shell' -or
                $content -match '(?i)StartMenu' -or
                $content -match '(?i)DesktopIcon' -or
                $content -match '(?i)Start-Process\s+.*Mistral')
        {
            $score += 3
        }
    }
    catch
    {
    }

    # Ekstra poeng for "launcher" i filnavn/innhold
    try
    {
        $fileName = [IO.Path]::GetFileName($Path)
        if ($fileName -match '(?i)launcher' -or $fileName -match '(?i)mistral.*launcher' -or $fileName -match '(?i)suite.*launcher')
        {
            $score += 8
        }
        if ($content -match '(?i)\blauncher\b' -or
                $content -match '(?i)CreateShortcut' -or
                $content -match '(?i)WScript\.Shell' -or
                $content -match '(?i)StartMenu' -or
                $content -match '(?i)DesktopIcon' -or
                $content -match '(?i)Start-Process\s+.*Mistral')
        {
            $score += 3
        }
    }
    catch
    {
    }

    return $score
}

function Audit-FoundScript
{
    param([string]$Path)
    if (-not (Test-Path $Path))
    {
        Write-Host "Audit: Fil ikke funnet: $Path" -ForegroundColor Red
        return
    }
    $content = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    Write-Host "`n===== Audit av skript =====" -ForegroundColor Cyan
    Write-Host ("Fil: {0}" -f $Path) -ForegroundColor Gray
    try
    {
        $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($fi)
        {
            Write-Host ("Størrelse: {0} KB | Endret: {1}" -f [Math]::Round($fi.Length/1KB, 2), $fi.LastWriteTime) -ForegroundColor Gray
        }
    }
    catch
    {
    }

    function Show([string]$label, [bool]$ok, [string]$hint)
    {
        $icon = if ($ok)
        {
            "✅"
        }
        else
        {
            "⚠️"
        }
        $color = if ($ok)
        {
            "Green"
        }
        else
        {
            "Yellow"
        }
        Write-Host ("{0} {1} : {2}" -f $icon, $label, $hint) -ForegroundColor $color
    }

    $has = @{
        Inno = ($content -match "Inno Setup" -or $content -match "ISCC" -or $content -match "\.iss")
        MSBuild = ($content -match "MSBuild" -or $content -match "dotnet build" -or $content -match "/t:Clean(;|,)Build")
        OutDir = ($content -match "/p:OutDir" -or $content -match "OutDir=")
        Uninstall = ($content -match "UninstayllString" -or $content -match "msiexec" -or $content -match "VERYSILENT")
        StopProcess = ($content -match "Stop-Process")
        Cleanup = ($content -match "Remove-Item" -and $content -match "build" -and $content -match "dist")
        CsInclude = ($content -match "<Compile Include=" -or $content -match "CreateElement\(\"Compile\"\)" -or $content -match "\.csproj")
        Launcher = ($content -match '(?i)\blauncher\b' -or $content -match "CreateShortcut" -or $content -match "StartMenu" -or $content -match "DesktopIcon")
        X64_Inno = ($content -match "ArchitecturesInstallIn64BitMode" -or $content -match "ArchitecturesAllowed\s*=\s*x64" -or $content -match "\{pf64\}" -or $content -match "Use64BitLauncher" -or $content -match "DefaultDirName\s*=\s*\{pf64\}")
        X64_Build = ($content -match "/p:Platform\s*=\s*x64" -or $content -match "PlatformTarget\s*=\s*x64" -or $content -match "\bx64\b")
        X86_Signals = ($content -match "\b(x86|Win32)\b" -or $content -match "Program Files \(x86\)")
    }

    Show "Inno Setup"       $has.Inno        (if ($has.Inno)
    {
        "funnet"
    }
    else
    {
        "mangler"
    })
    Show "Bygg (MSBuild)"   $has.MSBuild     (if ($has.MSBuild) {
    "funnet"
    } else {
    "mangler"
    })
    Show "OutDir"           $has.OutDir      (if ($has.OutDir) {
    "funnet"
    } else {
    "mangler"
    })
    Show "Avinstallasjon"   $has.Uninstall   (if ($has.Uninstall) {
    "funnet"
    } else {
    "mangler"
    })
    Show "Stop-Process"     $has.StopProcess (if ($has.StopProcess) {
    "funnet"
    } else {
    "anbefalt ved avinstallasjon"
    })
    Show "Opprydding"       $has.Cleanup     (if ($has.Cleanup) {
    "funnet"
    } else {
    "mangler"
    })
    Show ".cs-inkludering"  $has.CsInclude   (if ($has.CsInclude) {
    "spor funnet"
    } else {
    "ikke påkrevd hvis SDK-stil"
    })
    Show "Launcher-spor"    $has.Launcher    (if ($has.Launcher) {
    "funnet"
    } else {
    "ikke avgjørende"
    })
    Show "x64 (Inno)"       $has.X64_Inno    (if ($has.X64_Inno) {
    "OK"
    } else {
    "anbefalt: ArchitecturesInstallIn64BitMode/ArchitecturesAllowed=x64/{pf64}/Use64BitLauncher"
    })
    Show "x64 (Build)"      $has.X64_Build   (if ($has.X64_Build) {
    "OK"
    } else {
    "kontroller /p:Platform=x64 eller PlatformTarget=x64"
    })
    if ($has.X86_Signals -and -not ($has.X64_Inno -or $has.X64_Build)) {
    Write-Host "❌ Finner x86/Win32-signaler uten x64 – dette ser ikke ut som 64-bit-only." -ForegroundColor Red
    } elseif ($has.X86_Signals) {
    Write-Host "⚠️ Skriptet inneholder noen x86/Win32-referanser. Verifiser at x64-dominerer." -ForegroundColor Yellow
    } else {
    Write-Host "✅ Ingen tydelige x86/Win32-signaler." -ForegroundColor Green
    }
    Write-Host "===== Slutt på audit =====`n" -ForegroundColor Cyan
}

function Should-Exclude
{
    param([string]$FullPath)
    foreach ($e in $excludePathsLike)
    {
        if ($FullPath -like "*$e*")
        {
            return $true
        }
    }
    return $false
}

# Early audit-modus: Auditer en spesifikk fil og avslutt
if ($AuditPath)
{
    if (Test-Path $AuditPath)
    {
        Audit-FoundScript -Path $AuditPath
        if ($OpenPath -and -not $AuditOnly)
        {
            try
            {
                notepad $AuditPath
            }
            catch
            {
                Write-Host "Kunne ikke åpne i Notepad: $AuditPath" -ForegroundColor Red
            }
        }
        if ($CopyIntoProject -and -not $AuditOnly)
        {
            $scriptsDir = Join-Path $ProjectPath "scripts"
            if (-not (Test-Path $scriptsDir))
            {
                New-Item -ItemType Directory -Path $scriptsDir | Out-Null
            }
            $dest = Join-Path $scriptsDir ([IO.Path]::GetFileName($AuditPath))
            try
            {
                Copy-Item -Path $AuditPath -Destination $dest -Force; Write-Host "Kopiert: $dest" -ForegroundColor Green
            }
            catch
            {
                Write-Host "Kopi feilet: $( $_.Exception.Message )" -ForegroundColor Red
            }
        }
        exit 0
    }
    else
    {
        Write-Host "Audit: Stien finnes ikke: $AuditPath" -ForegroundColor Red
        exit 1
    }
}

# Finn kandidater
$allCandidates = New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach ($root in $searchRoots)
{
    Write-Host "Søker i: $root" -ForegroundColor Yellow
    try
    {
        $files = Get-ChildItem -Path $root -Recurse -Filter *.ps1 -File -ErrorAction SilentlyContinue
        foreach ($f in $files)
        {
            if (-not (Should-Exclude -FullPath $f.FullName))
            {
                $allCandidates.Add($f) | Out-Null
            }
        }
    }
    catch
    {
        Write-Host "  (Hoppet over pga. tilgang): $root" -ForegroundColor DarkGray
    }
}

if ($allCandidates.Count -eq 0)
{
    Write-Host "`nIngen PowerShell-skript funnet i angitte områder." -ForegroundColor Red
    exit 1
}

# Score og sorter
$ranked = @()
foreach ($f in $allCandidates)
{
    $score = Score-File -Path $f.FullName
    if ($score -gt 0)
    {
        $ranked += [pscustomobject]@{
            Path = $f.FullName
            Name = $f.Name
            Directory = $f.DirectoryName
            SizeKB = [Math]::Round($f.Length/1KB, 2)
            Modified = $f.LastWriteTime
            Score = $score
        }
    }
}

if ($ranked.Count -eq 0)
{
    Write-Host "`nFant ingen skript som matcher kriteriene (avinstallasjon/bygg/Inno/ssO)." -ForegroundColor Red
    exit 1
}

$ranked = $ranked | Sort-Object Score, SizeKB, Modified -Descending

Write-Host "`nMest lovende kandidater:" -ForegroundColor Green
$displayTop = [Math]::Min(20, $ranked.Count)
for ($i = 0; $i -lt $displayTop; $i++) {
    $r = $ranked[$i]
    $star = if ($i -eq 0 -and $r.Score -ge 12)
    {
        "⭐ "
    }
    else
    {
        "  "
    }
    Write-Host ("{0}{1,2}. {2} | Score: {3} | Size: {4} KB | Endret: {5}" -f $star, ($i + 1), $r.Name, $r.Score, $r.SizeKB, $r.Modified) -ForegroundColor $( if ($i -eq 0)
    {
        "Yellow"
    }
    else
    {
        "White"
    } )
    Write-Host ("     {0}" -f $r.Path) -ForegroundColor DarkGray
}

$best = $ranked[0]

# Alternativ handling
if ($RunBest)
{
    Write-Host "`nKjører beste treff direkte: $( $best.Name )" -ForegroundColor Cyan
    & $best.Path
    $exit = $LASTEXITCODE
    Write-Host "Skript ferdig. ExitCode: $exit" -ForegroundColor Gray
    exit $exit
}
elseif ($OpenBest)
{
    Write-Host "`nÅpner beste treff: $( $best.Name )" -ForegroundColor Cyan
    try
    {
        notepad $best.Path
    }
    catch
    {
        Write-Host "Kunne ikke åpne i Notepad. Sti: $( $best.Path )" -ForegroundColor Red
    }
}
else
{
    $ans = Read-Host "`nÅpne beste treff i Notepad? ($( $best.Name )) (y/n)"
    if ($ans -match '^(y|yes|ja|j)$')
    {
        notepad $best.Path
    }
}

# Audit av beste treff
if (-not $RunBest)
{
    Audit-FoundScript -Path $best.Path
    if ($OpenPath -and -not $OpenBest)
    {
        try
        {
            notepad $best.Path
        }
        catch
        {
            Write-Host "Kunne ikke åpne i Notepad. Sti: $( $best.Path )" -ForegroundColor Red
        }
    }
}

# Valgfritt: Kopier inn i prosjektet
if ($CopyIntoProject)
{
    $scriptsDir = Join-Path $ProjectPath "scripts"
    if (-not (Test-Path $scriptsDir))
    {
        New-Item -ItemType Directory -Path $scriptsDir | Out-Null
    }
    $dest = Join-Path $scriptsDir $best.Name
    try
    {
        Copy-Item -Path $best.Path -Destination $dest -Force
        Write-Host "Kopiert: $dest" -ForegroundColor Green
    }
    catch
    {
        Write-Host "Kunne ikke kopiere: $( $_.Exception.Message )" -ForegroundColor Red
    }
}
else
{
    $copyAns = Read-Host "Kopiere beste treff inn i prosjektets 'scripts' mappe? (y/n)"
    if ($copyAns -match '^(y|yes|ja|j)$')
    {
        $scriptsDir = Join-Path $ProjectPath "scripts"
        if (-not (Test-Path $scriptsDir))
        {
            New-Item -ItemType Directory -Path $scriptsDir | Out-Null
        }
        $dest = Join-Path $scriptsDir $best.Name
        try
        {
            Copy-Item -Path $best.Path -Destination $dest -Force
            Write-Host "Kopiert: $dest" -ForegroundColor Green
        }
        catch
        {
            Write-Host "Kunne ikke kopiere: $( $_.Exception.Message )" -ForegroundColor Red
        }
    }
}

Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "- Bruk -Deep for å søke i Desktop/Downloads/Documents/OneDrive i tillegg." -ForegroundColor Gray
Write-Host "- Øk sjansen for gjenfinning ved å huske om skriptet refererte til 'ISCC.exe', 'msiexec' eller '.iss'." -ForegroundColor Gray
