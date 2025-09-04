# ===================================================================
# Repair-AppXamlCs.ps1
# Skriver en kjent, balansert App.xaml.cs med globale unntakshåndterere,
# LogException og try/catch i OnStartup. Bygger/publiserer etterpå.
# Kjør fra hvor som helst.
# ===================================================================
$ErrorActionPreference = 'Stop'

function Backup-File {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path $Path) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $bak = "$Path.$stamp.bak"
        Copy-Item $Path $bak -Force
        Write-Host "Backup: $Path -> $bak" -ForegroundColor DarkGray
    }
}

# Finn prosjektrot robust (works from terminal eller når kjørt som fil)
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

# Finn App.xaml.cs
$appXamlCsPath = Join-Path $projectRoot "App.xaml.cs"
if (-not (Test-Path $appXamlCsPath)) {
    $cand = Get-ChildItem -Path $projectRoot -Recurse -Include "App.xaml.cs" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cand) { $appXamlCsPath = $cand.FullName }
}
if (-not (Test-Path $appXamlCsPath)) {
    throw "Fant ikke App.xaml.cs under $projectRoot"
}

# Skriv kjent god App.xaml.cs
Backup-File $appXamlCsPath
$appContent = @"
using System;
using System.IO;
using System.Windows;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MistralApp.Services;
using MistralApp.ViewModels;
using MistralApp.Views;

namespace MistralApp
{
    public partial class App : Application
    {
        private readonly IHost _host;

        public static new App Current => (App)Application.Current;
        public IServiceProvider Services { get; }

        public App()
        {
            _host = Host.CreateDefaultBuilder()
                .ConfigureAppConfiguration((context, config) =>
                {
                    config.SetBasePath(Directory.GetCurrentDirectory());
                    config.AddJsonFile("appsettings.json", optional: false);
                    config.AddEnvironmentVariables();
                })
                .ConfigureLogging((context, logging) =>
                {
                    logging.AddConsole();
                    logging.AddDebug();
                })
                .ConfigureServices((context, services) =>
                {
                    ConfigureServices(context.Configuration, services);
                })
                .Build();

            Services = _host.Services;

            // Globale unntakshåndterere for å fange XAML/oppstartsfeil
            try
            {
                DispatcherUnhandledException += (s, e) =>
                {
                    LogException(e.Exception);
                    MessageBox.Show(e.Exception.Message, "Feil (Dispatcher)");
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
        }

        private void ConfigureServices(IConfiguration configuration, IServiceCollection services)
        {
            services.AddSingleton(configuration);
            services.AddLogging();

            // Registrer BitwardenSsoService hvis konfigurasjonen er tilgjengelig
            if (!string.IsNullOrEmpty(configuration["Bitwarden:ClientId"]))
            {
                services.AddHttpClient<BitwardenSsoService>();
                services.AddSingleton<BitwardenSsoService>();
            }

            services.AddHttpClient<IMistralApiClient, MistralApiClient>();

            // Registrerer ViewModels
            services.AddSingleton<MainWindowViewModel>();
            services.AddSingleton<DocumentViewModel>();
            services.AddSingleton<ConfiguratorViewModel>();
            services.AddSingleton<ChatViewModel>();

            services.AddTransient<MainWindow>();
        }

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
                MessageBox.Show(ex.ToString(), "Oppstartsfeil");
                Current.Shutdown(-1);
                return;
            }

            base.OnStartup(e);
        }

        protected override async void OnExit(ExitEventArgs e)
        {
            using (_host)
            {
                await _host.StopAsync();
            }
            base.OnExit(e);
        }

        private static void LogException(Exception ex)
        {
            try
            {
                var logDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "MistralSuite", "logs");
                Directory.CreateDirectory(logDir);
                var path = Path.Combine(logDir, $"startup-{DateTime.Now:yyyyMMdd_HHmmss}.log");
                File.WriteAllText(path, ex.ToString());
            }
            catch { /* ignorer logging-feil */ }
        }
    }
}
"@

Set-Content -Path $appXamlCsPath -Value $appContent -Encoding UTF8
Write-Host "App.xaml.cs skrevet på nytt (stabilisert)." -ForegroundColor Green

# Bygg/publiser
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
