# Opprett ViewModel for hovedapplikasjonen
@"
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MistralApp.Models;
using MistralApp.Services;
using Microsoft.Extensions.Configuration;
using Newtonsoft.Json;

namespace MistralApp.ViewModels
{
    public partial class MainViewModel : ObservableObject
    {
        private readonly MistralApiClient _apiClient;
        private readonly IConfiguration _configuration;
        
        [ObservableProperty]
        private string _prompt = string.Empty;
        
        [ObservableProperty]
        private string _response = string.Empty;
        
        [ObservableProperty]
        private bool _isProcessing = false;
        
        [ObservableProperty]
        private string _statusMessage = "Klar";
        
        [ObservableProperty]
        private ObservableCollection<string> _availableModels = new()
        {
            "mistral-tiny",
            "mistral-small-latest",
            "mistral-medium-latest",
            "mistral-large-latest"
        };
        
        [ObservableProperty]
        private string _selectedModel;
        
        public MainViewModel(MistralApiClient apiClient, IConfiguration configuration)
        {
            _apiClient = apiClient;
            _configuration = configuration;
            _selectedModel = configuration["MistralApi:DefaultModel"] ?? "mistral-small-latest";
        }
        
        [RelayCommand]
        private async Task SendPromptAsync()
        {
            if (string.IsNullOrWhiteSpace(Prompt))
            {
                StatusMessage = "Feil: Prompt kan ikke være tom";
                return;
            }
            
            try
            {
                IsProcessing = true;
                StatusMessage = "Sender forespørsel...";
                
                var jsonResponse = await _apiClient.CompleteChatAsync(SelectedModel, Prompt);
                var parsedResponse = JsonConvert.DeserializeObject<ChatCompletionResponse>(jsonResponse);
                
                if (parsedResponse?.Choices?.Count > 0)
                {
                    Response = parsedResponse.Choices[0].Message.Content;
                    StatusMessage = \$"Fullført. Brukt {parsedResponse.Usage.TotalTokens} tokens.";
                }
                else
                {
                    Response = "Ingen svar mottatt fra API.";
                    StatusMessage = "Advarsel: Tomt svar fra API";
                }
            }
            catch (Exception ex)
            {
                Response = \$"Feil: {ex.Message}";
                StatusMessage = "Feil under API-kall";
            }
            finally
            {
                IsProcessing = false;
            }
        }
        
        [RelayCommand]
        private void ClearPrompt()
        {
            Prompt = string.Empty;
            Response = string.Empty;
            StatusMessage = "Klar";
        }
    }
}
"@ | Out-File -FilePath "ViewModels\MainViewModel.cs" -Encoding UTF8
