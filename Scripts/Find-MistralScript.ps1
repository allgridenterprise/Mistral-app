    function Clean-ScriptName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    # Fjern eventuelle kopinumre og ekstra tegn
    $cleanName = $ScriptName -replace '^\d+\s*-\s*', '' # Fjerner "1 - " etc.
    $cleanName = $cleanName -replace '[^\x20-\x7E]', '' # Fjerner usynlige tegn
    $cleanName = $cleanName.Trim()

    return $cleanName
    }

    function Find-ProjectScript {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,
        [string]$StartPath = $PWD,
        [int]$MaxDepth = 3
    )

    # Rens filnavnet først
    $ScriptName = Clean-ScriptName $ScriptName

    # Initialize paths array
    $searchPaths = @(
        $StartPath,
        "$StartPath\Scripts",
        [System.IO.Path]::GetDirectoryName($StartPath),
        "$([System.IO.Path]::GetDirectoryName($StartPath))\Scripts"
    )

    # Add parent directories up to MaxDepth
    $currentPath = $StartPath
    for ($i = 0; $i -lt $MaxDepth; $i++) {
        $parentPath = [System.IO.Path]::GetDirectoryName($currentPath)
        if ($parentPath) {
            $searchPaths += $parentPath
            $searchPaths += "$parentPath\Scripts"
            $currentPath = $parentPath
        }
    }

    # Search for the script
    foreach ($path in $searchPaths) {
        $fullPath = Join-Path $path $ScriptName
        if (Test-Path $fullPath) {
            return $fullPath
        }
    }

    return $null
}

function Initialize-MistralEnvironment {
    # Legg til i PowerShell-profilen for permanent konfigurasjon
    $profileContent = @'
# Mistral App Environment
$env:MISTRAL_PROJECT_ROOT = (Get-Location).Path
$env:MISTRAL_SCRIPTS_PATH = Join-Path $env:MISTRAL_PROJECT_ROOT "Scripts"

# Funksjon for å kjøre Mistral scripts
function Run-MistralScript {
    param([string]$ScriptName)
    $scriptPath = Find-ProjectScript -ScriptName $ScriptName
    if ($scriptPath) {
        & $scriptPath
    } else {
        Write-Error "Could not find script: $ScriptName"
    }
}

# Alias for vanlige kommandoer
Set-Alias -Name mrun -Value Run-MistralScript
'@

    # Legg til i PowerShell-profilen
    $profilePath = $PROFILE
    if (-not (Test-Path $profilePath)) {
        New-Item -Path $profilePath -ItemType File -Force
    }

    Add-Content -Path $profilePath -Value "`n# Mistral Environment Configuration" -Force
    Add-Content -Path $profilePath -Value $profileContent -Force

    # Last inn umiddelbart
    . $PROFILE

    Write-Host "Mistral miljø er konfigurert og lastet." -ForegroundColor Green
}

# Eksempel på bruk:
# Initialize-MistralEnvironment
# mrun "Master-MistralApp.ps1"
