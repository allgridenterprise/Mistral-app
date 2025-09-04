param(
    [ValidateSet('Clean', 'Build', 'Full')]
    [string]$Action = 'Full',
    [string]$Configuration = 'Release',
    [switch]$Force,
    [switch]$Silent,
    [switch]$NoInno,
    [switch]$RunInstaller,
    [switch]$SkipUninstall,
# Merk: Underliggende skript har KeepApiKeys som switch med default $true.
# Vi lar default styre og forwarder ikke eksplisitt false.
    [string]$AppDisplayName = 'Mistral Suite',
    [string]$ExeName = 'MistralApp.exe',
    [switch]$ConfigureBitwardenSSO,
    [string]$BitwardenEmail = 'dan@allgrid.com',
    [int]$SessionTimeout = 1440
)

$script = Join-Path $PSScriptRoot 'Scripts\Install-MistralSuite.ps1'
if (-not (Test-Path $script))
{
    Write-Host "✗ Fant ikke skript: $script" -ForegroundColor Red
    exit 1
}

# Bygg navngitt param-tabell for robust splatting
$params = @{
Action = $Action
Configuration = $Configuration
AppDisplayName = $AppDisplayName
ExeName = $ExeName
BitwardenEmail = $BitwardenEmail
SessionTimeout = $SessionTimeout
}
if ($Force)                 {
$params.Force = $true
}
if ($Silent)                {
$params.Silent = $true
}
if ($NoInno)                {
$params.NoInno = $true
}
if ($RunInstaller)          {
$params.RunInstaller = $true
}
if ($SkipUninstall)         {
$params.SkipUninstall = $true
}
if ($ConfigureBitwardenSSO) {
$params.ConfigureBitwardenSSO = $true
}

Write-Host "==> Starter kanonisk installer: $script" -ForegroundColor Cyan
$preview = $params.GetEnumerator() | ForEach-Object {
"-$($_.Key) $($_.Value)"
}
Write-Host ("==> Args: {0}" -f ($preview -join ' ')) -ForegroundColor DarkGray
& $script @params
