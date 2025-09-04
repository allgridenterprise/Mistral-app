# Oppdatere og flytte MistralApiClient til Services-mappen
@"
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
            _httpClient.DefaultRequestHeaders.Add("Authorization", \$"Bearer {_apiKey}");
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
"@ | Out-File -FilePath "Services\MistralApiClient.cs" -Encoding UTF8
