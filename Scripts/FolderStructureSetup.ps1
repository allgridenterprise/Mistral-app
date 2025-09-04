# Opprett kjernestruktur først
$coreFolders = @(
    "Core\Interfaces", # Kontrakter/interfaces
    "Core\Configuration", # Konfigurasjonshåndtering
    "Core\Services", # Kjerne-tjenester
    "Core\Events", # Event-håndtering
    "Infrastructure\Storage", # Lagringshåndtering
    "Infrastructure\Processing", # Prosesseringslag
    "Infrastructure\Integration" # Ekstern integrasjon
)

foreach ($folder in $coreFolders)
{
    $path = Join-Path "src" $folder
    New-Item -Path $path -ItemType Directory -Force
}
