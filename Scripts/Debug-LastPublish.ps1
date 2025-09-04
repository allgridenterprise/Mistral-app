# Debug-LastPublish.ps1
# Viser hale av siste publish-logg og ekstraherer relevante feillinjer

param(
    [int]$Tail = 200,
    [string]$ProjectRoot
)

# Finn prosjektrot (parent av skriptmappen) hvis ikke eksplisitt oppgitt
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProjectRoot -or [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $scriptDir
}

# Bruk prosjektrot → Output\logs
$logDir = Join-Path $ProjectRoot 'Output\logs'
if (-not (Test-Path $logDir))
{
    Write-Host "✗ Ingen loggmappe: $logDir" -ForegroundColor Red
    exit 1
}

$latest = Get-ChildItem -Path $logDir -Filter 'publish-*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latest)
{
    $latest = Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

if (-not $latest)
{
    Write-Host "✗ Fant ingen publish- eller loggfiler i $logDir" -ForegroundColor Red
    exit 1
}

Write-Host "==> Loggfil: $( $latest.FullName )" -ForegroundColor Cyan
Write-Host "`n----- Siste $Tail linjer -----" -ForegroundColor DarkGray
Get-Content -Path $latest.FullName -Tail $Tail -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host $_ -ForegroundColor DarkGray
}

# Ekstraher vanlige feilmønstre
Write-Host "`n----- Feillinjer (CSxxxx / MSBxxxx / MCxxxx / error) -----" -ForegroundColor DarkGray
$errors = Get-Content -Path $latest.FullName -ErrorAction SilentlyContinue | Where-Object {
    $_ -match '(^|\s)(error\s)|(\bCS\d{4}\b)|(\bMSB\d{4}\b)|(\bMC\d{4}\b)'
}
if ($errors -and $errors.Count -gt 0)
{
    $errors | Select-Object -First 120 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}
else
{
    Write-Host "(Ingen tydelige feillinjer funnet i loggen)" -ForegroundColor DarkYellow
}

Write-Host "`nTips: Åpne loggen i editor for full kontekst." -ForegroundColor Gray
