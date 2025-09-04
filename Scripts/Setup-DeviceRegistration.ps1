# Setup-DeviceRegistration.ps1
# Genererer nøyaktig device-info for Bitwarden-registrering + Win Hello-konfig

param(
    [switch]$RegisterInBitwarden,  # Opprett device-entry i Bitwarden automatisk
    [switch]$ShowOnly              # Bare vis info, ikke registrer
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { Write-Host $m -ForegroundColor $c }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }

Say "=== WINDOWS DEVICE REGISTRERING FOR BITWARDEN ===" 'Magenta'

# Samle device-informasjon
$deviceInfo = @{
    DeviceName = $env:COMPUTERNAME
    Username = $env:USERNAME
    Domain = $env:USERDOMAIN
    WindowsVersion = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    WindowsBuild = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    MachineGuid = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\Cryptography").MachineGuid
    DeviceId = (Get-CimInstance -Class Win32_ComputerSystemProduct).UUID
    TPMPresent = (Get-Tpm -ErrorAction SilentlyContinue).TpmPresent
    HelloForBusinessStatus = $null
    FaceIdAvailable = $null
    FingerprintAvailable = $null
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Sjekk Windows Hello-status
try {
    $helloStatus = Get-WindowsOptionalFeature -Online -FeatureName "HelloFace" -ErrorAction SilentlyContinue
    $deviceInfo.FaceIdAvailable = ($helloStatus.State -eq "Enabled")
} catch {
    $deviceInfo.FaceIdAvailable = $false
}

# Sjekk for fingerprint
try {
    $fingerprintDevices = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*fingerprint*" -or $_.FriendlyName -like "*biometric*" }
    $deviceInfo.FingerprintAvailable = ($fingerprintDevices.Count -gt 0)
} catch {
    $deviceInfo.FingerprintAvailable = $false
}

# Vis komplett device-informasjon
Say "`n=== DEVICE INFORMASJON ===" 'Yellow'
$deviceInfo.GetEnumerator() | Sort-Object Name | ForEach-Object {
    Say "$($_.Key): $($_.Value)"
}

# Generer Bitwarden Secure Note for device-registrering (gyldig schema for bw CLI)
$noteText = @"
Registrert: $($deviceInfo.Timestamp)
Bruker: $($deviceInfo.Username)@$($deviceInfo.Domain)
Windows: $($deviceInfo.WindowsVersion) (Build $($deviceInfo.WindowsBuild))
TPM: $($deviceInfo.TPMPresent)
Face ID: $($deviceInfo.FaceIdAvailable)
Fingerprint: $($deviceInfo.FingerprintAvailable)
MachineGuid: $($deviceInfo.MachineGuid)
Device ID: $($deviceInfo.DeviceId)
"@

$bitwardenItem = @{
    type = 2               # Secure Note
    name = "Device: $($deviceInfo.DeviceName) ($(Get-Date -Format 'yyyyMMdd'))"
    notes = $noteText
    secureNote = @{ type = 0 }
}

$json = $bitwardenItem | ConvertTo-Json -Depth 10
Say "`n=== BITWARDEN DEVICE JSON ===" 'Yellow'
Say $json

if ($RegisterInBitwarden -and -not $ShowOnly) {
    # Sørg for BW_SESSION
    if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) {
        try {
            Say "BW_SESSION mangler. Forsøker å låse opp hvelv..." 'Yellow'
            $env:BW_SESSION = & bw unlock --raw 2>$null
        } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) {
        WARN "Kunne ikke sette BW_SESSION. Kjør 'bw unlock --raw' og eksporter til BW_SESSION, eller logg inn med SSO først."
    } else {
        # Opprett secure note i Bitwarden
        $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
        try {
            $json | Set-Content $tempFile -Encoding UTF8

            Say "`nRegistrerer device i Bitwarden..." 'Green'
            $result = & bw create item --file $tempFile --session $env:BW_SESSION

            if ($LASTEXITCODE -eq 0) {
                OK "Device registrert i Bitwarden!"
                Say "Resultat: $result"
            } else {
                WARN "Device-registrering feilet: $result"
            }
        } finally {
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }
    }
}

Say "`n=== NESTE STEG ===" 'Magenta'
Say @"
1) Kopier JSON over og opprett 'Secure Note' i Bitwarden med navn: '$($bitwardenDevice.name)'

2) I Bitwarden Admin Console → Policies:
   - Enable "Require biometric unlock" policy
   - Set unlock frequency: 4 hours

3) På denne PC - aktiver Windows Hello:
   - Settings → Accounts → Sign-in options
   - Set up Face ID / Fingerprint

4) Test biometric unlock i Bitwarden Desktop app
"@
