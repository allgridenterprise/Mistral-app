# Fikser MistralApiClient.cs ved å opprette på nytt med enkelte anførselstegn
@'
using System;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Microsoft.Extensions.Configuration;

namespace MistralApp.Services
{
    public class MistralApiClient
    {
        private readonly HttpClient _httpClient;
        private readonly string _apiKey;
        private readonly IConfiguration _configuration;
        
        public MistralApiClient(HttpClient httpClient, IConfiguration configuration)
        {
            _httpClient = httpClient;
            _configuration = configuration;
            
            // Hent API-nøkkel fra miljøvariabel eller konfigurasjon
            _apiKey = Environment.GetEnvironmentVariable("MISTRAL_API_KEY") 
                ?? configuration["MistralApi:ApiKey"] 
                ?? "your-api-key-here";
                
            _httpClient.BaseAddress = new Uri(configuration["MistralApi:BaseUrl"] ?? "https://api.mistral.ai/");
            _httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_apiKey}");
        }
        
        public async Task<string> CompleteChatAsync(string model, string prompt)
        {
            var request = new
            {
                model = model,
                messages = new[]
                {
                    new { role = "user", content = prompt }
                }
            };
            
            var json = JsonConvert.SerializeObject(request);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var response = await _httpClient.PostAsync("v1/chat/completions", content);
            response.EnsureSuccessStatusCode();
            
            var responseContent = await response.Content.ReadAsStringAsync();
            return responseContent;
        }
    }
}
'@ | Out-File -FilePath "Services\MistralApiClient.cs" -Encoding UTF8 -Force

# Fikser MainViewModel.cs ved å opprette på nytt med enkelte anførselstegn
@'
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
                    StatusMessage = $"Fullført. Brukt {parsedResponse.Usage.TotalTokens} tokens.";
                }
                else
                {
                    Response = "Ingen svar mottatt fra API.";
                    StatusMessage = "Advarsel: Tomt svar fra API";
                }
            }
            catch (Exception ex)
            {
                Response = $"Feil: {ex.Message}";
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
'@ | Out-File -FilePath "ViewModels\MainViewModel.cs" -Encoding UTF8 -Force
