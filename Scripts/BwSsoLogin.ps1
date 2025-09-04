#Requires -Version 5.1

# Konstanter
$SCRIPT_CONFIG = @{
    Messages = @{
        NotFound = "❌ bw (Bitwarden CLI) ikke funnet. Installer: npm install -g @bitwarden/cli"
        Starting = "==> Starter Bitwarden SSO server på port {0}..."
        Running = "✅ SSO-server kjører nå (PID: {0})"
        Exit = "Trykk Ctrl+C for å avslutte"
    }
    LoginArgs = @(
        "login",
        "--sso",
        "--clientid", # Korrigert fra --client-id
        "{0}",
        "--tenantid", # Korrigert fra --tenant-id
        "{1}"
    )
}

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",

[Parameter(Mandatory = $false)]
[string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",

[Parameter(Mandatory = $false)]
[ValidateRange(1, 65535)]
[int]$Port = 8065
)

$ErrorActionPreference = 'Stop'

function Get-BitwardenPath {
$bwPath = (Get-Command "bw" -ErrorAction SilentlyContinue).Path
if (-not $bwPath) {
Write-Host $SCRIPT_CONFIG.Messages.NotFound -ForegroundColor Red
exit 1
}
return $bwPath
}

function Start-BitwardenSso {
param (
[string]$BwPath,
[string]$ClientId,
[string]$TenantId,
[int]$Port
)

$env: BW_PORT = $Port
Write-Host ($SCRIPT_CONFIG.Messages.Starting -f $Port) -ForegroundColor Cyan

$loginArgs = $SCRIPT_CONFIG.LoginArgs -f $ClientId, $TenantId
$process = Start-Process -FilePath $BwPath -ArgumentList $loginArgs -PassThru -NoNewWindow

Write-Host ($SCRIPT_CONFIG.Messages.Running -f $process.Id) -ForegroundColor Green
Write-Host $SCRIPT_CONFIG.Messages.Exit -ForegroundColor Yellow

return $process
}

# Hovedprogramflyt
try {
$bwPath = Get-BitwardenPath
$ssoProcess = Start-BitwardenSso -BwPath $bwPath -ClientId $ClientId -TenantId $TenantId -Port $Port
$ssoProcess.WaitForExit()
}
finally {
if ($ssoProcess -and -not $ssoProcess.HasExited) {
$ssoProcess.Kill()
}
}