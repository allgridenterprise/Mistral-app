# ===================================================================
# Fix-XamlNumeric.ps1
# Sanerer vanlige XAML-feil som gir "‘0}’ cannot be converted to Length/Thickness".
# - Retter StringFormat={}{0}} -> StringFormat={}{0}
# - Retter StringFormat='{}{0}}' -> StringFormat='{}{0}'
# - Fjerner trailing '}' i numeriske/Thickness-attributter når verdien ikke er markup (ikke inneholder '{')
# Kjør fra prosjektroten.
# ===================================================================
$ErrorActionPreference = 'Stop'

function Backup-File {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path $Path) {
        $stamp = (Get-Date -Format "yyyyMMdd_HHmmss")
        $bak = "$Path.$stamp.bak"
        Copy-Item $Path $bak -Force
        Write-Host "Backup: $Path -> $bak" -ForegroundColor DarkGray
    }
}

# Finn prosjektrot (også robust ved interaktiv kjøring)
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $cwd = (Get-Location).Path
    if ($cwd -match '([\\/]|^)Scripts([\\/]|$)') {
        $projectRoot = Split-Path $cwd -Parent
    } else {
        $projectRoot = $cwd
    }
} else {
    $projectRoot = Split-Path $PSScriptRoot -Parent
}
Write-Host "Prosjektrot: $projectRoot" -ForegroundColor Cyan

# Hent alle XAML-filer
$xamlFiles = Get-ChildItem -Path $projectRoot -Recurse -Include *.xaml -ErrorAction SilentlyContinue
if (-not $xamlFiles) {
    Write-Host "Ingen XAML-filer funnet. Avslutter." -ForegroundColor Yellow
    exit 0
}

# Regex-mønstre
# 1) StringFormat: fjern overflødig '}' i '...{0}}' -> '...{0}'
$sfFixes = @(
    @{ Pattern = 'StringFormat=\{\}\{0\}\}'; Replace = 'StringFormat={}{0}' },
    @{ Pattern = 'StringFormat="\{\}\{0\}\}"'; Replace = 'StringFormat="{}{0}"' },
    @{ Pattern = "StringFormat='\{\}\{0\}\}'"; Replace = "StringFormat='{}{0}'" },
    @{ Pattern = 'StringFormat=\s*\{\}\s*\{0\}\}'; Replace = 'StringFormat={}{0}' }
)

# 2) Numeriske/Thickness-attributter: fjern trailing '}' når verdien ikke er markup
#   Gjelder: Width, Height, MinWidth, MinHeight, MaxWidth, MaxHeight,
#            Margin, Padding, BorderThickness, StrokeThickness, CornerRadius
#   Kun når verdien IKKE inneholder '{' (for ikke å røre Binding/ressurser)
$numericAttrs = @(
    'Width','Height','MinWidth','MinHeight','MaxWidth','MaxHeight',
    'Margin','Padding','BorderThickness','StrokeThickness','CornerRadius'
)

# Bygg ett samlet regex for attributtene
$attrGroup = ($numericAttrs | ForEach-Object {[Regex]::Escape($_)}) -join '|'
# Finn tilfeller der verdien ender med '}' og ikke har '{' i seg:
#   attr="...}"  hvor ... ikke inneholder '{'
$numericPattern = "(?<!\w)($attrGroup)\s*=\s*""([^""\{]*?)\}"""

$changed = 0
foreach ($f in $xamlFiles) {
    $text = Get-Content $f.FullName -Raw -ErrorAction Stop
    $orig = $text

    # 1) StringFormat-fixes
    foreach ($fix in $sfFixes) {
        $text = [regex]::Replace($text, $fix.Pattern, $fix.Replace)
    }

    # 2) Numeric/Thickness trailing brace-fix
    # Erstatt attr="value}" -> attr="value" (når value ikke inneholder '{')
    $text = [regex]::Replace($text, $numericPattern, {
        param($m)
        $attr = $m.Groups[1].Value
        $val  = $m.Groups[2].Value
        "$attr=""$val"""
    })

    if ($text -ne $orig) {
        Backup-File $f.FullName
        Set-Content -Path $f.FullName -Value $text -Encoding UTF8
        Write-Host "Sanert: $($f.FullName)" -ForegroundColor Green
        $changed++
    }
}

Write-Host "Filer endret: $changed" -ForegroundColor Cyan

# Valider med build/publish (valgfritt – kjør fra prosjektrot)
$prev = Get-Location
$ok = $true
Set-Location $projectRoot

# Stabiliser App.xaml.cs før build (idempotent)
try {
    # 1) Finn App.xaml.cs
    $appXamlCs = Join-Path $projectRoot "App.xaml.cs"
    if (-not (Test-Path $appXamlCs)) {
        $cand = Get-ChildItem -Path $projectRoot -Recurse -Include "App.xaml.cs" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cand) { $appXamlCs = $cand.FullName }
    }

    if (Test-Path $appXamlCs) {
        Write-Host "Stabiliserer: $appXamlCs" -ForegroundColor Cyan
        $cs = Get-Content $appXamlCs -Raw

        # 2) Erstatt OnStartup med trygg implementasjon
        $onStartupPattern = 'protected\s+override\s+async\s+void\s+OnStartup\s*\(\s*StartupEventArgs\s+e\s*\)\s*\{.*?\}\s*'
        $onStartupNew = @'
        protected override async void OnStartup(StartupEventArgs e)
        {
            await _host.StartAsync();
            try
            {
                var mainWindow = _host.Services.GetRequiredService<MainWindow>();
                mainWindow.Show();
            }
            catch (Exception ex)
            {
                LogException(ex);
                System.Windows.MessageBox.Show(ex.ToString(), "Oppstartsfeil");
                Current.Shutdown(-1);
                return;
            }
            base.OnStartup(e);
        }
'@
        if ($cs -match $onStartupPattern) {
            $cs = [System.Text.RegularExpressions.Regex]::Replace(
                $cs,
                $onStartupPattern,
                $onStartupNew,
                [System.Text.RegularExpressions.RegexOptions]::Singleline
            )
        }

        # 3) Fjern alle eksisterende LogException-metoder (dup) og injiser én korrekt
        $logPattern = 'private\s+static\s+void\s+LogException\s*\(.*?\}\s*\}\s*'
        $cs = [System.Text.RegularExpressions.Regex]::Replace(
            $cs,
            $logPattern,
            '',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        $logMethod = @"
        private static void LogException(Exception ex)
        {
            try
            {
                var logDir = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "MistralSuite", "logs");
                System.IO.Directory.CreateDirectory(logDir);
                var path = System.IO.Path.Combine(logDir, $"startup-{DateTime.Now:yyyyMMdd_HHmmss}.log");
                System.IO.File.WriteAllText(path, ex.ToString());
            }
            catch { /* ignorer logging-feil */ }
        }
"@

        # Sett inn LogException før avsluttende "}" "}"
        $cs = $cs -replace '(?im)(^\s*\}\s*\}\s*$)', "`r`n$logMethod`r`n$0"

        # 4) Normaliser avsluttende klammeparenteser (sørg for nøyaktig to)
        $cs = [System.Text.RegularExpressions.Regex]::Replace(
            $cs.TrimEnd(),
            '\s*\}\s*\}\s*$',
            "`r`n}`r`n}"
        )

        Set-Content -Path $appXamlCs -Value $cs -Encoding UTF8
        Write-Host "App.xaml.cs stabilisert." -ForegroundColor Green
    } else {
        Write-Host "Fant ikke App.xaml.cs – hopper stabilisering." -ForegroundColor DarkYellow
    }

    # 5) Restore/Publish
    Write-Host "Verifiserer med dotnet restore/publish..." -ForegroundColor Cyan
    dotnet restore "MistralApp.csproj"
    if (-not $?) { throw "Restore feilet." }
    dotnet publish "MistralApp.csproj" -c Release -r win-x64 --self-contained true
    if (-not $?) { throw "Publish feilet." }
}
catch {
    $ok = $false
    Write-Error $_
}
finally {
    Set-Location $prev
}

if ($ok) {
    Write-Host "OK: Build/publish fullførte uten feil." -ForegroundColor Green
    Write-Host "Start app direkte: bin\\Release\\net8.0-windows\\win-x64\\publish\\MistralApp.exe" -ForegroundColor Yellow
    Write-Host "Ved feil, se logg under %LOCALAPPDATA%\\MistralSuite\\logs" -ForegroundColor Yellow
} else {
    Write-Host "Publisering feilet – se feil over for detaljer." -ForegroundColor Red
}
