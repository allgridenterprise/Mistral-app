# Copyright Allgrid@2024
# Script to securely retrieve Mistral API key from Bitwarden and update app configuration
param(
    [Parameter(Mandatory=$false)]
    [string]$BitwardenItemName = "Mistral API",
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "$PSScriptRoot\..\appsettings.json"
)

Write-Host "Updating Mistral API Key from Bitwarden..." -ForegroundColor Cyan

# Check if Bitwarden CLI is installed
$bwCommand = Get-Command bw -ErrorAction SilentlyContinue
if (-not $bwCommand) {
    Write-Error "Bitwarden CLI is not installed. Please install it from https://bitwarden.com/help/cli/"
    exit 1
}

try {
    # Check if user is logged in to Bitwarden
    $status = bw status | ConvertFrom-Json
    
    if ($status.status -ne "unlocked") {
        # Prompt user to login or unlock Bitwarden
        Write-Host "Bitwarden vault is locked. Please unlock it." -ForegroundColor Yellow
        $session = bw unlock --raw
        
        if (-not $session) {
            Write-Host "You may need to log in first. Use 'bw login' and then try again." -ForegroundColor Yellow
            exit 1
        }
        
        # Set the session key as an environment variable
        $env:BW_SESSION = $session
    }
    
    # Search for the Mistral API key item
    Write-Host "Searching for '$BitwardenItemName' in Bitwarden..." -ForegroundColor Gray
    $searchResults = bw list items --search $BitwardenItemName | ConvertFrom-Json
    
    if (-not $searchResults -or $searchResults.Count -eq 0) {
        Write-Error "No item found with name '$BitwardenItemName' in Bitwarden."
        exit 1
    }
    
    # Get the first matching item
    $item = $searchResults[0]
    Write-Host "Found item: $($item.name)" -ForegroundColor Green
    
    # Extract the API key from the item
    # Since API key is stored in the password field, this should work directly
    $apiKey = $null
    
    # Try to get the API key from the password field
    if ($item.login -and $item.login.password) {
        $apiKey = $item.login.password
        Write-Host "Found API key in password field." -ForegroundColor Green
    }
    # If not in the password field, try to find it in custom fields as fallback
    elseif ($item.fields) {
        $apiKeyField = $item.fields | Where-Object { $_.name -eq "API Key" -or $_.name -eq "ApiKey" } | Select-Object -First 1
        if ($apiKeyField) {
            $apiKey = $apiKeyField.value
            Write-Host "Found API key in custom field." -ForegroundColor Green
        }
    }
    
    if (-not $apiKey) {
        Write-Error "Could not find API Key in the Bitwarden item. Make sure it's stored as a password or in a custom field named 'API Key'."
        exit 1
    }
    
    # Now update the configuration file
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Configuration file not found at: $ConfigFile"
        exit 1
    }
    
    Write-Host "Updating configuration file: $ConfigFile" -ForegroundColor Yellow
    
    # Read the current configuration
    $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
    
    # Update the API key in ALL possible configuration locations to ensure the app finds it
    
    # Location 1: Direct MistralAI root property
    if (-not $config.MistralAI) {
        $config | Add-Member -MemberType NoteProperty -Name "MistralAI" -Value @{ ApiKey = $apiKey } -Force
        Write-Host "Added MistralAI root section with ApiKey." -ForegroundColor Green
    } else {
        $config.MistralAI.ApiKey = $apiKey
        Write-Host "Updated MistralAI.ApiKey in configuration." -ForegroundColor Green
    }
    
    # Location 2: In ApiKeys section
    if (-not $config.ApiKeys) {
        $config | Add-Member -MemberType NoteProperty -Name "ApiKeys" -Value @{ MistralAI = $apiKey } -Force
        Write-Host "Added ApiKeys section with MistralAI key." -ForegroundColor Green
    } else {
        $config.ApiKeys | Add-Member -MemberType NoteProperty -Name "MistralAI" -Value $apiKey -Force
        Write-Host "Updated ApiKeys.MistralAI in configuration." -ForegroundColor Green
    }
    
    # Location 3: Specific MistralAPIKey property that the app might be looking for
    $config | Add-Member -MemberType NoteProperty -Name "MistralAPIKey" -Value $apiKey -Force
    Write-Host "Added MistralAPIKey property directly in root." -ForegroundColor Green
    
    # Location 4: MistralApi section (which is what the client actually looks for)
    if (-not $config.MistralApi) {
        $config | Add-Member -MemberType NoteProperty -Name "MistralApi" -Value @{ ApiKey = $apiKey } -Force
        Write-Host "Added MistralApi section with ApiKey." -ForegroundColor Green
    } else {
        if (-not $config.MistralApi.PSObject.Properties['ApiKey']) {
            $config.MistralApi | Add-Member -MemberType NoteProperty -Name "ApiKey" -Value $apiKey -Force
        } else {
            $config.MistralApi.ApiKey = $apiKey
        }
        Write-Host "Updated MistralApi.ApiKey in configuration." -ForegroundColor Green
    }
    
    # Write the updated configuration back to the file
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigFile
    
    # Also set environment variable as the application error message suggests
    [System.Environment]::SetEnvironmentVariable("MISTRAL_API_KEY", $apiKey, "User")
    Write-Host "Set MISTRAL_API_KEY environment variable for current user." -ForegroundColor Green
    # Set for current process as well
    $env:MISTRAL_API_KEY = $apiKey
    
    # Also update the main executable config if different from the one we just updated
    $executableConfigFile = "$PSScriptRoot\..\bin\Release\net8.0-windows\win-x64\publish\appsettings.json"
    if ((Test-Path $executableConfigFile) -and ($executableConfigFile -ne $ConfigFile)) {
        Write-Host "Also updating executable configuration file: $executableConfigFile" -ForegroundColor Yellow
        
        try {
            $execConfig = Get-Content -Path $executableConfigFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $execConfig) { $execConfig = New-Object PSObject }
            
            # Add to all possible locations in this file too
            if (-not $execConfig.MistralAI) {
                $execConfig | Add-Member -MemberType NoteProperty -Name "MistralAI" -Value @{ ApiKey = $apiKey } -Force
            } else {
                $execConfig.MistralAI.ApiKey = $apiKey
            }
            
            if (-not $execConfig.ApiKeys) {
                $execConfig | Add-Member -MemberType NoteProperty -Name "ApiKeys" -Value @{ MistralAI = $apiKey } -Force
            } else {
                $execConfig.ApiKeys | Add-Member -MemberType NoteProperty -Name "MistralAI" -Value $apiKey -Force
            }
            
            $execConfig | Add-Member -MemberType NoteProperty -Name "MistralAPIKey" -Value $apiKey -Force
            
            $execConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $executableConfigFile
            Write-Host "Updated executable configuration file successfully." -ForegroundColor Green
        } catch {
            Write-Host "Warning: Could not update executable configuration file: $_" -ForegroundColor Yellow
        }
    }

    Write-Host "Successfully updated Mistral API key in all possible locations." -ForegroundColor Green
    Write-Host "The application will now use this API key when connecting to Mistral AI services." -ForegroundColor Cyan
    Write-Host "If you still experience issues, restart your application to ensure it picks up the environment variable." -ForegroundColor Yellow

} catch {
    Write-Error "Error updating API key: $_"
    exit 1
} finally {
    # Clear the session environment variable for security
    if ($env:BW_SESSION) {
        $env:BW_SESSION = $null
    }
}
