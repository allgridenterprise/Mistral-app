# Hjelpeskript for å holde PowerShell-vinduet åpent
param(
    [string]$ScriptPath,
    [string[]]$ScriptArguments
)

try {
    # Kjør hovedskriptet
    $scriptBlock = [ScriptBlock]::Create("& '$ScriptPath' $($ScriptArguments -join ' ')")
    Invoke-Command -ScriptBlock $scriptBlock
} catch {
    Write-Host "Feil under kjøring av skript: $_" -ForegroundColor Red
} finally {
    # Hold vinduet åpent
    Write-Host "`nTrykk Enter for å avslutte..." -ForegroundColor Yellow
    $null = Read-Host
}
