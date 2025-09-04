param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$IncludeInstaller, # forsøk et siste steg med -RunInstaller
    [switch]$SkipUninstallEarly, # skru på SkipUninstall i tidlige forsøk
    [switch]$AutoLaunch          # start GUI-appen etter kjeden
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $root 'Scripts\Install-MistralSuite.ps1'
if (-not (Test-Path $installer))
{
    Write-Host "✗ Fant ikke Scripts\Install-MistralSuite.ps1: $installer" -ForegroundColor Red
    exit 1
}

# Heuristiske standarder: hvis ikke eksplisitt angitt og vi kjører som administrator,
# slå på installer og autostart for "hyllevare"-opplevelse.
try
{
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
            IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin)
    {
        if (-not $PSBoundParameters.ContainsKey('IncludeInstaller'))
        {
            $IncludeInstaller = $true
        }
        if (-not $PSBoundParameters.ContainsKey('AutoLaunch'))
        {
            $AutoLaunch = $true
        }
    }
}
catch
{
}

# Patch build-profilen før forsøkene (deaktiver installer initialt)
$fix = Join-Path $root 'Scripts\Fix-BuildProfile.ps1'
if (Test-Path $fix)
{
    Write-Host "==> Forbereder build-profil (Fix-BuildProfile.ps1)" -ForegroundColor Cyan
    & $fix -CsprojPath (Join-Path $root 'MistralApp.csproj') -EnableInstaller:$false
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "⚠ Build-profil patch feilet, fortsetter likevel..." -ForegroundColor DarkYellow
    }
}
else
{
    Write-Host "⚠ Fant ikke Fix-BuildProfile.ps1 – hopper over build-profil patch" -ForegroundColor DarkYellow
}

# Logg
$logDir = Join-Path $root 'Output\logs'
if (-not (Test-Path $logDir))
{
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "run-$ts.log"
Start-Transcript -Path $transcript -Force | Out-Null

function Show-LatestPublishLog
{
    param([int]$Tail = 140)
    try
    {
        if (-not (Test-Path $logDir))
        {
            return
        }
        $latest = Get-ChildItem -Path $logDir -Filter 'publish-*.log' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest)
        {
            $latest = Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if ($latest)
        {
            Write-Host "— Siste publish-logg: $( $latest.FullName )" -ForegroundColor DarkGray
            $lines = Get-Content -Path $latest.FullName -Tail $Tail -ErrorAction SilentlyContinue
            if ($lines)
            {
                Write-Host "----- Halen av $( $latest.Name ) -----" -ForegroundColor DarkGray
                $lines | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
            }
        }
    }
    catch
    {
        Write-Host "⚠ Kunne ikke lese siste publish-logg: $( $_.Exception.Message )" -ForegroundColor DarkYellow
    }
}

# Forsøkssekvens – økende “gjennomslagskraft”
$attempts = @(
    @{ Action = 'Full'; Configuration = $Configuration; Force = $false; Silent = $false; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $false; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $true; RunInstaller = $false }
)
if ($IncludeInstaller)
{
    # Legg til forsøk med RunInstaller først (kjør installer direkte når mulig)
    $attempts = @(
        @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $false; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $true }
    ) + $attempts
    # Behold også eksisterende "siste" forsøk med RunInstaller for robusthet
    $attempts += @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $false; RunInstaller = $true }
}

# Konstante metadata
$baseParams = @{
    AppDisplayName = 'Mistral Suite'
    ExeName = 'MistralApp.exe'
    BitwardenEmail = 'dan@allgrid.com'
    SessionTimeout = 1440
}

$attemptNum = 0
foreach ($a in $attempts)
{
    $attemptNum++
    Write-Host ""
    Write-Host ("==> Forsøk {0}/{1}: Action={2}, Config={3}, Force={4}, Silent={5}, SkipUninstall={6}, NoInno={7}, RunInstaller={8}" -f `
        $attemptNum, $attempts.Count, $a.Action, $a.Configuration, $a.Force, $a.Silent, $a.SkipUninstall, $a.NoInno, $a.RunInstaller) -ForegroundColor Cyan

    # Navngitt splatting direkte til kanonisk installer
    $params = @{ }
    $params += $baseParams
    $params.Action = $a.Action
    $params.Configuration = $a.Configuration
    if ($a.Force)
    {
        $params.Force = $true
    }
    if ($a.Silent)
    {
        $params.Silent = $true
    }
    if ($a.SkipUninstall)
    {
        $params.SkipUninstall = $true
    }
    if ($a.NoInno)
    {
        $params.NoInno = $true
    }
    if ($a.RunInstaller)
    {
        $params.RunInstaller = $true
    }
    if ($AutoLaunch)
    {
        $params.AutoLaunch = $true
    }

    $preview = $params.Keys | Sort-Object | ForEach-Object { "-$_ $( $params[$_] )" }
    Write-Host ("==> Kaller installer med: {0}" -f ($preview -join ' ')) -ForegroundColor DarkGray

    & $installer @params
    $code = $LASTEXITCODE

    if ($code -eq 0)
    {
        Write-Host ("✓ Suksess på forsøk {0}. Transkript: {1}" -f $attemptNum, $transcript) -ForegroundColor Green
        Stop-Transcript | Out-Null
        exit 0
    }
    else
    {
        Write-Host ("⚠ Forsøk {0} feilet (kode {1}). Viser hale av siste publish-logg (dersom tilgjengelig)..." -f $attemptNum, $code) -ForegroundColor DarkYellow
        Show-LatestPublishLog -Tail 160
        Write-Host "Fortsetter til neste forsøk..." -ForegroundColor DarkYellow
    }
}

Write-Host "✗ Alle forsøk feilet. Se transkript for detaljer:" -ForegroundColor Red
Write-Host "  $transcript" -ForegroundColor DarkGray
Stop-Transcript | Out-Null
exit 1
