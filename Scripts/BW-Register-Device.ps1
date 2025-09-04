# BW-Register-Device.ps1
# Samler enhetsinfo og oppretter Secure Note "Device: <PC> (yyyyMMdd-HHmm)" i ønsket org/collection.

param(
    [string]$OrganizationName = "Allgrid",
    [string]$CollectionName   = "Devices",
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function Say($m, [string]$c='Cyan') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }
function OK($m) { Say $m 'Green' }
function WARN($m) { Say $m 'DarkYellow' }
function ERR($m) { Say $m 'Red' }

# Sjekk session
if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) {
    try { $env:BW_SESSION = & bw unlock --raw 2>$null } catch { }
}
if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) { ERR "BW_SESSION mangler. Kjør BW-Login.ps1 først."; exit 1 }

# Enhetsinfo
$dev = @{
    DeviceName = $env:COMPUTERNAME
    Username   = $env:USERNAME
    Domain     = $env:USERDOMAIN
    WindowsVersion = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    WindowsBuild   = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuild
    MachineGuid    = (Get-ItemProperty "HKLM:SOFTWARE\Microsoft\Cryptography").MachineGuid
    DeviceId       = (Get-CimInstance -Class Win32_ComputerSystemProduct).UUID
    Timestamp      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TPMPresent     = $null
    FaceIdAvailable = $false
    FingerprintAvailable = $false
}
try { $dev.TPMPresent = (Get-Tpm -ErrorAction SilentlyContinue).TpmPresent } catch { }
try {
    $hello = Get-WindowsOptionalFeature -Online -FeatureName HelloFace -ErrorAction SilentlyContinue
    $dev.FaceIdAvailable = ($hello.State -eq "Enabled")
} catch { }
try {
    $fp = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match '(fingerprint|biometric)' }
    $dev.FingerprintAvailable = ($fp.Count -gt 0)
} catch { }

$note = @"
Registrert: $($dev.Timestamp)
Bruker: $($dev.Username)@$($dev.Domain)
Windows: $($dev.WindowsVersion) (Build $($dev.WindowsBuild))
TPM: $($dev.TPMPresent)
Face ID: $($dev.FaceIdAvailable)
Fingerprint: $($dev.FingerprintAvailable)
MachineGuid: $($dev.MachineGuid)
Device ID: $($dev.DeviceId)
"@

$name = "Device: $($dev.DeviceName) ($(Get-Date -Format 'yyyyMMdd-HHmm'))"
$item = [ordered]@{
    type = 2
    name = $name
    notes = $note
    secureNote = @{ type = 0 }
}

# Org/collection
$orgId = $null
try {
    $orgs = & bw list organizations --session $env:BW_SESSION | ConvertFrom-Json
    if ($orgs) {
        $org = $orgs | Where-Object { $_.name -like "*$OrganizationName*" } | Select-Object -First 1
        if (-not $org) { $org = $orgs | Select-Object -First 1 }
        if ($org) { $orgId = $org.id; $item.organizationId = $orgId; Say "Organisasjon: $($org.name)" }
    }
} catch { }

$collectionId = $null
if ($orgId -and -not [string]::IsNullOrWhiteSpace($CollectionName)) {
    try {
        $cols = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
        $c = $cols | Where-Object { $_.organizationId -eq $orgId -and $_.name -eq $CollectionName } | Select-Object -First 1
        if (-not $c) {
            $def = @{ name=$CollectionName; organizationId=$orgId; groups=@(); externalId=$null } | ConvertTo-Json
            $tmpC = [IO.Path]::GetTempFileName()+".json"; $def | Set-Content $tmpC -Encoding UTF8
            & bw create org-collection --file $tmpC --session $env:BW_SESSION | Out-Null
            Remove-Item $tmpC -ErrorAction SilentlyContinue
            $cols = & bw list collections --session $env:BW_SESSION | ConvertFrom-Json
            $c = $cols | Where-Object { $_.organizationId -eq $orgId -and $_.name -eq $CollectionName } | Select-Object -First 1
            if ($c) { OK "Opprettet collection: $CollectionName" }
        }
        if ($c) { $collectionId = $c.id }
    } catch { WARN "Collection feilet: $($_.Exception.Message)" }
}
if ($collectionId) { $item.collectionIds = @($collectionId) }

# Opprett
$tmp = [IO.Path]::GetTempFileName()+".json"
try {
    ($item | ConvertTo-Json -Depth 20) | Set-Content $tmp -Encoding UTF8
    Say "Oppretter Secure Note: '$name' ..." 'Green'
    $res = & bw create item --file $tmp --session $env:BW_SESSION
    if ($LASTEXITCODE -ne 0) { ERR "Feil: $res"; exit 2 }
    OK "Opprettet."
} finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
