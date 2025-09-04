# ===================================================================
# Fix-WpfStartup.ps1
# Hardener WPF-oppstart: fjerner StartupUri, legger på globale
# unntakshåndterere + fil-logging, og wrapper OnStartup i try/catch.
# Kjøres fra prosjektroten.
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

# Finn filer robust fra skriptets plassering eller interaktiv kjøring
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    # Kjørt linje-for-linje i terminal: bruk CWD; gå én opp hvis vi står i Scripts\
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

$appXamlPath   = Join-Path $projectRoot "App.xaml"
$appXamlCsPath = Join-Path $projectRoot "App.xaml.cs"

# Fallback: søk rekursivt hvis App.xaml.cs ikke ligger i rot
if (-not (Test-Path $appXamlCsPath)) {
    $candidate = Get-ChildItem -Path $projectRoot -Recurse -Include "App.xaml.cs" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) {
        $appXamlCsPath = $candidate.FullName
        $appXamlPath   = Join-Path (Split-Path $appXamlCsPath -Parent) "App.xaml"
        Write-Host "Fant App.xaml.cs: $appXamlCsPath" -ForegroundColor DarkGray
    } else {
        throw "Fant ikke App.xaml.cs under $projectRoot"
    }
}

# 1) Rydd App.xaml: fjern StartupUri for å unngå dobbel init
if (Test-Path $appXamlPath) {
    Write-Host "Rydder App.xaml (fjerner StartupUri)..." -ForegroundColor Cyan
    Backup-File $appXamlPath
    $x = Get-Content $appXamlPath -Raw
    $x2 = $x -replace 'StartupUri\s*=\s*"(.*?)"', ''
    if ($x2 -ne $x) {
        Set-Content -Path $appXamlPath -Value $x2 -Encoding UTF8
        Write-Host "StartupUri fjernet." -ForegroundColor Green
    } else {
        Write-Host "Ingen StartupUri funnet (OK)." -ForegroundColor DarkGray
    }
} else {
    Write-Host "App.xaml ikke funnet (hopper over StartupUri-rens)." -ForegroundColor DarkYellow
}

# 2) Injiser globale unntakshåndterere i App.xaml.cs etter 'Services = _host.Services;'
Write-Host "Injiserer globale unntakshåndterere i App.xaml.cs..." -ForegroundColor Cyan
Backup-File $appXamlCsPath
$cs = Get-Content $appXamlCsPath -Raw

$handlers = @"
            // Globale unntakshåndterere for å fange XAML/oppstartsfeil
            try
            {
                DispatcherUnhandledException += (s, e) =>
                {
                    LogException(e.Exception);
                    System.Windows.MessageBox.Show(e.Exception.Message, "Feil (Dispatcher)");
                    e.Handled = true;
                    Current.Shutdown(-1);
                };

                AppDomain.CurrentDomain.UnhandledException += (s, e) =>
                {
                    if (e.ExceptionObject is Exception ex) LogException(ex);
                };

                System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (s, e) =>
                {
                    LogException(e.Exception);
                    e.SetObserved();
                };
            }
            catch { /* ignorér */ }
"@

# Sett inn handlere én gang etter 'Services = _host.Services;'
if ($cs -notmatch 'Globale unntakshåndterere for å fange XAML/oppstartsfeil') {
    $cs = $cs -replace '(Services\s*=\s*_host\.Services;\s*)', "`$1`r`n$handlers`r`n"
}

# 3) Legg til LogException-metode hvis ikke finnes
if ($cs -notmatch 'void\s+LogException\s*\(') {
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

    # Sett inn før siste klammeparentes i App-klassen
    $cs = $cs -replace '(?im)(^\s*\}\s*\}\s*$)', "`r`n$logMethod`r`n$0"
}

# 4) Wrap OnStartup i try/catch
$onStartupPattern = 'protected\s+override\s+async\s+void\s+OnStartup\s*\(\s*StartupEventArgs\s+e\s*\)\s*\{.*?\}\s*' 
if ($cs -match $onStartupPattern) {
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
    $cs = [System.Text.RegularExpressions.Regex]::Replace(
        $cs,
        $onStartupPattern,
        $onStartupNew,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
} else {
    Write-Host "Fant ikke OnStartup – ingen endring." -ForegroundColor DarkYellow
}

# 5) Skriv tilbake App.xaml.cs
Set-Content -Path $appXamlCsPath -Value $cs -Encoding UTF8
Write-Host "App.xaml.cs oppdatert." -ForegroundColor Green

# 6) Verifiser build/publish
Write-Host "Verifiserer med dotnet restore/publish..." -ForegroundColor Cyan
$prev = Get-Location
$ok = $true
Set-Location $projectRoot
try {
    dotnet restore "MistralApp.csproj"
    if (-not $?) { throw "Restore feilet." }

    dotnet publish "MistralApp.csproj" -c Release -r win-x64 --self-contained true
    if (-not $?) { throw "Publish feilet." }
}
catch {
    $ok = $false
    throw
}
finally {
    Set-Location $prev
}

if ($ok) {
    Write-Host "OK: Build/publish fullførte uten feil." -ForegroundColor Green
    Write-Host "Start app direkte: bin\\Release\\net8.0-windows\\win-x64\\publish\\MistralApp.exe" -ForegroundColor Yellow
    Write-Host "Ved feil, se logg under %LOCALAPPDATA%\\MistralSuite\\logs" -ForegroundColor Yellow
}
