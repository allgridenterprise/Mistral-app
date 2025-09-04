#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()][string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",
    [Parameter()][string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [Parameter()][int]$Port = 8065,
    [Parameter()][switch]$Force,
    [Parameter()][switch]$AutoUnlock,
    [Parameter()][switch]$UpdateSession
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Hjelpefunksjoner
function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg) { Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "⚠️ $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg) { Write-Host "❌ $msg" -ForegroundColor Red }

# Funksjon for å sjekke om en port er i bruk
function Test-PortInUse {
    param([int]$Port)
    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        $listener.Stop()
        return $false
    } catch {
        return $true
    }
}

# Funksjon for å finne en ledig port
function Find-FreePort {
    param([int]$StartPort = 8065)
    $port = $StartPort
    while (Test-PortInUse -Port $port) {
        $port++
        if ($port -gt ($StartPort + 100)) {
            throw "Kunne ikke finne en ledig port i området $StartPort-$($StartPort+100)"
        }
    }
    return $port
}

# Funksjon for å avslutte prosesser som blokkerer en port
function Clear-PortProcesses {
    param([int]$Port)
    try {
        $processes = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | 
                    Select-Object -ExpandProperty OwningProcess | 
                    ForEach-Object { Get-Process -Id $_ }

        foreach ($process in $processes) {
            Write-Host "Avslutter prosess som blokkerer port $Port - $($process.ProcessName) (PID: $($process.Id))" -ForegroundColor Yellow
            Stop-Process -Id $process.Id -Force
        }
    } catch {
        Write-Host "Kunne ikke finne/avslutte prosesser som blokkerer port $Port" -ForegroundColor Yellow
    }
}

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $paths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }

    try {
        $cmd = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Path }
    } catch {}

    return $null
}

Write-Step "Starter Bitwarden SSO-konfigurasjon"

# Finn og verifiser Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk nåværende status
try {
    $statusJson = & $bwPath status --raw | ConvertFrom-Json
    Write-OK "Nåværende status: $($statusJson.status)"

    # Tving utlogging hvis spesifisert
    if ($Force -and $statusJson.status -ne "unauthenticated") {
        Write-Step "Tvinger utlogging..."
        & $bwPath logout
    }
} catch {
    Write-Warn "Kunne ikke hente status: $_"
}

# Håndter port for SSO-pålogging
if (Test-PortInUse -Port $Port) {
    Write-Warn "Port $Port er i bruk. Prøver å frigjøre..."
    Clear-PortProcesses -Port $Port

    if (Test-PortInUse -Port $Port) {
        $newPort = Find-FreePort -StartPort ($Port + 1)
        Write-Warn "Bruker alternativ port: $newPort"
        $Port = $newPort
    }
}

# Sett miljøvariabel for Bitwarden port
$env:BW_PORT = $Port

# Kjør SSO-pålogging
Write-Step "Starter SSO-pålogging..."
$loginArgs = @(
    "login",
    "--sso",
    "--client-id", $ClientId,
    "--tenant-id", $TenantId
)

Write-Host "Kjører: $bwPath $($loginArgs -join ' ')" -ForegroundColor Gray
& $bwPath $loginArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "SSO-pålogging feilet"
    exit 1
}

Write-OK "SSO-pålogging vellykket"

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock --raw
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"

        if ($UpdateSession -and $unlockResult) {
            $env:BW_SESSION = $unlockResult
            Write-OK "BW_SESSION oppdatert"
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
    }
}

# Synkroniser vault
Write-Step "Synkroniserer vault..."
try {
    & $bwPath sync
    Write-OK "Vault synkronisert"
} catch {
    Write-Warn "Kunne ikke synkronisere vault: $_"
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"

# Tips for videre bruk
Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "1. Bruk 'bw sync' for å synkronisere vault manuelt" -ForegroundColor Cyan
Write-Host "2. Bruk 'bw status' for å sjekke tilkoblingsstatus" -ForegroundColor Cyan
Write-Host "3. Bruk 'bw lock' for å låse vault" -ForegroundColor Cyan

$ErrorActionPreference = 'Stop'

# Hjelpefunksjoner
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "⚠️ $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "❌ $msg" -ForegroundColor Red }

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $paths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }

    try {
        $cmd = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Path }
    } catch {}

    return $null
}

Write-Step "Starter Bitwarden SSO-konfigurasjon"

# Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk status
try {
    $statusOutput = & $bwPath status 2>$null
    if ($statusOutput) {
        $statusJson = $statusOutput | ConvertFrom-Json
        $status = $statusJson.status
        Write-OK "Nåværende status: $status"
    }
} catch {
    Write-Warn "Kunne ikke hente status"
}

# Logg ut hvis tvunget
if ($Force) {
    Write-Step "Logger ut..."
    & $bwPath logout
}

# SSO-innlogging
Write-Step "Starter SSO-innlogging..."
$loginArgs = @("login", "--sso")
if ($Email) { $loginArgs += "--email"; $loginArgs += $Email }
if ($OrganizationId) { $loginArgs += "--organization-id"; $loginArgs += $OrganizationId }

Write-Host "Kjører: $bwPath $($loginArgs -join ' ')" -ForegroundColor Gray
& $bwPath $loginArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "SSO-innlogging feilet"
    exit 1
}
Write-OK "SSO-innlogging vellykket"

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"
    } else {
        Write-Err "Kunne ikke låse opp vault"
    }
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"
Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "1. Bruk 'bw sync' for å synkronisere vault" -ForegroundColor Cyan
Write-Host "2. Bruk 'bw status' for å sjekke status" -ForegroundColor Cyan
Write-Host "3. Bruk 'bw lock' for å låse vault" -ForegroundColor Cyan

Write-Host "`nTrykk Enter for å avslutte..." -ForegroundColor Yellow
$null = Read-Host
[CmdletBinding()]
param(
    [Parameter()][string]$Email = "dan@allgrid.com",
    [Parameter()][string]$OrganizationId = "allgrid",
    [Parameter()][string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",
    [Parameter()][string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [Parameter()][switch]$Force,
    [Parameter()][switch]$AutoUnlock,
    [Parameter()][switch]$UpdateSession
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Hjelpefunksjoner
function Write-Step([string]$msg) { 
    Write-Host "`n==> $msg" -ForegroundColor Cyan 
}

function Write-OK([string]$msg) { 
    Write-Host "✅ $msg" -ForegroundColor Green 
}

function Write-Warn([string]$msg) { 
    Write-Host "⚠️ $msg" -ForegroundColor Yellow 
}

function Write-Err([string]$msg) { 
    Write-Host "❌ $msg" -ForegroundColor Red 
}

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $potentialPaths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $potentialPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    try {
        $bwCommand = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($bwCommand) {
            return $bwCommand.Path
        }
    } catch {}

    return $null
}

# Start hovedskript
Write-Step "Konfigurerer Bitwarden SSO"

# Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk nåværende status
try {
    $statusOutput = & $bwPath status | ConvertFrom-Json
    Write-OK "Nåværende status: $($statusOutput.status)"

    # Tving utlogging hvis spesifisert
    if ($Force -and $statusOutput.status -ne "unauthenticated") {
        Write-Step "Tvinger utlogging..."
        & $bwPath logout
    }
} catch {
    Write-Warn "Kunne ikke hente status: $_"
}

# Kjør SSO-pålogging
Write-Step "Starter SSO-pålogging..."

$loginArgs = @(
    "login",
    "--sso",
    "--email", $Email
)

if ($OrganizationId) {
    $loginArgs += "--organization-id"
    $loginArgs += $OrganizationId
}

Write-Host "Kjører: $bwPath $($loginArgs -join ' ')" -ForegroundColor Gray
& $bwPath $loginArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "SSO-pålogging feilet"
    exit 1
}

Write-OK "SSO-pålogging vellykket"

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock --raw
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"

        if ($UpdateSession -and $unlockResult) {
            $env:BW_SESSION = $unlockResult
            Write-OK "BW_SESSION oppdatert"
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
        exit 1
    }
}

Write-Step "Synkroniserer vault..."
try {
    & $bwPath sync
    Write-OK "Vault synkronisert"
} catch {
    Write-Warn "Kunne ikke synkronisere vault: $_"
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"
Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "1. Bruk 'bw sync' for å synkronisere vault manuelt" -ForegroundColor Cyan
Write-Host "2. Bruk 'bw status' for å sjekke tilkoblingsstatus" -ForegroundColor Cyan
Write-Host "3. Bruk 'bw lock' for å låse vault" -ForegroundColor Cyan

# Vent på brukerbekreftelse før avslutning
Write-Host "`nTrykk Enter for å avslutte..." -ForegroundColor Yellow
$null = Read-Host
[CmdletBinding()]
param(
    [Parameter()][string]$Email = "dan@allgrid.com",
    [Parameter()][string]$OrganizationId = "allgrid",
    [Parameter()][string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",
    [Parameter()][string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [Parameter()][int]$Port = 8065,
    [Parameter()][switch]$Force,
    [Parameter()][switch]$AutoUnlock,
    [Parameter()][switch]$UpdateSession,
    [Parameter()][switch]$TestSsoUrl,
    [Parameter()][switch]$SkipGraphSetup
)

# Grunnleggende oppsett
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Hjelpefunksjoner
function Write-Step([string]$msg) { 
    Write-Host "`n==> $msg" -ForegroundColor Cyan 
}

function Write-OK([string]$msg) { 
    Write-Host "✅ $msg" -ForegroundColor Green 
}

function Write-Warn([string]$msg) { 
    Write-Host "⚠️ $msg" -ForegroundColor Yellow 
}

function Write-Err([string]$msg) { 
    Write-Host "❌ $msg" -ForegroundColor Red 
}

# Funksjon for å sjekke om en port er i bruk
function Test-PortInUse {
    param([int]$Port)

    try {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
        $listener.Start()
        $listener.Stop()
        return $false
    } catch {
        return $true
    }
}

# Funksjon for å finne en ledig port
function Find-FreePort {
    param([int]$StartPort = 8065)

    $port = $StartPort
    while (Test-PortInUse -Port $port) {
        $port++
        if ($port -gt ($StartPort + 100)) {
            throw "Kunne ikke finne en ledig port i området $StartPort-$($StartPort+100)"
        }
    }
    return $port
}

# Funksjon for å avslutte prosesser som blokkerer en port
function Clear-PortProcesses {
    param([int]$Port)

    try {
        $processes = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | 
                    Select-Object -ExpandProperty OwningProcess | 
                    ForEach-Object { Get-Process -Id $_ }

        foreach ($process in $processes) {
            Write-Host "Avslutter prosess som blokkerer port $Port - Navn: $($process.ProcessName), PID: $($process.Id)" -ForegroundColor Yellow
            Stop-Process -Id $process.Id -Force
        }
    } catch {
        Write-Host "Kunne ikke finne prosesser som blokkerer port $Port" -ForegroundColor Yellow
    }
}

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $potentialPaths = @(
        "$env:USERPROFILE\bitwarden-cli\bw.exe",
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $potentialPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    try {
        $bwCommand = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($bwCommand) {
            return $bwCommand.Path
        }
    } catch {}

    return $null
}
#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",
    [string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [int]$Port = 8065,
    [switch]$Force,
    [switch]$AutoUnlock,
    [switch]$UpdateSession
)

$ErrorActionPreference = 'Stop'

# Hjelpefunksjoner
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "⚠️ $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "❌ $msg" -ForegroundColor Red }

# Funksjon for å sjekke og frigjøre porter
function Clear-Port {
    param([int]$Port)
    try {
        $processes = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | 
                    Select-Object -ExpandProperty OwningProcess | 
                    ForEach-Object { Get-Process -Id $_ }
        foreach ($process in $processes) {
            Write-Host "Avslutter prosess på port $Port - $($process.ProcessName) (PID: $($process.Id))"
            Stop-Process -Id $process.Id -Force
        }
    } catch {
        Write-Host "Ingen prosesser funnet på port $Port"
    }
}

# Finn Bitwarden CLI
$bwPath = $null
$paths = @(
    "$env:ProgramFiles\Bitwarden CLI\bw.exe",
    "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
    "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
    "$env:APPDATA\npm\bw.exe"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        $bwPath = $path
        break
    }
}

if (-not $bwPath) {
    try {
        $bwCmd = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($bwCmd) { $bwPath = $bwCmd.Path }
    } catch {}
}

Write-Step "Starter Bitwarden SSO-konfigurasjon"

if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk og frigjør port
Clear-Port -Port $Port
$env:BW_PORT = $Port

# Sjekk status
try {
    $status = & $bwPath status | ConvertFrom-Json
    Write-OK "Nåværende status: $($status.status)"

    if ($Force -and $status.status -ne "unauthenticated") {
        Write-Step "Tvinger utlogging..."
        & $bwPath logout
    }
} catch {
    Write-Warn "Kunne ikke hente status"
}

# SSO-innlogging
Write-Step "Starter SSO-pålogging..."
$loginCmd = "login --sso --client-id $ClientId"
Write-Host "Kjører: $bwPath $loginCmd" -ForegroundColor Gray
& $bwPath $loginCmd

if ($LASTEXITCODE -ne 0) {
    Write-Err "SSO-pålogging feilet"
    exit 1
}
Write-OK "SSO-pålogging vellykket"

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock --raw
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"
        if ($UpdateSession -and $unlockResult) {
            $env:BW_SESSION = $unlockResult
            Write-OK "BW_SESSION oppdatert"
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
    }
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"

# Vis tips
Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "1. Bruk 'bw sync' for å synkronisere vault" -ForegroundColor Cyan
Write-Host "2. Bruk 'bw status' for å sjekke status" -ForegroundColor Cyan
Write-Host "3. Bruk 'bw lock' for å låse vault" -ForegroundColor Cyan
# Start hovedskript
Write-Step "Konfigurerer Bitwarden SSO"

# Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk nåværende status
try {
    $statusOutput = & $bwPath status | ConvertFrom-Json
    Write-OK "Nåværende status: $($statusOutput.status)"

    # Tving utlogging hvis spesifisert
    if ($Force -and $statusOutput.status -ne "unauthenticated") {
        Write-Step "Tvinger utlogging..."
        & $bwPath logout
    }
} catch {
    Write-Warn "Kunne ikke hente status: $_"
}

# Håndter port for SSO-pålogging
if (Test-PortInUse -Port $Port) {
    Write-Warn "Port $Port er i bruk. Prøver å frigjøre..."
    Clear-PortProcesses -Port $Port

    if (Test-PortInUse -Port $Port) {
        $newPort = Find-FreePort -StartPort ($Port + 1)
        Write-Warn "Bruker alternativ port: $newPort"
        $Port = $newPort
    }
}

# Kjør SSO-pålogging
Write-Step "Starter SSO-pålogging..."

# Sett miljøvariabel for Bitwarden port
$env:BW_PORT = $Port

$loginArgs = @(
    "login",
    "--sso",
    "--email", $Email
)

if ($OrganizationId) {
    $loginArgs += "--organization-id"
    $loginArgs += $OrganizationId
}

Write-Host "Kjører: $bwPath $($loginArgs -join ' ')" -ForegroundColor Gray
$loginResult = & $bwPath $loginArgs 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Err "SSO-pålogging feilet:"
    Write-Host $loginResult -ForegroundColor Red
    exit 1
}

Write-OK "SSO-pålogging vellykket"

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock --raw
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"

        if ($UpdateSession -and $unlockResult) {
            $env:BW_SESSION = $unlockResult
            Write-OK "BW_SESSION oppdatert"
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
        exit 1
    }
}

# Synkroniser vault
Write-Step "Synkroniserer vault..."
try {
    $syncJob = Start-Job -ScriptBlock {
        param($bwPath)
        & $bwPath sync
    } -ArgumentList $bwPath

    # Vent på synkronisering med timeout
    $null = Wait-Job -Job $syncJob -Timeout 30
    Receive-Job -Job $syncJob
    Remove-Job -Job $syncJob -Force -ErrorAction SilentlyContinue
    Write-OK "Vault synkronisert"
} catch {
    Write-Warn "Kunne ikke synkronisere vault: $_"
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"

# Cleanup og sikre at prosesser avsluttes
Write-Step "Utfører cleanup..."
try {
    # Rydd opp eventuelle gjenværende Bitwarden prosesser
    Get-Process | Where-Object { $_.Name -like "*bitwarden*" -or $_.Name -eq "bw" } | ForEach-Object {
        try {
            $_ | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Host "Avsluttet prosess: $($_.Name) (PID: $($_.Id))" -ForegroundColor Gray
        } catch {
            Write-Warn "Kunne ikke avslutte prosess $($_.Name): $_"
        }
    }

    # Frigjør porten
    if (Test-PortInUse -Port $Port) {
        Clear-PortProcesses -Port $Port
    }
} catch {
    Write-Warn "Cleanup feilet: $_"
}

# Vent på brukerbekreftelse før avslutning
Write-Host "`nKonfigurasjon er fullført!" -ForegroundColor Green
Write-Host "Tips:" -ForegroundColor Cyan
Write-Host "1. Bruk 'bw sync' for å synkronisere vault manuelt" -ForegroundColor Cyan
Write-Host "2. Bruk 'bw status' for å sjekke tilkoblingsstatus" -ForegroundColor Cyan
Write-Host "3. Bruk 'bw lock' for å låse vault" -ForegroundColor Cyan
Write-Host "`nTrykk Enter for å avslutte..." -ForegroundColor Yellow
$null = Read-Host
Write-Host "`nTips:" -ForegroundColor Cyan
Write-Host "1. Bruk 'bw sync' for å synkronisere vault manuelt" -ForegroundColor Cyan
Write-Host "2. Bruk 'bw status' for å sjekke tilkoblingsstatus" -ForegroundColor Cyan
Write-Host "3. Bruk 'bw lock' for å låse vault" -ForegroundColor Cyan
    [Parameter()][string]$Email = "dan@allgrid.com",
    [Parameter()][string]$OrganizationId = "allgrid",
    [Parameter()][string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",
    [Parameter()][string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [Parameter()][switch]$Force,
    [Parameter()][switch]$AutoUnlock,
    [Parameter()][switch]$UpdateSession
)

# Grunnleggende oppsett
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Hjelpefunksjoner
function Write-Step([string]$msg) { 
    Write-Host "`n==> $msg" -ForegroundColor Cyan 
}

function Write-OK([string]$msg) { 
    Write-Host "✅ $msg" -ForegroundColor Green 
}

function Write-Warn([string]$msg) { 
    Write-Host "⚠️ $msg" -ForegroundColor Yellow 
}

function Write-Err([string]$msg) { 
    Write-Host "❌ $msg" -ForegroundColor Red 
}

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $potentialPaths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $potentialPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    try {
        $bwCommand = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($bwCommand) {
            return $bwCommand.Path
        }
    } catch {}

    return $null
}

# Start hovedskript
Write-Step "Konfigurerer Bitwarden SSO"

# Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk nåværende status
try {
    $statusOutput = & $bwPath status | ConvertFrom-Json
    Write-OK "Nåværende status: $($statusOutput.status)"

    # Tving utlogging hvis spesifisert
    if ($Force -and $statusOutput.status -ne "unauthenticated") {
        Write-Step "Tvinger utlogging..."
        & $bwPath logout
    }
} catch {
    Write-Warn "Kunne ikke hente status: $_"
}

# Kjør SSO-pålogging
Write-Step "Starter SSO-pålogging..."

$loginArgs = @(
    "login",
    "--sso",
    "--email", $Email
)

if ($OrganizationId) {
    $loginArgs += "--organization-id"
    $loginArgs += $OrganizationId
}

Write-Host "Kjører: $bwPath $($loginArgs -join ' ')" -ForegroundColor Gray
& $bwPath $loginArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "SSO-pålogging feilet"
    exit 1
}

Write-OK "SSO-pålogging vellykket"

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock --raw
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"

        if ($UpdateSession -and $unlockResult) {
            $env:BW_SESSION = $unlockResult
            Write-OK "BW_SESSION oppdatert"
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
        exit 1
    }
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"
Write-Host "`nTips: Kjør 'bw sync' for å synkronisere vault" -ForegroundColor Cyan

$ErrorActionPreference = 'Stop'

# Hjelpefunksjoner
function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "🟢 $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "🟡 $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "🔴 $msg" -ForegroundColor Red }

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $paths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }

    try {
        $cmd = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Path }
    } catch {}

    return $null
}

Write-Step "Starter Bitwarden SSO-konfigurasjon"

# Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk status
try {
    $status = "unauthenticated"
    $statusOutput = & $bwPath status 2>$null
    if ($statusOutput) {
        $statusJson = $statusOutput | ConvertFrom-Json
        $status = $statusJson.status
    }
    Write-OK "Nåværende status: $status"
} catch {
    Write-Warn "Kunne ikke hente status"
}

# Logg ut hvis tvunget
if ($Force -and $status -ne "unauthenticated") {
    Write-Step "Logger ut..."
    & $bwPath logout
    $status = "unauthenticated"
}

# Logg inn med SSO
if ($status -eq "unauthenticated") {
    Write-Step "Starter SSO-innlogging..."

    $loginArgs = @("login", "--sso")
    if ($ClientId) { $loginArgs += "--client-id"; $loginArgs += $ClientId }
    if ($OrgId) { $loginArgs += "--org-id"; $loginArgs += $OrgId }

    Write-Host "Kjører: $bwPath $($loginArgs -join ' ')" -ForegroundColor Gray
    & $bwPath $loginArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Err "SSO-innlogging feilet"
        exit 1
    }
    Write-OK "SSO-innlogging vellykket"
}

# Lås opp hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock --raw
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"

        # Oppdater session hvis ønsket
        if ($UpdateSession -and $unlockResult) {
            $env:BW_SESSION = $unlockResult
            Write-OK "BW_SESSION oppdatert"
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
        exit 1
    }
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"
Write-Host "`nTips: Kjør 'bw sync' for å synkronisere vault" -ForegroundColor Cyan
    [Parameter()][switch]$Force,
    [Parameter()][switch]$SkipGraphSetup,
    [Parameter()][string]$ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43",
    [Parameter()][string]$TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [Parameter()][string]$OrgId = "d22f0e02-1f57-4948-b925-a932c70f4f8e",
    [Parameter()][switch]$AutoUnlock,
    [Parameter()][switch]$UpdateSession
)

# Sett streng feilhåndtering
$ErrorActionPreference = 'Stop'

# Hjelpefunksjoner for logging
function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "🟢 $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "🟡 $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "🔴 $msg" -ForegroundColor Red }

# Finn Bitwarden CLI
function Find-BitwardenCli {
    $paths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }

    try {
        $cmd = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Path }
    } catch {}

    return $null
}

Write-Step "Konfigurerer Bitwarden SSO..."

# Finn og verifiser Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Sjekk nåværende status
$status = "unauthenticated"
try {
    $statusJson = & $bwPath status --raw | ConvertFrom-Json
    $status = $statusJson.status
    Write-Host "Status: $status"
} catch {
    Write-Warn "Kunne ikke hente status"
}

# Tving utlogging hvis spesifisert
if ($Force -and $status -ne "unauthenticated") {
    Write-Step "Tvinger utlogging..."
    & $bwPath logout
    $status = "unauthenticated"
}

# Logg inn hvis nødvendig
if ($status -eq "unauthenticated") {
    Write-Step "Starter SSO-innlogging..."

    $loginMethods = @(
        @{
            Name = "Standard SSO"
            Args = @("login", "--sso", "--client-id", $ClientId, "--org-id", $OrgId)
        },
        @{
            Name = "Azure AD SSO"
            Args = @("login", "--sso", "--client-id", $ClientId, "--tenant-id", $TenantId)
        }
    )

    $success = $false
    foreach ($method in $loginMethods) {
        Write-Host "Prøver $($method.Name)..." -ForegroundColor Cyan
        & $bwPath $method.Args
        if ($LASTEXITCODE -eq 0) {
            Write-OK "$($method.Name) vellykket"
            $success = $true
            break
        }
        Write-Warn "$($method.Name) feilet"
        Start-Sleep -Seconds 2
    }

    if (-not $success) {
        Write-Err "Ingen innloggingsmetoder fungerte"
        exit 1
    }
}

# Lås opp vault hvis ønsket
if ($AutoUnlock) {
    Write-Step "Låser opp vault..."
    $unlockResult = & $bwPath unlock
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Vault låst opp"

        if ($UpdateSession) {
            $env:BW_SESSION = $unlockResult | 
                Select-String -Pattern "export BW_SESSION=""(.+)""" | 
                ForEach-Object { $_.Matches.Groups[1].Value }
            if ($env:BW_SESSION) {
                Write-OK "BW_SESSION oppdatert"
            }
        }
    } else {
        Write-Err "Kunne ikke låse opp vault"
        exit 1
    }
}

Write-OK "Bitwarden SSO-konfigurasjon fullført"

# Vis tips for synkronisering
Write-Host "`nTips: Kjør 'bw sync' for å synkronisere vault`neller bruk 'bw unlock --check' for å verifisere status" -ForegroundColor Cyan

$ErrorActionPreference = 'Stop'

# Forbedrede utdata-funksjoner med emoji-indikatorer
function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "🟢 $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "🟡 $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "🔴 $msg" -ForegroundColor Red }

function Find-BitwardenCli {
    if ($CliPath -and (Test-Path $CliPath)) {
        return $CliPath
    }
    
    $potentialPaths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )
    
    foreach ($path in $potentialPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    try {
        $bwInPath = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($bwInPath) {
            return $bwInPath.Path
        }
    } catch {}
    
    return $null
}

function Execute-BitwardenCommand([string]$command, [switch]$IgnoreErrors) {
    if (!$bwPath) {
        throw "Bitwarden CLI ikke funnet"
    }
    
    # Vis kommandoen som skal kjøres
    Write-Host "Kjører: $bwPath $command" -ForegroundColor DarkGray
    
    try {
        # Split kommandoen riktig og kjør den
        $argsList = @()
        $command.Split() | ForEach-Object {
            if ($_ -ne "") { $argsList += $_ }
        }
        
        $process = Start-Process -FilePath $bwPath -ArgumentList $argsList -NoNewWindow -Wait -PassThru -RedirectStandardOutput "stdout.log" -RedirectStandardError "stderr.log"
        $stdout = Get-Content "stdout.log" -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "stderr.log" -Raw -ErrorAction SilentlyContinue
        
        # Fjern midlertidige filer
        if (Test-Path "stdout.log") { Remove-Item "stdout.log" -Force }
        if (Test-Path "stderr.log") { Remove-Item "stderr.log" -Force }
        
        if ($process.ExitCode -ne 0 -and -not $IgnoreErrors) {
            throw "Bitwarden CLI kommando feilet (ExitCode: $($process.ExitCode)): $command`nFeil: $stderr"
        }
        
        return $stdout
    } catch {
        if (-not $IgnoreErrors) {
            Write-Err "Feil ved utføring av Bitwarden CLI-kommando: $_"
            throw
        } else {
            Write-Warn "Kommando feilet (ignorert): $command"
            return $null
        }
    }
}

# Funksjon for å sjekke og kjøre Azure CLI-kommandoer
function Execute-AzureCliCommand([string]$command, [switch]$IgnoreErrors) {
    try {
        # Sjekk om Azure CLI er installert
        $azCliExists = Get-Command az -ErrorAction SilentlyContinue
        if (-not $azCliExists) {
            Write-Warn "Azure CLI ikke funnet. Installeres via https://aka.ms/installazurecli"
            return $null
        }
        
        # Vis kommandoen som skal kjøres
        Write-Host "Kjører Azure CLI: az $command" -ForegroundColor DarkGray
        
        # Kjør kommandoen og konverter til JSON hvis mulig
        $output = az $command.Split() | Out-String
        try {
            $jsonOutput = $output | ConvertFrom-Json
            return $jsonOutput
        } catch {
            return $output
        }
    } catch {
        if (-not $IgnoreErrors) {
            Write-Err "Feil ved kjøring av Azure CLI-kommando: $_"
            throw
        } else {
            Write-Warn "Azure CLI-kommando feilet (ignorert): az $command"
            return $null
        }
    }
}

# Ny funksjon for å håndtere alle Bitwarden-statussjekker
function Get-BitwardenCompleteStatus {
    param(
        [string]$BwPath = $bwPath
    )
    
    if (-not $BwPath) {
        Write-Err "Bitwarden CLI ikke funnet"
        return $null
    }
    
    try {
        $rawStatus = & $BwPath status --raw | ConvertFrom-Json
        
        # Utvid statusinformasjonen med brukervennlige detaljer
        $statusInfo = [PSCustomObject]@{
            RawStatus = $rawStatus
            Status = $rawStatus.status
            UserEmail = $rawStatus.userEmail
            IsAuthenticated = $rawStatus.status -ne "unauthenticated"
            IsLocked = $rawStatus.status -eq "locked"
            IsUnlocked = $rawStatus.status -eq "unlocked"
            StatusEmoji = switch ($rawStatus.status) {
                "unauthenticated" { "🔴" }
                "locked" { "🟡" }
                "unlocked" { "🟢" }
                default { "⚪" }
            }
        }
        
        return $statusInfo
    }
    catch {
        Write-Err "Kunne ikke hente Bitwarden-status: $_"
        return $null
    }
}

# Ny funksjon for å enkelt låse opp hvelvet basert på brukerens fungerende mønster
function Unlock-BitwardenVaultSimple {
    param(
        [switch]$SetSessionEnv = $true
    )
    
    try {
        $status = Get-BitwardenCompleteStatus
        
        if ($status.IsUnlocked) {
            Write-OK "Vault er allerede låst opp"
            
            if ($SetSessionEnv) {
                $env:BW_SESSION = & $bwPath unlock --raw --check
                Write-OK "BW_SESSION er oppdatert"
            }
            
            return $true
        }
        
        if ($status.IsLocked) {
            Write-Warn "Vault er låst. Prøver å låse opp..."
            $sessionKey = & $bwPath unlock --raw
            
            if ($sessionKey -and $sessionKey.Length -gt 10) {
                if ($SetSessionEnv) {
                    $env:BW_SESSION = $sessionKey
                    Write-OK "Vault er låst opp og BW_SESSION er satt"
                } else {
                    Write-OK "Vault er låst opp"
                }
                return $true
            } else {
                Write-Err "Klarte ikke å låse opp vault"
                return $false
            }
        }
        
        if (-not $status.IsAuthenticated) {
            Write-Err "Du er ikke logget inn i Bitwarden CLI"
            return $false
        }
        
        return $false
    }
    catch {
        Write-Err "Feil under opplåsing: $_"
        return $false
    }
}

# Ny funksjon for å synkronisere hvelvet slik brukeren gjorde det
function Sync-BitwardenVaultSimple {
    param(
        [string]$SessionKey = $env:BW_SESSION
    )
    
    Write-Step "Synkroniserer vault..."
    
    try {
        if (-not $SessionKey) {
            $status = Get-BitwardenCompleteStatus
            if ($status.IsUnlocked) {
                $SessionKey = & $bwPath unlock --raw --check
                $env:BW_SESSION = $SessionKey
            } else {
                Write-Err "Ingen gyldig sesjonsnøkkel. Lås opp vault først"
                return $false
            }
        }
        
        & $bwPath sync --session $SessionKey | Out-Null
        Write-OK "Vault synkronisert"
        return $true
    }
    catch {
        Write-Err "Feil under synkronisering: $_"
        return $false
    }
}

# Start av hovedskript
Write-Step "Konfigurerer Bitwarden SSO-integrasjon for MistralApp"

# 1. Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (!$bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Hjelpefunksjoner
function Write-Step([string]$msg) { 
    Write-Host "`n==> $msg" -ForegroundColor Cyan 
}

function Write-OK([string]$msg) { 
    Write-Host "🟢 $msg" -ForegroundColor Green 
}

function Write-Warn([string]$msg) { 
    Write-Host "🟡 $msg" -ForegroundColor Yellow 
}

function Write-Err([string]$msg) { 
    Write-Host "🔴 $msg" -ForegroundColor Red 
}

function Find-BitwardenCli {
    $potentialPaths = @(
        "$env:ProgramFiles\Bitwarden CLI\bw.exe",
        "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
        "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
        "$env:APPDATA\npm\bw.exe"
    )

    foreach ($path in $potentialPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    try {
        $bwCommand = Get-Command "bw" -ErrorAction SilentlyContinue
        if ($bwCommand) {
            return $bwCommand.Path
        }
    } catch {}

    return $null
}

function Test-AzureAD {
    param(
        [string]$ClientId,
        [string]$TenantId
    )

    if ($SkipGraphSetup) {
        Write-Warn "Azure AD-test hoppet over (SkipGraphSetup=true)"
        return $true
    }

    try {
        $null = Get-Command -Name "Get-MsalToken" -ErrorAction Stop
    } catch {
        Write-Warn "MSAL.PS modul ikke funnet. Installerer..."
        Install-Module -Name MSAL.PS -Scope CurrentUser -Force
    }

    try {
        $null = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Interactive
        Write-OK "Azure AD-tilkobling OK"
        return $true
    } catch {
        Write-Err "Azure AD-tilkobling feilet: $_"
        return $false
    }
}

function Initialize-BitwardenSso {
    param(
        [string]$BwPath,
        [string]$ClientId,
        [string]$TenantId,
        [string]$SsoOrgId
    )

    # Sjekk status først
    $status = "unauthenticated"
    try {
        $statusJson = & $BwPath status 2>$null | ConvertFrom-Json
        $status = $statusJson.status
        Write-Host "Bitwarden status: $status"
    } catch {
        Write-Warn "Kunne ikke hente Bitwarden-status"
    }

    # Tving utlogging hvis spesifisert
    if ($Force -and $status -ne "unauthenticated") {
        Write-Step "Tvinger utlogging..."
        & $BwPath logout
        $status = "unauthenticated"
    }

    if ($status -eq "unauthenticated") {
        Write-Step "Starter SSO-innlogging..."

        $loginMethods = @(
            @{
                Name = "Azure SSO"
                Args = @("login", "--sso", "--client-id", $ClientId, "--tenant-id", $TenantId)
            },
            @{
                Name = "Bitwarden SSO"
                Args = @("login", "--sso", "--org-id", $SsoOrgId)
            }
        )

        foreach ($method in $loginMethods) {
            Write-Host "Prøver $($method.Name)..." -ForegroundColor Cyan
            & $BwPath $method.Args
            if ($LASTEXITCODE -eq 0) {
                Write-OK "$($method.Name) vellykket"

                if ($AutoUnlock) {
                    Write-Host "Låser opp vault..." -ForegroundColor Cyan
                    $unlockResult = & $BwPath unlock --check
                    if ($LASTEXITCODE -eq 0) {
                        Write-OK "Vault allerede låst opp"
                    } else {
                        & $BwPath unlock
                    }
                }

                return $true
            }
            Write-Warn "$($method.Name) feilet"
            Start-Sleep -Seconds 2
        }

        Write-Err "Ingen innloggingsmetoder fungerte"
        return $false
    }

    Write-OK "Allerede logget inn som $status"
    return $true
}

# Hovedlogikk
Write-Step "Konfigurerer Bitwarden SSO-integrasjon"

# Finn Bitwarden CLI
$bwPath = Find-BitwardenCli
if (-not $bwPath) {
    Write-Err "Bitwarden CLI ikke funnet. Installer med: npm install -g @bitwarden/cli"
    exit 1
}
Write-OK "Fant Bitwarden CLI: $bwPath"

# Test Azure AD-tilkobling
$azureOk = Test-AzureAD -ClientId $ClientId -TenantId $TenantId

# Initialiser Bitwarden SSO
$success = Initialize-BitwardenSso -BwPath $bwPath -ClientId $ClientId -TenantId $TenantId -SsoOrgId $SsoOrgId

if ($success) {
    Write-OK "Bitwarden SSO-konfigurasjon fullført"
    if ($TestSsoUrl) {
        $ssoUrl = "https://vault.bitwarden.com/#/sso?organizationId=$SsoOrgId"
        Write-Host "Åpner SSO URL: $ssoUrl"
        Start-Process $ssoUrl
    }
    exit 0
} else {
    Write-Err "Bitwarden SSO-konfigurasjon feilet"
    exit 1
}

# Konfigurerer Bitwarden SSO-integrasjon for MistralApp
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Standard verdier hvis ikke angitt
if (-not $ClientId) { $ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43" }
if (-not $TenantId) { $TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e" }
if (-not $SsoOrgId) { $SsoOrgId = "d22f0e02-1f57-4948-b925-a932c70f4f8e" }

# Forbedrede utdata-funksjoner med emoji-indikatorer
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Standard verdier hvis ikke angitt
if (-not $ClientId) { $ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43" }
if (-not $TenantId) { $TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e" }
if (-not $SsoOrgId) { $SsoOrgId = "d22f0e02-1f57-4948-b925-a932c70f4f8e" }

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

Write-Step "Konfigurerer Bitwarden SSO-integrasjon for MistralApp"

# Sjekk om Bitwarden CLI er installert
$bwPath = $null
$potentialPaths = @(
    "$env:ProgramFiles\Bitwarden CLI\bw.exe",
    "${env:ProgramFiles(x86)}\Bitwarden CLI\bw.exe",
    "$env:LOCALAPPDATA\Programs\Bitwarden CLI\bw.exe",
    "$env:APPDATA\npm\bw.exe"
)

foreach ($path in $potentialPaths) {
    if (Test-Path $path) {
        $bwPath = $path
        break
    }
}

if (-not $bwPath) {
    $bwCommand = Get-Command "bw" -ErrorAction SilentlyContinue
    if ($bwCommand) {
        $bwPath = $bwCommand.Path
    }
}

if ($bwPath) {
    Write-Host "🟢 Fant Bitwarden CLI: $bwPath"
} else {
    Write-Host "🔴 Bitwarden CLI ikke funnet. Installer med:" -ForegroundColor Red
    Write-Host "npm install -g @bitwarden/cli" -ForegroundColor Yellow
    exit 1
}

# Sjekk nåværende status
$status = "unauthenticated"
try {
    $statusOutput = & $bwPath status | Out-String
    $statusJson = $statusOutput | ConvertFrom-Json
    $status = $statusJson.status
    Write-Host "Nåværende status: 🔵 $status"
} catch {
    Write-Host "Nåværende status: 🔴 $status"
}

# Hvis tvunget rekonfigurasjon, logg ut først
if ($Force -and $status -ne "unauthenticated") {
    Write-Host "`n==> Tvunget rekonfigurasjon valgt, logger ut..."
    & $bwPath logout
    $logoutResult = $?
    Write-Host "🟢 Utlogging fullført" -ForegroundColor $(if ($logoutResult) { "Green" } else { "Yellow" })
    $status = "unauthenticated"
}

if ($status -eq "unauthenticated") {
    Write-Step "Logger inn med SSO..."

    # Test Azure AD-tilkobling først
    Write-Step "Tester Azure AD-tilkobling..."
    $msalModuleInstalled = Get-Module -ListAvailable MSAL.PS
    if (-not $msalModuleInstalled) {
        Write-Warn "MSAL.PS-modul ikke funnet. Installerer..."
        Install-Module -Name MSAL.PS -Scope CurrentUser -Force
    }

    try {
        $msalToken = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Interactive
        Write-OK "Azure AD-tilkobling OK"
        $azureAdConnected = $true
    } catch {
        Write-Err "Kunne ikke koble til Azure AD: $_"
        Write-Host "Tips: Sjekk at du er pålogget riktig konto i Windows" -ForegroundColor Yellow
        $azureAdConnected = $false
    }

    # Prøv flere SSO-innloggingsmetoder
    $methods = @(
        @{ 
            Desc = "Azure AD SSO"; 
            Args = @("login", "--sso", "--client-id", $ClientId, "--tenant-id", $TenantId); 
            RequiresAzureAd = $true 
        },
        @{ 
            Desc = "Standard Bitwarden SSO"; 
            Args = @("login", "--sso", "--org-id", $SsoOrgId); 
            RequiresAzureAd = $false 
        },
        @{ 
            Desc = "Alternativ SSO"; 
            Args = @("login", "--sso", "--client-id", $ClientId, "--sso-org-id", $SsoOrgId); 
            RequiresAzureAd = $false 
        }
    )

    $success = $false
    foreach ($method in $methods) {
        if ($method.RequiresAzureAd -and -not $azureAdConnected) {
            Write-Warn "Hopper over $($method.Desc) (krever Azure AD-tilkobling)"
            continue
        }

        Write-Host "`nPrøver $($method.Desc)..." -ForegroundColor Cyan
        try {
            $output = & $bwPath $method.Args 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-OK "$($method.Desc) vellykket"
                $success = $true

                if ($AutoUnlock) {
                    Write-Host "Låser opp vault..." -ForegroundColor Cyan
                    $unlockResult = & $bwPath unlock --passwordenv BW_PASSWORD
                    if ($LASTEXITCODE -eq 0) {
                        Write-OK "Vault låst opp"

                        if ($UpdateSession) {
                            $env:BW_SESSION = $unlockResult | Select-String -Pattern "$ export BW_SESSION=""(.+)""" | ForEach-Object { $_.Matches.Groups[1].Value }
                            Write-OK "BW_SESSION oppdatert"
                        }
                    }
                }

                break
            } else {
                Write-Warn "$($method.Desc) feilet med exit code $LASTEXITCODE"
                if ($output) { Write-Host $output -ForegroundColor DarkYellow }
            }
        } catch {
            Write-Err "Feil under $($method.Desc): $_"
        }

        Write-Host "Venter 3 sekunder før neste forsøk..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }

    if (-not $success) {
        Write-Host "❌ Ingen SSO-innloggingsmetoder fungerte" -ForegroundColor Red
        exit 1
    }
}

# Sjekk om API-nøkler er tilgjengelige
Write-Step "Verifiserer API-nøkler..."

$requiredItems = @(
    @{ Name = "Mistral API Key"; Type = "API Key" },
    @{ Name = "Azure Graph API Key"; Type = "API Key" }
)

foreach ($item in $requiredItems) {
    $result = & $bwPath get item $item.Name 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Fant $($item.Name)" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Mangler $($item.Name)" -ForegroundColor Yellow
    }
}

Write-Host "`nBitwarden SSO-konfigurasjon fullført!" -ForegroundColor Green
Write-Host "Tips: Bruk 'bw sync' hvis du ikke ser alle elementer." -ForegroundColor Gray
# 2. Sjekk gjeldende status
$currentStatus = Get-BitwardenCompleteStatus
Write-Host "Nåværende status: $($currentStatus.StatusEmoji) $($currentStatus.Status)"
if ($currentStatus.UserEmail) {
    Write-Host "Bruker: $($currentStatus.UserEmail)"
}

# 4. Logg ut hvis Force brukes
if ($Force) {
    Write-Step "Tvunget rekonfigurasjon valgt, logger ut..."
    try {
        & $bwPath logout | Out-Null
        Write-OK "Utlogging fullført"
    } catch {
        Write-Warn "Utlogging feilet (muligens ikke innlogget): $_"
    }
}

# 5. Sett ClientId og TenantId
if (!$ClientId) { $ClientId = "2a12110a-5f05-4055-a386-aa03ca8b8e43" } # Updated to match Microsoft login URL
if (!$TenantId) { $TenantId = "d22f0e02-1f57-4948-b925-a932c70f4f8e" }

# Hvis TestSsoUrl er satt, generer og åpne SSO URL i nettleser
if ($TestSsoUrl) {
    Write-Step "Genererer og tester Bitwarden SSO URL"
    $ssoUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize" +
              "?client_id=$ClientId" +
              "&redirect_uri=https%3A%2F%2Fsso.bitwarden.com%2Foidc-signin" +
              "&response_type=code" +
              "&scope=openid%20profile%20email"
    
    Write-Host "SSO URL:" -ForegroundColor Cyan
    Write-Host $ssoUrl -ForegroundColor DarkGray
    
    Write-Warn "Åpner SSO URL i standard nettleser..."
    Start-Process $ssoUrl
    
    Write-Host "`nFølg instruksjonene i nettleseren for å fullføre SSO-innloggingen." -ForegroundColor Yellow
    Write-Host "Etter vellykket innlogging, kan du gå tilbake til dette vinduet." -ForegroundColor Yellow
    Read-Host "Trykk Enter for å fortsette etter fullført innlogging"
}

# 6. Logg inn med SSO - Bruk først enkle kommandoen som fungerer
Write-Step "Logger inn med SSO..."

# Bygg login kommando med riktige parametere
$loginCommand = "login --sso"
if ($ClientId) {
    $loginCommand += " --client-id $ClientId"
}
if ($OrgIdentifier) {
    $loginCommand += " --sso-org-identifier $OrgIdentifier"
} elseif ($TenantId) {
    $loginCommand += " --sso-org-id $TenantId"
}

# Prøv login med de oppdaterte parameterne
Write-Host "Kjører: $bwPath $loginCommand" -ForegroundColor DarkGray
$loginOutput = Execute-BitwardenCommand $loginCommand -IgnoreErrors
$loginSuccess = $false

# Sjekk om login var vellykket
$status = Get-BitwardenCompleteStatus
if ($status.IsAuthenticated) {
    Write-OK "SSO-innlogging vellykket"
    $loginSuccess = $true
}

# Hvis den oppdaterte kommandoen ikke fungerer, prøv de andre
if (-not $loginSuccess) {
    # Liste over mulige login-kommandoer å prøve
    $loginCommands = @(
        "login --sso --client-id $ClientId --sso-org-id $TenantId",
        "login --sso --organizationid $TenantId",
        "login --sso --applicationid $ClientId",
        "login --apikey"
    )

    foreach ($cmd in $loginCommands) {
        Write-Warn "Prøver alternativ login-metode: $cmd"
        try {
            $loginResult = Execute-BitwardenCommand $cmd -IgnoreErrors
            
            # Sjekk status etter login-forsøk
            $status = Get-BitwardenCompleteStatus
            if ($status.IsAuthenticated) {
                Write-OK "SSO-innlogging vellykket med kommando: $cmd"
                $loginSuccess = $true
                break
            }
        } catch {
            Write-Warn "Login-metode feilet: $cmd"
            continue
        }
    }
}

if (-not $loginSuccess) {
    Write-Err "Kunne ikke logge inn med noen av de tilgjengelige metodene."
    Write-Warn "Prøv kommandoen manuelt: $bwPath login --sso"
    exit 1
}

# Handle fingerprint verification after login success
if ($loginSuccess) {
    Write-OK "SSO-innlogging vellykket"
    
    # Handle fingerprint verification if specified
    if ($Fingerprint) {
        Write-Step "Verifiserer Bitwarden server fingeravtrykk..."
        
        # Get current fingerprint
        $currentFingerprint = & $bwPath get fingerprint --raw
        $currentFingerprint = $currentFingerprint.Trim()
        
        # Compare with provided fingerprint
        if ($currentFingerprint -eq $Fingerprint) {
            Write-OK "Fingeravtrykk verifisert: $currentFingerprint"
        } else {
            Write-Err "Fingeravtrykk stemmer ikke!"
            Write-Warn "Forventet: $Fingerprint"
            Write-Warn "Faktisk:   $currentFingerprint"
            Write-Warn "Dette kan indikere et sikkerhetsproblem eller en endring på Bitwarden-serveren."
            
            # Ask if user wants to continue anyway
            $choice = Read-Host "Vil du fortsette likevel? (j/n)"
            if ($choice -ne "j" -and $choice -ne "J") {
                Write-Err "Avbryter på grunn av fingeravtrykksmismatch."
                exit 1
            }
        }
    } else {
        # If no fingerprint was provided, we can get and store it
        $fingerprintFile = Join-Path $env:APPDATA "Bitwarden\fingerprint.txt"
        
        # Check if we should offer to save the fingerprint
        if (-not (Test-Path $fingerprintFile)) {
            Write-Warn "Ingen lagret fingeravtrykk funnet."
            $currentFingerprint = & $bwPath get fingerprint --raw
            $currentFingerprint = $currentFingerprint.Trim()
            
            Write-Step "Bitwarden server fingeravtrykk:"
            Write-Host $currentFingerprint -ForegroundColor Cyan
            
            $saveChoice = Read-Host "Vil du lagre dette fingeravtrykket for fremtidig verifisering? (j/n)"
            if ($saveChoice -eq "j" -or $saveChoice -eq "J") {
                try {
                    # Ensure directory exists
                    $directory = Split-Path $fingerprintFile -Parent
                    if (-not (Test-Path $directory)) {
                        New-Item -Path $directory -ItemType Directory -Force | Out-Null
                    }
                    
                    # Store fingerprint
                    $currentFingerprint | Out-File -FilePath $fingerprintFile -Force
                    Write-OK "Fingeravtrykk lagret i $fingerprintFile"
                } catch {
                    Write-Err "Kunne ikke lagre fingeravtrykk: $_"
                }
            }
        }
    }
}

# 7. Automatisk lås opp hvis valgt
if ($AutoUnlock -or $Sync) {
    $unlocked = Unlock-BitwardenVaultSimple -SetSessionEnv:$UpdateSession
    if (-not $unlocked) {
        Write-Warn "Kunne ikke låse opp vault. Visse operasjoner vil ikke fungere"
    }
}

# 8. Synkroniser hvis valgt
if ($Sync) {
    if ($status.IsUnlocked -or $unlocked) {
        $synced = Sync-BitwardenVaultSimple
        if ($synced) {
            Write-OK "Vault synkronisert"
        }
    } else {
        Write-Warn "Vault må være låst opp for å synkronisere"
    }
}

# 9. Vis status etter konfigurering
$finalStatus = Get-BitwardenCompleteStatus
Write-Step "Bitwarden SSO-konfigurasjon er fullført"
Write-Host "Status:    $($finalStatus.StatusEmoji) $($finalStatus.Status)"
Write-Host "Bruker:    $($finalStatus.UserEmail)"
Write-Host "ClientId:  $ClientId"
Write-Host "TenantId:  $TenantId"
if ($OrgIdentifier) {
    Write-Host "Org ID:    $OrgIdentifier"
}

if ($finalStatus.IsUnlocked) {
    Write-OK "Vault er låst opp og klar til bruk"
    
    # Always refresh the session key to prevent "BW_SESSION needs update" warning
    $env:BW_SESSION = & $bwPath unlock --raw --check
    Write-OK "BW_SESSION er oppdatert"
} elseif ($finalStatus.IsAuthenticated) {
    Write-Warn "Du er innlogget, men vault er låst"
    Write-Warn "Lås opp med: $bwPath unlock"
}

# 10. Lag en kjørbar kommando for automatisk oppsett
$autoSetupCmd = @"
# Komplett Bitwarden SSO-setup med ett trinn
function Setup-BitwardenSSO {
    # Sjekk om du er logget inn
    `$bwStatus = bw status --raw | ConvertFrom-Json
    
    if (`$bwStatus.status -eq "unauthenticated") {
        Write-Host "🔴 Du er ikke logget inn i Bitwarden CLI." -ForegroundColor Red
        Write-Host "Prøver å logge inn med SSO..." -ForegroundColor Yellow
        
        # Bruk riktig client ID for SSO-tilkobling
        bw login --sso --client-id $ClientId
        
        `$bwStatus = bw status --raw | ConvertFrom-Json
        
        # Get and store fingerprint after first login
        `$fingerprintFile = Join-Path `$env:APPDATA "Bitwarden\fingerprint.txt"
        if (-not (Test-Path `$fingerprintFile)) {
            try {
                `$fingerprint = bw get fingerprint --raw
                
                # Ensure directory exists
                `$directory = Split-Path `$fingerprintFile -Parent
                if (-not (Test-Path `$directory)) {
                    New-Item -Path `$directory -ItemType Directory -Force | Out-Null
                }
                
                # Store fingerprint
                `$fingerprint | Out-File -FilePath `$fingerprintFile -Force
                Write-Host "🟢 Fingeravtrykk lagret for sikker verifisering." -ForegroundColor Green
            } catch {
                Write-Host "🟡 Kunne ikke lagre fingeravtrykk: `$_" -ForegroundColor Yellow
            }
        }
    } else {
        # Verify fingerprint if already logged in
        `$fingerprintFile = Join-Path `$env:APPDATA "Bitwarden\fingerprint.txt"
        if (Test-Path `$fingerprintFile) {
            `$storedFingerprint = Get-Content `$fingerprintFile -Raw
            `$currentFingerprint = bw get fingerprint --raw
            
            if (`$storedFingerprint.Trim() -ne `$currentFingerprint.Trim()) {
                Write-Host "🔴 Advarsel: Fingeravtrykk stemmer ikke overens!" -ForegroundColor Red
                Write-Host "🔴 Dette kan indikere et sikkerhetsproblem." -ForegroundColor Red
            } else {
                Write-Host "🟢 Bitwarden server fingeravtrykk verifisert." -ForegroundColor Green
            }
        }
    }
    
    if (`$bwStatus.status -eq "locked") {
        Write-Host "🟡 Vault er låst. Prøver å låse opp..." -ForegroundColor Yellow
        `$sessionKey = bw unlock --raw
        if (`$sessionKey -and `$sessionKey.Length -gt 10) {
            `$env:BW_SESSION = `$sessionKey
            Write-Host "🟢 Vault er låst opp og BW_SESSION er satt." -ForegroundColor Green
        } else {
            Write-Host "🔴 Klarte ikke å låse opp vault." -ForegroundColor Red
            return
        }
    } elseif (`$bwStatus.status -eq "unlocked") {
        Write-Host "🟢 Vault er allerede låst opp." -ForegroundColor Green
        # Always update session to prevent warning about BW_SESSION needing update
        `$env:BW_SESSION = bw unlock --raw --check
        Write-Host "🟢 BW_SESSION er oppdatert." -ForegroundColor Green
    } else {
        Write-Host "🔴 Uventet status: `$(`$bwStatus.status)" -ForegroundColor Red
        return
    }
    
    Write-Host "`n==> Synkroniserer vault..." -ForegroundColor Cyan
    try {
        bw sync --session `$env:BW_SESSION | Out-Null
        Write-Host "🟢 Vault synkronisert." -ForegroundColor Green
    } catch {
        Write-Host "🔴 Feil under synkronisering: `$_" -ForegroundColor Red
    }
}

# Kjør funksjonen
Setup-BitwardenSSO
"@

$setupFilePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Setup-BitwardenSSO.ps1"
$autoSetupCmd | Out-File -FilePath $setupFilePath -Encoding utf8

Write-Host "`nEn enkel oppsettfil er opprettet:" -ForegroundColor Cyan
Write-Host "  $setupFilePath" -ForegroundColor Cyan
Write-Host "Kjør denne filen for enkel oppsett av Bitwarden SSO, opplåsning og synkronisering" -ForegroundColor Cyan

# Legg til informasjon om direkte SSO URL test
Write-Host "`nFor å teste SSO-tilkoblingen direkte i nettleser:" -ForegroundColor Cyan
Write-Host "  .\Scripts\Configure-BitwardenSso.ps1 -TestSsoUrl" -ForegroundColor Yellow
