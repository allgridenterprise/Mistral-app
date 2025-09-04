[CmdletBinding()]
param(
    [switch]$Persist
)

$ErrorActionPreference = 'Stop'

function W([string]$m,[string]$c='Cyan'){ Write-Host "==> $m" -ForegroundColor $c }
function OK([string]$m){ Write-Host "✓ $m" -ForegroundColor Green }
function WARN([string]$m){ Write-Host "⚠ $m" -ForegroundColor DarkYellow }
function ERR([string]$m){ Write-Host "✗ $m" -ForegroundColor Red }

# Rensefunksjon for innlimt tekst (vanlige chat-korrupsjoner)
function Sanitize-PastedText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $t = $Text
    $rules = @()

    # Fjern zero-width/byte order mark
    $before = $t
    $t = $t -replace "[\u200B\u200C\u200D\uFEFF]", ""
    if ($t -ne $before) { $rules += 'ZeroWidthRemoved' }

    # Bytt typografiske anførselstegn med vanlige
    $before = $t
    $t = $t -replace "[\u2018\u2019]", "'"
    $t = $t -replace "[\u201C\u201D]", '"'
    if ($t -ne $before) { $rules += 'SmartQuotes->ASCII' }

    # Bytt en/em-dash med vanlig bindestrek
    $before = $t
    $t = $t -replace "[\u2013\u2014]", "-"
    if ($t -ne $before) { $rules += 'DashNormalize' }

    # NBSP -> space
    $before = $t
    $t = $t -replace "\u00A0", " "
    if ($t -ne $before) { $rules += 'NBSP->Space' }

    # Fjern kulepunkter/ledende støy i starten av linjen(e)
    $before = $t
    $t = ($t -split "(\r?\n)") `
        | ForEach-Object {
            $_ -replace "^\s*[•\-–—]+\s+", "" `
               -replace "^\s*•\s*", "" `
               -replace "^\s*-\s+", ""
          } `
        | ForEach-Object { $_ } `
        -join ""
    if ($t -ne $before) { $rules += 'LeadingBullet/HyphenTrim' }

    # Normaliser Start-Mistral-kommandoer:
    #  - rett .\ foran skriptnavnet
    #  - fjern tilfeller av \. eller / eller ekstra prikker/brudd
    $before = $t
    $t = $t -replace "^\s*([\\\/]?\.?\\?)\s*(Start\-Mistral\.ps1.*)$", ".\${2}"
    if ($t -ne $before) { $rules += 'Start-Mistral-Normalize' }

    # Kollapsér mange mellomrom til ett (skånsomt)
    $before = $t
    $t = $t -replace " {2,}", " "
    if ($t -ne $before) { $rules += 'SpacesCollapse' }

    # Trim
    $before = $t
    $t = $t.Trim()
    if ($t -ne $before) { $rules += 'Trim' }

    # Beregn endringsgrad (andel fjernede ikke-whitespace-tegn)
    $origNoWS  = ([regex]::Replace($Text, '\s', '')).Length
    $cleanNoWS = ([regex]::Replace($t,    '\s', '')).Length
    $removalRatio = if ($origNoWS -gt 0) { [math]::Max(0, ($origNoWS - $cleanNoWS) / $origNoWS) } else { 0 }

    # Eksponér siste info for loggeren
    $script:SmartPaste_LastInfo = [pscustomobject]@{
        Original      = $Text
        Clean         = $t
        Rules         = $rules
        RemovalRatio  = [math]::Round($removalRatio, 3)
        Host          = $Host.Name
        Pwd           = (Get-Location).Path
    }

    return $t
}

# Lettvekts logg til %TEMP%\MistralSmartPaste\smartpaste-YYYYMMDD.log
$script:SmartPasteLogDir = Join-Path $env:TEMP 'MistralSmartPaste'
function Log-SmartPasteEvent {
    param(
        [string]$Original,
        [string]$Clean,
        [string[]]$Rules,
        [double]$RemovalRatio
    )
    try {
        if (-not (Test-Path $script:SmartPasteLogDir)) {
            New-Item -ItemType Directory -Path $script:SmartPasteLogDir -Force | Out-Null
        }
        $logPath = Join-Path $script:SmartPasteLogDir ("smartpaste-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $hostName = $Host.Name
        # Flate linjer; vis linjeskift som ⏎ for kompakt diagnostikk
        $o = ($Original -replace "(\r?\n)", "⏎")
        $c = ($Clean    -replace "(\r?\n)", "⏎")
        $line = @(
            "[{0}] Host={1} Pwd={2}" -f $stamp, $hostName, (Get-Location).Path
            " Rules=" + (($Rules | Where-Object { $_ }) -join ',')
            (" RemovalRatio={0:P0}" -f $RemovalRatio)
            " Original: " + $o
            " Cleaned : " + $c
            "----"
        ) -join [Environment]::NewLine
        Add-Content -Path $logPath -Value $line -Encoding UTF8
    } catch {
        # Stille feilhåndtering – logging skal ikke forstyrre innliming
    }
}

function Enable-SmartPaste {
    # Krever PSReadLine i terminalen
    if (-not (Get-Module -ListAvailable PSReadLine)) {
        try { Import-Module PSReadLine -ErrorAction Stop }
        catch {
            WARN "PSReadLine er ikke tilgjengelig – smart paste kan ikke aktiveres."
            return
        }
    } else {
        Import-Module PSReadLine -ErrorAction SilentlyContinue | Out-Null
    }

    # Key handler for Ctrl+V og Shift+Insert
    $handler = {
        param($key, $arg)
        try {
            $clip = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace($clip)) { return }
            $clean = Sanitize-PastedText $clip

            # Logg ved endring
            if ($clean -ne $clip) {
                $ratio = 0
                $rules = @()
                if ($script:SmartPaste_LastInfo) {
                    $ratio = $script:SmartPaste_LastInfo.RemovalRatio
                    $rules = $script:SmartPaste_LastInfo.Rules
                }
                Log-SmartPasteEvent -Original $clip -Clean $clean -Rules $rules -RemovalRatio $ratio

                if ($ratio -ge 0.5) {
                    Write-Host "SmartPaste: stor endring registrert og logget i %TEMP%\MistralSmartPaste" -ForegroundColor DarkYellow
                }
            }

            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($clean)
        } catch {
            # Fallback: vanlig paste
            try { [Microsoft.PowerShell.PSConsoleReadLine]::Paste() } catch { }
        }
    }

    try {
        Set-PSReadLineKeyHandler -Key Ctrl+V, Shift+Insert -BriefDescription "SmartPaste" -LongDescription "Sanitizes pasted commands (Mistral Suite)" -ScriptBlock $handler
        # Rå innliming på Ctrl+Shift+V som “bypass”
        Set-PSReadLineKeyHandler -Key Ctrl+Shift+V -Function Paste
        OK "Smart paste er aktiv i denne terminal-økten (Ctrl+V / Shift+Insert). Bypass: Ctrl+Shift+V"
    } catch {
        WARN "Kunne ikke sette key handler (Set-PSReadLineKeyHandler): $($_.Exception.Message)"
    }
}

function Persist-SmartPaste {
    try {
        $profilePath = $PROFILE
        $profileDir = Split-Path -Parent $profilePath
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }

        $block = @"
# --- Smart Paste (Mistral Suite) ---
try {
    if (-not (Get-Module -ListAvailable PSReadLine)) { Import-Module PSReadLine }
    function Sanitize-PastedText {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
        \$t = \$Text
        \$t = \$t -replace "[\u200B\u200C\u200D\uFEFF]", ""
        \$t = \$t -replace "[\u2018\u2019]", "'"
        \$t = \$t -replace "[\u201C\u201D]", '"'
        \$t = \$t -replace "[\u2013\u2014]", "-"
        \$t = \$t -replace "\u00A0", " "
        \$t = (\$t -split "(\r?\n)") | ForEach-Object {
            \$_ -replace "^\s*[•\-–—]+\s+", "" -replace "^\s*•\s*", "" -replace "^\s*-\s+", ""
        } | ForEach-Object { \$_ } -join ""
        \$t = \$t -replace "^\s*([\\\/]?\.?\\?)\s*(Start\-Mistral\.ps1.*)$", ".\${2}"
        \$t = \$t -replace " {2,}", " "
        \$t = \$t.Trim()
        return \$t
    }
    \$handler = {
        param(\$key, \$arg)
        try {
            \$clip = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace(\$clip)) { return }
            \$clean = Sanitize-PastedText \$clip
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert(\$clean)
        } catch {
            try { [Microsoft.PowerShell.PSConsoleReadLine]::Paste() } catch { }
        }
    }
    Set-PSReadLineKeyHandler -Key Ctrl+V, Shift+Insert -BriefDescription "SmartPaste" -LongDescription "Sanitizes pasted commands (Mistral Suite)" -ScriptBlock \$handler
} catch { }
# --- End Smart Paste ---
"@

        # Unngå å duplisere blokken i profilen
        $profileContent = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
        if ($profileContent -notmatch "Smart Paste \(Mistral Suite\)") {
            Add-Content -Path $profilePath -Value $block
            OK "Smart paste er persistert i profilen: $profilePath"
        } else {
            WARN "Smart paste var allerede konfigurert i profilen"
        }
    } catch {
        ERR ("Kunne ikke persistere smart paste i {0}: {1}" -f $PROFILE, $_.Exception.Message)
    }
}

# Aktiver for denne økten
Enable-SmartPaste

# Persister dersom ønsket
if ($Persist) { Persist-SmartPaste }
