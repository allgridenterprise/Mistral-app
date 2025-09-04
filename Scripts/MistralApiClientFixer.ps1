# Fikser MistralApiClient.cs
(Get-Content -Path "Services\MistralApiClient.cs") -replace '\$"Bearer \{_apiKey\}"', '`$"Bearer {_apiKey}"' | Set-Content -Path "Services\MistralApiClient.cs"

# Fikser MainViewModel.cs
(Get-Content -Path "ViewModels\MainViewModel.cs") -replace '\$"Fullført\. Brukt \{parsedResponse\.Usage\.TotalTokens\} tokens\."', '`$"Fullført. Brukt {parsedResponse.Usage.TotalTokens} tokens."' | Set-Content -Path "ViewModels\MainViewModel.cs"
(Get-Content -Path "ViewModels\MainViewModel.cs") -replace '\$"Feil: \{ex\.Message\}"', '`$"Feil: {ex.Message}"' | Set-Content -Path "ViewModels\MainViewModel.cs"
