# Oppdater SettingsDialog.xaml for å legge til Bitwarden-konfigurasjon
@'
<Window x:Class="MistralApp.Views.SettingsDialog"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        mc:Ignorable="d"
        Title="API Innstillinger" Height="400" Width="600"
        WindowStartupLocation="CenterOwner">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Mistral API Innstillinger" FontWeight="Bold" FontSize="16" Margin="0,0,0,10"/>
        
        <TabControl Grid.Row="1">
            <TabItem Header="Direkte API-nøkkel">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <Grid Grid.Row="0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="API Nøkkel:" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <TextBox Grid.Column="1" Text="{Binding ApiKey, UpdateSourceTrigger=PropertyChanged}" Padding="5"/>
                    </Grid>
                    
                    <TextBlock Grid.Row="1" TextWrapping="Wrap" Margin="0,10,0,0">
                        For å bruke Mistral API, trenger du en gyldig API-nøkkel. 
                        Hvis du ikke har en, kan du få en fra <Hyperlink NavigateUri="https://mistral.ai" RequestNavigate="Hyperlink_RequestNavigate">mistral.ai</Hyperlink>.
                    </TextBlock>
                </Grid>
            </TabItem>
            
            <TabItem Header="Bitwarden SSO">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    
                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Client ID:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                    <TextBox Grid.Row="0" Grid.Column="1" Text="{Binding BitwardenClientId, UpdateSourceTrigger=PropertyChanged}" Padding="5" Margin="0,5,0,5"/>
                    
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Client Secret:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                    <PasswordBox Grid.Row="1" Grid.Column="1" x:Name="ClientSecretBox" Padding="5" Margin="0,5,0,5"/>
                    
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Tenant ID:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                    <TextBox Grid.Row="2" Grid.Column="1" Text="{Binding BitwardenTenantId, UpdateSourceTrigger=PropertyChanged}" Padding="5" Margin="0,5,0,5"/>
                    
                    <TextBlock Grid.Row="3" Grid.Column="0" Text="API Key Item ID:" VerticalAlignment="Center" Margin="0,5,10,5"/>
                    <TextBox Grid.Row="3" Grid.Column="1" Text="{Binding BitwardenItemId, UpdateSourceTrigger=PropertyChanged}" Padding="5" Margin="0,5,0,5"/>
                    
                    <TextBlock Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" TextWrapping="Wrap" Margin="0,10,0,0">
                        For å bruke Bitwarden Enterprise med SSO, trenger du å konfigurere en applikasjon i Microsoft Entra (Azure AD) 
                        og koble den til Bitwarden. Se <Hyperlink NavigateUri="https://bitwarden.com/help/sso-azure-setup/" RequestNavigate="Hyperlink_RequestNavigate">Bitwarden SSO-dokumentasjon</Hyperlink> 
                        for mer informasjon.
                    </TextBlock>
                </Grid>
            </TabItem>
        </TabControl>
        
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button Content="Avbryt" Width="80" Margin="0,0,10,0" IsCancel="True"/>
            <Button Content="OK" Width="80" IsDefault="True" Click="OkButton_Click"/>
        </StackPanel>
    </Grid>
</Window>
'@ | Out-File -FilePath "Views\SettingsDialog.xaml" -Encoding UTF8 -Force

# Oppdater SettingsDialog.xaml.cs for å håndtere Bitwarden-konfigurasjon
@'
using System.Diagnostics;
using System.Windows;
using System.Windows.Navigation;
using MistralApp.Models;
using Microsoft.Extensions.Configuration;

namespace MistralApp.Views
{
    public partial class SettingsDialog : Window
    {
        public ApiSettings Settings { get; }

        public SettingsDialog(ApiSettings settings)
        {
            InitializeComponent();
            Settings = settings;
            DataContext = Settings;
            
            // Sett passord-boksen hvis klient-secret er konfigurert
            if (!string.IsNullOrEmpty(Settings.BitwardenClientSecret))
            {
                ClientSecretBox.Password = Settings.BitwardenClientSecret;
            }
        }

        private void OkButton_Click(object sender, RoutedEventArgs e)
        {
            // Hent verdien fra passord-boksen
            Settings.BitwardenClientSecret = ClientSecretBox.Password;
            
            DialogResult = true;
            Close();
        }

        private void Hyperlink_RequestNavigate(object sender, RequestNavigateEventArgs e)
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = e.Uri.AbsoluteUri,
                UseShellExecute = true
            });
            e.Handled = true;
        }
    }
}
'@ | Out-File -FilePath "Views\SettingsDialog.xaml.cs" -Encoding UTF8 -Force

# Oppdater ApiSettings-modellen
@'
using System.ComponentModel;

namespace MistralApp.Models
{
    public class ApiSettings : INotifyPropertyChanged
    {
        private string _apiKey;
        private string _bitwardenClientId;
        private string _bitwardenClientSecret;
        private string _bitwardenTenantId;
        private string _bitwardenItemId;

        public string ApiKey
        {
            get => _apiKey;
            set
            {
                if (_apiKey != value)
                {
                    _apiKey = value;
                    OnPropertyChanged(nameof(ApiKey));
                }
            }
        }
        
        public string BitwardenClientId
        {
            get => _bitwardenClientId;
            set
            {
                if (_bitwardenClientId != value)
                {
                    _bitwardenClientId = value;
                    OnPropertyChanged(nameof(BitwardenClientId));
                }
            }
        }
        
        public string BitwardenClientSecret
        {
            get => _bitwardenClientSecret;
            set
            {
                if (_bitwardenClientSecret != value)
                {
                    _bitwardenClientSecret = value;
                    OnPropertyChanged(nameof(BitwardenClientSecret));
                }
            }
        }
        
        public string BitwardenTenantId
        {
            get => _bitwardenTenantId;
            set
            {
                if (_bitwardenTenantId != value)
                {
                    _bitwardenTenantId = value;
                    OnPropertyChanged(nameof(BitwardenTenantId));
                }
            }
        }
        
        public string BitwardenItemId
        {
            get => _bitwardenItemId;
            set
            {
                if (_bitwardenItemId != value)
                {
                    _bitwardenItemId = value;
                    OnPropertyChanged(nameof(BitwardenItemId));
                }
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;

        protected virtual void OnPropertyChanged(string propertyName)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
'@ | Out-File -FilePath "Models\ApiSettings.cs" -Encoding UTF8 -Force

# Oppdater MainWindow.xaml.cs for å håndtere Bitwarden-innstillinger
@'
using System;
using System.Windows;
using MistralApp.Models;
using MistralApp.ViewModels;
using Microsoft.Extensions.Configuration;
using System.IO;
using Newtonsoft.Json.Linq;

namespace MistralApp.Views
{
    public partial class MainWindow : Window
    {
        private readonly MainViewModel _viewModel;
        private readonly IConfiguration _configuration;

        public MainWindow(MainViewModel viewModel, IConfiguration configuration)
        {
            InitializeComponent();
            _viewModel = viewModel;
            _configuration = configuration;
            DataContext = _viewModel;
        }

        private void SettingsButton_Click(object sender, RoutedEventArgs e)
        {
            var settings = new ApiSettings
            {
                ApiKey = _configuration["MistralApi:ApiKey"] ?? "",
                BitwardenClientId = _configuration["Bitwarden:ClientId"] ?? "",
                BitwardenClientSecret = _configuration["Bitwarden:ClientSecret"] ?? "",
                BitwardenTenantId = _configuration["Bitwarden:TenantId"] ?? "",
                BitwardenItemId = _configuration["Bitwarden:MistralApiKeyItemId"] ?? ""
            };

            var dialog = new SettingsDialog(settings)
            {
                Owner = this
            };

            if (dialog.ShowDialog() == true)
            {
                // Oppdater appsettings.json
                UpdateSettings(settings);
                
                // Informer brukeren om at innstillingene er lagret
                MessageBox.Show("Innstillingene er lagret. Start applikasjonen på nytt for at endringene skal tre i kraft.", 
                    "Innstillinger lagret", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void UpdateSettings(ApiSettings settings)
        {
            try
            {
                // Les den eksisterende appsettings.json
                string json = File.ReadAllText("appsettings.json");
                
                // Parse JSON til JObject
                JObject settingsObj = JObject.Parse(json);
                
                // Oppdater Mistral API-nøkkel
                if (settingsObj["MistralApi"] == null)
                {
                    settingsObj["MistralApi"] = new JObject();
                }
                settingsObj["MistralApi"]["ApiKey"] = settings.ApiKey;
                
                // Oppdater Bitwarden-innstillinger
                if (settingsObj["Bitwarden"] == null)
                {
                    settingsObj["Bitwarden"] = new JObject();
                }
                settingsObj["Bitwarden"]["ClientId"] = settings.BitwardenClientId;
                settingsObj["Bitwarden"]["ClientSecret"] = settings.BitwardenClientSecret;
                settingsObj["Bitwarden"]["TenantId"] = settings.BitwardenTenantId;
                settingsObj["Bitwarden"]["MistralApiKeyItemId"] = settings.BitwardenItemId;
                
                // Skriv oppdatert JSON til filen
                File.WriteAllText("appsettings.json", settingsObj.ToString(Newtonsoft.Json.Formatting.Indented));
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Kunne ikke lagre innstillingene: {ex.Message}", 
                    "Feil", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }
}
'@ | Out-File -FilePath "Views\MainWindow.xaml.cs" -Encoding UTF8 -Force
