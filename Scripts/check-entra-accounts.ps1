# Script to check for duplicate/ghost accounts in Microsoft Entra ID

# Make sure the Microsoft Graph PowerShell SDK is installed
# Install-Module Microsoft.Graph -Scope CurrentUser

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All"

# Define the email address to check
$emailToCheck = "dan@allgrid.com"

# Search for users with the specified email
$users = Get-MgUser -Filter "userPrincipalName eq '$emailToCheck' or mail eq '$emailToCheck' or otherMails/any(email:email eq '$emailToCheck')" -All

# Display results
Write-Host "Found $($users.Count) user accounts related to $emailToCheck"
foreach ($user in $users) {
    Write-Host "--------------------------------"
    Write-Host "Display Name: $($user.DisplayName)"
    Write-Host "UserPrincipalName: $($user.UserPrincipalName)"
    Write-Host "Object ID: $($user.Id)"
    Write-Host "Account Enabled: $($user.AccountEnabled)"
    
    # Get assigned licenses
    $licenses = Get-MgUserLicenseDetail -UserId $user.Id
    Write-Host "Assigned Licenses:"
    foreach ($license in $licenses) {
        Write-Host "  - $($license.SkuPartNumber)"
    }
}

# Check for related enterprise applications and app registrations
Write-Host "`n=== Checking for related enterprise applications ==="
try {
    # Get all enterprise applications (service principals)
    $apps = Get-MgServicePrincipal -All | Where-Object { 
        $_.DisplayName -like "*Bitwarden*" -or 
        $_.AppDisplayName -like "*Bitwarden*" 
    }
    
    if ($apps.Count -gt 0) {
        Write-Host "Found $($apps.Count) Bitwarden-related applications"
        foreach ($app in $apps) {
            Write-Host "--------------------------------"
            Write-Host "Display Name: $($app.DisplayName)"
            Write-Host "App ID: $($app.AppId)"
            Write-Host "Object ID: $($app.Id)"
        }
    } else {
        Write-Host "No Bitwarden-related applications found"
    }
    
    # Check app registrations that might be related to the user
    Write-Host "`n=== Checking app registrations ==="
    $appRegistrations = Get-MgApplication -All | Where-Object { 
        $_.DisplayName -like "*Bitwarden*"
    }
    
    if ($appRegistrations.Count -gt 0) {
        Write-Host "Found $($appRegistrations.Count) Bitwarden-related app registrations"
        foreach ($appReg in $appRegistrations) {
            Write-Host "--------------------------------"
            Write-Host "Display Name: $($appReg.DisplayName)"
            Write-Host "App ID: $($appReg.AppId)"
            Write-Host "Object ID: $($appReg.Id)"
            Write-Host "Redirect URIs: $($appReg.Web.RedirectUris -join ', ')"
        }
    } else {
        Write-Host "No Bitwarden-related app registrations found"
    }
}
catch {
    Write-Host "Error checking applications: $_"
    Write-Host "Recommendation: Check applications manually in the Microsoft Entra admin center"
}
