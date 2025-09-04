# Oppdater App.xaml.cs for å registrere BitwardenSsoService
@'
using System.Windows;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MistralApp.Services;
using MistralApp.ViewModels;
using MistralApp.Views;
using System.IO;

namespace MistralApp
{
    public partial class App : Application
    {
        private readonly IHost _host;

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
            
            services.AddHttpClient<MistralApiClient>();
            services.AddSingleton<MainViewModel>();
            services.AddTransient<MainWindow>();
        }

        protected override async void OnStartup(StartupEventArgs e)
        {
            await _host.StartAsync();

            var mainWindow = _host.Services.GetRequiredService<MainWindow>();
            mainWindow.Show();

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
    }
}
'@ | Out-File -FilePath "App.xaml.cs" -Encoding UTF8 -Force
