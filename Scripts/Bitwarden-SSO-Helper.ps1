# Bitwarden SSO Helper Functions
function Get-BitwardenQuickStatus {
    $status = @{
        IsLoggedIn = $false
        IsUnlocked = $false
        LastSync = $null
    }

    try {
        $bwStatus = bw status --raw | ConvertFrom-Json
        $status.IsLoggedIn = $bwStatus.status -eq "authenticated"
        $status.IsUnlocked = $bwStatus.status -eq "unlocked"

        Write-Host "Bitwarden Status:"
        Write-Host "Logged In: $($status.IsLoggedIn ? '✅' : '❌')"
        Write-Host "Unlocked:  $($status.IsUnlocked ? '✅' : '❌')"
    }
    catch {
        Write-Host "❌ Kunne ikke hente Bitwarden-status: $_"
    }

    return $status
}

function Connect-BitwardenSSO {
    param(
        [switch]$Force
    )

    $clientId = $env:BITWARDEN_CLIENT_ID
    if (-not $clientId) {
        Write-Error "BITWARDEN_CLIENT_ID ikke funnet i miljøvariabler"
        return $false
    }

    try {
        if ($Force) {
            bw logout
        }

        Write-Host "🔐 Kobler til Bitwarden SSO..."
        bw login --sso --client-id $clientId
        return $true
    }
    catch {
        Write-Error "Kunne ikke koble til Bitwarden: $_"
        return $false
    }
}

# Eksporter funksjonene
Export-ModuleMember -Function Get-BitwardenQuickStatus, Connect-BitwardenSSO
