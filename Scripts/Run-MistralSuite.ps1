param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$IncludeInstaller, # prøv et siste steg med -RunInstaller
    [switch]$SkipUninstallEarly  # skru på SkipUninstall allerede i tidlige forsøk
)

# Finn kanonisk installer
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$install = Join-Path $root 'Scripts\Install-MistralSuite.ps1'
if (-not (Test-Path $install))
{
    Write-Host "✗ Fant ikke Scripts\Install-MistralSuite.ps1: $install" -ForegroundColor Red
    exit 1
}

# Loggoppsett
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
    param([int]$Tail = 120)
    try
    {
        $pubDir = Join-Path $root 'Output\logs'
        if (-not (Test-Path $pubDir))
        {
            return
        }

        # Velg publish-*.log først, fallback til annen fil om ingen finnes
        $latest = Get-ChildItem -Path $pubDir -Filter 'publish-*.log' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest)
        {
            $latest = Get-ChildItem -Path $pubDir -File -ErrorAction SilentlyContinue |
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

# Forsøksprofiler – økende “gjennomslagskraft”
$attempts = @(
    @{ Action = 'Full'; Configuration = $Configuration; Force = $false; Silent = $false; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $false; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = ([bool]$SkipUninstallEarly); NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $true; RunInstaller = $false }
)
if ($IncludeInstaller)
{
    $attempts += @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $false; RunInstaller = $true }
}

# Konstante metadata vi forwarder
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

    # Bygg navngitt param-tabell (robust splatting)
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

    # Skriv forhåndsvisning
    $preview = $params.Keys | Sort-Object | ForEach-Object { "-$_ $( $params[$_] )" }
    Write-Host ("==> Kaller installer med: {0}" -f ($preview -join ' ')) -ForegroundColor DarkGray

    # Kjør
    & $install @params
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
        Show-LatestPublishLog -Tail 140
        Write-Host "Fortsetter til neste forsøk..." -ForegroundColor DarkYellow
    }
}

Write-Host "✗ Alle forsøk feilet. Se transkript for detaljer:" -ForegroundColor Red
Write-Host "  $transcript" -ForegroundColor DarkGray
Stop-Transcript | Out-Null
exit 1
