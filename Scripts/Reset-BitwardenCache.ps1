# Reset-BitwardenCache.ps1
# Renser alle Bitwarden-data for clean slate Enterprise-oppsett

param(
    [switch]$IncludeCredentialManager,  # Rens også Windows Credential Manager
    [switch]$WhatIf                     # Vis hva som vil bli gjort uten å utføre
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { Write-Host $m -ForegroundColor $c }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

if ($WhatIf) { Say "*** WHATIF-MODUS: Ingen endringer vil bli gjort ***" 'Yellow' }

# 1) Stopp Bitwarden-prosesser
$processes = @("Bitwarden", "bw", "BitwardenPasswordManager")
foreach ($proc in $processes) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | ForEach-Object {
        if ($WhatIf) {
            WARN "Ville stoppet prosess: $($_.Name) (PID: $($_.Id))"
        } else {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            OK "Stoppet prosess: $($_.Name)"
        }
    }
}

# 2) Rens Bitwarden CLI-konfig og cache
$bwPaths = @(
    "$env:APPDATA\Bitwarden CLI",
    "$env:LOCALAPPDATA\Bitwarden CLI", 
    "$env:USERPROFILE\.config\Bitwarden CLI"
)

foreach ($path in $bwPaths) {
    if (Test-Path $path) {
        if ($WhatIf) {
            WARN "Ville slettet: $path"
        } else {
            try {
                Remove-Item $path -Recurse -Force
                OK "Slettet: $path"
            } catch {
                WARN "Kunne ikke slette $path`: $($_.Exception.Message)"
            }
        }
    }
}

# 3) Rens Bitwarden Desktop-app data
$desktopPaths = @(
    "$env:APPDATA\Bitwarden",
    "$env:LOCALAPPDATA\Bitwarden"
)

foreach ($path in $desktopPaths) {
    if (Test-Path $path) {
        if ($WhatIf) {
            WARN "Ville slettet: $path"
        } else {
            try {
                Remove-Item $path -Recurse -Force
                OK "Slettet: $path"
            } catch {
                WARN "Kunne ikke slette $path`: $($_.Exception.Message)"
            }
        }
    }
}

# 4) Rens registry-entries for Bitwarden
$regPaths = @(
    "HKCU:\Software\Bitwarden",
    "HKCU:\Software\8bit Solutions LLC"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        if ($WhatIf) {
            WARN "Ville slettet registry: $regPath"
        } else {
            try {
                Remove-Item $regPath -Recurse -Force
                OK "Slettet registry: $regPath"
            } catch {
                WARN "Kunne ikke slette $regPath`: $($_.Exception.Message)"
            }
        }
    }
}

# 5) Rens Windows Credential Manager (valgfritt)
if ($IncludeCredentialManager) {
    try {
        $creds = cmdkey /list 2>$null | Select-String "bitwarden|8bit"
        foreach ($credLine in $creds) {
            if ($credLine -match "Target:\s*(.+)") {
                $target = $matches[1].Trim()
                if ($WhatIf) {
                    WARN "Ville fjernet credential: $target"
                } else {
                    try {
                        & cmdkey /delete:$target 2>$null
                        OK "Fjernet credential: $target"
                    } catch {
                        WARN "Kunne ikke fjerne credential: $target"
                    }
                }
            }
        }
    } catch {
        WARN "Feil under opprydding av Credential Manager: $($_.Exception.Message)"
    }
}

# 6) Rens browser-cookies (valgfri veiledning)
Say @"

=== MANUELL OPPFØLGING ===
For komplett reset, rens også nettleser-cookies for:
- *.bitwarden.com
- Din Enterprise Bitwarden-URL (hvis selvhost)

Chrome: chrome://settings/cookies → Søk "bitwarden"
Edge: edge://settings/cookies → Søk "bitwarden" 
Firefox: about:preferences#privacy → Cookies and Site Data

=== NESTE STEG FOR ENTERPRISE SSO ===
1) Installer ren Bitwarden CLI: 
   npm install -g @bitwarden/cli

2) Sett Enterprise server (hvis selvhost):
   bw config server https://your-enterprise-url.com

3) Test SSO-login:
   bw login --sso

4) Hvis problemer, sjekk:
   - MS Entra: riktig Redirect URI
   - Bitwarden Admin: SSO-konfig og bruker-tilordning
   - Nettleser: deaktiver popup-blocker for Bitwarden
"@

if ($WhatIf) {
    Say "*** WHATIF fullført. Kjør uten -WhatIf for å utføre endringene. ***" 'Yellow'
} else {
    OK "Bitwarden-cache og data rensket. Klar for Enterprise-oppsett!"
}
