# Bitwarden SSO PowerShell Module
# Version: 1.0.0

# Module-scope variabler
$script:ModuleRoot = $PSScriptRoot
$script:EnvFilePath = Join-Path $ModuleRoot "../../../.env"

function Initialize-BitwardenEnvironment {
    [CmdletBinding()]
    param()

    try {
        $envPath = Join-Path $PSScriptRoot "../../../.env"
        Write-Verbose "Leter etter .env fil: $envPath"

        if (-not (Test-Path $envPath)) {
            throw "Finner ikke .env fil på: $envPath"
        }

        $envContent = Get-Content $envPath

        foreach ($line in $envContent) {
            if ($line -match '^([^#][^=]+)=(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                Set-Item -Path "env:$key" -Value $value -ErrorAction Stop
                Write-Verbose "Satt miljøvariabel: $key"
            }
        }

        Write-Host "✅ Miljøvariabler lastet inn" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Feil ved initialisering av miljøvariabler: $_"
        return $false
    }
}

function Get-BitwardenLoginStatus {
    [CmdletBinding()]
    param()

    try {
        $bw = Get-Command bw -ErrorAction Stop
        $status = & bw status | ConvertFrom-Json
        return $status
    }
    catch {
        Write-Error "Kunne ikke hente Bitwarden-status: $_"
        return $null
    }
}

function Connect-BitwardenSSO {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Email = $env:BITWARDEN_EMAIL
    )

    try {
        Write-Verbose "Sjekker Bitwarden CLI-status..."
        $status = Get-BitwardenLoginStatus

        if (-not $status -or $status.status -eq "unauthenticated") {
            Write-Host "🔑 Starter SSO-pålogging..."
            if ($Email) {
                Write-Verbose "Bruker e-post: $Email"
                & bw login --sso --email $Email
            } else {
                & bw login --sso
            }
            return $true
        }

        switch ($status.status) {
            "locked" {
                Write-Host "🔒 Bitwarden er låst. Låser opp..."
                & bw unlock
            }
            "unlocked" {
                Write-Host "✅ Allerede pålogget til Bitwarden" -ForegroundColor Green
            }
            default {
                Write-Host "⚠️ Ukjent status: $($status.status)" -ForegroundColor Yellow
                Write-Host "🔄 Starter ny SSO-pålogging..."
                & bw login --sso
            }
        }

        return $true
    }
    catch {
        Write-Error "Feil ved SSO-tilkobling: $_"
        return $false
    }
}

function Get-BitwardenQuickStatus {
    [CmdletBinding()]
    param()

    try {
        $status = Get-BitwardenLoginStatus

        if (-not $status) {
            throw "Kunne ikke hente Bitwarden-status"
        }

        $result = [PSCustomObject]@{
            IsLoggedIn = $status.status -eq "unlocked"
            Status = $status.status
            UserId = $status.userId
            LastSync = $status.lastSync
        }

        return $result
    }
    catch {
        Write-Error "Feil ved statushenting: $_"
        return $null
    }
}

function Disconnect-BitwardenSSO {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    try {
        Write-Verbose "Logger ut av Bitwarden..."

        # Forsøk å logge ut
        if ($Force) {
            & bw logout --quiet
        } else {
            & bw logout
        }

        # Fjern eventuelle gjenværende sesjonsvariabler
        Remove-Item Env:\BW_SESSION -ErrorAction SilentlyContinue

        Write-Host "✅ Logget ut av Bitwarden" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Feil ved utlogging: $_"
        return $false
    }
}

function Connect-BitwardenSSO {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Email = $env:BITWARDEN_EMAIL,

        [Parameter()]
        [switch]$ForceReconnect
    )

    try {
        # Hvis ForceReconnect, logg ut først
        if ($ForceReconnect) {
            Write-Verbose "Tvungen rekobling aktivert, logger ut først..."
            Disconnect-BitwardenSSO -Force
        }

        Write-Verbose "Sjekker Bitwarden CLI-status..."
        $status = Get-BitwardenLoginStatus

        if (-not $status -or $status.status -eq "unauthenticated") {
            Write-Host "🔑 Starter SSO-pålogging..."
            if ($Email) {
                Write-Verbose "Bruker e-post: $Email"
                & bw login --sso --email $Email
            } else {
                & bw login --sso
            }
            return $true
        }

        switch ($status.status) {
            "locked" {
                Write-Host "🔒 Bitwarden er låst. Låser opp..."
                & bw unlock
            }
            "unlocked" {
                if ($ForceReconnect) {
                    Write-Verbose "Tvungen rekobling, starter ny pålogging..."
                    Disconnect-BitwardenSSO -Force
                    & bw login --sso --email $Email
                } else {
                    Write-Host "✅ Allerede pålogget til Bitwarden" -ForegroundColor Green
                }
            }
            default {
                Write-Host "⚠️ Ukjent status: $($status.status)" -ForegroundColor Yellow
                Write-Host "🔄 Starter ny SSO-pålogging..."
                & bw login --sso
            }
        }

        return $true
    }
    catch {
        Write-Error "Feil ved SSO-tilkobling: $_"
        return $false
    }
}

function Reset-BitwardenAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email,

        [Parameter()]
        [switch]$ClearBrowser,

        [Parameter()]
        [switch]$Force
    )

    try {
        Write-Host "🧹 Starter fullstendig kontoopprydding..." -ForegroundColor Yellow

        # 1. Fjern alle Bitwarden-sesjoner
        Write-Verbose "1/5: Fjerner Bitwarden-sesjoner..."
        Disconnect-BitwardenSSO -Force
        Remove-Item Env:\BW_SESSION -ErrorAction SilentlyContinue

        # 2. Fjern Azure AD tokens
        Write-Verbose "2/5: Fjerner Azure AD tokens..."
        $clearTokenScript = {
            $paths = @(
                "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache",
                "$env:LOCALAPPDATA\.IdentityService\*",
                "$env:LOCALAPPDATA\Packages\Microsoft.AAD.BrokerPlugin*"
            )

            foreach ($path in $paths) {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
        Start-Process powershell -Verb RunAs -ArgumentList "-Command & {$clearTokenScript}" -Wait

        # 3. Rens nettleserdata hvis ønsket
        if ($ClearBrowser) {
            Write-Verbose "3/5: Renser nettleserdata..."
            Start-Process "rundll32.exe" -ArgumentList "InetCpl.cpl,ClearMyTracksByProcess 255" -Wait
        }

        # 4. Verifiser at alt er fjernet
        Write-Verbose "4/5: Verifiserer opprydding..."
        $status = Get-BitwardenLoginStatus
        if ($status) {
            Write-Warning "Bitwarden-sesjon eksisterer fortsatt. Prøver hard reset..."
            & bw logout --quiet
            Start-Sleep -Seconds 2
        }

        # 5. Start ny pålogging
        Write-Verbose "5/5: Starter ny SSO-pålogging..."
        Write-Host "🔄 Kobler til med $Email..." -ForegroundColor Cyan
        & bw login --sso --email $Email

        Write-Host "✅ Kontoopprydding fullført" -ForegroundColor Green
        Write-Host "📝 Tips: Hvis du fortsatt har problemer, prøv å logge ut av Microsoft-kontoen i nettleseren og logge inn på nytt" -ForegroundColor Yellow

        return $true
    }
    catch {
        Write-Error "Feil ved kontoopprydding: $_"
        return $false
    }
}

function Test-AzureADConnection {
    [CmdletBinding()]
    param()

    try {
        Write-BitwardenLog "Tester Azure AD-tilkobling..." -Type Info

        # Sjekk om Azure AD PowerShell-modulen er installert
        if (-not (Get-Module -ListAvailable -Name AzureAD)) {
            Write-BitwardenLog "Installerer Azure AD PowerShell-modul..." -Type Info
            Install-Module -Name AzureAD -Force -AllowClobber -Scope CurrentUser
        }

        # Importer modulen
        Import-Module AzureAD -ErrorAction Stop

        # Prøv å koble til Azure AD
        try {
            Connect-AzureAD -ErrorAction Stop
            Write-BitwardenLog "Azure AD-tilkobling vellykket!" -Type Success

            # Hent og vis brukerkonto-informasjon
            $currentUser = Get-AzureADCurrentSessionInfo
            Write-BitwardenLog "Pålogget som: $($currentUser.Account)" -Type Info
            Write-BitwardenLog "Tenant: $($currentUser.TenantDomain)" -Type Info

            return $true
        }
        catch {
            Write-BitwardenLog "Kunne ikke koble til Azure AD. Prøv å logge inn manuelt først." -Type Error
            Write-BitwardenLog "Tips: Gå til https://portal.azure.com og logg inn" -Type Info
            return $false
        }
    }
    catch {
        Write-BitwardenLog "Feil ved Azure AD-test: $_" -Type Error
        return $false
    }
}

function Reset-BitwardenAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Email,

        [Parameter()]
        [switch]$ClearBrowser,

        [Parameter()]
        [switch]$Force
    )

    try {
        Write-BitwardenLog "Starter fullstendig kontoopprydding..." -Type Info

        # 1. Fjern alle tidligere tilstander
        Clear-BitwardenState

        # 2. Test Azure AD-tilkobling
        if (-not (Test-AzureADConnection)) {
            throw "Kunne ikke verifisere Azure AD-tilkobling"
        }

        # 3. Rens nettleserdata hvis ønsket
        if ($ClearBrowser) {
            Write-BitwardenLog "Renser nettleserdata..." -Type Info
            Start-Process "rundll32.exe" -ArgumentList "InetCpl.cpl,ClearMyTracksByProcess 255" -Wait
        }

        # 4. Start ny pålogging
        Write-BitwardenLog "Starter ny SSO-pålogging for $Email..." -Type Info
        & bw login --sso --email $Email

        Write-BitwardenLog "Kontoopprydding fullført" -Type Success
        return $true
    }
    catch {
        Write-BitwardenLog "Feil ved kontoopprydding: $_" -Type Error
        return $false
    }
}

Export-ModuleMember -Function @(
    'Initialize-BitwardenEnvironment',
    'Connect-BitwardenSSO',
    'Disconnect-BitwardenSSO',
    'Get-BitwardenQuickStatus',
    'Reset-BitwardenAccount',
    'Test-AzureADConnection'
)