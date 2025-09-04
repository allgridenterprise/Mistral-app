# Log analysis script for Bitwarden SSO integration logs

param (
    [Parameter(Mandatory=$false)]
    [string]$LogFilePath
)

# If no log file specified, try to find the latest one
if (-not $LogFilePath) {
    $logDir = "$PSScriptRoot\logs"
    if (-not (Test-Path -Path $logDir)) {
        Write-Host "No log directory found at $logDir" -ForegroundColor Red
        exit 1
    }

    $latestLog = Get-ChildItem -Path $logDir -Filter "bitwarden-sso-fix-log-*.txt" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1

    if ($latestLog) {
        $LogFilePath = $latestLog.FullName
        Write-Host "Using latest log file: $LogFilePath" -ForegroundColor Yellow
    } else {
        Write-Host "No log files found in $logDir" -ForegroundColor Red
        exit 1
    }
}

# Check if the log file exists
if (-not (Test-Path -Path $LogFilePath)) {
    Write-Host "Log file not found: $LogFilePath" -ForegroundColor Red
    exit 1
}

# Read the log file content
$logContent = Get-Content -Path $LogFilePath -Raw

Write-Host "=== Bitwarden SSO Log Analysis ===" -ForegroundColor Cyan
Write-Host "Analyzing log file: $LogFilePath" -ForegroundColor Cyan
Write-Host "Log size: $([Math]::Round((Get-Item $LogFilePath).Length / 1KB, 2)) KB" -ForegroundColor Cyan
Write-Host "Log date: $((Get-Item $LogFilePath).LastWriteTime)" -ForegroundColor Cyan
Write-Host "===============================`n" -ForegroundColor Cyan

# Extract and count errors
$errorMatches = [regex]::Matches($logContent, "(?i)ERROR[^`r`n]*")
$warnings = [regex]::Matches($logContent, "(?i)WARNING|Note:[^`r`n]*")

Write-Host "Found $($errorMatches.Count) errors and $($warnings.Count) warnings" -ForegroundColor Yellow

# Display errors with context
if ($errorMatches.Count -gt 0) {
    Write-Host "`n=== ERRORS ===" -ForegroundColor Red
    foreach ($errorItem in $errorMatches) {
        # Find the context around the error (up to 2 lines before and after)
        $errorIndex = $errorItem.Index
        $contextStart = $logContent.LastIndexOf("`n", [Math]::Max(0, $errorIndex - 200))
        if ($contextStart -eq -1) { $contextStart = 0 }
        $contextEnd = $logContent.IndexOf("`n", $errorIndex + $errorItem.Length + 200)
        if ($contextEnd -eq -1) { $contextEnd = $logContent.Length }
        
        $context = $logContent.Substring($contextStart, $contextEnd - $contextStart).Trim()
        
        Write-Host $context -ForegroundColor Red
        Write-Host "--------------------------" -ForegroundColor DarkGray
    }
}

# Check for successful completion
if ($logContent -match "Script execution completed") {
    Write-Host "`n=== SCRIPT COMPLETED EXECUTION ===" -ForegroundColor Green
} else {
    Write-Host "`n=== SCRIPT MAY NOT HAVE COMPLETED PROPERLY ===" -ForegroundColor Red
}

# Check for successful connections
if ($logContent -match "Connected to Microsoft Graph") {
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
} else {
    Write-Host "Failed to connect to Microsoft Graph" -ForegroundColor Red
}

# Check for SAML configuration
if ($logContent -match "SAML configuration updated successfully") {
    Write-Host "SAML configuration was updated successfully" -ForegroundColor Green
} else {
    Write-Host "SAML configuration may not have been updated properly" -ForegroundColor Yellow
}

# Check for user assignment
if ($logContent -match "User assigned to application successfully") {
    Write-Host "User was assigned to the application successfully" -ForegroundColor Green
} 
elseif ($logContent -match "User already assigned") {
    Write-Host "User was already assigned to the application" -ForegroundColor Yellow
} 
else {
    Write-Host "User may not have been assigned to the application" -ForegroundColor Red
}

# Check for certificate download
if ($logContent -match "SAML certificate saved to") {
    $certPath = [regex]::Match($logContent, "SAML certificate saved to ([^`r`n]*)").Groups[1].Value
    Write-Host "SAML certificate was downloaded to $certPath" -ForegroundColor Green
    
    # Check if the certificate file exists
    if (Test-Path -Path $certPath) {
        Write-Host "Certificate file exists" -ForegroundColor Green
        
        # Display certificate info
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $certPath
            Write-Host "Certificate Subject: $($cert.Subject)" -ForegroundColor Green
            Write-Host "Certificate Issuer: $($cert.Issuer)" -ForegroundColor Green
            Write-Host "Certificate Valid From: $($cert.NotBefore)" -ForegroundColor Green
            Write-Host "Certificate Valid To: $($cert.NotAfter)" -ForegroundColor Green
        } catch {
            Write-Host "Could not analyze certificate: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Certificate file no longer exists at $certPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "SAML certificate was not downloaded" -ForegroundColor Yellow
}

# Check for configuration output
if ($logContent -match "Configuration saved to:") {
    $configPath = [regex]::Match($logContent, "Configuration saved to: ([^`r`n]*)").Groups[1].Value
    Write-Host "Configuration was saved to $configPath" -ForegroundColor Green
    
    if (Test-Path -Path $configPath) {
        Write-Host "`n=== BITWARDEN CONFIGURATION DETAILS ===" -ForegroundColor Cyan
        Get-Content -Path $configPath | Write-Host -ForegroundColor White
    } else {
        Write-Host "Configuration file no longer exists at $configPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "Configuration details were not saved to a file" -ForegroundColor Yellow
}

Write-Host "`n=== Log Analysis Complete ===" -ForegroundColor Cyan
