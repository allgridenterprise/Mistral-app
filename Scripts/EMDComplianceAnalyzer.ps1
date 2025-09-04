# Copyright Allgrid@2024
# Script for EMD Compliance Analysis

Write-Host "EMD Compliance Analyzer for Mistral App" -ForegroundColor Cyan
Write-Host "Copyright Allgrid@2024" -ForegroundColor Cyan
Write-Host "This script will be implemented in a future release" -ForegroundColor Yellow

using System;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace MistralApp.Services
{
public class MistralApiClient: IMistralApiClient
{
private readonly HttpClient _httpClient;
private readonly IConfiguration _configuration;
private readonly ILogger<MistralApiClient> _logger;
private readonly BitwardenSsoService? _bitwardenService;
private string? _apiKey;

public MistralApiClient(
HttpClient httpClient,
IConfiguration configuration,
ILogger<MistralApiClient> logger,
BitwardenSsoService? bitwardenService = null)
{
_httpClient = httpClient;
_configuration = configuration;
_logger = logger;
_bitwardenService = bitwardenService;

_httpClient.BaseAddress = new Uri(configuration["MistralApi:BaseUrl"] ?? "https://api.mistral.ai/");
}

// NY: implementasjon som tilfredsstiller interfacet
public Task<string> SendMessageAsync(string model, string prompt)
= > CompleteChatAsync(model, prompt);

public async Task<string> CompleteChatAsync(string model, string prompt)
{
await EnsureApiKeyAsync();

var request = new
{
model = model,
messages = new[]
{
new {
role = "user", content = prompt
}
}
};

var json = JsonConvert.SerializeObject(request);
var content = new StringContent(json, Encoding.UTF8, "application/json");

_httpClient.DefaultRequestHeaders.Clear();
_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_apiKey}");

var response = await _httpClient.PostAsync("v1/chat/completions", content);

if (response.StatusCode = = System.Net.HttpStatusCode.Unauthorized)
{
_apiKey = null;
await EnsureApiKeyAsync(forceRefresh: true);

_httpClient.DefaultRequestHeaders.Clear();
_httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_apiKey}");

response = await _httpClient.PostAsync("v1/chat/completions", content);
if (response.StatusCode = = System.Net.HttpStatusCode.Unauthorized)
{
throw new UnauthorizedAccessException("API-nøkkelen ble ikke godkjent av Mistral. Kontroller at nøkkelen er gyldig.");
}
}

response.EnsureSuccessStatusCode();

var responseContent = await response.Content.ReadAsStringAsync();
return responseContent;
}

private async Task EnsureApiKeyAsync(bool forceRefresh = false)
{
if (!string.IsNullOrEmpty(_apiKey) && !forceRefresh)
{
return;
}

if (_bitwardenService ! = null)
{
try
{
var apiKey = await _bitwardenService.GetMistralApiKeyAsync();
if (!string.IsNullOrEmpty(apiKey))
{
_apiKey = apiKey;
return;
}
}
catch (Exception ex)
{
_logger.LogError(ex, "Kunne ikke hente API-nøkkel fra Bitwarden");
}
}

_apiKey = Environment.GetEnvironmentVariable("MISTRAL_API_KEY")
?? _configuration["MistralApi:ApiKey"]
?? "";

if (string.IsNullOrEmpty(_apiKey))
{
throw new InvalidOperationException("Mistral API-nøkkel mangler. Angi den i appsettings.json, som miljøvariabel MISTRAL_API_KEY, eller konfigurer Bitwarden SSO-integrasjon.");
}
}
}
}
