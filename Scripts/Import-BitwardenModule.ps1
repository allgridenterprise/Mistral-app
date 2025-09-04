$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $scriptPath "Modules\BitwardenSSO"

# Fjern eventuell eksisterende versjon av modulen
Remove-Module BitwardenSSO -ErrorAction SilentlyContinue

# Importer modulen
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    Write-Host "`n✅ Bitwarden-modulen er lastet inn"
    Write-Host "   Tilgjengelige kommandoer:"
    Write-Host "   - Get-BitwardenQuickStatus"
    Write-Host "   - Connect-BitwardenSSO`n"
} else {
    Write-Error "❌ Kunne ikke finne BitwardenSSO-modulen i $modulePath"
}
