param(
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$IncludeInstaller   # forsøk også med -RunInstaller i siste steg
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$install = Join-Path $root 'Install.ps1'

if (-not (Test-Path $install))
{
    Write-Host "✗ Fant ikke Install.ps1 i roten: $install" -ForegroundColor Red
    exit 1
}

# Forsøksprofiler – økende "gjennomslagskraft"
$attempts = @(
    @{ Action = 'Full'; Configuration = $Configuration; Force = $false; Silent = $false; SkipUninstall = $false; NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $false; SkipUninstall = $false; NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $false; NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $false; RunInstaller = $false },
    @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $true; RunInstaller = $false }
)

if ($IncludeInstaller)
{
    $attempts += @{ Action = 'Full'; Configuration = $Configuration; Force = $true; Silent = $true; SkipUninstall = $true; NoInno = $false; RunInstaller = $true }
}

# Loggoppsett
$logDir = Join-Path $root 'Output\logs'
if (-not (Test-Path $logDir))
{
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "run-$ts.log"
param(
[ValidateSet('Release', 'Debug')]
[string]$Configuration = 'Release',
[switch]$IncludeInstaller,
[switch]$SkipUninstallEarly
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $root 'Run-MistralSuite.ps1'
if (-not (Test-Path $runner)) {
Write-Host "✗ Fant ikke Run-MistralSuite.ps1 i roten: $runner" -ForegroundColor Red
exit 1
}

$args = @('-Configuration', $Configuration)
if ($IncludeInstaller)   {
$args += '-IncludeInstaller'
}
if ($SkipUninstallEarly) {
$args += '-SkipUninstallEarly'
}

& $runner @args
exit $LASTEXITCODE
Start-Transcript -Path $transcript -Force | Out-Null

$attemptNum = 0
foreach ($a in $attempts) {
$attemptNum++
Write-Host ""
Write-Host ("==> Forsøk {0}/{1}: Action={2}, Config={3}, Force={4}, Silent={5}, SkipUninstall={6}, NoInno={7}, RunInstaller={8}" -f `
        $attemptNum, $attempts.Count, $a.Action, $a.Configuration, $a.Force, $a.Silent, $a.SkipUninstall, $a.NoInno, $a.RunInstaller) -ForegroundColor Cyan

$args = @(
'-Action', $a.Action,
'-Configuration', $a.Configuration
)
if ($a.Force)         {
$args += '-Force'
}
if ($a.Silent)        {
$args += '-Silent'
}
if ($a.SkipUninstall) {
$args += '-SkipUninstall'
}
if ($a.NoInno)        {
$args += '-NoInno'
}
if ($a.RunInstaller)  {
$args += '-RunInstaller'
}

# kall wrapperen – den håndterer navngitt videre-splatting
& $install @args

$code = $LASTEXITCODE
if ($code -eq 0) {
Write-Host ("✓ Suksess på forsøk {0}. Logg: {1}" -f $attemptNum, $transcript) -ForegroundColor Green
Stop-Transcript | Out-Null
exit 0
} else {
Write-Host ("⚠ Forsøk {0} feilet (kode {1}). Fortsetter..." -f $attemptNum, $code) -ForegroundColor DarkYellow
}
}

Write-Host "✗ Alle forsøk feilet. Se logg for detaljer:" -ForegroundColor Red
Write-Host "  $transcript" -ForegroundColor DarkGray
Stop-Transcript | Out-Null
exit 1
