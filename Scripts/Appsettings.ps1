# Opprett appsettings.json for konfigurasjon
@"
{
  "MistralApi": {
    "BaseUrl": "https://api.mistral.ai/",
    "DefaultModel": "mistral-small-latest"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning"
    }
  }
}
"@ | Out-File -FilePath "appsettings.json" -Encoding UTF8
